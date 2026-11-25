---@type GearModManifest
return {
    id = 'questhelper',
    name = 'Quest helper',
    version = '0.2.3',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'A panel with the quest items in your backpack (read here) and the quest records of your hero, with hints, '
        .. 'which the game server reports (Sacred.GameServer with scripts-examples/quest_helper.lua and hero data). '
        .. 'Limits: neither Gear nor the server can read the game\'s quest journal.',
    settings = {
        {id = 'notices', type = 'bool', label = 'Show change notices', default = true,
            tooltip = 'A short line on the screen when the server reports a new or changed quest record'},
        {id = 'refresh', type = 'number', label = 'Refresh while open (seconds)', min = 5, max = 120, step = 5, default = 30},
    },
    keys = {
        {id = 'toggle', label = 'Open the quest helper', default = 'ctrl+u'},
    },
    config = {},
}
