-- The stash of a Closed Net game: kept by the game server (scripts-examples/shared_stash.lua of the GameServer), per lobby
-- account, over the Gear net channel 'shared-stash'. Nothing of it is ever written on this computer.
--
--   deposit:  take the item out of the character (destroyed, as the server sees it) -> the server sees it gone, saves the hero,
--             writes the entry and answers ok. If the server refuses (not 'keep') the item is made again from the export.
--   withdraw: the server reserves the entry and releases its data -> the item is made in the backpack (or the chest) ->
--             we report its id (`collected`) -> the server sees it in the hero, saves the hero, removes the entry, answers ok.
-- Requests carry ids and are resent until answered; after a crash or a reconnect the server's state is the truth (items that
-- did not reach a saved hero are in the stash again or still in the hero), so nothing is kept in a file.
local M = {}

local inv = gear.inv
local CHANNEL = 'shared-stash'
local RESEND = 4            -- seconds before an unanswered request is sent again
local INFO_EVERY = 20       -- seconds between `info` checks while the panel is in use
local LIST_EVERY = 8        -- seconds between refreshes of the list while the panel is in use

M.entries = {}              -- the server's ready entries (the list it last sent)
M.count, M.max = 0, nil
M.reason = nil              -- why there is no stash on this server (shown to the player)
M.pending = {}              -- rid -> {kind, msg, at, ...}

local channel, channel_err
local info_at, list_at = -100, -100
local info_ok_at = nil      -- when the server last said `closed = true`
local incoming = nil        -- entries of a list in progress

local function ensure_channel()
    if channel or channel_err then return channel end
    local ch, err = gear.net.channel(CHANNEL)
    if not ch then channel_err = err or 'no net channel' return nil end
    channel = ch
    ch:on(function(_, payload) M.receive(payload) end)
    return channel
end

-- Self tests: use `ch` (a table with on, send, transport) instead of the real net channel; nil goes back to the real one.
function M.use_channel(ch)
    channel, channel_err = nil, nil
    if ch then
        channel = ch
        ch:on(function(_, payload) M.receive(payload) end)
    end
end

-- Whether the server can be asked at all (the net layer is up and it knows net channels).
function M.reachable()
    if not ensure_channel() then return false, channel_err end
    local t = channel:transport('server')
    if not t then return false, 'this server does not support Gear net channels' end
    return true
end

local function send(msg)
    if not ensure_channel() then return nil, channel_err end
    return channel:send(msg, 'server')
end

local function new_rid()
    local parts = {}
    for i = 1, 3 do parts[i] = ('%08x'):format(math.random(0, 0x7FFFFFFF)) end
    return table.concat(parts)
end

-- true when the server has said it keeps the stash (recently); false, reason otherwise.
function M.available()
    if info_ok_at and gear.time() - info_ok_at < 90 then return true end
    local ok, why = M.reachable()
    if not ok then return false, why end
    return false, M.reason or 'waiting for the server (is it a GameServer with the shared_stash script and --authoritative?)'
end

function M.busy() return next(M.pending) ~= nil end

-- Callback for messages to show: M.notify(text, ok).
M.notify = function() end

