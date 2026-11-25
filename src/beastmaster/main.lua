-- Beastmaster: animals that travel with the hero. Allies (wolves, bears, boars) are made by gear.world.spawn with the hero's
-- allegiance, so enemies fight them and they fight enemies; the engine gives such a creature no orders of its own, so this mod does
-- (creature:order_attack / order_move): follow in a half circle behind the hero, attack the enemy nearest to the hero. Their health
-- and damage grow with the hero's level (creature:set_modifiers). Pets (rabbits, crows ...) take the same follow orders but never
-- fight: creature:set_pet draws them larger and keeps them out of the world pick (no click, no hover, no controller aim), and they
-- take no damage. The animals belong to the savegame (gear.store.game): ids and types, checked when they are read again.

local core = require('core')
local species = require('species')
local W, S = gear.world, gear.settings
local cfg = gear.config
local TILE = gear.world.TILE
local guard = gear.guard

local store = (gear.store.game or gear.store.file)('beastmaster.json', {list = {}}, {every = 10})
local followers = store.data.list        -- {{id, type, role}, ...} in the order they were taken along
local window

local function setting(id, fallback)
    local v = S.get(id)
    if v == nil then return fallback end
    return v
end
local function toast(text) if gear.toast then gear.toast.show('Beastmaster', text) else print(text) end end
local function log(...) if cfg.debug then print('beastmaster: ' .. table.concat({...}, ' ')) end end

local function count(role)
    local n = 0
    for _, e in ipairs(followers) do if e.role == role then n = n + 1 end end
    return n
end
local function limit(role) return tonumber(setting(role == 'ally' and 'max_allies' or 'max_pets', 3)) or 3 end

local function object_of(e)
    local c = W.object(e.id)
    if c and c:exists() and c:type() == e.type then return c end
end

-- A pet's look and safety: larger, not pickable, not hurt.
local function dress_pet(c)
    local ok, err = c:set_pet{scale = (tonumber(setting('pet_scale', 130)) or 130) / 100, untargetable = true}
    if not ok then log('set_pet: ' .. tostring(err)) end
    c:set_modifiers{taken = 0}
    return ok, err
end

-- A creature of the same kind (same model name: Silberwolf and Grauwolf are both WOLF.GRN) that the game placed (not one of ours): its level, combat values and health are what a plain create
-- lacks (a creature made by gear.world.spawn is level 1 with 100 health and bites for nothing).
local function donor_of(c, hero)
    local ours = {}
    for _, e in ipairs(followers) do ours[e.id] = true end
    local x, y, layer = hero:position()
    for _, o in ipairs(W.creatures_near(x, y, 6000, {layer = layer, limit = 200})) do
        if o.id ~= c.id and not ours[o.id] and not o:is_hero() and not o:is_dead() and o:type_name() == c:type_name() then return o end
    end
end

-- An ally's strength for the level of the hero it follows. With `creature:copy_stats` (a newer Sacred Gear) the ally first takes the
-- level and combat values of a placed creature of its kind that is near; then health and damage grow with the hero's level.
local function strengthen(c, hero)
    local lvl, st = hero:level() or 1, tonumber(setting('strength', 100)) or 100
    local copied
    if c.copy_stats then
        local donor = donor_of(c, hero)
        if donor then copied = c:copy_stats(donor) end
        if not copied then toast('No ' .. tostring(c:type_name()) .. ' nearby to take its strength from: this ally cannot bite properly yet.') end
    end
    local base = copied and c:max_hp() or 100
    c:set_modifiers{max_hp = math.floor(base * core.health(lvl, st) / 100), damage = core.damage(lvl, st)}
end

local function forget(i)
    table.remove(followers, i)
    store:changed()
end

