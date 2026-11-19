-- The reading and comparing half of the item comparison (no drawing; main.lua shows the result): an item's tooltip text is cut into
-- lines of words and numbers, two items are set against each other, and compare(item) returns the blocks to show for the hovered item:
-- one per worn item it would replace, for each hero of the party that can wear it (see the header of main.lua for how it works).
--
-- Where the numbers come from: the tooltip text of both items gives the lines (labels and numbers as the game shows them). For the
-- item's bonus slots the item's own data decides which lines are the same stat in two items (gear.inv.values: code, attribute and
-- type of each slot; gear.inv.bonus_text: the game's own line for the slot, found among the tooltip's lines), so the match does not
-- depend on the wording; the number of such a line is the stored value. Every other line (the protection icons, damage, attack, the
-- movement speed, set bonuses, the "expected" lines of the controlled hero: values the game computes or derives) is matched by its
-- words with the numbers cut out, as is every line on a Sacred Gear without the item data functions.

local ui = gear.ui
local W = gear.world

local TEXT = 0xFFE6E6E6          -- the default colour of an item's name (the same as TEXT in main.lua)

local function setting(id, fallback)
    local v = gear.settings.get(id, fallback)
    if v == nil then return fallback end
    return v
end

---------------------------------------------------------------------------------------------------------------------------------
-- Reading a tooltip
---------------------------------------------------------------------------------------------------------------------------------

-- The game's own words for the lines the comparison leaves out (text ids are the same in every language): the price, the level,
-- the requirements ("Minimum ...") and the two "expected" lines that belong to the hero the player controls.
local SKIP_IDS = {1055, 9067, 1070, 1108}
local EXPECTED_IDS = {1176, 1177}

local function label_of(id)
    local t = gear.text.get(id)
    if not t then return nil end
    t = t:gsub('\\[cw]%x%x%x%x%x%x%x%x', ''):gsub('^%s+', ''):gsub('[:%s]+$', ''):lower()
    return t ~= '' and t or nil
end

local skip_labels, expected_labels

