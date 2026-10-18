-- The Filters window: every filter in one place, opened by the Filters button
-- on the main window's right edge (and opening on that side, like the other
-- right-hand windows). Three tabs:
--   * Sources: where items come from. Each source has its own extra settings
--     right under it: Craft has the professions (and BoE Only for each), PvP
--     has "Only what my rank allows", Reputation has "Only what my reputation
--     allows" and a scrolling list of the factions with gear, each with the
--     character's standing and a box to show or hide that faction's gear.
--   * Weapons: weapon types, with All / None / Usable Only.
--   * Zones: zones and dungeons, with Show All / Show None / Current Level.
-- Every setting is stored where it always was, so nothing a player already
-- chose is lost: charDB.filters (sources), professionFilter and
-- professionBoEOnly, pvpFilter (hidden / ignoreRank), reputationFilter
-- (ignoreStanding, hiddenFactions), weaponTypeFilter and zoneFilter. Upgrades.lua's
-- PassesFilterPanels and UI.lua's RefreshUI read them.

EverGear = EverGear or {}

local H = EverGear.UIHelpers
local THEME = H.THEME
local mainFrame = EverGear.Frame

local WINDOW_TOP = -64        -- where a tab's contents start, below the title and tabs
local ROW = 24                -- a checkbox row
local SUB_ROW = 22            -- an indented setting under a source
local LINE = 14               -- a line of small text
local INDENT = 22

-- ===== Settings =====
-- Each read goes through the character's saved settings fresh (see UI.lua's
-- GetSourceFilters for why none of these are cached).

local function CharDB() return EverGear:GetCharDB() end

local function Sources()
    local db = CharDB()
    db.filters = db.filters or {}
    return db.filters
end

local function Table(key)
    local db = CharDB()
    db[key] = db[key] or {}
    return db[key]
end

local function Refresh() EverGear:RefreshUI() end

-- ===== The window =====

local window = CreateFrame("Frame", "EverGearFiltersPanel", mainFrame, "BackdropTemplate")
window:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
window:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0)
window:Hide()

local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -2, -2)

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -14)
title:SetText("Filters")
title:SetTextColor(unpack(THEME.gold))

local function Note(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontDisableSmall")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Tooltip(frame, heading, text, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(heading)
        GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A named checkbox (the tutorial and tests find them by name) whose checked
-- state comes from isOn() and is saved through setOn(on).
local function Checkbox(parent, name, label, x, y, isOn, setOn, small)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    if small then cb:SetSize(22, 22) end
    cb:SetPoint("TOPLEFT", x, y)
    local text = _G[name .. "Text"]
    if text then
        text:SetText(label)
        if small then text:SetFontObject("GameFontHighlightSmall") end
    end
    cb.isOn = isOn
    cb:SetScript("OnClick", function(self)
        setOn(self:GetChecked() and true or false)
        EverGear:SyncFiltersWindow()
        Refresh()
    end)
    return cb
end

local function SetEnabled(cb, enabled)
    if enabled then cb:Enable() else cb:Disable() end
    local text = cb:GetName() and _G[cb:GetName() .. "Text"]
    if text then text:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5) end
end

