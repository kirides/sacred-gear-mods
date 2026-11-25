-- Beastmaster: the logic without the game (tests/beastmaster_test.lua runs it outside the game).
local M = {}

-- The hero's maximum level in the game and the growth stages of an ally: one stage every 18 levels (216 / 12), so a hero of level 216 has an
-- ally in its last stage.
M.MAX_LEVEL, M.STAGES, M.LEVELS_PER_STAGE = 216, 12, 18

-- The level an ally has for the hero's level: `pct` percent of it (100: the level of a creature the game would place for that hero),
-- 1 to 250 (the engine's range).
function M.ally_level(hero_level, pct)
    local l = math.floor((tonumber(hero_level) or 1) * ((tonumber(pct) or 100) / 100) + 0.5)
    return math.min(250, math.max(1, l))
end

-- The growth stage (0 to 12) of the hero's level: one more every 18 levels, none beyond level 216.
function M.stage(hero_level)
    local l = math.min(M.MAX_LEVEL, math.max(1, tonumber(hero_level) or 1))
    return math.min(M.STAGES, math.floor(l / M.LEVELS_PER_STAGE))
end

-- The size factor of an ally for the hero's level: `from` (percent, at stage 0) growing in equal steps to `to` (percent, at the last stage).
function M.growth(hero_level, from, to)
    from, to = (tonumber(from) or 100) / 100, (tonumber(to) or 100) / 100
    return from + (to - from) * M.stage(hero_level) / M.STAGES
end

-- The model scale of an ally: the species' base scale times its growth, kept inside what SacredBild draws (0.1 to 4).
function M.ally_scale(base, hero_level, from, to)
    return math.min(4, math.max(0.1, (tonumber(base) or 1) * M.growth(hero_level, from, to)))
end

-- A pet's model scale: the species' base scale times the pet size (percent).
function M.pet_scale(base, pct)
    return math.min(4, math.max(0.1, (tonumber(base) or 1) * (tonumber(pct) or 130) / 100))
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

-- Orders (the orders menu: the same ones as the Companions mod's behaviours, for the animals). An ally: 'aggressive' (fights what comes
-- near the hero), 'defensive' (only what is close), 'passive' (only follows), 'hold' (waits where it stands, fights what comes near
-- that spot). A pet cannot fight: it only follows ('passive') or waits ('hold'). `order` is the animal's own (nil: the default of
-- the Mods screen), `default` the setting. Returns the order that counts.
M.ORDERS = {'aggressive', 'defensive', 'passive', 'hold'}
M.PET_ORDERS = {'passive', 'hold'}
M.ORDER_LABEL = {aggressive = 'Aggressive', defensive = 'Defensive', passive = 'Passive', hold = 'Wait here', follow = 'Follow'}
local VALID = {aggressive = true, defensive = true, passive = true, hold = true}
function M.order_of(role, order, default)
    local o = VALID[order] and order or (VALID[default] and default or 'aggressive')
    if role == 'pet' then return o == 'hold' and 'hold' or 'passive' end
    return o
end
-- The label of an order for a role (a pet that only follows reads 'Follow').
function M.order_label(role, order)
    if role == 'pet' and order == 'passive' then return M.ORDER_LABEL.follow end
    return M.ORDER_LABEL[order] or '?'
end

-- How far an ally looks for an enemy: `engage` (the setting, in tiles) for aggressive, a few tiles for defensive, around its own spot
-- when it waits. In world units (`tile` units per tile). 0: it does not fight.
M.DEFENSIVE_TILES, M.HOLD_TILES = 8, 6
function M.engage_range(order, engage_tiles, tile)
    if order == 'passive' then return 0 end
    if order == 'hold' then return M.HOLD_TILES * tile end
    if order == 'defensive' then return math.min(engage_tiles, M.DEFENSIVE_TILES) * tile end
    return engage_tiles * tile
end

-- Whether an animal in this order is called back to the hero when it is far away or on another layer. One that waits stays where it is
-- ("To me" calls it).
function M.joins_hero(order) return order ~= 'hold' end

return M
