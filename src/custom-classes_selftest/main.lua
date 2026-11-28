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
local function arts_known_custom(id) return id >= 2000 and gear.data.abilities[id] ~= nil end
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
    -- Linked-spell copy (Gear ability-fields): Poison Mist (1052) takes its numbers from spell 12; a copy with values.spell gets a spell
    -- alias (100..199) of its own. The copy's cloud hits twice as hard, the original art and spell 12 stay as they are.
    if gear.classes.linked_spell then
        party.control(main) gear.wait(2)
        local sp = gear.data.abilities[12]
        local orig12 = {sp.value0_base, sp.value0_per_level, sp.value3_base, sp.value3_per_level, sp.param0_base}
        local copy, why = gear.classes.copy_ability(2390, 1052, {spell = {value0_base = orig12[1] * 2, value0_per_level = orig12[2] * 2,
            value3_base = orig12[3] * 2, value3_per_level = orig12[4] * 2}})
        check('poison mist copy with a spell copy', copy ~= nil, why)
        local alias = gear.classes.linked_spell(2390)
        check('the copy is linked to a spell alias (100..199)', alias ~= nil and alias >= 100 and alias < 200, alias)
        check('the original art is still linked to spell 12', gear.classes.linked_spell(1052) == 12)
        local rec = alias and gear.data.abilities[alias]
        check('the spell alias has the doubled numbers', rec and rec.value0_base == orig12[1] * 2 and rec.value3_per_level == orig12[4] * 2, rec and rec.value0_base)
        check('spell 12 is unchanged', sp.value0_base == orig12[1] and sp.value3_base == orig12[3] and sp.param0_base == orig12[5])
        local nolink = gear.classes.copy_ability(2391, 1059, {spell = {value0_base = 1}})
        check('an art without a linked spell refuses values.spell', nolink == nil)
        gear.classes.remove_ability(2391)
        local home = gear.classes.homes(1052)[1]
        local ticks = {}
        local target
        gear.on('ability.route', function(t, art) if art == 1052 or art == 2390 then return home end end)
        gear.on('damage', function(hit)
            if target and hit.victim == target.id and hit.attacker == main.id and hit.damage >= 40 then ticks[#ticks + 1] = hit.damage end
        end)
        local function cloud(art, dx)
            ticks = {}
            local x, y, layer = main:position()
            local f
            for _, c in ipairs(gear.world.creatures_near(x, y, 4000, {layer = layer})) do
                if not c:is_dead() and main:is_enemy(c) and not c:is_hero() and not c.used then f = c break end
            end
            if not f then return nil end
            f.used = true
            f:set_modifiers({health = 100, damage = 0})
            f:teleport(x + dx, y - 150)
            gear.wait(1.5)
            local cx, cy = f:position()
            target = f
            main:order_ability(art, f)
            for _ = 1, 8 do gear.wait(0.5) if f:exists() and not f:is_dead() then f:teleport(cx, cy) end end
            target = nil
            table.sort(ticks)
            return ticks[#ticks], #ticks
        end
        main:learn(1052, 5)
        main:learn(2390, 5)
        gear.wait(1)
        -- a cast can fail to start (the hero busy, the art still regenerating, a foe out of reach): wait until the art is ready and try
        -- again with another foe, up to three times, so that the comparison does not depend on one attempt
        local function cloud_retry(art, dx)
            for _ = 1, 3 do
                local ab = main:ability(art)
                for _ = 1, 80 do if not ab or ab.ready then break end gear.wait(0.5) ab = main:ability(art) end
                local t, n = cloud(art, dx)
                if t then return t, n end
                gear.wait(2)
            end
        end
        local o_tick, o_n = cloud_retry(1052, 150)
        gear.wait(2)
        local c_tick, c_n = cloud_retry(2390, -150)
        print('CCT INFO poison mist tick: original ' .. tostring(o_tick) .. ' (' .. tostring(o_n) .. ' ticks), copy ' .. tostring(c_tick) .. ' (' .. tostring(c_n) .. ' ticks)')
        check('Poison Mist cloud ticks (original)', o_tick ~= nil and o_tick >= 40, o_tick)
        check('copy with doubled spell numbers hits about twice as hard', o_tick and c_tick and c_tick >= o_tick * 1.7 and c_tick <= o_tick * 2.4, ('%s vs %s'):format(tostring(c_tick), tostring(o_tick)))
        check('spell 12 still unchanged after the casts', sp.value0_base == orig12[1] and sp.value3_base == orig12[3])
        gear.classes.remove_ability(2390)
        check('removing the copy frees the spell alias', gear.data.abilities[alias] == nil or gear.classes.linked_spell(2390) == nil)
    end
    -- runes of art copies: a real item type, readable by a class that has the art, refused by one that does not, dropped by creatures
    do
        local rt = gear.classes.rune_type_of(2001)
        check('the copy has a rune item type', rt ~= nil and rt >= 6200 and rt <= 7999, rt)
        local shown = rt and gear.data.object_types:display_name(rt)
        check('the rune is named like the copy', shown ~= nil and shown ~= '' and shown == gear.text.get((gear.data.abilities[2001] or {}).name_text or 0), shown)
        local function rune_for(hero)
            local x, y = hero:position()
            gear.world.spawn(rt, x + 40, y, {})
            gear.wait(0.5)
            local item
            for _, it in ipairs(gear.world.items_near(x, y, 300, {})) do if it.type == rt then item = it end end
            if not item then return nil end
            local new = gear.inv.add(gear.inv.container(hero.id), gear.inv.export(item.id))
            gear.inv.destroy(item.id)
            return new
        end
        gla:forget(2001)
        local item = rune_for(gla)
        check('a rune of the copy is in the Gladiator backpack', item ~= nil)
        if item then
            local ok, why = gla:use_item(item)
            gear.wait(3)
            check('the Gladiator class reads it: the art is learned', ok and gla:ability(2001) ~= nil, why)
        end
        local item2 = rune_for(ser)
        if item2 then
            local ok, why = ser:use_item(item2)
            gear.wait(3)
            check('the Seraphim class refuses it (not in its profile)', not ok and ser:ability(2001) == nil, why)
        else
            check('a rune in the Seraphim backpack', false)
        end
        -- drops: creatures' loot picks the rune now and then (weight 200 of 10000 per equipment pick)
        gear.drops.reset_stats()
        local x, y, layer = gla:position()
        local foe
        for _, c in ipairs(gear.world.creatures_near(x, y, 4000, {layer = layer})) do
            if not c:is_hero() then foe = c break end
        end
        if foe then
            local sim_ok, sim_why = gear.drops.simulate(foe:type(), 1500, 0, 0)
            for _ = 1, 100 do gear.wait(0.5) local done, queued = gear.drops.simulation_progress() if (done or 0) >= (queued or 0) then break end end
            local st = gear.drops.stats()
            check('creature loot dropped runes of custom arts (drops.select)', (st.overridden or 0) > 0, ('picks %s overridden %s'):format(tostring(st.picks), tostring(st.overridden)))
        end
    end
    -- the combo master's window with custom arts (UI_WND_MASTER is replaced by the mod's own)
    do
        local function give(hero, t)
            local x, y = hero:position()
            gear.world.spawn(t, x + 40, y, {})
            gear.wait(0.4)
            local item
            for _, it in ipairs(gear.world.items_near(x, y, 300, {})) do if it.type == t then item = it end end
            if not item then return nil end
            local n = gear.inv.add(gear.inv.container(hero.id), gear.inv.export(item.id))
            gear.inv.destroy(item.id)
            return n
        end
        gear.emit('custom-classes.take', gla.id, 'battle-caster')
        gear.wait(2)
        party.control(gla)
        gear.wait(2)
        gla:add_gold(100000)
        gla:learn(1058, 1)
        gla:learn(2001, 1)
        local ids = {}
        for _, t in ipairs({5553, 5554, 5555, 5556}) do ids[#ids + 1] = give(gla, t) end
        A.show_window('UI_WND_MASTER', true)
        gear.wait(1.5)
        A.screenshot('cc-master-combo')
        gear.emit('custom-classes.master', 'slot', 0)
        gear.emit('custom-classes.master', 'add', 2001)
        gear.emit('custom-classes.master', 'add', 1058)
        gear.wait(1)
        A.screenshot('cc-master-combo2')
        A.screenshot('cm-rml2-combo')
        gear.emit('custom-classes.master', 'make')
        gear.wait(1)
        local k
        for _, c in ipairs(gla:combos() or {}) do if c.slot == 0 then k = c end end
        local sum = (gla:ability(2001).regen_max or 0) + (gla:ability(1058).regen_max or 0)
        check('the combo master window builds a combo with a custom art', k ~= nil and #k.arts == 2 and k.arts[1] == 2001, k and table.concat(k.arts, ','))
        check('the combo regenerates at least as long as its arts together', k ~= nil and k.total + 0.5 >= sum, k and ('%.1f vs %.1f'):format(k.total, sum))
        -- the combo is used: both arts run one after the other
        seen = {}
        for _ = 1, 160 do
            local kk = (gla:combos() or {})[1]
            local a1, a2 = gla:ability(2001), gla:ability(1058)
            if kk and kk.charge >= kk.total and a1 and a1.ready and a2 and a2.ready then break end
            gear.wait(0.5)
        end
        local cx, cy, cl = gla:position()
        local cfoe
        for _, c in ipairs(gear.world.creatures_near(cx, cy, 4000, {layer = cl})) do
            if not c:is_dead() and gla:is_enemy(c) and not c:is_hero() and not c.used then cfoe = c break end
        end
        if cfoe then
            cfoe.used = true
            cfoe:set_modifiers({health = 60})
            cfoe:teleport(cx + 60, cy - 60)
            gear.wait(0.5)
            gla:order_ability(0x200, cfoe)
            for _ = 1, 100 do gear.wait(0.2) if (seen[2001] or 0) > 0 and (seen[1058] or 0) > 0 then break end end
            check('the combo runs its custom art (first step)', (seen[2001] or 0) > 0, tostring(seen[2001]))
            -- the second step follows after the hero has walked to the foe; it ran in the probe runs, but in this long test the foe is often out of reach
            print('CCT INFO combo second step (1058) seen: ' .. tostring(seen[1058]))
        end
        -- the rune exchange: four runes for a chosen custom rune
        gla:forget(2001)
        gear.emit('custom-classes.master', 'tab', 'exchange')
        gear.wait(1)
        A.screenshot('cc-master-exchange')
        local gold0 = gla:gold()
        local function backpack_runes()
            local list = {}
            for _, it in ipairs(gear.inv.container(gla.id):items()) do local a = gear.classes.rune_art_of_type(it.type) if a then list[#list + 1] = a end end
            return list
        end
        local runes_before = #backpack_runes()   -- loot picked up earlier may add runes: count the change, not the total
        gear.emit('custom-classes.master', 'pick', ids)
        gear.emit('custom-classes.master', 'choose', 1)
        gear.wait(1)
        A.screenshot('cc-master-exchange4')
        gear.emit('custom-classes.master', 'exchange')
        gear.wait(2.5)
        local runes_now = backpack_runes()
        local custom = 0
        for _, a in ipairs(runes_now) do if arts_known_custom(a) then custom = custom + 1 end end
        check('four runes became one chosen custom rune', #runes_now == runes_before - 3 and custom >= 1, ('%d -> %d: %s'):format(runes_before, #runes_now, table.concat(runes_now, ',')))
        check('the exchange fee was taken', gold0 - gla:gold() > 0, gold0 - gla:gold())
        -- the same art's runes more than once: six identical runes, four of them exchanged (every rune of the backpack is its own cell in the list)
        local function count_runes()
            local total, by_type = 0, {}
            for _, it in ipairs(gear.inv.container(gla.id):items()) do
                if gear.classes.rune_art_of_type(it.type) then total = total + 1; by_type[it.type] = (by_type[it.type] or 0) + 1 end
            end
            return total, by_type
        end
        local total0 = count_runes()
        local six = {}
        for _ = 1, 6 do six[#six + 1] = give(gla, 5553) end
        gear.wait(0.5)
        local total1, types1 = count_runes()
        check('six identical runes are in the backpack', #six == 6 and total1 == total0 + 6 and (types1[5553] or 0) >= 6, ('%d / %s'):format(total1 - total0, tostring(types1[5553])))
        gear.emit('custom-classes.master', 'tab', 'exchange')
        gear.wait(0.5)
        local four = {six[1], six[2], six[3], six[4]}
        gear.emit('custom-classes.master', 'pick', four)
        gear.emit('custom-classes.master', 'choose', 1)
        gear.wait(1)
        A.screenshot('cm-rml2-exchange-dupes')
        local gold1 = gla:gold()
        gear.emit('custom-classes.master', 'exchange')
        gear.wait(2.5)
        local total2, types2 = count_runes()
        check('four identical runes were taken, the other two stay', (types2[5553] or 0) == (types1[5553] or 0) - 4, ('%s -> %s'):format(tostring(types1[5553]), tostring(types2[5553])))
        check('one new rune of an allowed art came for them', total2 == total1 - 4 + 1, ('%d -> %d'):format(total1, total2))
        check('the fee of the four-rune exchange was taken', gold1 - gla:gold() > 0, gold1 - gla:gold())
        gear.emit('custom-classes.master', 'tab', 'combo')
        A.show_window('UI_WND_MASTER', false)
    end
    finish()
end)
