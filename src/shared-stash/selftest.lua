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
            check(#stash.recent() >= #entries, 'recent withdrawals kept')

        elseif cfg.selftest == 'ui' then
            M.view.force_open = true
            M.say('Axe put into the stash')
            gear.wait(2)
            gear.auto.screenshot('stash-panel')
        end
        finish()
    end)
end
