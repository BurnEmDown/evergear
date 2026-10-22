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
-- paperdoll content panel's own size is unaffected. -56 when the two rows of
-- source checkboxes moved into the Filters window (Filters.lua), with
-- TOP_INSET below losing the same 56px.
local FRAME_HEIGHT = 565

local LEFT_MARGIN = 24
local RIGHT_MARGIN = 24
local TOP_Y = -10
-- Real PaperDollFrame slots sit almost flush against each other (~4px gap
-- between 37px icons); the old 48px pitch read as a loose, spread-out list
-- instead of the tight column the character screen has.
local ROW_SPACING = 42
local ICON_SIZE = 37
-- Distance from the window's top edge to where the paperdoll content panel
-- starts: title + spec dropdown + profile dropdown + look-ahead row.
local TOP_INSET = 160
-- Distance from the window's bottom edge to where the paperdoll content
-- panel ends -- the plain window background left below it.
local BOTTOM_INSET = 7

-- Left column, top to bottom. Shirt and Tabard sit where the game's own
-- character sheet has them; they only change the look, so they show what's
-- equipped but are never scored (see EverGear.COSMETIC_SLOTS).
local leftColumn = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
-- Right column, top to bottom
local rightColumn = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
-- Bottom row, centered
local bottomRow = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

-- slotOrder: the slots that get upgrade suggestions; cosmeticSlotOrder: the
-- look-only ones (Shirt, Tabard).
local slotOrder, cosmeticSlotOrder = {}, {}
for _, column in ipairs({ leftColumn, rightColumn, bottomRow }) do
    for _, s in ipairs(column) do
        table.insert(EverGear.COSMETIC_SLOTS[s] and cosmeticSlotOrder or slotOrder, s)
    end
end

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
-- Escape closes the window (instead of opening the game menu), like the
-- game's own panels. Hiding it also closes the profile editor, its popups
-- and the Wanted / Gear Sets windows (OnHide above).
tinsert(UISpecialFrames, "EverGearFrame")

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
    -- Read the clicked spec first: WoW's dropdowns share one set of menu
    -- buttons, and RefreshProfileDropdown below rebuilds the profile
    -- dropdown into them, so self.value is a profile id ("default") by the
    -- time it returns. Reading it after that sent the profile editor to a
    -- spec named "default" ("default Default"), stuck there for good.
    local newSpec = self.value
    local charDB = EverGear:GetCharDB()
    local oldSpec = charDB.spec
    -- Remember the profile used with the spec being left (also covers
    -- characters from before profiles were remembered per spec), then go
    -- back to whichever one was last used with the new spec.
    if oldSpec then
        charDB.profileBySpec = charDB.profileBySpec or {}
        charDB.profileBySpec[oldSpec] = charDB.profileId
    end
    charDB.spec = newSpec
    EverGear:SetActiveProfileId(EverGear:GetRememberedProfileId(EverGear:GetPlayerInfo().classToken, charDB.spec))
    UIDropDownMenu_SetSelectedValue(specDropdown, newSpec)
    if RefreshProfileDropdown then RefreshProfileDropdown() end
    -- Re-points the EP profile editor at the new spec too, but only if it
    -- was still showing the spec we're switching away from -- see
    -- NotifyLiveSpecChanged's own comment (Core/ProfileEditor.lua) for why
    -- that guard matters.
    if EverGear.NotifyLiveSpecChanged then EverGear:NotifyLiveSpecChanged(oldSpec, newSpec) end
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
    local profileId = self.value  -- read first, see SpecDropdown_OnClick
    EverGear:SetActiveProfileId(profileId)
    UIDropDownMenu_SetSelectedValue(profileDropdown, profileId)
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
-- Up to the level cap.
local LOOKAHEAD_MAX = 60

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
lookaheadLabel:SetText("Look Ahead: Off")
lookaheadLabel:SetTextColor(unpack(THEME.goldDim))

-- Reset button sits to the slider's left; shifting the slider right by half
-- the button's own footprint (button width + gap) keeps the [button][slider]
-- pair centered under the label as one group, rather than off-center.
local RESET_BUTTON_SIZE = 16
local RESET_BUTTON_GAP = 6
local sliderXOffset = (RESET_BUTTON_SIZE + RESET_BUTTON_GAP) / 2

local lookaheadSlider = CreateFrame("Slider", "EverGearLookaheadSlider", lookaheadRow, "BackdropTemplate")
lookaheadSlider:SetOrientation("HORIZONTAL")
lookaheadSlider:SetSize(170, 17)
lookaheadSlider:SetPoint("TOP", lookaheadLabel, "BOTTOM", sliderXOffset, -4)
lookaheadSlider:SetHitRectInsets(0, 0, -6, -6)
lookaheadSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
-- The game's own slider art (the same track as the Interface Options
-- sliders), so it reads as something to drag rather than a plain bar.
lookaheadSlider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
})
lookaheadSlider:SetValueStep(1)

