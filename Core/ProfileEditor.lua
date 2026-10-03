-- Profile editor window (M4). See CUSTOM_EP_PROFILES_PLAN.md. Lets the
-- player create/duplicate/rename/delete/copy custom EP profiles for their
-- current class+spec, and edit every weight field via a generic grid built
-- from EverGear:GetWeightFieldLayout (EPProfiles.lua) -- not hand-laid-out
-- per stat, so a new stat key added to SPEC_PROFILES later just shows up
-- here too.
--
-- Opened via UI.lua's small icon button next to the main window's Profile
-- dropdown (EverGear:ToggleProfileEditor, defined at the bottom of this
-- file). A second, smaller popup (copyPopup, also in this file) handles the
-- cross-spec/cross-class "Copy to..." flow (plan assumption 6).

EverGear = EverGear or {}

-- Duplicated from UI.lua's THEME rather than shared -- that table is a
-- plain local there, not exposed on EverGear, and these are just a handful
-- of color constants, not worth plumbing a cross-file dependency for.
local GOLD = { 1.00, 0.82, 0.20 }
local GOLD_DIM = { 0.78, 0.63, 0.24 }
local PARCHMENT = { 0.90, 0.85, 0.72 }
local PANEL_BG = { 0.05, 0.05, 0.07, 0.85 }
local PANEL_BORDER = { 0.55, 0.45, 0.20, 1.0 }

local EDITOR_WIDTH = 380
-- +14 over the original 480 -- makes room for the class+spec subtitle added
-- under the title (editorSubtitle below), which would otherwise overlap the
-- top of the list panel/weight grid (both anchored at a fixed -40).
local EDITOR_HEIGHT = 494
local LIST_WIDTH = 130
local LIST_ROW_HEIGHT = 20
-- Known limitation: the profile list itself doesn't scroll -- past this many
-- custom profiles for one class+spec, extras exist (GetProfileList still
-- returns them) but have no row to click here yet. Revisit if this turns
-- out to matter in practice; keeps this milestone's scope sane for now.
local MAX_LIST_ROWS = 9

-- ===== Forward declarations =====
-- These are assigned real function bodies further down (after the frames
-- they reference exist), but buttons/popups created before that point still
-- need to be able to call them from their OnClick/OnAccept bodies -- same
-- "local name; ...; name = function" idiom UI.lua already uses for
-- weaponFilterPanel/professionFilterPanel.
local SelectProfileForEditing
local RefreshProfileList
local RefreshWeightGrid
local RefreshButtonStates

