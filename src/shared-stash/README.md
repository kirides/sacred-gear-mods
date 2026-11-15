# Shared stash

A stash that all heroes of one player share (issue [kirides/sacred-bild#9](https://github.com/kirides/sacred-bild/issues/9)).
A mod for [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md), written in Lua on `gear.inv`.

## Use

Copy this folder to `mods\shared-stash` in the game folder (Sacred Gear and the `mods` folder as described in its
docs). In game, open the chest: a **Shared stash** button appears below the chest window (or press **F10** anywhere
in game). The panel:

- **In the stash** (top): click an item to take it into the backpack (into the chest if the backpack has no room).
- **Your items** (bottom): the items of the backpack and the chest; click one to put it into the stash.
- **Recent withdrawals**: the items taken out lately; click one to put its entry back into the stash (see below).

Items are shown by their type's file name, size and quality colour; the tooltip adds the class and which hero put it in.
The panel is a list, not the chest's picture grid: Sacred Gear cannot draw the game's item graphics yet.

Single player only (the panel says so otherwise). Gold and quest items never move; "special" items (horse gear ...)
only with the *Also move special items* setting. The stash holds up to 200 items. These settings and the key (F10) are in
Sacred Gear's **Mods** screen (F11), saved in `mods\gear_mods.json`; `config.lua` still sets their defaults.

## The file

`stash.json` in the mod's folder (`stash.bak.json` is the version before the last write). **Do not delete it when you
update the mod**: it is your stash. Format: `{"version": 1, "items": [...], "recent": [...]}`; every item is the
game's own data for it as hex (type, random properties, record), so it comes out exactly as it went in, plus a name,
quality and category for the list. A newer file version or a file that cannot be read (and has no readable backup)
switches the stash off with a message instead of overwriting anything.

Without the mod nothing changes in the game: the savegames are never touched (the mod only moves items in memory, the
game's own save stores the character).

## When the stash and a savegame disagree

The stash file lives outside any savegame's timeline, so the order of the steps and a recovery list decide what
happens, not luck:

- **Deposit**: the stash file is written first, then the item leaves the character. A crash in between, or a game
  that is quit without saving after a deposit, leaves the item in **both** places (never in neither); the character's
  copy comes back with the savegame you load, the stash entry stays.
- **Withdraw**: the item enters the character first, then the file is written. If the write fails the item is taken
  out again.
- **Loading an older savegame after a deposit**: that save still has the item, the stash has it too: a duplicate.
  Take it out of the stash or out of the character, whichever you do not want.
- **Loading an older savegame after a withdrawal**: that save does not have the item and the stash gave it up. It is
  not lost: **Recent withdrawals** (the last 30) lists it, click to put it back into the stash.
- The same item cannot be taken out of the stash twice: an entry leaves the file when it is withdrawn.

Save the game after moving items so that the character and the stash agree. The mod does not save for you.

## Self test

`-gear-auto -gear-instance=NAME -gear-load=N -gear-mods=shared-stash` with `config.lua` containing
`return {selftest = 'deposit', selftest_slot = 1}`: loads savegame N, runs the step, writes
`GearAutomation\NAME\sharedstash.json` and quits. `deposit` moves a weapon, an armour piece, a jewel and a shield from
the backpack into the stash; `withdraw` (another savegame, a new game process) takes everything out again and checks
each item is byte-identical to what went in; `ui` takes a screenshot of the panel.

## Files

| | |
|---|---|
| `mod.lua`, `main.lua` | manifest and defaults; the panel |
| `stash.lua` | the file: load, backup, atomic writes, recent withdrawals |
| `transfer.lua` | deposit and withdraw in the order described above |
| `selftest.lua` | the self test |
