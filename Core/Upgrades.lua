-- Scoring/comparison logic. Placeholder heuristic (a plain stat-sum) until real
-- EP stat-weight data exists for WoW Forever specs -- see LevelGearAdvisor's
-- Upgrades.lua for the eventual EP-based model this will grow into.

EverGear = EverGear or {}

local function SimpleScore(item)
    if not item or not item.stats then return 0 end
    local score = 0
    for _, value in pairs(item.stats) do
        -- Some stat values aren't numbers (e.g. WEAPON_DAMAGE is a "min - max Damage"
        -- string) -- skip anything that isn't. Note this heuristic still lumps
        -- WEAPON_SPEED/WEAPON_DPS in with primary stats like STAMINA, which is not
        -- meaningful; it's a placeholder until real EP stat weights replace it.
        if type(value) == "number" then
            score = score + value
        end
    end
    return score
end

-- Returns (candidates, currentScore) for a REAL slot token:
--   candidates  = a list of { item = <item>, score = <number> }, best first,
--                 restricted to the player's level and only items that beat
--                 currentScore.
--   currentScore = the score of whatever is currently equipped in that slot
--                  (0 if the slot is empty).
function EverGear:GetUpgradesForSlot(realSlotToken, equippedItemId)
    local playerInfo = self:GetPlayerInfo()
    local equippedItem = equippedItemId and self:GetItem(equippedItemId)
    local currentScore = equippedItem and SimpleScore(equippedItem) or 0

    local candidates = {}
    for _, item in ipairs(self:GetItemsForSlot(realSlotToken)) do
        if item.id ~= equippedItemId and (not item.minLevel or item.minLevel <= playerInfo.level) then
            local score = SimpleScore(item)
            if score > currentScore then
                table.insert(candidates, { item = item, score = score })
            end
        end
    end

    table.sort(candidates, function(a, b) return a.score > b.score end)
    return candidates, currentScore
end

-- Human-readable one-liner for where an item comes from, used in the detail
-- panel and in tooltips. Reads item.source (see Constants.lua for the shape).
function EverGear:GetSourceSummary(item)
    local source = item and item.source
    if not source then return "Unknown source" end

    if source.type == "quest" then
        return "Quest: " .. (source.quest or "Unknown quest")
    elseif source.type == "dungeonDrop" or source.type == "raidDrop" then
        if source.boss then
            return (source.zone or "Unknown zone") .. " (" .. source.boss .. ")"
        end
        return source.zone or "Unknown zone"
    elseif source.type == "vendor" then
        return "Vendor" .. (source.name and (": " .. source.name) or "")
    elseif source.type == "worldDrop" then
        return "World Drop" .. (source.zone and (" - " .. source.zone) or "")
    elseif source.type == "craft" then
        return "Crafted"
    end
    return "Unknown source"
end
