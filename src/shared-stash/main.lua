-- Shared stash: a stash of items shared by the heroes of this player, kept in stash.json in this folder.
-- See README.md. The panel opens only from the "Shared stash" button that shows while the game's chest window is open,
-- and closes with it.
local cfg = gear.config
-- The settings (Mods screen) live in gear.settings; `cfg` (shared with transfer.lua) holds their current values.
for _, id in ipairs({'max_items', 'allow_special'}) do cfg[id] = gear.settings.get(id) end
gear.on('settings.changed', function(id, value) cfg[id] = value end)
if not cfg.enabled then return end

local ui, world = gear.ui, gear.world
local kind = require('kind')
-- stash.lua (the local file) loads when first used, never in Closed Net
local stash = setmetatable({}, {__index = function(_, k) return require('stash')[k] end})
local transfer = require('transfer')
local remote = require('remote')

-- The kind of game decides where the stash lives: stash.json (single player, LAN, Open Net) or the server (Closed Net,
-- remote.lua; never stash.json). stash.lua loads its file only when it is first used outside Closed Net.
local function closed() return kind.closed() end

local QUALITY_COLOR = {
    normal = 0xFFEFEFEF, magic = 0xFFA0A0FF, rare = 0xFFF0E040, unique = 0xFFC19A33, set = 0xFF15FF25,
}
local CELL = 32                 -- layout units a cell, as in the game's inventory
local COLS, ROWS = 11, 6        -- the size of one page of a grid

local view = {
    stash_page = 0, source_page = 0,
    sources = {}, sources_at = -10,
    message = nil, message_until = 0, message_ok = true,
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
            local r = ui.region(id .. c.id, px, py, pw, ph, {enabled = c.enabled})
            local hot = r.hover and c.enabled
            ui.rect(px + 1, py + 1, pw - 1, ph - 1, hot and 0x80506090 or 0x50203040)
            ui.item_icon(c.icon, px + 2, py + 2, pw - 3, ph - 3)
            ui.frame(px, py, pw + 1, ph + 1, hot and 0xFFFFFFFF or (c.color or 0xFF606060))
            if not c.enabled then ui.rect(px + 1, py + 1, pw - 1, ph - 1, 0xA0000000) end
            if r.clicked and c.enabled then clicked = c end
            if r.hover then view.hover = c end
        end
    end
    return clicked
end

-- A section header: the title at the left, [<]  n / m  [>] at the right (18 high). Returns the page.
local function header(id, x, y, w, title, color, page, pages)
    page = math.max(0, math.min(page, pages - 1))
    local t = ui.table(id, x, y - 1, w, {columns = {'*', 22, 48, 22}, spacing = {6, 0}, row_height = 18})
    t:row()
    t:label(1, title, {id = id .. '-title', color = color})
    if t:button(2, '<', {id = id .. '-prev', enabled = page > 0}) then page = page - 1 end
    t:label(3, ('%d / %d'):format(page + 1, pages), {id = id .. '-n', halign = 'center'})
    if t:button(4, '>', {id = id .. '-next', enabled = page < pages - 1}) then page = page + 1 end
    return page
end

local function entry_cells(list, hint)
    local cells = {}
    for _, e in ipairs(list) do
        cells[#cells + 1] = {
            id = 'e' .. (e.uid or e.id), entry = e, w = e.w or 1, h = e.h or 1, icon = entry_type(e),
            color = QUALITY_COLOR[e.quality], enabled = true,
            tipsrc = e, hint = hint,
        }
    end
    return cells
end

-- Whether the stash can be shown now; if not, a line that says why is drawn instead. In Closed Net the stash is the
-- server's (remote.lua), otherwise the file's (stash.lua). Returns ready, closed_net.
local function check_ready(x, y, w)
    local net = closed()
    if net then
        remote.refresh(false)
        local ok, why = remote.available()
        if not ok then
            ui.text('The shared stash is not available on this server.', x, y, {width = w, color = 0xFFFF8080, size = 13})
            ui.text(tostring(why), x, y + 22, {width = w, color = 0xFFC0C0C0, size = 12})
            return false
        end
    else
        -- a network game that is not (yet) known to be Closed Net: ask the server first (it may keep the stash), then the file
        if kind.mode() ~= 'single' and remote.probe() == 'wait' then
            ui.text('Asking the server about the shared stash ...', x, y, {width = w, color = 0xFFC0C0C0, size = 12})
            return false
        end
        if closed() then return false end                   -- the server said so meanwhile: the next frame draws the server's stash
        stash.ensure()
    end
    if not net and stash.problem then
        ui.text(stash.problem, x, y, {width = w, color = 0xFFFF8080, size = 12})
        return false
    end
    local can, network = gear.inv.can_change()
    view.net = network
    if not can then
        ui.text('The shared stash cannot change your inventory right now.', x, y, {width = w, color = 0xFFFFC080, size = 12})
        return false
    end
    return true, net
end

-- The cells of the backpack and chest grid (from refresh_sources).
local function source_cells()
    refresh_sources(false)
    local cells = {}
    for _, s in ipairs(view.sources) do
        local it = s.item
        cells[#cells + 1] = {
            id = 'b' .. it.id, src = s, w = it.w, h = it.h, icon = it, color = QUALITY_COLOR[it.quality],
            enabled = s.ok,
            tipsrc = it, hint = s.ok and ('Click: put it into the stash (from the ' .. s.where .. ')') or s.why,
        }
    end
    return cells
end

-- The game's own item tooltip for the item under the cursor, beside the panel (never under the cursor).
local function hover_tooltip()
    local src = view.hover.tipsrc
    if src.data then
        local e = src
        if not e.bytes then e.bytes = gear.inv.unhex(e.data) end
        src = e.bytes
    end
    if src then
        -- The popup's x / y are its top-left corner and its size is known from the tooltip shown before (a first
        -- guess at first); Sacred Gear places it clear of the cursor and inside the screen.
        local tx, ty = ui.tooltip_rect(view.tip_w or 340, view.tip_h or 200)
        local ok, a, b = ui.item_tooltip(src, tx, ty)
        view.tip_ok, view.tip_err = ok, (not ok) and a or nil
        if ok and a > 0 then view.tip_w, view.tip_h = a, b end
    end
