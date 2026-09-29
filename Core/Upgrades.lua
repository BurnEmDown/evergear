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
-- Caster-exclusive secondary stats (spell power/healing, mana regen, spell
-- hit/crit/haste, spell penetration) -- worth exactly 0 to a melee role
-- (Physical DPS/Tank), which has no mana bar and no spells to cast. And the
-- reverse: melee-exclusive stats (attack power, physical hit/crit/haste,
-- expertise, armor penetration, and the tank-defense cluster) are worth 0 to
-- a caster role (Caster DPS/Healer). Both groups are listed explicitly with
-- a weight of 0 in every profile below, rather than left out, specifically
-- so they can NEVER fall through to the generic "unmapped stat" fallback
-- further down and accidentally get counted as real value -- which is
-- exactly how a Warrior ended up seeing a weak spell-power mace outscore a
-- much better weapon: Physical DPS explicitly weighted SPELL_POWER at 0.1
-- (nonzero!), and Tank didn't mention it at all, so it fell through to the
-- 0.3-per-point fallback meant for stats no profile has ever heard of yet.
local CASTER_ONLY_STATS = {
    SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_RATING = 0,
    SPELL_CRIT_RATING = 0, SPELL_HASTE_RATING = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0,
    -- Vanilla-era stat-name variant of SPELL_POWER (pre-unification, tracker
    -- data still uses this key for older items -- see "Scepter of the
    -- Abandoned", a weak mace that scored artificially high for a Warrior
    -- because SPELL_DAMAGE fell through to the generic unmapped fallback
    -- below instead of being recognized as a caster-only stat). Also its
    -- damage-school-specific siblings, which only matter to a spellcaster.
    SPELL_DAMAGE = 0, FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0,
    FROST_DAMAGE = 0, NATURE_DAMAGE = 0,
}
local MELEE_ONLY_STATS = {
    ATTACK_POWER = 0, HIT_RATING = 0, CRIT_RATING = 0, HASTE_RATING = 0,
    EXPERTISE_RATING = 0, ARMOR_PENETRATION_RATING = 0,
    DEFENSE_RATING = 0, DODGE_RATING = 0, PARRY_RATING = 0, BLOCK_RATING = 0, BLOCK_VALUE = 0,
    -- Melee/physical-only stats: bonus physical damage, conditional attack
    -- power (vs a creature type), ranged attack power (bows/guns/thrown --
    -- still a physical weapon, just not melee range), and the old flat
    -- "Defense" skill stat (distinct from DEFENSE_RATING) -- none of these
    -- do anything for a caster who never swings a weapon.
    PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0,
    ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0, DEFENSE = 0,
}
-- Stats worth roughly the same to every role -- small utility value (resist
-- gear, slow-effect resistance) that isn't exclusive to any one role, so it's
-- given a modest flat weight everywhere rather than 0 in half the profiles
-- (which would just recreate the same "unmapped stat" trap for the other
-- half) or left to the 0.3 fallback (which both over- and under-values it
-- depending on role).
local UNIVERSAL_STATS = {
    ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1,
    NATURE_RESISTANCE = 0.1, SHADOW_RESISTANCE = 0.1,
    MOVEMENT_IMPAIRING_REDUCTION = 0.2,
    -- Flat damage-taken reduction from spells -- a defensive stat useful to
    -- every role (a caster tanking a debuff, a healer avoiding a one-shot,
    -- and especially a tank), not exclusive to casters despite the name.
    SPELL_DAMAGE_REDUCTION = 0.3,
}

-- Shallow-merges any number of stat-weight tables into a new table, later
-- tables overriding earlier ones -- used below so each role profile is
-- "everything irrelevant is 0, then here's what actually matters", instead
-- of relying on omission (which is what created the bug above).
local function MergeWeights(...)
    local out = {}
    for _, tbl in ipairs({ ... }) do
        for k, v in pairs(tbl) do out[k] = v end
    end
    return out
end

