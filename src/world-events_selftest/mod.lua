---@type GearModManifest
return {
    id = 'world-events_selftest',
    name = 'World events self test',
    version = '1.0.0',
    requires = {'world-events'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
