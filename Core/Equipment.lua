-- Reads the player's currently equipped items so Upgrades.lua can compare against them.

EverGear = EverGear or {}

-- Pulls the numeric item id out of an item link string ("item:1234:0:0:...").
-- Returns nil if itemLink is nil (empty slot) or malformed.
function EverGear:GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local id = string.match(itemLink, "item:(%d+)")
    return id and tonumber(id) or nil
end

function EverGear:GetEquippedItemId(slotToken)
    local slotId = GetInventorySlotInfo(slotToken)
    if not slotId then return nil end
    return GetInventoryItemID("player", slotId)
end

-- The REAL item link for whatever's equipped in a slot (nil if empty). This is
-- what Upgrades.lua reads live stats from for the currently-equipped item, so
-- it can score gear the addon's own database doesn't know about yet.
function EverGear:GetEquippedItemLink(slotToken)
    local slotId = GetInventorySlotInfo(slotToken)
    if not slotId then return nil end
    return GetInventoryItemLink("player", slotId)
end

-- All equipped item LINKS at once, keyed by real slot token. Convenience for
-- UI.lua's single refresh pass instead of calling GetEquippedItemLink per slot.
function EverGear:GetCurrentGear()
    local gear = {}
    for _, slotToken in ipairs(self.EQUIP_SLOTS) do
        gear[slotToken] = self:GetEquippedItemLink(slotToken)
    end
    return gear
end
