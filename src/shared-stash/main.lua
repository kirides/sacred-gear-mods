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

-- A cell of a grid as the document shows it: its box in the grid, the item model (a stash entry is an item type, a backpack / chest
-- item is the live item), the quality colour as the border.
local function css_color(argb)
    argb = argb or 0xFF606060
    return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
end

local function cell_model(c)
    local icon
    if type(c.icon) == 'table' then icon = 'gear:item/id/' .. tostring(c.icon.id) else icon = 'gear:item/' .. tostring(c.icon) end
    return {id = c.id, x = (c.cx * CELL) .. 'dp', y = (c.cy * CELL) .. 'dp', w = (c.cw * CELL + 1) .. 'dp', h = (c.ch * CELL + 1) .. 'dp',
        iw = (c.cw * CELL - 3) .. 'dp', ih = (c.ch * CELL - 3) .. 'dp', src = icon, color = css_color(c.color), enabled = c.enabled and true or false}
end

local function page_cells(cells, page)
    local out = {}
    for _, c in ipairs(cells) do
        if c.page == page + 1 then out[#out + 1] = cell_model(c) end
    end
    return out
end

local function clamp_page(page, pages) return math.max(0, math.min(page, pages - 1)) end

-- Whether the stash can be shown now; if not, a line that says why. In Closed Net the stash is the server's (remote.lua), otherwise the
-- file's (stash.lua). Returns ready, closed_net, notice, notice2, bad.
local function check_ready()
    local net = closed()
    if net then
        remote.refresh(false)
        local ok, why = remote.available()
        if not ok then return false, net, 'The shared stash is not available on this server.', tostring(why), true end
    else
        -- a network game that is not (yet) known to be Closed Net: ask the server first (it may keep the stash), then the file
        if kind.mode() ~= 'single' and remote.probe() == 'wait' then return false, net, 'Asking the server about the shared stash ...', '', false end
        if closed() then return false, net, '', '', false end                -- the server said so meanwhile: the next frame shows the server's stash
        stash.ensure()
    end
    if not net and stash.problem then return false, net, stash.problem, '', true end
    local can, network = gear.inv.can_change()
    view.net = network
    if not can then return false, net, 'The shared stash cannot change your inventory right now.', '', false end
    return true, net, '', '', false
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

-- The window and the "Shared stash" button are ui/stash.rml (the game theme). The button is a layout panel of its own (Alt + Edit layout
-- moves it); it is clickable only while the chest window is open, and shown (dimmed) in the layout editor so it can be placed without a chest.
local doc
local last = {}
local stash_open = false
local live = {}              -- cell id -> the cell (for the clicks and the hover)
local hovered                -- the cell the cursor rests on

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function snapshot(chest_is_open)
    local edit = ui.edit_mode()
    local m = {
        open_shown = chest_is_open or edit, open_enabled = chest_is_open and not edit,
        open_label = stash_open and 'Close the stash' or 'Open the stash',
        open_tip = (chest_is_open and not edit) and 'Items shared between your heroes' or 'Open a chest to use the stash',
        stash_open = chest_is_open and stash_open, ready = false, notice = '', notice2 = '', notice_bad = false,
        stash_title = '', sp_n = '', sp_prev = false, sp_next = false, scells = {},
        src_title = '', xp_n = '', xp_prev = false, xp_next = false, bcells = {},
        status = '', msg_ok = true,
    }
    live = {}
    if not m.stash_open then return m end
    local ready, net, notice, notice2, bad = check_ready()
    m.ready, m.notice, m.notice2, m.notice_bad = ready, notice, notice2, bad
    view.net_game = net
    if not ready then return m end
    local items = net and remote.entries or stash.items()
    local scells = entry_cells(items, 'Click: take it into the backpack')
    local spages = pack(scells)
    view.stash_page = clamp_page(view.stash_page, spages)
    m.stash_title = ('In the stash: %d / %d'):format(#items, net and (remote.max or cfg.max_items) or cfg.max_items)
    m.sp_n, m.sp_prev, m.sp_next = ('%d / %d'):format(view.stash_page + 1, spages), view.stash_page > 0, view.stash_page < spages - 1
    m.scells = page_cells(scells, view.stash_page)
    local cells = source_cells()
    local pages = pack(cells)
    view.source_page = clamp_page(view.source_page, pages)
    m.src_title = ('Backpack and chest: %d'):format(#cells)
    m.xp_n, m.xp_prev, m.xp_next = ('%d / %d'):format(view.source_page + 1, pages), view.source_page > 0, view.source_page < pages - 1
    m.bcells = page_cells(cells, view.source_page)
    for _, c in ipairs(scells) do live[c.id] = c end
    for _, c in ipairs(cells) do live[c.id] = c end
    if view.message and gear.time() < view.message_until then
        m.status, m.msg_ok = view.message, view.message_ok
    elseif hovered and live[hovered.id] then
        m.status = hovered.hint or ''
    end
    return m
end

local function load_doc(m)
    last = m
    local err
    doc, err = ui.rml.load('ui/stash.rml', {dp = true, model = m})
    if not doc then gear.log('shared stash: ui/stash.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('#toggle', function()
        if transfer.chest_window_open() and not ui.edit_mode() then stash_open = not stash_open end
    end)
    on('#sp-prev', function() view.stash_page = math.max(0, view.stash_page - 1) end)
    on('#sp-next', function() view.stash_page = view.stash_page + 1 end)
    on('#xp-prev', function() view.source_page = math.max(0, view.source_page - 1) end)
    on('#xp-next', function() view.source_page = view.source_page + 1 end)
    on('.cell', function(e)
        local c = live[tostring(e.current)]
        if not (c and c.enabled) then return end
        if c.entry then withdraw_entry(c.entry, view.net_game) elseif c.src then deposit_source(c.src, view.net_game) end
    end)
    doc:on('.cell', 'mouseover', function(e) hovered = live[tostring(e.current)] end)
    doc:on('.cell', 'mouseout', function() hovered = nil end)
end

gear.on('draw', function(state)
    if closed() then remote.tick() end
    -- The stash exists only while the game's chest window is open (it opens only near a chest and closes when the hero
    -- walks away): closed with it, in the menus, in cinematics, with a dead hero.
    local chest_is_open = state.mode == 'game' and not state.exclusive and transfer.chest_window_open()
    if not chest_is_open then
        stash_open, hovered = false, nil
        if not (state.mode == 'game' and not state.exclusive and ui.edit_mode()) then return end
    end
    local m = snapshot(chest_is_open)
    if not doc then load_doc(m) end
    if not doc then return end
    for k, v in pairs(m) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
    view.hover = m.stash_open and hovered and live[hovered.id] or nil
    if view.hover then hover_tooltip() end
end)

M.is_open = function() return stash_open end
M.rect = function(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end

M.say = say
remote.notify = say
gear.on('session.stop', function() remote.reset() end)
M.refresh_sources = refresh_sources
if gear.auto and cfg.selftest then require('selftest')(M, stash, transfer) end
