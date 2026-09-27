-- Scoring/comparison logic. A hand-tuned per-role heuristic (primary stat
-- weighted highest, stamina next, secondary stats weighted per role) rather
-- than a full stat-weight simulation -- ported from Leveling Gear Advisor's
-- v1 heuristic (its ROLE_PROFILES/ScoreItem, before real per-class-spec EP
-- data existed for TBC). EverGear can grow into a real EP system the same
-- way once enough WoW Forever class data exists to build one.

EverGear = EverGear or {}

-- ===== Role / primary stat =====

-- A player-chosen spec (see UI.lua's dropdown), and the role it maps to for
-- scoring purposes. Roles, not exact specs, drive ScoreItem below -- e.g.
-- "Arms" and "Fury" both just mean "Physical DPS" here. Druid's Feral tree is
-- split into two selectable entries since it can be built as either a tank or
-- a physical DPS spec despite being one talent tree in-game.
EverGear.CLASS_SPECS = {
    WARRIOR = {
        { name = "Arms", role = "Physical DPS" },
        { name = "Fury", role = "Physical DPS" },
        { name = "Protection", role = "Tank" },
    },
    PALADIN = {
        { name = "Holy", role = "Healer" },
        { name = "Protection", role = "Tank" },
        { name = "Retribution", role = "Physical DPS" },
    },
    HUNTER = {
        { name = "Beast Mastery", role = "Physical DPS" },
        { name = "Marksmanship", role = "Physical DPS" },
        { name = "Survival", role = "Physical DPS" },
    },
    ROGUE = {
        { name = "Assassination", role = "Physical DPS" },
        { name = "Combat", role = "Physical DPS" },
        { name = "Subtlety", role = "Physical DPS" },
    },
    PRIEST = {
        { name = "Discipline", role = "Healer" },
        { name = "Holy", role = "Healer" },
        { name = "Shadow", role = "Caster DPS" },
    },
    SHAMAN = {
        { name = "Elemental", role = "Caster DPS" },
        { name = "Enhancement", role = "Physical DPS" },
        { name = "Restoration", role = "Healer" },
    },
    MAGE = {
        { name = "Arcane", role = "Caster DPS" },
        { name = "Fire", role = "Caster DPS" },
        { name = "Frost", role = "Caster DPS" },
    },
    WARLOCK = {
        { name = "Affliction", role = "Caster DPS" },
        { name = "Demonology", role = "Caster DPS" },
        { name = "Destruction", role = "Caster DPS" },
    },
    DRUID = {
        { name = "Balance", role = "Caster DPS" },
        { name = "Feral (DPS)", role = "Physical DPS" },
        { name = "Feral (Tank)", role = "Tank" },
        { name = "Restoration", role = "Healer" },
    },
}

function EverGear:GetDefaultSpec(classToken)
    local specs = self.CLASS_SPECS[classToken]
    return specs and specs[1] and specs[1].name or nil
end

function EverGear:GetRoleForSpec(classToken, specName)
    local specs = self.CLASS_SPECS[classToken]
    if not specs then return "Physical DPS" end
    for _, spec in ipairs(specs) do
        if spec.name == specName then return spec.role end
    end
    return specs[1].role
end

local CLASS_FALLBACK_STAT = {
    WARRIOR = "STRENGTH", PALADIN = "STRENGTH", HUNTER = "AGILITY", ROGUE = "AGILITY",
    PRIEST = "INTELLECT", SHAMAN = "INTELLECT", MAGE = "INTELLECT", WARLOCK = "INTELLECT", DRUID = "INTELLECT",
}

local CLASS_ROLE_PRIMARY_STAT = {
    WARRIOR = { ["Physical DPS"] = "STRENGTH", ["Tank"] = "STRENGTH" },
    PALADIN = { ["Physical DPS"] = "STRENGTH", ["Tank"] = "STRENGTH", ["Healer"] = "INTELLECT" },
    HUNTER  = { ["Physical DPS"] = "AGILITY" },
    ROGUE   = { ["Physical DPS"] = "AGILITY" },
    PRIEST  = { ["Caster DPS"] = "INTELLECT", ["Healer"] = "INTELLECT" },
    SHAMAN  = { ["Physical DPS"] = "AGILITY", ["Caster DPS"] = "INTELLECT", ["Healer"] = "INTELLECT" },
    MAGE    = { ["Caster DPS"] = "INTELLECT" },
    WARLOCK = { ["Caster DPS"] = "INTELLECT" },
    DRUID   = { ["Physical DPS"] = "AGILITY", ["Caster DPS"] = "INTELLECT", ["Healer"] = "INTELLECT", ["Tank"] = "AGILITY" },
}

function EverGear:GetPrimaryStat(classToken, role)
    local roleMap = CLASS_ROLE_PRIMARY_STAT[classToken]
    if roleMap and roleMap[role] then return roleMap[role] end
    return CLASS_FALLBACK_STAT[classToken] or "STAMINA"
end

-- Per-role scoring profile: which secondary stats matter, plus how much
-- Stamina, armor, and weapon DPS matter for that role. Tuned by feel, not
-- simulation -- adjust weights if suggestions consistently feel off for a
-- given role. Several secondary-stat key names (HIT_RATING, CRIT_RATING,
-- etc.) are a best guess at what wowtbc.gg will call them once dungeons with
-- combat-rating gear get converted -- none have shown up in real converted
-- data yet (Hall of Thanes/The Stockade only have primary stats + a few
-- caster stats), so verify/correct these key names against a real example
-- the first time one of these stats actually appears in Data/*.lua.
local ROLE_PROFILES = {
    ["Physical DPS"] = {
        staminaWeight = 1.5, armorWeight = 0.15, dpsWeight = 3.0,
        secondary = {
            ATTACK_POWER = 0.5, HIT_RATING = 0.8, CRIT_RATING = 0.6, HASTE_RATING = 0.5,
            EXPERTISE_RATING = 0.6, ARMOR_PENETRATION_RATING = 0.5, RESILIENCE_RATING = 0.3,
            DODGE_RATING = 0.2, DEFENSE_RATING = 0.2, PARRY_RATING = 0.2, BLOCK_RATING = 0.2, BLOCK_VALUE = 0.1,
            SPELL_POWER = 0.1, MANA_REGEN = 0.1, SPELL_PENETRATION = 0.05,
        },
    },
    ["Caster DPS"] = {
        staminaWeight = 1.0, armorWeight = 0.1, dpsWeight = 0.3,
        secondary = {
            SPELL_POWER = 0.8, SPELL_HIT_RATING = 0.7, SPELL_CRIT_RATING = 0.6, SPELL_HASTE_RATING = 0.5,
            MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, RESILIENCE_RATING = 0.3,
            ATTACK_POWER = 0.05, HIT_RATING = 0.05, CRIT_RATING = 0.1, HASTE_RATING = 0.1,
        },
    },
    ["Healer"] = {
        staminaWeight = 1.2, armorWeight = 0.08, dpsWeight = 0.1,
        secondary = {
            SPIRIT = 2.0,  -- overrides the generic non-primary-stat fallback weight below
            SPELL_POWER = 0.8, SPELL_HEALING = 0.8, SPELL_HIT_RATING = 0.5, SPELL_CRIT_RATING = 0.4, SPELL_HASTE_RATING = 0.4,
            MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05, RESILIENCE_RATING = 0.2,
        },
    },
    ["Tank"] = {
        staminaWeight = 2.5, armorWeight = 0.3, dpsWeight = 1.0,
        secondary = {
            DEFENSE_RATING = 1.0, DODGE_RATING = 0.8, PARRY_RATING = 0.7, BLOCK_RATING = 0.6, BLOCK_VALUE = 0.5,
            RESILIENCE_RATING = 0.2,
            ATTACK_POWER = 0.2, HIT_RATING = 0.3, CRIT_RATING = 0.2, HASTE_RATING = 0.1,
            EXPERTISE_RATING = 0.3, ARMOR_PENETRATION_RATING = 0.05,
        },
    },
}

local function GetRoleProfile(role)
    return ROLE_PROFILES[role] or ROLE_PROFILES["Physical DPS"]
end

-- Stat keys that are handled separately (armor/dps/weapon speed) or aren't
-- numeric (weapon damage range) -- never fed into the generic per-stat loop.
local EXCLUDED_STAT_KEYS = { ARMOR = true, WEAPON_DPS = true, WEAPON_SPEED = true, WEAPON_DAMAGE = true }

-- Computes a single comparable score from a stats table (our own item.stats
-- shape, or the live-read equivalent from NormalizeLiveStats below), plus
-- armor value and weapon DPS (0 for non-weapon/non-armor items).
local function ScoreItem(stats, primaryStat, role, armorValue, dps)
    local profile = GetRoleProfile(role)
    local score = 0

    for statName, value in pairs(stats or {}) do
        if type(value) == "number" and not EXCLUDED_STAT_KEYS[statName] then
            local weight
            if statName == primaryStat then
                weight = 3.0
            elseif statName == "STAMINA" then
                weight = profile.staminaWeight
            elseif profile.secondary[statName] then
                weight = profile.secondary[statName]
            elseif statName == "AGILITY" or statName == "STRENGTH" or statName == "INTELLECT" or statName == "SPIRIT" then
                weight = 0.5  -- a primary-ish stat that isn't yours
            else
                weight = 0.3  -- unmapped fallback
            end
            score = score + (value * weight)
        end
    end

    score = score + ((armorValue or 0) * profile.armorWeight)
    score = score + ((dps or 0) * profile.dpsWeight)
    return score
end

-- ===== Live equipped-item stat reading =====
-- GetItemStats() doesn't reliably expose an item's base Armor value -- the
-- standard workaround is scanning a hidden tooltip's rendered text for the
-- "N Armor" line, since there's no clean API for it.
local scanTooltip = CreateFrame("GameTooltip", "EverGear_ScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function ScanArmorFromLink(itemLink)
    if not itemLink then return 0 end
    scanTooltip:ClearLines()
    scanTooltip:SetHyperlink(itemLink)
    for i = 1, scanTooltip:NumLines() do
        local line = _G["EverGear_ScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            local armor = text:match("^(%d+) Armor$")
            if armor then return tonumber(armor) end
        end
    end
    return 0
end

-- Maps GetItemStats()/C_Item.GetItemStats() key names to our own stat names,
-- so a live-read equipped item scores on the same scale as a candidate from
-- our database. Primary stats keep the _SHORT suffix; the TBC-era combat
-- ratings (Hit/Crit/Haste/Defense/Dodge/Parry/Block/Resilience/Expertise/
-- ArmorPen) drop it -- this split was confirmed against real GetItemStats()
-- output while building the TBC sibling addon's Upgrades.lua, and reused
-- here since Blizzard's own key-naming convention doesn't change per game.
local API_KEY_TO_STAT = {
    ITEM_MOD_AGILITY_SHORT = "AGILITY", ITEM_MOD_STRENGTH_SHORT = "STRENGTH",
    ITEM_MOD_INTELLECT_SHORT = "INTELLECT", ITEM_MOD_SPIRIT_SHORT = "SPIRIT",
    ITEM_MOD_STAMINA_SHORT = "STAMINA",
    ITEM_MOD_DEFENSE_SKILL_RATING = "DEFENSE_RATING", ITEM_MOD_DODGE_RATING = "DODGE_RATING",
    ITEM_MOD_PARRY_RATING = "PARRY_RATING", ITEM_MOD_BLOCK_RATING = "BLOCK_RATING",
    ITEM_MOD_HIT_RATING = "HIT_RATING", ITEM_MOD_CRIT_RATING = "CRIT_RATING",
    ITEM_MOD_HASTE_RATING = "HASTE_RATING",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELL_HIT_RATING", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELL_CRIT_RATING",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "SPELL_HASTE_RATING",
    ITEM_MOD_RESILIENCE_RATING = "RESILIENCE_RATING", ITEM_MOD_EXPERTISE_RATING = "EXPERTISE_RATING",
    ITEM_MOD_ARMOR_PENETRATION_RATING = "ARMOR_PENETRATION_RATING",
    ITEM_MOD_ATTACK_POWER_SHORT = "ATTACK_POWER", ITEM_MOD_SPELL_POWER_SHORT = "SPELL_POWER",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MANA_REGEN", ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELL_PENETRATION",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCK_VALUE",
}
local DPS_API_KEY = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

local function SafeGetItemStats(itemLink)
    if C_Item and C_Item.GetItemStats then return C_Item.GetItemStats(itemLink) end
    if GetItemStats then return GetItemStats(itemLink) end
    return nil
end

-- Returns (stats, armorValue, dpsValue) for a real item link, read live from
-- the client -- used for whatever's currently equipped when it isn't (yet)
-- in our own database.
local function NormalizeLiveStats(itemLink)
    if not itemLink then return {}, 0, 0 end

    local stats = {}
    local apiStats = SafeGetItemStats(itemLink) or {}
    for apiKey, statName in pairs(API_KEY_TO_STAT) do
        if apiStats[apiKey] then
            stats[statName] = apiStats[apiKey]
        end
    end

    local armorValue = ScanArmorFromLink(itemLink)
    local dpsValue = apiStats[DPS_API_KEY] or 0
    return stats, armorValue, dpsValue
end

-- ===== Class usability (armor type / weapon type / shield) =====

local ARMOR_TYPE_ORDER = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }
local CLASS_MAX_ARMOR = {
    WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2,
    PRIEST = 1, MAGE = 1, WARLOCK = 1,
}

-- Best-effort per-class weapon-type whitelist (TBC-era classic weapon
-- skills), translated from item subclass IDs to our data's lowercase weapon-
-- type strings. wowtbc.gg's raw item data doesn't distinguish one-hand from
-- two-hand for axes/maces/swords, so both are unioned into one entry here --
-- a known simplification (e.g. a class restricted to 1H axes only will also
-- see 2H axes suggested). Flag any class+weapon combo that looks wrong in
-- practice and we'll correct that specific entry.
local CLASS_USABLE_WEAPON_TYPES = {
    WARRIOR = { axe = true, bow = true, gun = true, mace = true, polearm = true, sword = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    PALADIN = { axe = true, mace = true, polearm = true, sword = true, dagger = true },
    HUNTER  = { axe = true, bow = true, gun = true, polearm = true, sword = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    ROGUE   = { bow = true, gun = true, sword = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    PRIEST  = { mace = true, staff = true, dagger = true, wand = true },
    SHAMAN  = { axe = true, mace = true, staff = true, ["fist weapon"] = true, dagger = true },
    MAGE    = { sword = true, staff = true, dagger = true, wand = true },
    WARLOCK = { sword = true, staff = true, dagger = true, wand = true },
    DRUID   = { mace = true, staff = true, ["fist weapon"] = true, dagger = true },
}

local CLASS_CAN_USE_SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }

local function IsArmorTypeAllowed(item, classToken)
    if not item.armorType then return true end  -- not armor -- handled elsewhere
    local rank = ARMOR_TYPE_ORDER[item.armorType]
    if not rank then return true end
    return rank <= (CLASS_MAX_ARMOR[classToken] or 4)
end

local function IsWeaponTypeAllowed(item, classToken)
    if not item.weaponType then return true end  -- not a weapon/shield
    if item.weaponType == "shield" then
        return CLASS_CAN_USE_SHIELD[classToken] == true
    end
    local whitelist = CLASS_USABLE_WEAPON_TYPES[classToken]
    if not whitelist then return true end
    return whitelist[item.weaponType] == true
end

-- ===== Public interface =====

-- Returns (candidates, currentScore) for a REAL slot token:
--   candidates   = a list of { item = <item>, score = <number> }, best first,
--                  restricted to the player's level, class-usable armor/
--                  weapon types, and only items that beat currentScore.
--   currentScore = the score of whatever is currently equipped in that slot
--                  (0 if the slot is empty).
function EverGear:GetUpgradesForSlot(realSlotToken, equippedItemLink)
    local playerInfo = self:GetPlayerInfo()
    local role = self:GetRoleForSpec(playerInfo.classToken, EverGearDB.spec)
    local primaryStat = self:GetPrimaryStat(playerInfo.classToken, role)

    -- Look-ahead: show items up to the slider's chosen level (set via UI.lua's
    -- slider, player's current level - 30). EverGearDB.lookaheadLevel is an
    -- ABSOLUTE target level, not a delta -- UI.lua keeps it clamped to at
    -- least the player's current level, but never below it here either in
    -- case that sync hasn't run yet (e.g. right after a level-up). This only
    -- widens the minLevel filter below -- it doesn't change scoring or
    -- class/weapon usability.
    local effectiveLevel = math.max(playerInfo.level, EverGearDB.lookaheadLevel or playerInfo.level)

    local equippedItemId = self:GetItemIDFromLink(equippedItemLink)
    -- Prefer our own extracted data over the live API when we have it for the
    -- equipped item -- GetItemStats() isn't reliable for stats granted via an
    -- on-equip spell aura, which can silently undervalue an equipped item
    -- that uses one. Falls back to a live read for anything not in our (still
    -- very small) database yet, which is the common case for now.
    local equippedStats, equippedArmor, equippedDPS
    local equippedData = equippedItemId and self:GetItem(equippedItemId)
    if equippedData then
        equippedStats, equippedArmor, equippedDPS = equippedData.stats, (equippedData.stats and equippedData.stats.ARMOR) or 0, (equippedData.stats and equippedData.stats.WEAPON_DPS) or 0
    else
        equippedStats, equippedArmor, equippedDPS = NormalizeLiveStats(equippedItemLink)
    end
    local currentScore = ScoreItem(equippedStats, primaryStat, role, equippedArmor, equippedDPS)

    local candidates = {}
    for _, item in ipairs(self:GetItemsForSlot(realSlotToken)) do
        if item.id ~= equippedItemId
            and (not item.minLevel or item.minLevel <= effectiveLevel)
            and IsArmorTypeAllowed(item, playerInfo.classToken)
            and IsWeaponTypeAllowed(item, playerInfo.classToken)
        then
            local armorValue = (item.stats and item.stats.ARMOR) or 0
            local dpsValue = (item.stats and item.stats.WEAPON_DPS) or 0
            local score = ScoreItem(item.stats, primaryStat, role, armorValue, dpsValue)
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
