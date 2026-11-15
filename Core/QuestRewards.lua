-- Captures quest rewards while playing, with debug mode on (/eg debug).
--
-- The reward window that opens when a quest is turned in (QUEST_COMPLETE) lists every
-- reward the quest gives, so each time one opens this reads it:
--   * every reward item the addon doesn't have, or has wrong, is captured, the same
--     capture as hovering it (see Debug.lua), plus the quest it came from ("_quest" in
--     the capture: title, quest id, quest level, zone, the NPC, your faction and level);
--   * every turn-in is also recorded in EverGearDB.questRewards, so what the addon
--     files under a quest can be checked against what the quest really gives.
-- Nothing is accepted or chosen for you, and nothing happens with debug mode off.
-- Items EverGear doesn't track (potions, bags, quest items, gray items) are only
-- listed in the turn-in record.
--
-- /eg debug quests shows the turn-in records as JSON; /eg debug export shows the captures.

EverGear = EverGear or {}

local WINDOW_READS = 4      -- tries to get every reward's link while the window is open
local ITEM_TRIES = 8        -- tries for an item the game hasn't sent yet
local RETRY_SECONDS = 1

local windowOpen = false
local readToken = 0

local function DebugOn()
    return EverGearDB and EverGearDB.debugMode
end

local function Records()
    EverGearDB.questRewards = EverGearDB.questRewards or {}
    return EverGearDB.questRewards
end

local function After(seconds, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, fn)
    else
        fn()
    end
end

-- The level the quest log shows for a quest being turned in, or nil. The quest is
-- still in the log while its reward window is open.
local function QuestLogLevel(questId, title)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo and questId then
        local index = C_QuestLog.GetLogIndexForQuestID(questId)
        local info = index and C_QuestLog.GetInfo(index)
        if info and info.level and info.level > 0 then return info.level end
    end
    if GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (GetNumQuestLogEntries()) do
            local name, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and name and ((questId and id == questId) or (not questId and name == title)) then
                if level and level > 0 then return level end
            end
        end
    end
    return nil
end

-- Item id out of an item link.
local function IdFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Reads the open reward window. Returns the list of rewards ({ id, link, name, kind },
-- kind being "choice" or "reward") and how many rewards had no link yet.
local function ReadRewards()
    local list, unread = {}, 0
    local function scan(kind, count)
        for i = 1, count or 0 do
            local link = GetQuestItemLink and GetQuestItemLink(kind, i)
            local name = GetQuestItemInfo and GetQuestItemInfo(kind, i)
            local id = IdFromLink(link)
            if id then
                list[#list + 1] = { id = id, link = link, name = name, kind = kind }
            else
                unread = unread + 1
            end
        end
    end
    scan("choice", GetNumQuestChoices and GetNumQuestChoices())
    scan("reward", GetNumQuestRewards and GetNumQuestRewards())
    return list, unread
end

local function QuestKey(questId, title, zone)
    if questId and questId > 0 then return tostring(questId) end
    return (title or "?") .. " | " .. (zone or "?")
end

-- Captures one reward item, trying again while the game hasn't sent it yet.
local function CaptureItem(reward, quest, record, tries)
    tries = tries or 1
    local status, reason = EverGear:CaptureQuestRewardItem(reward.id, reward.link, quest)
    if reason == "uncached" and tries < ITEM_TRIES then
        local load = C_Item and C_Item.RequestLoadItemDataByID
        if load then load(reward.id) end
        After(RETRY_SECONDS, function() CaptureItem(reward, quest, record, tries + 1) end)
        return
    end
    local entry = record.items[tostring(reward.id)]
    if not entry then return end
    if status then
        entry.status = status
    else
        entry.status = "skipped"
        entry.skipReason = reason
    end
    if status == "missing" or status == "pending" or status == "differs" then
        local label = (status == "differs") and "differs from the addon" or "not in the addon"
        print(string.format("|cff33ff99EverGear|r debug: captured %s from \"%s\" (%s).",
            reward.name or ("item " .. reward.id), quest.title or "?", label))
    end
end

local function RecordTurnIn(rewards, unread)
    local title = GetTitleText and GetTitleText() or nil
    local questId = GetQuestID and GetQuestID() or nil
    if questId == 0 then questId = nil end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
    local quest = {
        title = title,
        id = questId,
        level = QuestLogLevel(questId, title),
        playerLevel = UnitLevel("player"),
        zone = zone,
        subzone = GetSubZoneText and GetSubZoneText() or nil,
        npc = (UnitName and (UnitName("questnpc") or UnitName("npc"))) or nil,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }

    local record = {
        quest = quest,
        choices = {},
        rewards = {},
        items = {},
        unreadRewards = unread > 0 and unread or nil,
        lastSeen = date and date("%Y-%m-%d %H:%M") or nil,
    }
    for _, reward in ipairs(rewards) do
        local list = (reward.kind == "choice") and record.choices or record.rewards
        list[#list + 1] = reward.id
        local dbItem = EverGear:GetItem(reward.id)
        local dbSource = dbItem and dbItem.source
        record.items[tostring(reward.id)] = {
            id = reward.id,
            name = reward.name,
            kind = reward.kind,
            inAddon = dbItem and true or false,
            -- The quest the addon files this item under, to spot a wrong or missing quest name.
            addonQuest = dbSource and dbSource.type == "quest" and dbSource.quest or nil,
        }
    end
    Records()[QuestKey(questId, title, zone)] = record

    -- Always say that the turn-in was seen, so it's clear the feature is working.
    local known = 0
    for _, item in pairs(record.items) do
        if item.inAddon then known = known + 1 end
    end
    local message = string.format("|cff33ff99EverGear|r debug: recorded \"%s\" (%s) -- %d reward item(s), %d already in the addon.",
        title or "?", zone or "?", #rewards, known)
    if unread > 0 then
        message = message .. string.format(" %d reward(s) couldn't be read, hover them in the window.", unread)
    end
    print(message)

    for _, reward in ipairs(rewards) do
        CaptureItem(reward, quest, record)
    end
end

-- Reads the window now, and again a few times while some reward links haven't
-- arrived (the game only knows an item's link once it has sent the item).
local function HandleWindow(token, attempt)
    if token ~= readToken or not windowOpen or not DebugOn() then return end
    local rewards, unread = ReadRewards()
    if unread > 0 and attempt < WINDOW_READS then
        After(RETRY_SECONDS, function() HandleWindow(token, attempt + 1) end)
        return
    end
    RecordTurnIn(rewards, unread)
end

local frame = CreateFrame("Frame", "EverGearQuestRewardEvents")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_FINISHED")
frame:SetScript("OnEvent", function(_, event)
    if event == "QUEST_FINISHED" then
        windowOpen = false
        return
    end
    windowOpen = true
    readToken = readToken + 1
    if DebugOn() then HandleWindow(readToken, 1) end
end)

-- Every recorded turn-in as JSON, and how many there are.
function EverGear:BuildQuestRewardsJSON()
    local out, count = {}, 0
    for key, record in pairs(Records()) do
        out[key] = record
        count = count + 1
    end
    return self.JSON.encode(out), count
end
