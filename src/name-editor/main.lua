-- Name editor: build character names with the game's colors and icons.
--
-- Sacred stores a name as plain text with codes in it: \cffRRGGBB switches the color of the letters that follow, \gffffffff00000XXX draws
-- a UI image (XXX is its id in hex) in the line. This window edits that as a list of tokens (letters, icons, color marks), shows the
-- name as the game draws it, and gives the raw text to copy. Pasting a raw name parses it back.
--
-- The window is the document ui/editor.rml. Its middle part (the fragment between <!--fragment--> markers, with ui/fragment.rcss) is
-- shared with the standalone web page docs/name-editor/index.html, whose JavaScript does what this file does: keep the two in step
-- (same ids, same token model, same markup builders). The web page draws the icons from a placeholder atlas; the game draws the real
-- UI images (gear:image/<decimal id>).
--
-- Keys while the window is open (the game takes no keys): type, Left/Right/Home/End, Backspace/Delete, Ctrl+V / Ctrl+C (paste / copy the
-- raw text), PageUp/PageDown (next / previous palette tab), Escape or the controller's B closes. The buttons are pad stops.
--
-- For the self test (name-editor_selftest): gear.emit('name-editor.query', out), 'name-editor.set' ({raw = ...}), 'name-editor.press' ({id = ...}).

local ui = gear.ui

local DATA, derr = gear.json.decode(gear.read('data.json') or '')
if type(DATA) ~= 'table' then
    gear.log('name editor: data.json: ' .. tostring(derr))
    return
end

local ICPFX, CPFX = '\\gffffffff00000', '\\cff'
local ICPAT, CPAT = '^%\\gffffffff00000(%x%x%x)', '^%\\cff(%x%x%x%x%x%x)'     -- the same as patterns (% escapes the backslash)
local TABS = {'col', 'ico', 'grd'}

local st = {
    toks = {}, caret = 0, recent = {}, tab = 1,
    gA = 'ED1C24', gB = 'FFF14E', slot = 'A', scope = 'all',
    selhex = nil, marks = true,
}

