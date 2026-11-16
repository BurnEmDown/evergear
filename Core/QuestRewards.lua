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

local announced = {}   -- itemId -> true once its capture was reported this session
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
    if (status == "missing" or status == "pending" or status == "differs") and not announced[reward.id] then
        announced[reward.id] = true
        local label = (status == "differs") and "differs from the addon" or "not in the addon"
        print(string.format("|cff33ff99EverGear|r debug: captured %s from \"%s\" (%s).",
            reward.name or ("item " .. reward.id), quest.title or "?", label))
    end
end

-- Stores one quest's rewards and captures what's new. quest = { title, id, level, playerLevel,
-- zone, subzone, npc, faction }. source is "turn-in" or "log". quiet skips the summary line.
local function Record(quest, rewards, unread, source, quiet)
    local record = {
        quest = quest,
        source = source,
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
    Records()[QuestKey(quest.id, quest.title, quest.zone)] = record

    -- Always say that the turn-in was seen, so it's clear the feature is working.
    if not quiet then
        local known = 0
        for _, item in pairs(record.items) do
            if item.inAddon then known = known + 1 end
        end
        local message = string.format("|cff33ff99EverGear|r debug: recorded \"%s\" (%s) -- %d reward item(s), %d already in the addon.",
            quest.title or "?", quest.zone or "?", #rewards, known)
        if unread > 0 then
            message = message .. string.format(" %d reward(s) couldn't be read, hover them in the window.", unread)
        end
        print(message)
    end

    for _, reward in ipairs(rewards) do
        CaptureItem(reward, quest, record)
    end
end

local function RecordTurnIn(rewards, unread)
    local title = GetTitleText and GetTitleText() or nil
    local questId = GetQuestID and GetQuestID() or nil
    if questId == 0 then questId = nil end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or nil
    Record({
        title = title,
        id = questId,
        level = QuestLogLevel(questId, title),
        playerLevel = UnitLevel("player"),
        zone = zone,
        subzone = GetSubZoneText and GetSubZoneText() or nil,
        npc = (UnitName and (UnitName("questnpc") or UnitName("npc"))) or nil,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }, rewards, unread, "turn-in")
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

-- ===== Scanning the quest log =====
-- A quest in your log shows its rewards in the log's detail panel, so every quest you
-- have can be read without turning it in. The zone is the log's zone heading for it.
-- Needs the classic quest log calls; zone headings that are collapsed hide their quests.

local function ReadLogRewards()
    local list, unread = {}, 0
    local function scan(kind, count)
        for i = 1, count or 0 do
            local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, i)
            local name = GetQuestLogRewardInfo and kind == "reward" and GetQuestLogRewardInfo(i)
                or GetQuestLogChoiceInfo and kind == "choice" and GetQuestLogChoiceInfo(i) or nil
            local id = IdFromLink(link)
            if id then
                list[#list + 1] = { id = id, link = link, name = name, kind = kind }
            else
                unread = unread + 1
            end
        end
    end
    scan("choice", GetNumQuestLogChoices and GetNumQuestLogChoices())
    scan("reward", GetNumQuestLogRewards and GetNumQuestLogRewards())
    return list, unread
end

-- The quest log has two APIs: the classic one (GetQuestLogTitle, SelectQuestLogEntry, ...) and
-- the newer C_QuestLog one that WoW Forever's client is expected to use. These wrappers use
-- whichever the client has.
local function LogEntryCount()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then return (C_QuestLog.GetNumQuestLogEntries()) end
    if GetNumQuestLogEntries then return (GetNumQuestLogEntries()) end
end

-- { title, level, isHeader, isCollapsed, questId } for log entry i, or nil.
local function LogEntry(i)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if not info then return nil end
        return { title = info.title, level = info.level, isHeader = info.isHeader,
                 isCollapsed = info.isCollapsed, questId = info.questID }
    end
    if GetQuestLogTitle then
        local title, level, _, isHeader, isCollapsed, _, _, questId = GetQuestLogTitle(i)
        if not title then return nil end
        return { title = title, level = level, isHeader = isHeader, isCollapsed = isCollapsed, questId = questId }
    end
end

-- What is selected in the quest log now: a quest id (newer API) or an index (classic).
local function LogSelection()
    if C_QuestLog and C_QuestLog.GetSelectedQuest then return C_QuestLog.GetSelectedQuest() end
    if GetQuestLogSelection then return GetQuestLogSelection() end
end

local function SelectLogEntry(i, entry)
    if C_QuestLog and C_QuestLog.SetSelectedQuest and entry.questId then
        C_QuestLog.SetSelectedQuest(entry.questId)
    elseif SelectQuestLogEntry then
        SelectQuestLogEntry(i)
    end
end

local function RestoreSelection(previous)
    if not previous or previous == 0 then return end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(previous)
    elseif SelectQuestLogEntry then
        SelectQuestLogEntry(previous)
    end
end

local function ReadLogRewards(questId)
    local list, unread = {}, 0
    local function scan(kind, count)
        for i = 1, count or 0 do
            local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, i, questId)
            local name
            if kind == "reward" and GetQuestLogRewardInfo then
                name = GetQuestLogRewardInfo(i, questId)
            elseif kind == "choice" and GetQuestLogChoiceInfo then
                name = GetQuestLogChoiceInfo(i, questId)
            end
            local id = IdFromLink(link)
            if id then
                list[#list + 1] = { id = id, link = link, name = name, kind = kind }
            else
                unread = unread + 1
            end
        end
    end
    scan("choice", GetNumQuestLogChoices and GetNumQuestLogChoices(questId))
    scan("reward", GetNumQuestLogRewards and GetNumQuestLogRewards(questId))
    return list, unread
end

-- Names of the calls the scan needs that this client doesn't have.
local function MissingForScan()
    local missing = {}
    local function need(label, ok) if not ok then missing[#missing + 1] = label end end
    need("a quest log entry count (GetNumQuestLogEntries or C_QuestLog.GetNumQuestLogEntries)",
        LogEntryCount ~= nil and ((C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries))
    need("a way to read log entries (GetQuestLogTitle or C_QuestLog.GetInfo)",
        (C_QuestLog and C_QuestLog.GetInfo) or GetQuestLogTitle)
    need("a way to select a log entry (SelectQuestLogEntry or C_QuestLog.SetSelectedQuest)",
        (C_QuestLog and C_QuestLog.SetSelectedQuest) or SelectQuestLogEntry)
    need("GetNumQuestLogChoices", GetNumQuestLogChoices)
    need("GetNumQuestLogRewards", GetNumQuestLogRewards)
    need("GetQuestLogItemLink", GetQuestLogItemLink)
    return missing
end

local function ScanOnce()
    local selected = LogSelection()
    local zone, quests, withItems, unreadTotal, collapsed = nil, 0, 0, 0, 0
    for i = 1, (LogEntryCount() or 0) do
        local entry = LogEntry(i)
        if entry and entry.isHeader then
            zone = entry.title
            if entry.isCollapsed then collapsed = collapsed + 1 end
        elseif entry and entry.title then
            SelectLogEntry(i, entry)
            local questId = (entry.questId and entry.questId > 0) and entry.questId or nil
            local rewards, unread = ReadLogRewards(questId)
            quests = quests + 1
            unreadTotal = unreadTotal + unread
            if #rewards > 0 then withItems = withItems + 1 end
            Record({
                title = entry.title,
                id = questId,
                level = entry.level,
                playerLevel = UnitLevel("player"),
                zone = zone,
                faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
            }, rewards, unread, "log", true)
        end
    end
    RestoreSelection(selected)
    return { quests = quests, withItems = withItems, unread = unreadTotal, collapsed = collapsed }
end

-- /eg debug scanlog. Runs twice, the second time after a moment, because item links
-- that weren't loaded the first time usually are by then.
function EverGear:ScanQuestLog()
    local missing = MissingForScan()
    if #missing > 0 then
        print("|cff33ff99EverGear|r debug: can't scan the quest log -- this client has no:")
        for _, label in ipairs(missing) do print("  " .. label) end
        print("  Run /eg debug api and send me its output.")
        return
    end
    local result = ScanOnce()
    print(string.format("|cff33ff99EverGear|r debug: scanned %d quests in your log, %d with item rewards.",
        result.quests, result.withItems))
    if result.collapsed > 0 then
        print(string.format("  %d zone heading(s) are collapsed, so their quests were skipped: expand them (click the +) and scan again.",
            result.collapsed))
    end
    if result.unread > 0 then
        After(2, function()
            local again = ScanOnce()
            if again and again.unread > 0 then
                print(string.format("|cff33ff99EverGear|r debug: %d reward(s) still couldn't be read; scan again in a moment.", again.unread))
            end
        end)
    end
end

-- /eg debug api: which of the game calls EverGear's quest features use this client has.
function EverGear:PrintQuestApi()
    local names = {
        "GetNumQuestLogEntries", "GetQuestLogTitle", "SelectQuestLogEntry", "GetQuestLogSelection",
        "GetNumQuestLogChoices", "GetNumQuestLogRewards", "GetQuestLogItemLink",
        "GetQuestLogChoiceInfo", "GetQuestLogRewardInfo",
        "GetNumQuestChoices", "GetNumQuestRewards", "GetQuestItemLink", "GetQuestItemInfo",
        "GetQuestID", "GetTitleText",
    }
    local cNames = { "GetNumQuestLogEntries", "GetInfo", "GetSelectedQuest", "SetSelectedQuest",
        "GetLogIndexForQuestID", "GetQuestInfo", "IsQuestFlaggedCompleted" }
    local have, missing = {}, {}
    for _, name in ipairs(names) do
        if _G[name] then have[#have + 1] = name else missing[#missing + 1] = name end
    end
    for _, name in ipairs(cNames) do
        local label = "C_QuestLog." .. name
        if C_QuestLog and C_QuestLog[name] then have[#have + 1] = label else missing[#missing + 1] = label end
    end
    print("|cff33ff99EverGear|r debug: quest API check")
    print("  available: " .. (#have > 0 and table.concat(have, ", ") or "none"))
    print("  missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
end
