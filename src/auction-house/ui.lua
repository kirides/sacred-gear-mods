-- The auction house panel: Browse, Sell, My auctions, Mailbox. Opened from the "Auction house" button that shows
-- while the game's chest window is open; closes with it. Everything is a widget (buttons, dropdowns, regions), so
-- the controller's D-pad reaches all of it; text fields have a "Kbd" button for an on-screen keyboard.
local ui, inv, world = gear.ui, gear.inv, gear.world
local plain = require('core').plain

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

-- What to show for an item whose tooltip gave no name: the localized type name, the internal one on an older Gear.
local function type_label(it)
    local ok, n = pcall(function() return gear.data.object_types:label(it.type) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return it.type_name or ('item ' .. tostring(it.type))
end

-- What the market lists about an item: its display name and level from the game's tooltip text.
function M.meta_of(it, bytes)
    local text = ''
    local ok, t = pcall(ui.item_tooltip_text, bytes or it.id)
    if ok and type(t) == 'string' then text = t
    elseif ok and type(t) == 'table' then text = table.concat(t, '\n') end
    text = plain(text)      -- without the game's colour and image codes
    local name
    for line in text:gmatch('[^\n]+') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then name = line break end
    end
    if not name then name = type_label(it) end
    -- the item's level line ("Level: 9"; German "Stufe: 9", French "Niveau", Spanish "Nivel", Italian "Livello"),
    -- not "Minimum Level" / "Minimum Stufe"
    local level = 0
    for line in text:lower():gmatch('[^\n]+') do
        line = line:gsub('^%s+', '')
        local n = line:match('^level%s*:?%s*(%d+)') or line:match('^stufe%s*:?%s*(%d+)')
            or line:match('^niveau%s*:?%s*(%d+)') or line:match('^nivel%s*:?%s*(%d+)')
            or line:match('^livello%s*:?%s*(%d+)')
        if n then level = tonumber(n) break end
    end
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

---------------------------------------------------------------------------------------------------------------
-- The window: ui/market.rml (the game theme)
---------------------------------------------------------------------------------------------------------------
-- One document holds the market window, the "Auction house" button and the on-screen keyboard. A model of ready-made values is rebuilt every
-- frame and only what changed is written; clicks are delegated listeners. The text fields are bound with data-value (the document hands
-- the text back through on_change); the on-screen keyboard (Kbd) is a window of its own for the controller.
local TABS = {{'browse', 'Browse'}, {'sell', 'Sell'}, {'mine', 'My auctions'}, {'mail', 'Mailbox'}}
local STEPS = {-1000, -100, 100, 1000, 10000}
local REASON = {sold = 'sold', expired = 'not sold', cancelled = 'cancelled', bought = 'bought', withdrawn = 'gold'}
local OSK_ROWS = {'1234567890', 'qwertyuiop', 'asdfghjkl', "zxcvbnm-'"}

local doc
local last = {}
local panel_open = false
local osk                 -- {target = 'q' | 'price' | 'gold', text, digits, max}
local ids = {}            -- element id -> what a click does
local search_at           -- gear.time() when the typed search text is sent
local pending_client

local function css_color(argb)
    argb = argb or 0xFFFFFFFF
    return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function item_src(it)
    if type(it) == 'table' and it.id then return 'gear:item/id/' .. tostring(it.id) end
    if type(it) == 'number' and it > 0 then return 'gear:item/' .. tostring(it) end
    return ''
end

-- A text field's text is the model's; set it from code with this (the document does not echo it back).
local function set_field(key, value)
    if doc then doc.model[key] = value; last[key] = value end
end

local function cycle(list, i) return i % #list + 1 end

local function stats_line(client)
    if client.info and client.info.problem then return client.info.problem, true end
    if client.where == 'probe' then return 'Looking for the market on the game server...', false end
    if client.where == 'closed' then
        return 'The market is closed: this game needs the game server market (Closed Net), and this server has none', true
    end
    if not client:online() then
        return (client.where == 'server' and 'The market on the game server is not answering'
            or 'The market is not answering (the host is not in the game?)'), true
    end
    local status = ({server = 'Market: on the game server', host = 'Market: in the host\'s game', here = 'Market: in this game'})[client.where]
    if status and client:authoritative() then status = status .. ' (the server keeps your hero: every transfer is saved there)' end
    return status or '', false
end

local function now_of(client)
    return client.info and client.info.now and (client.info.now + (gear.time() - client.info_at)) or os.time()
end

local function browse_model(client, m)
    local q = view.q
    m.cat, m.qual, m.level, m.price = CATEGORIES[q.cat][2], QUALITIES[q.qual][2], LEVELS[q.level][3], PRICES[q.price][3]
    m.mine_class, m.class_label = q.mine_class and true or false, 'My class'
    m.sort, m.order = SORTS[view.sort][2], view.desc and 'High-low' or 'Low-high'
    local page = client.page
    if not page then
        m.browse_msg = client:online() and 'Searching...' or 'Waiting for the market...'
        return
    end
    m.count, m.pg = ('%d found'):format(page.total or 0), ('%d / %d'):format(page.page, page.pages)
    m.can_prev, m.can_next = page.page > 1, page.page < page.pages
    local now = now_of(client)
    local me = client:me().key
    for _, r in ipairs(page.rows) do
        local mine_listing = r.seller_key == me
        local classes = (r.classes and #r.classes > 0) and table.concat(r.classes, ', ') or 'all classes'
        ids['buy' .. r.id] = r
        m.rows[#m.rows + 1] = {
            id = 'row' .. r.id, src = item_src(r.type), color = css_color(QUALITY_COLOR[r.quality] or 0xFFFFFFFF), name = r.name or '?',
            detail = ('Lv %d  -  %s  -  %s  -  %s'):format(r.level or 0, r.seller or '?', left(r.ends, now), classes),
            price = gold(r.price), median = r.median and ('recent %s'):format(gold(r.median)) or '',
            buy = mine_listing and 'Yours' or 'Buy', buy_id = 'buy' .. r.id, disabled = mine_listing or view.busy,
            buy_tip = mine_listing and 'Your own listing'
                or ('Buy for %s gold (taken from your wallet; what it lacks from the gold you carry)'):format(gold(r.price)),
        }
        ids['row' .. r.id] = {listing = r.id}
    end
    if #page.rows == 0 then m.browse_msg = 'Nothing for sale matches.' end
end

local function sell_model(client, cfg, m)
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
    s.page = math.max(0, math.min(s.page, view.src_pages - 1))
    m.sp_n, m.sp_prev, m.sp_next = ('%d / %d'):format(s.page + 1, view.src_pages), s.page > 0, s.page < view.src_pages - 1
    local sel = s.sel
    if sel and not inv.size(sel.id) then s.sel, sel = nil, nil end         -- gone (moved, sold)
    for _, c in ipairs(view.src_cells) do
        if c.page == s.page + 1 then
            ids['c' .. c.id] = c
            m.cells[#m.cells + 1] = {id = 'c' .. c.id, x = (c.cx * CELL) .. 'px', y = (c.cy * CELL) .. 'px', w = (c.cw * CELL + 1) .. 'px',
                h = (c.ch * CELL + 1) .. 'px', iw = (c.cw * CELL - 3) .. 'px', ih = (c.ch * CELL - 3) .. 'px', src = item_src(c.src.item),
                color = css_color(QUALITY_COLOR[c.src.item.quality] or 0xFF606060), ok = c.ok and true or false, sel = sel ~= nil and sel.id == c.id}
        end
    end
    m.has_sel = sel ~= nil
    if not sel then return end
    local it = sel.src.item
    s.meta = s.meta or M.meta_of(it)
    local hist = client:fetch_history(it.type)
    local htext = 'no recent sales of this kind'
    if hist and hist.median then htext = ('recent sales: median %s gold (%d)'):format(gold(hist.median), #(hist.sales or {})) end
    m.sel = {src = item_src(it), color = css_color(QUALITY_COLOR[it.quality] or 0xFFFFFFFF), name = s.meta.name,
        detail = ('Level %d  -  from your %s  -  %s'):format(s.meta.level or 0, sel.src.where, htext)}
    for _, step in ipairs(STEPS) do
        local label = (step > 0 and '+' or '') .. (math.abs(step) >= 1000 and ((math.floor(step / 1000)) .. 'k') or tostring(step))
        ids['st' .. step] = step
        m.steps[#m.steps + 1] = {id = 'st' .. step, label = label}
    end
    local price = tonumber(s.price) or 0
    local rules = client.info and client.info.rules or {durations = {1, 3, 7}, fee_per_day = 0, sale_cut = 0}
    s.days = math.max(1, math.min(s.days, #rules.durations))
    local d = rules.durations[s.days] or 1
    m.days = d == 1 and '1 day' or (d .. ' days')
    local fee = 0
    if (rules.fee_per_day or 0) > 0 and price > 0 then fee = math.max(rules.fee_min or 0, math.floor(price * rules.fee_per_day / 100 * d)) end
    local net = price - math.floor(price * (rules.sale_cut or 0) / 100)
    m.fee = ('Fee %s now  -  you get %s if it sells (%s%% cut)'):format(gold(fee), gold(net), tostring(rules.sale_cut or 0))
    m.can_list = price >= (rules.price_min or 1) and price <= (rules.price_max or 2e9) and not view.busy and client:online()
end

local function mine_model(client, m)
    if not view.mine_asked or gear.time() - view.mine_asked > 5 then
        view.mine_asked = gear.time()
        client:refresh_mine()
    end
    local list = client.mine and client.mine.rows or {}
    m.mine_title = ('Your listings: %d'):format(#list)
    local now = now_of(client)
    for n, r in ipairs(list) do
        if n > 12 then m.mine_more = ('and %d more'):format(#list - 12) break end
        ids['cancel' .. r.id] = r
        m.mine_rows[#m.mine_rows + 1] = {src = item_src(r.type), color = css_color(QUALITY_COLOR[r.quality] or 0xFFFFFFFF), name = r.name or '?',
            detail = ('%s gold  -  %s left'):format(gold(r.price), left(r.ends, now)), cancel_id = 'cancel' .. r.id}
    end
end

local function mail_model(client, m)
    if not view.mail_asked or gear.time() - view.mail_asked > 5 then
        view.mail_asked = gear.time()
        client:refresh_mail()
    end
    local hero = world.hero()
    m.wallet = ('Wallet: %s gold   (you carry %s)'):format(gold(client:wallet()), gold(hero and hero:gold() or 0))
    local amount = tonumber(view.gold_amount) or 0
    m.can_dep = amount > 0 and not view.busy and client:online()
    m.can_all = client:wallet() > 0
    local entries = client.mail and client.mail.entries or {}
    local returns = client:returns()
    m.mail_title = ('Mailbox: %d'):format(#entries + #returns)
    m.can_collect = #entries > 0 and not view.busy
    for _, e in ipairs(returns) do
        ids['ret' .. e.rid] = e
        m.returns[#m.returns + 1] = {src = item_src(e.meta and e.meta.type), name = (e.meta and e.meta.name or 'Item') .. '  (sale refused, kept here)',
            take_id = 'ret' .. e.rid}
    end
    for n, e in ipairs(entries) do
        if n > 10 then m.mail_more = ('and %d more'):format(#entries - 10) break end
        ids['col' .. e.mid] = e
        local gold_entry = e.kind == 'gold'
        m.mails[#m.mails + 1] = {src = gold_entry and '' or item_src(e.type), color = gold_entry and '#ffe080ff' or css_color(QUALITY_COLOR[e.quality] or 0xFFFFFFFF),
            name = gold_entry and ('%s gold'):format(gold(e.gold)) or (e.name or 'Item'), reason = gold_entry and '' or (REASON[e.reason] or e.reason or ''),
            col_id = 'col' .. e.mid}
    end
end

local function osk_model(m)
    m.osk_open = osk ~= nil
    if not osk then return end
    m.osk_text, m.osk_digits = osk.text, osk.digits and true or false
    for r, row in ipairs(OSK_ROWS) do
        local keys = {}
        for i = 1, #row do
            local ch = row:sub(i, i)
            keys[i] = {id = ('osk%d_%d'):format(r, i), label = ch:upper(), dis = osk.digits and not ch:match('%d') and true or false}
            ids[keys[i].id] = ch
        end
        m.osk_rows[r] = keys
    end
end

local function snapshot(client, cfg, st)
    local m = {
        open_shown = st.button ~= nil, open_enabled = st.button == 'on', open_label = panel_open and 'Close' or 'Open the market',
        open_tip = st.button == 'on' and 'Buy and sell items with the other players' or 'Open a chest to use the market',
        market_open = panel_open and st.market, tab = view.tab, tabs = {}, status = '', status_bad = false,
        q_text = last.q_text or '', price_in = last.price_in or '', gold_in = last.gold_in or '',
        cat = '', qual = '', level = '', price = '', mine_class = false, class_label = '', sort = '', order = '', count = '', pg = '',
        can_prev = false, can_next = false, browse_msg = '', rows = {},
        sp_n = '', sp_prev = false, sp_next = false, cells = {}, has_sel = false, sel = {src = '', color = '#ffffffff', name = '', detail = ''}, steps = {},
        days = '', fee = '', can_list = false,
        mine_title = '', mine_rows = {}, mine_more = '', busy = view.busy and true or false,
        wallet = '', can_dep = false, can_all = false, mail_title = '', can_collect = false, returns = {}, mails = {}, mail_more = '',
        msg_ok = true, footer = '',
        osk_open = false, osk_text = '', osk_digits = false, osk_rows = {},
    }
    ids = {}
    for i, t in ipairs(TABS) do m.tabs[i] = {id = 'tab-' .. t[1], name = t[2], on = view.tab == t[1]} end
    if not m.market_open then return m end
    m.status, m.status_bad = stats_line(client)
    if view.tab == 'browse' then browse_model(client, m)
    elseif view.tab == 'sell' then sell_model(client, cfg, m)
    elseif view.tab == 'mine' then mine_model(client, m)
    else mail_model(client, m) end
    -- the footer: the last message, or what the item under the cursor is
    local note
    for i = #client.notes, 1, -1 do
        local n = client.notes[i]
        if gear.time() < n['until'] then note = n break end
    end
    if view.msg and gear.time() < view.msg_until then m.footer, m.msg_ok = view.msg, view.msg_ok
    elseif note then m.footer, m.msg_ok = note.text, note.ok
    elseif view.hover and view.hover.why then m.footer = view.hover.why
    else m.footer = ('Wallet %s gold'):format(gold(client:wallet())) end
    osk_model(m)
    return m
end

local function open_osk(target, value, digits, max)
    osk = {target = target, text = value or '', digits = digits, max = max}
end

local function apply_osk()
    if not osk then return end
    if osk.target == 'q' then view.q.text = osk.text; set_field('q_text', osk.text); search_at = gear.time() + 0.1
    elseif osk.target == 'price' then view.sell.price = osk.text; set_field('price_in', osk.text)
    else view.gold_amount = osk.text; set_field('gold_in', osk.text) end
    osk = nil
end

local function load_doc(client, cfg, st)
    local m = snapshot(client, cfg, st)
    last = m
    local err
    doc, err = ui.rml.load('ui/market.rml', {model = m, on_change = function(_, model)
        local q = tostring(model.q_text or '')
        if q ~= view.q.text then view.q.text = q; search_at = gear.time() + 0.7 end
        view.sell.price = tostring(model.price_in or '')
        view.gold_amount = tostring(model.gold_in or '')
        last.q_text, last.price_in, last.gold_in = model.q_text, model.price_in, model.gold_in
    end})
    if not doc then gear.log('auction house: ui/market.rml failed: ' .. tostring(err)) return end
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    local function target(e) return ids[tostring(e.current)] end
    local c = function() return pending_client end
    on('#ah-toggle', function()
        local cl = c()
        if not (cl and last.open_enabled) then return end
        if panel_open then M.close() else
            panel_open = true
            M.search(cl, 1)
            cl:send({op = 'hello'})
        end
    end)
    on('.tab', function(e)
        local t = tostring(e.current):match('^tab%-(%a+)$')
        local cl = c()
        if not (t and cl) then return end
        view.tab, osk = t, nil
        if t == 'browse' then M.search(cl, view.page) end
        if t == 'mail' then view.mail_asked = nil end
        if t == 'mine' then view.mine_asked = nil end
    end)
    -- Browse
    on('#ah-cat', function() view.q.cat = cycle(CATEGORIES, view.q.cat); M.search(c(), 1) end)
    on('#ah-qual', function() view.q.qual = cycle(QUALITIES, view.q.qual); M.search(c(), 1) end)
    on('#ah-lvl', function() view.q.level = cycle(LEVELS, view.q.level); M.search(c(), 1) end)
    on('#ah-price', function() view.q.price = cycle(PRICES, view.q.price); M.search(c(), 1) end)
    on('#ah-class', function() view.q.mine_class = not view.q.mine_class; M.search(c(), 1) end)
    on('#ah-sort', function() view.sort = cycle(SORTS, view.sort); M.search(c(), 1) end)
    on('#ah-desc', function() view.desc = not view.desc; M.search(c(), 1) end)
    on('#ah-search', function() M.search(c(), 1) end)
    on('#ah-prev', function() local cl = c(); if cl and cl.page and cl.page.page > 1 then M.search(cl, cl.page.page - 1) end end)
    on('#ah-next', function() local cl = c(); if cl and cl.page and cl.page.page < cl.page.pages then M.search(cl, cl.page.page + 1) end end)
    on('[id^=buy]', function(e)
        local r, cl = target(e), c()
        if not (r and cl) or r.seller_key == cl:me().key or view.busy then return end
        view.busy = true
        cl:buy(r, function(ok, err2)
            view.busy = false
            if ok then
                say(('Bought %s. It is in your mailbox.'):format(r.name or 'the item'))
                M.search(cl, view.page)
                cl:refresh_mail()
            else
                say(err2 or 'not bought', false)
                M.search(cl, view.page)
            end
        end)
    end)
    -- Sell
    on('#ah-sp', function() view.sell.page = math.max(0, view.sell.page - 1) end)
    on('#ah-sn', function() view.sell.page = view.sell.page + 1 end)
    on('[id^=c]', function(e)
        local cell, cl = target(e), c()
        if not (cell and cell.ok and cl and tostring(e.current):match('^c%d+$')) then return end
        local s = view.sell
        s.sel, s.meta = cell, nil
        local hist = cl:fetch_history(cell.src.item.type)
        if hist and hist.median and s.price == '' then s.price = tostring(hist.median); set_field('price_in', s.price) end
    end)
    on('[id^=st]', function(e)
        local step = target(e)
        if type(step) ~= 'number' then return end
        view.sell.price = tostring(math.max(0, (tonumber(view.sell.price) or 0) + step))
        set_field('price_in', view.sell.price)
    end)
    on('#ah-days', function()
        local cl = c()
        local rules = cl and cl.info and cl.info.rules or {durations = {1, 3, 7}}
        view.sell.days = view.sell.days % #rules.durations + 1
    end)
    on('#ah-list', function()
        local cl, s = c(), view.sell
        if not (cl and s.sel and last.can_list) then return end
        local sel, it = s.sel, s.sel.src.item
        local rules = cl.info and cl.info.rules or {durations = {1, 3, 7}}
        local days = rules.durations[s.days] or 1
        local price = tonumber(s.price) or 0
        view.busy = true
        local name = s.meta.name
        cl:sell(sel.src.container, it, s.meta, price, days, function(done, err2)
            view.busy = false
            if done then say(('%s is for sale for %s gold.'):format(name, gold(price))) else say(err2 or 'not listed', false) end
            view.src_at = nil
        end)
        s.sel, s.meta, s.price = nil, nil, ''
        set_field('price_in', '')
        view.src_at = nil
    end)
    -- My auctions
    on('[id^=cancel]', function(e)
        local r, cl = target(e), c()
        if not (r and cl) or view.busy then return end
        view.busy = true
        cl:cancel(r.id, function(ok, err2)
            view.busy = false
            say(ok and ((r.name or 'It') .. ' is back in your mailbox.') or (err2 or 'not cancelled'), ok)
            view.mine_asked = nil
            cl:refresh_mail()
        end)
    end)
    -- Mailbox and wallet
    on('#ah-dep', function()
        local cl, amount = c(), tonumber(view.gold_amount) or 0
        if not (cl and amount > 0 and not view.busy and cl:online()) then return end
        view.busy = true
        cl:deposit(amount, function(ok, err2)
            view.busy = false
            say(ok and (gold(amount) .. ' gold deposited.') or (err2 or 'not deposited'), ok)
        end)
        view.gold_amount = ''
        set_field('gold_in', '')
    end)
    on('#ah-wd', function()
        local cl, amount = c(), tonumber(view.gold_amount) or 0
        if not (cl and amount > 0 and not view.busy and cl:online()) then return end
        view.busy = true
        cl:withdraw(amount, function(ok, err2)
            view.busy = false
            if not ok then say(err2 or 'not taken out', false) end
        end)
        view.gold_amount = ''
        set_field('gold_in', '')
    end)
    on('#ah-wall', function()
        local cl = c()
        if cl and cl:wallet() > 0 then view.gold_amount = tostring(cl:wallet()); set_field('gold_in', view.gold_amount) end
    end)
    on('#ah-call', function()
        local cl = c()
        if not (cl and cl.mail and not view.busy) then return end
        for _, e in ipairs(cl.mail.entries or {}) do cl:collect(e.mid) end
    end)
    on('[id^=ret]', function(e)
        local r, cl = target(e), c()
        if r and cl and not cl:take_return(r) then say('no room in the backpack or the chest', false) end
    end)
    on('[id^=col]', function(e)
        local r, cl = target(e), c()
        if not (r and cl) or view.busy then return end
        cl:collect(r.mid, function(ok, err2)
            if not ok and err2 then say(err2, false) end
            view.mail_asked = nil
        end)
    end)
    -- the on-screen keyboard
    on('#kbd-q', function() open_osk('q', view.q.text, false, 40) end)
    on('#kbd-price', function() open_osk('price', view.sell.price, true, 10) end)
    on('#kbd-gold', function() open_osk('gold', view.gold_amount, true, 10) end)
    on('[id^=osk]', function(e)
        local id = tostring(e.current)
        if not osk then return end
        if id == 'osk-space' then if not osk.digits and #osk.text < osk.max then osk.text = osk.text .. ' ' end
        elseif id == 'osk-back' then osk.text = osk.text:sub(1, -2)
        elseif id == 'osk-clear' then osk.text = ''
        elseif id == 'osk-done' then apply_osk()
        else
            local ch = ids[id]
            if ch and #osk.text < osk.max and (not osk.digits or ch:match('%d')) then osk.text = osk.text .. ch end
        end
    end)
    doc:on('.listing', 'mouseover', function(e) view.hover = ids[tostring(e.current)] end)
    doc:on('.listing', 'mouseout', function() view.hover = nil end)
end

-- Every frame (main.lua): st = {button = nil | 'off' | 'on' (the Open button), market = whether the window may show now}.
function M.draw(client, cfg, st)
    pending_client = client
    if not doc then load_doc(client, cfg, st) end
    if not doc then return end
    if search_at and gear.time() >= search_at then
        search_at = nil
        M.search(client, 1)
    end
    local m = snapshot(client, cfg, st)
    for k, v in pairs(m) do
        if k ~= 'q_text' and k ~= 'price_in' and k ~= 'gold_in' and not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
    if view.hover and m.market_open then
        if view.hover.listing then tooltip(client:fetch_item(view.hover.listing))
        elseif view.hover.item then tooltip(view.hover.item) end
    end
end

function M.is_open() return panel_open end
function M.open() panel_open = true end
function M.close()
    panel_open, osk = false, nil
end
function M.rect(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end

return M
