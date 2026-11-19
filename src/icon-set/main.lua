-- Icon Set drops: the six pieces of the Icon Set (object types 5101 .. 5106: Dragon, Dark Elf, Royal and Seraphim statue, Grail, Shell;
-- set 23 of sets.bin, bonus "Flaming Feet" while the whole set is in the backpack) are set items of level 1. The game's own set drops
-- are rare and compete with the 65 other sets, so at higher levels they are practically never seen. This mod turns a configurable share
-- of the equipment picks of creature loot into one of the pieces (gear.drops 'drops.select': the handler names the item type).
-- Everything is data driven by the settings; with chance 0 the mod changes nothing.

local S = gear.settings

local PIECES = {5101, 5102, 5103, 5104, 5105, 5106}

local function chance_for(level)
    local base = S.get('chance') or 0
    local lowest = S.get('min_level') or 1
    if level < lowest then return 0 end
    return (base + (S.get('per_level') or 0) * (level - lowest)) / 100
end

gear.on('drops.select', function(ev)
    if ev.type then return end          -- another mod already named the item
    local p = chance_for(ev.level or 1)
    if p <= 0 then return end
    if math.random() < p then
        ev.type = PIECES[math.random(#PIECES)]
    end
end)

-- Other mods can steer it: gear.emit('icon-set.configure', {chance = 5})
gear.on('icon-set.configure', function(values)
    for id, value in pairs(values or {}) do S.set(id, value) end
end)
