-- The D-pad in Better SaveLoad's list (a list marked data-nav-scroll: up / down walk it card by card). A test for runs without a player; it needs a COPY of the
-- game folder with many savegames (tools/make_test_saves.py "<copy>\Save" 60 100):
--
--     Sacred.exe -gear-auto -gear-instance=bsl-pad -gear-mods=sacred-theme,better-saveload,better-saveload_padtest
--
-- With the cursor on a card, one D-pad step down scrolls the list by exactly one card (the cursor is on the next card then); rows scrolled out of sight are
-- no pad stops. Results: GearAutomation\<instance>\bsl-pad.json.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0}
local WND_MENUS = 'UI_MENU_LOADGAME'
local LOAD_ENTRY = {512, 413}
local ROW = 56      -- a card (50, its border 2) and its gap (4)

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('bsl-pad.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function query()
    local out = {}
    gear.emit('better-saveload.query', out)
    return out
end
local function rect(sel)
    local out = {}
    gear.emit('better-saveload.rect', out)
    return out.rect and out.rect(sel) or nil
end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    gear.wait(2)
    A.ui_click(LOAD_ENTRY[1], LOAD_ENTRY[2])
    check('load game screen opens', gear.wait_until(function() return gear.ui.window_open(WND_MENUS) end, 8))
    check('the mod\'s screen replaces it', gear.wait_until(function() return query().open == WND_MENUS end, 5))
    gear.wait(1.5)
    local q = query()
    check('many savegames are listed', q.shown >= 30, q.shown)
    A.screenshot('pad-0-list')

    -- The pad's cursor starts on the topmost savegame, not on the search field (the first stop Gear reports is the first card's).
    do
        local fx, fy = A.nav_first()
        local card = rect('.row')
        check('the pad starts on the topmost card', fx ~= nil and card ~= nil and fx >= card.x and fx <= card.x + card.w and fy >= card.y and fy <= card.y + card.h,
            tostring(fx) .. ',' .. tostring(fy))
    end

    -- The filters are drop-down lists: a click opens the list under the button, a click on an entry picks it and closes it, B closes it without.
    local function click_rect(r, wait)
        local x, y = A.ui_to_pixels(r.x + r.w / 2, r.y + r.h / 2)
        A.move(x, y)
        gear.wait(0.3)
        A.click(x, y)
        gear.wait(wait or 0.6)
    end
    local stops_closed = A.nav()
    click_rect(rect('#sort'))
    gear.wait(0.4)
    check('the open list adds its entries as pad stops', A.nav() >= stops_closed + 5, tostring(stops_closed) .. ' -> ' .. tostring(A.nav()))
    check('the order button opens its list', query().dd == 'sort', query().dd)
    A.screenshot('pad-0b-dropdown')
    local opt = rect('#dds3')
    check('the list has entries', opt ~= nil)
    if opt then click_rect(opt) end
    q = query()
    if q.sort_i ~= 3 then
        gear.emit('better-saveload.press', {selector = '.opt', id = 'dds3'})      -- (what a click on the entry does: tells a handler that fails from a click that does not arrive)
        gear.wait(0.3)
        check('(the handler of an entry works)', query().sort_i == 3, tostring(query().sort_i))
        gear.emit('better-saveload.set', {sort_i = 1})
    end
    check('an entry picks the order and closes the list', q.dd == '' and q.sort_i == 3, tostring(q.dd) .. ' ' .. tostring(q.sort_i) .. ' sel=' .. tostring(q.sel))
    click_rect(rect('#hero'))
    check('the character button opens its list', query().dd == 'hero', query().dd)
    A.pad(0, 1, 0)                                                   -- B
    gear.wait(0.5)
    check('B closes the list and keeps the screen', query().dd == '' and query().open == WND_MENUS, tostring(query().dd))
    A.pad(0, 0, 0)
    local o3 = rect('#sort')
    if o3 then
        click_rect(o3)
        local first = rect('#dds1')
        if first then click_rect(first) end                          -- the newest-first order again
    end

    gear.emit('better-saveload.press', {selector = '#jump1'})        -- (the list to its top again after the clicks above)
    gear.wait(0.8)
    do
        local lr = rect('#list')
        if lr then
            local lx, ly = A.ui_to_pixels(lr.x + lr.w / 2, lr.y + lr.h / 2)
            A.move(lx, ly)
            gear.wait(0.3)
            for _ = 1, 60 do
                if query().scroll_top <= 0 then break end
                A.wheel(10)
                gear.wait(0.15)
            end
        end
    end

    -- A list scrolled to its top / bottom says so to the controller (+ 4 / + 8 on its kind): the D-pad leaves it there for the controls beyond.
    local function has_kind(want)
        for _, k in ipairs(A.nav_kinds()) do if k == want then return true end end
        return false
    end
    do
        local lr = rect('#list')
        local lx, ly = A.ui_to_pixels(lr.x + lr.w / 2, lr.y + lr.h / 2)
        A.move(lx, ly)
        gear.wait(0.8)
        check('the list at its top: the pad may leave it upward', has_kind(6), table.concat(A.nav_kinds(), ','))
        for _ = 1, 80 do
            local before = query().scroll_top
            A.wheel(-10)
            gear.wait(0.15)
            if query().scroll_top == before then break end
        end
        gear.wait(0.5)
        check('the list at its bottom: the pad may leave it downward', has_kind(10), table.concat(A.nav_kinds(), ','))
        for _ = 1, 80 do
            if query().scroll_top <= 0 then break end
            A.wheel(10)
            gear.wait(0.15)
        end
    end

    -- Rows scrolled out of sight are no pad stops: the stops are the visible cards and the buttons around the list.
    local stops = A.nav()
    check('only the visible cards are pad stops', stops > 0 and stops <= 22, stops)

    -- The cursor on the first card.
    local first = rect('.row')
    check('a card is on screen', first ~= nil)
    local cx, cy = first.x + first.w / 2, first.y + first.h / 2
    local px, py = A.ui_to_pixels(cx, cy)
    A.move(px, py)
    gear.wait(0.5)
    local top0 = query().scroll_top
    for step = 1, 4 do
        A.pad_scroll(1)
        gear.wait(0.5)
        local top = query().scroll_top
        check(('D-pad down %d scrolls by one card'):format(step), math.abs(top - top0 - step * ROW) <= 1, ('%s -> %s'):format(top0, top))
    end
    A.pad_scroll(-1)
    gear.wait(0.5)
    check('D-pad up scrolls back by one card', math.abs(query().scroll_top - top0 - 3 * ROW) <= 1, query().scroll_top)
    A.screenshot('pad-1-scrolled')

    -- A card that is only partly in view under the pad's cursor is brought fully into view (the pad's step puts the cursor on a card whose centre is in view).
    A.pad(1, 0, 0)                                                   -- the controller is in use from now on
    A.move(px, py)
    gear.wait(0.3)
    local list = rect('#list')
    local o = query()
    local reached, moved = false, false
    for _ = 1, 12 do
        A.wheel(-1)                                                  -- a notch of the wheel: the list scrolls by a few pixels more than a card, sooner or later partly
        gear.wait(0.3)
        o = query()
        local phase = o.scroll_top % ROW
        if phase > 8 and phase < 28 then reached = true break end
    end
    check('the list stands where a card is partly out of view', reached, o.scroll_top)
    if reached then
        -- the cursor on the card at the bottom edge: the card that is cut there
        local by = list.y + list.h - 6
        local bx, byp = A.ui_to_pixels(list.x + list.w / 2, by)
        A.move(bx, byp)
        gear.wait(0.8)
        local idx = math.floor((o.scroll_top + (by - list.y)) / ROW) + 1
        local slot = o.order[idx - (o.mode == 'save' and 1 or 0)]
        local r = slot and rect('#row' .. slot)
        check('the card under the cursor is in view as a whole', r and r.y + r.h <= list.y + list.h + 1 and r.y >= list.y - 1,
            r and ('%.1f..%.1f of %.1f..%.1f'):format(r.y, r.y + r.h, list.y, list.y + list.h))
    end
    -- The real mouse on the list's scroll bar: drag the knob, and press the groove.
    A.pad_scroll(-1)                                                 -- (the list back near the top)
    for _ = 1, 8 do A.pad_scroll(-1); gear.wait(0.1) end
    gear.wait(0.5)
    A.move(px, py)                                                   -- the mouse moves: the mouse is in use again
    gear.wait(0.3)
    local bar_x = list.x + list.w - 15                               -- the middle of the scroll bar (30 wide, at the list's right edge)
    local knob_y = list.y + 30 + 15                                  -- the knob (30 high) under the up arrow, while the list is at its top
    local top_before = query().scroll_top
    local kx, ky = A.ui_to_pixels(bar_x, knob_y)
    A.move(kx, ky)
    gear.wait(0.3)
    A.down()
    gear.wait(0.2)
    for step = 1, 8 do
        local mx, my = A.ui_to_pixels(bar_x, knob_y + step * 12)
        A.move(mx, my)
        gear.wait(0.08)
    end
    A.up()
    gear.wait(0.4)
    local top_dragged = query().scroll_top
    check('dragging the knob scrolls the list', top_dragged > top_before + 100, ('%s -> %s'):format(top_before, top_dragged))
    local gx, gy = A.ui_to_pixels(bar_x, list.y + list.h - 45)       -- the groove near its lower end
    A.move(gx, gy)
    gear.wait(0.3)
    A.down()
    gear.wait(0.3)
    A.up()
    gear.wait(0.4)
    local top_paged = query().scroll_top
    check('pressing the groove below the knob scrolls toward the cursor', top_paged > top_dragged + 50, ('%s -> %s'):format(top_dragged, top_paged))
    A.screenshot('pad-2-scrollbar')
    finish()
end)
