# Install

## What you need

- Sacred Gold (GOG or Steam, English or German) with **SacredBild** and **Sacred Gear** installed: extract a
  [release](https://github.com/kirides/sacred-bild/releases) of sacred-bild into the game folder. `SacredGear.dll` next to
  the game is loaded by SacredBild and runs the mods. It also works without SacredBild
  ([Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md)).
- This repository (a zip of it from GitHub's *Code* button, or a `git clone`).

## Copy the mods

A mod is a folder in the game's `mods` folder (next to `Sacred.exe`; create `mods` if it is missing).

| Copy | To | |
|---|---|---|
| `src\autosave` | `mods\autosave` | [Autosave](Autosave.md) |
| `src\shared-stash` | `mods\shared-stash` | [Shared stash](SharedStash.md) |

Do not copy `autosave_selftest`: it is a test that overwrites the autosave slots. (`shared-stash` contains a self test
too, but it only runs when the game starts with `-gear-auto`.)

The loot filter, the layout editor and the realm picker are in the sacred-bild repository
(`gear\examples\lootfilter`, `layout`, `realms`); install them the same way.

## The Mods screen

Press **F11** (or *Mods* under the escape menu, or **LT + LB** on a pad). Every mod is listed:

- **On / Off** switches it, live, without restarting.
- **Settings** and **Keys** change its settings and key binds (a warning shows when two mods want the same key).
  Choices are saved in `mods\gear_mods.json`.
- A mod's own **More** page shows its state (the autosave's time to the next save, for example).

The default keys: **F6** autosave now, **F5** loot filter settings, **F11** the Mods screen. The shared stash has no
hotkey; it opens from the chest window.

## Updating and removing

- Update: replace the mod's folder with the new one. **Keep `mods\shared-stash\stash.json`**: that file is your stash.
- Remove: delete the mod's folder. These mods never change savegames, so removing one breaks no save (items that are
  still in the shared stash stay in `stash.json`).
