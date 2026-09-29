-- Merges the generated Data\*.lua tables (EverGear.Items, populated per-zone) with
-- SavedVariables overrides, and exposes lookup helpers used by Upgrades.lua / UI.lua.

EverGear = EverGear or {}
EverGearDB = EverGearDB or {}

-- Per-character key so filter/spec/lookahead settings below don't leak
-- between alts sharing this one account-wide SavedVariables table (see
-- "## SavedVariables: EverGearDB" in the .toc -- not PerCharacter, since the
-- window's screen position/size stays deliberately shared across every
-- character). Name+realm, not just name, so two same-named characters on
-- different realms don't collide.
local function GetCharKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Returns this character's own settings table (filters, spec, lookahead
-- level -- see UI.lua/Upgrades.lua for what's stored in it), creating it on
-- first use. One-time migrates any pre-0.0.10 account-wide values (back when
-- every character shared them) into the table the FIRST character to log in
-- after this change gets, so that character's current setup isn't silently
-- reset to defaults -- every other/new character starts from EverGear's
-- normal defaults instead, and once a character has its own table here this
-- migration never runs again for it.
function EverGear:GetCharDB()
    EverGearDB.characters = EverGearDB.characters or {}
    local key = GetCharKey()
    local charDB = EverGearDB.characters[key]
    if not charDB then
        charDB = {}
        if not EverGearDB.migratedLegacySettings then
            EverGearDB.migratedLegacySettings = true
            local legacyKeys = { "filters", "weaponTypeFilter", "professionFilter", "professionBoEOnly", "spec", "lookaheadLevel" }
            for _, k in ipairs(legacyKeys) do
                if EverGearDB[k] ~= nil then
                    charDB[k] = EverGearDB[k]
                end
            end
        end
        EverGearDB.characters[key] = charDB
    end
    return charDB
end

function EverGear:GetItem(itemId)
    return self.Items[itemId]
end

-- Returns every known item whose data-slot matches the REAL inventory slot
-- token requested, going through GENERIC_SLOT_FOR_REAL_SLOT for rings/trinkets
-- (an item tagged slot="FingerSlot" is a candidate for both Finger0Slot and
-- Finger1Slot, and likewise "TrinketSlot" for both trinket slots).
function EverGear:GetItemsForSlot(realSlotToken)
    local matchSlot = self.GENERIC_SLOT_FOR_REAL_SLOT[realSlotToken] or realSlotToken
    local results = {}
    for _, item in pairs(self.Items) do
        if item.slot == matchSlot then
            table.insert(results, item)
        end
    end
    return results
end

function EverGear:GetItemsForZone(zoneName)
    local results = {}
    for _, item in pairs(self.Items) do
        if item.source and item.source.zone == zoneName then
            table.insert(results, item)
        end
    end
    return results
end
