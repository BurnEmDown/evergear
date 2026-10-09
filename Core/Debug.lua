-- Debug mode: tooling for keeping EverGear's item database honest, from inside the game.
--
-- With debug mode on (/eg debug), hovering any equippable item compares what the game's
-- tooltip says against what EverGear's database has for it. If the item is missing from
-- the database, or its stats / slot / type / level disagree with the game, a small window
-- appears listing what's wrong, with a "Capture" button that records the item exactly as
-- the game shows it, in the same JSON shape as evergear-backend's manual/<slug>.json, so
-- it can be handed straight over to be added to the DB.
--
-- Addons can't write files, so there are two ways to get a capture out:
--   * "Export JSON" opens a box with the JSON already selected -- Ctrl+C, paste anywhere.
--   * Every capture is also kept in EverGearDB.debugCaptures, which the game writes to
--     WTF\Account\<account>\SavedVariables\EverGear.lua on /reload or logout.
--
-- Commands: /eg debug [on|off]   toggle debug mode
--           /eg debug export     open the JSON box with everything captured
--           /eg debug clear      forget all captures
--
-- Items with a random suffix ("of the Monkey", ...) are skipped: their tooltip stats
-- belong to that one roll, not to the base item the database describes. They're spotted
-- by the link's suffixId, by Data\RandomSuffixItems.lua, or by the link's name being the
-- base item's name plus " of ..." (see BuildLiveItemRecord).

EverGear = EverGear or {}

local GOLD = { 1, 0.82, 0 }
local RED = { 1, 0.35, 0.35 }
local ORANGE = { 1, 0.65, 0.2 }
local GREEN = { 0.4, 1, 0.4 }
local PARCHMENT = { 0.9, 0.86, 0.75 }

-- ===== Item identification: slot / type from the client's own item data =====

-- equipLoc -> (data slot, true if two-hand)
local SLOT_FOR_EQUIP_LOC = {
    INVTYPE_HEAD = "HeadSlot", INVTYPE_NECK = "NeckSlot", INVTYPE_SHOULDER = "ShoulderSlot",
    INVTYPE_CLOAK = "BackSlot", INVTYPE_CHEST = "ChestSlot", INVTYPE_ROBE = "ChestSlot",
    INVTYPE_WRIST = "WristSlot", INVTYPE_HAND = "HandsSlot", INVTYPE_WAIST = "WaistSlot",
    INVTYPE_LEGS = "LegsSlot", INVTYPE_FEET = "FeetSlot", INVTYPE_FINGER = "FingerSlot",
    INVTYPE_TRINKET = "TrinketSlot",
    INVTYPE_WEAPON = "MainHandSlot", INVTYPE_WEAPONMAINHAND = "MainHandSlot",
    INVTYPE_2HWEAPON = "MainHandSlot",
    INVTYPE_WEAPONOFFHAND = "SecondaryHandSlot", INVTYPE_SHIELD = "SecondaryHandSlot",
    INVTYPE_HOLDABLE = "SecondaryHandSlot",
    INVTYPE_RANGED = "RangedSlot", INVTYPE_RANGEDRIGHT = "RangedSlot",
    INVTYPE_THROWN = "RangedSlot",
}

-- Weapon subclassID (classID 2) -> (weaponType, melee). 2H-ness comes from equipLoc.
local WEAPON_SUBCLASS = {
    [0] = "axe", [1] = "axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "mace",
    [6] = "polearm", [7] = "sword", [8] = "sword", [10] = "staff", [13] = "fist weapon",
    [15] = "dagger", [16] = "thrown", [18] = "crossbow", [19] = "wand",
}
local RANGED_WEAPON_TYPES = { bow = true, gun = true, crossbow = true, thrown = true, wand = true }
local ARMOR_SUBCLASS = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }

