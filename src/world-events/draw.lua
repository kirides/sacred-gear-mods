-- World events, the drawing: the pills of the events and the region boss counter, and the world boss health bar.
-- main.lua decides what to show (the views come from core.lua, regions.lua and bosses.lua) and calls D.stack and
-- D.boss_stack from its draw handlers; this file only draws them. Both are bare Gear panels, so the layout editor moves
-- and sizes them.
local ui = gear.ui

local D = {}
D.PULSE = 1.6              -- seconds a pill glows after its progress crossed a 25 / 50 / 75 % mark


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

-- The pills of ui/events.rml (the game theme: gear-ring elements, a movable and resizable panel): one pill per event, the region boss
-- counter in teal. A model of ready-made values is rebuilt every frame and only what changed is written; the details (the tooltip) are
-- drawn next to the cursor on hover, with Alt for the first pill, or pinned from the controller's mod menu.
local MAX_PILLS_DEFAULT = 4
D.MAX_PILLS = MAX_PILLS_DEFAULT

local function css(argb, factor)
    argb = with_alpha(argb, factor or 1)
    return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

-- Loads a document once, then writes what changed and draws it.
local function show(slot, path, model)
    if not slot.doc then
        local err
        slot.last = model
        slot.doc, err = ui.rml.load(path, {dp = true, model = model})
        if not slot.doc then gear.log('world events: ' .. path .. ' failed: ' .. tostring(err)) return nil end
        slot.doc:on('.pill', 'mouseover', function(e) slot.hover = tostring(e.current) end)
        slot.doc:on('.pill', 'mouseout', function() slot.hover = nil end)
        slot.doc:on('.boss', 'mouseover', function(e) slot.hover = tostring(e.current) end)
        slot.doc:on('.boss', 'mouseout', function() slot.hover = nil end)
    else
        for k, v in pairs(model) do
            if not same(v, slot.last[k]) then slot.doc.model[k] = v; slot.last[k] = v end
        end
    end
    slot.doc:draw({layer = 'hud'})
    return slot.doc
end

local bar = {}
local boss = {}

local function pill_model(view, i, flags)
    local region = view.kind == 'region'
    local fade = view.alpha or 1
    local now = gear.time()
    local bg = with_alpha(COLOR.pill, fade)
    if not region and now < flags.pulse_until then
        local t = (flags.pulse_until - now) / D.PULSE
        local s = math.sin(t * math.pi)
        local a = math.floor(math.floor(COLOR.glow / 0x1000000) % 256 * s * fade + 0.5)
        -- the glow over the pill: the warmer colour, as opaque as the two together
        local pa = math.floor(COLOR.pill / 0x1000000) % 256
        local total = math.min(255, math.floor(pa * fade + a))
        bg = total * 0x1000000 + (COLOR.glow % 0x1000000)
    end
    local outer_on = region and COLOR.region or view.kind == 'won' and COLOR.won or view.kind == 'failed' and COLOR.failed or COLOR.ring
    return {
        id = 'pill' .. i, bg = css(bg), alpha = '1',
        frac = view.frac or 0, ring_on = css(outer_on, fade), ring_off = css(region and COLOR.region_off or COLOR.ring_off, fade),
        timed = view.kind == 'active', time_frac = view.time_frac or 0,
        time_on = css(view.late and COLOR.time_late or COLOR.time, fade), time_off = css(COLOR.time_off, fade),
        percent = tostring(view.percent or 0), title = tostring(view.title or ''), title_color = css(region and COLOR.region_title or COLOR.title, fade),
        area = (view.area and view.area ~= '') and ('\194\183 ' .. view.area) or '', line2 = tostring(view.line2 or ''),
        time_text = (view.time_text and view.time_text ~= '') and ('\194\183 ' .. view.time_text) or '',
    }
end

-- All the pills in ONE movable panel, one below the other: the events first (least time left first), then the region boss pill, at most
-- D.MAX_PILLS and a line "+N more". The layout editor moves and sizes the panel; its height is made from the pills.
function D.stack(views, more, state, flags)
    local m = {bar_on = true, pills = {}, more = more > 0 and ('+' .. more .. ' more') or ''}
    for i, v in ipairs(views) do m.pills[i] = pill_model(v, i, flags) end
    local doc = show(bar, 'ui/events.rml', m)
    if not doc then return end
    state.tip_drawn = false
    local shown_for
    if bar.hover then
        local i = tonumber(bar.hover:match('^pill(%d+)$'))
        if i and views[i] then shown_for = {i = i, hover = true} end
    end
    if not shown_for and (state.show_text or flags.pinned) and views[1] then shown_for = {i = 1, hover = false} end
    if shown_for then
        local r = doc:query('#pill' .. shown_for.i)
        r = r and r:rect()
        if r then
            state.tip_drawn = true
            draw_tooltip(views[shown_for.i], r.x, r.y, r.h, shown_for.hover, state)
        end
    end
end

-- The bar: one panel 'boss', a name over a health bar for each boss, at most MAX_BARS.
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

function D.boss_stack(views, more, state)
    local m = {boss_on = true, bosses = {}, boss_more = more > 0 and ('+' .. more .. ' more') or ''}
    for i, v in ipairs(views) do
        local fade = v.alpha or 1
        local fill = BCOLOR.fill
        local pct = (v.frac or 0) * 100
        if (v.frac or 0) <= 0 and v.st == 'defeated' then
            fill, pct = BCOLOR.fill_dead, 100
            fade = fade * 0.6
        elseif (v.frac or 0) < 0.25 and (math.floor(gear.time() * 3) % 2 == 0) then
            fill = BCOLOR.fill_low
        end
        m.bosses[i] = {id = 'boss' .. i, name = tostring(v.name or ''), pct = ('%.1f%%'):format(pct), fill = css(fill, v.alpha or 1),
            hp_text = tostring(v.hp_text or ''), alpha = tostring(v.alpha or 1)}
    end
    local doc = show(boss, 'ui/boss.rml', m)
    if not doc then return end
    state.boss_tip_drawn = false
    local i
    if boss.hover then i = tonumber(boss.hover:match('^boss(%d+)$')) end
    local hover = i ~= nil and views[i] ~= nil
    if not hover and state.show_text and views[1] then i = 1 end
    if i and views[i] then
        local r = doc:query('#boss' .. i)
        r = r and r:rect()
        if r then
            state.boss_tip_drawn = true
            views[i].tip = boss_tip(views[i])
            draw_tooltip(views[i], r.x, r.y, r.h, hover, state)
        end
    end
end

return D
