-- Beastmaster: the logic without the game (tests/beastmaster_test.lua runs it outside the game).
local M = {}

-- Health and damage multiplier of an ally for a hero level and a strength percentage: a level 1 hero's animal is the wild kind, then +6%
-- health per hero level and +4% damage, scaled by strength.
function M.health(level, strength)
    level = math.max(1, tonumber(level) or 1)
    return math.max(100, math.floor(100 * (1 + 0.06 * (level - 1) * 4) * ((tonumber(strength) or 100) / 100)))
end
function M.damage(level, strength)
    level = math.max(1, tonumber(level) or 1)
    return 1 + 0.04 * (level - 1) * ((tonumber(strength) or 100) / 100)
end

-- Where follower `slot` of `count` stands around the hero: on a half circle behind, `radius` away. `facing` radians.
function M.spot(hx, hy, slot, count, radius, facing)
    local spread = math.pi * 0.9
    local a = (facing or 0) + math.pi - spread / 2 + (count > 1 and spread * (slot - 1) / (count - 1) or spread / 2)
    return math.floor(hx + math.cos(a) * radius), math.floor(hy + math.sin(a) * radius)
end

-- The nearest of `foes` ({x, y, id}) to (x, y) within `radius`, or nil.
function M.nearest(foes, x, y, radius)
    local best, bd
    for _, f in ipairs(foes) do
        local d = math.sqrt((f.x - x) ^ 2 + (f.y - y) ^ 2)
        if d <= radius and (not bd or d < bd) then best, bd = f, d end
    end
    return best, bd
end

-- Which followers to drop when the limits shrink: the newest of a role beyond `max`. Returns the ids.
function M.excess(list, role, max)
    local ids, n = {}, 0
    for _, e in ipairs(list) do
        if e.role == role then
            n = n + 1
            if n > max then ids[#ids + 1] = e.id end
        end
    end
    return ids
end

return M