end

-- A click on a stash cell takes the item out, a click on a backpack / chest cell puts it in.
local function withdraw_entry(e, net)
    if net then
        local ok, err = remote.withdraw(e)
        if ok then say('Asking the server ...') else say(err, false) end
    else
        local ok, where = transfer.withdraw(e)
        if ok then say(('%s taken into the %s'):format(e.name, where)) else say(where, false) end
    end
    refresh_sources(true)
end

local function deposit_source(s, net)
    if net then
        local ok, err = transfer.transferable(s.item)
        if ok then
            if not transfer.chest_open() then ok, err = nil, 'open a chest first'
            else ok, err = remote.deposit(s.container, s.item, transfer.entry_fields(s.item)) end
        end
        if ok then say('Asking the server ...') else say(err, false) end
    else
        local ok, err = transfer.deposit(s.container, s.item)
        if ok then say(('%s put into the stash'):format(transfer.pretty_name(s.item))) else say(err, false) end
    end
    refresh_sources(true)
end

-- The stash panel: the stash's grid on top, the backpack and chest below, a status line, the hovered item's tooltip.
local function panel()
    local p = ui.panel('stash', 'Shared stash', 646, 6, 372, 500, {closable = true})
    if not p.open then return end
    view.hover = nil
    local x, y, w = p.content_x + 4, p.content_y + 2, p.w - 16
    local ready, net = check_ready(x, y, w)
    if not ready then return end

    local items = net and remote.entries or stash.items()
    local scells = entry_cells(items, 'Click: take it into the backpack')
    local spages = pack(scells)
    view.stash_page = header('sp', x, y, w,
        ('In the stash: %d / %d'):format(#items, net and (remote.max or cfg.max_items) or cfg.max_items), ui.COLORS.accent,
        view.stash_page, spages)
    y = y + 22
    local withdraw = grid('s', x, y, scells, view.stash_page)
    y = y + ROWS * CELL + 8

    local cells = source_cells()
    local pages = pack(cells)
    view.source_page = header('xp', x, y, w, ('Backpack and chest: %d'):format(#cells), ui.COLORS.accent, view.source_page, pages)
    y = y + 22
    local deposit = grid('b', x, y, cells, view.source_page)
    y = y + ROWS * CELL

    if view.message and gear.time() < view.message_until then
        ui.text(view.message, x, y + 6, {width = w, size = 12, color = view.message_ok and 0xFF80FF80 or 0xFFFF8080})
    elseif view.hover then
        ui.text(view.hover.hint, x, y + 6, {width = w, size = 12, color = 0xFFC0C0C0})
    end
    if view.hover then hover_tooltip() end

    -- Changes after drawing, so the grids above were consistent for the frame.
    if withdraw then
        withdraw_entry(withdraw.entry, net)
    elseif deposit then
        deposit_source(deposit.src, net)
    end
end

-- The "Shared stash" button is a small panel of its own, so it is a layout panel like any other: Alt + Edit layout (the layout editor)
-- moves it and its place is kept in mods\gear_layout.json. Default: to the right of the chest and the inventory, below
-- the stash panel, clear of the game's buttons. It is clickable only while the chest window is open; in the layout
-- editor it is shown (greyed out) so it can be placed without a chest.
local function open_button(chest_is_open)
    local p = ui.panel('open', 'Shared stash', 646, 572, 160, 50, {closable = false})
    if not p.open then return end
    local open = ui.panel_open('stash')
    local enabled = chest_is_open and not ui.edit_mode()
    if ui.button('toggle', p.content_x + 2, p.content_y + 2, p.content_w - 4, 20, open and 'Close the stash' or 'Open the stash',
        {enabled = enabled, tooltip = enabled and 'Items shared between your heroes' or 'Open a chest to use the stash'}) then
        ui.show_panel('stash', not open)
    end
end

ui.show_panel('stash', false)
ui.show_panel('open', true)
if ui.persist_panel then ui.persist_panel('stash', false) end   -- it opens with a chest

gear.on('draw', function(state)
    if closed() then remote.tick() end
    -- The stash exists only while the game's chest window is open (it opens only near a chest and closes when the hero
    -- walks away): closed with it, in the menus, in cinematics, with a dead hero.
    local chest_is_open = state.mode == 'game' and not state.exclusive and transfer.chest_window_open()
    if not chest_is_open then
        ui.show_panel('stash', false)
        if state.mode == 'game' and not state.exclusive and ui.edit_mode() then open_button(false) end
        return
    end
    open_button(true)
    panel()
end)

M.say = say
remote.notify = say
gear.on('session.stop', function() remote.reset() end)
M.refresh_sources = refresh_sources
if gear.auto and cfg.selftest then require('selftest')(M, stash, transfer) end
