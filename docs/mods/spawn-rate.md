# Spawn rate

Makes the world busier: every creature the game spawns brings extra ones of its kind, from **1x** (the game as it is) up to **100x**.

## What you need

Sacred Gear with the `creature.created` event (SacredBild from the build that added it) and the mod in your `mods` folder (see [Install](../Install.md)). Single player only: in a network game the mod does nothing.

## How to use it

Open the Mods screen (**F11**), pick *Spawn rate* and set the rate with the slider. It takes effect at once, for creatures the game spawns from then on (sectors that fill when you arrive, scripted waves, respawns). Creatures that are already there stay as they are.

At 10x, nine more creatures appear around each creature the game spawns. Only creatures hostile to your hero are multiplied: merchants, villagers, companions and the like are not. The extra creatures are not multiplied again.

Fighting 100 times as many creatures costs frame rate. The safeguards keep the game playable:

| Setting | What it does |
|---|---|
| Spawn rate (x) | 1 to 100. 1 is the game as it is. |
| Most extra creatures at once | The extras alive at the same time never exceed this (default 200, 0 = no limit). Extras that die or vanish make room for new ones. |
| Extra creatures per frame | How many extras are made in one frame at most (default 4). The rest waits in a queue, so entering a crowded sector does not freeze the game. When the frame rate drops below 30 fps the mod makes only one per frame, below 15 fps none. |

The *More* page shows how the mod works in the game's language (English or German) and counters: extras alive, waiting, made, and not made.

Notes:

- The extras are plain creatures of the same type placed around the original. A creature whose level the game sets after creating it (scaled to your hero) may have its type's own level as an extra.
- Quest creatures and bosses that the game spawns are creatures like the others and are multiplied too. Use a lower rate while you hunt for a unique one, or switch the mod off in the Mods screen.
- Experience and drops of the extras are the game's own; combine with [Drop tuning](../DropTuning.md) to taste.

## Development

- **Files:** `src/spawn-rate/mod.lua` (manifest, settings), `core.lua` (the logic without the game: how many extras, the per-frame allowance, the bounded queue, the placement ring) and `main.lua` (the event, the frame loop, the More page).
- **Depends on:** the Gear API: the `creature.created` event (Sacred Gear hooks the engine's object create, `cObjectManager::create` 0x005FBA40; creations by Gear itself, by a savegame or network read and heroes send no event), `gear.world.spawn`, `gear.settings`, `gear.ui.table`.
- **Test it:** `luajit tests/spawn_rate_test.lua` runs the logic outside the game.