-- Gold fill from the left end up to the thumb: how far ahead it looks.
local lookaheadFill = lookaheadSlider:CreateTexture(nil, "BORDER")
lookaheadFill:SetColorTexture(THEME.gold[1], THEME.gold[2], THEME.gold[3], 0.55)
lookaheadFill:SetHeight(5)
lookaheadFill:SetPoint("LEFT", lookaheadSlider, "LEFT", 3, 0)
lookaheadFill:SetPoint("RIGHT", lookaheadSlider:GetThumbTexture(), "CENTER", 0, 0)

-- The highest level it can look ahead to, at the slider's right end.
local lookaheadMaxText = lookaheadRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lookaheadMaxText:SetPoint("LEFT", lookaheadSlider, "RIGHT", 4, 0)

lookaheadSlider:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Look ahead")
    GameTooltip:AddLine("Drag the slider (or use the mouse wheel over it) to also see upgrades you'll be able to use at higher levels. "
        .. "The button on the left goes back to your current level.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
lookaheadSlider:SetScript("OnLeave", function() GameTooltip:Hide() end)
lookaheadSlider:EnableMouseWheel(true)
lookaheadSlider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(self:GetValue() + delta)
end)
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

-- "Look Ahead: Off" while the slider is at its minimum (nothing being looked
-- ahead to), and the level number once it's been moved past that.
local function UpdateLookaheadLabel(value)
    if value <= GetLookaheadMin() then
        lookaheadLabel:SetText("Look Ahead: Off")
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
    lookaheadMaxText:SetText(tostring(maxLevel))
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

-- Content frame: everything below the top controls.
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
-- The slot the mouse is resting on, and how long it has to rest there before
-- the slot's suggested upgrades open by themselves.
local hoveredSlot
local HOVER_DETAIL_DELAY = 0.5
-- True while the Suggested Upgrades panel on screen was opened by a click:
-- hovering other slots then leaves it alone until it's closed (see
-- ShowUpgradeDetailOnHover). Only clicks and hovers set it, so a refresh
-- that briefly hides and reopens the panel keeps it.
local detailOpenedByClick = false
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
        -- Resting on a slot for a moment shows its suggested upgrades too,
        -- without a click (see ShowUpgradeDetailOnHover).
        hoveredSlot = self.slotToken
        local slotToken = self.slotToken
        if C_Timer and C_Timer.After then
            C_Timer.After(HOVER_DETAIL_DELAY, function()
                if hoveredSlot == slotToken then EverGear:ShowUpgradeDetailOnHover(slotToken) end
            end)
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        hoveredSlot = nil
    end)
    btn:SetScript("OnClick", function(self)
        -- Alt-click: the wanted list / gear set menu for the equipped item,
        -- same as Alt-clicking it on the character sheet.
        if IsAltKeyDown() and self.currentLink and EverGear.ShowItemMenu then
            EverGear:ShowItemMenu(self.currentLink)
            return
        end
        if EverGear:HandleItemModifiedClick(self.currentLink) then return end
        if EverGear.COSMETIC_SLOTS[self.slotToken] then return end  -- nothing to suggest
        detailOpenedByClick = true
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

-- ===== Character model =====
-- The player's own character, in the space between the two slot columns and
-- above the weapon row, like the real character sheet. Drag it to turn it.
-- Redrawn whenever the window opens and when gear or appearance changes.
-- A DressUpModel (the dressing room's model type) rather than a plain
-- PlayerModel, so the "hold ranged weapon" button can put the ranged weapon
-- in its hands; it shows the equipped gear the same way.
local characterModel = CreateFrame("DressUpModel", "EverGearCharacterModel", content)
characterModel:EnableMouse(true)
-- Shown by ApplyCharacterModelSetting (below) once the saved setting can be
-- read, so a model turned off is never drawn, not even for a moment.
characterModel:Hide()

-- The sheathe / melee / ranged buttons beside the eye button (created below
-- with CreateModelWeaponButtons).
local mainModelWeapons

local INVSLOT_RANGED_ID = 18

local function RefreshCharacterModel()
    if not characterModel:IsVisible() then return end
    characterModel:SetUnit("player")
    if mainModelWeapons then
        mainModelWeapons:Apply(characterModel, GetInventoryItemLink("player", INVSLOT_RANGED_ID),
            GetInventoryItemLink("player", 1), GetInventoryItemLink("player", 15))
    end
end

-- Dragging a model left/right turns it. Shared with the Gear Sets window's
-- model (WishlistUI.lua, through EverGear.UIHelpers).
local MODEL_TURN_SPEED = 0.02  -- radians per pixel dragged
local function MakeModelTurnable(model)
    local dragStartX, dragStartFacing
    model:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        dragStartX = GetCursorPosition()
        dragStartFacing = self:GetFacing() or 0
    end)
    model:SetScript("OnMouseUp", function() dragStartX = nil end)
    model:SetScript("OnHide", function() dragStartX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not dragStartX then return end
        if not IsMouseButtonDown("LeftButton") then dragStartX = nil return end
        local x = GetCursorPosition()
        self:SetFacing(dragStartFacing + (x - dragStartX) * MODEL_TURN_SPEED)
    end)
end
MakeModelTurnable(characterModel)
characterModel:SetScript("OnShow", RefreshCharacterModel)

local modelWatcher = CreateFrame("Frame")
modelWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_MODEL_CHANGED" and unit ~= "player" then return end
    RefreshCharacterModel()
end)

