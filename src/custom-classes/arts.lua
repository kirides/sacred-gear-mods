-- Custom classes: combat art copies and chains, from `arts/*.json` of this mod or of any installed mod (a mod the Sacred Class
-- Editor exported). Files that are not valid are reported and skipped.
--
-- A **copy** is the same art with its own id, name, description and numbers ("Venom Strike" = Poison Dart, stronger):
--   { "format": 1, "id": "venom-strike", "kind": "copy", "art_id": 2001, "base": 1059,
--     "name": {"en": "Venom Strike"}, "description": {"en": "..."},
--     "icon": "GUI_MOVE_KICK.TGA",                                                    (optional: another icon, a texture of the game)
--     "values": {"effect_base": 12.5, "effect_per_level": 2, "regen_base": 6, ...} }  (any field of gear.data.abilities)
-- `art_id` is 2000..4999 and `base` a combat art (1000..1999; spells cannot be copied): Gear serves the copy's own record to the
-- game's lookups and the base art's code runs it.
--
-- A **chain** is a named art that uses 2 to 8 arts or spells one after the other (it must start with a combat art):
--   { "format": 1, "id": "double-strike", "kind": "chain", "art_id": 2100, "steps": [1058, 1059], "delay": 0.1,
--     "name": {...}, "description": {...} }
-- The chain art is a copy of its first step (so the game starts that step), and this mod orders the next steps when the hero's
-- action ends, on the enemy nearest to the hero. Its regeneration is the sum of the steps' (`regen_base` and `regen_per_level` of the ability records, the game's
-- regeneration seconds, whole seconds for spells), so it can never be cheaper than the parts. The steps are learned with the chain.

local buffs = require('buffs')
local M = {}

