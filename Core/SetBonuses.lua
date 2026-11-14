-- Item sets: which sets exist (Data/ItemSets.lua, generated from the game's own tooltips),
-- which worn pieces count towards a set, and what the set bonuses are worth as stats.
-- Also home of ParseEquipText, the "Equip:" text parser the debug tool shares.

EverGear = EverGear or {}

local SCHOOLS = { "Fire", "Frost", "Shadow", "Holy", "Arcane", "Nature" }
local SCHOOL_UPPER = {}
for _, s in ipairs(SCHOOLS) do SCHOOL_UPPER[s] = s:upper() end

-- Parses the text after "Equip: " into a list of { key, value } stats, or nil if it's not a
-- pattern we know -- those stay as raw EQUIP_n text, which is how the database stores them
-- too. Matching is case-insensitive ("Restores 2 Mana" / "Restores 2 mana").
function EverGear.ParseEquipText(text)
    local t = text:lower()
    local v, w
    v, w = t:match("^increases healing done by up to (%d+) and damage done by up to (%d+) for all magical spells and effects%.?$")
    if v then return { { "SPELL_HEALING", tonumber(v) }, { "SPELL_DAMAGE", tonumber(w) } } end
    v = t:match("^increases damage done by magical spells and effects by up to (%d+)%.?$")
    if v then return { { "SPELL_DAMAGE", tonumber(v) } } end
    v = t:match("^increases damage and healing done by magical spells and effects by up to (%d+)%.?$")
    if v then return { { "SPELL_POWER", tonumber(v) } } end
    v = t:match("^increases healing done by spells and effects by up to (%d+)%.?$")
        or t:match("^increases healing done by magical spells and effects by up to (%d+)%.?$")
    if v then return { { "SPELL_HEALING", tonumber(v) } } end
    v = t:match("^increases attack power by (%d+)%.?$") or t:match("^%+(%d+) attack power%.?$")
    if v then return { { "ATTACK_POWER", tonumber(v) } } end
    v, w = t:match("^%+(%d+) attack power against (%a+)%.?$")
    if v then return { { "ATTACK_POWER_VS_" .. w:upper(), tonumber(v) } } end
    v = t:match("^increases ranged attack power by (%d+)%.?$") or t:match("^%+(%d+) ranged attack power%.?$")
    if v then return { { "RANGED_ATTACK_POWER", tonumber(v) } } end
    v = t:match("^restores (%d+) mana per 5 sec%.?$")
    if v then return { { "MP5", tonumber(v) } } end
    -- Darkspear Islands trinkets: a base value plus more "in Forest and Grassland
    -- areas". The database keeps the base value, which is what counts anywhere else.
    v = t:match("^restores (%d+) mana per 5 sec%. restores an additional %d+ mana per 5 sec in .+$")
    if v then return { { "MP5", tonumber(v) } } end
    v = t:match("^increases all resistances by (%d+)%. gain an additional %d+ to all resistances in .+$")
    if v then
        local list = {}
        for _, school in ipairs({ "FIRE", "FROST", "NATURE", "SHADOW", "ARCANE" }) do
            list[#list + 1] = { school .. "_RESISTANCE", tonumber(v) }
        end
        return list
    end
    v = t:match("^restores (%d+) health per 5 sec%.?$")
    if v then return { { "HP5", tonumber(v) } } end
    v = t:match("^increased defense %+(%d+)%.?$")
    if v then return { { "DEFENSE", tonumber(v) } } end
    v = t:match("^increases the block value of your shield by (%d+)%.?$")
    if v then return { { "BLOCK_VALUE", tonumber(v) } } end
    v = t:match("^improves your chance to hit by ([%d.]+)%%%.?$")
    if v then return { { "HIT_CHANCE", tonumber(v) } } end
    v = t:match("^improves your chance to get a critical strike by ([%d.]+)%%%.?$")
    if v then return { { "CRIT_CHANCE", tonumber(v) } } end
    v = t:match("^increases your chance to dodge an attack by ([%d.]+)%%%.?$")
    if v then return { { "DODGE_CHANCE", tonumber(v) } } end
    v = t:match("^increases your chance to parry an attack by ([%d.]+)%%%.?$")
    if v then return { { "PARRY_CHANCE", tonumber(v) } } end
    v = t:match("^increases your chance to block attacks with a shield by ([%d.]+)%%%.?$")
    if v then return { { "BLOCK_CHANCE", tonumber(v) } } end
    v = t:match("^improves your chance to hit with spells by ([%d.]+)%%%.?$")
    if v then return { { "SPELL_HIT_CHANCE", tonumber(v) } } end
    v = t:match("^improves your chance to get a critical strike with spells by ([%d.]+)%%%.?$")
    if v then return { { "SPELL_CRIT_CHANCE", tonumber(v) } } end
    for _, school in ipairs(SCHOOLS) do
        v = t:match("^increases damage done by " .. school:lower() .. " spells and effects by up to (%d+)%.?$")
        if v then return { { SCHOOL_UPPER[school] .. "_DAMAGE", tonumber(v) } } end
    end
    return nil
end

local PRIMARY = {
    agility = "AGILITY", strength = "STRENGTH", stamina = "STAMINA",
    intellect = "INTELLECT", spirit = "SPIRIT",
}

-- Set bonus text -> list of { key, value }, or nil when it isn't a plain stat (a proc, a
-- cooldown change...). Those are still shown in tooltips but never scored.
function EverGear.ParseBonusText(text)
    local list = EverGear.ParseEquipText(text)
    if list then return list end
    local t = text:lower()
    local v, w = t:match("^%+(%d+) (%a+)%.?$")
    if v and PRIMARY[w] then return { { PRIMARY[w], tonumber(v) } } end
    if v and w == "armor" then return { { "ARMOR", tonumber(v) } } end
    v = t:match("^%+(%d+) all resistances%.?$")
    if v then
        local out = {}
        for _, school in ipairs(SCHOOLS) do out[#out + 1] = { SCHOOL_UPPER[school] .. "_RESISTANCE", tonumber(v) } end
        return out
    end
    v, w = t:match("^%+(%d+) (%a+) resistance%.?$")
    if v and w and SCHOOL_UPPER[w:sub(1, 1):upper() .. w:sub(2)] then
        return { { w:upper() .. "_RESISTANCE", tonumber(v) } }
    end
    v = t:match("^improves your chance to get a critical strike with melee attacks by ([%d.]+)%%%.?$")
    if v then return { { "CRIT_CHANCE", tonumber(v) } } end
    return nil
end

-- name -> { { setName, variant }, ... }, built the first time it is needed.
local pieceIndex
local function PieceIndex()
    if pieceIndex then return pieceIndex end
    pieceIndex = {}
    for setName, variants in pairs(EverGear.ItemSets or {}) do
        for _, variant in ipairs(variants) do
            for _, pieceName in ipairs(variant.pieces) do
                local list = pieceIndex[pieceName]
                if not list then list = {}; pieceIndex[pieceName] = list end
                list[#list + 1] = { setName = setName, variant = variant }
            end
        end
    end
    return pieceIndex
end

-- The set an item belongs to: { setName, variant } or nil. When a set has several
-- variants listing the same piece, the one that was captured from this item id wins.
function EverGear:GetItemSet(itemName, itemId)
    local list = itemName and PieceIndex()[itemName]
    if not list then return nil end
    if itemId then
        for _, entry in ipairs(list) do
            for _, id in ipairs(entry.variant.itemIds) do
                if id == itemId then return entry end
            end
        end
    end
    return list[1]
end

-- Total stats the set gives with `count` pieces worn: { KEY = value }, plus the
-- bonus lines that aren't plain stats (not scored).
function EverGear:GetSetBonusStats(variant, count)
    local stats = {}
    for _, bonus in ipairs(variant.bonuses) do
        if bonus.pieces <= count then
            for _, kv in ipairs(EverGear.ParseBonusText(bonus.text) or {}) do
                stats[kv[1]] = (stats[kv[1]] or 0) + kv[2]
            end
        end
    end
    return stats
end
