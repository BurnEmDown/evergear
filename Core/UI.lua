-- UI.lua
-- Paper-doll style window, ported from Leveling Gear Advisor's UI.lua
-- (https://github.com/BurnEmDown/leveling-gear-advisor): item icons positioned
-- like the real character panel, each with a floating badge showing the score
-- gain from the best available upgrade ("+14"), or "BIS" if nothing beats what
-- you have. Clicking a slot opens a detail panel listing the top candidates.
--
-- Deliberately NOT ported from LGA (all depend on data/scoring EverGear doesn't
-- have yet, and would just be dead UI otherwise):
--   - spec dropdown / role-based primary stat (needs real per-class-spec EP data)
--   - profession filter (needs crafted-item source data, which doesn't exist yet)
--   - weapon type filter (needs per-class usable-weapon-subclass data)
--   - look-ahead level slider (built to lean on the same EP/role system)
-- These can be added once EverGear has the underlying data to back them.
--
-- Layout notes (same approach as LGA):
-- - The left column is anchored to the content frame's LEFT edge, and the
--   right column to its RIGHT edge, each with a constant margin - so
--   stretching the window wide visibly pulls the columns apart instead of
--   both drifting toward the middle.
-- - The first row's vertical position is a constant (not scaled), so it can
--   never move up into the filter checkbox row even if the window is
--   shrunk short. Only the SPACING between rows scales with height.

local FRAME_WIDTH = 300
local FRAME_HEIGHT = 560

local LEFT_MARGIN = 24
local RIGHT_MARGIN = 24
local TOP_Y = -10
local ROW_SPACING = 48
local ICON_SIZE = 37
local TOP_INSET = 134   -- title + spec dropdown + filter checkbox row
local BOTTOM_INSET = 12

-- Left column, top to bottom
local leftColumn = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot" }
-- Right column, top to bottom
local rightColumn = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
-- Bottom row, centered
local bottomRow = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

local slotOrder = {}
for _, s in ipairs(leftColumn) do table.insert(slotOrder, s) end
for _, s in ipairs(rightColumn) do table.insert(slotOrder, s) end
for _, s in ipairs(bottomRow) do table.insert(slotOrder, s) end

-- Persisted between sessions (filter choices, window position/size).
EverGearDB.filters = EverGearDB.filters or {}
for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
    if EverGearDB.filters[entry.key] == nil then
        EverGearDB.filters[entry.key] = true
    end
end
local EG_Filters = EverGearDB.filters

-- ===== Frame construction =====

local mainFrame = CreateFrame("Frame", "EverGearFrame", UIParent, "BackdropTemplate")

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local initialWidth = Clamp(EverGearDB.width or FRAME_WIDTH, 280, 460)
local initialHeight = Clamp(EverGearDB.height or FRAME_HEIGHT, 560, 760)
mainFrame:SetSize(initialWidth, initialHeight)

if EverGearDB.point then
    mainFrame:SetPoint("TOPLEFT", UIParent, EverGearDB.relativePoint or "TOPLEFT", EverGearDB.x or 0, EverGearDB.y or 0)
else
    mainFrame:SetPoint("TOPLEFT", UIParent, "CENTER", -(initialWidth / 2), (initialHeight / 2))
end
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")

local function SaveWindowPositionAndSize()
    local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
    EverGearDB.point = point
    EverGearDB.relativePoint = relativePoint
    EverGearDB.x = x
    EverGearDB.y = y
    EverGearDB.width = mainFrame:GetWidth()
    EverGearDB.height = mainFrame:GetHeight()
end

mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindowPositionAndSize()
end)
mainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
mainFrame:Hide()

mainFrame:SetResizable(true)
if mainFrame.SetResizeBounds then
    mainFrame:SetResizeBounds(280, 560, 460, 760)
else
    mainFrame:SetMinResize(280, 560)
    mainFrame:SetMaxResize(460, 760)
end

local resizeHandle = CreateFrame("Button", nil, mainFrame)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", -6, 6)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeHandle:SetScript("OnMouseDown", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
resizeHandle:SetScript("OnMouseUp", function()
    mainFrame:StopMovingOrSizing()
    SaveWindowPositionAndSize()
end)

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -16)
title:SetText("EverGear")

local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -4, -4)

-- ===== Spec dropdown =====
-- Shows the real specs for the player's class (e.g. Arms/Fury/Protection for
-- a Warrior); each maps to one of the 4 scoring roles Upgrades.lua understands
-- (see EverGear.CLASS_SPECS in Upgrades.lua). This heavily affects
-- suggestions since it picks which stats the scoring heuristic weights.
EverGearDB.spec = EverGearDB.spec or EverGear:GetDefaultSpec(EverGear:GetPlayerInfo().classToken)

