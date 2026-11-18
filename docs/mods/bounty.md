# Bounty board

![Bounty board](../images/bounty.jpg)

Bounties to hunt: what to kill, how far you are, how much time is left and what you get. Works **on its own in single
player** and shows the server's board in network games. A small tracker at the top right keeps your open bounties in view
while you play.

## What you need

Sacred Gear and the mod itself in your `mods` folder (see [Install](../Install.md)). Nothing else for single player.

In a network game the mod shows the board of the server. That needs a SacredEngineRemake game server (`Sacred.GameServer`)
running the script `bounty_board.lua`; on any other server the mod says it has no bounty board.

## How to use it

Press **Ctrl+J** to open the bounty board. The tracker at the top right shows your open bounties; switch it off in the
settings if you do not want it. Move the panel and the tracker with the [layout editor](layout.md) (hold **Alt**). With a
controller, **LT + LB** opens the mod menu, where *Open the bounty board* is a button.

### Single player

The board belongs to your hero: three bounties at a time ("Defeat 32 orc creatures"), drawn from orcs, undead, spiders,
thieves and pirates, wolves/bears/boars, trolls and ogres, demons and golems, and dragons. The strong ones only come up
once your hero has the level for them.

- **Counting:** a monster that dies after you hit one of its kind counts. Monsters only a pet or a trap killed, and
  monsters you never hit, do not.
- **Time:** a bounty runs for about three hours of play. The time only runs while you play (not in the menu, not while the
  game is closed). When it ends, a new one is posted; a finished one stays on the board, marked done, until its time is up.
- **Reward:** gold goes straight into your purse; some bounties add an item that drops at your feet (a chicken appears
  next to you as the "creature" the game's own loot roll drops it from, and stays there). Gold grows with your hero's level.
- **Saved per hero:** the board is saved in the mod's folder (`board_<hero>.json`), so it is still there after loading.
  It is not tamper-proof: single player, your game.
- **Network games** use the server's board. The own board is for single player only.

## Keys

| Key | What it does |
|---|---|
| **Ctrl+J** | Open or close the bounty board. |

You can change every key in the Mods screen (**F11**, then the mod's *Keys* page).

## Settings

Open the Mods screen with **F11** and pick the mod.

| Setting | What it does |
|---|---|
| Own board in single player | On: the mod posts, counts and pays the bounties itself. Off: no board without a server. |
| Tracker | Shows or hides the small progress list at the top right. |

## Development

- **Files:** `src/bounty/mod.lua` (manifest, tracker position, refresh time), `main.lua` (panel, tracker, toasts, the
  server board, the glue), `localboard.lua` (single player board: pool, posting, progress, expiry, saving; pure Lua, no
  `gear` calls), `localgame.lua` (kills and rewards: the parts that touch the game).
- **Two sources, one panel:** `main.lua` shows a payload of the form `{ v = 1, bounties = {{ id, title, text, target, n,
  done, left, reward, claims, level }} }`. In a network game it comes from the server's `bounty:state` channel
  (`gear.net`), otherwise from `localboard.Board:payload()` (`gear.mp.active()` decides, checked once a second).
- **The pool** is `M.POOL` in `localboard.lua`: `names` are words of the creature's type name (`ORC_WARRIOR.GRN` has `orc`
  and `warrior`; whole words, so `SORCERESS` is no orc), `target = {min, max}`, `gold` for a level 10 hero (see `gold_for`),
  `min_level`, `item` (a tier 1 to 3 that sets the rarity bonus). Only monsters count (object kind 3).
- **Kills:** the `kill` event does not fire in single player, so `localgame.lua` watches the monsters around the hero
  (`gear.world.creatures_near` every 0.25 s) and counts one that vanished or is dead when the `damage` event saw a hit of
  the hero's creature type on its type within 8 s, or when `drops.roll` named the hero (object id 1) as the killer.
- **Rewards:** `creature:add_gold` for gold. An item: `gear.world.spawn('CHICKEN.GRN', ...)` at the hero's feet and
  `gear.drops.simulate` on it (one roll at a time, up to 40) with the `drops.roll` bonus and the `drops.select` level set to
  the hero's; the first roll that puts an item on the ground ends it. The client cannot drop a gold pile of a given size.
- **Time and saving:** `Board:tick(dt)` runs once a second with the game's time, so a bounty's `left` only counts play
  time. The board is written with `gear.save` when it changes (at most every 20 s, after a kill at most every 5 s), and when
  the mod is switched off or the game ends.
- **Server side:** `scripts-examples/bounty_board.lua`. The server also pushes every change, `config.refresh` (60 s) is
  only the fallback.
- **Test it:** `src/bounty_selftest` (automation, single player) sets known bounties, spawns zombies, fights, and checks
  the count, the gold and the item. Run it in a **copy** of the game with
  `-gear-auto -gear-instance=bounty -gear-load=1 -gear-mods=bounty,bounty_selftest -gear-timeout=240`; the result is
  `GearAutomation\bounty\bounty_selftest.txt`. With a `config.lua` of `return {phase = 'shots'}` it takes the picture above
  instead. For the server side run a local server with the script, then the game; the protocol is in
  [GearServerMods](https://github.com/kirides/sacred-bild/blob/main/docs/GearServerMods.md).
