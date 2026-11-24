---@type GearModManifest
return {
    id = 'beastmaster_selftest',
    name = 'Beastmaster self test',
    version = '0.1.0',
    requires = {'beastmaster'},
    automation = true,
    config = {timeout_menu = 120, timeout_game = 180, quit = true},
}
