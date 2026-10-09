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
-- Window height. Hand-tuned (along with TOP_INSET/BOTTOM_INSET just below)
-- to fit the taller controls panel at the top and the "BoE Only" column in
-- the profession filter, while keeping the paperdoll content area and the
-- bottom margin below it reasonably sized. Change this and TOP_INSET/
-- BOTTOM_INSET together, not in isolation -- see content's own anchors
-- further down for how the three relate (content height = FRAME_HEIGHT -
-- TOP_INSET - BOTTOM_INSET).
-- +26 over the original 595 for the new Profile dropdown row (M3, custom EP
-- profiles) -- see TOP_INSET just below, which absorbs the same 26px so the
-- paperdoll content panel's own size is unaffected.
local FRAME_HEIGHT = 621

local LEFT_MARGIN = 24
local RIGHT_MARGIN = 24
local TOP_Y = -10
-- Real PaperDollFrame slots sit almost flush against each other (~4px gap
-- between 37px icons); the old 48px pitch read as a loose, spread-out list
-- instead of the tight column the character screen has.
local ROW_SPACING = 42
local ICON_SIZE = 37
-- Distance from the window's top edge to where the paperdoll content panel
-- starts: title + spec dropdown + profile dropdown + look-ahead row + filter
-- checkbox rows.
local TOP_INSET = 216
-- Distance from the window's bottom edge to where the paperdoll content
-- panel ends -- the plain window background left below it.
local BOTTOM_INSET = 7

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

-- Cropped straight from the addon's own Icon.tga (the small green up-arrow
-- "upgrade" badge in its bottom-right corner) -- see the badge-pill section
-- below, which overlays it next to the "+X" delta on an upgradable slot.
local UPGRADE_ARROW_TEXTURE = "Interface\\AddOns\\EverGear\\UpgradeArrow"

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
    local charDB = EverGear:GetCharDB()
    charDB.filters = charDB.filters or {}
    for _, entry in ipairs(EverGear.SOURCE_TYPE_FILTERS) do
        if charDB.filters[entry.key] == nil then
            charDB.filters[entry.key] = true
        end
    end
    return charDB.filters
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
-- Closes the EP profile editor (Core/ProfileEditor.lua) along with the main
-- window -- that window is parented to UIParent, not mainFrame (it has to
-- outlive a RefreshUI-driven re-anchor and sit beside mainFrame rather than
-- inside it), so it doesn't auto-hide with mainFrame the way a true child
-- frame would. Fires for every path that hides mainFrame (its own close
-- button, ToggleUI, /reload while shown, etc), not just one of them, since
-- it's a frame script rather than something wired into a specific button.
-- EverGearProfileEditor is that frame's own global name (ProfileEditor.lua
-- loads before this file in the .toc, so it already exists here); guarded
-- in case that ever isn't true.
mainFrame:SetScript("OnHide", function()
    if EverGearProfileEditor then EverGearProfileEditor:Hide() end
    if EverGearWantedFrame then EverGearWantedFrame:Hide() end
    if EverGearSetsFrame then EverGearSetsFrame:Hide() end
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

-- Recessed panel behind the spec dropdown / look-ahead slider / filter
-- checkboxes -- created before any of those (so it stays visually behind
-- them as a plain child-draw-order backdrop, no explicit frame level
-- juggling needed), giving the "controls" area its own visual boundary
-- distinct from both the outer dialog frame and the paperdoll panel below
-- it (matching the `content` panel's look), instead of every control
-- floating directly on the plain tan dialog background.
local controlsPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
-- x insets matched exactly to `content` (the suggestions/paperdoll panel
-- below it) -- 6px from each edge -- so the two panels line up flush on
-- both the left and right, same width, instead of drifting independently.
controlsPanel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, -38)
controlsPanel:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -38)
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
EverGear:GetCharDB().spec = EverGear:GetCharDB().spec or EverGear:GetDefaultSpec(EverGear:GetPlayerInfo().classToken)

local specDropdown = CreateFrame("Frame", "EverGearSpecDropdown", mainFrame, "UIDropDownMenuTemplate")
-- -44, not -34 -- dropped 10px per user feedback on the M3 layout.
specDropdown:SetPoint("TOP", mainFrame, "TOP", -8, -44)
UIDropDownMenu_SetWidth(specDropdown, 150)

