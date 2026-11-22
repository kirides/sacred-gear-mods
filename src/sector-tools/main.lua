-- Sector tools: see README.md. For server admins who tie world events to areas: the sector you stand in, sector boundaries on the
-- ground, a recorder for the sectors you walk through and a "copy config" that puts the line for world_events.lua on the clipboard.
-- It binds no key: the panel shows while Alt is held (the game's "show text") or when pinned from the controller's mod menu, and
-- every button is an ordinary widget the controller reaches.
local core = require('core')
local ui, S = gear.ui, gear.settings

local STATE_FILE, CELLS_FILE = 'state.json', 'cells.json'
local ANCHOR_X, ANCHOR_Y = 512, 362         -- where the hero stands on the 1024 x 768 layout (a guess, see the settings)
local LINGER = 1.5                          -- seconds the panel stays after Alt is released (so a click lands)

local rec = {on = false, ids = {}, circle = nil}      -- the area being recorded
local known = {}                                      -- "layer:cx,cy" -> the sector id seen there
local pinned, alt_until, panel_rect = false, 0, nil
local status, status_until = '', 0
local dirty_since, cells_dirty, last_sample, last_cells_save = nil, false, 0, 0
local function text_get() return gear.text and gear.text.get or nil end
local hero_now = {}                                   -- x, y, layer, sector, cx, cy of the hero this frame

local function say(text) status, status_until = text, gear.time() + 6 end

---------------------------------------------------------------------------------------------------------------
-- storage: the recording survives a restart; the cells seen (id of each grid cell) accumulate
---------------------------------------------------------------------------------------------------------------
local function load_files()
    local text = gear.read(STATE_FILE)
    local v = text and gear.json.decode(text)
    if type(v) == 'table' then
        for _, id in ipairs(v.ids or {}) do rec.ids[id] = true end
        if type(v.circle) == 'table' then rec.circle = v.circle end
        rec.on = v.on == true
    end
    local cells = gear.read(CELLS_FILE)
    local c = cells and gear.json.decode(cells)
    if type(c) == 'table' then known = c end
end

local function save_state()
    gear.save(STATE_FILE, gear.json.encode({ids = core.sorted(rec.ids), circle = rec.circle, on = rec.on}))
end

local function touch() dirty_since = dirty_since or gear.time() end

local function ids_count()
    local n = 0
    for _ in pairs(rec.ids) do n = n + 1 end
    return n
end

local function current_area()
    return {id = core.slug(S.get('area_name')), name = S.get('area_name'), ids = rec.ids, circle = rec.circle, near = S.get('near')}
end

---------------------------------------------------------------------------------------------------------------
-- actions (buttons, the controller menu and gear.emit('sector-tools.command', {op = ...}) all use these)
---------------------------------------------------------------------------------------------------------------
local actions = {}

function actions.start()
    rec.ids, rec.circle, rec.on = {}, nil, true
    if hero_now.sector and hero_now.sector ~= 0 then rec.ids[hero_now.sector] = true end
    touch()
    say(('Recording "%s": walk through the area, every sector is added.'):format(S.get('area_name')))
end

function actions.stop()
    rec.on = false
    touch()
    say(('Stopped: %d sectors.'):format(ids_count()))
end

function actions.add()
    if hero_now.sector and hero_now.sector ~= 0 then
        rec.ids[hero_now.sector] = true
        touch()
        say(('Sector %d added (%d).'):format(hero_now.sector, ids_count()))
    else
        say('No sector here.')
    end
end

function actions.clear()
    rec.ids, rec.circle, rec.on = {}, nil, false
    touch()
    say('Cleared.')
end

function actions.circle()
    if not hero_now.x then say('No hero.'); return end
    rec.circle = {x = hero_now.x, y = hero_now.y, r = S.get('radius')}
    touch()
    say(('Circle at x %d, y %d, radius %d.'):format(hero_now.x, hero_now.y, S.get('radius')))
end

local function copy(text, what)
    local ok, err = gear.clipboard.set(text)
    if ok then say(('Copied %s (%d characters).'):format(what, #text)) else say('Could not copy: ' .. tostring(err)) end
    return ok, text
end

function actions.copy()
    if ids_count() == 0 and not rec.circle then say('Nothing recorded yet.'); return false end
    return copy(core.snippet(current_area()), 'the config line')
end

function actions.copy_id()
    if not hero_now.sector or hero_now.sector == 0 then say('No sector here.'); return false end
    return copy(tostring(hero_now.sector), 'the sector id')
end

function actions.copy_region()
    local line = core.region_line(hero_now.region, text_get())
    if not line then say('No game region here.'); return false end
    return copy(line, 'the region line')
end

function actions.pin() pinned = not pinned end
function actions.labels() S.set('labels', not S.get('labels')) end

gear.on('sector-tools.command', function(cmd)
    local fn = type(cmd) == 'table' and actions[cmd.op]
    if fn then cmd.ok, cmd.text = fn() else cmd.error = 'unknown op' end
    cmd.status = status
end)

-- a query for tests and other mods
gear.on('sector-tools.query', function(out)
    out.sector, out.cx, out.cy, out.x, out.y = hero_now.sector, hero_now.cx, hero_now.cy, hero_now.x, hero_now.y
    out.recording, out.ids, out.circle, out.pinned = rec.on, core.sorted(rec.ids), rec.circle, pinned
    out.region, out.region_code = hero_now.region, hero_now.region_code
    out.snippet = core.snippet(current_area())
    out.known = known
    out.shown = alt_until
end)

---------------------------------------------------------------------------------------------------------------
-- following the hero, learning which sector id lies in which grid cell
---------------------------------------------------------------------------------------------------------------
local function key_of(layer, cx, cy) return ('%d:%d,%d'):format(layer or 0, cx, cy) end

local function learn(c)
    local x, y, layer = c:position()
    local id = c.sector and c:sector()
    if x and id and id ~= 0 then
        local cx, cy = core.cell_of(x, y)
        local k = key_of(layer, cx, cy)
        if known[k] ~= id then known[k] = id; cells_dirty = true end
    end
end

gear.on('frame', function()
    local hero = gear.world.hero()
    local x, y, layer
    if hero then x, y, layer = hero:position() end
    if not x then hero_now = {}; return end
    local sector = hero:sector() or 0
    local cx, cy = core.cell_of(x, y)
    hero_now = {x = x, y = y, layer = layer or 0, sector = sector, cx = cx, cy = cy}
    -- the game region the hero stands in (gear.data.regions, newer Gear versions); nil outside or without the table
    local regions = gear.data and gear.data.regions
    if regions and regions.of_sector and sector ~= 0 then
        local okr, r, code = pcall(regions.of_sector, regions, sector)
        if okr then hero_now.region, hero_now.region_code = r, code end
    end
    if sector ~= 0 then
        local k = key_of(layer, cx, cy)
        if known[k] ~= sector then known[k] = sector; cells_dirty = true end
        if rec.on and not rec.ids[sector] then
            rec.ids[sector] = true
            touch()
            say(('Sector %d added (%d).'):format(sector, ids_count()))
        end
    end
    local now = gear.time()
    -- the sectors of the creatures and items around show which id lies in the cells next door
    if now - last_sample > 0.8 then
        last_sample = now
        local ok, near = pcall(gear.world.creatures_near, x, y, 2500, {limit = 40})
        if ok and near then for _, c in ipairs(near) do learn(c) end end
    end
    if dirty_since and now - dirty_since > 1 then
        dirty_since = nil
        save_state()
    end
    if cells_dirty and now - last_cells_save > 20 then
        cells_dirty, last_cells_save = false, now
        gear.save(CELLS_FILE, gear.json.encode(known))
    end
end)

gear.on('unload', function() save_state(); gear.save(CELLS_FILE, gear.json.encode(known)) end)

---------------------------------------------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------------------------------------------
local COLOR = {
    line = 0xE6FFD060, line_edge = 0xE0FFF0A0, id = 0xFFFFE9A8, cell = 0xFFB4A78F, unknown = 0xFFC8C0B0, shadow = 0xD0000000,
    ok = 0xFF8FD08F, rec = 0xFFE06060,
}

local function cell_label(layer, cx, cy)
    local id = known[key_of(layer, cx, cy)]
    return id and tostring(id) or '?', ('%d,%d'):format(cx, cy), id ~= nil
end

local function draw_label(text, sub, known_id, x, y, align)
    local w = 70
    local left = align == 'right' and x - w or x
    ui.text(text, left, y - 9, {size = 13, bold = true, color = known_id and COLOR.id or COLOR.unknown, shadow = true, width = w,
        align = align, height = 14})
    ui.text(sub, left, y + 4, {size = 10, color = COLOR.cell, shadow = true, width = w, align = align, height = 12})
end

-- The dotted boundary lines of the sector grid around the hero, as the game shows its ground (an isometric approximation).
local function draw_ground(state)
    local h = hero_now
    if not h.x then return end
    local ax, ay = ANCHOR_X + (S.get('anchor_x') or 0), ANCHOR_Y + (S.get('anchor_y') or 0)
    local reach = 620
    local l, t, r, b = state.screen_left or 0, state.screen_top or 0, state.screen_right or 1024, state.screen_bottom or 768
    local function dot(px, py)
        if px > l and px < r and py > t and py < b then ui.rect(px - 2, py - 2, 4, 4, COLOR.line) end
    end
    -- lines of constant world x (the cell's lower / higher x side)
    for _, k in ipairs(core.edges_near(h.x, reach)) do
        local wx = k * core.SECTOR
        for wy = h.y - reach, h.y + reach, 14 do
            local px, py = core.project(wx - h.x, wy - h.y, ax, ay)
            dot(px, py)
        end
        local lx, ly = core.project(wx - h.x, 0, ax, ay)
        if lx > l and lx < r and ly > t and ly < b then
            local low = {cell_label(h.layer, k - 1, h.cy)}
            local high = {cell_label(h.layer, k, h.cy)}
            draw_label(low[1], low[2], low[3], lx - 8, ly - 10, 'right')
            draw_label(high[1], high[2], high[3], lx + 8, ly + 10, 'left')
        end
    end
    -- lines of constant world y
    for _, k in ipairs(core.edges_near(h.y, reach)) do
        local wy = k * core.SECTOR
        for wx = h.x - reach, h.x + reach, 14 do
            local px, py = core.project(wx - h.x, wy - h.y, ax, ay)
            dot(px, py)
        end
        local lx, ly = core.project(0, wy - h.y, ax, ay)
        if lx > l and lx < r and ly > t and ly < b then
            local low = {cell_label(h.layer, h.cx, k - 1)}
            local high = {cell_label(h.layer, h.cx, k)}
            draw_label(low[1], low[2], low[3], lx + 8, ly - 10, 'left')
            draw_label(high[1], high[2], high[3], lx - 8, ly + 10, 'right')
        end
    end
    -- the circle being recorded
    if rec.circle then
        for a = 0, 359, 6 do
            local rad = math.rad(a)
            local px, py = core.project(rec.circle.x + math.cos(rad) * rec.circle.r - h.x, rec.circle.y + math.sin(rad) * rec.circle.r - h.y, ax, ay)
            dot(px, py)
        end
    end
    -- the hero's own sector
    local sub = ('%d,%d'):format(h.cx, h.cy)
    ui.text(('Sector %s'):format(h.sector ~= 0 and h.sector or '?'), ax - 40, ay + 26, {size = 13, bold = true, color = COLOR.id, shadow = true,
        width = 80, align = 'center', height = 14})
    ui.text('cell ' .. sub, ax - 40, ay + 40, {size = 10, color = COLOR.cell, shadow = true, width = 80, align = 'center', height = 12})
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

-- ui/panel.rml (the game theme): the buttons and the readout. The ground lines above stay immediate mode (they are drawn in the world).
local doc
local last = {}

local function snapshot()
    local h = hero_now
    local m = {
        hero = h.x ~= nil, head = '', pos = '', region = '', region_known = false,
        area = ('Area "%s"  (id %s)'):format(S.get('area_name'), core.slug(S.get('area_name'))),
        rec_label = rec.on and 'Stop' or 'Start area', radius = S.get('radius'),
        circle_label = ('Circle %d'):format(S.get('radius')), rec_on = rec.on,
        lines_label = S.get('labels') and 'Lines: on' or 'Lines: off', status = gear.time() < status_until and status or '',
    }
    if h.x then
        m.head = ('Sector %s   cell %d,%d   layer %d'):format(h.sector ~= 0 and h.sector or '?', h.cx, h.cy, h.layer)
        m.pos = ('x %d    y %d'):format(h.x, h.y)
        m.region = 'Region: ' .. core.region_text(h.region, h.region_code, text_get())
        m.region_known = h.region and true or false
    end
    local compact = core.compact_text(core.compact(core.sorted(rec.ids)))
    m.summary = ('%d sectors%s: %s'):format(ids_count(), rec.circle and (' + circle r ' .. math.floor(rec.circle.r)) or '', compact ~= '' and compact or '-')
    return m
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/panel.rml', {dp = true, model = m, on_change = function(_, model)
        local radius = tonumber(model.radius)
        if radius and radius ~= S.get('radius') then
            S.set('radius', radius)
            if rec.circle then rec.circle.r = radius; touch() end
        end
    end})
    if not doc then gear.log('sector tools: ui/panel.rml failed: ' .. tostring(err)) return end
    local function on(id, fn) doc:on('#' .. id, 'click', gear.guard('click ' .. id, fn)) end
    on('rec', function() if rec.on then actions.stop() else actions.start() end end)
    on('add', actions.add)
    on('clear', actions.clear)
    on('circle', actions.circle)
    on('copy', actions.copy)
    on('copyid', actions.copy_id)
    on('labels', actions.labels)
    on('copyregion', actions.copy_region)
end

local function draw_panel()
    if not doc then load_doc() end
    if not doc then return end
    for k, v in pairs(snapshot()) do
        if k ~= 'radius' and not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    if tonumber(doc.model.radius) ~= S.get('radius') then doc.model.radius = S.get('radius') end
    doc:draw({layer = 'hud'})
    local r = doc:query('#panel'):rect()
    panel_rect = r and {x = r.x, y = r.y, w = r.w, h = r.h} or nil
end

gear.on('draw', function(state)
    if state.mode ~= 'game' or state.exclusive then return end
    local now = gear.time()
    if state.show_text then alt_until = now + LINGER end
    local mx, my = ui.mouse()
    local over = panel_rect and mx >= panel_rect.x and mx < panel_rect.x + panel_rect.w and my >= panel_rect.y and my < panel_rect.y + panel_rect.h
    local shown = pinned or now < alt_until or (over and now < alt_until + 4)
    if not shown and not ui.edit_mode() then panel_rect = nil; return end
    if S.get('labels') then draw_ground(state) end
    draw_panel()
end)

-- The controller's mod menu.
if ui.menu_item then
    ui.menu_item('show', 'Sector tools: show / hide', actions.pin)
    ui.menu_item('labels', 'Sector tools: ground lines on / off', actions.labels)
    ui.menu_item('copy', 'Sector tools: copy the area config', actions.copy)
end

load_files()

return {actions = actions, rec = rec, known = known}
