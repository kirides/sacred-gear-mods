---@type GearModManifest
return {
    id = 'minimap',
    name = 'Minimap',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = "The game's own world map as a small overlay that follows the hero: a clipped square or circle with a gold frame and compass, several zoom levels, the trader symbols of the map. Move it in the layout editor (ALT).",
    settings = {
        {id = 'shape', type = 'choice', label = 'Shape', default = 'round', section = 'Look',
            choices = {{value = 'round', label = 'Circle'}, {value = 'square', label = 'Rectangle'}}},
        {id = 'width', type = 'number', label = 'Width (layout units)', min = 100, max = 400, step = 10, default = 200, section = 'Look',
            tooltip = 'A circle uses the width for both sides'},
        {id = 'height', type = 'number', label = 'Height (rectangle only)', min = 80, max = 300, step = 10, default = 150, section = 'Look'},
        {id = 'zoom', type = 'number', label = 'Zoom level (1 = widest)', min = 1, max = 6, step = 1, default = 3, section = 'Look',
            tooltip = 'The zoom keys and buttons change this as well. The map is centred on the hero at every level'},
        {id = 'opacity', type = 'number', label = 'Opacity (%)', min = 30, max = 100, step = 5, default = 90, section = 'Look'},
        {id = 'compass', type = 'bool', label = 'Compass letters (N, E, S, W)', default = true, section = 'Look'},
        {id = 'markers', type = 'bool', label = 'Show traders (merchant, blacksmith, combo master, horse trader)', default = true, section = 'Look'},
        {id = 'show', type = 'bool', label = 'Show the minimap', default = true, section = 'General'},
    },
    keys = {
        {id = 'toggle', label = 'Show / hide the minimap', default = ''},
        {id = 'zoom_in', label = 'Minimap: zoom in', default = ''},
        {id = 'zoom_out', label = 'Minimap: zoom out', default = ''},
    },
}
