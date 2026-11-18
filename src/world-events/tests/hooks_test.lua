-- Unit tests of hooks.lua and localevents.lua (the hook checking, the engine, the spawn message, the local single player mode).
-- Plain Lua 5.1 / LuaJIT, no game:  luajit tests/hooks_test.lua  (from the mod's folder). Exit code 0 when everything passes.
package.path = './?.lua;' .. package.path
local hooks = require('hooks')
local localevents = require('localevents')
local core = require('core')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

-- ---- checking ---------------------------------------------------------------------------------------------------
local list, refused = hooks.clean({
    {at = 30, actions = {{action = 'spawn', n = 100000, target = 'owner', kinds = {{type = 'Orc', weight = 3}, {type = ''}, {type = 7}}, radius = 10}}},
    {actions = {{action = 'message', text = 'x'}}},                                  -- no trigger
    {at = 150, actions = {{action = 'message', text = 'x'}}},                        -- too far
    {at = 10, actions = {{action = 'explode'}}},                                     -- no valid action
    {kills = {creature = 'Shaman', count = 5, per_player = true}, actions = {{action = 'gold', amount = 100}}},
    {on = 'success', actions = {{action = 'item', spec = {quality = 9}, n = 99}, {action = 'message', text = 'a\nb\\c'}}},
    'nope',
})
eq(#list, 3, 'three valid hooks')
eq(#refused, 5, 'refusals are reported')
local spawn = list[1].actions[1]
eq(spawn.n, 40, 'spawn count is clamped')
eq(spawn.radius, 50, 'radius is clamped')
eq(#spawn.kinds, 2, 'the nameless kind is dropped')
eq(spawn.kinds[2].type, 7, 'type numbers stay numbers')
eq(spawn.target, 'owner', 'target')
eq(list[2].kills.per_player, true, 'per player')
eq(list[2].actions[1].target, 'killer', 'default target of gold')
eq(list[3].actions[1].n, 10, 'item count is clamped')
eq(list[3].actions[2].text, 'a b c', 'text is cleaned')
eq(hooks.clean('x'), nil, 'not a list')
eq(hooks.clean({}), nil, 'empty list')

-- ---- the engine ---------------------------------------------------------------------------------------------------
local acted = {}
local function act(action, ctx, key, index) acted[#acted + 1] = key .. ':' .. index .. ':' .. (action.text or action.action) end
local H = hooks.clean({
    {on = 'start', actions = {{action = 'message', text = 'go'}}},
    {at = 10, actions = {{action = 'message', text = 'ten'}}},
    {at = 20, actions = {{action = 'message', text = 'twenty'}, {action = 'message', text = 'twenty-b'}}},
    {at_time = 60, actions = {{action = 'message', text = 'minute'}}},
    {kills = {creature = 'shaman', count = 3}, actions = {{action = 'message', text = 'shamans'}}},
    {kills = {creature = 77, count = 2, per_player = true}, actions = {{action = 'message', text = 'wolves'}}},
    {on = 'fail', actions = {{action = 'message', text = 'lost'}}},
})
local state = {}
local r = hooks.runner(H, state, act)
r:on('start')
eq(table.concat(acted, ','), 'h1:1:go', 'start')
r:progress(25, 5)                                                -- passes two
eq(table.concat(acted, ','), 'h1:1:go,h2:1:ten,h3:1:twenty,h3:2:twenty-b', 'catch-up fires all, in order')
r:progress(99, 5)
eq(#acted, 4, 'no refire')
r:progress(0, 59); eq(#acted, 4, 'time hook waits')
r:progress(0, 60); eq(#acted, 5, 'time hook fires')
-- kills
r:kill('Orc Shaman', 1, 'me'); r:kill('orc warrior', 2, 'me'); r:kill('SHAMAN', 1, 'me')
eq(#acted, 5, 'two shamans: not yet')
r:kill('Shaman', 1, 'me')
eq(acted[#acted], 'h5:1:shamans', 'the third shaman fires')
r:kill('Shaman', 1, 'me'); eq(#acted, 6, 'once')
r:kill('Wolf', 77, 'a'); r:kill('Wolf', 77, 'b'); eq(#acted, 6, 'per hero: one each is not two')
r:kill('Wolf', 77, 'a'); eq(acted[#acted], 'h6:1:wolves', 'per hero fires for the one with two')
-- persistence: a runner on the same state does not fire again
local again = hooks.runner(H, state, act)
again:progress(100, 9999); again:on('start'); eq(#acted, 7, 'after a restart nothing repeats (only the fail hook is left)')
again:on('fail'); eq(acted[#acted], 'h7:1:lost', 'fail hook')
-- an action that throws never stops the others
local boom = hooks.runner(hooks.clean({{on = 'start', actions = {{action = 'message', text = 'a'}, {action = 'message', text = 'b'}}}}), {}, function(a)
    if a.text == 'a' then error('x') end
    acted[#acted + 1] = 'b-ran'
end)
boom:on('start'); eq(acted[#acted], 'b-ran', 'the next action runs after a failing one'); eq(boom.failed, 1, 'failure counted')

-- ---- texts -------------------------------------------------------------------------------------------------------
eq(hooks.trigger_text({at = 30}), 'At 30% of the goal', 'percent text')
eq(hooks.trigger_text({at_time = 1200}), 'After 20m 00s', 'time text')
eq(hooks.next_text(H, {}) , 'At 10% of the goal: "ten"', 'next hook')
eq(hooks.next_text(H, {h2 = true, h3 = true}), 'After 1m 00s: "minute"', 'next unfired percent / time hook')
eq(hooks.next_text(H, {h2 = true, h3 = true, h4 = true}), nil, 'only percent / time hooks are announced')

-- ---- the spawn message ---------------------------------------------------------------------------------------------
local wave = hooks.parse_spawn({v = 1, id = '1:h2:1:abcd', event = 'Orc hunt', n = 3, radius = 600, kinds = {{type = 'Orc Warrior', weight = 3}, {type = 'x', weight = 1}}, text = 'Hold on!'})
check(wave and wave.n == 3 and wave.radius == 600 and #wave.kinds == 2 and wave.text == 'Hold on!', 'a good wave parses')
check(hooks.parse_spawn({id = 'x', n = 0, kinds = {{type = 'a'}}}) == nil, 'n must be at least 1')
check(hooks.parse_spawn({id = 'x', n = 99999, kinds = {{type = 'a'}}}) == nil, 'n above the cap is refused, not spawned')
check(hooks.parse_spawn({n = 1, kinds = {{type = 'a'}}}) == nil, 'no id')
check(hooks.parse_spawn({id = 'x', n = 1, kinds = {}}) == nil, 'no kinds')
check(hooks.parse_spawn('x') == nil, 'not a table')
eq(hooks.parse_spawn({id = 'x', n = 1, kinds = {{type = 'a'}}, radius = 'far'}).radius, 400, 'default radius')

-- weighted choice: deterministic "random" numbers
local picks = hooks.pick_kinds({{type = 'A', weight = 3}, {type = 'B', weight = 1}}, 4, (function() local seq, i = {1, 3, 4, 2}, 0 return function() i = i + 1 return seq[i] end end)())
eq(table.concat(picks, ''), 'AAB' .. 'A', 'weights decide: 1,3 -> A; 4 -> B; 2 -> A')
eq(#hooks.pick_kinds({}, 3, function() return 1 end), 0, 'no kinds, no picks')
local off = hooks.offsets(5, 500, function(k) return math.random(k) end)
eq(#off, 5, 'five places')
local inside = true
for _, o in ipairs(off) do
    local d = math.sqrt(o[1] ^ 2 + o[2] ^ 2)
    if d > 501 or d < 199 then inside = false end
end
check(inside, 'places lie between 40% and 100% of the radius')

-- dedupe
local seen = hooks.seen(3)
check(seen:add('a') and seen:add('b'), 'new ids')
check(not seen:add('a'), 'a resent wave is dropped')
seen:add('c'); seen:add('d')
check(seen:add('a'), 'the oldest ids are forgotten')

-- ---- the local mode -----------------------------------------------------------------------------------------------------
local events = {
    v = 1, config = {first_delay = 10, cooldown = 30, result_hold = 20},
    events = {
        {id = 'wave', title = 'Wave', target = 4, duration = 100, names = {'orc'}, unit = 'orcs', hooks = {
            {on = 'start', actions = {{action = 'message', text = 'go'}}},
            {at = 50, actions = {{action = 'spawn', n = 3, kinds = {{type = 'Orc Warrior'}}}, {action = 'gold', amount = 10}}},
            {at_time = 40, actions = {{action = 'message', text = 'late'}}},
            {kills = {creature = 'shaman', count = 1}, actions = {{action = 'item', spec = {quality = 9}}}},
            {on = 'success', actions = {{action = 'message', text = 'won'}}},
            {on = 'fail', actions = {{action = 'message', text = 'lost'}}},
        }},
        {id = 'bad', target = 0, duration = 100},
        {id = 'sec', title = 'Sector', target = 2, duration = 50, sectors = {{100, 110}}},
    },
}
local log, done = {}, {}
local store = {}
local L = localevents.new({defs = events, store = store, act = function(a, ctx, key, index) done[#done + 1] = key .. ':' .. a.action end, log = function(t) log[#log + 1] = t end, rnd = function() return 1 end})
eq(#L.defs, 2, 'the bad event is refused')
check(log[1] and log[1]:find('refused', 1, true), 'and logged')
eq(L:payload(), nil, 'nothing before the first delay')
L:tick(5); eq(L:payload(), nil, 'still waiting')
L:tick(5)
local p = L:payload()
check(p and p.st == 'active' and p.title == 'Wave' and p.count == 0 and p.target == 4 and p.left == 100, 'the event starts after the delay')
eq(done[1], 'h1:message', 'the start hook ran')
eq(p.hook, 'At 50% of the goal: 3 of Orc Warrior appear around you', 'the next hook is announced')
check(core.parse(p) ~= nil, 'the core accepts the local state')
eq(L:kill('Wolf', 5), false, 'a wolf does not count'); eq(store.current.count, 0, 'count unchanged')
eq(L:kill('Orc Warrior', 38), true, 'an orc counts')
eq(L:kill('Orc Shaman', 40), true, 'a shaman counts and fires the kills hook')
check(table.concat(done, ','):find('h4:item', 1, true), 'the item hook ran')
eq(store.current.count, 2, 'two counted'); check(table.concat(done, ','):find('h2:spawn,h2:gold', 1, true), 'the 50% hook spawned and paid')
L:tick(2); eq(store.current.elapsed, 2, 'time counts')
L:tick(60); eq(store.current.elapsed, 7, 'a long pause counts at most 5 seconds')
for _ = 1, 8 do L:tick(5) end
check(table.concat(done, ','):find('h3:message', 1, true), 'the time hook fired after 40 seconds')
-- persistence: a new local mode on the same store continues the event and does not refire
local before = #done
local L2 = localevents.new({defs = events, store = store, act = function(a, ctx, key) done[#done + 1] = key .. ':' .. a.action end, rnd = function() return 1 end})
L2:tick(1)
eq(#done, before, 'nothing fires again after a restart')
eq(L2:payload().count, 2, 'the progress is kept')
L2:kill('Orc', 38); L2:kill('Orc', 38)
local won = L2:payload()
check(won and won.st == 'won' and won.count == 4, 'the goal ends it with a result')
check(table.concat(done, ','):find('h5:message', 1, true), 'success hook')
check(not table.concat(done, ','):find('h6', 1, true), 'no fail hook')
for _ = 1, 5 do L2:tick(5) end; eq(L2:payload(), nil, 'the result fades after its hold')
-- the second event starts after the cooldown; a failed event runs the fail hooks
L2:tick(5); L2:tick(5); L2:tick(5); L2:tick(5); L2:tick(5); L2:tick(5)
local sec = L2:payload()
check(sec and sec.title == 'Sector', 'the next event of the rotation starts after the cooldown')
eq(L2:kill('Orc', 38, 5), false, 'a sector event: nothing but its sectors counts (known sector 5)')
eq(L2:kill('Orc', 38, 105), true, 'inside the range')
eq(L2:kill('Orc', 38, nil), true, 'an unknown place counts')
-- expiry
local f = {}
local store3 = {}
local L3 = localevents.new({defs = {events = {{id = 'x', title = 'X', target = 5, duration = 10, hooks = {{on = 'fail', actions = {{action = 'message', text = 'lost'}}}}}}, config = {first_delay = 0}}, store = store3,
    act = function(a) f[#f + 1] = a.text end})
L3:tick(1); check(L3:payload() ~= nil, 'starts at once')
for _ = 1, 3 do L3:tick(5) end
eq(L3:payload().st, 'failed', 'expires'); eq(f[1], 'lost', 'fail hook')
-- an empty events.json and a missing definition never crash
local L4 = localevents.new({defs = {events = {}}, store = {}}); L4:tick(1); eq(L4:payload(), nil, 'no events, no state')
local L5 = localevents.new({defs = events, store = {current = {id = 'gone', n = 1, elapsed = 0, count = 0}, seq = 1}}); L5:tick(1); eq(L5:payload(), nil, 'an event whose definition is gone is dropped')
local L6 = localevents.new({defs = 'garbage', store = {}}); L6:tick(1); check(#L6.defs == 1, 'garbage falls back to the built-in rotation')

print(('hooks tests: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
