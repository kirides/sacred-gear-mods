-- Beastmaster core, outside the game: luajit tests/beastmaster_test.lua
package.path = 'src/beastmaster/?.lua;' .. package.path
local core = require('core')
local fails = 0
local function ok(c, name)
    if not c then fails = fails + 1; print('FAIL ' .. name) else print('ok ' .. name) end
end
ok(core.health(1, 100) == 100, 'level 1 is the wild kind')
ok(core.health(30, 100) > core.health(10, 100) and core.health(10, 200) > core.health(10, 100), 'health grows with level and strength')
ok(core.damage(1, 100) == 1 and core.damage(20, 100) > 1, 'damage grows with level')
local x, y = core.spot(0, 0, 1, 1, 100, 0)
ok(math.abs(math.sqrt(x * x + y * y) - 100) < 2 and x < 0, 'a lone follower stands behind at the radius')
local foes = {{x = 500, y = 0, id = 1}, {x = 100, y = 0, id = 2}}
ok(core.nearest(foes, 0, 0, 1000).id == 2 and core.nearest(foes, 0, 0, 50) == nil, 'nearest foe within the radius')
local list = {{id = 1, role = 'ally'}, {id = 2, role = 'pet'}, {id = 3, role = 'ally'}, {id = 4, role = 'ally'}}
local ex = core.excess(list, 'ally', 2)
ok(#ex == 1 and ex[1] == 4, 'the newest beyond the limit go')
os.exit(fails == 0 and 0 or 1)