-- The model can be turned off (eye button above it) for weaker computers.
-- Off means no model at all: it's hidden, emptied, and stops listening for
-- gear changes. The choice is account-wide (EverGearDB.hideCharacterModel),
-- since it's about the computer, not the character.
local modelToggle = CreateFrame("Button", "EverGearCharacterModelToggle", content)
modelToggle:SetSize(16, 16)
modelToggle:SetPoint("TOP", content, "TOP", 0, -2)
modelToggle:SetFrameLevel(characterModel:GetFrameLevel() + 2)
modelToggle:SetNormalTexture("Interface\\Icons\\Spell_Holy_MindVision")
modelToggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local function ApplyCharacterModelSetting()
    local hidden = EverGearDB.hideCharacterModel == true
    characterModel:SetShown(not hidden)
    if mainModelWeapons then mainModelWeapons:SetShown(not hidden) end
    modelToggle:GetNormalTexture():SetDesaturated(hidden)
    modelToggle:SetAlpha(hidden and 0.5 or 1)
    if hidden then
        modelWatcher:UnregisterAllEvents()
        if characterModel.ClearModel then characterModel:ClearModel() end
    else
        modelWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        modelWatcher:RegisterEvent("UNIT_MODEL_CHANGED")
        RefreshCharacterModel()
    end
end

modelToggle:SetScript("OnClick", function(self)
    EverGearDB.hideCharacterModel = not EverGearDB.hideCharacterModel
    ApplyCharacterModelSetting()
    if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
end)
modelToggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if EverGearDB.hideCharacterModel then
        GameTooltip:SetText("Show character model")
    else
        GameTooltip:SetText("Hide character model")
    end
    GameTooltip:Show()
end)
modelToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ===== Model weapon buttons =====
-- Four small buttons to the right of a model's eye button: draw / sheathe
-- the weapons, hold the ranged weapon (on / off), show / hide the helm, show /
-- hide the cloak. Holding the ranged weapon takes the melee weapons off the
-- model and tries the ranged one on in their place; turning it on also draws
-- the weapons. Hiding the helm or cloak takes it
-- off the model; showing it tries it on, so it shows even when the game's
-- own "show helm / cloak" option hides it. The eye button and these are
-- centred over the model as one row. The choices are kept per window for
-- the session. Shared with the Gear Sets window (WishlistUI.lua, through
-- EverGear.UIHelpers).
local MODEL_BUTTON_SIZE, MODEL_BUTTON_GAP = 16, 4
local MODEL_ROW_BUTTONS = 5  -- the eye button and the four below
local INVSLOT_HEAD_ID, INVSLOT_BACK_ID = 1, 15
local INVSLOT_MAINHAND_ID, INVSLOT_OFFHAND_ID = 16, 17
-- Ranged-slot items that are actually held: bows, guns, crossbows, wands and
-- thrown weapons (not librams, idols or relics).
local HOLDABLE_RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function IsHoldableRanged(link)
    if not link then return false end
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local equipLoc = getInfo and select(4, getInfo(link))
    if not equipLoc or equipLoc == "" then return true end
    return HOLDABLE_RANGED[equipLoc] == true
end

