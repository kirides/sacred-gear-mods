-- A layout editor in the manner of an MMO's edit mode: its "Edit layout" button (top left, shown while Alt shows the
-- game's labels) unlocks the UI. Then every open game window
-- (inventory, equipment, skills, minimap, taskbar, shops, log book ...) and every mod panel is covered by a translucent
-- blue overlay with its name, so you still see what lies below it:
--  * click a frame to select it (gold); drag it anywhere on its overlay to move it;
--  * it snaps to the screen's edges and centre and to the other frames' edges and centres (hold Shift: no snapping);
--  * the arrow keys nudge the selected frame by one unit of the virtual 4096 x 4096 screen (Shift: 10);
--  * its settings popup shows its place, resets it and, for resizable panels, sets the size (or drag the corner);
--  * a click on empty space deselects it; Done ends the edit mode. The mod binds no key.
-- Places are kept in mods\gear_layout.json in that virtual screen, so they stay when the resolution changes.
-- Moving the game's windows needs SacredBild (its UI frames); the mod panels move without it.
--
-- Self test: selftest.lua (run it twice: Sacred.exe -gear-auto -gear-load=1 -gear-mods=layout -gear-shared-input).
--
-- Names used below: a "frame" is one thing the edit mode can move (a game window or a mod panel); sl, st, sr, sb are
-- the screen's left, top, right and bottom edges in layout units (from the draw handler's state).

local cfg = gear.config
local ui = gear.ui
if ui.persist_panel then ui.persist_panel('toolbar', false); ui.persist_panel('sample', false) end
local C = ui.COLORS

local TOOLBAR = 'layout:toolbar'
local COLOR = {
    fill = 0x5A2A64C8, fill_hover = 0x783A78E0, edge = 0xFF6AAEFF,
    sel_fill = 0x5AD8A018, sel_hover = 0x78E8B428, sel_edge = 0xFFFFD040,
    name = 0xFFFFFFFF, sel_name = 0xFFFFE6A0, shadow = 0xD0000000, guide = 0xD0FFE070,
}
local SNAP = 8              -- layout units within which a dragged frame snaps

local selected = nil        -- the key of the selected frame ('game:UI_WND_INVENTORY', 'mod:panel')
local drag = nil            -- {key, mode = 'move' | 'size', ...} while the mouse button is held on a frame
local snapping = gear.settings.get('snap')
gear.on('settings.changed', function(id, v) if id == 'snap' then snapping = v end end)
local toolbar_rect = nil    -- the toolbar's place this frame (for the self test)
local popup_rect = nil      -- the settings popup's
local popup_pin = nil       -- where the popup was put for the selected frame's place
local edit_button_shown = false     -- the "Edit layout" button was drawn this frame
local done_rect = nil               -- the toolbar's Done button (for the self test)
local show_text_until = 0           -- gear.time() until which the button stays after Alt was released

local NAMES = {
    UI_WND_STATS_CHAR = 'Character', UI_WND_TASKBAR = 'Action bar', UI_WND_QUESTBOOK = 'Quest log',
    UI_WND_OVERVIEWMAP = 'Minimap', UI_WND_NETPORTRAIT = 'Party', UI_WND_TEXTLINES = 'Messages',
    UI_WND_NETINFO = 'Network info', UI_WND_MASTER = 'Combat master',
}

-- 'UI_WND_SKILL_TREE' -> 'Skill Tree'
local function pretty(name)
    if NAMES[name] then return NAMES[name] end
    local s = name:gsub('^UI_WND_', ''):gsub('^UI_', ''):lower():gsub('_', ' ')
    return (s:gsub('(%a)(%w*)', function(a, b) return a:upper() .. b end))
end

