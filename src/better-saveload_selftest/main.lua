-- A self test of the Better SaveLoad mod, for runs without a player (on a copy of the game folder: it saves and
-- deletes a savegame):
--
--     Sacred.exe -gear-auto -gear-instance=saveload -gear-mods=better-saveload,better-saveload_selftest
--
-- In the menus: opens the start menu's Load game screen (its 5th entry), checks that the mod's screen replaces it,
-- the filters and the order, that the game's own screen comes back when the mod stops drawing (and that the mod's
-- screen is back the next time it opens), then loads a savegame with Enter. In game: opens the savegame window (S),
-- saves a new savegame from the mod's screen, opens it again, deletes that savegame (Delete, Enter on the question)
-- and closes the screen with its Back button. Results and screenshots in GearAutomation\<instance>.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0}
local WND_GAME, WND_MENUS = 'UI_WND_SAVEGAME', 'UI_MENU_LOADGAME'
local LOAD_ENTRY = {512, 413}       -- the start menu's 5th entry (Load game), 1024x768 layout
local BACK_BUTTON = {854, 673}      -- the screen's Back button at the panel's default place and size

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('saveload.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function query()
    local out = {}
    gear.emit('better-saveload.query', out)
    return out
end

local function wait_open(name, want, timeout)
    return gear.wait_until(function() return gear.ui.window_open(name) == want end, timeout or 5)
end

local function wait_screen(name, timeout)
    return gear.wait_until(function() return query().open == name end, timeout or 5)
end

local saved = {}
gear.on('game.saved', function(slot) saved[#saved + 1] = slot end)
gear.on('game.save_failed', function(slot, msg) saved[#saved + 1] = {slot = slot, failed = msg} end)

local function slots()
    local set = {}
    for _, s in ipairs(gear.game.saves()) do set[s.slot] = s end
    return set
end

local function stamp(s)
    return s.time > 0 and s.time or s.mtime
end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    gear.wait(2)
    local before = gear.game.saves()
    results.saves = before
    check('savegames listed', #before > 0, #before)
    local with_hero, with_picture = 0, 0
    for _, s in ipairs(before) do
        if s.hero then with_hero = with_hero + 1 end
        if s.picture then with_picture = with_picture + 1 end
    end
    check('savegames have a hero', with_hero > 0, with_hero)
    check('savegames have a picture', with_picture > 0, with_picture)
    check('picture id', before[1] ~= nil and gear.game.save_picture(before[1].slot) ~= nil)

    -- The menus' Load game screen.
    A.ui_click(LOAD_ENTRY[1], LOAD_ENTRY[2])
    check('load game screen opens', wait_open(WND_MENUS, true))
    check('the mod\'s screen replaces it', wait_screen(WND_MENUS))
    local q = query()
    check('screen lists the savegames', q.count == #before, ('%s of %d'):format(tostring(q.count), #before))
    check('menus: load mode', q.mode == 'load', q.mode)
    gear.wait(1)
    A.screenshot('menu_load')

    -- Filters and order.
    local all = q.shown
    if #q.classes > 1 then
        gear.emit('better-saveload.set', {class_i = 2})
        q = query()
        local want = q.classes[2]
        local ok = q.shown > 0 and q.shown <= all
        local set = slots()
        for _, slot in ipairs(q.order) do
            if set[slot].class ~= want then ok = false end
        end
        check('class filter', ok, ('%s: %d of %d'):format(want, q.shown, all))
        gear.wait(0.5)
        A.screenshot('menu_filter_class')
        gear.emit('better-saveload.set', {class_i = 1})
    end
    q = query()
    if #q.heroes > 1 then
        gear.emit('better-saveload.set', {hero_i = 2})
        q = query()
        local want = q.heroes[2]
        local ok = q.shown > 0
        local set = slots()
        for _, slot in ipairs(q.order) do
            if set[slot].hero ~= want then ok = false end
        end
        check('character filter', ok, ('%s: %d'):format(want, q.shown))
        gear.emit('better-saveload.set', {hero_i = 1})
    end
    gear.emit('better-saveload.set', {sort_i = 1})
    q = query()
    local set = slots()
    local newest_ok = true
    for i = 2, #q.order do
        if stamp(set[q.order[i - 1]]) < stamp(set[q.order[i]]) then newest_ok = false end
    end
    check('newest first', newest_ok and q.sort == 'newest')
    gear.emit('better-saveload.set', {sort_i = 2})
    q = query()
    local file_ok = #q.order == #before
    for i, s in ipairs(before) do
        if q.order[i] ~= s.slot then file_ok = false end
    end
    check('by file name', file_ok and q.sort == 'file')
    gear.wait(0.5)
    A.screenshot('menu_by_file')
    gear.emit('better-saveload.set', {sort_i = 1})

    -- Keyboard: Down moves the selection to the next one listed.
    q = query()
    local at = 1
    for i, slot in ipairs(q.order) do
        if slot == q.sel then at = i end
    end
    A.press('down')
    gear.wait(0.3)
    local want = q.order[math.min(at + 1, #q.order)]
    check('Down moves the selection', query().sel == want, tostring(q.sel) .. ' -> ' .. tostring(query().sel))

    -- The controller: the screen has the pad alone (SacredBild's stops are the screen's widgets, modal).
    local stops, flags = A.nav()
    results.nav = {stops = stops, flags = flags}
    check('controller: the screen widgets are the stops, modal', stops == -2 or (stops > 5 and flags % 2 == 1),
        ('%d stops, flags %d'):format(stops, flags))

    -- The game's own screen comes back when the mod stops drawing.
    gear.emit('better-saveload.stall', true)
    gear.wait(2.5)
    check('stalled: the mod\'s screen is gone', query().open == nil)
    check('stalled: the game\'s screen is still open', gear.ui.window_open(WND_MENUS))
    A.screenshot('menu_fallback')
    gear.emit('better-saveload.stall', false)
    gear.wait(0.5)
    check('lapsed: the game\'s screen until it closes', query().open == nil)
    check('close_window closes it', gear.ui.close_window(WND_MENUS) and wait_open(WND_MENUS, false))
    gear.wait(1.5)
    A.ui_click(LOAD_ENTRY[1], LOAD_ENTRY[2])
    check('reopened: the mod\'s screen again', wait_screen(WND_MENUS))

    -- Load the first compatible savegame with a hero (not the quicksave), with Enter.
    local target
    for _, s in ipairs(before) do
        if s.compatible and s.slot ~= 0 and s.hero then target = s break end
    end
    if not target then
        check('a savegame to load', false)
        return finish()
    end
    results.loaded = target.slot
    gear.emit('better-saveload.set', {sel = target.slot})
    gear.wait(0.3)
    A.press('enter')
    local game = A.wait_for_game(cfg.timeout_game)
    check('loaded from the mod\'s screen', game, target.file)
    if not game then return finish() end
    gear.wait(4)
    local h = gear.world.hero()
    check('the loaded hero', h ~= nil and h:name() == target.hero, h and h:name())

    -- In game: S opens the savegame window, the mod's screen shows in save mode.
    A.press('s')
    local s_ok = wait_open(WND_GAME, true)
    if not s_ok then
        -- Right after loading the game may not take the key yet: once more.
        A.screenshot('s_failed')
        A.press('s')
        s_ok = wait_open(WND_GAME, true)
    end
    check('savegame window opens', s_ok)
    check('game: the mod\'s screen replaces it', wait_screen(WND_GAME))
    q = query()
    check('game: save mode, the new savegame row', q.mode == 'save' and q.sel == 'new',
        tostring(q.mode) .. ' ' .. tostring(q.sel))
    gear.wait(1)
    check('a default name', (q.name or '') ~= '', q.name)
    -- Typing: the keys go into the name (the player's keyboard layout, through gear.ui.typed).
    gear.emit('better-saveload.set', {name = ''})
    A.type('mein test 42')
    gear.wait(0.5)
    check('typed into the name', query().name == 'mein test 42', query().name)
    A.press('backspace')
    gear.wait(0.3)
    check('Backspace', query().name == 'mein test 4', query().name)
    -- The on-screen keyboard (for the controller).
    A.ui_click(BACK_BUTTON[1] - 30, BACK_BUTTON[2] - 32)
    gear.wait(0.3)
    check('the on-screen keyboard opens', query().osk == true)
    A.screenshot('game_osk')
    A.pad(0, 1, 0)
    gear.wait(0.3)
    check('B closes the keyboard, not the screen', query().osk == false and gear.ui.window_open(WND_GAME))
    -- A name beyond ASCII comes back as it was saved.
    local NAME = 'Größe über alles 42'
    gear.emit('better-saveload.set', {name = NAME})
    gear.wait(0.3)
    A.screenshot('game_save')
    local had = slots()
    A.press('enter')
    check('save closes the window', wait_open(WND_GAME, false))
    check('saved', gear.wait_until(function() return #saved > 0 end, 30), saved[1])
    local new_slot = type(saved[1]) == 'number' and saved[1] or nil
    check('a new savegame', new_slot ~= nil and not had[new_slot] and slots()[new_slot] ~= nil, new_slot)
    results.saved = new_slot
    gear.wait(2)

    -- The load tab: the new savegame is the newest; delete it.
    A.press('s')
    check('reopened in game', wait_screen(WND_GAME))
    gear.emit('better-saveload.set', {mode = 'load', sel = new_slot})
    gear.wait(0.5)
    q = query()
    check('the new savegame is the newest', q.order[1] == new_slot, q.order[1])
    local ns = new_slot and slots()[new_slot]
    check('the new savegame has the hero', ns and h and ns.hero == h:name(), ns and ns.hero)
    check('the new savegame has a picture', ns and ns.picture)
    check('the typed name was saved (umlauts too)', ns and ns.name == NAME, ns and ns.name)
    A.screenshot('game_load')
    A.press('delete')
    gear.wait(0.3)
    check('delete asks', query().confirm ~= nil, query().confirm)
    A.screenshot('game_delete_question')
    A.press('enter')
    gear.wait(0.5)
    check('deleted', new_slot ~= nil and slots()[new_slot] == nil)
    -- The Back button: a real click on the screen's widget (at its default place).
    if not gear.ui.layout()['better-saveload:screen'] then
        A.ui_click(BACK_BUTTON[1], BACK_BUTTON[2])
        check('Back closes the window', wait_open(WND_GAME, false))
    end
    if gear.ui.window_open(WND_GAME) then
        A.press('escape')
        check('Esc closes the window', wait_open(WND_GAME, false))
    end
    -- The controller's B closes it too.
    gear.wait(1)
    A.press('s')
    check('reopened for B', wait_screen(WND_GAME))
    check('in game it opens on the Save tab (after the Load tab was used)', query().mode == 'save', query().mode)
    A.pad(0, 1, 0)
    check('B closes the window', wait_open(WND_GAME, false))
    gear.wait(1)
    A.screenshot('game_after')
    finish()
end)
