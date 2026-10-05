# EverGear

A leveling gear-upgrade advisor addon for **WoW Forever**, in the same spirit as
[Leveling Gear Advisor](https://github.com/) for TBC Anniversary, but built for a game
whose loot data doesn't exist in any public database yet.

## Why this is different from the TBC project

TBC has a complete, mature community database (`tbc-db` / cmangos `classicdb`) to pull
from. WoW Forever is brand new — item/drop data is still being discovered by players
and community trackers as people level through the game. So EverGear ships with
whatever data exists at the time, and grows incrementally:

- Bulk data is pulled from community trackers (currently [wowtbc.gg's WoW Forever loot
  tables](https://wowtbc.gg/warcraftforever/loot-tables/)) by the
  [`evergear-backend`](https://github.com/amitreuveni/evergear-backend) pipeline.
- Anything the addon's author finds in-game that isn't on those trackers yet gets added
  by hand as a **manual** entry, which always takes priority over imported data for the
  same item id.

See `evergear-backend`'s README for the full data pipeline and schema.

## Status

Early scaffold. `Data/Items_Stockade.lua` is a placeholder — no items have been
converted from raw source data yet. Structure mirrors Leveling Gear Advisor
(`Core/Constants.lua`, `Database.lua`, `Character.lua`, `Equipment.lua`, `Upgrades.lua`,
`UI.lua`, `Main.lua`) so logic can be ported over as real WoW Forever item/stat data
comes in.

## Install

Copy this folder to:

```
D:\World of Warcraft\_classic_beta_\Interface\AddOns\EverGear
```

## Versioning

`EverGear.VERSION` (`Core/Constants.lua`) is shown in small text bottom-left of the
addon's main window. Policy, effective 2026-09-29:

- Every shipped change bumps the **patch** digit (0.0.1 → 0.0.2 → 0.0.3 …), no matter
  how small the change.
- Moving to **0.1.0** or **1.0.0** is the user's call alone. Claude may suggest when it
  seems like the right moment, but must never bump a minor/major version on its own.

## Note on the .toc Interface version

`## Interface: 16001` -- confirmed in-game via `/run print(select(4, GetBuildInfo()))`
on 2026-09-30, matching client version 1.30.1.10124. If WoW Forever ships a client
update, re-run that command and update this value if it changes.

## Debug mode

`/eg debug` toggles a developer mode for keeping the item database honest. While it is on,
hovering an equippable item that is missing from EverGear's data, or whose stats / slot /
type / level disagree with the game's tooltip, opens a small window listing what's wrong.
**Capture** records the item as the game shows it; **Export JSON** shows everything captured
in the `manual/<slug>.json` shape from `evergear-backend` (Ctrl+C, then paste it where it's
needed). Captures are also kept in `EverGearDB.debugCaptures`, which the game writes to
`WTF/Account/<account>/SavedVariables/EverGear.lua` on `/reload` or logout. Addons can't
write files themselves. Other commands: `/eg debug export`, `/eg debug clear`. Items with a
random suffix ("of the Monkey") are skipped.

## Releasing

The `.toc`'s `## Version:` line is `@project-version@`, a keyword the
[BigWigsMods packager](https://github.com/BigWigsMods/packager) substitutes for the
real version at package time, rather than a number hand-edited to match
`EverGear.VERSION`. `.github/workflows/ci.yml` and `release.yml` do the packaging:

- **Pull requests:** `ci.yml` builds the addon zip and attaches it to the workflow run
  as an artifact. Nothing is published.
- **Merge to master:** `ci.yml` builds again, then reads `EverGear.VERSION`. If tag
  `v<version>` doesn't exist yet, it creates and pushes it and triggers `release.yml`
  on that tag, which uploads to CurseForge. If the tag exists (version not bumped),
  nothing is released.
- If the CurseForge upload fails, re-run the Release job; the tag stays.
- To ship, bump `EverGear.VERSION` in the PR. Merging without a bump publishes nothing.

To release: bump `EverGear.VERSION` in `Core/Constants.lua`, add its `CHANGELOG.md`
entry, and merge. The upload needs a `CF_API_TOKEN` repo secret (Settings → Secrets and
variables → Actions) and `## X-Curse-Project-ID: <id>` in the `.toc`.

A zip delivered directly in chat (rather than via a pushed tag) still has the literal
`@project-version@` string substituted for the real version number before it's handed
over, so it's always correct to install even outside the tagged-release flow.