local ROLE_PROFILES = {
    ["Physical DPS"] = {
        staminaWeight = 1.5, armorWeight = 0.15, dpsWeight = 3.0,
        secondary = MergeWeights(CASTER_ONLY_STATS, UNIVERSAL_STATS, {
            ATTACK_POWER = 0.5, HIT_RATING = 0.8, CRIT_RATING = 0.6, HASTE_RATING = 0.5,
            EXPERTISE_RATING = 0.6, ARMOR_PENETRATION_RATING = 0.5, RESILIENCE_RATING = 0.3,
            DODGE_RATING = 0.2, DEFENSE_RATING = 0.2, PARRY_RATING = 0.2, BLOCK_RATING = 0.2, BLOCK_VALUE = 0.1,
            PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15,
            ATTACK_POWER_VS_UNDEAD = 0.15, RANGED_ATTACK_POWER = 0.4, DEFENSE = 0.1,
            THREAT_REDUCTION = 0.2,
        }),
    },
    ["Caster DPS"] = {
        staminaWeight = 1.0, armorWeight = 0.1, dpsWeight = 0.3,
        secondary = MergeWeights(MELEE_ONLY_STATS, UNIVERSAL_STATS, {
            SPELL_POWER = 0.8, SPELL_HIT_RATING = 0.7, SPELL_CRIT_RATING = 0.6, SPELL_HASTE_RATING = 0.5,
            MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, RESILIENCE_RATING = 0.3,
            SPELL_DAMAGE = 0.8, FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.4,
            FROST_DAMAGE = 0.4, NATURE_DAMAGE = 0.4,
            THREAT_REDUCTION = 0.2,
        }),
    },
    ["Healer"] = {
        staminaWeight = 1.2, armorWeight = 0.08, dpsWeight = 0.1,
        secondary = MergeWeights(MELEE_ONLY_STATS, UNIVERSAL_STATS, {
            SPIRIT = 2.0,  -- overrides the generic non-primary-stat fallback weight below
            SPELL_POWER = 0.8, SPELL_HEALING = 0.8, SPELL_HIT_RATING = 0.5, SPELL_CRIT_RATING = 0.4, SPELL_HASTE_RATING = 0.4,
            MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05, RESILIENCE_RATING = 0.2,
            SPELL_DAMAGE = 0.4,  -- healing power matters far more than raw spell damage to this role
            THREAT_REDUCTION = 0.2,
        }),
    },
    ["Tank"] = {
        staminaWeight = 2.5, armorWeight = 0.3, dpsWeight = 1.0,
        secondary = MergeWeights(CASTER_ONLY_STATS, UNIVERSAL_STATS, {
            DEFENSE_RATING = 1.0, DODGE_RATING = 0.8, PARRY_RATING = 0.7, BLOCK_RATING = 0.6, BLOCK_VALUE = 0.5,
            RESILIENCE_RATING = 0.2,
            ATTACK_POWER = 0.2, HIT_RATING = 0.3, CRIT_RATING = 0.2, HASTE_RATING = 0.1,
            EXPERTISE_RATING = 0.3, ARMOR_PENETRATION_RATING = 0.05,
            DEFENSE = 1.0, PHYSICAL_DAMAGE = 0.1, ATTACK_POWER_VS_BEASTS = 0.05,
            ATTACK_POWER_VS_HUMANOIDS = 0.05, ATTACK_POWER_VS_UNDEAD = 0.05, RANGED_ATTACK_POWER = 0.05,
            THREAT_REDUCTION = 0,  -- a tank wants threat, not less of it
        }),
    },
}

local function GetRoleProfile(role)
    return ROLE_PROFILES[role] or ROLE_PROFILES["Physical DPS"]
end

-- Stat keys that are handled separately (armor/dps/weapon speed) or aren't
-- numeric (weapon damage range) -- never fed into the generic per-stat loop.
-- HERBALISM/LOCKPICKING are profession-skill bonuses (gathering/utility, not
-- combat) -- never worth anything to any of the 4 combat role profiles, so
-- excluded outright rather than left to fall through to the 0.3 fallback.
local EXCLUDED_STAT_KEYS = {
    ARMOR = true, WEAPON_DPS = true, WEAPON_SPEED = true, WEAPON_DAMAGE = true,
    HERBALISM = true, LOCKPICKING = true,
}

-- How much each of the 4 primary-ish stats (STR/AGI/INT/SPI) is worth to a
-- role when it ISN'T that role's chosen primary stat. This used to be one
-- flat 0.5 for all four regardless of role -- which meant a Retribution
-- Paladin (Physical DPS, primary STRENGTH) saw INTELLECT and SPIRIT valued
-- almost as highly as AGILITY, even though a melee DPS gets nothing from
-- casting stats. That's what was pulling healing/caster gear up into
-- "upgrade" suggestions it had no business being in. Tuned per role instead.
local OFF_STAT_WEIGHT = {
    ["Physical DPS"] = { STRENGTH = 0.15, AGILITY = 0.3,  INTELLECT = 0.05, SPIRIT = 0.05 },
    ["Caster DPS"]   = { STRENGTH = 0.05, AGILITY = 0.05, INTELLECT = 0.3,  SPIRIT = 0.3 },
    ["Healer"]       = { STRENGTH = 0.05, AGILITY = 0.05, INTELLECT = 0.3,  SPIRIT = 0.3 },
    ["Tank"]         = { STRENGTH = 0.15, AGILITY = 0.25, INTELLECT = 0.05, SPIRIT = 0.05 },
}

