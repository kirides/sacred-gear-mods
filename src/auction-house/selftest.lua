-- Self test (needs -gear-auto and config.selftest in gear_mods.json):
--   'sp'   loads savegame config.selftest_slot (default 1); the market runs in this game.
--   'lan'  hosts a LAN game through the menus (the hero at config.hero_x / hero_y of the LAN hero list, 1600x900
--          screenshot pixels); the host's own requests and the market's answers go through gear.mp.send with
--          gear.mp.force_network(true), so out through the real chat carrier and back.
-- Both: deposit gold, sell a backpack item, browse finds it with the seller's name, the panel draws every tab
-- (a screenshot of each), cancel, collect the item back byte-identical, withdraw the gold, check the hero's gold.
-- Delete market.json and journal.json in this folder before a run. Results: GearAutomation\<instance>\auction.json.
return function(M)
    local cfg = gear.config
    local inv, A = gear.inv, gear.auto
    local client, panel = M.client, M.panel
    local mode = cfg.selftest
    local out = {mode = mode, ok = true, notes = {}, timings = {}}
    local function note(s)
        out.notes[#out.notes + 1] = s
        print(s)
    end
    local function check(cond, what)
        if not cond then out.ok = false note('FAILED: ' .. what) else note('ok: ' .. what) end
        return cond
    end
    local function finish()
        if mode == 'lan' and gear.mp and gear.mp.force_network then gear.mp.force_network(false) end
        if M.via_channel then M.via_channel(false) end
        out.draw_errors = out.draw_errors or {}
        A.write('auction.json', gear.json.encode(out))
        A.quit(out.ok and 0 or 1)
    end

    -- Every draw of the panel goes through pcall here: a Lua error in any tab is counted and kept.
    local draws, errors = {}, {}
    local real_panel = panel.panel
    panel.panel = function(c, conf)
        local tab = panel.view.tab
        local ok, err = pcall(real_panel, c, conf)
        draws[tab] = (draws[tab] or 0) + 1
        if not ok then
            errors[#errors + 1] = tab .. ': ' .. tostring(err)
            if #errors <= 5 then gear.log('auction selftest: panel error in ' .. tab .. ': ' .. tostring(err)) end
        end
    end

    -- Runs fn(cb) and waits for cb(...) up to `timeout` seconds: returns true and cb's arguments, or false.
    local function await(label, timeout, fn)
        local done, res = false, nil
        local t0 = gear.time()
        fn(function(...) done, res = true, {...} end)
        local got = gear.wait_until(function() return done end, timeout)
        out.timings[#out.timings + 1] = ('%s %.2f s'):format(label, gear.time() - t0)
        if not got then note(label .. ': no answer in ' .. timeout .. ' s') return false end
        return true, unpack(res)
    end

    local function bp_has(hex)
        local bp = inv.container('backpack')
        for _, it in ipairs(bp and bp:items() or {}) do
            local b = inv.export(it.id)
            if b and inv.hex(b) == hex then return it end
        end
    end

    local function host_lan()
        local function px(x, y) return (x - 200) / 1.1719, y / 1.1719 end
        gear.wait(8)
        A.ui_click(512, 352)                    -- Multiplayer
        gear.wait(2)
        A.ui_click(512, 352 - 38 / 1.1719)      -- LAN
        gear.wait(3)
        A.ui_click(px(cfg.hero_x or 820, cfg.hero_y or 400))
        gear.wait(2)
        A.ui_click(px(910, 838))                -- next
        gear.wait(3)
        A.ui_click(px(553, 448))                -- create
        gear.wait(3)
        A.ui_click(px(747, 448))                -- create: the game starts its gameserver and connects to it
        -- the dialog turns into "join game" with Starten at the same place once the server is up: press it until in game
        for _ = 1, 8 do
            gear.wait(5)
            if A.wait_for_game(1) then return end
            A.ui_click(px(747, 448))            -- Starten
            if A.wait_for_game(10) then return end
        end
    end

    gear.task(function()
        A.wait_for_menu(120)
        if mode == 'lan' then
            host_lan()
            if not A.wait_for_game(240) then
                A.screenshot('ah-lan-no-game')
                check(false, 'the hosted LAN game started')
                return finish()
            end
            gear.wait(8)
            local mp = gear.mp
            -- (mp.active() means "more than one player": false while the host is alone)
            local network = select(2, gear.inv.can_change())
            check(network == true and mp.is_host(), 'a network game, this game is the host (slot ' .. tostring(mp.local_slot()) .. ')')
            mp.force_network(true)
            M.via_channel(true)
            out.channel_before = mp._channel and mp._channel.received or 0
        else
            A.load_save(cfg.selftest_slot or 1)
            if not A.wait_for_game(120) then check(false, 'game loaded') return finish() end
            gear.wait(3)
        end
        local hero = gear.world.hero()
        local bp = inv.container('backpack')
        if not check(hero ~= nil and bp ~= nil, 'hero and backpack') then return finish() end
        local me = client:me()
        out.me = me
        note(('hero %s (%s)'):format(tostring(me.name), tostring(me.key)))

        -- the market answers the hello
        local online = gear.wait_until(function() return client:online() end, 30)
        if not check(online, 'the market answers (info)') then return finish() end
        check(client:wallet() == 0, 'the wallet starts empty: ' .. tostring(client:wallet()))

        -- 1. deposit
        local g0 = hero:gold()
        out.gold_start = g0
        local DEP = math.min(1000, g0)
        check(DEP >= 100, 'the hero carries gold: ' .. tostring(g0))
        local got, ok, err = await('deposit', 30, function(cb) client:deposit(DEP, cb) end)
        check(got and ok, ('deposit %d: %s'):format(DEP, tostring(err)))
        check(hero:gold() == g0 - DEP, ('hero gold %d -> %d'):format(g0, hero:gold()))
        check(client:wallet() == DEP, 'wallet ' .. tostring(client:wallet()))

        -- 2. sell an item of the backpack
        local pick
        for _, it in ipairs(bp:items()) do
            if panel.sellable(it, false) and (it.category == 'weapon' or it.category == 'armor' or it.category == 'shield'
                or it.category == 'jewelry') then pick = it break end
        end
        if not pick then
            for _, it in ipairs(bp:items()) do if panel.sellable(it, false) then pick = it break end end
        end
        if not check(pick ~= nil, 'a sellable backpack item') then return finish() end
        local hex = inv.hex(inv.export(pick.id))
        local meta = panel.meta_of(pick)
        out.item = {name = meta.name, level = meta.level, category = pick.category, quality = pick.quality, bytes = #hex / 2}
        local count0 = #bp:items()
        local PRICE, DAYS = 1234, 1
        local wallet0 = client:wallet()
        got, ok, err = await('sell', 30, function(cb) client:sell(bp, pick, meta, PRICE, DAYS, cb) end)
        check(got and ok, 'sell ' .. meta.name .. ': ' .. tostring(err))
        check(#bp:items() == count0 - 1 and not bp_has(hex), 'the item left the backpack')
        local fee = wallet0 - client:wallet()
        out.fee = fee
        check(fee >= 1, 'the listing fee was paid: ' .. tostring(fee))
        local listing
        for _, e in ipairs(client.journal.entries) do
            if e.op == 'sell' and e.data == hex then listing = e.id end
        end
        check(listing ~= nil, 'the journal holds the sale with listing id ' .. tostring(listing))

        -- 3. browse finds it, with the seller's name
        client.page = nil
        client:browse({text = ''}, 'newest', true, 1)
        gear.wait_until(function() return client.page ~= nil end, 20)
        local row
        for _, r in ipairs(client.page and client.page.rows or {}) do if r.id == listing then row = r end end
        check(row ~= nil, 'browse finds the listing (' .. tostring(client.page and client.page.total) .. ' found)')
        if row then
            check(row.seller == me.name and row.seller_key == me.key, ('seller %s / %s'):format(tostring(row.seller), tostring(row.seller_key)))
            check(row.price == PRICE and row.name == meta.name, ('row %s for %s'):format(tostring(row.name), tostring(row.price)))
        end
        -- searching by a word of its name finds it too
        local word = meta.name:match('%a%a%a+')
        if word then
            client.page = nil
            client:browse({text = word:lower()}, 'price', false, 1)
            gear.wait_until(function() return client.page ~= nil end, 20)
            local found = false
            for _, r in ipairs(client.page and client.page.rows or {}) do if r.id == listing then found = true end end
            check(found, 'a search for "' .. word:lower() .. '" finds it')
        end

        -- 4. the panel: every tab, a screenshot of each
        gear.ui.show_panel('market', true)
        for _, tab in ipairs({'browse', 'sell', 'mine', 'mail'}) do
            panel.view.tab = tab
            if tab == 'browse' then panel.search(client, 1) end
            if tab == 'mine' then panel.view.mine_asked = nil end
            if tab == 'mail' then panel.view.mail_asked = nil end
            local before = draws[tab] or 0
            gear.wait(2)
            check((draws[tab] or 0) - before > 10, ('tab %s drawn %d times'):format(tab, (draws[tab] or 0) - before))
            A.screenshot(('ah-%s-%s'):format(mode, tab))
        end
        check(#errors == 0, 'no Lua errors in the panel (' .. #errors .. ')')
        out.draw_errors = errors
        panel.view.tab = 'browse'

        -- 5. cancel, then collect the item from the mailbox
        got, ok, err = await('cancel', 30, function(cb) client:cancel(listing, cb) end)
        check(got and ok, 'cancel: ' .. tostring(err))
        client.mail = nil
        client:refresh_mail()
        gear.wait_until(function() return client.mail ~= nil end, 20)
        local entry
        for _, m in ipairs(client.mail and client.mail.entries or {}) do
            if m.kind == 'item' and m.reason == 'cancelled' then entry = m end
        end
        check(entry ~= nil, 'the cancelled item is in the mailbox')
        if entry then
            got, ok, err = await('collect', 30, function(cb) client:collect(entry.mid, cb) end)
            check(got and ok, 'collect: ' .. tostring(err))
            check(bp_has(hex) ~= nil, 'the item is back in the backpack, byte-identical (' .. #hex / 2 .. ' bytes)')
            check(#bp:items() == count0, 'backpack count ' .. #bp:items() .. ' (was ' .. count0 .. ')')
        end
        -- a sale's and a deposit's receipts ('done') stay in the journal until the next load (the crash check)
        local function settled()
            for _, e in ipairs(client.journal.entries) do
                if not ((e.op == 'sell' or e.op == 'deposit') and e.state == 'done') then return false end
            end
            return true
        end
        gear.wait_until(settled, 15)
        check(not meta.name:find('\\', 1, true) and meta.level > 0,
            ('the listed name has no tooltip codes: "%s", level %d'):format(meta.name, meta.level))

        -- 6. withdraw the rest of the wallet
        local rest = client:wallet()
        check(rest == DEP - fee, 'wallet holds the deposit less the fee: ' .. tostring(rest))
        got, ok, err = await('withdraw', 30, function(cb) client:withdraw(rest, cb) end)
        check(got and ok, ('withdraw %d: %s'):format(rest, tostring(err)))
        gear.wait_until(function() return client:wallet() == 0 end, 10)
        check(client:wallet() == 0, 'wallet empty: ' .. tostring(client:wallet()))
        check(hero:gold() == g0 - fee, ('hero gold %d = start %d - fee %d'):format(hero:gold(), g0, fee))
        gear.wait_until(settled, 15)
        local open = {}
        for _, e in ipairs(client.journal.entries) do
            if not ((e.op == 'sell' or e.op == 'deposit') and e.state == 'done') then
                open[#open + 1] = e.op .. ':' .. tostring(e.state)
            end
        end
        check(#open == 0, 'nothing open in the journal (' .. table.concat(open, ', ') .. ')')
        local m = M.market()
        if m then
            local s = m.state
            check(#s.listings == 0 and #s.mail == 0, ('market: %d listings, %d mail'):format(#s.listings, #s.mail))
        end
        if mode == 'lan' then
            local mp = gear.mp
            out.channel_received = (mp._channel and mp._channel.received or 0) - (out.channel_before or 0)
            check(out.channel_received > 0, 'frames came back through the chat carrier: ' .. out.channel_received)
            mp.force_network(false)
            M.via_channel(false)
            gear.ui.show_panel('market', false)
            gear.wait(1)
            A.screenshot('ah-lan-chat')     -- the chat box must show none of it
        end
        out.gold_end = hero:gold()
        finish()
    end)
end
