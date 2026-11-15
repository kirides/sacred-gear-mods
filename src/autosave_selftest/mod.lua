---@type GearModManifest
return {
    id = 'autosave_selftest',
    name = 'Autosave self test',
    version = '1.0.0',
    requires = {'autosave'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {
        timeout_menu = 120,     -- seconds to wait for the main menu
        timeout_game = 180,     -- seconds to wait for the game after loading
        saves = 4,              -- autosaves to wait for (3 slots: the 4th reuses the oldest)
        interval_minutes = 0.1, -- the test's autosave interval (6 s)
        quit = true,
    },
}
