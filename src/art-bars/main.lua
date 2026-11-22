-- Art bars: extra bars of slots for a hero's combat arts and spells.
--
-- A slot holds an ability id (a combat art, a spell, a combo of the combo master, or a copy / chain of the custom-classes mod). It is used
-- with the game's own ability order (creature:order_ability), the way the skill slot does, so the regeneration the game keeps shows on
-- the slot. Aimed with the mouse: a key press uses the ability on the creature under the cursor (hostile), else the one nearest to the
-- hero; on the spot under the cursor for arts aimed at a place or a direction; on the hero for self and area arts. A click on a slot (or the
-- controller) has no cursor in the world: it uses the nearest enemy and the hero's own spot.
-- What the slots hold is kept per hero in the savegame (gear.store.game).

local ui = gear.ui
local guard = gear.guard
local cfg = gear.config

local function setting(id, fallback)
    local v = gear.settings.get(id)
    if v == nil then return fallback end
    return v
end

local function log(fmt, ...)
    if setting('debug', false) then print(('[art-bars] ' .. fmt):format(...)) end
end

local function toast(text) if gear.toast then gear.toast.show('Art bars', text) else print(text) end end

local store = (gear.store.game or gear.store.file)('art_bars.json', {heroes = {}}, {every = 5})

local state = {edit = false, picking = nil, page = 1}

local function hero()
    if gear.party.available() then return gear.party.leader() end
    return nil
end

local function key_of(h) return 'id:' .. tostring(h.id) end

local function slots_of(h, create)
    local k = key_of(h)
    local r = store.data.heroes[k]
    if not r and create then
        r = {bars = {}}
        store.data.heroes[k] = r
    end
    return r
end

local function get_slot(h, bar, slot)
    local r = slots_of(h)
    return r and r.bars[tostring(bar)] and r.bars[tostring(bar)][tostring(slot)] or nil
end

local function set_slot(h, bar, slot, id)
    local r = slots_of(h, true)
    local b = r.bars[tostring(bar)]
    if not b then b = {}; r.bars[tostring(bar)] = b end
    b[tostring(slot)] = id
    store:changed()
end

---------------------------------------------------------------------------------------------------------------
-- Using an ability.
---------------------------------------------------------------------------------------------------------------
local function nearest_foe(h, radius)
    local x, y, layer = h:position()
    local best, bd
    for _, c in ipairs(gear.world.creatures_near(x, y, radius or 800, {layer = layer})) do
        if not c:is_dead() and h:is_enemy(c) and not c:is_hero() then
            local d = h:distance(c)
            if not bd or d < bd then best, bd = c, d end
        end
    end
    return best
end

-- The combo master's combos have the ids 0x200 .. 0x203, the combat arts start at 1000.
local function is_combo(id) return id >= 0x200 and id < 0x204 end

local function ability_name(id)
    if is_combo(id) then return 'Combo ' .. (id - 0x200 + 1) end
    local a = gear.data.abilities[id]
    return (a and gear.text.get(a.name_text)) or ('#' .. id)
end

