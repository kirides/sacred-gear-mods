-- Beastmaster core, outside the game: luajit tests/beastmaster_test.lua
package.path = 'src/beastmaster/?.lua;' .. package.path
local core = require('core')
local fails = 0
local function ok(c, name)
    if not c then fails = fails + 1; print('FAIL ' .. name) else print('ok ' .. name) end
end
ok(core.ally_level(1, 100) == 1 and core.ally_level(216, 100) == 216 and core.ally_level(216, 200) == 250 and core.ally_level(1, 10) == 1, 'ally level follows the hero, within 1 to 250')
ok(core.stage(1) == 0 and core.stage(17) == 0 and core.stage(18) == 1 and core.stage(215) == 11 and core.stage(216) == 12 and core.stage(400) == 12, 'a growth stage every 18 levels up to 216')
ok(core.growth(1, 75, 125) == 0.75 and math.abs(core.growth(216, 75, 125) - 1.25) < 1e-9, 'growth runs from the first to the last size')
ok(core.growth(108, 75, 125) > core.growth(36, 75, 125), 'growth rises with the level')
ok(math.abs(core.ally_scale(0.5, 216, 75, 125) - 0.625) < 1e-9 and core.ally_scale(10, 216, 100, 100) == 4, 'ally scale: base times growth, capped at 4')
ok(math.abs(core.pet_scale(0.5, 130) - 0.65) < 1e-9, 'pet scale: base times the pet size')
local x, y = core.spot(0, 0, 1, 1, 100, 0)
ok(math.abs(math.sqrt(x * x + y * y) - 100) < 2 and x < 0, 'a lone follower stands behind at the radius')
local foes = {{x = 500, y = 0, id = 1}, {x = 100, y = 0, id = 2}}
ok(core.nearest(foes, 0, 0, 1000).id == 2 and core.nearest(foes, 0, 0, 50) == nil, 'nearest foe within the radius')
local list = {{id = 1, role = 'ally'}, {id = 2, role = 'pet'}, {id = 3, role = 'ally'}, {id = 4, role = 'ally'}}
local ex = core.excess(list, 'ally', 2)
ok(#ex == 1 and ex[1] == 4, 'the newest beyond the limit go')
local species = require('species')
local seen, bad = {}, 0
for _, sp in ipairs(species) do
    if seen[sp.type] or type(sp.type) ~= 'number' or type(sp.family) ~= 'string' or not (sp.scale > 0.1 and sp.scale <= 2) then bad = bad + 1 end
    seen[sp.type] = true
end
ok(#species > 100 and bad == 0, 'the species list has every animal once, with a base scale of 0.1 to 2 (' .. #species .. ')')
local small = {}
for _, sp in ipairs(species) do small[sp.family] = sp.scale end
ok(small.gigant_spider < 0.5 and small.scorpion < 0.7 and small.wolf == 1, 'big monsters are drawn smaller by default, a wolf as it is')
os.exit(fails == 0 and 0 or 1)