local function GetInstant(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    return fn(link)
end

local function GetFullInfo(link)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return fn(link)
end

-- ===== Tooltip parsing =====

local scanTooltip = CreateFrame("GameTooltip", "EverGear_DebugScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local PRIMARY_STATS = {
    Agility = "AGILITY", Strength = "STRENGTH", Stamina = "STAMINA",
    Intellect = "INTELLECT", Spirit = "SPIRIT",
}
local SCHOOLS = { "Fire", "Frost", "Shadow", "Holy", "Arcane", "Nature" }
local SCHOOL_UPPER = {}
for _, s in ipairs(SCHOOLS) do SCHOOL_UPPER[s] = s:upper() end

-- Every stat key the tooltip parser can produce. The comparison only judges keys in this
-- set -- a database stat the parser has no way to read (Herbalism, Mining...) is left
-- alone rather than reported as a false mismatch.
local PARSEABLE = {
    AGILITY = true, STRENGTH = true, STAMINA = true, INTELLECT = true, SPIRIT = true,
    ARMOR = true, BLOCK_VALUE = true,
    ATTACK_POWER = true, RANGED_ATTACK_POWER = true,
    ATTACK_POWER_VS_BEASTS = true, ATTACK_POWER_VS_UNDEAD = true,
    ATTACK_POWER_VS_HUMANOIDS = true, ATTACK_POWER_VS_ELEMENTALS = true,
    SPELL_DAMAGE = true, SPELL_HEALING = true, MP5 = true, HP5 = true, DEFENSE = true,
    HIT_CHANCE = true, CRIT_CHANCE = true, DODGE_CHANCE = true, PARRY_CHANCE = true,
    BLOCK_CHANCE = true, SPELL_HIT_CHANCE = true, SPELL_CRIT_CHANCE = true,
    WEAPON_SPEED = true, WEAPON_DPS = true,
}
for _, s in ipairs(SCHOOLS) do
    PARSEABLE[SCHOOL_UPPER[s] .. "_RESISTANCE"] = true
    PARSEABLE[SCHOOL_UPPER[s] .. "_DAMAGE"] = true
end
-- "Increases damage done by Nature spells" etc. share names with the school list above;
-- NATURE_DAMAGE is intentionally included.

-- Parses the text after "Equip: " into a list of { key, value } stats, or nil if it's not a
-- pattern we know -- those stay as raw EQUIP_n text, which is how the database stores them
-- too. Matching is case-insensitive ("Restores 2 Mana" / "Restores 2 mana").
local function ParseEquipText(text)
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

local function StripColor(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Reads one item link's tooltip into canonical-shaped stats. Returns stats, notes where
-- notes lists lines worth a human look (school-damage wands and the like).
local function ReadTooltipStats(link)
    scanTooltip:ClearLines()
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetHyperlink(link)

    local stats, notes = {}, {}
    local equipN, onhitN, useN = 0, 0, 0
    local classes

    local function Fragment(text)
        if not text or text == "" then return end
        text = StripColor(text)
        -- Large numbers carry a thousands separator ("1,380 Armor" on a shield);
        -- drop it so the number patterns below match. Lines with a colon
        -- (Equip:, Use:, Classes: ...) are kept as the tooltip shows them.
        if not text:find(":") then text = text:gsub("(%d),(%d%d%d)", "%1%2") end

        local sign, n, statName = text:match("^([%+%-])(%d+) (%a+)$")
        if sign and PRIMARY_STATS[statName] then
            stats[PRIMARY_STATS[statName]] = tonumber(n) * (sign == "-" and -1 or 1)
            return
        end
        local resN, resName = text:match("^%+(%d+) (%a+) Resistance$")
        if resN and SCHOOL_UPPER[resName] then
            stats[SCHOOL_UPPER[resName] .. "_RESISTANCE"] = tonumber(resN)
            return
        end
        local allRes = text:match("^%+(%d+) All Resistances$")
        if allRes then
            for _, school in ipairs({ "Fire", "Frost", "Nature", "Shadow", "Arcane" }) do
                stats[SCHOOL_UPPER[school] .. "_RESISTANCE"] = tonumber(allRes)
            end
            return
        end
        -- Green "+N Armor" (or a negative "-N Armor" penalty) adjusts the base armor line.
        local armorSign, bonusArmor = text:match("^([%+%-])(%d+) Armor$")
        if bonusArmor then
            stats.BONUS_ARMOR = (stats.BONUS_ARMOR or 0) + tonumber(bonusArmor) * (armorSign == "-" and -1 or 1)
            return
        end
        local armor = text:match("^(%d+) Armor$")
        if armor then stats.ARMOR = tonumber(armor) return end
        local block = text:match("^(%d+) Block$")
        if block then stats.BLOCK_VALUE = tonumber(block) return end

        local lo, hi = text:match("^(%d+) %- (%d+) Damage$")
        if lo then stats.WEAPON_DAMAGE = lo .. " - " .. hi .. " Damage" return end
        local lo2, hi2, school = text:match("^(%d+) %- (%d+) (%a+) Damage$")
        if lo2 then
            -- The database keeps the school ("30 - 57 Shadow Damage") for wands/scepters.
            stats.WEAPON_DAMAGE = lo2 .. " - " .. hi2 .. " " .. school .. " Damage"
            return
        end
        local single = text:match("^(%d+) Damage$")
        if single then stats.WEAPON_DAMAGE = single .. " Damage" return end
        local speed = text:match("^Speed ([%d%.]+)$")
        if speed then stats.WEAPON_SPEED = tonumber(speed) return end
        local dps = text:match("^%(([%d%.]+) damage per second%)$")
        if dps then stats.WEAPON_DPS = tonumber(dps) return end

        local equip = text:match("^Equip: (.+)$")
        if equip then
            local parsed = ParseEquipText(equip)
            if parsed then
                for _, kv in ipairs(parsed) do stats[kv[1]] = kv[2] end
            else
                equipN = equipN + 1
                stats["EQUIP_" .. equipN] = equip
            end
            return
        end
        local onhit = text:match("^Chance on hit: (.+)$")
        if onhit then
            onhitN = onhitN + 1
            stats["ONHIT_" .. onhitN] = onhit
            return
        end
        local use = text:match("^Use: (.+)$")
        if use then
            useN = useN + 1
            stats["USE_" .. useN] = use
            return
        end
        local classList = text:match("^Classes: (.+)$")
        if classList then
            classes = {}
            for c in classList:gmatch("[^,]+") do
                -- The database (and IsClassAllowed) use upper-case class tokens, e.g. "ROGUE".
                classes[#classes + 1] = (c:gsub("^%s+", ""):gsub("%s+$", "")):upper()
            end
        end
    end

    for i = 2, scanTooltip:NumLines() do
        local left = _G["EverGear_DebugScanTooltipTextLeft" .. i]
        local right = _G["EverGear_DebugScanTooltipTextRight" .. i]
        Fragment(left and left:GetText())
        Fragment(right and right:GetText())
    end

    -- Green "+N Armor" is part of the item's armor; the database stores the total.
    if stats.BONUS_ARMOR then
        stats.ARMOR = (stats.ARMOR or 0) + stats.BONUS_ARMOR
        notes[#notes + 1] = "armor total includes " .. stats.BONUS_ARMOR .. " bonus armor"
        stats.BONUS_ARMOR = nil
    end

    return stats, notes, classes
end

-- Builds the canonical record for a link, as the game shows it. Returns nil for anything
-- that isn't a trackable piece of equipment, or whose data isn't cached yet.
function EverGear:BuildLiveItemRecord(link)
    if not link then return nil end
    local itemId, _, _, equipLoc, _, classID, subClassID = GetInstant(link)
    local slot = equipLoc and SLOT_FOR_EQUIP_LOC[equipLoc]
    if not itemId or not slot then return nil end

    -- Random-suffix items carry per-roll stats; skip (suffixId is field 7 of the item string).
    local itemString = link:match("item:([%-%d:]*)")
    if itemString then
        local fields = {}
        for field in (itemString .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
        local suffix = tonumber(fields[7] or "0") or 0
        if suffix ~= 0 then return nil, "suffix" end
    end
    -- WoW Forever's links don't always carry that suffixId, so also skip the random-suffix
    -- items the database deliberately leaves out (Data\RandomSuffixItems.lua)...
    if EverGear.RandomSuffixItems and EverGear.RandomSuffixItems[itemId] then return nil, "suffix" end

    local name, _, quality, ilvl, minLevel = GetFullInfo(link)
    if not name then return nil, "uncached" end  -- the next hover will have it
    -- ...and any other one: asked by id alone, the game names the base item ("Brute Sword"),
    -- while the link names the roll ("Brute Sword of the Eagle"). A quest item whose own
    -- name has an "of ..." in it ("... of Ganm") is named the same both ways, so it stays.
    local baseName = GetFullInfo(itemId)
    if not baseName then return nil, "uncached" end
    if name ~= baseName and name:sub(1, #baseName + 4) == baseName .. " of " then return nil, "suffix" end
    -- Gray (0) and white (1) items never matter for upgrades; only flag green and better.
    if quality and quality < 2 then return nil, "lowQuality" end

    -- Quest rewards report a required level of 0 (sometimes 1): the item itself has no
    -- minimum, the quest does. The database prefers the quest's level, which the tooltip
    -- can't tell us -- so leave it empty here, never report it as a mismatch, and flag it
    -- in the capture so the quest level gets filled in.
    local itemMinLevel = (minLevel and minLevel > 1) and minLevel or nil
    local record = { id = itemId, name = name, slot = slot, ilvl = ilvl, minLevel = itemMinLevel, confirmed = true }
    local notes = {}
    if not itemMinLevel then
        notes[#notes + 1] = "game minimum level is " .. tostring(minLevel) .. " (likely a quest reward) - minLevel left empty; needs the quest's level"
    end

    if classID == 4 then
        if equipLoc == "INVTYPE_SHIELD" then
            record.weaponType = "shield"
        elseif equipLoc == "INVTYPE_HOLDABLE" then
            record.weaponType = "offhand"
        else
            record.armorType = ARMOR_SUBCLASS[subClassID]
        end
    elseif classID == 2 then
        local weaponType = WEAPON_SUBCLASS[subClassID]
        record.weaponType = weaponType
        if weaponType and not RANGED_WEAPON_TYPES[weaponType] then
            record.isTwoHand = (equipLoc == "INVTYPE_2HWEAPON")
        end
    end

    local stats, tooltipNotes, classes = ReadTooltipStats(link)
    for _, n in ipairs(tooltipNotes) do notes[#notes + 1] = n end
    record.stats = stats
    record.classes = classes
    return record, nil, notes
end

-- ===== Comparison against the database =====

-- Expands raw EQUIP_n text into numeric stats (same parser as the tooltip side) and
-- collapses SPELL_POWER into the damage+healing pair, so "+8 spell power" in the database
-- and "+8 spell damage / +8 healing" read identically.
local function NormalizeForCompare(stats)
    local out = {}
    for key, value in pairs(stats or {}) do
        if type(value) == "number" then
            out[key] = value
        elseif type(value) == "string" and key:match("^EQUIP_%d+$") then
            for _, kv in ipairs(ParseEquipText(value) or {}) do
                if out[kv[1]] == nil then out[kv[1]] = kv[2] end
            end
        end
    end
    -- A database entry that kept bonus armor separate counts toward the same total.
    if out.BONUS_ARMOR then
        out.ARMOR = (out.ARMOR or 0) + out.BONUS_ARMOR
        out.BONUS_ARMOR = nil
    end
    if out.SPELL_POWER then
        out.SPELL_DAMAGE = out.SPELL_DAMAGE or out.SPELL_POWER
        out.SPELL_HEALING = out.SPELL_HEALING or out.SPELL_POWER
        out.SPELL_POWER = nil
    end
    return out
end

local function Same(a, b, key)
    if key == "WEAPON_DPS" then return math.abs(a - b) <= 0.15 end
    if key == "WEAPON_SPEED" then return math.abs(a - b) <= 0.01 end
    return a == b
end

-- Returns a list of human-readable difference strings (empty = matches).
function EverGear:CompareLiveToDatabase(live, db)
    local diffs = {}
    for _, field in ipairs({ "slot", "armorType", "weaponType", "isTwoHand", "minLevel" }) do
        local skip = (field == "minLevel" and live.minLevel == nil)  -- see BuildLiveItemRecord
        if not skip and live[field] ~= db[field] and not (live[field] == nil and db[field] == nil) then
            diffs[#diffs + 1] = string.format("%s: addon %s, game %s", field, tostring(db[field]), tostring(live[field]))
        end
    end

    local g, d = NormalizeForCompare(live.stats), NormalizeForCompare(db.stats)
    local keys = {}
    for k in pairs(g) do keys[k] = true end
    for k in pairs(d) do keys[k] = true end
    local sorted = {}
    for k in pairs(keys) do
        if PARSEABLE[k] or g[k] ~= nil then sorted[#sorted + 1] = k end
    end
    table.sort(sorted)
    for _, k in ipairs(sorted) do
        local gv, dv = g[k], d[k]
        if gv == nil then
            diffs[#diffs + 1] = string.format("%s: addon %s, game has none", k, tostring(dv))
        elseif dv == nil then
            diffs[#diffs + 1] = string.format("%s: missing in addon, game %s", k, tostring(gv))
        elseif not Same(gv, dv, k) then
            diffs[#diffs + 1] = string.format("%s: addon %s, game %s", k, tostring(dv), tostring(gv))
        end
    end
    return diffs
end

-- ===== Capture storage =====

local function Captures()
    EverGearDB.debugCaptures = EverGearDB.debugCaptures or {}
    return EverGearDB.debugCaptures
end

local function StoreCapture(record, status, diffs, notes, addonStats, sourceNote)
    Captures()[record.id] = {
        record = record,
        status = status,
        diffs = diffs,
        notes = notes,
        addonStats = addonStats,
        sourceNote = sourceNote,
        level = UnitLevel("player"),
    }
end

local function CaptureCount()
    local n = 0
    for _ in pairs(Captures()) do n = n + 1 end
    return n
end

-- JSON object keyed by item id, same shape as evergear-backend/manual/<slug>.json. Keys
-- starting with "_" are context for whoever ingests it, not part of the schema.
function EverGear:BuildCaptureJSON()
    local out = {}
    for id, entry in pairs(Captures()) do
        local record = {}
        for k, v in pairs(entry.record) do record[k] = v end
        record._status = entry.status
        record._sourceNote = (entry.sourceNote and entry.sourceNote ~= "") and entry.sourceNote or nil
        record._diffs = (entry.diffs and #entry.diffs > 0) and entry.diffs or nil
        record._notes = (entry.notes and #entry.notes > 0) and entry.notes or nil
        record._addonStats = entry.addonStats
        record._capturedAtLevel = entry.level
        out[tostring(id)] = record
    end
    return EverGear.JSON.encode(out)
end

-- ===== The window =====

local debugPendingCheck
local debugFrame, nameText, statusText, diffText, sourceBox, captureButton, countText
local exportPopup, exportEditBox
local current  -- { record, status, diffs, notes, addonStats }
local currentExportText = ""

local function OpaqueBackground(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(0.04, 0.04, 0.05, 1)
end

local function RefreshCaptureUI()
    if not debugFrame then return end
    local already = current and Captures()[current.record.id]
    captureButton:SetText(already and "Update capture" or "Capture")
    countText:SetText(CaptureCount() .. " captured")
end

local function ShowExport()
    if CaptureCount() == 0 then
        print("|cff33ff99EverGear|r debug: nothing captured yet.")
        return
    end
    currentExportText = EverGear:BuildCaptureJSON()
    exportEditBox:SetText(currentExportText)
    exportPopup:Show()
    exportEditBox:SetFocus()
    exportEditBox:HighlightText()
end

local function BuildWindow()
    debugFrame = CreateFrame("Frame", "EverGearDebugFrame", UIParent, "BackdropTemplate")
    debugFrame:SetSize(360, 250)
    debugFrame:SetFrameStrata("DIALOG")
    debugFrame:SetMovable(true)
    debugFrame:EnableMouse(true)
    debugFrame:RegisterForDrag("LeftButton")
    debugFrame:SetClampedToScreen(true)
    debugFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    OpaqueBackground(debugFrame)
    local pos = EverGearDB.debugPos
    if pos then
        debugFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        debugFrame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
    debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
    debugFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        EverGearDB.debugPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    debugFrame:Hide()

    local title = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("EverGear Debug")
    title:SetTextColor(unpack(GOLD))

    local close = CreateFrame("Button", nil, debugFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    nameText = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    nameText:SetWidth(324)
    nameText:SetJustifyH("LEFT")

    statusText = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)

    diffText = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diffText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
    diffText:SetWidth(324)
    diffText:SetHeight(80)
    diffText:SetJustifyH("LEFT")
    diffText:SetJustifyV("TOP")
    diffText:SetTextColor(unpack(PARCHMENT))

    local sourceLabel = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sourceLabel:SetPoint("BOTTOMLEFT", 18, 62)
    sourceLabel:SetText("Where it dropped / notes (optional):")
    sourceLabel:SetTextColor(unpack(PARCHMENT))

    sourceBox = CreateFrame("EditBox", nil, debugFrame, "InputBoxTemplate")
    sourceBox:SetSize(316, 20)
    sourceBox:SetPoint("BOTTOMLEFT", 22, 40)
    sourceBox:SetAutoFocus(false)
    sourceBox:SetMaxLetters(200)
    sourceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sourceBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    captureButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
    captureButton:SetSize(100, 22)
    captureButton:SetPoint("BOTTOMLEFT", 18, 14)
    captureButton:SetText("Capture")
    captureButton:SetScript("OnClick", function()
        if not current then return end
        StoreCapture(current.record, current.status, current.diffs, current.notes, current.addonStats, sourceBox:GetText())
        print("|cff33ff99EverGear|r debug: captured " .. current.record.name .. " (" .. CaptureCount() .. " total).")
        RefreshCaptureUI()
    end)

    local exportButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
    exportButton:SetSize(100, 22)
    exportButton:SetPoint("LEFT", captureButton, "RIGHT", 6, 0)
    exportButton:SetText("Export JSON")
    exportButton:SetScript("OnClick", ShowExport)

    local clearButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(100, 22)
    clearButton:SetPoint("LEFT", exportButton, "RIGHT", 6, 0)
    clearButton:SetText("Clear captured")
    clearButton:SetScript("OnClick", function()
        EverGearDB.debugCaptures = {}
        print("|cff33ff99EverGear|r debug: captures cleared.")
        RefreshCaptureUI()
    end)

    -- Items that are in the backend DB but held back from the addon (no source yet).
    local pendingCheck = CreateFrame("CheckButton", nil, debugFrame, "UICheckButtonTemplate")
    pendingCheck:SetSize(22, 22)
    pendingCheck:SetPoint("TOPLEFT", 112, -12)
    pendingCheck:SetChecked(EverGearDB.debugShowPending ~= false)
    pendingCheck:SetScript("OnClick", function(self)
        EverGearDB.debugShowPending = self:GetChecked() and true or false
    end)
    pendingCheck.text = pendingCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pendingCheck.text:SetPoint("LEFT", pendingCheck, "RIGHT", 0, 1)
    pendingCheck.text:SetText("Show pending")
    pendingCheck.text:SetTextColor(unpack(PARCHMENT))
    pendingCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show items that are in the database but not shipped in the addon yet (no known source)", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pendingCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    debugPendingCheck = pendingCheck

    countText = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -8)
    countText:SetTextColor(unpack(GOLD))

    -- Export popup
    exportPopup = CreateFrame("Frame", "EverGearDebugExportPopup", UIParent, "BackdropTemplate")
    exportPopup:SetSize(460, 340)
    exportPopup:SetPoint("CENTER")
    exportPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    exportPopup:EnableMouse(true)
    exportPopup:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    OpaqueBackground(exportPopup)
    exportPopup:Hide()

    local exportTitle = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportTitle:SetPoint("TOP", 0, -14)
    exportTitle:SetText("Captured items (JSON)")
    exportTitle:SetTextColor(unpack(GOLD))

    local exportClose = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
    exportClose:SetPoint("TOPRIGHT", -2, -2)

    local hint = exportPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", exportTitle, "BOTTOM", 0, -6)
    hint:SetWidth(420)
    hint:SetText("Already selected -- press Ctrl+C, then paste it into a file or into chat. "
        .. "Captures are also saved in EverGear.lua under SavedVariables after /reload.")
    hint:SetTextColor(unpack(PARCHMENT))

    local panel = CreateFrame("Frame", nil, exportPopup, "BackdropTemplate")
    panel:SetSize(420, 220)
    panel:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.02, 0.02, 0.03, 1)
    panel:SetBackdropBorderColor(0.4, 0.37, 0.28, 1)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    exportEditBox = CreateFrame("EditBox", nil, scroll)
    exportEditBox:SetMultiLine(true)
    exportEditBox:SetFontObject(ChatFontNormal)
    exportEditBox:SetWidth(384)
    exportEditBox:SetAutoFocus(false)
    exportEditBox:EnableMouse(true)
    exportEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    exportEditBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= currentExportText then
            self:SetText(currentExportText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(exportEditBox)

    local done = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
    done:SetSize(100, 22)
    done:SetPoint("BOTTOM", 0, 14)
    done:SetText("Done")
    done:SetScript("OnClick", function() exportPopup:Hide() end)
end

local function ShowFlaggedItem(record, status, diffs, notes, addonStats)
    if not debugFrame then BuildWindow() end
    current = { record = record, status = status, diffs = diffs, notes = notes, addonStats = addonStats }

    local _, _, quality = GetFullInfo(record.id)
    local r, g, b = 1, 1, 1
    if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
    nameText:SetText(record.name .. "  |cff888888(id " .. record.id .. ")|r")
    nameText:SetTextColor(r, g, b)

    if status == "missing" or status == "pending" then
        if status == "pending" then
            statusText:SetText("IN DB, MISSING SOME STATS (no source yet - not in addon)")
            statusText:SetTextColor(unpack(ORANGE))
        else
            statusText:SetText("NOT IN ADDON")
            statusText:SetTextColor(unpack(RED))
        end
        local keys = {}
        for k, v in pairs(record.stats) do
            keys[#keys + 1] = k .. " = " .. tostring(v)
        end
        table.sort(keys)
        diffText:SetText(string.format("%s %s, level %s\n%s",
            record.slot, record.armorType or record.weaponType or "", tostring(record.minLevel),
            table.concat(keys, "\n")))
    else
        statusText:SetText("STATS DIFFER FROM GAME")
        statusText:SetTextColor(unpack(ORANGE))
        diffText:SetText(table.concat(diffs, "\n"))
    end

    local existing = Captures()[record.id]
    sourceBox:SetText(existing and existing.sourceNote or "")
    RefreshCaptureUI()
    debugFrame:Show()
end

-- ===== Hover handling =====

local lastLink
local function OnItemTooltip(tooltip)
    if not (EverGearDB and EverGearDB.debugMode) then return end
    if not tooltip or not tooltip.GetItem or tooltip == scanTooltip then return end
    local _, link = tooltip:GetItem()
    if not link or link == lastLink then return end
    lastLink = link

    local record, skipReason, notes = EverGear:BuildLiveItemRecord(link)
    if not record then
        if skipReason == "uncached" then lastLink = nil end  -- look again on the next hover
        return
    end

    local dbItem = EverGear:GetItem(record.id)
    if not dbItem and EverGear.PendingItems and EverGear.PendingItems[record.id] then
        -- In the backend DB, deliberately not shipped yet. Popup is optional.
        if EverGearDB.debugShowPending ~= false then
            ShowFlaggedItem(record, "pending", nil, notes, nil)
        end
        return
    end
    if not dbItem then
        ShowFlaggedItem(record, "missing", nil, notes, nil)
        return
    end
    local diffs = EverGear:CompareLiveToDatabase(record, dbItem)
    -- Remembered so the item browser (ItemBrowser.lua) can show what's been checked.
    EverGearDB.debugChecked = EverGearDB.debugChecked or {}
    EverGearDB.debugChecked[record.id] = #diffs > 0 and "differs" or "ok"
    if #diffs > 0 then
        ShowFlaggedItem(record, "differs", diffs, notes, dbItem.stats)
    end
    if EverGear.OnItemBrowserCheck then EverGear:OnItemBrowserCheck() end
end

local function HookTooltips()
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tip and tip.HookScript then
            tip:HookScript("OnTooltipSetItem", OnItemTooltip)
            -- Re-evaluate on the next hover of the same item.
            tip:HookScript("OnTooltipCleared", function() lastLink = nil end)
        end
    end
end
-- pcall: if this client has dropped OnTooltipSetItem for TooltipDataProcessor, fall back
-- to that rather than breaking the addon's load.
if not pcall(HookTooltips) and TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        OnItemTooltip(tooltip)
    end)
end

-- ===== Checking without hovering =====
-- Used by the item browser's "Check all" (ItemBrowser.lua).

-- Checks one database item against the game through the hidden scan tooltip.
-- Returns "ok" or "differs"; a difference is captured right away (keeping any
-- note already typed for it). Returns nil plus the reason when it can't be
-- checked: "uncached" (ask the server, try again later), "suffix",
-- "lowQuality" or "notEquippable".
function EverGear:CheckItemAgainstGame(itemId)
    local dbItem = self:GetItem(itemId)
    if not dbItem then return nil, "unknown" end
    local _, link = GetFullInfo(itemId)
    local record, reason, notes = self:BuildLiveItemRecord(link or ("item:" .. itemId))
    if not record then return nil, reason or "notEquippable" end

    local diffs = self:CompareLiveToDatabase(record, dbItem)
    local status = #diffs > 0 and "differs" or "ok"
    EverGearDB.debugChecked = EverGearDB.debugChecked or {}
    EverGearDB.debugChecked[itemId] = status
    if status == "differs" then
        local existing = Captures()[itemId]
        StoreCapture(record, status, diffs, notes, dbItem.stats, existing and existing.sourceNote)
    end
    return status
end

-- Opens the debug window on an item that's already captured.
function EverGear:ShowDebugCapture(itemId)
    local entry = Captures()[itemId]
    if not entry then return end
    ShowFlaggedItem(entry.record, entry.status, entry.diffs, entry.notes, entry.addonStats)
end

-- ===== Slash commands =====

function EverGear:HandleDebugCommand(arg)
    EverGearDB = EverGearDB or {}
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "export" then
        if not debugFrame then BuildWindow() end
        ShowExport()
        return
    elseif arg == "pending" then
        EverGearDB.debugShowPending = (EverGearDB.debugShowPending == false)
        if debugPendingCheck then debugPendingCheck:SetChecked(EverGearDB.debugShowPending) end
        print("|cff33ff99EverGear|r debug: pending-source items popups " .. (EverGearDB.debugShowPending and "|cff00ff00ON|r" or "|cffff4040OFF|r"))
        return
    elseif arg == "items" then
        EverGear:ToggleItemBrowser()
        return
    elseif arg == "clear" then
        EverGearDB.debugCaptures = {}
        RefreshCaptureUI()
        print("|cff33ff99EverGear|r debug: captures cleared.")
        return
    end

    if arg == "on" then
        EverGearDB.debugMode = true
    elseif arg == "off" then
        EverGearDB.debugMode = false
    else
        EverGearDB.debugMode = not EverGearDB.debugMode
    end
    lastLink = nil
    if EverGearDB.debugMode then
        print("|cff33ff99EverGear|r debug mode |cff00ff00ON|r -- hover an item that's missing or wrong in the addon to flag it.")
        print("  /eg debug export  -- show captured items as JSON     /eg debug clear  -- forget captures")
        print("  /eg debug items  -- browse every item in EverGear's data")
    else
        print("|cff33ff99EverGear|r debug mode |cffff4040OFF|r.")
        if debugFrame then debugFrame:Hide() end
    end
    if EverGear.OnItemBrowserCheck then EverGear:OnItemBrowserCheck() end
end
