return {
    id = 'key-bindings_selftest',
    name = 'Key bindings self test',
    version = '1.0.0',
    requires = {'key-bindings'},
    automation = true,
    config = {
        slot = 1,               -- the savegame to load
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
    },
}
