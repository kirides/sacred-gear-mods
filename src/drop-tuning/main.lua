-- Drop tuning: sets gear.drops from the mod's settings (see docs/GearDrops.md in the sacred-bild repository). All of it is
-- declarative: the multipliers are written into the game once per change and cost nothing per drop. The mod binds no keys; its
-- settings are on its page of the Mods screen (mouse or controller), and the "More" tab shows the rarity table as the game has it.

local S = gear.settings
local drops = gear.drops

-- The qualities 1 .. 14 of each group (plain items are what is left over; their weight changes nothing).
local GROUPS = {
    low = {1, 2, 3, 4},
    mid = {5, 6, 7, 8, 9},
    high = {10, 11, 12, 13, 14},
}

local function apply()
    drops.chance_scale(S.get('chance'))
    drops.find_scale(S.get('find'))
    local weights = {special0 = S.get('special'), special1 = S.get('special')}
    for group, qualities in pairs(GROUPS) do
        local m = S.get(group)
        for _, q in ipairs(qualities) do weights[q] = m end
    end
    drops.rarity_weights(weights)
    local mode = S.get('rng')
    if mode == 'fair' then
        drops.rng('fair')
    elseif mode == 'seeded' then
        drops.rng({seed = S.get('seed')})
    else
        drops.rng(nil)
    end
end

gear.on('load', apply)
gear.on('settings.changed', apply)

-- Other mods (and the self test) can steer it: gear.emit('drop-tuning.configure', {chance = 2, high = 0, rng = 'fair'}) sets those settings.
gear.on('drop-tuning.configure', function(values)
    for id, value in pairs(values or {}) do S.set(id, value) end
end)

gear.on('unload', function()
    drops.chance_scale(nil)
    drops.find_scale(nil)
    drops.rarity_weights(nil)
    drops.rng(nil)
end)

-- The "More" tab: the game's rarity table now against what it loaded, and the counters.
gear.mods.page(function(x, y, w, h)
    local row = 0
    local function line(text)
        gear.ui.label('dt_row_' .. row, text, x, y + row * 20, {})
        row = row + 1
    end
    local t = drops.rarity_table()
    if #t == 0 then
        line('The rarity table is not loaded yet (start a game).')
    else
        line('Quality   Weight (game)   Weight now')
        for _, e in ipairs(t) do
            line(('%7d   %13d   %10d'):format(e.quality, e.vanilla, e.weight))
        end
    end
    local s = drops.stats()
    line(('Loot rolls %d (%d authored), equipment picks %d, rarity draws %d'):format(s.rolls, s.forced, s.picks, s.rarity_draws))
    return row * 20
end)
