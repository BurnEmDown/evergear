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

local FRAME_WIDTH = 334
-- +34 over the original 560 to give the new look-ahead row its own space
-- without squeezing the bottom weapon row's margin.
local FRAME_HEIGHT = 594

local LEFT_MARGIN = 24
local RIGHT_MARGIN = 24
local TOP_Y = -10
-- Real PaperDollFrame slots sit almost flush against each other (~4px gap
-- between 37px icons); the old 48px pitch read as a loose, spread-out list
-- instead of the tight column the character screen has.
local ROW_SPACING = 42
local ICON_SIZE = 37
local TOP_INSET = 168   -- title + spec dropdown + look-ahead row + filter checkbox rows
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

-- ===== Theme =====
-- One shared palette so the gold/bronze fantasy look reads as one system
-- instead of every panel picking its own ad-hoc colors. R/G/B triples
-- (0-1 range, matching every WoW color API) unless noted otherwise.
local THEME = {
    gold        = { 1.00, 0.82, 0.20 },  -- headers, accents
    goldDim     = { 0.78, 0.63, 0.24 },  -- secondary/label text
    parchment   = { 0.90, 0.85, 0.72 },  -- body text on dark backgrounds
    panelBg     = { 0.05, 0.05, 0.07, 0.85 },  -- recessed inset panels
    panelBorder = { 0.55, 0.45, 0.20, 1.0 },
    -- Status colors used on both the slot-button ring and its badge pill --
    -- an actual upgrade is available, this slot is already best-in-slot, or
    -- there's nothing to show (no upgrade, or filtered out).
    statusUpgrade = { 0.20, 0.90, 0.25 },
    statusBIS     = { 1.00, 0.82, 0.20 },
    statusNone    = { 0.45, 0.42, 0.38 },
}

-- Standard WoW item-quality colors (Poor..Legendary), keyed by the quality
-- index GetItemInfo()/C_Item.GetItemInfo() returns as their 3rd value.
-- Blizzard exposes this as a live API (GetItemQualityColor /
-- C_Item.GetItemQualityColor) but that call can be unavailable on some
-- client builds -- this addon has already hit a couple of missing-API
-- surprises on the WoW Forever beta client (see CreateItemIconFrame's and
-- SafeGetItemInfo's comments), so a small hardcoded fallback table (these
-- values never change patch to patch) is safer than relying on it outright.
local QUALITY_COLORS = {
    [0] = { 0.61, 0.61, 0.61 },  -- Poor
    [1] = { 1.00, 1.00, 1.00 },  -- Common
    [2] = { 0.12, 1.00, 0.00 },  -- Uncommon
    [3] = { 0.00, 0.44, 0.87 },  -- Rare
    [4] = { 0.64, 0.21, 0.93 },  -- Epic
    [5] = { 1.00, 0.50, 0.00 },  -- Legendary
}

local function GetQualityColor(quality)
    local c = quality and QUALITY_COLORS[quality]
    if c then return c[1], c[2], c[3] end
    return THEME.goldDim[1], THEME.goldDim[2], THEME.goldDim[3]
end

-- Persisted between sessions (filter choices, window position/size).
--
-- IMPORTANT: this client build has already shown SavedVariables fields
-- coming back nil later despite being set once at file-load time (see
-- UI.lua's look-ahead slider notes) -- the working theory is EverGearDB
-- itself (or a nested table on it) can end up getting swapped for a
-- different table object sometime after this file's top-level code runs,
-- which would silently orphan any `local x = EverGearDB.someTable` alias
-- captured at that early point: click handlers would go on writing into the
-- orphaned table forever while every fresh `EverGearDB.someTable` read
-- elsewhere (Upgrades.lua's filtering, in particular) sees a table that was
-- never actually updated. A checkbox would then show as unchecked/updated
-- in the UI while doing nothing at all to what's suggested. So none of the
-- three filter tables below are captured as a plain local alias -- each is
-- fetched fresh through a small Get*Filters() function on every single read
-- and write, the same "never trust a one-time init" rule the look-ahead
-- slider already follows.
local function GetSourceFilters()
    EverGearDB.filters = EverGearDB.filters or {}
    for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
        if EverGearDB.filters[entry.key] == nil then
            EverGearDB.filters[entry.key] = true
        end
    end
    return EverGearDB.filters
end
GetSourceFilters()  -- seed defaults now so they're set even before any checkbox is touched

-- ===== Frame construction =====

local mainFrame = CreateFrame("Frame", "EverGearFrame", UIParent, "BackdropTemplate")

-- Fixed size -- the window is no longer user-resizable, so there's nothing
-- to clamp or persist beyond its screen position.
mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)

if EverGearDB.point then
    mainFrame:SetPoint("TOPLEFT", UIParent, EverGearDB.relativePoint or "TOPLEFT", EverGearDB.x or 0, EverGearDB.y or 0)
else
    mainFrame:SetPoint("TOPLEFT", UIParent, "CENTER", -(FRAME_WIDTH / 2), (FRAME_HEIGHT / 2))
end
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")

local function SaveWindowPosition()
    local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
    EverGearDB.point = point
    EverGearDB.relativePoint = relativePoint
    EverGearDB.x = x
    EverGearDB.y = y
end

mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveWindowPosition()
end)
mainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
mainFrame:Hide()
mainFrame:SetResizable(false)

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -16)
title:SetText("EverGear")
title:SetTextColor(unpack(THEME.gold))

