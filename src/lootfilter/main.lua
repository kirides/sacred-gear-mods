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

local QUALITY_OPTIONS = {'normal', 'magic', 'rare', 'set', 'unique'}
local CATEGORY_OPTIONS = {'(minimum)', 'normal', 'magic', 'rare', 'set', 'unique', 'never'}
local function index_of(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return 1
end

-- Where the self test finds the controls it clicks (set by the panel while it is drawn).
local rects = {}

-- The window: ui/filter.rml (the game theme) holds the overlay and the settings form. Check orbs and the cycling buttons are handled by
-- delegated click listeners (the settings keep their old rules: push() writes them to the mod manager, refresh() applies them).
local doc
local last = {}
local settings_open = false
local editing_now = false

local function olines()
    local out = {}
    local classes = wanted_classes(W.hero())
    local function add(k, v, q, sub) out[#out + 1] = {k = k, v = v or '', q = q or '', sub = sub and true or false} end
    add('Classes:', classes and table.concat(classes, ', ') or 'any')
    add('Minimum:', cfg.min_quality, cfg.min_quality)
    for _, cat in ipairs(CATEGORIES) do
        local rule = cfg.categories[cat]
        if rule == false then
            add(cat, 'never', 'never', true)
        else
            local q = rule or cfg.min_quality
            add(cat, q .. (rule and '' or ' *'), q, true)
        end
    end
    local taken = {}        -- the potion kinds picked up, then the colours that are not
    for _, k in ipairs(POTIONS) do
        if cfg.potions[k] ~= false then taken[#taken + 1] = k end
    end
    for _, color in ipairs(POTION_COLORS) do
        if cfg.potions[color] == false then taken[#taken + 1] = 'no ' .. color end
    end
    add('Potions:', #taken > 0 and table.concat(taken, ', ') or 'none')
    add('Set items:', cfg.keep_set and 'always' or 'by rule')
    add('Quest items:', cfg.keep_quest and 'always' or 'by rule')
    add('Nearby:', ('%d items, %d filtered'):format(stats.near, stats.blocked))
    add('Refused pickups:', tostring(W.pickup_refused()))
    return out
end

local function snapshot(visible)
    local picked = {}
    if type(cfg.classes) == 'table' then for _, n in ipairs(cfg.classes) do picked[n] = true end end
    local mode = cfg.classes == 'own' and 1 or cfg.classes == false and 2 or 3
    local m = {
        overlay_x = (cfg.overlay_x or 16) .. 'px', overlay_y = (cfg.overlay_y or 100) .. 'px', overlay_visible = visible, editing = editing_now, enabled = cfg.enabled == true, on_text = cfg.enabled and 'on' or 'off',
        settings_label = 'Settings' .. key_hint('panel'), olines = visible and olines() or {},
        settings_open = settings_open, mode = tostring(mode), min_quality = cfg.min_quality, classes = {}, cats = {}, potions = {},
        keep_set = cfg.keep_set == true, keep_quest = cfg.keep_quest ~= false, dim = cfg.dim_alpha,
    }
    if settings_open then
        for _, cls in ipairs(W.CLASSES) do m.classes[#m.classes + 1] = {id = 'class-' .. cls.name, name = cls.name, on = picked[cls.name] == true} end
        for _, cat in ipairs(CATEGORIES) do
            local rule = cfg.categories[cat]
            m.cats[#m.cats + 1] = {id = 'cat-' .. cat, name = cat, rule = rule == false and 'never' or rule or '(minimum)'}
        end
        for _, k in ipairs(POTIONS) do
            m.potions[#m.potions + 1] = {id = 'potion-' .. k, name = k, on = cfg.potions[k] ~= false,
                tip = k == 'colored' and 'The black, blue, green, red and yellow potions' or ''}
        end
    end
    return m
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function changed()
    push()
    refresh()
end

local function next_in(list, v)
    for i, x in ipairs(list) do if x == v then return list[i % #list + 1] end end
    return list[1]
end

local function load_doc()
    local m = snapshot(false)
    last = m
    local err
    doc, err = ui.rml.load('ui/filter.rml', {model = m, on_change = function(_, model)
        local dim = tonumber(model.dim)
        if dim and dim ~= cfg.dim_alpha then cfg.dim_alpha = dim; changed() end
    end})
    if not doc then gear.log('loot filter: ui/filter.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('#open-settings', function() settings_open = not settings_open end)
    on('#close', function() settings_open = false end)
    on('#enabled', function() cfg.enabled = not cfg.enabled; changed() end)
    on('#keep_set', function() cfg.keep_set = not cfg.keep_set; changed() end)
    on('#keep_quest', function() cfg.keep_quest = not (cfg.keep_quest ~= false); changed() end)
    on('#mode1', function() cfg.classes = 'own'; changed() end)
    on('#mode2', function() cfg.classes = false; changed() end)
    on('#mode3', function()
        if type(cfg.classes) ~= 'table' then
            local own = W.hero() and W.hero():class()
            cfg.classes = {own or 'seraphim'}
        end
        changed()
    end)
    on('#min_quality', function() cfg.min_quality = next_in(QUALITY_OPTIONS, cfg.min_quality); changed() end)
    on('[id^=class-]', function(e)
        if type(cfg.classes) ~= 'table' then return end
        local name = tostring(e.current):sub(7)
        local picked = {}
        for _, n in ipairs(cfg.classes) do picked[n] = true end
        picked[name] = not picked[name] or nil
        local list = {}
        for _, k in ipairs(W.CLASSES) do if picked[k.name] then list[#list + 1] = k.name end end
        cfg.classes = list
        changed()
    end)
    on('.catb', function(e)
        local cat = tostring(e.current):sub(5)
        local rule = cfg.categories[cat]
        local cur = rule == false and 'never' or rule or '(minimum)'
        cfg.categories[cat] = category_rule(next_in(CATEGORY_OPTIONS, cur))
        changed()
    end)
    on('[id^=potion-]', function(e)
        local k = tostring(e.current):sub(8)
        cfg.potions[k] = not (cfg.potions[k] ~= false)
        changed()
    end)
end

-- Overlay: only while the game shows its labels (Alt held), like the game's own text, and in the layout editor; the settings window stays open on its own.
local overlay_shown = false
local show_text_until = 0       -- gear.time() until which the overlay stays after Alt was released
gear.on('draw', function(state)
    if not state then return end
    overlay_shown = false
    if state.show_text then show_text_until = gear.time() + 0.4 end     -- it stays a moment, so a click made just before still lands on its button
    editing_now = ui.edit_mode()
    local game = state.mode == 'game' and not state.exclusive
    local visible = cfg.overlay and game and (gear.time() < show_text_until or editing_now) and true or false
    overlay_shown = visible
    if not game or (not visible and not settings_open) then return end
    if not doc then load_doc() end
    if not doc then return end
    for k, v in pairs(snapshot(visible)) do
        if k ~= 'dim' and not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    if tonumber(doc.model.dim) ~= cfg.dim_alpha then doc.model.dim = cfg.dim_alpha end
    doc:draw({layer = 'hud'})
end)

gear.keys.on('panel', function()
    settings_open = not settings_open
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
        rect = function(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end,
        settings_open = function() return settings_open end,
    })
end
