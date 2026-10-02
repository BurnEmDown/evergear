-- Custom EQ (scoring weight) profiles. See CUSTOM_EQ_PROFILES_PLAN.md for the
-- full design/milestone writeup this implements.
--
-- A "profile" is the same shape as one EverGear.SPEC_PROFILES[class][spec]
-- entry, plus a `primaryStatWeight` field (hardcoded to 3.0 inline in
-- Upgrades.lua's ScoreItem before this file existed -- now a real, tunable
-- part of the profile instead of a silent exception):
--   {
--     primaryStatWeight = 3.0,
--     staminaWeight = 1.5,
--     armorWeight = 0.15,
--     dpsWeight = 3.0,
--     offStat = { AGILITY = 0.3, INTELLECT = 0.05, ... },
--     secondary = { ATTACK_POWER = 0.5, SPELL_POWER = 0, ... },
--   }
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

-- Deep-copies a flat-ish weights table (scalars + offStat{}/secondary{} sub-
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
-- directly, offStat{}/secondary{} sub-tables merge key-by-key rather than
-- replacing the whole sub-table wholesale. A key `overlay` doesn't define
-- is left at `base`'s value -- this is what lets CopyProfile move a profile
-- between specs with different offStat key sets (plan assumption 6) without
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
-- fresh, independent, fully-populated copy (including the primaryStatWeight
-- this table never carried before) rather than the live SPEC_PROFILES
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
        primaryStatWeight = 3.0,
        staminaWeight = self:ClampWeight(source.staminaWeight),
        armorWeight = self:ClampWeight(source.armorWeight),
        dpsWeight = self:ClampWeight(source.dpsWeight),
        offStat = CloneWeights(source.offStat),
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
-- key the target actually uses -- its own offStat set in particular, which
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