local function load_labels()
    skip_labels, expected_labels = {}, {}
    for _, id in ipairs(SKIP_IDS) do skip_labels[#skip_labels + 1] = label_of(id) end
    for _, id in ipairs(EXPECTED_IDS) do expected_labels[#expected_labels + 1] = label_of(id) end
end

local function starts_with_label(plain, labels)
    local low = plain:lower()
    for _, l in ipairs(labels) do
        if l and low:sub(1, #l) == l then return true end
    end
    return false
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

-- Cuts a line at its numbers: pieces[i] is the text before number i (pieces[#nums + 1] the text after the last one), nums[i] its value:
-- a decimal comma or point is read, a sign directly before the number is applied (and left out of the piece), and a range such as
-- 22-25 counts as its middle.
local function split_numbers(s)
    local pieces, nums = {}, {}
    local pos = 1
    while true do
        local a, b = s:find('%d+', pos)
        if not a then break end
        local dec = s:match('^[%.,]%d+', b + 1)
        if dec then b = b + #dec end
        local value = tonumber((s:sub(a, b):gsub(',', '.')))
        local before = s:sub(pos, a - 1)
        local stripped = before:match('^(.-)%s*$')
        local last = stripped:sub(-1)
        local sign = 1
        if last == '+' or last == '-' then
            if last == '-' then sign = -1 end
            before = stripped:sub(1, -2)
        end
        local a2, b2, second = s:find('^%s*%-%s*(%d+[%.,]?%d*)', b + 1)
        if a2 then
            value = (value + (tonumber((second:gsub(',', '.'):gsub('%.$', ''))) or 0)) / 2
            b = b2
        end
        pieces[#pieces + 1] = before
        nums[#nums + 1] = sign * (value or 0)
        pos = b + 1
    end
    pieces[#pieces + 1] = s:sub(pos)
    return pieces, nums
end
-- One tooltip line: markup removed (`\cAARRGGBB` colour, `\wAARRGGBB` wave colour, `\gAARRGGBB` + 8 characters an inline image),
-- cut at its numbers: pieces[i] is the text before number i, nums[i] its value (sign applied, a range such as 22-25 as its middle).
local function parse_line(raw, index)
    local L = {raw = raw}
    L.color = raw:match('\\c(%x%x%x%x%x%x%x%x)')
    local s = raw:gsub('\\c%x%x%x%x%x%x%x%x', ''):gsub('\\w%x%x%x%x%x%x%x%x', '')
    local ids = {}
    s = s:gsub('\\g%x%x%x%x%x%x%x%x(........)', function(id)
        ids[#ids + 1] = trim(id)
        return string.char(15 + math.min(#ids, 15))
    end)
    L.plain = trim((s:gsub('[\16-\31]', '')))
    local pieces, nums = split_numbers(s)

    -- The key: the words and image ids with the numbers taken out; the display pieces show an image as a bullet.
    local key, display = {}, {}
    for i, p in ipairs(pieces) do
        key[i] = p:gsub('[\16-\31]', function(c) return '<' .. (ids[c:byte() - 15] or '') .. '>' end):gsub('%s+', ' ')
        display[i] = (p:gsub('[\16-\31]', ' \226\128\162 '):gsub('%s+', ' '))
    end
    L.expected = starts_with_label(L.plain, expected_labels)
    if L.expected then
        -- the icons of the "expected" lines say which resistances count: they differ between two items, the line is the same stat
        for i, p in ipairs(key) do key[i] = (p:gsub('<[^>]*>', '')) end
    end
    L.key = table.concat(key, '#'):lower()
    L.pieces, L.nums = display, nums
    L.skip = index == 1 or #nums == 0 or L.color == 'ffffffff' or starts_with_label(L.plain, skip_labels)
        or L.plain:find('%d+%s*/%s*%d+') ~= nil
    return L
end

-- Ties the tooltip lines that are bonus slots of the item to the item's data: such a line gets the key of its bonus (code, attribute,
-- type: the same in every language) and, when its number is the stored value, that value. Returns how many were tied.
local function attach_data(item, lines)
    local inv = gear.inv
    if not (inv and inv.values and inv.bonus_text) then return 0 end
    local v = inv.values(item.id)
    if not v then return 0 end
    local all = {}
    for _, b in ipairs(v.bonuses) do all[#all + 1] = b end
    for _, e in ipairs(v.entries) do
        if e.active then for _, b in ipairs(e.bonuses) do all[#all + 1] = b end end
    end
    local tied = 0
    for _, b in ipairs(all) do
        local t = inv.bonus_text(item.id, b.entry, b.slot)
        t = t and trim(t)
        if t and t ~= '' then
            for _, L in ipairs(lines) do
                if not L.data and trim(L.raw) == t then
                    L.data = b
                    L.key = ('bonus:%d:%d:%x'):format(b.code, b.attribute, b.flags)
                    if #L.nums == 1 and math.abs(L.nums[1]) == math.abs(b.value) then
                        L.nums[1] = b.value
                        L.exact = true
                    end
                    tied = tied + 1
                    break
                end
            end
        end
    end
    return tied
end

-- The comparable lines of an item's tooltip, the item's name (its first line) and the name's colour. `text_only`: no item data.
local function read_item(item, text_only)
    if not skip_labels then load_labels() end
    local text = ui.item_tooltip_text(item)
    if type(text) ~= 'string' then return nil end
    local lines, name, color = {}, nil, nil
    local power = 0
    for raw in text:gmatch('[^\r\n]+') do
        local L = parse_line(raw, #lines + 1)
        if #lines == 0 then
            name = L.plain
            color = tonumber('FF' .. (raw:match('\\c%x%x(%x%x%x%x%x%x)') or 'E6E6E6'), 16)
        end
        if not L.skip then
            for _, v in ipairs(L.nums) do power = power + v end
        end
        lines[#lines + 1] = L
    end
    local tied = text_only and 0 or attach_data(item, lines)
    return {lines = lines, name = name ~= '' and name or select(2, pcall(function() return gear.data.object_types:label(item.type) end)) or tostring(item.type_name), color = color or TEXT, power = power, tied = tied}
end

---------------------------------------------------------------------------------------------------------------------------------
-- The difference of two items
---------------------------------------------------------------------------------------------------------------------------------

local function fmt_delta(d)
    local r = math.floor(d + 0.5)
    if math.abs(d - r) < 0.005 then return ('%+d'):format(r) end
    return ('%+.1f'):format(d)
end

-- A row of the panel: the line's words and numbers with each number replaced by its change, as {text, good = bool|nil} segments.
local function make_row(L, deltas)
    local nonzero, good = false, nil
    for _, d in ipairs(deltas) do
        if math.abs(d) > 0.004 then
            nonzero = true
            if good == nil then good = d > 0 end
        end
    end
    if not nonzero then return nil end
    local segs = {}
    for i, piece in ipairs(L.pieces) do
        if i > 1 and piece ~= '' then
            segs[#segs + 1] = {piece, false}
        elseif i == 1 and piece ~= '' then
            segs[#segs + 1] = {piece, false}
        end
        if i <= #deltas then
            local d = deltas[i]
            segs[#segs + 1] = {fmt_delta(d), math.abs(d) > 0.004 and (d > 0 and 'good' or 'bad') or 'dim'}
        end
    end
    return {segs = segs, good = good}
end

-- The rows for item `new` against item `old` (both from read_item); `with_expected` keeps the two "expected" lines.
local function diff(new, old, with_expected)
    local rows = {}
    local omap, used = {}, {}
    local count = {}
    for _, O in ipairs(old.lines) do
        if not O.skip and (with_expected or not O.expected) then
            count[O.key] = (count[O.key] or 0) + 1
            omap[O.key .. '\0' .. count[O.key]] = O
        end
    end
    count = {}
    for _, L in ipairs(new.lines) do
        if not L.skip and (with_expected or not L.expected) then
            count[L.key] = (count[L.key] or 0) + 1
            local k = L.key .. '\0' .. count[L.key]
            local O = omap[k]
            used[k] = true
            local deltas = {}
            for i, v in ipairs(L.nums) do deltas[i] = v - (O and O.nums[i] or 0) end
            local row = make_row(L, deltas)
            if row then rows[#rows + 1] = row end
        end
    end
    count = {}
    for _, O in ipairs(old.lines) do
        if not O.skip and (with_expected or not O.expected) then
            count[O.key] = (count[O.key] or 0) + 1
            if not used[O.key .. '\0' .. count[O.key]] then
                local deltas = {}
                for i, v in ipairs(O.nums) do deltas[i] = -v end
                local row = make_row(O, deltas)
                if row then rows[#rows + 1] = row end
            end
        end
    end
    return rows
end

---------------------------------------------------------------------------------------------------------------------------------
-- Which items to compare with
---------------------------------------------------------------------------------------------------------------------------------

local EQUIPMENT = {weapon = true, armor = true, shield = true, jewelry = true}

-- The slots an item of group-first-slot `slot` can sit in: rings use 8..11, amulets 6 and 7.
local function group(slot)
    if slot == 6 or slot == 7 then return {6, 7} end
    if slot >= 8 and slot <= 11 then return {8, 9, 10, 11} end
    return {slot}
end

local function can_wear(hero, item)
    if not item.classes or #item.classes == 0 then return true end
    local class = hero:class()
    if not class then return true end
    for _, c in ipairs(item.classes) do
        if c == class then return true end
    end
    return false
end

local function party_heroes()
    local lead = W.hero()
    if not lead then return {} end
    local list = {lead}
    if setting('companions', true) and gear.party and gear.party.available() then
        local ok, all = pcall(gear.party.heroes)
        if ok and all then
            list = {}
            for _, h in ipairs(all) do list[#list + 1] = h end
            -- the controlled hero first
            table.sort(list, function(a, b) return (a.id == lead.id and 0 or 1) < (b.id == lead.id and 0 or 1) end)
        end
    end
    return list, lead
end

local tooltip_cache = {}

local function read_cached(item, text_only)
    local k = text_only and -item.id or item.id
    local c = tooltip_cache[k]
    if c == nil then
        c = read_item(item, text_only) or false
        tooltip_cache[k] = c
    end
    return c or nil
end

-- The rows of a block as text, for comparing the two ways of reading.
local function rows_text(rows)
    local out = {}
    for _, row in ipairs(rows) do
        local parts = {}
        for _, seg in ipairs(row.segs) do parts[#parts + 1] = seg[1] end
        out[#out + 1] = table.concat(parts)
    end
    table.sort(out)
    return table.concat(out, '|')
end

-- The blocks to show for `item`: one per worn item it would replace: {hero, hero_name, worn, name, color, rows, same}. With `verify`
-- a second result: one report per compared worn item, {worn, same = the rows equal those made from the tooltip text alone,
-- data_rows, text_rows, tied_new, tied_worn = lines tied to the item data}.
local function compare(item, verify)
    tooltip_cache = {}
    local blocks, report = {}, {}
    if not item or not EQUIPMENT[item.category] then return blocks, report end
    local new = read_cached(item)
    if not new then return blocks, report end
    local heroes, lead = party_heroes()
    local many = #heroes > 1
    local limit = setting('max_blocks', 4)
    for _, hero in ipairs(heroes) do
        if #blocks >= limit then break end
        local primary = lead and hero.id == lead.id
        local slot = can_wear(hero, item) and hero:equip_slot(item) or nil
        local worn = slot and hero:equipment() or nil
        if slot and worn then
            local by_slot, already = {}, false
            for _, e in ipairs(worn) do
                by_slot[e.slot] = e.item
                if e.item.id == item.id then already = true end
            end
            if not already then
                local cands = {}
                for _, s in ipairs(group(slot)) do
                    local e = by_slot[s]
                    if e then
                        local read = read_cached(e)
                        if read then cands[#cands + 1] = {item = e, read = read, slot = s} end
                    end
                end
                table.sort(cands, function(a, b) return a.read.power < b.read.power end)
                local hname = many and (hero:name() or ('Hero ' .. hero.id)) or nil
                if #cands == 0 and not primary then
                    blocks[#blocks + 1] = {hero = hero.id, hero_name = hname, empty = true}
                end
                for i = 1, math.min(#cands, 2) do
                    if #blocks >= limit then break end
                    local c = cands[i]
                    local rows = diff(new, c.read, primary)
                    if verify then
                        local alt = diff(read_cached(item, true), read_cached(c.item, true), primary)
                        report[#report + 1] = {worn = c.item.id, same = rows_text(rows) == rows_text(alt),
                            data_rows = rows_text(rows), text_rows = rows_text(alt), tied_new = new.tied, tied_worn = c.read.tied}
                    end
                    blocks[#blocks + 1] = {hero = hero.id, hero_name = hname, worn = c.item.id, name = c.read.name,
                        color = c.read.color, rows = rows}
                end
            end
        end
    end
    return blocks, report
end

return {compare = compare}