local specDropdown = CreateFrame("Frame", "EverGearSpecDropdown", mainFrame, "UIDropDownMenuTemplate")
specDropdown:SetPoint("TOP", mainFrame, "TOP", -8, -34)
UIDropDownMenu_SetWidth(specDropdown, 150)

local function SpecDropdown_OnClick(self)
    EverGearDB.spec = self.value
    UIDropDownMenu_SetSelectedValue(specDropdown, self.value)
    EverGear:RefreshUI()
end

UIDropDownMenu_Initialize(specDropdown, function()
    local specs = EverGear.CLASS_SPECS[EverGear:GetPlayerInfo().classToken] or {}
    for _, spec in ipairs(specs) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = spec.name
        info.value = spec.name
        info.func = SpecDropdown_OnClick
        UIDropDownMenu_AddButton(info)
    end
end)
UIDropDownMenu_SetSelectedValue(specDropdown, EverGearDB.spec)

-- ===== Source-type filter checkboxes =====
-- One checkbox per entry in EverGear.SOURCE_TYPE_FILTERS (Constants.lua) --
-- add a row there, not here, when a new source type shows up in the data.

local filterCheckboxes = {}

local function CreateFilterCheckbox(name, label, key)
    local cb = CreateFrame("CheckButton", name, mainFrame, "UICheckButtonTemplate")
    cb:SetChecked(EG_Filters[key])
    _G[name .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self)
        EG_Filters[key] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(filterCheckboxes, cb)
    return cb
end

for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
    CreateFilterCheckbox("EverGearFilter_" .. entry.key, entry.label, entry.key)
end

-- Filter layout: centered, collapses from a 3-column grid into a single row
-- once the window is wide enough to fit one. Recalculated on every resize.
local FILTER_SLOT_WIDTH = 92
local FILTER_ROW_GAP = 26
local FILTER_SINGLE_ROW_MIN_WIDTH = 92 * #filterCheckboxes + 40
local FILTER_TOP_Y = -70
local FILTER_WRAP_COLUMNS = 3

local function RepositionFilters()
    local width = mainFrame:GetWidth()

    if width >= FILTER_SINGLE_ROW_MIN_WIDTH then
        local totalWidth = #filterCheckboxes * FILTER_SLOT_WIDTH
        local startX = (width - totalWidth) / 2
        for i, cb in ipairs(filterCheckboxes) do
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + (i - 1) * FILTER_SLOT_WIDTH, FILTER_TOP_Y)
        end
    else
        local columns = math.min(FILTER_WRAP_COLUMNS, #filterCheckboxes)
        local totalWidth = columns * FILTER_SLOT_WIDTH
        local startX = (width - totalWidth) / 2
        for i, cb in ipairs(filterCheckboxes) do
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            cb:ClearAllPoints()
            cb:SetPoint(
                "TOPLEFT", mainFrame, "TOPLEFT",
                startX + col * FILTER_SLOT_WIDTH, FILTER_TOP_Y - row * FILTER_ROW_GAP
            )
        end
    end
end

mainFrame:SetScript("OnSizeChanged", RepositionFilters)
RepositionFilters()

-- Content frame: everything below the filter row.
local content = CreateFrame("Frame", nil, mainFrame)
content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -TOP_INSET)
content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, BOTTOM_INSET)

-- ===== Slot buttons =====

local slotButtons = {}
local leftItems, rightItems, bottomItems = {}, {}, {}

-- Hand-built item-icon button instead of Blizzard's "ItemButtonTemplate" XML
-- template -- that template doesn't exist in every client build (confirmed
-- missing in the WoW Forever beta client), so this only relies on a plain
-- Button frame plus a couple of textures/paths that have existed since
-- Vanilla and are extremely unlikely to ever be removed.
local function CreateItemIconFrame(name, parent, size)
    -- Border is a plain 1px backdrop edge, not a texture -- "UI-Quickslot2"
    -- (the first attempt) has most of its art as transparent padding around a
    -- small ring, so scaling it to exactly the icon's bounds made the visible
    -- ring render tiny and centered instead of framing the edge. A backdrop
    -- edge sits at the true edge regardless of icon size.
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trims the icon's own built-in border padding
    btn.icon = icon

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    return btn
end

-- Sets an item-icon frame's texture (icon-only; the surrounding border/
-- highlight textures are created once in CreateItemIconFrame and never change).
local function SetIconTexture(iconFrame, texturePath)
    iconFrame.icon:SetTexture(texturePath)
