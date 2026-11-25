-- Beastmaster: animals that travel with the hero, every animal type of the game (species.lua).
--
-- Allies are made by gear.world.spawn, join the hero's side with creature:copy_allegiance (so enemies fight them and they fight enemies)
-- and get the level of the hero you play (creature:set_level: the engine derives health and damage from the type and the level, as for
-- the creatures it places, so an ally grows stronger as you do). The engine gives such a creature no orders of its own, so this mod does
-- (creature:order_attack / order_move): follow in a half circle behind the hero, attack the enemy nearest to the hero. An ally is drawn at its
-- species' base size times a growth factor that steps up every 18 levels until level 216 (creature:set_pet with a scale).
-- Pets take the same follow orders but never fight: creature:set_pet draws them larger and keeps them out of the world pick (no click, no
-- hover, no controller aim), and they take no damage. Orders (window): each animal is Aggressive, Defensive, Passive or told to Wait here,
-- as a companion can be; one that waits stays where it stands (never called back to the hero) until "To me" brings it. The animals belong to the savegame (gear.store.game): ids and types, checked when they
-- are read again. The base size of a species is changed in the window and kept for all games (gear.store.file).

local core = require('core')
local species = require('species')
local W, S = gear.world, gear.settings
local cfg = gear.config
local TILE = gear.world.TILE
local guard = gear.guard

local store = (gear.store.game or gear.store.file)('beastmaster.json', {list = {}}, {every = 10})
local prefs = gear.store.file('beastmaster_prefs.json', {scales = {}}, {every = 10})
local followers = store.data.list        -- {{id, type, role}, ...} in the order they were taken along
local window

local by_type = {}
for _, sp in ipairs(species) do by_type[sp.type] = sp end

local function setting(id, fallback)
    local v = S.get(id)
    if v == nil then return fallback end
    return v
end
local function toast(text) if gear.toast then gear.toast.show('Beastmaster', text) else print(text) end end
local function log(...) if cfg.debug then print('beastmaster: ' .. table.concat({...}, ' ')) end end

-- The base model scale of a species: the player's own (window), else the species' default.
local function base_scale(type_id)
    local sp = by_type[type_id]
    local own = prefs.data.scales[tostring(type_id)]
    return own or (sp and sp.scale) or 1
end
local function set_base_scale(type_id, value)
    prefs.data.scales[tostring(type_id)] = math.min(2, math.max(0.1, math.floor(value * 100 + 0.5) / 100))
    prefs:changed()
end

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

local function hero_level()
    local hero = W.hero()
    return hero and hero:level() or 1
end

-- A pet's look and safety: larger, not pickable, not hurt.
local function dress_pet(c)
    local scale = core.pet_scale(base_scale(c:type()), tonumber(setting('pet_scale', 130)) or 130)
    local ok, err = c:set_pet{scale = scale, untargetable = true}
    if not ok then log('set_pet: ' .. tostring(err)) end
    c:set_modifiers{taken = 0}
    return ok, err
end

-- An ally's strength and size for the hero's level: its level is a share of the hero's (the engine derives health and damage from the
-- type and the level), its size the species' base size times the growth of the stage; the damage setting scales its bites on top.
local function dress_ally(c, e, level)
    local want = core.ally_level(level, tonumber(setting('ally_level', 100)) or 100)
    if e.level ~= want then
        local ok, err = c:set_level(want)
        if ok then e.level = want else log('set_level: ' .. tostring(err)) end
    end
    local damage = (tonumber(setting('strength', 100)) or 100) / 100
    if e.damage ~= damage then
        c:set_modifiers(damage ~= 1 and {damage = damage} or nil)
        e.damage = damage
    end
    local scale = core.ally_scale(base_scale(c:type()), level, tonumber(setting('grow_from', 75)) or 75, tonumber(setting('grow_to', 125)) or 125)
    if e.scale ~= scale then
        local ok = c:set_pet{scale = scale}
        if ok then e.scale = scale end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Party buffs. The companions mod tells (event 'companions.buff') which buff it shares with the heroes; the animals get it too: an ally all of
-- it (damage, attack speed, resistances ...), a pet the speed factor only. 'companions.buff_end' ends it. A buff that is running when an animal
-- is taken along is given to it then.
---------------------------------------------------------------------------------------------------------------
local active = {}       -- key -> {def, strength, seconds, since}
local function clock_now() return gear.time() end

