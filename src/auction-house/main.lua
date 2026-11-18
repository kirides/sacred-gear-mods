-- Auction house: see README.md and DESIGN.md. The market (core.lua) runs on our C# GameServer when it has the
-- script auction_house.lua (net channel 'auction', gear.net), else where the game is hosted: in single player in this
-- game, in a network game in the host's game (the stock GameServer.exe); every player's game runs the client
-- (client.lua) and the panel (ui.lua). They talk over gear.net to the server, over Sacred Gear's mod channel
-- (gear.mp.send, channel 'ah') to the host, or directly when the market is in this game.
local cfg = gear.config
if not cfg.enabled then return end

local core = require('core')
local kind = require('kind')
local clientmod = require('client')
local panel = require('ui')
local ui, world = gear.ui, gear.world

local CHANNEL = 'ah'
local MARKET, BACKUP = 'market.json', 'market.bak.json'
local SAVE_LIMIT = 7500000      -- gear.save takes up to 8 MB

math.randomseed(os.time() + math.floor((gear.time() % 1) * 1e6))

local mp = gear.mp
local has_channel = mp and mp.send ~= nil
local net = gear.net
local SERVER_CHANNEL = 'auction'
local server_ch = net and net.channel and net.channel(SERVER_CHANNEL) or nil
local PROBE_SECONDS = 12        -- after a game starts: how long to look for a market on the game server

