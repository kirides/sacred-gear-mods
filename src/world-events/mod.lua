---@type GearModManifest
return {
    id = 'world-events',
    name = 'World events',
    version = '0.1.0',
    author = 'kirides',
    description = 'Shows the game server\'s world event (a realm-wide goal such as "slay 1000 orcs in 2 hours") as a movable progress bar. Needs a Sacred Gear game server with the world_events script.',
    settings = {
        {id = 'visibility', type = 'choice', label = 'Show the bar', default = 'always', section = 'Progress bar',
         choices = {{value = 'always', label = 'Always while an event runs'}, {value = 'alt', label = 'Only while Alt is held'}},
         tooltip = 'Move it with the layout editor (hold Alt, then "Edit layout"). The controller\'s mod menu has an entry that switches this.'},
        {id = 'area', type = 'choice', label = 'Where', default = 'sector',
         choices = {{value = 'sector', label = 'Where the event counts'}, {value = 'everywhere', label = 'Everywhere'}},
         tooltip = 'Events of one sector only count there; the bar shows while you stand in that sector. Events without a sector show everywhere.'},
        {id = 'results', type = 'bool', label = 'Show the result for a while', default = true,
         tooltip = 'After an event ends, the bar says whether the realm made it, for the time the server sets (2 minutes by default)'},
    },
}
