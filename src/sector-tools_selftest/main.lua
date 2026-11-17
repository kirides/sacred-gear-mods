-- A self test of the sector-tools mod, for runs without a player (needs a SacredGear.dll with creature:sector() and gear.clipboard):
--
--     Sacred.exe -gear-auto -gear-instance=sectortools -gear-load=1 -gear-mods=sector-tools,sector-tools_selftest
--
-- loads savegame 1 and checks, in the real game: the hero's sector id and grid cell, the panel (shown while Alt is held), the ground
-- lines near a sector boundary, recording a second sector (the hero is teleported over the boundary), the circle, the copied
-- config line (read back from the Windows clipboard) and "Copy id". Screenshots st-*.bmp go to GearAutomation\<instance>\.
if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local ui = gear.ui
local results = {checks = {}, passed = 0, failed = 0}
local SECTOR = 64 * 53.66563034057617

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('sectortools.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function query()
    local q = {}
    gear.emit('sector-tools.query', q)
    return q
end

local function command(op)
    local c = {op = op}
    gear.emit('sector-tools.command', c)
    return c
end

local function panel()
    for _, p in ipairs(ui.panels()) do
        if p.key == 'sector-tools:panel' then return p end
    end
end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    local game = A.wait_for_game(cfg.timeout_game)
    check('game with a hero', game)
    if not game then return finish() end
    gear.wait(3)

    local hero = gear.world.hero()
    check('the hero', hero ~= nil)
    if not hero then return finish() end
    local x, y, layer = hero:position()
    local sector = hero:sector()
    check('the hero has a sector', type(sector) == 'number' and sector > 0, tostring(sector))
    local q = query()
    check('the mod follows the hero', q.sector == sector and q.cx == math.floor(x / SECTOR) and q.cy == math.floor(y / SECTOR),
        ('sector %s cell %s,%s'):format(tostring(q.sector), tostring(q.cx), tostring(q.cy)))
    check('the id of the hero\'s cell is known', q.known[('%d:%d,%d'):format(layer or 0, q.cx, q.cy)] == sector)

    -- hidden until Alt
    check('no panel without Alt', panel() == nil)
    A.key_down('alt')
    gear.wait(0.8)
    check('Alt shows the panel', panel() ~= nil)
    A.key_up('alt')

    -- walk the hero to the nearest sector boundary by clicking on the ground in its direction (a teleport is refused on most spots)
    local oy = q.cy * SECTOR
    local function nearest_edge()
        local hx, hy = hero:position()
        local list = {
            {axis = 'x', e = q.cx * SECTOR, d = hx - q.cx * SECTOR, dir = -1}, {axis = 'x', e = (q.cx + 1) * SECTOR, d = (q.cx + 1) * SECTOR - hx, dir = 1},
            {axis = 'y', e = oy, d = hy - oy, dir = -1}, {axis = 'y', e = oy + SECTOR, d = oy + SECTOR - hy, dir = 1},
        }
        table.sort(list, function(l, r) return l.d < r.d end)
        return list[1], hx, hy
    end
    local function click_towards(edge, hx, hy)
        local dx, dy = 0, 0
        if edge.axis == 'x' then dx = edge.dir * 700 else dy = edge.dir * 700 end
        local sx = 512 + (dx - dy) * 48 / 53.66563
        local sy = 362 + (dx + dy) * 24 / 53.66563
        sx, sy = math.max(80, math.min(sx, 940)), math.max(80, math.min(sy, 520))
        A.ui_click(sx, sy)
    end
    local edge, hx, hy = nearest_edge()
    for _ = 1, 40 do
        edge, hx, hy = nearest_edge()
        if edge.d < 320 then break end
        click_towards(edge, hx, hy)
        gear.wait(1.2)
    end
    gear.wait(1.5)
    edge, hx, hy = nearest_edge()
    check('walked next to a sector boundary', edge.d < 450, ('%d units away'):format(edge.d))
    local crossing = edge
    gear.emit('sector-tools.command', {op = 'pin'})
    gear.wait(1.0)
    check('pinned: the panel stays without Alt', panel() ~= nil)
    A.screenshot('st-ground')

    -- record: the sector the hero stands in, then walk back over the boundary
    local here = hero:sector()
    check('start recording', command('start') ~= nil and query().recording == true)
    local back = {axis = crossing.axis, dir = -crossing.dir}
    for _ = 1, 25 do
        if hero:sector() ~= here then break end
        click_towards(back, 0, 0)
        gear.wait(1)
    end
    gear.wait(1)
    local after = hero:sector()
    q = query()
    check('the hero is in a sector after the move', type(after) == 'number' and after > 0, tostring(after))
    check('the sector walked into is recorded too', #q.ids >= 2 and after ~= here, tostring(#q.ids) .. ' sectors, now ' .. tostring(after))
    command('add')
    command('circle')
    q = query()
    check('a circle at the hero', q.circle ~= nil and q.circle.r == 1500)
    gear.wait(1)
    A.screenshot('st-recorded')

    -- the clipboard
    local copied = command('copy')
    check('copy config', copied.ok == true, copied.status)
    local text = gear.clipboard.get()
    check('the clipboard has the config line', text ~= nil and text:find('= { name = "My area", sectors = {', 1, true) ~= nil
        and text:find('circle = { x = ', 1, true) ~= nil, tostring(text))
    check('the line is the one the mod built', text == q.snippet, tostring(q.snippet))
    command('copy_id')
    check('copy id: the sector number', gear.clipboard.get() == tostring(hero:sector()), tostring(gear.clipboard.get()))
    check('the clipboard handles non-ASCII text', gear.clipboard.set('Silver Creek \xc3\xa9\xc3\xa4') and gear.clipboard.get() == 'Silver Creek \xc3\xa9\xc3\xa4')

    -- the layout editor can move the panel
    ui.set_edit_mode(true)
    gear.wait(0.6)
    A.screenshot('st-layout')
    ui.set_edit_mode(false)
    command('clear')
    check('clear', #query().ids == 0 and query().circle == nil)

    finish()
end)
