-- A self test of the item-compare mod, for runs without a player (use a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=compare -gear-load=N -gear-mods=item-compare,item-compare_selftest
--
-- Opens the inventory, puts a pair of gloves and a ring into the backpack, rests the (real) game cursor on backpack items and on
-- the worn gloves and checks what `ui.hovered_item()` and the mod's comparison say; screenshots show the panel. The savegame's
-- hero should wear gloves and a weapon (the test savegame's woodelf does). Results: GearAutomation\<instance>\item-compare.json.

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
gear.on('itemcompare.compared', function(id, n, blocks) compared[id] = n last_blocks[id] = blocks end)

-- Rests the cursor at client pixel (x, y) until the game shows a tooltip for an item (or gives up).
local function hover_at(x, y)
    A.move(x - 6, y - 4)
    gear.wait(0.2)
    A.move(x, y)
    for _ = 1, 20 do
        gear.wait(0.1)
        local it = ui.hovered_item()
        if it then gear.wait(0.7) return ui.hovered_item() end
    end
    return nil
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

    -- Backpack items by cell: the grid starts at the window's left edge; find each item's pixel by scanning down the first column.
    local seen = {}
    for py = 470, 720, 12 do
        local it, tx, ty, tw, th = hover_at(24, py)
        if it and not seen[it.id] then
            seen[it.id] = {item = it, py = py, rect = {tx, ty, tw, th}}
        end
    end
    local found = 0
    for _ in pairs(seen) do found = found + 1 end
    check('the hovered item is read from the game for backpack items', found >= 4, found)
    for id, s in pairs(seen) do
        print(('hovered %d %s (%s) py=%d tooltip %s'):format(id, tostring(s.item.type_name), s.item.category, s.py, table.concat(s.rect, ',')))
    end
    gear.wait(0.5)
    local gloves, torch, ring = made[1], nil, made[2]
    for id, s in pairs(seen) do
        if s.item.category == 'weapon' then torch = id end
    end
    check('gloves compared with the worn gloves (one block)', gloves and seen[gloves] and compared[gloves] == 1, gloves and compared[gloves])
    check('the torch is compared with the worn bow (one block)', torch and compared[torch] == 1, torch and compared[torch])
    if gloves and seen[gloves] then
        hover_at(24, seen[gloves].py)
        gear.wait(0.5)
        A.screenshot('compare-gloves')
    end
    if torch and seen[torch] then
        hover_at(24, seen[torch].py)
        gear.wait(0.5)
        A.screenshot('compare-torch')
    end
    -- The ring sits in the second column of the first row.
    local rit = hover_at(62, 472)
    check('the ring is hovered', rit and rit.id == ring, rit and rit.id)
    check('the ring is not compared (no ring worn)', ring and compared[ring] == 0, ring and compared[ring])
    -- The worn gloves in the equipment window: nothing to compare them with.
    local worn
    for _, e in ipairs(hero:equipment()) do if e.slot == 4 then worn = e.item.id end end
    local wit = hover_at(1225, 645)
    check('the worn gloves are hovered in the equipment window', wit and wit.id == worn, wit and wit.id)
    check('the worn gloves are compared with nothing', worn and compared[worn] == 0, worn and compared[worn])
    A.screenshot('compare-worn')
    -- With a companion that wears something: the comparison lists it too.
    if cfg.party and gear.party and gear.party.available() then
        local file
        for _, f in ipairs(gear.party.hero_files()) do print('hero file', f.file, f.name, f.class, f.level) file = file or f.file end
        local comp, err = file and gear.party.recruit_hero(file)
        check('a companion was brought from a hero file', comp, err)
        if comp then
            gear.wait(2)
            for _, e in ipairs(comp:equipment() or {}) do print('companion wears', e.slot, e.item.type_name, e.item.id) end
            compared[gloves] = nil
            hover_at(24, seen[gloves].py)
            gear.wait(0.8)
            for _, b in ipairs(last_blocks[gloves] or {}) do
                print('block', b.hero, b.hero_name, b.worn, b.name, b.rows and #b.rows, b.empty)
            end
            A.screenshot('compare-party')
            -- The ring: the hero wears none, the companion three: the two weakest are compared.
            compared[ring] = nil
            hover_at(62, 472)
            gear.wait(0.8)
            local rb = last_blocks[ring] or {}
            for _, b in ipairs(rb) do print('ring block', b.hero, b.hero_name, b.worn, b.name, b.rows and #b.rows, b.empty) end
            check('the ring is compared with two of the three rings of the companion', #rb == 2 and rb[1].hero == comp.id and rb[2].hero == comp.id, #rb)
            A.screenshot('compare-party-ring')
        end
    end
    -- Moving the cursor off the item hides the tooltip and the panel.
    A.move(500, 300)
    gear.wait(0.5)
    check('no hovered item once the cursor left', ui.hovered_item() == nil)
    A.screenshot('compare-off')
    finish()
end)
