---@type GearModManifest
return {
    id = 'item-compare',
    name = 'Item comparison',
    version = '0.2.2',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'Hover an item (backpack, chest, shop, the pad\'s cursor too) and a panel beside the game\'s tooltip shows what it changes compared with the item your hero wears in that slot: green for better, red for worse. Optionally for your companions too.',
    settings = {
        {id = 'enabled', type = 'bool', label = 'Compare items', default = true, section = 'General',
            tooltip = 'Show the comparison beside the item tooltip'},
        {id = 'companions', type = 'bool', label = 'Also compare with party members', default = true, section = 'General',
            tooltip = 'Single player with companions: also show what the item would change for the other heroes of the party that can wear it'},
        {id = 'placement', type = 'choice', label = 'Place the panel', default = 'tooltip', section = 'General',
            choices = {{value = 'tooltip', label = 'Beside the tooltip'}, {value = 'panel', label = 'At a fixed place (move it in the layout editor)'}},
            tooltip = 'Beside the game\'s tooltip, or in a panel you move with the layout editor (hold Alt)'},
        {id = 'max_blocks', type = 'number', label = 'Most items compared at once', min = 1, max = 6, step = 1, default = 4, section = 'General',
            tooltip = 'Rings and amulets have several slots, and every party member is a comparison of its own'},
        {id = 'verify_data', type = 'bool', label = 'Check the item data against the tooltip text', default = false, section = 'General',
            tooltip = 'For tests: compare every result with one made from the tooltip text alone'},
    },
    keys = {
        {id = 'toggle', label = 'Switch the comparison on / off', default = ''},
    },
}
