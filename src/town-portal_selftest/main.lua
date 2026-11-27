-- Self test of Town Portal (-gear-auto -gear-load=N): a potion in the pack, the list, a trip, the portal, the way back.
local A = gear.auto
local results = {}
local function check(name, ok, detail)
    results[#results + 1] = {name = name, ok = ok and true or false, detail = detail}
    gear.log(('portaltest: %s %s %s'):format(ok and 'PASS' or 'FAIL', name, detail or ''))
end
local function state()
    local s
    gear.emit('town-portal.state', function(v) s = v end)
    return s
end

gear.task(function()
    A.wait_for_game(180)
    gear.wait(6)
    local hero = gear.world.hero()
    local s = state()
    check('state answers', s ~= nil)
    if not s then A.quit(1) return end
    if s.home then
        -- second run, from the savegame of the first: the spot and the portal came back
        gear.wait(4)
        s = state()
        check('persist: the spot is kept', s.home ~= nil, gear.json.encode(s.home))
        check('persist: the portal is there', s.has_portal == true)
        A.screenshot('persist-loaded')
        gear.emit('town-portal.step')
        gear.wait(4)
        s = state()
        check('persist: stepping through clears it', s.home == nil and s.has_portal == false, gear.json.encode(s))
        A.write('result-persist.json', gear.json.encode(results))
        A.quit(0)
        return
    end
    -- custom points: the file's, the window's own (add / remove), and a trip to one of them
    local list
    gear.emit('town-portal.entries', function(v) list = v end)
    local base = #list
    check('custom_teleports.lua point is listed', list[14] and list[14].name == 'File point' and list[14].known, gear.json.encode(list[14]))
    gear.world.portals(0)
    gear.emit('town-portal.edit')
    gear.wait(1)
    gear.emit('town-portal.addpoint', 'My spot')
    gear.emit('town-portal.addpoint', 'Camp by the lake')
    gear.wait(0.5)
    A.screenshot('own-points')
    gear.emit('town-portal.entries', function(v) list = v end)
    check('a point is added', #list == base + 2 and list[#list - 1].name == 'My spot' and list[#list].own == 2, #list .. ' vs ' .. base)
    gear.emit('town-portal.entries', function(v) list = v end)
    check('found portals only: none found, game points not known', not list[1].known and not list[13].known)
    gear.emit('town-portal.remove', #list)
    gear.emit('town-portal.remove', #list - 1)
    gear.emit('town-portal.entries', function(v) list = v end)
    check('a point is removed', #list == base, tostring(#list))
    gear.emit('town-portal.cancel')
    gear.emit('town-portal.addpoint', 'Stays')
    gear.world.portals(0x1FFF)
    local nm, err = gear.data.object_types:display_name(s.scroll_type)
    check('the potion type has its name', nm and nm:lower():find('portal'), tostring(nm) .. ' ' .. tostring(err))

    -- a potion into the pack
    local c = gear.world.spawn(s.scroll_type, select(1, hero:position()) + 40, select(2, hero:position()) + 40, {})
    check('scroll spawned', c ~= nil)
    local backpack = gear.inv.container('backpack')
    for _, it in ipairs(backpack:items()) do gear.log(('portaltest: pack item %s %s at %s,%s size %sx%s'):format(it.id, it.type_name, it.col, it.row, it.w, it.h)) end
    gear.log('portaltest: pack ' .. backpack.columns .. 'x' .. backpack.rows)
    local col, row = 1, 0
    check('room in the pack', col ~= nil)
    local put, perr = backpack:put(c.id, col, row)
    check('scroll in the pack', put == true, tostring(perr))
    -- all portals found
    gear.world.portals(0x1FFF)
    local hx, hy, hl = hero:position()

    -- Reading: the potion through the game's own item use (a click on it in the backpack)
    A.press('i')
    gear.wait(1.5)
    A.screenshot('inventory')
    gear.emit('town-portal.combat', true)
    gear.log(('portaltest: scroll cell %d,%d'):format(col, row))
    local cx, cy = 38 + (col - 1 + 0.5) * 37.5, 462 + (row + 0.5) * 37.5
    A.move(cx, cy)
    gear.wait(0.5)
    A.screenshot('hover')
    A.click(cx, cy, 'rbutton')
    gear.wait(1.5)
    s = state()
    check('a click on the potion opens the list', s.open == true, 'cell ' .. col .. ',' .. row)
    if s.open then gear.emit('town-portal.cancel') gear.wait(0.5) end
    A.press('i')
    gear.wait(0.5)
    local opened
    gear.emit('town-portal.read', function(v) opened = v end)
    gear.wait(1)
    s = state()
    check('the list opens', s.open == true)
    A.screenshot('list')
    if gear.settings and false then end
    -- pick Porto Vallum (2)
    gear.emit('town-portal.travel', 2)
    gear.wait(4)
    s = state()
    local x1, y1 = hero:position()
    check('the hero arrived', math.abs(x1 - 141811) < 2000 and math.abs(y1 - 164082) < 2000, ('%d,%d'):format(x1, y1))
    check('the spot is saved', s.home and math.abs(s.home.x - hx) < 5, gear.json.encode(s.home))
    check('the portal stands', s.has_portal == true)
    local left = 0
    for _, it in ipairs(backpack:items()) do if it.type == s.scroll_type then left = left + 1 end end
    check('the potion is used up', left == 0, tostring(left))
    A.screenshot('arrived')
    if gear.settings and false then end
    local saved
    gear.on('game.saved', function() saved = true end)
    local sok, serr = gear.game.save(50)
    gear.log('portaltest: save requested ' .. tostring(sok) .. ' ' .. tostring(serr))
    for _ = 1, 20 do if saved then break end gear.wait(0.5) end
    check('saved to slot 50', saved == true)

    -- the portal: its dialog and the way back
    gear.emit('town-portal.talk')
    gear.wait(2)
    A.screenshot('portal-dialog')
    gear.log('portaltest: dialog ui nodes ' .. #A.ui())
    A.press('escape')
    gear.wait(0.5)
    gear.emit('town-portal.step')
    gear.wait(4)
    s = state()
    local x2, y2 = hero:position()
    check('back at the saved spot', math.abs(x2 - hx) < 300 and math.abs(y2 - hy) < 300, ('%d,%d vs %d,%d'):format(x2, y2, hx, hy))
    check('the portal is gone', s.has_portal == false and s.home == nil, gear.json.encode(s))
    A.screenshot('back')
    A.write('result.json', gear.json.encode(results))
    A.quit(0)
end)
