-- World events, the single player half that touches the game (the logic is in localevents.lua / hooks.lua): finding the hero's kills,
-- spawning a wave around the hero (also the server's `worldevents:spawn` message, in the hero's own game), dropping items and gold.
-- Gear changes the world in single player only (`gear.world.can_change()`); everything here asks first and never throws.
--
-- Kills: the `kill` event only comes from network games, so the creatures around the hero are watched (the same way as the
-- bounty mod does it): a monster (object kind 3) that was near and is gone or dead now counts as the hero's kill when the hero hit a
-- creature of its type in the last 8 seconds (the `damage` event), or when the loot roll of its death named the hero as the killer.
local hooks = require('hooks')

local W = gear.world
local G = {}

local TRACK, FORGET, HIT_WINDOW, MAX_TRACKED, KIND_MONSTER = 1400, 2600, 8, 160, 3
local CARRIER = 'HORSE.GRN'      -- a harmless creature whose loot table has equipment: the item is rolled as its drop
local EQUIPMENT = {weapon = true, armor = true, shield = true, jewelry = true}

local tracked, hit_at, roll_at = {}, {}, {}
local hero_type
local on_kill
local rolling                    -- {level, bonus} while a reward item is rolled
local waves_alive = 0            -- creatures of this mod's waves that were created (for the selftest)

-- Called as fn(name, type_id, sector, region id or nil) for every kill that counts.
function G.on_kill(fn) on_kill = fn end

-- The id of the game region a creature is in (gear.data.regions, newer Gear versions), nil outside or without the table.
function G.region_of(c)
    local api = gear.data and gear.data.regions
    if not (api and api.of_creature) then return nil end
    local ok, r = pcall(api.of_creature, api, c)
    return ok and type(r) == 'table' and tonumber(r.id) or nil
end

function G.reset() tracked, hit_at, roll_at = {}, {}, {} end

gear.on('damage', function(hit)
    -- inside the engine's damage resolution: only a table write
    if type(hit) == 'table' and hero_type and hit.attacker_type == hero_type then hit_at[hit.victim_type] = gear.time() end
    return nil
end)
gear.on('drops.roll', function(r)
    if rolling then r.bonus = rolling.bonus return end
    if r.killer == 1 then roll_at[r.creature] = gear.time() end
end)
gear.on('drops.select', function(s)
    if rolling then s.level = rolling.level end
end)

local function counts(entry, now)
    local h, r = hit_at[entry.type], roll_at[entry.type]
    return (h and now - h <= HIT_WINDOW) or (r and now - r <= 2)
end

-- Run a few times a second.
function G.poll()
    local hero = W.hero()
    if not hero or not W.can_change() then return end
    hero_type = hero:type()
    local hx, hy, layer = hero:position()
    if not hx then return end
    local now = gear.time()
    local n = 0
    for _ in pairs(tracked) do n = n + 1 end
    for _, c in ipairs(W.creatures_near(hx, hy, TRACK, {limit = 64, layer = layer}) or {}) do
        local id = c.id
        if id > 16 and not tracked[id] and n < MAX_TRACKED and not c:is_dead() then
            local t = c:type()
            if t and gear.data.object_types:kind(t) == KIND_MONSTER then
                tracked[id] = {c = c, type = t, name = c:type_name() or '', sector = c.sector and c:sector() or nil, region = G.region_of(c)}
                n = n + 1
            end
        end
    end
    for id, e in pairs(tracked) do
        local c = e.c
        if not c:exists() or c:is_dead() then
            tracked[id] = nil
            if on_kill and counts(e, now) then on_kill(e.name, e.type, e.sector, e.region) end
        else
            local x, y = c:position()
            if not x or (x - hx) ^ 2 + (y - hy) ^ 2 > FORGET ^ 2 then tracked[id] = nil end
        end
    end
end

-- The object type id of a creature kind from a hook: a number is the id; a name is the game's internal name (ORC_WARRIOR.GRN) or
-- words of it ("Orc Warrior" -> ORC_WARRIOR, the first monster type that has them).
function G.resolve(kind)
    if type(kind) == 'number' then return kind end
    if type(kind) ~= 'string' or kind == '' then return nil end
    local types = gear.data and gear.data.object_types
    if not types then return nil end
    local id = types:find(kind)
    if id then return id end
    local needle = kind:upper():gsub('%s+', '_')
    for _, form in ipairs({needle .. '.', needle}) do
        for _, m in ipairs(types:search(form, 50) or {}) do
            if m.kind == KIND_MONSTER or m.kind == nil then return m.id end
        end
    end
    return nil
end

