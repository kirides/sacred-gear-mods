-- Balance editor: the list of values of balance.bin the screen offers, with where each one sits in the file.
--
-- `off` is the byte offset in the block of global values that opens the file (its first 4 bytes are the block's length, so the offset in the
-- file is off + 4). The positions come from the game's own code (what reads them, Sacred.exe Gold) as written up by the SacredEngineRemake
-- project (Sacred.Core/GameBin/Balance), and from SacredMagician's tables for the difficulty grid. A tip says what is known of a value and
-- what is not; where nobody measured the effect in play, the tip says so.
--
-- `kind`: 'f' (a 32 bit float) or 'i' (a signed 32 bit integer). `min`, `max`, `step` bound what the screen lets you pick.
-- The vanilla values (what shows as "game: ...") are in defaults.lua, made from the game's file by tools/balance_defaults.lua.
local M = {}

M.FILE_SIZE = 24328          -- bin\balance.bin of Sacred Gold; a file of another size is never patched (Gear checks that)
M.FILE = 'bin\\balance.bin'

-- tabs and the order of their groups
M.TABS = {
    {id = 'difficulty', label = 'Difficulty'},
    {id = 'creatures', label = 'Creatures'},
    {id = 'hero', label = 'Hero'},
    {id = 'loot', label = 'Loot'},
    {id = 'items', label = 'Items'},
    {id = 'world', label = 'World'},
}

M.fields = {}
M.by_id = {}
M.groups = {}                -- tab id -> list of group names in order

