-- A test of savegame numbers beyond 99 / 509 and of Better SaveLoad's screen with hundreds of savegames, for runs
-- without a player. It needs a COPY of the game folder whose Save folder was filled by tools/make_test_saves.py:
--
--     python tools/make_test_saves.py "<copy>\Save" 300 100 509
--     Sacred.exe -gear-auto -gear-instance=manysaves -gear-mods=better-saveload,better-saveload_manysaves_selftest
--
-- Checks the list (numbers up to 32766), the first free number and reserved numbers, the screen's search, orders and
-- jumps, loads savegame 32766 and saves a new one beyond 509. Results: GearAutomation\<instance>\manysaves.json.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0}
local WND_GAME, WND_MENUS = 'UI_WND_SAVEGAME', 'UI_MENU_LOADGAME'
local LOAD_ENTRY = {512, 413}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('manysaves.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function query()
    local out = {}
    gear.emit('better-saveload.query', out)
    return out
end

local function set(t) gear.emit('better-saveload.set', t) end

local function wait_open(name, want, timeout)
    return gear.wait_until(function() return gear.ui.window_open(name) == want end, timeout or 5)
end

local function by_slot(list)
    local m = {}
    for _, s in ipairs(list) do m[s.slot] = s end
    return m
end

local function stamp(s) return s.time > 0 and s.time or s.mtime end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    gear.wait(2)

    ---- The list and the API -------------------------------------------------------------------------------------
    local t0 = os.clock()
    local list = gear.game.saves()
    local took = os.clock() - t0
    local set_ = by_slot(list)
    results.count = #list
    check('hundreds of savegames listed', #list >= 500, #list)
    check('slot 1000 / 12345 / 32766 listed', set_[1000] and set_[12345] and set_[32766],
        (set_[32766] or {}).file)
    check('file name of a 5 digit number', set_[32766] ~= nil and set_[32766].file == 'GAME32766.PAK')
    check('their hero and name are read', set_[12345] and set_[12345].hero ~= nil and set_[12345].name:find('12345', 1, true),
        set_[12345] and (tostring(set_[12345].hero) .. ' / ' .. set_[12345].name))
    t0 = os.clock()
    gear.game.saves()
    check('a second listing uses the cache (fast)', os.clock() - t0 < math.max(0.05, took / 2),
        ('%.3f s after %.3f s'):format(os.clock() - t0, took))
    check('save_info up to 32766', gear.game.save_info(32766).exists and gear.game.save_info(32767) == nil)
    check('scope_of for a high number', gear.savegame.scope_of(32766) == 'GAME32766', gear.savegame.scope_of(32766))
    local free = gear.game.free_slot()
    results.free = free
    check('free_slot is beyond 509 (1..509 are taken)', free == 510, free)
    -- The engine's own picker (the function a new savegame without a number asks; it stopped at 509) is replaced.
    check("the game's own first free number looks beyond 509", A.engine_free_slot() == 510, A.engine_free_slot())
    gear.game.reserve_slots({510, 511})
    check('... and skips reserved numbers', A.engine_free_slot() == 512, A.engine_free_slot())
    check('reserved slots are skipped', gear.game.free_slot() == 512, gear.game.free_slot())
    gear.game.reserve_slots({})
    check('reservation released', gear.game.free_slot() == 510, gear.game.free_slot())

    ---- The menus' screen -----------------------------------------------------------------------------------------
    A.ui_click(LOAD_ENTRY[1], LOAD_ENTRY[2])
    check('load game screen opens', wait_open(WND_MENUS, true))
    check('the mod\'s screen replaces it', gear.wait_until(function() return query().open == WND_MENUS end, 5))
    gear.wait(1.5)
    local q = query()
    check('the screen lists them all', q.count == #list and q.shown == #list, ('%s / %s of %d'):format(q.count, q.shown, #list))
    A.screenshot('many_load')

    -- Search: typed text narrows the list (hero, name, number, date); the words are ANDed.
    A.type('gwyn')
    gear.wait(0.4)
    q = query()
    local want = 0
    for _, s in ipairs(list) do
        if (s.hero and s.hero:lower():find('gwyn', 1, true)) or s.name:lower():find('gwyn', 1, true) or
            s.file:lower():find('gwyn', 1, true) then want = want + 1 end
    end
    check('typing searches', q.search == 'gwyn' and q.shown == want and want > 0 and want < #list,
        ('%s: %d (expected %d)'):format(q.search, q.shown, want))
    A.screenshot('many_search')
    A.type(' 15')
    gear.wait(0.3)
    q = query()
    local shown = {}
    for _, slot in ipairs(q.order) do shown[#shown + 1] = set_[slot].file end
    check('two words: both must match', q.shown >= 1 and q.shown < want, table.concat(shown, ' ', 1, math.min(#shown, 6)))
    for _ = 1, 3 do A.press('backspace') end
    gear.wait(0.3)
    check('Backspace edits the search', query().search == 'gwyn', query().search)
    A.press('escape')
    gear.wait(0.3)
    q = query()
    check('Esc clears the search first, the screen stays', q.search == '' and q.open == WND_MENUS and q.shown == #list,
        ('%q %s %d'):format(q.search, tostring(q.open), q.shown))
    set({search = 'no such savegame anywhere'})
    gear.wait(0.3)
    check('nothing matches', query().shown == 0)
    A.screenshot('many_nomatch')
    set({search = ''})
    gear.wait(0.3)

    -- Orders.
    local function ordered(cmp)
        local o = query().order
        for i = 2, #o do
            if cmp(set_[o[i - 1]], set_[o[i]]) == false then return false, i end
        end
        return #o > 0
    end
    set({sort_i = 1})
    check('order: newest first', ordered(function(a, b) return stamp(a) >= stamp(b) end))
    set({sort_i = 2})
    check('order: oldest first', ordered(function(a, b) return stamp(a) <= stamp(b) end))
    set({sort_i = 3})
    check('order: by character', ordered(function(a, b) return (a.hero or ''):lower() <= (b.hero or ''):lower() end))
    set({sort_i = 4})
    check('order: highest level first', ordered(function(a, b) return a.level >= b.level end))
    set({sort_i = 5})
    check('order: by number', ordered(function(a, b) return a.slot < b.slot end))
    q = query()
    check('by number: 32766 is the last', q.order[#q.order] == 32766, q.order[#q.order])
    set({sort_i = 1})
    gear.wait(0.3)

    -- Jumps: End, Home, Page down (a page is the rows that fit, less one).
    q = query()
    local first = q.order[1]
    A.press('end')
    gear.wait(0.4)
    q = query()
    check('End selects the last', q.sel == q.order[#q.order], tostring(q.sel))
    A.screenshot('many_end')
    A.press('home')
    gear.wait(0.4)
    q = query()
    check('Home selects the first', q.sel == q.order[1] and q.sel == first, tostring(q.sel))
    A.press('pagedown')
    gear.wait(0.3)
    q = query()
    check('Page down moves by a page', q.sel == q.order[1 + q.page] and q.page > 3, ('%s page %d'):format(tostring(q.sel), q.page))
    A.press('pageup')
    gear.wait(0.3)
    check('Page up moves back', query().sel == first)

    -- The controller: the screen's widgets (search, jumps, the list) are the stops.
    local stops, flags = A.nav()
    check('controller: widgets are the stops, modal', stops == -2 or (stops > 8 and flags % 2 == 1),
        ('%d stops, flags %d'):format(stops, flags))

    ---- Loading savegame 32766 -----------------------------------------------------------------------------------
    set({sel = 32766})
    gear.wait(0.3)
    A.press('enter')
    local game = A.wait_for_game(cfg.timeout_game)
    check('savegame 32766 loads', game)
    if not game then return finish() end
    gear.wait(4)
    local h = gear.world.hero()
    check('the loaded hero', h ~= nil and h:name() == set_[32766].hero, h and h:name())
    check('scope of the loaded game', gear.savegame.scope() == 'GAME32766', gear.savegame.scope())

    ---- Saving beyond 509 ----------------------------------------------------------------------------------------
    A.press('s')
    local ok = wait_open(WND_GAME, true)
    if not ok then A.press('s') ok = wait_open(WND_GAME, true) end
    check('savegame window opens', ok)
    check('game: the mod\'s screen', gear.wait_until(function() return query().open == WND_GAME end, 5))
    gear.wait(1)
    check('save mode, the new savegame row', query().mode == 'save' and query().sel == 'new')
    set({name = 'beyond 509'})
    gear.wait(0.3)
    local saved
    gear.on('game.saved', function(slot) saved = slot end)
    -- Enter saves the selected "new savegame".
    A.press('enter')
    check('save window closes', wait_open(WND_GAME, false))
    check('saved', gear.wait_until(function() return saved ~= nil end, 30), saved)
    check('the new savegame took the first free number (510)', saved == 510 and gear.game.save_info(510).exists, saved)
    gear.wait(2)
    local fresh = by_slot(gear.game.saves())
    check('it is listed with the typed name', fresh[510] and fresh[510].name == 'beyond 509' and fresh[510].hero == h:name(),
        fresh[510] and fresh[510].name)
    check('a second new savegame would be 511', gear.game.free_slot() == 511, gear.game.free_slot())
    -- The savegame loads again.
    check('load works for it', gear.game.load(510) == true)
    check('the loaded game', A.wait_for_game(cfg.timeout_game))
    gear.wait(4)
    check('scope after loading 510', gear.savegame.scope() == 'GAME510', gear.savegame.scope())
    finish()
end)
