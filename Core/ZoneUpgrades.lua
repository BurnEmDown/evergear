-- "Upgrades by Zone": pick a zone or dungeon and see every upgrade it has for
-- this character, across all slots (quest rewards, boss and trash drops,
-- vendors...), best gain first -- instead of checking slot by slot. Opened
-- from the button under the zone filter button, or /eg zone.
--
-- Same rules as Suggested Upgrades (level and look-ahead, class, faction, the
-- source / weapon / profession filters) except the zone filter, since the zone
-- is picked here on purpose (EverGear:GetUpgradesForZone in Upgrades.lua).
-- Opens on the zone the character is in when that zone has items, otherwise
-- on the last one picked.

EverGear = EverGear or {}

local H = EverGear.UIHelpers
local THEME = H.THEME

local PANEL_WIDTH = 330
local ROWS, ROW_HEIGHT = 8, 40
local LIST_TOP, LIST_LEFT, BAR_WIDTH = -74, 16, 8
local ICON = 30

local panel = CreateFrame("Frame", "EverGearZoneUpgradesPanel", EverGear.Frame, "BackdropTemplate")
panel:SetSize(PANEL_WIDTH, -LIST_TOP + ROWS * ROW_HEIGHT + 36)
panel:SetPoint("TOPLEFT", EverGear.Frame, "TOPRIGHT", 8, 0)
panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
panel:EnableMouse(true)
panel:EnableMouseWheel(true)
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -14)
title:SetText("Upgrades by Zone")
title:SetTextColor(unpack(THEME.gold))
local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local zoneDropdown = CreateFrame("Frame", "EverGearZoneUpgradesDropdown", panel, "UIDropDownMenuTemplate")
zoneDropdown:SetPoint("TOP", 0, -30)
UIDropDownMenu_SetWidth(zoneDropdown, 220)

local emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
emptyText:SetPoint("TOPLEFT", LIST_LEFT + 4, LIST_TOP - 6)
emptyText:SetPoint("RIGHT", -20, 0)
emptyText:SetJustifyH("LEFT")
emptyText:SetWordWrap(true)
emptyText:SetTextColor(unpack(THEME.parchment))

local countText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
countText:SetPoint("BOTTOM", 0, 16)

local state = { zone = nil, list = {}, offset = 0 }

-- ===== Scroll bar =====
-- Same look and handling as the Wanted list's: a thin track with a thumb
-- sized to how much of the list is visible, shown only when the list doesn't
-- fit. Drag the thumb, click the track to jump, or use the mouse wheel.
local bar = CreateFrame("Frame", "EverGearZoneUpgradesScrollBar", panel)
bar:SetWidth(BAR_WIDTH)
bar:SetHeight(ROWS * ROW_HEIGHT - 4)
bar:SetPoint("TOPLEFT", LIST_LEFT, LIST_TOP)
local track = bar:CreateTexture(nil, "BACKGROUND")
track:SetAllPoints()
track:SetColorTexture(0, 0, 0, 0.5)
local thumb = CreateFrame("Button", "EverGearZoneUpgradesScrollThumb", bar)
thumb:SetWidth(BAR_WIDTH)
thumb:SetHeight(40)
thumb:SetPoint("TOP", bar, "TOP", 0, 0)
local thumbTexture = thumb:CreateTexture(nil, "OVERLAY")
thumbTexture:SetAllPoints()
thumbTexture:SetColorTexture(THEME.goldDim[1], THEME.goldDim[2], THEME.goldDim[3], 0.9)
thumb:SetHitRectInsets(-4, -4, 0, 0)
thumb:SetScript("OnEnter", function() thumbTexture:SetVertexColor(1.25, 1.25, 1.25) end)
thumb:SetScript("OnLeave", function() thumbTexture:SetVertexColor(1, 1, 1) end)
bar:Hide()

