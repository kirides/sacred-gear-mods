-- In-game test of spell-tuning: the hero (a wood elf in savegame 10) casts the root spell (40) on a foe at 100 % and at 50 % of the
-- duration for "the hero you play"; the foe's time standing still must follow, and the record must show the scaled numbers.
-- Run: Sacred.exe -gear-auto -gear-load=10 -gear-mods=spell-tuning,spell-tuning_selftest (in a copy of the game folder).
local AU = gear.auto
local abil = gear.data.abilities
local used = {}
local failures = 0
local function check(c, name) print((c and 'PASS ' or 'FAIL ') .. name) if not c then failures = failures + 1 end end
local function dist(a, b, c, d) return math.sqrt((a - c) ^ 2 + (b - d) ^ 2) end

local function pick_foe(h)
    local x, y, layer = h:position()
    for _, c in ipairs(gear.world.creatures_near(x, y, 4000, {layer = layer})) do
        if not c:is_dead() and h:is_enemy(c) and not c:is_hero() and not used[c.id] and (c:type_name() or ''):lower():find('darkelve') then
            used[c.id] = true
            return c
        end
    end
end

-- Seconds from the cast until the foe moves; nil if it did not within 40 s.
local function root_seconds(h)
    local foe = pick_foe(h)
    if not foe then print('no foe') return nil end
    foe:set_modifiers({health = 5000, damage = 0})
    local x, y = h:position()
    foe:teleport(x + 130, y - 130)
    gear.wait(2)
    local fx0, fy0 = foe:position()
    h:order_ability(40, foe)
    local t = 0
    while t < 40 do
        gear.wait(0.25) t = t + 0.25
        local fx, fy = foe:position()
        if fx and t > 1 and dist(fx, fy, fx0, fy0) > 25 then
            foe:teleport(x + 4000, y)
            return t
        end
    end
    foe:teleport(x + 4000, y)
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
    local full = root_seconds(h)
    print('root at 100 %: ' .. tostring(full) .. ' s, record p0 ' .. abil[40].param0_base)
    gear.wait(20) -- the spell regenerates
    gear.emit('spell-tuning.configure', {hero_duration = 50})
    local half = root_seconds(h)
    print('root at 50 %: ' .. tostring(half) .. ' s, record p0 ' .. abil[40].param0_base)
    check(abil[40].param0_base == math.floor(base / 2 + 0.5), 'the record holds half the base duration while the hero casts')
    check(full and half and half < full * 0.7, 'the root lasts clearly shorter at 50 %')
    gear.emit('spell-tuning.configure', {hero_duration = 100})
    AU.quit(failures == 0 and 0 or 1)
end
gear.task(function() local ok, e = pcall(main) if not ok then print('ERROR ' .. tostring(e)) AU.quit(2) end end)