local function add(f)
    assert(not M.by_id[f.id], 'duplicate id ' .. f.id)
    f.kind = f.kind or 'f'
    f.step = f.step or (f.kind == 'i' and 1 or 0.05)
    f.min = f.min or 0
    assert(f.max, f.id)
    f.index = #M.fields + 1
    M.fields[f.index] = f
    M.by_id[f.id] = f
    local g = M.groups[f.tab]
    if not g then g = {}; M.groups[f.tab] = g end
    local seen = false
    for i = 1, #g do if g[i] == f.group then seen = true break end end
    if not seen then g[#g + 1] = f.group end
end

-- Ranges and steps shared by many values.
local R = {
    mult = {min = 0, max = 20, step = 0.05},         -- a factor around 1
    big = {min = 0, max = 1000, step = 1},
    level = {kind = 'i', min = 0, max = 300, step = 1},
    chance = {kind = 'i', min = 0, max = 1000, step = 5},     -- out of 1000
    price = {kind = 'i', min = 0, max = 100000, step = 10},
}
local function with(preset, t)
    for k, v in pairs(preset) do if t[k] == nil then t[k] = v end end
    return t
end

---------------------------------------------------------------------------------------------------------------- difficulty
-- Six columns per row. The game stores them in the order silver, gold, platinum, niobium, the shared online value, bronze.
local DIFFS = {{'Bronze', 5}, {'Silver', 0}, {'Gold', 1}, {'Platinum', 2}, {'Niobium', 3}, {'Online', 4}}
local function per_difficulty(group, key, base, preset, tip, label_fn)
    for _, d in ipairs(DIFFS) do
        add(with(preset, {id = 'diff.' .. key .. '.' .. d[1]:lower(), tab = 'difficulty', group = group, label = label_fn and label_fn(d[1]) or d[1],
            off = base + d[2] * 4, tip = tip}))
    end
end
local DTIP = ' Per difficulty: Bronze, Silver, Gold, Platinum, Niobium; "Online" is the value the game keeps for network games and does not map to a level.'
per_difficulty('Attack and defence value', 'av', 0x710, {min = 0, max = 10, step = 0.01},
    'Multiplier of the attack and defence value of creatures (AW/VW).' .. DTIP)
per_difficulty('Hit points', 'hp', 0x728, {min = 0, max = 10, step = 0.01}, 'Multiplier of the hit points of creatures.' .. DTIP)
per_difficulty('Damage', 'dmg', 0x740, {min = 0, max = 10, step = 0.01}, 'Multiplier of the damage creatures deal.' .. DTIP)
per_difficulty('Resistance', 'res', 0x758, {min = 0, max = 50, step = 0.1}, 'Multiplier of the resistances of creatures.' .. DTIP)
per_difficulty('Experience', 'xp', 0x770, {min = 0, max = 20, step = 0.01}, 'Multiplier of the experience a creature gives.' .. DTIP)
per_difficulty('Lowest creature level', 'minlvl', 0x9B4, R.level,
    'The lowest level creatures get on this difficulty (the game: 20 Silver, 60 Gold, 100 Platinum, 140 Niobium).' .. DTIP)
per_difficulty('Highest creature level', 'maxlvl', 0x98C, R.level,
    'The highest level creatures can reach on this difficulty; 0 means no limit as far as the game code shows.' .. DTIP)
per_difficulty('Level added before scaling', 'lvladd', 0x788, R.level,
    'Levels added to a creature before the difficulty scales it (read by the game when it sets a creature\'s level).' .. DTIP)
per_difficulty('Level scaling (percent)', 'lvlpct', 0x11B8, {kind = 'i', min = -50, max = 300, step = 1},
    'Percent the difficulty adds to the level of creatures (from the game code: used when a creature\'s level is normalised and when its loot is made).' .. DTIP)
per_difficulty('Level added after scaling', 'lvladd2', 0x11D0, {kind = 'i', min = -50, max = 300, step = 1},
    'Levels added after the percentage scaling.' .. DTIP)

---------------------------------------------------------------------------------------------------------------- creatures
for i = 1, 5 do
    add({id = 'cre.hpcurve.level' .. i, tab = 'creatures', group = 'Health by creature level', label = 'Step ' .. i .. ': from level', off = 0x2E0 + (i - 1) * 8,
        min = 0, max = 300, step = 1, tip = 'The creature health curve is five points (level, factor). Between two points the game interpolates; above the last it carries on with the last segment.'})
    add({id = 'cre.hpcurve.factor' .. i, tab = 'creatures', group = 'Health by creature level', label = 'Step ' .. i .. ': health factor', off = 0x2E4 + (i - 1) * 8,
        min = 0, max = 20, step = 0.01, tip = 'Health factor at that level (1 = the creature type\'s own health).'})
end
add({id = 'cre.hp.behavior', tab = 'creatures', group = 'Health factors', label = 'Health factor: boss behaviour', off = 0x8C0, min = 0, max = 20, step = 0.05,
    tip = 'Factor selected for creatures whose behaviour has flag 0x80000 (bosses and champions as far as the code shows), before the type and difficulty factors.'})
add({id = 'cre.hp.status', tab = 'creatures', group = 'Health factors', label = 'Health factor: marked creatures', off = 0x8C4, min = 0, max = 20, step = 0.05,
    tip = 'Alternative factor for creatures whose status bit 6 is set, when the other flag is not.'})
add({id = 'cre.cap.behavior', tab = 'creatures', group = 'Level caps', label = 'Extra level cap: behaviour flag', off = 0x8B8, kind = 'i', min = 0, max = 300, step = 1,
    tip = 'Added to the sector\'s level cap for creatures whose behaviour has flag 0x80000.'})
add({id = 'cre.cap.actor', tab = 'creatures', group = 'Level caps', label = 'Extra level cap: actor flag', off = 0x8BC, kind = 'i', min = 0, max = 300, step = 1,
    tip = 'Added to the sector\'s level cap for creatures whose actor flag 0x40 is set.'})

---------------------------------------------------------------------------------------------------------------- hero & skills
for i, lv in ipairs({3, 6, 12, 20, 30, 50}) do
    add({id = 'hero.skillstep.' .. i, tab = 'hero', group = 'New skills', label = 'Skill step ' .. i .. ' opens at hero level', off = 0x308 + (i - 1) * 4,
        kind = 'i', min = 1, max = 300, step = 1, tip = 'The hero level at which the next group of skills opens (the game: 3, 6, 12, 20, 30, 50). Keep them in ascending order.'})
end
-- The passive skill curves: base, divisor, limit. Offset of each curve and what it does (skill numbers are the game's skill slots).
local CURVES = {
    {0x40, 'Weapon lore: damage'}, {0x4C, 'Spell damage'}, {0x58, 'Unarmed: attack'}, {0x64, 'Unarmed: speed'},
    {0x70, 'Skill 4: attack'}, {0x7C, 'Skill 4: speed'}, {0x88, 'Skill 5: attack'}, {0x94, 'Skill 5: speed'},
    {0xA0, 'Skill 13: attack'}, {0xAC, 'Skill 13: speed'}, {0xB8, 'Skill 3: attack'}, {0xC4, 'Skill 3: speed'},
    {0xD0, 'Skill 6: attack'}, {0xDC, 'Skill 6: speed'}, {0xE8, 'Skill 7: attack'}, {0xF4, 'Skill 7: speed (and casting speed)'},
    {0x160, 'Skill 25: regeneration'}, {0x16C, 'Skill 12: regeneration'}, {0x178, 'Skill 8: attack'}, {0x184, 'Skill 8: defence'},
    {0x190, 'Constitution: regeneration'}, {0x19C, 'Vitality: health'}, {0x1A8, 'Skill 9: defence'}, {0x1B4, 'Skill 9: alternate defence'},
    {0x1C0, 'Armor lore: physical protection'}, {0x1CC, 'Armor lore: fire protection'}, {0x1D8, 'Armor lore: magic protection'},
    {0x1E4, 'Armor lore: poison protection'}, {0x1F0, 'Armor lore: movement'}, {0x127C, 'Skill 32: regeneration'},
}
M.CURVES = CURVES
for _, c in ipairs(CURVES) do
    local slug = ('%x'):format(c[1])
    local tip = 'A skill curve of three numbers: with the skill at rank r the bonus is about base * r / (r + divisor) up to the limit (from the game code; the exact formula was not tested in play).'
    add({id = 'skill.' .. slug .. '.base', tab = 'hero', group = c[2], label = 'Base', off = c[1], min = 0, max = 100, step = 0.5, tip = tip, skill = true})
    add({id = 'skill.' .. slug .. '.divisor', tab = 'hero', group = c[2], label = 'Divisor', off = c[1] + 4, min = 1, max = 500, step = 1, tip = tip, skill = true})
    add({id = 'skill.' .. slug .. '.limit', tab = 'hero', group = c[2], label = 'Limit', off = c[1] + 8, min = 0, max = 2000, step = 5, tip = tip, skill = true})
end
local DIV = {{0x0C, 'Physical protection'}, {0x10, 'Fire protection'}, {0x14, 'Magic protection'}, {0x18, 'Poison protection'}}
for _, d in ipairs(DIV) do
    add({id = 'hero.protdiv.' .. d[2]:lower():gsub(' ', '_'), tab = 'hero', group = 'Protection and damage divisors', label = d[2] .. ' divisor', off = d[1],
        min = 1, max = 2000, step = 1, tip = 'The game divides the protection value by this to get the effect (a larger divisor makes the protection weaker).'})
end
local DIV2 = {{0x20, 'Physical damage'}, {0x24, 'Fire damage'}, {0x28, 'Magic damage'}, {0x2C, 'Poison damage'}}
for _, d in ipairs(DIV2) do
    add({id = 'hero.dmgdiv.' .. d[2]:lower():gsub(' ', '_'), tab = 'hero', group = 'Protection and damage divisors', label = d[2] .. ' divisor', off = d[1],
        min = 1, max = 2000, step = 1, tip = 'The game divides the damage value by this (a larger divisor makes the damage weaker).'})
end
local DIV3 = {{0x30, 'Physical protection (multiplier)'}, {0x34, 'Fire protection (multiplier)'}, {0x38, 'Magic protection (multiplier)'}, {0x3C, 'Poison protection (multiplier)'}}
for _, d in ipairs(DIV3) do
    add({id = 'hero.protmul.' .. d[2]:lower():gsub('[ ()]+', '_'), tab = 'hero', group = 'Protection and damage divisors', label = d[2] .. ' divisor', off = d[1],
        min = 1, max = 2000, step = 1, tip = 'Divisor of the protection multipliers of equipment (read by the game\'s result calculation).'})
end
add({id = 'hero.attr.growth', tab = 'hero', group = 'Protection and damage divisors', label = 'Attribute growth start', off = 0x1C, min = 0, max = 500, step = 1,
    tip = 'Where the growth of attributes with the level starts (the game interpolates from here towards 156 over 156 levels).'})

---------------------------------------------------------------------------------------------------------------- loot
add({id = 'loot.base', tab = 'loot', group = 'How much drops', label = 'Chance of drops (per thousand)', off = 0x700, min = 0, max = 5000, step = 10,
    tip = 'The chance budget of a creature drop, per thousand. A value above 1000 allows several passes, so it is not a percentage. The game: 350.'})
add({id = 'loot.boosted', tab = 'loot', group = 'How much drops', label = 'Factor for champions and bosses', off = 0x708, min = 0, max = 20, step = 0.05,
    tip = 'Multiplier of the drop chance of boosted creatures.'})
add({id = 'loot.party', tab = 'loot', group = 'How much drops', label = 'Extra chance per nearby party member', off = 0x126C, min = 0, max = 5, step = 0.01,
    tip = 'Added to the drop chance for each eligible party member nearby (at most four count).'})
add({id = 'loot.rolls', tab = 'loot', group = 'How much drops', label = 'Drop attempts per death', off = 0x11E8, kind = 'i', min = 0, max = 20, step = 1,
    tip = 'How many times the game tries to drop something when a creature dies.'})
add({id = 'loot.extra.marked', tab = 'loot', group = 'How much drops', label = 'Most extra attempts: marked creature', off = 0x1250, kind = 'i', min = 0, max = 50, step = 1,
    tip = 'Upper bound of the extra drop attempts of marked creatures (the lower bound is one).'})
add({id = 'loot.extra.boosted', tab = 'loot', group = 'How much drops', label = 'Most extra attempts: boosted creature', off = 0x1254, kind = 'i', min = 0, max = 50, step = 1,
    tip = 'Upper bound of the extra drop attempts of boosted creatures.'})
add({id = 'loot.detach', tab = 'loot', group = 'How much drops', label = 'Equipment falling off (per thousand)', off = 0x7A8, kind = 'i', min = 0, max = 1000, step = 5,
    tip = 'Chance, per thousand, that a dying creature loses worn equipment (three tries before the killer is checked). The game: 0.'})
add(with(R.chance, {id = 'loot.kind.weapon', tab = 'loot', group = 'What drops (per thousand)', label = 'Weapon', off = 0x89C, tip = 'Chance per thousand of a weapon drop.'}))
add(with(R.chance, {id = 'loot.kind.armor', tab = 'loot', group = 'What drops (per thousand)', label = 'Armour', off = 0x8A0, tip = 'Chance per thousand of an armour drop.'}))
add(with(R.chance, {id = 'loot.kind.money', tab = 'loot', group = 'What drops (per thousand)', label = 'Gold', off = 0x8A4, tip = 'Chance per thousand of gold.'}))
add(with(R.chance, {id = 'loot.kind.potion', tab = 'loot', group = 'What drops (per thousand)', label = 'Potion', off = 0x8B4, tip = 'Chance per thousand of a potion.'}))
add({id = 'loot.money.min', tab = 'loot', group = 'Gold', label = 'Least gold per drop', off = 0x8AC, kind = 'i', min = 0, max = 100000, step = 10, tip = 'The smallest gold amount of a drop.'})
add({id = 'loot.money.max', tab = 'loot', group = 'Gold', label = 'Most gold per drop', off = 0x8B0, kind = 'i', min = 0, max = 100000, step = 10, tip = 'The largest gold amount of a drop.'})
add({id = 'loot.rarity.floor', tab = 'loot', group = 'Rarity', label = 'Rarity weight floor', off = 0x1218, min = 0, max = 1, step = 0.01,
    tip = 'A floor blended into the rarity weights; raising it flattens how much level and bonuses matter.'})
add({id = 'loot.rarity.survival', tab = 'loot', group = 'Rarity', label = 'Survival-time rarity factor', off = 0x121C, min = 0, max = 5, step = 0.05,
    tip = 'Factor on the survival-time curve that adds to the rarity of what a source gives.'})
add({id = 'loot.rarity.boosted', tab = 'loot', group = 'Rarity', label = 'Rarity bonus: boosted creature', off = 0x1258, kind = 'i', min = 0, max = 500, step = 1,
    tip = 'Rarity bonus added to a boosted creature\'s drops.'})
add({id = 'loot.rarity.marked', tab = 'loot', group = 'Rarity', label = 'Rarity bonus: marked creature', off = 0x125C, kind = 'i', min = 0, max = 500, step = 1,
    tip = 'Rarity bonus added to a marked creature\'s drops.'})
add({id = 'loot.rarity.expscale', tab = 'loot', group = 'Rarity', label = 'Experience to rarity scale', off = 0x1318, min = 1, max = 500, step = 1,
    tip = 'The rarity argument is rescaled with the square root of the creature\'s experience value divided by this.'})
for i = 1, 11 do
    add({id = 'loot.reward.' .. i, tab = 'loot', group = 'Rarity bonus by source', label = 'Source ' .. i, off = 0x1224 + (i - 1) * 4, kind = 'i', min = -200, max = 500, step = 1,
        tip = 'Rarity bonus added for one of the eleven kinds of boosted source the game tells apart (chests and container kinds; which is which was not mapped).'})
end
add({id = 'loot.ratio.lower', tab = 'loot', group = 'Level difference', label = 'Lower ratio', off = 0x9A8, min = 0, max = 3, step = 0.01,
    tip = 'Creature level to hero level ratio below which the experience and drop penalty starts to interpolate.'})
add({id = 'loot.ratio.upper', tab = 'loot', group = 'Level difference', label = 'Upper ratio', off = 0x9AC, min = 0, max = 3, step = 0.01,
    tip = 'Ratio at which the penalty is complete (the creature marker turns red at this ratio).'})
add({id = 'loot.ratio.plateau', tab = 'loot', group = 'Level difference', label = 'Full value from ratio', off = 0x9B0, min = 0, max = 3, step = 0.01,
    tip = 'Ratio from which a creature gives its full experience and drops.'})
local CLASSES = {'Wood Elf', 'Gladiator', 'Vampiress', 'Dark Elf', 'Battle Mage', 'Seraphim', 'Daemon', 'Dwarf'}
for i, c in ipairs(CLASSES) do
    add({id = 'loot.rune.class' .. i, tab = 'loot', group = 'Runes', label = 'Level factor: ' .. c, off = 0x810 + (i - 1) * 4, min = 0, max = 10, step = 0.05,
        tip = 'Level coefficient of the rune drop for this hero class (file order: Wood Elf, Gladiator, Vampiress, Dark Elf, Battle Mage, Seraphim, Daemon, Dwarf).'})
end
add({id = 'loot.rune.chance', tab = 'loot', group = 'Runes', label = 'Rune chance factor', off = 0x6F8, min = 0, max = 500, step = 1, tip = 'Scales the threshold of a rune drop.'})
add({id = 'loot.rune.divisor', tab = 'loot', group = 'Runes', label = 'Rune inventory divisor', off = 0x11A4, min = 0.1, max = 20, step = 0.1,
    tip = 'Each carried or stored rune counts 1 / this towards the learned combat art rank sum used as the denominator.'})
add({id = 'loot.rune.boosted', tab = 'loot', group = 'Runes', label = 'Rune factor: boosted', off = 0x11A8, min = 0, max = 20, step = 0.05, tip = 'Rune chance factor of boosted sources.'})
add({id = 'loot.rune.limit', tab = 'loot', group = 'Runes', label = 'Rune ratio limit', off = 0x11AC, min = 0, max = 20, step = 0.05, tip = 'Upper limit of the rune ratio.'})

---------------------------------------------------------------------------------------------------------------- items & prices
add({id = 'item.levelfactor.0', tab = 'items', group = 'Item generation', label = 'Level factor at level 0', off = 0x1FC, min = 0, max = 500, step = 1,
    tip = 'The game interpolates the combat level factor of generated equipment between the values at level 0 and level 100.'})
add({id = 'item.levelfactor.100', tab = 'items', group = 'Item generation', label = 'Level factor at level 100', off = 0x200, min = 0, max = 1000, step = 5,
    tip = 'See the factor at level 0.'})
add({id = 'item.levelscale', tab = 'items', group = 'Item generation', label = 'Generation level scale', off = 0x111C, min = 0.05, max = 5, step = 0.01,
    tip = 'The cap of the generation level is 216 / this; creature set loot also needs the creature level times this to stay below the hero level.'})
add({id = 'item.norm.other', tab = 'items', group = 'Item generation', label = 'Normalisation: other opponents', off = 0x9D0, min = 0, max = 10, step = 0.05,
    tip = 'Normalisation factor for equipment bonuses restricted to something other than hero class one.'})
add({id = 'item.norm.hero', tab = 'items', group = 'Item generation', label = 'Normalisation: hero opponents', off = 0x9D4, min = 0, max = 10, step = 0.05, tip = 'Normalisation factor, hero opponents.'})
add({id = 'item.norm.class', tab = 'items', group = 'Item generation', label = 'Normalisation: hero class', off = 0x9D8, min = 0, max = 10, step = 0.05, tip = 'Normalisation factor for hero-class restricted bonuses.'})
add(with({kind = 'i', min = 0, max = 1000, step = 5}, {id = 'item.socket.first', tab = 'items', group = 'Sockets', label = 'First socket (per thousand)', off = 0x11B0,
    tip = 'Chance per thousand that an item gets a first socket.'}))
add(with({kind = 'i', min = 0, max = 1000, step = 5}, {id = 'item.socket.more', tab = 'items', group = 'Sockets', label = 'Each further socket (per thousand)', off = 0x11B4,
    tip = 'Chance per thousand for each additional socket.'}))
for i = 1, 3 do
    add({id = 'item.socket.cost' .. i, tab = 'items', group = 'Sockets', label = 'Cost factor of socket kind ' .. i, off = 0x10E4 + (i - 1) * 4, min = 0, max = 5, step = 0.01,
        tip = 'Added to the bonus cost multiplier for socket kinds 1, 2 and 3.'})
end
local function curve3(prefix, group, name, off, tip)
    add({id = prefix .. '.c', tab = 'items', group = group, label = name .. ': constant', off = off, min = -1000, max = 10000, step = 0.1, tip = tip})
    add({id = prefix .. '.l', tab = 'items', group = group, label = name .. ': linear', off = off + 4, min = -1000, max = 10000, step = 0.1, tip = tip})
    add({id = prefix .. '.q', tab = 'items', group = group, label = name .. ': quadratic', off = off + 8, min = -100, max = 1000, step = 0.01, tip = tip})
end
curve3('price.damage', 'Item prices', 'Damage price curve', 0x204, 'Price coefficient (constant, linear, quadratic) of the damage of a weapon.')
curve3('price.protection', 'Item prices', 'Protection price curve', 0x210, 'Price coefficient of the protection of armour.')
curve3('price.attack', 'Item prices', 'Attack price curve', 0x268, 'Price coefficient of the attack value.')
curve3('price.defense', 'Item prices', 'Defence price curve', 0x274, 'Price coefficient of the defence value.')
add({id = 'price.final', tab = 'items', group = 'Item prices', label = 'Final price factor', off = 0x11EC, min = 0, max = 20, step = 0.05,
    tip = 'Multiplier of the price of every item, applied before the requirements change it.'})
local RANKS = {{0x21C, 'Combat art'}, {0x220, 'Spell'}, {0x224, 'Skill'}, {0x22C, 'Attribute'}, {0x230, 'Other bonus'}}
for _, r in ipairs(RANKS) do
    add({id = 'price.rank.' .. r[2]:lower():gsub(' ', '_'), tab = 'items', group = 'Item prices', label = 'Price per rank: ' .. r[2], off = r[1], min = 0, max = 100000, step = 10,
        tip = 'What each rank of this kind of bonus adds to an item\'s price.'})
end
local WEIGHTS = {{0x2C8, 'Physical damage'}, {0x280, 'Fire damage'}, {0x298, 'Magic damage'}, {0x2B0, 'Poison damage'},
    {0x2D4, 'Physical protection'}, {0x28C, 'Fire protection'}, {0x2A4, 'Magic protection'}, {0x2BC, 'Poison protection'}}
for _, w in ipairs(WEIGHTS) do
    add({id = 'price.weight.' .. w[2]:lower():gsub(' ', '_'), tab = 'items', group = 'Price weights', label = w[2], off = w[1], min = 0, max = 100, step = 0.05,
        tip = 'How much of the price this kind of damage or protection carries.'})
end
for i = 1, 23 do
    add({id = 'price.special.' .. i, tab = 'items', group = 'Special bonus prices', label = 'Special bonus ' .. i, off = 0x900 + (i - 1) * 4, kind = 'i', min = 0, max = 1000000, step = 10,
        tip = 'Price for one of the 23 special bonuses (bonus codes 840 to 867); some are fixed amounts, others are multiplied by the bonus value.'})
end

---------------------------------------------------------------------------------------------------------------- world
add({id = 'world.speed', tab = 'world', group = 'Movement', label = 'Movement speed scale', off = 0x6FC, min = 0.1, max = 5, step = 0.05,
    tip = 'Scales the walking speed of every creature and the speed its movement animation plays at. The game: 1.25.'})
add({id = 'world.respawn.first', tab = 'world', group = 'Respawn', label = 'Region fill, first (seconds)', off = 0x7A0, min = 0, max = 100000, step = 10,
    tip = 'Seconds the game waits before it fills a region the first time (compared with the performance clock).'})
add({id = 'world.respawn.next', tab = 'world', group = 'Respawn', label = 'Region fill, later (seconds)', off = 0x9CC, min = 0, max = 100000, step = 10,
    tip = 'Seconds the game waits before it fills a region again.'})
for i = 1, 9 do
    local o = 0x830 + (i - 1) * 12
    add({id = 'world.horse.' .. i .. '.base', tab = 'world', group = 'Horse values', label = 'Horse class ' .. i .. ': base', off = o, min = 0, max = 1000000, step = 100,
        tip = 'Value curve of a horse of this class: the game works out a value from the owner\'s level with base, linear and quadratic parts.'})
    add({id = 'world.horse.' .. i .. '.linear', tab = 'world', group = 'Horse values', label = 'Horse class ' .. i .. ': linear', off = o + 4, min = 0, max = 100000, step = 1,
        tip = 'See base.'})
    add({id = 'world.horse.' .. i .. '.quad', tab = 'world', group = 'Horse values', label = 'Horse class ' .. i .. ': quadratic', off = o + 8, min = 0, max = 1000, step = 0.1,
        tip = 'See base.'})
end

-- the word index (counted from the start of the file) of a field
function M.word(f) return (f.off + 4) / 4 end

return M