-- Addon's own icon (Icon.tga, see MinimapButton.lua for the same texture)
-- beside the title instead of a bare text label -- kept to the title's left
-- at the same vertical position (rather than stacked above it) so it adds
-- branding without pushing every control below it further down.
local titleIcon = mainFrame:CreateTexture(nil, "ARTWORK")
titleIcon:SetSize(18, 18)
titleIcon:SetPoint("RIGHT", title, "LEFT", -6, 0)
titleIcon:SetTexture("Interface\\AddOns\\EverGear\\Icon")

local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -4, -4)

-- Small version stamp, bottom-left of the window -- see Constants.lua's
-- EverGear.VERSION for the bump policy (every shipped change bumps the
-- patch digit; only the user decides when to move to 0.1.0/1.0.0).
local versionText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
versionText:SetPoint("BOTTOMLEFT", 10, 6)
versionText:SetText("v" .. EverGear.VERSION)
versionText:SetTextColor(unpack(THEME.goldDim))

-- Recessed panel behind the spec dropdown / look-ahead slider / filter
-- checkboxes -- created before any of those (so it stays visually behind
-- them as a plain child-draw-order backdrop, no explicit frame level
-- juggling needed), giving the "controls" area its own visual boundary
-- distinct from both the outer dialog frame and the paperdoll panel below
-- it (matching the `content` panel's look), instead of every control
-- floating directly on the plain tan dialog background.
local controlsPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
controlsPanel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -38)
controlsPanel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -38)
controlsPanel:SetPoint("BOTTOM", mainFrame, "TOP", 0, -(TOP_INSET - 4))
controlsPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
controlsPanel:SetBackdropColor(unpack(THEME.panelBg))
controlsPanel:SetBackdropBorderColor(unpack(THEME.panelBorder))

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

