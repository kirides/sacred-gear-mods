-- Spell tuning, the logic without the game: who the caster is, how a percentage changes a spell's numbers.
local M = {}

M.ROLES = {'hero', 'companion', 'enemy', 'neutral', 'trap'}

-- Spells whose parameter 0 is how long the effect on the victim lasts (seconds = base + level * per level). Measured for 40
-- (root: the victim stood 1 s with 1, 7 s with 7); the others by the spell's text and values, not yet measured.
M.DURATION = {
    [16] = 'Bannkreis der Angst', [18] = 'Irritation', [19] = 'Bekehrung', [25] = 'Fleisch zu Stein', [40] = 'Pflanzenkaefig',
    [67] = 'Hoellenfurcht',
}

-- The record fields by what the player calls them. A spell record keeps `base + level * per_level` for each pair.
M.GROUPS = {
    duration = {'param0_base', 'param0_per_level'},
    strength = {'attack_mod_base', 'attack_mod_per_level', 'defense_mod_base', 'defense_mod_per_level', 'speed_mod_base', 'speed_mod_per_level'},
    damage = {'value0_base', 'value0_per_level', 'value1_base', 'value1_per_level', 'value2_base', 'value2_per_level',
              'value3_base', 'value3_per_level'},
}

local TRAPS = {'trap', 'falle', 'fallen', 'spike', 'turret'}

-- The caster's role. info: {hero = the creature is a hero, played = it is the one the player plays, enemy = hostile to the
-- hero the player plays, name = its type name}.
function M.role(info)
    if info.hero then return info.played and 'hero' or 'companion' end
    local n = (info.name or ''):lower()
    for _, t in ipairs(TRAPS) do if n:find(t, 1, true) then return 'trap' end end
    return info.enemy and 'enemy' or 'neutral'
end

function M.scale(v, percent)
    if percent == 100 then return v end
    return math.floor(v * percent / 100 + 0.5)
end

-- The values to write for a spell: `original` is a table field -> value as the game made it, `percent` {duration, strength,
-- damage} in percent. Duration applies to the spells of M.DURATION only.
function M.plan(id, original, percent)
    local out = {}
    for group, fields in pairs(M.GROUPS) do
        local p = percent[group] or 100
        if group ~= 'duration' or M.DURATION[id] then
            for _, f in ipairs(fields) do
                local v = original[f]
                if v and v ~= 0 then
                    local n = M.scale(v, p)
                    -- a duration never drops to nothing while the player left it above 0 %
                    if group == 'duration' and f == 'param0_base' and n < 1 and p > 0 then n = 1 end
                    out[f] = n
                end
            end
        end
    end
    return out
end

return M
