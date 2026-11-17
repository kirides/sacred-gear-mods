-- Auction house: see README.md and DESIGN.md. The market (core.lua) runs where the game is hosted: in single player
-- in this game, in a network game in the host's game; every player's game runs the client (client.lua) and the
-- panel (ui.lua). They talk over Sacred Gear's mod channel (gear.mp.send, channel 'ah'), or directly when the market
-- is in this game.
local cfg = gear.config
if not cfg.enabled then return end

local core = require('core')
local clientmod = require('client')
local panel = require('ui')
local ui, world = gear.ui, gear.world

local CHANNEL = 'ah'
local MARKET, BACKUP = 'market.json', 'market.bak.json'
local SAVE_LIMIT = 7500000      -- gear.save takes up to 8 MB

math.randomseed(os.time() + math.floor((gear.time() % 1) * 1e6))

local mp = gear.mp
local has_channel = mp and mp.send ~= nil

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

-- Is the market in this game? Single player, or this game is the host of a network game.
local function market_here()
    if not (mp and mp.active and mp.active()) then return true end
    return mp.is_host and mp.is_host() or false
end

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
            if slot == local_slot() or not (mp and mp.active and mp.active()) then
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
    if market_here() then
        to_market[#to_market + 1] = msg
    elseif has_channel then
        mp.send(CHANNEL, msg, 'host')
    end
end)

gear.on('settings.changed', function(id, value)
    if id == 'allow_special' then cfg.allow_special = value end
    if market then market:set_rules(settings()) end
end)

if has_channel then
    gear.on('mp_message', function(from, channel, payload)
        if channel ~= CHANNEL or type(payload) ~= 'table' then return end
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

gear.on('session.start', function() client:session_start() end)
gear.on('session.stop', function()
    client:session_stop()
    panel.close()
end)

gear.on('frame', function()
    if market_here() then
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

gear.on('draw', function(state)
    local open = state.mode == 'game' and not state.exclusive and (chest_window_open() or (gear.auto and cfg.selftest))
    if not open then
        if ui.panel_open('market') then panel.close() end
        if state.mode == 'game' and not state.exclusive and ui.edit_mode() then panel.open_button(false, client) end
        return
    end
    if mp and mp.active and mp.active() and not has_channel then
        panel.open_button(false, client)
        return
    end
    panel.open_button(true, client)
    panel.panel(client, cfg)
end)

local M = {client = client, panel = panel, market = function() return market end, ensure_market = ensure_market}
if gear.auto and cfg.selftest then require('selftest')(M) end
