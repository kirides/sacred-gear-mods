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

-- The X-MAS sets (sets 33 .. 38 of sets.bin, one per class; item types as Sacred Gear lists them with their class masks). The game
-- itself has no date check for them (nothing in Sacred.exe compares the month), and its set drops never produced one in 823 set
-- drops at creature level 10, so they only come from this setting (or from Carried gear).
local XMAS_PIECES = {
    seraphim = {1840, 1841, 1842, 7978, 7979},
    gladiator = {1833, 1834, 1837},
    battlemage = {1838, 7974, 7975},
    darkelf = {1835, 7968, 7969},
    woodelf = {1836, 7970, 7971},
    vampiress = {1839, 7976, 7977},
}

local function hero_class()
    local hero = gear.world.hero()
    return hero and hero:class()
end

local function xmas_chance(level)
    local lowest = S.get('xmas_min_level') or 1
    if level < lowest then return 0 end
    return math.min(1, ((S.get('xmas_weight') or 0) + (S.get('xmas_per_level') or 0) * (level - lowest)) / 10000)
end

-- drops.select: a share of the equipment picks of creature loot becomes an Icon Set piece, or a piece of the hero's X-MAS set
-- (nothing at weight 0).
gear.on('drops.select', function(ev)
    if ev.type then return end          -- another mod already named the item
    local level = ev.level or 1
    local p = icon_chance(level)
    if p > 0 and math.random() < p then ev.type = ICON_PIECES[math.random(#ICON_PIECES)]; return end
    p = xmas_chance(level)
    if p > 0 and math.random() < p then
        local pieces = XMAS_PIECES[hero_class()]
        if pieces then ev.type = pieces[math.random(#pieces)] end
    end
end)

-- For the self test: the class of the hero decides which pieces drop.
gear.on('drop-tuning.xmas_pieces', function(class, answer) answer(XMAS_PIECES[class]) end)

-- Carried gear: monsters hold the items the Disarming skill takes from them in their equipment slots; only the Disarming skill gets them.
-- With a chance above 0 a dying creature drops (a share of) them instead, so no hero needs the skill. The drop is a fresh item of the same
-- type at the corpse, which is what disarming gives too: the item's own record decides its level and quality (the same fixed, lowest tier
-- of a unique or set item every time), not the level of the creature.
local carry = {handler = nil, done = {}, count = 0, dropped = 0, seen = 0}

-- Which carried items the filter admits: 'special' = set and unique items only (what can be disarmed), 'all' = any equipment.
local function carry_wanted(item, filter)
    if item.gold or item.quest or item.potion then return false end
    if filter == 'all' then return true end
    return item.set == true or item.rarity >= 15 or item.category == 'special'
end

local function carry_roll(ev)
    if ev.network or not ev.id or ev.id <= 16 then return end       -- heroes and network games: nothing
    local p = (S.get('carry_chance') or 0) / 100
    if p <= 0 then return end
    local c = gear.world.object(ev.id)
    local items = c and c:carried()
    if not items or #items == 0 then return end
    local filter = S.get('carry_filter') or 'special'
    local x, y, layer = c:position()
    for _, e in ipairs(items) do
        local item = e.item
        if not carry.done[item.id] and carry_wanted(item, filter) then
            carry.done[item.id] = true          -- the loot function runs once per authored drop: roll each item once
            carry.count = carry.count + 1
            carry.seen = carry.seen + 1
            if carry.count > 4000 then carry.done, carry.count = {}, 0 end
            if math.random() < p then
                local type = item.type
                gear.after(0.05, function()
                    local ax, ay = gear.world.around(x, y, 20, 90)
                    local made = gear.world.spawn(type, ax, ay, {layer = layer})
                    if made then carry.dropped = carry.dropped + 1 end
                end)
            end
        end
    end
end

-- Switched on only while the chance is above 0: with the setting off the loot function does not call into Lua for this mod at all.
local function carry_apply()
    local on = (S.get('carry_chance') or 0) > 0
    if on and not carry.handler then
        carry.handler = gear.on('drops.roll', carry_roll)
    elseif not on and carry.handler then
        gear.off(carry.handler)
        carry.handler = nil
    end
end

local function apply()
    carry_apply()
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

-- For the self test: the filter, and the counters of the carried gear.
gear.on('drop-tuning.carry_filter', function(item, filter, answer) answer(carry_wanted(item, filter)) end)
gear.on('drop-tuning.carry_stats', function(answer) answer({seen = carry.seen, dropped = carry.dropped}) end)

gear.on('unload', function()
    if carry.handler then gear.off(carry.handler); carry.handler = nil end
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
    cy = cy + 6
    local class = hero_class()
    local pieces = XMAS_PIECES[class]
    local xp = xmas_chance(level)
    if xp > 0 and pieces then
        line(('X-MAS set (%s) at level %d: %.3f%% of equipment drops become a piece, about one in %d (one given piece: one in %d)'):format(
            tostring(class), level, xp * 100, math.floor(1 / xp + 0.5), math.floor(#pieces / xp + 0.5)))
    elseif xp > 0 then
        line(('X-MAS set: there is no set for the class %s'):format(tostring(class)))
    else
        line('X-MAS set: off (give it a weight to let creatures drop the pieces of the X-MAS set of your class)')
    end
    line('The game alone: the X-MAS pieces never showed up in a test of 823 set drops of a creature (and the game has no date check for them), so their odds are about 0%')
    cy = cy + 6
    if (S.get('carry_chance') or 0) > 0 then
        line(('Carried gear: %d%% chance (%s); %d items seen on dying creatures, %d dropped'):format(
            S.get('carry_chance') or 0, S.get('carry_filter') == 'all' and 'all equipment' or 'set and unique items', carry.seen, carry.dropped))
    else
        line('Carried gear: off (give it a chance to let creatures drop the items you could disarm)')
    end
    local s = drops.stats()
    line(('Loot rolls %d (%d authored), equipment picks %d, rarity draws %d'):format(s.rolls, s.forced, s.picks, s.rarity_draws))
    ui.scroll_end(cy + 8)
    return h
end)
