# Changelog

## [0.0.29] - 2026-10-09

### Added
- Wanted list and gear sets, per character. Alt-click any item (bags,
  character sheet, chat links, loot, quest rewards, EverGear's own window)
  to put it on the wanted list or into a gear set; the star on a Suggested
  Upgrades row adds it to the wanted list. Open them with the buttons in the
  top-left corner of the main window, or `/eg wanted` and `/eg sets`.
  - Wanted items that turn up in your bags or get equipped are ticked as
    acquired and stay on the list until you remove them.
  - Up to 20 gear sets per character, with unique names of up to 30
    characters. A set can't hold a two-hander and an off-hand item together,
    and items your class can't use are refused.
  - Gear tooltips say when an item is wanted or in a set.
- City of Dalaran: quest rewards for both factions and the full boss loot.
- Razorfen Downs: drops from Mordresh Fire Eye, Glutton and Tuten'kash.
- More items, among them Knight's Lance, Brewer's Bracers, Repurposed Hair
  Band, Hunter's Muzzle Loader, Quillord Mail Leggings, Thorncursed Grips,
  Thornweaver Drape, Dire Wand, Fury Ring and Nat Pagle's Extreme Anglin'
  Boots.

### Changed
- EP profiles: up to 8 custom profiles per class and spec, and names must be
  unique within a spec and at most 30 characters.
- Items listed by tracker sites (wowtbc.gg, wowhead) count as confirmed.

### Fixed
- Stats updated from in-game checks for many items, among them Fallen
  Guard's Pendant (it was ranked too high for tanks), Master Hunter's Bow and
  Rifle, Defias Renegade Ring, Lucine Longsword, Burning Sliver, Reliquary
  Mantle, Pronged Reaver, Tiger Band, Beetle Clasps and Talvash's Gold Ring.
- Truthseeker's Bow requires level 40.
- Debug mode missed armor values over 999 (e.g. Collection Plate's 1,380
  armor) and reported them as a difference.

## [0.0.28] - 2026-10-08

### Added
- Quest rewards are no longer suggested before you can pick up the quest:
  each one now knows its quest's required level (e.g. the Morganth rewards
  wait until 20, "Oh Brother..." until 15).
- Rune-Etched Ring, Raptor's End, Dwarven Guard Cloak, Firestarter, Lesser
  Magic Wand (Enchanting), Rage of the Storm (The Tempest's Weapons), and
  Wild Headdress, Stromgarde Bracers, Arathi Armbands and War Rider Bracers
  (Arathi Highlands Wanted quests).
- Fight Club (Scarlet Monastery trash), and Crest of Elucidation and
  Researcher's Night Light (Greater Friend of the Library, 25 books).

### Fixed
- "BoE only" on a profession still suggested Bind on Pickup items such as
  Goblin Mining Helmet: bind types now come from the game's own item data.
- "Usable Only" unticked Staves for Warriors and Hunters, who can use them.
- Items that aren't in WoW Forever or have no stats (e.g. The Frozen Clutch,
  "Encrypted by Forever Beta Build" in game) are no longer suggested.
- Quest names: Seal of Wrynn (An Audience with the King), Razzeric's Racing
  Grips (Safety First). Slain Baron's Signet, Grave Shroud and Monstrous
  Cleaver show only your faction's quest (Abominable Creatures / Unending
  Torment).
