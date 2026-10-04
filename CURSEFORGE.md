# EverGear

**A leveling gear-upgrade advisor for WoW Forever.**

Think of it as your character panel's evil twin. Every equipment slot gets a little
badge telling you whether something better exists, how much better, or whether
you're already sitting on the best-in-slot item. Click a slot and you'll see exactly
which items beat what you've got, where to find them, and why they're worth the trip.

## Features

Every slot is laid out paperdoll-style, same as your character panel, with a badge
floating over it: "+14", "BIS", or nothing at all if there's nothing worth showing.
One glance tells you how your whole kit is doing, no tooltips required.

Click into a slot and you get the full list: every upgrade candidate for that slot,
ranked best first, where each one drops (quest, vendor, dungeon boss, crafted), and
how much it actually beats what you're wearing by.

Pick your spec from the dropdown and the scoring follows -- tank, melee DPS, caster,
healer all weight stats differently, so you're not told a tank piece is an upgrade
just because it has more Intellect. A look-ahead slider lets you preview upgrades
above your current level too, for when you want to know what to aim for rather than
just what you can slap on right now.

Filters go deep: source (quest, vendor, craft, world drop, dungeon drop), weapon type
(down to splitting 1H and 2H axes/maces/swords), and profession, including a "BoE
only" toggle so you can browse what a profession makes without needing to level it
yourself -- just the stuff you could realistically buy or trade for. Suggestions also
know your class's weapon and armor restrictions, including the level-40 gate on
Mail/Plate for Hunters, Shamans, Warriors, and Paladins, so you're never pointed at
gear you can't actually wear.

Everything -- filters, spec, look-ahead level -- is remembered per character. There's
a minimap button, and `/evergear` or `/eg` toggles the window if you'd rather not
click.

## Why EverGear exists

Classic and TBC have mature, complete item databases to build from. WoW Forever
doesn't -- it's brand new, so the drop and quest-reward data is still being figured
out by players and trackers as people actually level through the game. EverGear
ships with whatever's known at the time and grows from there: bulk data comes from
community trackers like wowtbc.gg and foreverdb.net, and anything spotted in-game
that isn't tracked anywhere yet gets added by hand.

So the data's going to be incomplete for a while, and that's expected, not a bug. If
EverGear doesn't flag an upgrade you know exists, it's probably just missing from the
data so far -- it'll get filled in over time.

## Status

Actively developed. The version number sits in small text at the bottom-left of the
addon's window. Check the [CHANGELOG](https://github.com/BurnEmDown/evergear/blob/master/CHANGELOG.md)
for what's shipped in each release.

## Install

Copy the `EverGear` folder into your WoW Forever `Interface/AddOns` directory.
