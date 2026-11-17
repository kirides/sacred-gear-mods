---@type GearModManifest
return {
    id = 'sector-tools_selftest',
    name = 'Sector tools self test',
    version = '1.0.0',
    requires = {'sector-tools'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
