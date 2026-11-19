-- A loot filter: the hero picks up only the items the rules allow (config.lua, or the in-game settings panel: F5 or
-- the overlay's button, kept in the mod manager's gear_mods.json); the labels of the others are dimmed on the ground,
-- and a small overlay shows the rules in force. Gold is always picked up.
--
-- How it works: every quarter second the mod looks at the items lying around the hero (gear.world.items_near),
-- decides for each and hands the ones to refuse to Gear (gear.world.pickup_rules), which turns the game's pickup
-- down for them, for clicks and for the automatic collecting alike. Single player (and the host of a network game);
-- a network client's pickups go through the host and are not filtered.
--
-- Self test (no player needed, selftest.lua): Sacred.exe -gear-auto -gear-load=1 -gear-mods=lootfilter

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local cfg = gear.config
local ui = gear.ui
local W = gear.world

local QUALITY_RANK = {}
for i, q in ipairs(W.QUALITIES) do QUALITY_RANK[q] = i end
-- The game's label colours, for the overlay.
local QUALITY_COLOR = {normal = 0xFFEFEFEF, magic = 0xFFA0A0FF, rare = 0xFFF0E040, set = 0xFF15FF25, unique = 0xFFC19A33}
local CATEGORIES = {'weapon', 'armor', 'shield', 'jewelry', 'rune', 'scroll', 'special', 'other'}
local POTIONS = {'health', 'mana', 'stamina', 'colored', 'other'}
local POTION_COLORS = {'black', 'blue', 'green', 'red', 'yellow'}     -- the 'colored' potions, each with a rule of its own

-- Checks the settings once; a bad value is logged and replaced by its default.
local function check_config()
    if cfg.classes ~= 'own' and cfg.classes ~= false and type(cfg.classes) ~= 'table' then
        print('config: classes must be "own", false or a list of classes; using "own"')
        cfg.classes = 'own'
    end
    if type(cfg.classes) == 'table' then
        local known = {}
        for _, c in ipairs(W.CLASSES) do known[c.name] = true end
        for _, c in ipairs(cfg.classes) do
            if not known[c] then print('config: unknown class ' .. tostring(c)) end
        end
    end
    if not QUALITY_RANK[cfg.min_quality] then
        print('config: min_quality must be one of normal, magic, rare, set, unique; using normal')
        cfg.min_quality = 'normal'
    end
    cfg.categories = type(cfg.categories) == 'table' and cfg.categories or {}
    for cat, rule in pairs(cfg.categories) do
        if rule ~= false and not QUALITY_RANK[rule] then
            print(('config: categories.%s must be a quality or false; ignored'):format(tostring(cat)))
            cfg.categories[cat] = nil
        end
    end
    cfg.potions = type(cfg.potions) == 'table' and cfg.potions or {}
end
check_config()

-- The classes whose items are kept (names), nil: any.
local function wanted_classes(hero)
    if cfg.classes == false then return nil end
    if cfg.classes == 'own' then
        local own = hero and hero:class()
        return own and {own} or nil
    end
    return cfg.classes
end

-- keep(item) -> true | false, reason
local function keep(item, classes)
    if item.gold then return true end
    if item.quest and cfg.keep_quest then return true end
    if item.category == 'potion' then
        local rule = item.potion_color and cfg.potions[item.potion_color]
        if rule == nil then rule = cfg.potions[item.potion or 'other'] end
        if rule == false then return false, 'potion' end
        return true
    end
    if classes then
        local usable = false
        for _, c in ipairs(classes) do
            if W.usable_by(item, c) then usable = true; break end
        end
        if not usable then return false, 'class' end
    end
    if item.set and cfg.keep_set then return true end
    local rule = cfg.categories[item.category]
    if rule == nil then rule = cfg.min_quality end
    if rule == false then return false, 'category' end
    if item.quality_rank < QUALITY_RANK[rule] then return false, 'quality' end
    return true
end

local stats = {near = 0, blocked = 0, reasons = {}}
local last_items = {}

