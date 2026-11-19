-- World events: a small movable indicator for the realm-wide goal the game server runs (the server script world_events.lua,
-- see README.md): a dark pill with a double ring (gold: the progress, blue: the time left) and two lines of text. The
-- server pushes the state over the custom net channel 'worldevents:state'; this mod only displays it.
-- It binds no key and has no buttons: the pill is moved in the layout editor (hold Alt, "Edit layout"), the details show on hover or
-- while Alt is held, its settings are on its page of the Mods screen, and the controller's mod menu has entries that switch
-- "always / only with Alt" and pin the details.
local core = require('core')
local hooks = require('hooks')
local wevents = require('events')
local localevents = require('localevents')
local bosses = require('bosses')
local regions = require('regions')
local ui, S = gear.ui, gear.settings

local CHANNEL = 'worldevents:state'
local SPAWN_CHANNEL = 'worldevents:spawn'     -- the server asks THIS game to spawn a wave around its own hero (only the target's client does)
local LOCAL_AFTER = 15      -- seconds without a state from a server until the mod runs the events itself (single player / LAN)
local HELLO_EVERY = 30      -- seconds: asks the server for the state again (a lost push, a server that restarted)

local model = core.new()
local channel
local last_hello = -1e9
local pulse_until = 0       -- gear.time() until which the pill pulses (a 25 / 50 / 75 % mark was crossed)
local pinned = false        -- the details stay up (the controller's mod menu)

local PULSE = 1.6

local last_server = -1e9    -- gear.time() of the last state a server pushed

-- Hooks for other mods (README: Hooks): the states the bar receives, compared with the ones before.
if gear.events then
    for _, e in ipairs(wevents.EVENTS) do gear.events.declare(e[1], {doc = e[2], args = e[3] or wevents.ARGS}) end
end

local function emit_hook(name, p) local ok, err = pcall(gear.emit, name, p) if not ok then gear.log('world-events: ' .. name .. ': ' .. tostring(err)) end end

local function feed(payload, source)
    local before = model.states or (model.state and {model.state}) or nil
    local ok, crossed = model:receive(payload, gear.time())
    if ok then
        local after = model.states or (model.state and {model.state}) or {}
        local good, err = pcall(wevents.diff, before, after, emit_hook, source or 'server')
        if not good then gear.log('world-events: hooks: ' .. tostring(err)) end
    end
    if ok and crossed and S.get('pulse') ~= false then pulse_until = gear.time() + PULSE end
end

local function ensure_channel()
    if channel then return channel end
    local net = gear.net
    if not (net and net.channel) then return nil end
    local ch, err = net.channel(CHANNEL)
    if not ch then
        gear.log('world-events: no channel (' .. tostring(err) .. ')')
        return nil
    end
    ch:on(function(from, payload)
        -- only the server pushes states (slot 0); a message from another player is ignored
        if from and from.slot == 0 and type(payload) == 'table' then last_server = gear.time(); feed(payload) end
    end)
    channel = ch
    return ch
end

---------------------------------------------------------------------------------------------------------------
-- spawn waves (a hook's `spawn` action of the server)
---------------------------------------------------------------------------------------------------------------
-- The mod's JSON files: gear.store where this Gear has it, else a small stand-in on gear.read / gear.save (an older SacredGear.dll).
local function files()
    if gear.store then return gear.store end
    if not (gear.read and gear.save and gear.json) then return nil end
    local api = {}
    function api.load(name, default)
        local text = gear.read(name)
        if not text then return default, 'missing' end
        local ok, value = pcall(gear.json.decode, text)
        if ok and type(value) == 'table' then return value end
        return default, 'invalid'
    end
    function api.save(name, value)
        local ok, text = pcall(gear.json.encode, value)
        if not ok then return false, text end
        return gear.save(name, text)
    end
    function api.file(name, default)
        local h = {name = name, data = (api.load(name, default)), saved = 0, dirty = false}
        function h:changed()
            self.dirty = true
            local now = gear.time()
            if now - self.saved >= 10 then self.saved = now; self.dirty = false; api.save(self.name, self.data) end
        end
        return h
    end
    return api
end
local FILES = files()

local G                      -- localgame.lua, when this Gear has the world API
if gear.world and FILES then
    local ok, mod = pcall(require, 'localgame')
    if ok then G = mod else gear.log('world-events: no game binding (' .. tostring(mod) .. ')') end
end
local seen = hooks.seen(200)
local M_spawn_boss              -- the boss manager, below
local spawn_channel
local waves = {}             -- the outcome of the last waves: {id, made, why}

-- One wave the server asked for. Gear can only create creatures in a game of its own (single player); in a network game the
-- request is logged and dropped. The wave id drops a message that arrives twice.
local function on_spawn(wave)
    if not seen:add(wave.id) then return end
    if not G then waves[#waves + 1] = {id = wave.id, made = 0, why = 'no world API'}; return end
    if wave.boss then
        local ok, why2 = M_spawn_boss(wave.boss, wave.event ~= '' and wave.event or 'World event', wave.text, 'server')
        waves[#waves + 1] = {id = wave.id, made = ok and 1 or 0, why = why2}
        if #waves > 20 then table.remove(waves, 1) end
        if not ok then gear.log('world-events: the boss ' .. wave.id .. ' was not made: ' .. tostring(why2)) end
        return
    end
    local made, why = G.spawn_wave(wave)
    waves[#waves + 1] = {id = wave.id, made = made, why = why}
    if #waves > 20 then table.remove(waves, 1) end
    gear.log(('world-events: wave %s: %d creatures made%s'):format(wave.id, made, why and (' (' .. why .. ')') or ''))
    emit_hook('worldevent.hook', {title = wave.event, action = 'spawn', text = wave.text, source = 'server'})
    if made == 0 then gear.log('world-events: the wave ' .. wave.id .. ' was not spawned: ' .. tostring(why)) end
    if wave.text and wave.text ~= '' then G.message(wave.event ~= '' and wave.event or 'World event', wave.text) end
end

local function ensure_spawn_channel()
    if spawn_channel then return spawn_channel end
    local net = gear.net
    if not (net and net.channel) then return nil end
    local ch = net.channel(SPAWN_CHANNEL)
    if not ch then return nil end
    ch:on(function(from, payload)
        if not (from and from.slot == 0) then return end         -- only the server asks for waves
        local wave, why = hooks.parse_spawn(payload)
        if not wave then gear.log('world-events: bad spawn message (' .. tostring(why) .. ')'); return end
        on_spawn(wave)
    end)
    spawn_channel = ch
    return ch
end

local function hello(force)
    local now = gear.time()
    if not force and now - last_hello < HELLO_EVERY then return end
    local net = gear.net
    if not (net and net.supported and net.supported()) then return end
    local ch = ensure_channel()
    if not ch then return end
    last_hello = now
    ch:send({hello = 1, v = 1}, 'server')
end

ensure_channel()
ensure_spawn_channel()

gear.on('net_caps', function() hello(true) end)
gear.on('session.start', function() model:reset(); hello(true) end)
gear.on('session.stop', function() model:reset(); last_hello = -1e9 end)
local local_frame     -- the single player mode, below
gear.on('frame', function() hello(false); if local_frame then local_frame() end end)

-- Other mods (and the self test) can steer it: gear.emit('world-events.configure', {visibility = 'alt', area = 'everywhere'}) sets those settings.
gear.on('world-events.configure', function(values)
    for id, value in pairs(values or {}) do S.set(id, value) end
end)
-- ... and feed a state: gear.emit('world-events.state', {st = 'active', ...}).
gear.on('world-events.state', feed)
-- ... and a wave: gear.emit('world-events.spawn', {id = 'x1', n = 3, radius = 400, kinds = {{type = 'Orc Warrior', weight = 1}}}) spawns it for the hero
-- (what the server's 'worldevents:spawn' message does; the self test uses it).
gear.on('world-events.spawn', function(payload)
    local wave = hooks.parse_spawn(payload)
    if wave then on_spawn(wave) end
end)

-- The single player mode: no server pushed a state for LOCAL_AFTER seconds, so this mod runs the events of its own events.json
-- (a server's `/mods/world_events/export` writes one; a first run writes a small default to edit): it counts the hero's kills, fires
-- the hooks for the hero and feeds the bar the same table a server would push. A server that speaks up again takes over.
local localmode, local_file
local kill_hooked = false
local last_frame, last_feed, last_poll = nil, -1e9, -1e9
local fed_local = false      -- the bar currently shows a state of the local mode

local function local_on()
    return G ~= nil and S.get('local_mode') ~= 'off' and gear.time() - last_server > LOCAL_AFTER
end

local function start_local()
    if localmode or not G then return end
    -- The run of events (the count, the running one, the wait) belongs to the savegame: kept per savegame (an older Gear keeps one
    -- file for all of them); another game starts its own run (see the handler of savegame.changed below).
    if not local_file then
        local_file = (FILES.game or FILES.file)('local_events_state.json', {}, {every = 10})
    end
    local defs = FILES.load('events.json', nil)
    if defs == nil then
        defs = localevents.DEFAULT
        FILES.save('events.json', defs)                        -- a first run: a file to edit
    end
    localmode = localevents.new({
        defs = defs, store = local_file.data, log = function(t) gear.log('world-events: ' .. t) end,
        act = function(action, ctx, key, index, def)
            if action.action == 'boss' then
                local ok, why = M_spawn_boss(action.boss, def and def.title or 'World event', action.text, 'local')
                if not ok then gear.log('world-events: boss failed: ' .. tostring(why)) end
            else
                G.run_action(action, def and def.title or 'World event')
            end
            emit_hook('worldevent.hook', {title = def and def.title, id = localmode and localmode.store.current and localmode.store.current.n,
                action = action.action, text = action.text, source = 'local'})
        end,
    })
    if not kill_hooked then
        kill_hooked = true
        G.on_kill(function(name, type_id, sector, region) if localmode then localmode:kill(name, type_id, sector, region) end end)
    end
end

-- Another savegame (or a new game) is going: the run of events of the old one is dropped, the next frame starts the new one's from
-- what that game kept. Progress since the last save is gone with the game's own.
gear.on('savegame.changed', function()
    localmode, last_frame = nil, nil
    if fed_local then model:reset(); fed_local = false end
end)

function local_frame()
    if not local_on() then last_frame = nil; return end
    start_local()
    if not localmode then return end
    local now = gear.time()
    local dt = last_frame and (now - last_frame) or 0
    last_frame = now
    if now - last_poll >= 0.25 then last_poll = now; pcall(G.poll) end
    local ok, err = pcall(localmode.tick, localmode, dt)
    if not ok then gear.log('world-events: local tick failed: ' .. tostring(err)) end
    if localmode.changed then localmode.changed = false; local_file:changed() end
    if now - last_feed >= 1 then
        last_feed = now
        local payload = localmode:payload()
        if payload then feed(payload, 'local'); fed_local = true
        elseif fed_local then model:reset(); fed_local = false end
    end
end

-- A kill reported by the game's `kill` event (network games): counts in the local mode too.
gear.on('kill', function(kill)
    if localmode and local_on() and type(kill) == 'table' then
        pcall(localmode.kill, localmode, kill.name or kill.victim_name, kill.type or kill.victim_type, kill.sector, kill.region)
    end
end)

---------------------------------------------------------------------------------------------------------------
-- the pill
---------------------------------------------------------------------------------------------------------------
local W, H = 220, 46                -- the panel's default size (layout units); the layout editor can change both
local X, Y = 402, 40                -- top centre, clear of the minimap and the action bar

local COLOR = {
    pill = 0x59101014,              -- about 35 % opaque
    glow = 0x55E3B341,
    ring = 0xFFE3B341, ring_off = 0x30E3B341,
    time = 0xFF86C3F2, time_off = 0x2886C3F2, time_late = 0xFFE88A68,
    won = 0xFF63C269, failed = 0xFFB86060,
    title = 0xFFF2D58A, count = 0xFFD2CCBE, timer = 0xFF9CCBF5, percent = 0xFFFFF2D0,
    region = 0xFF6FC2B8, region_off = 0x306FC2B8, region_title = 0xFFA9E3DC, region_glow = 0x556FC2B8,     -- the region boss pill: teal, not the events' gold
    tip_back = 0xE60E0E14, tip_edge = 0xFF5A4A36, tip_text = 0xFFE6DFD0, tip_title = 0xFFF2D58A,
}

-- A color with its opacity multiplied by `factor` (0..1).
local function with_alpha(color, factor)
    if factor >= 1 then return color end
    local a = math.floor(math.floor(color / 0x1000000) % 256 * factor + 0.5)
    return a * 0x1000000 + color % 0x1000000
end

-- A rounded pill from one-pixel rows (rectangles are all gear.ui has).
local function draw_pill(x, y, w, h, color)
    local r = h / 2
    for i = 0, math.floor(h) - 1 do
        local dy = i + 0.5 - r
        local inset = r - math.sqrt(math.max(0, r * r - dy * dy))
        ui.rect(x + inset, y + i, w - 2 * inset, 1, color)
    end
end

local SIN, COS = {}, {}
local function unit_circle(n)
    if not SIN[n] then
        SIN[n], COS[n] = {}, {}
        for i = 0, n - 1 do
            local a = -math.pi / 2 + 2 * math.pi * i / n
            SIN[n][i], COS[n][i] = math.sin(a), math.cos(a)
        end
    end
    return SIN[n], COS[n]
end

-- A ring of dots from the top, clockwise: the first `lit` (0..1) of the circle in `on`, the rest in `off`.
local function draw_ring(cx, cy, radius, n, dot, lit, on, off)
    local sin, cos = unit_circle(n)
    local half = dot / 2
    for i = 0, n - 1 do
        ui.rect(cx + radius * cos[i] - half, cy + radius * sin[i] - half, dot, dot, ((i + 0.5) / n <= lit) and on or off)
    end
end

local function text_width(text, font)
    local w = ui.text_size(text, font)
    return w or (#text * (font.size or 12) * 0.55)
end

-- The details: next to the cursor on hover, else under the pill (above it at the bottom of the screen).
local function draw_tooltip(view, x, y, h, hover, state)
    local lines = view.tip or {}
    if #lines == 0 then return end
    local tw, th = 0, 0
    for i, line in ipairs(lines) do
        tw = math.max(tw, text_width(line, i == 1 and {size = 13, bold = true} or {size = 12}))
        th = th + (i == 1 and 18 or 16)
    end
    local bw, bh = tw + 16, th + 12
    local bx, by
    if hover then
        bx, by = ui.tooltip_rect(bw, bh)
    else
        bx, by = x, y + h + 4
        if by + bh > (state.screen_bottom or 768) then by = y - bh - 4 end
        bx = math.max(state.screen_left or 0, math.min(bx, (state.screen_right or 1024) - bw))
    end
    ui.rect(bx, by, bw, bh, COLOR.tip_back)
    ui.frame(bx, by, bw, bh, COLOR.tip_edge, 1)
    local ty = by + 6
    for i, line in ipairs(lines) do
        ui.text(line, bx + 8, ty, i == 1 and {size = 13, bold = true, color = COLOR.tip_title, shadow = true}
            or {size = 12, color = COLOR.tip_text, shadow = true})
        ty = ty + (i == 1 and 18 or 16)
    end
end

-- One pill in the rectangle (x, y, w, h). A region pill is teal, has a single ring and no time.
local function draw_one(view, state, x, y, w, h, first)
    local k = math.max(0.65, math.min(h / H, 1.8))          -- the contents follow the pill's height
    local fade = view.alpha or 1
    local now = gear.time()
    local region = view.kind == 'region'

    -- the pill; a pulse warms it for a moment (events only)
    draw_pill(x, y, w, h, with_alpha(COLOR.pill, fade))
    if not region and now < pulse_until then
        local t = (pulse_until - now) / PULSE
        draw_pill(x, y, w, h, with_alpha(COLOR.glow, math.sin(t * math.pi) * fade))
    end

    -- the double ring: gold = progress, blue = the time left; the percent in the middle
    local d = math.min(42 * k, h - 2)
    local cx, cy = x + 2 + d / 2, y + h / 2
    local outer_on = region and COLOR.region or view.kind == 'won' and COLOR.won or view.kind == 'failed' and COLOR.failed or COLOR.ring
    draw_ring(cx, cy, d / 2 - 2.5 * k, math.floor(86 * k), 3 * k, view.frac, with_alpha(outer_on, fade), with_alpha(region and COLOR.region_off or COLOR.ring_off, fade))
    if view.kind == 'active' then
        draw_ring(cx, cy, d / 2 - 7 * k, math.floor(58 * k), 2 * k, view.time_frac,
            with_alpha(view.late and COLOR.time_late or COLOR.time, fade), with_alpha(COLOR.time_off, fade))
    end
    ui.text(view.percent .. '%', cx - d / 2, cy - d / 2, {
        size = 11 * k, bold = true, color = with_alpha(COLOR.percent, fade), shadow = true, width = d, height = d,
        align = 'center', valign = 'middle'})

    -- two lines: the title, then the count and the time left (blue)
    local tx = x + d + 10
    local tw = math.max(20, w - (tx - x) - 10)
    ui.text(view.title, tx, y + h / 2 - 15 * k, {size = 12.5 * k, bold = true, color = with_alpha(region and COLOR.region_title or COLOR.title, fade),
        shadow = true, width = tw, height = 15 * k})
    if view.area and view.area ~= '' then
        -- "Orc hunt · Silver Creek": the area name after the title, dimmer, as far as there is room
        local title_w = text_width(view.title .. '  ', {size = 12.5 * k, bold = true})
        if title_w < tw - 30 * k then
            ui.text('\194\183 ' .. view.area, tx + title_w, y + h / 2 - 14 * k, {size = 11 * k, color = with_alpha(COLOR.count, fade),
                shadow = true, width = tw - title_w, height = 14 * k})
        end
    end
    local f2 = {size = 11.5 * k}
    ui.text(view.line2, tx, y + h / 2 + 1 * k, {size = f2.size, color = with_alpha(COLOR.count, fade), shadow = true, height = 14 * k})
    if view.time_text ~= '' then
        local lw = text_width(view.line2 .. ' ', f2)
        ui.text('\194\183 ' .. view.time_text, tx + lw, y + h / 2 + 1 * k, {size = f2.size, color = with_alpha(COLOR.timer, fade),
            shadow = true, height = 14 * k})
    end

    -- the details: on hover, with Alt (the game's "show text", for the first pill) or pinned from the controller's mod menu
    local mx, my = ui.mouse()
    local hover = mx >= x and mx < x + w and my >= y and my < y + h
    if hover or ((state.show_text or pinned) and first and not state.tip_drawn) then
        state.tip_drawn = true
        draw_tooltip(view, x, y, h, hover, state)
    end
end

-- All the pills in ONE movable panel, one below the other (the first stays where the panel is): the events first (least time left first), then
-- the region boss pill, at most MAX_PILLS and a line "+N more". The panel's WIDTH sets the size of the pills (resize it in the layout editor),
-- its height is made from that and the number of pills, so it grows and shrinks by itself and keeps its place.
local GAP, MORE_H, MAX_PILLS = 4, 14, 4

local function draw_stack(views, more, state)
    local n = #views
    local extra = more > 0 and MORE_H or 0
    local p = ui.panel('bar', 'World events', X, Y, W, n * H + (n - 1) * GAP + extra, {bare = true, resizable = true, min_width = 150, min_height = 30})
    if not p or not p.open then return end
    local x, y, w, h = p.content_x or X, p.content_y or Y, p.content_w or W, p.content_h or H
    local unit = H * math.max(0.68, math.min(w / W, 1.8))
    local want_h = n * unit + (n - 1) * GAP + extra
    if math.abs(h - want_h) > 1 and ui.set_panel_rect then
        ui.set_panel_rect(p.key or 'world-events:bar', x, y, w, want_h)
    end
    state.tip_drawn = false
    for i, v in ipairs(views) do
        draw_one(v, state, x, y + (i - 1) * (unit + GAP), w, unit, i == 1)
    end
    if more > 0 then
        ui.text('+' .. more .. ' more', x + 12, y + n * (unit + GAP) - GAP + 1, {size = 11, color = COLOR.count, shadow = true, height = 13})
    end
end

ui.show_panel('bar', true)

if gear.text and gear.text.get then regions.set_text(gear.text.get) end      -- region names: the texts of the install's language

-- The pills of the game's region boss counter (the region the hero stands in), read from gear.data.regions every half second.
local region_views, region_poll = {}, -1e9
local function region_frame()
    local now = gear.time()
    if now - region_poll < 0.5 then return end
    region_poll = now
    if S.get('region_pill') == false then region_views = {}; return end
    local hero = gear.world and gear.world.hero and gear.world.hero()
    region_views = regions.collect(gear.data and gear.data.regions, hero)
end

-- For tests and other mods: gear.emit('world-events.regions', out) fills out with {id, raw, name} for every region record of the game.
gear.on('world-events.regions', function(out)
    local api = gear.data and gear.data.regions
    if type(out) ~= 'table' or not (api and api.count and api.get) then return end
    for i = 1, math.min((api:count() or 1) - 1, 40) do
        local rec = api:get(i)
        if regions.valid(rec) then out[#out + 1] = {id = rec.id, raw = rec.name, name = regions.name_of(rec), needed = rec.kills_needed, left = rec.kills_left} end
    end
end)

gear.on('draw', function(state)
    if state.mode ~= 'game' or state.exclusive then return end
    local editing = ui.edit_mode()
    pcall(region_frame)
    local views = model:views(gear.time(), {area = S.get('area'), results = S.get('results'), preview = editing})
    local rviews = region_views
    if editing and #rviews == 0 and S.get('region_pill') ~= false then rviews = {regions.view(regions.sample(gear.data and gear.data.regions))} end
    local stacked, more = regions.stack(views, rviews, MAX_PILLS)
    if #stacked == 0 then return end
    if not editing and S.get('visibility') == 'alt' and not state.show_text then return end
    draw_stack(stacked, more, state)
end)

---------------------------------------------------------------------------------------------------------------
-- world bosses: made by a hook's `boss` action (this game: single player / LAN host, Gear's creature modifiers), or announced by the
-- server's channel `worldevents:boss` (any game: the bar only). The records of the bosses of this game are kept with the savegame
-- (`local_bosses.json`) so a boss comes back after a load (the creature stays in the savegame with its boosted health, the modifiers are
-- put on it again).
---------------------------------------------------------------------------------------------------------------
local btracker = bosses.tracker()
local boss_recs = {}            -- key -> the record of a boss of this game that is alive
local boss_file                 -- gear.store.game('local_bosses.json')
local boss_pending              -- {at, until}: the saved bosses are attached again once the loaded game is up
local boss_poll_at = -1e9
local BOSS_CHANNEL = 'worldevents:boss'
local boss_channel

local function boss_store()
    if boss_file then return boss_file end
    if not FILES then return nil end
    boss_file = (FILES.game or FILES.file)('local_bosses.json', {list = {}}, {every = 10})
    return boss_file
end

local function save_boss_list()
    local f = boss_store()
    if not f then return end
    local list = {}
    for _, r in pairs(boss_recs) do
        list[#list + 1] = {key = r.key, creature = r.creature, type = r.type, type_name = r.type_name, name = r.name, base_hp = r.base_hp, max_hp = r.max_hp,
            mods = r.mods, reward = r.reward, reward_text = r.reward_text, text = r.text, event = r.event}
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    f.data = type(f.data) == 'table' and f.data or {}
    f.data.list = list
    f:changed()
end

local function boss_view_record(r, st)
    return {key = r.key, name = r.name, hp = r.max_hp, max = r.max_hp, st = st or 'active', source = 'local', text = r.text, event = r.event,
        reward = r.reward_text}
end

-- Makes a boss (a clean boss of hooks.clean_boss) for this game. Returns true, or false and a reason. `source` 'local' (an event of this game)
-- or 'server' (a spawn message that asks this game to make it).
function M_spawn_boss(boss, title, text, source)
    if not G then return false, 'no world API' end
    local rec, why = G.make_boss(boss)
    if not rec then return false, why end
    rec.event = title
    rec.text = text
    rec.reward_text = bosses.reward_text(boss.reward)
    boss_recs[rec.key] = rec
    btracker:set(boss_view_record(rec), gear.time())
    emit_hook('worldevent.boss.spawned', wevents.boss_payload(rec, source or 'local'))
    G.message(title, (text and text ~= '') and text or (rec.name .. ' has appeared!'))
    save_boss_list()
    return true
end

-- The reward of a defeated boss, for this hero.
local function pay_boss(rec)
    local r = rec.reward
    if type(r) ~= 'table' then return end
    if r.gold then G.gold(r.gold) end
    if r.item then G.item(r.item) end
    if r.text then G.message(rec.name, r.text)
    elseif r.gold or r.item then G.message(rec.name, 'Reward: ' .. rec.reward_text) end
end

local function boss_poll()
    local now = gear.time()
    if now - boss_poll_at < 0.25 then return end
    boss_poll_at = now
    btracker:expire(now)
    if not G or next(boss_recs) == nil then return end
    local changed = false
    for key, rec in pairs(boss_recs) do
        local st, hp, max = G.boss_state(rec)
        if st == 'active' then
            rec.max_hp = max
            btracker:health(key, hp, max)
        else
            boss_recs[key] = nil
            changed = true
            btracker:finish(key, st, now)
            emit_hook('worldevent.boss.defeated', wevents.boss_payload(rec, 'local', {gone = st == 'gone' or nil}))
            if st == 'defeated' then
                local ok, err = pcall(pay_boss, rec)
                if not ok then gear.log('world-events: boss reward: ' .. tostring(err)) end
                G.message(rec.event or 'World event', rec.name .. ' was defeated!')
            end
        end
    end
    if changed then save_boss_list() end
end

-- A savegame was loaded (or a game started): the bosses of the old one are over (Gear forgot their modifiers); the saved ones are put back once
-- the creatures exist again.
local function boss_game_changed()
    for key in pairs(boss_recs) do btracker:remove(key) end
    boss_recs = {}
    local old = {}
    for _, b in ipairs(btracker.list) do if b.source == 'local' then old[#old + 1] = b.key end end
    for _, key in ipairs(old) do btracker:remove(key) end
    boss_pending = {at = gear.time() + 4, stop = gear.time() + 90}
end
gear.on('savegame.changed', boss_game_changed)
gear.on('session.start', boss_game_changed)

local function boss_attach_saved()
    local hero = gear.world and gear.world.hero and gear.world.hero()
    local now = gear.time()
    if now >= boss_pending.stop then boss_pending = nil return end
    if now < boss_pending.at or not hero or not G or not G.can_attach() then return end
    boss_pending = nil
    local f = boss_store()
    local list = f and type(f.data) == 'table' and f.data.list or {}
    for _, saved in ipairs(list) do
        if type(saved) == 'table' and type(saved.key) == 'string' and not boss_recs[saved.key] then
            local ok, why = G.attach_boss(saved)
            if ok then
                boss_recs[saved.key] = saved
                btracker:set(boss_view_record(saved), now)
                emit_hook('worldevent.boss.spawned', wevents.boss_payload(saved, 'local', {initial = true}))
            else
                gear.log(('world-events: the saved boss %s (%s) is not back: %s'):format(tostring(saved.name), tostring(saved.key), tostring(why)))
            end
        end
    end
    save_boss_list()
end

gear.on('frame', function()
    if boss_pending then pcall(boss_attach_saved) end
    pcall(boss_poll)
end)

-- The server announces a boss (any game): the bar shows it. A message from another player is ignored.
local function ensure_boss_channel()
    if boss_channel then return boss_channel end
    local net = gear.net
    if not (net and net.channel) then return nil end
    local ch = net.channel(BOSS_CHANNEL)
    if not ch then return nil end
    ch:on(function(from, payload)
        if not (from and from.slot == 0) then return end
        local rec, why = bosses.parse(payload)
        if not rec then gear.log('world-events: bad boss message (' .. tostring(why) .. ')'); return end
        last_server = gear.time()
        local prev = btracker.by_key[rec.key]
        local was_active = prev and prev.st == 'active'
        if rec.st == 'active' then
            btracker:set(rec, gear.time())
            if not prev then emit_hook('worldevent.boss.spawned', wevents.boss_payload({key = rec.key, name = rec.name, event = rec.event, max = rec.max,
                reward_text = rec.reward}, 'server')) end
        elseif was_active or not prev then
            if not prev then btracker:set(rec, gear.time()) else btracker:finish(rec.key, rec.st, gear.time(), rec.by) end
            if was_active then emit_hook('worldevent.boss.defeated', wevents.boss_payload({key = rec.key, name = rec.name, event = rec.event, max = rec.max,
                reward_text = rec.reward, by = rec.by}, 'server', {gone = rec.st == 'gone' or nil})) end
        end
    end)
    boss_channel = ch
    return ch
end
ensure_boss_channel()
gear.on('net_caps', function() ensure_boss_channel() end)
gear.on('session.stop', function() btracker:clear(); boss_recs = {} end)

-- Other mods (and the self test) can make a boss: gear.emit('world-events.boss', {name = 'Grakk', near = 'Orc', health = 20, damage = 2, reward = {gold = 1000}}).
gear.on('world-events.boss', function(payload)
    local boss, why = hooks.clean_boss(payload)
    if not boss then gear.log('world-events: bad boss (' .. tostring(why) .. ')'); return end
    local ok, err = M_spawn_boss(boss, type(payload) == 'table' and payload.event or 'World event', type(payload) == 'table' and payload.text or nil, 'local')
    if not ok then gear.log('world-events: boss failed: ' .. tostring(err)) end
end)

-- The bar: one panel 'boss' (movable in the layout editor like the pill's), a name over a health bar for each boss, at most MAX_BARS.
local BW_, BH_ = 420, 40            -- the panel's default width, and one boss block's height at that width
local BX, BY = 302, 170             -- top centre, under the event pill and the toasts

local BCOLOR = {
    back = 0xC00C0C10, edge = 0xFF4A3A2A, fill = 0xFFC0392B, fill_low = 0xFFE5532F, fill_dead = 0xFF6B6F63,
    name = 0xFFF2D58A, text = 0xFFF4EEDF, tip_title = 0xFFF2D58A,
}

local function boss_tip(v)
    local lines = {v.name}
    if v.event and v.event ~= '' then lines[#lines + 1] = v.event end
    lines[#lines + 1] = (v.st == 'defeated') and 'Defeated' .. ((v.by and v.by ~= '') and (' by ' .. v.by) or '') or ('Health: ' .. v.hp_text)
    if v.text and v.text ~= '' then lines[#lines + 1] = v.text end
    if v.reward and v.reward ~= '' then lines[#lines + 1] = 'Reward: ' .. v.reward end
    if v.area and v.area ~= '' then lines[#lines + 1] = v.area end
    return lines
end

local function draw_boss_bar(v, state, x, y, w, h, first)
    local k = math.max(0.7, math.min(h / BH_, 1.8))
    local fade = v.alpha or 1
    local name_h = 17 * k
    local bar_y, bar_h = y + name_h + 2 * k, h - name_h - 2 * k
    ui.text(v.name, x, y, {size = 14 * k, bold = true, color = with_alpha(BCOLOR.name, fade), shadow = true, width = w, height = name_h, align = 'center'})
    ui.rect(x, bar_y, w, bar_h, with_alpha(BCOLOR.back, fade))
    local fill_w = math.floor((w - 2) * v.frac)
    if fill_w > 0 then
        local low = v.frac < 0.25 and (math.floor(gear.time() * 3) % 2 == 0)
        ui.rect(x + 1, bar_y + 1, fill_w, bar_h - 2, with_alpha(low and BCOLOR.fill_low or BCOLOR.fill, fade))
    elseif v.st == 'defeated' then
        ui.rect(x + 1, bar_y + 1, w - 2, bar_h - 2, with_alpha(BCOLOR.fill_dead, fade * 0.6))
    end
    ui.frame(x, bar_y, w, bar_h, with_alpha(BCOLOR.edge, fade), 1)
    ui.text(v.hp_text, x, bar_y, {size = 11.5 * k, bold = true, color = with_alpha(BCOLOR.text, fade), shadow = true, width = w, height = bar_h,
        align = 'center', valign = 'middle'})
    local mx, my = ui.mouse()
    local hover = mx >= x and mx < x + w and my >= y and my < y + h
    if hover or (state.show_text and first and not state.boss_tip_drawn) then
        state.boss_tip_drawn = true
        v.tip = boss_tip(v)
        draw_tooltip(v, x, y, h, hover, state)
    end
end

local function draw_boss_stack(views, more, state)
    local n = #views
    local extra = more > 0 and MORE_H or 0
    local p = ui.panel('boss', 'World boss', BX, BY, BW_, n * BH_ + (n - 1) * GAP + extra, {bare = true, resizable = true, min_width = 240, min_height = 30})
    if not p or not p.open then return end
    local x, y, w, h = p.content_x or BX, p.content_y or BY, p.content_w or BW_, p.content_h or BH_
    local unit = BH_ * math.max(0.7, math.min(w / BW_, 1.8))
    local want_h = n * unit + (n - 1) * GAP + extra
    if math.abs(h - want_h) > 1 and ui.set_panel_rect then ui.set_panel_rect(p.key or 'world-events:boss', x, y, w, want_h) end
    state.boss_tip_drawn = false
    for i, v in ipairs(views) do draw_boss_bar(v, state, x, y + (i - 1) * (unit + GAP), w, unit, i == 1) end
    if more > 0 then ui.text('+' .. more .. ' more', x + 12, y + n * (unit + GAP) - GAP + 1, {size = 11, color = COLOR.count, shadow = true, height = 13}) end
end

ui.show_panel('boss', true)

gear.on('draw', function(state)
    if state.mode ~= 'game' or state.exclusive then return end
    if S.get('boss_bar') == false then return end
    local views, more = btracker:views(gear.time())
    if #views == 0 and ui.edit_mode() then
        views = {bosses.view({key = 'sample', name = 'Boss name', hp = 6000, max = 10000, st = 'active', source = 'local'}, gear.time())}
    end
    if #views == 0 then return end
    draw_boss_stack(views, more, state)
end)


-- The controller's mod menu: the same switches for players without a keyboard.
if ui.menu_item then
    ui.menu_item('visibility', 'World events: always / only with Alt', function()
        S.set('visibility', S.get('visibility') == 'alt' and 'always' or 'alt')
    end)
    ui.menu_item('details', 'World events: pin / unpin the details', function() pinned = not pinned end)
    ui.menu_item('region_pill', 'World events: region boss pill on / off', function() S.set('region_pill', S.get('region_pill') == false) end)
    ui.menu_item('boss_bar', 'World events: boss health bar on / off', function() S.set('boss_bar', S.get('boss_bar') == false) end)
end

local M = {bosses = btracker, boss_recs = function() return boss_recs end, spawn_boss = function(...) return M_spawn_boss(...) end,
    region_views = function() return region_views end, model = model, waves = waves, hooks = hooks, local_events = function() return localmode end, seen = seen}
return M
