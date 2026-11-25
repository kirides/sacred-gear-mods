-- Improved shops: when the game fills a merchant's stock (`shop.stock`), a share of the shops that sell gear gets a few better pieces of the
-- hero's level. The mod only ever adds to what the game just made; it never rolls when you merely open a shop, so a shop shows the same wares
-- until the game resets it (a different merchant, or the game's own restock).

local S = gear.settings

-- The equipment categories of the item picker; potions and the rest are left alone.
local C = gear.shop.CATEGORY
local EQUIPMENT = {}
for _, c in ipairs({C.WEAPON, C.CHEST_ARMOUR, C.RING, C.SHIELD, C.HELMET, C.BOOTS, C.BELT, C.AMULET, C.SHOULDERS, C.ARMS, C.LEGS, C.GLOVES, C.WINGS, C.HORSE}) do
    EQUIPMENT[c] = true
end

local stats = {events = 0, rolled = 0, added = 0, failed = 0}

-- One of a page's own equipment categories, by the weights the game gave it; nil if the page sells no gear.
local function pick_category(categories)
    local total = 0
    for _, c in ipairs(categories) do
        if EQUIPMENT[c.category] then total = total + math.max(c.weight, 1) end
    end
    if total == 0 then return nil end
    local roll = math.random() * total
    for _, c in ipairs(categories) do
        if EQUIPMENT[c.category] then
            roll = roll - math.max(c.weight, 1)
            if roll < 0 then return c.category end
        end
    end
end

-- A quality tier between the settings, the lower ones more often (the lower of two draws).
local function pick_quality()
    local lo = math.floor(S.get('quality_min') or 7)
    local hi = math.max(lo, math.floor(S.get('quality_max') or 14))
    return math.min(math.random(lo, hi), math.random(lo, hi))
end

-- A merchant's wares come in three pages that the game stocks one after the other (the event fires once per page, in the order of their
-- containers). The first page of a run decides whether this merchant has finds and how many; the pages share them out.
local batch = {merchant = 0, last = 0, remaining = 0}

gear.on('shop.stock', function(e)
    stats.events = stats.events + 1
    local info = gear.shop.info()
    if not info then return end
    if e.merchant ~= batch.merchant or e.container <= batch.last then
        batch = {merchant = e.merchant, last = 0, remaining = 0}
        local chance = (e.reason == 'restock') and (S.get('chance_restock') or 0) or (S.get('chance_new') or 0)
        if chance > 0 and math.random() * 100 < chance then
            batch.remaining = math.random(1, math.max(1, math.floor(S.get('count') or 2)))
            stats.rolled = stats.rolled + 1
        end
    end
    batch.last = e.container
    if batch.remaining <= 0 then return end
    local index, page = 0, nil
    for i, p in ipairs(info.pages) do
        if p.container == e.container then index, page = i, p end
    end
    if not page then return end
    local share = math.ceil(batch.remaining / math.max(1, #info.pages - index + 1))
    local level = math.max(1, (info.hero_level or 1) + math.floor(S.get('level_offset') or 0))
    for _ = 1, share do
        local category = pick_category(page.categories)
        if not category then return end
        local id, err = gear.shop.add{container = page.container, category = category, quality = pick_quality(), level = level}
        if id then
            stats.added = stats.added + 1
            batch.remaining = batch.remaining - 1
        else
            stats.failed = stats.failed + 1
            gear.log(('improved-shops: could not stock a find: %s'):format(tostring(err)))
            return
        end
    end
end)

-- For the self test.
gear.on('improved-shops.stats', function(answer) answer(stats) end)
