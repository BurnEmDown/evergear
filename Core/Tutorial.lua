-- Tutorial.lua
-- A guided tour of the main window: the small "?" button in its top-left
-- corner starts a series of small popups ("steps"), shown one at a time,
-- each sitting next to the part of the window it explains (with a pulsing
-- gold frame around that part). Next / Back move through the steps; the X,
-- Escape, or closing the main window ends the tour at any point.
--
-- Some steps need a side window or panel to be open to make sense (the
-- Suggested Upgrades panel, a filter panel, the EP profile editor, the
-- Wanted / Gear Sets windows). A step opens it when it starts, and closes it
-- again when the tour moves on or ends -- but only if the step was the one
-- that opened it, so a window the player already had open stays open.
--
-- Every step looks up what it points at when it's shown, by global frame
-- name, and is skipped if that isn't there (a file that didn't load in some
-- client build, say) instead of throwing an error.
--
-- First-time hint: the first time the window is opened on this client
-- (account-wide, EverGearDB.tutorialHintSeen), the "?" button glows and a
-- small "New here?" label sits beside it. Clicking the button (or starting
-- the tour any other way) removes it, and it never comes back on this
-- client -- the button itself always stays.

EverGear = EverGear or {}

local H = EverGear.UIHelpers
local THEME = H.THEME
local mainFrame = EverGear.Frame

-- Frames are looked up by their global names at the moment a step is shown
-- (they're created by other files, some only on first use), never cached.
local function Named(name)
    return _G[name]
end

local function IsShownFrame(frame)
    return frame ~= nil and frame:IsShown() and true or false
end

-- ===== "?" button =====
-- Top-left corner, level with the window title -- the same corner column
-- as the Wanted / Gear Sets buttons below it, mirroring the close button in
-- the opposite corner. Drawn as a small dark tile with a gold "?" (the same
-- look as the slot icons) rather than a texture, so it can't go missing on
-- a client that lacks some art file.
local helpButton = CreateFrame("Button", "EverGearTutorialButton", mainFrame, "BackdropTemplate")
helpButton:SetSize(20, 20)
helpButton:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -14)
helpButton:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
helpButton:SetBackdropColor(unpack(THEME.panelBg))
helpButton:SetBackdropBorderColor(unpack(THEME.panelBorder))
helpButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local helpButtonText = helpButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
helpButtonText:SetPoint("CENTER", 0, 0)
helpButtonText:SetText("?")
helpButtonText:SetTextColor(unpack(THEME.gold))

helpButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quick tour")
    GameTooltip:AddLine("A short walk through everything in this window.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
helpButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ===== First-time hint =====
-- A soft gold glow behind the button (the action-button border texture,
-- ADD-blended) plus a small "New here?" label just outside the window's left
-- edge, both pulsing together. Lives on its own frame (child of the main
-- window) so a single Hide() takes the whole cue away.
local hint = CreateFrame("Frame", "EverGearTutorialHint", mainFrame)
hint:SetAllPoints(helpButton)
hint:SetFrameLevel(helpButton:GetFrameLevel() + 2)
hint:Hide()

local hintGlow = hint:CreateTexture(nil, "OVERLAY")
hintGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
hintGlow:SetBlendMode("ADD")
hintGlow:SetVertexColor(THEME.gold[1], THEME.gold[2], THEME.gold[3])
hintGlow:SetSize(44, 44)
hintGlow:SetPoint("CENTER", helpButton, "CENTER", 0, 0)

local hintBubble = CreateFrame("Frame", nil, hint, "BackdropTemplate")
hintBubble:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
hintBubble:SetBackdropColor(unpack(THEME.panelBg))
hintBubble:SetBackdropBorderColor(unpack(THEME.gold))
-- Right edge just outside the window's left border, level with the button.
hintBubble:SetPoint("RIGHT", helpButton, "LEFT", -20, 0)
hintBubble:SetClampedToScreen(true)

local hintText = hintBubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hintText:SetPoint("CENTER", 0, 0)
hintText:SetText("New here? Take the tour  >")
hintText:SetTextColor(unpack(THEME.gold))
hintBubble:SetSize(hintText:GetStringWidth() + 16, 20)

-- Pulse: alpha eases between ~0.35 and 1 about once a second.
local hintClock = 0
hint:SetScript("OnUpdate", function(self, elapsed)
    hintClock = hintClock + (elapsed or 0)
    local pulse = 0.675 + 0.325 * math.sin(hintClock * 5)
    hintGlow:SetAlpha(pulse)
    hintBubble:SetAlpha(0.6 + 0.4 * pulse)
end)

local function HideHint()
    hint:Hide()
end

-- Marks the hint as seen for good (account-wide) and takes it away.
local function DismissHint()
    EverGearDB.tutorialHintSeen = true
    HideHint()
end

-- Checked each time the window opens rather than when this file loads: the
-- saved EverGearDB isn't reliably in place yet at load time (see the notes in
-- Database.lua / UI.lua). The very first open shows the cue and records it
-- right away, so later opens never show it again even if the player closes
-- the window without trying the tour.
mainFrame:HookScript("OnShow", function()
    if EverGearDB.tutorialHintSeen then
        HideHint()
    else
        EverGearDB.tutorialHintSeen = true
        hintClock = 0
        hint:Show()
    end
end)

-- ===== Step popup =====

local POPUP_WIDTH = 270
local POPUP_PAD = 18

-- Pulsing gold frame drawn around whatever the current step is about.
local highlightBox = CreateFrame("Frame", "EverGearTutorialHighlight", UIParent, "BackdropTemplate")
highlightBox:SetFrameStrata("DIALOG")
highlightBox:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
})
highlightBox:SetBackdropBorderColor(THEME.gold[1], THEME.gold[2], THEME.gold[3], 1)
highlightBox:EnableMouse(false)
highlightBox:Hide()

local highlightClock = 0
highlightBox:SetScript("OnUpdate", function(self, elapsed)
    highlightClock = highlightClock + (elapsed or 0)
    self:SetAlpha(0.6 + 0.4 * math.sin(highlightClock * 5))
end)

local popup = CreateFrame("Frame", "EverGearTutorialFrame", UIParent, "BackdropTemplate")
popup:SetSize(POPUP_WIDTH, 140)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(highlightBox:GetFrameLevel() + 5)
popup:SetClampedToScreen(true)
popup:EnableMouse(true)
popup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
popup:Hide()
-- Escape ends the tour, like closing any of the game's own panels.
tinsert(UISpecialFrames, "EverGearTutorialFrame")

local popupTitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popupTitle:SetPoint("TOPLEFT", POPUP_PAD, -POPUP_PAD)
popupTitle:SetPoint("RIGHT", popup, "RIGHT", -34, 0)
popupTitle:SetJustifyH("LEFT")
popupTitle:SetTextColor(unpack(THEME.gold))

local popupBody = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
popupBody:SetPoint("TOPLEFT", popupTitle, "BOTTOMLEFT", 0, -8)
popupBody:SetWidth(POPUP_WIDTH - 2 * POPUP_PAD)
popupBody:SetJustifyH("LEFT")
popupBody:SetWordWrap(true)
popupBody:SetTextColor(unpack(THEME.parchment))

local popupClose = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
popupClose:SetPoint("TOPRIGHT", -4, -4)

local backButton = CreateFrame("Button", "EverGearTutorialBackButton", popup, "UIPanelButtonTemplate")
backButton:SetSize(70, 22)
backButton:SetPoint("BOTTOMLEFT", 16, 16)
backButton:SetText("Back")

