-- Achievements and login streak, the client side of the game server's scripts-examples/achievements.lua.
--
-- The server (Sacred.GameServer with that script) pushes {op = 'unlock' | 'streak' | 'state'} on the custom net channel
-- 'achievements:sync'; this mod shows a toast for the first two and keeps the last 'state' for a panel (Ctrl+G, rebind in the
-- Mods screen) with the streak, tomorrow's reward and every achievement with its progress. It asks for the state with
-- {op = 'get'} once the server's handshake is done and while the panel is open. Servers without the script, and the
-- original GameServer.exe, never answer: the panel then says so and nothing else happens.
local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local ui, net = gear.ui, gear.net

local ch = net.channel('achievements:sync')
local state = nil          -- the last {op = 'state'} table
local toast = gear.toast
toast.options({
    seconds = function() return gear.settings.get('seconds', 6) end,
    when = function(st) return st.mode == 'game' and gear.settings.get('toasts', true) end,
})

local function request()
    if ch and net.supported() then ch:send({op = 'get'}, 'server') end
end

if ch then
    ch:on(function(from, p)
        if type(p) ~= 'table' then return end
        if p.op == 'state' then
            state = p
        elseif p.op == 'unlock' then
            toast.show('Achievement unlocked', tostring(p.name or '?'), tostring(p.desc or ''),
                p.reward and ('Reward: ' .. p.reward) or nil)
        elseif p.op == 'streak' then
            toast.show(('Daily login: day %d'):format(tonumber(p.streak) or 0), p.reward and ('Reward: ' .. p.reward) or nil,
                ('Best streak: %d'):format(tonumber(p.best) or 0))
        end
    end)
end

gear.on('net_caps', function(caps)
    if caps.supported then request() else state = nil end
end)
gear.on('load', function() request() end)

local shown = false

-- keep the panel's numbers fresh while it is open
gear.every(30, function()
    if shown then request() end
end)

gear.keys.on('panel', function()
    shown = not shown
    if shown then request() end
end)

-- ---- drawing ----
-- ui/panel.rml (the game theme): the model holds ready-made strings; it is rebuilt when the server's state or the key hint changes.

local doc
local function plural(n, word) return ('%d %s%s'):format(n, word, n == 1 and '' or 's') end

local function snapshot()
    local m = {title = 'Achievements' .. key_hint('panel'), has_state = state ~= nil, msg = '', streak = '', reward = '', count = '', list = {}}
    if not state then
        m.msg = net.supported() and 'Waiting for the server...'
            or 'This server has no achievements.\nThey need the Sacred Gear game server with its achievements.lua script.'
        return m
    end
    local list = state.ach or {}
    local done = 0
    for _, a in ipairs(list) do if a.done then done = done + 1 end end
    m.streak = ('Login streak: %s, best %d, %s visited'):format(plural(state.streak or 0, 'day'), state.best or 0, plural(state.days or 0, 'day'))
    if state.next then
        m.reward = (state.claimed and "Today's reward is claimed. Tomorrow: " or "Today's reward: ") .. state.next
    end
    m.count = ('%d of %d unlocked'):format(done, #list)
    for i, a in ipairs(list) do
        local need = math.max(1, tonumber(a.need) or 1)
        local have = tonumber(a.have) or 0
        m.list[i] = {
            name = tostring(a.name), desc = tostring(a.desc), done = a.done and true or false,
            prog = a.done and 'Done' or ('%d / %d'):format(math.floor(have), math.floor(need)),
            pct = a.done and 100 or math.floor(math.min(1, have / need) * 100),
        }
    end
    return m
end

local last = {}
local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

gear.on('draw', function(st)
    if not st or st.mode ~= 'game' or st.exclusive or not shown then return end
    if not doc then
        local m = snapshot()
        last = m
        local err
        doc, err = ui.rml.load('ui/panel.rml', {dp = true, model = m})
        if not doc then gear.log('achievements: ui/panel.rml failed: ' .. tostring(err)) return end
    end
    for k, v in pairs(snapshot()) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
end)