-- Computes a single comparable score from a stats table (our own item.stats
-- shape, or the live-read equivalent from NormalizeLiveStats below), plus
-- armor value and weapon DPS (0 for non-weapon/non-armor items).
local function ScoreItem(stats, primaryStat, role, armorValue, dps)
    local profile = GetRoleProfile(role)
    local offStatWeights = OFF_STAT_WEIGHT[role] or OFF_STAT_WEIGHT["Physical DPS"]
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
            elseif offStatWeights[statName] then
                weight = offStatWeights[statName]
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

-- Classic armor proficiency: Warriors/Paladins don't train Plate, and
-- Hunters/Shamans don't train Mail, until level 40 -- before that they're
-- capped one armor tier below CLASS_MAX_ARMOR's eventual max (Warriors/
-- Paladins wear Mail, Hunters/Shamans wear Leather). Rogues/Druids/casters
-- never gain a higher tier, so they're absent here and unaffected.
local ARMOR_PROFICIENCY_UNLOCK_LEVEL = 40
local CLASS_ARMOR_UNLOCK_LEVEL = {
    WARRIOR = ARMOR_PROFICIENCY_UNLOCK_LEVEL, PALADIN = ARMOR_PROFICIENCY_UNLOCK_LEVEL,
    HUNTER = ARMOR_PROFICIENCY_UNLOCK_LEVEL, SHAMAN = ARMOR_PROFICIENCY_UNLOCK_LEVEL,
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

-- Exposed so UI.lua can build the weapon-type filter checklist from the same
-- per-class whitelist used for usability checks below, rather than keeping a
-- second copy that could drift out of sync.
EverGear.CLASS_USABLE_WEAPON_TYPES = CLASS_USABLE_WEAPON_TYPES
EverGear.CLASS_CAN_USE_SHIELD = CLASS_CAN_USE_SHIELD

-- Some items are restricted to specific classes regardless of armor/weapon
-- type -- a caster relic like "Orb of Soran'ruk" (Warlock-only) has no armor
-- type and no real weapon type to gate on, so without this it would be
-- suggested to every class. item.classes is nil for anything unrestricted.
local function IsClassAllowed(item, classToken)
    if not item.classes then return true end
    for _, allowedToken in ipairs(item.classes) do
        if allowedToken == classToken then return true end
    end
    return false
end

local function IsArmorTypeAllowed(item, classToken, level)
    if not item.armorType then return true end  -- not armor -- handled elsewhere
    local rank = ARMOR_TYPE_ORDER[item.armorType]
    if not rank then return true end
    local maxRank = CLASS_MAX_ARMOR[classToken] or 4
    -- The class's eventual top tier is locked out below the proficiency
    -- level (see CLASS_ARMOR_UNLOCK_LEVEL) -- checked against `level`, the
    -- caller's effective/look-ahead level, so looking ahead to 40+ correctly
    -- reveals it (including strong sub-40 items in that tier, per design).
    local unlockLevel = CLASS_ARMOR_UNLOCK_LEVEL[classToken]
    if unlockLevel and rank == maxRank and (level or 0) < unlockLevel then
        maxRank = maxRank - 1
    end
    return rank <= maxRank
end

-- One filter map for every weapon-type checkbox, instead of a separate
-- "exclude two-handed" toggle bolted on beside it -- for the handful of types
-- the data can tell 1H/2H apart on (Constants.lua's SPLIT_WEAPON_TYPES), the
-- filter key includes that suffix (e.g. "axe:2h"), matching how real WoW item
-- subclass IDs already split those into distinct subclasses. Every other type
-- (Dagger, Staff, Bow, ...) just uses its bare weaponType as the key. UI.lua
-- builds the checklist using this exact same key scheme so a checkbox and
-- what it filters can never drift apart.
function EverGear:GetWeaponFilterKey(item)
    if not item.weaponType then return nil end
    if EverGear.SPLIT_WEAPON_TYPES[item.weaponType] and item.isTwoHand ~= nil then
        return item.weaponType .. (item.isTwoHand and ":2h" or ":1h")
    end
    return item.weaponType
end

-- Whether a weapon-type filter key (the same keys the checklist and
-- GetWeaponFilterKey use, including a ":1h"/":2h" suffix) is actually usable
-- by a given class at all. This does NOT gate what gets suggested by
-- itself -- IsWeaponTypeAllowed below still does that, independently of
-- whatever the player later does with the checkbox -- it's only used to
-- pick each row's initial checked state (unusable = off by default, e.g. a
-- Paladin starts with every ranged weapon type unchecked) and to recompute
-- that same state on demand via the filter panel's "Usable Only" button.
function EverGear:IsWeaponFilterKeyUsable(filterKey, classToken)
    local baseType = filterKey:match("^(.-):[12]h$") or filterKey
    if baseType == "shield" then
        return CLASS_CAN_USE_SHIELD[classToken] == true
    end
    if baseType == "offhand" then
        return true  -- relic-style items -- see IsWeaponTypeAllowed below
    end
    local whitelist = CLASS_USABLE_WEAPON_TYPES[classToken]
    return whitelist ~= nil and whitelist[baseType] == true
end

local function IsWeaponTypeAllowed(item, classToken)
    if not item.weaponType then return true end  -- not a weapon/shield
    if item.weaponType == "shield" then
        return CLASS_CAN_USE_SHIELD[classToken] == true
    end
    if item.weaponType == "offhand" then
        -- A relic-style held-in-off-hand item (Libram/Idol/Totem/Orb/etc) --
        -- not gated by CLASS_USABLE_WEAPON_TYPES at all, since that table is
        -- only ever populated with real weapon subtypes and has no "offhand"
        -- key for any class -- treating it like the others would hide these
        -- items from EVERY class. The real per-class restriction for these
        -- (a Warlock-only Orb, say) lives in the source data's dropped
        -- other_stats.classes field, which the converter doesn't thread
        -- through yet -- a known gap, not something this filter should mask.
        return true
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

    -- Player-chosen weapon-type opt-outs (e.g. a tank who never wants
    -- two-handers suggested even though their class/spec can technically use
    -- them) -- set via UI.lua's weapon-type filter panel. Off by default for
    -- everyone; a class-usable weapon type only ever gets hidden if the
    -- player explicitly unchecked it. Missing from the table (never touched
    -- by the player, or a class/spec that's never seen this weapon type
    -- before) means "shown" -- only an explicit false hides it.
    local weaponTypeFilter = EverGearDB.weaponTypeFilter or {}

    -- Same idea for crafted items: EverGearDB.professionFilter[profName] ==
    -- false hides that profession's items specifically (e.g. only
    -- Blacksmithing checked hides Leatherworking/Tailoring/etc crafted
    -- suggestions), set via UI.lua's profession filter panel. Only ever
    -- checked for source.type == "craft" items that actually name a
    -- profession -- everything else (dungeon drops, quests, vendor items)
    -- is untouched by this filter regardless of its state.
    local professionFilter = EverGearDB.professionFilter or {}

    local candidates = {}
    for _, item in ipairs(self:GetItemsForSlot(realSlotToken)) do
        local itemFaction = item.source and item.source.faction
        -- Faction-locked quest rewards (item.source.faction) are only ever
        -- obtainable by that faction -- skip them for the other one entirely
        -- rather than suggesting an "upgrade" the player can never get. If
        -- the player's own faction can't be read for some reason, don't
        -- filter (better to over-show than silently hide real options).
        local factionAllowed = (not itemFaction) or (not playerInfo.faction) or itemFaction == playerInfo.faction

        local filterKey = self:GetWeaponFilterKey(item)
        local weaponTypeAllowed = (not filterKey) or (weaponTypeFilter[filterKey] ~= false)

        local itemProfession = item.source and item.source.type == "craft" and item.source.profession
        local professionAllowed = (not itemProfession) or (professionFilter[itemProfession] ~= false)

        if item.id ~= equippedItemId
            and (not item.minLevel or item.minLevel <= effectiveLevel)
            and IsArmorTypeAllowed(item, playerInfo.classToken, effectiveLevel)
            and IsWeaponTypeAllowed(item, playerInfo.classToken)
            and IsClassAllowed(item, playerInfo.classToken)
            and factionAllowed
            and weaponTypeAllowed
            and professionAllowed
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
        -- Mirrors the dungeonDrop "Zone (Boss)" format below so both source
        -- types read the same way at a glance -- zone first (where to go),
        -- then what to do there.
        local questName = source.quest or "Unknown quest"
        if source.zone then
            return source.zone .. " (Quest: " .. questName .. ")"
        end
        return "Quest: " .. questName
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
        return "Crafted" .. (source.profession and (" (" .. source.profession .. ")") or "")
    end
    return "Unknown source"
end
