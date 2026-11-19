---@type GearModManifest
return {
    id = 'spawn-rate_selftest',
    name = 'Spawn rate self test',
    version = '1.0.0',
    requires = {'spawn-rate'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,     -- seconds to wait for the main menu
        timeout_game = 180,     -- seconds to wait for the game after loading
        dwell = 1.5,            -- seconds the hero stays at each site
        sites = 8,              -- places tried per phase
        quit = true,
    },
}
