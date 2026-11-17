# World events

A [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md) mod that shows the **world event** of a game
server as a movable progress bar: a realm-wide goal such as *"slay 1000 orcs in 2 hours"*. Everybody who takes part shares the
reward when the realm makes it; the server announces the start, 25 / 50 / 75 % and the result in chat.

![The bar](../../docs/images/world-events.jpg)

## What you need

* The mod: copy this folder to `mods\world-events` in the game folder and switch it on in the mod manager (**F11**).
* A game server with Sacred Gear's custom net messages and the script `world_events.lua`: the remake's
  `Sacred.GameServer` (`scripts-examples/world_events.lua` in the SacredEngineRemake repository; copy it to the server's
  `scripts` folder). **The original `GameServer.exe` cannot run scripts and does not carry the messages, so there is nothing for this mod
  to show there** and no fallback: the mod stays silent (the server's own chat lines do not exist either). In single player or
  a LAN game without that server the mod does nothing.

Players need no other setup: the server pushes the state when you join, when you enter another sector, when the progress
changes and every few seconds while an event runs. Names on the server's public dashboard page are character names only.

## The bar

Title bar: the event's name. Inside: the goal, the time left (counting down on your computer between the server's pushes, so the
clocks do not matter), a bar with the percentage and `count / target`, and your own share (`Your share: 12 of 10 needed` until you
reached the minimum for the reward). In the last minute the bar and the clock turn red. When an event ends the bar stays for
a while (2 minutes by default, set by the server) and says **Completed!** or **Failed**.

* **Move it:** hold **Alt** and press *Edit layout* (the layout editor from Sacred Gear's examples), drag the bar, resize it by its
  corner. While you edit, the bar shows a sample if no event runs, so you can place it any time. The place is kept in
  `mods\gear_layout.json`.
* **Settings** (*Mods* screen, **F11**, or the *Mods* button under the escape menu; all reachable with the controller):
  * *Show the bar*: **always while an event runs** (default) or **only while Alt is held** (like the game's own labels).
  * *Where*: **where the event counts** (default) or **everywhere**. An event that counts only in some sectors shows its bar
    while you stand in one of them; an event without sectors shows everywhere.
  * *Show the result for a while*: on / off.
* **Controller:** the mod has no buttons and binds no key. The *Mods* screen reaches the settings, and the controller's mod menu
  (LT + LB by default) has an entry **World events: bar always / only with Alt** that switches the first setting.

## How it talks to the server

Channel `worldevents:state` of `gear.net` (custom opcodes). The mod says `{hello = 1}` to the server when the messages become
available, when a game starts and every 30 seconds; the server answers with the state for this player:

```lua
{ v = 1, st = 'active', n = <event number>, title, text, count, target, left = <seconds>, dur, here = <counts where you are>,
  mine = <your share>, need = <minimum for the reward>, people, reward }
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
luajit tests/main_test.lua     main.lua against a fake gear: who may push, hello, what is drawn when, the controller entry
```

`src/world-events_selftest` runs in the real game (`-gear-auto`, a copy of the game folder, see its header): the bar as a layout panel,
hidden with "only while Alt" and outside the event's sector, a sample in the layout editor, the result banner, a move.

The server half has its own tests in the remake repository (`WorldEventsScriptTests`).
