-- Custom classes: reading and checking the profile files.
--
-- A profile is a JSON file (format 1) in the `classes` folder of this mod or of any installed mod (a mod the Sacred Class
-- Editor exported). `scan()` returns the valid profiles by id and a list of problems; anything invalid is logged and skipped,
-- never an error. Combat art copies come from `arts/*.json` files (see arts.lua) and are referenced by their `id` there.
--
--   {
--     "format": 1, "id": "spellblade", "name": {"en": "Spellblade", "de": "Zauberklinge"}, "description": {"en": "..."},
--     "body": "seraphim",
--     "skills": {"start": [12, 3], "available": [1, 2, 5, ...up to 16]},      (optional: the body's own when missing)
--     "arts": [{"id": 5, "learn": "start", "level": 1}, {"id": 1059, "learn": "rune"}, {"id": 72, "learn": "level", "level": 12}],
--     "motion_remap": {"202": 211}                                          (optional: slot -> slot, for slots the body lacks)
--   }
--
-- `learn`: "start" (known from the moment the class is taken, at `level`, default 1), "level" (granted when the hero reaches
-- `level`), "rune" (not given: only readable). Every art of the profile can also be read from its rune.

local M = {}

-- The installed mods that are switched on (data of a mod that is off is not read).
local function active_mods()
    local out = {}
    for _, m in ipairs(gear.mods.list()) do
        if m.state == 'on' then out[#out + 1] = m end
    end
    return out
end

local BODIES = {seraphim = 1, gladiator = 2, battlemage = 3, darkelf = 4, woodelf = 5, vampiress = 6, dwarf = 8, daemon = 9}
M.BODIES = BODIES
-- the game's own (localized) name of the hero body, the English one if the game has none; looked up when first shown
local function localized_labels(english, types)
    local cache = {}
    return setmetatable({}, {__index = function(_, k)
        local v = cache[k]
        if v == nil then
            v = english[k]
            local t = types[k]
            if t and gear and gear.data and gear.data.object_types then
                local ok, n = pcall(function() return gear.data.object_types:display_name(t) end)
                if ok and type(n) == 'string' and n ~= '' then v = n end
            end
            cache[k] = v or false
        end
        return v or nil
    end})
end

M.BODY_LABEL = localized_labels({seraphim = 'Seraphim', gladiator = 'Gladiator', battlemage = 'Battle Mage', darkelf = 'Dark Elf',
    woodelf = 'Wood Elf', vampiress = 'Vampiress', dwarf = 'Dwarf', daemon = 'Daemon'}, BODIES)

local LEARN = {start = true, level = true, rune = true}

-- The hero type 7 is the Vampiress in her other form: a profile for the Vampiress (6) fits both.
function M.same_body(profile_body_id, hero_type)
    return profile_body_id == hero_type or (hero_type == 7 and profile_body_id == 6)
end

-- The bit of a hero type in an ability's `class_mask` (gear.world.CLASSES has them; the form of the Vampiress shares hers).
local class_bits
function M.class_bit(hero_type)
    if not class_bits then
        class_bits = {}
        for _, c in ipairs(gear.world.CLASSES or {}) do class_bits[c.id] = c.bit end
        class_bits[7] = class_bits[7] or class_bits[6]
    end
    return class_bits[hero_type] or 0
end

-- A text of this mod's own for a name or description. The id comes from `key`, so it is the same in every session and a reload
-- of the files changes the text instead of making a new one (gear.text.add makes a new text on every call).
function M.new_text(key, value)
    local id, err
    if gear.text.key then id, err = gear.text.key('custom-classes.' .. key, value) else id, err = gear.text.add(value) end
    return assert(id, err)
end

-- A text as the profile gives it ({en = ..., de = ...} or a string) for the game's language.
function M.text(value, fallback)
    if type(value) == 'string' then return value end
    if type(value) ~= 'table' then return fallback end
    local lang = tostring(gear.game.config('LANGUAGE') or 'EN'):lower()
    if lang == 'us' then lang = 'en' end
    return value[lang] or value.en or select(2, next(value)) or fallback
end

local function whole(v, lo, hi)
    return type(v) == 'number' and v == math.floor(v) and v >= lo and v <= hi
end

-- Checks one decoded profile; returns the cleaned profile, or nil and the problems.
function M.check(p, where, art_ids)
    local problems = {}
    local function bad(fmt, ...) problems[#problems + 1] = where .. ': ' .. fmt:format(...) end
    if type(p) ~= 'table' then return nil, {where .. ': not a JSON object'} end
    if p.format ~= 1 then bad('format must be 1') end
    if type(p.id) ~= 'string' or not p.id:match('^[%w_%-]+$') then bad('id must be letters, digits, _ and -') end
    if not BODIES[p.body] then bad('body must be one of %s', 'seraphim, gladiator, battlemage, darkelf, woodelf, vampiress, dwarf, daemon') end
    local out = {id = p.id, name = p.name or p.id, description = p.description or '', body = p.body, body_id = BODIES[p.body],
        arts = {}, motion_remap = {}, source = where}
    if p.skills ~= nil then
        local s = p.skills
        if type(s) ~= 'table' or type(s.start) ~= 'table' or #s.start ~= 2 or type(s.available) ~= 'table' or #s.available > 16 then
            bad('skills needs two start skills and at most 16 available')
        else
            for _, v in ipairs(s.start) do if not whole(v, 1, 255) then bad('a start skill must be an id 1..255') end end
            for _, v in ipairs(s.available) do if not whole(v, 1, 255) then bad('an available skill must be an id 1..255') end end
            out.skills = {start = s.start, available = s.available}
        end
    end
    local seen = {}
    for i, a in ipairs(p.arts or {}) do
        local id = a.id
        local learn = a.learn or 'rune'
        if not whole(id, 1, 4999) then
            bad('arts[%d]: id must be an ability id', i)
        elseif seen[id] then
            bad('arts[%d]: %d is listed twice', i, id)
        elseif not LEARN[learn] then
            bad('arts[%d]: learn must be start, level or rune', i)
        elseif learn == 'level' and not whole(a.level, 1, 200) then
            bad('arts[%d]: learn "level" needs a level 1..200', i)
        elseif not gear.data.abilities[id] and not (art_ids and art_ids[id]) then
            bad('arts[%d]: the game has no ability %d', i, id)
        else
            seen[id] = true
            out.arts[#out.arts + 1] = {id = id, learn = learn, level = a.level or 1}
        end
    end
    for k, v in pairs(p.motion_remap or {}) do
        local from, to = tonumber(k), v
        if whole(from, 0, 255) and whole(to, 0, 255) then out.motion_remap[from] = to else bad('motion_remap %s -> %s is not a slot', tostring(k), tostring(v)) end
    end
    if #problems > 0 then return nil, problems end
    return out
end

-- Every profile of every installed mod: {[id] = profile}, problems = {string, ...}
function M.scan(art_ids)
    local profiles, problems = {}, {}
    for _, m in ipairs(active_mods()) do
        local files = gear.mods.files(m.id, 'classes')
        for _, name in ipairs(files or {}) do
            if name:lower():match('%.json$') then
                local where = m.id .. '/classes/' .. name
                local text = gear.mods.read(m.id, 'classes/' .. name)
                local ok, data = pcall(gear.json.decode, text or '')
                if not ok or type(data) ~= 'table' then
                    problems[#problems + 1] = where .. ': not valid JSON'
                else
                    local p, why = M.check(data, where, art_ids)
                    if p then
                        if profiles[p.id] then problems[#problems + 1] = where .. ': id ' .. p.id .. ' is taken by ' .. profiles[p.id].source
                        else profiles[p.id] = p end
                    else
                        for _, w in ipairs(why) do problems[#problems + 1] = w end
                    end
                end
            end
        end
    end
    return profiles, problems
end

return M
