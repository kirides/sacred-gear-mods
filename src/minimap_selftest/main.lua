-- Self test of the minimap for runs without a player:
--     Sacred.exe -gear-auto -gear-instance=minimap -gear-load=<slot> -gear-mods=minimap,minimap_selftest
-- Loads the savegame, takes a screenshot (mm-*.bmp in GearAutomation\<instance>) of the round view at every zoom level, of the
-- rectangle and of the view without markers, and logs the hero's map position.
if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end
local A, cfg = gear.auto, gear.config

local function set(id, v) gear.emit('minimap.set', id, v); gear.wait(0.5) end

gear.task(function()
    print((A.wait_for_menu(cfg.timeout_menu) and 'PASS' or 'FAIL') .. ' main menu')
    local game = A.wait_for_game(cfg.timeout_game)
    print((game and 'PASS' or 'FAIL') .. ' game')
    gear.wait(4)
    local hero = gear.world.hero()
    if hero then print('hero', hero:position()) end
    set('shape', 'round'); set('width', 200); set('markers', true)
    for level = 1, 6 do
        set('zoom', level)
        gear.wait(0.5)
        A.screenshot('mm-round-z' .. level)
    end
    set('width', 400); set('zoom', 1)
    A.screenshot('mm-wide')
    set('width', 200)
    set('zoom', 2)
    set('shape', 'square'); set('width', 320); set('height', 190)
    A.screenshot('mm-square-z2')
    set('markers', false)
    A.screenshot('mm-square-nomarkers')
    print('done')
    if cfg.quit then A.quit(0) end
end)
