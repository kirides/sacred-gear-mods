-- Daily and weekly quests (part of the bounty mod; the rules are in quests.lua, the events in hooks.lua).
--
--   single player: this computer draws the day's and the week's quests from the date (the same date always gives the same quests),
--     counts the kills with the bounty board's kill watcher (localgame.lua) and pays through its reward path (gold into the purse,
--     an item rolled at the hero's feet). Progress, the streaks and the rewards still to be paid are saved per savegame
--     (gear.store.game 'quest_progress.json'); the pool, the number of quests and the streak bonuses are in quests.json of the
--     mod's folder (all savegames, edited by hand, see docs/mods/bounty.md).
--   network game: the quests and streaks of a Sacred Gear game server with scripts-examples/daily_quests.lua, pushed over the
--     custom net channel 'bounty:quests'. The server counts, pays and keeps the streak; this side only shows it. No answer from
--     the server: the panel says so (a network game has no local rotation, the kills are the server's).
--
-- Protocol (server -> client, answers { req = 1 } and is pushed on every change of the hero's quests):
--   { v = 1, daily = { key, left, done, complete, quests = { { id, title, text, target, n, done, claimed, reward, level } } },
--     weekly = { same }, streak = { daily = { count, best, today, every, next_in, bonus }, weekly = { ... } }, pending, totals }
-- `left` is relative (seconds until the next reset). Nothing in it is trusted for anything but display.

local Q = require('quests')
local hooks = require('hooks')
local localgame = require('localgame')
local localboard = require('localboard')

local ui, net, cfg = gear.ui, gear.net, gear.config
local W = gear.world
local R = {}

local GOLD, GREEN, GREY, RED = 0xFFFFD780, 0xFF80FF80, 0xFFB0B0B0, 0xFFFF8080

ui.show_panel('quests', false)

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

if gear.events then
    for _, e in ipairs(hooks.QUEST_EVENTS) do
        local streak = e[1] == 'quest.streak' or e[1] == 'quest.streak_lost' or e[1] == 'quest.set_completed'
        gear.events.declare(e[1], {doc = e[2], args = streak and hooks.STREAK_ARGS or hooks.QUEST_ARGS})
    end
end

---------------------------------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------------------------------

local offset = 0                    -- seconds added to the real time: the test hook moves the date with it
local function now() return os.time() + offset end

local conf = Q.clean_config(nil)    -- quests.json over the defaults
local function load_conf()
    local text = gear.read('quests.json')
    local ok, data = false, nil
    if text then ok, data = pcall(gear.json.decode, text) end
    conf = Q.clean_config(ok and data or nil)
    if text and not ok then print('bounty: quests.json is not readable, the defaults are used') end
end
load_conf()

-- The hero's progress belongs to the savegame; the handle's data is replaced when another game loads, so always go through H.
local H = gear.store.game('quest_progress.json', Q.new_state(), {every = 20, check = Q.sanitize})

local announced = false             -- the running quests were reported (initial = true) after the game / savegame changed
local view = nil                    -- the payload the panel draws (local: made here; network: the server's)
local server_view, server_at = nil, 0
local asked = -1e9
local paying = false

local function mode()
    if gear.settings.get('quests') == false then return nil end
    if gear.mp and gear.mp.active() then return 'server' end
    return 'local'
end
function R.wants_poll() return mode() == 'local' and gear.settings.get('quests') ~= false end

local function toast(title, ...) gear.toast.show(title, ...) end

local function level_of()
    local hero = W.hero()
    return hero and hero:level() or nil
end

local function rebuild()
    if mode() == 'local' then view = Q.payload(H.data, now(), conf, level_of() or 10) end
end

---------------------------------------------------------------------------------------------------------------------
-- Events (gear.emit) and toasts for what quests.lua reports
---------------------------------------------------------------------------------------------------------------------

local function qpayload(q)
    local p = hooks.payload({id = q.id, title = q.title, text = q.text, target = q.target, n = q.n, period = q.period,
        level = q.min_level > 1 and q.min_level or nil, reward = Q.reward_text(q.gold, q.item)}, 'local')
    return p
end

local PERIOD_NAME = {daily = 'Daily', weekly = 'Weekly'}

local function publish(events)
    local started = {daily = 0, weekly = 0}
    for _, e in ipairs(events) do
        local q = e.quest
        if e.name == 'started' then
            local p = qpayload(q)
            p.initial = e.initial or nil
            gear.emit('quest.started', p)
            if e.fresh then started[q.period] = started[q.period] + 1 end
        elseif e.name == 'progress' then
            local p = qpayload(q)
            p.previous = e.previous
            gear.emit('quest.progress', p)
        elseif e.name == 'completed' then
            gear.emit('quest.completed', qpayload(q))
            toast('Quest complete: ' .. q.title, 'Reward: ' .. Q.reward_text(q.gold, q.item))
        elseif e.name == 'failed' then
            gear.emit('quest.failed', qpayload(q))
        elseif e.name == 'set_completed' then
            gear.emit('quest.set_completed', {period = e.period, count = H.data.streak[e.period].count, source = 'local'})
            toast(PERIOD_NAME[e.period] .. ' quests done', 'Every quest of the ' .. (e.period == 'daily' and 'day' or 'week') .. ' is finished')
        elseif e.name == 'streak' then
            gear.emit('quest.streak', {period = e.period, count = e.count, best = e.best, bonus = e.bonus, source = 'local'})
            local unit = e.period == 'daily' and 'days' or 'weeks'
            toast(PERIOD_NAME[e.period] .. ' streak: ' .. e.count .. ' ' .. unit, e.bonus and 'Streak bonus on its way' or nil)
        elseif e.name == 'streak_lost' then
            gear.emit('quest.streak_lost', {period = e.period, previous = e.previous, source = 'local'})
            toast(PERIOD_NAME[e.period] .. ' streak lost', 'It was ' .. e.previous .. ' in a row')
        end
    end
    for _, period in ipairs(Q.PERIODS) do
        if started[period] > 0 then
            toast('New ' .. period .. ' quests', started[period] .. ' quests are up')
        end
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Paying (the bounty board's path: gold into the purse, an item rolled at the hero's feet)
---------------------------------------------------------------------------------------------------------------------

local function claimed_event(e)
    local q
    for _, period in ipairs(Q.PERIODS) do
        for _, c in ipairs(H.data[period].quests) do if c.id == e.id then q = c end end
    end
    local p = q and qpayload(q) or {id = e.id, title = e.title, period = e.period, target = 1, n = 1, source = 'local'}
    p.reward = Q.reward_text(e.gold, e.item)
    if e.kind == 'bonus' then p.bonus = true end
    gear.emit('quest.claimed', p)
end

local function pay_pending()
    if paying or #H.data.pending == 0 then return end
    local hero = W.hero()
    if not hero or not W.can_change() then return end
    local list = Q.take_pending(H.data)
    H:changed()
    paying = true
    local i = 0
    local function nextone()
        i = i + 1
        local e = list[i]
        if not e then
            paying = false
            H:changed()
            rebuild()
            return
        end
        if e.gold > 0 and not localgame.gold(e.gold) then
            if (e.tries or 0) < 4 then Q.put_back(H.data, e) end
            return nextone()
        end
        claimed_event(e)
        if e.kind == 'bonus' then toast('Streak bonus: ' .. e.title, 'Reward: ' .. Q.reward_text(e.gold, e.item)) end
        if e.item then
            localgame.drop_item(e.item, function(ok)
                if not ok then
                    if (e.tries or 0) < 3 then
                        Q.put_back(H.data, {id = e.id, kind = e.kind, period = e.period, title = e.title, gold = 0, item = e.item, tries = e.tries or 0})
                    else
                        toast('Quest reward failed', 'No item could be made')
                    end
                end
                nextone()
            end)
        else
            nextone()
        end
    end
    nextone()
end
R.pay_pending = pay_pending

---------------------------------------------------------------------------------------------------------------------
-- The local rotation
---------------------------------------------------------------------------------------------------------------------

local function tick_local()
    local level = level_of()
    if not level then return end
    local events = Q.roll(H.data, now(), level, conf)
    if not announced then
        announced = true
        local had = {}
        for _, e in ipairs(events) do if e.name == 'started' then had[e.quest.id] = true end end
        for _, period in ipairs(Q.PERIODS) do
            for _, q in ipairs(H.data[period].quests) do
                if not q.done and not had[q.id] then events[#events + 1] = {name = 'started', quest = q, initial = true} end
            end
        end
    end
    if #events > 0 then H:changed() end
    publish(events)
    if gear.settings.get('auto_claim') ~= false then pay_pending() end
    rebuild()
end

localgame.on_kill(function(type_name)
    if mode() ~= 'local' then return end
    local level = level_of()
    if not level then return end
    local events = Q.kill(H.data, localboard.words(type_name), level, conf)
    if #events > 0 then H:changed() end
    publish(events)
    rebuild()
    if gear.settings.get('auto_claim') ~= false then pay_pending() end
end)

gear.every(1, function()
    if mode() == 'local' then tick_local() end
end)

gear.on('savegame.changed', function()
    announced = false
    view = nil
    paying = false
end)

---------------------------------------------------------------------------------------------------------------------
-- The server's quests
---------------------------------------------------------------------------------------------------------------------

local channel = net and net.channel('bounty:quests')

local function valid(p)
    if type(p) ~= 'table' or p.v ~= 1 then return false end
    for _, period in ipairs(Q.PERIODS) do
        local s = p[period]
        if type(s) ~= 'table' or type(s.quests) ~= 'table' then return false end
        for _, q in ipairs(s.quests) do
            if type(q) ~= 'table' or type(q.title) ~= 'string' or type(q.target) ~= 'number' then return false end
        end
    end
    p.streak = type(p.streak) == 'table' and p.streak or {}
    for _, period in ipairs(Q.PERIODS) do
        if type(p.streak[period]) ~= 'table' then p.streak[period] = {count = 0, best = 0} end
        p.streak[period].count = tonumber(p.streak[period].count) or 0
    end
    return true
end

if channel then
    channel:on(function(_, payload)
        if not valid(payload) then return end
        local old = server_view
        server_view, server_at = payload, gear.time()
        hooks.diff(old and Q.flatten(old) or nil, Q.flatten(payload), gear.emit, {source = 'server', claim_on_done = true, prefix = 'quest'})
        hooks.diff_streak(old, payload, gear.emit, {source = 'server'})
    end)
end

local function ask(force)
    if mode() ~= 'server' or not channel or not net.supported() then return end
    local t = gear.time()
    if not force and t - asked < (cfg.refresh or 60) then return end
    asked = t
    channel:send({req = 1}, 'server')
end

gear.on('net_caps', function(caps) if caps and caps.supported then ask(true) end end)
gear.on('session.start', function() server_view = nil ask(true) end)
gear.on('session.stop', function() server_view = nil end)
gear.every(5, function() ask(false) end)

---------------------------------------------------------------------------------------------------------------------
-- Panel and tracker
---------------------------------------------------------------------------------------------------------------------

local function current()
    local m = mode()
    if m == 'local' then return view, 0 end
    if m == 'server' then return server_view, server_view and (gear.time() - server_at) or 0 end
end

local function left_text(p, age)
    return gear.fmt.span(math.max(0, (p.left or 0) - age))
end

local ROW = 54
local function row(q, x, y, w)
    local done = q.done == true
    local n = math.min(q.n or 0, q.target)
    ui.text(q.title, x, y, {color = done and GREEN or GOLD, size = 15, bold = true})
    ui.text(done and (q.claimed and 'paid' or 'reward waiting') or '', x, y, {width = w, align = 'right', color = done and GREEN or GREY, size = 12})
    ui.text((q.text or '') .. (q.level and q.level > 1 and (' (level ' .. q.level .. '+)') or ''), x, y + 17, {color = 0xFFE0E0E0, size = 12})
    local by = y + 33
    ui.rect(x, by, w, 10, ui.rgba(0, 0, 0, 160))
    local frac = q.target > 0 and n / q.target or 0
    if frac > 0 then ui.rect(x, by, math.max(1, math.floor(w * frac)), 10, done and ui.rgba(80, 200, 100, 220) or ui.rgba(210, 160, 60, 220)) end
    ui.frame(x, by, w, 10, ui.rgba(200, 170, 90, 160), 1)
    ui.text(('%d / %d'):format(n, q.target), x, by - 2, {width = w, align = 'center', size = 11, shadow = true})
    ui.text('Reward: ' .. tostring(q.reward or '?'), x, by + 12, {color = GREY, size = 11})
    return ROW
end

local function streak_lines(period, s)
    local unit, units = period == 'daily' and 'day' or 'week', period == 'daily' and 'days' or 'weeks'
    local line = ('Streak: %d %s in a row (best %d)%s'):format(s.count or 0, (s.count or 0) == 1 and unit or units, s.best or 0,
        s.today and ' - done ' .. (period == 'daily' and 'today' or 'this week') or '')
    local second
    if (s.next_in or 0) > 0 then
        second = ('Bonus in %d %s: %s'):format(s.next_in, s.next_in == 1 and unit or units, s.bonus or 'a reward')
    end
    return line, second
end

local function section(period, p, s, age, x, y, w)
    local cy = y
    ui.text((period == 'daily' and 'Daily quests' or 'Weekly quests') .. ('  %d/%d'):format(p.done or 0, #p.quests), x, cy, {color = GOLD, size = 16, bold = true})
    ui.text('new in ' .. left_text(p, age), x, cy + 2, {width = w, align = 'right', color = GREY, size = 12})
    cy = cy + 22
    if #p.quests == 0 then
        ui.text('No quests for this ' .. (period == 'daily' and 'day' or 'week') .. '.', x, cy, {color = GREY, size = 12})
        cy = cy + 18
    end
    for _, q in ipairs(p.quests) do
        row(q, x, cy, w)
        cy = cy + ROW + 6
    end
    if s then
        local a, b = streak_lines(period, s)
        ui.text(a, x, cy, {color = (s.count or 0) > 0 and GREEN or GREY, size = 12})
        cy = cy + 15
        if b then ui.text(b, x, cy, {color = GREY, size = 11}) cy = cy + 14 end
    end
    return cy - y + 10
end

local function panel()
    local p = ui.panel('quests', 'Daily and weekly quests' .. key_hint('quests'), 320, 70, 430, 460, {resizable = true, min_width = 340, min_height = 200})
    if not p.open then return end
    local x, y, w, h = p.content_x, p.content_y, p.content_w, p.content_h
    local m = mode()
    if not m then
        ui.text('Quests are off (setting "Daily and weekly quests").', x, y, {color = GREY})
        return
    end
    local v, age = current()
    if not v then
        local text = m == 'local' and 'Looking for your hero...'
            or ((not channel or not net.supported()) and 'This server has no daily quests (it needs the Sacred Gear game server with daily_quests.lua).'
                or 'Waiting for the server...')
        for i, line in ipairs(ui.text_wrap(text, w, {size = 12})) do ui.text(line, x, y + (i - 1) * 15, {color = GREY, size = 12}) end
        return
    end
    local waiting = m == 'local' and #H.data.pending or (v.pending or 0)
    local foot = (m == 'local' and 22 or 0)
    local area = ui.scroll_begin('quest-list', x, y, w, h - 4 - foot)
    local cy = area.content_y
    for _, period in ipairs(Q.PERIODS) do
        cy = cy + section(period, v[period], v.streak and v.streak[period], age, area.content_x, cy, area.w - 4)
    end
    ui.scroll_end(cy - area.content_y)
    if m == 'local' then
        ui.text(waiting > 0 and ('Rewards waiting: %d'):format(waiting) or 'Single player: your own quests, new ones every day and Monday.',
            x, y + h - 16, {color = waiting > 0 and GOLD or GREY, size = 11})
        if waiting > 0 and ui.button('quest-claim', x + w - 130, y + h - 20, 130, 18, 'Claim rewards',
            {tooltip = 'Pay the rewards of finished quests and streak bonuses now'}) then
            pay_pending()
        end
    end
end

local function tracker()
    if not gear.settings.get('quest_tracker') then return end
    local v = current()
    if not v then return end
    local lines = {}
    for _, period in ipairs(Q.PERIODS) do
        for _, q in ipairs(v[period].quests) do
            if not q.done then lines[#lines + 1] = {tag = period == 'daily' and 'D' or 'W', q = q} end
        end
    end
    local editing = ui.edit_mode()
    if #lines == 0 and not editing then return end
    local h = 18 + math.max(1, #lines) * 14
    local p = ui.panel('quest_tracker', 'Quest tracker', cfg.quest_tracker_x, cfg.quest_tracker_y, 240, h, {bare = true})
    ui.text('Quests', p.x, p.y, {color = GOLD, size = 13, bold = true, shadow = true})
    for i, e in ipairs(lines) do
        ui.text(('%s  %s  %d/%d'):format(e.tag, e.q.title, math.min(e.q.n or 0, e.q.target), e.q.target), p.x, p.y + 4 + i * 14,
            {color = 0xFFE0E0E0, size = 12, shadow = true})
    end
end

gear.on('draw', function(state)
    if not state or state.mode ~= 'game' or state.exclusive then return end
    tracker()
    panel()
end)

gear.keys.on('quests', function() ui.toggle_panel('quests') end)
if ui.menu_item then ui.menu_item('quests', 'Daily and weekly quests', function() ui.toggle_panel('quests') end) end

---------------------------------------------------------------------------------------------------------------------
-- Test aid for quests_selftest: moves the date, counts a kill, reports the state
---------------------------------------------------------------------------------------------------------------------

gear.on('bounty.test', function(ctx)
    local op = ctx.op
    if op == 'q_offset' then
        offset = ctx.seconds or 0
        if mode() == 'local' then tick_local() end
    elseif op == 'q_kill' then
        for _ = 1, ctx.count or 1 do
            local events = Q.kill(H.data, localboard.words(ctx.name), ctx.level or level_of() or 1, conf)
            if #events > 0 then H:changed() end
            publish(events)
        end
        rebuild()
        if gear.settings.get('auto_claim') ~= false then pay_pending() end
    elseif op == 'q_tick' then
        tick_local()
    elseif op == 'q_reset' then
        H.data = Q.new_state()
        H:changed()
        announced = false
        view = nil
    elseif op == 'q_save' then
        H:save()
    elseif op == 'q_pay' then
        pay_pending()
    elseif op == 'q_conf' then
        if ctx.conf then conf = Q.clean_config(ctx.conf) else load_conf() end
    elseif op == 'q_server' then
        -- a payload as the server would send it (a test of the display and the events of the network side)
        if valid(ctx.payload) then
            local old = server_view
            server_view, server_at = ctx.payload, gear.time()
            hooks.diff(old and Q.flatten(old) or nil, Q.flatten(ctx.payload), gear.emit, {source = 'server', claim_on_done = true, prefix = 'quest'})
            hooks.diff_streak(old, ctx.payload, gear.emit, {source = 'server'})
        end
    end
    ctx.q_mode, ctx.q_data, ctx.q_view, ctx.q_paying, ctx.q_now = mode(), H.data, view, paying, now()
end)

return R
