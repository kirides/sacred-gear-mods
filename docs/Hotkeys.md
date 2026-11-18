# Example mods: install, hotkeys, settings

Eight client mods in `src/` are documented here. Five belong to the SacredEngineRemake game server's Lua mods and show
their data in the game; three work alone.

| Mod (`id`) | Needs | What | Hotkey (default) | Doc |
|---|---|---|---|---|
| `bounty` | server `bounty_board.lua` | Bounty board panel and a small tracker | **Ctrl+J** | [ServerMods.md](ServerMods.md#bounty--bounty-board) |
| `achievements` | server `achievements.lua` | Toasts and a panel for achievements and the login streak | **Ctrl+G** | [ServerMods.md](ServerMods.md#achievements--achievements-and-login-streak) |
| `serverfeed` | server `rare_drops.lua`, `graveyard.lua` | Rare drops and hero deaths as lines on screen, a list of the latest | **Ctrl+Y** | [ServerMods.md](ServerMods.md#serverfeed--server-feed) |
| `buildsharer` | server `build_sharer.lua` | Publish and browse hero builds | **Ctrl+K** | [ServerMods.md](ServerMods.md#buildsharer--build-sharer) |
| `questhelper` | server `quest_helper.lua` (for records) | Quest items near you and the server's quest records | **Ctrl+U** | [ServerMods.md](ServerMods.md#questhelper--quest-helper) |
| `sessiontracker` | nothing | Session time, kills, gold, experience, rates | **F2** | [Session mods](https://github.com/kirides/sacred-bild/blob/main/docs/GearSessionMods.md) |
| `lootlog` | nothing | Log of drops and pickups | **F3** | [Session mods](https://github.com/kirides/sacred-bild/blob/main/docs/GearSessionMods.md) |
| `damagemeter` | nothing | Damage dealt and taken, DPS | **Ctrl+D** | [Session mods](https://github.com/kirides/sacred-bild/blob/main/docs/GearSessionMods.md) |

The server side of the first five (what the scripts do, their pages and chat commands, with screenshots) is documented in the
SacredEngineRemake repository, `docs/mods/README.md`.

## Install

1. Install Sacred Gear itself (see [Gear.md](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md#install)).
2. Copy the mod's folder from `src/<id>/` (it holds `mod.lua` and `main.lua`) into the game's **`mods`** folder, so that
   you get `mods\<id>\mod.lua`. One folder per mod. Do not copy mods you do not want: every mod in `mods` loads.
3. Start the game. Press **F11** (or the **Mods** button under the escape menu) to open the Mods screen: it lists the mod, an
   On/Off switch, its **Settings** page and its **Keys** page. Every choice is saved at once in `mods\gear_mods.json`.
4. For the five server mods: play on a server that runs the matching script (and the Sacred Gear game server's custom net
   messages, which are on by default). See below.

## Hotkeys, and the clashes in the defaults

All hotkeys are rebindable in the Mods screen (Keys page of each mod; **Default** restores it). The defaults of these mods do
not overlap with each other or with the game's own keys:

| Key | Used by (default) |
|---|---|
| F2 | `sessiontracker` |
| F3 | `lootlog` |
| F5 | `lootfilter` |
| F6 | `autosave` |
| F10 | `shared-stash` |
| F11 | the Mods screen |
| Ctrl+D | `damagemeter` |
| Ctrl+G | `achievements` |
| Ctrl+J | `bounty` |
| Ctrl+K | `buildsharer` |
| Ctrl+U | `questhelper` |
| Ctrl+Y | `serverfeed` |

F7, F8 and F9 are left to the game (F8 is its **quick load**) and the letters the game uses (digits, Q W E R B, A, I, F, C, L,
M, Tab, O, S, H, N, P, Space, Esc, + and -) react with any modifier held, so the mods use Ctrl with letters the game does not
use. If you bind two mods to one key anyway, the Mods screen marks the conflict and both mods fire.

The game's own hotkeys are listed in
[Gear.md](https://github.com/kirides/sacred-bild/blob/main/docs/Gear.md#mod-manager).

## Settings

Declared in each mod's `mod.lua` and shown on its Settings page of the Mods screen (stored in `mods\gear_mods.json`); values
without a screen (positions, refresh seconds) are in `config` of `mod.lua` and can be edited in that file. See the doc of each
mod.

## When there is no server

The five server mods need a server that talks custom net messages (`gear.net`): the SacredEngineRemake game server with the
script. In single player, on the original `GameServer.exe` (it drops the handshake) or on a server without the script they stay
idle; the panels of `bounty`, `achievements`, `buildsharer` and `questhelper` say so ("This server has no ..."). `serverfeed` shows
nothing.

## Screenshots

The client panels are drawn inside the game, so they need the game running; **no screenshots of them exist yet**, and none are
faked here. Each mod's doc describes the layout from its code. The matching web pages of the server are pictured in the server
repository's docs.
