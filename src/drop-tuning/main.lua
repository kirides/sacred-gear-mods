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
    local ui = gear.ui
    local LH = 20
    local text_opts = { color = ui.rgba(235, 235, 235, 255), shadow = true, layer = 'top' }
    -- a solid panel behind the page: the dim game background made the text unreadable
    local area = ui.scroll_begin('dt_more_scroll', x, y, w, h, { step = LH, layer = 'top' })
    ui.rect(area.x, area.y, area.w, area.h, ui.rgba(18, 18, 22, 235), { layer = 'top' })
    local inner = area.w - 16
    local cy = 8
    local n = 0
    local function line(text, mono)
        local lines = ui.text_wrap(text, inner, text_opts)
        for _, l in ipairs(lines) do
            ui.text(l, area.content_x + 8, area.content_y + cy, text_opts)
            n = n + 1
            cy = cy + LH
        end
    end
    local t = drops.rarity_table()
    if #t == 0 then
        line('The rarity table is not loaded yet (start a game).')
    else
        -- columns instead of padded spaces (the UI font is proportional)
        local c1, c2, c3 = 8, 8 + math.floor(inner * 0.33), 8 + math.floor(inner * 0.66)
        local function row(a, b, c)
            ui.text(a, area.content_x + c1, area.content_y + cy, text_opts)
            ui.text(b, area.content_x + c2, area.content_y + cy, text_opts)
            ui.text(c, area.content_x + c3, area.content_y + cy, text_opts)
            n = n + 1
            cy = cy + LH
        end
        row('Quality', 'Weight (game)', 'Weight now')
        for _, e in ipairs(t) do
            row(tostring(e.quality), tostring(e.vanilla), tostring(e.weight))
        end
    end
    cy = cy + 6
    local level = gear.world.hero() and gear.world.hero():level() or 1
    local p = icon_chance(level)
    line(('Icon Set at level %d: %.3f%% of equipment drops become a piece'):format(level, p * 100))
    if p > 0 then
        line(('about one piece in %d equipment drops (one given piece: one in %d)'):format(math.floor(1 / p + 0.5), math.floor(6 / p + 0.5)))
    end
    line('The game alone: set weight 9 (x10 of 10000), 60% take the set path, then one of up to 65 sets: roughly 0.01% or less')
    local s = drops.stats()
    line(('Loot rolls %d (%d authored), equipment picks %d, rarity draws %d'):format(s.rolls, s.forced, s.picks, s.rarity_draws))
    ui.scroll_end(cy + 8)
    return h
end)
