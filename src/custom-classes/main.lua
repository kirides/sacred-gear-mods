-- Custom classes: a profile on one of the eight hero bodies (skills, arts from any class, runes, motion remap).
--
-- The save stays a vanilla hero: this mod keeps which profile a hero has per savegame (gear.store.game) and makes the engine
-- behave accordingly while it runs:
--   * skills       the body's Creature.pak record gets the profile's skill lists while that hero is the one played
--   * arts         `creature:learn` gives the starting arts and the arts that come with a level; every art of the profile is readable
--                  from its rune (`rune.usable`), runes of other arts are not
--   * use          `ability.route` runs an art of another class with that class's code; `motion.select` plays a clip of the body's
--                  own (or the profile's remap) where the body has none
-- Engine side and limits: docs/CustomClasses.md of sacred-bild. Everything here is plain Lua on gear.classes.

local profiles_lib = require('profiles')
local arts = require('arts')
local buffs = require('buffs')
local window = require('window')
local ui = gear.ui
local guard = gear.guard
local cfg = gear.config

local function setting(id, fallback)
    local v = gear.settings.get(id)
    if v == nil then return fallback end
    return v
end

local function log(fmt, ...)
    if setting('debug', false) then print(('[custom-classes] ' .. fmt):format(...)) end
end

local function toast(text) if gear.toast then gear.toast.show('Custom classes', text) else print(text) end end

---------------------------------------------------------------------------------------------------------------
-- Data: the profiles and the art copies of every installed mod.
---------------------------------------------------------------------------------------------------------------
local state = {profiles = {}, problems = {}, loaded = false}

local function load_data()
    local art_problems = arts.load()
    for _, p in ipairs(buffs.load_definitions()) do art_problems[#art_problems + 1] = p end
    state.profiles, state.problems = profiles_lib.scan(arts.ids())
    for _, p in ipairs(art_problems) do state.problems[#state.problems + 1] = p end
    for _, p in ipairs(state.problems) do print('[custom-classes] ' .. p) end
    state.loaded = true
    local n = 0
    for _ in pairs(state.profiles) do n = n + 1 end
    local nb = 0
    for _ in pairs(buffs.rules) do nb = nb + 1 end
    print(('[custom-classes] %d class profiles, %d arts with buffs, %d buff definitions'):format(n, nb, (function() local c = 0 for _ in pairs(buffs.defined) do c = c + 1 end return c end)()))
end

---------------------------------------------------------------------------------------------------------------
-- Which hero has which profile: per savegame. Key: the hero's id in single player; in a network game the id of
-- the local player's hero changes with the slot, so the hero's name stands for it.
---------------------------------------------------------------------------------------------------------------
local store = (gear.store.game or gear.store.file)('assignments.json', {heroes = {}, asked = false}, {every = 10})

local function key_of(c)
    if gear.mp.active() then return 'name:' .. tostring(c:name() or '?') end
    return 'id:' .. tostring(c.id)
end

local function assignment(c)
    local r = c and store.data.heroes[key_of(c)]
    if not r then return nil end
    local p = state.profiles[r.profile]
    if not p or p.body_id ~= (select(2, c:class())) and not (p.body_id == 6 and select(2, c:class()) == 7) then return nil end
    return p, r
end

local function profile_of_id(id)
    local c = gear.world.object(id)
    if not c or not c:is_hero() then return nil end
    return assignment(c)
end

-- the art ids a profile lets a hero read: its own list; copies are in it by their ids
local function art_set(p)
    if p.art_set then return p.art_set end
    local set = {}
    for _, a in ipairs(p.arts) do set[a.id] = a end
    p.art_set = set
    return set
end

---------------------------------------------------------------------------------------------------------------
-- Taking and leaving a class.
---------------------------------------------------------------------------------------------------------------
local function grant(c, p, r)
    local level = c:level() or 1
    local changed = false
    for _, a in ipairs(p.arts) do
        if (a.learn == 'start' or (a.learn == 'level' and level >= a.level)) and not r.granted[tostring(a.id)] then
            if not c:ability(a.id) then
                local ok, why = c:learn(a.id, a.learn == 'start' and a.level or 1)
                if not ok then log('learn %d for %s: %s', a.id, tostring(c.id), tostring(why)) end
            end
            -- a chain needs its steps known
            for _, step in ipairs(arts.steps_of(a.id) or {}) do
                if not c:ability(step) then c:learn(step, 1) end
            end
            r.granted[tostring(a.id)] = true
            changed = true
        end
    end
    if changed then store:changed() end
end

local function take(c, p)
    local r = {profile = p.id, granted = {}}
    store.data.heroes[key_of(c)] = r
    store:changed()
    grant(c, p, r)
    state.skills_for = nil
    toast(('%s is now a %s'):format(c:name() or 'The hero', profiles_lib.text(p.name, p.id)))
end

local function leave(c)
    store.data.heroes[key_of(c)] = nil
    store:changed()
    state.skills_for = nil
end

-- The skill lists follow the hero played: they are the body's record, so they are switched when the played hero changes.
local function sync_skills()
    local c = gear.party.available() and gear.party.leader() or gear.world.hero()
    local p = c and assignment(c)
    local want = p and p.skills and p.id or false
    if state.skills_for == want then return end
    state.skills_for = want
    gear.classes.restore_hero_skills()
    if p and p.skills then
        local ok, why = gear.classes.set_hero_skills(p.body_id, p.skills.start, p.skills.available)
        if not ok then print('[custom-classes] skills of ' .. p.id .. ': ' .. tostring(why)) end
    end
end

---------------------------------------------------------------------------------------------------------------
-- The engine's questions.
---------------------------------------------------------------------------------------------------------------
-- Chains (arts.lua): the chain art is a copy of its first step, so the game starts that step; the next steps are ordered here
-- when the hero's action ends, on the enemy nearest to the hero.
local running = {}
local function nearest_foe(h)
    local x, y, layer = h:position()
    local best, bd
    for _, c in ipairs(gear.world.creatures_near(x, y, 900, {layer = layer})) do
        if not c:is_dead() and h:is_enemy(c) and not c:is_hero() then
            local d = h:distance(c)
            if not bd or d < bd then best, bd = c, d end
        end
    end
    return best
end

local function start_chain(id, art)
    if running[id] then return end
    local chain = arts.chains[art]
    if not chain then return end
    running[id] = true
    gear.task(function()
        local ok, err = pcall(function()
            local h = gear.world.object(id)
            local function wait_done()
                gear.wait(0.2)
                local t = 0
                while t < 4 and h:action() ~= nil and (h:action() == 'ability' or h:action() == 'busy') do
                    gear.wait(0.1)
                    t = t + 0.1
                end
            end
            wait_done()
            for i = 2, #chain.steps do
                if not h or h:is_dead() then break end
                gear.wait(chain.delay)
                -- a step still regenerating from earlier use is waited for (the chain's own regeneration is the sum of its steps')
                for _ = 1, 100 do
                    local ab = h:ability(chain.steps[i])
                    if not ab or ab.ready then break end
                    gear.wait(0.2)
                end
                -- the order is refused while the hero is still busy: try a few times
                local done = false
                for _ = 1, 8 do
                    local foe = nearest_foe(h)
                    if not foe then break end
                    if h:order_ability(chain.steps[i], foe) then done = true break end
                    gear.wait(0.3)
                end
                if not done then log('chain %d: step %d not started', art, chain.steps[i]) break end
                wait_done()
            end
        end)
        if not ok then print('[custom-classes] chain: ' .. tostring(err)) end
        running[id] = nil
    end)
end

-- ability.route: a hero of a profile uses an art another class's handler knows: that handler runs it.
local route_cache = {}
gear.on('ability.route', guard('route', function(type_id, art, vanilla, action, id)
    if arts.chains[art] then start_chain(id, art) end
    if buffs.rules[art] then
        local who = gear.world.object(id)
        if who then buffs.used(who, art) end
    end
    local p = profile_of_id(id)
    if not p then return nil end
    local a = gear.data.abilities[art]
    local base = a and a.base or art
    local k = type_id * 100000 + base
    local answer = route_cache[k]
    if answer == nil then
        answer = false
        if gear.classes.tier(base, type_id) == 'B' then
            for _, h in ipairs(gear.classes.homes(base)) do
                if h ~= type_id then answer = h break end
            end
        end
        route_cache[k] = answer
    end
    if answer then log('route %d (base %d) of body %d to class %d', art, base, type_id, answer) end
    return answer or nil
end))

-- ability.hit: the art hit a creature: its buff rules
gear.on('ability.hit', guard('hit', function(attacker, victim, art)
    if buffs.rules[art] then buffs.hit(attacker, victim, art) end
end))

-- motion.select: a body without a clip for a slot plays one of its own.
local FALLBACK = {
    {154, 164}, {144, 153}, {201, 207}, {210, 216}, {219, 225},
}
local function group_of(slot)
    for i, g in ipairs(FALLBACK) do if slot >= g[1] and slot <= g[2] then return i end end
end
local motion_cache = {}
local function substitute(type_id, slot, p)
    local k = type_id * 1000 + slot
    local c = motion_cache[k]
    if c ~= nil then return c or nil end
    local pick = false
    if gear.models.has_motion(type_id, slot) == false then
        local remap = p.motion_remap[slot]
        if remap and gear.models.has_motion(type_id, remap) then
            pick = remap
        elseif setting('auto_remap', true) then
            local g = group_of(slot)
            if g then
                -- same group first (nearest slot), then the other groups in order
                local order = {g}
                for i = 1, #FALLBACK do if i ~= g then order[#order + 1] = i end end
                for _, gi in ipairs(order) do
                    local best, dist = nil, 1000
                    for s = FALLBACK[gi][1], FALLBACK[gi][2] do
                        if gear.models.has_motion(type_id, s) and math.abs(s - slot) < dist then best, dist = s, math.abs(s - slot) end
                    end
                    if best then pick = best break end
                end
            end
        end
    end
    motion_cache[k] = pick
    return pick or nil
end

gear.on('motion.select', guard('motion', function(type_id, slot, id)
    if slot < 140 then return nil end
    local p = profile_of_id(id)
    if not p then return nil end
    local s = substitute(type_id, slot, p)
    if s then log('motion %d -> %d (body %d)', slot, s, type_id) end
    return s
end))

-- rune.usable: the rune of an art of the played hero's profile can be read, any other cannot. Reading is done by the hero played.
gear.on('rune.usable', guard('rune', function(type_id, ability, vanilla)
    local c = gear.party.available() and gear.party.leader() or gear.world.hero()
    local p = c and assignment(c)
    if not p or p.body_id ~= type_id then return nil end
    return art_set(p)[ability] ~= nil
end))

---------------------------------------------------------------------------------------------------------------
-- Frames.
---------------------------------------------------------------------------------------------------------------
local next_grant = 0
gear.on('frame', guard('frame', function(dt)
    next_grant = next_grant - dt
    if next_grant > 0 then return end
    next_grant = cfg.grant_every
    if not state.loaded then return end
    sync_skills()
    for _, c in ipairs(gear.party.available() and gear.party.heroes() or {gear.world.hero()}) do
        local p, r = assignment(c)
        if p then grant(c, p, r) end
    end
end))

local function reset()
    state.skills_for = nil
    route_cache, motion_cache = {}, {}
    gear.classes.restore_hero_skills()
end

gear.on('session.start', guard('session', function()
    reset()
    if not state.loaded then load_data() end
    state.offered = false
end))
gear.on('session.stop', guard('session', reset))
gear.on('party.control', guard('control', function() state.skills_for = nil end))
gear.on('savegame.changed', guard('changed', function() reset() state.offered = false end))
gear.on('unload', function() gear.classes.restore_hero_skills() end)

local win
-- Other mods (and the tests) give a hero a class with events: `gear.emit('custom-classes.take', hero_id, profile_id)` and
-- `gear.emit('custom-classes.leave', hero_id)`.
if gear.events and gear.events.declare then
    pcall(gear.events.declare, 'custom-classes.take', 'Give a hero a class: (hero id, profile id)')
    pcall(gear.events.declare, 'custom-classes.select', 'Select a class in the class window: (profile id)')
    pcall(gear.events.declare, 'custom-classes.window', 'Show (true) or hide (false) the class window')
    pcall(gear.events.declare, 'custom-classes.leave', "Take a hero's class away: (hero id)")
end
gear.on('custom-classes.take', guard('take', function(id, profile_id)
    local c, p = gear.world.object(id), state.profiles[profile_id]
    if c and c:is_hero() and p then take(c, p) end
end))
gear.on('custom-classes.select', guard('select', function(id) if win then win.select(id) end end))
gear.on('custom-classes.window', guard('window', function(open) if win then win.open(open ~= false) end end))
gear.on('custom-classes.leave', guard('leave', function(id)
    local c = gear.world.object(id)
    if c and c:is_hero() then leave(c) end
end))

win = window.new({
    state = state, store = store, setting = setting, take = take, leave = leave, assignment = assignment,
    reload = function() reset() load_data() end,
})

gear.on('draw', guard('draw', function(s)
    if type(s) ~= 'table' or s.mode ~= 'game' or s.exclusive then return end
    -- a new hero: offer the classes once
    if not state.offered and state.loaded and setting('ask_new', true) then
        state.offered = true
        local h = gear.world.hero()
        if h and not store.data.asked and not assignment(h) and (h:level() or 1) <= 1 and next(state.profiles) then
            store.data.asked = true
            store:changed()
            win.open(true)
        end
    end
    win.draw()
end))

gear.keys.on('window', guard('key', function() win.toggle() end))
if ui.menu_item then
    pcall(ui.menu_item, 'classes', 'Class window (custom classes)', function() win.toggle() end)
end

-- Used by tests and other mods: gear.mods.get('custom-classes') cannot expose functions, so the state is global to this mod only.
