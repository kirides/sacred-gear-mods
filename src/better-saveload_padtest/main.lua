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
    finish()
end)
