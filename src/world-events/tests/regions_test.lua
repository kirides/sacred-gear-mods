-- Unit tests of regions.lua (the region boss pill's logic) and of core.lua's lists of events. Plain Lua 5.1 / LuaJIT, no game:
-- luajit tests/regions_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path
local regions = require('regions')
local core = require('core')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

-- ---- a region record -> a view ----------------------------------------------------------------------------------------
local desert = {id = 4, index = 4, name = 'Desert', kills_needed = 8500, kills_left = 5200}
local v = regions.view(desert)
eq(v.kind, 'region', 'kind')
eq(v.title, 'Desert', 'title is the game name')
eq(v.count, 3300, 'kills done')
eq(v.target, 8500, 'kills needed')
eq(v.percent, 38, 'percent rounds down')
eq(v.line2, '3,300 / 8,500 kills', 'line 2')
check(v.frac > 0.38 and v.frac < 0.39, 'ring fraction')
eq(v.time_text, '', 'no time on a region pill')
eq(v.tip[1], 'Desert', 'tooltip title')
check(v.tip[2]:find('3,300 / 8,500 kills (38%)', 1, true), 'tooltip count')
check(v.tip[3]:find('5,200 kills until the region boss', 1, true), 'tooltip kills left')
check(v.tip[#v.tip]:find("game's own count", 1, true), 'tooltip says where the number comes from')

local done = regions.view({id = 2, name = 'Swamp', kills_needed = 5500, kills_left = 0})
eq(done.percent, 100, 'a finished countdown is 100 %'); eq(done.line2, 'Boss time!', 'boss due'); check(done.ready, 'ready')
eq(regions.view({id = 3, name = '', kills_needed = 100, kills_left = 100}).title, 'Region 3', 'a nameless region')
eq(regions.view({id = 3, name = 'X', kills_needed = 100, kills_left = 100}).percent, 0, 'nothing done yet')
-- numbers that make no sense give nothing (a record the game did not set up, garbage)
eq(regions.view({id = 1, name = 'X', kills_needed = 0, kills_left = 0}), nil, 'not set up')
eq(regions.view({id = 1, name = 'X', kills_needed = -5, kills_left = 1}), nil, 'negative')
eq(regions.view({id = 1, name = 'X', kills_needed = 'a', kills_left = 1}), nil, 'not numbers')
eq(regions.view({id = 1, name = 'X', kills_needed = 10, kills_left = 50}).count, 0, 'more left than needed: nothing done, no negative')
eq(regions.view(nil), nil, 'nil')
eq(regions.view({id = 1, name = 'A\nB\\c', kills_needed = 10, kills_left = 5}).title, 'A B/c', 'name text is cleaned')

-- the other regions with progress are listed in the tooltip
local others = {desert, {id = 1, name = 'Southern Core', kills_needed = 7500, kills_left = 7000}, {id = 5, name = 'Quiet', kills_needed = 100, kills_left = 100}}
local with = regions.view(desert, others)
local text = table.concat(with.tip, '\n')
check(text:find('Southern Core: 500 / 7,500', 1, true), 'another region with progress is listed')
check(not text:find('Quiet', 1, true), 'a region without progress is not')
check(not text:find('  Desert', 1, true), 'the current region is not listed twice')

-- ---- collecting from the game ------------------------------------------------------------------------------------------
local api = {
    count = function() return 4 end,
    get = function(_, i) return ({desert, {id = 1, name = 'Southern Core', kills_needed = 7500, kills_left = 7000}, {id = 6, name = 'Lava', kills_needed = 5500, kills_left = 5500}})[i] end,
    of_creature = function(_, hero) return hero == 'in' and desert or nil end,
}
eq(#regions.collect(api, 'in'), 1, 'the hero is in a region')
eq(regions.collect(api, 'in')[1].title, 'Desert', 'its pill')
check(regions.collect(api, 'in')[1].tip[#regions.collect(api, 'in')[1].tip]:find('Southern Core', 1, true), 'with the others in the tooltip')
eq(#regions.collect(api, 'out'), 0, 'outside any region: no pill')
eq(#regions.collect(nil, 'in'), 0, 'an older Gear without gear.data.regions: nothing')
eq(#regions.collect(api, nil), 0, 'no hero: nothing')
eq(#regions.collect({of_creature = function() error('boom') end}, 'in'), 0, 'a failing call never throws')
eq(#regions.collect({of_creature = function() return {kills_needed = 'x'} end}, 'in'), 0, 'garbage gives nothing')

-- ---- the stack: events first, then the regions, a cap ---------------------------------------------------------------------
local ev = function(title, left) return {kind = 'active', title = title, left = left, frac = 0.5} end
local r1, r2 = {kind = 'region', title = 'A', frac = 0.2}, {kind = 'region', title = 'B', frac = 0.7}
local stacked, more = regions.stack({ev('E1', 100), ev('E2', 200)}, {r1, r2}, 4)
eq(#stacked, 4, 'four pills'); eq(more, 0, 'nothing hidden')
eq(stacked[1].title, 'E1', 'events first'); eq(stacked[3].title, 'B', 'then the region with the most progress'); eq(stacked[4].title, 'A', 'then the other')
stacked, more = regions.stack({ev('E1', 1), ev('E2', 2), ev('E3', 3), ev('E4', 4), ev('E5', 5)}, {r1}, 4)
eq(#stacked, 4, 'capped'); eq(more, 2, 'two more are hidden'); eq(stacked[4].title, 'E4', 'the events keep their places, the region is cut first')
stacked, more = regions.stack({}, {}, 4); eq(#stacked, 0, 'nothing'); eq(more, 0, 'nothing more')

-- ---- several events at once: a list of states ----------------------------------------------------------------------------------
local function state(n, title, left, count)
    return {st = 'active', n = n, title = title, text = 'Do it', count = count or 10, target = 100, left = left, dur = 3600, here = true, unit = 'orcs'}
end
local model = core.new()
local ok = model:receive({v = 1, list = {state(1, 'Orc hunt', 3000), state(2, 'Wolf hunt', 600), {st = 'bogus'}, state(3, 'Thieves', 1800)}}, 100)
check(ok, 'a list is accepted')
local views = model:views(100, {area = 'everywhere', results = true})
eq(#views, 3, 'the invalid entry is dropped')
eq(views[1].title, 'Wolf hunt', 'the least time left first'); eq(views[2].title, 'Thieves', 'then'); eq(views[3].title, 'Orc hunt', 'then')
eq(model:view(100, {area = 'everywhere'}).title, 'Wolf hunt', 'view() is the first of them')
-- time counts down per event; a result sorts after the active ones
model:receive({v = 1, list = {state(1, 'Orc hunt', 3000), {st = 'won', n = 9, title = 'Old one', count = 100, target = 100, hold = 60, here = true}}}, 100)
views = model:views(101, {area = 'everywhere', results = true})
eq(#views, 2, 'an event and a result'); eq(views[1].kind, 'active', 'active first'); eq(views[2].kind, 'won', 'the result after it')
-- here = false: only where the event counts
model:receive({v = 1, list = {state(1, 'A', 100), {st = 'active', n = 2, title = 'B', text = '', count = 0, target = 10, left = 50, dur = 60, here = false}}}, 100)
eq(#model:views(100, {area = 'sector'}), 1, 'an event that does not count here is hidden'); eq(#model:views(100, {area = 'everywhere'}), 2, 'unless everywhere')
-- a pulse for the quarter mark of any event of the list
model:receive({v = 1, list = {state(1, 'A', 100, 20), state(2, 'B', 100, 5)}}, 100)
local _, crossed = model:receive({v = 1, list = {state(1, 'A', 100, 26), state(2, 'B', 100, 6)}}, 101)
eq(crossed, 25, 'a mark crossed by one of the events pulses')
-- an empty list: no event is running
check(model:receive({v = 1, list = {}}, 100), 'an empty list means nothing runs'); eq(#model:views(100, {area = 'everywhere'}), 0, 'no pills')
check(not model:receive({v = 1, list = {{st = 'bogus'}}}, 100), 'a list of garbage is refused')
-- stale pushes drop out
model:receive({v = 1, list = {state(1, 'A', 100)}}, 100)
eq(#model:views(100 + core.STALE + 1, {area = 'everywhere'}), 0, 'a list not refreshed for two minutes is gone')
-- a single state still works, and replaces a list
model:receive(state(1, 'Solo', 100), 200)
eq(#model:views(200, {area = 'everywhere'}), 1, 'a single state'); eq(model:view(200, {area = 'everywhere'}).title, 'Solo', 'and its title')
-- the layout editor's sample when nothing runs
eq(#core.new():views(0, {preview = true}), 1, 'a sample for the layout editor')
-- at most MAX_STATES entries are taken
local big = {}
for i = 1, 30 do big[i] = state(i, 'E' .. i, i * 10) end
model:receive({v = 1, list = big}, 300)
eq(#model:views(300, {area = 'everywhere'}), core.MAX_STATES, 'a long list is cut')

print(('world-events regions: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
