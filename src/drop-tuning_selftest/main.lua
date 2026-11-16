-- A self test of the drop-tuning mod, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=droptuning -gear-load=1 -gear-mods=drop-tuning,drop-tuning_selftest
--
-- loads savegame 1, checks that the mod leaves the game's rarity table alone with its default settings, then steers it
-- with gear.emit('drop-tuning.configure', ...) and checks that the table, the drop rate and the generator follow, and that
-- the defaults bring everything back. The loot rolls make items in the world: use a copy of the game folder.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local drops = gear.drops
local results = {passed = 0, failed = 0}

local function check(name, ok, detail)
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
end

local function finish()
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    A.write('drop-tuning.json', gear.json.encode(results))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function configure(values)
    gear.emit('drop-tuning.configure', values)
    gear.wait(0.3)       -- the kernel pushes the settings after the tick
end

local function run(creature, n)
    drops.reset_stats()
    if not drops.simulate(creature, n, 0) then return nil end
    while true do
        local done, queued = drops.simulation_progress()
        if done >= queued then break end
        gear.wait(0.05)
    end
    gear.wait(0.1)
    return drops.stats()
end

local DEFAULTS = {chance = 1, find = 1, special = 1, low = 1, mid = 1, high = 1, rng = 'game', seed = 1}

gear.task(function()
    A.wait_for_menu(cfg.timeout_menu)
    if not A.wait_for_game(cfg.timeout_game) then
        check('game with a hero', false)
        return finish()
    end
    gear.wait(3)
    local hero = gear.world.hero()
    local x, y, layer = hero:position()
    local vanilla = drops.rarity_table()
    check('rarity table loaded', #vanilla > 0, #vanilla)

    local same = true
    for _, e in ipairs(vanilla) do same = same and e.weight == e.vanilla end
    check('defaults: the rarity table is the game\'s', same)

    local creature
    for _, c in ipairs(gear.world.creatures_near(x, y, 4000, {layer = layer})) do
        if c.id ~= hero.id then
            local s = run(c.id, 150)
            if s and s.picks > 0 then creature = c.id; break end
        end
    end
    if not creature then
        check('a creature that drops equipment', false)
        return finish()
    end
    local base = run(creature, cfg.rolls)
    check('defaults: no generator calls', base.rand_calls == 0 and base.vetoed == 0 and base.overridden == 0)

    configure({chance = 2, mid = 2, high = 0, special = 3, rng = 'fair'})
    local t = drops.rarity_table()
    local ok_t = true
    for _, e in ipairs(t) do
        local expect = e.vanilla
        if e.kind == 'special' then expect = e.vanilla * 3
        elseif e.kind == 'quality' and e.quality >= 10 then expect = 0
        elseif e.kind == 'quality' and e.quality >= 5 then expect = e.vanilla * 2 end
        ok_t = ok_t and e.weight == expect
    end
    check('settings: the table follows the mid / high / special settings', ok_t)
    local tuned = run(creature, cfg.rolls)
    check('settings: twice the chance gives clearly more equipment', tuned.picks > base.picks * 1.5, tuned.picks .. ' vs ' .. base.picks)
    check('settings: the fair generator answers', tuned.rand_calls > 0, tuned.rand_calls)
    local high = 0
    for q = 10, 14 do high = high + tuned.quality[q] end
    check('settings: no quality 10 to 14 with their weight at 0', high == 0, high)

    configure(DEFAULTS)
    local back = drops.rarity_table()
    local restored = #back == #vanilla
    for i, e in ipairs(back) do restored = restored and e.weight == vanilla[i].weight end
    check('defaults again: the table is the game\'s', restored)
    local again = run(creature, 100)
    check('defaults again: the game generator', again.rand_calls == 0)
    finish()
end)
