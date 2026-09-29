EverGear = EverGear or {}
EverGear.ADDON_NAME = "EverGear"

-- Versioning policy (started 2026-09-29, shown bottom-left of the main
-- window by UI.lua): bump the PATCH digit (third number) on every shipped
-- change, no matter how small -- 0.0.1 -> 0.0.2 -> 0.0.3, etc. Moving to
-- 0.1.0 or 1.0.0 is the user's call alone; Claude may suggest it's time,
-- but must never bump a minor/major version on its own initiative.
EverGear.VERSION = "0.0.8"

-- Populated later from Data\*.lua files. Each entry keyed by numeric item id.
-- Canonical item shape (mirrors evergear-backend/schema.md):
-- {
--   id = 1234,
--   name = "Item Name",
--   slot = "HeadSlot",              -- real inventory slot token for most gear (see
--                                    -- EQUIP_SLOTS below), OR one of the two GENERIC
--                                    -- slot tokens "FingerSlot"/"TrinketSlot" for rings
--                                    -- and trinkets, since those don't have a single
--                                    -- real slot -- see GENERIC_SLOT_FOR_REAL_SLOT.
--   armorType = "Cloth",        -- Cloth / Leather / Mail / Plate / nil for non-armor
--   ilvl = 5,
--   minLevel = 3,
--   confirmed = true,           -- false = seen on a tracker site but not yet in-game verified
--   bindType = "BoE",           -- "BoE" / "BoP" / "BoU" / nil (unconfirmed -- treated as NOT
--                                -- BoE by the "BoE only" profession filter in UI.lua, never
--                                -- assumed). Currently only populated for crafted items:
--                                -- foreverdb.net doesn't expose bind type in static HTML for
--                                -- ANY item (confirmed absent, not just for new items), so real
--                                -- item ids (< 100000) are seeded "BoE" on the well-established
--                                -- Classic/TBC-era rule that ordinary trainer-taught leveling
--                                -- profession gear is virtually always Bind on Equip -- WoW
--                                -- Forever's own custom items (id >= 200000) are NOT assumed
--                                -- and stay nil until verified in-game.
--   source = {
--     type = "dungeonDrop",     -- worldDrop | dungeonDrop | raidDrop | quest | vendor | craft
--     zone = "The Stockade",
--     boss = "Hamhock",         -- present for dungeonDrop/raidDrop
--     quest = "Quest Title",    -- present for quest
--     chance = 0.18,            -- optional, 0-1
--   },
--   stats = {
--     STAMINA = 4,
--     STRENGTH = 2,
--     -- etc, keys match the GetItemStats() API naming used in Equipment.lua.
--     -- A few keys (WEAPON_DAMAGE in particular) hold a display string rather
--     -- than a number -- anything reading this table for arithmetic must skip
--     -- non-numeric values.
--   },
-- }
EverGear.Items = EverGear.Items or {}

-- Real WoW inventory slot tokens, in the order Equipment.lua iterates them.
EverGear.EQUIP_SLOTS = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

-- Rings and trinkets each have two real slots, but item data only ever tags an
-- item generically as "goes in a finger slot" / "goes in a trinket slot" -- so
-- when looking up candidates FOR a specific real slot, check this map first and
-- fall back to the real slot token itself if it's not a ring/trinket slot.
EverGear.GENERIC_SLOT_FOR_REAL_SLOT = {
    Finger0Slot = "FingerSlot",
    Finger1Slot = "FingerSlot",
    Trinket0Slot = "TrinketSlot",
    Trinket1Slot = "TrinketSlot",
}

-- Friendly display names for the UI (tooltips, detail panel headers).
EverGear.FRIENDLY_SLOT_NAMES = {
    HeadSlot = "Head", NeckSlot = "Neck", ShoulderSlot = "Shoulder",
    BackSlot = "Back", ChestSlot = "Chest", WristSlot = "Wrist",
    HandsSlot = "Hands", WaistSlot = "Waist", LegsSlot = "Legs", FeetSlot = "Feet",
    Finger0Slot = "Ring 1", Finger1Slot = "Ring 2",
    Trinket0Slot = "Trinket 1", Trinket1Slot = "Trinket 2",
    MainHandSlot = "Main Hand", SecondaryHandSlot = "Off Hand", RangedSlot = "Ranged",
}

