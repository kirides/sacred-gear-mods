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
        if cfg.selftest == 'e2e' then
            -- A real Closed Net game (gear/examples/closedtest drives the menus into a loopback game server with shared_stash.lua).
            local A, remote, kind = gear.auto, require('remote'), require('kind')
            local touched = {}
            local read0, save0 = gear.read, gear.save
            gear.read = function(name, ...) touched[#touched + 1] = 'read ' .. tostring(name) return read0(name, ...) end
            gear.save = function(name, ...) touched[#touched + 1] = 'save ' .. tostring(name) return save0(name, ...) end
            local said = {}
            remote.notify = function(text, ok) said[#said + 1] = (ok and 'ok: ' or 'no: ') .. text note('notice ' .. said[#said]) end
            local function until_(fn, seconds)
                local t0 = gear.time()
                while not fn() and gear.time() - t0 < seconds do gear.wait(0.5) end
                return fn()
            end
            check(A.wait_for_game(400), 'the Closed Net world loaded')
            gear.wait(8)
            check(gear.mp.mode() == 'closed', "gear.mp.mode() reads closed (" .. tostring(gear.mp.mode()) .. ')')
            remote.refresh(true)
            check(until_(function() return remote.available() == true end, 15), 'the server says it keeps the stash')
            check(kind.closed(), 'kind.closed()')
            local bp = inv.container('backpack')
            check(bp ~= nil, 'backpack')
            local before = #bp:items()
            local it
            for _, cand in ipairs(bp:items()) do if transfer.transferable(cand) then it = cand break end end
            check(it ~= nil, 'a transferable item (' .. before .. ' in the backpack)')
            if it then
                local ok, err = remote.deposit(bp, it, transfer.entry_fields(it))
                check(ok, 'deposit sent: ' .. tostring(err))
                check(until_(function() return not remote.busy() end, 60), 'the deposit was answered')
                check(#bp:items() == before - 1, 'the item is out of the backpack')
                remote.refresh(true)
                check(until_(function() return #remote.entries == 1 end, 15), 'the server lists one entry')
                local e = remote.entries[1]
                if e then
                    local ok2, err2 = remote.withdraw(e)
                    check(ok2, 'withdraw sent: ' .. tostring(err2))
                    check(until_(function() return not remote.busy() end, 60), 'the withdrawal was confirmed')
                    check(#bp:items() == before, 'the item is back in the backpack')
                    remote.refresh(true)
                    check(until_(function() return #remote.entries == 0 end, 15), 'the server stash is empty again')
                end
            end
            local n = 0
            for _, s in ipairs(touched) do if s:find('stash', 1, true) then n = n + 1 end end
            check(n == 0, 'no access to stash files during the whole run (' .. table.concat(touched, ', ') .. ')')
            gear.read, gear.save = read0, save0
            note(table.concat(said, ' | '))
            return finish()
        end
        gear.auto.wait_for_menu(120)
        if cfg.selftest == 'lan' or cfg.selftest == 'lanui' then
            -- Hosts a LAN game through the menus (as gear/examples/lanhosttest does): the game starts GameServer.exe and
            -- the hero joins it as a client, so this process is a network game.
            local A = gear.auto
            local function px(x, y) return (x - 200) / 1.1719, y / 1.1719 end
            gear.wait(8)
            A.ui_click(512, 352)                    -- Multiplayer
            gear.wait(2)
            A.ui_click(512, 352 - 38 / 1.1719)      -- LAN
            gear.wait(3)
            A.ui_click(px(820, 400))                -- a hero
            gear.wait(2)
            A.ui_click(px(910, 838))                -- Weiter
            gear.wait(3)
            A.ui_click(px(553, 448))                -- Erstellen
            gear.wait(3)
            A.ui_click(px(747, 448))                -- Erstellen: starts the gameserver and connects
            if not A.wait_for_game(120) then
                A.screenshot('lan-no-game')
                check(false, 'the hosted game started')
                return finish()
            end
            gear.wait(8)
            A.screenshot('lan-in-game')
        else
            gear.auto.load_save(cfg.selftest_slot or 1)
            if not gear.auto.wait_for_game(120) then check(false, 'game loaded') return finish() end
            gear.wait(3)
        end
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

        elseif cfg.selftest == 'lanui' then
            -- In a hosted LAN game: the stash grid with real icons and the game's own tooltip for a stashed item next to the
            -- tooltip of the same item in the backpack, then a minute of hovering with the panel open.
            local network = select(2, gear.inv.can_change())
            check(network == true, 'this is a network game')
            local picked = 0
            for _, it in ipairs(bp:items()) do
                if picked < 6 and transfer.transferable(it) and it.category ~= 'rune' and it.category ~= 'potion' then
                    if transfer.deposit(bp, it) then picked = picked + 1 end
                end
            end
            check(picked >= 3, 'stashed ' .. picked .. ' items')
            gear.auto.show_window('UI_WND_CHEST', true)
            gear.wait(1)
            local function panel_of(key)
                for _, p in ipairs(gear.ui.panels()) do if p.key == key then return p end end
            end
            local op = panel_of('shared-stash:open')
            if op then gear.auto.ui_click(op.x + 80, op.y + 34) end
            gear.wait(1.5)
            local panel = panel_of('shared-stash:stash')
            check(panel ~= nil, 'the stash panel is open')
            if panel then
                local gx, gy = panel.x + 8, panel.y + 24 + 22 + 2
                local function hover(name, lx, ly)
                    local px, py = gear.auto.ui_to_pixels(lx, ly)
                    gear.auto.move(px, py)
                    gear.wait(1.5)
                    gear.auto.screenshot(name)
                end
                hover('lan-tip-stash', gx + 16, gy + 16)
                hover('lan-tip-backpack', gx + 16, gy + 6 * 32 + 8 + 22 + 16)
                -- a minute of hovering over the cells, the panel open
                local t0, n = gear.time(), 0
                while gear.time() - t0 < (cfg.lan_hover_seconds or 45) do
                    local col, row = n % 6, math.floor(n / 6) % 3
                    local px, py = gear.auto.ui_to_pixels(gx + 16 + col * 32, gy + 16 + row * 32)
                    gear.auto.move(px, py)
                    gear.wait(0.15)
                    n = n + 1
                end
                note('hover moves: ' .. n)
            end
            check(gear.world.hero() ~= nil, 'the hero is still there')
            gear.auto.screenshot('lan-ui-end')

        elseif cfg.selftest == 'lan' then
            -- In a hosted LAN game (network flag set by the engine): the stash through the engine's announcing calls.
            local can, network = gear.inv.can_change()
            check(network == true, 'this is a network game')
            check(can == true, 'the inventory may be changed in a network game')
            check(gear.world.can_change() == false, 'the world stays closed')
            check(#bp:items() > 0, 'backpack has ' .. #bp:items() .. ' items')
            local before = #bp:items()
            local list = {}
            for _, it in ipairs(bp:items()) do
                if transfer.transferable(it) and it.category ~= 'rune' and #list < 3 then list[#list + 1] = it end
            end
            local sent = {}
            for _, it in ipairs(list) do
                local b = inv.export(it.id)
                local ok, err = transfer.deposit(bp, it)
                check(ok, 'deposit ' .. it.type_name .. ' ' .. tostring(err))
                sent[#sent + 1] = inv.hex(b)
                gear.wait(0.5)
            end
            check(#stash.items() == #list, 'stash holds ' .. #stash.items())
            gear.wait(2)
            local entries = {}
            for _, e in ipairs(stash.items()) do entries[#entries + 1] = e end
            for _, e in ipairs(entries) do
                local ok, where = transfer.withdraw(e)
                check(ok, 'withdraw ' .. e.name .. ' ' .. tostring(where))
                gear.wait(0.5)
                local found
                for _, it in ipairs(bp:items()) do
                    if inv.hex(inv.export(it.id)) == e.data then found = true break end
                end
                check(found, 'identical item back in the backpack: ' .. e.name)
            end
            check(#stash.items() == 0, 'stash empty again')
            check(#bp:items() == before, 'backpack has the same number of items again: ' .. #bp:items())
            -- back and forth for a while, as the user did
            local t0, fails = gear.time(), 0
            for i = 1, (cfg.lan_cycles or 20) do
                local l2 = bp:items()
                local it = l2[#l2]
                local okd = transfer.deposit(bp, it)
                gear.wait(0.2)
                local e = stash.items()[1]
                local okw = e and transfer.withdraw(e)
                gear.wait(0.2)
                if not (okd and okw) then fails = fails + 1 end
            end
            check(fails == 0, 'back and forth: ' .. (cfg.lan_cycles or 20) .. ' cycles, ' .. fails .. ' failures')
            check(#bp:items() == before and #stash.items() == 0, 'counts unchanged after the cycles')
            gear.auto.screenshot('lan-end')

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

        elseif cfg.selftest == 'gating' then
            -- The kind of game decides where the stash lives. In Closed Net nothing may touch stash.json (no read, no write, no
            -- local deposit or withdrawal, no panel path) and a server without the stash channel gives "not available".
            -- Single player stands in for the game; the flags gear.mp.mode() reads are set with gear.auto.network_mode.
            local A, remote = gear.auto, require('remote')
            local touched = {}
            local read0, save0 = gear.read, gear.save
            gear.read = function(name, ...) touched[#touched + 1] = 'read ' .. tostring(name) return read0(name, ...) end
            gear.save = function(name, ...) touched[#touched + 1] = 'save ' .. tostring(name) return save0(name, ...) end
            local function stash_touched()
                local n = 0
                for _, s in ipairs(touched) do if s:find('stash', 1, true) then n = n + 1 end end
                return n
            end
            for _, m in ipairs({'lan', 'open', 'closed', 'single'}) do
                check(A.network_mode(m) == true and gear.mp.mode() == m, 'gear.mp.mode() reads ' .. m)
            end
            check(gear.mp.mode() == 'single', 'single player reads single')
            -- default-deny: the Internet menu with nothing proven reads closed; a hero delivered by the server too
            check(A.network_mode('internet') and gear.mp.mode() == 'closed', 'the Internet menu without proof reads closed')
            check(A.network_mode('open') and gear.mp.mode() == 'open', 'Open Net proven reads open')
            A.hero_from_server(true)
            check(gear.mp.mode() == 'closed', 'a hero from the server reads closed even if everything else says open')
            A.hero_from_server(false)
            check(gear.mp.mode() == 'open', 'no hero from the server: open again')
            check(A.network_mode('lan') and gear.mp.mode() == 'lan', 'the LAN menu reads lan')
            A.network_mode('single')
            local before = #bp:items()
            local it
            for _, cand in ipairs(bp:items()) do if transfer.transferable(cand) then it = cand break end end
            check(it ~= nil, 'a transferable item')

            -- Closed Net
            check(A.network_mode('closed'), 'closed set')
            touched = {}
            check(stash.closed(), 'stash.closed() in Closed Net')
            check(#stash.items() == 0, 'the local stash shows nothing in Closed Net')
            stash.load()
            check(stash.add({name = 'x', data = '00'}, 10) == nil, 'stash.add refused in Closed Net')
            check(stash.remove(1) == nil, 'stash.remove refused in Closed Net')
            local ok, err = transfer.deposit(bp, it)
            check(not ok and tostring(err):find('Closed Net', 1, true), 'local deposit refused: ' .. tostring(err))
            local wok, werr = transfer.withdraw({uid = 1, data = string.rep('00', 40), name = 'x'})
            check(not wok and tostring(werr):find('Closed Net', 1, true), 'local withdraw refused: ' .. tostring(werr))
            check(#bp:items() == before, 'the backpack did not change')
            -- no server channel here: the stash is "not available", never local
            local avail, why = remote.available()
            check(avail == false, 'no server stash without a server: ' .. tostring(why))
            local rok, rerr = remote.deposit(bp, it, transfer.entry_fields(it))
            check(not rok and tostring(rerr):find('not available', 1, true), 'remote deposit refused: ' .. tostring(rerr))
            check(#bp:items() == before, 'the item stayed in the backpack')
            -- the panel with the chest open
            gear.auto.show_window('UI_WND_CHEST', true)
            gear.wait(1)
            local bp_panel
            for _, p in ipairs(gear.ui.panels()) do if p.key == 'shared-stash:open' then bp_panel = p end end
            check(bp_panel ~= nil, 'the button shows')
            if bp_panel then A.ui_click(bp_panel.x + 80, bp_panel.y + 34) end
            gear.wait(2)
            check(gear.ui.panel_open('stash'), 'the panel is open')
            A.screenshot('gating-closed')
            check(stash_touched() == 0, 'no access to stash files in Closed Net (' .. table.concat(touched, ', ') .. ')')
            A.network_mode('single')
            gear.auto.show_window('UI_WND_CHEST', false)

            -- the server says it keeps the stash (info closed = true) while the engine's flags say 'open': closed all the same
            touched = {}
            A.network_mode('open')
            require('kind').server_closed = true
            check(stash.closed(), 'a server that keeps the stash makes it Closed Net whatever the flags say')
            check(#stash.items() == 0 and stash.add({name = 'x', data = '00'}, 10) == nil, 'and the local stash is dead')
            check(stash_touched() == 0, 'no stash file access then')
            require('kind').reset()
            A.network_mode('single')

            -- outside Closed Net the same code reads the file
            touched = {}
            check(stash.closed() == false, 'not closed again')
            local n = #stash.items()
            check(stash_touched() >= 1, 'the local stash reads its file in single player (' .. table.concat(touched, ', ') .. ')')
            A.network_mode('lan')
            check(not stash.closed(), 'LAN keeps the local stash')
            A.network_mode('open')
            check(not stash.closed(), 'Open Net keeps the local stash')
            A.network_mode('single')
            gear.read, gear.save = read0, save0
            note('stash items ' .. n)

        elseif cfg.selftest == 'remote' then
            -- remote.lua (the Closed Net client) against a fake server in Lua: the real inventory calls, the messages of the
            -- server's script (info, list, entry/listed, deposit/result, withdraw/release, collected). Single player stands in.
            local server_entries, queue, nextid, refuse = {}, {}, 1, false
            local handler
            local fake = {
                on = function(_, fn) handler = fn return fn end,
                transport = function() return 'custom' end,
                send = function(_, msg) queue[#queue + 1] = msg return true end,
            }
            local remote = require('remote')
            remote.use_channel(fake)
            local said = {}
            remote.notify = function(text, ok) said[#said + 1] = (ok and 'ok: ' or 'no: ') .. text end
            local function reply(m) handler(nil, m) end
            local function pump()
                while #queue > 0 do
                    local msg = table.remove(queue, 1)
                    if msg.op == 'info' then reply({op = 'info', closed = true, count = #server_entries, max = 200})
                    elseif msg.op == 'list' then
                        reply({op = 'info', closed = true, count = #server_entries, max = 200})
                        for _, e in ipairs(server_entries) do reply({op = 'entry', id = e.id, data = e.data, name = e.name, w = e.w, h = e.h}) end
                        reply({op = 'listed', count = #server_entries})
                    elseif msg.op == 'deposit' then
                        if refuse then reply({op = 'result', rid = msg.rid, ok = false, err = 'your hero could not be saved (test)'})
                        else
                            local e = {id = nextid, data = msg.data, name = msg.name, w = msg.w, h = msg.h}
                            nextid = nextid + 1
                            server_entries[#server_entries + 1] = e
                            reply({op = 'result', rid = msg.rid, ok = true, id = e.id, count = #server_entries})
                        end
                    elseif msg.op == 'withdraw' then
                        for _, e in ipairs(server_entries) do
                            if e.id == msg.id then reply({op = 'release', rid = msg.rid, id = e.id, data = e.data}) end
                        end
                    elseif msg.op == 'collected' then
                        for i, e in ipairs(server_entries) do
                            if e.id == msg.rid_entry or true then end
                        end
                        server_entries = {}   -- one entry in this test
                        reply({op = 'collected', rid = msg.rid, ok = true, count = 0})
                    elseif msg.op == 'abort' then reply({op = 'result', rid = msg.rid, ok = true, aborted = true}) end
                end
            end
            remote.refresh(true) pump()
            check(remote.available() == true, 'the server said it keeps the stash')
            check(require('kind').server_closed, "its info made the stash 'closed' for the mod")
            local before = #bp:items()
            local it
            for _, cand in ipairs(bp:items()) do if transfer.transferable(cand) then it = cand break end end
            check(it ~= nil, 'a transferable item')
            -- a refused deposit gives the item back
            refuse = true
            local ok, err = remote.deposit(bp, it, transfer.entry_fields(it))
            check(ok, 'deposit sent: ' .. tostring(err))
            check(#bp:items() == before - 1, 'the item left the backpack while the server decides')
            pump()
            check(#bp:items() == before, 'a refused deposit gives the item back (' .. tostring(said[#said]) .. ')')
            check(not remote.busy(), 'nothing pending after the refusal')
            -- an accepted one (the item given back is a new object)
            refuse = false
            for _, cand in ipairs(bp:items()) do if transfer.transferable(cand) then it = cand break end end
            ok, err = remote.deposit(bp, it, transfer.entry_fields(it))
            check(ok, 'deposit sent again')
            pump()
            check(#bp:items() == before - 1 and #server_entries == 1, 'accepted: the item is on the server only')
            check(#remote.entries == 1 and remote.count == 1, 'the list shows it')
            check(not remote.busy(), 'nothing pending after the answer')
            -- withdraw
            if not remote.entries[1] then check(false, 'an entry to withdraw') return finish() end
            ok, err = remote.withdraw(remote.entries[1])
            check(ok, 'withdraw sent: ' .. tostring(err))
            pump()
            check(#bp:items() == before, 'the item is in the backpack again')
            check(#server_entries == 0 and #remote.entries == 0, 'the server entry is gone after the confirmation')
            check(not remote.busy(), 'nothing pending at the end')
            note(table.concat(said, ' | '))
            remote.use_channel(nil)
            remote.reset()
            check(not require('kind').server_closed, 'reset forgets what the server said')

        elseif cfg.selftest == 'noinst' then
            -- 1000 tooltips of exports and several seconds of stash icons with the panel open, then a real item is still made fine
            -- (single player only: the probe makes a real item).
            local function probe()
                local bytes = inv.export(bp:items()[1].id)
                local id = inv.create(bytes)
                if id then inv.destroy(id) end
                return id
            end
            local a = probe()
            local items = bp:items()
            local texts = 0
            for i = 1, 1000 do
                local it = items[(i % #items) + 1]
                if gear.ui.item_tooltip_text(inv.export(it.id)) then texts = texts + 1 end
            end
            local b = probe()
            check(texts == 1000, '1000 tooltips from exports')
            note(('next item id before %s, after the tooltips %s (the game itself creates objects meanwhile, so this only shows it works)'):format(tostring(a), tostring(b)))
            local picked = 0
            for _, it in ipairs(bp:items()) do
                if picked < 8 and transfer.transferable(it) and it.category ~= 'rune' then
                    if transfer.deposit(bp, it) then picked = picked + 1 end
                end
            end
            gear.auto.show_window('UI_WND_CHEST', true)
            gear.wait(1)
            local op
            for _, p in ipairs(gear.ui.panels()) do if p.key == 'shared-stash:open' then op = p end end
            if op then gear.auto.ui_click(op.x + 80, op.y + 34) end
            gear.wait(6)
            local c = probe()
            note('next item id after 6 s of stash icons ' .. tostring(c))
            check(c ~= nil, 'the game is still creating items normally')
            gear.auto.screenshot('noinst-end')

        elseif cfg.selftest == 'tipcmp' then
            -- The tooltip words of a live item against those of a scratch item (made from its export, never registered),
            -- twice (the price must not change), for every item of the backpack; socketed items included.
            local same, diff, errs = 0, 0, 0
            local examples = {}
            local items = bp:items()
            for _, it in ipairs(items) do
                local live, e1 = gear.ui.item_tooltip_text(it.id)
                local bytes = inv.export(it.id)
                local s1, e2 = gear.ui.item_tooltip_text(bytes)
                local s2 = gear.ui.item_tooltip_text(bytes)
                if not live or not s1 then
                    errs = errs + 1
                    note('error ' .. it.type_name .. ': ' .. tostring(e1 or e2))
                elseif live == s1 and s1 == s2 then
                    same = same + 1
                else
                    diff = diff + 1
                    if #examples < 3 then examples[#examples + 1] = {it.type_name, live, s1, s2} end
                end
            end
            out.examples = examples
            note(('items %d: identical %d, different %d, errors %d'):format(#items, same, diff, errs))
            check(errs == 0, 'every tooltip could be read')
            check(diff == 0, 'scratch tooltips equal the live ones')

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
