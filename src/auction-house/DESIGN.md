# Auction house: design

Status: built in stages (see "Build plan" at the end). This is the spec the mod and the Gear additions follow.

Goal: players of one game (single player, LAN, Open Net, later Closed Net on our own GameServer) put items up for sale
for gold; others browse, filter, sort and buy them. A listed item leaves the seller's inventory and is held by the
host ("the market") until it sells or its time runs out; then the item, or the gold, waits in the seller's mailbox
until they collect it at a chest. The market is reached from the game's chest window, like the shared stash.

## 1. What other games did, and what it did to their economies

| Game | Model | Fees / sinks | Duration | Notes |
|---|---|---|---|---|
| Diablo III (2012-2014) | Global gold AH and a real-money AH, buyout + bids | 15 % cut of the sale (gold AH), flat fee + cut on the RMAH | 48 h | Closed 18 March 2014. Blizzard's own reasoning: it "undermined Diablo's core game play: kill monsters to get great loot". Best-in-slot gear was a few clicks away, so drops stopped mattering; loot tables were tuned around the AH, which made self-found play miserable. Loot 2.0 (fewer, better, class-targeted drops) replaced it. |
| World of Warcraft | Per-faction, later per-region AH, buyout + bids, mail delivery | Deposit by vendor price and duration (lost on expiry or cancel, refunded on sale); 5 % cut on the sale | 12 / 24 / 48 h | Expired and cancelled items and the gold come back by mail. The deposit punishes listing spam and absurd prices; the cut is a steady gold sink. Bots and "AH goblins" (buy low, relist high) are part of the culture. |
| Guild Wars 2 Trading Post | Global order book: sell listings and buy orders, instant match | 5 % listing fee (non-refundable) + 10 % exchange fee on the sale = 15 % | No expiry | Deliveries wait in a pickup box. Buy orders give real price discovery (bid/ask spread). The 15 % is one of the game's largest gold sinks and keeps inflation down. |
| Path of Exile | No AH for most of its life: public stash tabs indexed by a trade website, then "whisper and meet" | None (barter currency); the Currency Exchange later added a fee for currency only | Until removed | Deliberate friction: Grinding Gear Games keeps item trade manual so self-found loot stays exciting and bots/flippers have a harder time. Price discovery happens outside the game. |
| RuneScape Grand Exchange | Order book, instant matching at a market price | 1 % tax (2021), later 2 % (Old School) | Until filled | Buy limits per item per 4 hours against market manipulation and gold-farm bots; the tax funds an item sink. |

What follows for a small co-op/LAN game like Sacred:

- **Friction is a feature.** An instant global market makes drops worthless (D3). Sacred is a loot game; its groups
  are 2 to 16 players. So: buyout only (no bids to snipe), listings that expire, a sale cut and a small listing fee,
  and the market only at a chest (not from anywhere).
- **Gold sinks keep gold worth something.** Sacred's gold inflates heavily in the late game (merchant sales). The
  defaults take 5 % of a sale and 0.5 % of the price per listed day; the host can change both (0 turns them off).
- **Expiry and mail.** Unsold items come back automatically (WoW). Nothing is ever destroyed silently.
- **Price discovery.** No bid/ask book (too few players), but the market keeps the recent sales per item type and
  shows their median beside the price field and in the browse list.
- **Dupes and bots.** Every famous dupe was a transfer that was not atomic (an item in two places after a crash or a
  repeated request). Section 4 is the answer. Bots are not a concern in LAN games; the per-seller listing cap and the
  fees limit flooding anyway.

## 2. Where the market runs

Sacred's multiplayer has a separate server process (GameServer.exe, or our C# remake); the host's own `sacred.exe` is
an ordinary client of it. Every computer runs the same mod (required on all clients, as for the other server-side
mods). The market logic is one pure Lua module (`core.lua`) with no game calls: time, storage and sending are passed
in. So it can run anywhere:

