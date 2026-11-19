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
local form = nil           -- the definition being edited (a working copy with text fields), or nil: the list is shown
local focus = nil          -- id of the text field that takes the keys
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

-- The creature picker: the chosen creatures as buttons (click one to remove it), a dropdown to add one (a group or a single
-- creature of the game) and a filter for the dropdown. `words` is the list being edited. Returns the height used.
local picks = {}           -- per picker id: {filter, index}
local function picker(id, x, y, w, target)
    local words, types = target.words, target.types
    local st = picks[id]
    if not st then st = {filter = '', index = 1} picks[id] = st end
    local cy = y
    local cx = x
    if #words == 0 and #types == 0 then
        ui.text('Any monster', x, cy + 3, {size = 12, color = GREY})
        cy = cy + 24
    else
        local remove_word, remove_type
        local function chip(key, text, on_click)
            local label = text .. '  x'
            local tw = (ui.text_size(label) or (#label * 7)) + 14
            if cx + tw > x + w and cx > x then cx = x cy = cy + 24 end
            if ui.button(id .. ':' .. key, cx, cy, tw, 20, label, {tooltip = 'Click to remove'}) then on_click() end
            cx = cx + tw + 4
        end
        for i, word in ipairs(words) do chip('w' .. i, creatures.label(word), function() remove_word = i end) end
        for i, t in ipairs(types) do chip('t' .. i, creatures.type_label(t), function() remove_type = i end) end
        if remove_word then table.remove(words, remove_word) end
        if remove_type then table.remove(types, remove_type) end
        cy = cy + 26
    end
    local labels, entries = creatures.options(st.filter)
    if st.index > #labels then st.index = 1 end
    local ch, idx = ui.dropdown(id .. ':add', x, cy, w - 130, labels, st.index, {max_rows = 12})
    if ch and entries[idx] then
        for _, word in ipairs(entries[idx].words or {}) do
            local have = false
            for _, v in ipairs(words) do if v == word then have = true end end
            if not have and #words + #types < 30 then words[#words + 1] = word end
        end
        for _, t in ipairs(entries[idx].types or {}) do
            local have = false
            for _, v in ipairs(types) do if v == t then have = true end end
            if not have and #words + #types < 30 then types[#types + 1] = t end
        end
        st.index = 1
    elseif ch then
        st.index = 1
    end
    ui.text('Filter', x + w - 124, cy + 3, {size = 11, color = GREY})
    st.filter = field(id .. ':filter', x + w - 84, cy, 84, st.filter, 'Type part of a creature name to shorten the list')
    st.height = cy + 24 - y
    return st.height
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
        id = d.id, title = d.title, words = copy(d.names), types = copy(d.types or {}), target = d.target, minutes = d.minutes,
        min_level = d.min_level, gold = d.gold, trigger_on = d.trigger.on, trigger_words = copy(d.trigger.names),
        trigger_types = copy(d.trigger.types or {}),
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
        id = f.id, title = f.title, names = f.words, types = f.types, target = f.target, minutes = f.minutes, min_level = f.min_level,
        gold = f.gold, item = item,
        trigger = {on = f.trigger_on, names = (#f.trigger_words + #f.trigger_types > 0) and f.trigger_words or f.words,
            types = (#f.trigger_words + #f.trigger_types > 0) and f.trigger_types or f.types, count = f.count,
            cooldown = f.cooldown},
    }
end

local function draw_form(x, y, w, h)
    local f = form
    -- Label column, then the fields; the item mode has a dropdown of 200 and the tier's of 100 beside it.
    local t = ui.table('form', x, y, w - 8, {columns = {142, 200, 100, '*'}, row_height = 22})
    local LABEL = {color = GREY, size = 12}
    local function slider(id, label, lo, hi, value, step)
        t:row()
        t:label(1, label, LABEL)
        local _, v = t:slider(2, lo, hi, value, {id = id, span = 3, step = step, format = '%d', value_width = 56})
        return v
    end
    t:row()
    t:label(1, 'Title', LABEL)
    do
        local fx, fy, fw = t:cell(2, 3)
        f.title = field('title', fx, fy + 1, fw, f.title)
    end
    t:row((picks.names and picks.names.height) or 50)
    t:label(1, 'Creatures', {color = GREY, size = 12, valign = 'top'})
    do
        local fx, fy, fw = t:cell(2, 3)
        picker('names', fx, fy, fw, {words = f.words, types = f.types})
    end
    f.target = slider('target', 'How many', 1, 1000, f.target, 1)
    f.minutes = slider('minutes', 'Time limit (0 = none)', 0, 240, f.minutes, 5)
    f.min_level = slider('minlevel', 'Minimum level', 1, 100, f.min_level, 1)
    f.gold = slider('gold', 'Gold', 0, 100000, f.gold, 100)
    t:row()
    t:label(1, 'Item', LABEL)
    local _, mi = t:dropdown(2, ITEM_MODES, f.mode, {id = 'mode'})
    f.mode = mi
    if f.mode == 2 or f.mode == 3 then
        local _, ti = t:dropdown(3, TIERS, f.tier, {id = 'tier'})
        f.tier = ti
    end
    if f.mode == 4 then
        t:row()
        t:label(1, 'Items', LABEL)
        if t:button(2, 'Find an item...', {id = 'finditem', tooltip = 'Search by the name of the item in your language; typos are fine'}) then
            gear.lookup.open('item', {title = 'Find an item', multi = true, select = function(c)
                for _, o in ipairs(f.chosen) do if o.id == c.id then return false end end
                if #f.chosen < 12 then f.chosen[#f.chosen + 1] = {id = c.id, name = c.name} end
            end})
        end
        local line = {}
        for _, c in ipairs(f.chosen) do line[#line + 1] = c.name end
        if #line > 0 and t:button(3, 'Clear', {id = 'clearpick'}) then f.chosen = {} end
        t:row(18)
        t:label(2, #line > 0 and ('Drops one of: ' .. table.concat(line, ', ')) or 'No item chosen yet: search and press Add.',
            {span = 3, size = 11, color = #line > 0 and GOLD or RED})
    end
    t:row()
    local _, on = t:checkbox(1, 'Start automatically after kills', f.trigger_on, {id = 'trig', span = 4,
        tooltip = 'Counts kills of the creatures below; at the count the bounty starts, unless it is already running'})
    f.trigger_on = on
    if f.trigger_on then
        t:row((picks.trig and picks.trig.height) or 50)
        t:label(1, 'Trigger creatures', {color = GREY, size = 12, valign = 'top'})
        do
            local fx, fy, fw = t:cell(2, 3)
            ui.text('(empty: as the bounty)', t:column(1), fy + 18, {size = 10, color = GREY})
            picker('trig', fx, fy, fw, {words = f.trigger_words, types = f.trigger_types})
        end
        f.count = slider('count', 'Kills to start', 1, 1000, f.count, 1)
        f.cooldown = slider('cool', 'Cooldown (min)', 0, 240, f.cooldown, 5)
    end
    local by = math.max(y + t:height() + 8, y + h - 26)
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
    -- Title, summary and state on the left; Start / Stop, Edit and Delete in three columns on the right.
    local t = ui.table('custom-list', area.content_x, area.content_y, area.w - 6, {
        columns = {'*', 56, 64, 68}, row_height = 48,
    })
    for _, d in ipairs(customs.defs) do
        local running = hooks.active(d.id)
        t:row()
        local ax, ay, aw = t:cell(1)
        ui.text(d.title, ax, ay, {color = running and GREEN or GOLD, size = 14, bold = true, width = aw})
        ui.text(customs.summary(d), ax, ay + 17, {color = 0xFFE0E0E0, size = 11, width = aw})
        local extra = {}
        if d.minutes > 0 then extra[#extra + 1] = d.minutes .. ' min' end
        if d.trigger.on then
            local cool, n = hooks.trigger_state(d.id)
            extra[#extra + 1] = cool > 0 and ('auto: ready in ' .. math.ceil(cool / 60) .. ' min')
                or ('auto: ' .. n .. '/' .. d.trigger.count .. ' kills')
        end
        if running then extra[#extra + 1] = ('running %d/%d'):format(running.n, running.target) end
        ui.text(table.concat(extra, ', '), ax, ay + 31, {color = GREY, size = 10, width = aw})
        if t:button(2, running and 'Stop' or 'Start', {id = 'go:' .. d.id, height = 20, valign = 'top'}) then
            if running then hooks.stop(d.id) else hooks.start(d) end
        end
        if t:button(3, 'Edit', {id = 'ed:' .. d.id, height = 20, valign = 'top'}) then form = new_form(d); focus = nil end
        if t:button(4, 'Delete', {id = 'del:' .. d.id, height = 20, valign = 'top'}) then hooks.stop(d.id); customs.remove(d.id) end
    end
    ui.scroll_end(t:height())
end

-- hooks: active(def_id) -> bounty or nil, start(def), stop(def_id), trigger_state(def_id) -> cooldown, count
function E.draw(hooks)
    local p = ui.panel('editor', 'Bounty editor', 240, 40, 560, 600, {resizable = true, min_width = 520, min_height = 300})
    if not p.open then
        if focus then focus = nil ui.capture_keys(false) end
        return
    end
    ui.capture_keys(focus ~= nil or gear.lookup.is_open())
    local x, y, w, h = p.content_x, p.content_y, p.content_w, p.content_h
    if form then draw_form(x, y, w, h) else draw_list(x, y, w, h, hooks) end
end

function E.open() form, focus = nil, nil; ui.show_panel('editor', true) end

-- Opens the panel on the form (a new bounty, or the definition `def`); the self test uses it for the picture.
function E.open_form(def) form, focus = new_form(def), nil; ui.show_panel('editor', true) end

return E