-- Every frame the edit mode covers: {key, name, x, y, w, h, game | panel, resizable, min_w, min_h}. A game window's
-- frame is where it drew (its tabs and ornaments too, `bounds`), else its rect; ox, oy: from there to its place.
local function collect()
    local list = {}
    if ui.can_move_windows() then
        for _, w in ipairs(ui.windows()) do
            local b = w.bounds
            if w.drawn and w.movable and w.name ~= '' and (b or (w.width > 0 and w.height > 0)) then
                local wx, wy = w.x + w.frame_x, w.y + w.frame_y
                b = b or {x = wx, y = wy, w = w.width, h = w.height}
                list[#list + 1] = {key = 'game:' .. w.name, name = pretty(w.name), game = w.name,
                    x = b.x, y = b.y, w = b.w, h = b.h, ox = wx - b.x, oy = wy - b.y}
            end
        end
    end
    for _, p in ipairs(ui.panels()) do
        if p.key ~= TOOLBAR then
            list[#list + 1] = {key = p.key, name = p.title ~= '' and p.title or p.key, panel = true,
                x = p.x, y = p.y, w = p.w, h = p.h, resizable = p.resizable, min_w = p.min_width, min_h = p.min_height}
        end
    end
    return list
end

local function move(f, x, y, w, h)
    if f.game then
        ui.set_window_position(f.game, x + f.ox, y + f.oy)
    else
        ui.set_panel_rect(f.key, x, y, w, h)
        if f.resizable and w then
            f.w, f.h = math.max(w, f.min_w), math.max(h, f.min_h)
        end
    end
    f.x, f.y = x, y
end

local function reset(f)
    if f.game then ui.reset_window(f.game) else ui.reset_panel(f.key) end
end

-- Moves `pos` (a frame of `size`) so that its start, centre or end lies on the nearest target within SNAP.
local function snap_axis(pos, size, targets)
    local best, dist, line = pos, SNAP + 0.001, nil
    for _, t in ipairs(targets) do
        for _, edge in ipairs({0, size / 2, size}) do
            local d = math.abs(pos + edge - t)
            if d < dist then best, dist, line = t - edge, d, t end
        end
    end
    return best, line
end

local guides = {}           -- the snap lines of this frame: {vertical = x} / {horizontal = y}

