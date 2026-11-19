---@type GearModManifest
return {
    id = 'icon-set_selftest',
    name = 'Icon Set drops self test',
    version = '1.0.0',
    requires = {'icon-set'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