- Library book rewards are listed as Special ("Hand in 10/20/25 library
  books") instead of quests; Truthseeker's Bow needs 25 books and level 30.
- Talvash's Gold Ring (Gnome Improvement) is listed under Gnomeregan.
- Malignant Root is listed as Special (turn in Rotheap Innards to Rethiel the
  Greenwarden), not as a quest reward.
- Arcane Runed Bracers and Rod of Sorrow stats; Rage of the Storm no longer
  shows a Stormstrike equip line.
- Some Alliance-only quest rewards (Wetlands, Excavation Site) were offered
  to Horde characters.

## [0.0.27] - 2026-10-07

### Added
- 163 items that were held back for lack of a known source are now
  suggested: 118 world drops, 34 quest rewards, 5 dungeon drops, 5 vendor
  items and Blackfury (Blacksmithing). Class-quest rewards (e.g. Blade of
  Cunning, Bastion of Stormwind, Whirlwind Axe) are only suggested to that
  class.
- 19 more items, among them the Scarlet Monastery: Library drops from
  Arcanist Doan and Houndmaster Loksey, Golem War Cloak, Energized Stone
  Circle, Moonlit Amice, Alterac Assassin's Gloves, Heavehammer and Fire
  Hardened Hauberk.
- A "Special" source type for items that aren't a plain drop, quest,
  vendor or craft, with its own filter checkbox. First one: Coldflame Saber
  (Blade of Silverlaine + Scroll of the Saber).
- World drops that come from one named mob or rare now name it, e.g.
  "World Drop - Teldrassil (Nightscreech)".

### Fixed
- Wrong or missing stats on Swampchill Fetish, Windweaver Staff, Snake Eye
  Kaleidoscope, Yeti Fur Cloak, Consecrated Wand, Sizzle Stick, Geomancer
  Headdress and Dwarven Defender. Swampchill Fetish and Windweaver Staff
  are now listed as Scarlet Monastery trash outside the Graveyard.
- Debug mode flagged items whose healing bonus is worded "Increases healing
  done by magical spells and effects" (e.g. Death Speaker Scepter) as
  missing that bonus in-game.
- The "Dungeon Drop" filter label ran into the checkbox next to it.

## [0.0.26] - 2026-10-06

### Added
- Resilient Bands, Yorgen Bracers, Holy Shroud (world drops).
- Northshire Hammer (Rare Books) and Apprentice Wizard's Gown
  (WANTED: "Hogger"), Elwynn Forest.
- Silk Mantle of Gamn (Uncovering the Past) and Malignant Root (turning
  in Rotheap Innards to Rethiel the Greenwarden), Wetlands.
- Steadfast Cinch (Escape Through Force), Darkshore.
- Skycaller's Leather Belt (Leatherworking) and Crimson Silk Belt
  (Tailoring).

### Fixed
- Compact Hammer was missing its weapon damage and speed, so its damage
  counted for nothing.
- Wind Spirit Staff had the wrong damage (76-115 instead of 56-85) and
  was missing its +23 spell damage and +71 healing.
- 65 armor pieces in Darkshore, Teldrassil, Loch Modan and Silverpine
  Forest were marked as one-handed weapons, which made debug mode flag
  them (e.g. Ridgeback Bracers, Hammerfist Gloves).

## [0.0.25] - 2026-10-06

### Added
- Zephras Isle: 39 quest-reward items from the zone's 16 gear-reward
  quests (levels 1-11), including Watcher's Mail Chest, Flutterfly
  Swatter, Planting Shovel and Windshaped Shield. Horde-only rewards
  (To Valanaar, A Firm Response, Meddlesome Mages) and the Alliance-only
  Dowsing Rod (A Magical Affront) are only suggested to that faction.
  Idol of Shifting Tides and Totem of Charged Flames are limited to
  Druids and Shamans. All are sourced from wowseer.gg and foreverdb.net
  and not yet checked in-game, so `/eg debug` captures are welcome.

### Removed
- 63 random-suffix items ("of the Eagle", "of the Tiger", "of Spirit",
  ...), e.g. Ivycloth Bracelets of the Eagle and Splitting Hatchet of
  the Owl. Every suffix of an item shares one item id but gives
  different stats, so EverGear can't tell which one a player has and
  was suggesting the wrong stats. They're kept aside to be added back
  once suffixes are supported.

### Fixed
- Debug mode now ignores random-suffix items. It was still flagging them
  as missing, because WoW Forever's item links don't always carry the
  suffix. An item whose own name contains "of ..." (a quest item like
  "... of Ganm") is still checked as usual.

## [0.0.24] - 2026-10-06

### Fixed
- Protection Warriors and Paladins were suggested off-hand-only weapons
  (e.g. Shoni's Disarming Tool) as upgrades over their shield, because both
  share the off-hand slot and the weapon's stats could outscore the shield.
  Tank specs that can use a shield now only get shields in the off-hand slot.

## [0.0.17] - 2026-10-05

### Added
- Precision Bow (world drop), the first world-drop item in the addon.

### Changed
- Protection Warrior (Mitigation) scoring: weapon DPS now counts a little
  (it used to count for nothing, so a weapon with no bonus stats always
  scored 0 however good its damage was), and Strength is now weighted the
  same as Stamina instead of almost nothing. A plain caster mace could
  previously outrank a Strength/Stamina tank weapon on a couple of
  Stamina points alone.

### Fixed
- Golden Iron Destroyer, Solid Iron Maul and Bronze Battle Axe were marked
  one-handed but are two-handed, so they ignored the "exclude two-handed"
  filter. Golden Iron Destroyer's bogus "Spell Power 4" is now +4 Spell
  Damage and +4 Healing.
- Crested Scepter's Spell Damage and Healing (+32 each) were removed in
  0.0.16 by mistake -- they're real, and are back. Its Spirit is now
  Intellect, and its damage range is corrected to 33-62.

## [0.0.16] - 2026-10-04

### Added
- Razorfen Kraul: 40 items across its 8 bosses, trash, and quest rewards
  (Willix the Importer, Mortality Wanes, and the Alliance/Horde pair The
  Crone of the Kraul / A Vengeful Fate).

### Fixed
- Gnomeregan's Civinad Robes, Triprunner Dungarees, and Dual Reinforced
  Leggings were marked Horde-only ("Rig Wars"), so Alliance players were
  told they could never get them -- in reality Alliance gets the same
  3 items from their own version of the quest ("The Grand Betrayal").
  These are no longer faction-filtered, and the detail panel now shows
  whichever quest name matches the viewer's own faction.
- 17 items across 11 zone/crafted data files had the wrong one-hand/
  two-hand flag (wowtbc.gg's own scrape data was wrong), letting them
  slip past the "exclude two-handed weapons" filter regardless of what
  was checked -- e.g. Woodsman Sword and Heavy Copper Broadsword kept
  showing up as suggestions with 2H unchecked. Includes Bonecracker,
  Steady Bastard Sword, Trogg Slicer, Dwarven Tree Chopper, Logsplitter,
  Coldridge Hammer, Samophlange Screwdriver, Zhovur Axe, Copper Claymore,
  Copper Battle Axe, Edge of the People's Militia, Goblin Smasher
  (wrongly 1H, actually 2H), and Brushwood Blade, Defender Axe,
  Thornroot Club (wrongly 2H, actually 1H).
- Crested Scepter (Blackfathom Deeps) had a fabricated +32 Spell Damage
  and +32 Spell Healing that don't exist on the real item, plus a wrong
  weapon damage range -- this was inflating its suggestion score even
  for melee/tank specs with no use for spell power.
- Razorfen Kraul: corrected stats, item level, and/or weapon damage on
  25 of its 40 items (re-verified against WoW Forever's own game
  database rather than Wowhead tooltip fetches, which turned out to be
  unreliable for this dungeon), plus Armor corrections on Ferine
  Leggings, Whisperwind Headdress, Heart of Agamaggan, Batwing Mantle,
  and Tusken Helm (which also gets a separate +120 Armor buff beyond its
  base value).
- Gear scoring: a stat no EP profile has an explicit weight for used to
  silently score at a flat 0.3-per-point default instead of 0 -- this is
  exactly how Crested Scepter's fabricated spell power was skewing its
  score under Protection Warrior Mitigation and every other profile that
  hadn't explicitly zeroed those keys out.

## [0.0.15] - 2026-10-04

### Added
- Custom EP (Equipment Points) profiles: create, duplicate, rename, and
  delete your own weight profiles per class/spec, with every stat exposed
  as an explicit per-stat weight grid instead of a single "Primary Stat"
  dropdown.
- A builtin profile can now offer multiple variants for one spec (e.g.
  Warrior Protection: Mitigation vs. Threat), selectable from the same
  dropdown as custom profiles.
- "Copy to..." popup to copy a profile's weights across specs or classes,
  plus Export/Import of a profile as copy-pasteable JSON text.
- Weapon scoring now accounts for actual speed and damage range, not just
  DPS: four new per-profile weights (`avgDamageWeight`, `maxDamageWeight`,
  `fastWeaponWeight`, `slowWeaponWeight`) alongside the existing
  `dpsWeight`.

### Changed
- Every class's builtin EP weights updated to match sixtyupgrades.com's
  published weight sets (Warrior, Hunter, Rogue, Warlock, Mage, Priest,
  Paladin, Shaman, and Druid), replacing earlier hand-tuned placeholders.
  Paladin Protection was left untouched (not covered by sixtyupgrades).
- Weight range raised from 0-5 (step 0.1) to 0-100 (step 0.01) so
  real sixtyupgrades-scale weights (e.g. Haste = 100) aren't clipped.
- Secondary combat stats renamed from speculative TBC-style "ratings"
  (Hit Rating, Crit Rating, Haste Rating, etc.) to the flat percentages
  WoW Forever actually grants, with every existing weight rescaled to
  preserve each profile's relative emphasis. Expertise and Resilience
  removed outright -- confirmed to not exist as mechanics in this game.
- Profile editor moved next to the main window (opens to its left and
  stacks with the upgrade-suggestions panel instead of overlapping it),
  reorganized its weight grid (secondary stats grouped and ordered,
  resistances moved to their own section at the bottom), and no longer
  drags around the screen.

### Fixed
- A crash opening the New/Duplicate/Rename profile popups caused by a nil
  editBox reference.
- `DEFENSE_SKILL_RATING` was mapped to a key no profile ever defined, so a
  live-equipped item's Defense silently scored via a generic fallback
  instead of each profile's real Defense weight.
- The profile editor's "Copy to...", Export, and Import popups weren't
  actually opaque (the background tint couldn't exceed the dialog art's
  own built-in transparency), could be opened several at once stacked on
  top of each other, and stayed open if the editor itself was closed
  (including when closing the main window). Also resized Copy To
  (taller, narrower) and the Weapon Types panel (slightly taller).
- The gear-upgrade suggestion panel would sometimes fail to open on the
  first click of a slot, only opening on the second -- a background
  item-cache-refresh event triggered by that same click could silently
  close the panel before the player ever saw it.

## [0.0.14] - 2026-10-03

### Changed
- Paper-doll slot icon borders now show the equipped item's rarity color
  (gray/white/green/blue/purple/yellow) instead of the upgrade-status
  color. Best-in-slot items still show a "BIS" badge, and upgradable items
  now show their "+X" score delta with a small green arrow next to it
  (cropped from the addon's own icon) -- the badge pill carries the
  upgrade-status signal on its own now that the slot border doesn't.
- An empty equipment slot's border is now white (matching "Common"
  quality) instead of the same neutral-gold used for a cache-miss on a
  real item -- those are different situations ("nothing equipped" vs.
  "something's equipped but not resolved yet") and should look different.

### Fixed
- The new rarity-colored slot/detail-panel borders showed yellow for an
  item the client hadn't cached yet instead of its real rarity color --
  most noticeable the first time opening a slot's upgrade list, since
  those candidates are often items the player has never seen before.
  Previously required closing and reopening to pick up the right color
  once the client's background fetch landed; now self-corrects in place
  via the client's GET_ITEM_INFO_RECEIVED event.

## [0.0.13] - 2026-10-03

### Added
- Excavation Site: Wetlands dungeon, entirely missing from the addon
  before now: 8 items across its 3 bosses (Saltspine, Shadetooth, Relic
  Guardian).
- Verigan's Fist (6953), a Paladin-only quest reward ("Test of
  Righteousness"), missing from both The Deadmines and Shadowfang Keep's
  data.
- Two Stockade quest rewards missing from the scrape: Headbasher and
  Belt of Vindication ("The Fury Runs Deep").

### Fixed
- Re-verified and corrected item data for Ragefire Chasm, Ruins of
  Lordaeron, The Deadmines, Wailing Caverns, Shadowfang Keep, and The
  Stockade (around 70 items total) against current Wowhead tooltips.
  Recurring issues: missing or wrong weapon damage/speed/DPS, missing
  armor and shield block values, wrong spell power/damage/healing
  amounts, proc effects mislabeled as on-hit procs instead of passive
  equip auras (and vice versa), flattened weapon-proc damage ranges
  shown as a single (often wrong) number, and raw internal placeholder
  text leaking into a couple of tooltip fields instead of real wording.
- Tarnished Locket (279870, Ruins of Lordaeron) had the wrong
  Strength/Stamina values.

## [0.0.12] - 2026-10-02

### Changed
- Completed the per-class EQ scoring pass: added HP5/MP5 scoring weights to
  every spec profile (Priest, Shaman, and Druid were the remaining classes;
  Warrior, Rogue, Hunter, Mage, Warlock, and Paladin were already done).

### Fixed
- `MOVEMENT_IMPAIRING_REDUCTION`/`THREAT_REDUCTION`/fire resistance stored as
  percent strings instead of numbers across several dungeon items, which
  silently zeroed their contribution to the upgrade score.
- Plaguefang's (Ruins of Lordaeron) poison proc wasn't counted toward its
  weapon DPS, understating its score vs. comparable weapons.

## [0.0.11] - 2026-09-29

### Added
- 200 missing early-tier crafted profession items found by re-scanning
  foreverdb.net against the 4 tracked professions: Blacksmithing (+63),
  Tailoring (+86), Leatherworking (+46), Engineering (+5). Same
  early-leveling tier as existing data (roughly minLevel <=35 / ilvl <=40).

## [0.0.10] - 2026-09-29

### Fixed
- Filter checkboxes (source type, weapon type, profession, profession
  BoE-only), spec, and look-ahead level were stored account-wide, so
  switching characters carried over the previous character's settings
  (e.g. a Druid seeing a Hunter's usable weapon types). Each character now
  gets its own saved settings; window position/size remain shared
  intentionally.

## [0.0.9] - 2026-09-29

### Fixed
- Item icon textures overlapped their colored border by up to 1px in
  height on some icons, due to texture-height rounding pushing past a
  too-small inset. Icon inset now matches the border's edge width exactly.
- Synced a manual edit to the version text's vertical offset.

## [0.0.8] - 2026-09-29

### Changed
- Synced hand-tuned window/panel sizing values (frame height, top/bottom
  insets) and rewrote the layout comments to match.

## [0.0.7] - 2026-09-29

### Changed
- Controls panel height +5px, BoE-only column dropped 5px further, main
  window height -15px (removed from the bottom).

## [0.0.6] - 2026-09-29

### Changed
- Controls panel height +5px, BoE-only checkboxes/label dropped 5px,
  content panel height -15px (removed from the bottom, version text
  shifted up to compensate).

## [0.0.5] - 2026-09-29

### Changed
- Controls panel width now matches the suggestions panel exactly.
- Profession filter panel: All/None buttons dropped ~5px, panel height
  +10px, "BoE" label reworded to "BoE Only" and moved above its checkboxes.

## [0.0.4] - 2026-09-29

### Added
- Per-profession "BoE Only" checkbox: suggests a profession's crafted
  items even without that profession, restricted to confirmed
  Bind-on-Equip items.

### Fixed
- Version text rendered behind the suggestions panel due to a WoW
  frame-level-vs-draw-layer ordering quirk; moved to its own
  explicitly-higher-leveled frame.

### Changed
- Controls panel made taller; weapon-type/profession filter buttons moved
  left.

## [0.0.3] - 2026-09-29

### Changed
- Version text position adjusted up by its own height; weapon-type and
  profession filter button positions nudged left; filter panel's top
  border height increased.

## [0.0.2] - 2026-09-29

### Fixed
- The addon now re-applies every saved filter checkbox's state to the UI
  every time the window opens, instead of only at addon load -- a
  checkbox could previously go stale (e.g. unchecking then re-checking
  "Craft" was required to see head-slot suggestions again).

## [0.0.1] - 2026-09-29

### Added
- Version number, shown in small text bottom-left of the main window.
  Versioning starts here: everything below this entry was built before
  version tracking began, folded in for a complete history.
- Gear suggestions from regular quests in the first 4 starting zones
  (Elwynn Forest, Durotar, Westfall, Mulgore), then 8 more leveling zones
  up to level 20 (The Barrens, Silverpine Forest, Loch Modan, Darkshore,
  Redridge Mountains, Teldrassil, Dun Morogh, Tirisfal Glades).
- Quest zone display and a full visual overhaul of the suggestions window.
- Initial craftable gear data: 169 items across Blacksmithing, Engineering,
  Leatherworking and Tailoring, wired into the profession filter.
- Missing Blacksmithing/Tailoring/Leatherworking helm and hood recipes.
- Addon icon.

### Fixed
- Quest reward items showing as suggestions at the wrong character level.
- Mail/Plate armor suggested to Hunters/Shamans/Warriors/Paladins before
  they actually train it at level 40 (they were previously gated only by
  their eventual max armor type, not by when they unlock it).
