# Companions

![Companions](../images/companions.jpg)

A party of heroes in single player, the way Dragon Age does it. Recruit companions of any class: each is a real hero
with their own backpack, equipment, attributes, skills, combat arts, spells and experience, saved with your
savegame. Play any of them: click their portrait under the game's own (top right), press **PageDown**, or use the controller's
mod menu. The heroes you do not play follow you and fight on their own, with their weapons, combat arts, spells and
combos.

## What you need

Sacred Gear (with `gear.party`) and the mod. Single player only: in a network game the mod does nothing (there the
hero slots belong to the players).

## How to use it

1. Press **Home** (or *Party window* in the controller's mod menu, **LT + LB**) and pick a class next to *Recruit*.
   The new hero joins where you stand, with the experience of the hero you play (setting), so they have skill points
   to spend: switch to them and spend the points like for your own hero. They come without items: give them equipment from your
   stash or what you find.
2. Play another hero: click their portrait, press **PageDown** / **PageUp**, use *Play* in the party window, or the mod menu.
   The camera, the HUD, the inventory, skills and combat arts windows, the mouse, the keys and the controller then serve
   that hero. The gold goes with you (the party shares one purse) and mercenaries follow the hero you play.
3. **Heroes from other savegames:** in the party window, *Keep <name> for other savegames* writes the hero you play
   to a hero file (in `mods\companions\heroes`). In another savegame, pick them under *Bring* and press *Bring*: a copy
   of that hero joins with their level, attributes, skills, combat arts, combos, equipment and backpack. Your network
   characters (`Save\HeroNN.pax`) are listed there too. The hero in the other savegame stays as they are.
4. In the party window each hero has a **behaviour** for the time you play someone else (*Aggressive*: fights what
   comes near; *Defensive*: protects the hero you play; *Passive*: only follows), a **name**, and **tactics**: the combat
   arts, spells and combos they may use on their own. *Dismiss* sends a companion away for good (empty their backpack first:
   what they wear is lost).

**The game's own mercenaries** follow the hero you play. Under *Mercenaries* in the party window you choose what they
do: *As the game does* (default, nothing changes), *Assist* (they attack the enemy the party fights when they stand
idle) or *Passive* (they stay with you). Their own combat AI, their quests and escort scripts stay the game's; the mod
never teleports them or changes what they are.

What the companions do on their own: they keep up with you (a companion left far behind or on another level joins
you), pick the enemy nearest to you, attack it with their weapon, and use their abilities like a player would: combos
and attack arts and spells on the target as soon as they have regenerated, auras and buffs (Steinhaut, Ehrfurcht ...)
once a fight starts, healing spells when someone in the party is low on health (setting): first on the hero you play, then on
themselves (or the lowest, setting). The game casts these spells (Genesung, Spirituelle Heilkraft) only on the caster,
its own AI too: for you, the companion casts the spell and you get the health it gives (what it healed the companion
last time, until then a third of your health). Buffs and auras (Steinhaut, Wieselflink ...) are cast in fights and
again when they run out, or whenever they are ready (setting). The ones the game meant for companions too (Steinhaut,
Glaubensstärke, Katarakt der Wendigkeit, Reiki) reach the other heroes near the caster through Gear's buffs: at half
strength by default (a setting per buff, 0: off), with the game's look (Steinhaut's stone), for as long as the
caster's own lasts. A Vampiress changes into her vampire form
(Vampirform) when a fight starts and back after it, or when she is low on health (in daylight the form costs health).
Other shape changes (Ritterform ...), teleports and tricks are left to you.

Experience: what one party hero earns from kills and quests also goes to the others nearby (setting). If the hero you
play falls, you play a living companion (setting).

**Hardcore companions** (setting, off by default): a companion who falls is gone for good, with what they carry. This
belongs to the savegame: a savegame written before the fall still has them, one written after it does not.

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
| Fallen companions get up after the fight | At your side with a quarter of their health, once no enemy is near. |
| Hardcore companions: the fallen stay gone | Off (default). On: a companion who falls is gone for good (see above). |
| Play a living companion when your hero falls | Switch to a companion when the hero you play dies. |
| Companion portraits | The portraits under the game's own, in the game's portrait ring and with its health bar. |
| Portraits under the game's own | On (default): they continue the game's column of portraits at the right edge. Off: the layout editor (hold Alt) moves them. |
| Companions act on their own | Off: the companions stand where they are. |
| Default behaviour | Aggressive, defensive or passive, for companions without their own. |
| Use combat arts and spells | Off: companions fight with their weapons only. |
| Healing spells first for | The hero you play, then themselves (default); whoever has the least health; or themselves first. |
| Heal a hero below (% health) | Default 60. |
| Buffs and auras | In fights and again when they run out (default), or whenever they are ready. |
| Steinhaut / Glaubensstärke / Katarakt der Wendigkeit / Reiki on the others (%) | How strong the other heroes get it (default 50, 0: off). |
| Follow distance / Fight enemies within | In tiles. |

## Limits

- Single player only. In a network game the hero ids 1 to 16 are the players' and each computer runs only what it
  owns: companions there would need the server's cooperation (not done).
- The game names companions "playernameN"; the mod gives them their names again after every load.
- Loading a savegame gives control back to your main hero.
- Companions start without items (as a new hero would) and with the class's first combat art.
- A fallen companion gets up after the fight (unless *Hardcore companions* is on); left down, the game removes them
  after about 25 s, with what they carry.
- A hero brought from a file is a copy: the items they bring exist twice (in their own savegame and in this one).
- Mercenaries keep the game's limited combat AI (its packages use only a few combat arts); *Assist* only chooses their
  target. Making them heroes would break the quests that track them, so the mod does not.
- Combos: a companion uses the combo slots they have (the combo master's); the party window lists them under tactics.

## Development

- **Files:** `src/companions/mod.lua` (manifest), `main.lua` (switching, names, recruiting, shared
  experience), `window.lua` (the portraits and the party window: drawing only, actions come from main.lua), `ai.lua` (what a companion does each think, four times a second).
- **Depends on:** `gear.party` (sacred-bild: recruit, control, orders, abilities, combos, shared experience),
  `gear.world`, `gear.data.abilities` (how the game aims an ability), `gear.ui`, `gear.store`.
- **Self test:** `src/companions_selftest` (`Sacred.exe -gear-auto -gear-load=N -gear-mods=companions,companions_selftest
  -gear-instance=companions`, a single player savegame with enemies nearby, in a copy of the game folder): recruits
  through the party window, checks the name, following, fighting with a combat art, the portrait click, PageDown, the D-pad
  stops and the mod menu.
