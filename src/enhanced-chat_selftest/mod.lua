---@type GearModManifest
return {
    id = 'enhanced-chat_selftest',
    name = 'Enhanced Chat self test',
    version = '1.0.0',
    requires = {'enhanced-chat'},
    automation = true,
    config = {
        slot = 1,               -- the savegame to load (single player)
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
        -- 'sp': single player; 'lan': hosts a LAN game alone (the game's own gameserver, on its usual ports);
        -- 'server': two instances join a dedicated server's LAN game (see main.lua)
        mode = 'sp',
        hero_x = 820,           -- lan / server: the hero to pick in the LAN hero list (1600x900 screenshot pixels)
        hero_y = 400,
        sender_hero_x = 620,    -- server: the sending instance's hero (another one)
        sender_hero_y = 450,
        host_wait = 45,         -- server: seconds the receiving instance (the host) waits in the join dialog for the sender
    },
}
