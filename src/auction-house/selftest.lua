-- Self test (needs -gear-auto and config.selftest in gear_mods.json):
--   'sp'   loads savegame config.selftest_slot (default 1); the market runs in this game.
--   'lan'  hosts a LAN game through the menus (the hero at config.hero_x / hero_y of the LAN hero list, 1600x900
--          screenshot pixels); the host's own requests and the market's answers go through gear.mp.send with
--          gear.mp.force_network(true), so out through the real chat carrier and back.
--   'closed' a REAL Closed Net game: the menus (Multiplayer > Closed Internet, lobby login, join) lead into a loopback game server
--          (config host/port/account/password, realm 'ahclosed'; create = true makes the account's hero first; see tools/closed-net-test.md).
--          The market is the server's (auction_house.lua), no forced network. Roles: 'closed' = the whole seller flow, 'closed_sell' = sell
--          and stay (state in closed-state.json), 'closed_check' = rejoin and look for a duplicate, 'closed_buy' = buy that listing,
--          'closed_collect' = collect the bought item, 'closed_gold' = deposit/withdraw gold only.
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
    local real_panel = panel.draw
    panel.draw = function(c, conf, st)
        local tab = panel.view.tab
        local ok, err = pcall(real_panel, c, conf, st)
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

    local function enter_closed()
        gear.wait(6)
        gear.realm.add({id = 'ahclosed', name = 'AH closed', host = cfg.host, port = cfg.port})
        gear.realm.use('ahclosed')
        A.ui_click(512, 352)            -- Multiplayer
        gear.wait(2)
        A.ui_click(512, 352)            -- Closed Internet (second entry)
        gear.wait(3)
        A.screenshot('cn-1-login')
        local fields = {{512, 183, cfg.account}, {512, 249, cfg.password or ''}, {430, 319, 'AAAA'}, {430, 379, 'AAAA'}}
        for i, f in ipairs(fields) do
            A.ui_click(f[1], f[2]) gear.wait(0.4)
            if i <= 2 then for _ = 1, 24 do A.press('back') end gear.wait(0.2) end
            if f[3] ~= '' then A.type(f[3]) end gear.wait(0.4)
        end
        A.screenshot('cn-2-filled')
        A.ui_click(512, 577)            -- Einloggen
        gear.wait(6)
        A.screenshot('cn-3-after-login')
        A.ui_click(508, 438) gear.wait(2)       -- Ok on a message (invalid data block / reservation key)
        gear.wait(4)
        A.screenshot('cn-4-select')
        if cfg.create then
            A.ui_click(94, 495) gear.wait(1.5)      -- an empty slot
            A.ui_click(508, 662) gear.wait(5)       -- Neuer Charakter
            A.screenshot('cn-4b-newchar')
            A.ui_click(cfg.class_x or 102, cfg.class_y or 480) gear.wait(2.5)
            A.screenshot('cn-4c-class')
            A.ui_click(512, 585) gear.wait(0.5)     -- the name
            for _ = 1, 16 do A.press('back') end
            A.type(cfg.hero or 'Seller')
            gear.wait(0.5)
            A.ui_click(608, 713) gear.wait(4)       -- Ok
            A.screenshot('cn-5-created')
        end
        A.ui_click(102, 480) gear.wait(2)       -- the hero (slot 1)
        A.screenshot('cn-6-hero')
        A.ui_click(580, 713) gear.wait(4)       -- Lobby
        A.screenshot('cn-7-lobby')
        A.ui_click(222, 97) gear.wait(1)        -- the channel
        A.ui_click(469, 382) gear.wait(4)       -- Betreten
        A.screenshot('cn-8-games')
        A.ui_click(222, 65) gear.wait(1)        -- the game
        A.ui_click(469, 382) gear.wait(3)       -- Beitreten
        A.screenshot('cn-9-joining')
        -- the join turns into the "Starten" screen (hero profile of the players): click it until the world loads
        for i = 1, 8 do
            gear.wait(5)
            if A.wait_for_game(1) then return end
            A.ui_click(484, 381)                -- Starten
            if i == 1 then A.screenshot('cn-10-starten') end
            if A.wait_for_game(12) then return end
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
        if mode:find('^closed') then
            enter_closed()
            if not A.wait_for_game(240) then
                A.screenshot('cn-no-game')
                check(false, 'joined the Closed Net game')
                return finish()
            end
            gear.wait(8)
            check(gear.mp.mode() == 'closed', "gear.mp.mode() reads closed (" .. tostring(gear.mp.mode()) .. ')')
            out.channel_before = 0
            if cfg.nudge ~= false then
                -- the engine tells the server about the hero's gold with its next hero update: walk the hero now and then
                -- so there is one (an idle hero sends none); every walk is logged with the time for the gold timing
                gear.task(function()
                    local pts = {{420, 330}, {600, 420}, {500, 300}, {620, 380}}
                    local i = 0
                    while true do
                        gear.wait(cfg.nudge_every or 6)
                        i = i % #pts + 1
                        A.ui_click(pts[i][1], pts[i][2])
                        out.nudges = (out.nudges or 0) + 1
                        gear.log(('auction selftest: nudge %d at %.1f'):format(out.nudges, gear.time()))
                    end
                end)
            end
        elseif mode == 'lan' then
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
        if mode == 'mkitem' then
            -- single player prep: dumps the gear pieces of the backpack (name, category, socket entries n, capacity) into
            -- unique-item.json; with cfg.fill the free sockets of the best piece are filled with the backpack's runes first
            local function info(b)
                local n = b:byte(5) + 256 * b:byte(6)
                local rec = 6 + n * 130
                local caps = 0
                for i = 0, 7 do if b:byte(rec + 0x0C + i + 1) ~= 0 then caps = caps + 1 end end
                return caps, n
            end
            local list, runes = {}, {}
            for _, it in ipairs(bp:items()) do
                local b = inv.export(it.id)
                local caps, n = info(b)
                note(('backpack: %s [%s] n=%d caps=%d %d bytes'):format(tostring(it.type_name), tostring(it.category), n, caps, #b))
                if it.category == 'rune' then runes[#runes + 1] = it
                elseif it.category == 'weapon' or it.category == 'armor' or it.category == 'shield' then list[#list + 1] = {it = it, n = n, caps = caps} end
            end
            table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.caps > b.caps end)
            local best = list[1]
            if not check(best ~= nil, 'a gear piece in the backpack') then return finish() end
            if cfg.fill and best.n < best.caps then
                for _ = best.n + 1, best.caps do
                    local rune = table.remove(runes)
                    if not rune then break end
                    bp:take(rune.id)
                    local ok, err = inv.socket(best.it.id, rune.id)
                    note('socket ' .. tostring(rune.type_name) .. ': ' .. tostring(ok) .. ' ' .. tostring(err))
                end
            end
            local b = inv.export(best.it.id)
            local _, n = info(b)
            local meta = panel.meta_of(best.it)
            gear.save('unique-item.json', gear.json.encode({name = meta.name, category = best.it.category, n = n, hex = inv.hex(b)}))
            note(('unique-item.json: %s [%s] with %d socket entries, %d bytes'):format(meta.name, best.it.category, n, #b))
            out.made = {name = meta.name, n = n}
            return finish()
        end
        if mode == 'closed_sell' or mode == 'closed_check' or mode == 'closed_buy' or mode == 'closed_proceeds' or mode == 'closed_relogin' then
            -- the multi-run flow of a real Closed Net game (state between the runs in closed-state.json of the mod's folder):
            --   closed_sell      seller: deposit gold, sell an item, remember it, then wait to be killed (no save, no quit)
            --   closed_check     seller again: no duplicate in the backpack, the listing still stands
            --   closed_buy       buyer: deposit, buy the listing, collect the item from the mailbox, remember it
            --   closed_relogin   buyer again: the collected item is (still) in the backpack after the relogin
            --   closed_proceeds  seller again: the wallet holds the sale less the cut, withdraw it
            local function load_state() local t = gear.read('closed-state.json') return t and gear.json.decode(t) or {} end
            local function save_state(st) gear.save('closed-state.json', gear.json.encode(st)) end
            local st = load_state()
            local online = gear.wait_until(function() return client:online() end, 30)
            if not check(online, 'the market answers (info)') then return finish() end
            check(client:authoritative(), 'the server says it keeps the hero (authoritative)')
            local g0 = hero:gold()
            out.gold_start = g0
            note('gold ' .. tostring(g0) .. ', wallet ' .. tostring(client:wallet()) .. ', backpack ' .. #bp:items())
            if mode == 'closed_sell' then
                local DEP = 1000
                local got, ok, err = await('deposit', 30, function(cb) client:deposit(DEP, cb) end)
                check(got and ok, 'deposit: ' .. tostring(err))
                local pick
                if cfg.unique then
                    -- a unique, non-stackable gear piece (the most sockets first): one the hero carries, else the one made from
                    -- unique-item.json (test only: its export hex, made by the 'mkitem' run in single player, put into the
                    -- backpack with inv.add, which announces it like any item the client makes; the server accepts it with
                    -- --auth-strict-items=off, and with =log it shows up as one unexplained item in the log)
                    local function sockets(it) local b = inv.export(it.id) return b and (b:byte(5) + 256 * b:byte(6)) or 0 end
                    local function gear_piece(it) return it.category == 'weapon' or it.category == 'armor' or it.category == 'shield' end
                    local best, bn = nil, -1
                    for _, it in ipairs(bp:items()) do
                        if gear_piece(it) and panel.sellable(it, false) and sockets(it) > bn then best, bn = it, sockets(it) end
                    end
                    local made = gear.read('unique-item.json')
                    made = made and gear.json.decode(made)
                                        if made and made.hex and (best == nil or bn < (made.n or 0)) then
                        local id, col, row = inv.add(bp, inv.unhex(made.hex))
                        note(('made %s (%d sockets) into the backpack: %s %s %s'):format(tostring(made.name), made.n or 0, tostring(id), tostring(col), tostring(row)))
                        out.made_item = {name = made.name, hex = made.hex, id = id}
                        gear.wait(3)
                        for _, it in ipairs(bp:items()) do if it.id == id then best = it end end
                    end
                    pick = best
                    out.unique = true
                else
                    for _, it in ipairs(bp:items()) do if panel.sellable(it, false) then pick = it break end end
                end
                if not check(pick ~= nil, 'a sellable item') then return finish() end
                local hex = inv.hex(inv.export(pick.id))
                out.hex_sold = hex
                note('item hex before the sale: ' .. hex)
                local meta = panel.meta_of(pick)
                local count0 = #bp:items()
                got, ok, err = await('sell', 60, function(cb) client:sell(bp, pick, meta, 500, 1, cb) end)
                check(got and ok, 'sell ' .. meta.name .. ': ' .. tostring(err))
                check(not bp_has(hex) and #bp:items() == count0 - 1, 'the item left the backpack')
                local listing
                for _, e in ipairs(client.journal.entries) do if e.op == 'sell' and e.data == hex then listing = e.id end end
                save_state({hex = hex, listing = listing, name = meta.name, sockets = (hex:sub(9, 10) ~= '' and tonumber(hex:sub(9, 10), 16)) or 0, count_before = count0, price = 500, sold_at = os.time()})
                A.write('auction.json', gear.json.encode(out))
                note('state saved; waiting to be killed')
                gear.wait(600)
                return finish()
            end
            if mode == 'closed_check' then
                check(st.hex ~= nil, 'state of the sale present')
                local same = 0
                for _, it in ipairs(bp:items()) do
                    local b = inv.export(it.id)
                    if b and inv.hex(b) == st.hex then same = same + 1 end
                end
                -- (identical items, e.g. potions, can be in the backpack more than once: the count decides)
                out.identical_left = same
                note('identical items still in the backpack: ' .. same)
                check(#bp:items() == st.count_before - 1, ('NO duplicate after the kill and rejoin: backpack %d (was %d, one sold)'):format(#bp:items(), st.count_before))
                client.page = nil
                client:browse({text = ''}, 'newest', true, 1)
                gear.wait_until(function() return client.page ~= nil end, 20)
                local found
                for _, r in ipairs(client.page and client.page.rows or {}) do if r.name == st.name then found = r end end
                check(found ~= nil, 'the listing is still on the market after the rejoin')
                return finish()
            end
            if mode == 'closed_buy' then
                client.page = nil
                client:browse({text = ''}, 'newest', true, 1)
                gear.wait_until(function() return client.page ~= nil end, 20)
                local row
                for _, r in ipairs(client.page and client.page.rows or {}) do if r.name == st.name then row = r end end
                if not check(row ~= nil, 'the listing is there for the buyer') then return finish() end
                local count0 = #bp:items()
                local got, ok, err = await('buy', 60, function(cb) client:buy(row, cb) end)
                check(got and ok, 'buy: ' .. tostring(err))
                client.mail = nil
                client:refresh_mail()
                gear.wait_until(function() return client.mail ~= nil end, 20)
                local entry
                for _, m in ipairs(client.mail and client.mail.entries or {}) do if m.kind == 'item' then entry = m end end
                if not check(entry ~= nil, 'the bought item is in the mailbox of the buyer') then return finish() end
                got, ok, err = await('collect', 60, function(cb) client:collect(entry.mid, cb) end)
                check(got and ok, 'collect: ' .. tostring(err))
                local arrived = bp_has(st.hex)
                check(arrived ~= nil, 'the item arrived in the backpack, byte-identical')
                if arrived then out.hex_collected = inv.hex(inv.export(arrived.id)) note('item hex collected: ' .. out.hex_collected) end
                check(#bp:items() == count0 + 1, ('backpack %d (was %d)'):format(#bp:items(), count0))
                st.buyer_count = #bp:items()
                st.bought_at = os.time()
                save_state(st)
                gear.wait(20)           -- the hero save after the arrival
                return finish()
            end
            if mode == 'closed_relogin' then
                local back = bp_has(st.hex or 'x')
                check(back ~= nil, 'the item the buyer collected is in the backpack after the relogin')
                out.hex_sold = st.hex
                if back then out.hex_after_relogin = inv.hex(inv.export(back.id)) note('item hex after the relogin: ' .. out.hex_after_relogin) end
                check(out.hex_after_relogin == st.hex, 'export hex after the relogin == the hex that was sold (sockets included)')
                check(#bp:items() == st.buyer_count, ('backpack %d (was %d before the relogin)'):format(#bp:items(), st.buyer_count or -1))
                return finish()
            end
            if mode == 'closed_proceeds' then
                local w = client:wallet()
                out.wallet = w
                check(w > 0, 'the wallet of the seller holds the proceeds: ' .. tostring(w))
                local got, ok, err = await('withdraw', 60, function(cb) client:withdraw(w, cb) end)
                check(got and ok, ('withdraw %d: %s'):format(w, tostring(err)))
                gear.wait(5)
                check(hero:gold() == g0 + w, ('hero gold %d = %d + %d'):format(hero:gold(), g0, w))
                return finish()
            end
        end
        if mode == 'closed_goldtime' then
            -- how long until the server hears of a gold change by Gear (hero update 0x169/0x16B/0x16C/0x16E/0x16F with the hero's
            -- slot): the server log (--trace) holds the arrival; here the wall clock of the change
            gear.wait(15)
            local g0 = hero:gold()
            local t0 = os.time()
            local ok, err = hero:add_gold(-1000)
            out.gold_change = {at_epoch = t0, at_gear = gear.time(), before = g0, after = hero:gold(), ok = ok, err = err}
            note(('gold %d -> %d at epoch %d (gear %.1f)'):format(g0, hero:gold(), t0, gear.time()))
            gear.wait(cfg.watch or 420)
            return finish()
        end
        local me = client:me()
        out.me = me
        note(('hero %s (%s)'):format(tostring(me.name), tostring(me.key)))

        -- the market answers the hello
        local online = gear.wait_until(function() return client:online() end, 30)
        if not check(online, 'the market answers (info)') then return finish() end
        check(client:wallet() == 0, 'the wallet starts empty: ' .. tostring(client:wallet()))

        -- 1. deposit (a run that gives the hero gold, the readme-shots 'gold' phase, may do it just now)
        gear.wait_until(function() return (hero:gold() or 0) >= 100 end, 8)
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
            check(row.seller == me.name and (mode:find('^closed') or row.seller_key == me.key), ('seller %s / %s'):format(tostring(row.seller), tostring(row.seller_key)))
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
        panel.open()
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
            panel.close()
            gear.wait(1)
            A.screenshot('ah-lan-chat')     -- the chat box must show none of it
        end
        out.gold_end = hero:gold()
        finish()
    end)
end
