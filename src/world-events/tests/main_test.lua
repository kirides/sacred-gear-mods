-- Wiring test of main.lua against a fake `gear`: the channel, who may push, the hello, what is drawn when. Plain
-- Lua 5.1 / LuaJIT, no game:  luajit tests/main_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end

local function new_gear()
    local g = {now = 1000, handlers = {}, calls = {}, sent = {}, settings = {visibility = 'always', area = 'sector', results = true},
        supported = true, edit = false, menu = {}, channels = {}, panels = {}}
    g.log = function() end
    g.time = function() return g.now end
    g.on = function(event, fn) g.handlers[event] = g.handlers[event] or {}; table.insert(g.handlers[event], fn) end
    g.fire = function(event, ...) for _, fn in ipairs(g.handlers[event] or {}) do fn(...) end end
    g.settings_api = {
        get = function(id) return g.settings[id] end,
        set = function(id, v) g.settings[id] = v end,
    }
    g.net = {
        supported = function() return g.supported end,
        channel = function(name)
            local ch = {name = name, listeners = {}}
            function ch:on(fn) table.insert(self.listeners, fn); return fn end
            function ch:send(payload, to) table.insert(g.sent, {name = name, payload = payload, to = to}); return true end
            g.channels[name] = ch
            return ch
        end,
    }
    g.ui = {
        panel = function(id, title, x, y, w, h, opts)
            table.insert(g.panels, {id = id, title = title, opts = opts})
            return {open = true, x = x, y = y, w = w, h = h, content_x = x + 6, content_y = y + 20, content_w = w - 12, content_h = h - 26}
        end,
        show_panel = function() end,
        text = function(text) table.insert(g.calls, 'text:' .. text) end,
        rect = function() table.insert(g.calls, 'rect') end,
        frame = function() table.insert(g.calls, 'frame') end,
        edit_mode = function() return g.edit end,
        menu_item = function(id, label, fn) g.menu[id] = {label = label, fn = fn} end,
    }
    g.gear = {
        on = g.on, time = g.time, log = g.log, net = g.net, ui = g.ui, settings = g.settings_api,
    }
    return g
end

local function load_mod(g)
    package.loaded['core'] = nil
    _G.gear = g.gear
    local chunk = assert(loadfile('main.lua'))
    chunk()
end

local function draw(g, state)
    g.calls, g.panels = {}, {}
    g.fire('draw', state or {mode = 'game', show_text = false})
end

local function has(g, needle)
    for _, c in ipairs(g.calls) do if c:find(needle, 1, true) then return true end end
    return false
end

local pushed = {st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', count = 370, target = 1000, left = 4325, dur = 7200,
    here = true, mine = 12, need = 10, people = 5, reward = 'gold', n = 1}

-- 1. a game with a server that supports the messages
local g = new_gear()
load_mod(g)
local ch = g.channels['worldevents:state']
check(ch ~= nil, 'the channel is created at load')
check(g.menu.visibility ~= nil, 'the controller menu entry exists')
g.fire('session.start', {})
check(#g.sent == 1 and g.sent[1].to == 'server' and g.sent[1].payload.hello == 1, 'hello to the server at session start')
g.now = g.now + 5
g.fire('frame', 0.016)
check(#g.sent == 1, 'no second hello within 30 s')
g.now = g.now + 31
g.fire('frame', 0.016)
check(#g.sent == 2, 'hello again after 30 s')
g.fire('net_caps', {supported = true, peers = {1}})
check(#g.sent == 3, 'hello when the messages become available')

draw(g)
check(#g.panels == 0, 'nothing drawn before a state')
for _, fn in ipairs(ch.listeners) do fn({slot = 3}, pushed) end
draw(g)
check(#g.panels == 0, 'a push from another player is ignored')
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, 'bytes') end
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, pushed) end
draw(g)
check(#g.panels == 1 and g.panels[1].title == 'Orc hunt', 'the bar is a panel titled with the event')
check(g.panels[1].opts.closable == false and g.panels[1].opts.draggable ~= false, 'movable, not closable')
check(has(g, 'text:Slay 1000 orcs'), 'goal text')
check(has(g, '37%   370 / 1,000'), 'percentage and count')
check(has(g, 'text:1:12:05'), 'time left')
check(has(g, 'Your share: 12'), 'own share')

-- visibility: only while Alt is held
g.settings.visibility = 'alt'
draw(g, {mode = 'game', show_text = false})
check(#g.panels == 0, 'alt mode: hidden without Alt')
draw(g, {mode = 'game', show_text = true})
check(#g.panels == 1, 'alt mode: shown with Alt')
g.edit = true
draw(g, {mode = 'game', show_text = false})
check(#g.panels == 1, 'the layout editor always shows the bar')
g.edit = false
g.settings.visibility = 'always'
-- not in the game screen
draw(g, {mode = 'menus'})
check(#g.panels == 0, 'no bar in the menus')
draw(g, {mode = 'game', exclusive = 'UI_WND_OPTIONS'})
check(#g.panels == 0, 'no bar under a full-screen window')

-- the controller menu entry flips the setting
g.menu.visibility.fn()
check(g.settings.visibility == 'alt', 'menu entry: always -> alt')
g.menu.visibility.fn()
check(g.settings.visibility == 'always', 'menu entry: alt -> always')

-- area
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, {st = 'active', title = 'X', text = 'y', count = 1, target = 2, left = 5, here = false}) end
draw(g)
check(#g.panels == 0, 'elsewhere: hidden')
g.settings.area = 'everywhere'
draw(g)
check(#g.panels == 1, 'everywhere: shown')
g.settings.area = 'sector'

-- results
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, {st = 'won', title = 'Orc hunt', text = 'x', count = 1000, target = 1000, hold = 30, here = true, people = 3}) end
draw(g)
check(has(g, 'text:Completed!'), 'the result is shown')
g.now = g.now + 31
draw(g)
check(#g.panels == 0, 'and goes after the hold')

-- a bar from the emit hook (other mods, tests)
g.fire('world-events.state', pushed)
draw(g)
check(#g.panels == 1, 'world-events.state feeds the bar')
g.fire('session.stop')
draw(g)
check(#g.panels == 0, 'session.stop clears it')

-- 2. a server without the messages: no hello, nothing shown, no errors
local g2 = new_gear()
g2.supported = false
load_mod(g2)
g2.fire('session.start', {})
g2.fire('frame', 0.016)
check(#g2.sent == 0, 'no hello without server support')
draw(g2)
check(#g2.panels == 0, 'nothing without a state')

-- 3. no gear.net at all (an old Sacred Gear): loads, draws nothing
local g3 = new_gear()
g3.gear.net = nil
load_mod(g3)
g3.fire('session.start', {})
draw(g3)
check(#g3.panels == 0, 'no gear.net: no bar, no error')

print(('world-events main: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