-- ===== Look-ahead slider =====
-- Lets the player preview upgrades above their current level (e.g. "what
-- should I be aiming for in 10 levels"), without needing the full EP/role
-- system the old LGA look-ahead slider leaned on -- this just widens the
-- minLevel filter in GetUpgradesForSlot up to the chosen level. The stored
-- value (EverGearDB.lookaheadLevel) is an ABSOLUTE target level, not a delta,
-- because the slider's own minimum has to track the player's current level
-- (it rises as they level up) and a delta would drift out of sync with that.
-- Capped at 30 for now since that's roughly as far as the converted dungeon
-- data currently goes; raise LOOKAHEAD_MAX once higher-level zones are added.
local LOOKAHEAD_MAX = 30

-- Every read/write below re-defaults defensively (via GetLookaheadMin() and
-- "or" fallbacks) rather than trusting a one-time init -- in-game testing
-- showed EverGearDB fields can still be nil the first time a handler fires
-- in this client, so nothing here assumes a prior assignment stuck.
local function GetLookaheadMin()
    return EverGear:GetPlayerInfo().level or 1
end

local lookaheadRow = CreateFrame("Frame", nil, mainFrame)
lookaheadRow:SetSize(200, 34)
lookaheadRow:SetPoint("TOP", mainFrame, "TOP", 0, -60)

local lookaheadLabel = lookaheadRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
lookaheadLabel:SetPoint("TOP", lookaheadRow, "TOP", 0, 0)
lookaheadLabel:SetText("Current Level")
lookaheadLabel:SetTextColor(unpack(THEME.goldDim))

-- Reset button sits to the slider's left; shifting the slider right by half
-- the button's own footprint (button width + gap) keeps the [button][slider]
-- pair centered under the label as one group, rather than off-center.
local RESET_BUTTON_SIZE = 16
local RESET_BUTTON_GAP = 6
local sliderXOffset = (RESET_BUTTON_SIZE + RESET_BUTTON_GAP) / 2

local lookaheadSlider = CreateFrame("Slider", "EverGearLookaheadSlider", lookaheadRow, "BackdropTemplate")
lookaheadSlider:SetOrientation("HORIZONTAL")
lookaheadSlider:SetSize(170, 14)
lookaheadSlider:SetPoint("TOP", lookaheadLabel, "BOTTOM", sliderXOffset, -6)
lookaheadSlider:SetHitRectInsets(0, 0, -6, -6)
lookaheadSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
lookaheadSlider:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
lookaheadSlider:SetBackdropColor(0.06, 0.06, 0.08, 1)
lookaheadSlider:SetBackdropBorderColor(0.6, 0.56, 0.42, 1)
lookaheadSlider:SetValueStep(1)
if lookaheadSlider.SetObeyStepOnDrag then
    lookaheadSlider:SetObeyStepOnDrag(true)
end

-- Resets the slider back to the player's current level (its minimum).
-- SetValue below fires OnValueChanged, which does the actual write + refresh,
-- so this button doesn't need its own copy of that logic.
local lookaheadResetButton = CreateFrame("Button", nil, lookaheadRow)
lookaheadResetButton:SetSize(RESET_BUTTON_SIZE, RESET_BUTTON_SIZE)
lookaheadResetButton:SetPoint("RIGHT", lookaheadSlider, "LEFT", -RESET_BUTTON_GAP, 0)
lookaheadResetButton:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
lookaheadResetButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
lookaheadResetButton:SetScript("OnClick", function()
    lookaheadSlider:SetValue(GetLookaheadMin())
end)
lookaheadResetButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset to current level")
    GameTooltip:Show()
end)
lookaheadResetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Suppresses the OnValueChanged->RefreshUI round trip while we're the ones
-- moving the slider programmatically (bounds sync on show/level-up), so it
-- only fires RefreshUI in response to an actual player drag or the reset
-- button, not every automatic bounds sync.
local syncingSlider = false

-- Shows a plain "Current Level" label when the slider is at its minimum
-- (nothing being looked ahead to), and the level number only once it's
-- actually been moved past that.
local function UpdateLookaheadLabel(value)
    if value <= GetLookaheadMin() then
        lookaheadLabel:SetText("Current Level")
    else
        lookaheadLabel:SetText("Look Ahead: Lvl " .. tostring(value))
    end
end

-- Recomputes the slider's min (current player level) and re-clamps the
-- stored target level into [min, LOOKAHEAD_MAX] -- called on window show and
-- after every refresh so leveling up during a session doesn't leave the
-- slider's range stale.
local function SyncLookaheadBounds()
    local minLevel = GetLookaheadMin()
    local maxLevel = math.max(minLevel, LOOKAHEAD_MAX)
    local stored = EverGearDB.lookaheadLevel or minLevel
    stored = math.max(minLevel, math.min(maxLevel, stored))
    EverGearDB.lookaheadLevel = stored

    syncingSlider = true
    lookaheadSlider:SetMinMaxValues(minLevel, maxLevel)
    lookaheadSlider:SetValue(stored)
    syncingSlider = false
    UpdateLookaheadLabel(stored)
end

lookaheadSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    UpdateLookaheadLabel(value)
    if syncingSlider then return end
    EverGearDB.lookaheadLevel = value
    EverGear:RefreshUI()
end)

SyncLookaheadBounds()

-- ===== Source-type filter checkboxes =====
-- One checkbox per entry in EverGear.SOURCE_TYPE_FILTERS (Constants.lua) --
-- add a row there, not here, when a new source type shows up in the data.

local filterCheckboxes = {}

-- Forward-declared: the weapon-type filter panel is built further down (after
-- the detail panel it needs to hide/be hidden by), but ShowUpgradeDetail
-- below needs to be able to close it, and Lua locals are resolved lexically
-- -- so the name has to exist up here even though its value isn't set until
-- later.
local weaponFilterPanel
local professionFilterPanel

