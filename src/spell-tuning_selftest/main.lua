-- In-game test of spell-tuning: the hero (a wood elf in savegame 10) casts the root spell (40) on a foe at 100 % and at 50 % of the
-- duration for "the hero you play"; the foe's time standing still must follow, and the record must show the scaled numbers.
-- Run: Sacred.exe -gear-auto -gear-load=10 -gear-mods=spell-tuning,spell-tuning_selftest (in a copy of the game folder).
local AU = gear.auto
local abil = gear.data.abilities
local failures = 0
local function check(c, name) print((c and 'PASS ' or 'FAIL ') .. name) if not c then failures = failures + 1 end end
local function dist(a, b, c, d) return math.sqrt((a - c) ^ 2 + (b - d) ^ 2) end

local function pick_foe(h)
    local x, y, layer = h:position()
    for _, c in ipairs(gear.world.creatures_near(x, y, 3000, {layer = layer, limit = 80})) do
        if not c:is_dead() and h:is_enemy(c) and not c:is_hero() and (c:type_name() or ''):lower():find('darkelve') then
            return c
        end
    end
end

-- Seconds from the cast until the foe moves; nil if it did not within 40 s.
local function root_seconds(h, caster)
    caster = caster or h
    local foe = pick_foe(h)
    if not foe then print('no foe') return nil end
    foe:set_modifiers({health = 5000, damage = 0})
    local x, y = h:position()
    foe:teleport(x + 130, y - 130)
    gear.wait(2)
    local fx0, fy0 = foe:position()
    -- the spell regenerates for about 80 s: wait until the caster may cast it
    local waited = 0
    while waited < 120 do
        local a = caster:ability(40)
        if a and a.ready then break end
        gear.wait(1) waited = waited + 1
    end
    print(('caster %d ready after %d s'):format(caster.id, waited))
    caster:order_ability(40, foe)
    gear.wait(1)
    if caster:casting() ~= 40 then print('the cast did not start') end
    local rec = abil[40].param0_base
    local t = 1
    while t < 40 do
        gear.wait(0.25) t = t + 0.25
        local fx, fy = foe:position()
        if fx and t > 1 and dist(fx, fy, fx0, fy0) > 25 then
            foe:set_modifiers({health = 5000, damage = 0})
            return t, rec
        end
    end
    foe:set_modifiers({health = 5000, damage = 0})
    return nil, rec
end

local function main()
    AU.wait_for_menu(120)
    if not AU.wait_for_game(180) then AU.quit(1) return end
    gear.wait(4)
    local h = gear.party.leader()
    h:learn(40, 5)
    gear.wait(1)
    local base = abil[40].param0_base
    gear.emit('spell-tuning.configure', {hero_duration = 100})
    local full, rec_full = root_seconds(h)
    print('root at 100 %: ' .. tostring(full) .. ' s, record p0 ' .. abil[40].param0_base)
    gear.emit('spell-tuning.configure', {hero_duration = 50})
    local half, rec_half = root_seconds(h)
    print('root at 50 %: ' .. tostring(half) .. ' s, record p0 ' .. abil[40].param0_base)
    check(rec_full == base and rec_half == math.floor(base / 2 + 0.5), ('the record holds %s then %s (base %s) when the hero casts at 100 %% then 50 %%'):format(tostring(rec_full), tostring(rec_half), tostring(base)))
    print(('hero root lasted %s s at 100 %%, %s s at 50 %% (informational: the foes vary)'):format(tostring(full), tostring(half)))
    gear.emit('spell-tuning.configure', {hero_duration = 100})

    -- A companion casts the same root: its role is 'companion', so only companion_duration counts (hero_duration stays 100).
    local comp = gear.party.recruit('woodelf', {experience = h:experience() or 0})
    if comp then
        gear.wait(3)
        local px, py, pl = h:position()
        comp:teleport(px + 60, py + 60, pl)
        comp:learn(40, 5)
        gear.wait(2)
        gear.emit('spell-tuning.configure', {hero_duration = 100, companion_duration = 100})
        local c_full, rec_c_full = root_seconds(h, comp)
        gear.emit('spell-tuning.configure', {companion_duration = 25})
        local c_quarter, rec_c_quarter = root_seconds(h, comp)
        print(('companion root at 100 %%: %s s, at 25 %%: %s s, record p0 %d'):format(tostring(c_full), tostring(c_quarter), abil[40].param0_base))
        check(rec_c_full == base and rec_c_quarter == math.floor(base / 4 + 0.5), ('a companion cast gets companion_duration (hero 100 %%): record %s then %s, base %s'):format(tostring(rec_c_full), tostring(rec_c_quarter), tostring(base)))
        gear.emit('spell-tuning.configure', {companion_duration = 100})
    else
        print('no companion recruited')
    end
    AU.quit(failures == 0 and 0 or 1)
end
gear.task(function() local ok, e = pcall(main) if not ok then print('ERROR ' .. tostring(e)) AU.quit(2) end end)
