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

local seen = {}
gear.on('ability.route', function(t, art) seen[art] = (seen[art] or 0) + 1 end)

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
    foe:set_modifiers({health = 40, taken = 0.5})   -- a foe that lasts, so that the second step of a chain has a target
    foe:teleport(x + 60, y - 60)
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
    return {ok = ok, trace = table.concat(trace, ' '), busy = busy, hp0 = hp0, hp1 = hp1, foe = foe}
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
    -- both heroes are recruited first: recruiting after a dismissal has crashed the engine's level up (see the companions notes)
    local ser = party.recruit('seraphim', {experience = 120000})
    gear.wait(2)
    local gla = party.recruit('gladiator', {experience = 120000})
    check('recruit seraphim', ser ~= nil)
    if not ser or not gla then return finish() end
    gear.emit('custom-classes.take', ser.id, 'spellblade')
    gear.wait(3)
    check('start spell granted', ser:ability(5) ~= nil)
    check('start art granted', ser:ability(1058) ~= nil)
    check('level art granted (hero level high enough)', ser:ability(34) ~= nil)
    check('rune arts not given', ser:ability(8) == nil and ser:ability(1059) == nil)
    party.control(ser)
    gear.wait(2)
    gear.emit('custom-classes.select', 'spellblade')
    gear.emit('custom-classes.window', true) gear.wait(1.5) A.screenshot('cc-window-seraphim') gear.emit('custom-classes.window', false) gear.wait(0.5)
    party.control(main)
    gear.wait(2)
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
    -- the profile's route handler answers first, so this mod's own handler never sees the routed art: the proof is the action state
    -- ('ability': the art runs; without the routing a Seraphim does a plain attack)
    local routed
    for attempt = 1, 3 do
        r = use(ser, 1058, attempt == 1 and 'cc-art' or nil)
        routed = r and r.trace:find('ability')
        if routed then break end
    end
    check('seraphim uses the Gladiator art (routed: action "ability")', routed, r and r.trace)
    -- Gladiator: Battle Caster
    check('recruit gladiator', gla ~= nil)
    if gla then
        gear.emit('custom-classes.take', gla.id, 'battle-caster')
        gear.wait(3)
        check('gladiator got the spell', gla:ability(5) ~= nil and gla:ability(1059) ~= nil)
        check('gladiator body has no cast clip', gear.models.has_motion('gladiator', 155) == false)
        r = use(gla, 5, 'cc-caster')
        check('gladiator casts a spell (clip remapped)', r and r.ok and r.busy >= 0.9, r and (r.trace .. ' busy ' .. r.busy))
        -- art copies and chains (the Gladiator is played now: a hero the game's AI runs attacks on its own and overrides the orders)
        party.control(gla)
        gear.wait(2)
        local copy = gear.data.abilities[2001]
        check('copy exists with the base code', copy ~= nil and copy.base == 1059 and copy.kind == 'combat_art', copy and copy.base)
        check('copy has its own numbers', copy and copy.effect_base == 40 and gear.data.abilities[1059].effect_base ~= 40, copy and copy.effect_base)
        check('copy has its own name', copy and (gear.text.get(copy.name_text) or ''):find('Gift') or (gear.text.get(copy.name_text) or ''):find('Venom'), copy and gear.text.get(copy.name_text))
        check('gladiator knows the copy and the chain steps', gla:ability(2001) ~= nil and gla:ability(2100) ~= nil and gla:ability(1058) ~= nil)
        local chain = gear.data.abilities[2100]
        local A = gear.data.abilities
        local base0, base1 = A[1058].regen_base + A[1059].regen_base, A[1058].regen_per_level + A[1059].regen_per_level
        check('chain regeneration record is the sum of its steps', chain.regen_base + 0.001 >= base0 and chain.regen_per_level + 0.001 >= base1,
            ('%.2f/%.2f vs %.2f/%.2f'):format(chain.regen_base, chain.regen_per_level, base0, base1))
        r = use(gla, 2001, 'cc-copy')
        check('copied art runs (a hit or the art action)', r and r.ok and (r.hp1 ~= r.hp0 or r.trace:find('ability')), r and (r.trace .. ' hp ' .. tostring(r.hp0) .. '->' .. tostring(r.hp1)))
        -- buffs of the copy: the hit puts the venom debuff on the foe, the use gives the hero the self buff
        local function has(c, key) for _, b in ipairs(c:buffs() or {}) do if b.key == key then return b end end end
        local venom, focus = r and r.foe and has(r.foe, 'cc:2001:1'), has(gla, 'cc:2001:2')
        check('hit buff: the foe has the venom debuff', venom ~= nil, venom and (('%s %.1fs'):format(venom.id, venom.left)) or 'none')
        check('use buff: the hero has the battle focus', focus ~= nil, focus and (('%s %.1fs'):format(focus.id, focus.left)) or 'none')
        seen = {}
        gear.wait(1)
        for attempt = 1, 4 do
            for _, id in ipairs({2100, 1058, 1059}) do
                local ab = gla:ability(id)
                for _ = 1, 60 do if not ab or ab.ready then break end gear.wait(0.5) ab = gla:ability(id) end
            end
            r = use(gla, 2100, attempt == 1 and 'cc-chain' or nil)
            if (seen[2100] or 0) > 0 and (seen[1059] or 0) > 0 then break end
        end
        check('chain starts', r and r.ok, r and r.trace)
        check('both steps of the chain were used (step 1 runs as the chain art, step 2 is ordered)', (seen[2100] or 0) > 0 and (seen[1059] or 0) > 0,
            ('chain art %s, step 2 %s'):format(tostring(seen[2100]), tostring(seen[1059])))
        -- a chain that ends in a spell: the spell is cast (the body has no cast clip: the class's remap plays one)
        local cast = false
        for attempt = 1, 4 do
            local ab = gla:ability(2101)
            for _ = 1, 40 do if ab and ab.ready then break end gear.wait(0.5) ab = gla:ability(2101) end
            local r3 = use(gla, 2101, attempt == 1 and 'cc-spellchain' or nil)
            if r3 and (r3.trace:find('busy') or r3.busy > 0.9) then cast = true break end
        end
        check('chain of an art and a spell: the spell follows', cast)
        gear.emit('custom-classes.leave', gla.id)
        gear.wait(1)
        r = use(gla, 5)
        print('CCT INFO without the class the same cast: ' .. (r and (r.trace .. ' busy ' .. r.busy) or 'no foe') .. ' (the vanilla body has no cast clip; this run is a control, not a check)')
    end
    finish()
end)