-- Blizzard's built-in "empty slot" placeholder icons, same set Leveling Gear
-- Advisor uses. BackSlot's path is a best-effort guess (reuses the Chest
-- texture) -- flag it if it renders wrong/blank in-game.
EverGear.EMPTY_SLOT_TEXTURES = {
    HeadSlot     = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Head",
    NeckSlot     = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Neck",
    ShoulderSlot = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Shoulder",
    BackSlot     = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest",
    ChestSlot    = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Chest",
    WristSlot    = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Wrist",
    HandsSlot    = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Hands",
    WaistSlot    = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Waist",
    LegsSlot     = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Legs",
    FeetSlot     = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Feet",
    Finger0Slot  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    Finger1Slot  = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Finger",
    Trinket0Slot = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    Trinket1Slot = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Trinket",
    MainHandSlot      = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-MainHand",
    SecondaryHandSlot = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-SecondaryHand",
    RangedSlot        = "Interface\\PaperDollInfoFrame\\UI-PaperDoll-Slot-Ranged",
}

-- Which known source.type values currently exist and how to label them in the
-- filter row. Order here is display order. New types (raidDrop, vendor, etc.)
-- just need a row added here -- everything else reads this list generically.
-- Raid Drop deliberately omitted for now (not relevant until the addon has
-- raid data) -- add it back here when that data exists.
EverGear.SOURCE_TYPE_FILTERS = {
    { key = "quest",       label = "Quest" },
    { key = "vendor",      label = "Vendor" },
    { key = "craft",       label = "Craft" },
    { key = "worldDrop",   label = "World Drop" },
    { key = "dungeonDrop", label = "Dungeon Drop" },
}

-- Every weapon/shield subtype the backend's converter can tag an item with
-- (see evergear-backend's KNOWN_WEAPON_TYPES), in display order. Drives the
-- single weapon-type filter checklist in UI.lua -- Upgrades.lua's
-- CLASS_USABLE_WEAPON_TYPES narrows this down to only the types a given
-- class/spec can actually equip, so e.g. a Mage never sees an "Axe"
-- checkbox it has no use for either way.
EverGear.WEAPON_TYPE_FILTER_LIST = {
    { key = "axe",          label = "Axe" },
    { key = "mace",         label = "Mace" },
    { key = "sword",        label = "Sword" },
    { key = "dagger",       label = "Dagger" },
    { key = "fist weapon",  label = "Fist Weapon" },
    { key = "polearm",      label = "Polearm" },
    { key = "staff",        label = "Staff" },
    { key = "wand",         label = "Wand" },
    { key = "bow",          label = "Bow" },
    { key = "gun",          label = "Gun" },
    { key = "crossbow",     label = "Crossbow" },
    { key = "thrown",       label = "Thrown" },
    { key = "shield",       label = "Shield" },
    -- Synthetic type (see evergear-backend's convert_to_canonical.py) for
    -- Libram/Idol/Totem/Orb-style held-in-off-hand items that aren't a real
    -- weapon or shield -- occupies the same slot as Shield, so it needs its
    -- own row rather than being lumped in with (or invisible to) that filter.
    { key = "offhand",      label = "Off Hand" },
}

-- Professions that actually produce equippable gear -- gathering professions
-- (Herbalism, Mining, Skinning) and consumable-only ones (Alchemy, Cooking,
-- First Aid, Fishing) are left out since they never show up as an item
-- source here either way. Jewelcrafting is left out too -- it doesn't exist
-- as a profession in WoW Forever at all. Drives the profession filter
-- checklist in UI.lua, same button+panel pattern as the weapon-type filter.
-- Every profession shown by default; unchecking one hides crafted items
-- tagged with it (see source.profession in evergear-backend/schema.md) --
-- e.g. checking only Blacksmithing hides Leatherworking/Tailoring/etc
-- crafted suggestions.
EverGear.PROFESSION_FILTER_LIST = {
    "Blacksmithing", "Leatherworking", "Tailoring",
    "Engineering", "Enchanting",
}

-- Weapon types where the addon's data actually distinguishes one-handed from
-- two-handed (via item.isTwoHand -- see evergear-backend/schema.md), the same
-- way real WoW item subclass IDs split "Axe" into two separate subclasses.
-- For these, the filter checklist below shows two rows ("Axe (1H)" / "Axe
-- (2H)") instead of one, so e.g. a Protection Warrior can uncheck just
-- "Mace (2H)" and keep 1H maces + shields showing. Every other type here is
-- inherently only ever one length (Dagger, Staff, Bow, ...), so it gets a
-- single row.
EverGear.SPLIT_WEAPON_TYPES = { axe = true, mace = true, sword = true }
