-- A self test of the companions mod, for runs without a player (use a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=companions -gear-load=N -gear-mods=companions,companions_selftest
--
-- needs a single player savegame with hostile creatures within ~30 tiles of the hero. It recruits through the party
-- window (Ctrl+F8, the Recruit button), checks the name the mod gives, that the companion follows the hero and fights
-- an enemy with its combat art, that a click on its portrait plays it and F8 plays the next hero, and that the
-- former hero now follows and fights on its own. Results: GearAutomation\<instance>\companions.json, screenshots.

if not gear.auto then return end

local A = gear.auto
local cfg = gear.config
local party = gear.party
local results = {checks = {}, passed = 0, failed = 0}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('companions.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function chord(mod, key)
    A.key_down(mod)
    gear.wait(0.05)
    A.press(key)
    A.key_up(mod)
    gear.wait(0.05)
end

local function dist(a, b)
    local ax, ay = a:position()
    local bx, by = b:position()
    if not ax or not bx then return 1e9 end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function enemy_near(hero, radius)
    local x, y, layer = hero:position()
    for _, c in ipairs(gear.world.creatures_near(x, y, radius, {layer = layer})) do
        if not c:is_dead() and not c:is_hero() and hero:is_enemy(c) then return c end
    end
end

-- The rectangle of a mod panel (layout coordinates) by its key, nil if it is not shown.
local function panel_rect(key)
    for _, p in ipairs(gear.ui.panels() or {}) do
        if p.key == key and p.open ~= false then return p end
    end
end

gear.task(function()
    A.wait_for_menu(cfg.timeout_menu)
    if not A.wait_for_game(cfg.timeout_game) then check('game', false) return finish() end
    gear.wait(3)
    local main = party.leader()
    check('a hero, no companions yet', main ~= nil and #party.companions() == 0, #party.companions())

    -- Recruit through the party window: Ctrl+F8, then its Recruit button (the second widget row from the bottom).
    chord('control', 'f8')
    gear.wait(1)
    local p = panel_rect('companions:party')
    check('party window opens', p ~= nil)
    A.screenshot('companions-1-window')
    if p then
        local nodes = {}
        -- the Recruit button is drawn at content (220, rows + 6): find it from the panel and click its middle
        local heroes = #party.heroes()
        local cx = p.x + 10 + 220 + 45
        local cy = p.y + 30 + heroes * 52 + 6 + 11
        A.ui_click(cx, cy)
        gear.wait(1.5)
        nodes = party.companions()
        check('Recruit adds a companion', #nodes == 1, #nodes)
    end
    if #party.companions() == 0 then
        party.recruit('darkelf', {experience = main:experience() or 0})
    end
    local comp = party.companions()[1]
    if not comp then check('companion', false) return finish() end
    gear.wait(2.5)
    check('the mod names it', comp:name() ~= nil and not comp:name():find('playername'), comp:name())
    chord('control', 'f8')    -- close the window
    gear.wait(0.5)

    -- It follows: walk the hero away, the companion comes along.
    local hx, hy = main:position()
    main:order_move(hx + 400, hy + 50)
    gear.wait(5)
    check('the companion follows', dist(comp, main) < 6 * gear.world.TILE, math.floor(dist(comp, main)))

    -- It fights: the party goes to the nearest enemy (teleported next to it), the companion engages.
    local foe = enemy_near(main, 3000)
    check('an enemy nearby', foe ~= nil)
    if foe then
        local fx, fy = foe:position()
        local placed = false
        for _, o in ipairs(cfg.fight_offsets or {{250, 250}, {300, 0}, {0, 300}, {-260, 0}, {0, -260}}) do
            if main:teleport(fx + o[1], fy + o[2]) then
                comp:teleport(fx + o[1] * 1.3, fy + o[2] * 1.3)
                placed = true
                break
            end
        end
        check('the party is next to it', placed)
        -- every enemy around: the companion may pick another one than the nearest to the hero
        local foes = {}
        local fx2, fy2, fl2 = comp:position()
        for _, e in ipairs(gear.world.creatures_near(fx2, fy2, 1500, {layer = fl2})) do
            if not e:is_hero() and not e:is_dead() and comp:is_enemy(e) then foes[#foes + 1] = {e, e:hp()} end
        end
        local art = (comp:abilities() or {})[1]
        local used = false
        for _ = 1, 60 do
            gear.wait(0.5)
            local a = art and comp:ability(art.id)
            if a and not a.ready then used = true end
            if used then break end
        end
        gear.wait(1)
        local hurt = 0
        for _, f in ipairs(foes) do
            if f[1]:is_dead() or (f[1]:hp() or f[2]) < f[2] then hurt = hurt + 1 end
        end
        check('the enemies took damage', hurt > 0, hurt .. ' of ' .. #foes)
        check('the companion used its combat art', used, art and art.id)
    end
    A.screenshot('companions-2-fight')

    -- A click on its portrait plays it.
    local pr = panel_rect('companions:portraits')
    check('portraits shown', pr ~= nil)
    if pr then
        A.ui_click(pr.x + 2 + 31, pr.y + 2 + 31)
        gear.wait(1.5)
        check('portrait click plays the companion', party.leader() == comp)
    end
    A.screenshot('companions-3-played')

    -- The former hero follows and fights now.
    local cx, cy = comp:position()
    comp:order_move(cx - 400, cy + 60)
    local acted = gear.wait_until(function()
        local act = main:action()
        return dist(main, comp) < 6 * gear.world.TILE or act == 'attacking' or act == 'ability'
    end, 12)
    check('the former hero follows or fights', acted, math.floor(dist(main, comp)) .. ' ' .. tostring(main:action()))

    -- F8 plays the next hero (back to the main one).
    A.press('f8')
    gear.wait(1.5)
    check('F8 plays the next hero', party.leader() == main)
    A.screenshot('companions-4-back')

    -- The controller: the portrait is a D-pad stop, and the mod menu (LT + LB) plays the next hero. Its entries:
    -- the Mods screen, then the companions' keys (next, previous, window), rows of 30 from the content.
    local n = A.nav()
    check('portraits are D-pad stops (SacredBild holds stops)', n and n >= 1, n)
    A.pad(0, 0, 1)
    gear.wait(0.5)
    local menu = panel_rect('gear-mods:padmenu')
    check('the mod menu opens', menu ~= nil)
    A.screenshot('companions-5-padmenu')
    if menu then
        A.ui_click(menu.x + menu.w / 2, menu.y + 28 + 30 + 13)
        gear.wait(1.5)
        check('the mod menu plays the next hero', party.leader() == comp)
    end
    finish()
end)
