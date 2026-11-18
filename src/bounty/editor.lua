-- The bounty editor panel (single player): list of the player's own bounties with Start / Stop / Edit / Delete, and a form to make
-- one: title, creatures, how many, time limit, minimum level, gold, an item (random, for the hero's class, or chosen types)
-- and an optional automatic trigger ("kill 10 orcs to start it, then wait 30 minutes").
-- Keyboard text fields (ui.typed) for the title and the creature words; everything else is dropdowns, sliders and buttons.

local ui = gear.ui
local customs = require('customs')
local creatures = require('creatures')

local E = {}

local GOLD, GREY, GREEN, RED = 0xFFFFD780, 0xFFB0B0B0, 0xFF80FF80, 0xFFFF8080

local ITEM_MODES = {'No item', 'Random item', 'Random item for my class', 'Chosen items'}
local MODE_OF = {nil, 'tier', 'class', 'specific'}
local TIERS = {'Good', 'Rare', 'Best'}
local ITEM_KINDS = {[5] = true, [6] = true, [8] = true, [13] = true, [17] = true, [18] = true, [19] = true, [20] = true, [21] = true,
    [22] = true, [23] = true, [24] = true, [25] = true, [29] = true}

local form = nil           -- the definition being edited (a working copy with text fields), or nil: the list is shown
local focus = nil          -- id of the text field that takes the keys
local search_results = {}
local search_for = ''
local flash = nil          -- {text, until}

local function words_of(text)
    local list = {}
    for w in tostring(text or ''):gmatch('[^,;%s]+') do list[#list + 1] = w end
    return list
end

-- A one-line text field. Returns the new text.
local function field(id, x, y, w, text, tip)
    local r = ui.region('f:' .. id, x, y, w, 20, {tooltip = tip})
    if r.clicked then focus = id end
    local active = focus == id
    ui.rect(x, y, w, 20, ui.rgba(0, 0, 0, active and 220 or 140))
    ui.frame(x, y, w, 20, active and ui.rgba(240, 200, 110, 230) or ui.rgba(200, 170, 90, 140), 1)
    ui.text(text .. (active and (math.floor(gear.time() * 2) % 2 == 0 and '|' or '') or ''), x + 4, y + 3, {size = 12, width = w - 8})
    if active then
        local typed = ui.typed()
        if typed ~= '' then text = (text .. typed):sub(1, 60) end
        if ui.key_pressed(8) and #text > 0 then
            -- drop one UTF-8 character
            local cut = #text
            while cut > 1 and text:byte(cut) >= 0x80 and text:byte(cut) < 0xC0 do cut = cut - 1 end
            text = text:sub(1, cut - 1)
        end
        if ui.key_pressed('enter') or ui.key_pressed('escape') then focus = nil end
    end
    return text
end

local function row_label(text, x, y) ui.text(text, x, y + 3, {color = GREY, size = 12}) end

-- The creature picker: the chosen creatures as buttons (click one to remove it), a dropdown to add one (a group or a single
-- creature of the game) and a filter for the dropdown. `words` is the list being edited. Returns the height used.
local picks = {}           -- per picker id: {filter, index}
local function picker(id, x, y, w, words)
    local st = picks[id]
    if not st then st = {filter = '', index = 1} picks[id] = st end
    local cy = y
    local cx = x
    if #words == 0 then
        ui.text('Any monster', x, cy + 3, {size = 12, color = GREY})
        cy = cy + 24
    else
        local remove
        for i, word in ipairs(words) do
            local label = creatures.label(word) .. '  x'
            local tw = (ui.text_size(label) or (#label * 7)) + 14
            if cx + tw > x + w and cx > x then cx = x cy = cy + 24 end
            if ui.button(id .. ':w' .. i, cx, cy, tw, 20, label, {tooltip = 'Click to remove'}) then remove = i end
            cx = cx + tw + 4
        end
        if remove then table.remove(words, remove) end
        cy = cy + 26
    end
    local labels, entries = creatures.options(st.filter)
    if st.index > #labels then st.index = 1 end
    local ch, idx = ui.dropdown(id .. ':add', x, cy, w - 130, labels, st.index, {max_rows = 12})
    if ch and entries[idx] then
        for _, word in ipairs(entries[idx].words) do
            local have = false
            for _, v in ipairs(words) do if v == word then have = true end end
            if not have and #words < 30 then words[#words + 1] = word end
        end
        st.index = 1
    elseif ch then
        st.index = 1
    end
    ui.text('Filter', x + w - 124, cy + 3, {size = 11, color = GREY})
    st.filter = field(id .. ':filter', x + w - 84, cy, 84, st.filter, 'Type part of a creature name to shorten the list')
    return cy + 24 - y
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function new_form(def)
    local d = def or {id = customs.new_id(), title = 'My bounty', names = {'orc'}, target = 10, minutes = 0, min_level = 1,
        gold = 500, trigger = {on = false, names = {}, count = 10, cooldown = 30}}
    local f = {
        id = d.id, title = d.title, words = copy(d.names), target = d.target, minutes = d.minutes,
        min_level = d.min_level, gold = d.gold, trigger_on = d.trigger.on, trigger_words = copy(d.trigger.names),
        count = d.trigger.count, cooldown = d.trigger.cooldown, search = '', chosen = {}, tier = 1, mode = 1, pick = 1,
    }
    if d.item then
        f.mode = d.item.mode == 'tier' and 2 or d.item.mode == 'class' and 3 or 4
        f.tier = d.item.tier or 1
        for _, t in ipairs(d.item.types or {}) do f.chosen[#f.chosen + 1] = {id = t.id, name = t.name} end
    end
    return f
end

local function def_of(f)
    local item = nil
    if MODE_OF[f.mode] then item = {mode = MODE_OF[f.mode], tier = f.tier, types = f.chosen} end
    return {
        id = f.id, title = f.title, names = f.words, target = f.target, minutes = f.minutes, min_level = f.min_level,
        gold = f.gold, item = item,
        trigger = {on = f.trigger_on, names = #f.trigger_words > 0 and f.trigger_words or f.words, count = f.count,
            cooldown = f.cooldown},
    }
end

-- Every item type with its name as the game shows it (the player's language) and its internal name; built once.
local item_catalog
local function items()
    if item_catalog then return item_catalog end
    item_catalog = {}
    local types = gear.data.object_types
    for id = 1, 0x7E5F do
        if ITEM_KINDS[types:kind(id)] then
            local internal = types:name(id)
            local shown = types:display_name(id)
            if internal and shown then
                item_catalog[#item_catalog + 1] = {id = id, name = shown, internal = internal, key = (shown .. ' ' .. internal):lower()}
            end
        end
    end
    return item_catalog
end

-- Types whose shown or internal name contains the text (any case), best first: names that start with it.
local function search_items(text)
    if text == search_for then return end
    search_for = text
    search_results = {}
    local needle = text:lower()
    if #needle < 2 then return end
    local starts, others = {}, {}
    for _, e in ipairs(items()) do
        local at = e.key:find(needle, 1, true)
        if at == 1 then starts[#starts + 1] = e elseif at then others[#others + 1] = e end
    end
    for _, list in ipairs({starts, others}) do
        for _, e in ipairs(list) do
            if #search_results < 40 then search_results[#search_results + 1] = e end
        end
    end
end

local function slider(id, x, y, w, lo, hi, value, step, fmt)
    local _, v = ui.slider(id, x, y, w - 56, lo, hi, value, {step = step, format = fmt})
    return v
end

local function draw_form(x, y, w, h)
    local f = form
    local lx, fx = x, x + 150
    local fw = w - 150 - 8
    local cy = y
    row_label('Title', lx, cy)
    f.title = field('title', fx, cy, fw, f.title); cy = cy + 26
    row_label('Creatures', lx, cy)
    cy = cy + picker('names', fx, cy, fw, f.words) + 4
    row_label('How many', lx, cy); f.target = slider('target', fx, cy, fw, 1, 1000, f.target, 1, '%d'); cy = cy + 24
    row_label('Time limit (0 = none)', lx, cy); f.minutes = slider('minutes', fx, cy, fw, 0, 240, f.minutes, 5, '%d'); cy = cy + 24
    row_label('Minimum level', lx, cy); f.min_level = slider('minlevel', fx, cy, fw, 1, 100, f.min_level, 1, '%d'); cy = cy + 24
    row_label('Gold', lx, cy); f.gold = slider('gold', fx, cy, fw, 0, 100000, f.gold, 100, '%d'); cy = cy + 26
    row_label('Item', lx, cy)
    local _, mi = ui.dropdown('mode', fx, cy, 200, ITEM_MODES, f.mode)
    f.mode = mi
    if f.mode == 2 or f.mode == 3 then
        local _, ti = ui.dropdown('tier', fx + 208, cy, 100, TIERS, f.tier)
        f.tier = ti
    end
    cy = cy + 26
    if f.mode == 4 then
        row_label('Find an item', lx, cy)
        f.search = field('search', fx, cy, 200, f.search, 'Part of an item name in your game language, e.g. sword, ring, helmet')
        search_items(f.search)
        cy = cy + 24
        if #search_results > 0 then
            local names = {}
            for i, m in ipairs(search_results) do names[i] = m.name end
            if f.pick > #names then f.pick = 1 end
            row_label('Matches', lx, cy)
            local _, pi2 = ui.dropdown('pick', fx, cy, fw - 52, names, f.pick)
            f.pick = pi2
            if ui.button('addpick', fx + fw - 46, cy, 46, 20, 'Add') then
                local m = search_results[f.pick]
                if m and #f.chosen < 12 then f.chosen[#f.chosen + 1] = {id = m.id, name = m.name} end
            end
            cy = cy + 24
        end
        local line = {}
        for _, t in ipairs(f.chosen) do line[#line + 1] = t.name end
        ui.text(#line > 0 and ('Drops one of: ' .. table.concat(line, ', ')) or 'No item chosen yet: search and press Add.',
            fx, cy, {size = 11, color = #line > 0 and GOLD or RED, width = fw})
        if #line > 0 and ui.button('clearpick', fx + fw - 60, cy - 2, 60, 18, 'Clear') then f.chosen = {} end
        cy = cy + 20
    end
    local _, on = ui.checkbox('trig', lx, cy, 'Start automatically after kills', f.trigger_on,
        {tooltip = 'Counts kills of the creatures below; at the count the bounty starts, unless it is already running'})
    f.trigger_on = on
    cy = cy + 24
    if f.trigger_on then
        row_label('Trigger creatures', lx, cy)
        ui.text('(empty: as the bounty)', lx, cy + 18, {size = 10, color = GREY})
        cy = cy + picker('trig', fx, cy, fw, f.trigger_words) + 4
        row_label('Kills to start', lx, cy); f.count = slider('count', fx, cy, fw, 1, 1000, f.count, 1, '%d'); cy = cy + 24
        row_label('Cooldown (min)', lx, cy); f.cooldown = slider('cool', fx, cy, fw, 0, 240, f.cooldown, 5, '%d'); cy = cy + 26
    end
    local by = math.max(cy + 4, y + h - 26)
    local blocked = f.title:match('%S') == nil or (f.mode == 4 and #f.chosen == 0)
    if ui.button('save', x, by, 100, 22, 'Save', {enabled = not blocked}) then
        local saved = customs.put(def_of(f))
        if saved then flash = {text = 'Saved', at = gear.time()} end
        form, focus = nil, nil
    end
    if ui.button('cancel', x + 108, by, 100, 22, 'Cancel') then form, focus = nil, nil end
end

local function draw_list(x, y, w, h, hooks)
    if ui.button('new', x, y, 120, 22, 'New bounty') then form = new_form(); focus = nil; return end
    if ui.button('reload', x + 128, y, 120, 22, 'Reload file', {tooltip = 'Read custom.json again after editing it by hand'}) then
        customs.load()
    end
    if flash and gear.time() - flash.at < 3 then ui.text(flash.text, x + 260, y + 4, {color = GREEN, size = 12}) end
    local cy = y + 30
    if #customs.defs == 0 then
        local lines = ui.text_wrap('No bounties of your own yet. "New bounty" makes one: pick the creatures, how many, and the reward. '
            .. 'Start it here, or let it start by itself after some kills. Good for challenges on a stream.', w, {size = 12})
        for i, line in ipairs(lines) do ui.text(line, x, cy + (i - 1) * 15, {color = GREY, size = 12}) end
        return
    end
    local area = ui.scroll_begin('custom-list', x, cy, w, h - 34)
    local ay = area.content_y
    local ax, aw = area.content_x, area.w - 6
    for _, d in ipairs(customs.defs) do
        local running = hooks.active(d.id)
        ui.text(d.title, ax, ay, {color = running and GREEN or GOLD, size = 14, bold = true})
        ui.text(customs.summary(d), ax, ay + 17, {color = 0xFFE0E0E0, size = 11, width = aw - 200})
        local extra = {}
        if d.minutes > 0 then extra[#extra + 1] = d.minutes .. ' min' end
        if d.trigger.on then
            local cool, n = hooks.trigger_state(d.id)
            extra[#extra + 1] = cool > 0 and ('auto: ready in ' .. math.ceil(cool / 60) .. ' min')
                or ('auto: ' .. n .. '/' .. d.trigger.count .. ' kills')
        end
        if running then extra[#extra + 1] = ('running %d/%d'):format(running.n, running.target) end
        ui.text(table.concat(extra, ', '), ax, ay + 31, {color = GREY, size = 10, width = aw - 200})
        local bx = ax + aw - 196
        if ui.button('go:' .. d.id, bx, ay + 4, 56, 20, running and 'Stop' or 'Start') then
            if running then hooks.stop(d.id) else hooks.start(d) end
        end
        if ui.button('ed:' .. d.id, bx + 60, ay + 4, 64, 20, 'Edit') then form = new_form(d); focus = nil end
        if ui.button('del:' .. d.id, bx + 128, ay + 4, 68, 20, 'Delete') then hooks.stop(d.id); customs.remove(d.id) end
        ay = ay + 52
    end
    ui.scroll_end(ay - area.content_y)
end

-- hooks: active(def_id) -> bounty or nil, start(def), stop(def_id), trigger_state(def_id) -> cooldown, count
function E.draw(hooks)
    local p = ui.panel('editor', 'Bounty editor', 240, 40, 560, 600, {resizable = true, min_width = 520, min_height = 300})
    if not p.open then
        if focus then focus = nil ui.capture_keys(false) end
        return
    end
    ui.capture_keys(focus ~= nil)
    local x, y, w, h = p.content_x, p.content_y, p.content_w, p.content_h
    if form then draw_form(x, y, w, h) else draw_list(x, y, w, h, hooks) end
end

function E.open() form, focus = nil, nil; ui.show_panel('editor', true) end

-- Opens the panel on the form (a new bounty, or the definition `def`); the self test uses it for the picture.
function E.open_form(def) form, focus = new_form(def), nil; ui.show_panel('editor', true) end

return E
