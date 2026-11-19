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
        if setting('show_empty', true) then state.picking = {bar = bar, slot = slot}; ui.show_panel('picker', true) end
        return
    end
    use(h, id, false)
end

---------------------------------------------------------------------------------------------------------------
-- Drawing.
---------------------------------------------------------------------------------------------------------------
local DIM, ACCENT = 0xFFB0A890, 0xFFE8C878

local function bar_count() return setting('paging', false) and 1 or setting('bars', 2) end

local function slot_icon(id, x, y, size, tint_override)
    if is_combo(id) then
        ui.rect(x, y, size, size, 0xFF2A2418)
        ui.text('C' .. (id - 0x200 + 1), x + size / 2 - 8, y + size / 2 - 8, {color = ACCENT, bold = true, size = 14})
        return
    end
    local image, tint = gear.classes.art_icon(id)
    if image then
        ui.image(image, x, y, size, size, {color = tint_override or tint})
    else
        ui.rect(x, y, size, size, 0xFF2A2418)
        ui.text('?', x + size / 2 - 4, y + size / 2 - 8, {color = DIM})
    end
end

local function draw_slot(h, bar, slot, x, y, size, key_id)
    local id = get_slot(h, bar, slot)
    local tip
    local known = id and (is_combo(id) or h:ability(id) ~= nil)
    if id then
        local a = (not is_combo(id)) and h:ability(id) or nil
        tip = ability_name(id) .. (a and ('  (level %d)'):format((a.level or 0) + (a.bonus or 0)) or '')
        if state.edit then tip = tip .. '\nClick: change the slot' else tip = tip .. '\nClick or key: use' end
    else
        tip = state.edit and 'Click: choose an ability' or 'Empty slot'
    end
    local label = gear.keys.label(key_id)
    if label ~= '' then tip = tip .. '\nKey: ' .. label end
    local clicked = ui.button('slot' .. bar .. '_' .. slot, x, y, size, size, '', {tooltip = tip})
    if id then
        local dim = not known
        slot_icon(id, x + 3, y + 3, size - 6, dim and 0xFF606060 or nil)
        local a = (not is_combo(id)) and h:ability(id) or (function()
            for _, k in ipairs(h:combos() or {}) do if k.id == id then return {regen = math.max(0, k.total - k.charge), regen_max = k.total} end end
        end)()
        if a and a.regen and a.regen > 0.05 then
            local frac = math.min(1, a.regen / math.max(0.1, a.regen_max or a.regen))
            ui.rect(x + 3, y + 3, size - 6, (size - 6) * frac, 0xA0000000)
            ui.text(('%.0f'):format(a.regen), x + 6, y + size / 2 - 7, {color = 0xFFFFFFFF, bold = true, size = 13, shadow = true})
        end
    elseif state.edit or setting('show_empty', true) then
        ui.text('+', x + size / 2 - 4, y + size / 2 - 9, {color = DIM, size = 16})
    end
    if setting('keys_shown', true) and label ~= '' then
        ui.text(label:gsub('ctrl%+shift%+', 'cs+'):gsub('ctrl%+', 'c+'):gsub('Ctrl%+Shift%+', 'CS+'):gsub('Ctrl%+', 'C+'), x + 4, y + size - 14,
            {color = 0xFFFFFFFF, size = 10, shadow = true})
    end
    if clicked then
        if state.edit or not id then
            state.picking = {bar = bar, slot = slot}
            ui.show_panel('picker', true)
        else
            use(h, id, true)
        end
    end
end

