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

-- There used to be a CLASS_ROLE_PRIMARY_STAT table + GetPrimaryStat(classToken,
-- role) here, used by ScoreItem to decide which one stat got a profile's
-- generic `primaryStatWeight`. Removed per user feedback -- it made a
-- profile's grid show an opaque "Primary Stat" row with no indication of
-- which actual stat it affected. Every spec below now just names its own
-- stats directly in its `stats` table (e.g. a Warrior's is
-- `{ STRENGTH = 3.0, ... }`), so there's no separate "which stat is
-- primary" lookup left to do -- see SPEC_PROFILES and ScoreItem below.

-- Per-class-spec scoring profile: which secondary stats matter, plus how
-- much Stamina/armor/weapon-DPS/off-stats (STR/AGI/INT/SPI when not the
-- primary stat) matter, for EVERY class+spec individually (EverGear.
-- SPEC_PROFILES below) -- not shared by role. This used to be one table
-- per role (Physical DPS/Caster DPS/Healer/Tank) that every class+spec
-- mapped to that role shared -- e.g. tuning Warrior would have also
-- silently changed Rogue/Hunter/Paladin/Shaman/Druid, since they all map
-- to "Physical DPS" too. Keeping every class+spec's numbers independent
-- means editing one can never leak into another, at the cost of some
-- duplication between specs that happen to want the same numbers (most of
-- them, until tuned otherwise) -- an intentional trade favoring safety over
-- DRY-ness here, since these values get hand-tuned piecemeal over time.
--
-- Within each spec's `secondary` table: caster-exclusive stats (spell
-- power/healing, mana regen, spell hit/crit/haste, spell penetration, the
-- damage-school-specific SPELL_DAMAGE/FIRE_DAMAGE/etc variants) are listed
-- at exactly 0 for every melee/physical spec, and melee-exclusive stats
-- (attack power, physical hit/crit/haste, expertise, armor penetration,
-- the tank-defense cluster) are listed at exactly 0 for every caster/
-- healer spec -- explicitly, rather than simply omitted, so they can NEVER
-- fall through to the generic "unmapped stat" 0.3-per-point fallback
-- further down and accidentally get counted as real value. That fallback
-- gap is exactly how a Warrior once saw a weak spell-power mace outscore a
-- much better weapon (SPELL_POWER/SPELL_DAMAGE fell through to 0.3/point
-- instead of being recognized as caster-only) -- see git history on this
-- file if the details matter.
--
-- Hit/Crit/Haste/Dodge/Parry/Block (and the spell equivalents) are named
-- HIT_CHANCE/CRIT_CHANCE/HASTE/DODGE_CHANCE/PARRY_CHANCE/BLOCK_CHANCE/
-- SPELL_HIT_CHANCE/SPELL_CRIT_CHANCE/SPELL_HASTE, not "...RATING" --
-- confirmed with the player that WoW Forever has no TBC-style scaling
-- "rating" stat at all: an item just grants the flat percentage directly
-- (e.g. "Equip: Increases your chance to hit by 0.3%" is stored/scored as
-- HIT_CHANCE = 0.3, not run through a rating-to-percent conversion). Every
-- weight below for these keys is therefore priced per PERCENTAGE POINT, a
-- much bigger number than the old (wrong) per-rating-point guess -- e.g.
-- Warrior's CRIT_CHANCE = 13.2 here used to be CRIT_RATING = 0.6, rescaled
-- by the old guessed rating-per-% conversion (*22) to preserve this spec's
-- existing relative emphasis on the stat now that the unit itself changed,
-- not because any of these per-class numbers are independently verified --
-- same hand-tuned/piecemeal caveat as the rest of this table applies to the
-- rescaled numbers too. Expertise and Resilience are confirmed to not exist
-- as mechanics in this game at all (removed outright, not just zeroed), and
-- Armor Penetration is confirmed to be a flat armor-reduction value (not a
-- percentage), so ARMOR_PENETRATION kept its old per-point weight unchanged
-- -- only its name lost the misleading "_RATING" suffix.
--
EverGear.SPEC_PROFILES = {
    WARRIOR = {
        ["Arms"] = {  -- role: Physical DPS
            stats = { STRENGTH = 3.0, AGILITY = 0.3, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.5, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0.1,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.1, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Fury"] = {  -- role: Physical DPS
            stats = { STRENGTH = 3.0, AGILITY = 0.3, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.5, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0.1,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.1, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Protection"] = {  -- role: Tank
            stats = { STRENGTH = 3.0, AGILITY = 0.3, STAMINA = 2.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.3, dpsWeight = 1.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Tank-specific stats
                DODGE_CHANCE = 15.84, PARRY_CHANCE = 13.86, BLOCK_CHANCE = 11.88,
                BLOCK_VALUE = 0.5, ATTACK_POWER = 0.2, HIT_CHANCE = 4.74,
                CRIT_CHANCE = 4.4, HASTE = 1.58, ARMOR_PENETRATION = 0.05,
                DEFENSE = 1.0, PHYSICAL_DAMAGE = 0.1, ATTACK_POWER_VS_BEASTS = 0.05, ATTACK_POWER_VS_HUMANOIDS = 0.05,
                ATTACK_POWER_VS_UNDEAD = 0.05, RANGED_ATTACK_POWER = 0.05, THREAT_REDUCTION = 0,
                HP5 = 0.4, MP5 = 0,
            },
        },
    },
    PALADIN = {
        ["Holy"] = {  -- role: Healer
            -- SPIRIT = 1, not the generic 0.3 fallback -- this was hand-tuned
            -- (found inside the old `secondary` table's "Healer-specific
            -- stats" as a real SPIRIT=1 entry, missed during the primary-
            -- stat refactor since every OTHER healer spec deliberately
            -- omits its primary stat from `secondary`, so this one's
            -- survival there read like 0.3-fallback territory at a glance).
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.2, INTELLECT = 3.0, SPIRIT = 1 }, armorWeight = 0.08, dpsWeight = 0.1,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Healer-specific stats (Spirit's own weight lives in this
                -- spec's `stats` table above, alongside every other main stat)
                SPELL_POWER = 0.8, SPELL_HEALING = 1.4, SPELL_HIT_CHANCE = 13,
                SPELL_CRIT_CHANCE = 8.8, SPELL_HASTE = 6.32, MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05,
                SPELL_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.6,
            },
        },
        ["Protection"] = {  -- role: Tank
            stats = { STRENGTH = 3.0, AGILITY = 0.5, STAMINA = 2.5, INTELLECT = 0.25, SPIRIT = 0.05 }, armorWeight = 0.3, dpsWeight = 1.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 1.2, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Tank-specific stats
                DODGE_CHANCE = 15.84, PARRY_CHANCE = 13.86, BLOCK_CHANCE = 11.88,
                BLOCK_VALUE = 0.5, ATTACK_POWER = 0.2, HIT_CHANCE = 4.74,
                CRIT_CHANCE = 4.4, HASTE = 1.58, ARMOR_PENETRATION = 0.05,
                DEFENSE = 1.0, PHYSICAL_DAMAGE = 0.1, ATTACK_POWER_VS_BEASTS = 0.05, ATTACK_POWER_VS_HUMANOIDS = 0.05,
                ATTACK_POWER_VS_UNDEAD = 0.05, RANGED_ATTACK_POWER = 0, THREAT_REDUCTION = 0,
                HP5 = 0.4, MP5 = 0,
            },
        },
        ["Retribution"] = {  -- role: Physical DPS
            stats = { STRENGTH = 3.0, AGILITY = 1, STAMINA = 1.5, INTELLECT = 0.1, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0.5, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 1, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0.1,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    HUNTER = {
        ["Beast Mastery"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.2, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 1, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.4, ATTACK_POWER_VS_HUMANOIDS = 0.4, ATTACK_POWER_VS_UNDEAD = 0.4,
                RANGED_ATTACK_POWER = 1.5, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.4,
            },
        },
        ["Marksmanship"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.2, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 1, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.4, ATTACK_POWER_VS_HUMANOIDS = 0.4, ATTACK_POWER_VS_UNDEAD = 0.4,
                RANGED_ATTACK_POWER = 1.5, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.4,
            },
        },
        ["Survival"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.2, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 1, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.4, ATTACK_POWER_VS_HUMANOIDS = 0.4, ATTACK_POWER_VS_UNDEAD = 0.4,
                RANGED_ATTACK_POWER = 1.5, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.4,
            },
        },
    },
    ROGUE = {
        ["Assassination"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.9, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.1, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Combat"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.9, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.1, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Subtlety"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.9, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.1, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    PRIEST = {
        ["Discipline"] = {  -- role: Healer (Spirit-primary for Priest -- see CLASS_ROLE_PRIMARY_STAT)
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.2, INTELLECT = 1, SPIRIT = 3.0 }, armorWeight = 0.08, dpsWeight = 0.1,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Healer-specific stats (Spirit's own weight lives in this
                -- spec's `stats` table above, alongside every other main stat)
                SPELL_POWER = 0.8, SPELL_HEALING = 1.4, SPELL_HIT_CHANCE = 13,
                SPELL_CRIT_CHANCE = 8.8, SPELL_HASTE = 6.32, MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05,
                SPELL_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.6,
            },
        },
        ["Holy"] = {  -- role: Healer (Spirit-primary for Priest -- see CLASS_ROLE_PRIMARY_STAT)
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.2, INTELLECT = 1, SPIRIT = 3.0 }, armorWeight = 0.08, dpsWeight = 0.1,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Healer-specific stats (Spirit's own weight lives in this
                -- spec's `stats` table above, alongside every other main stat)
                SPELL_POWER = 0.8, SPELL_HEALING = 1.4, SPELL_HIT_CHANCE = 13,
                SPELL_CRIT_CHANCE = 8.8, SPELL_HASTE = 6.32, MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05,
                SPELL_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.6,
            },
        },
        ["Shadow"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 1 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1.2, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 0.8,
                -- Shadow Damage weighted well above the other schools -- it's
                -- this spec's entire kit (Mind Flay/Shadow Word: Pain/etc).
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 1, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
    },
    SHAMAN = {
        ["Elemental"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0.05, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.3 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 0.8, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 0.8,
                -- Nature Damage weighted well above the other schools -- it's
                -- Elemental's actual nuke school (Lightning Bolt/Chain Lightning).
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
        ["Enhancement"] = {  -- role: Physical DPS (Strength-primary for Shaman -- see CLASS_ROLE_PRIMARY_STAT)
            stats = { STRENGTH = 3.0, AGILITY = 1, STAMINA = 1.5, INTELLECT = 0.3, SPIRIT = 0.3 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.5, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 3.96, BLOCK_VALUE = 0.1,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0.4, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.4,
            },
        },
        ["Restoration"] = {  -- role: Healer (Spirit-primary for Shaman -- see CLASS_ROLE_PRIMARY_STAT)
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.2, INTELLECT = 1, SPIRIT = 3.0 }, armorWeight = 0.08, dpsWeight = 0.1,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Healer-specific stats (Spirit's own weight lives in this
                -- spec's `stats` table above, alongside every other main stat)
                SPELL_POWER = 0.8, SPELL_HEALING = 1.2, SPELL_HIT_CHANCE = 13,
                SPELL_CRIT_CHANCE = 8.8, SPELL_HASTE = 6.32, MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05,
                SPELL_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.6,
            },
        },
    },
    MAGE = {
        ["Arcane"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.1 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- ARCANE_DAMAGE weighted higher than the other schools -- Arcane is
                -- this spec's actual nuke school, so +Arcane spell damage items are
                -- worth more to it than the flat 0.4 every caster gets by default.
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.7, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
        ["Fire"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.1 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- FIRE_DAMAGE weighted higher than the other schools -- Fire is this
                -- spec's actual nuke school, so +Fire spell damage items are worth
                -- more to it than the flat 0.4 every caster gets by default.
                FIRE_DAMAGE = 0.7, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
        ["Frost"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.1 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- FROST_DAMAGE weighted higher than the other schools -- Frost is
                -- this spec's actual nuke school, so +Frost spell damage items are
                -- worth more to it than the flat 0.4 every caster gets by default.
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.7,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
    },
    WARLOCK = {
        ["Affliction"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.01 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- Shadow is this spec's nuke school; Fire is not used, so it stays
                -- at the universal flat default rather than being boosted.
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.7, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0.2, MP5 = 0.5,
            },
        },
        ["Demonology"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.01 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- Fire and Shadow are both relevant nuke schools for Demonology's kit,
                -- so both get the boosted weight instead of the universal 0.4.
                FIRE_DAMAGE = 0.7, SHADOW_DAMAGE = 0.7, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0.2, MP5 = 0.5,
            },
        },
        ["Destruction"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.01 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 1, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 1,
                -- Fire and Shadow are both relevant nuke schools for Destruction's kit,
                -- so both get the boosted weight instead of the universal 0.4.
                FIRE_DAMAGE = 0.7, SHADOW_DAMAGE = 0.7, ARCANE_DAMAGE = 0.4, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0.2, MP5 = 0.5,
            },
        },
    },
    DRUID = {
        ["Balance"] = {  -- role: Caster DPS
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.0, INTELLECT = 3.0, SPIRIT = 0.5 }, armorWeight = 0.1, dpsWeight = 0.3,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Caster DPS-specific stats
                SPELL_POWER = 0.8, SPELL_HIT_CHANCE = 18.2, SPELL_CRIT_CHANCE = 13.2, SPELL_HASTE = 7.9,
                MANA_REGEN = 0.4, SPELL_PENETRATION = 0.3, SPELL_DAMAGE = 0.8,
                -- Nature and Arcane Damage weighted above the other schools --
                -- Balance's kit spans both (Starfire is Arcane, Wrath/Moonfire
                -- are Nature).
                FIRE_DAMAGE = 0.4, SHADOW_DAMAGE = 0.4, ARCANE_DAMAGE = 0.7, FROST_DAMAGE = 0.4,
                NATURE_DAMAGE = 0.7, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.5,
            },
        },
        ["Feral (DPS)"] = {  -- role: Physical DPS
            stats = { STRENGTH = 1, AGILITY = 3.0, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.05 }, armorWeight = 0.15, dpsWeight = 3.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Physical DPS-specific stats
                ATTACK_POWER = 0.5, HIT_CHANCE = 12.64, CRIT_CHANCE = 13.2, HASTE = 7.9,
                ARMOR_PENETRATION = 0.5, DODGE_CHANCE = 3.96,
                PARRY_CHANCE = 3.96, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0.3, ATTACK_POWER_VS_BEASTS = 0.15, ATTACK_POWER_VS_HUMANOIDS = 0.15, ATTACK_POWER_VS_UNDEAD = 0.15,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0.1, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Feral (Tank)"] = {  -- role: Tank
            stats = { STRENGTH = 2, AGILITY = 3.0, STAMINA = 2.5, INTELLECT = 0.05, SPIRIT = 0.05 }, armorWeight = 0.3, dpsWeight = 1.0,
            secondary = {
                -- Caster-exclusive stats -- 0 for this melee/physical role
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Tank-specific stats
                DODGE_CHANCE = 15.84, PARRY_CHANCE = 13.86, BLOCK_CHANCE = 0,
                BLOCK_VALUE = 0, ATTACK_POWER = 0.2, HIT_CHANCE = 4.74,
                CRIT_CHANCE = 4.4, HASTE = 1.58, ARMOR_PENETRATION = 0.05,
                DEFENSE = 1.0, PHYSICAL_DAMAGE = 0.1, ATTACK_POWER_VS_BEASTS = 0.05, ATTACK_POWER_VS_HUMANOIDS = 0.05,
                ATTACK_POWER_VS_UNDEAD = 0.05, RANGED_ATTACK_POWER = 0, THREAT_REDUCTION = 0,
                HP5 = 0.4, MP5 = 0,
            },
        },
        ["Restoration"] = {  -- role: Healer (Spirit-primary for Druid -- see CLASS_ROLE_PRIMARY_STAT)
            stats = { STRENGTH = 0, AGILITY = 0.05, STAMINA = 1.2, INTELLECT = 0.5, SPIRIT = 3.0 }, armorWeight = 0.08, dpsWeight = 0.1,
            secondary = {
                -- Melee-exclusive stats -- 0 for this caster/healer role
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                -- Universal utility stats
                ARCANE_RESISTANCE = 0.1, FIRE_RESISTANCE = 0.1, FROST_RESISTANCE = 0.1, NATURE_RESISTANCE = 0.1,
                SHADOW_RESISTANCE = 0.1, MOVEMENT_IMPAIRING_REDUCTION = 0.2, SPELL_DAMAGE_REDUCTION = 0.3,
                -- Healer-specific stats (Spirit's own weight lives in this
                -- spec's `stats` table above, alongside every other main stat)
                SPELL_POWER = 0.8, SPELL_HEALING = 1.2, SPELL_HIT_CHANCE = 13,
                SPELL_CRIT_CHANCE = 8.8, SPELL_HASTE = 6.32, MANA_REGEN = 0.6, SPELL_PENETRATION = 0.05,
                SPELL_DAMAGE = 0.4, THREAT_REDUCTION = 0.2,
                HP5 = 0, MP5 = 0.6,
            },
        },
    },
}

