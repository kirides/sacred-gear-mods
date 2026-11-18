-- Daily / weekly quests (src/bounty/quests.lua) and their hooks outside the game. From the repository root:  luajit tests/quests_test.lua
-- (The self test mod src/quests_selftest runs the same logic inside the game, against the real kill watcher and rewards.)
package.path = 'src/bounty/?.lua;' .. package.path
local Q = require('quests')
local hooks = require('hooks')
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

local function at(y, m, d, h) return os.time({year = y, month = m, day = d, hour = h or 12, min = 0, sec = 0}) end
local conf = Q.clean_config(nil)

-- calendar
ok(Q.days_from_civil(1970, 1, 1) == 0, 'epoch day')
ok(Q.days_from_civil(2000, 3, 1) == 11017, 'leap year')
ok(Q.date_text(Q.days_from_civil(2026, 11, 19)) == '2026-11-19', 'date text round trip')
ok(Q.date_text(Q.days_from_civil(2024, 2, 29)) == '2024-02-29', 'leap day text')
ok(Q.day_of(at(2026, 11, 30)) + 1 == Q.day_of(at(2026, 12, 1)), 'month change is the next day')
ok(Q.day_of(at(2026, 12, 31)) + 1 == Q.day_of(at(2027, 1, 1)), 'year change is the next day')
-- 2026-11-16 is a Monday
local mon = Q.week_of_day(Q.day_of(at(2026, 11, 16)))
ok(Q.week_of_day(Q.day_of(at(2026, 11, 22))) == mon, 'Sunday is in the same week as the Monday before')
ok(Q.week_of_day(Q.day_of(at(2026, 11, 23))) == mon + 1, 'the next Monday starts a new week')
ok(Q.week_of_day(Q.day_of(at(2026, 11, 15))) == mon - 1, 'the Sunday before belongs to the week before')
ok(Q.seconds_left('daily', at(2026, 11, 19, 23)) <= 3600 and Q.seconds_left('daily', at(2026, 11, 19, 23)) > 0, 'time to midnight')
ok(Q.seconds_left('weekly', at(2026, 11, 22, 23)) <= 3600, 'Sunday evening: the week ends at midnight')
ok(Q.seconds_left('weekly', at(2026, 11, 16, 0)) > 6 * 86400, 'Monday morning: nearly a week')

