---@type GearModManifest
return {
    id = 'sacred-theme',
    name = 'Sacred theme',
    version = '0.4.0',
    author = 'Sacred Gear',
    description = 'The look of the game for the RmlUi screens of the other mods: the thick frame, game buttons, check orbs, sliders, tab bars, scroll bars and the controller prompts. Gear puts its stylesheet in front of every RmlUi document. The mods do not need it: without a theme they use the plain base style of Sacred Gear and look plainer; this one gives them the look of the game.',
    theme = 'theme.rcss',       -- the stylesheet Gear puts in front of every RmlUi document
    theme_dp = 'theme-dp.rcss', -- the same stylesheet for documents laid out in screen pixels (generated: tools/make_theme_dp.py)
    theme_sprites = 'sprites.rcss',        -- the .sprite-N classes (a rule per game picture): Gear links this sheet only into documents that mention `sprite-` (generated: tools/make_sprites_rcss.py)
    theme_sprites_dp = 'sprites-dp.rcss',
    exports = {'templates/'},              -- <link type="text/template" href="@sacred-theme/templates/screen.rml"/> in the documents of mods that `requires` this one
}