-- Stat keys that are handled separately (armor/dps/weapon speed) or aren't
-- numeric (weapon damage range) -- never fed into the generic per-stat loop.
-- HERBALISM/LOCKPICKING are profession-skill bonuses (gathering/utility, not
-- combat) -- never worth anything to any of the 4 combat role profiles, so
-- excluded outright rather than left to fall through to the 0.3 fallback.
local EXCLUDED_STAT_KEYS = {
    ARMOR = true, WEAPON_DPS = true, WEAPON_SPEED = true, WEAPON_DAMAGE = true,
    HERBALISM = true, LOCKPICKING = true,
}

-- Looks up the final scoring profile for a specific class+spec's ACTIVE
-- profile (EverGear:GetActiveProfile, Core/EPProfiles.lua) -- either the
-- read-only builtin from EverGear.SPEC_PROFILES, or the player's own custom
-- profile if they've selected one for this character. No role-level merging
-- happens here, so editing one class+spec's entry/profile can never affect
-- another's.
local function GetScoringProfile(classToken, specName)
    return EverGear:GetActiveProfile(classToken, specName)
end

-- "39 - 60 Damage" -> 39, 60. Also handles the single-value form some ranged/
-- thrown weapons use ("18 Damage", no dash). Returns nil, nil if `text` isn't
-- a weapon damage string at all (non-weapon items, or a live-read item whose
-- tooltip scan below found nothing).
local function ParseWeaponDamageRange(text)
    if type(text) ~= "string" then return nil, nil end
    local lo, hi = text:match("(%d+)%s*%-%s*(%d+)")
    if lo and hi then return tonumber(lo), tonumber(hi) end
    local single = text:match("^(%d+)%s*Damage$")
    if single then return tonumber(single), tonumber(single) end
    return nil, nil