local function snap(f, x, y, list, sl, st, sr, sb)
    local xs, ys = {sl, sr, (sl + sr) / 2}, {st, sb, (st + sb) / 2}
    for _, o in ipairs(list) do
        if o.key ~= f.key then
            xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = o.x, o.x + o.w, o.x + o.w / 2
            ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = o.y, o.y + o.h, o.y + o.h / 2
        end
    end
    local gx, gy
    x, gx = snap_axis(x, f.w, xs)
    y, gy = snap_axis(y, f.h, ys)
    if gx then guides[#guides + 1] = {vertical = gx} end
    if gy then guides[#guides + 1] = {horizontal = gy} end
    return x, y
end

-- One virtual unit (Shift: 10) at a time, from the stored place so nothing drifts.
local function nudge(f, dx, dy)
    local e = ui.layout()[f.key]
    local vx, vy
    if e then vx, vy = e.x, e.y else vx, vy = ui.to_virtual(f.x + (f.ox or 0), f.y + (f.oy or 0)) end
    local x, y = ui.from_virtual(vx + dx, vy + dy)
    move(f, x - (f.ox or 0), y - (f.oy or 0))
end

-- Arrow keys with auto repeat: once when pressed, again after 0.4 s held, then every 0.06 s. Timed, not counted in
-- frames: at a few hundred frames per second "18 frames" passed within one short key press, which nudged twice.
local held = {}
local function repeating(key)
    if not ui.key_down(key) then
        held[key] = nil
        return false
    end
    local now = gear.time()
    local next_at = held[key]
    if not next_at then
        held[key] = now + 0.4
        return true
    end
    if now >= next_at then
        held[key] = now + 0.06
        return true
    end
    return false
end

-- The largest of a few fonts in which the name fits the frame (cached per name and font).
local sizes = {}
local function name_font(name, max_w, max_h)
    for _, size in ipairs({30, 22, 16, 12}) do
        local font = {size = size, bold = true}
        local k = name .. '\0' .. size
        local s = sizes[k]
        if not s then
            local w, h = ui.text_size(name, font)
            s = {w or #name * 8, h or 16}
            sizes[k] = s
        end
        if s[1] <= max_w and s[2] <= max_h then return font, s[1], s[2] end
    end
end

local function overlay(f, sel, hot)
    local top = {layer = 'top'}
    local fill = sel and (hot and COLOR.sel_hover or COLOR.sel_fill) or (hot and COLOR.fill_hover or COLOR.fill)
    ui.rect(f.x, f.y, f.w, f.h, fill, top)
    ui.frame(f.x, f.y, f.w, f.h, sel and COLOR.sel_edge or COLOR.edge, sel and 3 or 1, top)
    local font, tw, th = name_font(f.name, f.w - 12, f.h - 4)
    if font then
        local tx, ty = math.floor(f.x + (f.w - tw) / 2), math.floor(f.y + (f.h - th) / 2)
        ui.text(f.name, tx, ty, {size = font.size, bold = true, outline = true,
            color = sel and COLOR.sel_name or COLOR.name, layer = 'top'})
    end
    if f.resizable then
        local c = sel and COLOR.sel_edge or COLOR.edge
        for i = 0, 2 do
            ui.rect(f.x + f.w - 5 - i * 4, f.y + f.h - 5, 2, 2, c, top)
            ui.rect(f.x + f.w - 5, f.y + f.h - 5 - i * 4, 2, 2, c, top)
        end
    end
end

local function overlaps(a, x, y, w, h)
    return a and x < a.x + a.w and a.x < x + w and y < a.y + a.h and a.y < y + h
end

-- The selected frame's settings, beside it (right, left, below, above; the first place on the screen that leaves the
-- toolbar free, else the first on the screen, else inside the frame).
local function popup(f, sl, st, sr, sb)
    local top = {layer = 'top'}
    local pw, ph = 230, f.resizable and 150 or 108
    local function clamp_y(y) return math.max(st, math.min(sb - ph, y)) end
    local function clamp_x(x) return math.max(sl, math.min(sr - pw, x)) end
    local spots = {
        {f.x + f.w + 10, clamp_y(f.y)}, {f.x - pw - 10, clamp_y(f.y)},
        {clamp_x(f.x), f.y + f.h + 10}, {clamp_x(f.x), f.y - ph - 10},
    }
    local px, py
    for pass = 1, 2 do
        for _, s in ipairs(spots) do
            if not px and s[1] >= sl and s[1] + pw <= sr and s[2] >= st and s[2] + ph <= sb
                and (pass == 2 or not overlaps(toolbar_rect, s[1], s[2], pw, ph)) then
                px, py = s[1], s[2]
            end
        end
    end
    if not px then px, py = clamp_x(f.x + 10), clamp_y(f.y + 10) end
    px, py = math.floor(px), math.floor(py)
    -- It stays put while only the frame's size changes (its own sliders would move away under the cursor).
    local pin = popup_pin
    -- (Places come back through the virtual screen: compare within a unit.)
    if pin and pin.key == f.key and math.abs(pin.fx - f.x) < 1 and math.abs(pin.fy - f.y) < 1 and pin.h == ph then
        px, py = pin.x, pin.y
    else
        popup_pin = {key = f.key, fx = f.x, fy = f.y, h = ph, x = px, y = py}
    end
    popup_rect = {x = px, y = py, w = pw, h = ph}
    ui.region('popup', px, py, pw, ph, top)
    ui.rect(px, py, pw, ph, 0xEC101018, top)
    ui.frame(px, py, pw, ph, COLOR.sel_edge, 1, top)
    ui.rect(px + 1, py + 1, pw - 2, 20, C.title, top)
    ui.text(f.name, px + 8, py + 3, {color = C.accent, layer = 'top'})
    if ui.button('popup-close', px + pw - 21, py + 2, 18, 18, 'x', {layer = 'top', tooltip = 'Deselect'}) then
        selected = nil
    end
    local y = py + 28
    local vx, vy = ui.to_virtual(f.x + (f.ox or 0), f.y + (f.oy or 0))
    ui.text(('Position %d, %d  (of 4096)'):format(math.floor(vx + 0.5), math.floor(vy + 0.5)), px + 8, y,
        {color = C.text, layer = 'top'})
    ui.text(f.key, px + 8, y + 16, {color = C.text_dim, layer = 'top'})
    y = y + 38
    if f.resizable then
        local l, t, r, b = sl, st, sr, sb
        local g = ui.table('popup-size', px + 8, y, 44 + 6 + 170, {columns = {44, 170}, spacing = {6, 2}, row_height = 22, layer = 'top'})
        g:row(); g:label(1, 'Width')
        local cw, nw = g:slider(2, f.min_w, math.floor(r - l), math.floor(f.w + 0.5), {id = 'popup-w', width = 120})
        g:row(); g:label(1, 'Height')
        local ch, nh = g:slider(2, f.min_h, math.floor(b - t), math.floor(f.h + 0.5), {id = 'popup-h', width = 120})
        if cw or ch then move(f, f.x, f.y, nw, nh) end
        y = y + g:height() + 2
    end
    if ui.button('popup-reset', px + 8, y, 120, 22, 'Reset position', {layer = 'top',
        tooltip = f.resizable and 'Its own place and size again' or 'Its own place again'}) then
        reset(f)
    end
    ui.text('Arrows: nudge', px + 136, y + 4, {color = C.text_dim, layer = 'top'})
end

local function editor(state)
    local sl, st, sr, sb = state.screen_left, state.screen_top, state.screen_right, state.screen_bottom
    local top = {layer = 'top'}
    local list = collect()
    guides = {}
    popup_rect = nil

    -- Behind the overlays: the whole screen, so a click on empty space deselects (and does not walk the hero).
    local bg = ui.region('background', sl, st, sr - sl, sb - st, top)
    if bg.clicked then selected = nil end

    -- Larger frames first, so the smaller ones on top of them stay reachable; the selected one on top of all.
    table.sort(list, function(a, b)
        local sa, sb_ = a.key == selected, b.key == selected
        if sa ~= sb_ then return sb_ end
        local aa, ab = a.w * a.h, b.w * b.h
        if aa ~= ab then return aa > ab end
        return a.key < b.key
    end)
    local by_key = {}
    local mx, my = ui.mouse()
    for _, f in ipairs(list) do
        by_key[f.key] = f
        local r = ui.region('frame:' .. f.key, f.x, f.y, f.w, f.h, top)
        if r.pressed then
            selected = f.key
            drag = {key = f.key, mode = 'move', grab_x = mx - f.x, grab_y = my - f.y, start_x = mx, start_y = my}
        end
        local g = f.resizable and ui.region('grip:' .. f.key, f.x + f.w - 16, f.y + f.h - 16, 16, 16,
            {layer = 'top', tooltip = 'Drag to resize'})
        if g and g.pressed then
            selected = f.key
            drag = {key = f.key, mode = 'size', grab_w = mx - f.w, grab_h = my - f.h}
        end
        if drag and drag.key == f.key then
            if drag.mode == 'move' and r.held then
                -- A click selects; only a drag (a few units) moves.
                if drag.moved or math.abs(mx - drag.start_x) + math.abs(my - drag.start_y) >= 3 then
                    drag.moved = true
                    local x, y = mx - drag.grab_x, my - drag.grab_y
                    if snapping and not ui.key_down('shift') then x, y = snap(f, x, y, list, sl, st, sr, sb) end
                    move(f, x, y)
                end
            elseif drag.mode == 'size' and g and g.held then
                move(f, f.x, f.y, math.max(f.min_w, mx - drag.grab_w), math.max(f.min_h, my - drag.grab_h))
            else
                drag = nil
            end
        end
        overlay(f, f.key == selected, r.hover or (g and g.hover) or (drag and drag.key == f.key))
    end
    for _, gl in ipairs(guides) do
        if gl.vertical then ui.rect(gl.vertical, st, 1, sb - st, COLOR.guide, top) end
        if gl.horizontal then ui.rect(sl, gl.horizontal, sr - sl, 1, COLOR.guide, top) end
    end

    local f = selected and by_key[selected]
    if f then
        if not drag then
            local step = ui.key_down('shift') and 10 or 1
            if repeating('left') then nudge(f, -step, 0) end
            if repeating('right') then nudge(f, step, 0) end
            if repeating('up') then nudge(f, 0, -step) end
            if repeating('down') then nudge(f, 0, step) end
        end
    end
    return f
end

local function toolbar(state)
    local p = ui.panel('toolbar', 'Edit mode', 400, 300, 250, 160, {layer = 'top', closable = false,
        resizable = true, min_width = 250, min_height = 160, tooltip = 'Drag me too'})
    toolbar_rect = p.open and {x = p.x, y = p.y, w = p.w, h = p.h} or nil
    if not p.open then return end
    local x, y = p.content_x, p.content_y
    if ui.can_move_windows() then
        ui.text('Click a frame, drag it anywhere.', x, y, {layer = 'top'})
    else
        ui.text('Game windows need SacredBild.', x, y, {color = 0xFFFF8080, layer = 'top'})
    end
    ui.text('Arrows nudge it (Shift: 10).', x, y + 15, {color = C.text_dim, layer = 'top'})
    -- Done and Reset windows side by side, Reset everything and the checkbox across both columns.
    local t = ui.table('buttons', x, y + 36, 234, {columns = {112, 112}, spacing = {10, 6}, row_height = 22, layer = 'top'})
    t:row()
    local dx, dy, dw, dh = t:cell(1)
    done_rect = {x = dx, y = dy, w = dw, h = dh}
    if t:button(1, 'Done', {id = 'done'}) then ui.set_edit_mode(false) end
    if t:button(2, 'Reset windows', {id = 'reset-game', tooltip = 'The game windows back to their places'}) then
        ui.reset_layout('game:')
    end
    t:row()
    if t:button(1, 'Reset everything', {id = 'reset-all', span = 2, tooltip = 'Game windows and every mod panel'}) then
        ui.reset_layout()
    end
    t:row()
    local changed, on = t:checkbox(1, 'Snap to edges and frames', snapping, {id = 'snap', span = 2,
        tooltip = 'Hold Shift while dragging to place freely'})
    if changed then snapping = on; gear.settings.set('snap', on) end
end

-- The self test's own resizable panel, so a mod panel shows up in the edit mode without another mod.
local sample_panel = gear.auto ~= nil

-- The controller reaches the edit mode through the mod menu; there the pad drives the editor alone (D-pad between
-- the frames and buttons, A held and the stick to drag, B is Done).
-- (ui.menu_item and nav_modal are newer than some SacredGear.dll builds: the mod still loads without them.)
if ui.menu_item then
    ui.menu_item('edit', 'Edit layout', function() ui.set_edit_mode(not ui.edit_mode()) end)
end

gear.on('draw', function(state)
    if not state or state.mode ~= 'game' or state.exclusive then
        drag = nil
        if ui.nav_modal then ui.nav_modal(false) end
        return
    end
    if ui.nav_modal then ui.nav_modal(ui.edit_mode() and not (state.escape_menu or state.message_box)) end
    if ui.edit_mode() and ui.back_pressed and ui.back_pressed() then ui.set_edit_mode(false) end
    if sample_panel then
        local p = ui.panel('sample', 'Sample panel', 60, 120, 200, 110, {resizable = true, min_width = 140,
            min_height = 80, closable = false})
        if p.open then ui.text('A mod panel', p.content_x, p.content_y, {}) end
    end
    if ui.edit_mode() then
        -- The editor covers the screen on the top layer: out of the way of the escape menu and message boxes.
        if state.escape_menu or state.message_box then
            drag = nil
            return
        end
        local f = editor(state)
        toolbar(state)
        -- The selected frame's settings over everything, the toolbar too.
        if f then popup(f, state.screen_left, state.screen_top, state.screen_right, state.screen_bottom) end
    else
        selected, drag, toolbar_rect, popup_rect = nil, nil, nil, nil
        -- The button only with the game's labels (Alt held), like the game's own text.
        -- It stays a moment after Alt is released, so a click made just before still lands on it.
        if state.show_text then show_text_until = gear.time() + 0.4 end
        edit_button_shown = gear.time() < show_text_until
        if edit_button_shown and ui.button('edit', state.screen_left + 4, state.screen_top + 4, 80, 20, 'Edit layout',
            {tooltip = 'Move windows and panels'}) then
            ui.set_edit_mode(true)
        end
    end
end)

---------------------------------------------------------------------------------------------------------------
-- Self test (selftest.lua): only when the game runs with -gear-auto. It reads the editor's state through `probe`.
---------------------------------------------------------------------------------------------------------------
if gear.auto then
    require('selftest')({
        SNAP = SNAP,
        collect = collect,
        selected = function() return selected end,
        toolbar_rect = function() return toolbar_rect end,
        popup_rect = function() return popup_rect end,
        done_rect = function() return done_rect end,
        edit_button_shown = function() return edit_button_shown end,
    })
end
