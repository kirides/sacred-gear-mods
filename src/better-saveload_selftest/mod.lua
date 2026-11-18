---@type GearModManifest
return {
    id = 'better-saveload_selftest',
    name = 'Better SaveLoad self test',
    version = '1.0.0',
    requires = {'better-saveload'},
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
        probe = false,      -- only screenshots of the main menu and its UI (to find the Load game entry)
    },
}
