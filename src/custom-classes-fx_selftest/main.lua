if not gear.auto then return end
local A = gear.auto
local passed, failed, results = 0, 0, {}
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    local line = ('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or '')
    results[#results + 1] = line
    print('CCFX ' .. line)
end

local function finish()
    A.write('custom-classes-fx_selftest.json', gear.json.encode({passed = passed, failed = failed, results = results}))
    print(('CCFX %d passed, %d failed'):format(passed, failed))
    if gear.config.quit then A.quit(failed == 0 and 0 or 1) end
end

local seen = {}
local function note(ctx)
    local key = ('fx=0x%X creature=%s ability=%s level=%s parent=%s'):format(ctx.fx, tostring(ctx.creature and ctx.creature.id),
        tostring(ctx.ability), tostring(ctx.level), tostring(ctx.parent))
    print(('CCFX PFX t=%.2f %s'):format(gear.time(), key))
end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then check('game', false) return finish() end
    gear.wait(4)
    local party = gear.party
    local main = party.leader()
    local ser = party.recruit('seraphim', {experience = 120000})
    gear.wait(2)
    check('recruit seraphim', ser ~= nil)
    if not ser then return finish() end
    gear.emit('custom-classes.take', ser.id, 'fxtest')
    gear.wait(3)
    party.control(ser)
    gear.wait(3)

    check('the copy exists', gear.data.abilities[2010] ~= nil and gear.data.abilities[2010].base == 1052, gear.data.abilities[2010] and gear.data.abilities[2010].base)
    check('hero knows the art and its copy', ser:ability(1052) ~= nil and ser:ability(2010) ~= nil)
    local defs = gear.pfx.definitions()
    local mine
    for _, d in ipairs(defs) do if d.id == 200000 + 2010 * 64 then mine = d end end
    check('the fx rule made a variant', mine ~= nil and mine.hue == -120, #defs)

    local handler = gear.on('pfx.select', note)
    local routes = {}
    local rh = gear.on('ability.route', function(_, art) if not routes[art] then routes[art] = true print(('CCFX ROUTE t=%.2f art=%s'):format(gear.time(), tostring(art))) end return nil end)
    local function shoot(tag, id)
        local x, y = ser:position()
        for _ = 1, 60 do
            local a = ser:ability(id)
            if a and a.ready then break end
            gear.wait(0.5)
        end
        local ok = ser:order_ability(id, x + 250, y)
        local t = 0
        for i, at in ipairs({0.6, 1.4, 2.4}) do
            gear.wait(at - t)
            t = at
            A.screenshot(('%s-%d-%d'):format(tag, id, i))
        end
        gear.wait(8)
        return ok
    end
    local applied0 = gear.pfx.stats().applied
    check('cast the original', shoot('base', 1052))
    check('the original is not recoloured', gear.pfx.stats().applied == applied0, gear.pfx.stats().applied - applied0)
    check('cast the copy', shoot('fx', 2010))
    check('the rule gave the copy its variant', gear.pfx.stats().applied > applied0, gear.pfx.stats().applied - applied0)
    gear.off(handler)
    gear.off(rh)
    party.control(main)
    finish()
end)