-- the seeded draw is stable and differs between days
local function ids(state, p) local t = {} for _, q in ipairs(state[p].quests) do t[#t + 1] = q.id .. '=' .. q.target end return table.concat(t, ',') end
local a, b, c = Q.new_state(), Q.new_state(), Q.new_state()
Q.roll(a, at(2026, 11, 19), 25, conf) Q.roll(b, at(2026, 11, 19, 3), 25, conf) Q.roll(c, at(2026, 11, 20), 25, conf)
ok(#a.daily.quests == 3 and #a.weekly.quests == 2, 'three daily, two weekly quests')
ok(ids(a, 'daily') == ids(b, 'daily') and ids(a, 'weekly') == ids(b, 'weekly'), 'same day, same quests')
ok(ids(a, 'daily') ~= ids(c, 'daily'), 'next day, other quests')
ok(ids(a, 'weekly') == ids(c, 'weekly'), 'next day, same week quests')
local seen = {}
for _, q in ipairs(a.daily.quests) do ok(not seen[q.def], 'no quest twice a day') seen[q.def] = true end
local low = Q.new_state()
Q.roll(low, at(2026, 11, 19), 1, conf)
for _, q in ipairs(low.daily.quests) do ok(q.min_level <= 1, 'level 1 gets no gated quest') end

-- roll: the same day changes nothing; a new day ends the old quests
local s = Q.new_state()
local ev = Q.roll(s, at(2026, 11, 19), 10, conf)
ok(#ev == 5, 'first roll: five started')
ok(#Q.roll(s, at(2026, 11, 19, 20), 10, conf) == 0, 'same day, no events')
ev = Q.roll(s, at(2026, 11, 20), 10, conf)
local failed, started = 0, 0
for _, e in ipairs(ev) do if e.name == 'failed' then failed = failed + 1 elseif e.name == 'started' then started = started + 1 end end
ok(failed == 3 and started == 3, 'new day: three failed, three started')
ok(#Q.roll(s, at(2026, 11, 19), 10, conf) == 0, 'the clock never goes back')

-- kills, completion, the streak
local function finish_day(state, t)
    local out = {}
    for _, q in ipairs(state.daily.quests) do
        local w = {}
        for _, n in ipairs(q.names) do w[n] = true end
        if #q.names == 0 then w.anything = true end
        for _ = 1, q.target - q.n do for _, e in ipairs(Q.kill(state, w, 30, conf)) do out[#out + 1] = e end end
    end
    return out
end
local function names(events) local t = {} for _, e in ipairs(events) do t[#t + 1] = e.name end return table.concat(t, ' ') end
s = Q.new_state()
Q.roll(s, at(2026, 11, 19), 30, conf)
local w = {}
for _, n in ipairs(s.daily.quests[1].names) do w[n] = true end
if #s.daily.quests[1].names == 0 then w.anything = true end
local e1 = Q.kill(s, w, 30, conf)
ok(e1[1] and e1[1].name == 'progress' and e1[1].previous == 0 and e1[1].quest.n == 1, 'a kill is progress')
for _, e in ipairs(Q.kill(s, {nothing = true}, 30, conf)) do ok(#e.quest.names == 0, 'other creatures count only for any-monster quests') end
local ev1 = finish_day(s, at(2026, 11, 19))
ok(s.streak.daily.count == 1 and s.streak.daily.last == s.daily.key, 'set done: streak 1')
ok(s.streak.weekly.count == 0, 'weekly untouched by the daily set')
local nc = 0
for _, e in ipairs(ev1) do if e.name == 'completed' then nc = nc + 1 end end
ok(nc == 3, 'three completed')
ok(#s.pending == 3, 'three rewards wait: ' .. #s.pending)
local list = Q.take_pending(s)
ok(#list == 3 and #s.pending == 0, 'take_pending empties the list')
for _, q in ipairs(s.daily.quests) do ok(q.claimed, 'quest marked claimed') end
Q.put_back(s, list[1])
ok(#s.pending == 1 and s.pending[1].tries == 1, 'put_back keeps the reward')
Q.take_pending(s)

-- a second finished day, third day: the bonus
Q.roll(s, at(2026, 11, 20), 30, conf)
ok(s.streak.daily.count == 1, 'streak survives one day')
finish_day(s, at(2026, 11, 20))
ok(s.streak.daily.count == 2, 'second day: 2')
Q.take_pending(s)
Q.roll(s, at(2026, 11, 21), 30, conf)
local ev3 = finish_day(s, at(2026, 11, 21))
ok(s.streak.daily.count == 3 and s.streak.daily.best == 3, 'third day: 3')
local bonus
for _, e in ipairs(ev3) do if e.name == 'streak' then bonus = e end end
ok(bonus and bonus.bonus == true and bonus.count == 3, 'the third day is a bonus day')
local nbonus = 0
for _, e in ipairs(s.pending) do if e.kind == 'bonus' then nbonus = nbonus + 1 ok(e.gold > 0 and e.item ~= nil, 'bonus pays gold and an item') end end
ok(nbonus == 1, 'one bonus waits')
-- two bonuses later pay more (gold_step)
ok(Q.bonus_for('daily', 6, conf, 10).gold > Q.bonus_for('daily', 3, conf, 10).gold, 'the second bonus is bigger')
ok(Q.bonus_for('daily', 4, conf, 10) == nil, 'no bonus between multiples')
-- a missed day breaks it
Q.take_pending(s)
local lost = Q.roll(s, at(2026, 11, 23), 30, conf)
local got
for _, e in ipairs(lost) do if e.name == 'streak_lost' then got = e end end
ok(got and got.previous == 3 and s.streak.daily.count == 0 and s.streak.daily.best == 3, 'two days later: streak lost, best kept')
-- completing a set twice on one day counts once
finish_day(s, at(2026, 11, 23))
ok(s.streak.daily.count == 1, 'streak restarts at 1')

-- weekly set
s = Q.new_state()
Q.roll(s, at(2026, 11, 16), 30, conf)
for _, q in ipairs(s.weekly.quests) do
    local ws = {}
    for _, n in ipairs(q.names) do ws[n] = true end
    if #q.names == 0 then ws.anything = true end
    for _ = 1, q.target do Q.kill(s, ws, 30, conf) end
end
ok(s.streak.weekly.count == 1, 'weekly set done: weekly streak 1')
Q.roll(s, at(2026, 11, 23), 30, conf)
ok(s.streak.weekly.count == 1 and s.weekly.quests[1].n == 0, 'next Monday: new quests, streak alive')
Q.roll(s, at(2026, 12, 14), 30, conf)
ok(s.streak.weekly.count == 0, 'weeks missed: weekly streak lost')

-- payload for the panel, flatten, sanitize / json-like round trip
s = Q.new_state()
Q.roll(s, at(2026, 11, 19), 30, conf)
local p = Q.payload(s, at(2026, 11, 19), conf, 30)
ok(p.v == 1 and #p.daily.quests == 3 and p.daily.left > 0 and p.streak.daily.next_in == 3 and p.streak.daily.bonus ~= nil, 'payload')
ok(#Q.flatten(p).bounties == 5 and Q.flatten(p).bounties[1].period == 'daily', 'flatten')
local copy = Q.sanitize(s)
ok(ids(copy, 'daily') == ids(s, 'daily') and copy.daily.key == s.daily.key, 'sanitize keeps a good state')
ok(Q.sanitize(nil).daily.quests[1] == nil and Q.sanitize('x').streak.daily.count == 0, 'sanitize of rubbish')
local bad = Q.sanitize({daily = {key = 5, quests = {{id = 'x'}, 7, {id = 'a', title = 'T', target = 2, n = 9, names = {'Orc', 4}}}},
    streak = {daily = {count = -3, best = 'x'}}, pending = {{id = 'p', title = 'P', gold = 5}, 'junk'}})
ok(#bad.daily.quests == 1 and bad.daily.quests[1].n == 2 and bad.daily.quests[1].names[1] == 'orc', 'sanitize repairs entries')
ok(bad.streak.daily.count == 0 and #bad.pending == 1, 'sanitize: counts and pending')

-- configuration
local cc = Q.clean_config({daily = {slots = 1, pool = {{id = 'x', title = 'X', names = {'Orc'}, target = 5, gold = 100}, {id = ''}, 'junk'}},
    streak = {daily = {every = 2, gold = 10, item = false}}, seed = 'abc'})
ok(cc.daily.slots == 1 and #cc.daily.pool == 1 and cc.daily.pool[1].target[1] == 5, 'config: own pool, bad entries dropped')
ok(#cc.weekly.pool == #Q.DEFAULTS.weekly.pool, 'config: missing list keeps the default')
ok(cc.streak.daily.every == 2 and cc.streak.daily.item == nil and cc.streak.weekly.every == Q.DEFAULTS.streak.weekly.every, 'config: streak')
local one = Q.new_state()
Q.roll(one, at(2026, 11, 19), 10, cc)
ok(#one.daily.quests == 1 and one.daily.quests[1].def == 'x', 'config pool is drawn from')
ok(Q.clean_config(nil).seed == 'sacred', 'default seed')

-- hooks: quest events from payload diffs (the server side)
local function run(old, new, opts)
    local out = {}
    hooks.diff(old and Q.flatten(old), Q.flatten(new), function(name, pl) out[#out + 1] = name .. ':' .. pl.period .. (pl.initial and '!' or '') end, opts)
    return table.concat(out, ' ')
end
local function mk(n)
    return {daily = {quests = {{id = 'd1', title = 'A', target = 3, n = n, done = n >= 3}}}, weekly = {quests = {}}, streak = {daily = {count = 0, best = 0, every = 3, next_in = 3}, weekly = {count = 0}}}
end
ok(run(nil, mk(0), {prefix = 'quest'}) == 'quest.started:daily!', 'quest hooks: first state is initial')
ok(run(mk(0), mk(2), {prefix = 'quest'}) == 'quest.progress:daily', 'quest hooks: progress')
ok(run(mk(2), mk(3), {prefix = 'quest', claim_on_done = true}) == 'quest.progress:daily quest.completed:daily quest.claimed:daily', 'quest hooks: completed and claimed')
local function streaks(old, new)
    local out = {}
    hooks.diff_streak(old, new, function(name, pl) out[#out + 1] = name .. ':' .. pl.period .. ':' .. tostring(pl.count or pl.previous) .. (pl.bonus and '+' or '') end)
    return table.concat(out, ' ')
end
local s0, s1 = mk(0), mk(3)
s1.streak.daily = {count = 3, best = 3, today = true, every = 3, next_in = 3}
ok(streaks(s0, s1) == 'quest.set_completed:daily:3 quest.streak:daily:3+', 'streak hooks: set done, streak up with bonus')
local s2 = mk(0)
s2.streak.daily = {count = 0, best = 3, every = 3, next_in = 3}
ok(streaks(s1, s2) == 'quest.streak_lost:daily:3', 'streak hooks: lost')
ok(streaks(nil, s1) == '', 'streak hooks: nothing without a state before')
ok(#hooks.QUEST_EVENTS == 8, 'quest events listed')
-- the bounty diff still works with the default prefix
local out = {}
hooks.diff(nil, {bounties = {{id = 1, title = 'T', target = 3, n = 0}}}, function(name) out[#out + 1] = name end)
ok(out[1] == 'bounty.started', 'bounty hooks unchanged')

if failures == 0 then print('quests: ok') if gear and gear.auto then gear.auto.quit(0) end os.exit(0) end
if gear and gear.auto then gear.auto.quit(1) end
os.exit(1)
