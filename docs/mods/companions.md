# Companions

![Companions](../images/companions.jpg)

A party of heroes in single player, the way Dragon Age does it. Recruit companions of any class: each is a real hero
with its own backpack, equipment, attributes, skills, combat arts, spells and experience, and it is saved with your
savegame. Play any of them: click its portrait under the game's own (top right), press **PageDown**, or use the controller's
mod menu. The heroes you do not play follow you and fight on their own, with their weapons, combat arts, spells and
combos.

## What you need

Sacred Gear (with `gear.party`) and the mod. Single player only: in a network game the mod does nothing (there the
hero slots belong to the players).

## How to use it

1. Press **Home** (or *Party window* in the controller's mod menu, **LT + LB**) and pick a class next to *Recruit*.
   The new hero joins where you stand, with the experience of the hero you play (setting), so it has skill points to
   spend: switch to it and spend them like for your own hero. It comes without items: give it equipment from your
   stash or what you find.
2. Play another hero: click its portrait, press **PageDown** / **PageUp**, use *Play* in the party window, or the mod menu.
   The camera, the HUD, the inventory, skills and combat arts windows, the mouse, the keys and the controller then serve
   that hero. The gold goes with you (the party shares one purse) and mercenaries follow the hero you play.
3. **Heroes from other savegames:** in the party window, *Keep <name> for other savegames* writes the hero you play
   to a hero file (in `mods\companions\heroes`). In another savegame, pick it under *Bring* and press *Bring*: a copy
   of that hero joins with its level, attributes, skills, combat arts, combos, equipment and backpack. Your network
   characters (`Save\HeroNN.pax`) are listed there too. The hero in the other savegame stays as it is.
4. In the party window each hero has a **behaviour** for the time you play someone else (*Aggressive*: fights what
   comes near; *Defensive*: protects the hero you play; *Passive*: only follows), a **name**, and **tactics**: the combat
   arts, spells and combos it may use on its own. *Dismiss* sends a companion away for good (empty its backpack first:
   what it wears is lost).

**The game's own mercenaries** follow the hero you play. Under *Mercenaries* in the party window you choose what they
do: *As the game does* (default, nothing changes), *Assist* (they attack the enemy the party fights when they stand
idle) or *Passive* (they stay with you). Their own combat AI, their quests and escort scripts stay the game's; the mod
never teleports them or changes what they are.

What the companions do on their own: they keep up with you (a companion left far behind or on another level joins
you), pick the enemy nearest to you, attack it with their weapon, and use their abilities like a player would: combos
and attack arts and spells on the target as soon as they have regenerated, auras and buffs (Steinhaut, Ehrfurcht ...)
once a fight starts, healing spells when someone in the party is below half health. Shape changes (Vampirform,
Ritterform ...), teleports and other tricks are left to you.

Experience: what one party hero earns from kills and quests also goes to the others nearby (setting). If the hero you
play falls, you play a living companion (setting).

## Keys

| Key | What it does |
|---|---|
| **PageDown** | Play the next hero of the party. |
| **PageUp** | Play the previous hero. |
| **Home** | The party window: recruit, names, behaviour, tactics, dismiss. |

You can change every key in the Mods screen (**F11**, then the mod's *Keys* page). With a controller: **LT + LB**
opens the mod menu with *Party window*, *Play the next hero* and *Play the previous hero*; the companions' portraits
are D-pad stops like the game's buttons (**A** plays that hero). For one-press switching, SacredBild's Options
(Controller page) have the actions *Next party hero* and *Previous party hero*: give them a button.

## Settings

Open the Mods screen with **F11** and pick the mod.

| Setting | What it does |
|---|---|
| Companions at most | How many companions the party window lets you recruit (1 to 14, default 3). |
| A new companion starts | With the experience of the hero you play, with half of it, or at level 1. |
| Shared experience (%) | Experience a party hero gains also goes to the others nearby, times this (0: off). |
| Shared within (tiles) | How near they must be (0: anywhere). |
| Play a living companion when your hero falls | Switch to a companion when the hero you play dies. |
| Companion portraits | The portraits under the game's own, in its portrait ring and with its health bar. |
| Portraits under the game's own | On (default): they continue the game's column of portraits at the right edge. Off: the layout editor (hold Alt) moves them. |
| Companions act on their own | Off: the companions stand where they are. |
| Default behaviour | Aggressive, defensive or passive, for companions without their own. |
| Use combat arts and spells | Off: companions fight with their weapons only. |
| Follow distance / Fight enemies within | In tiles. |

## Limits

- Single player only. In a network game the hero ids 1 to 16 are the players' and each computer runs only what it
  owns: companions there would need the server's cooperation (not done).
- The game names companions "playernameN"; the mod gives them their names again after every load.
- Loading a savegame gives control back to your main hero.
- Companions start without items (as a new hero would) and with the class's first combat art.
- A fallen companion stays down until the game raises it as it raises your own hero; the mod then brings it back to you.
- A hero brought from a file is a copy: items it brings exist twice (in its own savegame and in this one).
- Mercenaries keep the game's limited combat AI (its packages use only a few combat arts); *Assist* only chooses their
  target. Making them heroes would break the quests that track them, so the mod does not.
- Combos: a companion uses the combo slots it has (the combo master's); the party window lists them under tactics.

## Development

- **Files:** `src/companions/mod.lua` (manifest), `main.lua` (party window, portraits, switching, names, shared
  experience), `ai.lua` (what a companion does each think, four times a second).
- **Depends on:** `gear.party` (sacred-bild: recruit, control, orders, abilities, combos, shared experience),
  `gear.world`, `gear.data.abilities` (how the game aims an ability), `gear.ui`, `gear.store`.
- **Self test:** `src/companions_selftest` (`Sacred.exe -gear-auto -gear-load=N -gear-mods=companions,companions_selftest
  -gear-instance=companions`, a single player savegame with enemies nearby, in a copy of the game folder): recruits
  through the party window, checks the name, following, fighting with a combat art, the portrait click, PageDown, the D-pad
  stops and the mod menu.
