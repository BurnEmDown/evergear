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

`## Interface: 11507` is a placeholder guess for a Classic-era-based client. Once you're
in the WoW Forever beta client, run `/run print(select(4, GetBuildInfo()))` in-game and
update the `.toc` if it differs.