local function CreateFilterCheckbox(name, label, key)
    local cb = CreateFrame("CheckButton", name, mainFrame, "UICheckButtonTemplate")
    cb:SetChecked(GetSourceFilters()[key])
    local labelText = _G[name .. "Text"]
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.parchment))
    cb:SetScript("OnClick", function(self)
        GetSourceFilters()[key] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(filterCheckboxes, cb)
    return cb
end

for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
    CreateFilterCheckbox("EverGearFilter_" .. entry.key, entry.label, entry.key)
end

-- Filter layout: two fixed centered rows. Row 1 is Quest/Vendor/Craft (the
-- first 3 entries in SOURCE_TYPE_FILTERS), row 2 is World Drop/Dungeon Drop
-- (the last 2) -- each row centers independently rather than sharing one
-- grid, since row 2 only has 2 items. The window no longer resizes, so this
-- doesn't need to be recalculated dynamically, but it's still driven off
-- mainFrame's actual width rather than a hardcoded number.
local FILTER_SLOT_WIDTH = 92
local FILTER_ROW_GAP = 26
local FILTER_TOP_Y = -104   -- shifted down to clear the look-ahead label+slider row
local FILTER_ROW_1_COUNT = 3

local function RepositionFilters()
    local width = mainFrame:GetWidth()

    local function centerRow(checkboxes, y)
        local totalWidth = #checkboxes * FILTER_SLOT_WIDTH
        local startX = (width - totalWidth) / 2
        for i, cb in ipairs(checkboxes) do
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + (i - 1) * FILTER_SLOT_WIDTH, y)
        end
    end

    local row1, row2 = {}, {}
    for i, cb in ipairs(filterCheckboxes) do
        table.insert(i <= FILTER_ROW_1_COUNT and row1 or row2, cb)
    end

    centerRow(row1, FILTER_TOP_Y)
    centerRow(row2, FILTER_TOP_Y - FILTER_ROW_GAP)
end

RepositionFilters()

-- Content frame: everything below the filter row.
-- A recessed panel (dark fill + thin gold edge) instead of a bare
-- transparent frame -- gives the paperdoll area its own visual boundary
-- instead of everything floating directly on the outer dialog backdrop.
local content = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, -TOP_INSET)
content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -6, BOTTOM_INSET)
content:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
content:SetBackdropColor(unpack(THEME.panelBg))
content:SetBackdropBorderColor(unpack(THEME.panelBorder))

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
    --
    -- The edge is a light gold-grey (matching the real PaperDollFrame's slot
    -- borders) with a solid dark fill behind the icon, not just a black edge
    -- with nothing behind it -- against this window's dark backdrop a black
    -- border on a mostly-transparent square was nearly invisible for any slot
    -- showing one of the muted EMPTY_SLOT_TEXTURES placeholders, so an empty
    -- slot effectively vanished and only its floating badge number stood out.
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 1)
    btn:SetBackdropBorderColor(0.6, 0.56, 0.42, 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
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

    -- Bottom-right corner, like Blizzard's own item-count/durability overlays --
    -- dead-centering it on the icon (the old approach) covered the item art
    -- itself, which is the opposite of the clean look the real character
    -- panel has (an icon you can actually see, with any overlay tucked into
    -- a corner). A small rounded-looking pill behind the number (rather than
    -- bare outlined text floating over the icon art) so the status reads at
    -- a glance without needing to squint at faint outline-font digits over a
    -- busy item icon -- same status color drives both the pill and the
    -- slot's own border, so "this is an upgrade" is legible even before
    -- reading the number.
    local badgeBG = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    badgeBG:SetSize(24, 13)
    badgeBG:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    badgeBG:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    badgeBG:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
    btn.badgeBG = badgeBG

    local badge = badgeBG:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    badge:SetPoint("CENTER", badgeBG, "CENTER", 0, 0)
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
    SyncLookaheadBounds()
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
detailHeader:SetTextColor(unpack(THEME.gold))

local detailHeaderDivider = detailPanel:CreateTexture(nil, "ARTWORK")
detailHeaderDivider:SetHeight(1)
detailHeaderDivider:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 14, -30)
detailHeaderDivider:SetPoint("TOPRIGHT", detailPanel, "TOPRIGHT", -14, -30)
detailHeaderDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
detailHeaderDivider:SetVertexColor(unpack(THEME.panelBorder))

