# Sacred Gear mods

<a href="https://kirides.github.io/sacred-bild/add-to-mod-manager.html?index=https%3A%2F%2Fraw.githubusercontent.com%2Fkirides%2Fsacred-gear-mods%2Fmain%2Fmod-index.json"><img src="docs/images/gear-mod-manager.png" alt="Gear Mod Manager icon" width="56" align="middle"> <img src="https://img.shields.io/badge/Gear_Mod_Manager-Add_this_source-2e7d32?style=for-the-badge" alt="Add to Gear Mod Manager" align="middle"></a>
<!-- GitHub strips gear-mod-manager:// links, so the button opens an https page that hands the link to the manager (docs/add-to-mod-manager.html in sacred-bild). -->
Have the [Gear Mod Manager](https://github.com/kirides/sacred-mod-manager)? Press the button to add this repository's index as a source (it asks first).

**More Sacred Gold, from small Lua scripts.** These are mods for [Sacred Gear](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md),
the mod kit of [SacredBild](https://github.com/kirides/sacred-bild) for the GOG / Steam Sacred Gold (also the German
build). A mod is a folder you copy into the game's `mods` folder; you switch it on or off in game.

## For players

### What you get

Click a name for the mod's page: how to use it, its settings and keys, and notes for anyone who wants to tinker with it.
The pictures are screenshots from the game, taken by a script ([how](docs/Screenshots.md)); the numbers and names of the server mods are examples.

| Mod | Preview | What it does |
|---|---|---|
| [**Autosave**](docs/Autosave.md) | <img src="docs/images/autosave.jpg" width="220" alt="Autosave"> | Saves the game every few minutes into its own slots. F6 saves right now. |
| [**Shared stash**](docs/SharedStash.md) | <img src="docs/images/shared-stash.jpg" width="220" alt="Shared stash"> | One stash for all your heroes, next to the chest window. Works in LAN games too. |
| [**Better SaveLoad**](src/better-saveload/README.md) | <img src="docs/images/better-saveload.jpg" width="220" alt="Better SaveLoad"> | A clearer savegame screen with the Save tab first. |
| [**Enhanced Chat**](docs/mods/enhanced-chat.md) | <img src="docs/images/enhanced-chat.jpg" width="220" alt="Enhanced Chat"> | A chat window with scrollback, tabs for global, private and system messages, a player filter and item names in their rarity colour. |
| [**Key bindings**](docs/mods/key-bindings.md) | <img src="docs/images/key-bindings.jpg" width="220" alt="Key bindings"> | Choose the keys and mouse buttons of the game's actions (two per action), and quick cast combat arts with one press. |
| [**Drop tuning**](docs/DropTuning.md) | <img src="docs/images/drop-tuning.jpg" width="220" alt="Drop tuning"> | More or fewer drops, better rarity odds, creatures drop the gear you could otherwise only disarm from them, optional fair random numbers. |
| [**Balance editor**](docs/mods/balance-editor.md) | <img src="docs/images/balance-editor.jpg" width="220" alt="Balance editor"> | Edit the game's balance.bin in game: difficulty multipliers, creature health, skill curves, loot chances, prices, movement speed. Your own overlay, the game's file is never touched; export and import balance patches. Ctrl+Shift+B. |
| [**Loot filter**](docs/mods/lootfilter.md) | <img src="docs/images/lootfilter.jpg" width="220" alt="Loot filter"> | Picks up only the items you want and dims the rest on the ground. F5. |
| [**Loot log**](docs/mods/lootlog.md) | <img src="docs/images/lootlog.jpg" width="220" alt="Loot log"> | A list of what dropped and what you picked up. F3. |
| [**Companions**](docs/mods/companions.md) | <img src="docs/images/companions.jpg" width="220" alt="Companions"> | A party of heroes in single player: recruit companions of any class with their own gear, skills and experience, play any of them (click a portrait, PageDown), the others follow and fight with their combat arts, spells and combos. Home. |
| [**Name editor**](docs/mods/name-editor.md) | <img src="docs/images/name-editor.jpg" width="220" alt="Name editor"> | Build character names with colors, icons and gradients; copy the raw text Sacred stores. Ctrl+Shift+N. Also a [web page](docs/name-editor/index.html). |
| [**Custom classes**](docs/mods/custom-classes.md) | <img src="docs/images/custom-classes.jpg" width="220" alt="Custom classes"> | Heroes with a class of your own: a Seraphim with Battle Mage fire, a Gladiator that casts. A class is a profile on one of the eight hero bodies (skills, arts from any class, runes), written by the Sacred Class Editor or by hand. Ctrl+Shift+C. |
| [**Art bars**](docs/mods/art-bars.md) | <img src="docs/images/art-bars.jpg" width="220" alt="Art bars"> | Extra bars of slots for your combat arts, spells and combos (also the copies and chains of Custom classes), with keys (Ctrl+1 ...), cooldowns and the controller. |
| [**Item comparison**](docs/mods/item-compare.md) | <img src="docs/images/item-compare.jpg" width="220" alt="Item comparison"> | Hover an item and see, in green and red, what it changes compared with what your hero (or a companion) wears in that slot. Works with the controller's cursor too. |
| [**Damage meter**](docs/mods/damagemeter.md) | <img src="docs/images/damagemeter.jpg" width="220" alt="Damage meter"> | Damage and DPS, for you and your party. Ctrl+D. |
| [**Session tracker**](docs/mods/sessiontracker.md) | <img src="docs/images/sessiontracker.jpg" width="220" alt="Session tracker"> | Time played, kills, gold and experience, with rates per hour. F2. |
| [**Spawn rate**](docs/mods/spawn-rate.md) | <img src="docs/images/spawn-rate.jpg" width="220" alt="Spawn rate"> | Multiply the creatures the game spawns, from 1x to 100x, with safeguards for the frame rate. Single player. |
| [**Spell tuning**](docs/mods/spell-tuning.md) | | Shorten or strengthen root, stun, fear, spell strength and damage by who casts the spell: you, companions, enemies, neutrals or traps. Single player. |
| [**Region counter**](docs/mods/region-counter.md) | <img src="docs/images/region-counter.jpg" width="220" alt="Region counter"> | The kills a region needs before its Region Boss quest: set your own number, and keep the count when you leave the region or quit. |
| [**Layout editor**](docs/mods/layout.md) | <img src="docs/images/layout.jpg" width="220" alt="Layout editor"> | Move the game's windows and mod panels where you want them. Hold Alt. |
| [**Realm picker**](docs/mods/realms.md) | <img src="docs/images/realms.jpg" width="220" alt="Realm picker"> | Choose the online play server for Closed and Open Internet. |
| [**Auction house**](src/auction-house/README.md) | <img src="docs/images/auction-house.jpg" width="220" alt="Auction house"> | Buy and sell items between players. Needs a multiplayer game (useless in single player). |
| [**World events**](src/world-events/README.md) | <img src="docs/images/world-events.jpg" width="220" alt="World events"> | A progress bar for the server's world event. |
| [**Sector tools**](src/sector-tools/README.md) | <img src="docs/images/sector-tools.jpg" width="220" alt="Sector tools"> | For server admins: sector and grid cell, recording areas. Not in the release zip. |
| [**Achievements**](docs/mods/achievements.md) | <img src="docs/images/achievements.jpg" width="220" alt="Achievements"> | Messages for achievements and the daily login reward. Needs a server script. |
| [**Bounty board**](docs/mods/bounty.md) | <img src="docs/images/bounty.jpg" width="220" alt="Bounty board"> | Bounties to hunt, with progress and rewards. Works alone in single player (make your own bounties and automatic triggers, e.g. for streams), shows the server's board in network games. Ctrl+J. Also [daily and weekly quests](docs/mods/bounty.md#daily-and-weekly-quests) with a streak bonus (Ctrl+Shift+D). |
| [**Build sharer**](docs/mods/buildsharer.md) | <img src="docs/images/buildsharer.jpg" width="220" alt="Build sharer"> | Publish your build and browse the builds of others. Ctrl+K. Needs a server script. |
| [**Quest helper**](docs/mods/questhelper.md) | <img src="docs/images/questhelper.jpg" width="220" alt="Quest helper"> | Quest items and the server's quest records with hints. Ctrl+U. Needs a server script. |
| [**Server feed**](docs/mods/serverfeed.md) | <img src="docs/images/serverfeed.jpg" width="220" alt="Server feed"> | Rare finds and hero deaths on screen. Needs a server script. |
| [**Twitch Integration**](docs/mods/twitch_integration.md) | <img src="docs/images/twitch_integration.jpg" width="220" alt="Twitch Integration"> | Turns rewards, bits and chat into actions in your game. Base mod. |
| [**Twitch Integration: actions**](docs/mods/twi_sacred.md) | <img src="docs/images/twi_sacred.jpg" width="220" alt="Twitch Integration: actions"> | Viewers spawn monsters, give gold, heal or teleport your hero. |

Each mod is switched on or off in the **Mod manager** (**F11**, or the *Mods* button under the escape menu), where you also change its settings and keys.

### Sacred ReBorn

The mod for Sacred ReBorn lives in a repository of its own:
[sacred-gear-reborn-decomp](https://github.com/kirides/sacred-gear-reborn-decomp).

### Recommended installation: Gear Mod Manager

The easiest way to get SacredBild, Sacred Gear and these mods, and to keep them updated, is the
[**Gear Mod Manager**](https://github.com/kirides/sacred-mod-manager):

1. Download the newest `Gear-Mod-Manager-nightly-win-x64.zip` from its [releases](https://github.com/kirides/sacred-mod-manager/releases) (under **Assets**).
2. Unzip it into the folder with `Sacred.exe` and start `Gear Mod Manager.exe`.
3. Open **Browse**: install the plugins **Sacred-Bild** and **Sacred Gear** (tab **Plugins**), then the mods you like (tab **Mods**).
4. Press **Start Sacred**.

![Gear Mod Manager, Browse](https://raw.githubusercontent.com/kirides/sacred-mod-manager/main/docs/images/02-browse-dark.png)

### Install by hand

1. Install [SacredBild and Sacred Gear](https://github.com/kirides/sacred-bild#install): extract a release zip into
   the game folder. `SacredGear.dll` next to the game loads with SacredBild.
2. Copy the folders you want from `src` to the game's `mods` folder: `src\autosave` becomes `mods\autosave`,
   `src\shared-stash` becomes `mods\shared-stash`. Leave the `*_selftest` folders out; they are tests.
3. Start the game and press **F11**: the mods are listed, each can be switched on or off.

Details, settings, controller use and limits: [Install](docs/Install.md), [Autosave](docs/Autosave.md),
[Shared stash](docs/SharedStash.md), [Controller](docs/Controller.md).

---

## Technical overview

> **AI disclosure:** like SacredBild, these mods are developed with an AI coding assistant (Anthropic's Claude), at the
> maintainer's direction; the maintainer decides what goes in and tests the changes in the game.

Each mod is a folder in `src`: `mod.lua` is the manifest (id, version, settings, keys), `main.lua` the code, in Lua
(LuaJIT) on Sacred Gear's API ([GearApi](https://github.com/kirides/sacred-bild/blob/main/docs/GearApi.md)).

| Folder | |
|---|---|
| `src/autosave` | Periodic autosave. [README](src/autosave/README.md) |
| `src/autosave_selftest` | Automation self test of the autosave mod |
| `src/better-saveload` | The savegame screen on Gear's replaced windows. [README](src/better-saveload/README.md) |
| `src/better-saveload_selftest` | Automation self test of Better SaveLoad |
| `src/enhanced-chat` | A chat window with scrollback, tabs and rarity colours, on `gear.chat`. [Doc](docs/mods/enhanced-chat.md) |
| `src/enhanced-chat_selftest` | Automation self test of Enhanced Chat |
| `src/drop-tuning` | Drop chance, rarity weights and drop random numbers on `gear.drops`. [Doc](docs/DropTuning.md) |
| `src/drop-tuning_selftest` | Automation self test of the drop-tuning mod |
| `src/balance-editor` | Edits bin\balance.bin through a file overlay owned by the mod. [Doc](docs/mods/balance-editor.md) |
| `src/balance-editor_selftest` | Automation self test of the balance editor |
| `src/world-events` | A movable progress bar for the game server's world event (needs the remake server's `world_events.lua`). [README](src/world-events/README.md) |
| `src/world-events_selftest` | Automation self test of the world-events mod |
| `src/sector-tools` | For server admins: the sector id and grid cell you stand in, boundaries on the ground, recording areas by walking, copy-to-clipboard of the config line for the server's `world_events.lua`. [README](src/sector-tools/README.md) |
| `src/sector-tools_selftest` | Automation self test of the sector-tools mod |
| `src/achievements`, `buildsharer`, `questhelper`, `serverfeed` | Clients of the SacredEngineRemake server mods. [Doc](docs/ServerMods.md) |
| `src/bounty`, `src/bounty_selftest`, `src/quests_selftest` | Bounty board and daily / weekly quests: own board and quests in single player, the server's in network games, and the self tests. [Doc](docs/mods/bounty.md); logic tests `tests/bounty_hooks_test.lua`, `tests/bounty_board_test.lua`, `tests/quests_test.lua` |
| `server-scripts/daily_quests.lua` | The game server's half of the daily and weekly quests (copy it into the server's `scripts` folder) |
| `src/lootfilter` | Loot filter: pick up by class, quality and category, dim the rest |
| `src/layout` | Layout editor: move the game's windows and mod panels |
| `src/realms` | Realm picker for the online play server |
| `src/twitch_integration`, `src/twi_sacred` | Twitch Integration: the connector's pipe and the actions (monsters, gold, heal, teleport) |
| `src/name-editor`, `src/name-editor_selftest` | Name editor: colors, icons and gradients for character names; its window and the web page (`tools/make_name_editor_web.py`) share one fragment. [Doc](docs/mods/name-editor.md) |
| `src/sprite-browser` | All UI images with their numbers in the mod's page; the `.sprite-N` classes of the theme. [Doc](docs/mods/sprite-browser.md) |
| `src/sacred-theme` | The shared RmlUi look (game frame, buttons, orbs, sliders, tab bars, controller prompts); optional: the mods look plainer without it |
| `src/sessiontracker`, `src/lootlog`, `src/damagemeter` | Session mods. [Doc](docs/SessionMods.md); logic test `tests/session_mods_test.lua` |
| `src/item-compare`, `src/item-compare_selftest` | Item comparison tooltips and its self test. [Doc](docs/mods/item-compare.md) |
| `src/region-counter` | Region Boss kill counters on `gear.data.regions`. [Doc](docs/mods/region-counter.md); logic test `tests/region_counter_test.lua` |
| `tests/modmock` | Smoke tests of buildsharer and questhelper without the game ([how](tests/modmock/README.md)) |
| `src/shared-stash` | The shared stash, built on `gear.inv`; includes its self tests. [README](src/shared-stash/README.md) |
| `tools/readme-shots` | Takes this README's screenshots in a copy of the game folder ([how](docs/Screenshots.md)) |

Editor support: `.luarc.json` points LuaLS at `../sacred-bild/gear/meta` (check both repositories out side by side).
The self tests run the real game without a player (`-gear-auto`); see each mod's README and the
[automation](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md#automation) docs.

## Documentation

| Document | Contents |
|---|---|
| [Install](docs/Install.md) | Installing Sacred Gear and the mods, the Mods screen, updating |
| [Autosave](docs/Autosave.md) | Timer, slots, settings, loading an autosave |
| [Drop tuning](docs/DropTuning.md) | Drop chance, rarity weights, carried gear, the generator; the self test |
| [Shared stash](docs/SharedStash.md) | Using the stash, LAN, limits, the file, savegame caveats |
| [Server mods](docs/ServerMods.md) | The five clients of the remake server's scripts: install, hotkeys, settings |
| [Mod events](docs/ModEvents.md) | Events mods publish for other mods (bounty, quests, world events) and how to subscribe |
| [Session mods](docs/SessionMods.md) | Session tracker, loot log, damage meter |
| [Hotkeys](docs/Hotkeys.md) | Install, default keys and the clashes between mods |
| [Controller](docs/Controller.md) | Using the mods with a gamepad |
| [Screenshots](docs/Screenshots.md) | Re-taking the README's screenshots |
| [Names and IDs](docs/NamesAndIds.md) | Mods save ids and show localized names; migrating saved names |
| [Mod index](docs/ModIndex.md) | The `mod-index.json` format for mod managers |

## Mod manager index

[`mod-index.json`](mod-index.json) lists the mods of this repository for desktop mod managers; the Gear Mod Manager
reads it from the branch. Every release has one asset, `mods.zip`, so the index points to `releases/latest/download/mods.zip`
(the newest non-pre-release). A CI step fails when the index and the mods in `src` disagree. Other repositories can publish their own `mod-index.json` the same way, and an index can
also point at other indexes. The full format is in [Mod index](docs/ModIndex.md).
`python tools/make_mod_index.py` regenerates the `mods` array from the `mod.lua` files (`--check` for CI); see [Generating the index](docs/ModIndex.md#generating-the-index).

| Field | |
|---|---|
| `schema` | Format version, `1` |
| `name`, `author`, `description`, `homepage` | Who publishes the index |
| `download` | `url` of the zip and its `version` (the latest tag, or `latest`) |
| `mods[]` | One entry per mod: `id` (the id of its `mod.lua`), `path` (the folder inside the zip, `mods/<name>`), `name`, `version`, `author`, `description`, optional `tags`, `thumbnail`, `requires`, `defaultEnabled`, `download` |
| `indexes[]` | Optional: other indexes to follow, each `url` (absolute https, or relative to this index) and an optional `name` |

## Versioning

`tools/bump_versions.py` raises the `version` of each mod from the git history, so nobody edits it by hand. Per mod it looks at the commits since
the last version bump of that mod (the last commit that changed its `version = '...'` line): any change to a non-test file raises the **patch**
number, a commit message with `feat(<mod>)` raises **minor**, one with `break(<mod>)` raises **major** (spaces and case do not matter,
`feat(a, b)` counts for both mods). Test files (`tests`, `tools`, names ending in `test`) do not count.

```
python tools/bump_versions.py            # show the plan
python tools/bump_versions.py --commit   # bump, one commit per mod, refresh mod-index.json
python -m unittest tools/test_bump_versions.py
```