local function MaxOffset() return math.max(0, #state.list - ROWS) end
local function Travel() return math.max(1, (bar:GetHeight() or 0) - thumb:GetHeight()) end
local function CursorY()
    local _, y = GetCursorPosition()
    return y / bar:GetEffectiveScale()
end

local rows = {}
local Draw

local function ScrollTo(offset)
    state.offset = math.max(0, math.min(math.floor(offset + 0.5), MaxOffset()))
    Draw()
end

local dragStartY, dragStartOffset
thumb:SetScript("OnMouseDown", function() dragStartY, dragStartOffset = CursorY(), state.offset end)
thumb:SetScript("OnUpdate", function()
    if not dragStartY then return end
    if not IsMouseButtonDown("LeftButton") then dragStartY = nil return end
    ScrollTo(dragStartOffset + (dragStartY - CursorY()) / Travel() * MaxOffset())
end)
thumb:SetScript("OnMouseUp", function() dragStartY = nil end)
thumb:SetScript("OnHide", function() dragStartY = nil end)
bar:EnableMouse(true)
bar:SetHitRectInsets(-4, -4, 0, 0)
bar:SetScript("OnMouseDown", function()
    local top = bar:GetTop()
    if not top then return end
    ScrollTo(((top - CursorY()) - thumb:GetHeight() / 2) / Travel() * MaxOffset())
end)
bar:EnableMouseWheel(true)
bar:SetScript("OnMouseWheel", function(_, delta) ScrollTo(state.offset - delta * 2) end)
panel:SetScript("OnMouseWheel", function(_, delta) ScrollTo(state.offset - delta * 2) end)

-- ===== Rows =====
-- Like the Suggested Upgrades rows: hover for the item's tooltip, click (left
-- or right) for the wanted list / gear sets menu, Ctrl-click to preview,
-- Shift-click to link it.
for i = 1, ROWS do
    local row = CreateFrame("Button", "EverGearZoneUpgradesRow" .. i, panel)
    row:SetSize(PANEL_WIDTH - LIST_LEFT - BAR_WIDTH - 8 - 20, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", LIST_LEFT + BAR_WIDTH + 8, LIST_TOP - (i - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local icon = H.CreateItemIconFrame(nil, row, ICON)
    icon:SetPoint("LEFT", 0, 0)
    icon:EnableMouse(false)  -- the row handles the mouse
    row.iconFrame = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
    name:SetPoint("RIGHT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    info:SetPoint("RIGHT", 0, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    info:SetTextColor(0.7, 0.7, 0.7)
    row.info = info

    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(H.BuildItemLink(self.entry.item.id))
        GameTooltip:AddLine(EverGear:GetSourceSummary(self.entry.item), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        local itemId = self.entry.item.id
        if IsAltKeyDown() and EverGear.ShowItemMenu then
            EverGear:ShowItemMenu(H.BuildItemLink(itemId))
            return
        end
        if EverGear:HandleItemModifiedClick(itemId) then return end
        if EverGear.ShowStarMenu then EverGear:ShowStarMenu(self, itemId, self.entry.slotToken) end
    end)
    rows[i] = row
end

-- Slot names for rings/trinkets without the 1/2: the gain is for whichever
-- of the two it improves most.
local function SlotLabel(slotToken)
    if slotToken == "Finger0Slot" or slotToken == "Finger1Slot" then return "Ring" end
    if slotToken == "Trinket0Slot" or slotToken == "Trinket1Slot" then return "Trinket" end
    return EverGear.FRIENDLY_SLOT_NAMES[slotToken] or slotToken
end

-- What the source line says beyond the zone, which is already the header:
-- the quest, the boss, or the kind of source.
local function SourceDetail(item)
    local source = item.source or {}
    if source.type == "quest" then
        local quest = source.quest
        if source.questByFaction then
            quest = source.questByFaction[EverGear:GetPlayerInfo().faction or ""] or quest
        end
        return "Quest: " .. (quest or "?")
    end
    if source.boss then return source.boss end
    if source.npc then return source.npc end
    return EverGear:GetSourceSummary(item)
end

Draw = function()
    local list = state.list
    local maxOffset = MaxOffset()
    state.offset = math.max(0, math.min(state.offset, maxOffset))
    for i, row in ipairs(rows) do
        local entry = list[state.offset + i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local item = entry.item
            H.SetIconTexture(row.iconFrame, H.SafeGetItemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local _, _, quality = H.SafeGetItemInfo(item.id)
            local r, g, b = H.GetQualityColor(quality)
            row.iconFrame:SetBackdropBorderColor(r, g, b, 1)
            local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
            row.name:SetText("|cff" .. hex .. item.name .. "|r  |cff20e626(+" .. math.floor(entry.gain + 0.5) .. ")|r")
            row.info:SetText(SlotLabel(entry.slotToken) .. "  -  " .. SourceDetail(item))
        end
    end
    emptyText:SetShown(#list == 0)
    if #list == 0 then
        countText:SetText("")
        emptyText:SetText(state.zone and ("No upgrades from " .. state.zone .. " for you right now.\n\nItems above your look-ahead level and ones your filters hide aren't counted.") or "Pick a zone or dungeon above.")
    else
        countText:SetText(#list .. " upgrade" .. (#list == 1 and "" or "s"))
    end
    bar:SetShown(maxOffset > 0)
    if maxOffset > 0 then
        thumb:SetHeight(math.max(20, (bar:GetHeight() or 0) * ROWS / #list))
        thumb:SetPoint("TOP", bar, "TOP", 0, -(state.offset / maxOffset * Travel()))
    end
end

local function Rebuild(keepOffset)
    state.list = state.zone and EverGear:GetUpgradesForZone(state.zone) or {}
    if not keepOffset then state.offset = 0 end
    UIDropDownMenu_SetText(zoneDropdown, state.zone or "Pick a zone or dungeon")
    Draw()
end

local function SelectZone(zone)
    state.zone = zone
    EverGear:GetCharDB().zoneUpgradesZone = zone
    Rebuild()
    CloseDropDownMenus()
end

-- Zone list: "Dungeons" and "Zones" open sub-lists, each with the level range
-- where one is known, and the character's own zone is offered on top.
UIDropDownMenu_Initialize(zoneDropdown, function(_, level, menuList)
    local dungeons, zones = EverGear.CollectSourceZones()
    level = level or 1
    local function AddZone(zone)
        local info = UIDropDownMenu_CreateInfo()
        local range = EverGear.ZONE_LEVEL_RANGES and EverGear.ZONE_LEVEL_RANGES[zone]
        info.text = range and (zone .. "  |cff999999(" .. range[1] .. "-" .. range[2] .. ")|r") or zone
        info.checked = (zone == state.zone)
        info.func = function() SelectZone(zone) end
        UIDropDownMenu_AddButton(info, level)
    end
    if level == 1 then
        local here = GetRealZoneText and GetRealZoneText()
        local known = {}
        for _, z in ipairs(dungeons) do known[z] = true end
        for _, z in ipairs(zones) do known[z] = true end
        if here and known[here] then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Where you are: " .. here
            info.notCheckable = true
            info.func = function() SelectZone(here) end
            UIDropDownMenu_AddButton(info, level)
        end
        for _, group in ipairs({ { "Dungeons", "dungeons" }, { "Zones", "zones" } }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = group[1]
            info.hasArrow = true
            info.notCheckable = true
            info.menuList = group[2]
            UIDropDownMenu_AddButton(info, level)
        end
    elseif menuList == "dungeons" then
        for _, zone in ipairs(dungeons) do AddZone(zone) end
    elseif menuList == "zones" then
        for _, zone in ipairs(zones) do AddZone(zone) end
    end
end)

function EverGear:RefreshZoneUpgrades()
    if panel:IsShown() then Rebuild(true) end
end

function EverGear:ToggleZoneUpgrades()
    if panel:IsShown() then panel:Hide() return end
    if not EverGear.Frame:IsShown() then EverGear:ToggleUI() end
    local here = GetRealZoneText and GetRealZoneText()
    local dungeons, zones = EverGear.CollectSourceZones()
    local known = {}
    for _, z in ipairs(dungeons) do known[z] = true end
    for _, z in ipairs(zones) do known[z] = true end
    local saved = EverGear:GetCharDB().zoneUpgradesZone
    state.zone = (here and known[here] and here) or (saved and known[saved] and saved) or nil
    panel:Show()
    Rebuild()
end

-- Opening button: under the zone filter button on the main window's right edge.
local openButton = CreateFrame("Button", "EverGearZoneUpgradesButton", EverGear.Frame)
openButton:SetSize(20, 20)
openButton:SetPoint("TOPRIGHT", EverGear.Frame, "TOPRIGHT", -16, -116)
openButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
openButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
openButton:SetScript("OnClick", function() EverGear:ToggleZoneUpgrades() end)
openButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Upgrades by zone")
    GameTooltip:AddLine("Pick a zone or dungeon and see every upgrade it has for you, across all slots.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
openButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
