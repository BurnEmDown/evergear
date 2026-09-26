-- Scoring/comparison logic. Placeholder heuristic until EP stat-weight data exists
-- for WoW Forever (see LevelGearAdvisor's Upgrades.lua for the eventual EP-based model).

EverGear = EverGear or {}

local function SimpleScore(item)
    if not item or not item.stats then return 0 end
    local score = 0
    for _, value in pairs(item.stats) do
        score = score + value
    end
    return score
end

-- Returns candidate items for a slot that beat the currently equipped item,
-- restricted to the player's level (minLevel <= player level) and, once armor-type
-- filtering is added, the player's armor class.
function EverGear:GetUpgradesForSlot(slotToken)
    local playerInfo = self:GetPlayerInfo()
    local equippedId = self:GetEquippedItemId(slotToken)
    local equippedItem = equippedId and self:GetItem(equippedId)
    local equippedScore = equippedItem and SimpleScore(equippedItem) or 0

    local upgrades = {}
    for _, item in ipairs(self:GetItemsForSlot(slotToken)) do
        if (not item.minLevel or item.minLevel <= playerInfo.level) then
            local score = SimpleScore(item)
            if score > equippedScore then
                table.insert(upgrades, item)
            end
        end
    end

    table.sort(upgrades, function(a, b) return SimpleScore(a) > SimpleScore(b) end)
    return upgrades
end
