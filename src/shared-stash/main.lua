-- Shared stash: a stash of items shared by the heroes of this player, kept in stash.json in this folder.
-- See README.md. The panel opens from a button below the chest window (and with its key, F10 by default).
local cfg = gear.config
-- The settings (Mods screen) live in gear.settings; `cfg` (shared with transfer.lua) holds their current values.
for _, id in ipairs({'max_items', 'allow_special', 'recent'}) do cfg[id] = gear.settings.get(id) end
gear.on('settings.changed', function(id, value) cfg[id] = value end)
if not cfg.enabled then return end

local ui, world = gear.ui, gear.world
local stash = require('stash')
local transfer = require('transfer')

stash.load()
if stash.problem then gear.log('stash disabled: ' .. stash.problem) end
if stash.note then gear.log(stash.note) end

local QUALITY_COLOR = {
    normal = 0xFFEFEFEF, magic = 0xFFA0A0FF, rare = 0xFFF0E040, unique = 0xFFC19A33, set = 0xFF15FF25,
}
local CELL = 32                 -- layout units a cell, as in the game's inventory
local COLS, ROWS = 11, 6        -- the size of one page of a grid

local view = {
    stash_page = 0, source_page = 0,
    mode = 'deposit',       -- 'deposit' or 'recent' (the lower grid)
    sources = {}, sources_at = -10,
    message = nil, message_until = 0, message_ok = true,
    force_open = false,     -- self tests
}
local M = {view = view}

local function say(text, ok)
    view.message, view.message_ok, view.message_until = text, ok ~= false, gear.time() + 6
end

