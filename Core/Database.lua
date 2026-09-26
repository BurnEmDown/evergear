-- Merges the generated Data\*.lua tables (EverGear.Items, populated per-zone) with
-- SavedVariables overrides, and exposes lookup helpers used by Upgrades.lua / UI.lua.

EverGear = EverGear or {}
EverGearDB = EverGearDB or {}

function EverGear:GetItem(itemId)
    return self.Items[itemId]
end

-- Returns every known item for a given equipment slot token (e.g. "HeadSlot").
function EverGear:GetItemsForSlot(slotToken)
    local results = {}
    for itemId, item in pairs(self.Items) do
        if item.slot == slotToken then
            table.insert(results, item)
        end
    end
    return results
end

function EverGear:GetItemsForZone(zoneName)
    local results = {}
    for itemId, item in pairs(self.Items) do
        if item.source and item.source.zone == zoneName then
            table.insert(results, item)
        end
    end
    return results
end