-- A wave (a checked `hooks.parse_spawn` table, or {n, radius, kinds}) around the hero. Returns the number of creatures made and,
-- when nothing was made, a reason. `rnd(k)` -> 1..k.
function G.spawn_wave(wave, rnd)
    rnd = rnd or function(k) return math.random(k) end
    local hero = W.hero()
    if not hero then return 0, 'no hero' end
    if not W.can_change() then return 0, 'the world cannot be changed here (not a single player game)' end
    local hx, hy, layer = hero:position()
    if not hx then return 0, 'no hero position' end
    local names = hooks.pick_kinds(wave.kinds, wave.n, rnd)
    local places = hooks.offsets(#names, wave.radius, rnd)
    local made, why = 0, nil
    for i, kind in ipairs(names) do
        local id = G.resolve(kind)
        if not id then
            why = 'unknown creature ' .. tostring(kind)
            gear.log('world-events: ' .. why)
        else
            local x, y = hx + places[i][1], hy + places[i][2]
            local c, err = W.spawn(id, x, y, {layer = layer, label = 'world-events'})
            if c then made = made + 1 else why = tostring(err); gear.log('world-events: cannot spawn ' .. tostring(kind) .. ': ' .. why) end
        end
    end
    waves_alive = waves_alive + made
    return made, made == 0 and why or nil
end

function G.gold(amount)
    local hero = W.hero()
    if not hero or not amount or amount <= 0 then return false end
    return hero:add_gold(amount) and true or false
end

function G.message(title, text)
    if gear.toast and gear.toast.show then gear.toast.show(title, text) end
end

local function ground_items(x, y) return W.items_near(x, y, 400, {limit = 64}) or {} end

-- One item for the hero: an item type by name or number lies down at the hero's feet; a rarity / category / level spec is rolled with the
-- game's own loot function (a horse is put there as the creature that "drops" it, rolled with a raised rarity bonus at the spec's
-- level until something fitting lands; the horse is removed again). `done(ok)` is called when it is over.
function G.item(spec, done)
    local function finish(ok) if done then done(ok) end end
    local hero = W.hero()
    if not hero or not W.can_change() or type(spec) ~= 'table' then return finish(false) end
    local hx, hy, layer = hero:position()
    if not hx then return finish(false) end
    if spec.type ~= nil then
        local id = G.resolve(spec.type)
        if not id then gear.log('world-events: unknown item ' .. tostring(spec.type)); return finish(false) end
        local item, err = W.spawn(id, hx + 24, hy + 24, {layer = layer, label = 'world-events'})
        if not item then gear.log('world-events: cannot drop ' .. tostring(spec.type) .. ': ' .. tostring(err)) end
        return finish(item ~= nil)
    end
    if rolling then return finish(false) end
    local quality = spec.quality or 0
    local bonus = quality >= 9 and 700 or quality >= 5 and 350 or 150
    local level = spec.level or hero:level() or 1
    gear.task(function()
        local ok = false
        local carrier = W.spawn(CARRIER, hx + 24, hy + 24, {layer = layer, label = 'world-events'})
        if carrier then
            local before = {}
            for _, it in ipairs(ground_items(hx, hy)) do before[it.id] = true end
            rolling = {level = level, bonus = bonus}
            for _ = 1, 120 do
                if not gear.drops.simulate(carrier.id, 1, bonus, 0) then break end
                gear.wait_until(function() local d, q = gear.drops.simulation_progress() return d >= q end, 2)
                gear.wait(0.05)
                for _, it in ipairs(ground_items(hx, hy)) do
                    if not before[it.id] then
                        before[it.id] = true
                        local keep = not ok and (spec.category and it.category == spec.category or (not spec.category and EQUIPMENT[it.category] == true))
                        if keep and spec.quality and W.QUALITIES then
                            local rank = (it.quality_rank or 0)
                            keep = rank >= math.min(spec.quality, 4)
                        end
                        if keep then ok = true else gear.inv.destroy(it.id) end
                    end
                end
                if ok then break end
            end
            rolling = nil
            local gone, why = carrier:remove()
            if not gone then gear.log('world-events: cannot remove the loot carrier: ' .. tostring(why)) end
        end
        finish(ok)
    end)
end

---------------------------------------------------------------------------------------------------------------
-- world bosses (a `boss` action): a creature with Gear's modifiers (gear.world creature:set_modifiers)
---------------------------------------------------------------------------------------------------------------
-- Does the creature type name have the words `near` ("Orc Warrior" matches ORC_WARRIOR.GRN)? "*" or "any" match every monster.
local function name_has(type_name, near)
    if near == '*' or near:lower() == 'any' then return true end
    if type(type_name) ~= 'string' then return false end
    return type_name:upper():find((near:upper():gsub('%s+', '_')), 1, true) ~= nil
end

-- The nearest living hostile monster within `radius` of the hero whose type name has the words `near`, that is no boss yet; nil if none.
function G.find_creature(near, radius, skip)
    local hero = W.hero()
    if not hero then return nil end
    local hx, hy, layer = hero:position()
    if not hx then return nil end
    local taken = {}
    for _, m in ipairs(W.modified and W.modified() or {}) do taken[m.id] = true end
    for _, c in ipairs(W.creatures_near(hx, hy, radius, {limit = 64, layer = layer}) or {}) do
        if c.id > 16 and not taken[c.id] and not (skip and skip[c.id]) and not c:is_dead() then
            local t = c:type()
            if t and gear.data.object_types:kind(t) == KIND_MONSTER and name_has(c:type_name(), near) and hero:is_enemy(c) then return c end
        end
    end
    return nil
end

local boss_counter = 0