local nextButton = CreateFrame("Button", "EverGearTutorialNextButton", popup, "UIPanelButtonTemplate")
nextButton:SetSize(70, 22)
nextButton:SetPoint("BOTTOMRIGHT", -16, 16)
nextButton:SetText("Next")

-- "3 / 12", between the two buttons.
local popupCounter = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
popupCounter:SetPoint("BOTTOM", popup, "BOTTOM", 0, 22)

-- ===== Placement helpers =====

-- How far below the main window's top edge a frame's top edge is (<= 0), or
-- 0 when that can't be worked out (frame not laid out yet).
local function OffsetFromMainTop(frame)
    if not (frame and frame.GetTop) then return 0 end
    local top, mainTop = frame:GetTop(), mainFrame:GetTop()
    if type(top) ~= "number" or type(mainTop) ~= "number" then return 0 end
    return math.min(0, top - mainTop)
end

-- Popup beside the main window, on the given side, level with `target`.
local function PlaceBesideMain(side, target)
    local y = OffsetFromMainTop(target)
    if side == "left" then
        popup:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -8, y)
    else
        popup:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 8, y)
    end
end

-- Popup beside a side window or panel, on its outer side (or below it).
local function PlaceBesideFrame(frame, side)
    if side == "left" then
        popup:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, 0)
    elseif side == "below" then
        popup:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -8)
    else
        popup:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    end
end

local function ShowHighlight(frame, pad)
    highlightBox:ClearAllPoints()
    if not (frame and frame:IsVisible()) then
        highlightBox:Hide()
        return
    end
    pad = pad or 4
    highlightBox:SetPoint("TOPLEFT", frame, "TOPLEFT", -pad, pad)
    highlightBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", pad, -pad)
    highlightClock = 0
    highlightBox:Show()
end

-- Opens `frame` with `opener` unless it's already open, and remembers it on
-- the step so LeaveStep can close it again -- only what the step itself
-- opened, so a window the player already had open is left alone.
local function OpenForStep(step, frame, opener)
    if not frame or frame:IsShown() then return end
    opener()
    if frame:IsShown() then step.opened = frame end
end

-- Calls a button's click handler directly (same as the player clicking it).
local function ClickButton(button)
    local onClick = button and button:GetScript("OnClick")
    if onClick then onClick(button) end
end

-- A slot that has suggested upgrades right now (right column first, so its
-- panel opens on the right, clear of the windows that open on the left);
-- any upgradeable slot if none do.
local SLOT_SEARCH_ORDER = {
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot",
}
local function PickUpgradeSlot()
    local fallback
    for _, slotToken in ipairs(SLOT_SEARCH_ORDER) do
        local btn = Named("EverGearSlotButton_" .. slotToken)
        if btn then
            fallback = fallback or slotToken
            local list = btn.upgradeList
            if type(list) == "table" and #list > 0 then return slotToken end
        end
    end
    return fallback
end

-- Opens the Suggested Upgrades panel on a slot that has some, for the two
-- steps about it.
local function OpenUpgradePanel(step)
    local panel = Named("EverGearDetailPanel")
    local slotToken = PickUpgradeSlot()
    if not (panel and slotToken and EverGear.ShowUpgradeDetail) then return end
    local wasShown = panel:IsShown()
    EverGear:ShowUpgradeDetail(slotToken)
    if not wasShown and panel:IsShown() then step.opened = panel end
    -- Which side of the window it opened on (left-column slots open it on
    -- the left), so the popup can go on its outer side.
    local btn = Named("EverGearSlotButton_" .. slotToken)
    step.panelSide = (btn and btn.side == "left") and "left" or "right"
end

-- Shared shape for the weapon / profession / zone filter steps.
local function FilterPanelStep(buttonName, panelName, title, text, panelSide)
    return {
        title = title,
        text = text,
        target = function() return Named(buttonName) end,
        open = function(step)
            local panel = Named(panelName)
            OpenForStep(step, panel, function() ClickButton(Named(buttonName)) end)
        end,
        place = function(step, target)
            local panel = Named(panelName)
            if IsShownFrame(panel) then
                PlaceBesideFrame(panel, panelSide or "right")
            else
                PlaceBesideMain("right", target)
            end
        end,
    }