end

-- Computes a single comparable score from a stats table (our own item.stats
-- shape, or the live-read equivalent from NormalizeLiveStats below), plus
-- armor value and weapon DPS (0 for non-weapon/non-armor items). `profile`
-- comes from GetScoringProfile (class+spec-aware) -- this function itself
-- doesn't know or care whether it came from a builtin or a custom profile.
--
-- Weapon scoring beyond raw DPS: a weapon's speed and its damage range carry
-- real, independent information DPS alone collapses away, so a profile can
-- weight them on top of (not instead of) dpsWeight --
--   avgDamageWeight: per point of average per-hit damage (dps * speed) --
--     what "weapon damage" special abilities (Heroic Strike, Mortal Strike,
--     Execute, etc.) actually roll against each swing, confirmed random
--     between the weapon's low and high end rather than weighted toward the
--     top -- see CUSTOM_EP_PROFILES_PLAN.md for the writeup. Two weapons
--     with the same average score identically here even if their min/max
--     spread differs, which is mechanically correct for expected damage.
--   maxDamageWeight: per point of the weapon's highest possible roll --
--     doesn't affect expected DPS, but is the right number for someone
--     explicitly optimizing burst/crit-ceiling rather than average output.
--     Zero by default on every builtin profile; it's here for a player who
--     wants to tune for it deliberately, not a standard scoring factor.
--   fastWeaponWeight / slowWeaponWeight: per point of attacks-per-second
--     (1/speed) or of speed itself -- two one-directional fields rather than
--     one signed "speed preference" field, so they clamp/clone/import the
--     same way every other weight here does. A spec that wants fast weapons
--     (poison/proc uptime) sets fastWeaponWeight; one that wants slow
--     weapons (Windfury, big-hit-based abilities) sets slowWeaponWeight --
--     ordinarily only one of the two is ever nonzero for a given profile.
-- All four read with an `or 0` fallback so a profile created before these
-- fields existed (every builtin profile as of this writing) scores them as
-- flatly irrelevant rather than erroring on a missing key.
--
-- Every main stat (STRENGTH/AGILITY/STAMINA/INTELLECT/SPIRIT) is weighted
-- straight out of profile.stats -- there's no more separate "primary stat"
-- concept here; each spec's profile just names its own stats explicitly
-- (see SPEC_PROFILES above), so a Warrior's grid says "Strength", not
-- "Primary Stat".
local function ScoreItem(stats, profile, armorValue, dps)
    local score = 0

    for statName, value in pairs(stats or {}) do
        if type(value) == "number" and not EXCLUDED_STAT_KEYS[statName] then
            local weight
            if profile.stats[statName] then
                weight = profile.stats[statName]
            elseif profile.secondary[statName] then
                weight = profile.secondary[statName]
            else
                weight = 0.3  -- unmapped fallback
            end
            score = score + (value * weight)
        end
    end

    score = score + ((armorValue or 0) * profile.armorWeight)
    score = score + ((dps or 0) * profile.dpsWeight)

    local weaponSpeed = stats and stats.WEAPON_SPEED
    if weaponSpeed and weaponSpeed > 0 then
        local avgDamage = (dps or 0) * weaponSpeed
        score = score + (avgDamage * (profile.avgDamageWeight or 0))
        score = score + ((1 / weaponSpeed) * (profile.fastWeaponWeight or 0))
        score = score + (weaponSpeed * (profile.slowWeaponWeight or 0))

        local _, maxDamage = ParseWeaponDamageRange(stats.WEAPON_DAMAGE)
        if maxDamage then
            score = score + (maxDamage * (profile.maxDamageWeight or 0))
        end
    end

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