---------------------------------------------------------------------------------------------------------------------------------
-- model: a flat token list ({t = 'ch', v = 'x'}, {t = 'ic', v = '0DA'}, {t = 'co', v = 'FF0000'}); the raw text is derived and parseable
---------------------------------------------------------------------------------------------------------------------------------
local function utf8_chars(s)
    local out = {}
    for c in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do out[#out + 1] = c end
    return out
end

local function serialize(toks)
    local parts = {}
    for i, k in ipairs(toks or st.toks) do
        parts[i] = k.t == 'ch' and k.v or k.t == 'ic' and (ICPFX .. k.v) or (CPFX .. k.v)
    end
    return table.concat(parts)
end

local function parse(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local ic = s:match(ICPAT, i)
        local co = not ic and s:match(CPAT, i)
        if ic then
            out[#out + 1] = {t = 'ic', v = ic:upper()}
            i = i + #ICPFX + 3
        elseif co then
            out[#out + 1] = {t = 'co', v = co:upper()}
            i = i + #CPFX + 6
        else
            local c = s:match('^[%z\1-\127\194-\244][\128-\191]*', i) or s:sub(i, i)
            if c:byte() >= 32 or c == ' ' then out[#out + 1] = {t = 'ch', v = c} end
            i = i + #c
        end
    end
    return out
end

local function color_at(idx)
    local c
    for i = 1, idx do
        if st.toks[i].t == 'co' then c = st.toks[i].v end
    end
    return c
end

local function hx(h) return {tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)} end
local function mix(a, b, f)
    local A, B = hx(a), hx(b)
    local o = {}
    for i = 1, 3 do o[i] = ('%02X'):format(math.floor(A[i] + (B[i] - A[i]) * f + 0.5)) end
    return table.concat(o)
end

local function esc(c)
    if c == ' ' then return '&nbsp;' end
    return (c:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

---------------------------------------------------------------------------------------------------------------------------------
-- markup builders (the web page has the same ones; only icon_html differs)
---------------------------------------------------------------------------------------------------------------------------------
local function icon_html(code)
    return ('<span class="ic" style="decorator: image(gear:image/%d?dp contain)"></span>'):format(tonumber(code, 16))
end

-- the name as markup; with_cursor puts the underscore at the caret, with_marks a dot where a color code sits
local function tokens_html(with_cursor, with_marks)
    local out, c = {}, nil
    for i = 0, #st.toks do
        if with_cursor and i == st.caret then out[#out + 1] = '<span id="ne-cur" class="cur">_</span>' end
        local k = st.toks[i + 1]
        if not k then break end
        if k.t == 'co' then
            c = k.v
            if with_marks then out[#out + 1] = ('<span class="cm" style="background-color: #%s"></span>'):format(k.v) end
        elseif k.t == 'ic' then
            out[#out + 1] = icon_html(k.v)
        elseif c then
            out[#out + 1] = ('<span style="color: #%s">%s</span>'):format(c, esc(k.v))
        else
            out[#out + 1] = esc(k.v)
        end
    end
    return table.concat(out)
end

local function raw_html()
    if #st.toks == 0 then return '<span class="e">(empty)</span>' end
    local out = {}
    for i, k in ipairs(st.toks) do
        if k.t == 'ch' then out[i] = esc(k.v)
        elseif k.t == 'ic' then out[i] = ('<span class="g">\\gffffffff00000%s</span>'):format(k.v)
        else out[i] = ('<span class="k">\\cff</span><span class="h">%s</span>'):format(k.v) end
    end
    return table.concat(out)
end

local function color_name(i)
    local r, c = math.floor((i - 1) / 6) + 1, (i - 1) % 6 + 1
    if c <= 5 then return DATA.rows[r] .. ' \194\183 ' .. DATA.cols[c] end
    return DATA.rgbnames[r]
end

local function grid_html(prefix)
    local out = {}
    for i, hex in ipairs(DATA.pal) do
        out[i] = ('<button id="%s-%s" class="sw" style="background-color: #%s" title="%s  \\cff%s"></button>'):format(prefix, hex, hex, color_name(i), hex)
    end
    return table.concat(out)
end

local function icons_html()
    local out = {}
    for i, code in ipairs(DATA.ids) do
        out[i] = ('<button id="ic-%s" class="ib" title="Icon %s (UI image %d)">%s</button>'):format(code, code, tonumber(code, 16), icon_html(code))
    end
    return table.concat(out)
end

local function bar_html(a, b, n)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = ('<span class="sl" style="background-color: #%s"></span>'):format(mix(a, b, n > 1 and i / (n - 1) or 0)) end
    return table.concat(out)
end

local function presets_html()
    local out = {}
    for i, p in ipairs(DATA.presets) do
        out[i] = ('<button id="pre-%d" class="pre" title="%s">%s</button>'):format(i, p[1], bar_html(p[2], p[3], 12))
    end
    return table.concat(out)
end

local function recent_html()
    local out = {}
    for i, hex in ipairs(st.recent) do
        out[i] = ('<button id="rc-%s" class="sw" style="background-color: #%s" title="Recent  \\cff%s"></button>'):format(hex, hex, hex)
    end
    return table.concat(out)
end

---------------------------------------------------------------------------------------------------------------------------------
-- the document
---------------------------------------------------------------------------------------------------------------------------------
local doc
local shown = false
local blink_on = true

local function q(sel) return doc and doc:query(sel) end
local function set_class(sel, name, on) local e = q(sel) if e then e:class(name, on and true or false) end end

local function mark_selected()
    if st.selhex then set_class('#sw-' .. st.selhex, 'sel', false) end
    local c = color_at(st.caret)
    st.selhex = c
    if c then set_class('#sw-' .. c, 'sel', true) end
end

local function paint_gradient()
    if not doc then return end
    doc:html('#ne-gbar', bar_html(st.gA, st.gB, 32))
    for _, s in ipairs({'A', 'B'}) do
        local hex = s == 'A' and st.gA or st.gB
        local dot = q('#slot-' .. s .. '-dot')
        if dot then dot:style('background-color', '#' .. hex) end
        doc:text('#slot-' .. s .. '-txt', (s == 'A' and 'Start ' or 'End ') .. hex)
        set_class('#slot-' .. s, 'on', st.slot == s)
    end
    set_class('#scope-all', 'on', st.scope == 'all')
    set_class('#scope-cursor', 'on', st.scope == 'cursor')
    local vis = 0
    for _, k in ipairs(st.toks) do if k.t == 'ch' and k.v ~= ' ' then vis = vis + 1 end end
    doc:text('#ne-gcost', ('Adds up to %d raw characters (9 per colored letter)'):format(vis * 9))
end

local function refresh()
    if not doc then return end
    doc:html('#ne-prev', tokens_html(false, false))
    doc:html('#ne-raw', raw_html())
    local pill = tokens_html(true, st.marks)
    if #st.toks == 0 then pill = pill .. '<span class="ph">Type a name\226\128\166</span>' end
    doc:html('#ne-pill', pill)
    local chars, icons = 0, 0
    for _, k in ipairs(st.toks) do
        if k.t == 'ch' then chars = chars + 1 elseif k.t == 'ic' then icons = icons + 1 end
    end
    doc:text('#ne-info', ('Characters %d  ·  Icons %d  ·  Raw length %d  ·  Max length: unknown'):format(chars, icons, #serialize()))
    blink_on = true
    mark_selected()
    paint_gradient()
end

local function insert(list)
    for _, k in ipairs(list) do
        table.insert(st.toks, st.caret + 1, k)
        st.caret = st.caret + 1
    end
    refresh()
end

local function back()
    if st.caret > 0 then table.remove(st.toks, st.caret) st.caret = st.caret - 1 refresh() end
end
local function del()
    if st.caret < #st.toks then table.remove(st.toks, st.caret + 1) refresh() end
end
local function set_raw(s) st.toks = parse(s) st.caret = #st.toks refresh() end

local function insert_color(hex)
    insert({{t = 'co', v = hex}})
    for i = #st.recent, 1, -1 do if st.recent[i] == hex then table.remove(st.recent, i) end end
    table.insert(st.recent, 1, hex)
    while #st.recent > 10 do table.remove(st.recent) end
    if doc then doc:html('#ne-recent', recent_html()) end
end

local function apply_gradient()
    local from = st.scope == 'cursor' and st.caret or 0
    local head, tail = {}, {}
    for i = 1, from do head[#head + 1] = st.toks[i] end
    for i = from + 1, #st.toks do
        if st.toks[i].t ~= 'co' then tail[#tail + 1] = st.toks[i] end
    end
    local vis = 0
    for _, k in ipairs(tail) do if k.t == 'ch' and k.v ~= ' ' then vis = vis + 1 end end
    local n, last = 0, color_at(from)
    for _, k in ipairs(tail) do
        if k.t == 'ch' and k.v ~= ' ' then
            local c = mix(st.gA, st.gB, vis > 1 and n / (vis - 1) or 0)
            n = n + 1
            if c ~= last then head[#head + 1] = {t = 'co', v = c} last = c end
        end
        head[#head + 1] = k
    end
    st.toks = head
    st.caret = #st.toks
    refresh()
end

local function remove_colors()
    local o = {}
    for _, k in ipairs(st.toks) do if k.t ~= 'co' then o[#o + 1] = k end end
    st.toks = o
    st.caret = math.min(st.caret, #o)
    refresh()
end

local function set_tab(i)
    st.tab = (i - 1) % #TABS + 1
    for n, t in ipairs(TABS) do
        set_class('#ne-p-' .. t, 'ne-hide', n ~= st.tab)
        set_class('#tab-' .. t, 'on', n == st.tab)
    end
    paint_gradient()
end

local function copy_raw()
    local ok, err = gear.clipboard.set(serialize())
    if not ok then gear.log('name editor: copy failed: ' .. tostring(err)) end
end

local EXAMPLE = ICPFX .. '0DA ' .. CPFX .. 'FEC2C5Ra' .. CPFX .. 'F2D7D7v' .. CPFX .. 'BF0B57en ' .. CPFX .. 'A2B90AHe' .. CPFX .. 'F49AC1ro ' .. ICPFX .. '496'

-- what a press of a button (by id) does; the same table of ids as the web page
local function press(id)
    local kind, arg = id:match('^(%a+)%-(.+)$')
    if kind == 'sw' or kind == 'rc' then insert_color(arg)
    elseif kind == 'gs' then
        if st.slot == 'A' then st.gA = arg st.slot = 'B' else st.gB = arg end
        paint_gradient()
    elseif kind == 'ic' then insert({{t = 'ic', v = arg}})
    elseif kind == 'tab' then for n, t in ipairs(TABS) do if t == arg then set_tab(n) end end
    elseif kind == 'slot' then st.slot = arg paint_gradient()
    elseif kind == 'scope' then st.scope = arg paint_gradient()
    elseif kind == 'pre' then
        local p = DATA.presets[tonumber(arg)]
        if p then st.gA, st.gB = p[2], p[3] paint_gradient() end
    elseif id == 'act-left' then st.caret = math.max(0, st.caret - 1) refresh()
    elseif id == 'act-right' then st.caret = math.min(#st.toks, st.caret + 1) refresh()
    elseif id == 'act-back' then back()
    elseif id == 'act-clear' then st.toks, st.caret = {}, 0 refresh()
    elseif id == 'act-example' then set_raw(EXAMPLE)
    elseif id == 'act-copy' then copy_raw()
    elseif id == 'act-paste' then local t = gear.clipboard.get() if t then set_raw(t) end
    elseif id == 'act-swap' then st.gA, st.gB = st.gB, st.gA paint_gradient()
    elseif id == 'act-apply' then apply_gradient()
    elseif id == 'act-nocol' then remove_colors()
    elseif id == 'act-close' then shown = false
    end
end

local function guard(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then gear.log('name editor: ' .. name .. ': ' .. tostring(err)) end
    end
end

local function load_doc()
    local err
    doc, err = ui.rml.load('ui/editor.rml', {dp = true})
    if not doc then
        gear.log('name editor: ui/editor.rml failed: ' .. tostring(err))
        shown = false
        return
    end
    -- no LB / RB for a mod yet: the tabs are pad stops, PageUp / PageDown switch them from the keyboard
    for _, id in ipairs({'#ne-lb', '#ne-rb'}) do local e = doc:query(id) if e then e:remove() end end
    doc:html('#ne-colors', grid_html('sw'))
    doc:html('#ne-gcolors', grid_html('gs'))
    doc:html('#ne-icons', icons_html())
    doc:html('#ne-presets', presets_html())
    doc:html('#ne-recent', recent_html())
    local on_press = guard('click', function(e) if e.current and e.current ~= '' then press(e.current) end end)
    doc:on('button', 'click', on_press)
    doc:on('a', 'click', on_press)
    set_class('#ne-pill', 'on', true)      -- the keyboard always goes to the name while the window is open
    set_tab(st.tab)
    refresh()
end

---------------------------------------------------------------------------------------------------------------------------------
-- keyboard (the game takes no keys while the window is open)
---------------------------------------------------------------------------------------------------------------------------------
local function input()
    if ui.back_pressed() or ui.key_pressed('escape') then shown = false return end
    local ctrl = ui.key_down('control')
    local typed = ui.typed()
    if ctrl then
        if ui.key_pressed('v') then
            local t = gear.clipboard.get()
            if t and t ~= '' then insert(parse(t)) end
        elseif ui.key_pressed('c') then copy_raw() end
    elseif typed ~= '' then
        local list = {}
        for _, c in ipairs(utf8_chars(typed)) do
            if c:byte() >= 32 and c:byte() ~= 127 then list[#list + 1] = {t = 'ch', v = c} end
        end
        if #list > 0 then insert(list) end
    end
    if ui.key_pressed('left') then st.caret = math.max(0, st.caret - 1) refresh() end
    if ui.key_pressed('right') then st.caret = math.min(#st.toks, st.caret + 1) refresh() end
    if ui.key_pressed('home') then st.caret = 0 refresh() end
    if ui.key_pressed('end') then st.caret = #st.toks refresh() end
    if ui.key_pressed(8) then back() end
    if ui.key_pressed('delete') then del() end
    if ui.key_pressed('pagedown') then set_tab(st.tab + 1) end
    if ui.key_pressed('pageup') then set_tab(st.tab - 1) end
end

local was_shown = false
gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' then return end
    if shown and not (state.mode == 'game' or state.mode == 'menus') then return end
    if shown ~= was_shown then
        was_shown = shown
        ui.capture_keys(shown)
        if shown then ui.typed() end      -- the key that opened the window is not part of the name
    end
    if not shown then return end
    if not doc then load_doc() end
    if not doc then return end
    input()
    if not shown then return end
    -- the game's blinking underscore: on for a little over half a second, off for a little under
    local on = (gear.time() * 1.7) % 1 < 0.6
    if on ~= blink_on then
        blink_on = on
        set_class('#ne-cur', 'off', not on)
    end
    doc:draw({layer = 'hud'})
end))

gear.keys.on('window', guard('key', function() shown = not shown end))
ui.menu_item('name-editor', 'Name editor', function() shown = not shown end)

---------------------------------------------------------------------------------------------------------------------------------
-- for the self test and other mods
---------------------------------------------------------------------------------------------------------------------------------
gear.on('name-editor.query', function(out)
    out.shown, out.raw, out.caret, out.tab, out.gA, out.gB, out.scope, out.slot = shown, serialize(), st.caret, TABS[st.tab], st.gA, st.gB, st.scope, st.slot
    out.recent = st.recent
    out.rect = function(sel) local e = doc and doc:query(sel) return e and e:rect() or nil end
end)
gear.on('name-editor.set', function(t)
    if t.shown ~= nil then shown = t.shown end
    if t.raw then st.toks = parse(t.raw) st.caret = t.caret or #st.toks refresh() end
    if t.caret then st.caret = t.caret refresh() end
    if t.tab then set_tab(t.tab) end
end)
gear.on('name-editor.press', function(t) press(t.id) t.done = true end)
