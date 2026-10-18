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

-- A shirt or tabard from Data/Cosmetics.lua ({ id, name, slot, quality,
-- faction, source }), or nil.
function EverGear:GetCosmetic(itemId)
    return self.Cosmetics and self.Cosmetics[itemId]
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

-- ===== Where an item comes from, for one faction =====
-- A vendor item may list several vendors (source.vendors: { name, zone,
-- faction }, the ones seen in WoW Forever first), some only for the Alliance
-- or the Horde and some neutral. These answer "where can THIS character get
-- it": faction is "Alliance" / "Horde", or nil for every vendor.

-- The vendors the faction can buy from, in the data's order.
function EverGear:GetUsableVendors(item, faction)
    local usable = {}
    local vendors = item.source and item.source.vendors
    if not vendors then return usable end
    for _, vendor in ipairs(vendors) do
        if not faction or not vendor.faction or vendor.faction == faction then
            table.insert(usable, vendor)
        end
    end
    return usable
end

-- The character's usable vendors, most convenient first: one in the zone the
-- character is in, then one in a zone meant for their level
-- (ZONE_LEVEL_RANGES); otherwise the data's order, which has the vendors seen
-- in WoW Forever first. Suggestion rows name the first; item tooltips list
-- them all.
function EverGear:GetVendorsByPreference(item)
    local playerInfo = self:GetPlayerInfo()
    local here = GetRealZoneText and GetRealZoneText()
    local level = playerInfo.level or 1
    local vendors = self:GetUsableVendors(item, playerInfo.faction)
    local rank = {}
    for index, vendor in ipairs(vendors) do
        local range = vendor.zone and self.ZONE_LEVEL_RANGES and self.ZONE_LEVEL_RANGES[vendor.zone]
        local score = 0
        if here and vendor.zone == here then score = score + 8 end
        if range and level >= range[1] and level <= range[2] then score = score + 4 end
        rank[vendor] = { score = score, index = index }
    end
    table.sort(vendors, function(a, b)
        if rank[a].score ~= rank[b].score then return rank[a].score > rank[b].score end
        return rank[a].index < rank[b].index
    end)
    return vendors
end

-- False when only the other faction can get the item: a faction-locked source
-- (source.faction), or a vendor item none of whose vendors serve this faction.
function EverGear:IsSourceAvailableToFaction(item, faction)
    if not faction then return true end
    local source = item.source
    if not source then return true end
    if source.faction and source.faction ~= faction then return false end
    if source.vendors and #self:GetUsableVendors(item, faction) == 0 then return false end
    return true
end

-- The zones the item comes from for the faction: its usable vendors' zones,
-- or source.zone. Empty for items not tied to a place (crafted, world drops).
function EverGear:GetSourceZones(item, faction)
    local source = item.source
    if not source then return {} end
    if source.vendors then
        local zones, seen = {}, {}
        for _, vendor in ipairs(self:GetUsableVendors(item, faction)) do
            if vendor.zone and not seen[vendor.zone] then
                seen[vendor.zone] = true
                table.insert(zones, vendor.zone)
            end
        end
        return zones
    end
    return source.zone and { source.zone } or {}
end

local function HasZone(zones, zoneName)
    for _, zone in ipairs(zones) do
        if zone == zoneName then return true end
    end
    return false
end
EverGear.ZoneListHas = HasZone

function EverGear:GetItemsForZone(zoneName, faction)
    local results = {}
    for _, item in pairs(self.Items) do
        if HasZone(self:GetSourceZones(item, faction), zoneName) then
            table.insert(results, item)
        end
    end
    return results
end
