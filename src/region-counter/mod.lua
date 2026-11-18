---@type GearModManifest
return {
    id = 'region-counter',
    name = 'Region counter',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'The kills a region needs before its Region Boss quest comes: set your own number, and keep the progress when you leave the region, teleport, save or quit.',
    settings = {
        {id = 'kill_percent', type = 'number', label = 'Kills needed (% of vanilla)', min = 5, max = 300, step = 5, default = 100,
            section = 'General', tooltip = "100 is the game's own number. 50 halves the kills a region needs, 200 doubles them. Progress is kept as a share when you change it"},
        {id = 'keep_progress', type = 'bool', label = 'Keep progress between regions and sessions', default = true,
            section = 'General', tooltip = 'The game forgets the count when you leave a region and never saves it. Switched on, the count of every region is kept per hero'},
    },
}
