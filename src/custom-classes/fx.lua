-- Custom classes: effect rules of art copies (gear.pfx of sacred-bild).
--
-- An art file (arts/*.json, format 3) lists `fx`: what the art's particle effects look like, by effect type and cast level:
--   { "fx": [792], "min_level": 10, "max_level": 20,                 (all optional: no `fx` = every effect, no level = any)
--     "hue": -120, "colorize": "#FF2020", "multiply": "#80FFFFFF", "alpha": 1, "speed": 0.5,
--     "textures": {"PARTICLE_GLOW01.TGA": "PARTICLE_SMOKE01.TGA"} }
-- Each rule becomes a gear.pfx variant (an id of this mod's block, 200000 + art_id * 64 + rule number - 1) and a gear.pfx rule that picks it for
-- the art's effects. The first rule of the list that matches an effect and a level wins (rules have falling priority). Only copies have effects: a
-- chain makes the effects of its steps.
--
-- Which effects are "the art's": the effects made with the art in flight (ctx.ability is the art's id) always; but some effects (a spell's cloud
-- or projectile, the effects of a hit) are made by the engine with no caster and no ability. For those a rule that NAMES effect types also takes
-- the effects of those types that appear within WINDOW seconds after the art was used by a hero (main.lua tells it from the `ability.route` question the engine asks); another hero's creature-less effect of the same type in that time gets the look too. A rule without types does not do that. The look is local (other players of a network game see the engine's effect). The editor makes these
-- files and shows what the rules look like (Effects screen of the Sacred Class Editor).

local M = {}
M.MAX_RULES = 64
M.TYPE_MIN, M.TYPE_MAX = 0x300, 0x49D
local BLOCK_BASE = 200000
M.WINDOW = 4.0

local watched = {}      -- art id -> true while the art has rules
local used_at = {}      -- art id -> gear.time() of the last time a hero had it in flight

local handles = {}      -- list of {rule = handle, id = variant id}

local function whole(v, lo, hi) return type(v) == 'number' and v == math.floor(v) and v >= lo and v <= hi end

local function hex(s, digits)
    if type(s) ~= 'string' then return nil end
    local t = s:match('^%s*#?(%x+)%s*$') or s:match('^%s*0[xX](%x+)%s*$')
    if not t or #t ~= digits then return nil end
    return tonumber(t, 16)
end

local function number_of(v, lo, hi) return type(v) == 'number' and v >= lo and v <= hi end

-- Checks the `fx` list of an art file; returns nil, or the first problem (without the file prefix).
function M.check(list)
    if list == nil then return nil end
    if type(list) ~= 'table' then return 'fx must be a list' end
    if #list > M.MAX_RULES then return ('fx has more than %d rules'):format(M.MAX_RULES) end
    for i, r in ipairs(list) do
        local at = ('fx[%d]'):format(i)
        if type(r) ~= 'table' then return at .. ' is not an object' end
        if r.fx ~= nil then
            if type(r.fx) ~= 'table' then return at .. '.fx must be a list of effect types' end
            for _, t in ipairs(r.fx) do
                if not whole(t, M.TYPE_MIN, M.TYPE_MAX) then
                    return ('%s.fx: %s is not an effect type (0x%X..0x%X)'):format(at, tostring(t), M.TYPE_MIN, M.TYPE_MAX)
                end
            end
        end
        for _, k in ipairs({'min_level', 'max_level'}) do
            if r[k] ~= nil and not whole(r[k], 1, 200) then return ('%s.%s must be a whole number 1..200'):format(at, k) end
        end
        if r.min_level and r.max_level and r.min_level > r.max_level then
            return ('%s: min_level %d is above max_level %d'):format(at, r.min_level, r.max_level)
        end
        for _, k in ipairs({{'hue', -360, 360}, {'alpha', 0, 4}, {'speed', 0.01, 100}}) do
            if r[k[1]] ~= nil and not number_of(r[k[1]], k[2], k[3]) then
                return ('%s.%s must be a number %s..%s'):format(at, k[1], tostring(k[2]), tostring(k[3]))
            end
        end
        if r.colorize ~= nil and not hex(r.colorize, 6) then return at .. '.colorize must be a colour text like "#RRGGBB"' end
        if r.multiply ~= nil and not hex(r.multiply, 8) then return at .. '.multiply must be a colour text like "#AARRGGBB"' end
        if r.textures ~= nil then
            if type(r.textures) ~= 'table' then return at .. '.textures must be an object (texture name to texture name)' end
            for from, to in pairs(r.textures) do
                if type(to) ~= 'string' then return ('%s.textures: %s must map to a texture name'):format(at, tostring(from)) end
            end
        end
    end
    return nil
end

-- The variant definition of a rule (gear.pfx.define).
function M.definition(id, r)
    local d = {id = id}
    if r.hue ~= nil then d.hue = r.hue end
    if r.colorize ~= nil then d.colorize = hex(r.colorize, 6) end
    if r.multiply ~= nil then d.multiply = hex(r.multiply, 8) end
    if r.alpha ~= nil then d.alpha = r.alpha end
    if r.speed ~= nil then d.speed = r.speed end
    if r.textures ~= nil and next(r.textures) ~= nil then d.textures = r.textures end
    return d
end

-- The variant id of rule `index` (1..64) of an art.
function M.variant_id(art_id, index) return BLOCK_BASE + art_id * M.MAX_RULES + (index - 1) end

-- Notes that a hero has an art in flight (main.lua calls it from its ability.route handler, which the engine asks for every use of an art);
-- only arts that have rules are noted.
function M.used(art_id)
    if watched[art_id] then used_at[art_id] = gear.time() end
end

-- Whether a creature-less effect belongs to a recent use of the art.
function M.recent(art_id)
    local t = used_at[art_id]
    return t ~= nil and gear.time() - t <= M.WINDOW
end

-- The decision of a rule for an effect (gear.pfx select): the variant id, or nil.
function M.select(art_id, id, ctx, by_window)
    if ctx.ability == art_id then return id end
    if by_window and ctx.ability == nil and ctx.creature == nil and M.recent(art_id) then return id end
    return nil
end

-- Removes every rule and variant this mod made.
function M.clear()
    if gear.pfx then
        for _, h in ipairs(handles) do
            pcall(gear.pfx.remove_rule, h.rule)
            pcall(gear.pfx.undefine, h.id)
        end
    end
    handles = {}
    for k in pairs(watched) do watched[k] = nil end
    for k in pairs(used_at) do used_at[k] = nil end
end

-- Defines the variants and rules of an art (a checked list). Returns the number of rules made and the problems.
function M.apply(art_id, list, where)
    local made, problems = 0, {}
    if not gear.pfx then return 0, {where .. ': this version of Sacred Gear has no gear.pfx (skill effects), the fx rules are not used'} end
    watched[art_id] = true
    for i, r in ipairs(list) do
        local id = M.variant_id(art_id, i)
        local ok, err = pcall(gear.pfx.define, M.definition(id, r))
        if not ok then
            problems[#problems + 1] = ('%s: fx[%d]: %s'):format(where, i, tostring(err))
        else
            local types = (r.fx and #r.fx > 0) and r.fx or nil
            local by_window = types ~= nil
            local rule = {fx = types, min_level = r.min_level, max_level = r.max_level, priority = M.MAX_RULES - i,
                select = function(ctx) return M.select(art_id, id, ctx, by_window) end}
            local ok2, h = pcall(gear.pfx.rule, rule)
            if ok2 then
                handles[#handles + 1] = {rule = h, id = id}
                made = made + 1
            else
                pcall(gear.pfx.undefine, id)
                problems[#problems + 1] = ('%s: fx[%d]: %s'):format(where, i, tostring(h))
            end
        end
    end
    return made, problems
end

return M
