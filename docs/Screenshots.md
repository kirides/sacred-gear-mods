# Screenshots

The images in `docs/images` are taken from the real game, with the current Sacred Gear build, by small automation
scripts (`tools/readme-shots`): no mock-ups, nothing reused. They run in a **copy** of the game folder, never in the one
you play in (the runs write autosave slots and move items into the stash).

```powershell
tools\readme-shots\run.ps1 -Game "B:\Games\sacred-copy"
```

The copy needs `ddraw.dll` (SacredBild) and `SacredGear.dll` of the build you want shown, and a savegame in slot 1 with
a hero. `run.ps1` puts the mods in (this repository's, and the loot filter and layout editor from
`..\sacred-bild\gear\examples`), runs the game with `-gear-auto -gear-instance=shot-<name> -gear-load=1` once per set of
pictures and leaves BMP files in `GearAutomation\shot-<name>\`. Convert them to JPEG (the game window is 1600x900).

| Run | Result |
|---|---|
| `shot-mods` | `mod-manager.bmp`: F11 (a copy of the autosave mod drives it, so no helper mod is listed) |
| `shot-loot` | `loot-overlay.bmp`, `loot-settings.bmp`: items spawned at the hero's feet, Alt, then F5 |
| `shot-layout` | `layout-2-selected.bmp`: Alt, *Edit layout*, the inventory selected |
| `shot-autosave` | `autosave-note.bmp`: a 3-second interval, a shot when the note shows |
| `shot-stash-deposit`, `shot-stash-ui` | `chest-stash.bmp`, `stash-tip-stash.bmp`: the stash self tests (`deposit`, `ui`); the README crops the right half (the chest window is only shown, not filled) |

The loot filter and layout editor copies are made plain mods (`automation = false`), so they do not run their own self
tests in the same game.