-- Forward-declared: the Profile dropdown is built just below (needs the spec
-- dropdown to exist first so it can anchor under it), but changing spec has
-- to reset+refresh it too (a profile id from the OLD spec means nothing for
-- the new one -- plan's M3) -- same "local name; ...; name = function"
-- pattern this file already uses for weaponFilterPanel/professionFilterPanel.
local RefreshProfileDropdown

local function SpecDropdown_OnClick(self)
    local charDB = EverGear:GetCharDB()
    local oldSpec = charDB.spec
    -- Remember the profile used with the spec being left (also covers
    -- characters from before profiles were remembered per spec), then go
    -- back to whichever one was last used with the new spec.
    if oldSpec then
        charDB.profileBySpec = charDB.profileBySpec or {}
        charDB.profileBySpec[oldSpec] = charDB.profileId
    end
    charDB.spec = self.value
    EverGear:SetActiveProfileId(EverGear:GetRememberedProfileId(EverGear:GetPlayerInfo().classToken, charDB.spec))
    UIDropDownMenu_SetSelectedValue(specDropdown, self.value)
    if RefreshProfileDropdown then RefreshProfileDropdown() end
    -- Re-points the EP profile editor at the new spec too, but only if it
    -- was still showing the spec we're switching away from -- see
    -- NotifyLiveSpecChanged's own comment (Core/ProfileEditor.lua) for why
    -- that guard matters.
    if EverGear.NotifyLiveSpecChanged then EverGear:NotifyLiveSpecChanged(oldSpec, self.value) end
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
UIDropDownMenu_SetSelectedValue(specDropdown, EverGear:GetCharDB().spec)

-- ===== Profile dropdown (custom EP profiles, M3) =====
-- Lists "Default" (the read-only builtin EverGear:GetBuiltinProfile weights)
-- plus whatever custom profiles the player has saved for their CURRENT
-- class+spec (EverGear:GetProfileList -- Core/EPProfiles.lua). Selecting one writes
-- charDB.profileId; GetScoringProfile (Upgrades.lua) already resolves that
-- through EverGear:GetActiveProfile on every score, so just changing the
-- dropdown + RefreshUI is the entire wiring needed here -- no separate
-- scoring-side change.
EverGear:GetCharDB().profileId = EverGear:GetCharDB().profileId
    or EverGear:GetDefaultProfileId(EverGear:GetPlayerInfo().classToken, EverGear:GetCharDB().spec)

local profileDropdown = CreateFrame("Frame", "EverGearProfileDropdown", mainFrame, "UIDropDownMenuTemplate")
-- +1, not -14 -- raised 15px per user feedback. Anchored directly off
-- specDropdown (not chained through profileLabel below) so this offset
-- alone determines its position -- the label is purely cosmetic and
-- doesn't feed into anything else's layout math.
profileDropdown:SetPoint("TOP", specDropdown, "BOTTOM", 0, 1)
UIDropDownMenu_SetWidth(profileDropdown, 150)

-- Small label above the dropdown -- unlike the spec dropdown (self-evident
-- from showing real spec names like "Arms"/"Fury"), "Default" alone doesn't
-- read as EP-profile selection on its own, per user feedback on the M3
-- layout.
local profileLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
profileLabel:SetPoint("BOTTOM", profileDropdown, "TOP", -8, 2)
profileLabel:SetText("EP Profile")
profileLabel:SetTextColor(unpack(THEME.goldDim))

local function ProfileDropdown_OnClick(self)
    EverGear:SetActiveProfileId(self.value)
    UIDropDownMenu_SetSelectedValue(profileDropdown, self.value)
    EverGear:RefreshUI()
end

-- Re-resolves and re-selects the current class+spec's profile list -- called
-- after a spec change (which just reset profileId to "default") and usable
-- later by the M4 editor window after a profile is created/renamed/deleted,
-- so the dropdown never shows a stale list or a vanished id.
RefreshProfileDropdown = function()
    local charDB = EverGear:GetCharDB()
    UIDropDownMenu_Initialize(profileDropdown, function()
        local playerInfo = EverGear:GetPlayerInfo()
        local profiles = EverGear:GetProfileList(playerInfo.classToken, charDB.spec)
        for _, profile in ipairs(profiles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = profile.name
            info.value = profile.id
            info.func = ProfileDropdown_OnClick
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(profileDropdown, charDB.profileId)
end
RefreshProfileDropdown()
-- Exposed globally so Core/ProfileEditor.lua (M4) can tell this dropdown to
-- re-read the profile list after a create/rename/delete/copy -- this file's
-- own RefreshProfileDropdown is a plain local, not reachable from another
-- file otherwise.
EverGear.RefreshProfileDropdown = RefreshProfileDropdown

-- Re-reads this character's saved spec/profile and makes both dropdowns show it.
-- Needed because everything above runs when the addon files load, which can be
-- before the character's name/realm are available (EverGear:GetCharDB keys on them),
-- so the dropdowns could be built from the wrong settings table -- they then showed
-- the first spec while scoring (Upgrades.lua reads the real table on every refresh)
-- used the spec the player actually saved. Called from PLAYER_LOGIN (Core/Main.lua)
-- and every time the window is shown, when everything is ready. Also writes the
-- visible text explicitly: UIDropDownMenu_SetSelectedValue alone doesn't update the
-- displayed text of a dropdown that has never been opened.
function EverGear:SyncSpecAndProfileDropdowns()
    local charDB = self:GetCharDB()
    local classToken = self:GetPlayerInfo().classToken
    local specs = self.CLASS_SPECS[classToken] or {}

    local valid = false
    for _, spec in ipairs(specs) do
        if spec.name == charDB.spec then valid = true break end
    end
    if not valid then
        -- nothing saved yet, or a spec that no longer exists for this class
        charDB.spec = self:GetDefaultSpec(classToken)
        charDB.profileId = nil
    end
    if not charDB.profileId then
        charDB.profileId = self:GetDefaultProfileId(classToken, charDB.spec)
    end

    UIDropDownMenu_SetSelectedValue(specDropdown, charDB.spec)
    UIDropDownMenu_SetText(specDropdown, charDB.spec)
    RefreshProfileDropdown()

    -- same explicit-text rule for the profile dropdown; fall back to the default
    -- profile if the saved id no longer exists (e.g. the profile was deleted)
    local profiles = self:GetProfileList(classToken, charDB.spec)
    local shownName
    for _, profile in ipairs(profiles) do
        if profile.id == charDB.profileId then shownName = profile.name break end
    end
    if not shownName then
        charDB.profileId = self:GetDefaultProfileId(classToken, charDB.spec)
        for _, profile in ipairs(profiles) do
            if profile.id == charDB.profileId then shownName = profile.name break end
        end
        UIDropDownMenu_SetSelectedValue(profileDropdown, charDB.profileId)
    end
    if shownName then UIDropDownMenu_SetText(profileDropdown, shownName) end
end

-- Small icon button opening the profile editor window (Core/ProfileEditor.lua,
-- M4) -- where "Default" is the only option stops being true. Sits directly
-- to the LEFT of the Profile dropdown at the same height, per user feedback
-- (previously stacked in the weaponFilterButton/professionFilterButton
-- corner-icon column further down this file -- moved out of there since it's
-- really about the dropdown right next to it, not a filter panel toggle like
-- those two).
local profileEditorButton = CreateFrame("Button", "EverGearProfileEditorButton", mainFrame)
profileEditorButton:SetSize(20, 20)
profileEditorButton:SetPoint("RIGHT", profileDropdown, "LEFT", 14, 2)  -- tucked in close to the dropdown, clear of the Sets button
profileEditorButton:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_01")
profileEditorButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
profileEditorButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("EP profiles")
    GameTooltip:AddLine("Create, edit, and manage custom EP scoring profiles.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
profileEditorButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
profileEditorButton:SetScript("OnClick", function()
    EverGear:ToggleProfileEditor()
end)

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
-- -106: -60 originally, +26 to clear the new Profile dropdown row (M3), then
-- +20 more per user feedback on that layout.
lookaheadRow:SetPoint("TOP", mainFrame, "TOP", 0, -106)

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
    local charDB = EverGear:GetCharDB()
    local stored = charDB.lookaheadLevel or minLevel
    stored = math.max(minLevel, math.min(maxLevel, stored))
    charDB.lookaheadLevel = stored

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
    EverGear:GetCharDB().lookaheadLevel = value
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
-- first 3 entries in SOURCE_TYPE_FILTERS), row 2 is World Drop/Dungeon Drop/
-- Special (the rest) -- each row centers independently rather than sharing
-- one grid, in case the rows ever differ in length. The window no longer resizes, so this
-- doesn't need to be recalculated dynamically, but it's still driven off
-- mainFrame's actual width rather than a hardcoded number.
local FILTER_SLOT_WIDTH = 92
-- The right-hand column (Craft / Special) sits a little further right so the
-- middle column's longer label ("Dungeon Drop") doesn't run into its checkbox.
local FILTER_LAST_COLUMN_NUDGE = 16
local FILTER_ROW_GAP = 26
-- -150: -104 originally, +26 to clear the new Profile dropdown row (M3),
-- then +20 more per user feedback on that layout.
local FILTER_TOP_Y = -150
local FILTER_ROW_1_COUNT = 3

local function RepositionFilters()
    local width = mainFrame:GetWidth()

    local function centerRow(checkboxes, y)
        local totalWidth = #checkboxes * FILTER_SLOT_WIDTH
        local startX = (width - totalWidth) / 2
        for i, cb in ipairs(checkboxes) do
            local nudge = (i == 3) and FILTER_LAST_COLUMN_NUDGE or 0
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + (i - 1) * FILTER_SLOT_WIDTH + nudge, y)
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

-- Small version stamp, bottom-left of the window -- see Constants.lua's
-- EverGear.VERSION for the bump policy (every shipped change bumps the
-- patch digit; only the user decides when to move to 0.1.0/1.0.0).
-- On its own frame, explicitly leveled above `content` (a plain FontString
-- parented straight to mainFrame rendered BEHIND content here, since a
-- child frame's own level -- content is mainFrame's level+1 -- wins over
-- draw-layer ordering across different frames regardless of OVERLAY/etc).
-- Nudged up by its own text height on top of the base 6px margin (rather
-- than a second hardcoded pixel guess) so it clears the window's bottom
-- edge/border regardless of what font size GameFontDisable resolves to.
-- +15 more on top of that to follow `content`'s bottom edge, which moved up
-- 15px (BOTTOM_INSET 12 -> 27 above) -- keeps the same small overlap with
-- content's corner that the frame-level fix above accounts for.
local versionFrame = CreateFrame("Frame", nil, mainFrame)
versionFrame:SetFrameLevel(content:GetFrameLevel() + 1)
versionFrame:SetAllPoints(mainFrame)
local versionText = versionFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
versionText:SetText("v" .. EverGear.VERSION)
versionText:SetTextColor(unpack(THEME.goldDim))
versionText:SetPoint("BOTTOMLEFT", 10, versionText:GetStringHeight())

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

    -- Inset matches edgeSize exactly (2px) so the icon sits fully inside the
    -- backdrop edge with no overlap. A smaller inset (1px, the original value)
    -- left the icon's texture overlapping half the border's width by design,
    -- which is fine horizontally but not vertically: WoW's texture-height
    -- rounding can push a texture's rendered height a fraction of a pixel
    -- past its anchor points, and with only 1px of border showing that was
    -- enough to fully paint over the border's top/bottom edge on some rows.
    -- Matching the inset to edgeSize removes the overlap entirely instead of
    -- relying on sub-pixel rounding staying in our favor.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
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

    -- Left-anchored (not centered) now that the pill's width is recomputed
    -- every refresh (see UpdateBadgePill below) -- an upgrade slot needs room
    -- for the arrow icon after the text, a BIS/"--" slot doesn't, and only a
    -- fixed left edge keeps the text from jumping around between the two.
    local badge = badgeBG:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    badge:SetPoint("LEFT", badgeBG, "LEFT", 4, 0)
    btn.badge = badge

    -- Small green "upgrade available" arrow (cropped from the addon's own
    -- icon, see UPGRADE_ARROW_TEXTURE) shown next to the "+X" delta text --
    -- hidden for the BIS/"--" cases, where there's no delta to point at.
    local upgradeArrow = badgeBG:CreateTexture(nil, "OVERLAY")
    upgradeArrow:SetSize(10, 10)
    upgradeArrow:SetTexture(UPGRADE_ARROW_TEXTURE)
    upgradeArrow:SetPoint("LEFT", badge, "RIGHT", 2, 0)
    upgradeArrow:Hide()
    btn.upgradeArrow = upgradeArrow

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
        -- Alt-click: the wanted list / gear set menu for the equipped item,
        -- same as Alt-clicking it on the character sheet.
        if IsAltKeyDown() and self.currentLink and EverGear.ShowItemMenu then
            EverGear:ShowItemMenu(self.currentLink)
            return
        end
        EverGear:ShowUpgradeDetail(self.slotToken)
    end)

    slotButtons[slotToken] = btn
    return btn
end

-- Resizes/repositions a slot button's badge pill for its current text +
-- (optionally) the upgrade arrow -- the pill only has a BOTTOMRIGHT anchor
-- point (see CreateSlotButton), so changing its width grows/shrinks it
-- leftward from that fixed corner, same as it's always been sized. Keeping
-- this fixed-minimum-width rather than always tight-fitting the text means
-- "BIS"/"--" render at the same pill size they always have.
local BADGE_PAD_LEFT = 4
local BADGE_PAD_RIGHT = 4
local BADGE_ARROW_GAP = 2
local BADGE_ARROW_WIDTH = 10
local BADGE_MIN_WIDTH = 24

local function UpdateBadgePill(btn, showArrow)
    btn.upgradeArrow:SetShown(showArrow)
    local width = BADGE_PAD_LEFT + btn.badge:GetStringWidth() + BADGE_PAD_RIGHT
    if showArrow then
        width = width + BADGE_ARROW_GAP + BADGE_ARROW_WIDTH
    end
    btn.badgeBG:SetWidth(math.max(BADGE_MIN_WIDTH, width))
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
    EverGear:SyncSpecAndProfileDropdowns()
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

-- Which slot's detail panel is currently showing, if any -- used below to
-- re-run ShowUpgradeDetail when a cold item-info cache miss resolves (see
-- the GET_ITEM_INFO_RECEIVED watcher near the end of this file).
local currentDetailSlot

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
    icon:SetScript("OnClick", function(self)
        if IsAltKeyDown() and self.itemLink and EverGear.ShowItemMenu then
            EverGear:ShowItemMenu(self.itemLink)
        end
    end)
    row.icon = icon

    -- Star: one click puts the item on the wanted list (and a second click
    -- takes it off). Bright while it's wanted. Gear sets go through Alt-click
    -- on the icon instead (menu in WishlistUI.lua).
    local star = CreateFrame("Button", nil, row)
    star:SetSize(16, 16)
    star:SetPoint("TOPRIGHT", 0, 0)
    star:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    star:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.itemId and EverGear:IsWanted(row.itemId) then
            GameTooltip:SetText("On your wanted list")
            GameTooltip:AddLine("Click to take it off.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText("Want this")
            GameTooltip:AddLine("Click to add it to your wanted list. Alt-click the icon to put it in a gear set.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    star:SetScript("OnClick", function(self)
        if not row.itemId then return end
        if EverGear:IsWanted(row.itemId) then
            EverGear:RemoveWanted(row.itemId)
        else
            EverGear:AddWanted(row.itemId, row.slotToken)
        end
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    row.star = star

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    nameText:SetPoint("RIGHT", star, "LEFT", -4, 0)
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

-- Shared with WishlistUI.lua so its windows look the same as this one.
EverGear.UIHelpers = {
    THEME = THEME,
    CreateItemIconFrame = CreateItemIconFrame,
    SetIconTexture = SetIconTexture,
    GetQualityColor = GetQualityColor,
    SafeGetItemInfo = SafeGetItemInfo,
    SafeGetItemIcon = SafeGetItemIcon,
    BuildItemLink = BuildItemLink,
}

local function UpdateStar(row)
    local tracked = row.itemId and EverGear:IsWanted(row.itemId)
    local texture = row.star:GetNormalTexture()
    texture:SetDesaturated(not tracked)
    texture:SetAlpha(tracked and 1 or 0.45)
end

-- Called by WishlistUI.lua whenever the wanted list or a set changes.
function EverGear:RefreshDetailStars()
    for _, row in ipairs(detailRows) do
        if row:IsShown() then UpdateStar(row) end
    end
end

-- Exposed so Core/ProfileEditor.lua can hide a stale detail panel when IT
-- opens (same side, left, as of the profile editor's reposition below) --
-- otherwise a detail panel left open from an earlier item click would sit at
-- its old anchor, now directly under/behind the freshly-opened editor
-- window instead of following it.
function EverGear:HideUpgradeDetail()
    detailPanel:Hide()
end

function EverGear:ShowUpgradeDetail(slotToken)
    local btn = slotButtons[slotToken]
    if not btn then return end

    currentDetailSlot = slotToken

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
            row.itemId = candidate.item.id
            row.slotToken = slotToken
            UpdateStar(row)
            SetIconTexture(row.icon, SafeGetItemIcon(candidate.item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon.itemLink = itemLink

            -- Quality-colored name + icon border (a live lookup -- our own
            -- item DB doesn't carry rarity, but the client's item cache
            -- does for any real item id/link). Falls back to the theme's
            -- neutral gold-grey when the client hasn't cached this item yet
            -- (a common cold-cache miss for anything not recently seen,
            -- especially here -- a candidate the player may never have laid
            -- eyes on) rather than leaving it uncolored; the
            -- GET_ITEM_INFO_RECEIVED watcher near the end of this file
            -- re-runs this once the real data arrives, so it self-corrects
            -- in place instead of needing the panel closed and reopened.
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
        -- The profile editor (Core/ProfileEditor.lua) now also opens to the
        -- LEFT of mainFrame, same side as a left-slot's detail panel -- per
        -- user feedback, anchor this panel below the editor instead of
        -- beside mainFrame directly when the editor is open, so the two
        -- windows stack vertically instead of landing on top of each other.
        -- EverGearProfileEditor is that frame's own global name (ProfileEditor.lua
        -- loads before this file in the .toc, so it already exists here).
        -- The wanted list and gear sets windows (WishlistUI.lua) open in that
        -- same spot, so the same stacking applies to them.
        local editor
        for _, frame in ipairs({ EverGearProfileEditor, EverGearWantedFrame, EverGearSetsFrame }) do
            if frame and frame:IsShown() then editor = frame end
        end
        if editor then
            detailPanel:SetPoint("TOPRIGHT", editor, "BOTTOMRIGHT", 0, -8)
        else
            detailPanel:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -8, 0)
        end
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
    local charDB = EverGear:GetCharDB()
    charDB.weaponTypeFilter = charDB.weaponTypeFilter or {}
    return charDB.weaponTypeFilter
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

-- +26 over the plain grid height for the extra "Usable Only" button row,
-- +5 more per user feedback (the panel is anchored by its TOPLEFT corner
-- when shown, so growing its height here extends the bottom edge downward
-- without moving the top).
weaponFilterPanel:SetSize(WEAPON_PANEL_WIDTH, 97 + math.ceil(#weaponFilterEntries / WEAPON_COLS) * WEAPON_ROW_HEIGHT)

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
-- TOPRIGHT -4,-4 instead of overlapping its click area. -16 (not -8) on x so
-- it isn't flush against the window's right edge/border.
weaponFilterButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, -44)
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
    local charDB = EverGear:GetCharDB()
    charDB.professionFilter = charDB.professionFilter or {}
    return charDB.professionFilter
end

-- "BoE only" per profession -- see Upgrades.lua's professionBoEOnly comment
-- for the filtering behavior. Off (false/nil) by default for everyone.
local function GetProfessionBoEOnly()
    local charDB = EverGear:GetCharDB()
    charDB.professionBoEOnly = charDB.professionBoEOnly or {}
    return charDB.professionBoEOnly
end

-- +50 over the original 170 to fit the new per-row "BoE only" checkbox
-- without crowding the profession name/checkbox already there.
local PROFESSION_PANEL_WIDTH = 220
local PROFESSION_ROW_HEIGHT = 22
-- First checkbox row's y offset -- below both the main "Professions" title
-- and the "BoE Only" column header (see their own y offsets just below),
-- with a genuine gap to each rather than crowding them.
local PROFESSION_TOP_Y = -36

professionFilterPanel = CreateFrame("Frame", "EverGearProfessionFilterPanel", mainFrame, "BackdropTemplate")
-- +10 over the original 66 base for extra room around the new "BoE Only"
-- column header above the checkboxes.
professionFilterPanel:SetSize(PROFESSION_PANEL_WIDTH, 76 + #EverGear.PROFESSION_FILTER_LIST * PROFESSION_ROW_HEIGHT)
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
professionFilterHeader:SetPoint("TOP", 0, -4)
professionFilterHeader:SetText("Professions")
professionFilterHeader:SetTextColor(unpack(THEME.gold))

-- Small header label above the BoE-only column so the checkbox's purpose is
-- clear without needing to hover every row for the tooltip.
local professionFilterBoEHeader = professionFilterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
-- Above the checkbox column (PROFESSION_TOP_Y + 8, i.e. 8px higher up /
-- less negative than the first row), not below it -- and below the main
-- title header at -4, so both have real breathing room around them. (+18
-- originally, dropped 5px twice along with the checkboxes themselves below.)
professionFilterBoEHeader:SetPoint("TOPRIGHT", -12, PROFESSION_TOP_Y + 8)
professionFilterBoEHeader:SetText("BoE Only")
professionFilterBoEHeader:SetTextColor(unpack(THEME.goldDim))

local professionFilterCheckboxes = {}
local professionBoECheckboxes = {}

for index, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do
    local rowY = PROFESSION_TOP_Y - (index - 1) * PROFESSION_ROW_HEIGHT

    local name = "EverGearProfessionFilterCheck_" .. profName
    local cb = CreateFrame("CheckButton", name, professionFilterPanel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, rowY)
    _G[name .. "Text"]:SetText(profName)
    cb:SetChecked(GetProfessionFilters()[profName] ~= false)
    cb:SetScript("OnClick", function(self)
        GetProfessionFilters()[profName] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(professionFilterCheckboxes, { cb = cb, name = profName })

    -- Per-row "BoE only" checkbox, right-aligned in its own column -- when
    -- checked, only that profession's confirmed-BoE items are suggested
    -- (see Upgrades.lua), for browsing crafted gear from a profession the
    -- player doesn't actually have. Small (18x18, vs the ~26px default) so
    -- it reads as a secondary control next to the main profession checkbox.
    local boeName = "EverGearProfessionBoECheck_" .. profName
    local boeCb = CreateFrame("CheckButton", boeName, professionFilterPanel, "UICheckButtonTemplate")
    boeCb:SetSize(18, 18)
    -- rowY + 2 originally, dropped 5px twice to rowY - 8 (matches the header above).
    boeCb:SetPoint("TOPRIGHT", -14, rowY - 8)
    _G[boeName .. "Text"]:SetText("")
    boeCb:SetChecked(GetProfessionBoEOnly()[profName] == true)
    boeCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("BoE Only")
        GameTooltip:AddLine("Only suggest " .. profName .. " items confirmed Bind on Equip --", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("for checking crafted gear from a profession you don't have.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    boeCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    boeCb:SetScript("OnClick", function(self)
        GetProfessionBoEOnly()[profName] = self:GetChecked()
        EverGear:RefreshUI()
    end)
    table.insert(professionBoECheckboxes, { cb = boeCb, name = profName })
end

local function RefreshProfessionFilterCheckboxes()
    for _, entry in ipairs(professionFilterCheckboxes) do
        entry.cb:SetChecked(GetProfessionFilters()[entry.name] ~= false)
    end
    for _, entry in ipairs(professionBoECheckboxes) do
        entry.cb:SetChecked(GetProfessionBoEOnly()[entry.name] == true)
    end
end

local professionFilterAllButton = CreateFrame("Button", nil, professionFilterPanel, "UIPanelButtonTemplate")
professionFilterAllButton:SetSize(70, 20)
professionFilterAllButton:SetPoint("BOTTOMLEFT", 10, 13)
professionFilterAllButton:SetText("All")
professionFilterAllButton:SetScript("OnClick", function()
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do GetProfessionFilters()[profName] = true end
    RefreshProfessionFilterCheckboxes()
    EverGear:RefreshUI()
end)

local professionFilterNoneButton = CreateFrame("Button", nil, professionFilterPanel, "UIPanelButtonTemplate")
professionFilterNoneButton:SetSize(70, 20)
professionFilterNoneButton:SetPoint("BOTTOMRIGHT", -10, 13)
professionFilterNoneButton:SetText("None")
professionFilterNoneButton:SetScript("OnClick", function()
    for _, profName in ipairs(EverGear.PROFESSION_FILTER_LIST) do GetProfessionFilters()[profName] = false end
    RefreshProfessionFilterCheckboxes()
    EverGear:RefreshUI()
end)

-- Small icon button, same corner-stacking pattern as the weapon-type button
-- directly above it (including its -16 x offset, so both line up flush).
local professionFilterButton = CreateFrame("Button", "EverGearProfessionFilterButton", mainFrame)
professionFilterButton:SetSize(20, 20)
professionFilterButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -16, -68)
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

-- ===== Wanted list / gear sets buttons =====
-- Top-LEFT corner, at the same heights as the weapon / profession filter
-- buttons on the right: the windows they open sit on the left of the main
-- window too (WishlistUI.lua), so each button is on the side its window opens.
local function CreateCornerButton(name, y, texture, title, line, onClick)
    local b = CreateFrame("Button", name, mainFrame)
    b:SetSize(20, 20)
    b:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, y)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

CreateCornerButton("EverGearWantedButton", -44, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    "Wanted list", "Items this character wants. Alt-click any item, or use the star in Suggested Upgrades, to add one.",
    function() EverGear:OpenWishlistWindow("ToggleWantedWindow") end)
CreateCornerButton("EverGearSetsButton", -68, "Interface\\Icons\\INV_Chest_Chain_05",
    "Gear sets", "Build gear sets for this character and see which pieces you have.",
    function() EverGear:OpenWishlistWindow("ToggleSetsWindow") end)

-- WishlistUI.lua defines the toggles; if it didn't load (a client that lacks
-- something it needs, or new files that need a full game restart to be seen),
-- say so in chat instead of throwing a Lua error on every click.
function EverGear:OpenWishlistWindow(toggleName)
    if self[toggleName] then
        self[toggleName](self)
    else
        print("|cff33ff99EverGear|r: the wanted list / gear sets didn't load. If you just updated EverGear, exit and restart the game (a /reload doesn't pick up new addon files).")
    end
end

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

        local itemQuality
        if itemLink then
            local _, _, quality, _, _, _, _, _, _, itemTexture = SafeGetItemInfo(itemLink)
            itemQuality = quality
            SetIconTexture(btn, itemTexture or SafeGetItemIcon(itemLink) or EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn.currentLink = itemLink
        else
            SetIconTexture(btn, EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn.currentLink = nil
        end

        btn.currentScore = currentScore
        btn.upgradeList = filtered

        -- The slot's own border ring is now the equipped item's rarity color
        -- (gray/white/green/blue/purple/yellow -- same lookup/fallback the
        -- detail panel's rows already use below), not an upgrade-status
        -- color -- per user feedback, "what is this item" (rarity) belongs on
        -- the icon itself, while "do I need to act on this" moves entirely to
        -- the badge pill (status-colored still) plus its text/arrow. An empty
        -- slot has no rarity to show -- white (same RGB as the "Common"
        -- quality color, per user feedback) rather than GetQualityColor's own
        -- unknown-quality fallback (a muted gold, meant for a cache-miss on a
        -- REAL item, not "there's nothing here").
        local qr, qg, qb
        if itemLink then
            qr, qg, qb = GetQualityColor(itemQuality)
        else
            qr, qg, qb = 1, 1, 1
        end
        btn:SetBackdropBorderColor(qr, qg, qb, 1)

        -- Status color still drives the badge pill, so "this needs attention"
        -- (green), "you're set" (gold), or "nothing to see" (dim) reads at a
        -- glance even before reading the badge text -- only the slot's own
        -- border moved to rarity coloring above.
        local statusColor
        local showArrow = false
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
            showArrow = true
        end

        btn.badge:SetTextColor(1, 1, 1)
        btn.badgeBG:SetBackdropBorderColor(unpack(statusColor))
        UpdateBadgePill(btn, showArrow)
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
    for _, entry in ipairs(professionBoECheckboxes) do
        entry.cb:SetChecked(GetProfessionBoEOnly()[entry.name] == true)
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
SlashCmdList["EVERGEAR"] = function(msg)
    local debugArg = (msg or ""):match("^%s*[Dd][Ee][Bb][Uu][Gg]%s*(.-)%s*$")
    if debugArg then
        EverGear:HandleDebugCommand(debugArg)
        return
    end
    local command = strlower(strtrim(msg or ""))
    if command == "wanted" or command == "sets" then
        if not mainFrame:IsShown() then EverGear:ToggleUI() end
        EverGear:OpenWishlistWindow(command == "wanted" and "ToggleWantedWindow" or "ToggleSetsWindow")
        return
    end
    EverGear:ToggleUI()
end

-- ===== Cold item-cache self-correction =====
-- SafeGetItemInfo (C_Item.GetItemInfo under the hood) returns nils for an
-- item the client hasn't cached yet -- most often one of the detail panel's
-- upgrade candidates, since those can easily be items the player has never
-- seen in-game before. That's what GetQualityColor's neutral-gold fallback
-- above was showing instead of the real rarity color (reported as "borders
-- are yellow the first time, correct after closing and reopening" -- closing
-- and reopening just happened to re-run the same lookup after the client's
-- background fetch had time to land). The client fires
-- GET_ITEM_INFO_RECEIVED once that fetch actually completes, so this just
-- re-runs whichever of RefreshUI/ShowUpgradeDetail is currently relevant
-- instead of waiting for the player to close and reopen something.
local itemInfoWatcher = CreateFrame("Frame")
itemInfoWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemInfoWatcher:SetScript("OnEvent", function(_, _, _, success)
    if not success then return end
    -- Captured BEFORE RefreshUI runs, not after: RefreshUI unconditionally
    -- calls detailPanel:Hide() as its very first line (it has no way to know
    -- whether the panel's current candidates are still valid), so checking
    -- detailPanel:IsShown() afterward was always false and this reopen never
    -- fired. That was the actual cause of a since-reported bug ("the first
    -- time I click a gear slot the suggestions window doesn't open, but it
    -- does the 2nd time") -- showing the detail panel for a slot almost
    -- always looks up brand-new candidate items the player has never seen
    -- (see the quality-color lookup above), which is exactly the kind of
    -- cache miss this watcher exists to catch: the click shows the panel,
    -- then this event fires moments later for that same cache miss, and
    -- RefreshUI silently closed it again with nothing to reopen it.
    local wasDetailShown = detailPanel:IsShown()
    if mainFrame:IsShown() then
        EverGear:RefreshUI()
    end
    if wasDetailShown and currentDetailSlot then
        EverGear:ShowUpgradeDetail(currentDetailSlot)
    end
end)
