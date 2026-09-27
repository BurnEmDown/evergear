EverGear = EverGear or {}
EverGear.ADDON_NAME = "EverGear"
EverGear.VERSION = "0.1.0"

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
