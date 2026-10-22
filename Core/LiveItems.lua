-- Unconfirmed items (item.unverified: not seen in WoW Forever yet, above the
-- beta's level cap) are checked against the game while playing. Sources don't
-- change in Forever, only stats, so:
--   * an item the game has: its stats are read from the game's own tooltip
--     (they replace the data's, which stay in item.dataStats for debug mode)
--     and it's shown like any confirmed item, without the Unconfirmed tag;
--   * an item the game doesn't have (not in its item files): left out of
--     suggestions, and tagged "Not in WoW Forever" where it still shows (a
--     gear set or the Wanted list);
--   * until the game answers: tagged Unconfirmed, scored with the data's stats.
-- After login every unconfirmed item is checked a few at a time; items not in
-- the client's cache yet are requested, and GET_ITEM_INFO_RECEIVED finishes
-- them.

EverGear = EverGear or {}

local BATCH = 20
local states = {}  -- itemId -> "live" | "missing"; absent while still pending
local queue, queueIndex
local refreshPending = false

local function ItemExists(itemId)
    if C_Item and C_Item.DoesItemExistByID then return C_Item.DoesItemExistByID(itemId) end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return instant ~= nil and instant(itemId) ~= nil
end

-- One window refresh for a burst of answers.
local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    local function run()
        refreshPending = false
        if EverGear.Frame and EverGear.Frame:IsShown() then EverGear:RefreshUI() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end

-- Settles an unconfirmed item if the game can answer now; true once settled.
local function Check(item)
    if states[item.id] then return true end
    if not ItemExists(item.id) then
        states[item.id] = "missing"
        return true
    end
    local record, reason
    if EverGear.BuildLiveItemRecord then
        record, reason = EverGear:BuildLiveItemRecord("item:" .. item.id, true)
    end
    if record and record.stats then
        item.dataStats = item.dataStats or item.stats
        item.liveRecord = record
        item.stats = record.stats
        states[item.id] = "live"
        return true
    end
    if reason and reason ~= "uncached" then
        -- The game has it but its tooltip can't be read as gear stats (a
        -- random-suffix item, say): keep the data's stats.
        states[item.id] = "live"
        return true
    end
    local load = C_Item and C_Item.RequestLoadItemDataByID
    if load then load(item.id) end
    return false
end

local checker = CreateFrame("Frame", "EverGearUnconfirmedChecker")
checker:Hide()
checker:SetScript("OnUpdate", function(self)
    local changed = false
    for _ = 1, BATCH do
        queueIndex = queueIndex + 1
        local item = queue[queueIndex]
        if not item then
            self:Hide()
            break
        end
        if not states[item.id] and Check(item) then changed = true end
    end
    if changed then ScheduleRefresh() end
end)

function EverGear:CheckUnconfirmedItems()
    queue, queueIndex = {}, 0
    for _, item in pairs(self.Items) do
        if item.unverified and not states[item.id] then queue[#queue + 1] = item end
    end
    if #queue > 0 then checker:Show() end
end

local events = CreateFrame("Frame", "EverGearUnconfirmedEvents")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, itemId, success)
    if event == "PLAYER_LOGIN" then
        EverGear:CheckUnconfirmedItems()
        return
    end
    local item = EverGear.Items[itemId]
    if not (item and item.unverified) or states[itemId] then return end
    if success == false then
        states[itemId] = "missing"
    elseif not Check(item) then
        return
    end
    ScheduleRefresh()
end)

-- nil for a confirmed item; "live" (the game has it), "missing" (it doesn't)
-- or "pending" (no answer yet) for an unconfirmed one.
function EverGear:GetUnconfirmedState(item)
    if not item or not item.unverified then return nil end
    return states[item.id] or "pending"
end

-- ===== Debug report =====

-- Every unconfirmed item and what the game said about it, as JSON for the
-- backend, keyed by item id like a capture: "live" items carry the game's
-- record (with _diffs against the data, "ok" or "differs"), "missing" ones
-- aren't in the game. /eg debug unconfirmed shows it.
function EverGear:BuildUnconfirmedReportJSON()
    local out, counts = {}, { ok = 0, differs = 0, missing = 0, pending = 0 }
    for id, item in pairs(self.Items) do
        local state = self:GetUnconfirmedState(item)
        if state then
            local entry
            if state == "live" and item.liveRecord then
                entry = {}
                for k, v in pairs(item.liveRecord) do entry[k] = v end
                local diffs = self.CompareLiveToDatabase and self:CompareLiveToDatabase(item.liveRecord, item) or {}
                entry._status = #diffs > 0 and "differs" or "ok"
                entry._diffs = #diffs > 0 and diffs or nil
                entry._addonStats = item.dataStats
            else
                entry = { id = id, name = item.name, _status = (state == "live") and "ok" or state }
            end
            counts[entry._status] = (counts[entry._status] or 0) + 1
            out[tostring(id)] = entry
        end
    end
    out._summary = counts
    return self.JSON.encode(out), counts
end
