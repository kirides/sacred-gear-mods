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
        -- 'sp': single player; 'lan': hosts a LAN game alone (the game's own gameserver, on its usual ports)
        mode = 'sp',
        hero_x = 820,           -- lan: the hero to pick in the LAN hero list (1600x900 screenshot pixels)
        hero_y = 400,
    },
}
