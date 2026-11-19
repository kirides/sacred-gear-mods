# Mod events: reacting to other mods

Mods publish *events* that other mods can react to (an achievements mod that rewards a finished bounty, a stream overlay that
shows a world event starting). It is Sacred Gear's own event bus: `gear.emit` publishes, `gear.on` subscribes, `gear.events`
lists what is published (needs a Sacred Gear with `gear.events`; the mods here work without it, they only skip the listing).
Reference: the "Hooks between mods" chapter of `GearApi.md` in the Gear MDK.

Rules every publisher follows:

- The name is `<mod>.<what>`; the payload is **one table**. Fields may be added, never renamed or removed. Do not change the table.
- `source` says where the fact came from: `'local'` (this computer's own mod: single player, or counted from this hero) or `'server'` (the game server told us).
- The first board or state of a session reports what is already running with `initial = true` on `started`; finished things are not replayed.
- A subscriber's error never reaches the publisher. Subscribing needs no dependency: nothing emitted, nothing called.
- Every computer emits for what happens on it. In a network game each player's mods fire for their own view; the game server's Lua mods use the same names and payloads (see GearServerMods in sacred-bild).

```lua
gear.on('bounty.completed', function(ev) print(ev.title, ev.target) end)
gear.on('worldevent.*', function(event, ev) print(event, ev.title, ev.percent) end)   -- every event of one mod
for _, h in ipairs(gear.events.list()) do print(h.name, h.mod, h.listeners) end
```

## bounty

| Event | When | Payload |
| --- | --- | --- |
| `bounty.started` | a bounty is on the board | `id, title, text, region?, level?, target, n, reward?, custom?, source, initial?` |
| `bounty.progress` | its counter went up | same, plus `previous` |
| `bounty.completed` | the target is reached | same |
| `bounty.claimed` | the reward was paid (server boards: together with `completed`) | same |
| `bounty.failed` | it left the board unfinished (time out, stopped) | same |

## quests (daily and weekly)

The daily and weekly quests of the `bounty` mod. `period` is `'daily'` or `'weekly'`. Ids look like `daily:20776:orcs` (the day or week number and the pool entry).

| Event | When | Payload |
| --- | --- | --- |
| `quest.started` | a quest is up (a new day or week; `initial = true` for the running ones when a savegame is loaded or the first state of a session arrives) | `id, period, title, text, target, n, reward?, level?, source, initial?` |
| `quest.progress` | its counter went up | same, plus `previous` |
| `quest.completed` | its target is reached | same |
| `quest.claimed` | its reward was paid; also a streak bonus (`bonus = true`, id `bonus:<period>:<n>`) | same, plus `bonus?` |
| `quest.failed` | the day or week ended before it was done | same |
| `quest.set_completed` | every quest of the day or week is done | `period, count, source` |
| `quest.streak` | one more day or week in a row (`bonus = true` when this step pays a streak bonus) | `period, count, best, bonus?, source` |
| `quest.streak_lost` | a day or week was missed | `period, previous, source` |

On a server the same events come from the state the server pushes (`source = 'server'`).

## world events

| Event | When | Payload |
| --- | --- | --- |
| `worldevent.started` | an event began | `id, title, text, unit, area, count, target, percent, here, source, initial?` |
| `worldevent.progress` | the count went up | same, plus `previous` |
| `worldevent.completed` | the goal was reached | same |
| `worldevent.failed` | the time ran out | same |
| `worldevent.hook` | a trigger fired its actions (spawn, item, message, gold, boss) | `title, id?, action, text?, source` |
| `worldevent.boss.spawned` | a world boss appeared (a `boss` action of an event, or the server announced one; `initial = true` when a boss from the savegame came back after a load) | `id, name, event, type?, type_name?, creature?, health?, damage?, taken?, deflect?, reflect?, regen?, reward?, source, initial?` |
| `worldevent.boss.defeated` | it was defeated (`gone = true`: it left the world without dying as far as the mod can tell, or the server's time for it ran out) | `id, name, event, type?, type_name?, creature?, health?, reward?, by?, gone?, source` |

`id` of a boss is a string (`local:<time>:<n>` in your game, `<event>:<hook>:<action>` from a server); `creature` is the object id in your own game (local bosses only), `health` the boss's maximum health, `damage`, `taken`, `deflect`, `reflect` and `regen` the multipliers it was made with.

The Gear MDK has an example mod that uses these (`examples/hooks`).
