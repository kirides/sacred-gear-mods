# Autosave

A [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md) mod: saves a single player game every
few minutes of play, into slots of its own, so a crash costs minutes instead of an hour. It answers
[kirides/sacred-bild#10](https://github.com/kirides/sacred-bild/issues/10). It is separate from Sacred Gold's own
"Auto-Save" option (which saves at important points).

## Install

Copy this folder to `mods\autosave` in the game folder (next to `Sacred.exe`; Sacred Gear and SacredBild installed).
It saves with the game's own save request, `gear.game.save`, which needs a Sacred Gear that has it.

## What it does

- **Active play time only.** The timer runs while the hero plays: the game is shown and no window (inventory, map,
  trade ...), escape menu, message box or help screen is open. It stops in the main menu, loading screens, cinematics
  and menus (Sacred Gear runs mods only in game frames). A single frame counts at most one second.
- **Waits for a valid moment.** When the interval is up, the save starts at the first moment the game can save:
  single player, a living hero, the game itself shown, no window drawn alone, no cinematic, no save or load pending, and
  none of the trade / chest / blacksmith windows that make the engine refuse. Until then it asks again every
  2 seconds (not every frame).
- **Own slots, rotating, oldest first.** Default: `Save\GAME97.PAK`, `GAME98.PAK`, `GAME99.PAK`. A slot that does not
  exist yet is used first, then the oldest file by modification time, so the two earlier autosaves survive. The
  quicksave (`GAME00.PAK`, F9) and the manual saves (the game's savegame window numbers them from `GAME01`) are never
  written.
- **Confirmation and failures.** After a successful save a note ("Autosaved (slot 97)") shows for four seconds
  below the top of the screen. A refused or failed save is written to `SacredGear.log` (`[autosave] ...`) and retried
  after 10, 30, 60, then every 120 seconds; the timer keeps counting meanwhile, so the next autosave happens as soon as
  it can.

## Settings

Sacred Gear's mod manager keeps them: press **F11** (or **Mods** under the escape menu), pick Autosave and change
them on its **Settings** page; they are saved at once in `mods\gear_mods.json`. `mod.lua` holds the defaults.

| Setting | Default | |
|---|---|---|
| `enabled` | `true` | Autosave on / off. |
| `interval_minutes` | `5` | Minutes of active play between autosaves (slider, whole minutes 1 to 60; `autosave.configure` takes 0.05 to 240). |
| `slots` | `97, 98, 99` | The slots to rotate through (text: numbers 1 to 32766 separated by commas, up to 8). Keep them clear of the numbers the game gives to manual saves. |
| `name` | `Autosave %H:%M` | The display name in the savegame list; `os.date` format, 60 characters at most. |
| `show_confirmation` | `true` | The note after each autosave. |
| key `save_now` | `f6` | Autosave right away, into the next slot. Rebind it on the Keys page (F5 is the loot filter, F11 the Mods screen; the layout edit mode is on Alt). |

The **More** tab of the mod's page shows the time to the next autosave, why one waits and the last slot written, and has
a **Save now** button.

## Together with the game's own Auto-Save

Sacred Gold has an **Auto-Save** option (`AUTOSAVE : 1` in `Settings.cfg`, the options window). It is a different thing:
it saves only when a quest or map script reaches an autosave point, into the *first free* `GAMEnn` slot (a new file each
time, never overwritten), and it does not look whether a window is open. The two do not collide: this mod's slots are
97 to 99, and the engine handles one save at a time (a request that comes while a save runs is dropped; this mod
waits and tries again). A save of the game's (or the quicksave, or a manual one) counts: the timer starts over. The
More tab of the mod shows a note while the game's Auto-Save is on. Both can run together; turn the game's off if you do
not want its extra savegames to pile up.

## Recovery: loading an autosave

The autosaves appear in the game's savegame list under their slot (`GAME97` ... `GAME99`) with the name
"Autosave HH:MM". They are normal savegames: load the newest one (check the time in its name, or the file dates).
If the newest is damaged (the game crashed while writing it), take the one before: the previous autosave is still in
the next slot. To keep an autosave for good, copy `Save\GAME97.PAK` to a free number (`GAME06.PAK` ...) or rename it.

## For other mods

```lua
gear.emit('autosave.configure', {enabled = true, interval_minutes = 10, slots = {95, 96}, persist = false})
local out = {}
gear.emit('autosave.query', out)   -- enabled, interval_minutes, slots, active_seconds, due, requested, fails, saves, last_slot, ...
```

`gear.game.can_save()`, `gear.game.save(slot, name)`, `gear.game.save_info(slot)` and the events `game.saved` /
`game.save_failed` are Sacred Gear's ([GearApi.md](https://github.com/kirides/sacred-bild/blob/main/docs/GearApi.md)).

## Test

`mods\autosave_selftest` (a sibling folder in this repository) is the automation self test:

```
Sacred.exe -gear-auto -gear-instance=autosave -gear-load=1 -gear-mods=autosave,autosave_selftest
```

It checks that the timer stops in the escape menu, that four autosaves rotate through 97, 98, 99, 97, and that the
quicksave and the loaded savegame stay untouched. Results: `GearAutomation\autosave\autosave.json`. Back up `Save\`
first; the test writes slots 97 to 99.