local function refresh()
    local hero = W.hero()
    if not cfg.enabled or not hero then
        W.pickup_rules(nil)
        stats.near, stats.blocked = 0, 0
        return
    end
    local x, y, layer = hero:position()
    local items = W.items_near(x, y, cfg.radius * W.TILE, {layer = layer, limit = 512})
    local classes = wanted_classes(hero)
    local blocked, reasons = {}, {}
    for _, it in ipairs(items) do
        local ok, why = keep(it, classes)
        it.keep, it.why = ok, why
        if not ok then
            blocked[#blocked + 1] = it.id
            reasons[why] = (reasons[why] or 0) + 1
        end
    end
    W.pickup_rules({block = blocked, dim = blocked, dim_alpha = cfg.dim_alpha})
    stats.near, stats.blocked, stats.reasons = #items, #blocked, reasons
    last_items = items
end

gear.every(0.25, refresh)
gear.on('session.start', refresh)

-- The overlay: the rules in force, read only.
local function line(text, x, y, color)
    ui.text(text, x, y, {color = color or 0xFFE0E0E0, size = 11})
end

-- Only while the game shows its labels (Alt held), like the game's own text; the settings panel stays open on its own.
local overlay_shown = false
local show_text_until = 0       -- gear.time() until which the overlay stays after Alt was released
local function overlay(state)
    overlay_shown = false
    -- It stays a moment after Alt is released, so a click made just before still lands on its button.
    if state.show_text then show_text_until = gear.time() + 0.4 end
    local editing = ui.edit_mode()
    if not cfg.overlay or state.mode ~= 'game' or state.exclusive or (gear.time() >= show_text_until and not editing) then
        return
    end
    overlay_shown = true
    local rows = 7 + #CATEGORIES
    local h = 18 + rows * 13
    -- A bare panel (no window of its own), so the layout editor lists it and the player can move it; it also shows in
    -- the edit mode, Alt or not. cfg.overlay_x / overlay_y are only its default place. The settings button lies in it.
    local p = ui.panel('overlay', 'Loot filter overlay', cfg.overlay_x, cfg.overlay_y, 196, h + 26, {bare = true})
    local x, y = p.x, p.y
    ui.rect(x, y, 196, h, ui.rgba(0, 0, 0, 140))
    ui.frame(x, y, 196, h, ui.rgba(200, 170, 90, 200))
    ui.text('Loot filter', x + 6, y + 3, {color = cfg.enabled and 0xFFFFD780 or 0xFF909090, size = 15, bold = true})
    ui.text(cfg.enabled and 'on' or 'off', x + 6, y + 3, {width = 184, align = 'right',
        color = cfg.enabled and 0xFF80FF80 or 0xFFFF8080})
    local ty = y + 24
    local classes = wanted_classes(W.hero())
    line('Classes: ' .. (classes and table.concat(classes, ', ') or 'any'), x + 6, ty); ty = ty + 13
    line('Minimum:', x + 6, ty)
    line(cfg.min_quality, x + 90, ty, QUALITY_COLOR[cfg.min_quality]); ty = ty + 13
    for _, cat in ipairs(CATEGORIES) do
        local rule = cfg.categories[cat]
        line(cat, x + 14, ty, 0xFFB0B0B0)
        if rule == false then
            line('never', x + 90, ty, 0xFFFF8080)
        else
            local q = rule or cfg.min_quality
            line(q .. (rule and '' or ' *'), x + 90, ty, QUALITY_COLOR[q])
        end
        ty = ty + 13
    end
    local taken = {}        -- the potion kinds picked up, then the colours that are not
    for _, k in ipairs(POTIONS) do
        if cfg.potions[k] ~= false then taken[#taken + 1] = k end
    end
    for _, color in ipairs(POTION_COLORS) do
        if cfg.potions[color] == false then taken[#taken + 1] = 'no ' .. color end
    end
    line('Potions: ' .. (#taken > 0 and table.concat(taken, ', ') or 'none'), x + 6, ty); ty = ty + 13
    line(('Set items: %s, quest: %s'):format(cfg.keep_set and 'always' or 'by rule', cfg.keep_quest and 'always' or 'by rule'), x + 6, ty); ty = ty + 13
    line(('Nearby: %d items, %d filtered'):format(stats.near, stats.blocked), x + 6, ty); ty = ty + 13
    line(('Refused pickups: %d'):format(W.pickup_refused()), x + 6, ty, 0xFFB0B0B0)
    if not editing and ui.button('open-settings', x + 6, y + h + 4, 184, 20, 'Settings' .. key_hint('panel'), {tooltip = 'Change the rules in game'}) then
        ui.toggle_panel('settings')
    end
end

---------------------------------------------------------------------------------------------------------------
-- The settings panel: the same rules, changed in game.
---------------------------------------------------------------------------------------------------------------
-- The rules live in the mod manager's settings (declared in mod.lua, kept in mods\gear_mods.json); `cfg` is the
-- working copy the rest of the mod reads. pull() takes the player's settings into it, push() writes it back after the
-- panel changed it. (An old settings.json of this folder is migrated once, below.)
local S = gear.settings
local SAVED_KEYS = {'enabled', 'classes', 'min_quality', 'categories', 'potions', 'keep_quest', 'keep_set', 'dim_alpha'}
local pushing = false

local function chosen_classes()
    local list = {}
    for _, c in ipairs(W.CLASSES) do
        if S.get('class_' .. c.name) then list[#list + 1] = c.name end
    end
    return list
end

-- Lua's `c and false or x` always yields x, so false values are chosen with explicit ifs.
local function category_rule(v)
    if v == 'never' then return false end
    if v == '(minimum)' then return nil end
    return v
end

local function potion_rule(v)
    if v == 'leave' then return false end
    if v == 'take' then return true end
    return nil
end

local function classes_rule(v)
    if v == 'own' then return 'own' end
    if v == 'any' then return false end
    return chosen_classes()
end

-- One setting into cfg.
local function apply_setting(id, v)
    if id == 'classes_mode' then
        cfg.classes = classes_rule(v)
    elseif id:sub(1, 6) == 'class_' then
        if type(cfg.classes) == 'table' then cfg.classes = chosen_classes() end
    elseif id:sub(1, 4) == 'cat_' then
        cfg.categories[id:sub(5)] = category_rule(v)
    elseif id:sub(1, 13) == 'potion_color_' then
        cfg.potions[id:sub(14)] = potion_rule(v)
    elseif id:sub(1, 7) == 'potion_' then
        cfg.potions[id:sub(8)] = v
    else
        cfg[id] = v
    end
end

local function pull()
    for id in pairs(S.all()) do
        if S.is_set(id) then apply_setting(id, S.get(id)) end
    end
    check_config()
end

local function push()
    pushing = true
    S.set('enabled', cfg.enabled == true)
    S.set('keep_quest', cfg.keep_quest ~= false)
    S.set('keep_set', cfg.keep_set == true)
    S.set('dim_alpha', cfg.dim_alpha)
    S.set('min_quality', cfg.min_quality)
    S.set('classes_mode', cfg.classes == 'own' and 'own' or cfg.classes == false and 'any' or 'chosen')
    local picked = {}
    if type(cfg.classes) == 'table' then for _, n in ipairs(cfg.classes) do picked[n] = true end end
    for _, c in ipairs(W.CLASSES) do S.set('class_' .. c.name, picked[c.name] == true) end
    for _, cat in ipairs(CATEGORIES) do
        local rule = cfg.categories[cat]
        S.set('cat_' .. cat, rule == false and 'never' or rule or '(minimum)')
    end
    for _, k in ipairs(POTIONS) do S.set('potion_' .. k, cfg.potions[k] ~= false) end
    for _, color in ipairs(POTION_COLORS) do
        local rule = cfg.potions[color]
        S.set('potion_color_' .. color, rule == false and 'leave' or rule == true and 'take' or 'default')
    end
    pushing = false
end

-- The old settings.json of this folder, once.
S.migrate('settings.json', function(old)
    for _, k in ipairs(SAVED_KEYS) do
        if old[k] ~= nil then cfg[k] = old[k] end
    end
    check_config()
    push()
    print('settings.json migrated to the mod manager')
end)
pull()
gear.on('settings.changed', function(id, v)
    if pushing then return end
    apply_setting(id, v)
    check_config()
    refresh()
end)
ui.show_panel('settings', false)

local QUALITY_OPTIONS = {'normal', 'magic', 'rare', 'set', 'unique'}
local CATEGORY_OPTIONS = {'(minimum)', 'normal', 'magic', 'rare', 'set', 'unique', 'never'}
local function index_of(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return 1
end

-- Where the self test finds the controls it clicks (set by the panel while it is drawn).
local rects = {}

-- The settings form: stacked tables (a table per block), so the labels, checkboxes and dropdowns of a block share their
-- columns and rows; the radio group is the only widget placed by hand, in the cell the table reserves for it.
local function settings_panel()
    local p = ui.panel('settings', 'Loot filter settings', 240, 70, 540, 440)
    if not p.open then return end
    local x, y, w = p.content_x, p.content_y, p.content_w
    local accent = ui.COLORS.accent
    local changed = false   -- any rule changed this frame: saved and applied at the end
    local c, t

    c, cfg.enabled = ui.checkbox('enabled', x, y, 'Filter on', cfg.enabled, {tooltip = 'Off: the hero picks up everything'})
    changed = changed or c
    y = y + 28

    -- Classes
    local mode = cfg.classes == 'own' and 1 or cfg.classes == false and 2 or 3
    t = ui.table('classes', x, y, w, {columns = {'*', '*', '*', '*'}, spacing = {8, 2}, row_height = 20})
    t:row(); t:label(1, 'Pick up items for', {id = 'l-classes', color = accent, span = 4})
    t:row()
    local rx, ry = t:cell(1, 4)
    c, mode = ui.radio_group('classmode', rx, ry, {'my class', 'any class', 'these classes:'}, mode,
        {horizontal = true, tooltips = {"The hero's own class", 'Every item, whatever its class',
            'The classes ticked below (for your other heroes too)'}})
    if c then
        changed = true
        if mode == 1 then cfg.classes = 'own'
        elseif mode == 2 then cfg.classes = false
        else
            local own = W.hero() and W.hero():class()
            cfg.classes = {own or 'seraphim'}
        end
    end
    local picked = {}
    if type(cfg.classes) == 'table' then for _, n in ipairs(cfg.classes) do picked[n] = true end end
    for i, cls in ipairs(W.CLASSES) do
        if (i - 1) % 4 == 0 then t:row() end
        local cc, on = t:checkbox((i - 1) % 4 + 1, cls.name, picked[cls.name] == true,
            {id = 'class-' .. cls.name, enabled = mode == 3})
        if cc then
            changed = true
            picked[cls.name] = on
            local list = {}
            for _, k in ipairs(W.CLASSES) do if picked[k.name] then list[#list + 1] = k.name end end
            cfg.classes = list
        end
    end
    y = y + t:height() + 12

    -- Qualities
    ui.label('l-quality', 'Lowest quality', x, y, {height = 22, valign = 'middle', color = accent,
        tooltip = 'Items below it are left on the ground'})
    local qc, qi = ui.dropdown('min_quality', x + 140, y, 120, QUALITY_OPTIONS, index_of(QUALITY_OPTIONS, cfg.min_quality))
    rects.min_quality = {x + 140, y, 120, 22}
    cfg.min_quality = QUALITY_OPTIONS[qi]
    changed = changed or qc
    y = y + 30

    t = ui.table('categories', x, y, w, {columns = {72, 120, 40, 72, 120}, spacing = {8, 3}})
    for i, cat in ipairs(CATEGORIES) do
        local col = (i - 1) % 2 * 3 + 1
        if col == 1 then t:row() end
        t:label(col, cat)
        local rule = cfg.categories[cat]
        local cur = rule == false and 'never' or rule or '(minimum)'
        local ch, idx = t:dropdown(col + 1, CATEGORY_OPTIONS, index_of(CATEGORY_OPTIONS, cur), {id = 'cat-' .. cat})
        if ch then
            cfg.categories[cat] = category_rule(CATEGORY_OPTIONS[idx])
            changed = true
        end
    end
    y = y + t:height() + 12

    -- Potions and the rest
    t = ui.table('potions', x, y, w, {columns = {'*', '*', '*', '*', '*'}, spacing = {8, 2}, row_height = 20})
    t:row(); t:label(1, 'Potions', {id = 'l-potions', color = accent, span = 5})
    t:row()
    for i, k in ipairs(POTIONS) do
        local pc, on = t:checkbox(i, k, cfg.potions[k] ~= false,
            {id = 'potion-' .. k, tooltip = k == 'colored' and 'The black, blue, green, red and yellow potions' or nil})
        if k == 'stamina' then rects.potion_stamina = {t:cell(i)} end
        if pc then cfg.potions[k] = on; changed = true end
    end
    y = y + t:height() + 10

    t = ui.table('rest', x, y, w, {columns = {180, 220, '*'}, spacing = {8, 6}})
    t:row()
    c, cfg.keep_set = t:checkbox(1, 'Set items always', cfg.keep_set == true, {id = 'keep_set'})
    changed = changed or c
    c, cfg.keep_quest = t:checkbox(2, 'Quest items always', cfg.keep_quest ~= false, {id = 'keep_quest'})
    changed = changed or c
    t:row()
    t:label(1, 'Dim filtered labels')
    c, cfg.dim_alpha = t:slider(2, 0, 255, cfg.dim_alpha, {id = 'dim', step = 5,
        tooltip = 'Alpha of the labels of filtered items (255: not dimmed)'})
    changed = changed or c
    t:row(28)
    if t:button(1, 'Close', {id = 'close', width = 120, halign = 'left'}) then ui.show_panel('settings', false) end
    t:label(2, 'Also in the Mods screen (F11)', {size = 11, color = ui.COLORS.text_dim, span = 2})
    if changed then push(); refresh() end
end

gear.on('draw', function(state)
    if not state then return end
    overlay(state)
    if state.mode == 'game' and not state.exclusive then settings_panel() end
end)

gear.keys.on('panel', function()
    ui.toggle_panel('settings')
end)

---------------------------------------------------------------------------------------------------------------
-- Self test (selftest.lua): only when the game runs with -gear-auto. It reads the filter's state through `probe`.
---------------------------------------------------------------------------------------------------------------
if gear.auto then
    require('selftest')({
        CATEGORIES = CATEGORIES,
        refresh = refresh,
        stats = stats,
        last_items = function() return last_items end,
        overlay_shown = function() return overlay_shown end,
        rects = rects,
    })
end
