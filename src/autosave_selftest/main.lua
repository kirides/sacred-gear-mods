-- A self test of the autosave mod, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=autosave -gear-load=1 -gear-mods=autosave,autosave_selftest
--
-- loads savegame 1, checks that the timer stops in the escape menu, sets a tiny interval, waits for four autosaves and
-- checks the rotation through the slots 97, 98, 99, 97 (oldest file first), that the quicksave and the loaded
-- savegame were not touched and that the game keeps running. The hero's state at each save goes to
-- GearAutomation\<instance>\autosave.json. A second run with -gear-instance=autosave-verify -gear-load=<slot> only
-- records the loaded hero (hero.json) to compare with it.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0, saves = {}}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('autosave.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function hero_summary()
    local h = gear.world.hero()
    if not h then return nil end
    local x, y, layer = h:position()
    return {level = h:level(), gold = h:gold(), exp = h:experience(), hp = h:hp(), max_hp = h:max_hp(),
        x = x, y = y, layer = layer, type = h:type_name()}
end

local function query()
    local out = {}
    gear.emit('autosave.query', out)
    return out
end

local function same_file(a, b)
    return a and b and a.exists == b.exists and a.size == b.size and a.mtime == b.mtime
end

gear.task(function()
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    local game = A.wait_for_game(cfg.timeout_game)
    check('game with a hero', game)
    if not game then return finish() end
    gear.wait(3)

    if A.instance:find('verify', 1, true) then
        -- The restore check: what the loaded autosave contains.
        local s = hero_summary()
        check('hero loaded', s ~= nil)
        A.write('hero.json', gear.json.encode(s or {}))
        A.screenshot('verify')
        return finish()
    end

    results.initial = query()    -- what the mod manager's settings (mods\gear_mods.json) made of the mod
    local game_api = gear.game
    local ok, why = game_api.can_save()
    check('can_save in the game', ok, why)

    local slots = {97, 98, 99}
    local before = {}
    for _, s in ipairs({0, 1, 97, 98, 99}) do before[s] = game_api.save_info(s) end
    check('quicksave / loaded save info readable', before[0] ~= nil and before[1] ~= nil and before[1].exists,
        before[1] and (before[1].size .. ' bytes'))
    -- The expected order: free slots first (in order), then the oldest file.
    local order = {}
    for _, s in ipairs(slots) do order[#order + 1] = s end
    table.sort(order, function(a, b)
        local ta = before[a].exists and before[a].mtime or -1
        local tb = before[b].exists and before[b].mtime or -1
        if ta ~= tb then return ta < tb end
        return a < b
    end)

    -- The timer stops while the escape menu is open.
    gear.emit('autosave.configure', {enabled = true, interval_minutes = 30, slots = slots})
    local a0 = query().active_seconds
    A.press('escape')
    check('escape menu opens', gear.wait_until(function() return gear.ui.state().escape_menu end, 10))
    local a1 = query().active_seconds
    gear.wait(3)
    local a2 = query().active_seconds
    check('timer stopped in the escape menu', a2 - a1 < 0.3, ('%.2f s'):format(a2 - a1))
    A.press('escape')
    check('escape menu closes', gear.wait_until(function() return not gear.ui.state().escape_menu end, 10))
    local can, reason = game_api.can_save()
    gear.wait(2)
    local a3 = query().active_seconds
    check('timer runs again', a3 - a2 >= 1.5, ('%.2f s over 2 s'):format(a3 - a2))

    -- The autosaves.
    local saved, failed = {}, {}
    gear.on('game.saved', function(slot, info)
        local s = hero_summary()
        saved[#saved + 1] = slot
        results.saves[#results.saves + 1] = {slot = slot, size = info.size, mtime = info.mtime, hero = s}
        print(('game.saved %d (%d bytes)'):format(slot, info.size))
    end)
    gear.on('game.save_failed', function(slot, message)
        failed[#failed + 1] = slot .. ': ' .. tostring(message)
    end)
    local frames_before = query().total_active_seconds
    gear.emit('autosave.configure', {interval_minutes = cfg.interval_minutes})
    check('autosaves arrive', gear.wait_until(function() return #saved >= cfg.saves end, 20 * cfg.saves),
        #saved .. ' of ' .. cfg.saves)
    check('no failures', #failed == 0, table.concat(failed, '; '))
    local expected = {order[1], order[2], order[3], order[1]}
    for i = 1, math.min(#saved, cfg.saves) do
        check(('autosave %d slot'):format(i), saved[i] == expected[i], ('%s (expected %s)'):format(tostring(saved[i]), expected[i]))
    end
    for _, s in ipairs(slots) do
        local info = game_api.save_info(s)
        check(('slot %d written'):format(s), info.exists and info.size > 0, info.size)
    end
    check('quicksave untouched', same_file(before[0], game_api.save_info(0)))
    check('loaded savegame untouched', same_file(before[1], game_api.save_info(1)))
    check('game keeps running', query().total_active_seconds > frames_before and gear.world.hero() ~= nil
        and not gear.world.hero():is_dead())
    gear.emit('autosave.configure', {enabled = false})
    check('save_pending false at the end', not game_api.save_pending())
    A.screenshot('autosave')
    finish()
end)
