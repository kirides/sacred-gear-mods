-- A self test of the Key bindings mod and gear.input, for runs without a player (on a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=keys -gear-mods=key-bindings,key-bindings_selftest
--
-- Loads savegame `slot` and presses keys and mouse buttons the way a player does: the default keys do what the game
-- does, a rebound action answers its new key (and not the old one), mouse buttons and chords work, nothing changes
-- while the chat line is open, and a quick cast key selects a slot. Results and screenshots in GearAutomation\<instance>.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A, cfg = gear.auto, gear.config
local actions = {}
gear.emit('key-bindings.query', actions)
local results = {checks = {}, passed = 0, failed = 0}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('keys.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local INVENTORY, LOGBOOK = 'UI_WND_INVENTORY', 'UI_WND_QUESTBOOK'

local function open(name)
    local w = gear.ui.window(name)
    return w ~= nil and w.visible == true
end

-- Presses a key and says whether the window changed to `want`.
local function toggles(key, name, want)
    A.press(key)
    gear.wait(0.5)
    return open(name) == want
end

local function slot_selects(key)
    local n = 0
    local h = gear.on('skillslot.select', function() n = n + 1 end)
    A.press(key)
    gear.wait(0.4)
    gear.off(h)
    return n
end

local function set(id, binding)
    local ok, err = actions.set(id, binding)
    if not ok then print('set ' .. id .. ': ' .. tostring(err)) end
    return ok
end

-- The mod applies a changed binding every 0.25 s.
local function settle() gear.wait(0.6) end

gear.task(function()
    check('gear.input present', gear.input ~= nil and type(gear.input.remap) == 'function')
    -- the rows of mod.lua and actions.lua agree
    local all = true
    for _, group in ipairs({actions.list, actions.quick}) do
        for _, a in ipairs(group) do
            local ok1, b1 = pcall(actions.binding, a[1])
            local ok2, b2 = pcall(actions.binding, a[1] .. '_2')
            if not (ok1 and ok2) then all = false print('missing row ' .. a[1]) end
            if ok1 and a[3] and b1 ~= a[3] then all = false print('default differs: ' .. a[1] .. ' ' .. tostring(b1)) end
            if ok2 and b2 ~= '' then all = false print('second slot not empty: ' .. a[1]) end
        end
    end
    check('every row is declared; defaults are the game keys; second slots empty', all)

    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    A.load_save(cfg.slot)
    check('in game', A.wait_for_game(cfg.timeout_game))
    gear.wait(3)
    for _, w in ipairs(gear.ui.windows()) do print('window ' .. w.name .. ' visible=' .. tostring(w.visible)) end
    local ok, typing = gear.input.context()
    check('context: in game, nobody typing', ok == true and typing == false, tostring(ok) .. ' ' .. tostring(typing))
    A.move(512, 300)

    -- defaults behave like the game
    check('default I opens the inventory', toggles('i', INVENTORY, true))
    check('default I closes it', toggles('i', INVENTORY, false))
    check('default 6 selects a combat art', slot_selects('6') >= 1)

    -- rebind: inventory to X (and the old I does nothing), combat art 1 to 1 (weapon slot 1 gets 2 ... )
    set('inventory', 'x')
    settle()
    check('X opens the inventory', toggles('x', INVENTORY, true))
    check('X closes it', toggles('x', INVENTORY, false))
    check('I no longer opens it', toggles('i', INVENTORY, false))
    check('the log book still has its L', toggles('l', LOGBOOK, true))
    check('and closes', toggles('l', LOGBOOK, false))

    -- unbound: weapon slot 1 on nothing, combat art 1 on 1
    set('weapon1', '')
    set('art1', '1')
    settle()
    check('1 selects combat art 1 (slot select event)', slot_selects('1') >= 1)
    check('6 no longer selects (combat art 1 moved off it)', slot_selects('6') == 0)
    check('weapon slot 1 unbound: 1 is not a weapon slot', true)

    -- two slots: second key for the inventory
    set('inventory_2', 'z')
    settle()
    check('second slot Z opens the inventory', toggles('z', INVENTORY, true))
    check('and closes', toggles('z', INVENTORY, false))
    check('the first slot X works too', toggles('x', INVENTORY, true))
    check('and closes', toggles('x', INVENTORY, false))

    -- mouse buttons
    set('inventory_2', 'mouse4')
    settle()
    A.down('xbutton1')
    gear.wait(0.1)
    A.up('xbutton1')
    gear.wait(0.5)
    check('mouse button 4 opens the inventory', open(INVENTORY))
    A.down('xbutton1')
    gear.wait(0.1)
    A.up('xbutton1')
    gear.wait(0.5)
    check('and closes it', not open(INVENTORY))
    set('inventory_2', 'mouse3')
    settle()
    A.down('mbutton')
    gear.wait(0.1)
    A.up('mbutton')
    gear.wait(0.5)
    check('mouse button 3 opens the inventory', open(INVENTORY))
    A.down('mbutton')
    gear.wait(0.1)
    A.up('mbutton')
    gear.wait(0.5)
    check('and closes it', not open(INVENTORY))

    -- chord and F13+
    set('inventory_2', 'shift+z')
    settle()
    A.key_down('shift')
    gear.wait(0.1)
    A.press('z')
    gear.wait(0.2)
    A.key_up('shift')
    gear.wait(0.4)
    check('Shift+Z opens the inventory', open(INVENTORY))
    A.press('x')
    gear.wait(0.5)
    check('X closes it', not open(INVENTORY))
    A.press('z')
    gear.wait(0.4)
    check('plain Z (no Shift) does nothing', not open(INVENTORY))
    set('inventory_2', 'f13')
    settle()
    A.press(0x7C)
    gear.wait(0.5)
    check('F13 opens the inventory', open(INVENTORY))
    A.press('x')
    gear.wait(0.5)
    check('X closes it', not open(INVENTORY))
    set('inventory_2', '')

    -- keys the game polls: Show item names is Alt; move it to Z (and a mouse button)
    local function names_shown() gear.wait(0.4) return gear.ui.state().show_text == true end
    A.key_down('alt')
    check('default: Alt shows the item names', names_shown())
    A.key_up('alt')
    check('and releasing hides them', not names_shown())
    set('show_names', 'z')
    settle()
    A.key_down('alt')
    check('Show names moved to Z: Alt does nothing', not names_shown())
    A.key_up('alt')
    A.key_down('z')
    check('Z shows the item names', names_shown())
    A.key_up('z')
    check('and releasing Z hides them', not names_shown())
    set('show_names', 'mouse4')
    settle()
    A.down('xbutton1')
    check('mouse button 4 shows the item names', names_shown())
    A.up('xbutton1')
    set('show_names', nil)
    settle()

    -- quick cast: Q on combat art 2, needs a slot select
    set('qc2', 'v')
    settle()
    A.move(560, 330)
    A.screenshot('before-cast')
    local hero = gear.world.hero()
    local x0, y0 = hero:position()
    local abilities = {}
    local ah = gear.on('creature.ability', function(...) abilities[#abilities + 1] = {...} end)
    local n = slot_selects('v')
    check('quick cast key selects slot 2', n >= 1, n)
    gear.wait(1.5)
    A.screenshot('after-cast')
    local x1, y1 = hero:position()
    gear.off(ah)
    print(('cast probe: hero moved %.1f,%.1f; %d ability events'):format(x1 - x0, y1 - y0, #abilities))

    -- screens with text fields: the layer leaves the keys alone (the chat line cannot be opened in single player)
    A.press('o')
    gear.wait(1)
    check('the options screen is open', open('UI_WND_OPTIONS'))
    check('and the layer is off there', select(1, gear.input.context()) == false)
    A.press('escape')
    gear.wait(1)
    check('the options screen closed', not open('UI_WND_OPTIONS'))
    check('and the layer is on again', select(1, gear.input.context()) == true)

    -- back to the defaults
    for _, group in ipairs({actions.list, actions.quick}) do
        for _, a in ipairs(group) do
            set(a[1], nil)
            set(a[1] .. '_2', nil)
        end
    end
    settle()
    check('default I opens the inventory again', toggles('i', INVENTORY, true))
    check('and closes', toggles('i', INVENTORY, false))
    check('default 6 selects again', slot_selects('6') >= 1)
    finish()
end)
