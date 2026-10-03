# Changelog

All notable changes to EverGear are recorded here. Versioning policy: the
patch digit (`0.0.X`) bumps on every shipped change, no matter how small.
Moving to `0.1.0` or `1.0.0` is a deliberate decision, not a patch-count
milestone -- see the "Versioning" section of `README.md`.

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
