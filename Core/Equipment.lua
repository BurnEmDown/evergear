-- Reads the player's currently equipped items so Upgrades.lua can compare against them.

EverGear = EverGear or {}

function EverGear:GetEquippedItemId(slotToken)
    local slotId = GetInventorySlotInfo(slotToken)
    if not slotId then return nil end
    return GetInventoryItemID("player", slotId)
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
