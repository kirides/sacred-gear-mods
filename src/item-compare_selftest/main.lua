-- A self test of the item-compare mod, for runs without a player (use a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=compare -gear-load=N -gear-mods=item-compare,item-compare_selftest
--
-- Opens the inventory, puts a pair of gloves and a ring into the backpack, rests the (real) game cursor on backpack items and on
-- the worn gloves and checks what `ui.hovered_item()` and the mod's comparison say; screenshots show the panel. The savegame's
-- hero should wear gloves and a weapon (the test savegame's woodelf does). Nothing depends on the screen's size: the cursor goes to
-- points in the UI layout, worked out from the inventory's and the equipment window's rectangles and the items' cells. For the ring
-- check a companion that wears two rings is looked for among the hero files (without one the check is skipped).
-- Results: GearAutomation\<instance>\item-compare.json.

if not gear.auto then return end

local A = gear.auto
local ui = gear.ui
local W = gear.world
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0}
local compared = {}         -- item id -> number of blocks the mod made

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('item-compare.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local last_blocks = {}
local verified = {}     -- item id -> the mod's report of the item data against the tooltip text (itemcompare.verify)
gear.on('itemcompare.verify', function(id, report) verified[id] = report end)
gear.emit('itemcompare.verify_on')
gear.on('itemcompare.compared', function(id, n, blocks) compared[id] = n last_blocks[id] = blocks end)

-- Rests the cursor on the layout point (lx, ly) until the game shows a tooltip for an item (or gives up).
local function hover_layout(lx, ly)
    local px, py = A.ui_to_pixels(lx, ly)
    if not px then return nil end
    A.move(px - 6, py - 4)
    gear.wait(0.2)
    A.move(px, py)
    for _ = 1, 20 do
        gear.wait(0.1)
        local it = ui.hovered_item()
        if it then gear.wait(0.7) return ui.hovered_item() end
    end
    return nil
end

-- The backpack's grid: cells of CW x CH layout units, the first row OY below the window's top, the first column at its left edge
-- (calibrated on the game's own inventory window at any screen size: the window's rectangle moves, the cells do not).
local CW, CH, OY = 32, 31, 4

-- The layout point of the middle of a backpack item (an entry of container:items()).
local function backpack_point(it)
    local w = ui.window('UI_WND_INVENTORY')
    if not w then return nil end
    return w.x + w.frame_x + (it.col + it.w / 2) * CW, w.y + w.frame_y + OY + (it.row + it.h / 2) * CH
end

local function hover_backpack(bp, id)
    for _, it in ipairs(bp:items()) do
        if it.id == id then
            local lx, ly = backpack_point(it)
            if not lx then return nil end
            return hover_layout(lx, ly)
        end
    end
    return nil
end

-- A hero file whose hero wears at least two rings (slots 8..11): recruits the candidates one after the other and dismisses those that
-- do not. Returns the companion, or nil and the first one recruited (kept) when none wears two rings.
local function recruit_ring_wearer()
    local first
    for _, f in ipairs(gear.party.hero_files()) do
        print('hero file', f.file, f.name, f.class, f.level)
        local comp = gear.party.recruit_hero(f.file)
        if comp then
            gear.wait(2)
            local rings = 0
            for _, e in ipairs(comp:equipment() or {}) do
                print('companion wears', f.name, e.slot, e.item.type_name, e.item.id)
                if e.slot >= 8 and e.slot <= 11 then rings = rings + 1 end
            end
            if rings >= 2 then
                return comp
            end
            if not first then first = comp else gear.party.dismiss(comp) end
        end
    end
    return nil, first
end

gear.task(function()
    A.wait_for_menu(cfg.timeout_menu)
    if not A.wait_for_game(cfg.timeout_game) then return A.quit(1) end
    gear.wait(3)
    local hero = W.hero()
    local x, y, layer = hero:position()
    local bp = gear.inv.container('backpack')
    local made = {}
    for _, word in ipairs({'Gloves_elve', 'Ring1_Edel'}) do
        local r = gear.data.object_types:search(word, 5)[1]
        if r then
            local s = W.spawn(r.id, x + 50, y + 50, {layer = layer})
            local col, row = bp:free_spot(2, 2)
            if s and col and bp:put(s.id, col, row) then made[#made + 1] = s.id end
        end
    end
    check('test items placed in the backpack', #made == 2, #made)
    A.show_window('UI_WND_INVENTORY', true)
    gear.wait(1)

    local gloves, ring, torch = made[1], made[2], nil
    for _, it in ipairs(bp:items()) do
        if it.category == 'weapon' and not torch then torch = it.id end
    end
    local seen = {}
    for _, id in ipairs({gloves, torch, ring}) do
        local it, tx, ty, tw, th = hover_backpack(bp, id)
        if it then seen[id] = {item = it, rect = {tx, ty, tw, th}} end
        check('the backpack item ' .. tostring(id) .. ' is hovered', it and it.id == id, it and it.id)
    end
    for id, s in pairs(seen) do
        print(('hovered %d %s (%s) tooltip %s'):format(id, tostring(s.item.type_name), s.item.category, table.concat(s.rect, ',')))
    end
    gear.wait(0.5)
    check('gloves compared with the worn gloves (one block)', gloves and compared[gloves] == 1, gloves and compared[gloves])
    check('the torch is compared with the worn bow (one block)', torch and compared[torch] == 1, torch and compared[torch])
    if gloves then
        hover_backpack(bp, gloves)
        gear.wait(0.5)
        A.screenshot('compare-gloves')
    end
    if torch then
        hover_backpack(bp, torch)
        gear.wait(0.5)
        A.screenshot('compare-torch')
    end
    check('the ring is not compared (no ring worn)', ring and compared[ring] == 0, ring and compared[ring])
    -- The panel sits beside the game's tooltip (gear.ui.tooltip_anchor).
    if gloves and ui.tooltip_anchor then
        hover_backpack(bp, gloves)
        local _, tx, ty, tw = ui.hovered_item()
        local ax, ay, side = ui.tooltip_anchor(100, 100)
        check('tooltip_anchor puts a panel beside the hovered tooltip', ax and tx and ((side == 'right' and ax > tx + tw) or (side == 'left' and ax < tx)), side)
    end
    -- The worn gloves in the equipment window: nothing to compare them with. Found from the window's rectangle.
    local worn
    for _, e in ipairs(hero:equipment()) do if e.slot == 4 then worn = e.item.id end end
    local eq = ui.window('UI_WND_EQUIPMENT')
    local wit
    if eq then
        -- the glove slot lies at (48, 162) inside the equipment window
        wit = hover_layout(eq.x + eq.frame_x + 48, eq.y + eq.frame_y + 162)
    end
    check('the worn gloves are hovered in the equipment window', wit and wit.id == worn, wit and wit.id)
    check('the worn gloves are compared with nothing', worn and compared[worn] == 0, worn and compared[worn])
    A.screenshot('compare-worn')
    -- With a companion that wears something: the comparison lists it too.
    if cfg.party and gear.party and gear.party.available() then
        local comp, first = recruit_ring_wearer()
        local any = comp or first
        check('a companion was brought from a hero file', any, any and any.id)
        if any then
            compared[gloves] = nil
            hover_backpack(bp, gloves)
            gear.wait(0.8)
            for _, b in ipairs(last_blocks[gloves] or {}) do
                print('block', b.hero, b.hero_name, b.worn, b.name, b.rows and #b.rows, b.empty)
            end
            A.screenshot('compare-party')
            if comp then
                -- The ring: the hero wears none, the companion two or more: the two weakest are compared.
                compared[ring] = nil
                hover_backpack(bp, ring)
                gear.wait(0.8)
                local rb = last_blocks[ring] or {}
                for _, b in ipairs(rb) do print('ring block', b.hero, b.hero_name, b.worn, b.name, b.rows and #b.rows, b.empty) end
                local mine = 0
                for _, b in ipairs(rb) do if b.hero == comp.id and b.worn then mine = mine + 1 end end
                -- (another companion that wears nothing there may show as an empty block of its own: only this one's are counted)
                check('the ring is compared with two of the rings of the companion', mine == 2, mine .. ' of ' .. #rb .. ' blocks')
                A.screenshot('compare-party-ring')
            else
                print('SKIP the ring check: no hero file wears two rings')
            end
        end
    end
    -- The item data (gear.inv.values / bonus_text): the comparison made from it equals the one made from the tooltip text alone.
    local nverified, nsame, ntied = 0, 0, 0
    for id, report in pairs(verified) do
        for _, r in ipairs(report) do
            nverified = nverified + 1
            if r.same then nsame = nsame + 1 else print('verify differs', id, r.data_rows, '<>', r.text_rows) end
            ntied = ntied + (r.tied_new or 0) + (r.tied_worn or 0)
        end
    end
    check('the item data and the tooltip text give the same rows', nverified > 0 and nsame == nverified, nsame .. '/' .. nverified)
    check('bonus lines are tied to the item data', ntied > 0, ntied)
    -- Moving the cursor off the item hides the tooltip and the panel.
    local sl = ui.screen()
    local px, py = A.ui_to_pixels(sl + 330, 300)
    A.move(px or 500, py or 300)
    gear.wait(0.5)
    check('no hovered item once the cursor left', ui.hovered_item() == nil)
    A.screenshot('compare-off')
    finish()
end)
