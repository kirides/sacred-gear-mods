# Icon Set drops

The Icon Set is six items: the Dragon, Dark Elf, Royal and Seraphim statue, the Grail and the Shell. Every class can use it, and it is "worn" just by carrying all six in the backpack. Its set bonus is the **Flaming Feet** trail of fire.

This mod lets the pieces drop from creatures of any level. A small share of the equipment that creatures drop is turned into one of the six pieces instead.

## What you need

Sacred Gear and the mod. A single player game or a LAN game you host (the host's game rolls the loot).

## How it works

The six pieces are set items of level 1 (set 23 of `sets.bin`, object types 5101 to 5106). The game's own set drops are rare and share the odds with 65 other sets, so at higher levels the pieces are hardly ever seen. The mod needs no level change: whenever the game picks an equipment item for a creature's drop, the mod swaps it for a random Icon Set piece with the chance you set. With chance 0 it changes nothing.

Side effects of the set you should know: Flaming Feet raises the number of clones the Split modifier makes and the number of fireballs of the Fadalmar's Counsel set bonus, does a very small amount of fire damage and can cause lag in multiplayer games.

## Settings

Open the Mods screen with **F11** and pick the mod.

| Setting | What it does |
|---|---|
| Chance per equipment drop (%) | The share of random equipment drops that becomes an Icon Set piece (0 to 20, default 1). |
| Lowest creature level | Creatures below this level never drop a piece through the mod (default 1). |
| Extra chance per level (%) | Added to the chance for every level above the lowest level (0 to 1, default 0). |

Other mods can steer it: `gear.emit('icon-set.configure', {chance = 5})`.

## Self test

`src\icon-set_selftest`, in a copy of the game folder (the rolled items stay in the world):

```
Sacred.exe -gear-auto -gear-load=1 -gear-instance=iconset -gear-mods=icon-set,icon-set_selftest
```

## Development

- **Files:** `src/icon-set/mod.lua` (settings) and `main.lua` (about 30 lines). Self test: `src/icon-set_selftest`.
- **Depends on:** the `drops.select` event of `gear.drops` ([GearDrops](https://github.com/kirides/sacred-bild/blob/main/docs/GearDrops.md)), `gear.settings`.
- **Not covered:** the replaced picks come from creature loot only (not chests, shops or quest rewards), and the drops.select event does not run in the game's own set path.
