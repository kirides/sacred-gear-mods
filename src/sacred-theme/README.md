# Sacred theme

The shared look of the RmlUi screens of the other mods in this repository: the game's thick frame, `game-button`, `game-check`, `game-slider`,
the tab bar (`.tabbar`), the game's scroll bar, the controller prompts (`.padkey`) and the game's fonts (`.font-game`). Gear puts `theme.rcss`
in front of every RmlUi document, so a mod's own stylesheet only adds what is special about its screen.

It has no code and no settings, and the other mods do not need it: without a theme, Sacred Gear gives every RmlUi document a plain base style (dark panels, gold edges, simple buttons, check boxes and sliders), so the mods run and read well but look plainer. With this mod they look like the game.

## Sprites

Every UI image of the game is a class: `.sprite-N` (N = the image number, as in `gear:image/N`) gives an element that image at its natural size, e.g. `<span class="sprite sprite-218"></span>`. The classes are generated (`tools/make_sprites_rcss.py`); the [Sprite browser](../../docs/mods/sprite-browser.md) mod lists them all with their numbers.

## Core widgets

The widgets of Sacred Gear's `gear.kit` (window, tabs, buttons, check boxes, sliders, rows, bars, lists, the confirm dialog) are plain markup with the classes this stylesheet styles, so every mod that builds its screen from the kit gets this look from here, and Gear's plain base style without it. Add a new widget by giving `gear.kit` the markup and this stylesheet its classes; a mod never needs to carry a look of its own.

## Icons

The theme ships a bigger icon set than Sacred Gear's built-in one (`icons.ttf`, 172 icons of Google's Material Symbols Sharp, Apache License 2.0; `<span class="icon icon-swords"></span>`). Without this mod the same classes work for the 85 icons Gear has built in, so a mod that only needs those looks right everywhere. To add or update icons edit `tools/icons.txt` and run `python tools/make_icons.py <MaterialSymbolsSharp-Regular.ttf>` (writes `icons.ttf` and the ICONS block of `theme.rcss`, then `theme-dp.rcss`); no new Gear is needed.
