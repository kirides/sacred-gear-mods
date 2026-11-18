-- Wiring test of main.lua + localgame.lua against a fake `gear` that has a world: the server's spawn message (who may send it, the
-- dedupe, the weighted kinds, a game that cannot change the world) and the single player mode (kills in, state out, hooks fired,
-- the server taking over). Plain Lua 5.1 / LuaJIT, no game:  luajit tests/local_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

local function new_gear(opts)
    opts = opts or {}
    local g = {now = 1000, handlers = {}, sent = {}, channels = {}, settings = {}, spawned = {}, gold = 0, toasts = {}, logs = {}, files = {}, can_change = opts.can_change ~= false}
    g.log = function(t) g.logs[#g.logs + 1] = t end
    g.time = function() return g.now end
    g.on = function(event, fn) g.handlers[event] = g.handlers[event] or {}; table.insert(g.handlers[event], fn) end
    g.fire = function(event, ...) for _, fn in ipairs(g.handlers[event] or {}) do fn(...) end end
    g.creatures = {}
    local hero = {
        position = function() return 5000, 6000, 0 end, type = function() return 1 end, level = function() return 30 end,
        add_gold = function(_, n) g.gold = g.gold + n; return true end,
    }
    g.world = {
        hero = function() return hero end,
        can_change = function() return g.can_change end,
        creatures_near = function() return g.creatures end,
        spawn = function(type, x, y, o)
            if not g.can_change then return nil, 'single player only' end
            table.insert(g.spawned, {type = type, x = x, y = y, label = o and o.label}); return {id = 100 + #g.spawned}
        end,
        items_near = function() return {} end,
    }
    local types = {ORC_WARRIOR = 38, ORC_SHAMAN = 39}
    g.data = {object_types = {
        find = function(_, name) return types[name:upper():gsub('%.%w+$', '')] end,
        search = function(_, text) local out = {} for n, id in pairs(types) do if n:find(text:upper():gsub('%.$', ''), 1, true) then out[#out + 1] = {id = id, name = n, kind = 3} end end return out end,
        kind = function() return 3 end,
    }}
    g.store = {
        load = function(name, default) local v = g.files[name]; if v == nil then return default, 'missing' end return v end,
        save = function(name, v) g.files[name] = v; return true end,
        file = function(name, default) local f = {data = g.files[name .. '#state'] or default, changed = function() g.files[name .. '#state'] = nil end}; g.files[name .. '#h'] = f; return f end,
    }
    g.toast = {show = function(title, text) g.toasts[#g.toasts + 1] = title .. ': ' .. tostring(text) end}
    g.net = {
        supported = function() return true end,
        channel = function(name)
            local ch = {name = name, listeners = {}}
            function ch:on(fn) table.insert(self.listeners, fn); return fn end
            function ch:send(payload, to) table.insert(g.sent, {name = name, payload = payload, to = to}); return true end
            g.channels[name] = ch
            return ch
        end,
    }
    g.texts, g.panel_asks, g.rects = {}, {}, {}
    g.panel_h = nil
    g.ui = {
        panel = function(id, title, x, y, w, h)
            g.panel_asks[#g.panel_asks + 1] = h
            g.panel_kept = g.panel_kept or h          -- the first size asked for is kept (the layout file), later asks are ignored
            return {open = true, key = 'world-events:' .. id, content_x = x, content_y = y, content_w = w, content_h = g.panel_h or g.panel_kept}
        end,
        set_panel_rect = function(key, x, y, w, h) g.rects[#g.rects + 1] = {key = key, h = h}; g.panel_h = h; return true end,
        mouse = function() return 0, 0 end, text_size = function(t) return #t * 6, 12 end, tooltip_rect = function() return 0, 0 end,
        show_panel = function() end, text = function(t, x, y) g.texts[#g.texts + 1] = {t = t, y = y} end, rect = function() end, frame = function() end,
        edit_mode = function() return g.edit end, menu_item = function() end,
    }
    g.regions_api = nil
    g.data.regions = opts.regions
    g.gear = {on = g.on, time = g.time, log = g.log, net = g.net, ui = g.ui, world = g.world, data = g.data, store = g.store, toast = g.toast,
        settings = {get = function(id) return g.settings[id] end, set = function(id, v) g.settings[id] = v end}, task = function(fn) fn() end}
    return g
end

local function load_mod(g)
    for _, name in ipairs({'core', 'hooks', 'localevents', 'localgame'}) do package.loaded[name] = nil end
    _G.gear = g.gear
    return assert(loadfile('main.lua'))()
end

-- ---- the server's spawn message ------------------------------------------------------------------------------------------
local g = new_gear()
local mod = load_mod(g)
local spawn = g.channels['worldevents:spawn']
check(spawn ~= nil, 'the spawn channel is created')
local msg = {v = 1, id = '1:h2:1:abcd1234', event = 'Orc hunt', n = 4, radius = 500, kinds = {{type = 'Orc Warrior', weight = 3}, {type = 'Orc Shaman', weight = 1}}, text = 'Here they come!'}
for _, fn in ipairs(spawn.listeners) do fn({slot = 2}, msg) end
eq(#g.spawned, 0, 'a wave from another player is ignored')
for _, fn in ipairs(spawn.listeners) do fn({slot = 0}, msg) end
eq(#g.spawned, 4, 'the server asks for four creatures')
local near = true
for _, c in ipairs(g.spawned) do
    local d = math.sqrt((c.x - 5000) ^ 2 + (c.y - 6000) ^ 2)
    if d > 501 or d < 199 or c.type ~= 38 and c.type ~= 39 then near = false end
end
check(near, 'around the hero, inside the radius, of the right kinds')
eq(g.spawned[1].label, 'world-events', 'labelled')
eq(g.toasts[1], 'Orc hunt: Here they come!', 'the text shows as a toast')
for _, fn in ipairs(spawn.listeners) do fn({slot = 0}, msg) end
eq(#g.spawned, 4, 'the same wave id spawns once')
msg.id = '1:h2:1:other'; msg.n = 500
for _, fn in ipairs(spawn.listeners) do fn({slot = 0}, msg) end
eq(#g.spawned, 4, 'a wave above the cap is refused')
msg.id = '1:h2:1:third'; msg.n = 2; msg.kinds = {{type = 'Nonsense Beast'}}
for _, fn in ipairs(spawn.listeners) do fn({slot = 0}, msg) end
eq(#g.spawned, 4, 'an unknown creature is skipped, nothing crashes')
eq(mod.waves[#mod.waves].made, 0, 'and reported as made 0')
for _, fn in ipairs(spawn.listeners) do fn({slot = 0}, {id = 'zzz'}) end
check(#g.logs > 0, 'a broken message is logged')

-- a network game: Gear refuses to spawn; the wave is dropped with a log line
local gn = new_gear({can_change = false})
local modn = load_mod(gn)
local before = #gn.logs
for _, fn in ipairs(gn.channels['worldevents:spawn'].listeners) do fn({slot = 0}, {id = 'net1', n = 2, kinds = {{type = 'Orc Warrior'}}}) end
eq(#gn.spawned, 0, 'no creatures in a network game'); check(#gn.logs > before, 'the refusal is logged'); eq(modn.waves[1].made, 0, 'wave outcome 0')

-- ---- the single player mode --------------------------------------------------------------------------------------------------
local gs = new_gear()
gs.files.events = {
    v = 1, config = {first_delay = 5, cooldown = 10, result_hold = 10},
    events = {{id = 'e', title = 'Local hunt', target = 2, duration = 300, names = {'orc'}, unit = 'orcs', hooks = {
        {at = 50, actions = {{action = 'spawn', n = 3, kinds = {{type = 'Orc Warrior'}}, radius = 300}, {action = 'gold', amount = 77}, {action = 'message', text = 'Halfway'}}},
        {on = 'success', actions = {{action = 'gold', amount = 1000}}},
    }}},
}
local ms = load_mod(gs)
local function step(seconds, n)
    for _ = 1, n or 1 do gs.now = gs.now + seconds; gs.fire('frame', 0.016) end
end
-- creatures the hero hits and that then die (what localgame.poll watches)
local function creature(id, name, type)
    local c = {id = id, dead = false, exists_ = true}
    function c:is_dead() return self.dead end
    function c:exists() return self.exists_ end
    function c:type() return type end
    function c:type_name() return name end
    function c:position() return 5100, 6000 end
    return c
end
step(1, 1)                                  -- the mod has waited LOCAL_AFTER seconds without a server (time since 1000 is 1 > -1e9 + 15)
local state = ms.local_events()
check(state ~= nil, 'the local mode starts without a server')
eq(state:payload(), nil, 'nothing before the first delay')
step(1, 6)
local p = state:payload()
check(p and p.st == 'active' and p.title == 'Local hunt', 'the event starts after its delay')
check(ms.model.state and ms.model.state.st == 'active' and ms.model.state.title == 'Local hunt', 'the bar got the local state')
-- the first kill: the hero hits an orc, it dies
local orc1 = creature(50, 'Orc Warrior', 38)
gs.creatures = {orc1}
step(0.3, 1)
gs.fire('damage', {attacker_type = 1, victim_type = 38})
orc1.dead = true
step(0.3, 1)
eq(state:payload().count, 1, 'a kill of the hero counts')
check(#gs.spawned == 3, 'the 50% hook spawned a wave of three around the hero')
eq(gs.gold, 77, 'and paid its gold')
check(gs.toasts[#gs.toasts]:find('Halfway', 1, true) ~= nil, 'and told the hero')
-- a creature that dies without the hero's hit does not count
local orc2 = creature(51, 'Orc Shaman', 39)
gs.creatures = {orc2}
step(0.3, 1); orc2.dead = true
gs.fire('damage', {attacker_type = 7, victim_type = 99})
step(0.3, 1)
eq(state:payload().count, 1, 'a creature the hero did not hit does not count')
-- the second kill ends the event; the success hook pays
local orc3 = creature(52, 'Orc Warrior', 38)
gs.creatures = {orc3}
step(0.3, 1); gs.fire('damage', {attacker_type = 1, victim_type = 38}); orc3.dead = true
step(0.3, 1)
eq(gs.gold, 1077, 'the success hook paid')
step(1.1, 1)
check(ms.model.state and ms.model.state.st == 'won', 'the bar shows the result')
-- a server that speaks up takes over: no more local feeding
for _, fn in ipairs(gs.channels['worldevents:state'].listeners) do fn({slot = 0}, {st = 'active', title = 'Server event', text = 'x', count = 1, target = 10, left = 100, dur = 100, here = true, n = 7}) end
step(2, 3)
eq(ms.model.state.title, 'Server event', 'the server state is kept while a server pushes')
gs.settings.local_mode = 'off'

-- local mode off / no world API
local goff = new_gear(); goff.settings.local_mode = 'off'
local moff = load_mod(goff)
goff.now = goff.now + 20; goff.fire('frame', 0.016)
eq(moff.local_events(), nil, 'switched off: nothing runs')
local gnoworld = new_gear(); gnoworld.gear.world = nil
local mnw = load_mod(gnoworld)
gnoworld.now = gnoworld.now + 20; gnoworld.fire('frame', 0.016)
eq(mnw.local_events(), nil, 'an older Gear without the world API: nothing runs, nothing breaks')
-- a first run writes the default file
local gfirst = new_gear()
local mfirst = load_mod(gfirst)
gfirst.now = gfirst.now + 20; gfirst.fire('frame', 0.016)
check(type(gfirst.files.events) == 'table' and #gfirst.files.events.events >= 1, 'a first run writes a default events.json to edit')

-- ---- the stack of pills: several events and the region boss pill in one movable group ---------------------------------------------------
local function title_order(g)
    local out = {}
    for _, t in ipairs(g.texts) do
        if t.t == 'Wolf hunt' or t.t == 'Orc hunt' or t.t == 'Thieves' or t.t == 'Desert' or t.t == 'Other' then out[#out + 1] = t.t end
    end
    return table.concat(out, ',')
end
local desert = {id = 4, index = 4, name = 'Desert', kills_needed = 8500, kills_left = 5200}
local gp = new_gear({regions = {count = function() return 5 end, get = function() return nil end, of_creature = function() return desert end}})
gp.settings.local_mode = 'off'
local mp = load_mod(gp)
local function ev_state(n, title, left) return {st = 'active', n = n, title = title, text = 'x', count = 10, target = 100, left = left, dur = 3600, here = true, unit = 'orcs'} end
local function draw(g) g.texts = {}; g.fire('draw', {mode = 'game', show_text = false}) end
for _, fn in ipairs(gp.channels['worldevents:state'].listeners) do fn({slot = 0}, {v = 1, list = {ev_state(1, 'Orc hunt', 3000), ev_state(2, 'Wolf hunt', 600)}}) end
draw(gp)
eq(title_order(gp), 'Wolf hunt,Orc hunt,Desert', 'two events (least time left first) and the region pill, in one group')
eq(gp.panel_asks[#gp.panel_asks], 3 * 46 + 2 * 4, 'one panel, as high as its three pills')
eq(#gp.rects, 0, 'the panel had the right height: nothing to resize')
-- the region pill goes away outside a region and the panel shrinks to its pills, keeping its place
gp.data.regions.of_creature = function() return nil end
gp.now = gp.now + 1
draw(gp)
eq(title_order(gp), 'Wolf hunt,Orc hunt', 'outside a region no region pill')
eq(gp.rects[#gp.rects].h, 2 * 46 + 4, 'the panel shrinks to two pills')
-- more than the cap: a "+N more" line
local five = {}
for i = 1, 5 do five[i] = ev_state(i, i == 1 and 'Orc hunt' or i == 2 and 'Wolf hunt' or 'Thieves', i * 100) end
for _, fn in ipairs(gp.channels['worldevents:state'].listeners) do fn({slot = 0}, {v = 1, list = five}) end
gp.now = gp.now + 1
draw(gp)
local plus
for _, t in ipairs(gp.texts) do if t.t:find('more', 1, true) then plus = t.t end end
eq(plus, '+1 more', 'a fifth event is a "+1 more" line')
eq(gp.rects[#gp.rects].h, 4 * 46 + 3 * 4 + 14, 'the panel grows by the line')
-- the setting switches the region pill off
gp.data.regions.of_creature = function() return desert end
gp.settings.region_pill = false
gp.now = gp.now + 1
for _, fn in ipairs(gp.channels['worldevents:state'].listeners) do fn({slot = 0}, {v = 1, list = {ev_state(1, 'Orc hunt', 3000)}}) end
draw(gp)
eq(title_order(gp), 'Orc hunt', 'the setting switches the region pill off')
gp.settings.region_pill = nil
gp.now = gp.now + 1
draw(gp)
eq(title_order(gp), 'Orc hunt,Desert', 'and on again (the default)')
-- a Gear without gear.data.regions: the events alone, no error
local gold = new_gear(); gold.settings.local_mode = 'off'
load_mod(gold)
for _, fn in ipairs(gold.channels['worldevents:state'].listeners) do fn({slot = 0}, ev_state(1, 'Orc hunt', 100)) end
draw(gold)
eq(title_order(gold), 'Orc hunt', 'no region API: only the event')
-- region pill only (no event): it shows alone
local alone = new_gear({regions = {count = function() return 5 end, get = function() return nil end, of_creature = function() return desert end}}); alone.settings.local_mode = 'off'
load_mod(alone)
draw(alone)
eq(title_order(alone), 'Desert', 'a region pill without any event')

print(('world-events local: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
