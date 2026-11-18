-- Better SaveLoad: the game's savegame screens made new, on Sacred Gear's replaced windows (gear.ui.replace_window).
--
-- The game's own windows still open and close as they always do: the savegame window in game (S, the escape menu)
-- and the start menu's Load game screen. While one is open this mod draws its screen in its place: every savegame with
-- its picture, the hero's name, class and level and when it was saved; filters by character and class; newest first
-- or by file name, as the game lists them. Loading, saving and deleting go the game's own ways (gear.game.load,
-- gear.game.save with `window = true`, gear.game.delete_save). If this mod is off or fails, the game's window shows.

local ui, game = gear.ui, gear.game
if ui.persist_panel then ui.persist_panel('screen', false) end   -- it follows the game's save / load window
local S = gear.settings
local C = ui.COLORS

local WND_GAME, WND_MENUS = 'UI_WND_SAVEGAME', 'UI_MENU_LOADGAME'
local LAYER = 'top'
local ROW_H, THUMB_W, THUMB_H = 54, 64, 48
local DOUBLE_CLICK = 0.4    -- seconds between the two clicks of a double click
local NAME_MAX = 60     -- the engine keeps 60 characters of a savegame's name (Windows-1252: umlauts and the like)

local CLASS_LABEL = {
    seraphim = 'Seraphim', gladiator = 'Gladiator', battlemage = 'Battle Mage', darkelf = 'Dark Elf',
    woodelf = 'Wood Elf', vampiress = 'Vampiress', dwarf = 'Dwarf', daemon = 'Daemon',
}
local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
local SORTS = {{id = 'newest', label = 'Newest first'}, {id = 'file', label = 'By file name'}}

