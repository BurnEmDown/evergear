-- Merges the generated Data\*.lua tables (EverGear.Items, populated per-zone) with
-- SavedVariables overrides, and exposes lookup helpers used by Upgrades.lua / UI.lua.

EverGear = EverGear or {}
EverGearDB = EverGearDB or {}

function EverGear:GetItem(itemId)
    return self.Items[itemId]
end

-- Returns every known item whose data-slot matches the REAL inventory slot
-- token requested, going through GENERIC_SLOT_FOR_REAL_SLOT for rings/trinkets
-- (an item tagged slot="FingerSlot" is a candidate for both Finger0Slot and
-- Finger1Slot, and likewise "TrinketSlot" for both trinket slots).
function EverGear:GetItemsForSlot(realSlotToken)
    local matchSlot = self.GENERIC_SLOT_FOR_REAL_SLOT[realSlotToken] or realSlotToken
    local results = {}
    for _, item in pairs(self.Items) do
        if item.slot == matchSlot then
            table.insert(results, item)
        end
    end
    return results
end

function EverGear:GetItemsForZone(zoneName)
    local results = {}
    for _, item in pairs(self.Items) do
        if item.source and item.source.zone == zoneName then
            table.insert(results, item)
        end
    end
    return results
end
