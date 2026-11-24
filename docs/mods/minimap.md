# Minimap

The game's own world map as a small overlay that follows the hero: the same map pictures the world map window shows,
cut to a rectangle or a circle, with a gold frame, compass letters and the trader symbols of the map.

- **Centred on the hero** at every zoom level. **Six zoom levels** (1 is the widest): the keys *Minimap: zoom in / out*
  (unbound by default, set them in the Mods screen), the **+ / -** buttons that appear while the mouse is over the map,
  the setting *Zoom level*, and the controller's mod menu (**LT + LB**, then *Minimap: zoom in* / *zoom out* / *show / hide*).
- **Shape and size:** *Circle* or *Rectangle*, width and height, opacity, compass letters, trader symbols (merchant,
  blacksmith, combo master, horse trader; needs a SacredBild with `gear.game.map_markers`).
- **Position:** the layout editor (ALT) moves it like any other mod panel.
- Outdoors only. In dungeons the panel is hidden.

## How it works

The map is the 8 x 11 tiles `UI_WORLDMAP*.TGA` (Underworld above Ancaria), drawn through `gear:texture/`. The hero's tile
position goes to the picture with the engine's own world-to-map transform. An element cannot be cut round, so the circle is
stacked from thin clipping rows. The geometry is in `src/minimap/projection.lua` (`luajit tests/minimap_test.lua`).

Not tested in the game yet: the transform comes from the engine remake's notes of the game's code; the first line of the log
(`minimap: hero at world ...`) shows where the mod puts the hero on the map.
