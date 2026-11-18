-- A self test of gear.chat and the Enhanced Chat mod, for runs without a player (on a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=chat -gear-mods=enhanced-chat,enhanced-chat_selftest
--
-- Loads savegame `slot`, adds lines to the game's message list as the game does (gear.auto.chat_add) and checks what
-- gear.chat makes of them (kind, colours, history), that the window shows them and hides the game's own lines, that
-- they come back when the window is hidden, the tabs (clicked with the mouse), the scrolling and its new-lines button.
-- config mode = 'lan' hosts a LAN game through the menus instead (the game's own gameserver on its usual ports: not
-- next to a real game) and also sends a private message to the own slot through the server, which comes back with
-- its sender, and checks the player filter. Results and screenshots in GearAutomation\<instance>.

if not gear.auto then
    print('no automation (start the game with -gear-auto): nothing to do')
    return
end

local A, chat = gear.auto, gear.chat
local cfg = gear.config
local results = {checks = {}, passed = 0, failed = 0}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end

local function finish()
    A.write('chat.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if cfg.quit then A.quit(results.failed == 0 and 0 or 1) end
end

local function query(set)
    local out = set or {}
    gear.emit('enhanced-chat.query', out)
    return out
end

local got = {}
gear.on('chat.line', function(l) got[#got + 1] = l end)

-- Adds a line and waits for it to come back through chat.line.
local function add(text, channel, color)
    local n = #got
    local ok = A.chat_add(text, channel, color)
    if not ok then return nil end
    if not gear.wait_until(function() return #got > n end, 3) then return nil end
    for i = n + 1, #got do
        if got[i].text == text then return got[i] end
    end
    return got[#got]
end

local function count(kinds)
    local n = 0
    for _, l in ipairs(chat.history()) do if kinds[l.kind] then n = n + 1 end end
    return n
end

local function click_tab(i)
    local q = query()
    local r = q.tabs and q.tabs[i]
    if not r then return false end
    A.ui_click(r.x + r.w / 2, r.y + r.h / 2)
    return gear.wait_until(function() return query().tab == i end, 3)
end

-- Hosts a LAN game through the menus (as gear/examples/mptest does in sacred-bild).
local function host_lan()
    gear.wait(8)
    A.screenshot('lan-0-menu')
    A.ui_click(512, 352)                    -- Multiplayer
    gear.wait(2)
    A.ui_click(512, 352 - 38 / 1.1719)      -- LAN
    gear.wait(3)
    local function px(x, y) return (x - 200) / 1.1719, y / 1.1719 end
    A.ui_click(px(cfg.hero_x, cfg.hero_y))
    gear.wait(2)
    A.ui_click(px(910, 838))                -- next
    gear.wait(3)
    A.screenshot('lan-1-games')
    A.ui_click(px(553, 448))                -- create
    gear.wait(3)
    A.ui_click(px(747, 448))                -- create: the game starts its gameserver and connects to it
    for _ = 1, 8 do
        gear.wait(5)
        if A.wait_for_game(1) then return end
        A.ui_click(px(747, 448))            -- Starten
        if A.wait_for_game(10) then return end
    end
end

-- Chat on the network: a message to the own slot goes out to the game server and comes back through the receive
-- dispatcher's chat case, so gear.chat pairs the line with its type and sender as for another player's.
local function network_checks()
    local mp = gear.mp
    check('a network game', mp.mode() ~= 'single' and query().network == true, mp.mode())
    local me = mp.local_slot()
    local function send(kind, target, text)
        local n = #got
        local ok = A.chat_send(kind, target, text)
        check(kind .. ' chat sent', ok == true)
        if not ok then return nil end
        gear.wait_until(function()
            for i = n + 1, #got do if got[i].message == text then return true end end
            return false
        end, 8)
        for i = n + 1, #got do if got[i].message == text then return got[i] end end
        return nil
    end
    local pv = send('private', me, 'Selftest whisper to myself')
    check('private chat comes back as kind private', pv and pv.kind == 'private', pv and pv.kind)
    check('with the sender\'s slot and name', pv and pv.slot == me and type(pv.sender) == 'string' and pv.sender ~= '',
        pv and (tostring(pv.slot) .. ' ' .. tostring(pv.sender)))
    check('and the game\'s text around the message', pv and pv.plain:find('Selftest whisper to myself', 1, true) ~= nil, pv and pv.plain)
    local gl = send('global', 0, 'Selftest hello everyone')
    print('global chat: ' .. (gl and (gl.kind .. ' / ' .. tostring(gl.sender) .. ' / ' .. gl.plain) or 'did not come back to the sender'))
    local tm = send('team', 0, 'Selftest hello team')
    print('team chat: ' .. (tm and (tm.kind .. ' / ' .. tostring(tm.sender) .. ' / ' .. tm.plain) or 'did not come back to the sender'))
    gear.wait(0.5)
    A.screenshot('lan-chat')
    if pv and pv.sender then
        local q = query({set_player = pv.sender, tab = 1})
        local listed = false
        for _, n in ipairs(q.players or {}) do if n == pv.sender then listed = true end end
        check('the sender is in the player filter', listed)
        gear.wait(0.3)
        q = query()
        local from = 0
        for _, l in ipairs(chat.history()) do if l.sender == pv.sender then from = from + 1 end end
        check('the player filter shows only that player\'s lines', q.shown == from and from >= 1, ('%s of %s'):format(q.shown, from))
        A.screenshot('lan-chat-filtered')
        query({set_player = ''})
    end
end

-- Mode 'server': two instances join a LAN game of a dedicated server (the remake's SacredGameServer on test ports; the
-- instances' own GameServer.exe is ended whenever one of them opens the Multiplayer menu). The instance whose
-- -gear-instance name contains 'send' writes on every channel, the other checks what gear.chat and the window make of it.
-- Setup (a copy of the game folder): settings.cfg NETWORK_PORT_LISTEN : 26005, then
--     SacredGameServer.exe --game-dir=<copy> --network-port-tcp=26006 --network-port-listen=26005 --udp-port=0
--         --lan-announce=1 --public-address=127.0.0.1 --server-name=ChatTest --network-lobby=
-- and start the receiver (e.g. -gear-instance=chatrecv) about 15 s before the sender (-gear-instance=chatsend).
local function join_lan()
    if tostring(A.instance or ''):find('send') then cfg.hero_x, cfg.hero_y = cfg.sender_hero_x, cfg.sender_hero_y end
    gear.wait(8)
    A.ui_click(512, 352)                    -- Multiplayer
    gear.wait(2)
    A.ui_click(512, 352 - 38 / 1.1719)      -- LAN
    gear.wait(3)
    local function px(x, y) return (x - 200) / 1.1719, y / 1.1719 end
    A.ui_click(px(cfg.hero_x, cfg.hero_y))
    gear.wait(2)
    A.ui_click(px(910, 838))                -- Weiter
    gear.wait(8)
    A.screenshot('join-list')
    A.ui_click(px(555, 75))                 -- the first game of the list
    gear.wait(2)
    A.ui_click(px(747, 448))                -- Beitreten
    gear.wait(3)
    -- The first player in is the game's host: it starts only once the other one waits in the join dialog too
    -- (a player who comes after the host started waits there with Starten greyed out).
    if not tostring(A.instance or ''):find('send') then gear.wait(cfg.host_wait) end
    A.screenshot('join-dialog')
    for _ = 1, 20 do
        A.ui_click(px(747, 448))            -- Starten
        if A.wait_for_game(8) then return end
    end
end

local LINES = {global = 'Selftest hello from the other player', team = 'Selftest team from the other player',
               private = 'Selftest whisper from the other player'}

local function other_player()
    local mp = gear.mp
    if not gear.wait_until(function() return mp.active() end, 180) then return nil end
    for _, p in ipairs(mp.players()) do if not p.is_local then return p end end
end

local function sender()
    local other = other_player()
    check('the other player is in the game', other ~= nil)
    if not other then return end
    gear.wait(5)
    for round = 1, 8 do                     -- the other one may still be loading: say it a few times
        check('global sent ' .. round, A.chat_send('global', 0, LINES.global))
        A.chat_send('team', 0, LINES.team)
        A.chat_send('private', other.slot, LINES.private)
        gear.wait(5)
        if round == 1 then A.screenshot('sender-chat') end
    end
end

local function receiver()
    local other = other_player()
    check('the other player is in the game', other ~= nil, other and other.name)
    if not other then return end
    local seen = {}
    gear.wait_until(function()
        for _, l in ipairs(chat.history()) do
            for kind, text in pairs(LINES) do
                if l.message == text then seen[kind] = l end
            end
        end
        return seen.global and seen.private
    end, 90)
    -- team chat reaches only the sender's party: two players who did not team up never see it
    if seen.team then
        check('team chat from the other player', seen.team.kind == 'team', seen.team.kind .. ': ' .. seen.team.plain)
    else
        print('team chat did not arrive (the players are not in a party): not checked')
    end
    for _, kind in ipairs({'global', 'private'}) do
        local l = seen[kind]
        check(kind .. ' chat from the other player', l ~= nil and l.kind == kind, l and (l.kind .. ': ' .. l.plain))
        check(kind .. ': its sender', l and l.slot == other.slot and type(l.sender) == 'string' and l.sender ~= '',
            l and (tostring(l.slot) .. ' ' .. tostring(l.sender)))
        check(kind .. ': the game did not show it itself', l and l.hidden == true)
    end
    gear.wait(1)
    A.screenshot('two-all')
    local name = seen.global and seen.global.sender
    if not name then return end
    local q = query({set_player = name, tab = 1})
    local listed = false
    for _, n in ipairs(q.players or {}) do if n == name then listed = true end end
    check('the other player is in the player filter', listed, table.concat(q.players or {}, ', '))
    gear.wait(0.3)
    local from = 0
    for _, l in ipairs(chat.history()) do if l.sender == name then from = from + 1 end end
    check('filtered to that player: only their lines', query().shown == from and from >= 2, ('%s of %s'):format(query().shown, from))
    A.screenshot('two-filtered')
    query({set_player = '', tab = 2})
    gear.wait(0.3)
    check('Global tab: the global chat', query().shown == count({global = true, team = true, own = true}) and query().shown >= 1, query().shown)
    A.screenshot('two-global')
    query({tab = 3})
    gear.wait(0.3)
    check('Private tab: the whispers', query().shown == count({private = true}) and query().shown >= 1, query().shown)
    A.screenshot('two-private')
    query({tab = 1})
end

gear.task(function()
    check('chat API present', chat ~= nil and type(chat.history) == 'function')
    if not chat then return finish() end
    check('main menu', A.wait_for_menu(cfg.timeout_menu))
    if cfg.mode == 'lan' then host_lan() elseif cfg.mode == 'server' then join_lan() else A.load_save(cfg.slot) end
    check('in game', A.wait_for_game(cfg.timeout_game))
    gear.wait(3)
    if cfg.mode == 'server' then
        if tostring(A.instance or ''):find('send') then sender() else receiver() end
        return finish()
    end
    if cfg.mode == 'lan' then network_checks() end
    check('chat lines available (the hook is in)', chat.available() == true)
    check('the window shows', query().visible == true)

    -- the game's own kinds of lines, by channel
    local l = add('Selftest \\cFFF0E040golden\\r line', 1)
    check('a line comes through chat.line', l ~= nil)
    if l then
        check('plain text without the codes', l.plain == 'Selftest golden line', l.plain)
        check('kind system (channel 1)', l.kind == 'system' and l.channel == 1 and l.main == true, l.kind)
        check('runs: the \\c colour, then back to white', #l.runs == 3 and l.runs[2].color == 0xFFF0E040 and l.runs[3].color == 0xFFFFFFFF, #l.runs)
        check('the game did not show it (overlay replaced)', l.hidden == true)
    end
    local p = add('Selftest private channel', 2)
    check('channel 2 is private (light blue)', p and p.kind == 'private' and p.color == 0xFF00A0FF, p and p.kind)
    local o = add('Selftest own line', 4)
    check('channel 4 is the own line (green)', o and o.kind == 'own' and o.color == 0xFF00FF50, o and o.kind)
    local s = add('Selftest server line', 3, 0xFFFF8000)
    check('channel 3 is the server, with its own colour', s and s.kind == 'server' and s.color == 0xFFFF8000, s and s.color)
    local h = chat.history(4)
    check('history: the last four, oldest first', #h == 4 and h[4].text == 'Selftest server line' and h[1].plain == 'Selftest golden line', #h)
    gear.wait(0.5)
    local q = query()
    check('the window keeps them', q.entries >= 4 and q.last and q.last.plain == 'Selftest server line', q.entries)
    A.screenshot('chat-all')

    -- tabs: the mouse
    check('Private tab (mouse)', click_tab(3))
    gear.wait(0.3)
    check('Private shows the private lines only', query().shown == count({private = true}), query().shown)
    A.screenshot('chat-private')
    check('Global tab (mouse)', click_tab(2))
    gear.wait(0.3)
    check('Global shows the own, global and team lines', query().shown == count({own = true, global = true, team = true}), query().shown)
    check('System tab (mouse)', click_tab(4))
    gear.wait(0.3)
    check('System shows the game and server lines', query().shown == count({system = true, server = true, notice = true}), query().shown)
    add('Selftest second private', 2)
    gear.wait(0.3)
    check('a line for another tab marks it', query().unread[3] == true)
    check('All tab (mouse)', click_tab(1))

    -- many lines: the window scrolls, keeps the newest in view
    for i = 1, 40 do A.chat_add(('Selftest filler line %d, long enough to wrap in a window of four hundred units of width'):format(i), 1) end
    gear.wait(1)
    A.screenshot('chat-many')
    local sq = query()
    check('the lines scroll, the newest in view', sq.scroll_max > 0 and sq.scroll_offset >= sq.scroll_max - 2, ('%s / %s'):format(sq.scroll_offset, sq.scroll_max))
    -- the wheel over the lines scrolls up and stops following; the newest line does not pull it back
    local r = sq.tabs[1]
    A.move(A.ui_to_pixels(r.x + 100, r.y + 80))
    gear.wait(0.5)
    for _ = 1, 3 do
        A.wheel(3)
        if gear.wait_until(function() return query().following == false end, 1) then break end
    end
    -- (the automation's wheel does not always arrive: the scrollbar's up arrow as well)
    local lr = query().lines
    for _ = 1, 4 do
        if query().following == false then break end
        A.ui_click(lr.x + lr.w - 5, lr.y + 5)
        gear.wait(0.3)
    end
    A.chat_add('Selftest while scrolled up', 1)
    gear.wait(0.5)
    sq = query()
    check('scrolled up: not following, the new line waits below', sq.following == false and sq.scroll_offset < sq.scroll_max - 2, ('%s / %s'):format(sq.scroll_offset, sq.scroll_max))
    A.screenshot('chat-scrolled-up')
    sq = query()
    check('a button tells of the new line below', sq.new_below == 1 and sq.newer ~= nil, sq.new_below)
    if sq.newer then A.ui_click(sq.newer.x + sq.newer.w / 2, sq.newer.y + sq.newer.h / 2) end
    gear.wait(0.5)
    check('the button goes to the newest line and follows again', query().following == true)

    -- the window hidden: the game's own lines come back
    query({set_visible = false})
    gear.wait(1)
    local back = add('Selftest after hiding', 1)
    check('hidden window: the game shows its lines again', back and back.hidden == false, back and tostring(back.hidden))
    A.screenshot('chat-game-lines')
    query({set_visible = true})
    gear.wait(0.5)
    local again = add('Selftest shown again', 1)
    check('shown again: the game\'s lines are off again', again and again.hidden == true, again and tostring(again.hidden))

    -- rarity colours
    check('quality colours', gear.world.quality_color('unique') == 0xFFC19A33 and gear.world.quality_color(13) == 0xFFF0E040)
    local hero = gear.world.hero()
    local x, y, layer
    if hero then x, y, layer = hero:position() end
    local near = x and gear.world.items_near(x, y, 40 * gear.world.TILE, {layer = layer}) or {}
    if near[1] then
        local c = gear.world.item_color(near[1])
        check('item_color of an item near the hero', type(c) == 'number' and c > 0xFF000000, c and ('%08X'):format(c))
    else
        print('no item near the hero: item_color not checked')
    end
    check('item_color of a missing item is nil', gear.world.item_color(0x7FFFFF) == nil)
    finish()
end)
