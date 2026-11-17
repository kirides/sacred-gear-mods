-- A self test of the world-events mod, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=worldevents -gear-load=1 -gear-mods=world-events,world-events_selftest
--
-- loads savegame 1, feeds the mod states through gear.emit('world-events.state', ...) (what the server's pushes would be) and
-- checks what the bar does in the real game: a panel 'world-events:bar' in the layout (so the layout editor can move it),
-- hidden with "Only while Alt" and elsewhere in "where the event counts", a sample while the layout editor is on, the
-- result banner, and a move through gear.ui.set_panel_rect. Screenshots go to GearAutomation\<instance>\.
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

local active = {st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', count = 370, target = 1000, left = 4325, dur = 7200,
    here = true, mine = 12, need = 10, people = 5, reward = 'gold, an item', n = 1}

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

    check('no bar before a state', bar() == nil)

    feed()
    local p = bar()
    check('the bar is a panel of the mod', p ~= nil)
    if p then
        check('titled with the event', p.title == 'Orc hunt', p.title)
        check('resizable', p.resizable == true)
        A.write('panel.json', gear.json.encode(p))
    end
    A.screenshot('bar-active')

    -- "Only while Alt is held": hidden without Alt
    gear.emit('world-events.configure', {visibility = 'alt'})
    gear.wait(0.6)
    check('alt mode: no bar without Alt', bar() == nil)
    gear.emit('world-events.configure', {visibility = 'always'})
    gear.wait(0.6)
    check('always again: bar back', bar() ~= nil)

    -- where the event counts
    feed({here = false})
    check('not in the event sector: hidden', bar() == nil)
    gear.emit('world-events.configure', {area = 'everywhere'})
    gear.wait(0.6)
    check('everywhere: shown', bar() ~= nil)
    gear.emit('world-events.configure', {area = 'sector'})
    feed()

    -- the layout editor's mode shows a sample when nothing runs, and the bar can be moved
    feed({st = 'idle', here = false})
    check('idle: no bar', bar() == nil)
    ui.set_edit_mode(true)
    gear.wait(0.6)
    check('layout editor: a sample bar to place', bar() ~= nil)
    A.screenshot('bar-editing')
    local moved = ui.set_panel_rect(KEY, 120, 300)
    gear.wait(0.6)
    local q = bar()
    check('set_panel_rect finds the panel', moved == true)
    check('the bar moved', q ~= nil and math.abs(q.x - 120) < 2 and math.abs(q.y - 300) < 2,
        q and ('%d,%d'):format(q.x, q.y) or 'no panel')
    ui.set_edit_mode(false)
    gear.wait(0.3)
    ui.reset_panel(KEY)

    -- the result of an event
    feed({st = 'won', hold = 30, people = 6, count = 1000})
    check('result bar', bar() ~= nil)
    A.screenshot('bar-won')
    feed({st = 'failed', hold = 30, count = 400})
    A.screenshot('bar-failed')

    finish()
end)
