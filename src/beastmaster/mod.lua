---@type GearModManifest
return {
    id = 'beastmaster',
    name = 'Beastmaster',
    version = '0.3.0',
    author = 'Sacred Gear',
    requires = {'sacred-theme'},
    description = 'Animals that travel with your hero: wolves, bears, boars, deer, horses, spiders, scorpions, crabs, lizards, birds ... every '
        .. 'animal of the game. Allies fight for you, have the level of the hero you play (so their damage grows with you) and grow bigger '
        .. 'every 18 levels up to level 216. Pets are drawn larger, follow you around, cannot be targeted or hurt and do nothing else. Each '
        .. 'species has its own base size (big monsters like spiders are drawn smaller). Pick them in the Beastmaster window (Ctrl+B, or the '
        .. "controller's mod menu). Single player only.",
    settings = {
        {id = 'max_allies', type = 'number', label = 'Allies at most', min = 0, max = 8, step = 1, default = 3, section = 'Allies',
            tooltip = 'How many fighting animals follow you at once'},
        {id = 'ally_level', type = 'number', label = "Ally level (% of your hero's level)", min = 10, max = 200, step = 5, default = 100, section = 'Allies',
            tooltip = '100: an ally has the level of a creature the game places for a hero of your level, so its health and damage grow with you. The level follows yours as you play'},
        {id = 'strength', type = 'number', label = 'Ally damage (%)', min = 10, max = 400, step = 10, default = 100, section = 'Allies',
            tooltip = 'Multiplies the damage an ally deals, on top of its level'},
        {id = 'grow_from', type = 'number', label = 'Ally size at level 1 (% of the base size)', min = 25, max = 200, step = 5, default = 75, section = 'Allies',
            tooltip = 'Allies grow in steps, one every 18 levels, from this size to the one below at level 216'},
        {id = 'grow_to', type = 'number', label = 'Ally size at level 216 (% of the base size)', min = 25, max = 250, step = 5, default = 125, section = 'Allies'},
        {id = 'engage', type = 'number', label = 'Allies fight enemies within (tiles)', min = 4, max = 25, step = 1, default = 12, section = 'Allies'},
        {id = 'max_pets', type = 'number', label = 'Pets at most', min = 0, max = 8, step = 1, default = 3, section = 'Pets',
            tooltip = 'How many pets follow you at once'},
        {id = 'pet_scale', type = 'number', label = 'Pet size (% of the base size)', min = 50, max = 250, step = 5, default = 130, section = 'Pets',
            tooltip = "Pets are drawn this much larger than their species' base size (needs a SacredBild with pets)"},
        {id = 'party_buffs', type = 'bool', label = "Companions' shared buffs also help the animals", default = true, section = 'Buffs',
            tooltip = 'The buffs a companion shares with the heroes (Steinhaut, Wieselflink ...) also go to your allies (all their effects: damage, attack speed, resistances ...) and to your pets (the speed part only)'},
        {id = 'buff_allies', type = 'number', label = 'Allies get (% of what a hero gets)', min = 0, max = 200, step = 10, default = 100, section = 'Buffs'},
        {id = 'buff_pets', type = 'number', label = 'Pets get (% of what a hero gets)', min = 0, max = 200, step = 10, default = 100, section = 'Buffs'},
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
