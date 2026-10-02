# Custom EQ Profiles — Plan

Feature request: let a player define their own EQ (Equipment Quality / scoring)
weights per class+spec, on top of the built-in defaults already hand-tuned in
`EverGear.SPEC_PROFILES` (Core/Upgrades.lua), and export/import them as JSON.

This doc exists so the milestones below can be worked one at a time, each
independently testable, without re-litigating the design every step. Read the
"Assumptions / open questions" section first -- a couple of calls in there
affect several milestones at once, so flag now if any should change before
work starts on M1.

## What currently exists (context for the design below)

- `EverGear.SPEC_PROFILES[classToken][specName]` is a static Lua table per
  class+spec: `staminaWeight`, `armorWeight`, `dpsWeight`, `offStat = {...}`
  (a handful of cross-role stats like AGILITY/INTELLECT/SPIRIT), and
  `secondary = {...}` (everything else -- ~50 stat keys, 0 for "doesn't apply
  to this role").
- `GetScoringProfile(classToken, specName)` (Upgrades.lua:786) looks the spec
  up in that table and falls back to Warrior/Arms if somehow missing.
- `ScoreItem(stats, primaryStat, profile, offStatWeights, armorValue, dps)`
  (Upgrades.lua:805) is the actual scoring function. The primary stat's
  weight is hardcoded to `3.0` inline -- not currently part of the profile
  table at all.
- Spec selection lives in `EverGear:GetCharDB().spec`, per-character
  (Database.lua), read by a plain `UIDropDownMenuTemplate` dropdown in
  UI.lua (~line 217).
- No JSON library, no file I/O, and no existing "popup window with an edit
  box" pattern anywhere in the addon yet -- all net-new.

## Assumptions / open questions (confirm or override before M1)

1. **Profile storage scope: account-wide, not per-character.** A custom
   profile is tied to a class+spec, not to one specific alt -- e.g. a
   Holy Paladin profile you tune on one Paladin should be available on
   every Paladin on the account. Stored in `EverGearDB.customProfiles`
   (account-wide), not inside `GetCharDB()`. The *choice* of which profile
   is active stays per-character (extends the existing `charDB.spec`
   pattern with a new `charDB.profileId`), same as today.
2. **The built-in default profile is read-only, not just undeletable.**
   "Deletable except the default" is read as: the hand-tuned defaults stay
   exactly as committed in `Core/Upgrades.lua` and can't be edited in place
   (they're code, not saved data, so there's nowhere to persist an edit to
   anyway). To customize, the player hits "Duplicate" on Default, which
   creates an editable custom copy seeded with the exact same numbers. This
   avoids needing an "overrides" layer on top of the static table.
3. **JSON import/export is copy/paste text, not an actual file picker.**
   WoW's addon Lua sandbox has no filesystem access -- an addon cannot open
   a save dialog or read an arbitrary `.json` off disk. "Save/import to/from
   json files" is implemented the way every other WoW addon does
   import/export (WeakAuras, etc.): a popup with a selectable/editable
   multi-line text box containing JSON. Export: box is pre-filled and
   selected for Ctrl+C; the player pastes it into a text file themselves.
   Import: player pastes JSON text in and clicks Import. No in-game file
   system is touched.
4. **"Anything which can have a weight" includes the primary-stat weight.**
   Currently hardcoded as `3.0` in `ScoreItem`. A custom profile gets its own
   `primaryStatWeight` field (default 3.0, same 0-5 range as everything
   else) so it's tunable too, not a silent exception.
5. **Per-spec, not per-class.** Re-reading "own EQ profiles for each class"
   together with "for their played specs" -- a profile is scoped to one
   class+spec combo (matching how `SPEC_PROFILES` itself is already keyed),
   not one set of weights shared across a whole class's specs. Flag if the
   intent was actually class-wide.
6. **"Copy to..." works across any class+spec, not just same-class.**
   Confirmed: "copy my Fury Warrior EQ profile to Arms Warrior." The two
   specs don't share the same key set (`offStat` varies by spec -- e.g.
   Fury's is `{AGILITY, INTELLECT, SPIRIT}`, Protection's is
   `{STRENGTH, AGILITY, INTELLECT}`), so a straight table copy can't just
   overwrite the target wholesale. The merge rule: start from the target
   spec's own builtin defaults (so every key the target actually uses gets
   *some* sane value), then overwrite with whatever keys the source profile
   defines. A key the source doesn't have (because it wasn't relevant to
   the source spec) falls back to the target's own default rather than
   silently becoming 0. The 4 scalars (`primaryStatWeight`/`staminaWeight`/
   `armorWeight`/`dpsWeight`) always copy straight across -- they're
   meta-weights ("how much do I value my own primary stat"), not tied to
   which literal stat is primary, so there's nothing spec-specific to
   reconcile there. Nothing restricts the target to the same class --
   cross-class copies (e.g. Fury Warrior -> Frost Mage) go through the same
   merge and work out fine mechanically, if a little unusual as a choice.

## Weight fields covered by a profile

