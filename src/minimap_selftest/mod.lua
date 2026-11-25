---@type GearModManifest
return {
    id = 'minimap_selftest',
    name = 'Minimap self test',
    version = '1.0.0',
    requires = {'minimap'},
    automation = true,
    config = {timeout_menu = 120, timeout_game = 180, quit = true},
}
