---@type GearModManifest
return {
    id = 'companions_selftest',
    name = 'Companions self test',
    version = '1.0.0',
    requires = {'companions'},
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
