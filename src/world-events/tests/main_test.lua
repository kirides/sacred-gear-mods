-- Wiring test of main.lua against a fake `gear`: the channel, who may push, the hello, what is drawn when. Plain
-- Lua 5.1 / LuaJIT, no game:  luajit tests/main_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end

local function new_gear()
    local g = {now = 1000, handlers = {}, calls = {}, sent = {}, settings = {visibility = 'always', area = 'sector', results = true, pulse = true},
        supported = true, edit = false, menu = {}, channels = {}, panels = {}, rects = {}, mouse = {0, 0}}
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
            if g.kept then w, h = g.kept.w, g.kept.h end
            return {open = true, key = 'world-events:' .. id, x = x, y = y, w = w, h = h, content_x = x, content_y = y, content_w = w, content_h = h}
        end,
        set_panel_rect = function(key, x, y, w, h) table.insert(g.rects, {key = key, w = w, h = h}); g.kept = nil; return true end,
        mouse = function() return g.mouse[1], g.mouse[2] end,
        text_size = function(text, font) return #text * ((font and font.size or 12) * 0.5), 12 end,
        tooltip_rect = function() return 500, 300 end,
        show_panel = function() end,
        text = function(text) table.insert(g.calls, 'text:' .. text) end,
        rect = function(x, y, w, h, c) table.insert(g.calls, 'rect'); g.rect_n = (g.rect_n or 0) + 1 end,
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

local pushed = {st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', unit = 'orcs', count = 370, target = 1000, left = 4325, dur = 7200,
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
check(#g.panels == 1 and g.panels[1].id == 'bar', 'the pill is the panel bar')
check(g.panels[1].opts.bare == true and g.panels[1].opts.resizable == true, 'a bare, resizable panel (the layout editor moves it)')
check(has(g, 'text:Orc hunt'), 'title')
check(has(g, 'text:370 / 1,000 orcs'), 'count and unit')
check(has(g, '1:12:05'), 'time left')
check(has(g, 'text:37%'), 'percentage in the ring')
check(not has(g, 'Your share') and not has(g, 'Slay 1000'), 'no details without hover or Alt')

-- details: Alt, hover, pinned from the controller menu
draw(g, {mode = 'game', show_text = true})
check(has(g, 'text:Slay 1000 orcs') and has(g, 'Your share: 12') and has(g, 'Time left: 1:12:05') and has(g, 'Reward: gold'), 'Alt shows the details')
g.mouse = {450, 60}
draw(g)
check(has(g, 'Your share: 12'), 'hover shows the details (the pill is at 402,40, 220 x 46)')
g.mouse = {0, 0}
draw(g)
check(not has(g, 'Your share'), 'cursor away: no details')
g.menu.details.fn()
draw(g)
check(has(g, 'Your share: 12'), 'the controller menu pins the details')
g.menu.details.fn()
draw(g)
check(not has(g, 'Your share'), 'and unpins them')

-- a bigger kept size of an older version is brought back
g.kept = {w = 300, h = 86}
draw(g)
check(#g.rects == 1 and g.rects[1].key == 'world-events:bar' and g.rects[1].w <= 220 and g.rects[1].h <= 46, 'an old kept size 300 x 86 is reset')
g.kept = {w = 200, h = 40}
draw(g)
check(#g.rects == 1, 'a small kept size stays')

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
-- the pulse at a quarter mark draws a second pill
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, {st = 'active', title = 'T', text = 'x', unit = 'u', count = 100, target = 1000, left = 100, dur = 200, here = true, n = 5}) end
draw(g); local plain = g.rect_n
g.rect_n = 0; draw(g); plain = g.rect_n
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, {st = 'active', title = 'T', text = 'x', unit = 'u', count = 260, target = 1000, left = 100, dur = 200, here = true, n = 5}) end
g.rect_n = 0; draw(g)
check(g.rect_n > plain, 'crossing 25 % pulses (more rectangles)')
g.now = g.now + 3
g.rect_n = 0; draw(g)
check(g.rect_n == plain, 'the pulse is over after a moment')
g.settings.pulse = false
for _, fn in ipairs(ch.listeners) do fn({slot = 0}, {st = 'active', title = 'T', text = 'x', unit = 'u', count = 510, target = 1000, left = 100, dur = 200, here = true, n = 5}) end
g.rect_n = 0; draw(g)
check(g.rect_n == plain, 'pulse off: no pulse')
g.settings.pulse = true
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
check(has(g, 'text:Completed!'), 'the result is one short line')
check(not has(g, '1:12:0'), 'a result has no timer')
g.now = g.now + 31
draw(g)
check(#g.panels == 0, 'and goes after the hold')

-- the configure hook sets settings
g.fire('world-events.configure', {visibility = 'alt', area = 'everywhere'})
check(g.settings.visibility == 'alt' and g.settings.area == 'everywhere', 'world-events.configure sets settings')
g.settings.visibility, g.settings.area = 'always', 'sector'

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
