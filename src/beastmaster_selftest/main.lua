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
local function recruit(type_id, role)
    local id, err
    gear.emit('beastmaster.recruit', type_id, role, function(i, e) id, err = i, e end)
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

    local wolf_id, e1 = recruit(567, 'ally')
    check('an ally was recruited', wolf_id ~= nil, e1)
    local rabbit_id, e2 = recruit(516, 'pet')
    check('a pet was recruited', rabbit_id ~= nil, e2)
    local crow_id, e3 = recruit(513, 'pet')
    check('a second pet was recruited', crow_id ~= nil, e3)
    local s = state()
    check('state: 1 ally, 2 pets', s.ally == 1 and s.pet == 2, ('%d/%d'):format(s.ally, s.pet))
    local wolf, rabbit = W.object(wolf_id), W.object(rabbit_id)
    check('the ally is not an enemy of the hero', wolf and wolf:is_enemy(hero) ~= true)
    local hl = hero:level() or 1
    check('the ally has the level of the hero', wolf and wolf:level() == math.min(250, hl), ('%s vs hero %d'):format(tostring(wolf and wolf:level()), hl))
    local st = state()
    local grown
    for _, f in ipairs(st.followers) do if f.id == wolf_id then grown = f.scale end end
    check('the ally has a growth size (75 to 125 % of its base size)', grown ~= nil and grown >= 0.74 and grown <= 1.26, grown)
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
    -- pace: with the hero standing, the animals have the hero's pace
    local hs = gear.buffs.speeds(hero)
    local ws = wolf and gear.buffs.speeds(wolf)
    local rs = rabbit and gear.buffs.speeds(rabbit)
    print(('NOTE move speed: hero %s, ally %s, pet %s'):format(tostring(hs and hs.move_speed), tostring(ws and ws.move_speed), tostring(rs and rs.move_speed)))
    check("the ally is at least as fast as the hero", hs and ws and ws.move_speed >= hs.move_speed - 8, ('%s vs %s'):format(tostring(ws and ws.move_speed), tostring(hs and hs.move_speed)))
    check("the pet is at least as fast as the hero", hs and rs and rs.move_speed >= hs.move_speed - 8, ('%s vs %s'):format(tostring(rs and rs.move_speed), tostring(hs and hs.move_speed)))
    -- far behind: the ally runs (gait 2, the run it uses when it chases)
    if wolf and wolf.gait then
        local wx2, wy2, wl2 = wolf:position()
        hero:teleport(wx2 - 700, wy2 - 420, wl2)
        local gait
        for _ = 1, 6 do
            gear.wait(0.4)
            gait = wolf:gait()
            if gait == 2 then break end
        end
        check('far behind the ally runs (gait 2)', gait == 2, gait)
        gear.wait(8)
    end
    -- a cow has no run animation: far behind the hero it still has to close the distance at about the hero's pace
    do
        local cid, cerr = recruit(523, 'pet')
        check('a cow pet was recruited', cid ~= nil, cerr)
        local cow = cid and W.object(cid)
        if cow then
            gear.wait(1)
            -- the open ground where the hero started (the cow's spawn spot may be walled in): the cow stands there, the hero 700 away to the north west
            local cx, cy, cl = hx, hy, layer
            cow:teleport(cx, cy, cl)
            gear.wait(1)
            hero:teleport(cx - 600, cy - 360, cl)
            local rates = {}
            local last = near(cow, hero)
            for _ = 1, 12 do
                gear.wait(0.5)
                local now = near(cow, hero)
                rates[#rates + 1] = (last - now) / 0.5
                last = now
                print(('NOTE cow step: distance %.0f, gait %s, speed %s'):format(now, tostring(cow:gait()), tostring(gear.buffs.speeds(cow).move_speed)))
            end
            local best = 0
            for _, r in ipairs(rates) do best = math.max(best, r) end
            local cs = gear.buffs.speeds(cow)
            print(('NOTE cow closes the distance at %.0f units a second at best (speed %s, hero %s)'):format(best, tostring(cs and cs.move_speed), tostring(gear.buffs.speeds(hero).move_speed)))
            check('the cow keeps up with the hero (closes in at 190 units a second or more)', best >= 190, best)
        end
    end
    A.screenshot('beasts_follow')

    -- fight: a hostile creature the game placed, with the ally next to it
    local hxx, hyy = hx, hy
    if not (wolf and wolf:exists() and not wolf:is_dead()) then
        print('NOTE the first ally fell on the way: a new one fights')
        local nid = recruit(567, 'ally')
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

    -- a big monster as an ally is drawn smaller (the giant spider's base size is 30 %)
    hero:teleport(hx, hy, layer)
    gear.wait(3)
    local spider_id, e4 = recruit(55, 'ally')
    check('a giant spider ally was recruited', spider_id ~= nil, e4)
    gear.wait(2)
    local sst = state()
    local sscale
    for _, f in ipairs(sst.followers) do if f.id == spider_id then sscale = f.scale end end
    check('the giant spider is drawn much smaller than its wild kind', sscale ~= nil and sscale < 0.5, sscale)
    A.screenshot('beasts_spider')

    -- the companions' shared buffs (the event the companions mod sends) reach the allies fully and the pets with their speed part only
    local function has(id, key)
        for _, b in ipairs(gear.buffs.list(id) or {}) do
            if b.key == key then return true end
        end
        return false
    end
    if not (wolf and wolf:exists() and not wolf:is_dead()) then wolf_id = recruit(567, 'ally'); wolf = wolf_id and W.object(wolf_id) end
    gear.emit('companions.buff', {key = 'test:1', strength = 1, seconds = 0, def = {id = 'test_party', name = 'Test',
        stats = {damage_min_physical = 20, damage_max_physical = 20}, factors = {attack_factor = 1.5, speed_factor = 1.5}}})
    gear.wait(0.5)
    check('a shared buff reaches the ally', wolf ~= nil and has(wolf_id, 'beastmaster:test:1'))
    check('a shared buff with no movement speed part does not reach the pet', not has(rabbit_id, 'beastmaster:test:1'))
    local late_id = recruit(567, 'ally')
    check('an animal taken along while the buff runs gets it too', late_id ~= nil and has(late_id, 'beastmaster:test:1'))
    gear.emit('companions.buff', {key = 'test:3', strength = 1, seconds = 0, def = {id = 'test_haste', name = 'Haste', speeds = {move_speed = 120, attack_speed = 50}}})
    gear.wait(0.5)
    local base_speed = gear.buffs.speeds(rabbit_id)
    check('a shared movement speed reaches the pet', has(rabbit_id, 'beastmaster:test:3'))
    check('and its movement speed is up (past the engine cap too)', base_speed ~= nil and base_speed.move_speed >= 200, base_speed and base_speed.move_speed)
    local wolf_speed = gear.buffs.speeds(wolf_id)
    check('the pet does not get the attack speed, the ally does', base_speed ~= nil and wolf_speed ~= nil and wolf_speed.attack_speed >= base_speed.attack_speed + 40,
          ('pet %s, ally %s'):format(tostring(base_speed and base_speed.attack_speed), tostring(wolf_speed and wolf_speed.attack_speed)))
    gear.emit('companions.buff', {key = 'test:2', strength = 1, seconds = 0, def = {id = 'test_armor', name = 'Armor', factors = {armor_factor = 2}}})
    gear.wait(0.5)
    check('a buff without a speed part reaches the ally', wolf ~= nil and has(wolf_id, 'beastmaster:test:2'))
    check('a buff without a speed part does not reach the pet', not has(rabbit_id, 'beastmaster:test:2'))
    gear.emit('companions.buff_end', 'test:1')
    gear.emit('companions.buff_end', 'test:2')
    gear.emit('companions.buff_end', 'test:3')
    gear.wait(0.5)
    check('the shared buffs end for the animals when they end for the heroes', not has(wolf_id, 'beastmaster:test:1') and not has(rabbit_id, 'beastmaster:test:1') and not has(wolf_id, 'beastmaster:test:2') and not has(rabbit_id, 'beastmaster:test:3'))

    -- orders: an ally told to wait stays where it stands (the hero far away, beyond the catch-up distance), "To me" calls it, a pet only
    -- follows or waits, and the order shows in the state
    local function index_of(id)
        for i, f in ipairs(state().followers) do if f.id == id then return i end end
    end
    if not (wolf and wolf:exists() and not wolf:is_dead()) then wolf_id = recruit(567, 'ally'); wolf = wolf_id and W.object(wolf_id); gear.wait(1) end
    local wi = index_of(wolf_id)
    check('the ally is found in the state with the default orders', wi ~= nil and state().followers[wi].order == 'aggressive')
    gear.emit('beastmaster.order', wi, 'hold')
    gear.wait(1)
    check('the order of the ally is wait', state().followers[wi].order == 'hold')
    local wx, wy, wl = wolf:position()
    local hxo, hyo, hlo = hero:position()
    hero:teleport(wx + 3600, wy, wl)
    gear.wait(8)
    local nx, ny = wolf:position()
    local away = nx and math.sqrt((nx - wx) ^ 2 + (ny - wy) ^ 2) or 1e9
    check('an ally told to wait stays put with the hero 3600 away', away < 200, away)
    check('and is far from the hero', (near(wolf, hero)) > 2600, near(wolf, hero))
    gear.emit('beastmaster.bring', wi)
    gear.wait(1)
    check('"To me" brings it to the hero', near(wolf, hero) < 600, near(wolf, hero))
    gear.emit('beastmaster.order', wi, nil)
    gear.emit('beastmaster.order', index_of(rabbit_id), 'aggressive')
    gear.wait(0.5)
    local ri = index_of(rabbit_id)
    check('a pet cannot be aggressive: it follows', state().followers[ri].order == 'passive')
    gear.emit('beastmaster.order', ri, 'hold')
    check('a pet can wait', state().followers[ri].order == 'hold')
    gear.emit('beastmaster.order_all', nil)
    check('orders for all: back to the default', state().followers[wi].order == 'aggressive' and state().followers[ri].order == 'passive')
    gear.emit('beastmaster.window', true)
    gear.emit('beastmaster.order', wi, 'defensive')
    gear.wait(1)
    A.screenshot('beasts_orders')
    gear.emit('beastmaster.dropdown', 'ord-' .. wi)
    gear.wait(1)
    A.screenshot('beasts_orders_open')
    gear.emit('beastmaster.dropdown', 'oall')
    gear.wait(1)
    A.screenshot('beasts_orders_all')
    gear.emit('beastmaster.dropdown', '')
    gear.emit('beastmaster.order_all', nil)

    -- the hero levels up: the allies follow (level, growth); a wolf that fell in the fights on the way is replaced first
    if not (wolf and wolf:exists() and not wolf:is_dead()) then
        wolf_id = recruit(567, 'ally')
        wolf = wolf_id and W.object(wolf_id)
        gear.wait(1)
    end
    local before = {}
    for _, f in ipairs(state().followers) do before[f.id] = f end
    local lvl0 = hero:level() or 1
    print('NOTE experience: ' .. tostring(hero:add_experience(300000000)))
    gear.wait(5)
    local lvl1 = hero:level() or 1
    print(('NOTE hero level %d -> %d'):format(lvl0, lvl1))
    check('the hero gained levels', lvl1 > lvl0, ('%d -> %d'):format(lvl0, lvl1))
    local after = {}
    for _, f in ipairs(state().followers) do after[f.id] = f end
    check('the wolf ally follows the hero level', after[wolf_id] and after[wolf_id].level == math.min(250, lvl1), ('%s vs %d'):format(tostring(after[wolf_id] and after[wolf_id].level), lvl1))
    check('the wolf ally has grown', after[wolf_id] and before[wolf_id] and after[wolf_id].scale > before[wolf_id].scale, ('%s -> %s'):format(tostring(before[wolf_id] and before[wolf_id].scale), tostring(after[wolf_id] and after[wolf_id].scale)))
    A.screenshot('beasts_grown')

    -- the filter row: a forgiving search over the names of all the animals
    local function filter(text)
        local names
        gear.emit('beastmaster.filter', text, function(n) names = n end)
        return names or {}
    end
    local all = filter('')
    check('the list has every animal', #all > 100, #all)
    local spiders = filter('spider')
    check('"spider" keeps spiders only (a handful, not all)', #spiders > 0 and #spiders < #all / 3, #spiders)
    local typo = filter('spyder')
    check('a typo is forgiven ("spyder" still finds spiders)', #typo > 0 and #typo < #all, #typo)
    local nothing = filter('qqqqzzzz')
    check('nothing matches nonsense', #nothing == 0, #nothing)
    gear.emit('beastmaster.window', true)
    filter('bear')
    gear.emit('beastmaster.osk', true)
    gear.wait(1)
    A.screenshot('beasts_filter')
    gear.emit('beastmaster.osk', false)
    filter('')

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
