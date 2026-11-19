# Screenshots

The images in `docs/images` are taken from the real game, with the current Sacred Gear build, by small automation
scripts (`tools/readme-shots`): no mock-ups, nothing reused. They run in a **copy** of the game folder, never in the one
you play in (the runs write autosave slots and move items into the stash).

```powershell
tools\readme-shots\run.ps1 -Game "B:\Games\sacred-copy"
```

The copy needs `ddraw.dll` (SacredBild) and `SacredGear.dll` of the build you want shown, and a savegame in slot 1 with
a hero. `run.ps1` puts the mods in (this repository's), runs the game with `-gear-auto -gear-instance=shot-<name> -gear-load=1` once per set of
pictures and leaves BMP files in `GearAutomation\shot-<name>\`. Convert them to JPEG (the game window is 1600x900).

| Run | Result |
|---|---|
| `shot-autosave` | `autosave-note.bmp`: a 3-second interval, a shot when the note shows |
| `shot-stash-deposit`, `shot-stash-ui` | `chest-stash.bmp`, `stash-tip-stash.bmp`: the stash self tests (`deposit`, `ui`); the README crops the right half (the chest window is only shown, not filled) |

## More pictures (`tools/readme-shots`, phases of `main.lua`)

Run a phase with `-gear-mods=<mod>,shots` after writing `mods\shots\config.lua` (`return {phase = '...'}`):
`lootfilter`, `modscreen` (Mods screen, `clicks = {{x, y}, ...}` open a mod's page; `{x, y, wheel = n}` turns the mouse wheel there), `fight` (zombies/spiders spawned next to
the hero: damage meter, session tracker), `twitch` (a `TWI_Raid` for the Twitch actions) and `server`
(`which = 'achievements' | 'bounty' | 'buildsharer' | 'questhelper' | 'serverfeed'`). The bounty picture does not come from this phase any more: it is the bounty mod's single player board
(`bounty_selftest` with `return {phase = 'shots'}`), the real panel and tracker, no server.

The `server` pictures were taken **without a game server**: the script hands what the server's Lua script would send to the
mod's own net channel handlers, so the real mod draws it, but the numbers and names are examples. Pictures that are still
drawn illustrations (`docs/images/*.svg`, made by `tools/illustrations/make.py`): loot log, quest helper, realm picker,
auction house and the Twitch base mod.