-- Takes an animal along: spawns it next to the hero with the hero's allegiance. Returns the creature, or nil and why.
local function recruit(sp)
    if not W.can_change() then return nil, 'Only in single player.' end
    local hero = W.hero()
    if not hero or hero:is_dead() then return nil, 'No hero.' end
    if count(sp.role) >= limit(sp.role) then
        return nil, (sp.role == 'ally' and 'Allies' or 'Pets') .. ': the limit is ' .. limit(sp.role) .. ' (Mods screen).'
    end
    local x, y, layer = hero:position()
    local sx, sy = core.spot(x, y, 1, 1, TILE * 2, 0)
    -- Not `like = hero`: that would also copy the hero's level and values onto the animal. Only the allegiance is wanted here.
    local c, err = W.spawn(sp.type, sx, sy, {layer = layer})
    if not c then return nil, err or 'Could not be made.' end
    if sp.role == 'ally' and c.copy_stats then
        -- The combat values copy_stats takes from a placed creature fit that creature's own type only (a Silberwolf copied from a
        -- Grauwolf bites for 1): the ally is made as the type of the donor, which is the same kind (WOLF.GRN) when one is near.
        local donor = donor_of(c, hero)
        if donor and donor:type() ~= c:type() then
            c:remove()
            c, err = W.spawn(donor:type(), sx, sy, {layer = layer})
            if not c then return nil, err or 'Could not be made.' end
        end
    end
    local ok, why = c:copy_allegiance(hero)
    if not ok then c:remove() return nil, why or 'Could not join your side.' end
    if sp.role == 'pet' then dress_pet(c) else strengthen(c, hero) end
    followers[#followers + 1] = {id = c.id, type = c:type(), role = sp.role, key = sp.key}
    store:changed()
    return c
end

local function dismiss(i)
    local e = followers[i]
    if not e then return end
    local c = object_of(e)
    if c then
        if e.role == 'pet' then c:set_pet(nil) end
        c:remove()
    end
    forget(i)
end

local function dismiss_all()
    for i = #followers, 1, -1 do dismiss(i) end
end

---------------------------------------------------------------------------------------------------------------
-- The orders. One think per cfg.think seconds.
---------------------------------------------------------------------------------------------------------------
local state = {}        -- id -> {at = clock of the last order, target = id}
local clock, think_t = 0, 0
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function foes_near(hero, hx, hy, layer, radius)
    local out = {}
    for _, c in ipairs(W.creatures_near(hx, hy, radius, {layer = layer, limit = 40})) do
        if not c:is_hero() and not c:is_dead() and c:is_enemy(hero) == true then
            local x, y = c:position()
            if x then out[#out + 1] = {x = x, y = y, id = c.id, creature = c} end
        end
    end
    return out
end

local function think()
    local hero = W.hero()
    if not hero or hero:is_dead() or #followers == 0 then return end
    local hx, hy, layer = hero:position()
    if not hx then return end
    local follow = (tonumber(setting('follow', 4)) or 4) * TILE
    local engage = (tonumber(setting('engage', 12)) or 12) * TILE
    local foes
    for i = #followers, 1, -1 do
        local e = followers[i]
        local c = object_of(e)
        if not c or c:is_dead() then
            log('gone: ' .. e.id)
            if c then c:remove() end
            forget(i)
            state[e.id] = nil
        end
    end
    local slot = {ally = 0, pet = 0}
    local total = {ally = count('ally'), pet = count('pet')}
    for _, e in ipairs(followers) do
        local c = object_of(e)
        if c then
            slot[e.role] = slot[e.role] + 1
            local s = state[e.id] or {at = -10}
            state[e.id] = s
            local x, y, l = c:position()
            local d = x and dist(x, y, hx, hy) or 0
            if not x or l ~= layer or d > 2600 then
                -- far away or on another layer: join the hero
                local tx, ty = core.spot(hx, hy, slot[e.role], total[e.role], follow, 0)
                c:teleport(tx, ty, layer)
                s.at = clock
            elseif e.role == 'ally' then
                local target = s.target and W.object(s.target)
                if target and (not target:exists() or target:is_dead()) then target = nil; s.target = nil end
                if not target or clock - s.at > 2.5 then
                    foes = foes or foes_near(hero, hx, hy, layer, engage)
                    local f = core.nearest(foes, hx, hy, engage)
                    target = f and f.creature or nil
                end
                if target and d < engage * 1.5 then
                    if s.target ~= target.id or clock - s.at > 2.5 then
                        local ok = c:order_attack(target)
                        if ok then s.target, s.at = target.id, clock end
                    end
                else
                    s.target = nil
                    if d > follow * 1.6 and clock - s.at > 0.8 then
                        local tx, ty = core.spot(hx, hy, slot.ally, total.ally, follow * 0.8, 0)
                        if c:order_move(tx, ty) then s.at = clock end
                    end
                end
            else
                -- a pet only follows
                if d > follow * 1.4 and clock - s.at > 0.8 then
                    local tx, ty = core.spot(hx, hy, slot.pet, total.pet, follow * 0.7, 0)
                    if c:order_move(tx, ty) then s.at = clock end
                end
            end
        end
    end
end

gear.on('frame', guard('frame', function(dt)
    clock = clock + dt
    think_t = think_t + dt
    if think_t < cfg.think then return end
    think_t = 0
    if not W.can_change() then return end
    think()
end))

-- The limits shrank (Mods screen): the newest beyond them go.
gear.on('settings.changed', guard('settings', function(id)
    if id == 'max_allies' or id == 'max_pets' then
        for _, role in ipairs({'ally', 'pet'}) do
            for _, fid in ipairs(core.excess(followers, role, limit(role))) do
                for i, e in ipairs(followers) do
                    if e.id == fid then dismiss(i) break end
                end
            end
        end
    elseif id == 'pet_scale' then
        for _, e in ipairs(followers) do
            local c = e.role == 'pet' and object_of(e)
            if c then dress_pet(c) end
        end
    end
end))

-- A loaded savegame: the animals it holds are the ones the store names (the ids are checked); pets get their look again.
local function after_load()
    followers = store.data.list
    state = {}
    for i = #followers, 1, -1 do
        local e = followers[i]
        local c = object_of(e)
        if not c then forget(i) elseif e.role == 'pet' then dress_pet(c) end
    end
end
gear.on('savegame.changed', guard('savegame.changed', function() after_load() end))
gear.on('session.start', guard('session.start', function() after_load() end))

gear.keys.on('window', guard('key', function() if window then window.toggle() end end))

-- For the self test and tools.
gear.on('beastmaster.state', function(answer)
    answer({followers = followers, ally = count('ally'), pet = count('pet')})
end)
gear.on('beastmaster.recruit', function(key, answer)
    for _, sp in ipairs(species) do
        if sp.key == key then
            local c, err = recruit(sp)
            return answer and answer(c and c.id or nil, err)
        end
    end
    if answer then answer(nil, 'unknown animal') end
end)
gear.on('beastmaster.dismiss_all', dismiss_all)
gear.on('beastmaster.window', function(on) window.open(on) end)

window = require('window').new({species = species, count = count, limit = limit, recruit = recruit, dismiss = dismiss,
    dismiss_all = dismiss_all, followers = function() return followers end, object_of = object_of, toast = toast})
gear.on('draw', guard('draw', function() window.draw() end))
