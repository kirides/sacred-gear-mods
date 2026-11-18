-- Self test of the daily and weekly quests of the bounty mod (single player). Needs -gear-auto and a savegame (-gear-load) with a
-- hero in a safe place; run with -gear-mods=bounty,quests_selftest. Result: GearAutomation\<instance>\quests_selftest.txt (PASS /
-- FAIL lines). The date is moved with the mod's test hook (bounty.test op q_offset), so no real day has to pass.
if not gear.auto then return end
local A = gear.auto
local W = gear.world
local DAY = 86400
local lines, failed = {}, false
local log = {}                      -- every quest.* event: 'name:period:id'

local function say(s) lines[#lines + 1] = s; A.write('quests_selftest.txt', table.concat(lines, '\n')) end
local function check(name, ok, detail)
    say((ok and 'PASS ' or 'FAIL ') .. name .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or ''))
    if not ok then failed = true end
end
local function op(o, extra)
    local ctx = extra or {}
    ctx.op = o
    gear.emit('bounty.test', ctx)
    return ctx
end
local function count(prefix)
    local n = 0
    for _, e in ipairs(log) do if e:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
end
for _, e in ipairs({'started', 'progress', 'completed', 'claimed', 'failed', 'set_completed', 'streak', 'streak_lost'}) do
    gear.on('quest.' .. e, function(ev)
        log[#log + 1] = ('quest.%s:%s:%s'):format(e, tostring(ev.period), tostring(ev.bonus and 'bonus' or ev.id or ev.count))
        if e == 'streak' then log[#log + 1] = ('quest.streak:%s:%d'):format(tostring(ev.period), ev.count) end
    end)
end

-- Kills the quests of `period` until each is done (the words of each quest as the creature's type name).
local function finish(period)
    local d = op('q_tick').q_data[period]
    for _, q in ipairs(d.quests) do
        local name = q.names[1] and (q.names[1]:upper() .. '_TEST.GRN') or 'ANYTHING.GRN'
        op('q_kill', {name = name, count = q.target - q.n})
    end
end
local function snapshot(period)
    local d = op('q_tick').q_data[period]
    local parts = {}
    for _, q in ipairs(d.quests) do parts[#parts + 1] = q.id .. '=' .. q.n .. '/' .. q.target end
    return table.concat(parts, ',')
end
local function settle() gear.wait_until(function() return not op('q_tick').q_paying end, 40) gear.wait(0.5) end
local function items_near()
    local hx, hy = W.hero():position()
    return #(W.items_near(hx, hy, 600, {limit = 128}) or {})
end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then say('FAIL no game') return A.quit(1) end
    gear.wait(4)
    local hero = W.hero()
    local ctx
    gear.wait_until(function() ctx = op('q_tick') return ctx.q_data and ctx.q_data.daily.key ~= nil end, 20)
    check('single player quests are up', ctx.q_mode == 'local' and #ctx.q_data.daily.quests > 0 and #ctx.q_data.weekly.quests > 0,
        ctx.q_mode)
    say('scope ' .. tostring(gear.savegame.scope()) .. ' level ' .. tostring(hero:level()) .. ' daily ' .. snapshot('daily') .. ' weekly ' .. snapshot('weekly'))
    check('initial quest.started events', count('quest.started') >= 3, count('quest.started'))
    check('panel payload', ctx.q_view and #ctx.q_view.daily.quests == #ctx.q_data.daily.quests and ctx.q_view.daily.left > 0)

    -- A clean start at the real date, and the draw is stable: the same date gives the same quests
    op('q_reset') op('q_tick')
    local first = snapshot('daily') .. '|' .. snapshot('weekly')
    op('q_reset') op('q_tick')
    check('same date, same quests', first == snapshot('daily') .. '|' .. snapshot('weekly'), first)

    -- Streak: day 0 complete, day 1 complete (2), day 2 complete (3: bonus), day 4 (day 3 missed): lost
    op('q_reset') op('q_offset', {seconds = 0}) log = {}
    local g0 = hero:gold()
    finish('daily')
    settle()
    local d = op('q_tick').q_data
    check('daily set done: streak 1', d.streak.daily.count == 1 and d.streak.daily.last == d.daily.key, d.streak.daily.count)
    check('weekly streak untouched', d.streak.weekly.count == 0)
    check('rewards paid: gold went up', hero:gold() > g0, tostring(g0) .. ' -> ' .. tostring(hero:gold()))
    check('quest.claimed for each quest', count('quest.claimed:daily:daily') == #d.daily.quests, count('quest.claimed'))
    check('quest.completed / set_completed / streak events', count('quest.completed') == #d.daily.quests and count('quest.set_completed:daily') == 1
        and count('quest.streak:daily:1') == 1)
    local v = op('q_tick').q_view
    check('payload shows the streak', v.streak.daily.count == 1 and v.streak.daily.today == true and v.streak.daily.next_in == 2)
    local day0_key = d.daily.key

    op('q_offset', {seconds = DAY})
    d = op('q_tick').q_data
    check('rollover: new day key', d.daily.key == day0_key + 1, d.daily.key)
    check('rollover: streak survives one day', d.streak.daily.count == 1)
    check('rollover: fresh quests', d.daily.quests[1] and d.daily.quests[1].n == 0 and not d.daily.quests[1].done)
    finish('daily') settle()
    d = op('q_tick').q_data
    check('second day: streak 2', d.streak.daily.count == 2 and d.streak.daily.best == 2, d.streak.daily.count)

    local items_before = items_near()
    local g1 = hero:gold()
    op('q_offset', {seconds = 2 * DAY})
    finish('daily') settle()
    d = op('q_tick').q_data
    check('third day: streak 3, bonus claimed', d.streak.daily.count == 3 and count('quest.claimed:daily:bonus') == 1, count('quest.claimed:daily:bonus'))
    check('streak event with the count', count('quest.streak:daily:3') == 1)
    check('streak bonus paid (gold)', hero:gold() > g1 + 1)
    gear.wait(2)
    check('streak bonus item dropped', items_near() > items_before, items_before .. ' -> ' .. items_near())

    log = {}
    op('q_offset', {seconds = 4 * DAY})       -- the day at offset 3 days is skipped
    d = op('q_tick').q_data
    check('missed day: streak lost', d.streak.daily.count == 0 and d.streak.daily.best == 3 and count('quest.streak_lost:daily') == 1, d.streak.daily.count)

    -- Weekly: the week of the real date, then a week later
    op('q_reset') op('q_offset', {seconds = 0}) op('q_tick')
    local w0 = op('q_tick').q_data.weekly.key
    finish('weekly') settle()
    d = op('q_tick').q_data
    check('weekly set done: weekly streak 1, daily untouched', d.streak.weekly.count == 1 and d.streak.daily.count == 0)
    op('q_offset', {seconds = 7 * DAY})
    d = op('q_tick').q_data
    check('a week later: new week key', d.weekly.key == w0 + 1, d.weekly.key)
    check('weekly quests are new', d.weekly.quests[1].n == 0)
    op('q_offset', {seconds = 21 * DAY})
    d = op('q_tick').q_data
    check('weeks missed: weekly streak lost', d.streak.weekly.count == 0)

    -- A pay that waits: auto claim off -> pending until q_pay
    gear.settings.set('auto_claim', false)
    op('q_reset') op('q_offset', {seconds = 0}) op('q_tick')
    local q = op('q_tick').q_data.daily.quests[1]
    op('q_kill', {name = (q.names[1] and q.names[1]:upper() or 'ANY') .. '_X.GRN', count = q.target - q.n})
    d = op('q_tick').q_data
    check('auto claim off: reward waits', #d.pending >= 1 and d.daily.quests[1].claimed == false, #d.pending)
    local g2 = hero:gold()
    op('q_pay') settle()
    check('claim rewards pays', hero:gold() > g2 and #op('q_tick').q_data.pending == 0)
    gear.settings.set('auto_claim', true)

    -- Per savegame: progress saved with a slot, another savegame has its own
    op('q_reset') op('q_offset', {seconds = 0}) op('q_tick')
    op('q_kill', {name = 'ORC_X.GRN', count = 1})
    op('q_kill', {name = 'ANYTHING.GRN', count = 2})
    local before = snapshot('daily')
    local st = op('q_tick').q_data
    st.streak.daily.count, st.streak.daily.best, st.streak.daily.last = 5, 7, st.daily.key
    op('q_save')
    local saved
    gear.on('game.saved', function(slot) saved = slot end)
    check('save accepted', gear.game.save(gear.config.slot_a, 'quests test') == true)
    gear.wait_until(function() return saved ~= nil end, 60)
    gear.wait(1)
    check('saved', saved == gear.config.slot_a, saved)
    local scope_a = gear.savegame.scope()
    op('q_kill', {name = 'ANYTHING.GRN', count = 3})       -- progress after the save: lost with the load
    local changed = 0
    gear.on('savegame.changed', function() changed = changed + 1 end)
    gear.game.load(gear.config.slot_b)
    gear.wait_until(function() return changed >= 1 end, 120)
    gear.wait(5)
    gear.wait_until(function() ctx = op('q_tick') return ctx.q_data and ctx.q_data.daily.key ~= nil end, 30)
    say('other savegame ' .. tostring(gear.savegame.scope()) .. ' streak ' .. tostring(ctx.q_data.streak.daily.count) .. ' daily ' .. snapshot('daily'))
    check('other savegame loaded', gear.savegame.scope() ~= scope_a, gear.savegame.scope())
    check('other savegame: not the first one\'s streak', ctx.q_data.streak.daily.count ~= 5)
    local c = changed
    gear.game.load(gear.config.slot_a)
    gear.wait_until(function() return changed > c end, 120)
    gear.wait(5)
    gear.wait_until(function() ctx = op('q_tick') return ctx.q_data and ctx.q_data.daily.key ~= nil end, 30)
    check('back to the first savegame: its streak', ctx.q_data.streak.daily.count == 5 and ctx.q_data.streak.daily.best == 7, ctx.q_data.streak.daily.count)
    check('its progress as saved (not the later kills)', snapshot('daily') == before, snapshot('daily') .. ' vs ' .. before)
    gear.game.delete_save(gear.config.slot_a)

    say(failed and 'RESULT FAIL' or 'RESULT PASS')
    A.quit(failed and 1 or 0)
end)