local function SmallButton(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- ===== Tabs =====

local pages, tabButtons, pageSizes = {}, {}, {}
local currentTab = "sources"
local TAB_ORDER = { "sources", "weapons", "zones" }
local TAB_LABELS = { sources = "Sources", weapons = "Weapons", zones = "Zones" }

for i, key in ipairs(TAB_ORDER) do
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    page:Hide()
    pages[key] = page

    local tab = CreateFrame("Button", "EverGearFiltersTab" .. TAB_LABELS[key], window, "UIPanelButtonTemplate")
    tab:SetSize(90, 22)
    tab:SetPoint("TOPLEFT", 18 + (i - 1) * 94, -34)
    tab:SetText(TAB_LABELS[key])
    tab:SetScript("OnClick", function() EverGear:SelectFiltersTab(key) end)
    tabButtons[key] = tab
end

-- ===== Sources tab =====

local sourcesPage = pages.sources
local sourceChecks = {}       -- every checkbox on the page, refreshed together
local COLUMN_2 = 316

local function SourceCheck(key, label, x, y)
    local cb = Checkbox(sourcesPage, "EverGearFilter_" .. key, label, x, y,
        function() return Sources()[key] ~= false end,
        function(on) Sources()[key] = on end)
    table.insert(sourceChecks, cb)
    return cb
end

-- Left column: the plain sources, then PvP and Reputation with their limits.
local y = WINDOW_TOP
for _, entry in ipairs({
    { key = "quest", label = "Quest" },
    { key = "vendor", label = "Vendor" },
    { key = "worldDrop", label = "World Drop" },
    { key = "dungeonDrop", label = "Dungeon Drop" },
    { key = "special", label = "Special" },
}) do
    SourceCheck(entry.key, entry.label, 16, y)
    y = y - ROW
end

-- PvP: the honor vendors' gear and the battleground reputation gear.
local pvpCheck = Checkbox(sourcesPage, "EverGearFilter_pvp", "PvP", 16, y,
    function() return not Table("pvpFilter").hidden end,
    function(on) Table("pvpFilter").hidden = not on or nil end)
Tooltip(pvpCheck, "PvP", "Gear from the PvP honor vendors, bought with Honor and Marks of Honor, and from the "
    .. "battleground reputation vendors (Arathi Basin, Darkspear Islands).")
table.insert(sourceChecks, pvpCheck)
y = y - ROW
local pvpRankCheck = Checkbox(sourcesPage, "EverGearFilterPvPRank", "Only what my rank allows", 16 + INDENT, y + 2,
    function() return not Table("pvpFilter").ignoreRank end,
    function(on) Table("pvpFilter").ignoreRank = not on or nil end, true)
Tooltip(pvpRankCheck, "Only what my rank allows", "Leave out items that need a higher PvP rank than you have. "
    .. "Most PvP gear needs no rank; the weapons, cloaks, necks and insignias do.")
table.insert(sourceChecks, pvpRankCheck)
y = y - SUB_ROW
local pvpRankText = Note(sourcesPage, "", "GameFontNormalSmall")
pvpRankText:SetPoint("TOPLEFT", 16 + INDENT + 6, y)
pvpRankText:SetTextColor(unpack(THEME.parchment))
y = y - LINE - 10

-- Reputation: every reputation vendor, battleground or not.
local repCheck = SourceCheck("reputation", "Reputation", 16, y)
Tooltip(repCheck, "Reputation", "Gear sold by reputation vendors, such as Booty Bay or Gadgetzan, and by the "
    .. "battleground vendors.")
y = y - ROW
local repStandingCheck = Checkbox(sourcesPage, "EverGearFilterReputationStanding", "Only what my reputation allows",
    16 + INDENT, y + 2,
    function() return not Table("reputationFilter").ignoreStanding end,
    function(on) Table("reputationFilter").ignoreStanding = not on or nil end, true)
Tooltip(repStandingCheck, "Only what my reputation allows", "Leave out reputation gear that needs a higher "
    .. "standing than you have with its faction.")
table.insert(sourceChecks, repStandingCheck)
y = y - SUB_ROW

local STANDING_NAMES = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- The factions with reputation gear this character's side can buy, by name.
local function ReputationFactions()
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    local seen, list = {}, {}
    for _, item in pairs(EverGear.Items) do
        local source = item.source
        if source and source.type == "reputation" and source.repFactionId and not seen[source.repFactionId]
            and (not source.faction or source.faction == playerFaction) then
            seen[source.repFactionId] = true
            list[#list + 1] = { id = source.repFactionId, name = source.repFaction or "?" }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Factions the player turned off (charDB.reputationFilter.hiddenFactions,
-- by faction id): their gear is left out whatever the standing.
local function HiddenFactions()
    local filter = Table("reputationFilter")
    filter.hiddenFactions = filter.hiddenFactions or {}
    return filter.hiddenFactions
end

-- The reputation list: one row per faction (a checkbox to show or hide its
-- gear, the name, the standing right-aligned), REP_ROWS at a time. More
-- factions than that scroll, with the mouse wheel or the scroll bar.
local REP_ROWS, REP_ROW_HEIGHT = 7, 18
-- The list sits in its own recessed box (dark fill, thin gold edge, like the
-- main window's gear area), as wide as the left column, with the scroll bar
-- inside its right edge. Rows are children of the box, so they draw over it.
local REP_BOX_LEFT, REP_BOX_RIGHT = 18, COLUMN_2 - 14
local REP_PAD, REP_SCROLLBAR = 6, 22
local REP_TEXT_RIGHT = REP_BOX_RIGHT - REP_BOX_LEFT - REP_PAD - REP_SCROLLBAR
local repFactions = {}
local repRows = {}
local repTitle = Note(sourcesPage, "Your standing:", "GameFontNormalSmall")
repTitle:SetPoint("TOPLEFT", REP_BOX_LEFT + 4, y - 4)
repTitle:SetTextColor(unpack(THEME.parchment))
y = y - LINE - 8

local repBox = CreateFrame("Frame", "EverGearFiltersReputationList", sourcesPage, "BackdropTemplate")
repBox:SetPoint("TOPLEFT", REP_BOX_LEFT, y)
repBox:SetSize(REP_BOX_RIGHT - REP_BOX_LEFT, REP_ROWS * REP_ROW_HEIGHT + 2 * REP_PAD)
repBox:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
repBox:SetBackdropColor(unpack(THEME.panelBg))
repBox:SetBackdropBorderColor(unpack(THEME.panelBorder))
local repListTop = -REP_PAD   -- inside the box

local repScroll = CreateFrame("ScrollFrame", "EverGearFiltersReputationScroll", repBox, "FauxScrollFrameTemplate")
repScroll:SetPoint("TOPLEFT", REP_PAD, repListTop)
repScroll:SetSize(REP_TEXT_RIGHT - REP_PAD, REP_ROWS * REP_ROW_HEIGHT)

local function RepOffset()
    return tonumber(FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(repScroll)) or 0
end

local function UpdateReputationRows()
    local count = #repFactions
    if FauxScrollFrame_Update then FauxScrollFrame_Update(repScroll, count, REP_ROWS, REP_ROW_HEIGHT) end
    local offset = RepOffset()
    local hidden = HiddenFactions()
    local enabled = Sources().reputation ~= false
    for i, row in ipairs(repRows) do
        local faction = repFactions[offset + i]
        if faction then
            row.faction = faction
            row.check:SetChecked(not hidden[faction.id])
            SetEnabled(row.check, enabled)
            row.name:SetText(faction.name)
            row.standing:SetText(STANDING_NAMES[EverGear:GetPlayerStanding(faction.id)] or "?")
            row.check:Show(); row.name:Show(); row.standing:Show()
        else
            row.faction = nil
            row.check:Hide(); row.name:Hide(); row.standing:Hide()
        end
    end
end

repScroll:SetScript("OnVerticalScroll", function(self, offset)
    if FauxScrollFrame_OnVerticalScroll then
        FauxScrollFrame_OnVerticalScroll(self, offset, REP_ROW_HEIGHT, UpdateReputationRows)
    end
end)

for i = 1, REP_ROWS do
    local rowY = repListTop - (i - 1) * REP_ROW_HEIGHT
    local check = CreateFrame("CheckButton", "EverGearFiltersReputationRow" .. i, repBox, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("TOPLEFT", REP_PAD - 2, rowY + 1)
    -- Faction on the left, standing right-aligned; a long name is cut short
    -- rather than wrapping onto the next line.
    local standing = Note(repBox, "", "GameFontHighlightSmall")
    standing:SetJustifyH("RIGHT")
    standing:SetPoint("TOPRIGHT", repBox, "TOPLEFT", REP_TEXT_RIGHT, rowY - 3)
    local name = Note(repBox, "", "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", REP_PAD + 20, rowY - 3)
    name:SetPoint("RIGHT", standing, "LEFT", -6, 0)
    if name.SetWordWrap then name:SetWordWrap(false) end
    local row = { check = check, name = name, standing = standing }
    check:SetScript("OnClick", function(self)
        if not row.faction then return end
        HiddenFactions()[row.faction.id] = (not self:GetChecked()) or nil
        Refresh()
    end)
    check:SetScript("OnEnter", function(self)
        if not row.faction then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.faction.name)
        GameTooltip:AddLine("Untick to leave out this faction's gear.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    repRows[i] = row
end

local function SetAllFactions(shown)
    local hidden = HiddenFactions()
    for _, faction in ipairs(repFactions) do hidden[faction.id] = (not shown) or nil end
    UpdateReputationRows()
    Refresh()
end
y = y - REP_ROWS * REP_ROW_HEIGHT - 2 * REP_PAD - 6
local repAll = SmallButton(sourcesPage, "All", 60, function() SetAllFactions(true) end)
repAll:SetPoint("TOPLEFT", REP_BOX_LEFT, y)
local repNone = SmallButton(sourcesPage, "None", 60, function() SetAllFactions(false) end)
repNone:SetPoint("LEFT", repAll, "RIGHT", 6, 0)
local leftBottom = -(y - 24)

-- Right column: Craft and the professions under it.
local craftCheck = SourceCheck("craft", "Craft", COLUMN_2, WINDOW_TOP)
Tooltip(craftCheck, "Craft", "Crafted items. Pick the professions below; for a profession you don't have, BoE Only "
    .. "keeps just the Bind on Equip items you could buy from other players.")
local boeHeader = Note(sourcesPage, "BoE Only", "GameFontNormalSmall")
boeHeader:SetTextColor(unpack(THEME.goldDim))
boeHeader:SetPoint("TOPRIGHT", sourcesPage, "TOPLEFT", COLUMN_2 + 226, WINDOW_TOP - ROW - 2)

local professionChecks = {}
local py = WINDOW_TOP - ROW - 14
for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do
    local cb = Checkbox(sourcesPage, "EverGearProfessionFilterCheck_" .. profName, profName, COLUMN_2 + INDENT, py,
        function() return Table("professionFilter")[profName] ~= false end,
        function(on) Table("professionFilter")[profName] = on end, true)
    local boe = Checkbox(sourcesPage, "EverGearProfessionBoECheck_" .. profName, "", COLUMN_2 + 204, py,
        function() return Table("professionBoEOnly")[profName] == true end,
        function(on) Table("professionBoEOnly")[profName] = on end, true)
    Tooltip(boe, "BoE Only", "Only suggest " .. profName .. " items confirmed Bind on Equip, for checking crafted "
        .. "gear from a profession you don't have.", "ANCHOR_LEFT")
    table.insert(professionChecks, { cb = cb, boe = boe })
    table.insert(sourceChecks, cb)
    table.insert(sourceChecks, boe)
    py = py - SUB_ROW
end

local function SetAllProfessions(on)
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do Table("professionFilter")[profName] = on end
    EverGear:SyncFiltersWindow()
    Refresh()
end
local professionAll = SmallButton(sourcesPage, "All", 60, function() SetAllProfessions(true) end)
professionAll:SetPoint("TOPLEFT", COLUMN_2 + INDENT, py - 4)
local professionNone = SmallButton(sourcesPage, "None", 60, function() SetAllProfessions(false) end)
professionNone:SetPoint("LEFT", professionAll, "RIGHT", 6, 0)

local function RefreshSourcesPage()
    for _, cb in ipairs(sourceChecks) do cb:SetChecked(cb.isOn()) end
    SetEnabled(pvpRankCheck, pvpCheck:GetChecked())
    SetEnabled(repStandingCheck, repCheck:GetChecked())
    local craftOn = craftCheck:GetChecked()
    for _, row in ipairs(professionChecks) do
        SetEnabled(row.cb, craftOn)
        SetEnabled(row.boe, craftOn)
    end

    local rank, rankName = EverGear:GetPlayerPvPRank()
    pvpRankText:SetText(rank > 0 and ("Your PvP rank: " .. (rankName or "?") .. " (rank " .. rank .. ")")
        or "Your PvP rank: none yet")

    repFactions = ReputationFactions()
    UpdateReputationRows()
    local repOn = repCheck:GetChecked()
    if repOn then repAll:Enable(); repNone:Enable() else repAll:Disable(); repNone:Disable() end
    local rightBottom = -py + 28
    pageSizes.sources = { COLUMN_2 + 240, math.max(leftBottom, rightBottom) + 24 }
end

-- ===== Weapons tab =====
-- One row per weapon type; Axe / Mace / Sword split into 1H and 2H (see
-- Constants.lua's SPLIT_WEAPON_TYPES), so e.g. a Protection Warrior can hide
-- 2H maces only. Every type gets a row for every class (WoW Forever doesn't
-- gate weapon usability as strictly as the original game); class only decides
-- each row's starting state and what Usable Only picks.

local weaponsPage = pages.weapons
local weaponEntries = {}
for _, entry in ipairs(EverGear.WEAPON_TYPE_FILTER_LIST) do
    if EverGear.SPLIT_WEAPON_TYPES[entry.key] then
        table.insert(weaponEntries, { key = entry.key .. ":1h", label = entry.label .. " (1H)" })
        table.insert(weaponEntries, { key = entry.key .. ":2h", label = entry.label .. " (2H)" })
    else
        table.insert(weaponEntries, { key = entry.key, label = entry.label })
    end
end

-- Seed each row's starting state from class usability, only the first time a
-- key is seen: a choice the player already made is never overwritten.
do
    local classToken = EverGear:GetPlayerInfo().classToken
    local filters = Table("weaponTypeFilter")
    for _, entry in ipairs(weaponEntries) do
        if filters[entry.key] == nil then
            filters[entry.key] = EverGear:IsWeaponFilterKeyUsable(entry.key, classToken)
        end
    end
end

local WEAPON_COL_WIDTH = 130
local weaponChecks = {}
for index, entry in ipairs(weaponEntries) do
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local cb = Checkbox(weaponsPage, "EverGearWeaponFilterCheck_" .. entry.key:gsub("[%s:]", "_"), entry.label,
        16 + col * WEAPON_COL_WIDTH, WINDOW_TOP - row * SUB_ROW,
        function() return Table("weaponTypeFilter")[entry.key] ~= false end,
        function(on) Table("weaponTypeFilter")[entry.key] = on end)
    table.insert(weaponChecks, cb)
end
local weaponRows = math.ceil(#weaponEntries / 2)
local weaponButtonsY = WINDOW_TOP - weaponRows * SUB_ROW - 10

local function SetWeapons(valueFor)
    local filters = Table("weaponTypeFilter")
    for _, entry in ipairs(weaponEntries) do filters[entry.key] = valueFor(entry.key) end
    EverGear:SyncFiltersWindow()
    Refresh()
end
local weaponAll = SmallButton(weaponsPage, "All", 70, function() SetWeapons(function() return true end) end)
weaponAll:SetPoint("TOPLEFT", 18, weaponButtonsY)
local weaponNone = SmallButton(weaponsPage, "None", 70, function() SetWeapons(function() return false end) end)
weaponNone:SetPoint("LEFT", weaponAll, "RIGHT", 6, 0)
local weaponUsable = SmallButton(weaponsPage, "Usable Only", 110, function()
    local classToken = EverGear:GetPlayerInfo().classToken
    SetWeapons(function(key) return EverGear:IsWeaponFilterKeyUsable(key, classToken) end)
end)
weaponUsable:SetPoint("LEFT", weaponNone, "RIGHT", 6, 0)
pageSizes.weapons = { 2 * WEAPON_COL_WIDTH + 40, -weaponButtonsY + 40 }

local function RefreshWeaponsPage()
    for _, cb in ipairs(weaponChecks) do cb:SetChecked(cb.isOn()) end
end

-- ===== Zones tab =====
-- Each zone and dungeon named as an item's source (quest rewards, boss and
-- trash drops, a zone's rare mob, vendors). Unticking one hides everything
-- from there; items not tied to one place (crafted items, world drops from all
-- over, class quests) are never hidden by it. A place counts as a dungeon when
-- any of its items is a dungeon drop. Built from the item data the first time
-- the tab opens, so new zones show up without touching this code.

local zonesPage = pages.zones
local ZONE_ROW_HEIGHT = 20
local ZONE_DUNGEON_COL_WIDTH = 190
local ZONE_ZONE_COL_WIDTH = 160
local ZONE_TOP_Y = WINDOW_TOP - 18
local zoneChecks = {}

-- Every place named as an item source, split into dungeons and zones, each
-- sorted by name ("The Deadmines" under D).
function EverGear.CollectSourceZones()
    local isDungeon, seen = {}, {}
    local faction = EverGear:GetPlayerInfo().faction
    for _, item in pairs(EverGear.Items) do
        local source = item.source
        for _, zone in ipairs(EverGear:GetSourceZones(item, faction)) do
            seen[zone] = true
            if source.type == "dungeonDrop" or source.type == "raidDrop" then isDungeon[zone] = true end
        end
    end
    local dungeons, zones = {}, {}
    for zone in pairs(seen) do
        table.insert(isDungeon[zone] and dungeons or zones, zone)
    end
    local function SortKey(zone) return (zone:gsub("^The ", "")) end
    local function ByName(a, b) return SortKey(a) < SortKey(b) end
    table.sort(dungeons, ByName)
    table.sort(zones, ByName)
    return dungeons, zones
end

local function RefreshZonesPage()
    local filters = Table("zoneFilter")
    for _, entry in ipairs(zoneChecks) do entry.cb:SetChecked(filters[entry.zone] ~= false) end
end

local function ZoneHeader(text, x)
    local header = Note(zonesPage, text, "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", x, ZONE_TOP_Y + 18)
    header:SetTextColor(unpack(THEME.goldDim))
end

local function AddZoneCheckbox(zone, x, y)
    local cb = CreateFrame("CheckButton", nil, zonesPage, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 1, 1)
    label:SetText(zone)
    cb:SetScript("OnClick", function(self)
        Table("zoneFilter")[zone] = self:GetChecked() and true or false
        Refresh()
    end)
    table.insert(zoneChecks, { cb = cb, zone = zone })
end

local zoneButtons
local function SetAllZones(shown)
    local filters = Table("zoneFilter")
    for _, entry in ipairs(zoneChecks) do filters[entry.zone] = shown end
    RefreshZonesPage()
    Refresh()
end

-- One-time: ticks the places whose level range includes the character's level
-- and unticks the rest, plus the other faction's starting zones and dungeons.
-- Clicking it again after leveling updates the ticks.
local function FilterZonesToCurrentLevel()
    local playerInfo = EverGear:GetPlayerInfo()
    local level = playerInfo.level or 1
    local otherFaction = {}
    for _, zone in ipairs(EverGear.OTHER_FACTION_ZONES[playerInfo.faction or ""] or {}) do
        otherFaction[zone] = true
    end
    local filters = Table("zoneFilter")
    for _, entry in ipairs(zoneChecks) do
        local range = EverGear.ZONE_LEVEL_RANGES[entry.zone]
        local inRange = (not range) or (level >= range[1] and level <= range[2])
        filters[entry.zone] = inRange and not otherFaction[entry.zone]
    end
    RefreshZonesPage()
    Refresh()
end

-- Built on first open (the item data isn't loaded yet when this file runs):
-- one column of dungeons, then the zones in two columns.
local function BuildZonesPage()
    if zoneButtons then return end
    local dungeons, zones = EverGear.CollectSourceZones()
    local left = 16
    ZoneHeader("Dungeons", left + 4)
    for i, zone in ipairs(dungeons) do
        AddZoneCheckbox(zone, left, ZONE_TOP_Y - (i - 1) * ZONE_ROW_HEIGHT)
    end
    local zoneLeft = left + ZONE_DUNGEON_COL_WIDTH
    local perColumn = math.ceil(#zones / 2)
    ZoneHeader("Zones", zoneLeft + 4)
    for i, zone in ipairs(zones) do
        local col = math.floor((i - 1) / perColumn)
        local row = (i - 1) % perColumn
        AddZoneCheckbox(zone, zoneLeft + col * ZONE_ZONE_COL_WIDTH, ZONE_TOP_Y - row * ZONE_ROW_HEIGHT)
    end
    local rows = math.max(#dungeons, perColumn)
    local bottom = ZONE_TOP_Y - rows * ZONE_ROW_HEIGHT

    local note = Note(zonesPage, "Crafted items and world drops from all over aren't tied to one place, so they always show.")
    note:SetPoint("TOPLEFT", left, bottom - 8)
    note:SetPoint("RIGHT", zonesPage, "RIGHT", -16, 0)

    local all = SmallButton(zonesPage, "Show All", 90, function() SetAllZones(true) end)
    all:SetPoint("TOPLEFT", left, bottom - 30)
    local none = SmallButton(zonesPage, "Show None", 90, function() SetAllZones(false) end)
    none:SetPoint("LEFT", all, "RIGHT", 8, 0)
    local current = SmallButton(zonesPage, "Current Level", 110, FilterZonesToCurrentLevel)
    current:SetPoint("LEFT", none, "RIGHT", 8, 0)
    Tooltip(current, "Current Level", "Shows only the zones and dungeons meant for your current level, and hides the "
        .. "other faction's starting zones and dungeons. Click it again after leveling up to update.")
    zoneButtons = { all = all, none = none, current = current }
    pageSizes.zones = { zoneLeft + 2 * ZONE_ZONE_COL_WIDTH + 8, -bottom + 66 }
end

-- ===== Showing, switching and syncing =====

local function ResizeFor(tab)
    local size = pageSizes[tab]
    if size then window:SetSize(math.max(size[1], 3 * 94 + 40), size[2]) end
end

-- Re-applies every saved setting to its checkbox, and resizes for the tab shown.
function EverGear:SyncFiltersWindow()
    RefreshSourcesPage()
    RefreshWeaponsPage()
    if zoneButtons then RefreshZonesPage() end
    ResizeFor(currentTab)
end

function EverGear:SelectFiltersTab(tab)
    if not pages[tab] then return end
    currentTab = tab
    if tab == "zones" then BuildZonesPage() end
    for key, page in pairs(pages) do
        page:SetShown(key == tab)
        local button = tabButtons[key]
        if key == tab then button:LockHighlight() else button:UnlockHighlight() end
    end
    self:SyncFiltersWindow()
end

-- Everything else that opens on the main window's right side closes.
function EverGear:OpenFiltersWindow(tab)
    if self.HideUpgradeDetail then self:HideUpgradeDetail() end
    if EverGearZoneUpgradesPanel then EverGearZoneUpgradesPanel:Hide() end
    window:Show()
    self:SelectFiltersTab(tab or currentTab)
end

function EverGear:ToggleFiltersWindow(tab)
    if window:IsShown() and (not tab or tab == currentTab) then
        window:Hide()
    else
        self:OpenFiltersWindow(tab)
    end
end

-- How many kinds of filter are hiding something right now, and what they are:
-- listed in the Filters button's tooltip.
function EverGear:GetActiveFilterSummary()
    local active = {}
    local sources = Sources()
    for _, key in ipairs({ "quest", "vendor", "craft", "worldDrop", "dungeonDrop", "special", "reputation" }) do
        if sources[key] == false then table.insert(active, "Sources") break end
    end
    if Table("pvpFilter").hidden and active[1] ~= "Sources" then table.insert(active, "Sources") end
    if next(HiddenFactions()) then table.insert(active, "Reputations") end
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do
        if Table("professionFilter")[profName] == false or Table("professionBoEOnly")[profName] then
            table.insert(active, "Professions") break
        end
    end
    local classToken = EverGear:GetPlayerInfo().classToken
    for _, entry in ipairs(weaponEntries) do
        if Table("weaponTypeFilter")[entry.key] == false and EverGear:IsWeaponFilterKeyUsable(entry.key, classToken) then
            table.insert(active, "Weapons") break
        end
    end
    for _, shown in pairs(Table("zoneFilter")) do
        if shown == false then table.insert(active, "Zones") break end
    end
    return #active, active
end

-- ===== The Filters button =====
-- Top of the main window's right edge, where the filter buttons used to be;
-- Upgrades by Zone sits under it (ZoneUpgrades.lua).

local button = CreateFrame("Button", "EverGearFiltersButton", mainFrame)
button:SetSize(20, 20)
button:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, -44)
button:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
button:SetScript("OnClick", function() EverGear:ToggleFiltersWindow() end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Filters")
    GameTooltip:AddLine("Choose which sources, weapon types, zones and dungeons your suggestions come from.",
        0.8, 0.8, 0.8, true)
    local count, active = EverGear:GetActiveFilterSummary()
    if count > 0 then
        GameTooltip:AddLine("Hiding some items by: " .. table.concat(active, ", "), 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)
