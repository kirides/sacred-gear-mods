-- A self test of the spawn-rate mod and of Sacred Gear's `creature.created` event, for runs without a player:
--
--     Sacred.exe -gear-auto -gear-instance=spawnrate -gear-load=1 -gear-mods=spawn-rate,spawn-rate_selftest
--
-- It loads a savegame, multiplies what is already there (100x), teleports the hero to places far away (sectors the savegame has not filled yet) and checks that
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
-- A teleport into new sectors costs the game itself hundreds of milliseconds (sector loads), whatever the mod does: judge by the
-- share of slow frames, with an upper bound for the worst.
local function frame_ok() return frames.slow <= math.max(5, frames.n * 0.03) and frames.max < 3 end
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

-- How many of the living extras (ids) are hostile to the hero, both ways (like their originals).
local function hostile_count(ids)
    local hero = W.hero()
    local total, enemies = 0, 0
    for _, id in ipairs(ids) do
        local c = W.object(id)
        if c and c:exists() and not c:is_dead() then
            total = total + 1
            if c:is_enemy(hero) == true and hero:is_enemy(c) == true then enemies = enemies + 1 end
        end
    end
    return enemies, total
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

    -- Phase H: hostility. An extra must be hostile to the hero like its original (is_enemy) and must actually attack: the hero
    -- stands next to a hostile group, the mod multiplies it (5x) and the extras close to the hero have to come and fight.
    do
        local mates = {}
        for _, c in ipairs(W.creatures_near(x0, y0, 5000, {layer = layer, limit = 800})) do
            if c.id ~= hero.id and not c:is_dead() and c:is_enemy(hero) == true then
                mates[#mates + 1] = c
            end
        end
        local origin = mates[1]
        check('hostility: a hostile group is in reach', origin ~= nil, #mates)
        if origin then
            local ox, oy = origin:position()
            local baseline_hp = hero:hp() or 1
            configure({rate = 5, max_extra = 200, budget = 20, existing = true})
            hero:teleport(ox + 450, oy, layer)
            local reached, near_ids, first_seen = {}, {}, {}
            -- level and maximum health of the originals by type and level (seen while the test runs: some die before it ends): an extra
            -- must have what an original of its type and level has
            local original_max, is_extra = {}, {}
            local worst = 1e9
            for step = 1, 48 do                        -- 24 s
                gear.wait(0.5)
                local hx, hy = hero:position()
                local st = stats()
                for _, id in ipairs(st.ids) do is_extra[id] = true end
                for _, m in ipairs(W.creatures_near(hx, hy, 3600, {layer = layer, limit = 800})) do
                    if not is_extra[m.id] and not m:is_dead() and m:is_enemy(hero) == true then
                        local t, lv = m:type(), m:level() or 0
                        original_max[t] = original_max[t] or {}
                        original_max[t][lv] = original_max[t][lv] or {}
                        original_max[t][lv][m:max_hp()] = true
                    end
                end
                for _, id in ipairs(st.ids) do
                    local c = W.object(id)
                    if c and c:exists() and not c:is_dead() then
                        local cx, cy = c:position()
                        local d = math.sqrt((cx - hx) ^ 2 + (cy - hy) ^ 2)
                        first_seen[id] = first_seen[id] or d
                        if first_seen[id] <= 650 then near_ids[id] = true end
                        if d < (reached[id] or 1e9) then reached[id] = d end
                    end
                end
                hero:set_hp(hero:max_hp() or 1000)     -- keep the hero alive: the test is about who comes
            end
            local st = stats()
            local enemies, total = 0, 0
            local lvl_ok, lvl_total, level_one, lvl_exact, lvl_unmatched = 0, 0, 0, 0, 0
            for _, id in ipairs(st.ids) do
                local c = W.object(id)
                if c and c:exists() and not c:is_dead() then
                    lvl_total = lvl_total + 1
                    local lv, mx = c:level() or 0, c:max_hp()
                    -- the same level, and a maximum health like an original's: exactly, or within 25% (an original's armour and weapon
                    -- bonuses are not copied: its equipment is its own)
                    local seen = original_max[c:type()] and original_max[c:type()][lv]
                    if not seen and lvl_unmatched < 6 then
                        lvl_unmatched = lvl_unmatched + 1
                        local known = {}
                        for l2 in pairs(original_max[c:type()] or {}) do known[#known + 1] = l2 end
                        table.sort(known)
                        note('unmatched_' .. id, {type = c:type_name(), level = lv, max_hp = mx, originals_levels = known})
                    end
                    if seen then
                        local exact, close = seen[mx] == true, false
                        for m in pairs(seen) do if mx and math.abs(m - mx) <= 0.25 * m then close = true end end
                        if not close and lvl_unmatched < 8 then
                            lvl_unmatched = lvl_unmatched + 1
                            local maxes = {}
                            for m in pairs(seen) do maxes[#maxes + 1] = m end
                            table.sort(maxes)
                            note('far_' .. id, {type = c:type_name(), level = lv, max_hp = mx, hp = c:hp(), originals_max = maxes})
                        end
                        if exact then lvl_exact = lvl_exact + 1 end
                        if close then lvl_ok = lvl_ok + 1 end
                    end
                    if lv <= 1 and mx == 100 then level_one = level_one + 1 end
                end
                if c and c:exists() then
                    total = total + 1
                    if c:is_enemy(hero) == true and hero:is_enemy(c) == true then enemies = enemies + 1
                    else
                        local function f(o) return A.object_bytes(o.id, 0x1F0, 16) end
                        local sib
                        for _, m in ipairs(mates) do if m:type() == c:type() then sib = m break end end
                        note('nonhostile_' .. id, {type = c:type_name(), enemy_of_hero = c:is_enemy(hero), hero_enemy_of = hero:is_enemy(c), hp = c:hp(),
                            raw = f(c), original_raw = sib and f(sib) or 'none', original_enemy = sib and sib:is_enemy(hero)})
                    end
                end
            end
            local near_n, came = 0, 0
            for id in pairs(near_ids) do
                near_n = near_n + 1
                if (reached[id] or 1e9) <= 260 then came = came + 1 end
            end
            note('hostility', {extras = total, hostile = enemies, near = near_n, came = came, ordered = st.ordered, made = st.made})
            check('hostility: extras exist', total > 0, total)
            note('stats', {extras = lvl_total, like_original = lvl_ok, exactly = lvl_exact, level1_100hp = level_one})
            check('stats: the extras have the level and about the maximum health of an original of their type (90%)', lvl_total > 0 and lvl_ok >= lvl_total * 0.9,
                  ('%d of %d (%d exactly), %d are level 1 with 100 health'):format(lvl_ok, lvl_total, lvl_exact, level_one))
            check('hostility: every extra is hostile to the hero, both ways (like its original)', total > 0 and enemies == total, ('%d of %d'):format(enemies, total))
            check('hostility: the mod gave attack orders', st.ordered > 0, st.ordered)
            check('hostility: at least 80% of the extras that started within 650 units came to fight (within 260)', near_n > 0 and came >= near_n * 0.8,
                  ('%d of %d came'):format(came, near_n))
            for _, id in ipairs(st.ids) do
                local c = W.object(id)
                if c and c:exists() then c:remove() end
            end
            gear.emit('spawn-rate.reset')
            configure({rate = 1, existing = false})
            gear.wait(3)
            hero:teleport(x0, y0, layer)
            gear.wait(1)
        end
    end

    -- Phase 0: the creatures already there (what a savegame restored: no creature.created event exists for them). At 100x with
    -- the sliders at their maxima the mod must make a good share of max_extra from them, near the hero first.
    local function remove_extras()
        for _, id in ipairs(stats().ids) do
            local c = W.object(id)
            if c and c:exists() then c:remove() end
        end
        gear.emit('spawn-rate.reset')
    end
    local present = 0
    local nearest
    for _, c in ipairs(W.creatures_near(x0, y0, 3500, {layer = layer, limit = 800})) do
        if c.id ~= hero.id and not c:is_dead() and c:is_enemy(hero) == true then
            present = present + 1
            if not nearest then local nx, ny = c:position(); nearest = {x = nx, y = ny, type = c:type_name()} end
        end
    end
    note('present_hostile_within_3500', present)
    local made_events_before = #created
    configure({rate = 100, max_extra = 1000, budget = 20, existing = true})
    reset_frames()
    local t_start = os.clock()
    local reached
    local max_alive0 = 0
    for _ = 1, 240 do                       -- up to 60 s
        gear.wait(0.25)
        local st = stats()
        if st.alive > max_alive0 then max_alive0 = st.alive end
        if st.alive >= 1000 or (st.queued == 0 and st.from_scan > 0 and st.alive > 0) then reached = st; break end
    end
    local s0 = reached or stats()
    local secs = os.clock() - t_start
    note('phase0', {present = present, from_scan = s0.from_scan, from_events = s0.from_events, made = s0.made, alive = s0.alive, queued = s0.queued,
                    refused = s0.refused, gave_up = s0.gave_up, failed = s0.failed, max_alive = max_alive0, seconds = secs,
                    frame_max = frames.max, slow = frames.slow, frames = frames.n, events_meanwhile = #created - made_events_before})
    check('existing: hostile creatures are there to multiply', present > 0, present)
    check('existing: they were found by the look around (no event for them)', s0.from_scan > 0 and s0.from_scan >= s0.from_events, ('%d scanned, %d by event'):format(s0.from_scan, s0.from_events))
    local want = math.min(1000, present * 99)
    check('existing: extras reach a good share of max_extra (at least 60% of what 100x asks within the cap)', s0.alive >= want * 0.6,
          ('%d alive, %d possible, %.1f s'):format(s0.alive, want, secs))
    check('existing: never more than max_extra', max_alive0 <= 1000, max_alive0)
    check('existing: frame time sane', frame_ok(), ('max %.3f s, %d slow of %d'):format(frames.max, frames.slow, frames.n))
    -- fair and near: extras stand around several originals, the nearest original has some
    local around, nearest_extras = {}, 0
    for _, id in ipairs(s0.ids) do
        local c = W.object(id)
        if c and c:exists() then
            local cx, cy = c:position()
            if nearest and math.abs(cx - nearest.x) < 450 and math.abs(cy - nearest.y) < 450 then nearest_extras = nearest_extras + 1 end
            local ty = c:type()
            around[tostring(ty)] = (around[tostring(ty)] or 0) + 1
        end
    end
    local kinds_made = 0
    for _ in pairs(around) do kinds_made = kinds_made + 1 end
    note('extras_by_type', around)
    check('existing: the nearest hostile creature got its extras', nearest_extras > 0, nearest_extras)
    -- a loaded game: the marks are written and read again, nothing is multiplied a second time
    local before = stats()
    gear.emit('spawn-rate.marks', 'write')
    gear.emit('spawn-rate.marks', 'read')
    gear.wait(5)
    local after = stats()
    check('reload: the extras are known again', after.alive == before.alive, ('%d -> %d'):format(before.alive, after.alive))
    check('reload: nothing is multiplied a second time (only what was still owed is queued again)',
          after.made == before.made and after.queued <= before.queued + 99 * (after.from_scan - before.from_scan) and after.alive == before.alive,
          ('made %d -> %d, queued %d -> %d (%d creatures came into reach), alive %d -> %d'):format(before.made, after.made, before.queued, after.queued,
              after.from_scan - before.from_scan, before.alive, after.alive))
    remove_extras()
    configure({rate = 1, existing = false})
    gear.wait(3)

    -- Phase 1: the game as it is (rate 1): the event for the engine's spawns, none for ours.
    configure({rate = 1})
    local first = #created
    local sites = visit(x0, y0, layer, 2500)
    local seen = #created - first
    local kinds = {}
    for i = first + 1, #created do
        local e = created[i]
        local c = W.object(e.id)
        local nm = (c and c:exists() and c:type_name()) or ('type ' .. e.type)
        local k = kinds[nm] or {n = 0, hostile = 0, hp = c and c:exists() and c:max_hp() or nil, level = c and c:exists() and c:level() or nil}
        k.n = k.n + 1
        if e.hostile then k.hostile = k.hostile + 1 end
        kinds[nm] = k
    end
    note('kinds', kinds)
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

    -- A mod that spawns from inside its own creature.created handler must not loop: what it makes raises no event.
    local loop_made, loop_ids, loop_events = 0, {}, 0
    local h = gear.on('creature.created', function(ev)
        if loop_made < 5 and not loop_ids[ev.id] then
            local c = W.spawn(ev.type, ev.x + 80, ev.y + 80, {layer = ev.layer})
            if c then loop_made = loop_made + 1; loop_ids[c.id] = true end
        end
        if loop_ids[ev.id] then loop_events = loop_events + 1 end
    end)
    sites = visit(x0, y0, layer, 3500)
    gear.wait(1)
    gear.off(h)
    check('spawning inside a creature.created handler: made', loop_made == 5, loop_made)
    check('spawning inside a creature.created handler: no event for them, no loop', loop_events == 0, loop_events)

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
    local ambient = 0
    for _, id in ipairs(s.ids) do
        local c = W.object(id)
        local n = c and c:exists() and (c:type_name() or ''):lower() or ''
        if n:find('rabbit') or n:find('crow') or n:find('dove') or n:find('bird') then ambient = ambient + 1 end
    end
    check('5x: no rabbits, crows, doves or birds among the extras', ambient == 0, ambient)
    local e5, t5 = hostile_count(s.ids)
    check('5x: every extra is hostile to the hero like its original', t5 > 0 and e5 == t5, ('%d of %d'):format(e5, t5))
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
    check('5x: the extras are next to originals of their kind (95%)', near > 0 and far <= near * 0.05, ('%d near, %d not'):format(near, far))
    check('5x: extras alive within max_extra', max_alive <= 200, max_alive)
    check('5x: nothing is refused for a full queue', s.refused == 0, s.refused)
    check('5x: frame time sane', frame_ok(), ('max %.3f s, %d slow frames of %d'):format(frames.max, frames.slow, frames.n))

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
    local e100, t100 = hostile_count(s.ids)
    check('100x: every extra is hostile to the hero like its original', t100 > 0 and e100 == t100, ('%d of %d'):format(e100, t100))
    check('100x: the cap was reached or no hostile spawned', max_alive >= 40 or hostile_since(first3 + 1) == 0, max_alive)
    check('100x: nothing is refused for a full queue', s.refused == 0, s.refused)
    check('100x: frame time sane', frame_ok(), ('max %.3f s, %d slow frames of %d'):format(frames.max, frames.slow, frames.n))
    configure({rate = 1})
    gear.wait(1)
    s = stats()
    check('rate back to 1: the queue is empty', s.queued == 0, s.queued)
    finish()
end)
