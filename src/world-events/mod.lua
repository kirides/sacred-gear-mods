---@type GearModManifest
return {
    id = 'world-events',
    name = 'World events',
    version = '0.1.0',
    author = 'kirides',
    description = 'Shows the game server\'s world event (a realm-wide goal such as "slay 1000 orcs in 2 hours") as a small movable indicator (a pill with progress and time rings). Needs a Sacred Gear game server with the world_events script.',
    settings = {
        {id = 'visibility', type = 'choice', label = 'Show the bar', default = 'always', section = 'Progress bar',
         choices = {{value = 'always', label = 'Always while an event runs'}, {value = 'alt', label = 'Only while Alt is held'}},
         tooltip = 'Move it with the layout editor (hold Alt, then "Edit layout"). Details show on hover or while Alt is held. The controller\'s mod menu has entries that switch this and pin the details.'},
        {id = 'area', type = 'choice', label = 'Where', default = 'sector',
         choices = {{value = 'sector', label = 'Where the event counts'}, {value = 'everywhere', label = 'Everywhere'}},
         tooltip = 'Events of one sector only count there; the bar shows while you stand in that sector. Events without a sector show everywhere.'},
        {id = 'pulse', type = 'bool', label = 'Pulse at 25, 50 and 75 %', default = true,
         tooltip = 'The pill glows briefly when the realm passes a quarter of the goal'},
        {id = 'results', type = 'bool', label = 'Show the result for a while', default = true,
         tooltip = 'After an event ends, one short line says whether the realm made it, then fades out (the server sets how long, 2 minutes by default)'},
    },
}
