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

Pick your spec from the dropdown and scoring adjusts to match it. A tank and a caster
don't care about the same stats, so a piece loaded with Intellect won't show up as an
upgrade for your Protection Warrior. There's also a look-ahead slider if you want to
peek at upgrades above your current level instead of only what you can wear today.

You can filter by source (quest, vendor, craft, world drop, dungeon drop), by weapon
type (axes/maces/swords even split out by 1H vs 2H), and by profession, with a "BoE
only" option so you can see what a profession makes without having leveled it, limited
to what you could actually buy or trade for. It also knows what your class can wear,
so Hunters, Shamans, Warriors, and Paladins won't get pointed at Mail or Plate before
they've hit the level where they can actually equip it.

Filters, spec, and look-ahead level all save per character. There's a minimap button
too, or just type `/evergear` or `/eg`.

## Why EverGear exists

Classic and TBC already have mature item databases built up over years. WoW Forever
is brand new, so nobody's fully mapped out what drops where yet -- that's still
happening in real time as people level through it. EverGear works with whatever's
known at any given moment: most of its data comes from community-sourced loot
trackers, and anything spotted in-game that hasn't been logged anywhere else gets
added by hand.

That means gaps are inevitable for now. If EverGear doesn't show an upgrade you know
exists, the data just hasn't caught up yet -- it's not a bug, and it'll get filled in.

## Status

Actively developed. The version number sits in small text at the bottom-left of the
addon's window. Check the [CHANGELOG](https://github.com/BurnEmDown/evergear/blob/master/CHANGELOG.md)
for what's shipped in each release.

## Install

Copy the `EverGear` folder into your WoW Forever `Interface/AddOns` directory.
