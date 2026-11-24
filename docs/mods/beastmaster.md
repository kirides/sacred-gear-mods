# Beastmaster

Animals that travel with your hero, in two roles. One mod, because both share the same spawning, following, savegame storage and window.

- **Allies** (wolves, bears, boars): follow you in a half circle behind, attack the enemy nearest to you, and grow stronger with your level (*Ally strength* scales it).
- **Pets** (rabbits, hares, crows, parrots, fawns): follow you around, are drawn larger (130% by default), cannot be clicked or targeted (not by the mouse, the hover cursor or the controller's aim) and take no damage. They do nothing else.

## What you need

Sacred Gear with `creature:set_pet`, `creature:order_move` on any creature and `gear.world.spawn` with `like`, and SacredBild with the pets module (draw scale, pick filter). For allies that really bite, also `creature:copy_stats` (a plain `gear.world.spawn` creature is level 1 and deals no damage). Single player only.

## How to use it

Press **Ctrl+B** (or open the controller's mod menu) for the Beastmaster window: pick an animal to take it along, *Dismiss* sends one away. The animals belong to the savegame. The Mods screen (**F11**) has the limits (allies and pets at most), ally strength, pet size, follow distance and how far allies fight from you.

The window uses the shared theme; every button is a stop for the controller (A presses).

## Species

The game has no fox or dove creature types (the creature list has wolves, bears, boars, rabbits, hares, crows, parrots, divers, fawns and deer, cows ...), so the list is those. `species.lua` is the list: a creature type id, a role and a label.

## Notes for tinkerers

- Pets are `creature:set_pet{scale, untargetable}` plus `set_modifiers{taken = 0}`. SacredBild scales the model about the object's render position (object +0x7C / +0x80) with a matrix applied before the draw, so the shadow grows with it.
- Allies are spawned with `like = hero` (the hero's faction, so enemies fight them) and ordered with `order_attack` / `order_move` every few tenths of a second.
- Self test: `src/beastmaster_selftest` (run it in a copy of the game folder).