end

local function CreateSlotButton(slotToken)
    local btn = CreateItemIconFrame("EverGearSlotButton_" .. slotToken, content, ICON_SIZE)
    btn.slotToken = slotToken

    local badge = btn:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    badge:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.badge = badge

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.currentLink then
            GameTooltip:SetHyperlink(self.currentLink)
        else
            GameTooltip:SetText((EverGear.FRIENDLY_SLOT_NAMES[self.slotToken] or self.slotToken) .. " (empty)")
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        EverGear:ShowUpgradeDetail(self.slotToken)
    end)

    slotButtons[slotToken] = btn
    return btn
end

for i, slotToken in ipairs(leftColumn) do
    local btn = CreateSlotButton(slotToken)
    btn.side = "left"
    table.insert(leftItems, { frame = btn, row = i })
end

for i, slotToken in ipairs(rightColumn) do
    local btn = CreateSlotButton(slotToken)
    btn.side = "right"
    table.insert(rightItems, { frame = btn, row = i })
end

for i, slotToken in ipairs(bottomRow) do
    local btn = CreateSlotButton(slotToken)
    btn.side = "right"
    table.insert(bottomItems, { frame = btn, index = i })
end

local function RepositionAll()
    local h = content:GetHeight()
    local w = content:GetWidth()
    if h <= 0 or w <= 0 then return end

    local scaleY = h / (FRAME_HEIGHT - TOP_INSET - BOTTOM_INSET)

    for _, item in ipairs(leftItems) do
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN, TOP_Y - (item.row - 1) * ROW_SPACING * scaleY)
    end

    for _, item in ipairs(rightItems) do
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -RIGHT_MARGIN, TOP_Y - (item.row - 1) * ROW_SPACING * scaleY)
    end

    local bottomRowY = TOP_Y - (#rightColumn) * ROW_SPACING * scaleY
    local bottomTotalWidth = #bottomItems * (ICON_SIZE + 10)
    local bottomStartX = (w - bottomTotalWidth) / 2

    for _, item in ipairs(bottomItems) do
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", content, "TOPLEFT", bottomStartX + (item.index - 1) * (ICON_SIZE + 10), bottomRowY)
    end
end

content:SetScript("OnSizeChanged", RepositionAll)
RepositionAll()

mainFrame:SetScript("OnShow", function()
    RepositionFilters()
    RepositionAll()
end)

-- ===== Detail panel =====
-- Opens to the left or right of the main window (whichever side has room),
-- listing the top candidates for the clicked slot: real item icon (hoverable
-- for its actual tooltip), name, source, and score gain over what's equipped.

local DETAIL_WIDTH = 220
local DETAIL_ROW_HEIGHT = 46
local MAX_DETAIL_CANDIDATES = 5

local detailPanel = CreateFrame("Frame", "EverGearDetailPanel", mainFrame, "BackdropTemplate")
detailPanel:SetSize(DETAIL_WIDTH, 150)
detailPanel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
detailPanel:Hide()

local detailCloseButton = CreateFrame("Button", nil, detailPanel, "UIPanelCloseButton")
detailCloseButton:SetPoint("TOPRIGHT", -2, -2)

local detailHeader = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailHeader:SetPoint("TOP", 0, -14)
detailHeader:SetText("Suggested Upgrades")

local detailEmptyMessage = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailEmptyMessage:SetPoint("TOPLEFT", 16, -40)
detailEmptyMessage:SetPoint("RIGHT", -12, 0)
detailEmptyMessage:SetJustifyH("LEFT")
detailEmptyMessage:SetWordWrap(true)
detailEmptyMessage:Hide()

local detailRows = {}

local function GetOrCreateDetailRow(index)
    if detailRows[index] then return detailRows[index] end

    local row = CreateFrame("Frame", nil, detailPanel)
    row:SetSize(DETAIL_WIDTH - 32, DETAIL_ROW_HEIGHT)

    local icon = CreateItemIconFrame(nil, row, ICON_SIZE)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.icon = icon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    nameText:SetPoint("RIGHT", 0, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    row.nameText = nameText

    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    sourceText:SetPoint("RIGHT", 0, 0)
    sourceText:SetJustifyH("LEFT")
    sourceText:SetWordWrap(true)
    sourceText:SetTextColor(0.7, 0.7, 0.7)
    row.sourceText = sourceText

    detailRows[index] = row
    return row
end

local function BuildItemLink(itemID)
    return "item:" .. itemID .. ":0:0:0:0:0:0:0:0:0:0:0"
end

-- This client build doesn't expose the old bare GetItemInfo/GetItemIcon
-- globals (confirmed via a live "attempt to call a nil value" error) --
-- it's on the modern C_Item namespace instead. These wrappers try C_Item
-- first and fall back to the old globals in case a future build restores them.
local function SafeGetItemInfo(itemId)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemId)
    end
    if GetItemInfo then
        return GetItemInfo(itemId)
    end
    return nil
end

local function SafeGetItemIcon(itemId)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemId)
    end
    if C_Item and C_Item.GetItemIcon then
        return C_Item.GetItemIcon(itemId)
    end
    if GetItemIcon then
        return GetItemIcon(itemId)
    end
    return nil