Every numeric field in a `SPEC_PROFILES` entry, generated from the table
shape itself (not hand-listed) so adding a new stat key to the defaults
later doesn't require separately updating the editor:

- 4 scalars: `primaryStatWeight`, `staminaWeight`, `armorWeight`, `dpsWeight`
- `offStat{}` entries (currently AGILITY/INTELLECT/SPIRIT -- varies by spec)
- `secondary{}` entries (~50 keys: ATTACK_POWER, SPELL_POWER, CRIT_RATING,
  HP5, MP5, resistances, etc. -- see Upgrades.lua:142-776 for the full set
  per spec)

All of them: range `[0, 5]`, step `0.1`.

## Milestones

### M1 -- Data model & persistence (no UI)
New `Core/EQProfiles.lua`:
- `EverGear:GetBuiltinProfile(classToken, specName)` -- read-only accessor
  wrapping today's `SPEC_PROFILES` lookup, now also exposing
  `primaryStatWeight = 3.0` as a real field.
- `EverGear:GetCustomProfiles(classToken, specName)` -- list of the
  player's saved profiles for that class+spec from
  `EverGearDB.customProfiles`.
- `EverGear:CreateCustomProfile(classToken, specName, name, weights)`,
  `:DeleteCustomProfile(...)` (refuses the synthetic "default" id),
  `:RenameCustomProfile(...)`.
- `EverGear:GetActiveProfile(classToken, specName)` -- resolves
  `charDB.profileId` to either the builtin or a custom profile, falling
  back to builtin default if the saved id no longer exists (deleted from
  another character, etc.).
- `EverGear:ClampWeight(value)` -- shared rounding/clamping helper (round to
  nearest 0.1, clamp to [0, 5]) used by both the UI input filter and
  JSON import validation, so both paths enforce the same rule.
