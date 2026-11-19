# Drop tuning

![The Drop tuning page of the Mods screen](images/drop-tuning.jpg)

Makes creature drops more or less frequent, tilts the rarity of what they drop and, if you like, swaps the game's random numbers for a fair
generator. Switched on, with every setting at its default, it changes nothing. It is built on `gear.drops` of Sacred Gear (what the engine does and what
each setting touches: [Gear drops](https://github.com/kirides/sacred-bild/blob/main/docs/GearDrops.md)).

Install it like the other mods (copy `src\drop-tuning` to the game's `mods` folder, **F11**, switch it on). It binds no keys; its settings are on its page
of the Mods screen (mouse or controller), and the **More** tab shows the game's rarity table next to the weights now in force.

| Setting | Meaning |
|---|---|
| Drop chance | A multiplier of the chance of every random drop attempt of creatures (2 = twice as many drops, 0 = none). Items a creature is set to drop (quest items, authored lists) are not touched. |
| Effect of magic find | How strongly the rarity bonus (magic find and the creature's own bonus) widens the odds of rarer equipment. |
| Set and unique drops | The two rows of the rarity table that hand the roll to the set / unique selection. |
| Qualities 1 to 4 / 5 to 9 / 10 to 14 | Multipliers of the weights of those equipment qualities (14 is the best). Setting the top group to 0 removes the best items; plain items are what is left over. The weights are read as a running sum against a roll of 1 to 10000, so large multipliers push the commoner qualities out of reach (see the Gear drops page). |
| Icon Set weight | The six pieces of the Icon Set (Dragon, Dark Elf, Royal and Seraphim statue, Grail, Shell; the Flaming Feet set bonus) are level 1 set items; the game's set drops are rare and shared with about 65 other sets, so they are hardly ever seen at higher levels (roughly 0.01% of equipment drops or less). This is the number out of 10000 random equipment drops of a creature that become one of them instead (10 = 0.1%, one in a thousand; 0 = off). The **More** tab shows the percentage and "one in N" at your hero's level. Also *lowest creature level* and *extra weight per level*. Creature loot only, not chests, shops or quest rewards. Flaming Feet makes Split clone more and Fadalmar's Counsel cast more fireballs, does little damage and can cause lag in multiplayer. |
| Random numbers | The game's own; a fair generator (no modulo bias: the game's rarity roll favours the first part of its range, which makes every rarer drop about 22% more likely than the table says); or the fair generator with a seed, which repeats the same numbers every run. |

Other mods can steer it: `gear.emit('drop-tuning.configure', {chance = 2, high = 0, rng = 'fair', icon_weight = 10})` sets those settings.

## Self test

`src\drop-tuning_selftest` is an automation run of the mod in a copy of the game folder (the loot rolls leave items in the world):

```
Sacred.exe -gear-auto -gear-load=1 -gear-instance=droptuning -gear-mods=drop-tuning,drop-tuning_selftest
```

It checks that the defaults leave the rarity table and the generator alone, that the settings change the table, the drop rate (twice the chance: 160 against 85
equipment drops in 400 rolls in the last run) and the generator, and that the defaults bring everything back (9 checks).

## Development

- **Files:** `src/drop-tuning/mod.lua` (settings) and `main.lua` (about 100 lines). Self test: `src/drop-tuning_selftest`.
- **Depends on:** `gear.drops` (hooks into the game's loot functions: drop chance, rarity weights, the random numbers), `gear.mods.page`, `gear.settings`, `gear.ui`. Settings that are at "as the game has it" leave the game untouched.
- **API reference:** [GearDrops](https://github.com/kirides/sacred-bild/blob/main/docs/GearDrops.md), [GearApi](https://github.com/kirides/sacred-bild/blob/main/docs/GearApi.md).
