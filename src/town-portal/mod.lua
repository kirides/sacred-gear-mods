---@type GearModManifest
return {
    id = 'town-portal',
    name = 'Town Portal',
    version = '0.3.0',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the window (the manager offers it on install)
    requires = {'sacred-theme'},
    description = 'The Town Portal Scroll: reading it saves where you stand and opens the list of the game\'s teleport portals (the ones you have found), '
        .. 'made again as a window you can use with the mouse, the keys or the controller. You arrive at the portal you pick, a portal of the mod opens there '
        .. 'for you, and stepping through it takes you back to the spot you left and closes it. The scroll is sold by merchants. You can add points of your own (the window, or a custom_teleports.lua). '
        .. 'The portal and the spot are kept with the savegame. Single player only.',
    settings = {
        {id = 'in_shops', type = 'bool', label = 'Merchants sell the scroll', default = true, section = 'Scroll',
            tooltip = 'When the game stocks a merchant that sells potions (the Miscellaneous tab), the mod may add scrolls to it'},
        {id = 'shop_chance', type = 'number', label = 'Chance a merchant has scrolls (%)', min = 0, max = 100, step = 5, default = 70, section = 'Scroll'},
        {id = 'shop_count', type = 'number', label = 'Scrolls a merchant has at most', min = 1, max = 5, step = 1, default = 2, section = 'Scroll'},
        {id = 'block_in_combat', type = 'bool', label = 'Not while enemies are about', default = true, section = 'Rules',
            tooltip = 'As the game\'s own teleport potions of ReBorn: the scroll does nothing while the engine says enemies are near'},
    },
    keys = {
        {id = 'read', label = 'Read a Town Portal Scroll from the backpack', default = 'ctrl+shift+t'},
        {id = 'points', label = 'Edit your own teleport points (add / remove)', default = 'ctrl+shift+p'},
        {id = 'close', label = 'Close the portal list', default = ''},
    },
    config = {},
}
