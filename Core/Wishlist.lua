-- Per-character "wanted" list and gear sets (data side; the windows live in
-- WishlistUI.lua).
--
-- Everything is stored in this character's own settings table (GetCharDB, see
-- Database.lua), so alts each have their own list and sets:
--
--   charDB.wanted   = { [itemId] = { added = <time()>, slot = "HandsSlot" }, ... }
--   charDB.sets     = { { name = "Tank set", slots = { [realSlotToken] = itemId } }, ... }
--   charDB.activeSet = <index into charDB.sets>  -- the one the Sets window shows
--   charDB.acquired = { [itemId] = true, ... }
--
-- "acquired" is sticky on purpose: once an item has been seen in this
-- character's bags or equipped (or ticked by hand), it stays ticked in every
-- set even after it's sold or replaced. Only items on the wanted list or in a
-- set are ever recorded, so it doesn't grow with everything the player loots.

EverGear = EverGear or {}

local function CharDB()
    local charDB = EverGear:GetCharDB()
    charDB.wanted = charDB.wanted or {}
    charDB.sets = charDB.sets or {}
    charDB.acquired = charDB.acquired or {}
    return charDB
end

local function Print(msg)
    print("|cff33ff99EverGear|r " .. msg)
end

-- Item name for messages and rows: the addon's own data first, then the
-- client's item cache, then whatever name was stored when it was added.
function EverGear:GetWishlistItemName(itemId, fallback)
    local item = self:GetItem(itemId)
    if item then return item.name end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = getInfo and getInfo(itemId)
    return name or fallback or ("item " .. tostring(itemId))
end

-- Called after every change so whichever windows are open can redraw.
function EverGear:NotifyWishlistChanged()
    if self.OnWishlistChanged then self:OnWishlistChanged() end
end

-- ===== Wanted list =====

function EverGear:IsWanted(itemId)
    return CharDB().wanted[itemId] ~= nil
end

function EverGear:AddWanted(itemId, slotToken)
    local charDB = CharDB()
    if charDB.wanted[itemId] then return end
    charDB.wanted[itemId] = { added = time(), slot = slotToken, name = self:GetWishlistItemName(itemId) }
    self:NotifyWishlistChanged()
    self:ScanForAcquiredItems()  -- already in the bags? tick it straight away
end

function EverGear:RemoveWanted(itemId)
    local charDB = CharDB()
    if not charDB.wanted[itemId] then return end
    charDB.wanted[itemId] = nil
    self:NotifyWishlistChanged()
end

-- Oldest first, so the list reads in the order things were added.
function EverGear:GetWantedList()
    local list = {}
    for itemId, entry in pairs(CharDB().wanted) do
        table.insert(list, { itemId = itemId, added = entry.added or 0, slot = entry.slot, name = entry.name })
    end
    table.sort(list, function(a, b)
        if a.added ~= b.added then return a.added < b.added end
        return a.itemId < b.itemId
    end)
    return list
end

-- ===== Acquired =====

function EverGear:IsAcquired(itemId)
    return CharDB().acquired[itemId] == true
end

-- Ticks (or unticks) an item by hand. A wanted item stays on the wanted list,
-- marked as acquired, until the player removes it.
function EverGear:SetAcquired(itemId, acquired)
    local charDB = CharDB()
    charDB.acquired[itemId] = acquired and true or nil
    self:NotifyWishlistChanged()
end

-- ===== Sets =====

function EverGear:GetSets()
    return CharDB().sets
end

function EverGear:GetActiveSetIndex()
    local charDB = CharDB()
    local index = charDB.activeSet
    if not index or not charDB.sets[index] then
        index = #charDB.sets > 0 and 1 or nil
        charDB.activeSet = index
    end
    return index
end

function EverGear:SetActiveSetIndex(index)
    CharDB().activeSet = index
    self:NotifyWishlistChanged()
end

EverGear.MAX_GEAR_SETS = 20
EverGear.MAX_SET_NAME_LENGTH = 30

-- Character count, not bytes, so accented names aren't cut short.
local function NameLength(name)
    return strlenutf8 and strlenutf8(name) or #name
end

local function NameTooLongMessage()
    return "Gear set names can be at most " .. EverGear.MAX_SET_NAME_LENGTH .. " characters."
end

local function NormalizeName(name)
    return strlower(strtrim(name or ""))
end

-- Set names are unique per character, ignoring case and outer spaces, so the
-- picker, menus and tooltips never show two sets that look the same.
-- exceptIndex lets a set be "renamed" to its own name.
function EverGear:IsSetNameTaken(name, exceptIndex)
    local wanted = NormalizeName(name)
    for index, set in ipairs(CharDB().sets) do
        if index ~= exceptIndex and NormalizeName(set.name) == wanted then return true end
    end
    return false
end

