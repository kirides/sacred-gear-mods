-- A self test of the world-events mod, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=worldevents -gear-load=1 -gear-mods=world-events,world-events_selftest
--
-- loads savegame 1, feeds the mod states through gear.emit('world-events.state', ...) (what the server's pushes would be) and
-- checks what the pill does in the real game (it needs a SacredGear.dll with gear.ui.panel's `bare` option): a bare panel
-- 'world-events:bar' in the layout (so the layout editor can move it), hidden with "Only while Alt" and elsewhere in "where the
-- event counts", a sample while the layout editor is on, a bigger size kept by an older version brought back, the result line,
-- and a move through gear.ui.set_panel_rect. Screenshots (pill-*.bmp: normal, hover, Alt, pulse, layout editor, result) go to
-- GearAutomation\<instance>\. Add the layout example mod (src/layout, without its self test) to get its overlay.
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
    gear.emit('world-events.configure', {local_mode = 'off', region_pill = false})      -- the single player mode would start its own events here
    gear.wait(3)

    check('no pill before a state', bar() == nil)

    feed()
    local p = bar()
    check('the pill is a panel of the mod', p ~= nil)
    if p then
        check('the default size is small', p.w < 460 and math.abs(p.h - 46 * p.w / 220) < 1.5, ('%s x %s'):format(p.w, p.h))
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

    -- a wider panel: the pill grows with it (its height is made from the width)
    ui.set_panel_rect(KEY, 400, 40, 300, 86)
    gear.wait(0.3)
    feed()
    gear.wait(0.8)
    local c = bar()
    check('the height follows the width of the panel', c ~= nil and math.abs(c.h - 46 * c.w / 220) < 1.5, c and ('%s x %s'):format(c.w, c.h) or 'no panel')

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

    -- several events at once: one panel with a pill for each, the least time left first (and the region boss pill below them when the game
    -- has gear.data.regions and the hero stands in a region)
    gear.emit('world-events.configure', {region_pill = true})
    local function ev(n, title, left) local t = {}; for k, v in pairs(active) do t[k] = v end; t.n, t.title, t.left = n, title, left; return t end
    gear.emit('world-events.state', {v = 1, list = {ev(1, 'Orc hunt', 3000), ev(2, 'Wolf hunt', 600), ev(3, 'Thieves', 1800)}})
    gear.wait(1)
    local stack = bar()
    local regions_api = gear.data and gear.data.regions
    local in_region = regions_api and regions_api.of_creature and gear.world.hero() and regions_api:of_creature(gear.world.hero()) ~= nil
    local pills = in_region and 4 or 3
    check('the panel holds one pill per event' .. (in_region and ' and the region' or ''), stack ~= nil and math.abs(stack.h - (pills * 46 * stack.w / 220 + (pills - 1) * 4)) < 2,
        stack and ('%s x %s'):format(stack.w, stack.h) or 'no panel')
    A.screenshot('pills-stack')
    -- the layout editor adds a sample of the region boss pill (teal) when the hero is in none
    ui.set_edit_mode(true)
    gear.wait(0.8)
    local edit = bar()
    check('the layout editor shows the region sample as a fourth pill', edit ~= nil and edit.h > 3.5 * 46 * edit.w / 220, edit and tostring(edit.h) or 'no panel')
    A.screenshot('pills-region')
    ui.set_edit_mode(false)
    gear.wait(0.5)
    print('region API: ' .. tostring(regions_api ~= nil) .. ', hero in a region: ' .. tostring(in_region and true or false))
    feed()
    gear.wait(0.8)

    -- region names: the game's records hold text keys, the pill shows the game's text of the install's language
    local list = {}
    gear.emit('world-events.regions', list)
    if gear.data and gear.data.regions then
        check('the game has regions with kill counts', #list > 0, tostring(#list))
        local raw_left = false
        for _, r in ipairs(list) do
            print(('region %s: key %s -> %s'):format(tostring(r.id), tostring(r.raw), tostring(r.name)))
            if tostring(r.name):find('UI_', 1, true) or tostring(r.name) == '' then raw_left = true end
        end
        check('no region shows its raw text key or an empty name', not raw_left)
        local localized = 0
        for _, r in ipairs(list) do
            local pretty = tostring(r.raw):gsub('^UI_REGION_', ''):gsub('_', ' '):lower()
            if r.name:lower() ~= pretty then localized = localized + 1 end
        end
        check('the names come from the game texts of the install language, not only the readable key', localized >= #list - 1, ('%d of %d'):format(localized, #list))
        ui.set_edit_mode(true)
        gear.wait(0.8)
        A.screenshot('pill-region-name')
        ui.set_edit_mode(false)
        gear.wait(0.4)
    else
        print('no gear.data.regions in this SacredGear.dll: the region names are not checked')
    end

    -- a spawn wave of a hook, in this single player game: the creatures appear around the hero (what the server's
    -- 'worldevents:spawn' message makes the mod do), once per wave id; they are removed again afterwards
    local W = gear.world
    local hero = W.hero()
    check('single player: the world can be changed', W.can_change() == true)
    local hx, hy, layer = hero:position()
    local function mine()
        local out = {}
        for _, c in ipairs(W.creatures_near(hx, hy, 1200, {limit = 64, layer = layer}) or {}) do
            if c:label() == 'world-events' then out[#out + 1] = c end
        end
        return out
    end
    check('no wave creatures before', #mine() == 0)
    local found = gear.data.object_types:search('ORC_WARRIOR', 5)
    check('the game knows an orc warrior type', #found > 0)
    local wave = {id = 'selftest:1', event = 'Self test', n = 3, radius = 400, kinds = {{type = 'Orc Warrior', weight = 3}}, text = 'A wave of three!'}
    gear.emit('world-events.spawn', wave)
    gear.wait(1)
    local made = mine()
    check('the wave: three creatures around the hero', #made == 3, tostring(#made))
    local near = true
    for _, c in ipairs(made) do
        local x, y = c:position()
        local d = math.sqrt((x - hx) ^ 2 + (y - hy) ^ 2)
        if d > 460 then near = false end      -- they spawn 40-100% of the radius out and may already walk towards the hero
    end
    check('within the radius around the hero', near)
    A.screenshot('wave')
    gear.emit('world-events.spawn', wave)
    gear.wait(0.6)
    check('the same wave id does not spawn twice', #mine() == 3)
    if made[1] and made[1].remove then
        for _, c in ipairs(made) do c:remove() end
        gear.wait(0.5)
        check('the wave creatures are removed again', #mine() == 0, tostring(#mine()))
    else
        print('this SacredGear.dll has no Creature:remove: the wave creatures stay (a throw-away game copy)')
    end

    finish()
end)
