-- The parts of the local bounty board that touch the game: finding the hero's kills in single player and paying rewards.
--
-- Kills: the `kill` event only comes from network games, so here the creatures around the hero are watched. A monster
-- (object kind 3) that was near, and is gone or dead now, counts as the hero's kill when the hero hit a creature of
-- that type in the last 8 seconds (the `damage` event), or when the loot roll of its death named the hero as the killer.
-- What this cannot tell: a monster someone else (a pet, a trap, another monster) finished right after the hero hit one
-- of its kind also counts. Pets killing alone, and monsters the hero never hit, do not.
--
-- Rewards: gold goes straight into the hero's purse (the client cannot make a pile of a given size). An item is made
-- by the game's own loot function: a chicken is put at the hero's feet as the creature that "drops" it, rolled with a
-- raised rarity bonus at the hero's level until something lands; the chicken stays and clucks.

local W = gear.world
local G = {}

local TRACK = 1400          -- world units around the hero that are watched (about 26 tiles)
local FORGET = 2600         -- a live monster farther away than this is not followed any more
local HIT_WINDOW = 8        -- seconds between the hero's last hit on a type and its death
local MAX_TRACKED = 160
local KIND_MONSTER = 3
local BONUS = {[1] = 150, [2] = 350, [3] = 700}     -- loot rarity bonus by item tier (the loot code caps it at 700)

local tracked = {}          -- creature id -> {c, type, name}
local hit_at = {}           -- victim type -> gear.time() of the hero's last hit
local roll_at = {}          -- type -> gear.time() when the loot roll of its death named the hero
local hero_type
local on_kill

-- Called as fn(type_name) for every kill that counts.
function G.on_kill(fn) on_kill = fn end

function G.reset()
    tracked, hit_at, roll_at = {}, {}, {}
end

gear.on('damage', function(hit)
    -- Inside the engine's damage resolution: only a table write.
    if type(hit) == 'table' and hero_type and hit.attacker_type == hero_type then hit_at[hit.victim_type] = gear.time() end
    return nil
end)

local rolling = nil         -- {level, bonus} while a reward item is rolled
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
                tracked[id] = {c = c, type = t, name = c:type_name() or ''}
                n = n + 1
            end
        end
    end
    for id, e in pairs(tracked) do
        local c = e.c
        if not c:exists() or c:is_dead() then
            tracked[id] = nil
            if on_kill and counts(e, now) then on_kill(e.name) end
        else
            local x, y = c:position()
            if not x or (x - hx) ^ 2 + (y - hy) ^ 2 > FORGET ^ 2 then tracked[id] = nil end
        end
    end
end

function G.gold(amount)
    local hero = W.hero()
    if not hero or amount <= 0 then return false end
    return hero:add_gold(amount) and true or false
end

local function ground_ids(x, y)
    local set = {}
    for _, it in ipairs(W.items_near(x, y, 400, {limit = 64}) or {}) do set[it.id] = true end
    return set
end

-- Rolls an item of `tier` (1 good, 2 rare, 3 best) at the hero's feet. `done(ok)` is called when it is over.
function G.drop_item(tier, done)
    if rolling then if done then done(false) end return end
    local hero = W.hero()
    if not hero or not W.can_change() then if done then done(false) end return end
    local level = hero:level() or 1
    local hx, hy, layer = hero:position()
    gear.task(function()
        local ok = false
        local carrier = W.spawn('CHICKEN.GRN', hx + 24, hy + 24, {layer = layer, label = 'bounty'})
        if carrier then
            local before = ground_ids(hx, hy)
            rolling = {level = level, bonus = BONUS[tier] or 150}
            for _ = 1, 40 do
                if not gear.drops.simulate(carrier.id, 1, rolling.bonus, 0) then break end
                gear.wait_until(function() local d, q = gear.drops.simulation_progress() return d >= q end, 2)
                gear.wait(0.05)
                for _, it in ipairs(W.items_near(hx, hy, 400, {limit = 64}) or {}) do
                    if not before[it.id] then ok = true break end
                end
                if ok then break end
            end
            rolling = nil
        end
        if done then done(ok) end
    end)
end

return G
