-- The auction house panel: Browse, Sell, My auctions, Mailbox. Opened from the "Auction house" button that shows
-- while the game's chest window is open; closes with it. Everything is a widget (buttons, dropdowns, regions), so
-- the controller's D-pad reaches all of it; text fields have a "Kbd" button for an on-screen keyboard.
local ui, inv, world = gear.ui, gear.inv, gear.world

local M = {}

local QUALITY_COLOR = {
    normal = 0xFFEFEFEF, magic = 0xFFA0A0FF, rare = 0xFFF0E040, unique = 0xFFC19A33, set = 0xFF15FF25,
}
local DIM, GOOD, BAD = 0xFFA8A8A8, 0xFF80FF80, 0xFFFF8080

local CATEGORIES = {
    {'', 'Any type'}, {'weapon', 'Weapons'}, {'armor', 'Armour'}, {'shield', 'Shields'}, {'jewelry', 'Jewellery'},
    {'rune', 'Runes'}, {'potion', 'Potions'}, {'scroll', 'Scrolls'}, {'special', 'Special'}, {'other', 'Other'},
}
local QUALITIES = {
    {'', 'Any quality'}, {'magic', 'Magic or better'}, {'rare', 'Rare or better'}, {'unique', 'Unique or better'},
    {'set', 'Set items'},
}
local LEVELS = {
    {nil, nil, 'Any level'}, {1, 10, 'Level 1-10'}, {11, 20, 'Level 11-20'}, {21, 30, 'Level 21-30'},
    {31, 45, 'Level 31-45'}, {46, 60, 'Level 46-60'}, {61, 80, 'Level 61-80'}, {81, 999, 'Level 81+'},
}
local PRICES = {
    {nil, nil, 'Any price'}, {nil, 1000, 'Up to 1,000'}, {1000, 10000, '1,000 - 10,000'},
    {10000, 100000, '10,000 - 100,000'}, {100000, 1000000, '100,000 - 1 M'}, {1000000, nil, 'Over 1 M'},
}
local SORTS = {
    {'price', 'Price'}, {'ppl', 'Price per level'}, {'ends', 'Time left'}, {'newest', 'Newest'}, {'name', 'Name'},
    {'level', 'Level'}, {'quality', 'Quality'},
}

local function labels(list, i)
    local t = {}
    for k, v in ipairs(list) do t[k] = v[i or 2] end
    return t
end

