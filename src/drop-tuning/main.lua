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

-- The six pieces of the Icon Set (set 23 of sets.bin: Dragon, Dark Elf, Royal and Seraphim statue, Grail, Shell).
local ICON_PIECES = {5101, 5102, 5103, 5104, 5105, 5106}

-- The weight is out of 10000 equipment drops: the chance of one pick is weight / 10000.
local function icon_chance(level)
    local lowest = S.get('icon_min_level') or 1
    if level < lowest then return 0 end
    return math.min(1, ((S.get('icon_weight') or 0) + (S.get('icon_per_level') or 0) * (level - lowest)) / 10000)
end

-- drops.select: a share of the equipment picks of creature loot becomes an Icon Set piece (nothing at weight 0).
gear.on('drops.select', function(ev)
    if ev.type then return end          -- another mod already named the item
    local p = icon_chance(ev.level or 1)
    if p > 0 and math.random() < p then ev.type = ICON_PIECES[math.random(#ICON_PIECES)] end
end)

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
    local level = gear.world.hero() and gear.world.hero():level() or 1
    local p = icon_chance(level)
    line(('Icon Set at level %d: %.3f%% of equipment drops become a piece'):format(level, p * 100))
    if p > 0 then
        line(('about one piece in %d equipment drops (one given piece: one in %d)'):format(math.floor(1 / p + 0.5), math.floor(6 / p + 0.5)))
    end
    line('The game alone: set weight 9 (x10 of 10000), 60% take the set path, then one of up to 65 sets: roughly 0.01% or less')
    local s = drops.stats()
    line(('Loot rolls %d (%d authored), equipment picks %d, rarity draws %d'):format(s.rolls, s.forced, s.picks, s.rarity_draws))
    return row * 20
end)
