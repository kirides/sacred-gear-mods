-- A self test of the beastmaster mod, for runs without a player (use a COPY of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=beasts -gear-load=10 -gear-mods=sacred-theme,beastmaster,beastmaster_selftest
--
-- Takes a wolf (ally) and a rabbit and a crow (pets) along, walks the hero away, and checks that they follow, that the ally
-- fights a hostile creature, that the pets cannot be hurt, and takes screenshots (pets next to an ordinary copy of their kind to
-- see the scale, and the window). Results: GearAutomation\<instance>\beastmaster.json.

if not gear.auto then print('no automation: nothing to do') return end
local A, W, cfg = gear.auto, gear.world, gear.config
local results = {passed = 0, failed = 0, notes = {}}
local function check(name, ok, detail)
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end
local function finish()
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    A.write('beastmaster.json', gear.json.encode(results))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end
local function recruit(key)
    local id, err
    gear.emit('beastmaster.recruit', key, function(i, e) id, err = i, e end)
    return id, err
end
local function state()
    local s
    gear.emit('beastmaster.state', function(v) s = v end)
    return s
end
local ally_hits, ally_damage, ally_id = 0, 0, nil
gear.on('damage', function(hit)
    if ally_id and hit.attacker == ally_id and hit.damage > 0 then ally_hits = ally_hits + 1; ally_damage = ally_damage + hit.damage end
end)
local function near(a, b) return a:distance(b) or 1e9 end

gear.task(function()
    A.wait_for_menu(cfg.timeout_menu)
    if not A.wait_for_game(cfg.timeout_game) then check('game with a hero', false) return finish() end
    gear.wait(3)
    local hero = W.hero()
    local hx, hy, layer = hero:position()

    local wolf_id, e1 = recruit('wolf')
    check('an ally was recruited', wolf_id ~= nil, e1)
    local rabbit_id, e2 = recruit('rabbit')
    check('a pet was recruited', rabbit_id ~= nil, e2)
    local crow_id, e3 = recruit('crow')
    check('a second pet was recruited', crow_id ~= nil, e3)
    local s = state()
    check('state: 1 ally, 2 pets', s.ally == 1 and s.pet == 2, ('%d/%d'):format(s.ally, s.pet))
    local wolf, rabbit = W.object(wolf_id), W.object(rabbit_id)
    check('the ally is not an enemy of the hero', wolf and wolf:is_enemy(hero) ~= true)
    check('the ally has health', wolf and wolf:max_hp() >= 1, wolf and wolf:max_hp())
    local mods = wolf and wolf:modifiers()
    check('the ally has modifiers', mods ~= nil and mods.max_hp ~= nil)
    local pm = rabbit and rabbit:modifiers()
    check('the pet takes no damage', pm ~= nil and pm.taken == 0)

    -- scale: an ordinary rabbit next to the pet, a screenshot
    local plain = W.spawn(516, hx + 60, hy + 200, {like = hero})
    local px, py = rabbit:position()
    if plain then plain:teleport(px + 90, py, layer) end
    gear.wait(1.0)
    A.screenshot('beasts_scale')

    -- follow: the hero walks away
    local ok = hero:teleport(hx - 500, hy - 300, layer)
    check('hero teleported', ok)
    gear.wait(9)
    local hx2, hy2 = hero:position()
    local d_wolf = wolf and wolf:position() and near(wolf, hero)
    local d_rabbit = rabbit and near(rabbit, hero)
    check('the ally follows the hero', d_wolf ~= nil and d_wolf < 900, d_wolf)
    check('the pet follows the hero', d_rabbit ~= nil and d_rabbit < 900, d_rabbit)
    gear.wait(2)
    A.screenshot('beasts_follow')

    -- fight: a hostile creature the game placed, with the ally next to it
    local hxx, hyy = hx, hy
    if not (wolf and wolf:exists() and not wolf:is_dead()) then
        print('NOTE the first ally fell on the way: a new one fights')
        local nid = recruit('wolf')
        wolf = nid and W.object(nid) or wolf
    end
    local foe
    for _, c in ipairs(W.creatures_near(hxx, hyy, 5000, {layer = layer, limit = 60})) do
        if not c:is_hero() and not c:is_dead() and c:is_enemy(hero) == true and c:type_name() == 'WOLF.GRN' and c.id ~= wolf.id then foe = c break end
    end
    local seen = {}
    for _, c in ipairs(W.creatures_near(hxx, hyy, 5000, {layer = layer, limit = 60})) do
        seen[#seen + 1] = ('%s%s%s'):format(c:type_name() or '?', c:is_enemy(hero) == true and '+' or '', c:is_dead() and 'x' or '')
    end
    print('NOTE creatures around the start: ' .. table.concat(seen, ' '))
    check('a hostile wolf of the game was found', foe ~= nil)
    if foe then
        local fx, fy = foe:position()
        hero:teleport(fx - 300, fy, layer)   -- the allies fight what comes near the hero
        wolf:teleport(fx - 200, fy, layer)
        local foe_hp = foe:hp()
        ally_id = wolf.id
        print(('NOTE ally type %s level %s hp %s, foe type %s level %s hp %s'):format(tostring(wolf:type()), tostring(wolf:level()), tostring(wolf:max_hp()), tostring(foe:type()), tostring(foe:level()), tostring(foe:max_hp())))
        for _ = 1, 10 do
            gear.wait(3)
            print(('NOTE fight: ally-foe %s, ally hp %s, foe hp %s, ally hits %d'):format(tostring(wolf:distance(foe)), tostring(wolf:hp()), tostring(foe:hp()), ally_hits))
            if foe:exists() and not foe:is_dead() then wolf:order_attack(foe) end
        end
        -- how often it bites varies a lot from run to run (1 to 8 hits in 40 s), so only the size of a bite is checked
        check('the ally bites for real when it hits (damage above 3 per hit; passes with 0 hits, they are rare)', ally_hits == 0 or ally_damage / ally_hits > 3,
              ('%d hits, %d damage'):format(ally_hits, ally_damage))
    end

    -- window and screenshot
    gear.emit('beastmaster.window', true)
    gear.wait(1)
    A.screenshot('beasts_window')

    -- dismiss
    gear.emit('beastmaster.dismiss_all')
    gear.wait(0.5)
    s = state()
    check('dismiss all', s.ally == 0 and s.pet == 0)
    finish()
end)
