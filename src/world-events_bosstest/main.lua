-- A self test of the world bosses of the world-events mod:
--
--     Sacred.exe -gear-auto -gear-instance=bosses -gear-load=10 -gear-mods=world-events,world-events_bosstest
--
-- needs a savegame with a hostile wolf of id 1266 near the hero (the author's GAME10) and a Sacred Gear with creature modifiers. It makes bosses
-- through gear.emit('world-events.boss', ...) (what the `boss` action of an event does): one spawned (an Orc Warrior), one promoted (the nearest
-- wolf), checks the events, the health, the reward, the bar (a panel 'world-events:boss' and screenshots) and a save and load with a boss. It saves
-- into slot 90: run it in a copy of the game folder. The result is in the log ("CHECK ok|FAIL") and boss.json; exit code 0 when all passed.
if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end
local A, ui = gear.auto, gear.ui
local results = {checks = {}, passed = 0, failed = 0}
local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('CHECK %s %s%s'):format(ok and 'ok' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end
local function finish()
    A.write('boss.json', gear.json.encode(results))
    print(('RESULT %d passed, %d failed'):format(results.passed, results.failed))
    A.quit(results.failed == 0 and 0 or 1)
end

local spawned, defeated = {}, {}
gear.on('worldevent.boss.spawned', function(ev) spawned[#spawned + 1] = ev end)
gear.on('worldevent.boss.defeated', function(ev) defeated[#defeated + 1] = ev end)
local saved, changed = nil, 0
gear.on('game.saved', function(slot) saved = slot end)
gear.on('savegame.changed', function() changed = changed + 1 end)

local function panel()
    for _, p in ipairs(ui.panels()) do if p.key == 'world-events:boss' then return p end end
end

gear.task(function()
    check('main menu', A.wait_for_menu(120))
    local game = A.wait_for_game(180)
    check('game with a hero', game)
    if not game then return finish() end
    gear.emit('world-events.configure', {local_mode = 'off', region_pill = false})
    gear.wait(3)
    local hero = gear.world.hero()
    local x, y = hero:position()
    local gold0 = hero:gold()
    check('the declared events', (function()
        local n = 0
        for _, h in ipairs(gear.events.list()) do if h.name == 'worldevent.boss.spawned' or h.name == 'worldevent.boss.defeated' then n = n + 1 end end
        return n == 2
    end)())
    check('no bar without a boss', panel() == nil)

    -- a boss of a spawned Orc Warrior
    gear.emit('world-events.boss', {name = 'Grakk the Test', kinds = {{type = 'Orc Warrior'}}, radius = 150, health = 10, damage = 3, taken = 0.5, reflect = 0.25,
        reward = {gold = 777}, text = 'Grakk has come!', event = 'Boss test'})
    gear.wait(1)
    check('worldevent.boss.spawned', #spawned == 1 and spawned[1].name == 'Grakk the Test' and spawned[1].source == 'local', spawned[1] and spawned[1].name)
    local ev = spawned[1] or {}
    local orc = ev.creature and gear.world.object(ev.creature)
    check('the boss creature exists', orc ~= nil and orc:exists(), ev.creature)
    check('it is an orc with boosted health', orc ~= nil and orc:max_hp() == ev.health and ev.health > 500, orc and (orc:max_hp() .. ' / ' .. tostring(ev.health)))
    check('modifiers are on it', orc ~= nil and orc:modifiers() ~= nil and orc:modifiers().reflect == 0.25)
    check('it is hostile', orc ~= nil and hero:is_enemy(orc))
    gear.wait(1)
    local p = panel()
    check('the bar is a panel of the mod', p ~= nil)
    if p then A.write('panel.json', gear.json.encode(p)) end
    A.move(A.ui_to_pixels(300, 600))
    gear.wait(0.5)
    A.screenshot('boss-bar')
    if p then
        local hx, hy = A.ui_to_pixels(p.x + p.w / 2, p.y + p.h / 2)
        A.move(hx, hy)
        gear.wait(0.8)
        A.screenshot('boss-hover')
        A.move(A.ui_to_pixels(300, 600))
    end

    -- the orc fights; the bar follows its health
    orc:teleport(x + 40, y + 40)
    hero:order_attack(orc)
    gear.wait(6)
    local hp1 = orc:hp()
    check('the orc is alive and its health is read', hp1 ~= nil, hp1)
    -- weaken it: a hit kills it
    orc:set_hp(1)
    gear.wait(0.6)
    A.screenshot('boss-weak')
    local deadline = gear.time() + 40
    while #defeated == 0 and gear.time() < deadline do
        if orc:exists() and not orc:is_dead() then
            local ox, oy = orc:position()
            local hx2, hy2 = hero:position()
            if ox and (ox - hx2) ^ 2 + (oy - hy2) ^ 2 > 120 ^ 2 then orc:teleport(hx2 + 40, hy2 + 40) end
            hero:order_attack(orc)
            orc:set_hp(1)
        end
        gear.wait(1)
    end
    check('worldevent.boss.defeated', #defeated == 1 and defeated[1].name == 'Grakk the Test', defeated[1] and defeated[1].name)
    gear.wait(1)
    check('the reward was paid', hero:gold() >= gold0 + 777, ('%s -> %s'):format(gold0, hero:gold()))
    A.screenshot('boss-defeated')
    gear.wait(8)
    check('the bar is gone after a while', panel() == nil)

    -- the nearest suitable creature is promoted
    gear.emit('world-events.boss', {name = 'Alpha Wolf', near = 'Wolf', radius = 3000, health = 6, damage = 2})
    gear.wait(1)
    check('a wolf was promoted (spawned event)', #spawned == 2 and spawned[2].type_name == 'WOLF.GRN', spawned[2] and spawned[2].type_name)
    local wolf = spawned[2] and spawned[2].creature and gear.world.object(spawned[2].creature)
    local base = wolf and wolf:modifier_stats() and wolf:modifier_stats().base_max_hp
    check('it has the boosted health', wolf ~= nil and base ~= nil and wolf:max_hp() == base * 6, wolf and (wolf:max_hp() .. ' / ' .. tostring(base)))
    check('an existing creature, not a new one', spawned[2] ~= nil and spawned[2].creature >= 1266 and spawned[2].creature <= 1268, spawned[2] and spawned[2].creature)
    local boosted_id = spawned[2] and spawned[2].creature

    -- save and load with a boss: it comes back
    print('save', gear.game.save(90, 'bossmod'))
    gear.wait_until(function() return saved ~= nil end, 60)
    gear.wait(2)
    local c0 = changed
    print('load', gear.game.load(90))
    gear.wait_until(function() return changed > c0 end, 120)
    gear.wait(15)
    local wolf2 = boosted_id and gear.world.object(boosted_id)
    check('after the load: the creature is still boosted', wolf2 ~= nil and base ~= nil and wolf2:max_hp() == base * 6, wolf2 and wolf2:max_hp())
    check('after the load: the modifiers are back', wolf2 ~= nil and wolf2:modifiers() ~= nil and wolf2:modifiers().damage == 2)
    check('after the load: spawned again with initial', #spawned >= 3 and spawned[#spawned].initial == true and spawned[#spawned].name == 'Alpha Wolf',
        spawned[#spawned] and tostring(spawned[#spawned].initial))
    check('after the load: the bar shows it', panel() ~= nil)
    A.screenshot('boss-after-load')

    -- clean up
    print('delete', gear.game.delete_save(90))
    finish()
end)