local function settings()
    local d = {}
    for n in tostring(gear.settings.get('durations') or '1,3,7'):gmatch('%d+') do d[#d + 1] = tonumber(n) end
    if #d == 0 then d = {1, 3, 7} end
    return {
        durations = d,
        fee_per_day = gear.settings.get('fee_per_day'),
        sale_cut = gear.settings.get('sale_cut'),
        max_per_seller = gear.settings.get('max_per_seller'),
    }
end
cfg.allow_special = gear.settings.get('allow_special')

-- Where the market is: 'server' (the game server answered on 'auction'), 'probe' (a network game just started and the
-- server may still answer: only hellos go out), 'here' (single player, or this game hosts) or 'host'.
local server_market = false
local session_t, probe_t = nil, -1e9

local function network_game() return mp and mp.active and mp.active() or false end

-- 'closed': Closed Net without a market on the game server (nothing is sent, nothing runs here): the host's market and a local one never serve Closed Net.
local function route()
    if server_market then return 'server' end
    if kind.closed() then
        if server_ch and session_t and gear.time() - session_t < PROBE_SECONDS and (net.supported and net.supported() or gear.time() - session_t < 4) then
            return 'probe'
        end
        return 'closed'
    end
    if server_ch and network_game() and session_t and gear.time() - session_t < PROBE_SECONDS then
        if net.supported and net.supported() or gear.time() - session_t < 4 then return 'probe' end
    end
    if not network_game() then return 'here' end
    return (mp.is_host and mp.is_host()) and 'here' or 'host'
end

-- Is the market in this game? Single player, or this game is the host of a network game (and the server has none).
local function market_here() return route() == 'here' end

local function local_slot()
    return (mp and mp.local_slot and mp.local_slot()) or 1
end

---------------------------------------------------------------------------------------------------------------
-- the market's storage: market.json, written atomically, the previous one kept as market.bak.json
---------------------------------------------------------------------------------------------------------------
local function load_state()
    local text = gear.read(MARKET)
    local from_backup = false
    if not text then
        text = gear.read(BACKUP)
        if not text then return nil end
        from_backup = true
    end
    local v, err = gear.json.decode(text)
    if type(v) ~= 'table' then
        local b = not from_backup and gear.read(BACKUP)
        local bv = b and gear.json.decode(b)
        if type(bv) == 'table' then
            gear.log('market.json cannot be read (' .. tostring(err) .. '): using market.bak.json')
            return bv
        end
        return nil, err or 'not JSON'
    end
    if from_backup then gear.log('market.json was missing: using market.bak.json') end
    return v
end

local last_text
local function save_state(state)
    local text = gear.json.encode(state)
    if #text > SAVE_LIMIT then return nil, 'the market file would be too large' end
    local prev = last_text or gear.read(MARKET)
    if prev then gear.save(BACKUP, prev) end
    local ok, err = gear.save(MARKET, text)
    if not ok then return nil, err end
    last_text = text
    return true
end

---------------------------------------------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------------------------------------------
local market            -- the market object when it runs here
local to_market = {}    -- requests of this game's own client to a market in this game
local to_client = {}    -- answers of a market in this game to this game's own client
local client
-- Self test only: the host's own requests and the market's answers to it go through gear.mp.send (with
-- gear.mp.force_network, out through the real chat carrier) instead of the in-game queues.
local via_channel = false

local function hex_id()
    return ('%08x%08x'):format(math.random(0, 0x7FFFFFFF), math.random(0, 0x7FFFFFFF))
end

local function ensure_market()
    if market then return market end
    market = core.new({
        now = os.time,
        load = load_state,
        save = save_state,
        random_id = hex_id,
        log = function(t) gear.log('market: ' .. t) end,
        send = function(slot, msg)
            if not via_channel and (slot == local_slot() or not (mp and mp.active and mp.active())) then
                to_client[#to_client + 1] = msg
            elseif has_channel then
                mp.send(CHANNEL, msg, slot)
            end
        end,
    }, settings())
    if market.problem then gear.log(market.problem) end
    market:sweep(true)
    market:flush()
    return market
end

client = clientmod.new(function(msg)
    local where = route()
    if where == 'server' then
        server_ch:send(msg, 'server')
    elseif where == 'closed' then
        return                                                           -- Closed Net, no server market: nothing goes anywhere
    elseif where == 'probe' then
        if msg.op == 'hello' then server_ch:send(msg, 'server') end      -- the rest is resent once the market is found
    elseif where == 'here' and not via_channel then
        to_market[#to_market + 1] = msg
    elseif has_channel then
        mp.send(CHANNEL, msg, 'host')
    end
end)

if server_ch then
    server_ch:on(function(from, payload)
        if type(payload) ~= 'table' or (from and from.slot ~= 0) then return end
        if payload.op == 'info' and payload.where == 'server' and payload.closed == true then kind.server_closed = true end
        if payload.op == 'info' and payload.where == 'server' and not server_market then
            server_market = true
            gear.log('auction house: the market is on the game server')
        end
        if server_market then client:receive(payload) end
    end)
end

-- 'Hide in Singleplayer' (this player's own setting): no button and no panel in a single player game.
local function hidden_here()
    return gear.settings.get('hide_in_singleplayer') and not network_game() and kind.mode() == 'single' or false
end

gear.on('settings.changed', function(id, value)
    if id == 'allow_special' then cfg.allow_special = value end
    if id == 'hide_in_singleplayer' and value and not network_game() and ui.panel_open('market') then panel.close() end
    if market then market:set_rules(settings()) end
end)

if has_channel then
    gear.on('mp_message', function(from, channel, payload)
        if channel ~= CHANNEL or type(payload) ~= 'table' then return end
        if kind.closed() then return end                -- Closed Net: no host market, no answers from one
        if payload.secret then
            -- a request: only the market answers it
            if not market_here() then return end
            local p = (from and from.key) and from or (mp.player and mp.player(from.slot))
            ensure_market():handle({slot = from.slot, key = p and p.key or nil, name = p and p.name or nil}, payload)
        else
            client:receive(payload)
        end
    end)
end

gear.on('session.start', function()
    server_market, session_t, probe_t = false, gear.time(), -1e9
    kind.reset()
    client:session_start()
end)
gear.on('session.stop', function()
    server_market, session_t = false, nil
    kind.reset()
    client:session_stop()
    panel.close()
end)

gear.on('frame', function()
    local where = route()
    client.where = where
    if where == 'probe' and gear.time() - probe_t > 2 then
        probe_t = gear.time()
        client:send({op = 'hello'})
    end
    if where == 'here' then
        local m = ensure_market()
        if #to_market > 0 then
            local me = client:me()
            local list = to_market
            to_market = {}
            for _, msg in ipairs(list) do m:handle({slot = local_slot(), key = me.key, name = me.name}, msg) end
        end
        m:sweep(false)
        m:flush()
    end
    if #to_client > 0 then
        local list = to_client
        to_client = {}
        for _, msg in ipairs(list) do client:receive(msg) end
    end
    client:tick()
end)

---------------------------------------------------------------------------------------------------------------
-- the panel, only with the chest window open
---------------------------------------------------------------------------------------------------------------
local function chest_window_open()
    local w = ui.window('UI_WND_CHEST')
    local hero = world.hero()
    return (w and w.drawn and hero and not hero:is_dead()) and true or false
end

ui.show_panel('market', false)
ui.show_panel('open', true)
if ui.persist_panel then ui.persist_panel('market', false); ui.persist_panel('osk', false) end   -- they open with a chest

gear.on('draw', function(state)
    if hidden_here() then
        if ui.panel_open('market') then panel.close() end
        -- the layout editor still shows the button so it can be placed
        if state.mode == 'game' and not state.exclusive and ui.edit_mode() then panel.open_button(false, client) end
        return
    end
    local open = state.mode == 'game' and not state.exclusive and (chest_window_open() or (gear.auto and cfg.selftest))
    if not open then
        if ui.panel_open('market') then panel.close() end
        if state.mode == 'game' and not state.exclusive and ui.edit_mode() then panel.open_button(false, client) end
        return
    end
    if network_game() and not has_channel and not server_market then
        panel.open_button(false, client)
        return
    end
    panel.open_button(true, client)
    panel.panel(client, cfg)
end)

local M = {client = client, panel = panel, market = function() return market end, ensure_market = ensure_market, route = route,
    via_channel = function(on) via_channel = (on and has_channel) and true or false end}
if gear.auto and cfg.selftest then require('selftest')(M) end
