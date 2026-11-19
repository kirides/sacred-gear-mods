-- Logic test of the spawn-rate mod outside the game (src/spawn-rate/core.lua). From the repository root:
--     luajit tests/spawn_rate_test.lua
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

package.path = 'src/spawn-rate/?.lua;' .. package.path
local core = require('core')

-- extras: rate - 1, fractions as a chance
ok(core.extras(1, math.random) == 0, '1x makes none')
ok(core.extras(0.5, math.random) == 0, 'below 1x makes none')
ok(core.extras(10, math.random) == 9, '10x makes nine')
ok(core.extras(100, math.random) == 99, '100x makes 99')
ok(core.extras(1000, math.random) == 99, 'capped at 100x')
ok(core.extras(2.5, function() return 0.2 end) == 2 and core.extras(2.5, function() return 0.7 end) == 1, 'fraction = chance of one more')

-- allowance: budget, slow frames, cap
ok(core.allowance(4, 0.016, 0, 200) == 4, 'full budget at 60 fps')
ok(core.allowance(4, 0.05, 0, 200) == 1, 'one per frame below 30 fps')
ok(core.allowance(4, 0.1, 0, 200) == 0, 'none below 15 fps')
ok(core.allowance(4, 0.016, 198, 200) == 2, 'room under the cap')
ok(core.allowance(4, 0.016, 200, 200) == 0, 'at the cap')
ok(core.allowance(4, 0.016, 5000, 0) == 4, 'cap 0 = no limit')

-- queue: one creature per take, jobs leave when done, bounded
local q = core.queue(2)
ok(q:push({type = 7, x = 1, y = 2, layer = 0, left = 2}), 'push 1')
ok(q:push({type = 8, x = 3, y = 4, layer = 1, left = 1}), 'push 2')
ok(not q:push({type = 9, x = 0, y = 0, layer = 0, left = 5}), 'bounded')
ok(q.left == 3 and q:size() == 2, 'counts')
local a, b, c, d = q:take(0, 0), q:take(0, 0), q:take(0, 0), q:take(0, 0)
ok(a.type == 7 and b.type == 8 and b.layer == 1 and c.type == 7 and d == nil, 'round robin, nearest first, exhaustion')
ok(q.left == 0 and q:size() == 0, 'empty after work')
q:push({type = 1, x = 0, y = 0, layer = 0, left = 4}); q:clear()
ok(q.left == 0 and q:take() == nil, 'clear')

-- scatter: inside the ring
math.randomseed(1)
for _ = 1, 200 do
    local x, y = core.scatter(1000, 1000, 80, 270, math.random)
    local dist = math.sqrt((x - 1000) ^ 2 + (y - 1000) ^ 2)
    if dist < 79 or dist > 271 then ok(false, 'scatter ring ' .. dist); break end
end

-- harmless wildlife is not multiplied
for _, n in ipairs({'RABBIT.GRN', 'dove_white.grn', 'CROW.GRN', 'BIRD_SMALL.GRN', 'Pigeon.grn', 'chicken.grn', 'SEAGULL.GRN'}) do
    ok(not core.multipliable(n), n .. ' is not multiplied')
end
for _, n in ipairs({'gob_warrior.grn', 'ORC_WARRIOR.GRN', 'THIEF_MAL.GRN', 'GHOST.GRN', 'SKEL_WARRIOR.GRN', 'BIRDMAN_SHAMAN.GRN'}) do
    ok(core.multipliable(n), n .. ' is multiplied')
end
ok(not core.multipliable(nil) and not core.multipliable(''), 'no name: not multiplied')

-- fair: the nearest jobs are served first, every job gets one before any gets two, a far job waits its turn
local f = core.queue(10)
f:push({type = 1, x = 5000, y = 0, layer = 0, left = 3, origin = 1})
f:push({type = 2, x = 100, y = 0, layer = 0, left = 3, origin = 2})
f:push({type = 3, x = 900, y = 0, layer = 0, left = 3, origin = 3})
local seq = {}
for i = 1, 6 do seq[#seq + 1] = f:take(0, 0).type end
ok(table.concat(seq) == '231231', 'nearest first, round robin: ' .. table.concat(seq))
local dropped = f:drop_if(function(job) return job.x > 1000 end)
ok(#dropped == 1 and dropped[1].origin == 1 and f.left == 2 and f:size() == 2, 'far jobs are dropped and returned')
ok(f:take(0, 0).type == 2 and f:take(0, 0).type == 3, 'the rest keeps its order')

-- a million creations at the worst rate cost a bounded queue, not memory
local big = core.queue(1500)
local refused = 0
for i = 1, 100000 do if not big:push({type = 1, x = i, y = i, layer = 0, left = core.extras(100, math.random)}) then refused = refused + 1 end end
ok(big:size() == 1500 and refused == 98500, 'queue stays bounded')

if failures == 0 then print('spawn-rate: all tests passed') else print(failures .. ' failed'); os.exit(1) end
