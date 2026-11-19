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
--     that are the same stat are one row, and the panel shows the difference of the numbers, in the line's own shape
--     ("Physical resistance: +4%"). A line only one of them has counts the other as 0. The labels are the game's own (its words in
--     the game's language); the few lines it skips, such as the price and the level, are found by the game's text ids.
--   * Which lines are the same stat: for the item's bonus slots (magic, rare and unique properties, rune and socket bonuses) the
--     item's own data decides (`gear.inv.values`, `gear.inv.bonus_text`), the rest is matched by words: see compare.lua.
--   * Party: with companions (gear.party) the same is done for every hero that can wear the item.
--
-- Limits: the game's "expected damage / protection" lines are computed for the hero the player controls, so for the other
-- party members those two lines are left out. A two-handed weapon against a worn shield (and the reverse) is compared with the
-- weapon only. Ranges (damage 22-25) are compared by their middle.

local ui = gear.ui
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

gear.events.declare('itemcompare.verify_on', {
    description = 'Asks the mod to check each comparison against one made from the tooltip text alone and to emit itemcompare.verify (for tests).',
})
gear.events.declare('itemcompare.verify', {
    description = 'After a comparison, when itemcompare.verify_on was emitted or the setting verify_data is on: (item id, report): one entry per compared worn item {worn, same = the rows equal those made from the tooltip text alone, data_rows, text_rows, tied_new, tied_worn = lines tied to the item data}.',
})
gear.events.declare('itemcompare.compared', {
    description = 'The comparison of the hovered item was made: (item id, number of blocks, blocks): blocks are {hero = hero id, hero_name, worn = item id, name, rows} (a hero with nothing worn there: empty = true).',
})

local compare = require('compare').compare

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

local force_verify = false     -- a test asked for the check (itemcompare.verify_on)
gear.on('itemcompare.verify_on', function() force_verify = true end)

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
        local verify = force_verify or setting('verify_data', false)
        local blocks, report = compare(item, verify)
        hover = {id = item.id, blocks = blocks, at = clock}
        if not keep then
            gear.emit('itemcompare.compared', item.id, #blocks, blocks)
            if verify then gear.emit('itemcompare.verify', item.id, report) end
        end
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
        if ui.tooltip_anchor then
            -- flush against the game's tooltip, corner ornaments touching; on its left near the screen's edge
            dx, dy = ui.tooltip_anchor(w, h)
            dx, dy = dx or last_dx, dy or last_dy
        else
            dx = hover.x + hover.w + 6 + OVER
            if dx + w + OVER > sr - 2 then dx = hover.x - w - 6 - OVER end
            dx = math.max(sl + 2 + OVER, math.min(dx, sr - w - 2 - OVER))
            dy = math.max(st + 2 + OVER, math.min(hover.y, sb - h - 2 - OVER))
        end
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