end

-- Shared shape for the Wanted / Gear Sets steps.
local function SideWindowStep(buttonName, windowName, toggleName, title, text)
    return {
        title = title,
        text = text,
        target = function()
            if not EverGear[toggleName] then return nil end
            return Named(windowName) and Named(buttonName)
        end,
        open = function(step)
            OpenForStep(step, Named(windowName), function() EverGear:OpenWishlistWindow(toggleName) end)
        end,
        place = function(step, target)
            local window = Named(windowName)
            if IsShownFrame(window) then
                PlaceBesideFrame(window, "left")
            else
                PlaceBesideMain("left", target)
            end
        end,
    }
end

-- ===== Steps =====
-- In the order they're shown. Each one has a title and text, plus:
--   target -- returns the frame the step is about (outlined while it's
--             shown); nil skips the step. Optional: no target = a general
--             step beside the window.
--   open   -- optional, opens whatever the step needs (see OpenForStep).
--   place  -- optional, positions the popup; by default it sits on `side`
--             ("left"/"right") of the main window, level with the target.
--   noHighlight -- don't outline the target (used for whole windows).

local STEPS = {
    {
        title = "Welcome to EverGear",
        text = "EverGear suggests better gear for every slot while you level. "
            .. "This quick tour shows you around. Click Next to go on, or close it at any time.",
        side = "right",
    },
    {
        title = "Your gear slots",
        text = "Each square is one of your equipment slots, showing what you have on. "
            .. "The badge in its corner sums it up: +N means an upgrade is out there (N is how much better it is), "
            .. "BIS means nothing known beats it, and -- means your filters are hiding the upgrades.",
        target = function() return Named("EverGearSlotButton_HeadSlot") end,
        side = "left",
    },
    {
        title = "Suggested Upgrades",
        text = "Click a slot, or rest the mouse on it, to see its best upgrades: "
            .. "where each item comes from and how much better it is than what you have.",
        target = function() return Named("EverGearDetailPanel") end,
        noHighlight = true,
        open = OpenUpgradePanel,
        place = function(step, target)
            if IsShownFrame(target) then
                PlaceBesideFrame(target, step.panelSide)
            else
                PlaceBesideMain("right", target)
            end
        end,
    },
    {
        title = "Want it? Star it",
        text = "Click the star on a suggestion to put that item on your Wanted list. "
            .. "Click it again to take it off.",
        target = function() return Named("EverGearDetailPanel") end,
        noHighlight = true,
        open = OpenUpgradePanel,
        place = function(step, target)
            if IsShownFrame(target) then
                PlaceBesideFrame(target, step.panelSide)
            else
                PlaceBesideMain("right", target)
            end
        end,
    },
    {
        title = "Your character",
        text = "Your character, wearing what you have on. Drag it to turn it around. "
            .. "The eye button above it turns the model off, which can help on slower computers.",
        target = function()
            local model = Named("EverGearCharacterModel")
            if IsShownFrame(model) then return model end
            return Named("EverGearCharacterModelToggle")
        end,
        side = "right",
    },
    {
        title = "Spec and EP profile",
        text = "Pick your spec here: it decides which stats count the most when items are compared. "
            .. "The EP Profile below it holds the exact stat values; Default works well to start with.",
        target = function() return Named("EverGearSpecDropdown") end,
        side = "right",
    },
    {
        title = "Your own EP profiles",
        text = "The note button opens the profile editor, where you can make your own profiles and choose "
            .. "how much each stat is worth. Your profiles then show up in the EP Profile list.",
        target = function() return Named("EverGearProfileEditor") and Named("EverGearProfileEditorButton") end,
        open = function(step)
            OpenForStep(step, Named("EverGearProfileEditor"), function() EverGear:ToggleProfileEditor() end)
        end,
        place = function(step, target)
            local editor = Named("EverGearProfileEditor")
            if IsShownFrame(editor) then
                PlaceBesideFrame(editor, "left")
            else
                PlaceBesideMain("left", target)
            end
        end,
    },
    {
        title = "Look ahead",
        text = "Drag this slider to also see upgrades for levels you haven't reached yet, so you can plan ahead. "
            .. "The round arrow next to it goes back to your current level.",
        target = function() return Named("EverGearLookaheadSlider") end,
        side = "right",
    },
    {
        title = "Where items come from",
        text = "Untick a source to stop seeing items from it, for example crafted items or dungeon drops.",
        target = function()
            local first = EverGear.SOURCE_TYPE_FILTERS and EverGear.SOURCE_TYPE_FILTERS[1]
            return first and Named("EverGearFilter_" .. first.key)
        end,
        -- The two rows of checkboxes, not just the first one.
        highlight = function()
            highlightBox:ClearAllPoints()
            highlightBox:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, -146)
            highlightBox:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", -14, -206)
            highlightClock = 0
            highlightBox:Show()
        end,
        side = "right",
    },
    FilterPanelStep("EverGearWeaponFilterButton", "EverGearWeaponFilterPanel", "Weapon types",
        "Hide weapon types you don't want suggested. Usable Only keeps just the ones your class can use."),
    FilterPanelStep("EverGearProfessionFilterButton", "EverGearProfessionFilterPanel", "Professions",
        "Untick professions you don't have to hide their crafted items. "
            .. "BoE Only still shows the ones you could buy from other players."),
    FilterPanelStep("EverGearZoneFilterButton", "EverGearZoneFilterPanel", "Zones and dungeons",
        "Hide items from zones and dungeons you won't visit. "
            .. "Current Level keeps just the places meant for your level.", "below"),
    SideWindowStep("EverGearWantedButton", "EverGearWantedFrame", "ToggleWantedWindow", "Wanted list",
        "Items you're hunting for on this character, ticked off once you have them. "
            .. "This button opens it any time."),
    SideWindowStep("EverGearSetsButton", "EverGearSetsFrame", "ToggleSetsWindow", "Gear sets",
        "Build gear sets, such as one for tanking and one for dealing damage, and see which pieces you already have. "
            .. "Click a slot in a set to choose an item for it."),
    {
        title = "Alt-click any item",
        text = "Alt-click an item anywhere, in your bags, on your character sheet, in chat or in EverGear, "
            .. "to add it to your Wanted list or a gear set.",
        target = function() return Named("EverGearSlotButton_HeadSlot") end,
        side = "left",
    },
    {
        title = "Preview and link",
        text = "Ctrl-click an item in EverGear to try it on in the dressing room, "
            .. "and Shift-click it to link it in chat.",
        target = function() return Named("EverGearSlotButton_HeadSlot") end,
        side = "left",
    },
    {
        title = "Opening EverGear",
        text = "Click the minimap button to open or close EverGear, and drag it to move it around the minimap. "
            .. "You can also type /eg. Click the ? button to see this tour again.",
        target = function() return Named("EverGearMinimapButton") end,
        place = function(step, target)
            -- Toward the middle of the screen from the minimap button.
            local x = target:GetCenter()
            local screenX = UIParent:GetCenter()
            if type(x) == "number" and type(screenX) == "number" and x < screenX then
                popup:SetPoint("TOPLEFT", target, "BOTTOMRIGHT", 4, -4)
            else
                popup:SetPoint("TOPRIGHT", target, "BOTTOMLEFT", -4, -4)
            end
        end,
    },
}
-- Exposed so the steps can be inspected (and swapped in tests).
EverGear.TutorialSteps = STEPS

