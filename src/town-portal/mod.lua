---@type GearModManifest
return {
    id = 'town-portal',
    name = 'Town Portal',
    version = '0.1.0',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the window (the manager offers it on install)
    requires = {'sacred-theme'},
    description = 'The Town Portal Potion: drinking it saves where you stand and opens the list of the game\'s teleport portals (the ones you have found), '
        .. 'made again as a window you can use with the mouse, the keys or the controller. You arrive at the portal you pick, a portal of the mod opens there '
        .. 'for you, and stepping through it takes you back to the spot you left and closes it. The potion is sold by merchants. '
        .. 'The portal and the spot are kept with the savegame. Single player only.',
    settings = {
        {id = 'in_shops', type = 'bool', label = 'Merchants sell the potion', default = true, section = 'Potion',
            tooltip = 'When the game stocks a merchant that sells potions (the Miscellaneous tab), the mod may add potions to it'},
        {id = 'shop_chance', type = 'number', label = 'Chance a merchant has potions (%)', min = 0, max = 100, step = 5, default = 70, section = 'Potion'},
        {id = 'shop_count', type = 'number', label = 'Potions a merchant has at most', min = 1, max = 5, step = 1, default = 2, section = 'Potion'},
        {id = 'block_in_combat', type = 'bool', label = 'Not while enemies are about', default = true, section = 'Rules',
            tooltip = 'As the game\'s own teleport potions of ReBorn: the potion does nothing while the engine says enemies are near'},
    },
    keys = {
        {id = 'read', label = 'Drink a Town Portal Potion from the backpack', default = 'ctrl+shift+t'},
        {id = 'close', label = 'Close the portal list', default = ''},
    },
    config = {},
}
