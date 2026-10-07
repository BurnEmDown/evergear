-- Windows for the per-character wanted list and gear sets (data in
-- Wishlist.lua), plus the "add to..." menu behind the star on each Suggested
-- Upgrades row, Alt-click on any item, and the hovered-item key binding.
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

-- Defined this early (not with the rest of the window code below) so the
-- main window's Wanted / Sets buttons keep working even if something further
-- down this file fails to load in some client build.
function EverGear:ToggleWantedWindow()
    if wantedFrame:IsShown() then wantedFrame:Hide() else ShowSideWindow(wantedFrame) end
end

function EverGear:ToggleSetsWindow()
    if setsFrame:IsShown() then setsFrame:Hide() else ShowSideWindow(setsFrame) end
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
wantedEmpty:SetText("Nothing here yet.\n\nAlt-click any item (bags, character sheet, chat links, loot, quest rewards...) or click the star next to an item in Suggested Upgrades to add it to this character's wanted list.")

-- Plain ScrollFrame scrolled with the mouse wheel -- no Blizzard scroll-bar
-- template, since templates can be missing from this client (see
-- CreateItemIconFrame in UI.lua for the same reason).
local wantedScroll = CreateFrame("ScrollFrame", "EverGearWantedScroll", wantedFrame)
wantedScroll:SetPoint("TOPLEFT", 18, -44)
wantedScroll:SetPoint("BOTTOMRIGHT", -18, 18)
wantedScroll:EnableMouseWheel(true)
wantedScroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
    local target = self:GetVerticalScroll() - delta * WANTED_ROW_HEIGHT
    self:SetVerticalScroll(math.min(maxScroll, math.max(0, target)))
end)
local wantedList = CreateFrame("Frame", nil, wantedScroll)
wantedList:SetSize(WANTED_WIDTH - 36, 10)
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
    row:SetSize(WANTED_WIDTH - 36, WANTED_ROW_HEIGHT)

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
        local source = item and EverGear:GetSourceSummary(item) or "Source not in EverGear's data"
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
setsEmpty:SetText("No gear sets yet.\n\nClick New to create one, then Alt-click any item (or use the star next to an item in Suggested Upgrades) to put it in the set.")

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
            GameTooltip:AddLine("Alt-click any item that fits this slot to add one.", 0.8, 0.8, 0.8, true)
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

-- Set up once: opening the picker re-runs SetPicker_Initialize by itself, so
-- the list is always current. Re-initializing it on every refresh broke the
-- refresh whenever it ran from inside a dropdown click (picking a set, or
-- adding an item through the star / Alt-click menu) -- the window then stayed
-- stale until it was closed and reopened.
UIDropDownMenu_Initialize(setPicker, SetPicker_Initialize)

local function RefreshSetsWindow()
    local sets = EverGear:GetSets()
    local index = EverGear:GetActiveSetIndex()
    local set = index and sets[index]

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

-- ===== Refreshing =====
-- Kept right after the windows (before the menu, Alt-click and tooltip code
-- below), so a client that lacks one of those can't stop open windows from
-- updating.


-- Changes mostly come from a dropdown click (star / Alt-click menu, set
-- picker, slot menu), so the redraw waits one frame for that menu to finish
-- closing; several changes in the same frame redraw once.
local refreshQueued = false

local function RefreshOpenWindows()
    refreshQueued = false
    if wantedFrame:IsShown() then RefreshWantedWindow() end
    if setsFrame:IsShown() then RefreshSetsWindow() end
    if EverGear.RefreshDetailStars then EverGear:RefreshDetailStars() end
end

function EverGear:OnWishlistChanged()
    if refreshQueued then return end
    refreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshOpenWindows)
    else
        RefreshOpenWindows()
    end
end

-- Icons and quality colors for items the client hadn't cached yet arrive later.
local cacheWatcher = CreateFrame("Frame")
cacheWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
cacheWatcher:SetScript("OnEvent", function()
    if wantedFrame:IsShown() then RefreshWantedWindow() end
    if setsFrame:IsShown() then RefreshSetsWindow() end
end)

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

-- ===== "Add to..." menu =====
-- Opened from the star on a Suggested Upgrades row, from Alt-clicking any item
-- in the game, or from the key binding (hovered item). Wanted list on top, then
-- the gear sets, then "New set...". An item that fits two slots (rings,
-- trinkets, one-handed weapons) gets one entry per slot under each set.

