-- A self test of the world-events mod, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=worldevents -gear-load=1 -gear-mods=world-events,world-events_selftest
--
-- loads savegame 1, feeds the mod states through gear.emit('world-events.state', ...) (what the server's pushes would be) and
-- checks what the pill does in the real game (it needs a SacredGear.dll with gear.ui.panel's `bare` option): a bare panel
-- 'world-events:bar' in the layout (so the layout editor can move it), hidden with "Only while Alt" and elsewhere in "where the
-- event counts", a sample while the layout editor is on, a bigger size kept by an older version brought back, the result line,
-- and a move through gear.ui.set_panel_rect. Screenshots (pill-*.bmp: normal, hover, Alt, pulse, layout editor, result) go to
-- GearAutomation\<instance>\. Add the layout example mod (gear/examples/layout, without its self test) to get its overlay.
if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local ui = gear.ui
local results = {checks = {}, passed = 0, failed = 0}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('worldevents.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local KEY = 'world-events:bar'
local function bar()
    for _, p in ipairs(ui.panels()) do
        if p.key == KEY then return p end
    end
end

local active = {st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', unit = 'orcs', count = 370, target = 1000, left = 4325, dur = 7200,
    here = true, mine = 12, need = 10, people = 5, reward = 'gold, an item', n = 1, area = 'Silver Creek',
    odds = 'Rare 20%, Magic 30%, Common 50%', odds_at = 30, odds_next = 'Epic 8%, Rare 25%, Magic 30%, Common 37%', odds_next_at = 80}

local function feed(t)
    local copy = {}
    for k, v in pairs(active) do copy[k] = v end
    for k, v in pairs(t or {}) do copy[k] = v end
    gear.emit('world-events.state', copy)
    gear.wait(0.6)
end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    local game = A.wait_for_game(cfg.timeout_game)
    check('game with a hero', game)
    if not game then return finish() end
    gear.wait(3)

    check('no pill before a state', bar() == nil)

    feed()
    local p = bar()
    check('the pill is a panel of the mod', p ~= nil)
    if p then
        check('the default size is small', p.w == 220 and p.h == 46, ('%s x %s'):format(p.w, p.h))
        check('resizable', p.resizable == true)
        A.write('panel.json', gear.json.encode(p))
    end
    -- far from the pill: the plain look
    local px, py = A.ui_to_pixels(300, 500)
    A.move(px, py)
    gear.wait(0.5)
    A.screenshot('pill-normal')

    -- the details on hover
    if p then
        local hx, hy = A.ui_to_pixels(p.x + p.w / 2, p.y + p.h / 2)
        A.move(hx, hy)
        gear.wait(0.8)
        A.screenshot('pill-hover')
        A.move(px, py)
        gear.wait(0.4)
    end
    -- ... and with Alt (the game's "show text")
    A.key_down('alt')
    gear.wait(0.8)
    check('Alt: show_text', ui.state().show_text)
    A.screenshot('pill-alt')
    A.key_up('alt')
    gear.wait(0.4)

    -- "Only while Alt is held": hidden without Alt, shown with it
    gear.emit('world-events.configure', {visibility = 'alt'})
    gear.wait(0.6)
    check('alt mode: no pill without Alt', bar() == nil)
    A.key_down('alt')
    gear.wait(0.6)
    check('alt mode: the pill with Alt', bar() ~= nil)
    A.key_up('alt')
    gear.emit('world-events.configure', {visibility = 'always'})
    gear.wait(0.6)
    check('always again: pill back', bar() ~= nil)

    -- a pulse at a quarter mark
    feed({count = 240})
    feed({count = 260})
    A.screenshot('pill-pulse')

    -- where the event counts
    feed({here = false})
    check('not in the event sector: hidden', bar() == nil)
    gear.emit('world-events.configure', {area = 'everywhere'})
    gear.wait(0.6)
    check('everywhere: shown', bar() ~= nil)
    gear.emit('world-events.configure', {area = 'sector'})
    feed()

    -- a bigger size kept by the first version (300 x 86) is brought back
    ui.set_panel_rect(KEY, 400, 40, 300, 86)
    gear.wait(0.3)
    feed()
    gear.wait(0.8)
    local c = bar()
    check('an old kept size is reset', c ~= nil and c.w <= 220.5 and c.h <= 46.5, c and ('%s x %s'):format(c.w, c.h) or 'no panel')

    -- the layout editor's mode shows a sample when nothing runs, and the pill can be moved
    feed({st = 'idle', here = false})
    check('idle: no pill', bar() == nil)
    ui.set_edit_mode(true)
    gear.wait(0.8)
    check('layout editor: a sample to place', bar() ~= nil)
    A.screenshot('pill-layout')
    local moved = ui.set_panel_rect(KEY, 120, 300)
    gear.wait(0.6)
    local q = bar()
    check('set_panel_rect finds the panel', moved == true)
    check('the pill moved', q ~= nil and math.abs(q.x - 120) < 2 and math.abs(q.y - 300) < 2,
        q and ('%d,%d'):format(q.x, q.y) or 'no panel')
    ui.set_edit_mode(false)
    gear.wait(0.3)
    ui.reset_panel(KEY)
    gear.wait(0.3)

    -- the result of an event: one line, fading out
    feed({st = 'won', hold = 30, people = 6, count = 1000})
    check('result pill', bar() ~= nil)
    A.screenshot('pill-won')
    feed({st = 'failed', hold = 30, count = 400})
    A.screenshot('pill-failed')
    feed({st = 'won', hold = 3, people = 6, count = 1000})
    gear.wait(1.5)
    A.screenshot('pill-fading')
    gear.wait(2.5)
    check('the result is gone after its hold', bar() == nil)

    finish()
end)
