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
-- healer spec -- explicitly, rather than simply omitted. The generic
-- "unmapped stat" fallback further down is 0 (any stat no profile lists an
-- opinion on scores as flatly irrelevant, never a default positive), so an
-- explicit 0 here is no longer load-bearing the way it used to be -- but it
-- stays, since it documents the intent and survives if the fallback is ever
-- changed again. This used to be a real bug: the fallback was once 0.3/
-- point, and a Warrior once saw a weak spell-power mace outscore a much
-- better weapon because SPELL_POWER/SPELL_DAMAGE fell through to that
-- default instead of being recognized as caster-only -- see git history on
-- this file if the details matter.
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
-- dpsWeight is the MELEE weapon DPS weight (main/off hand); rangedDpsWeight is the
-- ranged-slot one (bow/gun/crossbow/thrown/wand). Hunters weight ranged far above
-- melee; melee classes ignore ranged (0); wand users (Mage/Warlock/Priest) value
-- their wand while leveling -- 2.0 per wand DPS for the damage specs (roughly 2 spell
-- damage per DPS point on their scale), 1.0 for Priest Disc/Holy, whose scale is
-- much larger. All hand-picked, not derived -- tune freely.
EverGear.SPEC_PROFILES = {
    WARRIOR = {
        ["Arms"] = {  -- role: Physical DPS
            -- Same sixtyupgrades-derived weights as Fury (both are the same
            -- physical-DPS role for this class, and only Fury's JSON was
            -- provided) -- every key the source JSON omitted is an explicit
            -- 0 here (confirmed convention), not a mechanically-rescaled
            -- placeholder. Revisit if Arms ever gets its own distinct set.
            stats = { STRENGTH = 2, AGILITY = 1, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "speed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 20, CRIT_CHANCE = 20, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Fury"] = {  -- role: Physical DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder.
            stats = { STRENGTH = 2, AGILITY = 1, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "speed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 20, CRIT_CHANCE = 20, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Protection"] = {  -- role: Tank
            -- Two sixtyupgrades-derived default profiles, not one blended
            -- set: Mitigation (survive the hit) and Threat (hold aggro) pull
            -- in genuinely different directions for a tank (e.g. Mitigation
            -- wants Stamina/Dodge/Parry/Defense/Block Value for
            -- damage-reduction, Threat wants Attack Power/Hit/Crit/DPS to
            -- generate aggro), so the player picks whichever matches what
            -- they're optimizing for instead of EverGear guessing a
            -- compromise. Both are zero-filled per the sixtyupgrades
            -- convention -- every key the source JSON omitted (including
            -- Block Chance, which both sets omit) is an explicit 0, not the
            -- old mechanically-rescaled placeholder.
            variants = {
                {
                    id = "mitigation",
                    name = "Mitigation",
                    profile = {
                        -- dpsWeight was 0 in the original sixtyupgrades-derived
                        -- set (pure "ignore the weapon's own damage, only its
                        -- bonus stats matter" survival scoring) -- confirmed
                        -- with the player this made ANY weapon with zero bonus
                        -- stats score a flat 0 regardless of its actual damage,
                        -- so a plain high-DPS weapon could never beat a
                        -- low-DPS one with a trivial stat bonus (e.g. a few
                        -- points of Stamina). 1.0 gives weapon damage a small,
                        -- real say -- on the same order of magnitude as a
                        -- Stamina/Dodge/Parry point, not dominant the way it
                        -- is for the Threat variant (7.5) or pure-DPS specs
                        -- (14) -- while survival stats still carry the bulk
                        -- of the score.
                        --
                        -- STRENGTH was 0.02 in the original sixtyupgrades set
                        -- (pure "doesn't reduce damage taken" discounting) --
                        -- confirmed with the player this let a 2-point
                        -- Stamina edge outweigh a 5-point Strength edge
                        -- between two otherwise-comparable weapons, which
                        -- doesn't match how they want Mitigation to value a
                        -- str/stam tank weapon. Raised to 1 (player's
                        -- explicit ask: "should still be worth at least 1")
                        -- -- same per-point weight as Stamina now, rather
                        -- than nearly irrelevant.
                        stats = { STRENGTH = 1, AGILITY = 0.91, STAMINA = 1, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0.05, dpsWeight = 1.0, rangedDpsWeight = 0,
                        secondary = {
                            SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                            SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                            FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                            NATURE_DAMAGE = 0,
                            ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                            SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                            DODGE_CHANCE = 16.29, PARRY_CHANCE = 16.29, BLOCK_CHANCE = 0,
                            BLOCK_VALUE = 0.43, ATTACK_POWER = 0, HIT_CHANCE = 0,
                            CRIT_CHANCE = 0, HASTE = 0, ARMOR_PENETRATION = 0,
                            DEFENSE = 2.61, PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0,
                            ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0, THREAT_REDUCTION = 0,
                            -- sixtyupgrades' Mitigation set also lists a flat
                            -- "health" weight distinct from Stamina -- no
                            -- equivalent stat exists in this game's data
                            -- model (never confirmed as a real itemized
                            -- stat), so it's dropped rather than folded into
                            -- HP5/Stamina.
                            HP5 = 0, MP5 = 0,
                        },
                    },
                },
                {
                    id = "threat",
                    name = "Threat",
                    profile = {
                        stats = { STRENGTH = 2, AGILITY = 1.05, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 7.5, rangedDpsWeight = 0,
                        secondary = {
                            SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                            SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                            FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                            NATURE_DAMAGE = 0,
                            ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                            SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                            DODGE_CHANCE = 0, PARRY_CHANCE = 7.47, BLOCK_CHANCE = 0,
                            BLOCK_VALUE = 0.9, ATTACK_POWER = 1, HIT_CHANCE = 27,
                            CRIT_CHANCE = 22, HASTE = 0, ARMOR_PENETRATION = 0,
                            DEFENSE = 0.22, PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0,
                            ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0, THREAT_REDUCTION = 0,
                            HP5 = 0, MP5 = 0,
                        },
                    },
                },
            },
        },
    },
    PALADIN = {
        ["Holy"] = {  -- role: Healer
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE/SPELL_HEALING
            -- alone. The source JSON's "mana" (0.06) is folded into
            -- MANA_REGEN, same as Priest Holy/Discipline.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 1, SPIRIT = 0.5 }, armorWeight = 0, dpsWeight = 0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HEALING = 1, SPELL_HIT_CHANCE = 0,
                SPELL_CRIT_CHANCE = 20, SPELL_HASTE = 0, MANA_REGEN = 0.06, SPELL_PENETRATION = 0,
                SPELL_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 3,
            },
        },
        ["Protection"] = {  -- role: Tank
            stats = { STRENGTH = 3.0, AGILITY = 0.5, STAMINA = 2.5, INTELLECT = 0.25, SPIRIT = 0.05 }, armorWeight = 0.3, dpsWeight = 1.0, rangedDpsWeight = 0,
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
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder.
            stats = { STRENGTH = 2, AGILITY = 1, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                ATTACK_POWER = 1, HIT_CHANCE = 20, CRIT_CHANCE = 15, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    HUNTER = {
        ["Beast Mastery"] = {  -- role: Physical DPS
            stats = { STRENGTH = 0, AGILITY = 2.79, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 3.5, rangedDpsWeight = 14,
            secondary = {
                -- sixtyupgrades-derived weights: every key the source JSON
                -- omitted is an explicit 0 here (confirmed convention), not a
                -- mechanically-rescaled placeholder -- this is a pure-DPS EP
                -- metric, not a survivability-aware one.
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "rangedSpeed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 21.98, CRIT_CHANCE = 28.57, HASTE = 100,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 1, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Marksmanship"] = {  -- role: Physical DPS
            stats = { STRENGTH = 0, AGILITY = 2.79, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 3.5, rangedDpsWeight = 14,
            secondary = {
                -- sixtyupgrades-derived weights: every key the source JSON
                -- omitted is an explicit 0 here (confirmed convention), not a
                -- mechanically-rescaled placeholder -- this is a pure-DPS EP
                -- metric, not a survivability-aware one.
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "rangedSpeed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 21.98, CRIT_CHANCE = 28.57, HASTE = 100,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 1, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Survival"] = {  -- role: Physical DPS
            stats = { STRENGTH = 0, AGILITY = 2.79, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 3.5, rangedDpsWeight = 14,
            secondary = {
                -- sixtyupgrades-derived weights: every key the source JSON
                -- omitted is an explicit 0 here (confirmed convention), not a
                -- mechanically-rescaled placeholder -- this is a pure-DPS EP
                -- metric, not a survivability-aware one.
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "rangedSpeed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 21.98, CRIT_CHANCE = 28.57, HASTE = 100,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 1, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    ROGUE = {
        ["Assassination"] = {  -- role: Physical DPS
            -- sixtyupgrades-derived "Dagger (Subtlety/Assassination)"
            -- weights: every key the source JSON omitted is an explicit 0
            -- here (confirmed convention), not a mechanically-rescaled
            -- placeholder.
            stats = { STRENGTH = 1.1, AGILITY = 1.8, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "speed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 16, CRIT_CHANCE = 20, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Combat"] = {  -- role: Physical DPS
            -- sixtyupgrades-derived "Combat (Swords)" weights: every key
            -- the source JSON omitted is an explicit 0 here (confirmed
            -- convention), not a mechanically-rescaled placeholder.
            stats = { STRENGTH = 1.1, AGILITY = 1.9, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                -- HASTE here stands in for sixtyupgrades' "speed" --
                -- confirmed to mean the Haste stat, not the weapon's own
                -- base speed (already fully captured by dpsWeight/WEAPON_DPS).
                ATTACK_POWER = 1, HIT_CHANCE = 18, CRIT_CHANCE = 23, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Subtlety"] = {  -- role: Physical DPS
            -- Same sixtyupgrades-derived "Dagger" weights as Assassination
            -- (one JSON was given for both) -- see Assassination's comment
            -- for the zero-fill convention.
            stats = { STRENGTH = 1.1, AGILITY = 1.8, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                ATTACK_POWER = 1, HIT_CHANCE = 16, CRIT_CHANCE = 20, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    PRIEST = {
        ["Discipline"] = {  -- role: Healer (Spirit-primary for Priest -- see CLASS_ROLE_PRIMARY_STAT)
            -- sixtyupgrades-derived weights (same JSON given for both
            -- Discipline and Holy): every key the source JSON omitted is an
            -- explicit 0 here (confirmed convention), not a mechanically-
            -- rescaled placeholder -- including SPELL_POWER, which this set
            -- omits in favor of SPELL_DAMAGE/SPELL_HEALING alone. The
            -- source JSON's "mana" (0.07) is folded into MANA_REGEN per
            -- user confirmation.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 1.16, SPIRIT = 0.83 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 1.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HEALING = 1, SPELL_HIT_CHANCE = 0,
                SPELL_CRIT_CHANCE = 0, SPELL_HASTE = 0, MANA_REGEN = 0.07, SPELL_PENETRATION = 0,
                SPELL_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 3.5,
            },
        },
        ["Holy"] = {  -- role: Healer (Spirit-primary for Priest -- see CLASS_ROLE_PRIMARY_STAT)
            -- Same sixtyupgrades-derived weights as Discipline (one JSON
            -- was given for both) -- see Discipline's comment for the
            -- zero-fill convention and the "mana"->MANA_REGEN fold.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 1.16, SPIRIT = 0.83 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 1.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HEALING = 1, SPELL_HIT_CHANCE = 0,
                SPELL_CRIT_CHANCE = 0, SPELL_HASTE = 0, MANA_REGEN = 0.07, SPELL_PENETRATION = 0,
                SPELL_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 3.5,
            },
        },
        ["Shadow"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE alone.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.04, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 10, SPELL_CRIT_CHANCE = 2.4, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 1, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    SHAMAN = {
        ["Elemental"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE alone.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.13, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 10, SPELL_CRIT_CHANCE = 8, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 2.7, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Enhancement"] = {  -- role: Physical DPS (Strength-primary for Shaman -- see CLASS_ROLE_PRIMARY_STAT)
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder. HASTE stands in for
            -- sixtyupgrades' "speed" (confirmed to mean the Haste stat).
            stats = { STRENGTH = 2, AGILITY = 1.17, STAMINA = 0, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                ATTACK_POWER = 1, HIT_CHANCE = 24, CRIT_CHANCE = 23.38, HASTE = 50,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Restoration"] = {  -- role: Healer (Spirit-primary for Shaman -- see CLASS_ROLE_PRIMARY_STAT)
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE/SPELL_HEALING
            -- alone. The source JSON's "mana" (0.07) is folded into
            -- MANA_REGEN, same as Priest Holy/Discipline.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.5, SPIRIT = 0.5 }, armorWeight = 0, dpsWeight = 0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HEALING = 1, SPELL_HIT_CHANCE = 0,
                SPELL_CRIT_CHANCE = 0, SPELL_HASTE = 0, MANA_REGEN = 0.07, SPELL_PENETRATION = 0,
                SPELL_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 3,
            },
        },
    },
    MAGE = {
        ["Arcane"] = {  -- role: Caster DPS
            -- No sixtyupgrades JSON was given for Arcane -- derived from
            -- Fire's (same crit/hit/intellect), swapping ARCANE_DAMAGE in
            -- for FIRE_DAMAGE as the nuke school. See Fire's comment for the
            -- zero-fill convention.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.2, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 13, SPELL_CRIT_CHANCE = 12, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 1, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Fire"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE alone.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.2, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 13, SPELL_CRIT_CHANCE = 12, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 1, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Frost"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.19, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 13.58, SPELL_CRIT_CHANCE = 10.95, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 1,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    WARLOCK = {
        ["Affliction"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights (same JSON given for all 3
            -- Warlock specs): every key the source JSON omitted is an
            -- explicit 0 here (confirmed convention), not a mechanically-
            -- rescaled placeholder -- including SPELL_POWER, which this set
            -- omits in favor of SPELL_DAMAGE alone.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.28, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 19.53, SPELL_CRIT_CHANCE = 12.64, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 1, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Demonology"] = {  -- role: Caster DPS
            -- Same sixtyupgrades-derived weights as Affliction (one JSON
            -- was given for all 3 Warlock specs) -- see Affliction's comment
            -- for the zero-fill convention.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.28, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 19.53, SPELL_CRIT_CHANCE = 12.64, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 1, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Destruction"] = {  -- role: Caster DPS
            -- Same sixtyupgrades-derived weights as Affliction (one JSON
            -- was given for all 3 Warlock specs) -- see Affliction's comment
            -- for the zero-fill convention.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.28, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0, rangedDpsWeight = 2.0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 19.53, SPELL_CRIT_CHANCE = 12.64, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 1, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
    },
    DRUID = {
        ["Balance"] = {  -- role: Caster DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER
            -- and NATURE_DAMAGE (Balance's kit does both Arcane and Nature
            -- damage in practice, but this set only weights Arcane).
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.11, SPIRIT = 0 }, armorWeight = 0, dpsWeight = 0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HIT_CHANCE = 8.94, SPELL_CRIT_CHANCE = 6.59, SPELL_HASTE = 0,
                MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 1,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 1, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Feral (DPS)"] = {  -- role: Physical DPS
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder. The source JSON's "mana"
            -- (0.04) is folded into MANA_REGEN, same as the healer specs.
            stats = { STRENGTH = 2.2, AGILITY = 2.02, STAMINA = 0, INTELLECT = 0.67, SPIRIT = 0.08 }, armorWeight = 0, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0.04, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                ATTACK_POWER = 1, HIT_CHANCE = 8.21, CRIT_CHANCE = 8.19, HASTE = 4.17,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0,
                PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0,
                RANGED_ATTACK_POWER = 0, DEFENSE = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0.46,
            },
        },
        ["Feral (Tank)"] = {  -- role: Tank
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder.
            --
            -- "armorBonus" (0.069) is folded additively into armorWeight
            -- alongside "armor" (0.33, giving 0.4) -- confirmed earlier that
            -- bonus armor isn't a separate itemized stat in this game, it's
            -- the same total Armor value shown on the tooltip (just colored
            -- differently historically), so there's only one ARMOR number
            -- per item to apply a single weight to. This is my best
            -- approximation of two sixtyupgrades inputs that both ultimately
            -- score against that one number -- flagging in case a different
            -- split was intended.
            --
            -- "health" (0.167, a flat Health distinct from Stamina) has no
            -- equivalent key in this game's data model -- same situation as
            -- this spec's own Mitigation profile elsewhere -- and is
            -- dropped rather than folded into Stamina.
            stats = { STRENGTH = 2.2, AGILITY = 1.57, STAMINA = 2.2, INTELLECT = 0, SPIRIT = 0 }, armorWeight = 0.4, dpsWeight = 14, rangedDpsWeight = 0,
            secondary = {
                SPELL_POWER = 0, SPELL_HEALING = 0, SPELL_HIT_CHANCE = 0, SPELL_CRIT_CHANCE = 0,
                SPELL_HASTE = 0, MANA_REGEN = 0, SPELL_PENETRATION = 0, SPELL_DAMAGE = 0,
                FIRE_DAMAGE = 0, SHADOW_DAMAGE = 0, ARCANE_DAMAGE = 0, FROST_DAMAGE = 0,
                NATURE_DAMAGE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                DODGE_CHANCE = 0, PARRY_CHANCE = 0, BLOCK_CHANCE = 0,
                BLOCK_VALUE = 0, ATTACK_POWER = 1, HIT_CHANCE = 36.1,
                CRIT_CHANCE = 25.8, HASTE = 26.6, ARMOR_PENETRATION = 0,
                DEFENSE = 0.46, PHYSICAL_DAMAGE = 0, ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0,
                ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 0,
            },
        },
        ["Restoration"] = {  -- role: Healer (Spirit-primary for Druid -- see CLASS_ROLE_PRIMARY_STAT)
            -- sixtyupgrades-derived weights: every key the source JSON
            -- omitted is an explicit 0 here (confirmed convention), not a
            -- mechanically-rescaled placeholder -- including SPELL_POWER,
            -- which this set omits in favor of SPELL_DAMAGE/SPELL_HEALING
            -- alone. The source JSON's "mana" (0.02) is folded into
            -- MANA_REGEN, same as the other healer specs.
            stats = { STRENGTH = 0, AGILITY = 0, STAMINA = 0, INTELLECT = 0.3, SPIRIT = 0.46 }, armorWeight = 0, dpsWeight = 0,
            secondary = {
                ATTACK_POWER = 0, HIT_CHANCE = 0, CRIT_CHANCE = 0, HASTE = 0,
                ARMOR_PENETRATION = 0, DODGE_CHANCE = 0,
                PARRY_CHANCE = 0, BLOCK_CHANCE = 0, BLOCK_VALUE = 0, PHYSICAL_DAMAGE = 0,
                ATTACK_POWER_VS_BEASTS = 0, ATTACK_POWER_VS_HUMANOIDS = 0, ATTACK_POWER_VS_UNDEAD = 0, RANGED_ATTACK_POWER = 0,
                DEFENSE = 0,
                ARCANE_RESISTANCE = 0, FIRE_RESISTANCE = 0, FROST_RESISTANCE = 0, NATURE_RESISTANCE = 0,
                SHADOW_RESISTANCE = 0, MOVEMENT_IMPAIRING_REDUCTION = 0, SPELL_DAMAGE_REDUCTION = 0,
                SPELL_POWER = 0, SPELL_HEALING = 1, SPELL_HIT_CHANCE = 0,
                SPELL_CRIT_CHANCE = 10, SPELL_HASTE = 0, MANA_REGEN = 0.02, SPELL_PENETRATION = 0,
                SPELL_DAMAGE = 1, THREAT_REDUCTION = 0,
                HP5 = 0, MP5 = 3,
            },
        },
    },
}

-- Stat keys that are handled separately (armor/dps/weapon speed) or aren't
-- numeric (weapon damage range) -- never fed into the generic per-stat loop.
-- HERBALISM/LOCKPICKING are profession-skill bonuses (gathering/utility, not
-- combat) -- never worth anything to any of the 4 combat role profiles, so
-- excluded outright rather than left in the generic per-stat loop at all
-- (harmless either way now that the unmapped-stat fallback below is 0, but
-- kept explicit since these were never meant to be scored by ScoreItem).
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
--     top. Two weapons
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
local function ScoreItem(stats, profile, armorValue, dps, isRanged)
    local score = 0

    for statName, value in pairs(stats or {}) do
        if type(value) == "number" and not EXCLUDED_STAT_KEYS[statName] then
            local weight
            if profile.stats[statName] then
                weight = profile.stats[statName]
            elseif profile.secondary[statName] then
                weight = profile.secondary[statName]
            else
                weight = 0  -- unmapped fallback -- see comment above ScoreItem:
                            -- a stat no profile has an opinion on (including
                            -- a stray data-quality fabrication) should never
                            -- contribute value by default. Previously 0.3/
                            -- point, which is exactly how a fabricated
                            -- SPELL_DAMAGE/SPELL_HEALING on Crested Scepter
                            -- (Blackfathom Deeps, since corrected) skewed its
                            -- score under every melee/tank profile that
                            -- hadn't explicitly zeroed those keys.
            end
            score = score + (value * weight)
        end
    end

    score = score + ((armorValue or 0) * profile.armorWeight)
    -- Ranged-slot weapons (bow/gun/crossbow/thrown/wand) use their own DPS weight so
    -- a Hunter can value its ranged weapon far above its melee one while a melee
    -- class can ignore ranged DPS entirely. A profile with no rangedDpsWeight (older
    -- saved/imported data) falls back to dpsWeight, i.e. the previous behavior.
    local dpsWeight = profile.dpsWeight
    if isRanged and profile.rangedDpsWeight ~= nil then
        dpsWeight = profile.rangedDpsWeight
    end
    score = score + ((dps or 0) * dpsWeight)

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
    WARRIOR = { axe = true, bow = true, gun = true, mace = true, polearm = true, sword = true, staff = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    PALADIN = { axe = true, mace = true, polearm = true, sword = true, dagger = true },
    HUNTER  = { axe = true, bow = true, gun = true, polearm = true, sword = true, staff = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    ROGUE   = { bow = true, gun = true, sword = true, ["fist weapon"] = true, dagger = true, thrown = true, crossbow = true },
    PRIEST  = { mace = true, staff = true, dagger = true, wand = true },
    SHAMAN  = { axe = true, mace = true, staff = true, ["fist weapon"] = true, dagger = true },
    MAGE    = { sword = true, staff = true, dagger = true, wand = true },
    WARLOCK = { sword = true, staff = true, dagger = true, wand = true },
    DRUID   = { mace = true, staff = true, ["fist weapon"] = true, dagger = true },
}

local CLASS_CAN_USE_SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Relics (the ranged-slot items that aren't ranged weapons) and the one
-- class that can use each kind.
local RELIC_CLASS = { libram = "PALADIN", idol = "DRUID", relic = "SHAMAN" }

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
        return true  -- orb-style items -- see IsWeaponTypeAllowed below
    end
    if RELIC_CLASS[baseType] then
        return RELIC_CLASS[baseType] == classToken
    end
    local whitelist = CLASS_USABLE_WEAPON_TYPES[classToken]
    return whitelist ~= nil and whitelist[baseType] == true
end

local function IsWeaponTypeAllowed(item, classToken)
    if not item.weaponType then return true end  -- not a weapon/shield
    if item.weaponType == "shield" then
        return CLASS_CAN_USE_SHIELD[classToken] == true
    end
    if RELIC_CLASS[item.weaponType] then
        return RELIC_CLASS[item.weaponType] == classToken
    end
    if item.weaponType == "offhand" then
        -- An orb-style held-in-off-hand item (Orb, tome, etc) --
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

-- Client item class/subclass -> this addon's weaponType/armorType, for items
-- the data files don't have (anything Alt-clicked in the game).
local WEAPON_SUBCLASS_TYPES = {
    [0] = "axe", [1] = "axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "mace",
    [6] = "polearm", [7] = "sword", [8] = "sword", [10] = "staff", [13] = "fist weapon",
    [15] = "dagger", [16] = "thrown", [18] = "crossbow", [19] = "wand",
}
local ARMOR_SUBCLASS_TYPES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
-- Armor subclasses: 9 (Totems) and 11 (Relic) are both the Shaman's "Relic" type.
local RELIC_SUBCLASS_TYPES = { [7] = "libram", [8] = "idol", [9] = "relic", [11] = "relic" }

local function ItemFromClientInfo(itemId)
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInfo then return nil end
    local _, _, _, _, _, classID, subclassID = getInfo(itemId)
    if classID == 2 then
        return { weaponType = WEAPON_SUBCLASS_TYPES[subclassID] }
    elseif classID == 4 then
        if subclassID == 6 then return { weaponType = "shield" } end
        if RELIC_SUBCLASS_TYPES[subclassID] then
            return { weaponType = RELIC_SUBCLASS_TYPES[subclassID] }
        end
        return { armorType = ARMOR_SUBCLASS_TYPES[subclassID] }
    end
    return nil
end

-- Whether this character's class can use an item at all -- for the wanted
-- list and gear sets. Those are plans, so the level-40 mail/plate unlock
-- isn't held against it. Returns false plus the client's item subtype (e.g.
-- "Wands") for the message, when it's known.
function EverGear:CanPlayerUseItem(itemId)
    -- Shirts and tabards: any class can wear them.
    if self:GetCosmetic(itemId) then return true end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local equipLoc = getInstant and select(4, getInstant(itemId))
    if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return true end
    local classToken = self:GetPlayerInfo().classToken
    local item = self:GetItem(itemId) or ItemFromClientInfo(itemId)
    if not (item and classToken) then return true end
    if IsClassAllowed(item, classToken) and IsWeaponTypeAllowed(item, classToken)
        and IsArmorTypeAllowed(item, classToken, ARMOR_PROFICIENCY_UNLOCK_LEVEL) then
        return true
    end
    local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local subType = getInfo and select(3, getInfo(itemId))
    return false, subType
end

-- ===== Public interface =====

-- Returns (candidates, currentScore) for a REAL slot token:
--   candidates   = a list of { item = <item>, score = <number> }, best first,
--                  restricted to the player's level, class-usable armor/
--                  weapon types, and only items that beat currentScore.
--   currentScore = the score of whatever is currently equipped in that slot
--                  (0 if the slot is empty).
-- options (optional): { ignoreZoneFilter = true } for the Upgrades by Zone
-- view, where the zone is picked on purpose even if the zone filter hides it.
function EverGear:GetUpgradesForSlot(realSlotToken, equippedItemLink, options)
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
    local isRangedSlot = (realSlotToken == "RangedSlot")
    local currentScore = ScoreItem(equippedStats, profile, equippedArmor, equippedDPS, isRangedSlot)

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
    -- EverGearDB.zoneFilter[zoneName] == false hides everything sourced from
    -- that zone or dungeon (UI.lua's zone filter panel). Items with no
    -- source.zone (crafted, world drops from all over) are never hidden by it.
    local zoneFilter = charDB.zoneFilter or {}

    -- "BoE only" per profession (EverGearDB.professionBoEOnly[profName] ==
    -- true, set via the same profession filter panel) -- for browsing a
    -- profession's crafted items when the player doesn't actually have that
    -- profession, so only pieces they could actually acquire (buy/trade for)
    -- get suggested. Off by default for everyone. item.bindType == "BoE" is
    -- required exactly, not "~= BoP" -- an unconfirmed item (bindType nil,
    -- see Constants.lua) is deliberately excluded rather than assumed BoE.
    local professionBoEOnly = charDB.professionBoEOnly or {}

    -- A Tank spec whose class can wield a shield (Protection Warrior/Paladin) is
    -- meant to hold a shield in the off-hand. Off-hand-only WEAPONS (e.g. Shoni's
    -- Disarming Tool) share SecondaryHandSlot with shields, and their raw stats can
    -- outscore a shield, so they must never be offered as a "swap" for a shield
    -- there. Orb-style "offhand" items and shields themselves are untouched.
    local tankShieldOnly = false
    if realSlotToken == "SecondaryHandSlot"
        and CLASS_CAN_USE_SHIELD[playerInfo.classToken]
        and self:GetRoleForSpec(playerInfo.classToken, charDB.spec) == "Tank" then
        tankShieldOnly = true
    end

    local candidates = {}
    for _, item in ipairs(self:GetItemsForSlot(realSlotToken)) do
        local itemFaction = item.source and item.source.faction
        -- Faction-locked quest rewards (item.source.faction) are only ever
        -- obtainable by that faction -- skip them for the other one entirely
        -- rather than suggesting an "upgrade" the player can never get. If
        -- the player's own faction can't be read for some reason, don't
        -- filter (better to over-show than silently hide real options).
        -- An item BOTH factions can obtain (just via two differently-named
        -- quests -- source.questByFaction, see GetSourceSummary below) has
        -- no source.faction at all, so it's never caught by this filter in
        -- the first place -- nothing extra to do here for that case.
        local factionAllowed = (not itemFaction) or (not playerInfo.faction) or itemFaction == playerInfo.faction

        local filterKey = self:GetWeaponFilterKey(item)
        local weaponTypeAllowed = (not filterKey) or (weaponTypeFilter[filterKey] ~= false)

        local itemProfession = item.source and item.source.type == "craft" and item.source.profession
        local professionAllowed = (not itemProfession) or (professionFilter[itemProfession] ~= false)
        local boeAllowed = (not itemProfession) or (not professionBoEOnly[itemProfession]) or item.bindType == "BoE"
        local itemZone = item.source and item.source.zone
        local zoneAllowed = (not itemZone) or (zoneFilter[itemZone] ~= false)
            or (options and options.ignoreZoneFilter) or false

        -- A quest reward can't be had before the quest can be picked up, even
        -- when the item itself has no level requirement (most rewards don't):
        -- source.minLevel is the quest's required level.
        local requiredLevel = math.max(item.minLevel or 0, (item.source and item.source.minLevel) or 0)

        if item.id ~= equippedItemId
            and requiredLevel <= effectiveLevel
            and IsArmorTypeAllowed(item, playerInfo.classToken, effectiveLevel)
            and IsWeaponTypeAllowed(item, playerInfo.classToken)
            and IsClassAllowed(item, playerInfo.classToken)
            and factionAllowed
            and weaponTypeAllowed
            and professionAllowed
            and boeAllowed
            and zoneAllowed
            and not (tankShieldOnly and item.weaponType and item.weaponType ~= "shield" and item.weaponType ~= "offhand")
        then
            local armorValue = (item.stats and item.stats.ARMOR) or 0
            local dpsValue = (item.stats and item.stats.WEAPON_DPS) or 0
            local score = ScoreItem(item.stats, profile, armorValue, dpsValue, isRangedSlot)
            if score > currentScore then
                table.insert(candidates, { item = item, score = score })
            end
        end
    end

    table.sort(candidates, function(a, b) return a.score > b.score end)
    return candidates, currentScore
end

-- Every item in the addon's data this character could wear in a REAL slot,
-- scored with the active EP profile, best first: { { item, score,
-- requiredLevel }, ... }. Used by the Gear Sets item picker, which is for
-- planning, so only class / armor type / weapon type / faction are checked:
-- the look-ahead level, the filter panels and what's equipped are ignored.
-- maxLevel (optional) leaves out items that need a higher level.
function EverGear:GetWearableItemsForSlot(realSlotToken, maxLevel)
    local playerInfo = self:GetPlayerInfo()
    local profile = GetScoringProfile(playerInfo.classToken, self:GetCharDB().spec)
    local isRangedSlot = (realSlotToken == "RangedSlot")
    local results = {}
    for _, item in ipairs(self:GetItemsForSlot(realSlotToken)) do
        local itemFaction = item.source and item.source.faction
        local requiredLevel = math.max(item.minLevel or 0, (item.source and item.source.minLevel) or 0)
        -- Armor proficiencies (mail/plate) unlock with level, so check them at
        -- the level the item needs, not the character's current one.
        local proficiencyLevel = math.max(requiredLevel, playerInfo.level or 1)
        if (not maxLevel or requiredLevel <= maxLevel)
            and ((not itemFaction) or (not playerInfo.faction) or itemFaction == playerInfo.faction)
            and IsArmorTypeAllowed(item, playerInfo.classToken, proficiencyLevel)
            and IsWeaponTypeAllowed(item, playerInfo.classToken)
            and IsClassAllowed(item, playerInfo.classToken)
        then
            local stats = item.stats
            local score = ScoreItem(stats, profile, (stats and stats.ARMOR) or 0, (stats and stats.WEAPON_DPS) or 0, isRangedSlot)
            table.insert(results, { item = item, score = score, requiredLevel = requiredLevel })
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.item.id < b.item.id
    end)
    return results
end

-- EP score of one item (id or link) in a REAL slot, with the active profile:
-- the addon's own data when it has the item, the item's live stats
-- otherwise. 0 for no item. Used by the Gear Sets picker for its gain column.
function EverGear:ScoreItemForSlot(itemIdOrLink, realSlotToken)
    if not itemIdOrLink then return 0 end
    local playerInfo = self:GetPlayerInfo()
    local profile = GetScoringProfile(playerInfo.classToken, self:GetCharDB().spec)
    local itemId = type(itemIdOrLink) == "number" and itemIdOrLink or self:GetItemIDFromLink(itemIdOrLink)
    local data = itemId and self:GetItem(itemId)
    local stats, armor, dps
    if data then
        stats = data.stats
        armor, dps = (stats and stats.ARMOR) or 0, (stats and stats.WEAPON_DPS) or 0
    else
        local link = type(itemIdOrLink) == "string" and itemIdOrLink or ("item:" .. itemId)
        stats, armor, dps = NormalizeLiveStats(link)
    end
    return ScoreItem(stats, profile, armor or 0, dps or 0, realSlotToken == "RangedSlot")
end

-- Every upgrade from one zone or dungeon, across all slots, best gain first:
-- { { item, slotToken, gain }, ... }. Uses the same rules as the main
-- window's Suggested Upgrades (level / look-ahead, class, faction, source /
-- weapon / profession filters) except the zone filter. An item that fits two
-- slots (rings, trinkets) is listed once, for the slot where it gains most.
function EverGear:GetUpgradesForZone(zoneName)
    local sourceFilters = self:GetCharDB().filters or {}
    local best = {}
    for _, slotToken in ipairs(self.EQUIP_SLOTS) do
        local candidates, currentScore = self:GetUpgradesForSlot(slotToken, self:GetEquippedItemLink(slotToken), { ignoreZoneFilter = true })
        for _, candidate in ipairs(candidates) do
            local item = candidate.item
            local sourceType = item.source and item.source.type
            if item.source and item.source.zone == zoneName and sourceFilters[sourceType] ~= false then
                local gain = candidate.score - (currentScore or 0)
                if not best[item.id] or gain > best[item.id].gain then
                    best[item.id] = { item = item, slotToken = slotToken, gain = gain }
                end
            end
        end
    end
    local list = {}
    for _, entry in pairs(best) do table.insert(list, entry) end
    table.sort(list, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.item.id < b.item.id
    end)
    return list
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
        -- Some quests are offered to both factions for the identical reward,
        -- just under two different quest names (e.g. Gnomeregan's "The Grand
        -- Betrayal" for Alliance / "Rig Wars" for Horde) -- see schema.md's
        -- questByFaction. These items are never faction-filtered (no
        -- source.faction), so show whichever name the VIEWER would actually
        -- see in their own quest log, falling back to the generic "quest"
        -- name above if their faction can't be read for some reason.
        if source.questByFaction then
            local playerFaction = self:GetPlayerInfo().faction
            questName = (playerFaction and source.questByFaction[playerFaction]) or questName
        end
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
        -- A drop from one named mob (often a rare) names it after the zone:
        -- "World Drop - Teldrassil (Nightscreech)".
        local where = source.zone and (" - " .. source.zone) or ""
        if source.npc then where = where .. " (" .. source.npc .. ")" end
        return "World Drop" .. where
    elseif source.type == "special" then
        -- Not a plain drop/quest/vendor/craft (e.g. made by combining other
        -- items) -- the note says how, in the same "Zone (...)" shape.
        local what = "Special" .. (source.note and (": " .. source.note) or "")
        return source.zone and (source.zone .. " (" .. what .. ")") or what
    elseif source.type == "craft" then
        return "Crafted" .. (source.profession and (" (" .. source.profession .. ")") or "")
    end
    return "Unknown source"
end
