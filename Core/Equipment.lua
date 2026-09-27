-- Reads the player's currently equipped items so Upgrades.lua can compare against them.

EverGear = EverGear or {}

function EverGear:GetEquippedItemId(slotToken)
    local slotId = GetInventorySlotInfo(slotToken)
    if not slotId then return nil end
    return GetInventoryItemID("player", slotId)
end

-- All equipped item ids at once, keyed by real slot token. Convenience for
-- UI.lua's single refresh pass instead of calling GetEquippedItemId per slot.
function EverGear:GetCurrentGear()
    local gear = {}
    for _, slotToken in ipairs(self.EQUIP_SLOTS) do
        gear[slotToken] = self:GetEquippedItemId(slotToken)
    end
    return gear
end

function EverGear:GetEquippedStats()
    local equipped = {}
    for _, slotToken in ipairs(self.EQUIP_SLOTS) do
        local itemId = self:GetEquippedItemId(slotToken)
        if itemId then
            equipped[slotToken] = self:GetItem(itemId)
        end
    end
    return equipped
end