-- Real slots an item can go in, from the game's own equip location.
local SLOTS_FOR_EQUIP_LOC = {
    INVTYPE_HEAD = { "HeadSlot" }, INVTYPE_NECK = { "NeckSlot" }, INVTYPE_SHOULDER = { "ShoulderSlot" },
    INVTYPE_CLOAK = { "BackSlot" }, INVTYPE_CHEST = { "ChestSlot" }, INVTYPE_ROBE = { "ChestSlot" },
    INVTYPE_WRIST = { "WristSlot" }, INVTYPE_HAND = { "HandsSlot" }, INVTYPE_WAIST = { "WaistSlot" },
    INVTYPE_LEGS = { "LegsSlot" }, INVTYPE_FEET = { "FeetSlot" },
    INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
    INVTYPE_WEAPONMAINHAND = { "MainHandSlot" }, INVTYPE_2HWEAPON = { "MainHandSlot" },
    INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" }, INVTYPE_SHIELD = { "SecondaryHandSlot" },
    INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
    INVTYPE_RANGED = { "RangedSlot" }, INVTYPE_RANGEDRIGHT = { "RangedSlot" },
    INVTYPE_THROWN = { "RangedSlot" }, INVTYPE_RELIC = { "RangedSlot" },
}

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Item id and the slots it fits, for an item link or id; nil if it isn't gear.
function EverGear:GetItemSlots(itemLinkOrId)
    if not (itemLinkOrId and GetItemInfoInstant) then return nil end
    local itemId, _, _, equipLoc = GetItemInfoInstant(itemLinkOrId)
    local slots = equipLoc and SLOTS_FOR_EQUIP_LOC[equipLoc]
    if not (itemId and slots) then return nil end
    return itemId, slots
end

local starMenu = CreateFrame("Frame", "EverGearStarMenu", UIParent, "UIDropDownMenuTemplate")

-- Only these classes can dual wield, so only they get an off-hand entry for
-- one-handed weapons that fit either hand.
local CLASS_CAN_DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

local function DropOffHandIfNoDualWield(slotTokens)
    if #slotTokens < 2 or slotTokens[2] ~= "SecondaryHandSlot" then return slotTokens end
    if CLASS_CAN_DUAL_WIELD[EverGear:GetPlayerInfo().classToken] then return slotTokens end
    return { slotTokens[1] }
end