local detailEmptyMessage = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
detailEmptyMessage:SetPoint("TOPLEFT", 16, -40)
detailEmptyMessage:SetPoint("RIGHT", -12, 0)
detailEmptyMessage:SetJustifyH("LEFT")
detailEmptyMessage:SetWordWrap(true)
detailEmptyMessage:SetTextColor(unpack(THEME.parchment))
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

    if weaponFilterPanel then weaponFilterPanel:Hide() end
    if professionFilterPanel then professionFilterPanel:Hide() end

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

            -- Quality-colored name + icon border (a live lookup -- our own
            -- item DB doesn't carry rarity, but the client's item cache
            -- does for any real item id/link). Falls back to the theme's
            -- neutral gold-grey when the client hasn't cached this item yet
            -- (a common cold-cache miss for anything not recently seen),
            -- rather than leaving it uncolored.
            local _, _, quality = SafeGetItemInfo(itemLink)
            local qr, qg, qb = GetQualityColor(quality)
            row.icon:SetBackdropBorderColor(qr, qg, qb, 1)

            local delta = math.floor((candidate.score - (btn.currentScore or 0)) + 0.5)
            local nameHex = string.format("%02x%02x%02x", qr * 255, qg * 255, qb * 255)
            row.nameText:SetText("|cff" .. nameHex .. candidate.item.name .. "|r  |cff20e626(+" .. delta .. ")|r")
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

-- ===== Weapon-type filter panel =====
-- One flat checklist, one row per weapon type -- for the few types the data
-- can tell 1H from 2H apart on (Axe/Mace/Sword; see Constants.lua's
-- SPLIT_WEAPON_TYPES), that's two rows ("Axe (1H)" / "Axe (2H)") instead of a
-- separate standalone "two-handed" toggle bolted on beside the list, so a
-- Protection Warrior can uncheck just "Mace (2H)" and leave everything else
-- (including 1H maces and shields) alone. Only weapon types the player's
-- class can actually use get a row at all (via CLASS_USABLE_WEAPON_TYPES/
-- CLASS_CAN_USE_SHIELD, exposed from Upgrades.lua), so e.g. a Mage never
-- sees an "Axe" row either way. Everything shown by default; unchecking a
-- row is what hides it (same "checked = shown" convention as the source-type
-- filters above).
-- See GetSourceFilters() above for why this is a function, not a captured
-- local alias -- every read/write below goes through it fresh.
local function GetWeaponFilters()
    EverGearDB.weaponTypeFilter = EverGearDB.weaponTypeFilter or {}
    return EverGearDB.weaponTypeFilter
end

-- Built once at load (class doesn't change mid-session): the ordered list of
-- {key, label} rows the checklist and the "All"/"None"/"Usable Only" buttons
-- operate over. Every weapon type gets a row for every class now -- WoW
-- Forever doesn't gate weapon usability as strictly as real vanilla/TBC did,
-- so a class that "shouldn't" have a type per the addon's own
-- CLASS_USABLE_WEAPON_TYPES table can still end up needing it filterable.
-- What DOES still depend on class is each row's INITIAL checked state (see
-- the seeding loop below) and the "Usable Only" button.
local weaponFilterEntries = {}
for _, entry in ipairs(EverGear.WEAPON_TYPE_FILTER_LIST) do
    if EverGear.SPLIT_WEAPON_TYPES[entry.key] then
        table.insert(weaponFilterEntries, { key = entry.key .. ":1h", label = entry.label .. " (1H)" })
        table.insert(weaponFilterEntries, { key = entry.key .. ":2h", label = entry.label .. " (2H)" })
    else
        table.insert(weaponFilterEntries, { key = entry.key, label = entry.label })
    end
end

-- Seed each row's default checked state from class usability -- e.g. a
-- Paladin starts with every ranged weapon type already unchecked -- but only
-- the first time a key is ever seen (nil in the saved table). This never
-- overwrites a choice the player already made, including a previous click
-- of "Usable Only" below.
do
    local classToken = EverGear:GetPlayerInfo().classToken
    local filters = GetWeaponFilters()
    for _, entry in ipairs(weaponFilterEntries) do
        if filters[entry.key] == nil then
            filters[entry.key] = EverGear:IsWeaponFilterKeyUsable(entry.key, classToken)
        end
    end