-- ===== Running the tour =====

-- The steps this run of the tour uses (those whose target exists when it
-- starts), and which of them is showing.
local activeSteps = {}
local currentIndex
local running = false

-- Closes whatever the current step opened and clears its outline.
local function LeaveStep()
    local step = currentIndex and activeSteps[currentIndex]
    if step then
        if step.opened and step.opened:IsShown() then step.opened:Hide() end
        step.opened = nil
    end
    highlightBox:Hide()
    currentIndex = nil
end

local function GetTarget(step)
    if not step.target then return mainFrame end
    local ok, frame = pcall(step.target, step)
    if ok then return frame end
    return nil
end

-- Shows step `index`; returns false (leaving nothing open) if its target is
-- gone by now, so the caller can move on to the next one instead.
local function EnterStep(index)
    local step = activeSteps[index]
    if not step then return false end
    if step.open then pcall(step.open, step) end
    local target = GetTarget(step)
    if not target then
        if step.opened and step.opened:IsShown() then step.opened:Hide() end
        step.opened = nil
        return false
    end
    currentIndex = index

    popupTitle:SetText(step.title)
    popupBody:SetText(step.text)
    popupCounter:SetText(index .. " / " .. #activeSteps)
    if index > 1 then backButton:Show() else backButton:Hide() end
    nextButton:SetText(index == #activeSteps and "Done" or "Next")
    local bodyHeight = popupBody:GetStringHeight()
    local titleHeight = popupTitle:GetStringHeight()
    if type(bodyHeight) ~= "number" then bodyHeight = 40 end
    if type(titleHeight) ~= "number" then titleHeight = 14 end
    popup:SetHeight(POPUP_PAD + titleHeight + 8 + bodyHeight + 16 + 22 + 16)

    popup:ClearAllPoints()
    if step.place then
        step.place(step, target)
    else
        PlaceBesideMain(step.side, target)
    end

    if step.highlight then
        step.highlight(step, target)
    elseif step.noHighlight or target == mainFrame then
        highlightBox:Hide()
    else
        ShowHighlight(target)
    end

    popup:Show()
    return true
end

-- Moves from the current step in `direction` (+1 / -1), skipping any step
-- whose target has gone missing. Past the last step the tour is finished.
local function Go(direction)
    local from = currentIndex or 0
    LeaveStep()
    local index = from + direction
    while activeSteps[index] do
        if EnterStep(index) then return end
        index = index + direction
    end
    if direction > 0 then
        EverGear:EndTutorial()
    elseif not EnterStep(from) then
        -- nothing earlier to go back to; stay where we were
        EverGear:EndTutorial()
    end
end

function EverGear:StartTutorial()
    DismissHint()
    if running then LeaveStep() end
    if not mainFrame:IsShown() then self:ToggleUI() end

    activeSteps = {}
    for _, step in ipairs(STEPS) do
        if not step.target or GetTarget(step) then table.insert(activeSteps, step) end
    end
    if #activeSteps == 0 then return end

    running = true
    currentIndex = nil
    Go(1)
end

function EverGear:EndTutorial()
    DismissHint()
    if not running then return end
    running = false
    LeaveStep()
    popup:Hide()
end

function EverGear:IsTutorialRunning()
    return running
end

nextButton:SetScript("OnClick", function() Go(1) end)
backButton:SetScript("OnClick", function() Go(-1) end)
popupClose:SetScript("OnClick", function() EverGear:EndTutorial() end)
-- Covers Escape (UISpecialFrames hides the popup directly).
popup:SetScript("OnHide", function()
    if running then EverGear:EndTutorial() end
end)
-- Closing the main window ends the tour too.
mainFrame:HookScript("OnHide", function()
    if running then EverGear:EndTutorial() end
end)

helpButton:SetScript("OnClick", function()
    if running then
        EverGear:EndTutorial()
    else
        EverGear:StartTutorial()
    end
end)
