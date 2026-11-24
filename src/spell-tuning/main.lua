-- Spell tuning: the numbers of a spell are one record for every caster in the game. This mod looks at who is casting a spell
-- (Creature:casting, polled about 20 times a second around the hero) and writes the record's numbers for that caster's role just
-- before the effect reads them. Two casters of different roles casting the same spell within the same fraction of a second get
-- the numbers of the one seen last.
local core = require('core')
local W, S = gear.world, gear.settings

local EVERY = 0.05          -- seconds between two looks
local RADIUS, LIMIT = 3500, 300
local original = {}         -- spell id -> field -> value as the game made it
local applied = {}          -- spell id -> role whose numbers the record has now
local casting = {}          -- creature id -> spell id it was seen casting
local t = 0
local stats = {looks = 0, changes = 0}

local function snapshot()
    local abil = gear.data.abilities
    for id = 1, 400 do
        local r = abil[id]
        if r and r.kind == 'spell' and not original[id] then
            local o = {}
            for _, fields in pairs(core.GROUPS) do
                for _, f in ipairs(fields) do
                    local ok, v = pcall(function() return r[f] end)
                    if ok and type(v) == 'number' then o[f] = v end
                end
            end
            original[id] = o
        end
    end
end

local function percents(role)
    return {duration = tonumber(S.get(role .. '_duration', 100)) or 100, strength = tonumber(S.get(role .. '_strength', 100)) or 100,
            damage = tonumber(S.get(role .. '_damage', 100)) or 100}
end

-- Writes the numbers of spell `id` for `role`.
local function set(id, role)
    if applied[id] == role then return end
    local o = original[id]
    if not o then return end
    local plan = core.plan(id, o, percents(role))
    local r = gear.data.abilities[id]
    for f, v in pairs(o) do
        local want = plan[f]
        if want == nil then want = v end
        if r[f] ~= want then pcall(function() r[f] = want end) end
    end
    applied[id] = role
    stats.changes = stats.changes + 1
end

local function role_of(c, hero)
    return core.role({hero = c:is_hero(), played = c.id == hero.id, enemy = c:is_enemy(hero) == true, name = c:type_name()})
end

local function look()
    local hero = W.hero()
    if not hero then return end
    stats.looks = stats.looks + 1
    local hx, hy, layer = hero:position()
    if not hx then return end
    local seen, list = {}, W.creatures_near(hx, hy, RADIUS, {layer = layer, limit = LIMIT})
    list[#list + 1] = hero
    if gear.party and gear.party.heroes then
        for _, h in ipairs(gear.party.heroes() or {}) do list[#list + 1] = h end
    end
    for _, c in ipairs(list) do
        if not seen[c.id] then
            seen[c.id] = true
            local a = c:casting()
            if a and a < 1000 and original[a] then
                -- a hero in the middle of a cast (action 'ability') gets its numbers again: it may have cast the same spell before
                local again = c:is_hero() and c:action() == 'ability'
                if casting[c.id] ~= a or again then
                    casting[c.id] = a
                    set(a, role_of(c, hero))
                end
            else
                casting[c.id] = nil
            end
        end
    end
end

gear.on('frame', gear.guard('frame', function(dt)
    t = t + dt
    if t < EVERY then return end
    t = 0
    if not W.can_change() then return end
    look()
end))

gear.on('settings.changed', function() applied = {}; casting = {} end)
gear.on('savegame.changed', function() applied = {}; casting = {} end)
gear.on('unload', function()
    for id, o in pairs(original) do
        local r = gear.data.abilities[id]
        if r then
            for f, v in pairs(o) do
                if r[f] ~= v then pcall(function() r[f] = v end) end
            end
        end
    end
end)
snapshot()

-- For tests and tools.
gear.on('spell-tuning.stats', function(answer) answer({looks = stats.looks, changes = stats.changes}) end)
-- For the self test: sets settings without the Mods screen ({hero_duration = 50, ...}).
gear.on('spell-tuning.configure', function(values)
    for id, v in pairs(values) do S.set(id, v) end
end)
