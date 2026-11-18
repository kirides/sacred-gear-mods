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

-- Called as fn(name, type_id, sector) for every kill that counts.
function G.on_kill(fn) on_kill = fn end

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
                tracked[id] = {c = c, type = t, name = c:type_name() or '', sector = c.sector and c:sector() or nil}
                n = n + 1
            end
        end
    end
    for id, e in pairs(tracked) do
        local c = e.c
        if not c:exists() or c:is_dead() then
            tracked[id] = nil
            if on_kill and counts(e, now) then on_kill(e.name, e.type, e.sector) end
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

-- Runs one hook action for the hero (single player: every target is the hero). `ctx` is unused here.
function G.run_action(action, title)
    if action.action == 'spawn' then
        local made, why = G.spawn_wave(action)
        if made == 0 then gear.log('world-events: wave failed: ' .. tostring(why)) end
        if action.text then G.message(title, action.text) end
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
