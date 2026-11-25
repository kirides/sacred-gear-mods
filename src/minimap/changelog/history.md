## v0.2.2 (2026-11-25)

- Improved: the minimap costs much less time per frame while the hero stands still: it keeps its map tiles as they are until the hero moves, the zoom changes or a setting changes (about 0.15 ms less per frame and far less memory churn).

## v0.2.1 (2026-11-25)

- New: the map choice "Game" shows the pictures of the game's own TAB map, sector by sector, centred on the hero. The other two are now named "High-Res" (the render, as before) and "World Map" (the painted world map).
- New: eight zoom levels (were six).
- New: settings "Hero marker size" and "Trader symbol size". The hero marker is smaller by default (6, was 10).

## v0.2.0 (2026-11-25)

- New: setting "Map": Render or Original. Render is the whole world drawn from the game's data (terrain, water, trees, buildings, no creatures), lined up with the game's own map; where the world has no data (its edge, the sea beyond it) the game's own map shows through, matched to the render's colours. Original is the painted map as before. Render is the default.
- Under the hood: the render ships as 256 px JPEG tiles in three resolutions (about 16.8 MB, in one `tiles.gpak` instead of 1848 files; needs a Sacred Gear with packs), chosen by zoom level. `tools/make_minimap_tiles.py` rebuilds them from SacredEngineRemake's `--mega` output.
- Fixed: a faint horizontal hairline between two rows of map tiles (tiles now overlap by one unit, and the map has a dark base).
- Improved: the map tiles around the view are loaded ahead of time (one per frame), and tiles that stay out of that ring for a moment are released at once instead of piling up (reference counted textures; needs a Sacred Gear with `gear.ui.texture`, older ones load tiles as before).

## v0.1.3 (2026-11-25)

- Fixed: the minimap always stays fully on screen, at any resolution or UI scale, even if a saved layout was made on another screen.
- Improved: without a saved place it now starts left of the game's own minimap column, clear of the party portraits.
- Improved: the zoom controls are plain glow icon buttons (minus, level, plus) with even spacing, shown while the mouse is over the map.

## v0.1.2 (2026-11-25)

- New: the mod manager offers to install the Sacred theme along with this mod (optional).

## v0.1.1 (2026-11-25)

- Improved: the hero marker is now a small gold diamond.
- Fixed: the map stays inside the circle or rectangle frame.
- Fixed: trader symbols keep a consistent size on the minimap.

## v0.1.0 (2026-11-25)

- First release: a small world map overlay that follows your hero.
- New: Circle or rectangle shape, gold frame, optional compass letters.
- New: Six zoom levels, changed in settings or with the zoom keys.
- New: Trader symbols for merchant, blacksmith, combo master and horse trader.
