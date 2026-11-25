---@type GearModManifest
return {
    id = 'custom-classes',
    name = 'Custom classes',
    version = '0.3.3',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'Heroes with a class of your own: a Seraphim body with Battle Mage fire, a Gladiator that casts. A class is a '
        .. 'profile on one of the eight hero bodies (skills, arts from any class, runes) made with the Sacred Class Editor or '
        .. 'by hand. Needs the mod on every computer in a LAN game.',
    settings = {
        {id = 'ask_new', type = 'bool', label = 'Offer a class to a new hero', default = true, section = 'Classes',
            tooltip = 'A hero at level 1 without a class gets the class window when the game starts'},
        {id = 'rune_drops', type = 'number', label = 'Rune drops (%)', min = 0, max = 300, step = 10, default = 100, section = 'Runes',
            tooltip = 'How often creatures drop the runes of custom arts (their drop weight in the art file times this; 0: never)'},
        {id = 'replace_master', type = 'bool', label = 'Combo master window with custom arts', default = true, section = 'Runes',
            tooltip = "When art files exist, the combo master shows this mod's window (combos and rune exchange with custom arts) instead of the game's"},
        {id = 'master_native', type = 'bool', label = 'Combo master in the look of the game', default = true, section = 'Runes',
            tooltip = "The combo master window is drawn like the game's own (frame, rune slots, buttons); off: the plain mod window"},
        {id = 'exchange_fee_2', type = 'number', label = 'Exchange fee for 2 runes (gold)', min = 0, max = 1000000, step = 100, default = 500, section = 'Runes'},
        {id = 'exchange_fee_3', type = 'number', label = 'Exchange fee for 3 runes (gold)', min = 0, max = 1000000, step = 100, default = 2000, section = 'Runes'},
        {id = 'exchange_fee_4', type = 'number', label = 'Exchange fee for 4 runes (gold)', min = 0, max = 1000000, step = 100, default = 5000, section = 'Runes'},
        {id = 'auto_remap', type = 'bool', label = 'Play another clip where the body has none', default = true, section = 'Classes',
            tooltip = 'A body without a clip for an art or spell plays one of its own (or the profile\'s motion remap); off: the art does nothing visible'},
        {id = 'debug', type = 'bool', label = 'Log the decisions', default = false, section = 'Classes'},
    },
    keys = {
        {id = 'window', label = 'Class window', default = 'ctrl+shift+c'},
    },
    config = {
        grant_every = 2.0,   -- seconds between two checks for arts that come with a level
    },
}
