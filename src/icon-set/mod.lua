---@type GearModManifest
return {
    id = 'icon-set',
    name = 'Icon Set drops',
    version = '1.0.0',
    author = 'kirides',
    description = 'Lets the six pieces of the Icon Set (the statues, the grail and the shell: the Flaming Feet set) drop from creatures of any level, by turning a small share of equipment drops into Icon Set pieces.',
    settings = {
        {id = 'chance', type = 'number', label = 'Chance per equipment drop (%)', min = 0, max = 20, step = 0.1, default = 1,
         section = 'How often',
         tooltip = 'The share of a creature\'s random equipment drops that becomes one of the six Icon Set pieces instead (0 = off)'},
        {id = 'min_level', type = 'number', label = 'Lowest creature level', min = 1, max = 200, step = 1, default = 1,
         tooltip = 'Creatures below this level never drop an Icon Set piece through this mod'},
        {id = 'per_level', type = 'number', label = 'Extra chance per level (%)', min = 0, max = 1, step = 0.01, default = 0,
         tooltip = 'Added to the chance for every creature level above the lowest level: 0.05 makes level 100 about 5 percentage points likelier'},
    },
}