-- The installed mods that are switched on (data of a mod that is off is not read).
local function active_mods()
    local out = {}
    for _, m in ipairs(gear.mods.list()) do
        if m.state == 'on' then out[#out + 1] = m end
    end
    return out
end
local ids, chains = {}, {}
M.chains = chains

local function whole(v, lo, hi) return type(v) == 'number' and v == math.floor(v) and v >= lo and v <= hi end

local function text(value, fallback)
    if type(value) == 'string' then return value end
    if type(value) ~= 'table' then return fallback end
    local lang = tostring(gear.game.config('LANGUAGE') or 'EN'):lower()
    if lang == 'us' then lang = 'en' end
    return value[lang] or value.en or select(2, next(value)) or fallback
end

-- Writes an icon texture name (the game's file name, e.g. GUI_MOVE_KICK.TGA) into a copy's record (char[0x24] at +0x0C).
function M.set_icon(rec, name)
    if type(name) ~= 'string' or #name == 0 or #name > 0x23 then return nil, 'icon must be a texture file name of at most 35 characters' end
    if not gear.ui.texture_image(name) then return nil, 'the game has no texture ' .. name end
    local bytes = {name:byte(1, -1)}
    for i = #bytes + 1, 0x24 do bytes[i] = 0 end
    for w = 0, 8 do
        local v = 0
        for b = 3, 0, -1 do v = v * 256 + (bytes[w * 4 + b + 1] or 0) end
        local ok = pcall(function() rec[('unk_%02x'):format(0x0C + w * 4)] = v end)
        if not ok then return nil, 'cannot write the icon' end
    end
    return true
end

local function is_art(id) return id >= 1000 and id < 2000 end
local function range_ok(art_id, base)
    if base >= 1000 and base < 2000 then return art_id >= 2000 and art_id <= 4999 end
    return false
end

-- The id of the game's ability that runs a copy or chain id (its own id for the game's abilities).
function M.base_of(id)
    local a = gear.data.abilities[id]
    return a and a.base or id
end

local function ability_name(id)
    local a = gear.data.abilities[id]
    return (a and gear.text.get(a.name_text)) or ('#' .. id)
end

-- Makes the copy; returns true or nil, why.
local function make_copy(d, where)
    local base = d.base
    if not whole(d.art_id, 100, 4999) or not whole(base, 1, 1999) then return nil, 'art_id and base must be ability ids' end
    if not range_ok(d.art_id, base) then return nil, ('art_id %d does not fit a copy of %d (combat arts can be copied under 2000..4999)'):format(d.art_id, base) end
    if gear.data.abilities[d.art_id] and not ids[d.art_id] then return nil, 'the id ' .. d.art_id .. ' is a game ability' end
    local rec, err = gear.classes.copy_ability(d.art_id, base, d.values)
    if not rec then return nil, err end
    local name = text(d.name, nil)
    if name then rec.name_text = assert(gear.text.add(name)) end
    local desc = text(d.description, nil)
    if desc then rec.description_text = assert(gear.text.add(desc)) end
    if d.icon ~= nil then
        local ok, why = M.set_icon(rec, d.icon)
        if not ok then return nil, why end
    end
    return true
end

local function make_chain(d, where)
    local steps = d.steps
    if type(steps) ~= 'table' or #steps < 2 or #steps > 8 then return nil, 'a chain has 2 to 8 steps' end
    local total0, total1 = 0, 0
    for i, s in ipairs(steps) do
        if not whole(s, 1, 4999) or not gear.data.abilities[s] then return nil, ('step %d: no ability %s'):format(i, tostring(s)) end
        if chains[s] then return nil, ('step %d: a chain cannot be a step'):format(i) end
        local rec = gear.data.abilities[s]
        total0 = total0 + (rec.regen_base or 0)
        total1 = total1 + (rec.regen_per_level or 0)
    end
    local first = gear.data.abilities[steps[1]]
    local base = M.base_of(steps[1])
    if not whole(d.art_id, 100, 4999) or not range_ok(d.art_id, base) then
        return nil, ('art_id %s does not fit a chain that starts with %d'):format(tostring(d.art_id), steps[1])
    end
    local rec, err = gear.classes.copy_ability(d.art_id, base)
    if not rec then return nil, err end
    -- the first step's own numbers (it may be a copy itself), the summed regeneration
    for _, f in ipairs(gear.data.abilities:fields(steps[1]) or {}) do
        if f.name ~= 'id' and f.name ~= 'name_text' and f.name ~= 'description_text' then
            local ok = pcall(function() rec[f.name] = first[f.name] end)
        end
    end
    if first.table == 'T2' or first.table == 'A2' then total0, total1 = math.ceil(total0), math.ceil(total1) end
    local ok, why = pcall(function() rec.regen_base = total0; rec.regen_per_level = total1 end)
    if not ok then return nil, 'regeneration: ' .. tostring(why) end
    local names = {}
    for i, s in ipairs(steps) do names[i] = ability_name(s) end
    local name = text(d.name, nil)
    if name then rec.name_text = assert(gear.text.add(name)) end
    local desc = (text(d.description, '') .. '\n' .. 'Chain: ' .. table.concat(names, ' > ')):gsub('^\n', '')
    rec.description_text = assert(gear.text.add(desc))
    chains[d.art_id] = {steps = steps, delay = d.delay or 0.1}
    return true
end

-- Reads every art file; returns the problems. After it, ids() has every id the files made.
function M.load()
    for id in pairs(ids) do gear.classes.remove_ability(id) end
    ids = {}
    for id in pairs(chains) do chains[id] = nil end
    for id in pairs(buffs.rules) do buffs.rules[id] = nil end
    local problems = {}
    local pending = {}
    for _, m in ipairs(active_mods()) do
        for _, name in ipairs(gear.mods.files(m.id, 'arts') or {}) do
            if name:lower():match('%.json$') then
                local where = m.id .. '/arts/' .. name
                local ok, d = pcall(gear.json.decode, gear.mods.read(m.id, 'arts/' .. name) or '')
                if not ok or type(d) ~= 'table' or (d.format ~= 1 and d.format ~= 2) or (d.kind ~= 'copy' and d.kind ~= 'chain') then
                    problems[#problems + 1] = where .. ': not an art file of format 1 or 2 (kind copy or chain)'
                else
                    pending[#pending + 1] = {d = d, where = where}
                end
            end
        end
    end
    -- copies first (chains may use them as steps), then the chains
    for pass = 1, 2 do
        for _, p in ipairs(pending) do
            if (pass == 1) == (p.d.kind == 'copy') then
                local made, why
                local ok, e = pcall(function()
                    if p.d.kind == 'copy' then made, why = make_copy(p.d, p.where) else made, why = make_chain(p.d, p.where) end
                end)
                if not ok then made, why = nil, tostring(e) end
                local rules
                if made then
                    local list, why_not = buffs.check(p.d.buffs, p.where)
                    if list then rules = list else made = nil; why = table.concat(why_not, '; ') end
                end
                if made then
                    if rules and #rules > 0 then buffs.rules[p.d.art_id] = rules end
                    ids[p.d.art_id] = {id = p.d.id, kind = p.d.kind, name = text(p.d.name, p.d.id)}
                else problems[#problems + 1] = p.where .. ': ' .. tostring(why) end
            end
        end
    end
    return problems
end

-- {[ability id] = {id, kind, name}}: what the art files made
function M.ids() return ids end

-- The steps a chain needs known for the hero (the chain's own id excluded).
function M.steps_of(id)
    local c = chains[id]
    return c and c.steps or nil
end

return M
