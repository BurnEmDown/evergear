-- Windows for the per-character wanted list and gear sets (data in
-- Wishlist.lua), plus the menu behind the star on each Suggested Upgrades row.
--
-- Both windows open to the LEFT of the main window, the same spot as the EP
-- profile editor, and only one of the three is shown at a time. Shared visual
-- helpers (icon frames, quality colors, theme) come from UI.lua through
-- EverGear.UIHelpers, so these look the same as the rest of the addon.

EverGear = EverGear or {}

local H = EverGear.UIHelpers
local THEME = H.THEME

local WANTED_WIDTH, WANTED_HEIGHT = 320, 400
local WANTED_ROW_HEIGHT = 44
local SETS_WIDTH, SETS_HEIGHT = 300, 484
local SET_ICON_SIZE = 32
local SET_ROW_SPACING = 38

local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local REMOVE_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function Tooltip(owner, title, line)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

local function CreateWindow(name, width, height, titleText)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText(titleText)
    title:SetTextColor(unpack(THEME.gold))
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    return frame
end

local wantedFrame = CreateWindow("EverGearWantedFrame", WANTED_WIDTH, WANTED_HEIGHT, "Wanted")
local setsFrame = CreateWindow("EverGearSetsFrame", SETS_WIDTH, SETS_HEIGHT, "Gear Sets")

-- Opens one of the side windows beside the main window, closing the other
-- side windows that share that spot.
local function ShowSideWindow(frame)
    for _, other in ipairs({ wantedFrame, setsFrame, EverGearProfileEditor }) do
        if other and other ~= frame then other:Hide() end
    end
    EverGear:HideUpgradeDetail()
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", EverGear.Frame, "TOPLEFT", -8, 0)
    frame:Show()
end

-- The profile editor opens in the same spot, so it closes these two.
if EverGearProfileEditor then
    EverGearProfileEditor:HookScript("OnShow", function()
        wantedFrame:Hide()
        setsFrame:Hide()
    end)
end

-- ===== Wanted window =====

local wantedEmpty = wantedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
wantedEmpty:SetPoint("TOPLEFT", 24, -56)
wantedEmpty:SetPoint("RIGHT", -24, 0)
wantedEmpty:SetJustifyH("LEFT")
wantedEmpty:SetWordWrap(true)
wantedEmpty:SetTextColor(unpack(THEME.parchment))
wantedEmpty:SetText("Nothing here yet.\n\nClick the star next to an item in Suggested Upgrades to add it to this character's wanted list.")

local wantedScroll = CreateFrame("ScrollFrame", "EverGearWantedScroll", wantedFrame, "UIPanelScrollFrameTemplate")
wantedScroll:SetPoint("TOPLEFT", 18, -44)
wantedScroll:SetPoint("BOTTOMRIGHT", -36, 18)
local wantedList = CreateFrame("Frame", nil, wantedScroll)
wantedList:SetSize(WANTED_WIDTH - 54, 10)
wantedScroll:SetScrollChild(wantedList)

local wantedRows = {}

local function CreateRowButton(parent, texture, title, line, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self) Tooltip(self, title, line) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) onClick(self:GetParent().itemId) end)
    return b
end

