---@type GearModManifest
return {
    id = 'custom-classes',
    name = 'Custom classes',
    version = '0.2.0',
    author = 'Sacred Gear',
    description = 'Heroes with a class of your own: a Seraphim body with Battle Mage fire, a Gladiator that casts. A class is a '
        .. 'profile on one of the eight hero bodies (skills, arts from any class, runes) made with the Sacred Class Editor or '
        .. 'by hand. Needs the mod on every computer in a LAN game.',
    settings = {
        {id = 'ask_new', type = 'bool', label = 'Offer a class to a new hero', default = true, section = 'Classes',
            tooltip = 'A hero at level 1 without a class gets the class window when the game starts'},
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
