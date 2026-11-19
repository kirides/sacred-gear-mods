if not gear.auto then return end
local A = gear.auto
local party = gear.party
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(('ABT %s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end
local seen = {}
gear.on('ability.route', function(t, art) seen[art] = (seen[art] or 0) + 1 end)

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then check('game', false) A.quit(1) return end
    gear.wait(4)
    gear.emit('custom-classes.window', false)
    local main = party.leader()
    print('ABT available ' .. tostring(party.available()) .. ' leader ' .. tostring(main and main.id))
    local gla = party.recruit('gladiator', {experience = 120000})
    gear.wait(2)
    local list = main:abilities() or {}
    check('the hero has abilities', #list >= 1, #list)
    -- more arts than the game's bar holds: learn a few of other classes
    for _, id in ipairs({5, 8, 34, 1058, 1059, 1060, 1042}) do main:learn(id, 1) end
    gear.wait(1)
    local all = main:abilities() or {}
    check('the hero knows many abilities', #all >= 8, #all)
    local n = 0
    for bar = 1, 2 do
        for slot = 1, 8 do
            local a = all[(n % #all) + 1]
            gear.emit('art-bars.set', bar, slot, a.id)
            n = n + 1
        end
    end
    gear.emit('art-bars.set', 2, 3, list[1].id)
    local c = gear.world.cursor(main)
    print('ABT cursor ' .. gear.json.encode(c and {x = c.x, y = c.y, layer = c.layer, px = c.pixel_x, py = c.pixel_y, obj = c.object and c.object.id} or 'nil') .. ' hero ' .. table.concat({main:position()}, ','))
    gear.wait(0.5)
    gear.emit('art-bars.edit', false)
    gear.wait(1)
    A.screenshot('bars-1')
    -- use slot 3 of bar 2 on a foe next to the hero
    local x, y, layer = main:position()
    local foe
    for _, c in ipairs(gear.world.creatures_near(x, y, 3500, {layer = layer})) do
        if not c:is_dead() and main:is_enemy(c) and not c:is_hero() then foe = c break end
    end
    check('a foe', foe ~= nil)
    if foe then
        foe:set_modifiers({health = 40})
        foe:teleport(x + 70, y - 70)
        gear.wait(0.5)
        local id = list[1].id
        gear.emit('art-bars.use', 2, 3)
        local maxregen = 0
        for _ = 1, 20 do
            gear.wait(0.15)
            local a = main:ability(id)
            if a and a.regen > maxregen then maxregen = a.regen end
        end
        check('the slot used the ability (regeneration started)', maxregen > 0, ('%d regen %.1f'):format(id, maxregen))
        A.screenshot('bars-2-cooldown')
    end
    -- a copy of the custom-classes mod goes into a slot too (a Gladiator with the Battle Caster class, played)
    if gla then
        gear.emit('custom-classes.take', gla.id, 'battle-caster')
        gear.wait(3)
        party.control(gla)
        gear.wait(2)
        gear.emit('art-bars.set', 1, 1, 2001)
        local x2, y2, l2 = gla:position()
        local f2
        for _, c in ipairs(gear.world.creatures_near(x2, y2, 3500, {layer = l2})) do
            if not c:is_dead() and gla:is_enemy(c) and not c:is_hero() then f2 = c break end
        end
        if f2 then
            f2:set_modifiers({health = 40})
            f2:teleport(x2 + 60, y2 - 60)
            gear.wait(0.5)
            gear.emit('art-bars.use', 1, 1)
            for _ = 1, 20 do gear.wait(0.15) end
            check('a copied art from a slot runs (the game asks for its class)', (seen[2001] or 0) > 0, tostring(seen[2001]))
        end
        party.control(main)
        gear.wait(2)
    end
    gear.emit('art-bars.edit', true)
    gear.wait(0.5)
    gear.emit('art-bars.pick', 1, 2)
    gear.wait(1)
    A.screenshot('bars-3-picker')
    print(('ABT %d passed, %d failed'):format(passed, failed))
    A.quit(failed == 0 and 0 or 1)
end)
