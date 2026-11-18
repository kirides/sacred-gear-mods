---@type GearModManifest
return {
    id = 'enhanced-chat',
    name = 'Enhanced Chat',
    version = '1.0.0',
    author = 'kirides',
    description = 'A chat window in place of the lines at the top of the screen that fade and are gone: it keeps the '
        .. 'last lines of the session to scroll back through, has tabs for global, private and system messages (and a '
        .. 'filter by player in a network game) and shows item names in their rarity colour, also for the drops near '
        .. 'your hero. Move and resize it with the layout editor. Mouse, keyboard and controller.',
    settings = {
        {id = 'visible', type = 'bool', label = 'Show the chat window', default = true,
         tooltip = 'Off: the game shows its own chat lines again'},
        {id = 'hide_in_singleplayer', type = 'bool', label = 'Hide in Singleplayer', default = true,
         tooltip = 'No chat window in a single player game (the game shows its own lines there); network games are unaffected'},
        {id = 'replace_overlay', type = 'bool', label = 'Hide the game\'s own chat lines', default = true,
         tooltip = 'While the chat window shows, the game adds no lines at the top of the screen'},
        {id = 'lines', type = 'number', label = 'Lines kept', min = 50, max = 500, step = 50, default = 200},
        {id = 'font_size', type = 'number', label = 'Text size', min = 10, max = 20, step = 1, default = 13},
        {id = 'opacity', type = 'number', label = 'Background opacity', min = 0, max = 255, step = 5, default = 140},
        {id = 'timestamps', type = 'bool', label = 'Show the time of each line', default = false},
        {id = 'loot', type = 'choice', label = 'Drops near the hero', default = 'rare',
         tooltip = 'A line in the item\'s colour when such an item drops near your hero (System tab)',
         choices = {{value = 'off', label = 'Off'}, {value = 'magic', label = 'Magic and better'},
                    {value = 'rare', label = 'Rare and better'}, {value = 'set', label = 'Set and unique'},
                    {value = 'unique', label = 'Unique only'}}},
        {id = 'loot_radius', type = 'number', label = 'Drops: radius (tiles)', min = 5, max = 60, step = 5, default = 25},
    },
    keys = {
        {id = 'toggle', label = 'Show / hide the chat window', default = ''},
        {id = 'next_tab', label = 'Next chat tab', default = ''},
    },
}
