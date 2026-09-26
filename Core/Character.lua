-- Reads the player's class/spec/level. EP stat-weight tables (per class/spec) will be
-- added here once EverGear has enough leveling data to make weighting meaningful;
-- until then, Upgrades.lua falls back to a simple ilvl/slot-appropriate-stat heuristic.

EverGear = EverGear or {}

function EverGear:GetPlayerInfo()
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    return {
        class = class,
        level = level,
    }
end
