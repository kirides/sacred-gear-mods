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

        elseif cfg.selftest == 'ui' then
            M.view.force_open = true
            M.view.force_button = true
            local cw = gear.ui.window('UI_WND_CHEST')
            out.chest_window = cw and gear.json.encode({x = cw.x, y = cw.y, w = cw.width, h = cw.height, visible = cw.visible, drawn = cw.drawn, bounds = cw.bounds})
            M.say('Axe put into the stash')
            gear.wait(2)
            gear.auto.screenshot('stash-panel')
            -- hover the cells: a stash item (the first cell of the stash grid), then a backpack item
            local panel
            for _, p in ipairs(gear.ui.panels()) do if p.key == 'shared-stash:stash' then panel = p end end
            local keys = {}
            for _, p in ipairs(gear.ui.panels()) do keys[#keys + 1] = p.key .. ' movable=' .. tostring(p.draggable ~= false) end
            out.panel_keys = keys
            if panel then
                out.panel = gear.json.encode({x = panel.x, y = panel.y, w = panel.w, h = panel.h})
                local gx, gy = panel.x + 8, panel.y + 24 + 22 + 2
                local function hover(name, lx, ly)
                    local px, py = gear.auto.ui_to_pixels(lx, ly)
                    gear.auto.move(px, py)
                    gear.wait(1.5)
                    gear.auto.screenshot(name)
                    out['tip_' .. name] = tostring(M.view.tip_ok) .. ' ' .. tostring(M.view.tip_err)
                end
                hover('stash-tip-stash', gx + 16, gy + 16)
                hover('stash-tip-backpack', gx + 16, gy + 6 * 32 + 8 + 22 + 16)
            end
        end
        finish()
    end)
end
