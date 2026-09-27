-- Reads the player's class/spec/level, used by Upgrades.lua for role/stat
-- weighting and class-usability checks (armor type, weapon type).

EverGear = EverGear or {}

function EverGear:GetPlayerInfo()
    local _, classToken, classID = UnitClass("player")
    local level = UnitLevel("player")
    local _, _, raceID = UnitRace("player")
    return {
        classToken = classToken,  -- e.g. "PALADIN" -- used for role/armor/weapon checks
        classID = classID,
        raceID = raceID,
        level = level,
    }
end
