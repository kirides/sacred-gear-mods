---@type GearModManifest
return {
    id = 'better-saveload_manysaves',
    name = 'Better SaveLoad many savegames test',
    version = '1.0.0',
    requires = {'better-saveload'},
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
