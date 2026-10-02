-- Custom EQ (scoring weight) profiles. See CUSTOM_EQ_PROFILES_PLAN.md for the
-- full design/milestone writeup this implements.
--
-- A "profile" is the same shape as one EverGear.SPEC_PROFILES[class][spec]
-- entry:
--   {
--     stats = { STRENGTH = 3.0, AGILITY = 0.3, STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 },
--     armorWeight = 0.15,
--     dpsWeight = 3.0,
--     secondary = { ATTACK_POWER = 0.5, SPELL_POWER = 0, ... },
--   }
-- `stats` always names all 5 main stats explicitly by their real name --
-- there's no more generic "primary stat" field here (removed per user
-- feedback: a profile used to carry a single opaque `primaryStatWeight`
-- applied to whichever stat a hidden per-class/role table picked, which made
-- the editor UI show a "Primary Stat" row with no indication of which real
-- stat it actually weighted). Every spec just lists its own 5 stat weights
-- directly now, so e.g. a Warrior's editor row reads "Strength", not
-- "Primary Stat".
--
-- Every numeric value in here is expected to already be clamped via
-- EverGear:ClampWeight -- callers that accept outside input (the editor UI in
-- a later milestone, JSON import in M2) are responsible for running values
-- through it before they reach the functions below.
--
-- Storage (EverGearDB, account-wide -- NOT per-character, see plan
-- assumption 1): a custom profile tuned on one alt is available to every
-- character of that class.
--   EverGearDB.customProfiles = {
--     [classToken] = {
--       [specName] = {
--         [profileId] = { name = "My Fury Profile", weights = { ... } },
--       },
--     },
--   }
-- The *active* profile choice is per-character (extends the existing
-- charDB.spec pattern): charDB.profileId, "default" or absent meaning the
-- read-only builtin. Switching the spec dropdown (UI.lua, M3) is responsible
-- for resetting charDB.profileId back to "default" -- a profile id from one
-- spec means nothing for another, and this file doesn't second-guess that;
-- it just resolves whatever id it's given against the CURRENT class+spec's
-- own custom-profile table.

EverGear = EverGear or {}
EverGearDB = EverGearDB or {}

local DEFAULT_PROFILE_ID = "default"
local DEFAULT_PROFILE_NAME = "Default"

-- ===== Weight validation =====

-- Rounds to the nearest 0.1 and clamps to [0, 5] -- the single source of
-- truth for "is this a legal weight" used by the (future) editor UI's input
-- filter and by JSON import validation alike, so a value can never sneak in
-- through one path with different rules than the other.
function EverGear:ClampWeight(value)
    value = tonumber(value)
    if not value then return 0 end
    value = math.floor(value * 10 + 0.5) / 10
    if value < 0 then value = 0 end
    if value > 5 then value = 5 end
    return value
end

-- ===== Internal helpers =====