function M.receive(msg)
    if type(msg) ~= 'table' then return end
    local op = msg.op
    if op == 'info' then
        M.answered = true
        if msg.closed then
            require('kind').server_closed = true            -- the server keeps the stash: Closed Net whatever the engine's flags say
            info_ok_at, M.reason = gear.time(), nil
            M.count, M.max = msg.count or M.count, msg.max or M.max
        else
            info_ok_at = nil
            M.reason = 'the server does not keep a shared stash for this game' .. (msg.reason and (' (' .. msg.reason .. ')') or '')
            M.entries = {}
        end
    elseif op == 'entry' then
        incoming = incoming or {}
        incoming[#incoming + 1] = msg
    elseif op == 'listed' then
        M.entries, incoming = incoming or {}, nil
        M.count = #M.entries
        list_at = gear.time()
    elseif op == 'result' then
        M.on_result(msg)
    elseif op == 'release' then
        M.on_release(msg)
    elseif op == 'collected' then
        M.on_collected(msg)
    end
end

-- Outside Closed Net, once per game: asks the server whether it keeps the stash. Returns 'wait' (asked, no answer yet: the
-- local stash must not be used), or 'done' (answered, or no server that could answer within PROBE seconds).
local PROBE = 3
function M.probe()
    if M.answered then return 'done' end
    if not M.reachable() then M.answered = true return 'done' end
    local now = gear.time()
    if not M.probed_at then M.probed_at = now send({op = 'info'}) end
    if now - M.probed_at > PROBE then M.answered = true return 'done' end
    return 'wait'
end

function M.refresh(force)
    if not M.reachable() then return end
    local now = gear.time()
    if force or now - list_at > LIST_EVERY then
        list_at = now
        send({op = 'list'})
    elseif now - info_at > INFO_EVERY then
        info_at = now
        send({op = 'info'})
    end
end

-- Puts a made-again item back where it came from; text for the player.
local function give_back(p)
    if not p.bytes then return 'the item could not be given back' end
    local c = p.container
    local id = c and inv.add(c, p.bytes)
    if not id then
        for _, which in ipairs({'backpack', 'chest'}) do
            local cc = inv.container(which)
            if cc then id = inv.add(cc, p.bytes) if id then break end end
        end
    end
    return id and 'the item is back in your inventory' or 'the item could not be given back (no room)'
end

-- Deposit item `it` of `container`. true | nil, message. The answer comes later (notify).
function M.deposit(container, it, entry_fields)
    local ok, why = M.available()
    if not ok then return nil, 'the shared stash is not available on this server' .. (why and (': ' .. why) or '') end
    local bytes, err = inv.export(it.id)
    if not bytes then return nil, err end
    local ref = it.id
    local got, rerr = inv.remove(container, it.id)
    if not got then return nil, rerr end
    local rid = new_rid()
    local msg = {op = 'deposit', rid = rid, ref = ref, data = inv.hex(bytes), name = entry_fields.name,
        quality = entry_fields.quality, w = entry_fields.w, h = entry_fields.h}
    M.pending[rid] = {kind = 'deposit', msg = msg, at = gear.time(), container = container, bytes = bytes, name = entry_fields.name}
    local sent, serr = send(msg)
    if not sent then
        -- never reached the server: the item is ours to give back at once
        M.pending[rid] = nil
        return nil, (serr or 'the server could not be reached') .. '; ' .. give_back({container = container, bytes = bytes})
    end
    return true
end

-- Withdraw entry `entry` (from the server's list). true | nil, message.
function M.withdraw(entry)
    local ok, why = M.available()
    if not ok then return nil, 'the shared stash is not available on this server' .. (why and (': ' .. why) or '') end
    for _, p in pairs(M.pending) do
        if p.kind ~= 'deposit' and p.entry_id == entry.id then return nil, 'that item is being taken out already' end
    end
    local rid = new_rid()
    local msg = {op = 'withdraw', rid = rid, id = entry.id}
    M.pending[rid] = {kind = 'withdraw', msg = msg, at = gear.time(), entry_id = entry.id, name = entry.name}
    local sent, err = send(msg)
    if not sent then M.pending[rid] = nil return nil, err or 'the server could not be reached' end
    return true
end

function M.on_result(msg)
    local p = msg.rid and M.pending[msg.rid]
    if not p then return end
    if msg.ok then
        M.pending[msg.rid] = nil
        if p.kind == 'deposit' then
            M.count = msg.count or M.count
            M.notify(('%s put into the stash'):format(p.name or 'item'), true)
            M.refresh(true)
        end
    elseif msg.retry then
        -- the server tries again on its own (hero save); keep waiting and show why
        p.at = gear.time()
        M.notify(msg.err or 'the server is still working on it', false)
    else
        M.pending[msg.rid] = nil
        if p.kind == 'deposit' then
            local text = msg.err or 'the server refused the deposit'
            if msg.keep then
                M.notify(text, false)
            else
                M.notify(text .. '; ' .. give_back(p), false)
            end
        else
            M.notify(msg.err or 'the server refused the withdrawal', false)
        end
        M.refresh(true)
    end
end

function M.on_release(msg)
    local p = msg.rid and M.pending[msg.rid]
    if not p or p.kind == 'deposit' then return end
    if p.ref then return end                          -- the item exists already: `collected` is resent by the timer
    local bytes = inv.unhex(msg.data or '')
    if not bytes then
        M.pending[msg.rid] = nil
        send({op = 'abort', rid = msg.rid})
        return M.notify('the stash entry is damaged', false)
    end
    local id, where
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then id = inv.add(c, bytes) if id then where = which break end end
    end
    if not id then
        M.pending[msg.rid] = nil
        send({op = 'abort', rid = msg.rid})
        M.refresh(true)
        return M.notify('no room in the backpack or the chest', false)
    end
    p.kind, p.ref, p.where, p.at = 'collect', id, where, gear.time()
    p.msg = {op = 'collected', rid = msg.rid, ref = id}
    send(p.msg)
end

function M.on_collected(msg)
    local p = msg.rid and M.pending[msg.rid]
    if not p then return end
    if msg.ok then
        M.pending[msg.rid] = nil
        M.count = msg.count or M.count
        M.notify(('%s taken into the %s'):format(p.name or 'item', p.where or 'backpack'), true)
        M.refresh(true)
    elseif msg.retry then
        p.at = gear.time() - RESEND + 1                -- ask again soon
    else
        -- the server cannot confirm it (nothing reserved any more): stop asking; the server's state decides
        M.pending[msg.rid] = nil
        M.notify(msg.err or 'the server could not confirm the withdrawal', false)
        M.refresh(true)
    end
end

-- Every frame: resends of requests the server did not answer.
function M.tick()
    local now = gear.time()
    for _, p in pairs(M.pending) do
        if now - p.at > RESEND then
            p.at = now
            send(p.msg)
        end
    end
end

-- Forgets what the server told (a new game, another server).
function M.reset()
    require('kind').reset()
    M.probed_at, M.answered = nil, false
    M.entries, M.count, M.max, M.reason, incoming = {}, 0, nil, nil, nil
    info_ok_at, info_at, list_at = nil, -100, -100
    M.pending = {}
end

return M
