EverGear = EverGear or {}
EverGear.ADDON_NAME = "EverGear"
EverGear.VERSION = "0.1.0"

-- Populated later from Data\*.lua files. Each entry keyed by numeric item id.
-- Canonical item shape (mirrors evergear-backend/schema.md):
-- {
--   id = 1234,
--   name = "Item Name",
--   slot = "HEAD",              -- inventory slot token, see EQUIP_SLOTS below
--   armorType = "Cloth",        -- Cloth / Leather / Mail / Plate / nil for non-armor
--   ilvl = 5,
--   minLevel = 3,
--   confirmed = true,           -- false = seen on a tracker site but not yet in-game verified
--   source = {
--     type = "dungeonDrop",     -- worldDrop | dungeonDrop | raidDrop | quest | vendor | craft
--     zone = "The Stockade",
--     boss = "Hamhock",         -- present for dungeonDrop/raidDrop
--     chance = 0.18,            -- optional, 0-1
--   },
--   stats = {
--     STAMINA = 4,
--     STRENGTH = 2,
--     -- etc, keys match the GetItemStats() API naming used in Equipment.lua
--   },
-- }
EverGear.Items = EverGear.Items or {}

EverGear.EQUIP_SLOTS = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}