- `EverGear:CopyProfile(fromClass, fromSpec, fromProfileId, toClass, toSpec, newName)`
  -- builds the new profile by starting from `toSpec`'s builtin defaults
  (covers every key the target actually uses) and overwriting with every
  key present in the source profile (see assumption 6's merge rule), then
  creates it as a new custom profile on the target class+spec. Works for
  same-spec, same-class/different-spec, and cross-class alike -- it's the
  same merge either way.
- Rewire `GetScoringProfile` (Upgrades.lua) and `ScoreItem`'s hardcoded
  `3.0` to go through this module instead of reading `SPEC_PROFILES`
  directly.
- Testable via `/run` commands in-game (print a resolved profile, create/
  delete via slash commands temporarily) -- no editor UI needed yet to
  verify this milestone.

### M2 -- JSON encode/decode + (de)serialization
- Small vendored pure-Lua JSON module (`Core/JSON.lua`, encode+decode only,
  no external dependency -- WoW addons can't `require` npm/luarocks
  packages). MIT-style single-file lib, credited in a header comment.
- `EverGear:SerializeProfile(profile)` -> JSON string (includes class, spec,
  profile name, and the weights table, so an imported file is self-
  describing rather than just a bare number blob).
- `EverGear:DeserializeProfile(jsonString)` -> `profile, errorMessage`.
  Validates shape (every value numeric, clamps via `ClampWeight`, rejects
  unknown non-numeric fields) rather than trusting the input blindly.
- Pure logic, unit-testable via `/run` prints, still no UI.

### M3 -- Profile selection in the main window
- Add a second dropdown next to the existing spec dropdown: "Profile",
  listing `Default` + the player's custom profiles for the currently
  selected class+spec.
- Picking one writes `charDB.profileId` and calls `RefreshUI()` -- scoring
  immediately reflects the new weights (M1 already rewired
  `GetScoringProfile`, so this is purely a selection UI, no scoring changes
  needed here).
- Switching the *spec* dropdown resets the profile dropdown back to
  `Default` for the new spec (a profile id from one spec is meaningless for
  another).

### M4 -- Profile editor window
New second window (own `CreateFrame`, same visual theme as the main
window), opened via a small button next to the new Profile dropdown:
- Profile list for the current class+spec with **New**, **Duplicate**,
  **Rename**, **Delete** (Delete disabled/greyed on `Default`), and
  **Copy to...** (opens a small class+spec picker -- defaults to every
  other spec of the current class, with a toggle/section to pick a
  different class entirely -- then runs `CopyProfile` and switches the
  editor to the newly created copy on that target spec).
- A scrollable grid of label + numeric EditBox pairs, one per weight field
  (grouped under headers: Core / Off-stats / Secondary stats), generated
  from the field list in M1 -- not hand-laid-out per stat.
- Each EditBox: `OnChar`/`OnTextChanged` filter allows only digits and a
  single `.`; keeps at most the first 2 digit characters typed (ignores
  further digits), matching the "each digit after the 2nd is ignored"
  spec; on commit (focus lost / Enter), run through `ClampWeight`.
- Editing the synthesized `Default` profile is read-only (fields disabled);
  a "Duplicate to edit" button is shown instead of the grid being editable.
- Save button persists edits to the active custom profile immediately
  (or could autosave per-field on commit -- picking explicit Save for a
  clearer "did this stick" moment, open to revisiting).

### M5 -- Export / Import UI
- **Export** button on the editor: popup with a read-only multi-line
  EditBox pre-filled with `SerializeProfile(...)` output and pre-selected,
  so Ctrl+C immediately grabs it. Player pastes into their own `.json` file
  outside the game.
- **Import** button: popup with an empty editable multi-line EditBox +
  Import button. Runs `DeserializeProfile`; on success, creates a new
  custom profile (prompts for a name if the JSON's own name collides with
  an existing one); on failure, shows the specific validation error inline
  rather than failing silently.

### M6 -- Polish, edge cases, ship
- Class-change safety: switching characters to a different class naturally
  scopes profiles/dropdown to that class+spec already (M1's lookup keys on
  `classToken`) -- verify no stale cross-class state leaks through.
- Confirm deleting the profile currently active on *other* characters
  falls back cleanly (M1's `GetActiveProfile` fallback) rather than
  erroring their UI open.
- `CHANGELOG.md` entry + `EverGear.VERSION` bump (patch, per the repo's
  versioning policy -- this is a real shipped feature so likely also the
  moment to discuss a `0.1.0` bump, but that's explicitly the user's call,
  not something to do unprompted).
- In-game smoke-test checklist (manual, since there's no WoW client in this
  environment to automate): create/duplicate/rename/delete a profile,
  switch between profiles and confirm badges update, export then
  re-import a profile, paste malformed JSON and confirm a clean error
  instead of a Lua error/taint.

## Out of scope (unless asked)

- Sharing profiles between players in-game (e.g. via addon comm channels)
  -- only file-based (copy/paste) import/export as specified.
- A "reset to default" that overwrites a *custom* profile's values back to
  the builtin's current numbers in place (Duplicate already covers getting
  a fresh starting point).

## Post-M4 revision: "Primary Stat" removed

Per user feedback after testing M4: the generic `primaryStatWeight` field
(described above in "What currently exists" and the original M1 design) made
the editor show an opaque "Primary Stat" row with no indication of which
real stat it actually weighted -- e.g. a Warrior couldn't tell this row
meant Strength.

Fixed by removing the concept entirely:
- Every `EverGear.SPEC_PROFILES[class][spec]` entry now has a `stats` table
  naming all 5 main stats explicitly (`{ STRENGTH = 3.0, AGILITY = 0.3,
  STAMINA = 1.5, INTELLECT = 0.05, SPIRIT = 0.1 }`, say, for a Warrior),
  replacing the old `primaryStatWeight` + `staminaWeight` + `offStat{}`
  trio. The actual numbers are unchanged -- this only renamed/reshaped where
  each one lives (the old hardcoded-3.0 primary weight is now attached to
  whichever real stat used to receive it).
- `Core/Upgrades.lua`'s `CLASS_ROLE_PRIMARY_STAT`/`GetPrimaryStat` are gone;
  `ScoreItem` just reads `profile.stats[statName]` directly.
- The editor's field grid (`EverGear:GetWeightFieldLayout`,
  Core/EQProfiles.lua) now has one "Core" section covering all 7 of
  Strength/Agility/Stamina/Intellect/Spirit/Armor/Weapon DPS together
  (previously split across a "Core" section of 4 opaque scalars and a
  separate "Off-Stats" section), per user feedback. JSON export/import's
  recognized keys changed to match (`stats`/`armorWeight`/`dpsWeight`
  instead of `primaryStatWeight`/`staminaWeight`/`armorWeight`/`dpsWeight`/
  `offStat`) -- an old exported profile JSON from before this change will no
  longer import (its `primaryStatWeight`/`staminaWeight`/`offStat` keys are
  no longer recognized and are silently ignored, same as any other unknown
  key), since there's no previously-shipped version of this feature anyone
  could have real exports from yet.

## Decision: changing spec while the editor is open

Question raised by user: what should happen if the player changes their
main Spec dropdown while the EQ Profile Editor window is open?

Decision: **nothing happens to the editor automatically** -- it keeps
showing whatever class+spec it was last pointed at (the character's spec at
the moment it was opened, or wherever "Copy to..." last sent it), fully
independent of the main window's Spec dropdown from that point on.

Why: the editor already supports browsing/editing a DIFFERENT class+spec
than the character's own active one on purpose (Copy to..., plan
assumption 6) -- that's the whole point of `editorClassToken`/
`editorSpecName` being separate state from `charDB.spec`. Auto-syncing the
editor to the live spec on every change would fight that: either it would
undo an intentional Copy-to navigation the player is still looking at, or
it would need some way to tell "live-following" and "manually navigated"
apart, which isn't worth the complexity for a window that's explicitly a
secondary, independent browser/editor rather than a mirror of the live
suggestions. It's also the safer default: workingWeights (any unsaved edit)
is never touched by a spec change, so nothing is silently discarded either
way.

The risk this creates -- not noticing the editor is now showing a
different spec than the live one -- is addressed instead by always
labeling which class+spec the editor is currently on: a subtitle under the
window's title ("Warrior - Fury", etc), added alongside this decision.