-- slotTokens: one real slot (a Suggested Upgrades row) or a list of them.
function EverGear:ShowStarMenu(anchor, itemId, slotTokens)
    if type(slotTokens) ~= "table" then slotTokens = { slotTokens } end
    slotTokens = DropOffHandIfNoDualWield(slotTokens)
    local multiSlot = #slotTokens > 1
    local usable, subType = EverGear:CanPlayerUseItem(itemId)

    UIDropDownMenu_Initialize(starMenu, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = EverGear:GetWishlistItemName(itemId)
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        if not usable then
            -- Already tracked from before this check existed: still let it be
            -- taken off the wanted list / out of a set.
            info = UIDropDownMenu_CreateInfo()
            info.text = "Your class can't use " .. (subType and subType ~= "" and subType or "this item")
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
            if EverGear:IsWanted(itemId) then
                info = UIDropDownMenu_CreateInfo()
                info.text = "Remove from wanted list"
                info.notCheckable = true
                info.func = function() EverGear:RemoveWanted(itemId) end
                UIDropDownMenu_AddButton(info)
            end
            for index, set in ipairs(EverGear:GetSets()) do
                for slotToken, setItemId in pairs(set.slots) do
                    if setItemId == itemId then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Remove from " .. set.name
                        info.notCheckable = true
                        info.func = function() EverGear:SetSetSlot(index, slotToken, nil) end
                        UIDropDownMenu_AddButton(info)
                    end
                end
            end
            return
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = "Wanted list"
        info.isNotRadio = true
        info.checked = EverGear:IsWanted(itemId)
        info.func = function()
            if EverGear:IsWanted(itemId) then EverGear:RemoveWanted(itemId) else EverGear:AddWanted(itemId, slotTokens[1]) end
        end
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        if multiSlot then
            info.text = "Gear set"
        else
            info.text = "Gear set (" .. (EverGear.FRIENDLY_SLOT_NAMES[slotTokens[1]] or slotTokens[1]) .. " slot)"
        end
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        for index, set in ipairs(EverGear:GetSets()) do
            for _, slotToken in ipairs(slotTokens) do
                info = UIDropDownMenu_CreateInfo()
                info.text = multiSlot and (set.name .. " - " .. (EverGear.FRIENDLY_SLOT_NAMES[slotToken] or slotToken)) or set.name
                info.isNotRadio = true
                info.checked = (set.slots[slotToken] == itemId)
                if slotToken == "SecondaryHandSlot" and not info.checked and EverGear:IsSetOffHandBlocked(index) then
                    info.text = info.text .. " (two-hander in main hand)"
                    info.disabled = true
                end
                info.func = function()
                    if set.slots[slotToken] == itemId then
                        EverGear:SetSetSlot(index, slotToken, nil)
                    else
                        EverGear:SetSetSlot(index, slotToken, itemId)
                    end
                end
                UIDropDownMenu_AddButton(info)
            end
        end

        info = UIDropDownMenu_CreateInfo()
        info.text = "New set..."
        info.notCheckable = true
        info.func = function()
            StaticPopup_Show("EVERGEAR_NEW_SET", nil, nil, { itemId = itemId, slotToken = slotTokens[1] })
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
    ToggleDropDownMenu(1, nil, starMenu, anchor, 0, 0)
end

-- Menu for any item link (Alt-click, key binding), opened at the cursor.
-- Returns false for things that can't go in a slot (potions, quest items, ...).
function EverGear:ShowItemMenu(itemLink)
    local itemId, slots = self:GetItemSlots(itemLink)
    if not itemId then return false end
    self:ShowStarMenu("cursor", itemId, slots)
    return true
end

-- Alt-click on any item button or link: bags, character sheet, chat, loot,
-- quest rewards, vendors... all of them go through HandleModifiedItemClick.
-- Shift (link to chat) and Ctrl (dressing room) keep their usual jobs.
local function OnModifiedItemClick(itemLink)
    if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
        EverGear:ShowItemMenu(itemLink)
    end
end

if type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
else
    -- Older-style clients without the shared handler: at least bags and the
    -- character sheet (the hover key binding still covers everything else).
    if type(ContainerFrameItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self)
            local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
            OnModifiedItemClick(getLink and getLink(self:GetParent():GetID(), self:GetID()))
        end)
    end
    if type(PaperDollItemSlotButton_OnModifiedClick) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_OnModifiedClick", function(self)
            OnModifiedItemClick(GetInventoryItemLink("player", self:GetID()))
        end)
    end
end

-- Key binding (Key Bindings > AddOns > EverGear, see Bindings.xml; its labels
-- are set in Wishlist.lua): opens the menu for whatever item the mouse is
-- over, no click needed.

function EverGear:ShowHoveredItemMenu()
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip:IsShown() and tip.GetItem then
            local _, itemLink = tip:GetItem()
            if itemLink and self:ShowItemMenu(itemLink) then return end
        end
    end
end

-- One line at the bottom of gear tooltips: where the item already is, or how
-- to add it.
local function OnItemTooltip(tooltip)
    if not tooltip.GetItem then return end
    local _, itemLink = tooltip:GetItem()
    local itemId = EverGear:GetItemSlots(itemLink)
    if not itemId then return end

    local where = {}
    if EverGear:IsWanted(itemId) then table.insert(where, "wanted") end
    for _, set in ipairs(EverGear:GetSets()) do
        for _, setItemId in pairs(set.slots) do
            if setItemId == itemId then table.insert(where, set.name) break end
        end
    end
    if #where > 0 then
        local status = EverGear:IsAcquired(itemId) and " (acquired)" or ""
        tooltip:AddLine("EverGear: " .. table.concat(where, ", ") .. status, 1.00, 0.82, 0.20)
    else
        tooltip:AddLine("EverGear: Alt-click to add to wanted list / set", 0.55, 0.55, 0.55)
    end
end

-- Same approach as Debug.lua: this client has dropped OnTooltipSetItem in
-- favour of TooltipDataProcessor, and HookScript errors on an unknown script
-- type (which used to stop the rest of this file from loading), so try the old
-- hook under pcall and fall back to the new API.
local function HookTooltipsOldStyle()
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then tip:HookScript("OnTooltipSetItem", OnItemTooltip) end
    end
end

if not pcall(HookTooltipsOldStyle) and TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip or tooltip == ItemRefTooltip then OnItemTooltip(tooltip) end
    end)
end
