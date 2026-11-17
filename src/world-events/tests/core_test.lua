-- Unit tests of the bar's logic (core.lua). Plain Lua 5.1 / LuaJIT, no game:  luajit tests/core_test.lua  (from the mod's
-- folder). Exit code 0 when everything passes.
package.path = './?.lua;' .. package.path
local core = require('core')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

-- formats
eq(core.format_time(0), '0:00', 'zero')
eq(core.format_time(45), '0:45', 'seconds')
eq(core.format_time(750), '12:30', 'minutes')
eq(core.format_time(4325), '1:12:05', 'hours')
eq(core.format_time(-5), '0:00', 'negative')
eq(core.format_time(59.6), '1:00', 'rounds')
eq(core.format_time(nil), '0:00', 'nil')
eq(core.percent(370, 1000), 37, 'percent')
eq(core.percent(999, 1000), 99, 'rounded down')
eq(core.percent(1000, 1000), 100, 'full')
eq(core.percent(5000, 1000), 100, 'over')
eq(core.percent(5, 0), 0, 'no target')
eq(core.percent(nil, nil), 0, 'nil')
eq(core.group(0), '0', 'group 0')
eq(core.group(999), '999', 'group 999')
eq(core.group(1000), '1,000', 'group 1000')
eq(core.group(1234567), '1,234,567', 'group 7 digits')
eq(core.group(123456), '123,456', 'group 6 digits')
eq(core.clean('Orc\nhunt\\c', 80), 'Orc hunt/c', 'control characters and backslashes')
eq(core.clean(5), '', 'not a string')
eq(#core.clean(('x'):rep(300), 20), 20, 'cut to the limit')

-- parse
local ok, err = core.parse('x')
check(ok == nil and err, 'a string is no state')
check(core.parse({st = 'bogus'}) == nil, 'unknown state')
check(core.parse(nil) == nil, 'nil')
local s = core.parse({st = 'active', title = 'T', text = 'Do', count = '12', target = 0, left = -3, dur = 'x', mine = 2, here = true})
eq(s.count, 12, 'numeric strings are numbers')
eq(s.target, 1, 'target at least 1')
eq(s.left, 0, 'left at least 0')
eq(s.dur, 1, 'bad dur')
eq(s.here, true, 'here')
eq(core.parse({st = 'active', here = 'yes'}).here, false, 'only true counts as here')
eq(core.parse({st = 'idle', next_in = 30, here = true}).here, false, 'idle is never here')

-- the model
local active = {st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', unit = 'orcs', count = 370, target = 1000, left = 100, dur = 7200,
    here = true, mine = 3, need = 10, people = 4, reward = 'gold', n = 7}
local m = core.new()
check(m:view(0, {area = 'sector'}) == nil, 'nothing before the first state')
check(m:receive(active, 100), 'state accepted')
local v = m:view(100, {area = 'sector'})
eq(v.kind, 'active', 'active')
eq(v.title, 'Orc hunt', 'title')
eq(v.percent, 37, 'view percent')
eq(v.count_text, '370 / 1,000', 'view count text')
eq(v.time_text, '1:40', 'view time')
eq(v.mine_text, 'Your share: 3 (10 needed for the reward)', 'share below the minimum')
eq(v.line2, '370 / 1,000 orcs', 'second line: count and unit')
eq(v.tip[1], 'Orc hunt', 'tooltip: title')
eq(v.tip[2], 'Slay 1000 orcs', 'tooltip: goal')
eq(v.tip[3], '370 / 1,000 orcs (37%)', 'tooltip: progress')
eq(v.tip[4], 'Time left: 1:40', 'tooltip: time')
eq(v.tip[#v.tip - 1], v.mine_text, 'tooltip: share')
eq(v.tip[#v.tip], 'Reward: gold', 'tooltip: reward')
eq(v.alpha, 1, 'active is opaque')
check(math.abs(v.time_frac - 100 / 7200) < 1e-9, 'time ring: the share of the duration left')
eq(v.qualifies, false, 'does not qualify yet')
eq(v.late, false, 'not late')
-- the time counts down between pushes
v = m:view(130, {area = 'sector'})
eq(v.time_text, '1:10', 'time counts down')
v = m:view(165, {area = 'sector'})
eq(v.late, true, 'late in the last minute')
eq(m:view(200, {area = 'sector'}).time_text, '0:00', 'never below zero')
-- stale: no push for too long
check(m:view(100 + core.STALE + 1, {area = 'sector'}) == nil, 'a state without news disappears')
check(m:view(100 + core.STALE, {area = 'sector'}) ~= nil, 'but not just yet')
-- qualified
m:receive({st = 'active', title = 'T', text = 'x', count = 1, target = 2, left = 10, here = true, mine = 12, need = 10}, 0)
v = m:view(0, {area = 'sector'})
eq(v.mine_text, 'Your share: 12', 'share when qualified')
eq(v.qualifies, true, 'qualifies')
m:receive({st = 'active', title = 'T', text = 'x', count = 1, target = 2, left = 10, here = true, mine = 0, need = 0}, 0)
eq(m:view(0, {area = 'sector'}).qualifies, true, 'no minimum')
eq(m:view(0, {area = 'sector'}).line2, '1 / 2', 'no unit: just the count')

-- area
m:receive({st = 'active', title = 'T', text = 'x', count = 1, target = 2, left = 10, here = false}, 0)
check(m:view(0, {area = 'sector'}) == nil, 'not in the sector: hidden')
check(m:view(0, {area = 'everywhere'}) ~= nil, 'everywhere: shown')
check(m:view(0, {area = 'sector', preview = true}) ~= nil, 'the layout editor shows it')
m:receive({st = 'idle', next_in = 100}, 0)
check(m:view(0, {area = 'everywhere'}) == nil, 'idle: nothing')
local sample = m:view(0, {area = 'sector', preview = true})
eq(sample.title, 'Orc hunt', 'idle with preview: the sample')

-- results
m:receive({st = 'won', title = 'Orc hunt', text = 'x', count = 1000, target = 1000, hold = 60, here = true, people = 6}, 10)
v = m:view(20, {area = 'sector', results = true})
eq(v.kind, 'won', 'won')
eq(v.text, 'Completed!', 'won text')
eq(v.line2, 'Completed!', 'one short line')
eq(v.tip[#v.tip], '6 heroes took part', 'won people in the tooltip')
eq(v.alpha, 1, 'result before the fade')
check(math.abs(m:view(10 + 60 - 3, {area = 'sector', results = true}).alpha - 0.5) < 1e-9, 'result fades out in the last seconds')
eq(v.frac, 1, 'full bar')
check(m:view(69, {area = 'sector', results = true}) ~= nil, 'result held')
check(m:view(70, {area = 'sector', results = true}) == nil, 'result gone after the hold')
check(m:view(20, {area = 'sector', results = false}) == nil, 'results off')
m:receive({st = 'failed', title = 'Orc hunt', text = 'x', count = 400, target = 1000, hold = 60, here = false}, 10)
check(m:view(20, {area = 'sector', results = true}) == nil, 'a result elsewhere is not shown in sector mode')
eq(m:view(20, {area = 'everywhere', results = true}).text, 'Failed', 'failed everywhere')

-- a bad push keeps the last good state
m:receive(active, 0)
check(not m:receive({st = 'nope'}, 1), 'bad state refused')
check(m:view(1, {area = 'sector'}) ~= nil, 'the last good state stays')
m:reset()
check(m:view(1, {area = 'everywhere'}) == nil, 'reset')

-- pulses: the mark a push crosses (same event only)
local pm = core.new()
local function push(n, count) return pm:receive({st = 'active', title = 'T', text = 'x', count = count, target = 100, left = 10, n = n}, 0) end
local ok1, c1 = push(1, 10); check(ok1 and c1 == nil, 'the first state pulses nothing')
local _, c2 = push(1, 24); check(c2 == nil, 'below 25 %: no pulse')
local _, c3 = push(1, 25); eq(c3, 25, '25 % crossed')
local _, c4 = push(1, 26); check(c4 == nil, 'not again')
local _, c5 = push(1, 80); eq(c5, 75, 'several at once: the highest')
local _, c6 = push(2, 90); check(c6 == nil, 'another event: no pulse')
local _, c7 = push(2, 50); check(c7 == nil, 'going down: no pulse')
local okb, cb = pm:receive({st = 'nope'}, 0); check(okb == false and cb == nil, 'a bad push pulses nothing')

print(('world-events core: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
