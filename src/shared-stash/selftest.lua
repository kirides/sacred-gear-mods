-- Self test (needs -gear-auto and config.selftest): 'deposit', 'withdraw' or 'ui'. config.selftest_slot is the savegame
-- to load (default 1). Results go to GearAutomation\<instance>\sharedstash.json.
return function(M, stash, transfer)
    local cfg = gear.config
    local inv = gear.inv
    local out = {phase = cfg.selftest, ok = true, notes = {}}
    local function note(s) out.notes[#out.notes + 1] = s end
    local function check(cond, what)
        if not cond then out.ok = false note('FAILED: ' .. what) else note('ok: ' .. what) end
    end
    local function finish()
        gear.auto.write('sharedstash.json', gear.json.encode(out))
        gear.auto.quit(out.ok and 0 or 1)
    end

    gear.task(function()
        gear.auto.wait_for_menu(60)
        gear.auto.load_save(cfg.selftest_slot or 1)
        if not gear.auto.wait_for_game(120) then check(false, 'game loaded') return finish() end
        gear.wait(3)
        local bp = inv.container('backpack')
        check(bp ~= nil, 'backpack container')

        if cfg.selftest == 'deposit' then
            local before = #stash.items()
            local want, exports = {'weapon', 'armor', 'jewelry', 'shield'}, {}
            local moved = 0
            for _, cat in ipairs(want) do
                for _, it in ipairs(bp:items()) do
                    if it.category == cat and transfer.transferable(it) then
                        local b = inv.export(it.id)
                        local ok, err = transfer.deposit(bp, it)
                        check(ok, 'deposit ' .. transfer.pretty_name(it) .. ' ' .. tostring(err))
                        if ok then
                            moved = moved + 1
                            exports[#exports + 1] = inv.hex(b)
                            check(gear.world.item(it.id) == nil, 'item object gone after deposit')
                        end
                        break
                    end
                end
            end
            check(#stash.items() == before + moved and moved > 0, 'stash count ' .. #stash.items())
            local f = gear.read('stash.json')
            check(f and #f > 0, 'stash.json written')
            -- a quest item / gold must be refused
            note('backpack after: ' .. #bp:items())

        elseif cfg.selftest == 'withdraw' then
            local entries = {}
            for _, e in ipairs(stash.items()) do entries[#entries + 1] = e end
            check(#entries > 0, 'stash has entries from the deposit run')
            local before = #bp:items()
            for _, e in ipairs(entries) do
                local ok, where = transfer.withdraw(e)
                check(ok, 'withdraw ' .. e.name .. ' ' .. tostring(where))
                if ok then
                    -- find the item and compare its export with the stored one
                    local found
                    for _, it in ipairs(bp:items()) do
                        if inv.hex(inv.export(it.id)) == e.data then found = true break end
                    end
                    check(found, 'identical item in backpack: ' .. e.name)
                end
            end
            check(#bp:items() == before + #entries, 'backpack grew by ' .. #entries)
            check(#stash.items() == 0, 'stash empty')

        elseif cfg.selftest == 'sockets' or cfg.selftest == 'filled' then
            -- 'sockets': fills the free sockets of backpack items with the backpack's runes (the engine's own socket
            -- call), then deposits those items. 'filled': deposits the items that already hold a rune.
            local function info(b)
                local n = b:byte(5) + 256 * b:byte(6)
                local rec = 6 + n * 130
                local caps = 0
                for i = 0, 7 do if b:byte(rec + 0x0C + i + 1) ~= 0 then caps = caps + 1 end end
                return caps, n, b:sub(rec + 1, rec + 130)
            end
            local targets, runes = {}, {}
            for _, it in ipairs(bp:items()) do
                local b = inv.export(it.id)
                local caps, n = info(b)
                if it.category == 'rune' then runes[#runes + 1] = it
                elseif (cfg.selftest == 'sockets' and caps > n) or (cfg.selftest == 'filled' and n > 0) then
                    targets[#targets + 1] = {it = it, caps = caps, n = n}
                end
            end
            note(('targets %d, runes %d'):format(#targets, #runes))
            check(#targets > 0, 'there are items to work on')
            for _, t in ipairs(targets) do
                local it = t.it
                local before = inv.export(it.id)
                if cfg.selftest == 'sockets' then
                    for k = t.n + 1, t.caps do
                        local rune = table.remove(runes)
                        if not rune then note('no rune left for ' .. it.type_name) break end
                        local okt = bp:take(rune.id)
                        local ok, err = inv.socket(it.id, rune.id)
                        check(okt and ok, ('socket %s into %s: %s'):format(rune.type_name, it.type_name, tostring(err)))
                    end
                    local after = inv.export(it.id)
                    local _, n2, rec2 = info(after)
                    local _, _, rec1 = info(before)
                    check(n2 > t.n, it.type_name .. ' has ' .. n2 .. ' entries now')
                    check(rec2 ~= rec1, it.type_name .. ' record (bonuses) changed by the socketing')
                end
                local expected = inv.hex(inv.export(it.id))
                local ok, err = transfer.deposit(bp, it)
                check(ok, 'deposit ' .. it.type_name .. ' ' .. tostring(err))
                local stored
                for _, e in ipairs(stash.items()) do if e.data == expected then stored = true end end
                check(stored, 'the stash holds the exact export of ' .. it.type_name)
                out.deposited = out.deposited or {}
                out.deposited[#out.deposited + 1] = {name = it.type_name, bytes = #expected / 2}
            end

        elseif cfg.selftest == 'stress' then
            -- The user's crash: chest open, stash open, items moved back and forth. Deposits several items, opens the
            -- stash and moves items between it and the backpack for `cfg.stress_seconds`, noting how the object ids move.
            local picked = 0
            for _, it in ipairs(bp:items()) do
                if picked < 8 and transfer.transferable(it) and it.category ~= 'rune' then
                    if transfer.deposit(bp, it) then picked = picked + 1 end
                end
            end
            check(picked >= 4, 'stashed ' .. picked .. ' items')
            gear.auto.show_window('UI_WND_CHEST', true)
            gear.wait(1)
            local function panel_of(key)
                for _, p in ipairs(gear.ui.panels()) do if p.key == key then return p end end
            end
            local op = panel_of('shared-stash:open')
            if op then gear.auto.ui_click(op.x + 80, op.y + 34) end
            gear.wait(1)
            local t0, cycles, fails, maxid = gear.time(), 0, 0, 0
            local lastid = 0
            while gear.time() - t0 < (cfg.stress_seconds or 60) do
                local e = stash.items()[1]
                if e then
                    local ok, where = transfer.withdraw(e)
                    if not ok then fails = fails + 1 note('withdraw failed: ' .. tostring(where)) end
                end
                gear.wait(0.3)
                local list = bp:items()
                local it = list[#list]
                if it then
                    local ok = transfer.deposit(bp, it)
                    if not ok then fails = fails + 1 end
                    lastid = it.id
                    if it.id > maxid then maxid = it.id end
                end
                cycles = cycles + 1
                gear.wait(0.3)
            end
            note(('cycles %d, failures %d, highest item id seen %d, last %d, stash %d'):format(cycles, fails, maxid, lastid, #stash.items()))
            check(fails == 0, 'no failed transfers')
            gear.auto.screenshot('stress-end')

        elseif cfg.selftest == 'net' then
            -- The guards in a (simulated) network game: the world stays closed (spawn, temporary items), the inventory is
            -- open for the hero's own backpack and the chest only, through the engine's announcing calls. Nothing is
            -- really changed here: the flag is only set for the checks.
            local before = #bp:items()
            check(gear.world.can_change(), 'single player: world changes allowed')
            gear.auto.network_flag(true)
            local can_world = gear.world.can_change()
            local can_inv, network = gear.inv.can_change()
            local other = gear.inv.container(5)
            local item = bp:items()[1]
            local bytes = inv.export(item.id)
            local okp, errp = pcall(function() return gear.world.spawn('BOW_LONG.GRN', 0, 0) end)
            local tip_ok, tip_err = gear.ui.item_tooltip(bytes, 100, 100)
            local oth_id, oth_err
            if other then oth_id, oth_err = inv.add(other, bytes) end
            gear.auto.network_flag(false)
            check(can_world == false, 'network game: world changes refused')
            check(can_inv == true and network == true, 'network game: the inventory may be changed (announced)')
            check(tip_ok == nil, 'network game: no temporary item for a tooltip: ' .. tostring(tip_err))
            check(oth_id == nil, 'network game: another container is refused: ' .. tostring(oth_err))
            check(#bp:items() == before, 'nothing changed')
            check(gear.world.can_change(), 'flag cleared: changes allowed again')

        elseif cfg.selftest == 'ui' or cfg.selftest == 'chest' then
            -- 'chest': the stash exists only while the chest window is open. 'ui': screenshots of the open stash and of
            -- the tooltips of its first stash and backpack cells.
            local function panel_of(key)
                for _, p in ipairs(gear.ui.panels()) do if p.key == key then return p end end
            end
            local function click_button()
                local p = panel_of('shared-stash:open')
                if not p then return false end
                gear.auto.ui_click(p.x + 80, p.y + 34)
                gear.wait(1)
                return true
            end
            local function stash_open() return gear.ui.panel_open('stash') and panel_of('shared-stash:stash') ~= nil end
            gear.wait(1)
            check(not panel_of('shared-stash:open'), 'no button while the chest window is closed')
            check(not stash_open(), 'no stash panel while the chest window is closed')
            if cfg.selftest == 'chest' then
                gear.auto.press('f10')
                gear.wait(1)
                check(not stash_open(), 'F10 does not open the stash')
                local ok, why = transfer.deposit(bp, bp:items()[1])
                check(not ok and why == 'open a chest first', 'deposit refused without a chest: ' .. tostring(why))
            end
            check(gear.auto.show_window('UI_WND_CHEST', true), 'chest window shown')
            gear.wait(1.5)
            local cw = gear.ui.window('UI_WND_CHEST')
            out.chest_window = cw and gear.json.encode({x = cw.x, y = cw.y, w = cw.width, h = cw.height, visible = cw.visible, drawn = cw.drawn})
            check(cw and cw.drawn, 'chest window is drawn')
            check(panel_of('shared-stash:open') ~= nil, 'the button shows with the chest window open')
            gear.auto.screenshot('chest-open')
            check(click_button(), 'clicked the button')
            check(stash_open(), 'the stash panel opens from the button')
            gear.auto.screenshot('chest-stash')
            if cfg.selftest == 'chest' then
                local ok, err = transfer.deposit(bp, bp:items()[1])
                check(ok, 'deposit works with the chest open: ' .. tostring(err))
                gear.auto.show_window('UI_WND_CHEST', false)
                gear.wait(1)
                check(not stash_open(), 'the stash closes with the chest window')
                check(not panel_of('shared-stash:open'), 'the button goes with the chest window')
                local it2 = bp:items()[1]
                local ok2, why2 = transfer.deposit(bp, it2)
                check(not ok2 and why2 == 'open a chest first', 'deposit refused after the chest closed: ' .. tostring(why2))
                local e = stash.items()[1]
                local ok3, why3 = transfer.withdraw(e)
                check(not ok3 and why3 == 'open a chest first', 'withdraw refused after the chest closed: ' .. tostring(why3))
                -- reopening does not bring the panel back by itself
                gear.auto.show_window('UI_WND_CHEST', true)
                gear.wait(1)
                check(not stash_open(), 'the stash stays closed when the chest opens again')
            else
                local panel = panel_of('shared-stash:stash')
                if panel then
                    out.panel = gear.json.encode({x = panel.x, y = panel.y, w = panel.w, h = panel.h})
                    local gx, gy = panel.x + 8, panel.y + 24 + 22 + 2
                    local function hover(name, lx, ly)
                        local px, py = gear.auto.ui_to_pixels(lx, ly)
                        gear.auto.move(px, py)
                        gear.wait(1.5)
                        gear.auto.screenshot(name)
                    end
                    hover('stash-tip-stash', gx + 16, gy + 16)
                    hover('stash-tip-backpack', gx + 16, gy + 6 * 32 + 8 + 22 + 16)
                end
            end
        end
        finish()
    end)
end
