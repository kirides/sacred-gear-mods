# Screenshots

The images in `docs/images` are taken from the real game, with the current Sacred Gear build, by small automation
scripts (`tools/readme-shots`): no mock-ups, no drawn illustrations. They run in a **copy** of the game folder, never in
the one you play in (the runs write autosave slots, move items into the stash and empty the `mods` folder).

```powershell
tools\readme-shots\run.ps1 -Game "B:\Games\sacred-copy"                    # everything, then the crops
tools\readme-shots\run.ps1 -Game "B:\Games\sacred-copy" -Only fight,chat   # some steps only
tools\readme-shots\run.ps1 -Game "B:\Games\sacred-copy" -CropOnly          # only cut the images again
```

The copy needs `ddraw.dll` (SacredBild) and `SacredGear.dll` of the build you want shown, a window of 1600x900 and a
savegame (`-Save`, default slot 10) with a hero and a few hostile creatures near (the author's test savegame: a Wood Elf
of level 1 with a Dark Elf beside her, a chest, wolves). For every step `run.ps1` empties the copy's `mods` folder, puts the
step's mods in (from this repository's `src`, so the Mods screen lists only them), runs the game once with
`-gear-auto -gear-instance=shot-<step> -gear-load=<slot> -gear-mods=...` and leaves BMP files in
`GearAutomation\shot-<step>\`. Then `crop.py` (Python with Pillow) cuts every image out of its shot as
`tools/readme-shots/crops.json` says and writes JPEG files (PNG for `companions-portraits.png`).

**Cropping rule:** every picture of a window or panel is cut with about 10 to 30 pixels around it: not tight, not the
whole screen. Pictures of a scene (a fight, the layout editor) show the part that matters. After a change of a window's
look run the step and check the box in `crops.json` (the shots are 1600x900, the box is `[x0, y0, x1, y1]`).

## What takes which picture

| Step (`shot-<step>`) | Mods | Pictures |
|---|---|---|
| `companions` | companions, companions_selftest | `companions.jpg`, `companions-portraits.png` |
| `compare` | item-compare, item-compare_selftest, companions | `item-compare.jpg` |
| `artbars` | art-bars, art-bars_selftest, companions | `art-bars.jpg`, `art-bars-cooldown.jpg` |
| `cc` | custom-classes, custom-classes_selftest, companions | `custom-classes*.jpg` |
| `st` | sector-tools, sector-tools_selftest | `sector-tools.jpg` |
| `we`, `boss` | world-events, world-events_selftest / world-events_bosstest | `world-events.jpg`, `world-events-boss.jpg` |
| `chat` | enhanced-chat, enhanced-chat_selftest | `enhanced-chat.jpg` |
| `bsl` | better-saveload, better-saveload_selftest | `better-saveload.jpg` (the savegame window) |
| `bounty`, `beditor`, `quests` | bounty, bounty_selftest / quests_selftest (`phase = 'shots'` / `'editor'`) | `bounty.jpg`, `bounty-editor.jpg`, `quests.jpg` |
| `stash-ui` | shared-stash (`selftest = 'ui'`) | `shared-stash.jpg`, `shared-stash-tooltip.jpg` |
| `layout` | layout (its self test, edit mode) | `layout.jpg` |
| `ah` | auction-house (`selftest = 'sp'`), shots (`phase = 'gold'`: the hero gets gold) | `auction-house.jpg` (the market in a single player game) |
| `autosave`, `lf` | autosave / lootfilter, shots | `autosave.jpg`, `lootfilter.jpg` |
| `fight` | damagemeter, lootlog, sessiontracker, shots (`phase = 'fight'`) | `sessiontracker.jpg` |
| `twitch` | twitch_integration, twi_sacred, shots | `twi_sacred.jpg` |
| `srv-achievements`, `srv-buildsharer`, `srv-serverfeed`, `srv-questhelper` | the mod, shots (`phase = 'server'`) | `achievements.jpg`, `buildsharer.jpg`, `serverfeed.jpg`, `questhelper.jpg` |
| `dt`, `dtmore`, `keys`, `realms`, `spawn`, `region`, `twibase` | the mod, shots (`phase = 'modscreen'`) | `drop-tuning.jpg`, `drop-tuning-more.jpg`, `key-bindings.jpg`, `realms.jpg`, `spawn-rate.jpg`, `region-counter.jpg`, `twitch_integration.jpg` |

## Phases of `tools/readme-shots/main.lua`

Run a phase with `-gear-mods=<mod>,shots` after writing `mods\shots\config.lua` (`return {phase = '...'}`):
`autosave`, `lootfilter`, `layout`, `gold` (gives the hero `gold`; stays out of the way for a self test that needs it),
`modscreen` (the Mods screen: `clicks = {{x, y}, ...}` open a mod's page; `{x, y, wheel = n}` turns the mouse wheel there; `realm = {...}`
adds a realm first), `fight` (zombies spawned next to the hero, the hero attacks them: damage meter, loot log, session
tracker), `twitch` (a `TWI_Raid` for the Twitch actions) and `server`
(`which = 'achievements' | 'buildsharer' | 'questhelper' | 'serverfeed'`, `press = true` opens the panel, `wait` seconds before the shot).

The `server` pictures were taken **without a game server**: the script hands what the server's Lua script would send to the
mod's own net channel handlers, so the real mod draws it, but the numbers and names are examples. The bounty pictures are
the bounty mod's single player board (`bounty_selftest` with `phase = 'shots'`), the real panel and tracker, no server. The
auction house runs as a market of its own in a single player game.

## What these pictures do not show

* `lootlog.jpg` and `damagemeter.jpg` are real screenshots from a play session and are not retaken by the script: in its
  `fight` phase the loot log stayed empty and the damage meter read a DPS of 1 to 2 (the kills of the script's fights are not
  counted by the session tracker either), so the pictures would be worse than the ones from play. Their windows have not changed.
* The Quest helper's *Records* tab needs a network game with the server's quest script: the picture shows the *About* tab.
  The realm picker's page is drawn dimmed in the running game (the picture shows it as it is; the start menu has no screenshots).
