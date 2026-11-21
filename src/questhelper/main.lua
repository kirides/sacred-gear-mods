-- Quest helper: a panel (Ctrl+U).
--   Quest items: read here. The quest items in your backpack and the quest items lying near your hero (distance in tiles, position).
--   Records: from the game server (SacredEngineRemake Sacred.GameServer, scripts-examples/quest_helper.lua, channel 'questhelper'): the quest
--   records of your hero with the names, areas and hints the server's owner wrote for them, which other heroes have the same record,
--   and a line on the screen when one is new or changed.
--
-- What this cannot do, and why: Gear has no access to the game's quest journal (active quests, their texts, map markers), and the server
-- cannot read it either: a hero file holds only "quest pairs" ([key][value] records) and the journal is state of the game's script
-- interpreter that no message carries. So there is no list of active or available quests here, and the keys of the pairs have names only
-- where the server owner has filled in a catalog. The panel says so instead of showing guesses.

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local ui, net = gear.ui, gear.net
local ch = net.channel('questhelper')
local TABS = {'Quest items', 'Records', 'About'}
local NEAR_TILES = 40

local view = {             -- what the panel shows and waits for
    tab = 1, state = nil, reason = nil, asked = 0, opened = false, show_unknown = true,
    near = {}, near_at = 0, status = '',
}

local fit = gear.fmt.fit
gear.toast.options({seconds = 8, when = function(state) return state.mode == 'game' and not state.escape_menu end})

-- ---- the server ----
local function ask(watch)
    if not net.supported() then return false end
    local ok, err = ch:send({op = 'state', watch = watch and true or false}, 'server')
    if not ok then view.status = fit(err, 80) else view.asked = gear.time() end
    return ok
end

local function title_of(r)
    return (type(r.name) == 'string' and r.name ~= '') and r.name or ('record ' .. tostring(r.key))
end

-- A new or changed record against the last state: a line on the screen.
local function announce(old, new)
    if not old or not old.records or not gear.settings.get('notices') then return end
    local before = {}
    for _, r in ipairs(old.records) do if type(r) == 'table' then before[tostring(r.key)] = r.value end end
    for _, r in ipairs(new.records) do
        if type(r) == 'table' and before[tostring(r.key)] ~= r.value then
            gear.toast.show(('Quest record: %s%s'):format(fit(title_of(r), 50), before[tostring(r.key)] == nil and ' (new)' or ' (changed)'))
            return
        end
    end
end

