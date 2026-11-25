-- Balance editor: edits the values of the game's bin\balance.bin.
--
-- How the game gets the values: the mod ships `overlay.txt` (bin\balance.bin = patch:balance.lua). Sacred Gear serves the game its own
-- file with the changes of balance.lua applied, built into this mod's cache folder; the game's file is never written. This mod writes
-- balance.lua from the values you picked (kept in edits.json) and Gear reads it when the game starts, which is why a change needs a restart.
-- Switch the mod off or delete it and the game reads its own file again. Hosted and LAN games: Gear starts the game server with the same
-- overlay, so everyone who joins needs the same patch.
local catalog = require('catalog')
local core = require('core')

local ui = gear.ui
local fit = gear.fmt and gear.fmt.fit or function(s, n) s = tostring(s or ''); return #s > n and (s:sub(1, n - 1) .. '...') or s end

local MAX_ROWS = 150
local SAVE_DELAY = 0.6

local edits = {}                     -- field id -> the value you picked (only values that differ from the game's)
local view = {
    tab = 'difficulty', group = 1, q = '', only_changed = false, dd = '',
    confirm_all = false, confirm_until = 0, pname = '', share_msg = '', share_bad = false, imp = nil, undo = nil,
}
local shown = false
local doc, last, rows = nil, {}, {}
local rows_dirty = true
local save_at = nil
local quiet_until = 0               -- RmlUi echoes a `change` for every slider it sets from the data model: those are not the player's
local start_text = nil               -- balance.lua as the game read it when it started
local current_text = nil             -- balance.lua as it is now
local started_with_patch = false

---------------------------------------------------------------------------------------------------------- persistence
local function load_edits()
    local data = gear.store.load('edits.json', {})
    local values = type(data.values) == 'table' and data.values or {}
    for id, v in pairs(values) do
        local f = catalog.by_id[id]
        if f then
            local ok = core.check(f, v)
            if ok ~= nil then edits[id] = ok end
        end
    end
    core.prune(edits)
    if type(data.pname) == 'string' then view.pname = data.pname:sub(1, 40) end
end

local function write_files()
    save_at = nil
    local ok, err = gear.store.save('edits.json', {values = edits, pname = view.pname})
    if not ok then gear.log('balance-editor: edits.json not written: ' .. tostring(err)) end
    local text = core.build_patch(edits)
    if text ~= current_text then
        local saved, why = gear.save('balance.lua', text)
        if saved then current_text = text else gear.log('balance-editor: balance.lua not written: ' .. tostring(why)) end
    end
end

local function touch() save_at = gear.time() + SAVE_DELAY end

---------------------------------------------------------------------------------------------------------- what is listed
local skill_names = {}
local function skill_name(n)
    local v = skill_names[n]
    if v == nil then
        local ok, t = pcall(function() return gear.text and gear.text.get(9399 + n) end)
        v = (ok and type(t) == 'string' and t ~= '') and t or false
        skill_names[n] = v
    end
    return v
end

-- A group's name for the player: "Skill 4: attack" shows the game's name of that skill when the game has one.
local function group_label(g)
    local n, rest = g:match('^Skill (%d+)(.*)$')
    if n then
        local name = skill_name(tonumber(n))
        if name then return name .. rest end
    end
    return g
end

local function tab_label(id)
    for _, t in ipairs(catalog.TABS) do if t.id == id then return t.label end end
    return id
end

local function value_of(f)
    local v = edits[f.id]
    if v ~= nil then return v end
    return core.vanilla(f)
end

local function is_changed(f) return edits[f.id] ~= nil end

local function matches(f, words)
    local hay = (f.label .. ' ' .. group_label(f.group) .. ' ' .. tab_label(f.tab) .. ' ' .. (f.tip or '')):lower()
    for _, w in ipairs(words) do
        if not hay:find(w, 1, true) then return false end
    end
    return true
end

local function group_list()
    return catalog.groups[view.tab] or {}
end

-- The fields the current view lists, in catalog order.
local function visible()
    local out = {}
    local q = view.q:lower():gsub('^%s+', ''):gsub('%s+$', '')
    local words = {}
    for w in q:gmatch('%S+') do words[#words + 1] = w end
    local group = view.group > 1 and group_list()[view.group - 1] or nil
    for _, f in ipairs(catalog.fields) do
        local pass
        if #words > 0 then pass = matches(f, words)
        else pass = f.tab == view.tab and (not group or f.group == group) end
        if pass and view.only_changed and not is_changed(f) then pass = false end
        if pass then out[#out + 1] = f end
    end
    return out
end

local function build_rows()
    local list = visible()
    local out, prev = {}, nil
    local searching = view.q:match('%S') ~= nil
    for i = 1, math.min(#list, MAX_ROWS) do
        local f = list[i]
        local head = ''
        local key = f.tab .. '/' .. f.group
        if key ~= prev then
            head = group_label(f.group)
            if searching then head = tab_label(f.tab) .. ': ' .. head end
            prev = key
        end
        local v = value_of(f)
        out[i] = {
            rid = 'r' .. f.index, xid = 'x' .. f.index, label = f.label, head = head, tip = fit(f.tip or '', 300),
            min = f.min, max = f.max, step = f.step, value = v, text = core.format(f, v), vanilla = core.format(f, core.vanilla(f)),
            changed = is_changed(f), index = f.index,
        }
    end
    return out, #list
end

local function counts()
    local total, per_tab, per_group = 0, {}, {}
    for id in pairs(edits) do
        local f = catalog.by_id[id]
        total = total + 1
        per_tab[f.tab] = (per_tab[f.tab] or 0) + 1
        per_group[f.tab .. '/' .. f.group] = (per_group[f.tab .. '/' .. f.group] or 0) + 1
    end
    return total, per_tab, per_group
end

---------------------------------------------------------------------------------------------------------- the on-screen keyboard
-- gear.kit.osk (a small window of its own, bordered keys, pad and mouse); it types into the search or the patch name like the player's own keys.
local kb = gear.kit.osk and gear.kit.osk{}
local function set_search(t)
    view.q = t:sub(1, 30)
    if doc then doc.model.q = view.q; last.q = view.q end
    rows_dirty = true
end
local function set_pname(t)
    view.pname = t:sub(1, 40)
    if doc then doc.model.pname = view.pname; last.pname = view.pname end
    touch()
end
local function open_osk(name)
    if not kb then return end
    if name == 'name' then
        kb:toggle{title = 'Patch name', text = view.pname, max = 40, on_change = set_pname, get = function() return view.pname end}
    else
        kb:toggle{title = 'Search', text = view.q, max = 30, on_change = set_search, get = function() return view.q end}
    end
end

---------------------------------------------------------------------------------------------------------- the document's model
local function state_line(total)
    local served = 0
    pcall(function() served = gear.files.served(catalog.FILE) end)
    local pending = current_text ~= start_text
    if pending then
        return 'Changes are saved. They apply when the game starts again: restart Sacred.', false, true
    elseif total == 0 then
        return 'No changes: the game runs with its own balance.bin.', false, false
    elseif served > 0 then
        return ('Active: the game read your %d changes at its start.'):format(total), true, false
    end
    return 'Your changes are saved, but the game did not read them at its start (its balance.bin may not be the Sacred Gold file).', false, true
end

local function import_model()
    local imp = view.imp
    local m = {imp_open = false, imp_title = '', imp_note = '', imp_counts = '', imp_rows = {}, imp_changes = 0}
    if not imp then return m end
    m.imp_open = true
    local r = imp.report
    m.imp_title = r.name ~= '' and ('Import: ' .. r.name) or 'Import'
    m.imp_note = r.note
    local c = r.counts
    m.imp_counts = ('%d will change, %d already are as in the patch, %d rejected, %d unknown to this editor'):format(c.change, c.same, c.rejected, c.unknown)
    m.imp_changes = c.change
    for i, row in ipairs(r.rows) do
        if i > 200 then break end
        local f = catalog.by_id[row.id]
        local change
        if row.status == 'change' and f then change = core.format(f, row.current) .. '  >  ' .. core.format(f, row.new)
        elseif row.status == 'same' and f then change = core.format(f, row.new) .. ' (unchanged)'
        else change = row.why or row.status end
        local label = row.group and (tab_label(row.tab) .. ': ' .. group_label(row.group) .. ': ' .. row.label) or fit(row.label, 60)
        m.imp_rows[#m.imp_rows + 1] = {label = fit(label, 70), change = fit(change, 50), same = row.status == 'same', bad = row.status == 'rejected' or row.status == 'unknown'}
    end
    return m
end

-- Everything except the lists that change only when the view does.
local function light()
    local total, per_tab, per_group = counts()
    local grp = group_list()
    local gkey = view.tab .. '/' .. (view.group > 1 and grp[view.group - 1] or '')
    local group_changed = 0
    if view.q ~= '' then
        for _, r in ipairs(rows) do if r.changed then group_changed = group_changed + 1 end end
    elseif view.group > 1 then group_changed = per_group[view.tab .. '/' .. grp[view.group - 1]] or 0
    else group_changed = per_tab[view.tab] or 0 end
    local m = {
        open = shown, win_title = 'Balance editor' .. (gear.keys.label('toggle') ~= '' and (' (' .. gear.keys.label('toggle') .. ')') or ''),
        tab = view.tab, q = view.q, dd = view.dd, only_changed = view.only_changed, confirm_all = view.confirm_all,
        group_changed = group_changed, tab_changed = per_tab[view.tab] or 0, total_changed = total,
        reset_group_text = (view.q ~= '' and 'Reset these') or (view.group > 1 and 'Reset group') or 'Reset all shown',
        reset_all_text = view.confirm_all and 'Really reset everything?' or 'Reset all',
        pname = view.pname,
        share_msg = view.share_msg, share_bad = view.share_bad, can_undo = view.undo ~= nil,
        tabs = {},
    }
    for i, t in ipairs(catalog.TABS) do
        local n = per_tab[t.id] or 0
        m.tabs[i] = {id = 'tab-' .. t.id, name = t.label .. (n > 0 and (' (' .. n .. ')') or ''), on = view.tab == t.id and view.q == '', tip = ''}
    end
    m.tabs[#catalog.TABS + 1] = {id = 'tab-share', name = 'Share patches', on = view.tab == 'share', tip = 'Export your changes, import other players\' balance patches'}
    local s, good, warn = state_line(total)
    m.state_text, m.state_good, m.state_warn = s, good, warn
    return m
end

local function group_model()
    local opts = {{id = 'bal-group-1', label = 'All groups', on = view.group == 1}}
    for i, g in ipairs(group_list()) do opts[i + 1] = {id = 'bal-group-' .. (i + 1), label = group_label(g), on = view.group == i + 1} end
    local grp = group_list()
    return {key = 'group', title = 'Show one group of values', label = view.group > 1 and group_label(grp[view.group - 1] or '') or 'All groups', options = opts}
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function full_model()
    local m = light()
    local list, total = build_rows()
    rows = list
    m.rows = list
    m.group = group_model()
    local shown_n = #list
    m.count_text = total > shown_n and ('%d of %d shown'):format(shown_n, total) or ('%d value%s'):format(total, total == 1 and '' or 's')
    m.empty_text = total == 0 and (view.only_changed and 'You have not changed anything here.' or 'Nothing matches.') or ''
    for k, v in pairs(import_model()) do m[k] = v end
    return m
end

---------------------------------------------------------------------------------------------------------- actions
local function say(text, bad) view.share_msg = text; view.share_bad = bad and true or false end

local function set_value(f, v)
    v = core.clamp(f, v)
    if core.same(f, v, core.vanilla(f)) then edits[f.id] = nil else edits[f.id] = v end
    touch()
    return v
end

-- A row's data in the open document after its value changed (the slider itself is the player's hand and stays alone).
local function refresh_row(i, f, move_slider)
    local r = rows[i]
    if not r then return end
    local v = value_of(f)
    r.value, r.text, r.changed = v, core.format(f, v), is_changed(f)
    if doc then
        local mr = doc.model.rows[i]
        if mr then
            mr.text, mr.changed = r.text, r.changed
            if move_slider then mr.value = v end
        end
    end
end

local function reset_fields(list)
    local n = 0
    for _, f in ipairs(list) do
        if edits[f.id] ~= nil then edits[f.id] = nil; n = n + 1 end
    end
    if n > 0 then touch(); rows_dirty = true end
    return n
end

local function fields_in_view()
    local out = {}
    for _, f in ipairs(visible()) do out[#out + 1] = f end
    return out
end

local function set_tab(id)
    if view.tab == id and view.q == '' then return end
    view.tab, view.group, view.dd = id, 1, ''
    view.q = ''
    if doc then doc.model.q = '' ; last.q = '' end
    view.confirm_all = false
    if kb then kb:close() end
    rows_dirty = true
end

local function decode_import(text, source)
    if type(text) ~= 'string' or text == '' then say(source .. ' holds no text.', true) return end
    if #text > core.MAX_TEXT then say('That is too large for a balance patch.', true) return end
    local ok, data = pcall(gear.json.decode, text)
    if not ok or type(data) ~= 'table' then say('That is not a balance patch (it must be JSON).', true) return end
    local report = core.read_import(data, edits)
    if not report.ok then say(report.error or 'That is not a balance patch.', true) return end
    view.imp = {report = report}
    say(('Read %d entries from %s. Nothing changed yet.'):format(#report.rows, source))
    rows_dirty = true
end

local function do_export()
    local total = counts()
    if total == 0 then say('Nothing to export: you have not changed anything.', true) return end
    local patch = core.export(edits, {name = view.pname, note = ''})
    local text = gear.json.encode(patch)
    local saved, err = gear.save('export.json', text)
    local copied = false
    if gear.clipboard then copied = gear.clipboard.set(text) and true or false end
    if saved then
        say(('Exported %d changes to export.json in the mod\'s folder%s.'):format(#patch.changes, copied and ' and copied them to the clipboard' or ''))
    elseif copied then
        say(('Copied %d changes to the clipboard (the file could not be written: %s).'):format(#patch.changes, tostring(err)))
    else
        say('Could not export: ' .. tostring(err), true)
    end
end

local function snapshot_edits()
    local c = {}
    for k, v in pairs(edits) do c[k] = v end
    return c
end

local function apply_import()
    local imp = view.imp
    if not imp then return end
    local before = snapshot_edits()
    local n = core.apply_import(edits, imp.report)
    view.undo = before
    view.imp = nil
    say(('Applied %d changes. Restart the game to use them; "Undo import" takes them back.'):format(n))
    touch()
    rows_dirty = true
end

local function undo_import()
    if not view.undo then return end
    edits = view.undo
    view.undo = nil
    core.prune(edits)
    say('The import was undone.')
    touch()
    rows_dirty = true
end

---------------------------------------------------------------------------------------------------------- the document
local function load_doc()
    local m = full_model()
    last = m
    local err
    doc, err = ui.rml.load('ui/main.rml', {dp = true, model = m, on_change = function(_, model)
        local q = tostring(model.q or ''):sub(1, 30)
        if q ~= view.q then view.q = q; rows_dirty = true end
        local name = tostring(model.pname or ''):sub(1, 40)
        if name ~= view.pname then view.pname = name; touch() end
    end})
    if not doc then gear.log('balance-editor: ui/main.rml failed: ' .. tostring(err)) return end
    local function on(sel, ev, fn) doc:on(sel, ev, gear.guard(ev .. ' ' .. sel, fn)) end
    local function click(sel, fn) on(sel, 'click', fn) end
    local function field_of(id, prefix)
        local n = tonumber(tostring(id):match('^' .. prefix .. '(%d+)$'))
        return n and catalog.fields[n] or nil
    end
    local function row_index(f)
        for i, r in ipairs(rows) do if r.index == f.index then return i end end
    end

    click('.tab', function(e)
        local id = tostring(e.current):match('^tab%-(.+)$')
        if id then set_tab(id) end
    end)
    on('.bal-slider', 'change', function(e)
        local f = field_of(e.current, 'r')
        local v = tonumber(e.params and e.params.value)
        if not f or not v or gear.time() < quiet_until then return end
        local i = row_index(f)
        -- RmlUi also fires `change` when a slider is created or set from the data model; only a move of at least half a step is the player's
        local cur = value_of(f)
        if math.abs(v - cur) < f.step * 0.5 then return end
        set_value(f, v)
        if i then refresh_row(i, f, false) end
    end)
    click('.bal-reset', function(e)
        local f = field_of(e.current, 'x')
        if not f or edits[f.id] == nil then return end
        edits[f.id] = nil
        touch()
        local i = row_index(f)
        quiet_until = gear.time() + 0.4
        if i then refresh_row(i, f, true) end
        if view.only_changed then rows_dirty = true end
    end)
    click('#bal-ddshade', function() view.dd = '' end)
    click('#group', function() view.dd = view.dd == 'group' and '' or 'group' end)
    click('.bal-ddlist .opt', function(e)
        local i = tonumber(tostring(e.current):match('^bal%-group%-(%d+)$'))
        if i and i >= 1 and i <= #group_list() + 1 then view.group = i; rows_dirty = true end
        view.dd = ''
    end)
    click('#only-changed', function() view.only_changed = not view.only_changed; rows_dirty = true end)
    click('#clear-search', function() view.q = ''; doc.model.q = ''; last.q = ''; rows_dirty = true end)
    if kb then   -- (the buttons show only while the pad is the input; A on a field opens the keyboard too)
        kb:attach(doc, {field = '#search', button = '#kbd-search', open = function() open_osk('q') end})
        kb:attach(doc, {field = '#pname', button = '#kbd-name', open = function() open_osk('name') end})
    end
    click('#reset-group', function()
        reset_fields(fields_in_view())
        view.confirm_all = false
    end)
    click('#reset-tab', function()
        local list = {}
        for _, f in ipairs(catalog.fields) do if f.tab == view.tab then list[#list + 1] = f end end
        reset_fields(list)
        view.confirm_all = false
    end)
    click('#reset-all', function()
        if not view.confirm_all then view.confirm_all = true; view.confirm_until = gear.time() + 4 return end
        view.confirm_all = false
        reset_fields(catalog.fields)
    end)
    click('#export', do_export)
    click('#import-clip', function()
        local text = gear.clipboard and gear.clipboard.get()
        decode_import(text, 'the clipboard')
    end)
    click('#import-file', function()
        local text, err = gear.read('import.json')
        if not text then say('Put the balance patch in the mod\'s folder as import.json first (' .. tostring(err or 'no file') .. ').', true) return end
        decode_import(text, 'import.json')
    end)
    click('#imp-apply', apply_import)
    click('#imp-cancel', function() view.imp = nil; say('Import cancelled, nothing changed.'); rows_dirty = true end)
    click('#undo-import', undo_import)
end

local function open_close(on)
    if on == nil then on = not shown end
    shown = on
    if not shown then
        if kb then kb:close() end
        view.dd = ''
        write_files()
    end
end

gear.keys.on('toggle', function() open_close() end)
if ui.menu_item then pcall(ui.menu_item, 'balance', 'Balance editor', function() open_close() end) end

gear.on('draw', gear.guard('draw', function(state)
    if not state then return end
    if save_at and gear.time() >= save_at then write_files() end
    if view.confirm_all and gear.time() > view.confirm_until then view.confirm_all = false end
    if not shown then return end
    if state.mode ~= 'game' and state.mode ~= 'menus' then return end
    if state.mode == 'game' and state.exclusive then return end
    if not doc then quiet_until = gear.time() + 0.6; load_doc(); rows_dirty = false end
    if not doc then return end
    if rows_dirty then
        rows_dirty = false
        quiet_until = gear.time() + 0.4
        local m = full_model()
        for k, v in pairs(m) do
            if not same(v, last[k]) or k == 'rows' then doc.model[k] = v; last[k] = v end
        end
    else
        for k, v in pairs(light()) do
            if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
        end
    end
    doc:draw({layer = state.mode == 'game' and 'hud' or 'top'})
    if kb then kb:draw() end
end))

gear.on('unload', function()
    if save_at then write_files() end
end)

---------------------------------------------------------------------------------------------------------- start
start_text = gear.read('balance.lua') or ''
load_edits()
current_text = start_text
-- bring balance.lua in line with edits.json (it differs after an update of this mod, or a copied edits.json)
write_files()
started_with_patch = current_text == start_text

-- For the self test and tools.
gear.on('balance-editor.state', function(answer)
    answer({edits = snapshot_edits(), pending = current_text ~= start_text, served = (function()
        local n = 0
        pcall(function() n = gear.files.served(catalog.FILE) end)
        return n
    end)()})
end)
gear.on('balance-editor.set', function(id, value)
    local f = catalog.by_id[id]
    if not f then return false end
    set_value(f, value)
    rows_dirty = true
    return true
end)
gear.on('balance-editor.import', function(text) decode_import(text, 'a test') ; return view.imp ~= nil end)
gear.on('balance-editor.apply', function() apply_import() end)
gear.on('balance-editor.open', function(on, tab)
    if tab then set_tab(tab) end
    open_close(on)
end)
