-- Better SaveLoad: the game's savegame screens made new, on Sacred Gear's replaced windows (gear.ui.replace_window).
--
-- The game's own windows still open and close as they always do: the savegame window in game (S, the escape menu)
-- and the start menu's Load game screen. While one is open this mod draws its screen in its place: every savegame with
-- its picture, the hero's name, class and level and when it was saved; filters by character and class; newest first
-- or by file name, as the game lists them. Loading, saving and deleting go the game's own ways (gear.game.load,
-- gear.game.save with `window = true`, gear.game.delete_save). If this mod is off or fails, the game's window shows.

local ui, game = gear.ui, gear.game
local S = gear.settings
local C = ui.COLORS

local WND_GAME, WND_MENUS = 'UI_WND_SAVEGAME', 'UI_MENU_LOADGAME'
local LAYER = 'top'
local ROW_H, THUMB_W, THUMB_H = 54, 64, 48
local DOUBLE_CLICK = 0.4    -- seconds between the two clicks of a double click
local SEARCH_MAX = 40
local NAME_MAX = 60     -- the engine keeps 60 characters of a savegame's name (Windows-1252: umlauts and the like)

-- the game's own (localized) name of the hero body, the English one if the game has none; looked up when first shown
local function localized_labels(english, types)
    local cache = {}
    return setmetatable({}, {__index = function(_, k)
        local v = cache[k]
        if v == nil then
            v = english[k]
            local t = types[k]
            if t and gear and gear.data and gear.data.object_types then
                local ok, n = pcall(function() return gear.data.object_types:display_name(t) end)
                if ok and type(n) == 'string' and n ~= '' then v = n end
            end
            cache[k] = v or false
        end
        return v or nil
    end})
end

local CLASS_LABEL = localized_labels({
    seraphim = 'Seraphim', gladiator = 'Gladiator', battlemage = 'Battle Mage', darkelf = 'Dark Elf',
    woodelf = 'Wood Elf', vampiress = 'Vampiress', dwarf = 'Dwarf', daemon = 'Daemon',
}, {seraphim = 1, gladiator = 2, battlemage = 3, darkelf = 4, woodelf = 5, vampiress = 6, dwarf = 8, daemon = 9})
local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
local SORTS = {
    {id = 'newest', label = 'Newest first'}, {id = 'oldest', label = 'Oldest first'},
    {id = 'hero', label = 'By character'}, {id = 'level', label = 'Highest level first'},
    {id = 'number', label = 'By number'}, {id = 'file', label = 'By file name'},
}

local view = {
    open = nil,         -- the replaced window that is open (WND_GAME / WND_MENUS), nil: closed
    mode = 'save',      -- 'load' | 'save' (in the menus always 'load')
    all = {},           -- gear.game.saves()
    shown = {},         -- filtered and sorted
    heroes = {},        -- the character filter's names (index 1: all)
    classes = {},       -- the class filter's class names (index 1: all)
    hero_i = 1, class_i = 1, sort_i = 1,
    sel = nil,          -- the selected entry's slot; 'new' for the new savegame row (save mode)
    confirm = nil,      -- {text, yes = fn}: the question shown in place of the buttons
    message = nil, message_ok = false, message_until = 0,
    follow = false,     -- scroll the selection into view on the next draw
    search = '',        -- the search text: every word has to be somewhere in a savegame's text
    focus = 'name',     -- where typing goes in save mode: 'name' | 'search' (in load mode always the search)
    page = 8,           -- rows per page (set while drawing)
    name = '',          -- the name the next save gets (save mode); the player may type it
    name_edited = false, name_for = nil,  -- typed by the player / the selection the default name was made for
    osk = nil,          -- the on-screen keyboard is open: {shift = bool, target = 'name' | 'search'}
}

-- UTF-8: the number of characters, and the text without its last one.
local function utf8_len(text)
    local _, n = text:gsub('[^\128-\191]', '')
    return n
end
local function utf8_pop(text)
    local n = #text
    while n > 0 do
        local b = text:byte(n)
        n = n - 1
        if b < 0x80 or b >= 0xC0 then break end
    end
    return text:sub(1, n)
end

---------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------

local function L(opts)
    opts = opts or {}
    opts.layer = LAYER
    return opts
