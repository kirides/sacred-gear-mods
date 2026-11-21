# Sacred theme

The shared look of the RmlUi screens of the other mods in this repository: the game's thick frame, `game-button`, `game-check`, `game-slider`,
the tab bar (`.tabbar`), the game's scroll bar, the controller prompts (`.padkey`) and the game's fonts (`.font-game`). Gear puts `theme.rcss`
in front of every RmlUi document, so a mod's own stylesheet only adds what is special about its screen.

It has no code and no settings. The mods that use it list it in `requires`, so switching one of them on switches this on too.
