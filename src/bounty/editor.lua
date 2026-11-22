-- The bounty editor window (single player): list of the player's own bounties with Start / Stop / Edit / Delete, and a form to make
-- one: title, creatures, how many, time limit, minimum level, gold, an item (random, for the hero's class, or chosen types)
-- and an optional automatic trigger ("kill 10 orcs to start it, then wait 30 minutes").
--
-- ui/editor.rml (the game theme). Text fields and sliders are bound with data-value (the document hands the values back through
-- on_change); the item mode and tier are buttons that step through their options; the creature picker is the chosen creatures as
-- buttons (click one to remove it), a filter field and the matching creatures as rows to click.

local ui = gear.ui
local customs = require('customs')
local creatures = require('creatures')

local E = {}

local ITEM_MODES = {'No item', 'Random item', 'Random item for my class', 'Chosen items'}
local MODE_OF = {nil, 'tier', 'class', 'specific'}
local TIERS = {'Good', 'Rare', 'Best'}
local MAX_OPTS = 40
local form = nil           -- the definition being edited (a working copy), or nil: the list is shown
local flash = nil          -- {text, at}
local shown = false
local doc
local last = {}
local hooks_ref            -- the hooks of main.lua, set by draw()
local ids = {}             -- element id -> action data

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
        count = d.trigger.count, cooldown = d.trigger.cooldown, chosen = {}, tier = 1, mode = 1,
        names_filter = '', trig_filter = '',
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

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

-- The creature picker of one block ('n' creatures, 't' trigger): chips and the matching options.
local function picker_model(prefix, words, types, filter)
    ids[prefix] = {}
    local p = {any = #words == 0 and #types == 0, chips = {}, opts = {}}
    for i, word in ipairs(words) do
        p.chips[#p.chips + 1] = {id = prefix .. 'w' .. i, label = creatures.label(word)}
    end
    for i, t in ipairs(types) do
        p.chips[#p.chips + 1] = {id = prefix .. 't' .. i, label = creatures.type_label(t)}
    end
    local labels, entries = creatures.options(filter)
    for i = 2, math.min(#labels, MAX_OPTS) do
        if entries[i] then
            p.opts[#p.opts + 1] = {id = prefix .. 'o' .. i, label = labels[i]}
            ids[prefix][prefix .. 'o' .. i] = entries[i]
        end
    end
    return p
end

local function add_entry(words, types, entry)
    for _, word in ipairs(entry.words or {}) do
        local have = false
        for _, v in ipairs(words) do if v == word then have = true end end
        if not have and #words + #types < 30 then words[#words + 1] = word end
    end
    for _, t in ipairs(entry.types or {}) do
        local have = false
        for _, v in ipairs(types) do if v == t then have = true end end
        if not have and #words + #types < 30 then types[#types + 1] = t end
    end
end

local INPUT_KEYS = {f_title = true, f_target = true, f_minutes = true, f_minlevel = true, f_gold = true, f_count = true,
    f_cool = true, f_names_filter = true, f_trig_filter = true}

local function blank()
    return {open = false, view = 'list', flash = '', defs = {}, list_empty = false,
        mode_label = '', show_tier = false, tier_label = '', show_items = false, items_line = '', items_ok = false,
        trigger_on = false, blocked = false,
        names = {any = true, chips = {}, opts = {}}, trig = {any = true, chips = {}, opts = {}},
        f_title = '', f_target = 10, f_minutes = 0, f_minlevel = 1, f_gold = 500, f_count = 10, f_cool = 30,
        f_names_filter = '', f_trig_filter = ''}
end

local function inputs_of(f)
    return {f_title = f.title, f_target = f.target, f_minutes = f.minutes, f_minlevel = f.min_level, f_gold = f.gold,
        f_count = f.count, f_cool = f.cooldown, f_names_filter = f.names_filter, f_trig_filter = f.trig_filter}
end

local function snapshot()
    local m = blank()
    m.open = shown
    if not shown then return m end
    ids = {}
    if form then
        local f = form
        m.view = 'form'
        m.mode_label = ITEM_MODES[f.mode]
        m.show_tier = f.mode == 2 or f.mode == 3
        m.tier_label = TIERS[f.tier]
        m.show_items = f.mode == 4
        local line = {}
        for _, c in ipairs(f.chosen) do line[#line + 1] = c.name end
        m.items_ok = #line > 0
        m.items_line = #line > 0 and ('Drops one of: ' .. table.concat(line, ', ')) or 'No item chosen yet: search and press Add.'
        m.trigger_on = f.trigger_on
        m.names = picker_model('n', f.words, f.types, f.names_filter)
        m.trig = picker_model('t', f.trigger_words, f.trigger_types, f.trig_filter)
        m.blocked = f.title:match('%S') == nil or (f.mode == 4 and #f.chosen == 0)
    else
        m.view = 'list'
        if flash and gear.time() - flash.at < 3 then m.flash = flash.text end
        m.list_empty = #customs.defs == 0
        for i, d in ipairs(customs.defs) do
            local running = hooks_ref and hooks_ref.active(d.id)
            local extra = {}
            if d.minutes > 0 then extra[#extra + 1] = d.minutes .. ' min' end
            if d.trigger.on and hooks_ref then
                local cool, n = hooks_ref.trigger_state(d.id)
                extra[#extra + 1] = cool > 0 and ('auto: ready in ' .. math.ceil(cool / 60) .. ' min')
                    or ('auto: ' .. n .. '/' .. d.trigger.count .. ' kills')
            end
            if running then extra[#extra + 1] = ('running %d/%d'):format(running.n, running.target) end
            ids['go:' .. d.id], ids['ed:' .. d.id], ids['del:' .. d.id] = d, d, d
            m.defs[i] = {id_go = 'go:' .. d.id, id_ed = 'ed:' .. d.id, id_del = 'del:' .. d.id, title = d.title, summary = customs.summary(d),
                extra = table.concat(extra, ', '), running = running and true or false, go = running and 'Stop' or 'Start'}
        end
    end
    return m
end

-- Pushes the form's values into the document's inputs (when a form is opened or a creature was added).
local function sync_inputs()
    if not doc or not form then return end
    for k, v in pairs(inputs_of(form)) do doc.model[k] = v; last[k] = v end
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/editor.rml', {dp = true, model = m, on_change = function(_, model)
        local f = form
        if not f then return end
        f.title = tostring(model.f_title or f.title):sub(1, 60)
        f.target = tonumber(model.f_target) or f.target
        f.minutes = tonumber(model.f_minutes) or f.minutes
        f.min_level = tonumber(model.f_minlevel) or f.min_level
        f.gold = tonumber(model.f_gold) or f.gold
        f.count = tonumber(model.f_count) or f.count
        f.cooldown = tonumber(model.f_cool) or f.cooldown
        f.names_filter = tostring(model.f_names_filter or '')
        f.trig_filter = tostring(model.f_trig_filter or '')
        for k in pairs(INPUT_KEYS) do last[k] = model[k] end
    end})
    if not doc then gear.log('bounty editor: ui/editor.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('#new', function() form = new_form(); sync_inputs() end)
    on('#reload', function() customs.load() end)
    on('[id^=go:]', function(e)
        local d = ids[tostring(e.current)]
        if not (d and hooks_ref) then return end
        if hooks_ref.active(d.id) then hooks_ref.stop(d.id) else hooks_ref.start(d) end
    end)
    on('[id^=ed:]', function(e) local d = ids[tostring(e.current)]; if d then form = new_form(d); sync_inputs() end end)
    on('[id^=del:]', function(e)
        local d = ids[tostring(e.current)]
        if d and hooks_ref then hooks_ref.stop(d.id); customs.remove(d.id) end
    end)
    on('#mode', function() if form then form.mode = form.mode % #ITEM_MODES + 1 end end)
    on('#tier', function() if form then form.tier = form.tier % #TIERS + 1 end end)
    on('#finditem', function()
        local f = form
        if not f then return end
        gear.lookup.open('item', {title = 'Find an item', multi = true, select = function(c)
            for _, o in ipairs(f.chosen) do if o.id == c.id then return false end end
            if #f.chosen < 12 then f.chosen[#f.chosen + 1] = {id = c.id, name = c.name} end
        end})
    end)
    on('#clearpick', function() if form then form.chosen = {} end end)
    on('#trig', function() if form then form.trigger_on = not form.trigger_on end end)
    on('.chip', function(e)
        local f = form
        local prefix, kind, i = tostring(e.current):match('^(%a)(%a)(%d+)$')
        if not (f and prefix) then return end
        local list = prefix == 'n' and (kind == 'w' and f.words or f.types) or (kind == 'w' and f.trigger_words or f.trigger_types)
        table.remove(list, tonumber(i))
    end)
    on('.opt', function(e)
        local f = form
        local id = tostring(e.current)
        local prefix = id:sub(1, 1)
        local entry = ids[prefix] and ids[prefix][id]
        if not (f and entry) then return end
        if prefix == 'n' then
            add_entry(f.words, f.types, entry)
            f.names_filter = ''
        else
            add_entry(f.trigger_words, f.trigger_types, entry)
            f.trig_filter = ''
        end
        sync_inputs()
    end)
    on('#save', function()
        local f = form
        if not f or f.title:match('%S') == nil or (f.mode == 4 and #f.chosen == 0) then return end
        local saved = customs.put(def_of(f))
        if saved then flash = {text = 'Saved', at = gear.time()} end
        form = nil
    end)
    on('#cancel', function() form = nil end)
end

-- hooks: active(def_id) -> bounty or nil, start(def), stop(def_id), trigger_state(def_id) -> cooldown, count
function E.draw(hooks)
    hooks_ref = hooks
    if not shown then return end
    if not doc then load_doc() end
    if not doc then return end
    for k, v in pairs(snapshot()) do
        if not INPUT_KEYS[k] and not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
end

function E.open() form, shown = nil, true end
function E.close() shown = false end
function E.is_open() return shown end

-- Opens the window on the form (a new bounty, or the definition `def`); the self test uses it for the picture.
function E.open_form(def) form, shown = new_form(def), true; sync_inputs() end

return E