-- ===== State =====
-- Which class+spec the editor is currently browsing (defaults to the
-- player's own on open, but "Copy to..." can switch it to a DIFFERENT
-- class+spec -- plan M4's "switches the editor to the newly created copy on
-- the target spec"), which profile within that class+spec is loaded, and a
-- working (mutable, unsaved-until-Save) copy of its weights.
local editorClassToken, editorSpecName, editingProfileId
local workingWeights

-- ===== Frame skeleton =====

local editorFrame = CreateFrame("Frame", "EverGearProfileEditor", UIParent, "BackdropTemplate")
editorFrame:SetSize(EDITOR_WIDTH, EDITOR_HEIGHT)
editorFrame:SetPoint("CENTER")
-- Deliberately NOT movable/draggable -- this is a secondary window that
-- should always stay anchored to (and follow) the main window, per user
-- feedback that dragging it away from EverGearFrame was possible and
-- shouldn't be. EnableMouse(true) is kept so clicks on the backdrop don't
-- fall through to whatever's behind it; it's independent of Movable/drag.
editorFrame:EnableMouse(true)
editorFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
editorFrame:SetFrameStrata("HIGH")
editorFrame:Hide()

local editorTitle = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
editorTitle:SetPoint("TOP", 0, -16)
editorTitle:SetText("EP Profile Editor")
editorTitle:SetTextColor(unpack(GOLD))

-- Which class+spec this window is currently browsing -- NOT necessarily the
-- character's own live spec (see decision note on spec-change below).
-- Without this, there was no way to tell at a glance; added specifically so
-- that independence doesn't read as a bug when the two fall out of sync.
local editorSubtitle = editorFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
editorSubtitle:SetPoint("TOP", editorTitle, "BOTTOM", 0, -2)
editorSubtitle:SetTextColor(unpack(GOLD_DIM))

-- "WARRIOR" -> "Warrior". Classes are always written in Title Case
-- everywhere else in this addon's UI; only SPEC_PROFILES/CLASS_SPECS key
-- them in upper-case tokens.
local function HumanizeClassToken(classToken)
    if not classToken then return "" end
    return classToken:sub(1, 1) .. classToken:sub(2):lower()
end

local editorCloseButton = CreateFrame("Button", nil, editorFrame, "UIPanelCloseButton")
editorCloseButton:SetPoint("TOPRIGHT", -4, -4)

-- ===== Left column: profile list =====

local listPanel = CreateFrame("Frame", nil, editorFrame, "BackdropTemplate")
listPanel:SetPoint("TOPLEFT", 14, -54)
listPanel:SetSize(LIST_WIDTH, MAX_LIST_ROWS * LIST_ROW_HEIGHT + 8)
listPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
listPanel:SetBackdropColor(unpack(PANEL_BG))
listPanel:SetBackdropBorderColor(unpack(PANEL_BORDER))

local profileButtonPool = {}

local function GetOrCreateProfileButton(index)
    local btn = profileButtonPool[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, listPanel)
    btn:SetSize(LIST_WIDTH - 8, LIST_ROW_HEIGHT)
    btn:SetPoint("TOPLEFT", 4, -4 - (index - 1) * LIST_ROW_HEIGHT)

    local highlight = btn:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    btn.highlight = highlight

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 4, 0)
    text:SetPoint("RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    btn.text = text

    btn:SetScript("OnClick", function(self)
        if self.profileId then
            SelectProfileForEditing(self.profileId)
        end
    end)

    profileButtonPool[index] = btn
    return btn
end

-- ===== Left column: CRUD buttons (below the list) =====

local function MakeCrudButton(label, yOffset, onClick)
    local btn = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
    btn:SetSize(LIST_WIDTH, 20)
    btn:SetPoint("TOP", listPanel, "BOTTOM", 0, yOffset)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

local newButton = MakeCrudButton("New", -6, function()
    StaticPopup_Show("EVERGEAR_NEW_PROFILE")
end)
local duplicateButton = MakeCrudButton("Duplicate", -30, function()
    StaticPopup_Show("EVERGEAR_DUPLICATE_PROFILE")
end)
local renameButton = MakeCrudButton("Rename", -54, function()
    if not EverGear:IsBuiltinProfileId(editingProfileId) then StaticPopup_Show("EVERGEAR_RENAME_PROFILE") end
end)
local deleteButton = MakeCrudButton("Delete", -78, function()
    if not EverGear:IsBuiltinProfileId(editingProfileId) then StaticPopup_Show("EVERGEAR_DELETE_PROFILE") end
end)
local copyToButton = MakeCrudButton("Copy to...", -102, function()
    EverGear:ShowCopyProfilePopup(editorClassToken, editorSpecName, editingProfileId, workingWeights)
end)
-- M5: export/import as JSON (see CUSTOM_EP_PROFILES_PLAN.md). Export sends
-- whatever's currently in the grid, same as Duplicate -- including any
-- not-yet-saved edits ("export this" means what's on screen, not last-saved).
local exportButton = MakeCrudButton("Export...", -126, function()
    EverGear:ShowExportProfilePopup(editorClassToken, editorSpecName, editingProfileId, workingWeights)
end)
local importButton = MakeCrudButton("Import...", -150, function()
    EverGear:ShowImportProfilePopup(editorClassToken, editorSpecName)
end)

-- ===== Right column: weight grid (scrollable) =====

local GRID_X = 14 + LIST_WIDTH + 14
local GRID_HEIGHT = EDITOR_HEIGHT - 110
-- -34 from editorFrame's right edge leaves room for
-- UIPanelScrollFrameTemplate's scrollbar, which sits just outside/beside
-- the scrollFrame's own right edge.
local GRID_WIDTH = EDITOR_WIDTH - 34 - GRID_X

local scrollFrame = CreateFrame("ScrollFrame", "EverGearProfileEditorScroll", editorFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", GRID_X, -54)
scrollFrame:SetSize(GRID_WIDTH, GRID_HEIGHT)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
-- Width fixed to the scrollFrame's own (OnSizeChanged is a safety net, not
-- the primary path, in case this client's event timing doesn't fire it for
-- the initial anchor-derived size -- this window doesn't resize anyway, so
-- it should rarely matter either way); height is recomputed by
-- RefreshWeightGrid every time the row count changes.
scrollChild:SetSize(GRID_WIDTH, 1)
scrollFrame:SetScript("OnSizeChanged", function(self, width, height)
    scrollChild:SetWidth(width)
end)

local ROW_HEIGHT = 18
-- Extra vertical gap between consecutive stat rows within a section (on top
-- of ROW_HEIGHT itself) -- added per user feedback that the grid felt too
-- cramped. Started at 1px, bumped to 5px per follow-up feedback.
local ROW_GAP = 5
local SECTION_GAP = 6
local gridRowPool = {}

-- Only digits and a single '.' survive, and at most the first 2 DIGIT
-- characters typed (the '.' doesn't count toward that limit) -- per the
-- feature spec: "only numbers and decimal point", "each digit after the
-- 2nd is ignored". Final range/step clamping (0-5, nearest 0.1) happens
-- separately on commit, via EverGear:ClampWeight -- this is just keeping
-- the text itself sane while typing.
local function SanitizeWeightText(text)
    local digitsSeen = 0
    local sawDot = false
    local out = {}
    for i = 1, #text do
        local c = text:sub(i, i)
        if c:match("%d") then
            if digitsSeen < 2 then
                table.insert(out, c)
                digitsSeen = digitsSeen + 1
            end
        elseif c == "." and not sawDot then
            table.insert(out, c)
            sawDot = true
        end
    end
    return table.concat(out)
end

local function GetOrCreateGridRow(index)
    local row = gridRowPool[index]
    if row then return row end

    row = CreateFrame("Frame", nil, scrollChild)
    row:SetSize(1, ROW_HEIGHT)

    local headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", 2, 0)
    headerText:SetTextColor(unpack(GOLD))
    row.headerText = headerText

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 4, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(PARCHMENT))
    row.label = label

    local editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    editBox:SetSize(44, 16)
    editBox:SetPoint("RIGHT", -8, 0)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH("CENTER")
    row.editBox = editBox

    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local sanitized = SanitizeWeightText(self:GetText())
        if sanitized ~= self:GetText() then
            self:SetText(sanitized)
        end
    end)

    -- Closes over `row` (this specific pooled row, reused across refreshes
    -- for different fields) rather than any one field directly -- row.
    -- fieldKey/row.sectionSubtable/row.isReadOnly get updated in place by
    -- RefreshWeightGrid every time this row is repurposed.
    local function CommitRowValue(self)
        if row.isReadOnly then return end
        local value = EverGear:ClampWeight(tonumber(self:GetText()) or 0)
        if row.sectionSubtable then
            row.sectionSubtable[row.fieldKey] = value
        else
            workingWeights[row.fieldKey] = value
        end
        self:SetText(tostring(value))
        self:ClearFocus()
    end
    editBox:SetScript("OnEnterPressed", CommitRowValue)
    editBox:SetScript("OnEditFocusLost", CommitRowValue)

    gridRowPool[index] = row
    return row
end

-- ===== Save button =====

local saveButton = CreateFrame("Button", nil, editorFrame, "UIPanelButtonTemplate")
saveButton:SetSize(100, 22)
saveButton:SetPoint("BOTTOMRIGHT", -14, 14)
saveButton:SetText("Save")
saveButton:SetScript("OnClick", function()
    if EverGear:IsBuiltinProfileId(editingProfileId) then return end
    local ok, err = EverGear:SaveCustomProfile(editorClassToken, editorSpecName, editingProfileId, workingWeights)
    if not ok then
        UIErrorsFrame:AddMessage(err or "Couldn't save profile.", 1, 0.2, 0.2)
        return
    end
    EverGear:RefreshUI()
end)

-- ===== Function bodies (forward-declared above) =====

RefreshProfileList = function()
    local profiles = EverGear:GetProfileList(editorClassToken, editorSpecName)
    for i, profile in ipairs(profiles) do
        if i > MAX_LIST_ROWS then break end
        local btn = GetOrCreateProfileButton(i)
        btn.profileId = profile.id
        btn.text:SetText(profile.name)
        local selected = (profile.id == editingProfileId)
        btn.text:SetTextColor(unpack(selected and GOLD or PARCHMENT))
        btn.highlight:SetShown(selected)
        btn:Show()
    end
    for i = math.min(#profiles, MAX_LIST_ROWS) + 1, #profileButtonPool do
        profileButtonPool[i]:Hide()
    end
end

RefreshWeightGrid = function()
    local sections = EverGear:GetWeightFieldLayout(workingWeights)
    local isReadOnly = EverGear:IsBuiltinProfileId(editingProfileId)

    local rowIndex = 0
    local y = -4
    for _, section in ipairs(sections) do
        rowIndex = rowIndex + 1
        local headerRow = GetOrCreateGridRow(rowIndex)
        headerRow:ClearAllPoints()
        headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
        headerRow:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        headerRow.headerText:SetText(section.title)
        headerRow.headerText:Show()
        headerRow.label:Hide()
        headerRow.editBox:Hide()
        headerRow:Show()
        y = y - ROW_HEIGHT - SECTION_GAP

        for _, field in ipairs(section.fields) do
            rowIndex = rowIndex + 1
            local row = GetOrCreateGridRow(rowIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            row.headerText:Hide()
            row.label:SetText(field.label)
            row.label:Show()

            -- A field carries its own subtable when it has one (Core's stat
            -- rows all point at weights.stats even though Core's armor/DPS
            -- rows don't), falling back to the section's shared one
            -- (Secondary Stats) otherwise.
            local fieldSubtable = field.subtable or section.subtable
            row.sectionSubtable = fieldSubtable
            row.fieldKey = field.key
            row.isReadOnly = isReadOnly

            local currentValue = fieldSubtable and fieldSubtable[field.key] or workingWeights[field.key] or 0
            row.editBox:SetText(tostring(currentValue))
            -- Enable()/Disable(), not SetEnabled(bool) -- the latter is a
            -- newer convenience wrapper that may not exist on every client
            -- era this addon's Interface number could run on; the pair
            -- below has worked since vanilla.
            if isReadOnly then row.editBox:Disable() else row.editBox:Enable() end
            -- Read-only (viewing "Default") still shows every value, just
            -- dimmed and uneditable -- not hidden, since seeing the builtin
            -- numbers is exactly what someone deciding whether to
            -- Duplicate wants.
            row.editBox:SetAlpha(isReadOnly and 0.6 or 1.0)
            row.editBox:Show()
            row:Show()
            y = y - ROW_HEIGHT - ROW_GAP
        end
        y = y - SECTION_GAP
    end

    for i = rowIndex + 1, #gridRowPool do
        gridRowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(1, -y))
end

RefreshButtonStates = function()
    local isDefault = EverGear:IsBuiltinProfileId(editingProfileId)
    local buttons = { renameButton, deleteButton, saveButton }
    for _, btn in ipairs(buttons) do
        if isDefault then btn:Disable() else btn:Enable() end
    end
end

SelectProfileForEditing = function(profileId)
    local weights = EverGear:GetProfileWeights(editorClassToken, editorSpecName, profileId)
    if not weights then
        -- Deleted (e.g. from another character sharing this account-wide
        -- profile) since the list was last refreshed -- fall back rather
        -- than leaving the grid pointed at nothing.
        profileId = EverGear:GetDefaultProfileId(editorClassToken, editorSpecName)
        weights = EverGear:GetBuiltinProfile(editorClassToken, editorSpecName, profileId)
    end
    editingProfileId = profileId
    -- GetProfileWeights/GetBuiltinProfile always return a fresh, independent
    -- table -- safe to treat as a mutable working copy without touching
    -- anything persisted until Save.
    workingWeights = weights

    editorSubtitle:SetText(HumanizeClassToken(editorClassToken) .. " - " .. editorSpecName)

    RefreshProfileList()
    RefreshWeightGrid()
    RefreshButtonStates()
end

-- ===== New / Duplicate / Rename / Delete popups =====

StaticPopupDialogs["EVERGEAR_NEW_PROFILE"] = {
    text = "New EP profile name:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = self.EditBox or self.editBox
        editBox:SetText("")
        editBox:SetFocus()
    end,
    OnAccept = function(self)
        local editBox = self.EditBox or self.editBox
        local name = editBox:GetText()
        if name == "" then return end
        local defaults = EverGear:GetBuiltinProfile(editorClassToken, editorSpecName)
        local id = EverGear:CreateCustomProfile(editorClassToken, editorSpecName, name, defaults)
        SelectProfileForEditing(id)
        if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["EVERGEAR_DUPLICATE_PROFILE"] = {
    text = "Name for the duplicate:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = self.EditBox or self.editBox
        local profiles = EverGear:GetProfileList(editorClassToken, editorSpecName)
        local currentName = "Profile"
        for _, p in ipairs(profiles) do
            if p.id == editingProfileId then currentName = p.name end
        end
        editBox:SetText(currentName .. " (Copy)")
        editBox:HighlightText()
        editBox:SetFocus()
    end,
    OnAccept = function(self)
        local editBox = self.EditBox or self.editBox
        local name = editBox:GetText()
        if name == "" then return end
        -- Duplicates whatever's currently in the grid, including any
        -- not-yet-saved edits -- "duplicate this" means what's on screen.
        local id = EverGear:CreateCustomProfile(editorClassToken, editorSpecName, name, workingWeights)
        SelectProfileForEditing(id)
        if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["EVERGEAR_RENAME_PROFILE"] = {
    text = "Rename profile to:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = self.EditBox or self.editBox
        local profiles = EverGear:GetProfileList(editorClassToken, editorSpecName)
        for _, p in ipairs(profiles) do
            if p.id == editingProfileId then editBox:SetText(p.name) end
        end
        editBox:HighlightText()
        editBox:SetFocus()
    end,
    OnAccept = function(self)
        local editBox = self.EditBox or self.editBox
        local name = editBox:GetText()
        if name == "" then return end
        EverGear:RenameCustomProfile(editorClassToken, editorSpecName, editingProfileId, name)
        RefreshProfileList()
        if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["EVERGEAR_DELETE_PROFILE"] = {
    text = "Delete this EP profile? This can't be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        EverGear:DeleteCustomProfile(editorClassToken, editorSpecName, editingProfileId)
        SelectProfileForEditing(EverGear:GetDefaultProfileId(editorClassToken, editorSpecName))
        if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
        EverGear:RefreshUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ===== "Copy to..." popup (plan assumption 6) =====

local copyPopup = CreateFrame("Frame", "EverGearCopyProfilePopup", UIParent, "BackdropTemplate")
copyPopup:SetSize(260, 190)
copyPopup:SetPoint("CENTER")
copyPopup:SetFrameStrata("DIALOG")
copyPopup:EnableMouse(true)
copyPopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
copyPopup:Hide()

local copyTitle = copyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
copyTitle:SetPoint("TOP", 0, -14)
copyTitle:SetText("Copy Profile To")
copyTitle:SetTextColor(unpack(GOLD))

local copyCloseButton = CreateFrame("Button", nil, copyPopup, "UIPanelCloseButton")
copyCloseButton:SetPoint("TOPRIGHT", -2, -2)

local copyClassLabel = copyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
copyClassLabel:SetPoint("TOP", 0, -34)
copyClassLabel:SetText("Class")
copyClassLabel:SetTextColor(unpack(GOLD_DIM))

local copyClassDropdown = CreateFrame("Frame", "EverGearCopyClassDropdown", copyPopup, "UIDropDownMenuTemplate")
copyClassDropdown:SetPoint("TOP", copyClassLabel, "BOTTOM", 8, -2)
UIDropDownMenu_SetWidth(copyClassDropdown, 150)

local copySpecLabel = copyPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
copySpecLabel:SetPoint("TOP", copyClassDropdown, "BOTTOM", -8, -4)
copySpecLabel:SetText("Spec")
copySpecLabel:SetTextColor(unpack(GOLD_DIM))

local copySpecDropdown = CreateFrame("Frame", "EverGearCopySpecDropdown", copyPopup, "UIDropDownMenuTemplate")
copySpecDropdown:SetPoint("TOP", copySpecLabel, "BOTTOM", 8, -2)
UIDropDownMenu_SetWidth(copySpecDropdown, 150)

local copyNameEditBox = CreateFrame("EditBox", nil, copyPopup, "InputBoxTemplate")
copyNameEditBox:SetSize(170, 20)
copyNameEditBox:SetPoint("TOP", copySpecDropdown, "BOTTOM", 0, -16)
copyNameEditBox:SetAutoFocus(false)

local copyConfirmButton = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
copyConfirmButton:SetSize(100, 20)
copyConfirmButton:SetPoint("BOTTOM", 0, 14)
copyConfirmButton:SetText("Copy")

-- Fixed, friendly-ordered list rather than iterating CLASS_SPECS (pairs()
-- order over it isn't guaranteed stable either).
local CLASS_DISPLAY_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_DISPLAY_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local copySourceClass, copySourceSpec, copySourceProfileId, copySourceWeights
local copyTargetClass, copyTargetSpec

local function RefreshCopySpecDropdown()
    UIDropDownMenu_Initialize(copySpecDropdown, function()
        local specs = EverGear.CLASS_SPECS[copyTargetClass] or {}
        for _, spec in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spec.name
            info.value = spec.name
            info.func = function(self)
                copyTargetSpec = self.value
                UIDropDownMenu_SetSelectedValue(copySpecDropdown, self.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    local specs = EverGear.CLASS_SPECS[copyTargetClass] or {}
    -- Defaults to the first spec that ISN'T the source spec (copying a
    -- profile onto itself is what Duplicate is for) -- falls back to the
    -- first spec outright if that's somehow the only one.
    copyTargetSpec = specs[1] and specs[1].name
    for _, spec in ipairs(specs) do
        if spec.name ~= copySourceSpec then
            copyTargetSpec = spec.name
            break
        end
    end
    UIDropDownMenu_SetSelectedValue(copySpecDropdown, copyTargetSpec)
end

UIDropDownMenu_Initialize(copyClassDropdown, function()
    for _, classToken in ipairs(CLASS_DISPLAY_ORDER) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = CLASS_DISPLAY_NAMES[classToken]
        info.value = classToken
        info.func = function(self)
            copyTargetClass = self.value
            UIDropDownMenu_SetSelectedValue(copyClassDropdown, self.value)
            RefreshCopySpecDropdown()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

copyConfirmButton:SetScript("OnClick", function()
    local name = copyNameEditBox:GetText()
    if name == "" then name = "Copied Profile" end
    local id, err = EverGear:CopyProfile(copySourceClass, copySourceSpec, copySourceProfileId, copyTargetClass, copyTargetSpec, name)
    if not id then
        UIErrorsFrame:AddMessage(err or "Couldn't copy profile.", 1, 0.2, 0.2)
        return
    end
    copyPopup:Hide()
    -- Switches the editor itself to the target class+spec+new profile, per
    -- the plan's M4 spec -- the player was just looking at the source, the
    -- natural next thing to look at is what they made from it.
    editorClassToken = copyTargetClass
    editorSpecName = copyTargetSpec
    SelectProfileForEditing(id)
    if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
end)

function EverGear:ShowCopyProfilePopup(fromClass, fromSpec, fromProfileId, fromWeights)
    copySourceClass, copySourceSpec, copySourceProfileId, copySourceWeights = fromClass, fromSpec, fromProfileId, fromWeights
    copyTargetClass = fromClass
    UIDropDownMenu_SetSelectedValue(copyClassDropdown, fromClass)
    RefreshCopySpecDropdown()

    local profiles = EverGear:GetProfileList(fromClass, fromSpec)
    local sourceName = "Profile"
    for _, p in ipairs(profiles) do
        if p.id == fromProfileId then sourceName = p.name end
    end
    copyNameEditBox:SetText(sourceName)
    copyPopup:Show()
end

-- ===== Export / Import popups (M5) =====
-- See CUSTOM_EP_PROFILES_PLAN.md M5 and plan assumption 3: WoW addons have no
-- filesystem access, so "export/import a JSON file" is copy/paste text via a
-- selectable multi-line EditBox, not a real file picker. Both popups share a
-- small scrolling-multiline-EditBox panel builder since the only real
-- difference between them is editable-vs-read-only and the buttons below it.

local function CreateScrollingTextPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(unpack(PANEL_BG))
    panel:SetBackdropBorderColor(unpack(PANEL_BORDER))

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    -- -26 on the right leaves room for this template's scrollbar, same
    -- reasoning as the weight grid's own GRID_WIDTH margin above.
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(width - 36)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    return panel, editBox
end

-- ----- Export -----

local exportPopup = CreateFrame("Frame", "EverGearExportProfilePopup", UIParent, "BackdropTemplate")
exportPopup:SetSize(420, 320)
exportPopup:SetPoint("CENTER")
exportPopup:SetFrameStrata("DIALOG")
exportPopup:EnableMouse(true)
exportPopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
exportPopup:Hide()

local exportTitle = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
exportTitle:SetPoint("TOP", 0, -14)
exportTitle:SetText("Export Profile")
exportTitle:SetTextColor(unpack(GOLD))

local exportCloseButton = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
exportCloseButton:SetPoint("TOPRIGHT", -2, -2)

local exportSubtitle = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
exportSubtitle:SetPoint("TOP", exportTitle, "BOTTOM", 0, -4)
exportSubtitle:SetTextColor(unpack(GOLD_DIM))

local exportHint = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
exportHint:SetPoint("TOP", exportSubtitle, "BOTTOM", 0, -8)
exportHint:SetWidth(380)
exportHint:SetJustifyH("CENTER")
exportHint:SetText("Already selected -- press Ctrl+C to copy, then paste it into a file of your own.")
exportHint:SetTextColor(unpack(PARCHMENT))

local exportBoxPanel, exportEditBox = CreateScrollingTextPanel(exportPopup, 388, 190)
exportBoxPanel:SetPoint("TOP", exportHint, "BOTTOM", 0, -10)

-- Read-only in effect: any attempted edit snaps the text back to the stored
-- export string. Still focusable/selectable so Ctrl+A/Ctrl+C keep working --
-- an EditBox:Disable()'d box can't be focused at all in this client, which
-- would break copying, so this is done via a text-revert instead of Disable.
local currentExportText = ""
exportEditBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self:GetText() ~= currentExportText then
        self:SetText(currentExportText)
        self:HighlightText()
    end
end)

local exportDoneButton = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
exportDoneButton:SetSize(100, 22)
exportDoneButton:SetPoint("BOTTOM", 0, 14)
exportDoneButton:SetText("Done")
exportDoneButton:SetScript("OnClick", function() exportPopup:Hide() end)

function EverGear:ShowExportProfilePopup(classToken, specName, profileId, weights)
    local profiles = self:GetProfileList(classToken, specName)
    local profileName = "Profile"
    for _, p in ipairs(profiles) do
        if p.id == profileId then profileName = p.name end
    end
    exportSubtitle:SetText(HumanizeClassToken(classToken) .. " - " .. specName .. " - " .. profileName)
    currentExportText = self:SerializeProfile(classToken, specName, profileName, weights)
    exportEditBox:SetText(currentExportText)
    exportPopup:Show()
    exportEditBox:SetFocus()
    exportEditBox:HighlightText()
end

-- ----- Import -----

local importPopup = CreateFrame("Frame", "EverGearImportProfilePopup", UIParent, "BackdropTemplate")
importPopup:SetSize(420, 320)
importPopup:SetPoint("CENTER")
importPopup:SetFrameStrata("DIALOG")
importPopup:EnableMouse(true)
importPopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
importPopup:Hide()

local importTitle = importPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
importTitle:SetPoint("TOP", 0, -14)
importTitle:SetText("Import Profile")
importTitle:SetTextColor(unpack(GOLD))

local importCloseButton = CreateFrame("Button", nil, importPopup, "UIPanelCloseButton")
importCloseButton:SetPoint("TOPRIGHT", -2, -2)

-- Target is always the editor's CURRENT class+spec (wherever it's browsing,
-- same as New/Duplicate/Paste-equivalent actions) -- shown here so it's
-- never a surprise which class+spec the imported profile lands on, same
-- reasoning as editorSubtitle on the main editor frame.
local importSubtitle = importPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
importSubtitle:SetPoint("TOP", importTitle, "BOTTOM", 0, -4)
importSubtitle:SetTextColor(unpack(GOLD_DIM))

local importHint = importPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
importHint:SetPoint("TOP", importSubtitle, "BOTTOM", 0, -8)
importHint:SetWidth(380)
importHint:SetJustifyH("CENTER")
importHint:SetText("Paste exported profile JSON below, then click Import.")
importHint:SetTextColor(unpack(PARCHMENT))

local importBoxPanel, importEditBox = CreateScrollingTextPanel(importPopup, 388, 160)
importBoxPanel:SetPoint("TOP", importHint, "BOTTOM", 0, -10)

local importErrorText = importPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
importErrorText:SetPoint("TOP", importBoxPanel, "BOTTOM", 0, -8)
importErrorText:SetWidth(380)
importErrorText:SetJustifyH("CENTER")
importErrorText:SetTextColor(1, 0.3, 0.3)

local importCancelButton = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
importCancelButton:SetSize(100, 22)
importCancelButton:SetPoint("BOTTOMLEFT", 90, 14)
importCancelButton:SetText("Cancel")
importCancelButton:SetScript("OnClick", function() importPopup:Hide() end)

local importImportButton = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
importImportButton:SetSize(100, 22)
importImportButton:SetPoint("BOTTOMRIGHT", -90, 14)
importImportButton:SetText("Import")

-- Holds the already-validated weights between the Import click (which parses
-- the JSON) and the name-collision follow-up popup's OnAccept, if that one's
-- needed -- see EVERGEAR_IMPORT_NAME_COLLISION below.
local pendingImportWeights

local function ImportNameCollides(classToken, specName, name)
    local profiles = EverGear:GetProfileList(classToken, specName)
    for _, p in ipairs(profiles) do
        if p.name == name then return true end
    end
    return false
end

local function FinishImport(name, weights)
    local id = EverGear:ImportProfileWeights(editorClassToken, editorSpecName, name, weights)
    importPopup:Hide()
    SelectProfileForEditing(id)
    if EverGear.RefreshProfileDropdown then EverGear.RefreshProfileDropdown() end
end

StaticPopupDialogs["EVERGEAR_IMPORT_NAME_COLLISION"] = {
    text = "A profile named \"%s\" already exists for %s. Name the imported profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = self.EditBox or self.editBox
        editBox:SetText((self.data and self.data.suggestedName) or "Imported Profile")
        editBox:HighlightText()
        editBox:SetFocus()
    end,
    OnAccept = function(self)
        local editBox = self.EditBox or self.editBox
        local name = editBox:GetText()
        if name == "" or not pendingImportWeights then return end
        FinishImport(name, pendingImportWeights)
        pendingImportWeights = nil
    end,
    OnCancel = function() pendingImportWeights = nil end,
    EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

importImportButton:SetScript("OnClick", function()
    local data, err = EverGear:DeserializeProfile(importEditBox:GetText())
    if not data then
        importErrorText:SetText(err or "Couldn't import that profile.")
        return
    end
    importErrorText:SetText("")
    local name = data.name or "Imported Profile"
    if ImportNameCollides(editorClassToken, editorSpecName, name) then
        pendingImportWeights = data.weights
        importPopup:Hide()
        StaticPopup_Show(
            "EVERGEAR_IMPORT_NAME_COLLISION",
            name,
            HumanizeClassToken(editorClassToken) .. " " .. editorSpecName,
            { suggestedName = name .. " (Imported)" }
        )
    else
        FinishImport(name, data.weights)
    end
end)

function EverGear:ShowImportProfilePopup(classToken, specName)
    importSubtitle:SetText(HumanizeClassToken(classToken) .. " - " .. specName)
    importEditBox:SetText("")
    importErrorText:SetText("")
    importPopup:Show()
    importEditBox:SetFocus()
end

-- ===== Public entry point (called from UI.lua's button) =====

function EverGear:ToggleProfileEditor()
    if editorFrame:IsShown() then
        editorFrame:Hide()
        return
    end
    local playerInfo = self:GetPlayerInfo()
    local charDB = self:GetCharDB()
    editorClassToken = playerInfo.classToken
    editorSpecName = charDB.spec
    SelectProfileForEditing(charDB.profileId or self:GetDefaultProfileId(editorClassToken, editorSpecName))

    editorFrame:ClearAllPoints()
    if EverGearFrame then
        -- Opens to the LEFT of the main window now, not the right -- per
        -- user feedback (matches the profile editor button's new position,
        -- to the left of the Profile dropdown it opens). UI.lua's
        -- ShowUpgradeDetail checks whether this frame is shown and anchors
        -- the upgrade-suggestions detail panel below it (not beside
        -- mainFrame directly) specifically so the two windows don't land on
        -- top of each other now that both can appear on this same side.
        editorFrame:SetPoint("TOPRIGHT", EverGearFrame, "TOPLEFT", -8, 0)
    else
        editorFrame:SetPoint("CENTER")
    end
    editorFrame:Show()
    -- Hides a detail panel left open from an earlier left-slot item click --
    -- it was anchored beside mainFrame directly (no editor open yet at the
    -- time), which the editor now sits on top of/in front of. The player
    -- re-clicking the item re-opens it correctly anchored below this window
    -- (see UI.lua's ShowUpgradeDetail).
    if EverGear.HideUpgradeDetail then EverGear:HideUpgradeDetail() end
end

-- Called by UI.lua's Spec dropdown (SpecDropdown_OnClick) whenever the
-- player's LIVE spec changes, passing the spec it was on just before and the
-- one it's on now -- see CUSTOM_EP_PROFILES_PLAN.md's "changing spec while
-- the editor is open" decision and its follow-up revision.
--
-- Only follows the live spec change if the editor was showing the spec that
-- was JUST live (i.e. nobody has navigated it elsewhere via "Copy to..." --
-- editorClassToken/editorSpecName would then point at that other class+spec
-- instead). That preserves the original reason the editor doesn't just
-- mirror the main window's dropdown: an active "Copy to..." comparison
-- shouldn't be yanked out from under the player by an unrelated spec change
-- in the main window. But the far more common case -- the editor is open on
-- whatever's live, same as it was opened on -- previously left it stuck on
-- the old spec until closed and reopened, which this fixes by re-pointing it
-- at the new spec's own Default profile, same as a fresh ToggleProfileEditor
-- open would.
function EverGear:NotifyLiveSpecChanged(oldSpecName, newSpecName)
    if not editorFrame:IsShown() then return end
    local playerInfo = self:GetPlayerInfo()
    if editorClassToken == playerInfo.classToken and editorSpecName == oldSpecName then
        editorSpecName = newSpecName
        SelectProfileForEditing(self:GetDefaultProfileId(editorClassToken, editorSpecName))
    end
end
