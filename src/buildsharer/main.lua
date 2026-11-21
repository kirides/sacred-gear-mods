-- Build sharer: a panel (Ctrl+K) to publish your hero build to the game server and to browse the builds other players shared.
-- Server half: SacredEngineRemake Sacred.GameServer/scripts-examples/build_sharer.lua (channel 'buildsharer'). The server fills class,
-- level, skills and equipment from its own view of your hero; this mod sends a title, a note, tags (settings in the Mods screen) and
-- the names of the best items in your backpack. Gear cannot read a hero's skills or worn equipment, so nothing else can be sent.
-- Browsing: filter by class, sort, page; click a build to fetch it in full, and keep it in "Saved" (saved_builds.json in this mod's folder).
--
-- Nothing a server sends is trusted for more than showing it: texts are cut to a length, only the server (slot 0) is listened to.

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local ui, net = gear.ui, gear.net
local ch = net.channel('buildsharer')
local PAGE = tonumber(gear.config.page_size) or 12
local TABS = {'Browse', 'My build', 'Saved', 'Detail'}
local CLASSES = {'All classes', 'Seraphim', 'Gladiator', 'Battle Mage', 'Dark Elf', 'Wood Elf', 'Vampiress', 'Dwarf', 'Daemon'}
local CLASS_FILTER = {false, 1, 2, 3, 4, 5, 6, 8, 9}     -- false: all
local class_labels
-- the dropdown's entries: the game's own (localized) hero names, the English ones where the game has none
local function class_choices()
    if not class_labels then
        class_labels = {}
        for i, name in ipairs(CLASSES) do
            local t = CLASS_FILTER[i]
            if t then
                local ok, n = pcall(function() return gear.data.object_types:display_name(t) end)
                if ok and type(n) == 'string' and n ~= '' then name = n end
            end
            class_labels[i] = name
        end
    end
    return class_labels
end
local SORTS = {'Newest', 'Highest level'}
local SORT_KEY = {'new', 'level'}
local MAX_SAVED = 50

local view = {             -- what the panel shows and waits for
    tab = 1, class = 1, sort = 1, page = 1, list = nil, detail = nil, mine = nil, hero_data = nil,
    saved = {}, status = '', last_request = 0, opened = false, waiting = false,
}

local function say(text) view.status = tostring(text) end

-- Texts that come from outside are shown cut to a length (and only as text: the document shows them as plain text, never as markup).
local fit = gear.fmt.fit

-- ---- saved builds (a file of this mod) ----
local function load_saved()
    local data = gear.store.load('saved_builds.json', {})
    if type(data.builds) == 'table' then
        for i = 1, math.min(#data.builds, MAX_SAVED) do
            local b = data.builds[i]
            if type(b) == 'table' and type(b.name) == 'string' then view.saved[#view.saved + 1] = b end
        end
    end
end

local function store_saved()
    local ok, err = gear.store.save('saved_builds.json', {builds = view.saved})
    if not ok then say('could not save: ' .. tostring(err)) end
end

local function saved_index(build)
    for i, b in ipairs(view.saved) do
        if b.id == build.id and b.name == build.name then return i end
    end
end

-- ---- requests ----
local function ready()
    if net.supported() then return true end
    say('This server has no custom net support (it needs Sacred.GameServer with build_sharer.lua).')
    return false
end

local function request(op, fields)
    if not ready() then return false end
    if gear.time() - view.last_request < 0.4 then return false end        -- the server limits bursts too
    view.last_request = gear.time()
    local payload = fields or {}
    payload.op = op
    local ok, err = ch:send(payload, 'server')
    if not ok then say(err or 'not sent') end
    return ok
end

local function fetch_list()
    local payload = {sort = SORT_KEY[view.sort], page = view.page, per = PAGE}
    if CLASS_FILTER[view.class] then payload.class = CLASS_FILTER[view.class] end
    view.waiting = request('list', payload)
end

-- What to show for an item whose tooltip gave no name: the localized type name, the internal one on an older Gear.
local function type_label(it)
    local ok, n = pcall(function() return gear.data.object_types:label(it.type) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return it.type_name or ('item ' .. tostring(it.type))
end

local function carried_names()
    if not gear.settings.get('share_carried') then return {} end
    local c = gear.inv.container('backpack')
    if not c then return {} end
    local items = c:items()
    table.sort(items, function(a, b) return (a.quality_rank or 0) > (b.quality_rank or 0) end)
    local names = {}
    for i = 1, math.min(#items, 12) do names[#names + 1] = fit(type_label(items[i]), 48) end
    return names
end

local function my_tags()
    local tags = {}
    for tag in tostring(gear.settings.get('tags') or ''):gmatch('[^,]+') do
        tag = tag:match('^%s*(.-)%s*$')
        if #tag > 0 and #tags < 5 then tags[#tags + 1] = tag:sub(1, 16) end
    end
    return tags
end

local function publish()
    local hero = gear.world.hero()
    request('publish', {
        title = gear.settings.get('title'), note = gear.settings.get('note'), tags = my_tags(), carried = carried_names(),
        level = hero and hero:level() or nil,
    })
end

-- ---- what the server answers ----
ch:on(function(from, p)
    if from.slot ~= 0 or type(p) ~= 'table' then return end          -- only the server answers
    if p.op == 'list' then
        view.waiting = false
        if type(p.builds) ~= 'table' then return end
        view.list = {builds = p.builds, total = tonumber(p.total) or 0, pages = tonumber(p.pages) or 1}
        view.page = tonumber(p.page) or 1
        view.status = ''
    elseif p.op == 'build' and type(p.build) == 'table' then
        view.detail = p.build; view.tab = 4
    elseif p.op == 'mine' then
        view.mine = type(p.build) == 'table' and p.build or false
        view.hero_data = p.hero_data == true
    elseif p.op == 'published' then
        view.mine = type(p.build) == 'table' and p.build or view.mine
        say(view.mine and view.mine.verified and 'Published: the server read your hero.'
            or 'Published (the server has no hero data: class, level and your notes only).')
        view.list = nil
    elseif p.op == 'unpublished' then
        view.mine = false; view.list = nil
        say(p.removed and 'Your build is removed.' or 'You had no shared build.')
    elseif p.op == 'error' then
        view.waiting = false
        say(fit(p.error, 80))
    end
end)

-- ---- the window: ui/main.rml (the game theme) ----
-- One model of ready-made strings, rebuilt every frame; only what changed is written. Buttons are handled by delegated click listeners.
local function row_text(b)
    return ('%s  %s  L%s%s%s'):format(fit(b.name, 18), fit(b.class_name, 12), tostring(b.level or '?'), b.verified and '  [verified]' or '',
        (b.title and b.title ~= '') and ('  - ' .. fit(b.title, 30)) or '')
end

local function lines_of(items, fmt)
    local out = {}
    for _, item in ipairs(items or {}) do out[#out + 1] = fit(fmt(item), 70) end
    return out
end

local function detail_model(b)
    local d = {head = '', verified = false, verified_text = '', text = '', save_text = '', sections = {}, tags = ''}
    d.head = ('%s - %s, level %s'):format(fit(b.name, 24), fit(b.class_name, 14), tostring(b.level))
    d.verified = b.verified and true or false
    d.verified_text = b.verified and 'server-verified' or 'reported by the player'
    local text = {}
    if b.title and b.title ~= '' then text[#text + 1] = fit(b.title, 60) end
    if b.note and b.note ~= '' then text[#text + 1] = fit(b.note, 240) end
    d.text = table.concat(text, '\n')
    d.save_text = saved_index(b) and 'Remove from Saved' or 'Save to Saved'
    local function section(title, items, fmt)
        if type(items) ~= 'table' or #items == 0 then return end
        d.sections[#d.sections + 1] = {title = title, lines = lines_of(items, fmt)}
    end
    section('Skills', b.skills, function(s) return ('%s  %s%s'):format(fit(s.name, 30), tostring(s.level), (s.bonus or 0) > 0 and (' (+' .. tostring(s.bonus) .. ')') or '') end)
    section('Combat arts', b.arts, function(a) return fit(a.name, 40) end)
    section('Equipment', b.equipment, function(e)
        return ('%s  [%s, item level %s%s]'):format(fit(e.name, 36), fit(e.tier, 8), tostring(e.level), (e.sockets or 0) > 0 and (', ' .. tostring(e.sockets) .. ' socketed') or '')
    end)
    section('Carried (reported)', b.carried, function(c) return fit(c, 48) end)
    if type(b.tags) == 'table' and #b.tags > 0 then
        local tags = {}
        for _, t in ipairs(b.tags) do tags[#tags + 1] = fit(t, 16) end
        d.tags = table.concat(tags, ', ')
    end
    return d
end

local shown = false
local doc
local last = {}

local function snapshot()
    local hero = gear.world.hero()
    local m = {
        open = shown, title = 'Build sharer' .. key_hint('toggle'), tab = view.tab, status = fit(view.status, 90), tabs = {},
        class_name = class_choices()[view.class], sort_name = SORTS[view.sort], can_prev = view.page > 1,
        can_next = view.list ~= nil and view.page < view.list.pages, browse_msg = '', builds = {}, builds_count = '',
        me = '', my_title = fit(gear.settings.get('title'), 40), my_note = fit(gear.settings.get('note'), 70), my_tags = table.concat(my_tags(), ', '),
        carried = '', has_mine = view.mine ~= nil and view.mine ~= false, mine_verified = false, mine_line = '', mine_line2 = '',
        no_hero_data = view.hero_data == false, saved = {}, saved_msg = '', has_detail = view.detail ~= nil,
        d = {head = '', verified = false, verified_text = '', text = '', save_text = '', sections = {}, tags = ''},
    }
    for i, name in ipairs(TABS) do m.tabs[i] = {id = 'tab' .. i, name = name, on = view.tab == i} end
    if view.tab == 1 then
        if not view.list then
            m.browse_msg = view.waiting and 'Asking the server ...' or 'Press Refresh to list the shared builds.'
        elseif #view.list.builds == 0 then
            m.browse_msg = 'No build matches. Publish yours on the "My build" tab.'
        else
            for i, b in ipairs(view.list.builds) do
                if type(b) == 'table' and type(b.id) == 'string' then m.builds[#m.builds + 1] = {id = 'b' .. i, text = row_text(b)} end
            end
            m.builds_count = ('%d build%s, page %d of %d'):format(view.list.total, view.list.total == 1 and '' or 's', view.page, view.list.pages)
        end
    elseif view.tab == 2 then
        local cls = hero and hero:class() or '?'
        m.me = ('%s, %s, level %s'):format(hero and hero:name() or '(no hero)', cls, hero and tostring(hero:level()) or '?')
        local carried = carried_names()
        m.carried = ('Carried items sent: %d%s'):format(#carried, gear.settings.get('share_carried') and '' or ' (off)')
        if view.mine == false then
            m.mine_line = 'The server has no build of yours.'
        elseif view.mine then
            local b = view.mine
            m.mine_verified = b.verified and true or false
            m.mine_line = ('On the server: %s, level %s, %s'):format(fit(b.class_name, 14), tostring(b.level), b.verified and 'server-verified' or 'reported only')
            m.mine_line2 = ('%d skills, %d equipped items, %d combat arts'):format(#(b.skills or {}), #(b.equipment or {}), #(b.arts or {}))
        end
    elseif view.tab == 3 then
        if #view.saved == 0 then m.saved_msg = 'Nothing saved yet. Open a build and use "Save to Saved".' end
        for i, b in ipairs(view.saved) do m.saved[i] = {id = 's' .. i, text = row_text(b)} end
    elseif view.detail then
        m.d = detail_model(view.detail)
    end
    return m
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function pick_index(id, prefix)
    return tonumber(tostring(id):match('^' .. prefix .. '(%d+)$'))
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = gear.ui.rml.load('ui/main.rml', {model = m})
    if not doc then gear.log('build sharer: ui/main.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('.tab', function(e) local i = pick_index(e.current, 'tab'); if i then view.tab = i end end)
    on('#class', function() view.class = view.class % #CLASSES + 1; view.page = 1; fetch_list() end)
    on('#sort', function() view.sort = view.sort % #SORTS + 1; view.page = 1; fetch_list() end)
    on('#refresh', function() fetch_list() end)
    on('#prev', function() if view.page > 1 then view.page = view.page - 1; fetch_list() end end)
    on('#next', function() if view.list and view.page < view.list.pages then view.page = view.page + 1; fetch_list() end end)
    on('.brow', function(e)
        local i = pick_index(e.current, 'b')
        local s = pick_index(e.current, 's')
        if i and view.list and type(view.list.builds[i]) == 'table' then request('get', {id = view.list.builds[i].id})
        elseif s and view.saved[s] then view.detail = view.saved[s]; view.tab = 4 end
    end)
    on('#publish', publish)
    on('#unpublish', function() if view.mine then request('unpublish') end end)
    on('#mine', function() request('mine') end)
    on('#save', function()
        local b = view.detail
        if not b then return end
        local at = saved_index(b)
        if at then table.remove(view.saved, at) else
            if #view.saved >= MAX_SAVED then table.remove(view.saved, 1) end
            view.saved[#view.saved + 1] = b
        end
        store_saved()
    end)
end

gear.keys.on('toggle', function()
    shown = not shown
    if shown then
        view.opened = true
        if net.supported() then fetch_list(); gear.after(0.5, function() request('mine') end) else ready() end
    else
        view.opened = false
    end
end)

gear.on('draw', function(state)
    if not state or state.mode ~= 'game' or state.exclusive or not shown then return end
    if not doc then load_doc() end
    if not doc then return end
    for k, v in pairs(snapshot()) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
end)

gear.on('net_caps', function(caps)
    if caps.supported and shown and not view.list then fetch_list() end
end)

load_saved()
