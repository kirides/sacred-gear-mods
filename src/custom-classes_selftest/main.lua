if not gear.auto then return end
local A = gear.auto
local party = gear.party
local passed, failed, results = 0, 0, {}
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    local line = ('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or '')
    results[#results + 1] = line
    print('CCT ' .. line)
end

local function foe_for(hero)
    local x, y, layer = hero:position()
    for _, c in ipairs(gear.world.creatures_near(x, y, 3500, {layer = layer})) do
        if not c:is_dead() and hero:is_enemy(c) and not c:is_hero() then return c end
    end
end

-- Uses an ability on a foe next to the hero; returns the trace of actions and the foe's hp change.
local function use(h, ability, shot)
    local foe = foe_for(h)
    if not foe then return nil end
    local x, y = h:position()
    foe:teleport(x + 130, y - 130)
    gear.wait(0.4)
    local hp0 = foe:hp()
    local ok = h:order_ability(ability, foe)
    local last, trace, busy = nil, {}, 0
    for i = 1, 24 do
        gear.wait(0.15)
        local act = h:action()
        if act ~= last then trace[#trace + 1] = ('%.1f:%s'):format(i * 0.15, tostring(act)); last = act end
        if act == 'busy' or act == 'ability' then busy = i * 0.15 end
        if i == 6 and shot then A.screenshot(shot) end
    end
    local hp1 = foe:is_dead() and 0 or foe:hp()
    h:order_move(x, y)
    gear.wait(0.5)
    return {ok = ok, trace = table.concat(trace, ' '), busy = busy, hp0 = hp0, hp1 = hp1}
end

local function finish()
    A.write('custom-classes_selftest.json', gear.json.encode({passed = passed, failed = failed, results = results}))
    print(('CCT %d passed, %d failed'):format(passed, failed))
    if gear.config.quit then A.quit(failed == 0 and 0 or 1) end
end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then check('game', false) return finish() end
    gear.wait(4)
    check('mod loaded', gear.mods.get('custom-classes') ~= nil and gear.mods.get('custom-classes').state == 'on', gear.mods.get('custom-classes') and gear.mods.get('custom-classes').state)
    local files = gear.mods.files('custom-classes', 'classes') or {}
    check('profile files listed', #files >= 2, table.concat(files, ','))
    local main = party.leader()

    gear.emit('custom-classes.window', true) gear.wait(1.5) A.screenshot('cc-window') gear.emit('custom-classes.window', false) gear.wait(0.5)

    -- Seraphim: Spellblade
    local ser = party.recruit('seraphim', {experience = 120000})
    check('recruit seraphim', ser ~= nil)
    if not ser then return finish() end
    gear.emit('custom-classes.take', ser.id, 'spellblade')
    gear.wait(3)
    check('start spell granted', ser:ability(5) ~= nil)
    check('start art granted', ser:ability(1058) ~= nil)
    check('level art granted (hero level high enough)', ser:ability(34) ~= nil)
    check('rune arts not given', ser:ability(8) == nil and ser:ability(1059) == nil)
    local before = gear.classes.hero_skills('seraphim')
    check('skills untouched while another hero is played', before and before.start[1] == 14 and before.start[2] == 2, before and table.concat(before.start, ','))
    party.control(ser)
    gear.wait(3)
    local during = gear.classes.hero_skills('seraphim')
    check('class skills while the hero is played', during and during.start[1] == 14 and during.start[2] == 12 and #during.available == 16, during and table.concat(during.start, ',') .. '/' .. #during.available)
    A.press('c') gear.wait(1.5) A.screenshot('cc-skills') A.press('c') gear.wait(0.5)
    party.control(main)
    gear.wait(3)
    local after = gear.classes.hero_skills('seraphim')
    check('skills back after switching', after and after.start[2] == 2, after and table.concat(after.start, ','))

    local r = use(ser, 5, 'cc-spell')
    check('seraphim casts the Battle Mage spell', r and r.ok and r.busy >= 0.6, r and (r.trace .. ' busy ' .. r.busy))
    r = use(ser, 1058, 'cc-art')
    check('seraphim uses the Gladiator art (routed)', r and r.ok and r.hp1 < r.hp0, r and (r.trace .. ' hp ' .. tostring(r.hp0) .. '->' .. tostring(r.hp1)))
    party.dismiss(ser)
    gear.wait(1.5)

    -- Gladiator: Battle Caster
    local gla = party.recruit('gladiator', {experience = 120000})
    check('recruit gladiator', gla ~= nil)
    if gla then
        gear.emit('custom-classes.take', gla.id, 'battle-caster')
        gear.wait(3)
        check('gladiator got the spell', gla:ability(5) ~= nil and gla:ability(1059) ~= nil)
        check('gladiator body has no cast clip', gear.models.has_motion('gladiator', 155) == false)
        r = use(gla, 5, 'cc-caster')
        check('gladiator casts a spell (clip remapped)', r and r.ok and r.busy >= 0.9, r and (r.trace .. ' busy ' .. r.busy))
        gear.emit('custom-classes.leave', gla.id)
        gear.wait(1)
        r = use(gla, 5)
        check('without the class the cast aborts at once (no clip)', r and r.busy < 0.7, r and (r.trace .. ' busy ' .. r.busy))
        party.dismiss(gla)
    end
    finish()
end)