-- Deep-copies a flat-ish weights table (scalars + stats{}/secondary{} sub-
-- tables -- never anything deeper than that in a profile's shape), running
-- every numeric leaf through ClampWeight so a copy can never carry forward
-- an out-of-range or unrounded value from whatever table it was sourced
-- from (a SPEC_PROFILES entry that predates this clamp, a half-validated
-- JSON import, etc).
local function CloneWeights(source)
    local out = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local sub = {}
            for subKey, subValue in pairs(value) do
                if type(subValue) == "number" then
                    sub[subKey] = EverGear:ClampWeight(subValue)
                end
            end
            out[key] = sub
        elseif type(value) == "number" then
            out[key] = EverGear:ClampWeight(value)
        end
    end
    return out
end

-- Merges `overlay`'s keys onto a clone of `base`: scalars overwrite
-- directly, stats{}/secondary{} sub-tables merge key-by-key rather than
-- replacing the whole sub-table wholesale. A key `overlay` doesn't define
-- is left at `base`'s value -- this is what lets CopyProfile move a profile
-- between specs with different stats key sets (plan assumption 6) without
-- ever leaving a key nil: `base` is always the TARGET spec's own builtin
-- defaults, so every key the target actually uses is guaranteed present
-- before `overlay` (the source profile) gets a chance to overwrite any of
-- them.
local function MergeWeightsOnto(base, overlay)
    local merged = CloneWeights(base)
    for key, value in pairs(overlay or {}) do
        if type(value) == "table" then
            merged[key] = merged[key] or {}
            for subKey, subValue in pairs(value) do
                if type(subValue) == "number" then
                    merged[key][subKey] = EverGear:ClampWeight(subValue)
                end
            end
        elseif type(value) == "number" then
            merged[key] = EverGear:ClampWeight(value)
        end
    end
    return merged
end

-- Short, collision-safe-enough id -- profiles are created interactively by
-- one player clicking a button, not machine-generated in bulk, so
-- time()+a random suffix is plenty; no need for a persisted counter.
local function GenerateProfileId()
    return string.format("%x-%x", time(), math.random(0, 0xFFFFFF))
end

local function GetCustomProfileTable(classToken, specName, create)
    EverGearDB.customProfiles = EverGearDB.customProfiles or {}
    local byClass = EverGearDB.customProfiles[classToken]
    if not byClass then
        if not create then return nil end
        byClass = {}
        EverGearDB.customProfiles[classToken] = byClass
    end
    local bySpec = byClass[specName]
    if not bySpec then
        if not create then return nil end
        bySpec = {}
        byClass[specName] = bySpec
    end
    return bySpec
end

-- ===== Builtin (read-only) profile =====

-- Wraps today's EverGear.SPEC_PROFILES lookup (Upgrades.lua), returning a
-- fresh, independent, fully-populated copy rather than the live SPEC_PROFILES
-- table itself -- nothing should ever mutate what this returns, since
-- SPEC_PROFILES is shared, hand-tuned, committed data (plan assumption 2:
-- the builtin is read-only, full stop, not just "undeletable").
function EverGear:GetBuiltinProfile(classToken, specName)
    local classProfiles = self.SPEC_PROFILES[classToken]
    local source = classProfiles and classProfiles[specName]
    if not source then
        -- Same defensive fallback GetScoringProfile used before this file
        -- existed -- should never trigger (every CLASS_SPECS entry has a
        -- matching SPEC_PROFILES entry), but better a sane default than an
        -- error if the two ever drift apart.
        source = self.SPEC_PROFILES.WARRIOR.Arms
    end
    return {
        stats = CloneWeights(source.stats),
        armorWeight = self:ClampWeight(source.armorWeight),
        dpsWeight = self:ClampWeight(source.dpsWeight),
        secondary = CloneWeights(source.secondary),
    }
end

-- ===== Custom profile CRUD =====

-- Ordered list of every profile selectable for this class+spec: the
-- synthesized builtin first, then custom profiles sorted by name. Shape:
-- { { id = "default", name = "Default", builtin = true }, { id = "...", name = "...", builtin = false }, ... }
function EverGear:GetProfileList(classToken, specName)
    local list = { { id = DEFAULT_PROFILE_ID, name = DEFAULT_PROFILE_NAME, builtin = true } }
    local customTable = GetCustomProfileTable(classToken, specName, false)
    if customTable then
        local customList = {}
        for id, entry in pairs(customTable) do
            table.insert(customList, { id = id, name = entry.name, builtin = false })
        end
        table.sort(customList, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(customList) do
            table.insert(list, entry)
        end
    end
    return list
end

-- Raw weights for one profile id (builtin or custom), with no charDB/
-- "active selection" involvement -- used both by GetActiveProfile below and
-- by CopyProfile, which needs to resolve a specific source profile that may
-- not be the one currently active on this character. Returns nil if
-- profileId isn't "default" and doesn't exist in this class+spec's custom
-- table (e.g. deleted from another character since).
function EverGear:GetProfileWeights(classToken, specName, profileId)
    if not profileId or profileId == DEFAULT_PROFILE_ID then
        return self:GetBuiltinProfile(classToken, specName)
    end
    local customTable = GetCustomProfileTable(classToken, specName, false)
    local entry = customTable and customTable[profileId]
    if not entry then return nil end
    -- Merge onto the builtin defaults (not a bare clone of entry.weights) so
    -- a profile saved before a new stat key existed in SPEC_PROFILES still
    -- scores that key sanely (at the current default) instead of it being
    -- missing/nil in arithmetic -- same safety net CopyProfile relies on.
    return MergeWeightsOnto(self:GetBuiltinProfile(classToken, specName), entry.weights)
end

-- Resolves this CHARACTER's active profile for classToken+specName (reads
-- charDB.profileId). Falls back to -- and self-heals charDB.profileId back
-- to -- the builtin default if the saved id no longer exists (e.g. deleted
-- from a different character sharing this account-wide profile table).
function EverGear:GetActiveProfile(classToken, specName)
    local charDB = self:GetCharDB()
    local profileId = charDB.profileId
    local weights = self:GetProfileWeights(classToken, specName, profileId)
    if not weights then
        charDB.profileId = DEFAULT_PROFILE_ID
        weights = self:GetBuiltinProfile(classToken, specName)
    end
    return weights
end

-- Creates a new custom profile from a fully-formed weights table (same
-- shape GetBuiltinProfile returns). Callers that build `weights` from
-- partial input (the editor UI, JSON import) should merge onto
-- GetBuiltinProfile(classToken, specName) themselves first -- this function
-- clones/clamps whatever it's given but doesn't fill in missing keys.
-- Returns the new profile's id.
function EverGear:CreateCustomProfile(classToken, specName, name, weights)
    local customTable = GetCustomProfileTable(classToken, specName, true)
    local id = GenerateProfileId()
    customTable[id] = { name = name, weights = CloneWeights(weights) }
    return id
end

-- Returns true, or false + a reason string (e.g. for the editor UI to show)
-- on failure. Refuses to delete "default" (plan assumption 2 -- it isn't
-- saved data in the first place, there's nothing TO delete) and silently
-- succeeds on an id that's already gone (nothing left to do).
function EverGear:DeleteCustomProfile(classToken, specName, profileId)
    if not profileId or profileId == DEFAULT_PROFILE_ID then
        return false, "The default profile can't be deleted."
    end
    local customTable = GetCustomProfileTable(classToken, specName, false)
    if customTable then
        customTable[profileId] = nil
    end
    return true
end

function EverGear:RenameCustomProfile(classToken, specName, profileId, newName)
    if not profileId or profileId == DEFAULT_PROFILE_ID then
        return false, "The default profile can't be renamed."
    end
    local customTable = GetCustomProfileTable(classToken, specName, false)
    local entry = customTable and customTable[profileId]
    if not entry then
        return false, "That profile no longer exists."
    end
    entry.name = newName
    return true
end

-- Overwrites an existing custom profile's weights in place (the editor's
-- Save button, M4) -- refuses "default" for the same reason as above.
function EverGear:SaveCustomProfile(classToken, specName, profileId, weights)
    if not profileId or profileId == DEFAULT_PROFILE_ID then
        return false, "The default profile can't be edited -- duplicate it first."
    end
    local customTable = GetCustomProfileTable(classToken, specName, false)
    local entry = customTable and customTable[profileId]
    if not entry then
        return false, "That profile no longer exists."
    end
    entry.weights = CloneWeights(weights)
    return true
end

-- ===== Cross-spec/cross-class copy (plan assumption 6) =====

-- Copies fromProfileId (class+spec `fromClass`/`fromSpec`) onto a brand new
-- custom profile under `toClass`/`toSpec`, named `newName`. Merge rule: the
-- new profile starts from the TARGET spec's own builtin defaults (so every
-- key the target actually uses -- its own stats set in particular, which
-- can differ from the source spec's -- gets a sane value), then every key
-- the SOURCE profile defines overwrites that. The source doesn't have to be
-- the character's currently-active profile, and the target doesn't have to
-- be the same class -- both are just class+spec+profileId triples resolved
-- independently. Returns the new profile's id, or nil + a reason string if
-- the source profile couldn't be resolved.
function EverGear:CopyProfile(fromClass, fromSpec, fromProfileId, toClass, toSpec, newName)
    local sourceWeights = self:GetProfileWeights(fromClass, fromSpec, fromProfileId)
    if not sourceWeights then
        return nil, "The source profile no longer exists."
    end
    local targetDefaults = self:GetBuiltinProfile(toClass, toSpec)
    local merged = MergeWeightsOnto(targetDefaults, sourceWeights)
    local id = self:CreateCustomProfile(toClass, toSpec, newName, merged)
    return id
end

-- ===== JSON export / import (M2) =====
-- WoW addons have no filesystem access, so "export to / import from a JSON
-- file" is copy/paste text, not a real file picker -- see plan assumption 3.
-- The UI side (a popup with a selectable/editable multi-line EditBox) is
-- M5; this is just the (de)serialization logic, independently testable
-- without it.

local SCALAR_WEIGHT_KEYS = { "armorWeight", "dpsWeight" }
local SUBTABLE_WEIGHT_KEYS = { "stats", "secondary" }

-- JSON string -> { class, spec, name, weights }. Self-describing (carries
-- the class/spec/name it was exported from) rather than a bare number blob,
-- so an imported profile doesn't need the player to re-specify what it's
-- for. Field order in the output is alphabetical (JSON.lua's encoder sorts
-- object keys) so two exports of the same profile diff cleanly.
function EverGear:SerializeProfile(classToken, specName, profileName, weights)
    return self.JSON.encode({
        class = classToken,
        spec = specName,
        name = profileName,
        weights = weights,
    })
end

-- JSON string -> profileData, errorMessage. profileData is
-- { class, spec, name, weights } with weights containing ONLY the
-- recognized fields (SCALAR_WEIGHT_KEYS / SUBTABLE_WEIGHT_KEYS), every
-- numeric leaf run through ClampWeight. Returns nil + a human-readable
-- message instead of throwing -- callers (the M5 import popup) are
-- expected to show that message inline rather than letting a bad paste
-- produce a Lua error.
--
-- Deliberately permissive about EXTRA top-level fields (an export might
-- pick up e.g. a future "exportedAt" timestamp some day; ignoring unknown
-- keys rather than rejecting the whole import keeps old exports importable
-- after the addon grows new metadata) but strict about the recognized
-- weight fields themselves: if a field is present at all, it must be the
-- right type, or the import is rejected outright rather than silently
-- dropping/zeroing a value the player presumably meant to set.
function EverGear:DeserializeProfile(jsonString)
    local ok, decoded = pcall(self.JSON.decode, jsonString)
    if not ok then
        return nil, "Couldn't parse that as JSON (" .. tostring(decoded) .. ")."
    end
    if type(decoded) ~= "table" then
        return nil, "Expected a JSON object, not a bare value."
    end
    if type(decoded.weights) ~= "table" then
        return nil, "Missing or invalid \"weights\" object."
    end

    local weights = {}
    for _, key in ipairs(SCALAR_WEIGHT_KEYS) do
        local value = decoded.weights[key]
        if value ~= nil then
            if type(value) ~= "number" then
                return nil, "\"" .. key .. "\" must be a number."
            end
            weights[key] = self:ClampWeight(value)
        end
    end
    for _, key in ipairs(SUBTABLE_WEIGHT_KEYS) do
        local sub = decoded.weights[key]
        if sub ~= nil then
            if type(sub) ~= "table" then
                return nil, "\"" .. key .. "\" must be an object."
            end
            local cleanSub = {}
            for subKey, subValue in pairs(sub) do
                if type(subValue) ~= "number" then
                    return nil, "\"" .. key .. "." .. subKey .. "\" must be a number."
                end
                cleanSub[subKey] = self:ClampWeight(subValue)
            end
            weights[key] = cleanSub
        end
    end

    if decoded.class ~= nil and type(decoded.class) ~= "string" then
        return nil, "\"class\" must be a string."
    end
    if decoded.spec ~= nil and type(decoded.spec) ~= "string" then
        return nil, "\"spec\" must be a string."
    end
    if decoded.name ~= nil and type(decoded.name) ~= "string" then
        return nil, "\"name\" must be a string."
    end

    return {
        class = decoded.class,
        spec = decoded.spec,
        name = decoded.name,
        weights = weights,
    }
end

-- ===== Field layout for the editor UI (M4) =====
-- pairs() iteration order over stats{}/secondary{} is NOT guaranteed
-- stable in Lua, which would make the editor's field grid re-shuffle itself
-- on every reload -- this builds a deterministic, grouped, human-labeled
-- field list instead, generated from whatever keys the profile actually has
-- (not a hand-maintained list -- a new stat key added to SPEC_PROFILES later
-- just shows up here too).

-- The 5 main stats (read from/written to weights.stats -- see each field's
-- explicit `subtable` below) plus armor/weapon-DPS (plain scalars on
-- `weights` itself) all grouped into one "Core" section, per user feedback:
-- these are the numbers people actually tune first, and they belong
-- together rather than split across a "Primary Stat"/"Stamina"/"Off-Stats"
-- set of sections that didn't say which real stat each one was.
local CORE_STAT_FIELDS = {
    { key = "STRENGTH", label = "Strength" },
    { key = "AGILITY", label = "Agility" },
    { key = "STAMINA", label = "Stamina" },
    { key = "INTELLECT", label = "Intellect" },
    { key = "SPIRIT", label = "Spirit" },
}
local CORE_SCALAR_FIELDS = {
    { key = "armorWeight", label = "Armor" },
    { key = "dpsWeight", label = "Weapon DPS" },
}

-- "ATTACK_POWER_VS_UNDEAD" -> "Attack Power Vs Undead". Good enough for
-- display purposes -- this addon has no other source of "pretty" stat names
-- (Constants.lua's FRIENDLY_SLOT_NAMES is slot tokens, not stat keys).
local function HumanizeStatKey(key)
    local words = {}
    for word in key:gmatch("[A-Za-z0-9]+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

-- Returns an ordered list of sections for the editor to render:
--   { { title = "Core",
--       fields = { { key, label, subtable = weights.stats (stat rows) or
--                                nil (armor/DPS rows, read off `weights`
--                                itself) }, ... } },
--     { title = "Secondary Stats", fields = {...}, subtable = weights.secondary } }
-- Every field now carries its OWN `subtable` (falling back to the section's,
-- if any) rather than one subtable per whole section -- Core needs that,
-- since its stat rows live in weights.stats but its armor/DPS rows are
-- top-level scalars on `weights` directly.
-- `weights` must be a fully-populated profile table (e.g. from
-- GetBuiltinProfile/GetActiveProfile/GetProfileWeights) -- this only reads
-- its shape, never mutates it.
function EverGear:GetWeightFieldLayout(weights)
    local sections = {}

    local coreFields = {}
    for _, f in ipairs(CORE_STAT_FIELDS) do
        table.insert(coreFields, { key = f.key, label = f.label, subtable = weights.stats })
    end
    for _, f in ipairs(CORE_SCALAR_FIELDS) do
        table.insert(coreFields, { key = f.key, label = f.label })
    end
    table.insert(sections, { title = "Core", fields = coreFields })

    -- Ordered by category (per user feedback) rather than alphabetically --
    -- physical-damage stats first, then spell-damage/caster stats, then
    -- defensive/survivability stats, so a quick scan down the grid roughly
    -- matches "offense, then defense" instead of an arbitrary A-Z jumble.
    -- Alphabetical WITHIN each category (no finer ordering requested yet).
    -- Any key not listed here (a new stat added to SPEC_PROFILES's
    -- `secondary` tables later, say) falls into "Other" at the very bottom
    -- rather than being silently dropped -- same spirit as this whole
    -- function already being generated from whatever keys actually exist
    -- instead of a hand-maintained list.
    local SECONDARY_CATEGORY_ORDER = { "Physical Damage", "Spell Damage", "Defensive", "Other" }
    local SECONDARY_STAT_CATEGORY = {
        -- Physical Damage
        ATTACK_POWER = "Physical Damage", RANGED_ATTACK_POWER = "Physical Damage",
        HIT_RATING = "Physical Damage", CRIT_RATING = "Physical Damage", HASTE_RATING = "Physical Damage",
        EXPERTISE_RATING = "Physical Damage", ARMOR_PENETRATION_RATING = "Physical Damage",
        PHYSICAL_DAMAGE = "Physical Damage", ATTACK_POWER_VS_BEASTS = "Physical Damage",
        ATTACK_POWER_VS_HUMANOIDS = "Physical Damage", ATTACK_POWER_VS_UNDEAD = "Physical Damage",
        -- Spell Damage (includes healing -- same "caster" stat family, and
        -- MP5, whose entire relevance is feeding spellcasting)
        SPELL_POWER = "Spell Damage", SPELL_HEALING = "Spell Damage", SPELL_HIT_RATING = "Spell Damage",
        SPELL_CRIT_RATING = "Spell Damage", SPELL_HASTE_RATING = "Spell Damage", MANA_REGEN = "Spell Damage",
        SPELL_PENETRATION = "Spell Damage", SPELL_DAMAGE = "Spell Damage", FIRE_DAMAGE = "Spell Damage",
        SHADOW_DAMAGE = "Spell Damage", ARCANE_DAMAGE = "Spell Damage", FROST_DAMAGE = "Spell Damage",
        NATURE_DAMAGE = "Spell Damage", MP5 = "Spell Damage",
        -- Defensive (mitigation/avoidance, resistances, and HP5/threat
        -- reduction -- survivability, not offense)
        DODGE_RATING = "Defensive", PARRY_RATING = "Defensive", BLOCK_RATING = "Defensive",
        BLOCK_VALUE = "Defensive", RESILIENCE_RATING = "Defensive", DEFENSE = "Defensive",
        ARCANE_RESISTANCE = "Defensive", FIRE_RESISTANCE = "Defensive", FROST_RESISTANCE = "Defensive",
        NATURE_RESISTANCE = "Defensive", SHADOW_RESISTANCE = "Defensive",
        MOVEMENT_IMPAIRING_REDUCTION = "Defensive", SPELL_DAMAGE_REDUCTION = "Defensive",
        HP5 = "Defensive", THREAT_REDUCTION = "Defensive",
    }
    local SECONDARY_CATEGORY_RANK = {}
    for i, name in ipairs(SECONDARY_CATEGORY_ORDER) do SECONDARY_CATEGORY_RANK[name] = i end

    local function addSubtableSection(title, subtable)
        local keys = {}
        for k in pairs(subtable or {}) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
            local rankA = SECONDARY_CATEGORY_RANK[SECONDARY_STAT_CATEGORY[a] or "Other"]
            local rankB = SECONDARY_CATEGORY_RANK[SECONDARY_STAT_CATEGORY[b] or "Other"]
            if rankA ~= rankB then return rankA < rankB end
            return a < b
        end)
        local fields = {}
        for _, k in ipairs(keys) do
            table.insert(fields, { key = k, label = HumanizeStatKey(k) })
        end
        table.insert(sections, { title = title, fields = fields, subtable = subtable })
    end

    addSubtableSection("Secondary Stats", weights.secondary)

    return sections
end
