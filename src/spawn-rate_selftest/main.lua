-- A self test of the spawn-rate mod and of Sacred Gear's `creature.created` event, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=spawnrate -gear-load=1 -gear-mods=spawn-rate,spawn-rate_selftest
--
-- It loads a savegame, teleports the hero to places far away (sectors the savegame has not filled yet) and checks that
--   * `creature.created` fires for the creatures the engine spawns, and not for `gear.world.spawn`,
--   * at 5x the extras appear next to the originals, and are not multiplied again,
--   * at 100x the extras alive never exceed `max_extra`, the frame times stay sane and the queue drains.
-- The creatures it makes stay in the world: use a copy of the game folder. Results: GearAutomation\<instance>\spawn-rate.json.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A = gear.auto
local cfg = gear.config
local W = gear.world
local results = {passed = 0, failed = 0, notes = {}}

local function check(name, ok, detail)
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end
local function note(key, value)
    results.notes[key] = value
    print(('NOTE %s = %s'):format(key, gear.json.encode(value)))
end

local function finish()
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    A.write('spawn-rate.json', gear.json.encode(results))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

-- what the engine spawned (the event), what a frame took
local created = {}
local by_id = {}
gear.on('creature.created', function(ev)
    local hero = W.hero()
    local c = ev.creature
    local hostile = hero ~= nil and c ~= nil and c:is_enemy(hero) == true and not c:is_dead()
    local e = {id = ev.id, type = ev.type, x = ev.x, y = ev.y, layer = ev.layer, hostile = hostile}
    -- an id the spawn-rate mod holds as its own extra right now: the engine's create was seen for it (multiplied again)
    local s
    gear.emit('spawn-rate.stats', function(v) s = v end)
    for _, id in ipairs(s and s.ids or {}) do if id == ev.id then e.extra = true; break end end
    created[#created + 1] = e
    by_id[ev.id] = e
end)
local frames = {max = 0, slow = 0, n = 0}
gear.on('frame', function(dt)
    frames.n = frames.n + 1
    if dt > frames.max then frames.max = dt end
    if dt > 0.1 then frames.slow = frames.slow + 1 end
end)
local function reset_frames() frames.max, frames.slow, frames.n = 0, 0, 0 end

local function stats()
    local s
    gear.emit('spawn-rate.stats', function(v) s = v end)
    return s or {made = 0, refused = 0, failed = 0, alive = 0, queued = 0, ids = {}}
end

local function configure(values)
    gear.emit('spawn-rate.configure', values)
    gear.wait(0.3)
end

local DIRS = 8
-- Visits `cfg.sites` places on a ring of `radius` world units around (x0, y0); `each` runs every quarter second of the dwell.
local function visit(x0, y0, layer, radius, each)
    local hero = W.hero()
    local ok_count = 0
    for i = 0, cfg.sites - 1 do
        local a = (i / DIRS) * 2 * math.pi + radius * 0.001
        local x = math.floor(x0 + math.cos(a) * radius)
        local y = math.floor(y0 + math.sin(a) * radius)
        local ok, err = hero:teleport(x, y, layer)
        if ok then
            ok_count = ok_count + 1
            local t = 0
            while t < cfg.dwell do
                gear.wait(0.25)
                t = t + 0.25
                if each then each() end
            end
            hero:set_hp(hero:max_hp() or 1000)
        else
            print(('  site %d (%d, %d): %s'):format(i, x, y, tostring(err)))
        end
    end
    return ok_count
end

local function hostile_since(first)
    local n = 0
    for i = first, #created do if created[i].hostile then n = n + 1 end end
    return n
end

gear.task(function()
    A.wait_for_menu(cfg.timeout_menu)
    if not A.wait_for_game(cfg.timeout_game) then
        check('game with a hero', false)
        return finish()
    end
    gear.wait(3)
    local hero = W.hero()
    local x0, y0, layer = hero:position()
    note('start', {x0, y0, layer})
    check('single player: the world may be changed', W.can_change())

    -- Phase 1: the game as it is (rate 1): the event for the engine's spawns, none for ours.
    configure({rate = 1})
    local first = #created
    local sites = visit(x0, y0, layer, 2500)
    local seen = #created - first
    note('phase1', {sites = sites, created = seen, hostile = hostile_since(first + 1)})
    check('creature.created: fires for the creatures the engine spawns', seen > 0, ('%d events at %d sites'):format(seen, sites))
    if seen == 0 then
        results.notes.verdict = 'the hook on 0x5FBA40 does not see the engine spawns on this route'
        return finish()
    end
    local sample = created[1]
    local before = #created
    local mine = W.spawn(sample.type, x0 + 120, y0 + 120, {layer = layer})
    gear.wait(0.5)
    check('gear.world.spawn made a creature', mine ~= nil)
    local leaked = false
    for i = before + 1, #created do if mine and created[i].id == mine.id then leaked = true end end
    check('creature.created: not for gear.world.spawn', not leaked)
    if mine then mine:remove() end
    check('rate 1: no extras', stats().made == 0, stats().made)

    -- Phase 2: 5x
    configure({rate = 5, max_extra = 200, budget = 4})
    reset_frames()
    first = #created
    local max_alive = 0
    sites = visit(x0, y0, layer, 5000, function() local s = stats(); if s.alive > max_alive then max_alive = s.alive end end)
    gear.wait_until(function() return stats().queued == 0 end, 25)
    gear.wait(1)
    local s = stats()
    local hostile = hostile_since(first + 1)
    note('phase5', {sites = sites, created = #created - first, hostile = hostile, made = s.made, failed = s.failed, refused = s.refused,
                    alive = s.alive, max_alive = max_alive, queued = s.queued, frame_max = frames.max, slow = frames.slow, frames = frames.n})
    check('5x: extras were made', hostile == 0 or s.made > 0, ('%d hostile originals, %d extras'):format(hostile, s.made))
    check('5x: at most rate-1 extras per original', s.made <= hostile * 4, ('%d <= %d'):format(s.made, hostile * 4))
    local re_event = 0
    for _, e in ipairs(created) do if e.extra then re_event = re_event + 1 end end
    check('5x: no creature.created for the extras (they are not multiplied again)', re_event == 0, re_event)
    local near, far = 0, 0
    for _, id in ipairs(s.ids) do
        local c = W.object(id)
        if c and c:exists() then
            local cx, cy = c:position()
            local t = c:type()
            local found = false
            for _, e in ipairs(created) do
                if e.hostile and e.type == t and math.abs(e.x - cx) < 400 and math.abs(e.y - cy) < 400 then found = true; break end
            end
            if found then near = near + 1 else far = far + 1 end
        end
    end
    check('5x: the extras are next to originals of their kind', near > 0 and far == 0, ('%d near, %d not'):format(near, far))
    check('5x: extras alive within max_extra', max_alive <= 200, max_alive)
    check('5x: the queue stays bounded by max_extra', s.queued <= 200, s.queued)
    check('5x: frame time sane', frames.max < 1.0, ('max %.3f s, %d slow frames of %d'):format(frames.max, frames.slow, frames.n))

    -- Phase 3: 100x with a low cap (the extras of phase 2 are removed first: the cap limits new ones, it does not remove)
    for _, id in ipairs(s.ids) do
        local c = W.object(id)
        if c and c:exists() then c:remove() end
    end
    configure({rate = 1})
    gear.wait(3)    -- the mod notices the removed extras
    check('the extras of phase 2 are forgotten', stats().alive == 0, stats().alive)
    configure({rate = 100, max_extra = 50, budget = 4})
    reset_frames()
    max_alive = 0
    local first3 = #created
    sites = visit(x0, y0, layer, 7500, function() local st = stats(); if st.alive > max_alive then max_alive = st.alive end end)
    gear.wait(2)
    s = stats()
    note('phase100', {sites = sites, created = #created - first3, hostile = hostile_since(first3 + 1), made = s.made, refused = s.refused,
                      failed = s.failed, alive = s.alive, max_alive = max_alive, queued = s.queued, frame_max = frames.max, slow = frames.slow, frames = frames.n})
    check('100x: extras alive never exceed max_extra', max_alive <= 50, max_alive)
    check('100x: the cap was reached or no hostile spawned', max_alive >= 40 or hostile_since(first3 + 1) == 0, max_alive)
    check('100x: the queue stays bounded by max_extra', s.queued <= 50, s.queued)
    check('100x: frame time sane', frames.max < 1.0, ('max %.3f s, %d slow frames of %d'):format(frames.max, frames.slow, frames.n))
    configure({rate = 1})
    gear.wait(1)
    s = stats()
    check('rate back to 1: the queue is empty', s.queued == 0, s.queued)
    finish()
end)
