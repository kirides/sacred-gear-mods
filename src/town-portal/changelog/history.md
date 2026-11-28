## v0.2.0 (2026-11-28)

- Fixed: merchants now stock the Town Portal Potion. The game's shop refuses item types from 0x2000, so the potion's type id moved to 6150 (a potion made earlier with id 16000 no longer exists).
- Fixed: a missing `custom_teleports.lua` no longer fills the log; the file is read once when the mod starts (switch the mod off and on, or restart, after editing it).
- Improved: the portal NPC shows the game's talk cursor when the mouse is over it (needs Sacred Gear 0.17.0).

## v0.1.0 (2026-11-27)

- New: the Town Portal Potion, an item of its own. Drinking it (from the backpack or with the `Ctrl+Shift+T` key) saves where you stand and opens the list of the game's teleport portals you have found, as a window for the mouse, the keys and the controller.
- New: picking a portal takes you there, uses the potion up and opens a portal of its own beside you; talking to it and stepping through takes you back to the spot you left and closes it.
- New: merchants that sell potions may stock it (settings: chance and number); the potion does nothing while enemies are near (a setting).
- New: the spot and the portal are kept with the savegame.
- New: points of your own in the list: add the spot where you stand under a name and remove it again in the window (`Ctrl+Shift+P`), or list points in an optional `custom_teleports.lua`.
- Needs Sacred Gear 0.16.0 or newer (for the potion's item type).