| Phase | Where the market runs | How clients reach it |
|---|---|---|
| 1 (built now) | Single player: in the player's own game. Network game: in the **host's** `sacred.exe` (the player whose game started the server). Its files live in the host's `mods\auction-house\` folder. | `gear.mp.send('ah', ..., 'host')` |
| 2 | In GameServer.exe, through the planned headless Gear (docs/GearServerMods.md, phase 2) | Same messages; the server answers as slot 0 |
| 3 (built) | In the C# GameServer's server Lua (SacredEngineRemake `scripts-examples/auction_house.lua`, core.lua inlined). In Closed Net with `--authoritative` the server owns hero saves and inventories, so it checks that a listed item really left the seller's inventory and saves the hero before each transfer counts (section 4). | gear.net channel `auction` (slot 0); falls back to the host's market on a stock GameServer.exe |

The client never assumes a slot: the market announces itself (`hello` with its slot and market id) and clients
address whoever announced. A market in the server would announce as slot 0. Nothing in the protocol depends on the
market being a player.

While the host is not in the game the market is offline: the panel says so; nothing is lost (it is on the host's
disk and comes back the next time they host).

## 3. The mod channel (new in Gear)

Mods on different computers talk over the game's own connection, so no extra port, firewall rule or server change is
needed and it works through the stock GameServer.exe and the C# remake alike.

- **Carrier:** the game's private chat message `0x003` (`[u32 target slot][UTF-16 text]`), which every GameServer
  relays to the target slot unchanged (original: case `0x4CA8AA`; the remake mirrors it: text up to 0xFE bytes, cut at
  the first UTF-16 NUL). Gear builds it with the engine's message builder (ENG `0x7D4220`, then the send queue
  `0x7D4860`) and recognizes its own frames on receive before the chat shows them, so players never see them.
- **Frame:** a private-use marker character, a header (channel message number, fragment index and count) and the data
  packed 15 bits per UTF-16 unit in the range `0x4000..0xBFFF` (no NUL, no surrogates). About 228 bytes a frame;
  larger messages are split and joined again (messages up to 64 KB). Gear paces the frames so it never floods the
  game's send queue.
- **Lua:** `gear.mp.send(channel, payload, to)` (payload a JSON-able table or a string; `to` a slot, `'host'` or
  `'all'`) and the event `mp_message(from, channel, payload)`. In single player, and for a message to oneself, the
  message loops back on the next tick, so a mod runs the same way everywhere.
