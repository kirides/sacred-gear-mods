# Shared stash

A stash that all heroes of one player share (issue [kirides/sacred-bild#9](https://github.com/kirides/sacred-bild/issues/9)).
A mod for [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md), written in Lua on `gear.inv`.

## Use

Copy this folder to `mods\shared-stash` in the game folder (Sacred Gear and the `mods` folder as described in its
docs). In game, open the chest: a **Shared stash** button appears below the chest window (or press **F10** (rebindable in the Mods screen) anywhere
in game). The button is a small panel of its own: move it in Sacred Gear's layout editor (F7); its place is kept in
`mods/gear_layout.json`. The panel:

- **In the stash** (top): a grid of the stashed items' 3D icons, each as many 32-unit cells as in the game's inventory
  (11 x 6 cells a page, pages with < >). Click an item to take it into the backpack (into the chest if the backpack has
  no room).
- **Your items** (bottom): the items of the backpack and the chest, packed into the same kind of grid (not at their real
  places); click one to put it into the stash. Items that cannot move (quest items, gold) are greyed out.

Resting the cursor on an icon shows the game's own item tooltip (the display name in its rarity colour, price,
protection or damage, level, bonus lines and socket count, in the game's framed popup), placed beside the panel so it
never covers the cursor. Icons and tooltips come from `gear.ui.item_icon` and `gear.ui.item_tooltip`: items in the
backpack are read from the live object, stashed ones through a temporary item made for the hovered cell (at most 48
different item types a frame are drawn as icons; a grid page is at most 66 cells).

Single player only (the panel says so otherwise). Gold and quest items never move; "special" items (horse gear ...)
only with the *Also move special items* setting. The stash holds up to 200 items. These settings and the key (F10) are in
Sacred Gear's **Mods** screen (F11), saved in `mods\gear_mods.json`; `config.lua` still sets their defaults.

## The file

`stash.json` in the mod's folder (`stash.bak.json` is the version before the last write). **Do not delete it when you
update the mod**: it is your stash. Format: `{"version": 1, "items": [...]}`; every item is the
game's own data for it as hex (type, random properties, record), so it comes out exactly as it went in, plus a name,
quality and category for the list. A newer file version or a file that cannot be read (and has no readable backup)
switches the stash off with a message instead of overwriting anything.

Without the mod nothing changes in the game: the savegames are never touched (the mod only moves items in memory, the
game's own save stores the character).

## When the stash and a savegame disagree

The stash file lives outside any savegame's timeline, and the mod cannot see the game's saves, so it can only choose
the order of its steps. Nothing is ever restored into the stash: an item that left the stash is gone from the file
(there is no "undo" or "recent withdrawals" list, because any way to put a withdrawn item back could be used to
duplicate it).

- **Withdraw**: the item enters the character first, then it leaves the file. If the write fails the item is taken out
  of the character again. The same entry cannot be withdrawn twice.
- **Deposit**: the file is written first, then the item leaves the character. A crash in between leaves the item in
  both places.
- **Loading an older savegame after a withdrawal**: that save does not have the item and the stash gave it up, so it
  is gone. Save after moving items.
- **Loading an older savegame after a deposit** (or quitting without saving after one): that save still has the item
  and the stash has it too. That is a duplicate, and the mod cannot prevent it, because the stash has no way to know
  which savegame is loaded. Play it as a rule: deposit, then save, and do not reload an older save to get the item
  back.

## Self test

`-gear-auto -gear-instance=NAME -gear-load=N -gear-mods=shared-stash` with `config.lua` containing
`return {selftest = 'deposit', selftest_slot = 1}`: loads savegame N, runs the step, writes
`GearAutomation\NAME\sharedstash.json` and quits. `deposit` moves a weapon, an armour piece, a jewel and a shield from
the backpack into the stash; `withdraw` (another savegame, a new game process) takes everything out again and checks
each item is byte-identical to what went in; `sockets` fills the free sockets of backpack items with the backpack's runes (the engine's own socketing) and deposits them, `filled` deposits items that already hold a rune; `ui` takes screenshots of the panel and of the tooltips of the first stash and backpack cells.

## Files

| | |
|---|---|
| `mod.lua`, `main.lua` | manifest and defaults; the panel |
| `stash.lua` | the file: load, backup, atomic writes |
| `transfer.lua` | deposit and withdraw in the order described above |
| `selftest.lua` | the self test |
