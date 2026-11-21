---@type GearModManifest
return {
    id = 'sector-tools',
    name = 'Sector tools',
    version = '0.1.0',
    author = 'kirides',
    requires = {'sacred-theme'},
    description = 'For server admins: shows the sector you stand in (id, grid cell, position), draws sector boundaries on the ground, records the sectors you walk through into a named area and copies a ready-to-paste line for the server\'s world_events.lua.',
    settings = {
        {id = 'area_name', type = 'text', label = 'Area name', default = 'My area', max_length = 40, section = 'Recording',
         tooltip = 'The name of the area you record; the id in the config line is made from it ("Silver Creek" is silver_creek)'},
        {id = 'radius', type = 'number', label = 'Circle radius (world units)', min = 0, max = 8000, step = 100, default = 1500,
         tooltip = 'For the "Circle here" button: a point within this distance of where you stood counts too. A tile is about 54 units, a sector 3435.'},
        {id = 'near', type = 'number', label = 'Plus neighbours within (sector cells)', min = 0, max = 3, step = 1, default = 0,
         tooltip = 'The server adds every sector within this many grid cells of the recorded ones (needs its game data)'},
        {id = 'labels', type = 'bool', label = 'Sector boundaries on the ground', default = true, section = 'Overlay',
         tooltip = 'While the tools are shown: dotted lines where a sector ends, with the number of the sector on each side (when known) and its grid cell'},
        {id = 'anchor_x', type = 'number', label = 'Ground labels: move right', min = -200, max = 200, step = 2, default = 0,
         tooltip = 'Where the hero stands on the screen is a guess; shift the lines if they do not match the ground'},
        {id = 'anchor_y', type = 'number', label = 'Ground labels: move down', min = -200, max = 200, step = 2, default = 0},
    },
}
