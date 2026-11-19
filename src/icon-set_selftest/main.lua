-- Self test of the icon-set mod, for runs without a player (use a copy of the game folder: the rolled items stay in the world):
--
--     Sacred.exe -gear-auto -gear-load=1 -gear-instance=iconset -gear-mods=icon-set,icon-set_selftest
--
-- Finds a creature near the hero whose loot function drops equipment, has the engine roll it 600 times with the mod's chance at 0
-- and at 50 percent, and counts the Icon Set pieces (types 5101 .. 5106) that lie on the ground afterwards.

if not gear.auto then print('no automation (start the game with -gear-auto): nothing to do') return end
local A, cfg = gear.auto, gear.config
local results = {passed = 0, failed = 0}
local function check(name, ok, detail)
    results[ok and 'passed' or 'failed'] = results[ok and 'passed' or 'failed'] + 1
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end
local function finish()
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    A.write('iconset.json', gear.json.encode(results))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function roll(creature, n)
    gear.drops.reset_stats()
    if not gear.drops.simulate(creature, n, 0) then return nil end
    gear.wait_until(function() local d, q = gear.drops.simulation_progress() return d >= q end, 120)
    gear.wait(0.2)
    return gear.drops.stats()
end

local function icons(x, y, layer)
    local n = 0
    for _, it in pairs(gear.world.items_near(x, y, 4000, {layer = layer, limit = 100000})) do
        if it.type >= 5101 and it.type <= 5106 then n = n + 1 end
    end
    return n
end

check('main menu', A.wait_for_menu(cfg.timeout_menu))
if not A.wait_for_game(cfg.timeout_game) then check('game with a hero', false) return finish() end
gear.wait(3)
local hero = gear.world.hero()
local x, y, layer = hero:position()
local creature
for _, c in ipairs(gear.world.creatures_near(x, y, 4000, {layer = layer})) do
    if c.id ~= hero.id then
        local s = roll(c.id, 200)
        if s and s.picks > 0 then creature = c break end
    end
end
if not creature then check('a creature that drops equipment', false) return finish() end
local cx, cy, clayer = creature:position()

gear.emit('icon-set.configure', {chance = 0, per_level = 0, min_level = 1})
local before = icons(cx, cy, clayer)
local off = roll(creature.id, 600)
local after_off = icons(cx, cy, clayer)
check('chance 0: no Icon Set pieces from the mod', off and off.picks > 0 and after_off == before, after_off - before)

gear.emit('icon-set.configure', {chance = 50})
local on = roll(creature.id, 600)
local after_on = icons(cx, cy, clayer)
local made = after_on - after_off
check('chance 50: about half of the picks are Icon Set pieces', on and on.picks > 20 and made > on.picks * 0.3 and made < on.picks * 0.7,
      on and (made .. ' of ' .. on.picks))

gear.emit('icon-set.configure', {chance = 50, min_level = 200})
local high = roll(creature.id, 600)
local after_high = icons(cx, cy, clayer)
check('lowest level 200: no pieces below that level', high and after_high == after_on, after_high - after_on)
finish()
