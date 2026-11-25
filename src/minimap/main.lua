-- Minimap: the game's own world map (its texture tiles UI_WORLDMAP*.TGA) as a small overlay that follows the hero.
--
-- * The view is a rectangle or a circle (settings 'shape', 'width', 'height'), always centred on the hero, at one of six zoom
--   levels (setting 'zoom', the keys 'zoom_in' / 'zoom_out', the +/- buttons that show while the mouse is over the map, and the
--   controller's mod menu: LT + LB -> "Minimap: zoom in / out"). Level 1 is the widest.
-- * The panel is an ordinary Gear panel ("minimap" in ui/minimap.rml): the layout editor (ALT) moves it.
-- * The trader symbols (merchant, blacksmith, combo master, horse trader) come from gear.game.map_markers (bin\merc.bin); an
--   older SacredBild without it shows the map alone.
-- * An element cannot be cut round (RmlUi's clip masks need render layers Gear does not have), so the circle is stacked from thin
--   horizontal strips, each clipping its own copy of the visible map tiles (projection.lua: circle_strips). A rectangle is one strip.
-- * Outdoors only: in a dungeon (layer other than 0) the map has nothing to show and the panel is hidden.
--
-- The geometry (tile position -> map pixel, which tiles a view needs) is in projection.lua and tested without the game.

local P = require('projection')
local ui = gear.ui
local guard = gear.guard

local function setting(id, fallback)
    local v = gear.settings.get(id, fallback)
    if v == nil then return fallback end
    return v
end

local MARKER_TEXTURE = {[0] = 'MOUSE_TRADER', 'MOUSE_BLACKSMITH', 'MOUSE_COMBO', 'MOUSE_HORSETRADER'}
local MARKER_SIZE = 14
local MARKER_SLOTS = 40
local DUMMY = 'gear:texture/UI_WORLDMAPX00.TGA'

---------------------------------------------------------------------------------------------------------------
-- Markers: the game's service symbols as map pixels, loaded once.
---------------------------------------------------------------------------------------------------------------
local markers = nil     -- list of {px, py, kind}
local function load_markers()
    if markers then return markers end
    markers = {}
    if not (gear.game and gear.game.map_markers) then return markers end
    local ok, list = pcall(gear.game.map_markers)
    if not ok or type(list) ~= 'table' then return markers end
    for _, m in ipairs(list) do
        local px, py = P.to_map(m.x, m.y)
        if px >= 0 and px < P.WIDTH and py >= 0 and py < P.HEIGHT then
            markers[#markers + 1] = {px = px, py = py, kind = m.kind}
        end
    end
    gear.log(('minimap: %d trader symbols on the map'):format(#markers))
    return markers
end

---------------------------------------------------------------------------------------------------------------
-- The model
---------------------------------------------------------------------------------------------------------------
local doc
local last = {}
local logged = false

local function hero_map_position()
    local hero = gear.world.hero()
    if not hero then return nil end
    local x, y, layer = hero:position()
    if not x or (layer or 0) ~= 0 then return nil end
    local px, py = P.to_map(x / P.TILE, y / P.TILE)
    if not logged then
        logged = true
        gear.log(('minimap: hero at world %d, %d -> tile %.1f, %.1f -> map pixel %.0f, %.0f'):format(x, y, x / P.TILE, y / P.TILE, px, py))
    end
    return px, py
end

-- The strips of the current shape (cached per size).
local strip_cache = {}
local function strips_for(round, w, h)
    local key = (round and 'r' or 's') .. w .. 'x' .. h
    local s = strip_cache[key]
    if not s then
        if round then s = P.circle_strips(w, 3) else s = {{y = 0, h = h, x = 0, w = w}} end
        strip_cache = {[key] = s}
    end
    return s
end

-- The tiles a strip needs: those of the view's set whose rows meet the strip's vertical range.
local function strip_tiles(set, z, wy, s)
    local out, parts = {}, {}
    local top, bottom = s.y - wy, s.y + s.h - wy          -- the strip in world (zoomed map) coordinates
    for _, t in ipairs(set) do
        local y0 = math.floor(t.r * P.TILE_PX * z)
        local y1 = math.floor((t.r + 1) * P.TILE_PX * z)
        if y1 > top and y0 < bottom then
            local x0 = math.floor(t.c * P.TILE_PX * z)
            local x1 = math.floor((t.c + 1) * P.TILE_PX * z)
            out[#out + 1] = {src = 'gear:texture/' .. P.tile_name(t.r, t.c), x = x0, y = y0, w = x1 - x0, h = y1 - y0}
            parts[#parts + 1] = t.r * 8 + t.c
        end
    end
    return out, table.concat(parts, ',')
end

local function snapshot()
    -- Every key the document binds must exist from the first model on (a key added later is not seen by its bindings).
    local m = {vis = false, round = true, w = 200, h = 200, wx = 0, wy = 0, shade = '#00000000', compass = true,
        level_text = '', strips = {}, markers = {}, strips_sig = '', markers_sig = ''}
    if not setting('show', true) then return m end
    local px, py = hero_map_position()
    if not px then return m end
    local round = setting('shape', 'round') == 'round'
    local w = math.floor(tonumber(setting('width', 200)) or 200)
    local h = round and w or math.floor(tonumber(setting('height', 150)) or 150)
    local z, level = P.zoom_of(setting('zoom', 3))
    local wx, wy = w / 2 - px * z, h / 2 - py * z       -- where the map's top left lies in the view
    local set = P.visible_tiles(px, py, w, h, z)
    local opacity = math.max(30, math.min(100, tonumber(setting('opacity', 90)) or 90))
    local alpha = math.floor(255 * (1 - opacity / 100) + 0.5)

    m.vis, m.round, m.w, m.h, m.wx, m.wy = true, round, w, h, wx, wy
    m.shade = ('#000000%02x'):format(alpha)
    m.compass = setting('compass', true) and true or false
    m.level_text = tostring(level) .. '/' .. #P.ZOOMS

    -- Strips with their tiles; the signature says whether the set changed since the last frame (rebuilding the model's lists is
    -- what costs, moving the map is only wx / wy).
    -- Lists keep their length (padded with empty entries): RmlUi warns for every binding of an element that outlives a shrinking list.
    local tile_slots = (math.ceil(w / (P.TILE_PX * z)) + 1) * 2
    local strips, sig = {}, {tostring(w), tostring(h), tostring(z)}
    for i, s in ipairs(strips_for(round, w, h)) do
        local tiles, key = strip_tiles(set, z, wy, s)
        while #tiles < tile_slots do tiles[#tiles + 1] = {src = DUMMY, x = 0, y = 0, w = 0, h = 0} end
        strips[i] = {x = s.x, y = s.y, w = s.w, h = s.h, tiles = tiles}
        sig[#sig + 1] = key
    end
    m.strips, m.strips_sig = strips, table.concat(sig, '|')

    -- Markers inside the view (round: inside the circle), as map pixels times the zoom.
    local list, msig = {}, {tostring(z)}
    if setting('markers', true) then
        local rx, ry = w / 2 / z + 12, h / 2 / z + 12
        local rr = (w / 2 - MARKER_SIZE / 2) / z
        for i, mk in ipairs(load_markers()) do
            local dx, dy = mk.px - px, mk.py - py
            if math.abs(dx) < rx and math.abs(dy) < ry and (not round or dx * dx + dy * dy <= rr * rr) then
                list[#list + 1] = {x = mk.px * z - MARKER_SIZE / 2, y = mk.py * z - MARKER_SIZE / 2, s = MARKER_SIZE,
                    src = 'gear:texture/' .. (MARKER_TEXTURE[mk.kind] or MARKER_TEXTURE[0]) .. '.TGA'}
                msig[#msig + 1] = i
                if #list >= MARKER_SLOTS then break end
            end
        end
    end
    m.marker_count = #list
    while #list < MARKER_SLOTS do list[#list + 1] = {x = 0, y = 0, s = 0, src = DUMMY} end
    m.markers, m.markers_sig = list, table.concat(msig, ',')
    return m
end

local CHEAP = {'wx', 'wy', 'shade', 'compass', 'level_text', 'w', 'h', 'round'}

local function apply(m)
    local rebuild = last.vis ~= m.vis or last.strips_sig ~= m.strips_sig or last.markers_sig ~= m.markers_sig
    if not rebuild then
        -- Only the offsets (and the cheap scalars) moved.
        for _, k in ipairs(CHEAP) do
            if m[k] ~= last[k] then doc.model[k] = m[k]; last[k] = m[k] end
        end
        return
    end
    if m.marker_count ~= last.marker_count and m.marker_count then gear.log(('minimap: %d trader symbols in view'):format(m.marker_count)) end
    for k, v in pairs(m) do
        if k == 'strips' or k == 'markers' or v ~= last[k] then doc.model[k] = v end
    end
    last = m
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/minimap.rml', {dp = true, model = m, calls = {
        zoom_in = guard('zoom_in', function() gear.keys.trigger('zoom_in') end),
        zoom_out = guard('zoom_out', function() gear.keys.trigger('zoom_out') end),
    }})
    if not doc then gear.log('minimap: ui/minimap.rml failed: ' .. tostring(err)) end
end

gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' then return end
    if state.mode ~= 'game' or state.exclusive then return end
    local m = snapshot()
    if not doc then load_doc() end
    if not doc then return end
    apply(m)
    if m.vis then doc:draw({layer = 'hud'}) end
end))

---------------------------------------------------------------------------------------------------------------
-- Zoom and visibility: keys, the buttons and the controller's mod menu all end here.
---------------------------------------------------------------------------------------------------------------
local function zoom_by(d)
    local _, level = P.zoom_of(setting('zoom', 3))
    level = math.max(1, math.min(#P.ZOOMS, level + d))
    gear.settings.set('zoom', level)
end
local function toggle() gear.settings.set('show', not setting('show', true)) end

gear.keys.on('zoom_in', guard('zoom_in', function() zoom_by(1) end))
gear.keys.on('zoom_out', guard('zoom_out', function() zoom_by(-1) end))
-- For the self test (and other mods): gear.emit('minimap.set', id, value) changes one of the settings.
gear.on('minimap.set', guard('set', function(id, value) gear.settings.set(id, value) end))
gear.keys.on('toggle', guard('toggle', toggle))

if ui.menu_item then
    pcall(ui.menu_item, 'minimap_toggle', 'Minimap: show / hide', toggle)
    pcall(ui.menu_item, 'minimap_zoom_in', 'Minimap: zoom in', function() zoom_by(1) end)
    pcall(ui.menu_item, 'minimap_zoom_out', 'Minimap: zoom out', function() zoom_by(-1) end)
end