-- GetItemStats() exposes a weapon's DPS (ITEM_MOD_DAMAGE_PER_SECOND_SHORT,
-- see DPS_API_KEY below) but not its speed or its damage range -- same gap as
-- Armor above, same fix: scan the rendered tooltip text. Returns
-- (weaponDamageText, weaponSpeed) -- either or both nil if this isn't a
-- weapon/the lines weren't found. weaponDamageText comes back in the exact
-- "39 - 60 Damage" shape ParseWeaponDamageRange (above) expects, so a
-- live-read item's stats.WEAPON_DAMAGE is interchangeable with a database
-- item's.
local function ScanWeaponRangeFromLink(itemLink)
    if not itemLink then return nil, nil end
    scanTooltip:ClearLines()
    scanTooltip:SetHyperlink(itemLink)
    local damageText, speed
    for i = 1, scanTooltip:NumLines() do
        local line = _G["EverGear_ScanTooltipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            if not damageText then
                damageText = text:match("^%d+ %- %d+ Damage$") or text:match("^%d+ Damage$")
            end
            if not speed then
                local spd = text:match("^Speed ([%d%.]+)$")
                if spd then speed = tonumber(spd) end
            end
        end
    end
    return damageText, speed
end

-- Maps GetItemStats()/C_Item.GetItemStats() key names to our own stat names,
-- so a live-read equipped item scores on the same scale as a candidate from
-- our database. Primary stats keep the _SHORT suffix.
--
-- WoW Forever has no combat-rating itemization at all (confirmed by the
-- player) -- Hit/Crit/Haste/Dodge/Parry/Block/etc. are granted as flat
-- percentages (CRIT_CHANCE, HIT_CHANCE, etc. in SPEC_PROFILES above), not as
-- a scaling "rating" stat, and Expertise/Resilience don't exist as mechanics
-- here at all. This table's ITEM_MOD_*_RATING keys are retained below only
-- because they're (still) the Blizzard client API's own enum names for
-- these item-mod slots -- nothing here claims this game actually populates
-- them. In practice a flat-% bonus here (like Precision Bow's "Equip:
-- increases hit chance by 0.3%") is almost certainly granted via an on-equip
-- spell effect's tooltip text, which GetItemStats() can't see at all -- so a
-- LIVE-equipped item not yet in our own database likely can't have its
-- flat-% bonuses read at all through this table; they'd need a tooltip
-- scan (same trick as ScanArmorFromLink/ScanWeaponRangeFromLink above) to
-- ever be picked up live. Not implemented -- flagging the gap rather than
-- guessing at a tooltip pattern with zero real examples to check it against.
local API_KEY_TO_STAT = {
    ITEM_MOD_AGILITY_SHORT = "AGILITY", ITEM_MOD_STRENGTH_SHORT = "STRENGTH",
    ITEM_MOD_INTELLECT_SHORT = "INTELLECT", ITEM_MOD_SPIRIT_SHORT = "SPIRIT",
    ITEM_MOD_STAMINA_SHORT = "STAMINA",
    ITEM_MOD_DEFENSE_SKILL_RATING = "DEFENSE", ITEM_MOD_DODGE_RATING = "DODGE_CHANCE",
    ITEM_MOD_PARRY_RATING = "PARRY_CHANCE", ITEM_MOD_BLOCK_RATING = "BLOCK_CHANCE",
    ITEM_MOD_HIT_RATING = "HIT_CHANCE", ITEM_MOD_CRIT_RATING = "CRIT_CHANCE",
    ITEM_MOD_HASTE_RATING = "HASTE",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELL_HIT_CHANCE", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELL_CRIT_CHANCE",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "SPELL_HASTE",
    ITEM_MOD_ARMOR_PENETRATION_RATING = "ARMOR_PENETRATION",
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
    -- Only a weapon has DPS at all -- skip the extra tooltip scan for every
    -- other slot.
    if dpsValue > 0 then
        local damageText, speed = ScanWeaponRangeFromLink(itemLink)
        if damageText then stats.WEAPON_DAMAGE = damageText end
        if speed then stats.WEAPON_SPEED = speed end
    end
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
--
-- A split type ALWAYS gets a ":1h"/":2h" suffix, even when item.isTwoHand
-- itself is nil (a handful of hand-entered items are missing this field --
-- see the data fixes alongside this change). Previously, a nil isTwoHand
-- made this fall through to the bare "axe"/"mace"/"sword" key, which UI.lua
-- never creates a checkbox or seeds a filter entry for (only the :1h/:2h
-- rows exist) -- so `weaponTypeFilter[filterKey] ~= false` was always true
-- for that item, regardless of what the player had unchecked, silently
-- bypassing the filter entirely. Treating a nil/unknown isTwoHand as 1H
-- (the more common case) keeps the item inside the filterable set instead.
function EverGear:GetWeaponFilterKey(item)
    if not item.weaponType then return nil end
    if EverGear.SPLIT_WEAPON_TYPES[item.weaponType] then
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
    local charDB = self:GetCharDB()
    local profile = GetScoringProfile(playerInfo.classToken, charDB.spec)

    -- Look-ahead: show items up to the slider's chosen level (set via UI.lua's
    -- slider, player's current level - 30). EverGearDB.lookaheadLevel is an
    -- ABSOLUTE target level, not a delta -- UI.lua keeps it clamped to at
    -- least the player's current level, but never below it here either in
    -- case that sync hasn't run yet (e.g. right after a level-up). This only
    -- widens the minLevel filter below -- it doesn't change scoring or
    -- class/weapon usability.
    local effectiveLevel = math.max(playerInfo.level, charDB.lookaheadLevel or playerInfo.level)

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
    local currentScore = ScoreItem(equippedStats, profile, equippedArmor, equippedDPS)

    -- Player-chosen weapon-type opt-outs (e.g. a tank who never wants
    -- two-handers suggested even though their class/spec can technically use
    -- them) -- set via UI.lua's weapon-type filter panel. Off by default for
    -- everyone; a class-usable weapon type only ever gets hidden if the
    -- player explicitly unchecked it. Missing from the table (never touched
    -- by the player, or a class/spec that's never seen this weapon type
    -- before) means "shown" -- only an explicit false hides it.
    local weaponTypeFilter = charDB.weaponTypeFilter or {}

    -- Same idea for crafted items: EverGearDB.professionFilter[profName] ==
    -- false hides that profession's items specifically (e.g. only
    -- Blacksmithing checked hides Leatherworking/Tailoring/etc crafted
    -- suggestions), set via UI.lua's profession filter panel. Only ever
    -- checked for source.type == "craft" items that actually name a
    -- profession -- everything else (dungeon drops, quests, vendor items)
    -- is untouched by this filter regardless of its state.
    local professionFilter = charDB.professionFilter or {}

    -- "BoE only" per profession (EverGearDB.professionBoEOnly[profName] ==
    -- true, set via the same profession filter panel) -- for browsing a
    -- profession's crafted items when the player doesn't actually have that
    -- profession, so only pieces they could actually acquire (buy/trade for)
    -- get suggested. Off by default for everyone. item.bindType == "BoE" is
    -- required exactly, not "~= BoP" -- an unconfirmed item (bindType nil,
    -- see Constants.lua) is deliberately excluded rather than assumed BoE.
    local professionBoEOnly = charDB.professionBoEOnly or {}

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
        local boeAllowed = (not itemProfession) or (not professionBoEOnly[itemProfession]) or item.bindType == "BoE"

        if item.id ~= equippedItemId
            and (not item.minLevel or item.minLevel <= effectiveLevel)
            and IsArmorTypeAllowed(item, playerInfo.classToken, effectiveLevel)
            and IsWeaponTypeAllowed(item, playerInfo.classToken)
            and IsClassAllowed(item, playerInfo.classToken)
            and factionAllowed
            and weaponTypeAllowed
            and professionAllowed
            and boeAllowed
        then
            local armorValue = (item.stats and item.stats.ARMOR) or 0
            local dpsValue = (item.stats and item.stats.WEAPON_DPS) or 0
            local score = ScoreItem(item.stats, profile, armorValue, dpsValue)
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