-- The items of the backpack and the chest the player could stash, refreshed a few times a second.
local function refresh_sources(force)
    if not force and gear.time() - view.sources_at < 0.25 then return end
    view.sources_at = gear.time()
    local list = {}
    for _, src in ipairs(transfer.sources()) do
        for _, it in ipairs(src.container:items()) do
            local ok, why = transfer.transferable(it)
            list[#list + 1] = {item = it, container = src.container, where = src.name, ok = ok, why = why}
        end
    end
    view.sources = list
end

-- The type id of a stash entry: the first four bytes of its data (little endian).
local function entry_type(e)
    if not e.type_id then
        local b = gear.inv.unhex(e.data:sub(1, 8))
        e.type_id = b and (b:byte(1) + b:byte(2) * 256 + b:byte(3) * 65536 + b:byte(4) * 16777216) or 0
    end
    return e.type_id
end

local function tip(e)
    local parts = {e.quality or '?', e.category or '?'}
    if e.class and e.class ~= 'any' then parts[#parts + 1] = 'for ' .. e.class end
    if e.from then parts[#parts + 1] = 'from a ' .. tostring(e.from) end
    return table.concat(parts, ', ')
end

-- Packs cells (each {w, h, ...}) into pages of COLS x ROWS cells, first fit in reading order; sets cx, cy, cw, ch and
-- page on each. Returns the number of pages (at least 1).
local function pack(cells)
    local pages = {}
    local function fits(g, x, y, w, h)
        for yy = y, y + h - 1 do
            for xx = x, x + w - 1 do
                if g[yy * COLS + xx] then return false end
            end
        end
        return true
    end
    for _, c in ipairs(cells) do
        local w, h = math.min(c.w, COLS), math.min(c.h, ROWS)
        local placed = false
        local p = 1
        while not placed do
            local g = pages[p]
            if not g then g = {} pages[p] = g end
            for y = 0, ROWS - h do
                for x = 0, COLS - w do
                    if fits(g, x, y, w, h) then
                        for yy = y, y + h - 1 do
                            for xx = x, x + w - 1 do g[yy * COLS + xx] = true end
                        end
                        c.cx, c.cy, c.page, c.cw, c.ch = x, y, p, w, h
                        placed = true
                        break
                    end
                end
                if placed then break end
            end
            p = p + 1
        end
    end
    return math.max(1, #pages)
end

-- A page of a grid of cells at (x, y): the cell backgrounds and, for each cell of `cells` on `page`, its item icon and
-- a region that takes the click. Returns the clicked cell. A cell: {w, h, icon (an item table or a type id), color,
-- tip, enabled, id}.
local function grid(id, x, y, cells, page)
    local gw, gh = COLS * CELL, ROWS * CELL
    ui.rect(x, y, gw, gh, 0x60000000)
    for cx = 0, COLS do ui.rect(x + cx * CELL, y, 1, gh, 0x30FFFFFF) end
    for cy = 0, ROWS do ui.rect(x, y + cy * CELL, gw, 1, 0x30FFFFFF) end
    local clicked
    for _, c in ipairs(cells) do
        if c.page == page + 1 then
            local px, py, pw, ph = x + c.cx * CELL, y + c.cy * CELL, c.cw * CELL, c.ch * CELL
            local r = ui.region(id .. c.id, px, py, pw, ph, {tooltip = c.tip, enabled = c.enabled})
            local hot = r.hover and c.enabled
            ui.rect(px + 1, py + 1, pw - 1, ph - 1, hot and 0x80506090 or 0x50203040)
            ui.item_icon(c.icon, px + 2, py + 2, pw - 3, ph - 3)
            ui.frame(px, py, pw + 1, ph + 1, hot and 0xFFFFFFFF or (c.color or 0xFF606060))
            if not c.enabled then ui.rect(px + 1, py + 1, pw - 1, ph - 1, 0xA0000000) end
            if r.clicked and c.enabled then clicked = c end
        end
    end
    return clicked
end

local function pager(id, x, y, page, pages)
    page = math.max(0, math.min(page, pages - 1))
    if ui.button(id .. '-prev', x, y, 22, 18, '<', {enabled = page > 0}) then page = page - 1 end
    ui.label(id .. '-n', ('%d / %d'):format(page + 1, pages), x + 28, y, {height = 18, valign = 'middle'})
    if ui.button(id .. '-next', x + 76, y, 22, 18, '>', {enabled = page < pages - 1}) then page = page + 1 end
    return page
end

local function entry_cells(list, hint)
    local cells = {}
    for _, e in ipairs(list) do
        cells[#cells + 1] = {
            id = 'e' .. e.uid, entry = e, w = e.w or 1, h = e.h or 1, icon = entry_type(e),
            color = QUALITY_COLOR[e.quality], enabled = true,
            tip = e.name .. '\n' .. tip(e) .. '\n' .. hint,
        }
    end
    return cells
end

local function panel()
    local p = ui.panel('stash', 'Shared stash', 646, 6, 372, 560, {closable = true})
    if not p.open then return end
    local x, y, w = p.content_x + 4, p.content_y + 2, p.w - 16
    if stash.problem then
        ui.text(stash.problem, x, y, {width = w, color = 0xFFFF8080, size = 12})
        return
    end
    if not world.can_change() then
        ui.text('The shared stash works in single player games only.', x, y, {width = w, color = 0xFFFFC080, size = 12})
        return
    end

    local items = stash.items()
    local scells = entry_cells(items, 'Click: take it into the backpack')
    local spages = pack(scells)
    ui.label('stash-title', ('In the stash: %d / %d'):format(#items, cfg.max_items), x, y, {color = ui.COLORS.accent})
    view.stash_page = pager('sp', x + w - 100, y - 1, view.stash_page, spages)
    y = y + 22
    local withdraw = grid('s', x, y, scells, view.stash_page)
    y = y + ROWS * CELL + 8

    if ui.button('mode-deposit', x, y, 150, 20, 'Your items', {enabled = view.mode ~= 'deposit'}) then view.mode = 'deposit' end
    if ui.button('mode-recent', x + 156, y, 196, 20, 'Recent withdrawals', {enabled = view.mode ~= 'recent'}) then view.mode = 'recent' end
    y = y + 28

    local deposit, restore
    if view.mode == 'deposit' then
        refresh_sources(false)
        local cells = {}
        for _, s in ipairs(view.sources) do
            local it = s.item
            cells[#cells + 1] = {
                id = 'b' .. it.id, src = s, w = it.w, h = it.h, icon = it, color = QUALITY_COLOR[it.quality],
                enabled = s.ok,
                tip = transfer.pretty_name(it) .. '\n' .. it.quality .. ', ' .. it.category .. ' (' .. s.where .. ')\n' ..
                    (s.ok and 'Click: put it into the stash' or s.why),
            }
        end
        local pages = pack(cells)
        ui.label('src-title', ('Backpack and chest: %d'):format(#cells), x, y, {color = ui.COLORS.accent})
        view.source_page = pager('xp', x + w - 100, y - 1, view.source_page, pages)
        y = y + 22
        deposit = grid('b', x, y, cells, view.source_page)
        y = y + ROWS * CELL
    else
        local cells = entry_cells(stash.recent(),
            'Click: back into the stash file. Use this if an older savegame lost the item; the copy in your\n' ..
            'character, if it still has one, stays where it is.')
        local pages = pack(cells)
        ui.label('rec-title', 'Withdrawn lately (click: back into the stash)', x, y, {color = ui.COLORS.accent})
        view.source_page = pager('rp', x + w - 100, y - 1, view.source_page, pages)
        y = y + 22
        restore = grid('r', x, y, cells, view.source_page)
        y = y + ROWS * CELL
    end

    if view.message and gear.time() < view.message_until then
        ui.text(view.message, x, y + 6, {width = w, size = 12, color = view.message_ok and 0xFF80FF80 or 0xFFFF8080})
    end

    -- Changes after drawing, so the grids above were consistent for the frame.
    if withdraw then
        local e = withdraw.entry
        local ok, where = transfer.withdraw(e)
        if ok then say(('%s taken into the %s'):format(e.name, where)) else say(where, false) end
        refresh_sources(true)
    elseif deposit then
        local s = deposit.src
        local ok, err = transfer.deposit(s.container, s.item)
        if ok then say(('%s put into the stash'):format(transfer.pretty_name(s.item))) else say(err, false) end
        refresh_sources(true)
    elseif restore then
        local e = restore.entry
        local ok, err = transfer.restore(e)
        if ok then say(e.name .. ' is in the stash again') else say(err, false) end
    end
end

local function open_button()
    local w = ui.window('UI_WND_CHEST')
    if not w or not (w.drawn or view.force_button) then return end
    local b = w.bounds
    local bx, by, bw, bh = b and b.x or w.x, b and b.y or w.y, b and b.w or w.width, b and b.h or w.height
    local key = gear.keys.binding('toggle')
    local hint = key ~= '' and (' (' .. key:upper() .. ')') or ''
    if ui.button('open', bx + bw - 130, by + bh + 4, 126, 20, 'Shared stash',
        {tooltip = 'Items shared between your heroes' .. hint}) then
        ui.show_panel('stash', not ui.panel_open('stash'))
    end
end

ui.show_panel('stash', false)

gear.keys.on('toggle', function()
    if gear.ui.state().mode == 'game' then ui.show_panel('stash', not ui.panel_open('stash')) end
end)

gear.on('draw', function(state)
    if state.mode ~= 'game' then return end
    if view.force_open then ui.show_panel('stash', true) end
    if state.exclusive then return end
    open_button()
    panel()
end)

M.say = say
M.refresh_sources = refresh_sources
if gear.auto and cfg.selftest then require('selftest')(M, stash, transfer) end