local function buff_for(role, def)
    if role == 'ally' then return def end
    -- a pet: how fast it walks (the movement speed part, past the engine's cap), nothing else
    local move = def.speeds and def.speeds.move_speed
    local factor = def.speed_factors and def.speed_factors.move_speed
    if not (move or factor) then return nil end
    return {id = def.id, name = def.name, overlay = def.overlay, speeds = move and {move_speed = move} or nil,
        speed_factors = factor and {move_speed = factor} or nil}
end

local function give(c, role, key, b)
    local pct = tonumber(setting(role == 'ally' and 'buff_allies' or 'buff_pets', 100)) or 100
    local def = buff_for(role, b.def)
    if not def or pct <= 0 then return end
    local left = b.seconds and b.seconds > 0 and math.max(1, b.seconds - (clock_now() - b.since)) or 0
    gear.buffs.apply(c, def, {key = 'beastmaster:' .. key, strength = (b.strength or 1) * pct / 100, seconds = left})
end

-- (a buff with a time runs out by itself: forget it too)
local function expire_buffs()
    local now = clock_now()
    for key, b in pairs(active) do
        if b.seconds and b.seconds > 0 and now - b.since > b.seconds then active[key] = nil end
    end
end

local function forget(i)
    table.remove(followers, i)
    store:changed()
end

-- Takes an animal along: spawns it next to the hero on the hero's side. Returns the creature, or nil and why.
local function recruit(type_id, role)
    if not W.can_change() then return nil, 'Only in single player.' end
    local hero = W.hero()
    if not hero or hero:is_dead() then return nil, 'No hero.' end
    if role ~= 'pet' then role = 'ally' end
    if count(role) >= limit(role) then
        return nil, (role == 'ally' and 'Allies' or 'Pets') .. ': the limit is ' .. limit(role) .. ' (Mods screen).'
    end
    local x, y, layer = hero:position()
    local sx, sy = core.spot(x, y, 1, 1, TILE * 2, 0)
    -- Not `like = hero`: that would also copy the hero's level and values onto the animal. Only the allegiance is wanted here.
    local c, err = W.spawn(type_id, sx, sy, {layer = layer})
    if not c then return nil, err or 'Could not be made.' end
    local ok, why = c:copy_allegiance(hero)
    if not ok then c:remove() return nil, why or 'Could not join your side.' end
    local e = {id = c.id, type = c:type(), role = role}
    followers[#followers + 1] = e
    if setting('party_buffs', true) then
        for key, bf in pairs(active) do give(c, role, key, bf) end
    end
    if role == 'pet' then dress_pet(c) else dress_ally(c, e, hero:level() or 1) end
    store:changed()
    return c
end

local function dismiss(i)
    local e = followers[i]
    if not e then return end
    local c = object_of(e)
    if c then
        c:set_pet(nil)
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
local clock, think_t, dress_t = 0, 0, 0
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

-- The order that counts for an animal (its own, else the default of the Mods screen).
local function order_for(e)
    return core.order_of(e.role, e.order, setting('behaviour', 'aggressive'))
end

-- Pace: an animal keeps up with the hero. A creature ordered to move walks (the hero runs, about 2.5 times as fast), so when it is
-- far behind the order is followed by creature:gait(2), the run it uses when it chases an enemy; its movement speed is lifted to the
-- hero's with a buff of ours ('speeds' are added past the engine's cap) when it is slower. `e.pace` is what the buff adds now, so the
-- animal's own speed (with other buffs) is what the speed reads without it.
-- Ordered to a spot: running when far from the hero (Gear's creature:gait, 2 = run), else walking.
local function go(c, x, y, run)
    if not c:order_move(x, y) then return false end
    if run and c.gait and setting('match_speed', true) then c:gait(2) end
    return true
end

local pace_off = false     -- (the self test switches it off to measure the animals' own speed)
local function pace(c, e, hero, d, follow, fighting)
    if not (gear.buffs and gear.buffs.speeds and setting('match_speed', true)) or pace_off then return end
    local mine, theirs = gear.buffs.speeds(c), gear.buffs.speeds(hero)
    if not (mine and theirs and mine.move_speed and theirs.move_speed) then return end
    local base = mine.move_speed - (e.pace or 0)
    local want = theirs.move_speed
    local delta = fighting and 0 or math.max(0, math.floor(math.min(600, want) - base + 0.5))   -- never slower than it is (a shared speed buff stays)
    if math.abs(delta - (e.pace or 0)) < 6 then return end
    e.pace = delta
    gear.buffs.apply(c, {id = 'beastmaster_pace', name = 'Pace', speeds = {move_speed = delta}}, {key = 'beastmaster:pace', strength = 1, seconds = 0})
end

local function think()
    local hero = W.hero()
    if not hero or hero:is_dead() or #followers == 0 then return end
    local hx, hy, layer = hero:position()
    if not hx then return end
    local follow = (tonumber(setting('follow', 4)) or 4) * TILE
    local engage_tiles = tonumber(setting('engage', 12)) or 12
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
            local order = order_for(e)
            local x, y, l = c:position()
            local d = x and dist(x, y, hx, hy) or 0
            if x then pace(c, e, hero, d, follow, s.target ~= nil) end
            if order == 'hold' then
                -- waiting: stays where it stands (also when the hero leaves for another layer; "To me" calls it). An ally fights what
                -- comes near that spot and goes back to it afterwards.
                if x then
                    s.hold = s.hold or {x = x, y = y, layer = l}
                    local range = e.role == 'ally' and core.engage_range('hold', engage_tiles, TILE) or 0
                    local target = s.target and W.object(s.target)
                    if target and (not target:exists() or target:is_dead()) then target = nil; s.target = nil end
                    if range > 0 and (not target or clock - s.at > 2.5) then
                        local f = core.nearest(foes_near(hero, s.hold.x, s.hold.y, s.hold.layer or l, range * 1.5), s.hold.x, s.hold.y, range)
                        target = f and f.creature or nil
                    end
                    if target and range > 0 then
                        if s.target ~= target.id or clock - s.at > 2.5 then
                            if c:order_attack(target) then s.target, s.at = target.id, clock end
                        end
                    else
                        s.target = nil
                        if dist(x, y, s.hold.x, s.hold.y) > TILE * 1.5 and clock - s.at > 1.5 and (c:action() or 'idle') == 'idle' then
                            if c:order_move(s.hold.x, s.hold.y) then s.at = clock end
                        end
                    end
                end
            else
                s.hold = nil
                local range = e.role == 'ally' and core.engage_range(order, engage_tiles, TILE) or 0
                if not x or l ~= layer or d > 2600 then
                    -- far away or on another layer: join the hero
                    local tx, ty = core.spot(hx, hy, slot[e.role], total[e.role], follow, 0)
                    c:teleport(tx, ty, layer)
                    s.at = clock
                    s.target = nil
                elseif range > 0 then
                    local target = s.target and W.object(s.target)
                    if target and (not target:exists() or target:is_dead()) then target = nil; s.target = nil end
                    if not target or clock - s.at > 2.5 then
                        local f = core.nearest(foes_near(hero, hx, hy, layer, range), hx, hy, range)
                        target = f and f.creature or nil
                    end
                    if target and d < range * 1.5 then
                        if s.target ~= target.id or clock - s.at > 2.5 then
                            local ok = c:order_attack(target)
                            if ok then s.target, s.at = target.id, clock end
                        end
                    else
                        s.target = nil
                        if d > follow * 1.6 and clock - s.at > 0.8 then
                            local tx, ty = core.spot(hx, hy, slot.ally, total.ally, follow * 0.8, 0)
                            if go(c, tx, ty, d > follow * 2) then s.at = clock end
                        end
                    end
                else
                    -- a pet, or an ally told to stay passive: only follows
                    s.target = nil
                    local ally = e.role == 'ally'
                    if d > follow * (ally and 1.6 or 1.4) and clock - s.at > 0.8 then
                        local tx, ty = core.spot(hx, hy, slot[e.role], total[e.role], follow * (ally and 0.8 or 0.7), 0)
                        if go(c, tx, ty, d > follow * 2) then s.at = clock end
                    end
                end
            end
        end
    end
end

-- Sets the order of animal `i` (nil: the default of the Mods screen). It lets go of its target and, when it waits, takes its spot afresh.
local function set_order(i, order)
    local e = followers[i]
    if not e then return end
    if order ~= nil and not core.ORDER_LABEL[order] then return end
    e.order = order
    local s = state[e.id]
    if s then s.hold, s.target = nil, nil end
    store:changed()
    local c = object_of(e)
    if c and c.order_stop and order_for(e) ~= 'aggressive' and order_for(e) ~= 'defensive' then c:order_stop() end
end
local function set_order_all(order)
    for i = 1, #followers do set_order(i, order) end
end

-- "To me": a stuck or waiting animal joins the hero where they stand (and goes on waiting there, when it waits).
local function bring(i)
    local e = followers[i]
    local c = e and object_of(e)
    local hero = W.hero()
    if not c or not hero then return false end
    local hx, hy, layer = hero:position()
    if not hx then return false end
    local slot = 0
    for j = 1, i do if followers[j].role == e.role then slot = slot + 1 end end
    local tx, ty = core.spot(hx, hy, slot, count(e.role), (tonumber(setting('follow', 4)) or 4) * TILE, 0)
    c:teleport(tx, ty, layer)
    local s = state[e.id]
    if s then s.hold, s.target = nil, nil end
    return true
end
local function bring_all()
    for i = 1, #followers do bring(i) end
end

-- The allies' level, damage and size follow the hero (looked at every two seconds: a level up, a setting changed).
local function redress()
    local level = hero_level()
    for _, e in ipairs(followers) do
        local c = e.role == 'ally' and object_of(e)
        if c then dress_ally(c, e, level) end
    end
end

gear.on('frame', guard('frame', function(dt)
    clock = clock + dt
    think_t = think_t + dt
    dress_t = dress_t + dt
    if think_t < cfg.think then return end
    think_t = 0
    if not W.can_change() then return end
    think()
    if dress_t >= 2 then dress_t = 0; redress(); expire_buffs() end
end))

gear.on('companions.buff', guard('companions.buff', function(ev)
    if not (gear.buffs and setting('party_buffs', true) and type(ev) == 'table' and ev.key and type(ev.def) == 'table') then return end
    local b = {def = ev.def, strength = ev.strength or 1, seconds = ev.seconds or 0, since = clock_now()}
    active[ev.key] = b
    for _, e in ipairs(followers) do
        local c = object_of(e)
        if c then give(c, e.role, ev.key, b) end
    end
end))
gear.on('companions.buff_end', guard('companions.buff_end', function(key)
    if not (gear.buffs and key) then return end
    active[key] = nil
    for _, e in ipairs(followers) do gear.buffs.remove(e.id, 'beastmaster:' .. key) end
end))
-- The limits shrank (Mods screen): the newest beyond them go. A size or level setting changed: every animal is dressed again.
gear.on('settings.changed', guard('settings', function(id)
    if id == 'max_allies' or id == 'max_pets' then
        for _, role in ipairs({'ally', 'pet'}) do
            for _, fid in ipairs(core.excess(followers, role, limit(role))) do
                for i, e in ipairs(followers) do
                    if e.id == fid then dismiss(i) break end
                end
            end
        end
    else
        for _, e in ipairs(followers) do
            e.level, e.damage, e.scale = nil, nil, nil
            local c = e.role == 'pet' and object_of(e)
            if c then dress_pet(c) end
        end
        redress()
    end
end))

-- A loaded savegame: the animals it holds are the ones the store names (the ids are checked); they get their look again.
local function after_load()
    followers = store.data.list
    state = {}
    active = {}
    for i = #followers, 1, -1 do
        local e = followers[i]
        local c = object_of(e)
        if not c then
            forget(i)
        else
            e.level, e.damage, e.scale, e.pace = nil, nil, nil, nil
            if e.role == 'pet' then dress_pet(c) end
        end
    end
    redress()
end
gear.on('savegame.changed', guard('savegame.changed', function() after_load() end))
gear.on('session.start', guard('session.start', function() after_load() end))

gear.keys.on('window', guard('key', function() if window then window.toggle() end end))

-- For the self test and tools.
gear.on('beastmaster.state', function(answer)
    local list = {}
    for _, e in ipairs(followers) do
        local c = object_of(e)
        list[#list + 1] = {id = e.id, type = e.type, role = e.role, order = order_for(e), level = c and c:level() or nil, scale = e.scale}
    end
    answer({followers = list, ally = count('ally'), pet = count('pet')})
end)
gear.on('beastmaster.recruit', function(type_id, role, answer)
    local c, err = recruit(type_id, role)
    if answer then answer(c and c.id or nil, err) end
end)
gear.on('beastmaster.dismiss_all', dismiss_all)
gear.on('beastmaster.pace', function(on)
    pace_off = on == false
    if pace_off then for _, e in ipairs(followers) do gear.buffs.remove(e.id, 'beastmaster:pace'); e.pace = nil end end
end)
gear.on('beastmaster.order', function(i, order) set_order(i, order) end)
gear.on('beastmaster.order_all', function(order) set_order_all(order) end)
gear.on('beastmaster.bring', function(i) bring(i) end)
gear.on('beastmaster.bring_all', bring_all)
gear.on('beastmaster.filter', function(text, answer) answer(window.set_filter(text)) end)
gear.on('beastmaster.osk', function(on) window.set_osk(on) end)
gear.on('beastmaster.window', function(on) window.open(on) end)
gear.on('beastmaster.dropdown', function(id) window.open_dropdown(id) end)

window = require('window').new({species = species, count = count, limit = limit, recruit = recruit, dismiss = dismiss,
    dismiss_all = dismiss_all, followers = function() return followers end, object_of = object_of, toast = toast,
    base_scale = base_scale, set_base_scale = set_base_scale, order_of = order_for, set_order = set_order,
    set_order_all = set_order_all, bring = bring, bring_all = bring_all})
gear.on('draw', guard('draw', function() window.draw() end))