-- onChange is called after a button changes the pose, to redraw the model.
-- followGameHelmCloak: start the helm / cloak buttons the way the game's own
-- "show helm / show cloak" options are set (the main window, which shows the
-- character as it is); otherwise both start shown (gear sets).
local function CreateModelWeaponButtons(namePrefix, parent, eyeButton, onChange, followGameHelmCloak)
    local pose = { sheathed = false, ranged = false, showHelm = true, showCloak = true }
    local controls = { pose = pose, rangedAvailable = true }
    -- Read on the first draw, not now: the game's options may not be loaded
    -- yet while the addon's files load.
    local syncWithGame = followGameHelmCloak
    local weaponsButton, rangedButton, helmButton, cloakButton

    -- The eye button sits at the top centre of the model; move it left so
    -- the whole row is centred instead.
    local point, relativeTo, relativePoint, x, y = eyeButton:GetPoint(1)
    if point then
        local shift = ((MODEL_ROW_BUTTONS - 1) * (MODEL_BUTTON_SIZE + MODEL_BUTTON_GAP)) / 2
        eyeButton:SetPoint(point, relativeTo, relativePoint, (x or 0) - shift, y or 0)
    end

    local function SetActive(button, active)
        button:GetNormalTexture():SetDesaturated(not active)
        button:SetAlpha(active and 1 or 0.55)
    end

    local function UpdateButtons()
        SetActive(weaponsButton, not pose.sheathed)
        -- Without a holdable ranged weapon the model holds melee even with
        -- the ranged button on, so it shows as off then.
        SetActive(rangedButton, controls.rangedAvailable and pose.ranged)
        SetActive(helmButton, pose.showHelm)
        SetActive(cloakButton, pose.showCloak)
    end

    local function Make(suffix, texture, anchor, onClick, tooltip)
        local b = CreateFrame("Button", namePrefix .. suffix, parent)
        b:SetSize(MODEL_BUTTON_SIZE, MODEL_BUTTON_SIZE)
        b:SetPoint("LEFT", anchor, "RIGHT", MODEL_BUTTON_GAP, 0)
        b:SetFrameLevel(eyeButton:GetFrameLevel())
        b:SetNormalTexture(texture)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function(self)
            onClick()
            UpdateButtons()
            onChange()
            if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local title, line = tooltip()
            GameTooltip:SetText(title)
            if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        return b
    end

    weaponsButton = Make("Weapons", "Interface\\Icons\\INV_Sword_04", eyeButton,
        function() pose.sheathed = not pose.sheathed end,
        function() return pose.sheathed and "Draw weapons" or "Sheathe weapons" end)
    rangedButton = Make("Ranged", "Interface\\Icons\\Ability_Marksmanship", weaponsButton,
        function()
            if not controls.rangedAvailable then return end
            pose.ranged = not pose.ranged
            if pose.ranged then pose.sheathed = false end
        end,
        function()
            if not controls.rangedAvailable then
                return "Hold ranged weapon", "No bow, gun, crossbow, wand or thrown weapon to hold."
            end
            if pose.ranged then return "Hold melee weapons", "Puts the melee weapons back in hand." end
            return "Hold ranged weapon", "Holds the ranged weapon instead of the melee ones."
        end)
    helmButton = Make("Helm", "Interface\\Icons\\INV_Helmet_01", rangedButton,
        function() pose.showHelm = not pose.showHelm end,
        function() return pose.showHelm and "Hide helm" or "Show helm" end)
    cloakButton = Make("Cloak", "Interface\\Icons\\INV_Misc_Cape_01", helmButton,
        function() pose.showCloak = not pose.showCloak end,
        function() return pose.showCloak and "Hide cloak" or "Show cloak" end)
    UpdateButtons()

    function controls:SetShown(shown)
        weaponsButton:SetShown(shown)
        rangedButton:SetShown(shown)
        helmButton:SetShown(shown)
        cloakButton:SetShown(shown)
    end

    -- Call right after the model is dressed. rangedLink is the ranged-slot
    -- item it should hold in the ranged pose (nil if there isn't one);
    -- helmLink / cloakLink are what it wears there (nil if nothing), tried on
    -- again when shown so the game's own hide option doesn't hide them.
    function controls:Apply(model, rangedLink, helmLink, cloakLink)
        if syncWithGame then
            syncWithGame = false
            if ShowingHelm then pose.showHelm = ShowingHelm() and true or false end
            if ShowingCloak then pose.showCloak = ShowingCloak() and true or false end
        end
        controls.rangedAvailable = IsHoldableRanged(rangedLink)
        UpdateButtons()
        if pose.ranged and controls.rangedAvailable and model.TryOn then
            if model.UndressSlot then
                model:UndressSlot(INVSLOT_MAINHAND_ID)
                model:UndressSlot(INVSLOT_OFFHAND_ID)
            end
            model:TryOn(rangedLink)
        end
        for _, piece in ipairs({ { pose.showHelm, INVSLOT_HEAD_ID, helmLink }, { pose.showCloak, INVSLOT_BACK_ID, cloakLink } }) do
            local shown, slotId, link = piece[1], piece[2], piece[3]
            if not shown then
                if model.UndressSlot then model:UndressSlot(slotId) end
            elseif link and model.TryOn then
                model:TryOn(link)
            end
        end
        if model.SetSheathed then model:SetSheathed(pose.sheathed) end
    end

    return controls
end

mainModelWeapons = CreateModelWeaponButtons("EverGearCharacterModel", content, modelToggle, RefreshCharacterModel, true)

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

    -- Between the slot columns, from the top row down to just above the
    -- weapon row.
    local MODEL_GAP = 6
    characterModel:ClearAllPoints()
    characterModel:SetPoint("TOPLEFT", content, "TOPLEFT", LEFT_MARGIN + ICON_SIZE + MODEL_GAP, TOP_Y)
    characterModel:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -(RIGHT_MARGIN + ICON_SIZE + MODEL_GAP), bottomRowY + MODEL_GAP)