- **Players:** `GearPlayer.name` (the hero's name), `key` (`name:class`, opaque), `gear.mp.is_host()`,
  `gear.mp.host_slot()`, `gear.mp.local_slot()`.

Trust: in client-trusted games (single player, LAN, Open Net) a modified client can lie (as it can edit its savegame
anyway). The market guarantees its own state is never duplicated or lost; it cannot make a cheating client honest.
Phase 3 can.

## 4. Atomic transfers, no duplicates

Three kinds of state: the market's file (on the host), the client's journal (on the player's computer) and the
hero in the game's memory (saved by the game later).

**Market file.** `market.json` holds everything (listings with their item data, mailboxes, wallets, sales
history, request log). Every change is applied in memory and written with `gear.save` (temporary file + rename, the
previous file kept as `market.bak.json`) *before* any answer goes out. If the write fails, the change is undone and the
request is refused. Requests that arrive in the same tick are applied together and written once (group commit).

**Requests are idempotent.** Every request that changes something carries a request id (`rid`, random per client
plus a counter). The market remembers the answer to every rid for 14 days; a repeated request (resent after a lost
answer, a reconnect or a restart) gets the same answer and changes nothing.

**Item into the market (sell):**
1. The client exports the item and writes it to its journal (`journal.json`, atomic): `{rid, item, price, days}`.
2. It takes the item out of the inventory (`gear.inv.remove`). If that fails, the journal entry is dropped.
3. It sends `sell` and repeats it (same rid) until an answer comes, also after a reconnect or a restart.
4. The market checks it (price, limits, fee, the item's type matches its data), stores the listing, writes the file,
   answers. On "refused" the client puts the item back from the journal (or keeps it there as "to collect" if the
   inventory is full). On "ok" the journal entry becomes a *receipt* (step 5).
5. **Crash check.** If the game is killed before it saved the hero, the savegame still has the item. At the next
   game load the client looks for each receipt's item in the loaded inventory (same exported bytes). Found means the
   save does not know the item left: the client tells the market (`revoke`), which takes the listing off (unsold: the
   item is simply dropped, since the save has it; already sold: logged as a duplicate for the host to see). Not found:
   the receipt is deleted. Single player works the same way with any older savegame.

**Gold into the market (wallet):** the same steps, with the hero's gold before and after in the receipt; at the next
load a gold amount equal to "before" means the deposit never reached the save, and the market takes it back out of
the wallet (a wallet may go negative and then blocks buying until it is paid).

**Buying** happens inside the market only: the price leaves the buyer's wallet, the item goes to the buyer's mailbox,
the price minus the cut to the seller's wallet, in one write. There is no partial purchase. The client shows the
gold it would need and offers to deposit the rest first.

**Out of the market (collect):** the client asks for a mailbox entry with a rid; the market marks it *delivering
to that rid* (written) and sends the item or gold; the client adds it to the inventory, writes the rid to its journal
and confirms; the market deletes the entry (written). A repeated collect with the same rid gets the same delivery
(the client's journal says it already has it, so it only confirms). A delivery that is never confirmed stays
reserved for that client and is sent again on its next request. If the game is killed after collecting but before a
save, the item is gone from that save: like the shared stash, loss is preferred over duplication. The panel says
"save after collecting".

**Identity.** A player is `name:class` (the hero), as for the other server-side mods, plus a secret per hero that the
client creates and keeps in its own folder: the first request binds it to the key, later requests must carry it, so
another player cannot join with the same hero name to empty a wallet. Later the realm account replaces the key
(`<realm id>:<account>`). On our GameServer the server names the player: `uid` (an opaque per-server hero id) and the
character name; no secret is needed (`from.verified`).

**The market on our GameServer** (`auction_house.lua`, net channel `auction`). The client looks for it for 12 s after
a network game starts (hellos only), then falls back to the host's market (the stock GameServer.exe has no channel).
The market state is in the mod's storage in chunks; every batch is written with `server.flush` (temporary file,
flushed to the disk, moved) before any answer of it goes out, requests that arrive meanwhile wait for the next batch,
and a failed write undoes the batch and refuses it.

**What each mode guarantees.**

| | Single player, LAN, Open Net (host or our server) | Closed Net on our server with `--authoritative` |
|---|---|---|
| Market state | never duplicated or lost: written before answering, rids, rollback on a failed write (host: `gear.save`; server: `server.flush`) | the same |
| Who is the truth for the hero | the client's savegame (the client can edit it) | the server's hero save at the lobby |
| Item into the market | the client takes it out, journals it; the crash check revokes a listing whose item is back in a reloaded save | the server must see the item leave its own hero state (0x13E pick, 0x167 destroy of that object, the same value records as the listing's data) and the lobby must confirm a hero save without it (`server.save_hero`, result 12) before the listing exists |
| Gold into the wallet | as items, with the hero's gold before/after | `prepare` first (the server notes the hero's gold), then the server must see exactly that much leave and the lobby confirm the save |
| Delivery out (collect, withdraw) | the entry is reserved for the rid; removed when the client confirms; a crash before the next save loses the item (never twice; "save after collecting") | removed only after the server saw the new item (its id, the delivery's records) in the hero's inventory, or the gold rise by the amount, and the lobby confirmed a save with it |
| Crash, reconnect | the client's crash check (revoke) | no revoke: the server's saved hero is the truth. A delivery handed out before the crash is given out again only if no hero save went out since (`server.hero_upload_time`); with a save since, an item found in the reloaded hero counts as collected, otherwise the entry stays reserved (logged, for the server owner) |
| A cheating client | can lie about what it gave or got (as it can edit its save) | cannot list or deposit what the server did not see leave its hero, cannot confirm a delivery the server did not see arrive; it can still make items or gold locally (the authoritative mode has no item/gold plausibility for that yet) |

Open in Closed Net (unverified with a real client): that Gear's `inv.remove` reaches the server as 0x13E + 0x167 and
`inv.add` as 0x16F/0x16C + 0x13F, that the export's value records equal the server's in order, and how soon the client
reports a gold change in its hero state (a deposit waits `verify_seconds`, 30 s, then is refused and the gold given
back). A gold delivery whose hero spent gold before the server saw the rise stays unconfirmed (reserved, not lost, not
doubled). A delivery is reserved with the server's own memory of the hero's gold at the time it went out; a server
restart in between leaves that gold delivery to the reconnect rule.

## 5. Market rules (host settings, Mods screen)

| Setting | Default | |
|---|---|---|
| `durations` | 1, 3, 7 days | Real time on the host's clock |
| `fee_per_day` | 0.5 % of the price (at least 1 gold) | Paid from the wallet when listing; kept on cancel and expiry (gold sink) |
| `sale_cut` | 5 % | Taken from the price when it sells |
| `max_listings_per_seller` | 20 | |
| `max_listings` | 400 | All sellers |
| `price` | 1 to 2,000,000,000 | |
| `allow_special` | off | Gold, quest items and (unless on) special items never sell |

No bids; a seller cannot buy their own listing; a buyer can buy items their class cannot use (it says so). Cancelling
sends the item to the mailbox. Expired listings go to the mailbox (checked every minute and at load). Mailbox entries
never expire.

## 6. Messages (channel `ah`)

Client to market: `hello`, `browse {q, sort, desc, page}`, `item {id}` (the item data of a listing, for tooltips;
cached by the client), `history {type}`, `sell {rid, data, price, days, meta}`, `cancel {rid, id}`,
`buy {rid, id, price}`, `deposit {rid, gold}`, `withdraw {rid, gold}`, `mail`, `collect {rid, mid}`,
`collected {rid}`, `revoke {rid}`, `mine`. Every request carries the player's key and secret.

Market to client: `info` (rules, wallet, counts), `page` (rows: id, type, name, quality, category, size, level,
classes, price, seller name, ends), `item`, `history` (last prices, median), `result {rid, ok, err, ...}`,
`deliver {rid, mid, data | gold}`, `mail`, `notify` (your item sold / expired).

`meta` is what the seller's client read from the item (display name, level, classes, quality, category, size,
tooltip text for the text search). The market checks what it can (the type id in the data's first bytes) and trusts
the rest.

## 7. The panel

From the chest window: an **Auction house** button next to the shared stash's (a layout panel of its own, movable in
the layout editor). Shown only while the chest window is open; the panel closes with it. No hotkey. Every element is a
widget, so the controller reaches all of it; text fields have an on-screen keyboard button.

- **Browse:** search text (matches the name and every tooltip line), category, quality, "usable by my class", level
  range, price range; sort by price, price per level, time left, newest, name, level or quality, ascending or
  descending; pages of 10 rows: icon, name in its quality colour, level, seller, time left, price, recent median,
  **Buy**. Hover: the game's own tooltip.
- **Sell:** the backpack and the chest as an icon grid (as in the stash); pick an item, enter a price (with
  -/+ steps and the median of recent sales of that type), pick the duration, see the fee and what you get after the
  cut, **List**.
- **My auctions:** your listings with time left, **Cancel**.
- **Mailbox:** items and gold waiting for you (sold, expired, cancelled, bought), **Collect** / **Collect all**; the
  wallet with **Deposit** / **Withdraw** gold.

## 8. Build plan

1. Gear (sacred-bild, branch `gear-auction`, merged from `gear-server-mods`): hero names, host detection, the mod
   channel, gold in network games, a larger `gear.save` limit; LuaLS annotations, kernel tests.
2. Mod `auction-house` (sacred-gear-mods): `core.lua` (market, pure Lua, unit tests), `client.lua` (journal,
   requests, crash check), `ui.lua` (panel), `main.lua`.
3. Single-player test (market in the same game) with `-gear-auto`, then a LAN host test with one instance (market and
   client in one game through the real channel loopback). Two-client test on John's second PC.
