# Shared stash

A stash that all heroes of one player share (issue [kirides/sacred-bild#9](https://github.com/kirides/sacred-bild/issues/9)).
A mod for [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md), written in Lua on `gear.inv`.

## Use

Copy this folder to `mods\shared-stash` in the game folder (Sacred Gear and the `mods` folder as described in its
docs). In game, use a chest (the personal chest window opens only near a chest): a **Shared stash** button
appears, by default to the right of the chest and the inventory (below the stash panel); click it to open the stash.
**The stash is only available while the chest window is open**: the button exists only then, the panel closes the
moment the chest window closes (walking away, Esc, the menus, a dead hero), and a deposit or withdrawal is refused
unless the chest window is open right then. There is no hotkey. The button is a small panel of its own: move it in
Sacred Gear's layout editor (hold Alt, *Edit layout*; it is shown greyed out there so it can be placed without a chest); its place is kept
in `mods/gear_layout.json`. The panel:

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

It works in single player and in LAN games (in a network game the stash's changes go through `gear.inv`'s announcing calls). Gold and quest items never move; "special" items (horse gear ...)
only with the *Also move special items* setting. The stash holds up to 200 items. These settings are in
Sacred Gear's **Mods** screen (F11), saved in `mods\gear_mods.json`; `config.lua` still sets their defaults.

## Where the stash lives: by kind of game

`gear.mp.mode()` decides. **Single player, LAN and Open Net** use the local `stash.json` (below). **Closed Net** (the server checks
lobby identities) never touches it: the stash is the server's, kept per lobby account by the GameServer's `shared_stash.lua`
script over the Gear net channel `shared-stash`, shared by all heroes of the account. A deposit counts only after the server
saw the item leave your hero and the lobby stored the hero without it; a withdrawal only after it saw the new item in your hero
and the lobby stored the hero with it, so a killed client or a restored save cannot duplicate an item. If the server does not
offer the channel (a stock `GameServer.exe`, a server without the script or without `--authoritative`) the panel says "The shared
stash is not available on this server": the local stash is **not** used as a fallback, and `stash.json` is neither read, written
nor shown in Closed Net. Items you leave behind in `stash.json` from earlier games stay there for the other modes.

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
each item is byte-identical to what went in; `sockets` fills the free sockets of backpack items with the backpack's runes (the engine's own socketing) and deposits them, `filled` deposits items that already hold a rune; `ui` takes screenshots of the panel and of the tooltips of the first stash and backpack cells; `gating` (the kind of game: in a simulated Closed Net nothing reads or writes `stash.json`, local deposits and withdrawals are refused, the remote path says "not available" without a server; LAN, Open Net and single player keep the file) and `remote` (the Closed Net client against a fake server in Lua: refused deposit gives the item back, accepted deposit, withdrawal with confirmation) are the tests of that; `chest` checks that the stash exists only while the chest window is open (the window is shown and hidden with `gear.auto.show_window`, the button clicked, F10 pressed, a deposit and a withdrawal tried with the chest closed).

## Files

| | |
|---|---|
| `mod.lua`, `main.lua` | manifest and defaults; the panel |
| `stash.lua` | the file: load, backup, atomic writes |
| `transfer.lua` | deposit and withdraw in the order described above |
| `remote.lua` | the Closed Net stash: requests to the server's `shared_stash.lua`, resent until answered |
| `selftest.lua` | the self test |
