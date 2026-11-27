# Sacred theme

The shared look of the RmlUi screens of the other mods in this repository: the game's thick frame, `game-button`, `game-check`, `game-slider`,
the tab bar (`.tabbar`), the game's scroll bar, the controller prompts (`.padkey`) and the game's fonts (`.font-game`). Gear puts `theme.rcss`
in front of every RmlUi document, so a mod's own stylesheet only adds what is special about its screen.

It has no code and no settings, and the other mods do not need it: without a theme, Sacred Gear gives every RmlUi document a plain base style (dark panels, gold edges, simple buttons, check boxes and sliders), so the mods run and read well but look plainer. With this mod they look like the game.

## Sprites

Every UI image of the game is a class: `.sprite-N` (N = the image number, as in `gear:image/N`) gives an element that image at its natural size, e.g. `<span class="sprite sprite-218"></span>`. The classes are generated (`tools/make_sprites_rcss.py`) into `sprites.rcss` (and `sprites-dp.rcss`), not into `theme.rcss`: they are nine tenths of the theme's rules and RmlUi keeps a copy of every rule in every document that links the sheet. Sacred Gear links the sprite sheet only into documents whose markup mentions `sprite-` (a class that Lua adds later, with the name nowhere in the markup, needs `gear.ui.rml.load(path, {sprites = true})`; `sprites = false` never links it). The [Sprite browser](../../docs/mods/sprite-browser.md) mod lists them all with their numbers.

## Shared templates

The mod exports `templates/` (`mod.lua`: `exports`), so the documents of a mod that says `requires = {'sacred-theme'}` can use them (`<link type="text/template" href="@sacred-theme/templates/screen.rml"/>`, then the template by its name). They are plain flowing boxes in the classes of this stylesheet, no position anywhere but the popup of the drop-down:

| File | Template | What it is |
|---|---|---|
| `screen.rml` | `sacred-screen` | A **body template**: the game's window with a title bar (the model's `title`, a close button with the id `close-x`) and a body that grows with its content. `<body data-model="model" template="sacred-screen">`; the width is the mod's own (`.sacred-screen { width: 460dp; }`). |
| `group.rml` | `sacred-group` | A framed section: `<template src="sacred-group"><p class="heading">Title</p> ... </template>`. |
| `dropdown.rml` | `sacred-dropdown` | The game's drop-down button and its list, driven by the model (`key`, `title`, `label`, `dd`, `options`); put it inside `<div class="dd" data-class-open="dd == key">`. |

A template takes content and the data model, not attributes, so what a window needs on its own element (`data-panel` for moving it, its ids) stays in the mod's markup. Demo and test: `tests/sandbox/theme_templates.ps1` runs `tests/sandbox/theme-templates-demo` in Sacred Gear's UI sandbox at 1600x900. Hot reload (`mods\.rml-hot`) follows the template files like any file a document reads.

## Core widgets

The widgets of Sacred Gear's `gear.kit` (window, tabs, buttons, check boxes, sliders, rows, bars, lists, the confirm dialog) are plain markup with the classes this stylesheet styles, so every mod that builds its screen from the kit gets this look from here, and Gear's plain base style without it. Add a new widget by giving `gear.kit` the markup and this stylesheet its classes; a mod never needs to carry a look of its own.

## Icons

The theme ships a bigger icon set than Sacred Gear's built-in one (`icons.ttf`, 172 icons of Google's Material Symbols Sharp, Apache License 2.0; `<span class="icon icon-swords"></span>`). Without this mod the same classes work for the 85 icons Gear has built in, so a mod that only needs those looks right everywhere. To add or update icons edit `tools/icons.txt` and run `python tools/make_icons.py <MaterialSymbolsSharp-Regular.ttf>` (writes `icons.ttf` and the ICONS block of `theme.rcss`, then `theme-dp.rcss`); no new Gear is needed.

## On-screen keyboard

`gear.kit.osk` (Sacred Gear) is the shared on-screen keyboard of the mods: a small window with the typed text and rows of plain bordered keys (`.kit-osk`, `button.osk-key`; a thin gold edge on a dark fill, no game orbs, so forty keys stay readable and the pad's cursor shows on the bright edge), a number pad for amounts, and Shift, Space, Backspace, Clear, Paste and Done. This stylesheet gives it the look of the game; without the mod Gear's base style draws the same classes plainer. The mods open it from a `keyboard` icon button (`class="ibtn kit-kbd"`), which is shown only while the controller is the player's input (A on the field opens it too). Details: Gear docs, `docs/RmlKit.md`.

## Text fields

`<input type="text" class="field">` (and `textarea`) support Ctrl+A / C / X / V, Shift+arrows / Home / End, click-drag and double-click selection; the theme colours the selection (`input.field selection`). Without this mod Gear's base style gives a plain highlight, so mods need no code or markup of their own. Details: Gear docs, "Text fields of RmlUi documents".
