---@type GearModManifest
return {
    id = 'beastmaster',
    name = 'Beastmaster',
    version = '0.1.0',
    author = 'Sacred Gear',
    requires = {'sacred-theme'},
    description = 'Animals that travel with your hero. Allies (wolves, bears, boars) follow, fight for you and grow with your '
        .. 'level. Pets (rabbits, crows, fawns ...) are drawn a bit larger, follow you around, cannot be targeted or hurt and do nothing '
        .. 'else. Pick them in the Beastmaster window (the controller\'s mod menu works too). Single player only.',
    settings = {
        {id = 'max_allies', type = 'number', label = 'Allies at most', min = 0, max = 8, step = 1, default = 3, section = 'Allies',
            tooltip = 'How many fighting animals follow you at once'},
        {id = 'strength', type = 'number', label = 'Ally strength (%)', min = 10, max = 400, step = 10, default = 100, section = 'Allies',
            tooltip = 'Their health and damage grow with the level of the hero you play; this scales it'},
        {id = 'engage', type = 'number', label = 'Allies fight enemies within (tiles)', min = 4, max = 25, step = 1, default = 12, section = 'Allies'},
        {id = 'max_pets', type = 'number', label = 'Pets at most', min = 0, max = 8, step = 1, default = 3, section = 'Pets',
            tooltip = 'How many pets follow you at once'},
        {id = 'pet_scale', type = 'number', label = 'Pet size (%)', min = 50, max = 250, step = 5, default = 130, section = 'Pets',
            tooltip = 'Pets are drawn this much larger than their wild kind (needs a SacredBild with pets)'},
        {id = 'follow', type = 'number', label = 'Follow distance (tiles)', min = 2, max = 12, step = 1, default = 4, section = 'Behaviour'},
    },
    keys = {
        {id = 'window', label = 'Beastmaster window', default = 'ctrl+b'},
    },
    config = {
        think = 0.3,
        debug = false,
    },
}