-- target_mode: 0 direction, 1 creature, 2 self, 3 spot, 4 corpse, 5 around self (the game's own use of it, see GearApi).
local function use(h, id, from_ui)
    local rec = (not is_combo(id)) and gear.data.abilities[id] or nil
    local mode = rec and rec.target_mode or 1
    local cur = (not from_ui) and gear.world.cursor(h) or nil
    local ok, why
    if mode == 2 or mode == 5 then
        ok, why = h:order_ability(id, h)
    elseif mode == 1 or is_combo(id) then
        local t = cur and cur.object and cur.object.is_enemy and h:is_enemy(cur.object) and not cur.object:is_dead() and cur.object or nil
        t = t or nearest_foe(h, 900)
        if not t then toast('No target for ' .. ability_name(id)) return false end
        ok, why = h:order_ability(id, t)
    else
        -- a direction, a spot or a corpse: the cursor's spot, else the nearest enemy's, else in front of the hero
        local x, y
        if cur then x, y = cur.x, cur.y
        else
            local t = nearest_foe(h, 900)
            if t then x, y = t:position() else x, y = h:position() end
        end
        log('spot %s,%s hero at %s,%s cursor %s', tostring(x), tostring(y), tostring((h:position())), tostring(select(2, h:position())), cur and (cur.x .. ',' .. cur.y) or 'none')
        ok, why = h:order_ability(id, x, y)
    end
    log('%s (%d, mode %s): %s %s', ability_name(id), id, tostring(mode), tostring(ok), tostring(why))
    return ok
end

local function press(bar, slot)
    local h = hero()
    if not h then return end
    local id = get_slot(h, bar, slot)
    if not id then
        if setting('show_empty', true) then state.picking = {bar = bar, slot = slot}; state.picker = true end
        return
    end
    use(h, id, false)
end

---------------------------------------------------------------------------------------------------------------
-- Drawing.
---------------------------------------------------------------------------------------------------------------
local function bar_count() return setting('paging', false) and 1 or setting('bars', 2) end

-- ui/bars.rml (the game theme): up to three bars and the picker window; one model rebuilt every frame, only what changed is written.
local doc
local last = {}

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

-- The game's own sprite for the state: 'disabled' (not learned: the grey disc), 'cooldown' (regenerating), 'available'.
local function icon_of(id, state)
    if is_combo(id) then return '', 0xFFFFFFFF end
    local image, tint = gear.classes.art_icon(id, state)
    if image then return 'gear:image/' .. image, tint or 0xFFFFFFFF end
    return '', 0xFFFFFFFF
end

local function css_color(argb)
    argb = argb or 0xFFFFFFFF
    return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
end

local function slot_model(h, bar, slot, i)
    local id = get_slot(h, bar, slot)
    local key_id = ('bar%d_%d'):format(bar, slot)
    local known = id and (is_combo(id) or h:ability(id) ~= nil)
    local tip
    if id then
        local a = (not is_combo(id)) and h:ability(id) or nil
        tip = ability_name(id) .. (a and ('  (level %d)'):format((a.level or 0) + (a.bonus or 0)) or '')
        if state.edit then tip = tip .. '\nClick: change the slot' else tip = tip .. '\nClick or key: use' end
    else
        tip = state.edit and 'Click: choose an ability' or 'Empty slot'
    end
    local label = gear.keys.label(key_id)
    if label ~= '' then tip = tip .. '\nKey: ' .. label end
    local m = {id = ('b%ds%d'):format(i, slot), tip = tip, known = known and true or false, icon = '', tint = '#ffffffff', label = '', cd = 0, cdn = '', key = ''}
    if id then
        local a = (not is_combo(id)) and h:ability(id) or (function()
            for _, k in ipairs(h:combos() or {}) do if k.id == id then return {regen = math.max(0, k.total - k.charge), regen_max = k.total} end end
        end)()
        local cooling = a and a.regen and a.regen > 0.05
        if is_combo(id) then
            m.label = 'C' .. (id - 0x200 + 1)
        else
            local src, tint = icon_of(id, not known and 'disabled' or cooling and 'cooldown' or 'available')
            if src ~= '' then m.icon, m.tint = src, css_color(tint) else m.label = '?' end
        end
        if cooling then
            m.cd = math.floor(math.min(1, a.regen / math.max(0.1, a.regen_max or a.regen)) * 100)
            m.cdn = ('%.0f'):format(a.regen)
        end
    elseif state.edit or setting('show_empty', true) then
        m.label = '+'
    end
    if setting('keys_shown', true) and label ~= '' then
        m.key = label:gsub('ctrl%+shift%+', 'cs+'):gsub('ctrl%+', 'c+'):gsub('Ctrl%+Shift%+', 'CS+'):gsub('Ctrl%+', 'C+')
    end
    return m
end

local function snapshot()
    local h = hero()
    local size = setting('size', 44)
    local slots = setting('slots', 8)
    local n = h and bar_count() or 0
    local m = {px = size .. 'dp', ipx = (size - 6) .. 'dp', edit = state.edit, edit_mark = state.edit and 'x' or 'e',
        edit_tip = 'Fill the slots: click a slot, choose an ability', paging = setting('paging', false),
        page = ('%d/%d'):format(state.page, 3), picker_open = state.picker and true or false, picking = false,
        picker_title = 'Art bars', count = '', abilities = {}}
    local w = slots * (size + 4) + 4
    local height = size + 8
    for i = 1, 3 do
        local b = {show = i <= n, left = cfg.bar_x .. 'dp', top = (cfg.bar_y - (i - 1) * (height + 6)) .. 'dp', width = w .. 'dp', slots = {}}
        if b.show then
            local bar = setting('paging', false) and state.page or i
            for s = 1, slots do b.slots[s] = slot_model(h, bar, s, i) end
        end
        m['b' .. i] = b
    end
    local pick = state.picking
    if state.picker and h and pick then
        m.picking = true
        m.picker_title = ('Art bar %d, slot %d'):format(pick.bar, pick.slot)
        local list = {}
        for _, a in ipairs(h:abilities() or {}) do list[#list + 1] = a.id end
        for _, k in ipairs(h:combos() or {}) do list[#list + 1] = k.id end
        m.count = ('%d abilities'):format(#list)
        for i, id in ipairs(list) do
            local a = (not is_combo(id)) and h:ability(id) or nil
            local rec = (not is_combo(id)) and gear.data.abilities[id] or nil
            local src, tint = '', nil
            if not is_combo(id) then src, tint = icon_of(id) end
            local kind = is_combo(id) and 'combo' or ((id >= 1000 and 'combat art' or 'spell') .. (a and (', level %d'):format((a.level or 0) + (a.bonus or 0)) or ''))
            m.abilities[i] = {id = 'a' .. id, name = ability_name(id), kind = kind, icon = src, tint = css_color(tint), glyph = is_combo(id) and ('C' .. (id - 0x200 + 1)) or '?',
                tip = rec and gear.text.get(rec.description_text or 0) or "The combo master's combo"}
        end
    end
    return m
end

local function open_picker(bar, slot)
    state.picking = {bar = bar, slot = slot}
    state.picker = true
end

local function slot_of(id)
    local i, s = tostring(id):match('^b(%d+)s(%d+)$')
    if not i then return nil end
    i, s = tonumber(i), tonumber(s)
    return setting('paging', false) and state.page or i, s
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/bars.rml', {dp = true, model = m})
    if not doc then gear.log('art-bars: ui/bars.rml failed: ' .. tostring(err)) return end
    doc:on('.slot', 'click', guard('slot click', function(e)
        local bar, slot = slot_of(e.current)
        local h = hero()
        if not (bar and h) then return end
        local id = get_slot(h, bar, slot)
        if state.edit or not id then open_picker(bar, slot) else use(h, id, true) end
    end))
    doc:on('#edit', 'click', guard('edit click', function() state.edit = not state.edit end))
    doc:on('#clear', 'click', guard('clear click', function()
        local h, pick = hero(), state.picking
        if h and pick then set_slot(h, pick.bar, pick.slot, nil) end
        state.picker = false
    end))
    doc:on('#close', 'click', guard('close click', function() state.picker = false end))
    doc:on('.pick', 'click', guard('pick click', function(e)
        local h, pick = hero(), state.picking
        local id = tonumber(tostring(e.current):match('^a(%d+)$'))
        if h and pick and id then set_slot(h, pick.bar, pick.slot, id) end
        state.picker = false
    end))
end

gear.on('draw', guard('draw', function(s)
    if type(s) ~= 'table' or s.mode ~= 'game' or s.exclusive then return end
    if not doc then load_doc() end
    if not doc then return end
    for k, v in pairs(snapshot()) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
end))

for bar = 1, 3 do
    for slot = 1, 12 do
        gear.keys.on(('bar%d_%d'):format(bar, slot), guard('key', function()
            if setting('paging', false) then
                if bar == 1 and slot <= setting('slots', 8) then press(state.page, slot) end
            elseif bar <= setting('bars', 2) and slot <= setting('slots', 8) then
                press(bar, slot)
            end
        end))
    end
end
gear.keys.on('page_next', guard('key', function() state.page = state.page % 3 + 1 end))
gear.keys.on('page_previous', guard('key', function() state.page = (state.page + 1) % 3 + 1 end))
gear.keys.on('edit', guard('key', function() state.edit = not state.edit end))

if ui.menu_item then
    pcall(ui.menu_item, 'edit', 'Art bars: edit the slots', function() state.edit = not state.edit end)
    pcall(ui.menu_item, 'next', 'Art bars: next bar', function() state.page = state.page % 3 + 1 end)
    for bar = 1, 3 do
        for slot = 1, 12 do
            pcall(ui.menu_item, ('cast%d_%d'):format(bar, slot), ('Art bar %d, slot %d'):format(bar, slot), function()
                local h = hero()
                local id = h and get_slot(h, setting('paging', false) and state.page or bar, slot)
                if id and h then use(h, id, true) end
            end)
        end
    end
end


-- For the self test: the slots by event.
gear.events.declare('art-bars.set', 'Put an ability into a slot: (bar, slot, ability id or nil)')
gear.events.declare('art-bars.use', 'Use a slot like its key: (bar, slot)')
gear.on('art-bars.set', guard('set', function(bar, slot, id)
    local h = hero()
    if h then set_slot(h, bar, slot, id) end
end))
gear.on('art-bars.use', guard('use', function(bar, slot) press(bar, slot) end))
gear.events.declare('art-bars.pick', 'Open the picker for a slot: (bar, slot)')
gear.on('art-bars.pick', guard('pick', function(bar, slot) state.picking = {bar = bar, slot = slot}; state.picker = true end))
gear.on('art-bars.edit', guard('edit', function(on) state.edit = on ~= false end))
