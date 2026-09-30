# EverGear

**A leveling gear-upgrade advisor for WoW Forever.**

Open your character panel's evil twin: EverGear shows every equipment slot with a
badge on top telling you at a glance whether an upgrade exists, how big it is, or
whether you're already Best-in-Slot. Click any slot to see exactly which items beat
what you're wearing, where to get them, and why.

## Features

- **Paperdoll-style upgrade view** -- every gear slot laid out like your character
  panel, each with a floating badge ("+14", "BIS", or nothing) so you can tell your
  whole kit's status at a glance without opening a single tooltip.
- **Click a slot for details** -- see every upgrade candidate for that slot ranked
  best-first, where it comes from (quest, vendor, dungeon boss, crafted), and how it
  compares to what you have equipped.
- **Spec-aware scoring** -- pick your spec from the dropdown and EverGear weights
  stats around the right role (tank/melee DPS/caster/healer) instead of treating
  every stat as equally useful.
- **Look-ahead slider** -- preview upgrades above your current level, so you know
  what to aim for instead of only seeing what you can equip right now.
- **Fine-grained filters** -- toggle suggestions by source (quest / vendor / craft /
  world drop / dungeon drop), by weapon type (including 1H/2H split for
  axes/maces/swords), and by profession. A per-profession "BoE only" option lets you
  browse a profession's crafted gear even without having it yourself, restricted to
  items you could actually buy or trade for.
- **Class/armor-aware** -- suggestions respect your class's usable weapon and armor
  types, including the level-40 gate on Mail/Plate proficiency for
  Hunters/Shamans/Warriors/Paladins, so you're never shown gear you can't wear yet.
- **Per-character settings** -- filters, spec, and look-ahead level are remembered
  separately for each of your characters.
- Minimap button, plus `/evergear` or `/eg` to toggle the window.

## Why EverGear exists

WoW Forever is brand new, so unlike Classic/TBC there's no mature, complete item
database to pull from yet -- drop and quest-reward data is still being discovered by
players and community trackers as people level through the game. EverGear ships with
whatever data exists at any given time and grows as more is discovered: bulk data is
pulled from community trackers (wowtbc.gg, foreverdb.net), and anything found in-game
that isn't tracked anywhere yet gets added by hand.

**In practice, this means the data is incomplete and will keep growing.** If EverGear
doesn't suggest an upgrade you know exists, it's very likely just missing from the
data yet, not a bug -- and it'll get filled in over time.

## Status

Actively developed. Version is shown in small text bottom-left of the addon's own
window. See the [CHANGELOG](https://github.com/BurnEmDown/evergear/blob/master/CHANGELOG.md)
for what's shipped in each version.

## Install

Copy the `EverGear` folder into your WoW Forever `Interface/AddOns` directory.
