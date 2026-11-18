# Session mods: session tracker, loot log, damage meter

Three client-side mods in `src`, built only on the public Gear API (no new native code). Each shows
a panel (F2, F3, Ctrl+D; rebind in the Mods screen) and keeps its data in its own folder. All three guard every API call
and handler, so missing data (no hero, an item without a name, a failing setting) is skipped instead of raising.

Tests (no game needed; the `gear` global is faked): `luajit tests/session_mods_test.lua`.

## sessiontracker (F2)

Time played, kills, gold gained / spent, experience gained, levels gained, with per-hour rates, next to the lifetime
totals and the last three sessions (`session_totals.json`). A session is one game with a hero (`session.start`) or
the "New session" button.

- Time counts only with the game screen up (not in the escape menu or a full screen window).
- Kills use the `kill` event (the local hero's kills). It is fed by the net messages the game sends and is not
  confirmed in single player: if it never fires, kills stay 0 and the rest works.
- Gold and experience are polled twice a second; "gained" is the sum of the rises (a sale counts as a gain, a purchase
  as "spent").

## lootlog (F3)

Entries: time into the session, name, quality colour, kind (dropped, picked up, acquired), the creature when the
loot function ran in the last 3 seconds (`drops.roll`). Filters: lowest quality, category, kind. Kept in
`lootlog.json` (at most `max_entries`).

There is no pickup or drop event in the API, so it is inferred:

- *dropped*: an item newly lying within `radius` tiles of the hero (`gear.world.items_near`, twice a second). Items
  the player drops, or that walk into range, look the same.
- *picked up*: a new backpack item (`gear.inv.container('backpack')`) that was logged as lying on the ground.
  *acquired*: a new backpack item with no logged drop (bought, from equipment). Items that were in the chest a moment
  before are ignored.
- Items already around or in the backpack when a game starts are the baseline. Gold piles are logged only as drops
  ("Log gold piles"); their amount is not exposed. Plain (normal quality) items are skipped unless "Log plain items".

## damagemeter (Ctrl+D)

Uses the `damage` event, which gives the final damage of each hit and the creature TYPES of attacker and victim (no
ids, no skill, no overkill clipping). Dealt = attacker type is the hero's type, taken = victim type is the hero's type.
Three views (setting "View", the View button in the panel, the `view` key, or "Damage meter: next view" in the
controller's mod menu; the choice is kept in the mod's `view.txt`):

- **Compact** (default): one row per character, name and DPS (the last seconds while a fight runs, else the average of the
  last fight). Alone: one line with a large number. In a network game each player's copy of the mod sends its own
  numbers over the mod channel (`damagemeter`, once a second, setting "Share my DPS"), so the party is listed; players
  without the mod are not.
- **Extended**: per character DPS, DPS taken and total damage dealt, plus the local hero's biggest hit, fighting time and
  average DPS.
- **Detailed**: the full panel of the local hero: fight DPS (a fight ends after 5 s without damage), DPS of the last
  10 s, totals, biggest hits, average hit, fighting time, kills and kills per minute of fighting, a 30 second bar graph,
  the biggest targets and damage sources.

Allies (mercenaries, escorted NPCs such as Wilbur) get a row of their own under their owner. The hook knows only types, so an
ally is a creature TYPE: one whose name contains `wilbur` or `merc`, or one that stayed within 9 tiles of the hero for 20 s while
the hero walked 25 tiles. A type that ever hits the hero is never an ally; two creatures of one type count as one row.

The compact view is a bare, translucent panel (no title bar); the other views are framed. Small buttons: `^` bigger view (`v` back to compact), `x` clears the counters. The layout editor moves the panel, the buttons are controller stops, the size follows the view.

Limits: in a network game another hero of the same class counts as the local hero; pets, traps and effects are not
"dealt" (the hook cannot say whose they are); the number is the engine's computed damage, not the hit points removed;
damage that does not pass the hook (if there is any) is missing. Whether every skill passes the hook has not been
checked in a running game.

## Install, hotkeys, settings, panels

**Install.** Copy `src/sessiontracker`, `src/lootlog` and/or `src/damagemeter` (each holds `mod.lua` and
`main.lua`) into the game's `mods` folder as `mods\sessiontracker`, `mods\lootlog`, `mods\damagemeter`. They need no server. The
Mods screen (F11) lists them with their settings and keys; choices are saved in `mods\gear_mods.json`.

**Hotkeys** (rebindable in the Mods screen, Keys page): `sessiontracker` F2 (`panel`), `lootlog` F3 (`panel`), `damagemeter` Ctrl+D
(`panel`), `view` and `reset` (both unbound by default). The defaults do not overlap with other mods (see [Hotkeys](Hotkeys.md#hotkeys-and-the-clashes-in-the-defaults)).

**Settings** (Mods screen, Settings page):

| Mod | Setting | Default | Meaning |
|---|---|---|---|
| `sessiontracker` | Show per-hour rates after | 30 s (5 to 600) | Rates of a very short session swing wildly; they show as "-" until this much time has been played |
| `sessiontracker` | Save totals every | 60 s (15 to 600) | How often `session_totals.json` is written |
| `lootlog` | Watch the ground within | 25 tiles (5 to 60) | Items that appear on the ground within this distance of the hero are logged as drops |
| `lootlog` | Entries kept | 500 (50 to 2000) | Size of the log |
| `lootlog` | Log plain (normal quality) items | off | Off: only magic, rare, set, unique and quest items |
| `lootlog` | Log gold piles | off | Piles are logged as drops only (the amount is not exposed) |
| `damagemeter` | A fight ends after | 5 s (2 to 30) | Seconds without damage |
| `damagemeter` | View | Compact | Compact, extended or detailed (the View button changes it too) |
| `damagemeter` | Share my DPS with the other players | on | Network game: send this hero's numbers to the other players' meters |
| `damagemeter` | Rolling DPS window | 10 s (3 to 30) | The "Last N s" row |

**Panels** (no screenshots exist: they are drawn inside the running game, and none was available; this is read from the code, in the
1024x768 layout, and every panel can be dragged):

* *Session (F2)*, 270 x 330 at (16, 200), open when the mod loads. Rows: Time played, Kills (with a per-hour rate), Gold gained (rate),
  Gold spent, Experience (rate), Levels gained; "Lifetime (with this session)": Time, Kills, Gold gained, Experience; "Last sessions": up to
  three lines `time  hero  k<kills>  g<gold>`; a **New session** button.
* *Loot log (F3)*, 420 x 360 at (300, 200), resizable, closed until F3. Three dropdowns (lowest quality, category, kind), "N of M entries",
  a **Clear** button (also empties the file), then a scrolling list, newest first, of `#session  m:ss  item name` in the quality colour
  with "dropped", "picked up" or "acquired" (and "(creature)") at the right; at most 300 rows are drawn.
* *Damage meter (Ctrl+D)*, 290 x 420 at (700, 200), closed until Ctrl+D. "Fight (running / last)": dealt DPS / taken DPS and the rolling window; "Since
  reset": damage dealt and taken with hit counts, biggest hit dealt / taken, average hit, fighting time, average DPS while fighting, kills
  (and per minute after 10 s of fighting); a 30-second bar graph (dealt green up, taken red down); "Biggest targets" (3) and "Biggest damage
  sources" (2); a **Reset** button. It says "no hero" until a hero is known.

## Per savegame data

What belongs to one character or game (the session tracker's lifetime totals, the loot log, the region kill counters, the bounty
board, the world events' run, the companions' party records) is kept per savegame, not once for all games. Gear keeps a working copy
in `saves/_current/` of each mod's folder and moves it with the game: a save into a slot keeps it in `saves/GAME05/` (for
`Save\GAME05.PAK`), loading a savegame brings back what was kept for it (or starts fresh), a new game starts fresh, and deleting a
savegame in the game's list deletes its data. Progress since the last save is gone after a load, like the game's own. In a network
game the data follows the hero file (`HERO03`). With ReBorn's own save folder the folders are named after it
(`mods_reborn_save-GAME05`).

Settings, window places, the shared stash, the bounty editor's `custom.json`, world events' `events.json` and the mercenary
behaviour of the companions stay global. Data from before this existed (`session_totals.json`, `lootlog.json`, `region_kills.json`, a
bounty board file, `companions.json`, `local_events_state.json`) goes once to the first savegame that is loaded afterwards, so a
character keeps what it had; the other savegames start empty. Needs a Sacred Gear with `gear.store.game` (older ones keep one
file for all games as before).
