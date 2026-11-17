# World events

A [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md) mod that shows the **world event** of a game
server as a small movable indicator: a realm-wide goal such as *"slay 1000 orcs in 2 hours"*. Everybody who takes part shares the
reward when the realm makes it; the server announces the start, 25 / 50 / 75 % and the result in chat.

![The pill, and its details on hover](../../docs/images/world-events.jpg)

## What you need

* The mod: copy this folder to `mods\world-events` in the game folder and switch it on in the mod manager (**F11**).
* A game server with Sacred Gear's custom net messages and the script `world_events.lua`: the remake's
  `Sacred.GameServer` (`scripts-examples/world_events.lua` in the SacredEngineRemake repository; copy it to the server's
  `scripts` folder). **The original `GameServer.exe` cannot run scripts and does not carry the messages, so there is nothing for this mod
  to show there** and no fallback: the mod stays silent (the server's own chat lines do not exist either). In single player or
  a LAN game without that server the mod does nothing.

Players need no other setup: the server pushes the state when you join, when you enter another sector, when the progress
changes and every few seconds while an event runs. Names on the server's public dashboard page are character names only.

## The pill

A small, dark, rounded pill (about a third opaque, no frame, no title bar) with a **double ring**: the gold ring is the
realm's progress, the thin blue ring inside it drains with the time left (it turns orange in the last minute), and the
percentage is in the middle. To the right: the event's name, then `370 / 1,000 orcs · 1:12:04` (the timer in blue).

* **Details:** hover the pill with the cursor, or hold **Alt** (the game's "show text"), and a small tooltip lists the goal,
  the progress (`370 / 1,000 orcs (37%)`), the time left, **your share** (`Your share: 12 (10 needed for the reward)` until you
  reached the minimum), the reward, the **item odds** (see below) and, for an event tied to an area, Around Silver Creek; the area name also follows the title in the pill. The controller's mod menu (LT + LB by default) has **World events: pin / unpin the
  details**.
* **Pulse:** the pill glows for a moment when the realm passes 25, 50 or 75 % (a setting).
* **Result:** when an event ends, the pill shows one short line, **Completed!** or **Failed**, in a green or red ring, and fades
  out over its last seconds (the time is the server's `result_hold`, 2 minutes by default).
* **Move it:** hold **Alt** and press *Edit layout* (the layout editor from Sacred Gear's examples), drag it, resize it by its
  corner (the text and rings scale with its height). While you edit it shows a sample if no event runs, so you can place it
  any time. The place is kept in `mods\gear_layout.json`; a bigger size an older version of this mod kept (the old bar was
  300 x 86) is brought back to the new default (220 x 46).
* **Settings** (*Mods* screen, **F11**, or the *Mods* button under the escape menu; all reachable with the controller):
  * *Show the bar*: **always while an event runs** (default) or **only while Alt is held**. The controller's mod menu has an entry
    **World events: always / only with Alt** that switches it.
  * *Where*: **where the event counts** (default) or **everywhere**. An event that counts only in some sectors shows its pill
    while you stand in one of them; an event without sectors shows everywhere.
  * *Pulse at 25, 50 and 75 %* and *Show the result for a while*: on / off.
* **No key** is bound and there are no buttons: the pill takes no clicks (the mouse goes on to the game), so it never gets in
  the way.

The pill is a **bare panel** (`gear.ui.panel` with `bare = true`, added to Sacred Gear for it: no window chrome, but still a layout
panel). It needs a SacredGear.dll that has the option; an older one draws a plain panel with its title bar instead.

## Reward odds

The server can make the item reward better the further the realm gets (rows like *from 10 %: Magic 25 %, Common 75 %*). The tooltip lists the odds of the row the realm has reached and of the next one, as the server sends them, with the rule: the item is rolled once when the event ends, with the highest row reached. The server's dashboard, !event rewards and the milestone announcements show the same odds; nothing is hidden or added by this mod.

## How it talks to the server

Channel `worldevents:state` of `gear.net` (custom opcodes). The mod says `{hello = 1}` to the server when the messages become
available, when a game starts and every 30 seconds; the server answers with the state for this player:

```lua
{ v = 1, st = 'active', n = <event number>, title, text, unit = 'orcs', area = 'Silver Creek', count, target, left = <seconds>, dur, here = <counts where you are>,
  mine = <your share>, need = <minimum for the reward>, people, reward,
  odds = <current odds text>, odds_at = <percent>, odds_next = <next odds text>, odds_next_at = <percent> }
{ v = 1, st = 'won' | 'failed', n, title, text, count, target, hold = <seconds to keep showing>, here, people }
{ v = 1, st = 'idle', next_in = <seconds> }
```

Only messages from the server (slot 0) are accepted; everything is type-checked and clipped (`core.lua`) before it reaches a
draw call, and a state not refreshed for 2 minutes is dropped. Other mods can show something in the bar with
`gear.emit('world-events.state', {st = 'active', ...})`.

## Tests

No game needed (LuaJIT, from this folder):

```
luajit tests/core_test.lua     the state, percent / time / count formats, area, results, stale states
luajit tests/main_test.lua     main.lua against a fake gear: who may push, hello, what is drawn when, details, pulse, the controller entries
```

`src/world-events_selftest` runs in the real game (`-gear-auto`, a copy of the game folder, see its header): the pill as a bare layout panel,
hidden with "only while Alt" and outside the event's sector, a sample in the layout editor, an old kept size brought back, the result line, a move; screenshots `pill-*.bmp`.

The server half has its own tests in the remake repository (`WorldEventsScriptTests`).
