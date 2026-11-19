---@type GearModManifest
return {
    id = 'spawn-rate',
    name = 'Spawn rate',
    version = '1.0.1',
    author = 'kirides',
    description = 'Multiplies the creatures the game spawns, from 1x (the game as it is) up to 100x. Every creature the world creates for you brings extra ones of its kind with it. Single player only; safeguards keep the frame rate up.',
    settings = {
        {id = 'rate', type = 'number', label = 'Spawn rate (x)', min = 1, max = 100, step = 1, default = 1,
         section = 'How many',
         tooltip = '1 is the game as it is. 10 means ten creatures where the game spawns one: nine extra ones of the same kind appear next to it. Applies to creatures that are hostile to your hero; single player only'},
        {id = 'max_extra', type = 'number', label = 'Most extra creatures at once', min = 0, max = 1000, step = 10, default = 200,
         section = 'Safeguards',
         tooltip = 'The extra creatures alive at the same time never exceed this (0 = no limit, not advised). Extras that die or vanish make room for new ones'},
        {id = 'budget', type = 'number', label = 'Extra creatures per frame', min = 1, max = 20, step = 1, default = 4,
         tooltip = 'How many extra creatures are made in one frame at most. The rest waits in a queue, so entering a crowded sector does not freeze the game. The mod makes fewer while the frame rate is low'},
    },
}
