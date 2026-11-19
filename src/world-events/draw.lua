-- World events, the drawing: the pills of the events and the region boss counter, and the world boss health bar.
-- main.lua decides what to show (the views come from core.lua, regions.lua and bosses.lua) and calls D.stack and
-- D.boss_stack from its draw handlers; this file only draws them. Both are bare Gear panels, so the layout editor moves
-- and sizes them.
local ui = gear.ui

local D = {}
D.PULSE = 1.6              -- seconds a pill glows after its progress crossed a 25 / 50 / 75 % mark

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
local function draw_one(view, state, flags, x, y, w, h, first)
    local k = math.max(0.65, math.min(h / H, 1.8))          -- the contents follow the pill's height
    local fade = view.alpha or 1
    local now = gear.time()
    local region = view.kind == 'region'

    -- the pill; a pulse warms it for a moment (events only)
    draw_pill(x, y, w, h, with_alpha(COLOR.pill, fade))
    if not region and now < flags.pulse_until then
        local t = (flags.pulse_until - now) / D.PULSE
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
    if hover or ((state.show_text or flags.pinned) and first and not state.tip_drawn) then
        state.tip_drawn = true
        draw_tooltip(view, x, y, h, hover, state)
    end
end

-- All the pills in ONE movable panel, one below the other (the first stays where the panel is): the events first (least time left first), then
-- the region boss pill, at most D.MAX_PILLS and a line "+N more". The panel's WIDTH sets the size of the pills (resize it in the layout editor),
-- its height is made from that and the number of pills, so it grows and shrinks by itself and keeps its place.
local GAP, MORE_H = 4, 14
D.MAX_PILLS = 4

function D.stack(views, more, state, flags)
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
        draw_one(v, state, flags, x, y + (i - 1) * (unit + GAP), w, unit, i == 1)
    end
    if more > 0 then
        ui.text('+' .. more .. ' more', x + 12, y + n * (unit + GAP) - GAP + 1, {size = 11, color = COLOR.count, shadow = true, height = 13})
    end
end

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

function D.boss_stack(views, more, state)
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

return D
