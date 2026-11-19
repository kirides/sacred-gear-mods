# Names and IDs

The game's texts follow the player's language: "Orkkrieger" in a German game, "Orc Warrior" in an English one. A name is
therefore something to **show**, never something to **save or compare**. The rule for every mod of this repository, and for
mods written against it (the long form is in the Sacred Gear docs, *Names and IDs*):

| What | Save and compare | Show and search |
|---|---|---|
| A creature or item type | the type id (`creature:type()`, `item.type`, `type` in `drops.roll` and the kill event) | `gear.data.object_types:label(id)`, `creature:display_name()`, the kill event's `display_name`; items also the first line of `gear.ui.item_tooltip_text` |
| A family of creatures ("orc") | the family word, documented as a pattern for the model name, never shown as a name | the family's localized names |
| A kill, event or bounty target | a list of type ids (`types`), as the local bounty board and the world events do | the localized names of those ids |
| A log entry (loot log, chat) | the id next to a text snapshot; the text is only for entries that have no id | the label of the id, the snapshot when there is none |

## In a mod

- **Pickers search by name.** `gear.lookup.search('creature_type', text)` matches the localized and the internal names and
  returns `{id, name, internal}`; `'creature'` returns families, `'item'` items. Save `id`.
- **Show with a fallback.** `object_types:label(id)` is the localized name, else the internal name, else `type N`, and never
  nil. A mod that must run on an older Gear calls it inside `pcall` and falls back to `type_name`.
- **Migrate on load.** A saved name from an older version turns into an id with `object_types:resolve(name)` (it takes an id,
  an internal name or a localized creature name). The new form is written at the next save. A name that resolves to nothing is
  kept as it was, so an update that adds the type picks it up. Readers accept both forms for good.
- **Servers.** What a server understands stays what it understands. Where a payload carries a name, send the id next to it.

## What the mods keep

| Mod | Saved before | Saved now |
|---|---|---|
| Bounty (custom bounties, the hero's board) | family words in `names` | `names` for families, `types` (ids) for single creatures chosen by name; a file with `ORC_WARRIOR.GRN` or a localized name in `names` migrates to `types` |
| Bounty item rewards | `{id, name}` | the same; the name is only a fallback, the label of the id is shown |
| Bounty daily and weekly quests | family words in `names` | unchanged: a family is a pattern, not a name |
| World events | `names`, `types`, wave kinds by name | the same format (it always took ids); the default `events.json` of a first run names wave creatures by id; hook texts show a type id as its localized name |
| Loot log | the source creature as text (`src`) | the type id (`st`); old `src` text is still shown |
| Twitch (twi_sacred) | `config.monsters` names | ids or names (internal or localized) |
| Shared stash, auction house, build sharer, chat | the item's tooltip name as a snapshot | unchanged: an item's own name (a generated "Worn Greaves of Pain") is not derivable from its type, so the snapshot stays the display text |