end

local function say(text, ok)
    view.message, view.message_ok, view.message_until = text, ok and true or false, gear.time() + 4
end

-- `text` cut with an ellipsis to fit `width` at `size`.
local fit = gear.fmt.fit_width

local function when(s)
    local t = (s.time and s.time > 0) and s.time or s.mtime
    if not t or t <= 0 then return '' end
    return os.date('%Y-%m-%d %H:%M', t)
end

local function stamp(s)
    return (s.time and s.time > 0) and s.time or (s.mtime or 0)
end

local function hero_label(s)
    return s.hero or (s.slot == 0 and 'Quicksave' or s.file)
end

local function class_label(s)
    return s.class and CLASS_LABEL[s.class] or nil
end

local function sort_id()
    return SORTS[view.sort_i].id
end

---------------------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------------------

local function find(slot)
    for _, s in ipairs(view.all) do
        if s.slot == slot then return s end
    end
end

-- The words of the search, lower case.
local function search_words()
    local words = {}
    for w in view.search:lower():gmatch('%S+') do words[#words + 1] = w end
    return words
end

-- What a search looks through: hero, class, level, name, file, the date saved.
local function haystack(s)
    if not s.hay then
        s.hay = table.concat({s.hero or '', class_label(s) or '', 'level ' .. s.level, s.name, s.file, when(s),
            s.slot == 0 and 'quicksave' or ''}, '\n'):lower()
    end
    return s.hay
end

local SORT_LESS = {
    newest = function(a, b)
        local ta, tb = stamp(a), stamp(b)
        if ta ~= tb then return ta > tb end
        return a.slot < b.slot
    end,
    oldest = function(a, b)
        local ta, tb = stamp(a), stamp(b)
        if ta ~= tb then return ta < tb end
        return a.slot < b.slot
    end,
    hero = function(a, b)
        local ha, hb = (a.hero or ''):lower(), (b.hero or ''):lower()
        if ha ~= hb then return ha < hb end
        local ta, tb = stamp(a), stamp(b)
        if ta ~= tb then return ta > tb end
        return a.slot < b.slot
    end,
    level = function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        local ta, tb = stamp(a), stamp(b)
        if ta ~= tb then return ta > tb end
        return a.slot < b.slot
    end,
    number = function(a, b) return a.slot < b.slot end,
}

local function apply_filters()
    local hero = view.hero_i > 1 and view.heroes[view.hero_i] or nil
    local class = view.class_i > 1 and view.classes[view.class_i] or nil
    local words = search_words()
    local out = {}
    for _, s in ipairs(view.all) do
        if (not hero or s.hero == hero) and (not class or s.class == class) then
            local ok = true
            if #words > 0 then
                local hay = haystack(s)
                for _, w in ipairs(words) do
                    if not hay:find(w, 1, true) then ok = false break end
                end
            end
            if ok then out[#out + 1] = s end
        end
    end
    local less = SORT_LESS[sort_id()]
    if less then table.sort(out, less) end   -- else: by file name, as gear.game.saves() returns them (the game's own order)
    view.shown = out
    -- Keep the selection if it is still listed, else the first.
    if view.sel ~= 'new' then
        local still = false
        for _, s in ipairs(out) do
            if s.slot == view.sel then still = true break end
        end
        if not still then
            view.sel = view.mode == 'save' and 'new' or (out[1] and out[1].slot or nil)
        end
    elseif view.mode ~= 'save' then
        view.sel = out[1] and out[1].slot or nil
    end
    view.follow = true
end

local pic_cache = {}        -- slot -> {url, at}: the pictures made (see picture_url)
local function refresh()
    pic_cache = {}
    view.all = game.saves()
    local heroes, seen = {}, {}
    for _, s in ipairs(view.all) do
        if s.hero and not seen[s.hero] then
            seen[s.hero] = true
            heroes[#heroes + 1] = s.hero
        end
    end
    table.sort(heroes, function(a, b) return a:lower() < b:lower() end)
    local old_hero = view.heroes[view.hero_i]
    view.heroes = {'All characters'}
    view.hero_i = 1
    for _, h in ipairs(heroes) do
        view.heroes[#view.heroes + 1] = h
        if view.hero_i == 1 and old_hero == h then view.hero_i = #view.heroes end
    end
    local present = {}
    for _, s in ipairs(view.all) do
        if s.class then present[s.class] = true end
    end
    local old_class = view.classes[view.class_i]
    view.classes = {'all'}
    view.class_i = 1
    for _, c in ipairs(CLASS_ORDER) do
        if present[c] then
            view.classes[#view.classes + 1] = c
            if old_class == c then view.class_i = #view.classes end
        end
    end
    apply_filters()
end

local function current_hero()
    local h = gear.world.hero()
    if not h then return nil end
    local cls = h:class()
    return {name = h:name(), level = h:level(), class = cls}
end

-- The first slot no savegame uses (1 up; 0 is the quicksave), as the game's own "new savegame" picks.
local function free_slot()
    if game.free_slot then return game.free_slot() end     -- no limit at 509, skips the slots mods reserved
    local used = {}
    for _, s in ipairs(view.all) do used[s.slot] = true end
    for slot = 1, 509 do
        if not used[slot] then return slot end
    end
end

local function default_name()
    local pattern = S.get('save_name')
    if type(pattern) ~= 'string' or pattern == '' then pattern = '%hero% %Y-%m-%d %H:%M' end
    local h = current_hero()
    -- The hero's name may hold a % of its own: doubled, so os.date leaves it alone.
    local hero = (h and h.name or 'Hero'):gsub('%%', '%%%%')
    local name = pattern:gsub('%%hero%%', function() return hero end)
        :gsub('%%level%%', function() return tostring(h and h.level or '') end)
    name = os.date(name)
    while utf8_len(name) > NAME_MAX do name = utf8_pop(name) end
    return name
end

-- A savegame's name that is worth keeping when it is overwritten: not empty, not the game's "<empty>" text.
local function real_name(s)
    return s and s.name ~= '' and not s.name:match('^<.*>$') and s.name ~= 'QUICKSAVE' and s.name or nil
end

-- The name field follows the selection until the player types: the overwritten savegame's name, else a new one.
local function sync_name()
    if view.name_edited or view.name_for == view.sel then return end
    view.name_for = view.sel
    local s = view.sel ~= 'new' and find(view.sel) or nil
    view.name = real_name(s) or default_name()
end

-- Where typing goes now: 'name' (save mode), 'search', or nil (a question is open).
local function typing_target()
    if view.confirm then return nil end
    if view.mode == 'load' then return 'search' end
    return view.focus
end

local function add_to_name(text)
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if utf8_len(view.name) >= NAME_MAX then break end
        view.name = view.name .. ch
        view.name_edited = true
    end
end

-- Typing into the search: the list follows.
local function add_to_search(text)
    local before = view.search
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if utf8_len(view.search) >= SEARCH_MAX then break end
        view.search = view.search .. ch
    end
    if view.search ~= before then apply_filters() end
end

local function set_search(text)
    if view.search ~= text then
        view.search = text
        apply_filters()
    end
end

-- Typed text into whichever field has the keys.
local function add_text(text)
    local target = typing_target()
    if target == 'search' then add_to_search(text) elseif target == 'name' then add_to_name(text) end
end

local function pop_text()
    local target = typing_target()
    if target == 'search' then
        set_search(utf8_pop(view.search))
    elseif target == 'name' then
        view.name = utf8_pop(view.name)
        view.name_edited = true
    end
end

---------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------

local function close()
    view.confirm = nil
    if view.open then ui.close_window(view.open) end
end

local function do_load(s)
    local ok, err = game.load(s.slot)
    if not ok then say('Cannot load: ' .. tostring(err), false) end
end

local function do_save(slot)
    local name = view.name:match('^%s*(.-)%s*$')
    if name == '' then name = default_name() end
    local ok, err = game.save(slot, name, {window = true})
    if ok then
        view.note = {text = ('Saved to %s'):format(('GAME%02d.PAK'):format(slot)), slot = slot}
    else
        say('Cannot save: ' .. tostring(err), false)
    end
end

local function do_delete(s)
    local ok, err = game.delete_save(s.slot)
    if ok then
        say(('%s deleted'):format(s.file), true)
        refresh()
    else
        say('Cannot delete: ' .. tostring(err), false)
    end
end

local function ask(text, yes)
    view.confirm = {text = text, yes = yes}
end

local function load_selected()
    local s = view.sel ~= 'new' and find(view.sel)
    if not s then return end
    if not s.compatible then
        say('This savegame is of another version of the game', false)
        return
    end
    if view.open == WND_GAME and S.get('confirm_load') then
        ask(('Load %s? What was not saved is lost.'):format(hero_label(s)), function() do_load(s) end)
    else
        do_load(s)
    end
end

local function save_selected()
    if view.open ~= WND_GAME then return end
    if view.sel == 'new' then
        local slot = free_slot()
        if not slot then say('No free savegame number left', false) return end
        do_save(slot)
        return
    end
    local s = find(view.sel)
    if not s then return end
    ask(('Overwrite %s (%s)?'):format(hero_label(s), when(s)), function() do_save(s.slot) end)
end

local function delete_selected()
    local s = view.sel ~= 'new' and find(view.sel)
    if not s then return end
    ask(('Delete %s (%s, %s)? This cannot be undone.'):format(hero_label(s), s.file, when(s)), function() do_delete(s) end)
end

local function primary()
    if view.mode == 'save' then save_selected() else load_selected() end
end

-- The selection one up or down the list (keyboard).
local function move(d)
    local rows = {}
    if view.mode == 'save' then rows[1] = 'new' end
    for _, s in ipairs(view.shown) do rows[#rows + 1] = s.slot end
    if #rows == 0 then return end
    local at = 1
    for i, r in ipairs(rows) do
        if r == view.sel then at = i break end
    end
    if d == 'first' then at = 1 elseif d == 'last' then at = #rows else at = at + d end
    at = math.max(1, math.min(#rows, at))
    view.sel = rows[at]
    view.follow = true
end

local OSK_ROWS = {
    {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'ß'},
    {'q', 'w', 'e', 'r', 't', 'z', 'u', 'i', 'o', 'p', 'ü'},
    {'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ö', 'ä'},
    {'y', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '-', '!'},
}
local OSK_UPPER = {['ü'] = 'Ü', ['ö'] = 'Ö', ['ä'] = 'Ä', [','] = ';', ['.'] = ':', ['-'] = '_', ['!'] = '?'}

local function osk_type(text)
    if view.osk.target == 'search' then add_to_search(text) else add_to_name(text) end
end

local function osk_back()
    if view.osk.target == 'search' then
        set_search(utf8_pop(view.search))
    else
        view.name = utf8_pop(view.name)
        view.name_edited = true
    end
end

---------------------------------------------------------------------------------------------------------------
-- The screen: ui/screen.rml (the game theme, the thick frame of the menu screens)
---------------------------------------------------------------------------------------------------------------
-- A model of ready-made values (only the rows in view: the list may hold thousands), rebuilt every frame; only what changed is written.
-- The search and the name are text fields (data-value): the document takes the keys while one has the focus and hands the text back through
-- on_change. Clicks are delegated listeners; the keyboard shortcuts (arrows, Enter, Delete ...) stay in input().
local doc
local last = {}
local row_keys = {}          -- row element id -> slot | 'new'
local scroll_top = 0

-- A savegame's picture is read from its file the first time (a few milliseconds each): the rows in view ask every frame, and scrolling fast brings new ones every
-- frame, so a frame loads at most PIC_BUDGET of them (the others show nothing for a moment) and every one is kept for PIC_RECHECK seconds.
local PIC_BUDGET, PIC_RECHECK = 2, 5
local pic_budget = PIC_BUDGET
local function picture_url(s)
    if not (s and s.picture) then return '' end
    local c = pic_cache[s.slot]
    local now = gear.time()
    if c and now - c.at < PIC_RECHECK then return c.url end
    if pic_budget <= 0 then return c and c.url or nil end       -- nil: not loaded yet
    pic_budget = pic_budget - 1
    local pic = game.save_picture(s.slot)
    local url = pic and ('gear:image/' .. pic) or ''
    pic_cache[s.slot] = {url = url, at = now}
    return url
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function row_model(s, key)
    if not s then
        return {id = 'rownew', sel = key == view.sel, ok = true, pic = '', nopic = '', title = 'New savegame', sub = '',
            line2 = 'Saves into the first free number'}
    end
    local sub = {}
    if s.level > 0 then sub[#sub + 1] = 'Level ' .. s.level end
    if class_label(s) then sub[#sub + 1] = class_label(s) end
    if s.slot == 0 then sub[#sub + 1] = 'Quicksave' end
    local line2 = when(s)
    if s.name ~= '' and s.name ~= 'QUICKSAVE' then line2 = line2 .. '   ' .. s.name end
    if not s.compatible then line2 = 'another version of the game - ' .. line2 end
    local url = picture_url(s)
    return {id = 'row' .. tostring(key), sel = key == view.sel, ok = s.compatible and true or false, pic = url or '', nopic = url == '' and 'no picture' or '',
        title = hero_label(s), sub = table.concat(sub, ' - '), line2 = line2}
end

local function details_model(s)
    local d = {pic = '', nopic = '', title = '', sub = '', fields = {}, note = ''}
    local url = picture_url(s)
    d.pic = url or ''
    if url == '' then d.nopic = 'no picture' end
    if not s then
        if view.mode == 'save' then
            local h = current_hero()
            if h then
                d.title = h.name or ''
                d.sub = ('Level %d %s'):format(h.level or 0, CLASS_LABEL[h.class or ''] or '')
            end
            d.note = 'A new savegame of the game as it is now.'
        end
        return d
    end
    d.title = hero_label(s)
    local line = {}
    if s.level > 0 then line[#line + 1] = 'Level ' .. s.level end
    if class_label(s) then line[#line + 1] = class_label(s) end
    d.sub = table.concat(line, ' ')
    local function field(label, value)
        if value and value ~= '' then d.fields[#d.fields + 1] = {k = label, v = value} end
    end
    field('Saved', when(s))
    field('In game', s.world_date)
    field('Name', s.name ~= '' and s.name or nil)
    field('File', ('%s (%.1f MB)'):format(s.file, s.size / 1048576))
    if not s.compatible then field('Version', ('%d: this game cannot load it'):format(s.version)) end
    return d
end

local function osk_model()
    local o = view.osk
    if not o then return '', {}, '' end
    local rows = {}
    for r, rowkeys in ipairs(OSK_ROWS) do
        local keys = {}
        for i, k in ipairs(rowkeys) do
            local label = k
            if o.shift then label = OSK_UPPER[k] or k:upper() end
            keys[i] = {id = ('osk%d_%d'):format(r, i), label = label}
        end
        rows[r] = keys
    end
    return o.target == 'search' and 'On-screen keyboard: search' or 'On-screen keyboard: the name of the savegame', rows, o.shift and 'SHIFT' or 'Shift'
end

local ROW_H_UNITS = 56      -- a row (50 and its 1px border on both sides) and its gap (4)
local VIEW_ROWS = 8

local function snapshot(preview)
    pic_budget = PIC_BUDGET
    local m = {
        open = view.open ~= nil or preview == true, title = view.open == WND_MENUS and 'Load game' or 'Savegames',
        in_game = view.open == WND_GAME, load_on = view.mode == 'load', save_on = view.mode == 'save',
        hero_label = view.heroes[view.hero_i] or '', class_label = view.class_i == 1 and 'All classes' or (CLASS_LABEL[view.classes[view.class_i]] or ''),
        sort_label = SORTS[view.sort_i].label, count_text = ('%d of %d'):format(#view.shown, #view.all), no_rows = #view.shown == 0,
        search_kbd = (view.osk and view.osk.target == 'search') and 'Close' or 'Keyboard',
        name_kbd = (view.osk and view.osk.target == 'name') and 'Close keyboard' or 'Keyboard',
        osk = view.osk ~= nil, rows = {}, spacer_top = '0px', spacer_bot = '0px', empty_msg = '',
        confirm = view.confirm ~= nil, confirm_text = view.confirm and view.confirm.text or '', msg = '', msg_ok = true,
        can_primary = view.sel ~= nil, primary_label = view.sel == 'new' and 'Save' or 'Overwrite',
        can_load = false, can_delete = false,
        osk_title = '', osk_rows = {}, shift_label = 'Shift',
        d = {pic = '', nopic = '', title = '', sub = '', fields = {}, note = ''},
    }
    if not view.open then return m end
    local s = view.sel ~= 'new' and find(view.sel) or nil
    m.can_load = s ~= nil and s.compatible
    m.can_delete = s ~= nil
    if view.message and gear.time() < view.message_until then m.msg, m.msg_ok = view.message, view.message_ok end
    m.osk_title, m.osk_rows, m.shift_label = osk_model()
    m.d = details_model(s)
    -- the rows in view
    local rows = {}
    if view.mode == 'save' then rows[1] = false end   -- the "new savegame" row
    for _, sv in ipairs(view.shown) do rows[#rows + 1] = sv end
    local first = math.max(1, math.floor(scroll_top / ROW_H_UNITS) - 1)
    local lastrow = math.min(#rows, first + VIEW_ROWS + 4)
    row_keys = {}
    for i = first, lastrow do
        local sv = rows[i]
        local key = sv and sv.slot or 'new'
        local r = row_model(sv or nil, key)
        row_keys[r.id] = key
        m.rows[#m.rows + 1] = r
    end
    m.spacer_top = ((math.max(1, first) - 1) * ROW_H_UNITS) .. 'px'
    m.spacer_bot = (math.max(0, #rows - lastrow) * ROW_H_UNITS) .. 'px'
    view.rows_total = #rows
    view.page = VIEW_ROWS
    if #rows == 0 then m.empty_msg = #view.all == 0 and 'No savegames yet.' or 'No savegame matches the filters.' end
    return m
end

local function set_field(key, value)
    if doc then doc.model[key] = value; last[key] = value end
end

local pressers = {}       -- selector -> handler, for the self test's 'better-saveload.press'

local function load_doc()
    local m = snapshot()
    m.q, m.name = view.search, view.name
    last = m
    local err
    doc, err = ui.rml.load('ui/screen.rml', {model = m, on_change = function(_, model)
        local q = tostring(model.q or '')
        if q ~= view.search then
            view.search = q:sub(1, 200)
            apply_filters()
        end
        local name = tostring(model.name or '')
        if name ~= view.name then view.name, view.name_edited = name, true end
        last.q, last.name = model.q, model.name
    end})
    if not doc then gear.log('better-saveload: ui/screen.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn)
        local guarded = gear.guard('click ' .. sel, fn)
        pressers[sel] = guarded
        doc:on(sel, 'click', guarded)
    end
    on('#mode-load', function()
        view.mode, view.confirm, view.osk = 'load', nil, nil
        apply_filters()
    end)
    on('#mode-save', function()
        view.mode, view.confirm, view.osk, view.sel = 'save', nil, nil, 'new'
        apply_filters()
    end)
    on('#hero', function() view.hero_i = view.hero_i % #view.heroes + 1; apply_filters() end)
    on('#class', function() view.class_i = view.class_i % #view.classes + 1; apply_filters() end)
    on('#sort', function() view.sort_i = view.sort_i % #SORTS + 1; apply_filters() end)
    on('#search_kbd', function()
        view.focus = 'search'
        view.osk = not (view.osk and view.osk.target == 'search') and {shift = false, target = 'search'} or nil
    end)
    on('#kbd', function()
        view.osk = not (view.osk and view.osk.target == 'name') and {shift = false, target = 'name'} or nil
        view.focus = 'name'
    end)
    on('#search', function() view.focus = 'search' end)
    on('#name', function() view.focus = 'name' end)
    on('[id^=jump]', function(e)
        local i = tonumber(tostring(e.current):match('^jump(%d)$'))
        if not i or #view.shown == 0 then return end
        move(i == 1 and 'first' or i == 4 and 'last' or (i == 2 and -view.page or view.page))
    end)
    on('.row', function(e)
        local key = row_keys[tostring(e.current)]
        if key == nil then return end
        -- A second click on the same row soon after the first: Load / Save, as its button.
        local now = gear.time()
        local last_click = view.last_click
        local activate = last_click ~= nil and last_click.key == key and now - last_click.at <= DOUBLE_CLICK
        view.last_click = not activate and {key = key, at = now} or nil
        view.sel = key
        view.confirm = nil
        if activate then primary() end
    end)
    on('#save', function() if view.sel ~= nil then save_selected() end end)
    on('#load', load_selected)
    on('#delete', delete_selected)
    on('#close', close)
    on('#yes', function()
        if view.confirm then
            local yes = view.confirm.yes
            view.confirm = nil
            yes()
        end
    end)
    on('#no', function() view.confirm = nil end)
    -- the on-screen keyboard
    local function type_text(text)
        if not view.osk then return end
        if view.osk.target == 'search' then
            add_to_search(text)
            set_field('q', view.search)
        else
            add_to_name(text)
            set_field('name', view.name)
        end
    end
    on('[id^=osk]', function(e)
        local id = tostring(e.current)
        local o = view.osk
        if not o then return end
        if id == 'osk_shift' then o.shift = not o.shift
        elseif id == 'osk_space' then type_text(' ')
        elseif id == 'osk_back' then
            osk_back()
            set_field(o.target == 'search' and 'q' or 'name', o.target == 'search' and view.search or view.name)
        elseif id == 'osk_done' then view.osk = nil
        else
            local r, i = id:match('^osk(%d+)_(%d+)$')
            local k = r and OSK_ROWS[tonumber(r)] and OSK_ROWS[tonumber(r)][tonumber(i)]
            if k then
                type_text(o.shift and (OSK_UPPER[k] or k:upper()) or k)
                o.shift = false
            end
        end
    end)
end

-- Where the typed text goes by default when the screen opens: the name (save mode) or the search (load mode).
local function focus_default()
    if not doc then return end
    local sel = view.mode == 'save' and '#name' or '#search'
    local e = doc:query(sel)
    if e then e:focus() end
end

local function screen(preview)
    if not doc then load_doc() end
    if not doc then return end
    if not preview then sync_name() end
    local m = snapshot(preview)
    for k, v in pairs(m) do
        if k ~= 'q' and k ~= 'name' and not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    -- the name follows the selection until the player types (sync_name above): push it into the field when it changed from code
    if view.name ~= last.name then set_field('name', view.name) end
    if view.search ~= last.q then set_field('q', view.search) end
    if view.focus_request then
        view.focus_request = nil
        focus_default()
    end
    doc:draw({layer = LAYER, modal = not preview})
    local list = doc:query('#list')
    if list then
        local top, height, client = list:scroll()
        if top then
            scroll_top = top
            if view.follow then
                view.follow = false
                local rows = view.rows_total or 0
                for i = 1, rows do
                    local key = (view.mode == 'save' and i == 1) and 'new' or (view.shown[i - (view.mode == 'save' and 1 or 0)] or {}).slot
                    if key == view.sel then
                        local t = (i - 1) * ROW_H_UNITS
                        if t < top then list:scroll(t)
                        elseif t + ROW_H_UNITS > top + client then list:scroll(t + ROW_H_UNITS - client) end
                        break
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------------------------------------------

local function opened(name)
    view.open = name
    view.confirm = nil
    view.message = nil
    view.mode = name == WND_GAME and 'save' or 'load'     -- in game always the Save tab first
    for i, s in ipairs(SORTS) do
        if s.id == S.get('sort') then view.sort_i = i end
    end
    view.sel = nil
    view.name, view.name_edited, view.name_for, view.osk = '', false, nil, nil
    view.search, view.focus = '', 'name'
    refresh()
    if name == WND_GAME and S.get('current_hero') then
        local h = current_hero()
        for i, n in ipairs(view.heroes) do
            if h and n == h.name then view.hero_i = i end
        end
        apply_filters()
    end
    if view.mode == 'save' then view.sel = 'new' end
    view.focus_request = true
    scroll_top = 0
    -- (the document is drawn modal: the game and the pad belong to it)
    ui.capture_keys(true)
end

local function closed()
    view.open = nil
    view.confirm = nil

    ui.capture_keys(false)
end

local function input()
    local back = ui.back_pressed() or ui.key_pressed('escape')
    if back then
        if view.confirm then view.confirm = nil
        elseif view.osk then view.osk = nil
        elseif view.search ~= '' then set_search('') view.focus = 'name'      -- the first Back clears the search
        else close() end
        return
    end
    -- Typing goes into the text fields of the document (the search, the name).
    if view.confirm then
        if ui.key_pressed('enter') then
            local yes = view.confirm.yes
            view.confirm = nil
            yes()
        end
        return
    end
    if ui.key_pressed('up') then move(-1) end
    if ui.key_pressed('down') then move(1) end
    if ui.key_pressed('pageup') then move(-view.page) end
    if ui.key_pressed('pagedown') then move(view.page) end
    if ui.key_pressed('home') then move('first') end
    if ui.key_pressed('end') then move('last') end
    if ui.key_pressed('enter') then
        if view.mode == 'save' and view.focus == 'search' then view.focus = 'name' else primary() end
    end
    if ui.key_pressed('delete') then delete_selected() end
end

local function claim()
    ui.replace_window(WND_GAME, S.get('in_game') ~= false)
    ui.replace_window(WND_MENUS, S.get('in_menus') ~= false)
end

claim()
gear.on('settings.changed', function(id)
    if id == 'in_game' or id == 'in_menus' then claim() end
end)

gear.on('game.saved', function(slot)
    if view.note and view.note.slot == slot then
        view.note.until_ = gear.time() + 3
    end
end)

-- For the self test (better-saveload_selftest) and other mods: gear.emit('better-saveload.query', out) fills `out`
-- with the screen's state; 'better-saveload.stall' (true / false) stops drawing the screen, to check that the game's
-- own window comes back.
gear.on('better-saveload.query', function(out)
    out.open, out.mode, out.sel, out.confirm = view.open, view.mode, view.sel, view.confirm and view.confirm.text
    out.count, out.shown = #view.all, #view.shown
    out.heroes, out.classes, out.hero_i, out.class_i, out.sort = view.heroes, view.classes, view.hero_i, view.class_i, sort_id()
    out.message = view.message
    out.name, out.osk = view.name, view.osk ~= nil
    out.search, out.focus, out.page = view.search, view.focus, view.page
    out.osk_target = view.osk and view.osk.target or nil
    out.scroll_top = scroll_top
    out.order = {}
    for i, s in ipairs(view.shown) do out.order[i] = s.slot end
end)
-- gear.emit('better-saveload.press', {selector = '#close'}) runs the handler of a click on that selector (`id` is the element id for the row and
-- key selectors): the self test's way to press a button without the mouse.
gear.on('better-saveload.press', function(t) local fn = pressers[t.selector]; if fn then fn({current = t.id or tostring(t.selector):sub(2)}) t.done = true end end)
gear.on('better-saveload.rect', function(out) out.rect = function(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end end)   -- for the self test
gear.on('better-saveload.stall', function(on) view.stall = on and true or nil end)
gear.on('better-saveload.set', function(t)
    if t.hero_i then view.hero_i = t.hero_i end
    if t.class_i then view.class_i = t.class_i end
    if t.sort_i then view.sort_i = t.sort_i end
    if t.mode then view.mode = t.mode end
    if t.sel then view.sel = t.sel end
    if t.name then view.name, view.name_edited = t.name, true end
    if t.search then view.search = t.search end
    apply_filters()
end)

gear.on('draw', function(state)
    if view.stall then
        if view.open then closed() end
        return
    end
    local name = (ui.replaced(WND_GAME) and WND_GAME) or (ui.replaced(WND_MENUS) and WND_MENUS) or nil
    if name ~= view.open then
        if view.open then closed() end
        if name then opened(name) end
    end
    if name then
        input()
        if view.open then
            screen(false)
            ui.capture_keys(true)      -- the game takes no keys while the screen is open (the document's own capture ends with its text focus)
        end
        return
    end
    -- A note after a save from this screen.
    local note = view.note
    if note and note.until_ then
        if gear.time() < note.until_ and state.mode == 'game' then
            ui.text(note.text, 0, 60, {width = 1024, align = 'center', size = 15, color = 0xFFC8FFC8, outline = true})
        elseif gear.time() >= note.until_ then
            view.note = nil
        end
    end
    -- The layout editor: the screen's panel can be moved and sized while nothing else is open.
    if ui.edit_mode() and state.mode == 'game' and not state.exclusive then
        view.open = nil
        screen(true)
    end
end)
