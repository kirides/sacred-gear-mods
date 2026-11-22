# Sacred theme

The shared look of the RmlUi screens of the other mods in this repository: the game's thick frame, `game-button`, `game-check`, `game-slider`,
the tab bar (`.tabbar`), the game's scroll bar, the controller prompts (`.padkey`) and the game's fonts (`.font-game`). Gear puts `theme.rcss`
in front of every RmlUi document, so a mod's own stylesheet only adds what is special about its screen.

It has no code and no settings, and the other mods do not need it: without a theme, Sacred Gear gives every RmlUi document a plain base style (dark panels, gold edges, simple buttons, check boxes and sliders), so the mods run and read well but look plainer. With this mod they look like the game.

## Sprites

Every UI image of the game is a class: `.sprite-N` (N = the image number, as in `gear:image/N`) gives an element that image at its natural size, e.g. `<span class="sprite sprite-218"></span>`. The classes are generated (`tools/make_sprites_rcss.py`); the [Sprite browser](../../docs/mods/sprite-browser.md) mod lists them all with their numbers.
