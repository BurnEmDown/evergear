# Changelog

All notable changes to EverGear are recorded here. Versioning policy: the
patch digit (`0.0.X`) bumps on every shipped change, no matter how small.
Moving to `0.1.0` or `1.0.0` is a deliberate decision, not a patch-count
milestone -- see the "Versioning" section of `README.md`.

## [0.0.17] - 2026-10-04

### Added
- Razorfen Kraul: 40 items across its 8 bosses, trash, and quest rewards
  (Willix the Importer, Mortality Wanes, and the Alliance/Horde pair The
  Crone of the Kraul / A Vengeful Fate). 37 confirmed with real stats;
  3 Forever-only boss drops (Roogug's Severed Head, Geomancer Headdress,
  Death Prophet Spine) are in as unconfirmed placeholders pending a stat
  source.

## [0.0.16] - 2026-10-04

### Fixed
- Gnomeregan's Civinad Robes, Triprunner Dungarees, and Dual Reinforced
  Leggings were marked Horde-only ("Rig Wars"), so Alliance players were
  told they could never get them -- in reality Alliance gets the same
  3 items from their own version of the quest ("The Grand Betrayal").
  These are no longer faction-filtered, and the detail panel now shows
  whichever quest name matches the viewer's own faction.

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
