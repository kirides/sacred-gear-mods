-- In-game test of the companion behaviours "Wait here" and "fight back when hit".
-- Run: Sacred.exe -gear-auto -gear-load=10 -gear-mods=companions,companions_behaviour_selftest (in a copy of the game folder).
local AU = gear.auto
local failures = 0
local function check(c, name) print((c and 'PASS ' or 'FAIL ') .. name) if not c then failures = failures + 1 end end
local function dist(a, b, c, d) return math.sqrt((a - c) ^ 2 + (b - d) ^ 2) end
local TILE = gear.world.TILE or 54
local used = {}

local function pick_foe(h)
    local x, y, layer = h:position()
    for _, c in ipairs(gear.world.creatures_near(x, y, 2500, {layer = layer, limit = 60})) do
        if not c:is_dead() and h:is_enemy(c) and not c:is_hero() and not used[c.id] and (c:max_hp() or 0) < 3000 then used[c.id] = true return c end
    end
end

local function watch(c, foe, secs, label)
    local attacking, lastd = 0, nil
    for i = 1, secs do
        gear.wait(1)
        local cx, cy = c:position()
        local fx, fy = foe:position()
        lastd = fx and dist(cx, cy, fx, fy) or -1
        if c:action() == 'attacking' then attacking = attacking + 1 end
        print(('  %s t=%d companion %s hp %s dist %.0f, foe hp %s'):format(label, i, tostring(c:action()), tostring(c:hp()), lastd, tostring(foe:hp())))
    end
    return attacking, lastd
end

local function main()
    AU.wait_for_menu(120)
    if not AU.wait_for_game(180) then AU.quit(1) return end
    gear.wait(4)
    local hero = gear.party.leader()
    local c, err = gear.party.recruit('darkelf', {experience = hero:experience() or 0})
    print('recruit ' .. tostring(c and c.id) .. ' ' .. tostring(err))
    if not c then AU.quit(2) return end
    gear.wait(3)
    local x, y, layer = hero:position()
    c:teleport(x + 100, y, layer)
    gear.wait(2)

    -- 1. Wait here: the hero goes 2000 units away; the companion stays at its spot.
    gear.emit('companions.set', {id = c.id, behaviour = 'hold'})
    gear.wait(1)
    local sx, sy = c:position()
    hero:teleport(x + 2000, y, layer)
    gear.wait(12)
    local cx, cy = c:position()
    check(dist(cx, cy, sx, sy) < 150, ('Wait here: stays at its spot while the hero is 2000 away (moved %.0f)'):format(dist(cx, cy, sx, sy)))

    -- 2. Wait here: an enemy comes close, the companion fights it (the enemy loses health), then goes back to its spot.
    local foe = pick_foe(hero)
    if foe then
        foe:set_modifiers({health = 3000, damage = 0})
        foe:teleport(sx + 250, sy, layer)
        local hp0 = foe:hp()
        print('foe ' .. tostring(foe:type_name()) .. ' hp ' .. tostring(hp0))
        local att = watch(c, foe, 10, 'hold')
        check(att >= 2, ('Wait here: fights an enemy that comes near (attacking in %d of 10 samples)'):format(att))
        foe:teleport(sx + 6000, sy, layer)
        gear.wait(8)
        local bx, by = c:position()
        check(dist(bx, by, sx, sy) < 200, ('Wait here: back at its spot after the fight (%.0f away)'):format(dist(bx, by, sx, sy)))
    else
        print('no foe for test 2')
    end

    -- 3. Without hold, the companion follows (control).
    gear.emit('companions.set', {id = c.id, behaviour = nil})
    c:teleport(sx, sy, layer)
    hero:teleport(sx + 1500, sy, layer)
    gear.wait(8)
    local hx, hy = hero:position()
    local fx, fy = c:position()
    check(dist(fx, fy, hx, hy) < 900, ('Default: follows the hero (distance %.0f)'):format(dist(fx, fy, hx, hy)))

    -- 4. Fight back: the hero is farther away than the leash (about 1000), an enemy hits the companion; it must fight back.
    c:teleport(sx, sy, layer)
    hero:teleport(sx + 1900, sy, layer)
    gear.wait(1)
    local foe2 = pick_foe(hero)
    if foe2 then
        foe2:set_modifiers({health = 3000, damage = 0})
        foe2:teleport(sx + 300, sy, layer)
        print('foe2 ' .. tostring(foe2:type_name()) .. ' companion max hp ' .. tostring(c:max_hp()))
        -- control: nothing hurts the companion yet; with the hero out of the leash it does not fight (it walks to the hero)
        local att0 = watch(c, foe2, 3, 'before hit')
        -- a hit: its health drops (the mod notices a drop in health; the enemy is only a target, it never hits back: damage 0)
        c:set_hp(math.max(1, (c:hp() or 10) - 3))
        local att, lastd = watch(c, foe2, 8, 'after hit')
        print(('fight back: attacking before the hit %d of 3, after %d of 8'):format(att0, att))
        check(att0 == 0 and att >= 2, 'Fight back: after a hit it fights the enemy near it (not before), with the hero out of the leash')
    else
        print('no foe for test 4')
    end
    AU.quit(failures == 0 and 0 or 1)
end
gear.task(function() local ok, e = pcall(main) if not ok then print('ERROR ' .. tostring(e)) AU.quit(2) end end)