ch:on(function(from, p)
    if from.slot ~= 0 or type(p) ~= 'table' then return end          -- only the server answers
    if p.op == 'state' then
        if p.available == true and type(p.records) == 'table' then
            local new = {total = tonumber(p.total) or #p.records, known = tonumber(p.known) or 0, records = p.records, catalog = tonumber(p.catalog) or 0}
            announce(view.state, new)
            view.state, view.reason = new, nil
        else
            view.state, view.reason = nil, fit(p.reason or 'the server has no quest data for you', 160)
        end
        view.status = ''
    elseif p.op == 'error' then
        view.status = fit(p.error, 80)
    end
end)

-- ---- quest items (read here) ----
-- What to show for an item whose tooltip gave no name: the localized type name, the internal one on an older Gear.
local function type_label(it)
    local ok, n = pcall(function() return gear.data.object_types:label(it.type) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return it.type_name or ('item ' .. tostring(it.type))
end

local function refresh_near()
    view.near_at = gear.time()
    local hero = gear.world.hero()
    view.near = {}
    if not hero then return end
    local hx, hy, layer = hero:position()
    if not hx then return end
    for _, it in ipairs(gear.world.items_near(hx, hy, NEAR_TILES * gear.world.TILE, {layer = layer, limit = 64})) do
        if it.quest then
            local dist = math.sqrt((it.x - hx) ^ 2 + (it.y - hy) ^ 2) / gear.world.TILE
            view.near[#view.near + 1] = {name = type_label(it), dist = dist, x = it.x, y = it.y}
        end
    end
    table.sort(view.near, function(a, b) return a.dist < b.dist end)
end

local function backpack_quest_items()
    local list = {}
    local c = gear.inv.container('backpack')
    if not c then return list end
    for _, it in ipairs(c:items()) do
        if it.quest then list[#list + 1] = it end
    end
    return list
end

local function items_model(m)
    if gear.time() - view.near_at > 1 then refresh_near() end
    local bag = backpack_quest_items()
    m.bag_empty = #bag == 0
    for i, it in ipairs(bag) do m.bag[i] = {name = type_label(it), size = ('%d x %d cells'):format(it.w or 1, it.h or 1)} end
    m.near_title = ('On the ground within %d tiles'):format(NEAR_TILES)
    m.near_empty = #view.near == 0
    for i, n in ipairs(view.near) do
        m.near[i] = {name = n.name, dist = ('%.0f tiles away'):format(n.dist), pos = ('%d, %d'):format(n.x, n.y)}
    end
end

local function records_model(m)
    if not net.supported() then
        m.rec_msg = 'Records need a game server with the quest helper script (Sacred.GameServer of the SacredEngineRemake, scripts-examples/quest_helper.lua). '
            .. 'Single player and the original GameServer.exe have none.'
        m.rec_warn = true
        return
    end
    if not view.state then
        m.rec_msg = view.reason or 'Asking the server ...'
        m.rec_warn = view.reason ~= nil
        m.can_ask = true
        return
    end
    local st = view.state
    m.has_state = true
    m.rec_head = ('%d record%s, %d with a catalog entry (the catalog has %d)'):format(st.total, st.total == 1 and '' or 's', st.known, st.catalog)
    for _, r in ipairs(st.records) do
        if type(r) == 'table' and (r.known or view.show_unknown) then
            local label = (type(r.label) == 'string' and r.label ~= '') and (' - ' .. fit(r.label, 40)) or ''
            local others = ''
            if type(r.others) == 'table' and #r.others > 0 then
                local names = {}
                for _, n in ipairs(r.others) do names[#names + 1] = fit(n, 20) end
                others = 'Also: ' .. table.concat(names, ', ')
            end
            m.records[#m.records + 1] = {
                line = ('%s = %s%s'):format(fit(title_of(r), 50), tostring(r.value), label), known = r.known and true or false,
                area = (type(r.area) == 'string' and r.area ~= '') and ('Where: ' .. fit(r.area, 80)) or '',
                hint = (type(r.hint) == 'string' and r.hint ~= '') and fit(r.hint, 400) or '', others = others,
            }
        end
    end
    m.rec_none = #m.records == 0
end

local ABOUT = 'What this panel can show: quest items (backpack and near you, read by this mod) and the quest records of your hero (reported by the server). '
    .. 'What it cannot: the game\'s quest journal, active or available quests and their progress. Gear has no access to them and the server cannot read them: '
    .. 'a hero file holds only [key][value] quest pairs, the journal is state of the game\'s script interpreter. Names, areas and hints for a record key '
    .. 'exist only where the server owner added them to the server\'s catalog; every other record is shown as "record <key>". '
    .. 'The records need a Sacred.GameServer with quest_helper.lua that keeps hero data (web UI or --authoritative).'

-- ---- the window: ui/main.rml (the game theme) ----
local shown = false
local doc
local last = {}

local function snapshot()
    local m = {
        open = shown, title = 'Quest helper' .. key_hint('toggle'), tab = view.tab, status = view.status, tabs = {},
        bag = {}, bag_empty = false, near_title = '', near = {}, near_empty = false,
        rec_msg = '', rec_warn = false, can_ask = false, has_state = false, rec_head = '', show_unknown = view.show_unknown, rec_none = false, records = {},
        about = ABOUT,
    }
    for i, name in ipairs(TABS) do m.tabs[i] = {id = 'tab' .. i, name = name, on = view.tab == i} end
    if view.tab == 1 then items_model(m) elseif view.tab == 2 then records_model(m) end
    return m
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = gear.ui.rml.load('ui/main.rml', {model = m})
    if not doc then gear.log('quest helper: ui/main.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('.tab', function(e) local i = tonumber(tostring(e.current):match('^tab(%d+)$')); if i then view.tab = i end end)
    on('#ask', function() ask(true) end)
    on('#refresh', function() ask(true) end)
    on('#unknown', function() view.show_unknown = not view.show_unknown end)
end

gear.keys.on('toggle', function()
    shown = not shown
    if shown then
        view.opened = true; refresh_near(); ask(true)
    else
        view.opened = false
        if net.supported() then ch:send({op = 'unwatch'}, 'server') end
    end
end)

-- Refresh while the panel is open (the server also pushes changes to a watching client).
gear.every(5, function()
    if shown and net.supported() and gear.time() - view.asked >= (tonumber(gear.settings.get('refresh')) or 30) then ask(true) end
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
    if caps.supported and shown then ask(true) end
end)
