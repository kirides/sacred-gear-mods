-- Shared stash: a stash of items shared by the heroes of this player, kept in stash.json in this folder.
-- See README.md. The panel opens from a button below the chest window (and with config.hotkey).
local cfg = gear.config
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
local PAGE = 10
local ROW = 19

local view = {
    stash_page = 0, source_page = 0,
    mode = 'deposit',       -- 'deposit' or 'recent' (the lower list)
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

local function describe(e)
    return ('%s  %dx%d'):format(e.name, e.w or 1, e.h or 1)
end

local function tip(e)
    local parts = {e.quality or '?', e.category or '?'}
    if e.class and e.class ~= 'any' then parts[#parts + 1] = 'for ' .. e.class end
    if e.from then parts[#parts + 1] = 'from a ' .. tostring(e.from) end
    return table.concat(parts, ', ')
end

-- One clickable row; true when clicked.
local function row(id, x, y, w, text, color, tooltip, enabled)
    local r = ui.region(id, x, y, w, ROW - 1, {tooltip = tooltip, enabled = enabled})
    local bg = r.hover and enabled ~= false and 0x70404060 or 0x40000000
    ui.rect(x, y, w, ROW - 1, bg)
    ui.text(text, x + 4, y, {height = ROW - 1, valign = 'middle', color = enabled == false and 0xFF808080 or color,
        size = 12, width = w - 8})
    return r.clicked and enabled ~= false
end

local function pager(id, x, y, page, count)
    local pages = math.max(1, math.ceil(count / PAGE))
    page = math.min(page, pages - 1)
    if ui.button(id .. '-prev', x, y, 22, 18, '<', {enabled = page > 0}) then page = page - 1 end
    ui.label(id .. '-n', ('%d / %d'):format(page + 1, pages), x + 28, y, {height = 18, valign = 'middle'})
    if ui.button(id .. '-next', x + 76, y, 22, 18, '>', {enabled = page < pages - 1}) then page = page + 1 end
    return page
end

local function panel()
    local p = ui.panel('stash', 'Shared stash', 652, 6, 366, 590, {closable = true})
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
    ui.label('stash-title', ('In the stash: %d / %d'):format(#items, cfg.max_items), x, y, {color = ui.COLORS.accent})
    view.stash_page = pager('sp', x + w - 100, y - 1, view.stash_page, #items)
    y = y + 22
    local withdraw_entry
    for i = view.stash_page * PAGE + 1, math.min(#items, (view.stash_page + 1) * PAGE) do
        local e = items[i]
        if row('s' .. e.uid, x, y, w, describe(e), QUALITY_COLOR[e.quality] or 0xFFFFFFFF,
            tip(e) .. '\nClick: take it into the backpack') then
            withdraw_entry = e
        end
        y = y + ROW
    end
    y = y + (PAGE - math.min(PAGE, math.max(0, #items - view.stash_page * PAGE))) * ROW + 8

    if ui.button('mode-deposit', x, y, 150, 20, 'Your items', {enabled = view.mode ~= 'deposit'}) then view.mode = 'deposit' end
    if ui.button('mode-recent', x + 156, y, 190, 20, 'Recent withdrawals', {enabled = view.mode ~= 'recent'}) then view.mode = 'recent' end
    y = y + 28

    local deposit_row, restore_entry
    if view.mode == 'deposit' then
        refresh_sources(false)
        local list = view.sources
        ui.label('src-title', ('Backpack and chest: %d'):format(#list), x, y, {color = ui.COLORS.accent})
        view.source_page = pager('xp', x + w - 100, y - 1, view.source_page, #list)
        y = y + 22
        for i = view.source_page * PAGE + 1, math.min(#list, (view.source_page + 1) * PAGE) do
            local s = list[i]
            local it = s.item
            local label = ('%s  %dx%d  (%s)'):format(transfer.pretty_name(it), it.w, it.h, s.where)
            local t = s.ok and 'Click: put it into the stash' or s.why
            if row('b' .. it.id, x, y, w, label, QUALITY_COLOR[it.quality] or 0xFFFFFFFF, t, s.ok) then
                deposit_row = s
            end
            y = y + ROW
        end
        y = y + (PAGE - math.min(PAGE, math.max(0, #list - view.source_page * PAGE))) * ROW
    else
        local list = stash.recent()
        ui.label('rec-title', 'Withdrawn lately (click: back into the stash file)', x, y, {color = ui.COLORS.accent})
        y = y + 22
        for i = 1, math.min(#list, PAGE) do
            local e = list[i]
            if row('r' .. e.uid, x, y, w, describe(e), QUALITY_COLOR[e.quality] or 0xFFFFFFFF,
                tip(e) .. '\nUse this if an older savegame lost the item: it goes back to the stash, and the copy in\n' ..
                'your character, if it still has one, stays where it is.') then
                restore_entry = e
            end
            y = y + ROW
        end
        y = y + (PAGE - math.min(PAGE, #list)) * ROW
    end

    if view.message and gear.time() < view.message_until then
        ui.text(view.message, x, y + 6, {width = w, size = 12, color = view.message_ok and 0xFF80FF80 or 0xFFFF8080})
    end

    -- Changes after drawing, so the lists above were consistent for the frame.
    if withdraw_entry then
        local ok, where = transfer.withdraw(withdraw_entry)
        if ok then say(('%s taken into the %s'):format(withdraw_entry.name, where)) else say(where, false) end
        refresh_sources(true)
    elseif deposit_row then
        local ok, err = transfer.deposit(deposit_row.container, deposit_row.item)
        if ok then say(('%s put into the stash'):format(transfer.pretty_name(deposit_row.item))) else say(err, false) end
        refresh_sources(true)
    elseif restore_entry then
        local ok, err = transfer.restore(restore_entry)
        if ok then say(restore_entry.name .. ' is in the stash again') else say(err, false) end
    end
end

local function open_button()
    local w = ui.window('UI_WND_CHEST')
    if not w or not w.drawn then return end
    local b = w.bounds
    local bx, by, bw, bh = b and b.x or w.x, b and b.y or w.y, b and b.w or w.width, b and b.h or w.height
    local hint = cfg.hotkey ~= '' and (' (' .. cfg.hotkey:upper() .. ')') or ''
    if ui.button('open', bx + bw - 130, by + bh + 4, 126, 20, 'Shared stash',
        {tooltip = 'Items shared between your heroes' .. hint}) then
        ui.show_panel('stash', not ui.panel_open('stash'))
    end
end

ui.show_panel('stash', false)

gear.on('draw', function(state)
    if state.mode ~= 'game' then return end
    if view.force_open then ui.show_panel('stash', true) end
    if cfg.hotkey ~= '' and ui.key_pressed(cfg.hotkey) then
        ui.show_panel('stash', not ui.panel_open('stash'))
    end
    if state.exclusive then return end
    open_button()
    panel()
end)

M.say = say
M.refresh_sources = refresh_sources
if gear.auto and cfg.selftest then require('selftest')(M, stash, transfer) end
