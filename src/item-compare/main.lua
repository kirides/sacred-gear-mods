-- Item comparison: while the cursor (the mouse's or the controller's pad cursor) rests on an item, a panel beside the game's
-- own tooltip shows what the item changes compared with what the hero wears in that slot, in green (better) and red (worse).
--
-- How it works
--   * Which item: Gear's `ui.hovered_item()`: the item whose tooltip the game shows now, whichever window shows it (backpack,
--     chest, shop, the equipment window). It is the same for the mouse and the pad cursor: nothing to press.
--   * Which slot: `creature:equip_slot(item)`, the engine's own rule (rings 8..11, amulets 6..7, the others one slot each).
--     Something must be worn there; with several worn rings or amulets the two weakest are compared.
--   * The numbers: the TOOLTIP TEXT of both items (`ui.item_tooltip_text`), the words the player sees. Every line is cut into the
--     words and the numbers in it ("Physical resistance: +14%" -> words + [14]); a line of the new item and a line of the worn item
--     with the same words are one stat, and the panel shows the difference of the numbers, in the line's own shape
--     ("Physical resistance: +4%"). A line only one of them has counts the other as 0. This needs no knowledge of the item
--     records, works in every language (the words are only compared with each other; the few labels it skips, such as the price
--     and the level, are the game's own texts by id) and includes set, unique and rune bonuses, because the tooltip does.
--   * Party: with companions (gear.party) the same is done for every hero that can wear the item.
--
-- Limits: the game's "expected damage / protection" lines are computed for the hero the player controls, so for the other
-- party members those two lines are left out. A two-handed weapon against a worn shield (and the reverse) is compared with the
-- weapon only. Ranges (damage 22-25) are compared by their middle.

local ui = gear.ui
local W = gear.world
local guard = gear.guard

local function setting(id, fallback)
    local v = gear.settings.get(id, fallback)
    if v == nil then return fallback end
    return v
end

local GREEN, RED, DIM, TEXT = 0xFF66DD70, 0xFFF26B6B, 0xFFA9A9B4, 0xFFE6E6E6
local SIZE, ROW = 12, 15
-- The panel's frame is the game's own tooltip frame (gear.ui.native.frame; the plain rectangle where an older Sacred Gear lacks it).
-- The text keeps PAD from the bars' outer edge; the corner ornaments reach OVER units beyond the frame's box.
local NATIVE = ui.native ~= nil
local PAD = NATIVE and 12 or 7
local OVER = 12

gear.events.declare('itemcompare.compared', {
    description = 'The comparison of the hovered item was made: (item id, number of blocks, blocks): blocks are {hero = hero id, hero_name, worn = item id, name, rows} (a hero with nothing worn there: empty = true).',
})

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

-- The comparable lines of an item's tooltip, the item's name (its first line) and the name's colour.
local function read_item(item)
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
    return {lines = lines, name = name ~= '' and name or tostring(item.type_name), color = color or TEXT, power = power}
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

local function read_cached(item)
    local c = tooltip_cache[item.id]
    if c == nil then
        c = read_item(item) or false
        tooltip_cache[item.id] = c
    end
    return c or nil
end

-- The blocks to show for `item`: one per worn item it would replace: {hero, hero_name, worn, name, color, rows, same}.
local function compare(item)
    tooltip_cache = {}
    local blocks = {}
    if not item or not EQUIPMENT[item.category] then return blocks end
    local new = read_cached(item)
    if not new then return blocks end
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
                    blocks[#blocks + 1] = {hero = hero.id, hero_name = hname, worn = c.item.id, name = c.read.name,
                        color = c.read.color, rows = rows}
                end
            end
        end
    end
    return blocks
end

---------------------------------------------------------------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------------------------------------------------------------

local width_cache, width_count = {}, 0

local function text_width(s)
    local w = width_cache[s]
    if not w then
        w = ui.text_size(s, {size = SIZE}) or (#s * 6)
        if width_count > 4000 then width_cache, width_count = {}, 0 end
        width_cache[s] = w
        width_count = width_count + 1
    end
    return w
end

local SEG_COLOR = {good = GREEN, bad = RED, dim = DIM}

-- The size of the panel for blocks, and a function that draws it at (x, y).
local function layout(blocks)
    local w = 150
    local h = PAD
    local items = {}
    for _, b in ipairs(blocks) do
        local title
        if b.empty then
            title = b.hero_name .. ': nothing worn there'
            items[#items + 1] = {kind = 'title', text = title, color = DIM}
            w = math.max(w, text_width(title) + 2 * PAD)
            h = h + ROW
        else
            title = (b.hero_name and (b.hero_name .. ': ') or 'Worn: ') .. b.name
            items[#items + 1] = {kind = 'title', text = title, color = b.color}
            w = math.max(w, text_width(title) + 2 * PAD)
            h = h + ROW
            if #b.rows == 0 then
                items[#items + 1] = {kind = 'note', text = 'the same stats', color = DIM}
                h = h + ROW
            end
            for _, row in ipairs(b.rows) do
                local rw = 0
                for _, seg in ipairs(row.segs) do rw = rw + text_width(seg[1]) end
                w = math.max(w, rw + 2 * PAD + 8)
                items[#items + 1] = {kind = 'row', row = row}
                h = h + ROW
            end
        end
        h = h + 4
    end
    return math.min(w, 420), h + PAD - 4, items
end

local function draw_items(x, y, w, h, items)
    if NATIVE then
        ui.native.frame(x, y, w, h, {layer = 'top'})
    else
        ui.rect(x, y, w, h, 0xE6100D0A, {layer = 'top'})
        ui.frame(x, y, w, h, 0xFF6B5A3A, 1, {layer = 'top'})
    end
    local cy = y + PAD
    for i, it in ipairs(items) do
        if it.kind == 'title' then
            if i > 1 then
                ui.rect(x + 4, cy - 3, w - 8, 1, 0x40FFFFFF, {layer = 'top'})
                cy = cy + 1
            end
            ui.text(it.text, x + PAD, cy, {size = SIZE, layer = 'top', color = it.color, shadow = true})
        elseif it.kind == 'note' then
            ui.text(it.text, x + PAD + 6, cy, {size = SIZE, layer = 'top', color = it.color})
        else
            local cx = x + PAD + 6
            for _, seg in ipairs(it.row.segs) do
                ui.text(seg[1], cx, cy, {size = SIZE, layer = 'top', color = SEG_COLOR[seg[2]] or TEXT})
                cx = cx + text_width(seg[1])
            end
        end
        cy = cy + ROW
        if it.kind ~= 'title' and (not items[i + 1] or items[i + 1].kind == 'title') then cy = cy + 4 end
    end
end

---------------------------------------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------------------------------------

local hover = nil           -- {id, x, y, w, h, blocks, at}
local clock = 0
local last_dx, last_dy = 330, 120

local function enabled() return setting('enabled', true) end

gear.on('frame', guard('frame', function(dt)
    clock = clock + (type(dt) == 'number' and dt or 0)
    if not enabled() then hover = nil return end
    local item, x, y, w, h = ui.hovered_item()
    if not item then hover = nil return end
    if not hover or hover.id ~= item.id or clock - hover.at > 0.5 then
        local keep = hover and hover.id == item.id
        local blocks = compare(item)
        hover = {id = item.id, blocks = blocks, at = clock}
        if not keep then gear.emit('itemcompare.compared', item.id, #blocks, blocks) end
    end
    hover.x, hover.y, hover.w, hover.h = x, y, w, h
end))

local function sample_blocks()
    return {{hero_name = nil, name = 'Worn item', color = TEXT, rows = {
        {segs = {{'Armor: ', false}, {'+3', 'good'}}}, {segs = {{'Resistance: ', false}, {'-2', 'bad'}, {'%', false}}}}}}
end

gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' or state.mode ~= 'game' or state.exclusive or state.escape_menu or state.message_box then return end
    local edit = ui.edit_mode and ui.edit_mode()
    local follow = setting('placement', 'tooltip') == 'tooltip'
    local blocks
    if hover and #hover.blocks > 0 then
        blocks = hover.blocks
    elseif edit then
        blocks = sample_blocks()
    else
        -- nothing to show; keep the panel registered while the layout editor could ask for it
        return
    end
    local w, h, items = layout(blocks)
    local sl, st, sr, sb = ui.screen()
    local dx, dy = last_dx, last_dy
    if follow and hover and hover.w and not edit then
        dx = hover.x + hover.w + 6 + OVER
        if dx + w + OVER > sr - 2 then dx = hover.x - w - 6 - OVER end
        dx = math.max(sl + 2 + OVER, math.min(dx, sr - w - 2 - OVER))
        dy = math.max(st + 2 + OVER, math.min(hover.y, sb - h - 2 - OVER))
    end
    local p = ui.panel('compare', 'Item comparison', dx, dy, w, h, {bare = true, min_width = w, min_height = h})
    if not p.open then return end
    local x, y = dx, dy
    if not follow or edit then x, y = p.x, p.y; last_dx, last_dy = x, y end
    draw_items(x, y, w, h, items)
end))

gear.keys.on('toggle', guard('key', function()
    local on = not enabled()
    gear.settings.set('enabled', on)
    if gear.toast then pcall(gear.toast.show, on and 'Item comparison on' or 'Item comparison off') end
end))

gear.on('party.control', guard('party', function() hover = nil end))
gear.on('settings.changed', guard('settings', function() hover = nil end))