local function GetOrCreateWantedRow(index)
    if wantedRows[index] then return wantedRows[index] end
    local row = CreateFrame("Frame", nil, wantedList)
    row:SetSize(WANTED_WIDTH - 54, WANTED_ROW_HEIGHT)

    local icon = H.CreateItemIconFrame(nil, row, 32)
    icon:SetPoint("TOPLEFT", 0, -2)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(H.BuildItemLink(self:GetParent().itemId))
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.icon = icon

    row.removeButton = CreateRowButton(row, REMOVE_TEXTURE, "No longer interested",
        "Take it off the wanted list.", function(itemId) EverGear:RemoveWanted(itemId) end)
    row.removeButton:SetPoint("TOPRIGHT", 0, -4)
    row.acquiredButton = CreateRowButton(row, CHECK_TEXTURE, "Acquired",
        "Mark it as acquired and take it off the wanted list.", function(itemId) EverGear:SetAcquired(itemId, true) end)
    row.acquiredButton:SetPoint("RIGHT", row.removeButton, "LEFT", -4, 0)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetPoint("RIGHT", row.acquiredButton, "LEFT", -6, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.nameText = name

    local source = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    source:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    source:SetJustifyH("LEFT")
    source:SetWordWrap(true)
    source:SetTextColor(0.7, 0.7, 0.7)
    row.sourceText = source

    wantedRows[index] = row
    return row
end

local function RefreshWantedWindow()
    local list = EverGear:GetWantedList()
    wantedFrame.title:SetText("Wanted (" .. #list .. ")")
    wantedEmpty:SetShown(#list == 0)
    wantedScroll:SetShown(#list > 0)

    for i, entry in ipairs(list) do
        local row = GetOrCreateWantedRow(i)
        row.itemId = entry.itemId
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * WANTED_ROW_HEIGHT)
        row:Show()

        local item = EverGear:GetItem(entry.itemId)
        local _, _, quality = H.SafeGetItemInfo(entry.itemId)
        local r, g, b = H.GetQualityColor(quality)
        H.SetIconTexture(row.icon, H.SafeGetItemIcon(entry.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetBackdropBorderColor(r, g, b, 1)
        row.nameText:SetText(EverGear:GetWishlistItemName(entry.itemId, entry.name))
        row.nameText:SetTextColor(r, g, b)

        local slotName = EverGear.FRIENDLY_SLOT_NAMES[entry.slot or ""]
        local source = item and EverGear:GetSourceSummary(item) or "Unknown source"
        row.sourceText:SetText((slotName and (slotName .. " - ") or "") .. source)
    end
    for i = #list + 1, #wantedRows do wantedRows[i]:Hide() end
    wantedList:SetHeight(math.max(10, #list * WANTED_ROW_HEIGHT))
end

wantedFrame:SetScript("OnShow", RefreshWantedWindow)

-- ===== Gear sets window =====

local setPicker = CreateFrame("Frame", "EverGearSetPicker", setsFrame, "UIDropDownMenuTemplate")
setPicker:SetPoint("TOPLEFT", 4, -40)
UIDropDownMenu_SetWidth(setPicker, 150)

local function CreateSmallButton(text, width, onClick)
    local b = CreateFrame("Button", nil, setsFrame, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local newSetButton = CreateSmallButton("New", 50, function() StaticPopup_Show("EVERGEAR_NEW_SET") end)
newSetButton:SetPoint("LEFT", setPicker, "RIGHT", -8, 2)
local renameSetButton = CreateSmallButton("Rename", 64, function()
    local index = EverGear:GetActiveSetIndex()
    if index then StaticPopup_Show("EVERGEAR_RENAME_SET", nil, nil, index) end
end)
renameSetButton:SetPoint("TOPLEFT", setPicker, "BOTTOMLEFT", 20, -2)
local deleteSetButton = CreateSmallButton("Delete", 64, function()
    local index = EverGear:GetActiveSetIndex()
    local set = index and EverGear:GetSets()[index]
    if set then StaticPopup_Show("EVERGEAR_DELETE_SET", set.name, nil, index) end
end)
deleteSetButton:SetPoint("LEFT", renameSetButton, "RIGHT", 6, 0)

local setProgress = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
setProgress:SetPoint("LEFT", deleteSetButton, "RIGHT", 12, 0)
setProgress:SetTextColor(unpack(THEME.parchment))

local setsEmpty = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
setsEmpty:SetPoint("TOPLEFT", 24, -110)
setsEmpty:SetPoint("RIGHT", -24, 0)
setsEmpty:SetJustifyH("LEFT")
setsEmpty:SetWordWrap(true)
setsEmpty:SetTextColor(unpack(THEME.parchment))
setsEmpty:SetText("No gear sets yet.\n\nClick New to create one, then use the star next to an item in Suggested Upgrades to put it in that slot of the set.")

-- Paper-doll layout, same columns as the main window.
local SET_LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot" }
local SET_RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local SET_BOTTOM = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
local SET_TOP_Y = -110

local setSlotButtons = {}
local slotMenu = CreateFrame("Frame", "EverGearSetSlotMenu", UIParent, "UIDropDownMenuTemplate")

local function ShowSetSlotMenu(anchor, setIndex, slotToken, itemId)
    UIDropDownMenu_Initialize(slotMenu, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = EverGear:GetWishlistItemName(itemId)
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        if EverGear:IsAcquired(itemId) then
            info.text = "Mark as not acquired"
            info.func = function() EverGear:SetAcquired(itemId, false) end
        else
            info.text = "Mark as acquired"
            info.func = function() EverGear:SetAcquired(itemId, true) end
        end
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = "Remove from set"
        info.func = function() EverGear:SetSetSlot(setIndex, slotToken, nil) end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    ToggleDropDownMenu(1, nil, slotMenu, anchor, 0, 0)
end

local function CreateSetSlotButton(slotToken)
    local btn = H.CreateItemIconFrame("EverGearSetSlot_" .. slotToken, setsFrame, SET_ICON_SIZE)
    btn.slotToken = slotToken

    local check = btn:CreateTexture(nil, "OVERLAY")
    check:SetSize(16, 16)
    check:SetPoint("BOTTOMRIGHT", 3, -3)
    check:SetTexture(CHECK_TEXTURE)
    btn.check = check

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemId then
            GameTooltip:SetHyperlink(H.BuildItemLink(self.itemId))
            local item = EverGear:GetItem(self.itemId)
            if item then GameTooltip:AddLine(EverGear:GetSourceSummary(item), 0.7, 0.7, 0.7, true) end
            if EverGear:IsAcquired(self.itemId) then
                GameTooltip:AddLine("Acquired", 0.2, 0.9, 0.25)
            else
                GameTooltip:AddLine("Not acquired yet", 0.9, 0.6, 0.2)
            end
            GameTooltip:AddLine("Click for options.", 0.8, 0.8, 0.8)
        else
            GameTooltip:SetText((EverGear.FRIENDLY_SLOT_NAMES[self.slotToken] or self.slotToken) .. " (empty)")
            GameTooltip:AddLine("Use the star next to an item in Suggested Upgrades for this slot to add one.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function(self)
        local index = EverGear:GetActiveSetIndex()
        if index and self.itemId then ShowSetSlotMenu(self, index, self.slotToken, self.itemId) end
    end)

    setSlotButtons[slotToken] = btn
    return btn
end

for i, slotToken in ipairs(SET_LEFT) do
    CreateSetSlotButton(slotToken):SetPoint("TOPLEFT", 28, SET_TOP_Y - (i - 1) * SET_ROW_SPACING)
end
for i, slotToken in ipairs(SET_RIGHT) do
    CreateSetSlotButton(slotToken):SetPoint("TOPRIGHT", -28, SET_TOP_Y - (i - 1) * SET_ROW_SPACING)
end
for i, slotToken in ipairs(SET_BOTTOM) do
    local x = (i - 2) * (SET_ICON_SIZE + 12)
    CreateSetSlotButton(slotToken):SetPoint("TOP", setsFrame, "TOP", x, SET_TOP_Y - #SET_RIGHT * SET_ROW_SPACING - 4)
end

local function SetPicker_Initialize()
    for index, set in ipairs(EverGear:GetSets()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = set.name
        info.value = index
        info.checked = (index == EverGear:GetActiveSetIndex())
        info.func = function() EverGear:SetActiveSetIndex(index) end
        UIDropDownMenu_AddButton(info)
    end
end

local function RefreshSetsWindow()
    local sets = EverGear:GetSets()
    local index = EverGear:GetActiveSetIndex()
    local set = index and sets[index]

    UIDropDownMenu_Initialize(setPicker, SetPicker_Initialize)
    UIDropDownMenu_SetText(setPicker, set and set.name or "No sets")
    renameSetButton:SetEnabled(set ~= nil)
    deleteSetButton:SetEnabled(set ~= nil)
    setsEmpty:SetShown(set == nil)

    if set then
        local total, have = EverGear:GetSetProgress(index)
        setProgress:SetText(have .. "/" .. total .. " acquired")
    else
        setProgress:SetText("")
    end

    for slotToken, btn in pairs(setSlotButtons) do
        btn:SetShown(set ~= nil)
        local itemId = set and set.slots[slotToken]
        btn.itemId = itemId
        if itemId then
            local _, _, quality = H.SafeGetItemInfo(itemId)
            local r, g, b = H.GetQualityColor(quality)
            local acquired = EverGear:IsAcquired(itemId)
            H.SetIconTexture(btn, H.SafeGetItemIcon(itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
            btn.icon:SetDesaturated(not acquired)
            btn.icon:SetAlpha(acquired and 1 or 0.6)
            btn:SetBackdropBorderColor(r, g, b, 1)
            btn.check:SetShown(acquired)
        else
            H.SetIconTexture(btn, EverGear.EMPTY_SLOT_TEXTURES[slotToken])
            btn.icon:SetDesaturated(false)
            btn.icon:SetAlpha(0.4)
            btn:SetBackdropBorderColor(0.6, 0.56, 0.42, 1)
            btn.check:Hide()
        end
    end
end

setsFrame:SetScript("OnShow", RefreshSetsWindow)

-- ===== Popups for naming / deleting sets =====

local function PopupEditBox(popup)
    return popup.editBox or _G[popup:GetName() .. "EditBox"]
end

local function AcceptSetName(popup, data, isRename)
    local name = strtrim(PopupEditBox(popup):GetText() or "")
    if name == "" then return end
    if isRename then
        EverGear:RenameSet(data, name)
    else
        local index = EverGear:CreateSet(name)
        -- "New set..." from a star's menu: put that item straight into the new set.
        if data and data.itemId then EverGear:SetSetSlot(index, data.slotToken, data.itemId) end
        ShowSideWindow(setsFrame)
    end
end

StaticPopupDialogs["EVERGEAR_NEW_SET"] = {
    text = "Name for the new gear set:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnAccept = function(self, data) AcceptSetName(self, data, false) end,
    EditBoxOnEnterPressed = function(self, data)
        local popup = self:GetParent()
        AcceptSetName(popup, popup.data, false)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["EVERGEAR_RENAME_SET"] = {
    text = "New name for this gear set:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, data)
        local set = EverGear:GetSets()[data]
        local box = PopupEditBox(self)
        box:SetText(set and set.name or "")
        box:HighlightText()
    end,
    OnAccept = function(self, data) AcceptSetName(self, data, true) end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        AcceptSetName(popup, popup.data, true)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["EVERGEAR_DELETE_SET"] = {
    text = "Delete the gear set \"%s\"?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) EverGear:DeleteSet(data) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- ===== Star menu on Suggested Upgrades rows =====
-- Wanted list on top, then one entry per set (ticked when this item is already
-- in that slot of the set), then "New set...".

local starMenu = CreateFrame("Frame", "EverGearStarMenu", UIParent, "UIDropDownMenuTemplate")

function EverGear:ShowStarMenu(anchor, itemId, slotToken)
    UIDropDownMenu_Initialize(starMenu, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Wanted list"
        info.isNotRadio = true
        info.checked = EverGear:IsWanted(itemId)
        info.func = function()
            if EverGear:IsWanted(itemId) then EverGear:RemoveWanted(itemId) else EverGear:AddWanted(itemId, slotToken) end
        end
        UIDropDownMenu_AddButton(info)

        local slotName = EverGear.FRIENDLY_SLOT_NAMES[slotToken] or slotToken
        info = UIDropDownMenu_CreateInfo()
        info.text = "Gear set (" .. slotName .. " slot)"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        for index, set in ipairs(EverGear:GetSets()) do
            info = UIDropDownMenu_CreateInfo()
            info.text = set.name
            info.isNotRadio = true
            info.checked = (set.slots[slotToken] == itemId)
            info.func = function()
                if set.slots[slotToken] == itemId then
                    EverGear:SetSetSlot(index, slotToken, nil)
                else
                    EverGear:SetSetSlot(index, slotToken, itemId)
                end
            end
            UIDropDownMenu_AddButton(info)
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = "New set..."
        info.notCheckable = true
        info.func = function()
            StaticPopup_Show("EVERGEAR_NEW_SET", nil, nil, { itemId = itemId, slotToken = slotToken })
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    ToggleDropDownMenu(1, nil, starMenu, anchor, 0, 0)
end

-- ===== Opening / refreshing =====

function EverGear:ToggleWantedWindow()
    if wantedFrame:IsShown() then wantedFrame:Hide() else ShowSideWindow(wantedFrame) end
end

function EverGear:ToggleSetsWindow()
    if setsFrame:IsShown() then setsFrame:Hide() else ShowSideWindow(setsFrame) end
end

function EverGear:OnWishlistChanged()
    if wantedFrame:IsShown() then RefreshWantedWindow() end
    if setsFrame:IsShown() then RefreshSetsWindow() end
    if self.RefreshDetailStars then self:RefreshDetailStars() end
end

-- Icons and quality colors for items the client hadn't cached yet arrive later.
local cacheWatcher = CreateFrame("Frame")
cacheWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
cacheWatcher:SetScript("OnEvent", function()
    if wantedFrame:IsShown() then RefreshWantedWindow() end
    if setsFrame:IsShown() then RefreshSetsWindow() end
end)