local osk, name_row     -- the on-screen keyboard and the name row (below the list's helpers)
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
    name = '',          -- the name the next save gets (save mode); the player may type it
    name_edited = false, name_for = nil,  -- typed by the player / the selection the default name was made for
    osk = nil,          -- the on-screen keyboard is open: {shift = bool}
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

local function apply_filters()
    local hero = view.hero_i > 1 and view.heroes[view.hero_i] or nil
    local class = view.class_i > 1 and view.classes[view.class_i] or nil
    local out = {}
    for _, s in ipairs(view.all) do
        if (not hero or s.hero == hero) and (not class or s.class == class) then out[#out + 1] = s end
    end
    if sort_id() == 'newest' then
        table.sort(out, function(a, b)
            local ta, tb = stamp(a), stamp(b)
            if ta ~= tb then return ta > tb end
            return a.slot < b.slot
        end)
    end   -- else: by file name, as gear.game.saves() returns them (the game's own order)
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

local function refresh()
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

local function add_to_name(text)
    for ch in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if utf8_len(view.name) >= NAME_MAX then break end
        view.name = view.name .. ch
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
    at = math.max(1, math.min(#rows, at + d))
    view.sel = rows[at]
    view.follow = true
end

---------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------

local function picture(x, y, w, h, s)
    ui.rect(x, y, w, h, 0xFF08080C, L())
    local pic = s and s.picture and game.save_picture(s.slot)
    if pic then
        ui.image(pic, x, y, w, h, L({fit = 'contain'}))
    else
        ui.text('no picture', x, y, L({width = w, height = h, align = 'center', valign = 'middle', size = 11,
            color = C.text_dim}))
    end
    ui.frame(x, y, w, h, C.edge_dim, 1, L())
end

local function row(id, x, y, w, s, selected)
    local clicked = ui.button(id, x, y, w, ROW_H - 4, '', L())
    if selected then
        ui.rect(x, y, w, ROW_H - 4, 0x40FFD780, L())
        ui.frame(x, y, w, ROW_H - 4, C.accent, 2, L())
    end
    local tx = x + 6
    if s then
        picture(x + 4, y + 1, THUMB_W, THUMB_H, s)
        tx = x + THUMB_W + 12
        local tw = w - (tx - x) - 6
        local title = hero_label(s)
        local sub = {}
        if s.level > 0 then sub[#sub + 1] = 'Level ' .. s.level end
        if class_label(s) then sub[#sub + 1] = class_label(s) end
        if s.slot == 0 then sub[#sub + 1] = 'Quicksave' end
        ui.text(fit(title, tw * 0.6, 15), tx, y + 4, L({size = 15, bold = true, color = s.compatible and C.accent or C.text_dim}))
        ui.text(fit(table.concat(sub, ' - '), tw * 0.4, 12), tx, y + 6, L({size = 12, width = tw, align = 'right',
            color = C.text}))
        local line2 = when(s)
        if s.name ~= '' and s.name ~= 'QUICKSAVE' then line2 = line2 .. '   ' .. s.name end
        if not s.compatible then line2 = 'another version of the game - ' .. line2 end
        ui.text(fit(line2, tw, 12), tx, y + 28, L({size = 12, color = C.text_dim}))
    else
        ui.text('New savegame', tx + 4, y, L({size = 15, bold = true, height = ROW_H - 4, valign = 'middle',
            color = C.accent}))
        ui.text('Saves into the first free number', tx + 160, y, L({size = 12, height = ROW_H - 4, valign = 'middle',
            color = C.text_dim}))
    end
    return clicked
end

local function details(x, y, w, s)
    local ph = math.floor(w * 3 / 4)
    if not s then
        picture(x, y, w, ph, nil)
        y = y + ph + 10
        if view.mode == 'save' then
            local h = current_hero()
            if h then
                ui.text(fit(h.name or '', w, 16), x, y, L({size = 16, bold = true, color = C.accent}))
                ui.text(('Level %d %s'):format(h.level or 0, CLASS_LABEL[h.class or ''] or ''), x, y + 22, L({size = 13}))
            end
            ui.text('A new savegame of the game as it is now.', x, y + 46, L({size = 12, color = C.text_dim, width = w}))
        end
        return
    end
    picture(x, y, w, ph, s)
    y = y + ph + 10
    ui.text(fit(hero_label(s), w, 16), x, y, L({size = 16, bold = true, color = C.accent}))
    y = y + 22
    local line = {}
    if s.level > 0 then line[#line + 1] = 'Level ' .. s.level end
    if class_label(s) then line[#line + 1] = class_label(s) end
    if #line > 0 then
        ui.text(table.concat(line, ' '), x, y, L({size = 13}))
        y = y + 20
    end
    local function field(label, value)
        if not value or value == '' then return end
        ui.text(label, x, y, L({size = 12, color = C.text_dim}))
        ui.text(fit(value, w - 70, 12), x + 70, y, L({size = 12}))
        y = y + 17
    end
    field('Saved', when(s))
    field('In game', s.world_date)
    field('Name', s.name ~= '' and s.name or nil)
    field('File', ('%s (%.1f MB)'):format(s.file, s.size / 1048576))
    if not s.compatible then field('Version', ('%d: this game cannot load it'):format(s.version)) end
end

local function toolbar(x, y, w)
    -- In game: the Load / Save tabs. Filters and the order on the same line.
    local fx = x
    if view.open == WND_GAME then
        local idx = view.mode == 'load' and 1 or 2
        local changed, i = ui.radio_group('mode', x, y + 3, {'Load', 'Save'}, idx, L({horizontal = true, spacing = 14}))
        if changed then
            view.mode = i == 1 and 'load' or 'save'
            view.confirm = nil
            view.osk = nil
            if view.mode == 'save' then view.sel = 'new' end
            apply_filters()
        end
        fx = x + 140
    end
    local labels = {}
    for i, c in ipairs(view.classes) do labels[i] = i == 1 and 'All classes' or CLASS_LABEL[c] end
    local sorts = {}
    for i, s in ipairs(SORTS) do sorts[i] = s.label end
    local dw = math.max(120, math.min(200, (w - (fx - x) - 24) / 3))
    local changed, i = ui.dropdown('hero', fx, y, dw, view.heroes, view.hero_i, L({tooltip = 'Character'}))
    if changed then view.hero_i = i apply_filters() end
    changed, i = ui.dropdown('class', fx + dw + 8, y, dw, labels, view.class_i, L({tooltip = 'Class'}))
    if changed then view.class_i = i apply_filters() end
    changed, i = ui.dropdown('sort', fx + 2 * (dw + 8), y, dw, sorts, view.sort_i, L({tooltip = 'Order'}))
    if changed then view.sort_i = i apply_filters() end
end

local function buttons(x, y, w)
    local bh = 26
    if view.confirm then
        ui.text(fit(view.confirm.text, w - 220, 13), x, y, L({size = 13, height = bh, valign = 'middle', color = C.accent}))
        if ui.button('yes', x + w - 210, y, 100, bh, 'Yes', L()) then
            local yes = view.confirm.yes
            view.confirm = nil
            yes()
        end
        if ui.button('no', x + w - 104, y, 100, bh, 'No', L()) then view.confirm = nil end
        return
    end
    local s = view.sel ~= 'new' and find(view.sel) or nil
    local bx = x
    if view.mode == 'save' then
        local label = view.sel == 'new' and 'Save' or 'Overwrite'
        if ui.button('save', bx, y, 120, bh, label, L({enabled = view.sel ~= nil})) then save_selected() end
    else
        if ui.button('load', bx, y, 120, bh, 'Load', L({enabled = s ~= nil and s.compatible})) then load_selected() end
    end
    bx = bx + 128
    if ui.button('delete', bx, y, 100, bh, 'Delete', L({enabled = s ~= nil, tooltip = 'Deletes the savegame file'})) then
        delete_selected()
    end
    if ui.button('close', x + w - 100, y, 100, bh, 'Back', L()) then close() end
    if view.message and gear.time() < view.message_until then
        ui.text(fit(view.message, w - 340, 12), bx + 112, y, L({size = 12, height = bh, valign = 'middle',
            color = view.message_ok and 0xFF80FF80 or 0xFFFF8080}))
    end
end

-- The name of the savegame to write: typed straight in (the keys go to it while the screen is open in save mode),
-- or with the on-screen keyboard (for a controller).
function name_row(x, y, w)
    sync_name()
    ui.text('Name', x, y, L({size = 13, height = 24, valign = 'middle', color = C.text_dim}))
    local fx, fw = x + 50, w - 50 - 130
    ui.rect(fx, y, fw, 24, 0xF0202030, L())
    ui.frame(fx, y, fw, 24, C.edge, 1, L())
    local caret = (not view.confirm and math.floor(gear.time() * 2) % 2 == 0) and '|' or ''
    ui.text(fit(view.name, fw - 16, 13) .. caret, fx + 6, y, L({size = 13, height = 24, valign = 'middle'}))
    if ui.button('kbd', x + w - 120, y, 120, 24, view.osk and 'Close keyboard' or 'Keyboard',
        L({tooltip = 'Type the name with an on-screen keyboard (for a controller)'})) then
        view.osk = not view.osk and {shift = false} or nil
    end
end

local OSK_ROWS = {
    {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'ß'},
    {'q', 'w', 'e', 'r', 't', 'z', 'u', 'i', 'o', 'p', 'ü'},
    {'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ö', 'ä'},
    {'y', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '-', '!'},
}
local OSK_UPPER = {['ü'] = 'Ü', ['ö'] = 'Ö', ['ä'] = 'Ä', [','] = ';', ['.'] = ':', ['-'] = '_', ['!'] = '?'}

-- The on-screen keyboard, in place of the list.
function osk(x, y, w, h)
    local o = view.osk
    ui.rect(x, y, w, h, 0xC0101018, L())
    ui.text('On-screen keyboard: the name of the savegame', x + 8, y + 6, L({size = 13, color = C.accent}))
    local cols, gap = 11, 4
    local kw = math.floor((w - 16 - (cols - 1) * gap) / cols)
    local ky = y + 32
    for r, keys in ipairs(OSK_ROWS) do
        for i, k in ipairs(keys) do
            local label = k
            if o.shift then label = OSK_UPPER[k] or k:upper() end
            if ui.button(('osk%d_%d'):format(r, i), x + 8 + (i - 1) * (kw + gap), ky, kw, 30, label, L()) then
                add_to_name(label)
                o.shift = false
            end
        end
        ky = ky + 36
    end
    local bw = math.floor((w - 16 - 3 * gap) / 4)
    if ui.button('osk_shift', x + 8, ky, bw, 30, o.shift and 'SHIFT' or 'Shift', L()) then o.shift = not o.shift end
    if ui.button('osk_space', x + 8 + (bw + gap), ky, bw, 30, 'Space', L()) then add_to_name(' ') end
    if ui.button('osk_back', x + 8 + 2 * (bw + gap), ky, bw, 30, 'Backspace', L()) then
        view.name = utf8_pop(view.name)
        view.name_edited = true
    end
    if ui.button('osk_done', x + 8 + 3 * (bw + gap), ky, bw, 30, 'Done', L()) then view.osk = nil end
end

local function screen(preview)
    local l, t, r, b = ui.screen()
    if not preview then
        -- The game's window is not drawn: the whole screen is this one's.
        ui.rect(l, t, r - l, b - t, 0xF00C0C10, L())
        ui.region('blocker', l, t, r - l, b - t, L({nav = false}))
    end
    local title = view.open == WND_MENUS and 'Load game' or 'Savegames'
    if preview then title = 'Savegames (Better SaveLoad)' end
    local p = ui.panel('screen', title, 112, 74, 800, 620, L({resizable = true, min_width = 640, min_height = 440,
        back = false}))
    if not p.open then
        ui.show_panel('screen', true)
        if not preview then close() end
        return
    end
    if preview then
        ui.text('The savegame screen: move and resize it here.', p.content_x, p.content_y + 8,
            L({size = 14, color = C.text_dim}))
        return
    end
    local x, y, w, h = p.content_x, p.content_y, p.content_w, p.content_h
    toolbar(x, y, w)
    y = y + 32
    local bottom = 34
    local pw = math.floor(math.max(200, math.min(300, w * 0.36)))
    local lw = w - pw - 14
    if view.mode == 'save' then bottom = bottom + 32 end     -- the name row
    local lh = h - 32 - bottom
    -- The list.
    local rows = {}
    if view.mode == 'save' then rows[1] = false end   -- the "new savegame" row
    for _, s in ipairs(view.shown) do rows[#rows + 1] = s end
    if view.follow then
        view.follow = false
        for i, s in ipairs(rows) do
            if (s and s.slot or 'new') == view.sel then
                local top = (i - 1) * ROW_H
                local off = ui.scroll_offset('list')
                if top < off then ui.scroll_to('list', top)
                elseif top + ROW_H > off + lh then ui.scroll_to('list', top + ROW_H - lh) end
                break
            end
        end
    end
    if view.osk then
        osk(x, y, lw, lh)
        details(x + lw + 14, y, pw, view.sel ~= 'new' and find(view.sel) or nil)
        name_row(x, y + lh + 8, w)
        buttons(x, y + lh + 40, w)
        return
    end
    local area = ui.scroll_begin('list', x, y, lw, lh, L({step = ROW_H}))
    local cy = area.content_y
    local activate = false      -- a double click: the tab's action on the row (after drawing)
    for i, s in ipairs(rows) do
        local key = s and s.slot or 'new'
        if cy + ROW_H >= area.y and cy <= area.y + area.h then
            if row('row' .. tostring(key), area.content_x, cy, area.w - 2, s or nil, key == view.sel) then
                -- A second click on the same row soon after the first: Load / Save, as its button.
                local now = gear.time()
                local last = view.last_click
                activate = last ~= nil and last.key == key and now - last.at <= DOUBLE_CLICK
                view.last_click = not activate and {key = key, at = now} or nil
                view.sel = key
                view.confirm = nil
            end
        end
        cy = cy + ROW_H
    end
    if #rows == 0 then
        ui.text(#view.all == 0 and 'No savegames yet.' or 'No savegame matches the filters.', area.content_x + 8,
            area.content_y + 8, L({size = 13, color = C.text_dim}))
    end
    ui.scroll_end(#rows * ROW_H)
    if activate then primary() end
    -- The selected savegame.
    details(x + lw + 14, y, pw, view.sel ~= 'new' and find(view.sel) or nil)
    if view.mode == 'save' then
        name_row(x, y + lh + 8, w)
        buttons(x, y + lh + 40, w)
    else
        buttons(x, y + lh + 8, w)
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
    refresh()
    if name == WND_GAME and S.get('current_hero') then
        local h = current_hero()
        for i, n in ipairs(view.heroes) do
            if h and n == h.name then view.hero_i = i end
        end
        apply_filters()
    end
    if view.mode == 'save' then view.sel = 'new' end
    ui.show_panel('screen', true)
    ui.nav_modal(true)
    ui.capture_keys(true)
end

local function closed()
    view.open = nil
    view.confirm = nil
    ui.nav_modal(false)
    ui.capture_keys(false)
end

local function input()
    local back = ui.back_pressed() or ui.key_pressed('escape')
    if back then
        if view.confirm then view.confirm = nil elseif view.osk then view.osk = nil else close() end
        return
    end
    -- Typing goes into the name (save mode).
    local typed = ui.typed()
    if view.mode == 'save' and not view.confirm then
        sync_name()
        if typed ~= '' then add_to_name(typed) end
        if ui.key_down('backspace') then
            local now = gear.time()
            if not view.back_since or now - view.back_since > 0.45 then
                view.back_since = view.back_since and now - 0.4 or now
                view.name = utf8_pop(view.name)
                view.name_edited = true
            end
        else
            view.back_since = nil
        end
    end
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
    if ui.key_pressed('pageup') then move(-5) end
    if ui.key_pressed('pagedown') then move(5) end
    if ui.key_pressed('enter') then primary() end
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
    out.order = {}
    for i, s in ipairs(view.shown) do out.order[i] = s.slot end
end)
gear.on('better-saveload.stall', function(on) view.stall = on and true or nil end)
gear.on('better-saveload.set', function(t)
    if t.hero_i then view.hero_i = t.hero_i end
    if t.class_i then view.class_i = t.class_i end
    if t.sort_i then view.sort_i = t.sort_i end
    if t.mode then view.mode = t.mode end
    if t.sel then view.sel = t.sel end
    if t.name then view.name, view.name_edited = t.name, true end
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
        if view.open then screen(false) end
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
    if ui.edit_mode() and state.mode == 'game' and not state.exclusive then screen(true) end
end)
