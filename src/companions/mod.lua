---@type GearModManifest
return {
    id = 'companions',
    name = 'Companions',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'A party of heroes in single player: recruit companions of any class, each with their own inventory, '
        .. 'equipment, attributes, skills, combat arts and experience. Click a portrait (or use the controller\'s mod menu) '
        .. 'to play that hero; the others follow and fight on their own, with their combat arts and spells.',
    settings = {
        {id = 'max_companions', type = 'number', label = 'Companions at most', min = 1, max = 14, step = 1, default = 3, section = 'Party',
            tooltip = 'How many companions the party window lets you recruit'},
        {id = 'start_level', type = 'choice', label = 'A new companion starts', default = 'leader', section = 'Party',
            choices = {{value = 'leader', label = 'With the experience of the hero you play'}, {value = 'half', label = 'With half of it'}, {value = 'one', label = 'At level 1'}},
            tooltip = 'Their experience comes through the game\'s own level ups, so they have skill points to spend'},
        {id = 'share_xp', type = 'number', label = 'Shared experience (%)', min = 0, max = 100, step = 5, default = 100, section = 'Party',
            tooltip = 'Experience a party hero gains from kills and quests also goes to the others nearby, times this'},
        {id = 'share_radius', type = 'number', label = 'Shared within (tiles, 0: anywhere)', min = 0, max = 100, step = 5, default = 40, section = 'Party'},
        {id = 'revive', type = 'bool', label = 'Fallen companions get up after the fight', default = true, section = 'Party',
            tooltip = 'At your side with a quarter of their health, once no enemy is near (12 s at the latest). Off: the game removes a fallen companion, with what they carry'},
        {id = 'hardcore', type = 'bool', label = 'Hardcore companions: the fallen stay gone', default = false, section = 'Party',
            tooltip = 'A companion who falls is gone for good, with what they carry. A savegame written before the fall still has them; one written after does not. Off: fallen companions get up (setting above)'},
        {id = 'switch_on_death', type = 'bool', label = 'Play a living companion when your hero falls', default = true, section = 'Party'},
        {id = 'portraits', type = 'bool', label = 'Companion portraits', default = true, section = 'Party',
            tooltip = 'Portraits of the companions under the game\'s own, at the top right; a click plays that hero'},
        {id = 'portraits_follow', type = 'bool', label = 'Portraits under the game\'s own', default = true, section = 'Party',
            tooltip = 'The companions continue the column of the game\'s portraits at the right edge. Off: the layout editor (hold Alt) places them'},
        {id = 'ai', type = 'bool', label = 'Companions act on their own', default = true, section = 'Behaviour',
            tooltip = 'Off: the companions stand where they are'},
        {id = 'behaviour', type = 'choice', label = 'Default behaviour', default = 'aggressive', section = 'Behaviour',
            choices = {{value = 'aggressive', label = 'Aggressive (fight what comes near)'}, {value = 'defensive', label = 'Defensive (protect the hero you play)'}, {value = 'passive', label = 'Passive (only follow)'}},
            tooltip = 'Each companion can have their own in the party window'},
        {id = 'potions', type = 'number', label = 'Drink a healing potion below (% health, 0: never)', min = 0, max = 90, step = 5, default = 30, section = 'Behaviour',
            tooltip = "From the companion's own backpack, as Space does for you"},
        {id = 'heal_priority', type = 'choice', label = 'Healing spells first for', default = 'hero', section = 'Behaviour',
            choices = {{value = 'hero', label = 'The hero you play, then themselves'}, {value = 'lowest', label = 'Whoever has the least health'}, {value = 'self', label = 'Themselves, then the hero you play'}},
            tooltip = 'Genesung, Spirituelle Heilkraft: the companion casts the spell, and the hero it is meant for gets its health'},
        {id = 'heal_below', type = 'number', label = 'Heal a hero below (% health)', min = 10, max = 95, step = 5, default = 60, section = 'Behaviour'},
        {id = 'buffs', type = 'choice', label = 'Buffs and auras', default = 'combat', section = 'Behaviour',
            choices = {{value = 'combat', label = 'In fights, again when they run out'}, {value = 'always', label = 'Whenever they are ready'}},
            tooltip = 'Steinhaut, Wieselflink, Sturm und Drang ...: the game lets a companion cast these only on themselves'},
        {id = 'use_abilities', type = 'bool', label = 'Use combat arts and spells', default = true, section = 'Behaviour'},
        {id = 'follow', type = 'number', label = 'Follow distance (tiles)', min = 2, max = 12, step = 1, default = 5, section = 'Behaviour'},
        {id = 'engage', type = 'number', label = 'Fight enemies within (tiles)', min = 4, max = 25, step = 1, default = 12, section = 'Behaviour'},
    },
    keys = {
        -- Not F8: the game's quick load. PageDown / PageUp are also what SacredBild's controller actions "Next / Previous
        -- party hero" press.
        {id = 'next', label = 'Play the next hero of the party', default = 'pagedown'},
        {id = 'previous', label = 'Play the previous hero of the party', default = 'pageup'},
        {id = 'window', label = 'Party window (recruit, tactics)', default = 'home'},
    },
    config = {
        portraits_x = 932,  -- the portrait column's place in the 1024x768 layout when it does not follow the game's
        portraits_y = 260,
        think = 0.25,       -- seconds between two thinks of a companion
        debug = false,      -- log the AI's decisions
    },
}