end

local WEAPON_PANEL_WIDTH = 220
local WEAPON_COLS = 2
local WEAPON_COL_WIDTH = WEAPON_PANEL_WIDTH / WEAPON_COLS
local WEAPON_ROW_HEIGHT = 22

weaponFilterPanel = CreateFrame("Frame", "EverGearWeaponFilterPanel", mainFrame, "BackdropTemplate")
weaponFilterPanel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
weaponFilterPanel:Hide()

local weaponFilterCloseButton = CreateFrame("Button", nil, weaponFilterPanel, "UIPanelCloseButton")
weaponFilterCloseButton:SetPoint("TOPRIGHT", -2, -2)

local weaponFilterHeader = weaponFilterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
weaponFilterHeader:SetPoint("TOP", 0, -14)
weaponFilterHeader:SetText("Weapon Types")
weaponFilterHeader:SetTextColor(unpack(THEME.gold))

local weaponFilterCheckboxes = {}

for index, entry in ipairs(weaponFilterEntries) do
    local name = "EverGearWeaponFilterCheck_" .. entry.key:gsub("[%s:]", "_")
    local cb = CreateFrame("CheckButton", name, weaponFilterPanel, "UICheckButtonTemplate")
    local col = (index - 1) % WEAPON_COLS
    local row = math.floor((index - 1) / WEAPON_COLS)
    cb:SetPoint("TOPLEFT", 12 + col * WEAPON_COL_WIDTH, -38 - row * WEAPON_ROW_HEIGHT)
    _G[name .. "Text"]:SetText(entry.label)
    cb:SetChecked(GetWeaponFilters()[entry.key] ~= false)
    cb:SetScript("OnClick", function(self)
        GetWeaponFilters()[entry.key] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(weaponFilterCheckboxes, { cb = cb, key = entry.key })
end

local function RefreshWeaponFilterCheckboxes()
    for _, entry in ipairs(weaponFilterCheckboxes) do
        entry.cb:SetChecked(GetWeaponFilters()[entry.key] ~= false)
    end
end

-- +26 over the plain grid height for the extra "Usable Only" button row.
weaponFilterPanel:SetSize(WEAPON_PANEL_WIDTH, 92 + math.ceil(#weaponFilterEntries / WEAPON_COLS) * WEAPON_ROW_HEIGHT)

local weaponFilterUsableButton = CreateFrame("Button", nil, weaponFilterPanel, "UIPanelButtonTemplate")
weaponFilterUsableButton:SetSize(150, 20)
weaponFilterUsableButton:SetPoint("BOTTOM", 0, 34)
weaponFilterUsableButton:SetText("Usable Only")
weaponFilterUsableButton:SetScript("OnClick", function()
    local classToken = EverGear:GetPlayerInfo().classToken
    local filters = GetWeaponFilters()
    for _, entry in ipairs(weaponFilterEntries) do
        filters[entry.key] = EverGear:IsWeaponFilterKeyUsable(entry.key, classToken)
    end
    RefreshWeaponFilterCheckboxes()
    EverGear:RefreshUI()
end)

local weaponFilterAllButton = CreateFrame("Button", nil, weaponFilterPanel, "UIPanelButtonTemplate")
weaponFilterAllButton:SetSize(70, 20)
weaponFilterAllButton:SetPoint("BOTTOMLEFT", 10, 8)
weaponFilterAllButton:SetText("All")
weaponFilterAllButton:SetScript("OnClick", function()
    for _, entry in ipairs(weaponFilterEntries) do GetWeaponFilters()[entry.key] = true end
    RefreshWeaponFilterCheckboxes()
    EverGear:RefreshUI()
end)

local weaponFilterNoneButton = CreateFrame("Button", nil, weaponFilterPanel, "UIPanelButtonTemplate")
weaponFilterNoneButton:SetSize(70, 20)
weaponFilterNoneButton:SetPoint("BOTTOMRIGHT", -10, 8)
weaponFilterNoneButton:SetText("None")
weaponFilterNoneButton:SetScript("OnClick", function()
    for _, entry in ipairs(weaponFilterEntries) do GetWeaponFilters()[entry.key] = false end
    RefreshWeaponFilterCheckboxes()
    EverGear:RefreshUI()
end)

-- Small icon button (mirrors the close button's corner placement) that opens
-- the panel to the side of the main window, same as the upgrade-detail panel
-- does, so it never has to steal space from the fixed-size main window.
local weaponFilterButton = CreateFrame("Button", "EverGearWeaponFilterButton", mainFrame)
weaponFilterButton:SetSize(20, 20)
-- -44 (not -30) so it clears the close button's own ~32px footprint at
-- TOPRIGHT -4,-4 instead of overlapping its click area.
weaponFilterButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -8, -44)
weaponFilterButton:SetNormalTexture("Interface\\Icons\\INV_Sword_27")
weaponFilterButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
weaponFilterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Weapon type filters")
    GameTooltip:AddLine("Hide specific weapon types from suggestions.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
weaponFilterButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
weaponFilterButton:SetScript("OnClick", function()
    if weaponFilterPanel:IsShown() then
        weaponFilterPanel:Hide()
        return
    end
    detailPanel:Hide()
    professionFilterPanel:Hide()
    weaponFilterPanel:ClearAllPoints()
    weaponFilterPanel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0)
    weaponFilterPanel:Show()
end)

-- ===== Profession filter panel =====
-- Same button+popup checklist pattern as the weapon-type filter above, for
-- crafted-item professions (see Constants.lua's PROFESSION_FILTER_LIST and
-- source.profession in evergear-backend/schema.md). Every profession is
-- available to any class in-game, so unlike the weapon-type list this one
-- doesn't need to be narrowed per class -- it's the same fixed list for
-- everyone. Shown by default; unchecking one hides that profession's
-- crafted items specifically (e.g. only Blacksmithing checked hides
-- Leatherworking/Tailoring/etc).
-- See GetSourceFilters() above for why this is a function, not a captured
-- local alias -- every read/write below goes through it fresh.
local function GetProfessionFilters()
    EverGearDB.professionFilter = EverGearDB.professionFilter or {}
    return EverGearDB.professionFilter
end

local PROFESSION_PANEL_WIDTH = 170
local PROFESSION_ROW_HEIGHT = 22

professionFilterPanel = CreateFrame("Frame", "EverGearProfessionFilterPanel", mainFrame, "BackdropTemplate")
professionFilterPanel:SetSize(PROFESSION_PANEL_WIDTH, 66 + #EverGear.PROFESSION_FILTER_LIST * PROFESSION_ROW_HEIGHT)
professionFilterPanel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
professionFilterPanel:Hide()

local professionFilterCloseButton = CreateFrame("Button", nil, professionFilterPanel, "UIPanelCloseButton")
professionFilterCloseButton:SetPoint("TOPRIGHT", -2, -2)

local professionFilterHeader = professionFilterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
professionFilterHeader:SetPoint("TOP", 0, -14)
professionFilterHeader:SetText("Professions")
professionFilterHeader:SetTextColor(unpack(THEME.gold))

local professionFilterCheckboxes = {}

for index, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do
    local name = "EverGearProfessionFilterCheck_" .. profName
    local cb = CreateFrame("CheckButton", name, professionFilterPanel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, -38 - (index - 1) * PROFESSION_ROW_HEIGHT)
    _G[name .. "Text"]:SetText(profName)
    cb:SetChecked(GetProfessionFilters()[profName] ~= false)
    cb:SetScript("OnClick", function(self)
        GetProfessionFilters()[profName] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(professionFilterCheckboxes, { cb = cb, name = profName })
end

local function RefreshProfessionFilterCheckboxes()
    for _, entry in ipairs(professionFilterCheckboxes) do
        entry.cb:SetChecked(GetProfessionFilters()[entry.name] ~= false)
    end
end

local professionFilterAllButton = CreateFrame("Button", nil, professionFilterPanel, "UIPanelButtonTemplate")
professionFilterAllButton:SetSize(70, 20)
professionFilterAllButton:SetPoint("BOTTOMLEFT", 10, 8)
professionFilterAllButton:SetText("All")
professionFilterAllButton:SetScript("OnClick", function()
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do GetProfessionFilters()[profName] = true end
    RefreshProfessionFilterCheckboxes()
    EverGear:RefreshUI()
end)

local professionFilterNoneButton = CreateFrame("Button", nil, professionFilterPanel, "UIPanelButtonTemplate")
professionFilterNoneButton:SetSize(70, 20)
professionFilterNoneButton:SetPoint("BOTTOMRIGHT", -10, 8)
professionFilterNoneButton:SetText("None")
professionFilterNoneButton:SetScript("OnClick", function()
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do GetProfessionFilters()[profName] = false end
    RefreshProfessionFilterCheckboxes()
    EverGear:RefreshUI()
end)

-- Small icon button, same corner-stacking pattern as the weapon-type button
-- directly above it.
local professionFilterButton = CreateFrame("Button", "EverGearProfessionFilterButton", mainFrame)
professionFilterButton:SetSize(20, 20)
professionFilterButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -8, -68)
professionFilterButton:SetNormalTexture("Interface\\Icons\\Trade_BlackSmithing")
professionFilterButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
professionFilterButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Profession filters")
    GameTooltip:AddLine("Hide crafted items from professions you don't want suggested.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
professionFilterButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
professionFilterButton:SetScript("OnClick", function()
    if professionFilterPanel:IsShown() then
        professionFilterPanel:Hide()
        return
    end
    detailPanel:Hide()
    weaponFilterPanel:Hide()
    professionFilterPanel:ClearAllPoints()
    professionFilterPanel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0)
    professionFilterPanel:Show()
end)

-- ===== Refresh / toggle =====

function EverGear:RefreshUI()
    detailPanel:Hide()
    SyncLookaheadBounds()  -- re-clamps the slider if the player leveled up since it was last shown

    local gear = self:GetCurrentGear()

    for _, slotToken in ipairs(slotOrder) do
        local btn = slotButtons[slotToken]
        local itemLink = gear[slotToken]

        local candidates, currentScore = self:GetUpgradesForSlot(slotToken, itemLink)

        local filtered = {}
        for _, candidate in ipairs(candidates) do
            local sourceType = candidate.item.source and candidate.item.source.type
            if GetSourceFilters()[sourceType] ~= false then
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

        -- Status color drives both the badge pill and the slot's own border
        -- ring, so the whole icon reads as "this needs attention" (green),
        -- "you're set" (gold), or "nothing to see" (dim) even without
        -- reading the badge text itself.
        local statusColor
        if #candidates == 0 then
            btn.badge:SetText("BIS")
            statusColor = THEME.statusBIS
            btn.isBIS = true
        elseif #filtered == 0 then
            btn.badge:SetText("--")
            statusColor = THEME.statusNone
            btn.isBIS = false
        else
            local best = filtered[1]
            local delta = math.floor((best.score - currentScore) + 0.5)
            btn.badge:SetText("+" .. delta)
            statusColor = THEME.statusUpgrade
            btn.isBIS = false
        end

        btn.badge:SetTextColor(1, 1, 1)
        btn.badgeBG:SetBackdropBorderColor(unpack(statusColor))
        btn:SetBackdropBorderColor(statusColor[1], statusColor[2], statusColor[3], 0.9)
    end
end

-- Re-applies every persisted filter value (source-type, weapon-type,
-- profession) to its checkbox's visual checked state. The checkboxes are
-- only ever created once at addon load and set their own SavedVariables on
-- click, so this doesn't fix a real desync in the stored data -- it exists
-- so a checkbox can never visually drift from what's actually being
-- filtered on, however that happened (a stale SavedVariables read, a
-- checkbox toggled through some path that skipped its OnClick, etc.).
-- Called every time the window opens, right before RefreshUI, so what the
-- player sees checked always matches what RefreshUI is about to filter by.
local function SyncFilterCheckboxes()
    for i, cb in ipairs(filterCheckboxes) do
        local entry = EverGear.SOURCE_TYPE_FILTERS[i]
        cb:SetChecked(GetSourceFilters()[entry.key] ~= false)
    end
    for _, entry in ipairs(weaponFilterCheckboxes) do
        entry.cb:SetChecked(GetWeaponFilters()[entry.key] ~= false)
    end
    for _, entry in ipairs(professionFilterCheckboxes) do
        entry.cb:SetChecked(GetProfessionFilters()[entry.name] ~= false)
    end
end

EverGear.Frame = mainFrame

function EverGear:ToggleUI()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        SyncFilterCheckboxes()
        self:RefreshUI()
        mainFrame:Show()
    end
end

SLASH_EVERGEAR1 = "/evergear"
SLASH_EVERGEAR2 = "/eg"
SlashCmdList["EVERGEAR"] = function()
    EverGear:ToggleUI()
end
