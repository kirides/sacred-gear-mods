# Beastmaster

Animals that travel with your hero, in two roles. One mod, because both share the same spawning, following, savegame storage and window. Every animal of the game is on the list (122 species: wolves, bears, boars, deer, horses, cows, pigs, sheep, chickens, birds, bats, snakes, spiders, scorpions, crabs, lizards, insects, worms ...).

- **Allies** follow you in a half circle behind, attack the enemy nearest to you, and have the **level of the hero you play** (the engine derives their health and damage from their type and level, as for the creatures it places, so they grow with you; *Ally level* scales it, *Ally damage* multiplies their bites). They are drawn at the species' base size times a growth factor that **steps up every 18 levels until level 216** (75% at level 1 to 125% at level 216 by default: 12 steps of about 4%).
- **Pets** follow you around, are drawn larger (130% of the base size by default), cannot be clicked or targeted (not by the mouse, the hover cursor or the controller's aim) and take no damage. They do nothing else.

## What you need

Sacred Gear with `creature:set_level`, `creature:set_pet`, `creature:copy_allegiance` and `creature:order_move` on any creature, and SacredBild with the pets module (draw scale of the model and its shadow, pick filter). Single player only.

## How to use it

Press **Ctrl+B** (or open the controller's mod menu) for the Beastmaster window. Choose *Ally* or *Pet*, type in the **filter row** (a forgiving search over the names: words in any order, a beginning is enough, one typo is forgiven; the keyboard button opens an on-screen keyboard for the controller), then pick an animal from the list to take it along; *Dismiss* sends one away. Next to each species the **base size** is changed with - and + (5% a step, kept for all games): big monsters such as spiders, scorpions and crabs start much smaller than their wild kind, so they fit beside a hero. The animals belong to the savegame. The Mods screen (**F11**) has the limits (allies and pets at most), ally strength, pet size, follow distance and how far allies fight from you.

The window uses the shared theme; every button is a stop for the controller (A presses).

## Species

The game has no fox or dove creature types. `species.lua` is the list: a creature type id, the model family (WOLF.GRN covers Silberwolf, Grauwolf, Panzerwolf ...) and the default base scale (spiders 0.3 to 0.7, scorpion 0.5, crabs 0.4 to 0.5, lizards 0.6 and so on; a wolf 1.0). The names come from the game, in your language. The default sizes are set by eye: adjust them in the window.

## Notes for tinkerers

- Pets are `creature:set_pet{scale, untargetable}` plus `set_modifiers{taken = 0}`. SacredBild scales the model about the object's render position (object +0x7C / +0x80) with a matrix applied before the draw, so the shadow grows with it.
- Allies are spawned plain, join the hero's side with `copy_allegiance` (enemies fight them), get `set_level(hero level * Ally level %)` and are ordered with `order_attack` / `order_move` every few tenths of a second. Measured: a level 1 wolf bites for about 8.5 with 65 health, a level 50 one for about 84 with 1990 health, so the damage grows steeply with the level.
- Growth: `core.stage(level)` is one step per 18 levels up to 12 at level 216; `core.growth` runs linearly from *Ally size at level 1* to *at level 216*.
- Self test: `src/beastmaster_selftest` (run it in a copy of the game folder).
