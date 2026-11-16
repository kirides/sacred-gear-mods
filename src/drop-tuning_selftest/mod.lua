---@type GearModManifest
return {
    id = 'drop-tuning_selftest',
    name = 'Drop tuning self test',
    version = '1.0.0',
    requires = {'drop-tuning'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,     -- seconds to wait for the main menu
        timeout_game = 180,     -- seconds to wait for the game after loading
        rolls = 400,            -- loot rolls per phase
        quit = true,
    },
}