end

content:SetScript("OnSizeChanged", RepositionAll)
RepositionAll()

mainFrame:SetScript("OnShow", function()
    EverGear:SyncSpecAndProfileDropdowns()
    RepositionAll()
    SyncLookaheadBounds()
    ApplyCharacterModelSetting()
end)

-- ===== Detail panel =====
-- Opens to the left or right of the main window (whichever side has room),
-- listing the top candidates for the clicked slot: real item icon (hoverable
-- for its actual tooltip), name, source, and score gain over what's equipped.

-- 20 px wider than the rows' text needs, so the star / gear set buttons in
-- each row's top-right corner get a column of their own (see sourceText).
local DETAIL_WIDTH = 240
local DETAIL_BUTTON_COLUMN = 20  -- the buttons (16 px) and a gap
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

    -- Clicking the item (its icon or its text, left or right button) opens
    -- the "Add to..." menu: wanted list and every gear set (WishlistUI.lua).
    local function ShowAddMenu(anchor)
        if row.itemId and EverGear.ShowStarMenu then
            EverGear:ShowStarMenu(anchor, row.itemId, row.slotToken)
        end
    end
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "LeftButton" or mouseButton == "RightButton" then ShowAddMenu(self) end
    end)

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
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    icon:SetScript("OnClick", function(self)
        if IsAltKeyDown() and self.itemLink and EverGear.ShowItemMenu then
            EverGear:ShowItemMenu(self.itemLink)
            return
        end
        if EverGear:HandleItemModifiedClick(self.itemLink) then return end
        ShowAddMenu(self)
    end)
    row.icon = icon

    -- Star: one click puts the item on the wanted list (and a second click
    -- takes it off). Bright while it's wanted.
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
            GameTooltip:AddLine("Click to add it to your wanted list. Click the item itself for every option.", 0.8, 0.8, 0.8, true)
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

    -- Below the star: put the item in the selected gear set (the one the
    -- Gear Sets window shows), in this slot, replacing whatever is there; a
    -- second click takes it out. Bright while it's in that slot of that set.
    -- With no sets yet, it offers to create one with this item.
    local setButton = CreateFrame("Button", nil, row)
    setButton:SetSize(16, 16)
    setButton:SetPoint("TOP", star, "BOTTOM", 0, -2)
    setButton:SetNormalTexture("Interface\\Icons\\INV_Chest_Chain")
    setButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    setButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local index = EverGear:GetActiveSetIndex()
        local set = index and EverGear:GetSets()[index]
        local slotName = EverGear.FRIENDLY_SLOT_NAMES[row.slotToken] or row.slotToken
        if not set then
            GameTooltip:SetText("Put in a gear set")
            GameTooltip:AddLine("You have no gear sets yet. Click to create one with this item.", 0.8, 0.8, 0.8, true)
        elseif row.itemId and set.slots[row.slotToken] == row.itemId then
            GameTooltip:SetText("In " .. set.name .. " (" .. slotName .. ")")
            GameTooltip:AddLine("Click to take it out of the set.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText("Put in " .. set.name)
            local current = set.slots[row.slotToken]
            if current then
                GameTooltip:AddLine("Replaces " .. EverGear:GetWishlistItemName(current) .. " in the " .. slotName .. " slot.", 0.8, 0.8, 0.8, true)
            else
                GameTooltip:AddLine("Goes in the " .. slotName .. " slot. The set shown in the Gear Sets window is the one used.", 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
    end)
    setButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    setButton:SetScript("OnClick", function(self)
        if not row.itemId then return end
        local index = EverGear:GetActiveSetIndex()
        if not index then
            StaticPopup_Show("EVERGEAR_NEW_SET", nil, nil, { itemId = row.itemId, slotToken = row.slotToken })
            return
        end
        local set = EverGear:GetSets()[index]
        if set.slots[row.slotToken] == row.itemId then
            EverGear:SetSetSlot(index, row.slotToken, nil)
        else
            EverGear:SetSetSlot(index, row.slotToken, row.itemId)
        end
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    row.setButton = setButton

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    nameText:SetPoint("RIGHT", star, "LEFT", -4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    row.nameText = nameText

    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    -- Stops short of the button column, so a long source (two quest names,
    -- a long zone and boss) wraps instead of running under the buttons.
    sourceText:SetPoint("RIGHT", -DETAIL_BUTTON_COLUMN, 0)
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

-- ===== Items / Enhancements tabs =====
-- The panel has two tabs under its header, like gear sites do: Items (the
-- suggested upgrades) and Enhancements (enchants, armor kits, scopes and the
-- like for the item in this slot, from Enchants.lua). The chosen tab stays
-- chosen for every slot until switched back.
local DETAIL_CONTENT_TOP = -62
local MAX_ENHANCEMENT_ROWS = 8
local activeDetailTab = "items"

local detailTabs = {}
local function CreateDetailTab(key, label, name)
    local tab = CreateFrame("Button", name, detailPanel)
    tab:SetHeight(18)
    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 1)
    text:SetText(label)
    tab:SetWidth(text:GetStringWidth() + 16)
    tab.text = text
    local underline = tab:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 4, 0)
    underline:SetPoint("BOTTOMRIGHT", -4, 0)
    underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    underline:SetVertexColor(unpack(THEME.gold))
    tab.underline = underline
    tab:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    tab.key = key
    tab:SetScript("OnClick", function()
        if activeDetailTab == key then return end
        activeDetailTab = key
        if currentDetailSlot then EverGear:ShowUpgradeDetail(currentDetailSlot) end
    end)
    detailTabs[key] = tab
    return tab
end

local itemsTab = CreateDetailTab("items", "Items", "EverGearDetailTabItems")
itemsTab:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 14, -36)
local enhancementsTab = CreateDetailTab("enhancements", "Enhancements", "EverGearDetailTabEnhancements")
enhancementsTab:SetPoint("LEFT", itemsTab, "RIGHT", 4, 0)
enhancementsTab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Enhancements")
    GameTooltip:AddLine("Enchants, armor kits, scopes and the like for the item you have in this slot, best first.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
enhancementsTab:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateDetailTabs()
    for key, tab in pairs(detailTabs) do
        local active = key == activeDetailTab
        tab.underline:SetShown(active)
        if active then
            tab.text:SetTextColor(unpack(THEME.gold))
        else
            tab.text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

-- ===== Enhancements tab rows =====
local enhancementRows = {}

local function AddEnchantRequirements(enchant)
    if enchant.effect then GameTooltip:AddLine(enchant.effect, 1, 1, 1, true) end
    GameTooltip:AddLine(EverGear:GetEnchantSourceSummary(enchant), 0.8, 0.8, 0.8, true)
    if (enchant.minItemLevel or 0) > 0 then
        GameTooltip:AddLine("Goes on items of level " .. enchant.minItemLevel .. " and up.", 0.8, 0.8, 0.8, true)
    end
    if enchant.reqLevel then
        GameTooltip:AddLine("Requires level " .. enchant.reqLevel .. ".", 0.8, 0.8, 0.8, true)
    end
    if enchant.useProfession then
        GameTooltip:AddLine("Only usable with " .. enchant.useProfession .. ".", 0.8, 0.8, 0.8, true)
    end
    if enchant.proc then
        GameTooltip:AddLine("Its effect isn't scored yet, so it counts as 0.", 0.8, 0.8, 0.8, true)
    end
end

local function GetOrCreateEnhancementRow(index)
    if enhancementRows[index] then return enhancementRows[index] end
    local row = CreateFrame("Frame", "EverGearEnhancementRow" .. index, detailPanel)
    row:SetSize(DETAIL_WIDTH - 32, ICON_SIZE)

    local icon = CreateItemIconFrame(nil, row, ICON_SIZE)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:SetScript("OnEnter", function(self)
        local entry = row.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(EverGear:GetEnchantDisplayName(entry.enchant))
        AddEnchantRequirements(entry.enchant)
        if entry.isCurrent then GameTooltip:AddLine("On your item now.", 0.2, 0.9, 0.25, true) end
        GameTooltip:Show()
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

    enhancementRows[index] = row
    return row
end

local function HideEnhancementRows(from)
    for i = from or 1, #enhancementRows do enhancementRows[i]:Hide() end
end

local ENHANCEMENT_MESSAGES = {
    empty = "Nothing equipped in this slot.",
    none = "No enchant, kit or scope you can get goes on this item.",
    noGain = "No enhancement you can get adds anything for your EP profile.",
}

-- Fills the Enhancements tab from yOffset down; returns the yOffset below it.
local function LayoutEnhancements(slotToken, yOffset)
    local list = EverGear:GetEnhancementList(slotToken, EverGear:GetEquippedItemLink(slotToken), MAX_ENHANCEMENT_ROWS)
    if #list.entries == 0 then
        HideEnhancementRows()
        local message = ENHANCEMENT_MESSAGES[list.reason] or ENHANCEMENT_MESSAGES.none
        if list.reason ~= "empty" and list.currentEnchantId and not list.current then
            message = message .. "\n\nYour item has an enchant EverGear doesn't know."
        end
        detailEmptyMessage:SetText(message)
        detailEmptyMessage:ClearAllPoints()
        detailEmptyMessage:SetPoint("TOPLEFT", 16, yOffset)
        detailEmptyMessage:SetPoint("RIGHT", -12, 0)
        detailEmptyMessage:Show()
        return yOffset - detailEmptyMessage:GetStringHeight() - 16
    end
    detailEmptyMessage:Hide()
    local ROW_GAP = 12
    for i, entry in ipairs(list.entries) do
        local row = GetOrCreateEnhancementRow(i)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, yOffset)
        row:Show()
        SetIconTexture(row.icon, EverGear:GetEnchantIcon(entry.enchant))
        if entry.isCurrent then
            row.icon:SetBackdropBorderColor(0.2, 0.9, 0.25, 1)
        else
            row.icon:SetBackdropBorderColor(0.6, 0.56, 0.42, 1)
        end
        local gain = math.floor(entry.gain + 0.5)
        local gainText
        if entry.isCurrent then
            gainText = "|cff33e640(current)|r"
        elseif gain >= 0 then
            gainText = "|cff20e626(+" .. gain .. ")|r"
        else
            gainText = "|cffe62020(" .. gain .. ")|r"
        end
        row.nameText:SetText(EverGear:GetEnchantDisplayName(entry.enchant) .. "  " .. gainText)
        row.nameText:SetTextColor(1, 1, 1)
        row.sourceText:SetText(EverGear:GetEnchantSourceSummary(entry.enchant))
        local textHeight = row.nameText:GetStringHeight() + 4 + row.sourceText:GetStringHeight()
        yOffset = yOffset - math.max(ICON_SIZE, textHeight) - ROW_GAP
    end
    HideEnhancementRows(#list.entries + 1)
    return yOffset - 4
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

-- Ctrl-click previews an item on the character (the game's dressing room) and
-- Shift-click links it in chat, the same as clicking an item anywhere else in
-- the game. Returns true when it handled the click. Takes an item id or link;
-- the dressing room also works for an item the client hasn't cached yet.
function EverGear:HandleItemModifiedClick(itemIdOrLink)
    if not itemIdOrLink or IsAltKeyDown() then return false end
    if not (IsControlKeyDown() or IsShiftKeyDown()) then return false end
    local itemId = type(itemIdOrLink) == "number" and itemIdOrLink or self:GetItemIDFromLink(itemIdOrLink)
    local _, fullLink = SafeGetItemInfo(itemId or itemIdOrLink)
    local link = fullLink or (type(itemIdOrLink) == "string" and itemIdOrLink) or BuildItemLink(itemId)
    if IsControlKeyDown() then
        if DressUpItemLink then DressUpItemLink(link) end
        return true
    end
    -- Shift: a chat link needs the full link, which only a cached item has.
    if fullLink and ChatEdit_InsertLink then ChatEdit_InsertLink(fullLink) end
    return true
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
    MakeModelTurnable = MakeModelTurnable,
    CreateModelWeaponButtons = CreateModelWeaponButtons,
}

local function UpdateStar(row)
    local tracked = row.itemId and EverGear:IsWanted(row.itemId)
    local texture = row.star:GetNormalTexture()
    texture:SetDesaturated(not tracked)
    texture:SetAlpha(tracked and 1 or 0.45)

    local index = EverGear.GetActiveSetIndex and EverGear:GetActiveSetIndex()
    local set = index and EverGear:GetSets()[index]
    local inSet = set and row.itemId and set.slots[row.slotToken] == row.itemId
    local setTexture = row.setButton:GetNormalTexture()
    setTexture:SetDesaturated(not inSet)
    setTexture:SetAlpha(inSet and 1 or 0.45)
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
-- side (optional): only hide it if it's open on that side ("left" /
-- "right"), for windows that open on one side of the main window.
function EverGear:HideUpgradeDetail(side)
    if side and detailPanel:IsShown() then
        local btn = currentDetailSlot and slotButtons[currentDetailSlot]
        if btn and btn.side ~= side then return end
    end
    detailPanel:Hide()
end

-- Hover version of a slot click: opens the slot's suggested upgrades, but
-- only when there are some. Like a click, it leaves the Wanted, Gear Sets and
-- EP profile windows open (the panel stacks below them). It doesn't open
-- while the Filters window is open, since showing the
-- upgrades closes those and the mouse often crosses the slots on its way to
-- a checkbox. The panel stays open when the mouse moves on, so its rows can
-- be used, and switches to whichever slot is hovered next. A panel opened by
-- a click stays on its slot: hovering does nothing until it's closed.
function EverGear:ShowUpgradeDetailOnHover(slotToken)
    local btn = slotButtons[slotToken]
    if not (btn and mainFrame:IsShown()) then return end
    if detailOpenedByClick and detailPanel:IsShown() then return end
    if not btn.upgradeList or #btn.upgradeList == 0 then return end
    if detailPanel:IsShown() and currentDetailSlot == slotToken then return end
    if EverGearFiltersPanel and EverGearFiltersPanel:IsShown() then return end
    detailOpenedByClick = false
    self:ShowUpgradeDetail(slotToken)
end

function EverGear:ShowUpgradeDetail(slotToken)
    local btn = slotButtons[slotToken]
    if not btn then return end

    currentDetailSlot = slotToken

    if EverGearFiltersPanel then EverGearFiltersPanel:Hide() end

    UpdateDetailTabs()
    detailEmptyMessage:ClearAllPoints()
    detailEmptyMessage:SetPoint("TOPLEFT", 16, DETAIL_CONTENT_TOP)
    detailEmptyMessage:SetPoint("RIGHT", -12, 0)

    local candidates = btn.upgradeList or {}
    local shownCount = math.min(#candidates, MAX_DETAIL_CANDIDATES)

    if activeDetailTab == "enhancements" then
        for _, row in ipairs(detailRows) do row:Hide() end
        local yOffset = LayoutEnhancements(slotToken, DETAIL_CONTENT_TOP)
        detailPanel:SetHeight(math.max(150, -yOffset + 16))
    elseif shownCount == 0 then
        HideEnhancementRows()
        detailEmptyMessage:Show()
        for _, row in ipairs(detailRows) do row:Hide() end

        if btn.isBIS then
            detailEmptyMessage:SetText("This is your best-in-slot item!\n\nNo known upgrade for your current level.")
        else
            detailEmptyMessage:SetText("No upgrade shown.\n\nAn upgrade may exist but is hidden by your source-type filters.")
        end

        detailPanel:SetHeight(150 - DETAIL_CONTENT_TOP - 40)
    else
        detailEmptyMessage:Hide()
        HideEnhancementRows()

        local ROW_GAP = 16
        local yOffset = DETAIL_CONTENT_TOP

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
        -- The Upgrades by Zone window (ZoneUpgrades.lua) opens on this side,
        -- so stack below it the same way, instead of on top of it.
        local zonePanel = EverGearZoneUpgradesPanel
        if zonePanel and zonePanel:IsShown() then
            detailPanel:SetPoint("TOPLEFT", zonePanel, "BOTTOMLEFT", 0, -8)
        else
            detailPanel:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, 0)
        end
    end
    detailPanel:Show()
end

-- ===== Wanted list / gear sets buttons =====
-- Top-LEFT corner, at the same heights as the Filters and Upgrades by Zone
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

    -- Shirt / Tabard: just what's equipped, with its rarity border; no badge
    -- and no upgrades (hover and click leave them alone too).
    for _, slotToken in ipairs(cosmeticSlotOrder) do
        local btn = slotButtons[slotToken]
        local itemLink = self:GetEquippedItemLink(slotToken)
        btn.currentLink = itemLink
        btn.currentScore = 0
        btn.upgradeList = {}
        btn.isBIS = false
        btn.badgeBG:Hide()
        if itemLink then
            local _, _, quality, _, _, _, _, _, _, itemTexture = SafeGetItemInfo(itemLink)
            SetIconTexture(btn, itemTexture or SafeGetItemIcon(itemLink) or EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn:SetBackdropBorderColor(GetQualityColor(quality))
        else
            SetIconTexture(btn, EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end

    -- The Gear Sets item picker follows the same filters, so a filter change
    -- shows up there too while it's open.
    if self.RefreshSetItemPicker then self:RefreshSetItemPicker() end
end

-- The Upgrades by Zone window (ZoneUpgrades.lua) follows every refresh, so
-- gear, level and filter changes show up there too.
local BaseRefreshUI = EverGear.RefreshUI
function EverGear:RefreshUI()
    BaseRefreshUI(self)
    if self.RefreshZoneUpgrades then self:RefreshZoneUpgrades() end
end

-- Re-applies every saved filter setting to its checkbox in the Filters window
-- (Filters.lua), so a checkbox never drifts from what's actually filtered on.
-- Called every time the window opens, right before RefreshUI.
local function SyncFilterCheckboxes()
    if EverGear.SyncFiltersWindow then EverGear:SyncFiltersWindow() end
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
    if command == "zone" then
        if EverGear.ToggleZoneUpgrades then EverGear:ToggleZoneUpgrades() end
        return
    end
    if command == "wanted" or command == "sets" then
        if not mainFrame:IsShown() then EverGear:ToggleUI() end
        EverGear:OpenWishlistWindow(command == "wanted" and "ToggleWantedWindow" or "ToggleSetsWindow")
        return
    end
    -- "/eg tutorial" (or "tour" / "help"): the guided tour (Core/Tutorial.lua).
    if (command == "tutorial" or command == "tour" or command == "help") and EverGear.StartTutorial then
        EverGear:StartTutorial()
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