-- Whether saved bosses can be attached now (a game of its own, a hero).
function G.can_attach() return W.can_change() and W.hero() ~= nil end

-- Makes a boss next to the hero from a clean boss (hooks.clean_boss): promotes the nearest creature with the words `near`, or (else) creates
-- one of the `kinds` around the hero. Returns the record {key, creature, type, type_name, name, base_hp, max_hp, mods, reward, text, promoted}
-- (keep it: the mod saves it with the savegame) or nil and a reason. `rnd(k)` -> 1..k.
function G.make_boss(boss, rnd, skip)
    rnd = rnd or function(k) return math.random(k) end
    local hero = W.hero()
    if not hero then return nil, 'no hero' end
    if not W.can_change() then return nil, 'the world cannot be changed here (not a single player game)' end
    if not hero.set_modifiers or not hero.is_enemy then return nil, 'this Sacred Gear has no creature modifiers' end
    local hx, hy, layer = hero:position()
    if not hx then return nil, 'no hero position' end
    local c, promoted
    if boss.near then
        c = G.find_creature(boss.near, math.max(boss.radius, 600) * 2, skip)
        promoted = c ~= nil
    end
    if not c and #boss.kinds > 0 then
        local kind = hooks.pick_kinds(boss.kinds, 1, rnd)[1]
        local id = G.resolve(kind)
        if not id then return nil, 'unknown creature ' .. tostring(kind) end
        local place = hooks.offsets(1, boss.radius, rnd)[1]
        local made, err = W.spawn(id, hx + place[1], hy + place[2], {layer = layer, label = 'world-events boss'})
        if not made then return nil, tostring(err) end
        c = made
        waves_alive = waves_alive + 1
    end
    if not c then return nil, 'no suitable creature near the hero' end
    local mods = {health = boss.health, damage = boss.damage, taken = boss.taken, deflect = boss.deflect, reflect = boss.reflect, regen = boss.regen}
    local ok, err = c:set_modifiers(mods)
    if not ok then
        if not promoted then c:remove() end
        return nil, tostring(err)
    end
    local stats = c:modifier_stats() or {}
    boss_counter = boss_counter + 1
    return {
        key = ('local:%d:%d'):format(math.floor(gear.time()), boss_counter), creature = c.id, type = c:type(), type_name = c:type_name(), name = boss.name,
        base_hp = stats.base_max_hp or c:max_hp(), max_hp = c:max_hp(), mods = mods, reward = boss.reward, text = boss.text, promoted = promoted,
    }
end

-- A boss from the savegame (a record kept with it) is attached again: the creature is in the world with the boosted health the save wrote,
-- the modifiers were forgotten by the load. Returns true, or false and a reason (the creature is gone, dead or another one).
function G.attach_boss(rec)
    local c = W.object(rec.creature)
    if not c or not c:exists() then return false, 'gone' end
    if c:type() ~= rec.type then return false, 'another creature' end
    if c:is_dead() then return false, 'dead' end
    local mods = {}
    for k, v in pairs(rec.mods or {}) do mods[k] = v end
    mods.base_hp = rec.base_hp
    local ok, err = c:set_modifiers(mods)
    if not ok then return false, tostring(err) end
    return true
end

-- What a boss is doing: 'active' with its health and maximum, 'defeated' (dead; or gone while nearly dead), 'gone' (the creature left the world
-- without dying as far as can be told). `rec.frac` is kept up to date for that guess.
function G.boss_state(rec)
    local c = W.object(rec.creature)
    local alive = c and c:exists() and c:type() == rec.type
    if alive then
        local hp, max = c:hp(), c:max_hp()
        if not hp or not max then alive = false
        elseif c:is_dead() then return 'defeated', 0, max
        else
            rec.frac = max > 0 and hp / max or 1
            return 'active', hp, max
        end
    end
    if (rec.frac or 1) <= 0.15 then return 'defeated', 0, rec.max_hp end
    return 'gone', 0, rec.max_hp
end

-- Takes the modifiers off a boss that is still in the world (the mod is switched off, the boss is dismissed).
function G.release_boss(rec)
    local c = W.object(rec.creature)
    if c and c:exists() and c:type() == rec.type then pcall(c.set_modifiers, c, nil) end
end

-- Runs one hook action for the hero (single player: every target is the hero). `ctx` is unused here.
function G.run_action(action, title)
    if action.action == 'spawn' then
        local made, why = G.spawn_wave(action)
        if made == 0 then gear.log('world-events: wave failed: ' .. tostring(why)) end
        if action.text then G.message(title, action.text) end
    elseif action.action == 'boss' then
        -- main.lua makes bosses (it keeps the record, the events and the bar): nothing to do here
        gear.log('world-events: a boss action reached run_action without the boss manager')
    elseif action.action == 'item' then
        for _ = 1, action.n do G.item(action.spec) end
        if action.text then G.message(title, action.text) end
    elseif action.action == 'gold' then
        G.gold(action.amount)
        if action.text then G.message(title, action.text) end
    elseif action.action == 'message' then
        G.message(title, action.text)
    end
end

function G.waves_made() return waves_alive end

return G