local function draw_bars()
    local h = hero()
    if not h then return end
    local size = setting('size', 44)
    local slots = setting('slots', 8)
    local n = bar_count()
    for i = 1, n do
        local bar = setting('paging', false) and state.page or i
        local w = slots * (size + 4) + 4
        local height = size + 8
        local p = ui.panel('bar' .. i, ('Art bar %d'):format(bar), cfg.bar_x, cfg.bar_y - (i - 1) * (height + 6), w, height,
            {bare = true, min_width = w, min_height = height, passive = true})
        if p.open then
            local x0, y0 = p.content_x or 0, p.content_y or 0
            ui.rect(x0, y0, w, height, 0x80000000)
            for s = 1, slots do
                draw_slot(h, bar, s, x0 + 4 + (s - 1) * (size + 4), y0 + 4, size, ('bar%d_%d'):format(bar, s))
            end
            if i == 1 then
                if ui.button('edit', x0 + w + 4, y0 + 4, 22, 22, state.edit and 'x' or 'e', {tooltip = 'Fill the slots: click a slot, choose an ability'}) then
                    state.edit = not state.edit
                end
                if setting('paging', false) then
                    ui.text(('%d/%d'):format(state.page, 3), x0 + w + 4, y0 + 30, {color = DIM, size = 11})
                end
            end
        end
    end
end

-- The picker: the hero's abilities as cards (icon, name, level); click one to put it into the slot being edited.
local function draw_picker()
    if not ui.panel_open('picker') then return end
    local h = hero()
    local pick = state.picking
    local p = ui.panel('picker', pick and ('Art bar %d, slot %d'):format(pick.bar, pick.slot) or 'Art bars', 200, 100, 520, 420, {resizable = true, min_width = 360, min_height = 200})
    if not p.open then return end
    local x, y, w, hh = p.content_x or 0, p.content_y or 0, p.content_w or 500, p.content_h or 380
    if not h or not pick then
        ui.text('Choose a slot first: press the edit button next to the first bar, then click a slot.', x, y, {color = DIM, size = 12})
        return
    end
    local list = {}
    for _, a in ipairs(h:abilities() or {}) do list[#list + 1] = a.id end
    for _, k in ipairs(h:combos() or {}) do list[#list + 1] = k.id end
    if ui.button('clear', x, y, 130, 22, 'Empty this slot', {}) then
        set_slot(h, pick.bar, pick.slot, nil)
        ui.show_panel('picker', false)
        return
    end
    ui.text(('%d abilities'):format(#list), x + 140, y + 4, {color = DIM, size = 12})
    local area = ui.scroll_begin('picker_list', x, y + 28, w, hh - 28, {})
    local cw = math.floor((area.w - 8) / 2)
    for i, id in ipairs(list) do
        local cx = area.content_x + ((i - 1) % 2) * (cw + 8)
        local cy = area.content_y + math.floor((i - 1) / 2) * 52
        local r = ui.region('pick' .. id, cx, cy, cw, 48, {tooltip = ((not is_combo(id)) and gear.text.get((gear.data.abilities[id] or {}).description_text or 0) or 'The combo master\'s combo')})
        ui.rect(cx, cy, cw, 48, r.hover and 0xC02A2210 or 0xC0141008)
        ui.frame(cx, cy, cw, 48, r.hover and 0xFF8A7A4C or 0xFF4A3E24, 1)
        slot_icon(id, cx + 4, cy + 4, 40)
        local a = (not is_combo(id)) and h:ability(id) or nil
        ui.text(ability_name(id), cx + 50, cy + 6, {color = 0xFFFFFFFF, bold = true, size = 12})
        ui.text(is_combo(id) and 'combo' or ((id >= 1000 and 'combat art' or 'spell') .. (a and (', level %d'):format((a.level or 0) + (a.bonus or 0)) or '')), cx + 50, cy + 26, {color = DIM, size = 11})
        if r.clicked then
            set_slot(h, pick.bar, pick.slot, id)
            ui.show_panel('picker', false)
        end
    end
    ui.scroll_end(math.ceil(#list / 2) * 52)
end

gear.on('draw', guard('draw', function(s)
    if type(s) ~= 'table' or s.mode ~= 'game' or s.exclusive then return end
    draw_bars()
    draw_picker()
end))

ui.show_panel('picker', false)

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
gear.on('art-bars.pick', guard('pick', function(bar, slot) state.picking = {bar = bar, slot = slot}; ui.show_panel('picker', true) end))
gear.on('art-bars.edit', guard('edit', function(on) state.edit = on ~= false end))
