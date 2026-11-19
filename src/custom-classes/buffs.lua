-- Custom classes: buffs of art copies and chains (gear.buffs of sacred-bild).
--
-- Buff definitions: `buffs/<name>.json` in this mod or any installed mod that is on (format 1):
--   { "format": 1, "id": "venom", "name": {"en": "Venom"}, "description": {"en": "..."}, "icon": "GUI_MOVE_KICK.TGA",
--     "stats": {"resist_poison": -30}, "factors": {"speed_factor": 0.9}, "overlay": "flame", "seconds": 8, "debuff": true }
-- They are registered with gear.buffs.define (`stats`, `factors`, `overlay` as gear.buffs knows them) under the id `custom-classes:<id>`.
--
-- An art file (arts/*.json, format 2) lists `buffs`: rules for when the art is used or hits:
--   { "when": "use" | "hit", "buff": "venom" | "other_mod:name" | { inline definition },
--     "strength": 1 | {"base": 1, "per_level": 0.02}, "seconds": 8 | {"base": 6, "per_level": 0.5}, "chance": 100,
--     "radius": 0 }
-- `use`: the hero who used the art gets it (with `radius` > 0 also the party heroes within that many tiles); `hit`: every creature the art hits.
-- strength and seconds are `base + per_level * art level` (the art's level and bonus of the hero).

local M = {}
M.rules = {}        -- art id -> list of rules
M.defined = {}      -- 'custom-classes:id' -> true

local function whole_or(v) return type(v) == 'number' end

local function text(value, fallback)
    if type(value) == 'string' then return value end
    if type(value) ~= 'table' then return fallback end
    local lang = tostring(gear.game.config('LANGUAGE') or 'EN'):lower()
    if lang == 'us' then lang = 'en' end
    return value[lang] or value.en or select(2, next(value)) or fallback
end

-- {base, per_level} from a number or a table.
local function curve(v, default)
    if v == nil then return {base = default, per_level = 0} end
    if type(v) == 'number' then return {base = v, per_level = 0} end
    if type(v) == 'table' and whole_or(v.base) and (v.per_level == nil or whole_or(v.per_level)) then
        return {base = v.base, per_level = v.per_level or 0}
    end
    return nil
end
M.curve = curve

local function active_mods()
    local out = {}
    for _, m in ipairs(gear.mods.list()) do
        if m.state == 'on' then out[#out + 1] = m end
    end
    return out
end

-- Reads the buff files and registers them; returns the problems.
function M.load_definitions()
    local problems = {}
    if not gear.buffs then return {'gear.buffs is missing: update Sacred Gear (buffs are not available)'} end
    for _, m in ipairs(active_mods()) do
        for _, name in ipairs(gear.mods.files(m.id, 'buffs') or {}) do
            if name:lower():match('%.json$') then
                local where = m.id .. '/buffs/' .. name
                local ok, d = pcall(gear.json.decode, gear.mods.read(m.id, 'buffs/' .. name) or '')
                if not ok or type(d) ~= 'table' or d.format ~= 1 or type(d.id) ~= 'string' or not d.id:match('^[%w_%-]+$') then
                    problems[#problems + 1] = where .. ': not a buff file of format 1 with an id of letters, digits, _ and -'
                else
                    local def = {id = d.id, name = text(d.name, d.id), description = text(d.description, nil), icon = d.icon,
                        stats = d.stats, factors = d.factors, overlay = d.overlay, seconds = d.seconds, debuff = d.debuff}
                    local done, err = pcall(gear.buffs.define, def)
                    if done then M.defined['custom-classes:' .. d.id] = true else problems[#problems + 1] = where .. ': ' .. tostring(err) end
                end
            end
        end
    end
    return problems
end

-- Checks the `buffs` list of an art file; returns the cleaned rules or nil and the problems.
function M.check(list, where)
    local rules, problems = {}, {}
    local function bad(fmt, ...) problems[#problems + 1] = where .. ': ' .. fmt:format(...) end
    if list == nil then return rules, problems end
    if type(list) ~= 'table' then return nil, {where .. ': buffs must be a list'} end
    for i, r in ipairs(list) do
        local rule = {}
        if type(r) ~= 'table' then bad('buffs[%d] is not an object', i)
        elseif r.when ~= 'use' and r.when ~= 'hit' then bad('buffs[%d]: when must be use or hit', i)
        elseif type(r.buff) ~= 'string' and type(r.buff) ~= 'table' then bad('buffs[%d]: buff must be a buff id or an inline definition', i)
        else
            rule.when, rule.buff = r.when, r.buff
            rule.strength, rule.seconds = curve(r.strength, 1), curve(r.seconds, nil)
            if not rule.strength then bad('buffs[%d]: strength must be a number or {base, per_level}', i) end
            if r.seconds ~= nil and not rule.seconds then bad('buffs[%d]: seconds must be a number or {base, per_level}', i) end
            if r.seconds == nil then rule.seconds = nil end
            rule.chance = r.chance == nil and 100 or r.chance
            if not whole_or(rule.chance) or rule.chance < 0 or rule.chance > 100 then bad('buffs[%d]: chance is 0..100', i) end
            rule.radius = r.radius or 0
            if not whole_or(rule.radius) or rule.radius < 0 or rule.radius > 60 then bad('buffs[%d]: radius is 0..60 tiles', i) end
            rule.index = i
            rules[#rules + 1] = rule
        end
    end
    if #problems > 0 then return nil, problems end
    return rules, problems
end

local last_use = {}

local function resolve(rule, art)
    local b = rule.buff
    if type(b) == 'table' then
        local def = {}
        for k, v in pairs(b) do def[k] = v end
        def.id = def.id or ('art' .. art .. '_' .. rule.index)
        return def
    end
    if b:find(':', 1, true) then return b end
    return 'custom-classes:' .. b
end

local function level_of(c, art)
    local a = c:ability(art)
    return a and ((a.level or 0) + (a.bonus or 0)) or 1
end

local function give(rule, art, caster, target)
    if rule.chance < 100 and math.random() * 100 >= rule.chance then return end
    local level = level_of(caster, art)
    local strength = rule.strength.base + rule.strength.per_level * level
    local opts = {strength = strength, source = caster, ability = art, key = ('cc:%d:%d'):format(art, rule.index)}
    if rule.seconds then opts.seconds = rule.seconds.base + rule.seconds.per_level * level end
    local ok, err = gear.buffs.apply(target, resolve(rule, art), opts)
    if not ok then print('[custom-classes] buff ' .. tostring(type(rule.buff) == 'string' and rule.buff or rule.index) .. ': ' .. tostring(err)) end
    return ok
end

-- The art started (called for every sign that it is in flight: once per use).
function M.used(caster, art)
    local rules = M.rules[art]
    if not rules then return end
    local key = caster.id .. ':' .. art
    local now = gear.time()
    local again = last_use[key] and now - last_use[key] < 0.8
    last_use[key] = now
    if again then return end
    for _, rule in ipairs(rules) do
        if rule.when == 'use' then
            give(rule, art, caster, caster)
            if rule.radius > 0 and gear.party.available() then
                local cx, cy = caster:position()
                for _, h in ipairs(gear.party.heroes()) do
                    if h ~= caster and not h:is_dead() then
                        local x, y = h:position()
                        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / gear.world.TILE
                        if d <= rule.radius then give(rule, art, caster, h) end
                    end
                end
            end
        end
    end
end

-- A hit of the art on `victim`.
function M.hit(attacker, victim, art)
    local rules = M.rules[art]
    if not rules then return end
    for _, rule in ipairs(rules) do
        if rule.when == 'hit' then give(rule, art, attacker, victim) end
    end
end

return M