-- Returns the new set's index, or nil plus the reason it wasn't created.
function EverGear:CreateSet(name)
    local sets = CharDB().sets
    if #sets >= self.MAX_GEAR_SETS then
        return nil, "You already have " .. self.MAX_GEAR_SETS .. " gear sets, the most a character can have. Delete one first."
    end
    if NameLength(strtrim(name)) > self.MAX_SET_NAME_LENGTH then
        return nil, NameTooLongMessage()
    end
    if self:IsSetNameTaken(name) then
        return nil, "You already have a gear set called \"" .. strtrim(name) .. "\"."
    end
    table.insert(sets, { name = strtrim(name), slots = {} })
    CharDB().activeSet = #sets
    self:NotifyWishlistChanged()
    return #sets
end

-- Returns true, or false plus the reason it wasn't renamed.
function EverGear:RenameSet(index, name)
    local set = CharDB().sets[index]
    if not set then return false end
    if NameLength(strtrim(name)) > self.MAX_SET_NAME_LENGTH then
        return false, NameTooLongMessage()
    end
    if self:IsSetNameTaken(name, index) then
        return false, "You already have a gear set called \"" .. strtrim(name) .. "\"."
    end
    set.name = strtrim(name)
    self:NotifyWishlistChanged()
    return true
end

function EverGear:DeleteSet(index)
    local charDB = CharDB()
    if not charDB.sets[index] then return end
    table.remove(charDB.sets, index)
    charDB.activeSet = nil  -- GetActiveSetIndex falls back to the first set
    self:NotifyWishlistChanged()
end

function EverGear:IsTwoHandItem(itemId)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local equipLoc = getInfo and select(4, getInfo(itemId))
    if equipLoc and equipLoc ~= "" then return equipLoc == "INVTYPE_2HWEAPON" end
    local item = self:GetItem(itemId)
    return item ~= nil and item.isTwoHand == true
end

-- True if this set's main hand holds a two-hander, so its off hand must stay empty.
function EverGear:IsSetOffHandBlocked(index)
    local set = CharDB().sets[index]
    local mainHand = set and set.slots.MainHandSlot
    return mainHand ~= nil and self:IsTwoHandItem(mainHand)
end

-- One item per real slot: setting a slot that already has an item replaces it.
-- A two-handed main hand and an off-hand item can't be in the same set: adding
-- an off-hand item next to a two-hander is refused, and adding a two-hander
-- takes the off-hand item out.
function EverGear:SetSetSlot(index, slotToken, itemId)
    local set = CharDB().sets[index]
    if not set then return end
    if itemId and slotToken == "SecondaryHandSlot" and self:IsSetOffHandBlocked(index) then
        Print(set.name .. " has a two-handed weapon in the main hand -- remove it before adding an off-hand item.")
        return
    end
    set.slots[slotToken] = itemId
    local offHand = set.slots.SecondaryHandSlot
    if itemId and slotToken == "MainHandSlot" and offHand and self:IsTwoHandItem(itemId) then
        set.slots.SecondaryHandSlot = nil
        Print("Removed " .. self:GetWishlistItemName(offHand) .. " from " .. set.name .. "'s off hand -- a two-handed weapon needs both hands.")
    end
    self:NotifyWishlistChanged()
    if itemId then self:ScanForAcquiredItems() end
end

-- Number of filled slots and how many of those are acquired.
function EverGear:GetSetProgress(index)
    local set = CharDB().sets[index]
    if not set then return 0, 0 end
    local total, have = 0, 0
    for _, itemId in pairs(set.slots) do
        total = total + 1
        if self:IsAcquired(itemId) then have = have + 1 end
    end
    return total, have
end

-- True if the item is on the wanted list or in any set.
function EverGear:IsTracked(itemId)
    if self:IsWanted(itemId) then return true end
    for _, set in ipairs(self:GetSets()) do
        for _, setItemId in pairs(set.slots) do
            if setItemId == itemId then return true end
        end
    end
    return false
end

-- ===== Automatic acquire detection =====
-- Looks through equipped gear and the backpack + bags for anything on the
-- wanted list or in a set. One that turns up is ticked as acquired (it stays on
-- the wanted list until the player removes it), with a chat line for wanted
-- items so it's never a silent change.

local GetBagSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetBagItemId = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function ForEachOwnedItemId(callback)
    for slotId = 1, 19 do
        local itemId = GetInventoryItemID("player", slotId)
        if itemId then callback(itemId) end
    end
    if not (GetBagSlots and GetBagItemId) then return end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetBagSlots(bag) or 0 do
            local itemId = GetBagItemId(bag, slot)
            if itemId then callback(itemId) end
        end
    end
end

function EverGear:ScanForAcquiredItems()
    local charDB = CharDB()
    local changed = false
    ForEachOwnedItemId(function(itemId)
        if charDB.acquired[itemId] then return end
        local wanted = charDB.wanted[itemId]
        if wanted or self:IsTracked(itemId) then
            charDB.acquired[itemId] = true
            changed = true
            if wanted then
                Print("You got " .. self:GetWishlistItemName(itemId, wanted.name) .. " from your wanted list -- marked as acquired.")
            end
        end
    end)
    if changed then self:NotifyWishlistChanged() end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:SetScript("OnEvent", function()
    EverGear:ScanForAcquiredItems()
end)