local function gold(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (n < 0 and '-' or '') .. out
end
M.gold = gold

local function left(ends, now)
    local s = math.max(0, (ends or 0) - (now or os.time()))
    if s >= 86400 then return ('%dd %dh'):format(math.floor(s / 86400), math.floor((s % 86400) / 3600)) end
    if s >= 3600 then return ('%dh %dm'):format(math.floor(s / 3600), math.floor((s % 3600) / 60)) end
    return ('%dm'):format(math.max(1, math.floor(s / 60)))
end

---------------------------------------------------------------------------------------------------------------
-- text fields (keyboard, and an on-screen keyboard for the controller)
---------------------------------------------------------------------------------------------------------------
local KEYS = {}
for c = string.byte('a'), string.byte('z') do KEYS[#KEYS + 1] = {string.char(c), string.char(c)} end
for c = string.byte('0'), string.byte('9') do KEYS[#KEYS + 1] = {string.char(c), string.char(c)} end
for _, k in ipairs({{'space', ' '}, {'minus', '-'}, {'period', '.'}, {'quote', "'"}}) do KEYS[#KEYS + 1] = k end
local OSK_ROWS = {'1234567890', 'qwertyuiop', 'asdfghjkl', "zxcvbnm-'"}

local edit = {id = nil, text = '', back_at = nil}
local osk = nil   -- {id, text, digits, max, apply}

local function typing(digits, max)
    local text = edit.text
    for _, k in ipairs(KEYS) do
        if ui.key_pressed(k[1]) and #text < max and (not digits or k[2]:match('%d')) then text = text .. k[2] end
    end
    if ui.key_down('backspace') then
        local now = gear.time()
        if not edit.back_at then
            edit.back_at = now
            text = text:sub(1, -2)
        elseif now - edit.back_at > 0.45 then
            edit.back_at = now - 0.4
            text = text:sub(1, -2)
        end
    else
        edit.back_at = nil
    end
    edit.text = text
end

-- A one-line text field: returns its text. Click it to type (the game gets no keys meanwhile), Enter or a click
-- elsewhere ends typing; "Kbd" opens the on-screen keyboard.
local function field(id, x, y, w, value, opts)
    opts = opts or {}
    local max = opts.max or 40
    local focused = edit.id == id
    local r = ui.region(id, x, y, w - 36, 20)
    ui.rect(x, y, w - 36, 20, focused and 0xF0202030 or 0xC0101018)
    ui.frame(x, y, w - 36, 20, (focused or r.hover) and 0xFFC8A060 or 0xFF606060)
    if ui.button(id .. '#kbd', x + w - 34, y, 34, 20, 'Kbd', {tooltip = 'Type with an on-screen keyboard'}) then
        osk = {id = id, text = value, digits = opts.digits, max = max}
        edit.id = nil
    end
    if r.clicked and not focused then
        edit.id, edit.text, focused = id, value, true
    elseif not r.hover and ui.mouse_clicked and ui.mouse_clicked() and focused then
        edit.id, focused = nil, false
    end
    local shown = focused and edit.text or value
    if shown == '' and not focused and opts.hint then
        ui.text(opts.hint, x + 5, y, {height = 20, valign = 'middle', color = 0xFF707070, size = 12})
    else
        local blink = focused and math.floor(gear.time() * 2) % 2 == 0 and '|' or ''
        ui.text(shown .. blink, x + 5, y, {height = 20, valign = 'middle', size = 12})
    end
    if focused then
        if ui.key_pressed('enter') or ui.key_pressed('tab') or ui.key_pressed('escape') then
            edit.id = nil
        else
            typing(opts.digits, max)
        end
        value = edit.text
    end
    if osk and osk.id == id and osk.result then
        value = osk.result
        osk = nil
    end
    return value
end

local function draw_osk()
    if not osk then return false end
    local p = ui.panel('osk', 'Type', 300, 260, 460, 210, {closable = true})
    if not p.open then
        osk = nil
        ui.show_panel('osk', true)   -- for the next keyboard
        return false
    end
    local x, y = p.content_x + 4, p.content_y + 2
    ui.rect(x, y, p.content_w - 8, 22, 0xF0202030)
    ui.text(osk.text .. '|', x + 6, y, {height = 22, valign = 'middle'})
    y = y + 28
    for r, row in ipairs(OSK_ROWS) do
        for i = 1, #row do
            local ch = row:sub(i, i)
            local enabled = not osk.digits or ch:match('%d')
            if ui.button('osk' .. r .. '_' .. i, x + (i - 1) * 40 + (r - 1) * 10, y, 36, 24, ch:upper(),
                {enabled = enabled and true or false}) and #osk.text < osk.max then
                osk.text = osk.text .. ch
            end
        end
        y = y + 28
    end
    if ui.button('osk-space', x, y, 120, 24, 'Space', {enabled = not osk.digits}) and #osk.text < osk.max then
        osk.text = osk.text .. ' '
    end
    if ui.button('osk-back', x + 128, y, 110, 24, 'Backspace') then osk.text = osk.text:sub(1, -2) end
    if ui.button('osk-clear', x + 246, y, 80, 24, 'Clear') then osk.text = '' end
    if ui.button('osk-done', x + 334, y, 100, 24, 'Done') then osk.result = osk.text end
    return true
end

---------------------------------------------------------------------------------------------------------------
-- shared bits
---------------------------------------------------------------------------------------------------------------
local view = {
    tab = 'browse',
    q = {text = '', cat = 1, qual = 1, level = 1, price = 1, mine_class = false}, sort = 1, desc = false, page = 1,
    asked = nil, sell = {page = 0, sel = nil, price = '', days = 2}, gold_amount = '',
    msg = nil, msg_ok = true, msg_until = 0, hover = nil, busy = false,
}
M.view = view

local function say(text, ok)
    view.msg, view.msg_ok, view.msg_until = text, ok ~= false, gear.time() + 7
end
M.say = say

-- The game's own tooltip for hex item data or a live item, beside the panel.
local function tooltip(src)
    if not src then return end
    if type(src) == 'string' then src = inv.unhex(src) end
    if not src then return end
    local tx, ty = ui.tooltip_rect(view.tip_w or 340, view.tip_h or 200)
    local ok, a, b = ui.item_tooltip(src, tx, ty)
    if ok and a and a > 0 then view.tip_w, view.tip_h = a, b end
end

local function icon(type_or_item, x, y, w, h)
    if type_or_item then ui.item_icon(type_or_item, x, y, w, h) end
end

---------------------------------------------------------------------------------------------------------------
-- Browse
---------------------------------------------------------------------------------------------------------------
local function query()
    local q = view.q
    local lv, pr = LEVELS[q.level], PRICES[q.price]
    local hero = world.hero()
    local quality, min_quality = nil, nil
    local qv = QUALITIES[q.qual][1]
    if qv == 'set' then quality = 'set' elseif qv ~= '' then min_quality = qv end
    return {
        text = q.text, category = CATEGORIES[q.cat][1], quality = quality, min_quality = min_quality,
        class = q.mine_class and hero and hero:class() or nil,
        min_level = lv[1], max_level = lv[2], min_price = pr[1], max_price = pr[2],
    }
end

local function search(client, page)
    view.page = page or 1
    client:browse(query(), SORTS[view.sort][1], view.desc, view.page)
end
M.search = search

local function browse(client, x, y, w, h)
    local q = view.q
    local changed = false
    local text = field('ah-q', x, y, 250, q.text, {hint = 'Search name or any tooltip line', max = 40})
    if text ~= q.text then q.text = text end
    local c, i
    c, i = ui.dropdown('ah-cat', x + 258, y, 130, labels(CATEGORIES), q.cat)
    if c then q.cat, changed = i, true end
    c, i = ui.dropdown('ah-qual', x + 394, y, w - 394, labels(QUALITIES), q.qual)
    if c then q.qual, changed = i, true end
    y = y + 26
    c, i = ui.dropdown('ah-lvl', x, y, 120, labels(LEVELS, 3), q.level)
    if c then q.level, changed = i, true end
    c, i = ui.dropdown('ah-price', x + 126, y, 130, labels(PRICES, 3), q.price)
    if c then q.price, changed = i, true end
    local cc, cv = ui.checkbox('ah-class', x + 264, y + 2, 'My class', q.mine_class)
    if cc then q.mine_class, changed = cv, true end
    c, i = ui.dropdown('ah-sort', x + 352, y, 120, labels(SORTS), view.sort)
    if c then view.sort, changed = i, true end
    if ui.button('ah-desc', x + 478, y, w - 478, 20, view.desc and 'High-low' or 'Low-high',
        {tooltip = 'Sort order'}) then view.desc, changed = not view.desc, true end
    y = y + 26
    if ui.button('ah-search', x, y, 90, 20, 'Search') or changed or (edit.id == nil and view.last_text ~= q.text) then
        view.last_text = q.text
        search(client, 1)
    end
    local page = client.page
    if page then
        ui.label('ah-count', ('%d found'):format(page.total or 0), x + 100, y, {height = 20, valign = 'middle', color = DIM})
        if ui.button('ah-prev', x + w - 104, y, 24, 20, '<', {enabled = page.page > 1}) then search(client, page.page - 1) end
        ui.label('ah-pg', ('%d / %d'):format(page.page, page.pages), x + w - 76, y, {height = 20, valign = 'middle'})
        if ui.button('ah-next', x + w - 24, y, 24, 20, '>', {enabled = page.page < page.pages}) then search(client, page.page + 1) end
    end
    y = y + 26
    if not page then
        ui.text(client:online() and 'Searching...' or 'Waiting for the market...', x, y, {color = DIM})
        return
    end
    local now = client.info and client.info.now and (client.info.now + (gear.time() - client.info_at)) or os.time()
    local row_h = 36
    local me = client:me().key
    for n, r in ipairs(page.rows) do
        local ry = y + (n - 1) * row_h
        local reg = ui.region('ah-row' .. r.id, x, ry, w - 96, row_h - 2)
        ui.rect(x, ry, w, row_h - 2, reg.hover and 0x70405070 or (n % 2 == 0 and 0x40202830 or 0x40101820))
        icon(r.type, x + 2, ry + 1, 32, 32)
        ui.text(r.name or '?', x + 40, ry + 1, {color = QUALITY_COLOR[r.quality] or 0xFFFFFFFF, size = 13, width = 230})
        local classes = (r.classes and #r.classes > 0) and table.concat(r.classes, ', ') or 'all classes'
        ui.text(('Lv %d  -  %s  -  %s  -  %s'):format(r.level or 0, r.seller or '?', left(r.ends, now), classes),
            x + 40, ry + 18, {size = 11, color = DIM, width = w - 200})
        ui.text(gold(r.price), x + w - 200, ry + 1, {size = 13, width = 100, align = 'right', color = 0xFFFFE080})
        if r.median then
            ui.text(('recent %s'):format(gold(r.median)), x + w - 200, ry + 18, {size = 11, width = 100, align = 'right', color = DIM})
        end
        local mine = r.seller_key == me
        if ui.button('ah-buy' .. r.id, x + w - 90, ry + 6, 88, 22, mine and 'Yours' or 'Buy', {enabled = not mine and not view.busy,
            tooltip = mine and 'Your own listing' or ('Buy for %s gold (taken from your wallet; what it lacks from the gold you carry)'):format(gold(r.price))}) then
            view.busy = true
            client:buy(r, function(ok, err)
                view.busy = false
                if ok then
                    say(('Bought %s. It is in your mailbox.'):format(r.name or 'the item'))
                    search(client, view.page)
                    client:refresh_mail()
                else
                    say(err or 'not bought', false)
                    search(client, view.page)
                end
            end)
        end
        if reg.hover then view.hover = {listing = r.id} end
    end
    if #page.rows == 0 then ui.text('Nothing for sale matches.', x, y, {color = DIM}) end
end

---------------------------------------------------------------------------------------------------------------
-- Sell
---------------------------------------------------------------------------------------------------------------
local function sellable(it, allow_special)
    if it.gold then return false, 'gold cannot be sold here' end
    if it.quest then return false, 'quest items cannot be sold' end
    if it.category == 'special' and not allow_special then return false, 'special items are not sold' end
    return true
end
M.sellable = sellable

-- What the market lists about an item: its display name and level from the game's tooltip text.
function M.meta_of(it, bytes)
    local text = ''
    local ok, t = pcall(ui.item_tooltip_text, bytes or it.id)
    if ok and type(t) == 'string' then text = t
    elseif ok and type(t) == 'table' then text = table.concat(t, '\n') end
    local name
    for line in text:gmatch('[^\n]+') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then name = line break end
    end
    if not name then name = (it.type_name or ('item ' .. tostring(it.type))):gsub('%.%w+$', ''):gsub('_', ' ') end
    local level = tonumber(text:lower():match('level[^%d\n]*(%d+)')) or 0
    return {name = name, level = level, quality = it.quality, category = it.category, w = it.w, h = it.h,
        classes = it.classes or {}, type = it.type, text = text:sub(1, 2000)}
end

local CELL, COLS, ROWS = 32, 11, 5

local function sources()
    local list = {}
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then
            for _, it in ipairs(c:items()) do list[#list + 1] = {item = it, container = c, where = which} end
        end
    end
    return list
end

local function pack(cells)
    local pages = {}
    local function fits(g, x, y, w, h)
        for yy = y, y + h - 1 do for xx = x, x + w - 1 do if g[yy * COLS + xx] then return false end end end
        return true
    end
    for _, c in ipairs(cells) do
        local w, h = math.min(c.w, COLS), math.min(c.h, ROWS)
        local p, placed = 1, false
        while not placed do
            local g = pages[p]
            if not g then g = {} pages[p] = g end
            for y = 0, ROWS - h do
                for x = 0, COLS - w do
                    if fits(g, x, y, w, h) then
                        for yy = y, y + h - 1 do for xx = x, x + w - 1 do g[yy * COLS + xx] = true end end
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

local function sell(client, cfg, x, y, w, h)
    local s = view.sell
    if not view.src_at or gear.time() - view.src_at > 0.3 then
        view.src_at = gear.time()
        local cells = {}
        for _, src in ipairs(sources()) do
            local it = src.item
            local ok, why = sellable(it, cfg.allow_special)
            cells[#cells + 1] = {id = it.id, src = src, w = it.w, h = it.h, ok = ok, why = why}
        end
        view.src_pages = pack(cells)
        view.src_cells = cells
    end
    local cells = view.src_cells
    s.page = math.max(0, math.min(s.page, view.src_pages - 1))
    ui.label('ah-src', 'Your backpack and chest: pick an item', x, y, {height = 20, valign = 'middle', color = ui.COLORS.accent})
    if ui.button('ah-sp', x + w - 104, y, 24, 20, '<', {enabled = s.page > 0}) then s.page = s.page - 1 end
    ui.label('ah-spn', ('%d / %d'):format(s.page + 1, view.src_pages), x + w - 76, y, {height = 20, valign = 'middle'})
    if ui.button('ah-sn', x + w - 24, y, 24, 20, '>', {enabled = s.page < view.src_pages - 1}) then s.page = s.page + 1 end
    y = y + 24
    local gx = x + (w - COLS * CELL) / 2
    ui.rect(gx, y, COLS * CELL, ROWS * CELL, 0x60000000)
    for cx = 0, COLS do ui.rect(gx + cx * CELL, y, 1, ROWS * CELL, 0x30FFFFFF) end
    for cy = 0, ROWS do ui.rect(gx, y + cy * CELL, COLS * CELL, 1, 0x30FFFFFF) end
    for _, c in ipairs(cells) do
        if c.page == s.page + 1 then
            local px, py, pw, ph = gx + c.cx * CELL, y + c.cy * CELL, c.cw * CELL, c.ch * CELL
            local r = ui.region('ah-c' .. c.id, px, py, pw, ph, {enabled = c.ok})
            local selected = s.sel and s.sel.id == c.id
            ui.rect(px + 1, py + 1, pw - 1, ph - 1, (selected and 0xA0806020) or (r.hover and c.ok and 0x80506090) or 0x50203040)
            icon(c.src.item, px + 2, py + 2, pw - 3, ph - 3)
            ui.frame(px, py, pw + 1, ph + 1, selected and 0xFFFFE080 or (QUALITY_COLOR[c.src.item.quality] or 0xFF606060))
            if not c.ok then ui.rect(px + 1, py + 1, pw - 1, ph - 1, 0xA0000000) end
            if r.clicked and c.ok then
                s.sel = c
                s.meta = nil
                local hist = client:fetch_history(c.src.item.type)
                if hist and hist.median and s.price == '' then s.price = tostring(hist.median) end
            end
            if r.hover then view.hover = {item = c.src.item, why = c.why} end
        end
    end
    y = y + ROWS * CELL + 8

    local sel = s.sel
    if sel and not inv.size(sel.id) then s.sel, sel = nil, nil end   -- gone (moved, sold)
    if not sel then
        ui.text('Pick the item to sell above.', x, y, {color = DIM})
        return
    end
    local it = sel.src.item
    s.meta = s.meta or M.meta_of(it)
    icon(it, x, y, 32, 32)
    ui.text(s.meta.name, x + 40, y, {color = QUALITY_COLOR[it.quality] or 0xFFFFFFFF, size = 13, width = w - 40})
    local hist = client:fetch_history(it.type)
    local htext = 'no recent sales of this kind'
    if hist and hist.median then htext = ('recent sales: median %s gold (%d)'):format(gold(hist.median), #(hist.sales or {})) end
    ui.text(('Level %d  -  from your %s  -  %s'):format(s.meta.level or 0, sel.src.where, htext), x + 40, y + 17,
        {size = 11, color = DIM, width = w - 40})
    y = y + 40
    ui.label('ah-pl', 'Price', x, y, {height = 20, valign = 'middle'})
    s.price = field('ah-price-in', x + 50, y, 170, s.price, {digits = true, max = 10, hint = 'gold'})
    local price = tonumber(s.price) or 0
    local bx = x + 228
    for _, step in ipairs({-1000, -100, 100, 1000, 10000}) do
        local label = (step > 0 and '+' or '') .. (math.abs(step) >= 1000 and ((math.floor(step / 1000)) .. 'k') or tostring(step))
        if ui.button('ah-st' .. step, bx, y, 44, 20, label) then
            price = math.max(0, price + step)
            s.price = tostring(price)
        end
        bx = bx + 48
    end
    y = y + 26
    local rules = client.info and client.info.rules or {durations = {1, 3, 7}, fee_per_day = 0, sale_cut = 0}
    local durs = {}
    for i, d in ipairs(rules.durations) do durs[i] = d == 1 and '1 day' or (d .. ' days') end
    s.days = math.max(1, math.min(s.days, #durs))
    local dc, di = ui.dropdown('ah-days', x + 50, y, 120, durs, s.days)
    if dc then s.days = di end
    ui.label('ah-dl', 'For', x, y, {height = 20, valign = 'middle'})
    local days = rules.durations[s.days] or 1
    local fee = 0
    if (rules.fee_per_day or 0) > 0 and price > 0 then
        fee = math.max(rules.fee_min or 0, math.floor(price * rules.fee_per_day / 100 * days))
    end
    local net = price - math.floor(price * (rules.sale_cut or 0) / 100)
    ui.text(('Fee %s now  -  you get %s if it sells (%s%% cut)'):format(gold(fee), gold(net), tostring(rules.sale_cut or 0)),
        x + 178, y, {height = 20, valign = 'middle', size = 12, color = DIM})
    y = y + 28
    local ok = price >= (rules.price_min or 1) and price <= (rules.price_max or 2e9) and not view.busy and client:online()
    if ui.button('ah-list', x, y, 160, 24, 'Put up for sale', {enabled = ok,
        tooltip = 'The item leaves your inventory now; it comes back by the mailbox if it does not sell'}) then
        view.busy = true
        local name = s.meta.name
        client:sell(sel.src.container, it, s.meta, price, days, function(done, err)
            view.busy = false
            if done then say(('%s is for sale for %s gold.'):format(name, gold(price))) else say(err or 'not listed', false) end
            view.src_at = nil
        end)
        s.sel, s.meta, s.price = nil, nil, ''
        view.src_at = nil
    end
end

---------------------------------------------------------------------------------------------------------------
-- My auctions
---------------------------------------------------------------------------------------------------------------
local function mine(client, x, y, w)
    if not view.mine_asked or gear.time() - view.mine_asked > 5 then
        view.mine_asked = gear.time()
        client:refresh_mine()
    end
    local list = client.mine and client.mine.rows or {}
    ui.label('ah-mt', ('Your listings: %d'):format(#list), x, y, {height = 20, valign = 'middle', color = ui.COLORS.accent})
    y = y + 26
    local now = client.info and client.info.now and (client.info.now + (gear.time() - client.info_at)) or os.time()
    for n, r in ipairs(list) do
        if n > 12 then
            ui.text(('and %d more'):format(#list - 12), x, y, {color = DIM})
            break
        end
        local reg = ui.region('ah-m' .. r.id, x, y, w - 96, 34)
        ui.rect(x, y, w, 34, reg.hover and 0x70405070 or 0x40202830)
        icon(r.type, x + 2, y + 1, 32, 32)
        ui.text(r.name or '?', x + 40, y + 1, {color = QUALITY_COLOR[r.quality] or 0xFFFFFFFF, size = 13, width = 260})
        ui.text(('%s gold  -  %s left'):format(gold(r.price), left(r.ends, now)), x + 40, y + 18, {size = 11, color = DIM})
        if ui.button('ah-cancel' .. r.id, x + w - 90, y + 6, 88, 22, 'Cancel', {enabled = not view.busy,
            tooltip = 'Take it off the market; it goes to your mailbox (the fee is not returned)'}) then
            view.busy = true
            client:cancel(r.id, function(ok, err)
                view.busy = false
                say(ok and ((r.name or 'It') .. ' is back in your mailbox.') or (err or 'not cancelled'), ok)
                view.mine_asked = nil
                client:refresh_mail()
            end)
        end
        if reg.hover then view.hover = {listing = r.id} end
        y = y + 36
    end
end

---------------------------------------------------------------------------------------------------------------
-- Mailbox and wallet
---------------------------------------------------------------------------------------------------------------
local REASON = {sold = 'sold', expired = 'not sold', cancelled = 'cancelled', bought = 'bought', withdrawn = 'gold'}

local function mailbox(client, x, y, w)
    if not view.mail_asked or gear.time() - view.mail_asked > 5 then
        view.mail_asked = gear.time()
        client:refresh_mail()
    end
    local hero = world.hero()
    ui.label('ah-w', ('Wallet: %s gold   (you carry %s)'):format(gold(client:wallet()), gold(hero and hero:gold() or 0)), x, y,
        {height = 20, valign = 'middle', color = 0xFFFFE080})
    y = y + 24
    view.gold_amount = field('ah-gold', x, y, 150, view.gold_amount, {digits = true, max = 10, hint = 'amount'})
    local amount = tonumber(view.gold_amount) or 0
    if ui.button('ah-dep', x + 158, y, 90, 20, 'Deposit', {enabled = amount > 0 and not view.busy and client:online(),
        tooltip = 'Gold you carry into the wallet (buying and fees use it)'}) then
        view.busy = true
        client:deposit(amount, function(ok, err)
            view.busy = false
            say(ok and (gold(amount) .. ' gold deposited.') or (err or 'not deposited'), ok)
        end)
        view.gold_amount = ''
    end
    if ui.button('ah-wd', x + 254, y, 90, 20, 'Withdraw', {enabled = amount > 0 and not view.busy and client:online(),
        tooltip = 'Gold from the wallet to your hero'}) then
        view.busy = true
        client:withdraw(amount, function(ok, err)
            view.busy = false
            if not ok then say(err or 'not taken out', false) end
        end)
        view.gold_amount = ''
    end
    if ui.button('ah-wall', x + 350, y, 90, 20, 'All', {enabled = client:wallet() > 0, tooltip = 'The whole wallet'}) then
        view.gold_amount = tostring(client:wallet())
    end
    y = y + 30
    local entries = client.mail and client.mail.entries or {}
    local returns = client:returns()
    ui.label('ah-mb', ('Mailbox: %d'):format(#entries + #returns), x, y, {height = 20, valign = 'middle', color = ui.COLORS.accent})
    if ui.button('ah-call', x + w - 110, y, 110, 20, 'Collect all', {enabled = (#entries > 0) and not view.busy}) then
        for _, m in ipairs(entries) do client:collect(m.mid) end
    end
    y = y + 26
    for _, e in ipairs(returns) do
        ui.rect(x, y, w, 34, 0x40302020)
        icon(inv.unhex(e.data), x + 2, y + 1, 32, 32)
        ui.text((e.meta and e.meta.name or 'Item') .. '  (sale refused, kept here)', x + 40, y + 8, {size = 12, width = w - 140})
        if ui.button('ah-ret' .. e.rid, x + w - 90, y + 6, 88, 22, 'Take') then
            if not client:take_return(e) then say('no room in the backpack or the chest', false) end
        end
        y = y + 36
    end
    for n, m in ipairs(entries) do
        if n > 10 then
            ui.text(('and %d more'):format(#entries - 10), x, y, {color = DIM})
            break
        end
        ui.rect(x, y, w, 34, 0x40202830)
        if m.kind == 'gold' then
            ui.text(('%s gold'):format(gold(m.gold)), x + 40, y + 8, {color = 0xFFFFE080, size = 13})
        else
            icon(m.type, x + 2, y + 1, 32, 32)
            ui.text(m.name or 'Item', x + 40, y + 1, {color = QUALITY_COLOR[m.quality] or 0xFFFFFFFF, size = 13, width = w - 140})
            ui.text(REASON[m.reason] or m.reason or '', x + 40, y + 18, {size = 11, color = DIM})
        end
        if ui.button('ah-col' .. m.mid, x + w - 90, y + 6, 88, 22, 'Collect', {enabled = not view.busy}) then
            client:collect(m.mid, function(ok, err)
                if not ok and err then say(err, false) end
                view.mail_asked = nil
            end)
        end
        y = y + 36
    end
    ui.text('Save the game after collecting: an item collected and not saved is lost if the game ends.', x, y + 4,
        {size = 11, color = DIM, width = w})
end

---------------------------------------------------------------------------------------------------------------
-- the panel
---------------------------------------------------------------------------------------------------------------
local TABS = {{'browse', 'Browse'}, {'sell', 'Sell'}, {'mine', 'My auctions'}, {'mail', 'Mailbox'}}

function M.panel(client, cfg)
    local p = ui.panel('market', 'Auction house', 250, 16, 580, 590, {closable = true})
    if not p.open then
        edit.id = nil
        return
    end
    view.hover = nil
    local x, y, w = p.content_x + 4, p.content_y + 2, p.content_w - 8
    local tx = x
    for _, t in ipairs(TABS) do
        local on = view.tab == t[1]
        if ui.button('ah-tab-' .. t[1], tx, y, 120, 22, t[2], {color = on and ui.COLORS.accent or nil}) then
            view.tab = t[1]
            edit.id = nil
            if t[1] == 'browse' then search(client, view.page) end
            if t[1] == 'mail' then view.mail_asked = nil end
            if t[1] == 'mine' then view.mine_asked = nil end
        end
        tx = tx + 126
    end
    y = y + 30
    local status, scolor
    if client.info and client.info.problem then status, scolor = client.info.problem, BAD
    elseif not client:online() then status, scolor = 'The market is not answering (the host is not in the game?)', BAD
    end
    if status then
        ui.text(status, x, y, {size = 12, color = scolor, width = w})
        y = y + 18
    end
    local body_h = p.content_h - (y - p.content_y) - 44
    if view.tab == 'browse' then browse(client, x, y, w, body_h)
    elseif view.tab == 'sell' then sell(client, cfg, x, y, w, body_h)
    elseif view.tab == 'mine' then mine(client, x, y, w)
    else mailbox(client, x, y, w) end

    -- the footer: the last message, or what the item under the cursor is
    local fy = p.content_y + p.content_h - 40
    ui.rect(x, fy - 4, w, 1, 0x40FFFFFF)
    local note
    for i = #client.notes, 1, -1 do
        local n = client.notes[i]
        if gear.time() < n['until'] then note = n break end
    end
    if view.msg and gear.time() < view.msg_until then
        ui.text(view.msg, x, fy, {width = w, size = 12, color = view.msg_ok and GOOD or BAD})
    elseif note then
        ui.text(note.text, x, fy, {width = w, size = 12, color = note.ok and GOOD or BAD})
    elseif view.hover and view.hover.why then
        ui.text(view.hover.why, x, fy, {width = w, size = 12, color = DIM})
    else
        ui.text(('Wallet %s gold'):format(gold(client:wallet())), x, fy, {width = w, size = 12, color = DIM})
    end

    if view.hover then
        if view.hover.listing then tooltip(client:fetch_item(view.hover.listing))
        elseif view.hover.item then tooltip(view.hover.item) end
    end
    -- capture keys while typing, so the game does not act on them
    if ui.capture_keys then ui.capture_keys(edit.id ~= nil) end
    draw_osk()
end

function M.close()
    edit.id = nil
    osk = nil
    if ui.capture_keys then ui.capture_keys(false) end
    ui.show_panel('market', false)
end

-- The "Auction house" button: a small layout panel of its own beside the shared stash's button.
function M.open_button(chest_is_open, client)
    local p = ui.panel('open', 'Auction house', 812, 572, 160, 50, {closable = false})
    if not p.open then return end
    local open = ui.panel_open('market')
    local enabled = chest_is_open and not ui.edit_mode()
    if ui.button('ah-toggle', p.content_x + 2, p.content_y + 2, p.content_w - 4, 20, open and 'Close' or 'Open the market',
        {enabled = enabled, tooltip = enabled and 'Buy and sell items with the other players' or 'Open a chest to use the market'}) then
        if open then M.close() else
            ui.show_panel('market', true)
            search(client, 1)
            client:send({op = 'hello'})
        end
    end
end

return M
