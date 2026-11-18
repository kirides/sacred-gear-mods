-- World event hooks (src/world-events/events.lua) outside the game. From the repository root:  luajit tests/world_events_events_test.lua
package.path = 'src/world-events/?.lua;' .. package.path
local events = require('events')
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end
local function run(old, new, source)
    local out = {}
    events.diff(old, new, function(name, p) out[#out + 1] = name .. ':' .. p.id .. (p.previous and ('<' .. p.previous) or '') .. (p.initial and '!' or '') .. (p.source == 'local' and 'L' or '') end, source)
    return table.concat(out, ' ')
end
local function s(n, st, count) return {n = n, title = 'E' .. n, st = st, count = count, target = 100} end

ok(run(nil, {s(1, 'active', 5)}) == 'worldevent.started:1!', 'first state: started, initial')
ok(run(nil, {s(1, 'won', 100)}) == '', 'first state: finished events are silent')
ok(run({s(1, 'active', 5)}, {s(1, 'active', 9)}) == 'worldevent.progress:1<5', 'progress')
ok(run({s(1, 'active', 9)}, {s(1, 'won', 100)}) == 'worldevent.completed:1', 'completed')
ok(run({s(1, 'active', 9)}, {s(1, 'failed', 40)}) == 'worldevent.failed:1', 'failed')
ok(run({s(1, 'won', 100)}, {s(1, 'won', 100)}) == '', 'a held result is silent')
ok(run({s(1, 'active', 9)}, {s(1, 'active', 9), s(2, 'active', 0)}) == 'worldevent.started:2', 'a second event')
ok(run({s(1, 'active', 9)}, {{st = 'idle'}}) == '', 'idle is silent')
ok(run({s(1, 'active', 9)}, {s(2, 'active', 0)}, 'local') == 'worldevent.started:2L', 'local source')
if failures == 0 then print('world events hooks: ok') os.exit(0) end
os.exit(1)