end

function EverGear:ShowUpgradeDetail(slotToken)
    local btn = slotButtons[slotToken]
    if not btn then return end

    local candidates = btn.upgradeList or {}
    local shownCount = math.min(#candidates, MAX_DETAIL_CANDIDATES)

    if shownCount == 0 then
        detailEmptyMessage:Show()
        for _, row in ipairs(detailRows) do row:Hide() end

        if btn.isBIS then
            detailEmptyMessage:SetText("This is your best-in-slot item!\n\nNo known upgrade for your current level.")
        else
            detailEmptyMessage:SetText("No upgrade shown.\n\nAn upgrade may exist but is hidden by your source-type filters.")
        end

        detailPanel:SetHeight(150)
    else
        detailEmptyMessage:Hide()

        local ROW_GAP = 16
        local yOffset = -40

        for i = 1, shownCount do
            local candidate = candidates[i]
            local row = GetOrCreateDetailRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, yOffset)
            row:Show()

            local itemLink = BuildItemLink(candidate.item.id)
            SetIconTexture(row.icon, SafeGetItemIcon(candidate.item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon.itemLink = itemLink

            local delta = math.floor((candidate.score - (btn.currentScore or 0)) + 0.5)
            row.nameText:SetText(candidate.item.name .. "  |cff00ff00(+" .. delta .. ")|r")
            row.sourceText:SetText(EverGear:GetSourceSummary(candidate.item))

            local textHeight = row.nameText:GetStringHeight() + 4 + row.sourceText:GetStringHeight()
            local rowHeight = math.max(ICON_SIZE, textHeight)
            yOffset = yOffset - rowHeight - ROW_GAP
        end

        for i = shownCount + 1, #detailRows do
            detailRows[i]:Hide()
        end

        detailPanel:SetHeight(-yOffset + 16)
    end

    detailPanel:ClearAllPoints()
    if btn.side == "left" then
        detailPanel:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -8, 0)
    else
        detailPanel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0)
    end
    detailPanel:Show()
end

-- ===== Refresh / toggle =====

function EverGear:RefreshUI()
    detailPanel:Hide()

    local gear = self:GetCurrentGear()

    for _, slotToken in ipairs(slotOrder) do
        local btn = slotButtons[slotToken]
        local itemLink = gear[slotToken]

        local candidates, currentScore = self:GetUpgradesForSlot(slotToken, itemLink)

        local filtered = {}
        for _, candidate in ipairs(candidates) do
            local sourceType = candidate.item.source and candidate.item.source.type
            if EG_Filters[sourceType] ~= false then
                table.insert(filtered, candidate)
            end
        end

        if itemLink then
            local _, _, _, _, _, _, _, _, _, itemTexture = SafeGetItemInfo(itemLink)
            SetIconTexture(btn, itemTexture or SafeGetItemIcon(itemLink) or EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn.currentLink = itemLink
        else
            SetIconTexture(btn, EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn.currentLink = nil
        end

        btn.currentScore = currentScore
        btn.upgradeList = filtered

        if #candidates == 0 then
            btn.badge:SetText("BIS")
            btn.badge:SetTextColor(1, 0.82, 0)
            btn.isBIS = true
        elseif #filtered == 0 then
            btn.badge:SetText("--")
            btn.badge:SetTextColor(0.6, 0.6, 0.6)
            btn.isBIS = false
        else
            local best = filtered[1]
            local delta = math.floor((best.score - currentScore) + 0.5)
            btn.badge:SetText("+" .. delta)
            btn.badge:SetTextColor(0.1, 1, 0.1)
            btn.isBIS = false
        end
    end
end

EverGear.Frame = mainFrame

function EverGear:ToggleUI()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:RefreshUI()
        mainFrame:Show()
    end
end

SLASH_EVERGEAR1 = "/evergear"
SLASH_EVERGEAR2 = "/eg"
SlashCmdList["EVERGEAR"] = function()
    EverGear:ToggleUI()
end
