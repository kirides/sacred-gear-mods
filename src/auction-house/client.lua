-- The player's side of the market: requests with request ids, the journal (journal.json in this folder) that makes
-- every transfer between the game and the market safe against crashes and lost messages, the crash check at a game
-- load, and the caches the panel reads (DESIGN.md, section 4).
--
-- Journal entries (`op`, `state`):
--   sell     prepared -> sent -> done      the item left the inventory; `done` is a receipt kept until the next load
--   deposit  prepared -> sent -> done      gold left the hero; `before` / `after` are the hero's gold around it
--   collect  asked -> received             an item or gold from the mailbox (also a gold withdrawal)
--   return   (an item a refused sale gave back that did not fit into the inventory; collected from the mailbox tab)
-- A request is resent with the same rid until it is answered; the market answers a repeated rid the same way.
local M = {}

local inv, world = gear.inv, gear.world

local FILE = 'journal.json'
local RESEND = 8            -- seconds before an unanswered request is sent again
local HELLO_EVERY = 10      -- seconds between hellos while no market answered

local C = {}
C.__index = C

-- send(msg): to the market. log(text).
function M.new(send)
    local self = setmetatable({
        send_raw = send,
        journal = {version = 1, secrets = {}, counter = 0, entries = {}},
        pending = {},           -- rid -> {msg, at, cb}
        info = nil, info_at = -1e9, hello_at = -1e9,
        page = nil, mine = nil, mail = nil, items = {}, history = {},
        notes = {},             -- {text, ok, until}
        session = nil, checked = nil,
        req = 0,
    }, C)
    self:load_journal()
    return self
end

---------------------------------------------------------------------------------------------------------------
-- journal
---------------------------------------------------------------------------------------------------------------
function C:load_journal()
    local text = gear.read(FILE)
    if not text then return end
    local j = gear.json.decode(text)
    if type(j) == 'table' and type(j.entries) == 'table' then
        j.secrets = type(j.secrets) == 'table' and j.secrets or {}
        j.counter = tonumber(j.counter) or 0
        self.journal = j
    else
        -- never overwrite what we cannot read: keep it beside and start empty
        gear.save('journal.broken.json', text)
        self:note('journal.json could not be read; kept as journal.broken.json', false)
    end
end

function C:save_journal()
    local ok, err = gear.save(FILE, gear.json.encode(self.journal))
    if not ok then self:note('cannot write journal.json: ' .. tostring(err), false) end
    return ok
end

function C:entry(rid)
    for i, e in ipairs(self.journal.entries) do
        if e.rid == rid then return e, i end
    end
end

function C:drop(rid)
    local _, i = self:entry(rid)
    if i then table.remove(self.journal.entries, i) end
end

function C:new_rid()
    self.journal.counter = self.journal.counter + 1
    return ('%x%04x%d'):format(os.time(), math.random(0, 0xFFFF), self.journal.counter)
end

---------------------------------------------------------------------------------------------------------------
-- identity
---------------------------------------------------------------------------------------------------------------
-- The local player: {key, name}. The key is the hero (name and class); the market binds it to a secret this
-- computer keeps in the journal.
function C:me()
    local p = gear.mp and gear.mp.local_player and gear.mp.local_player()
    local hero = world.hero()
    local class = hero and hero:class() or 'hero'
    local name = (p and p.name) or (hero and type(hero.name) == 'function' and hero:name()) or nil
    local key = (p and p.key) or ((name or 'player'):lower() .. ':' .. class)
    return {key = key, name = name or class}
end

function C:secret(key)
    local s = self.journal.secrets[key]
    if not s then
        local parts = {}
        for i = 1, 4 do parts[i] = ('%08x'):format(math.random(0, 0x7FFFFFFF)) end
        s = table.concat(parts)
        self.journal.secrets[key] = s
        self:save_journal()
    end
    return s
end

---------------------------------------------------------------------------------------------------------------
-- messages
---------------------------------------------------------------------------------------------------------------
function C:note(text, ok)
    self.notes[#self.notes + 1] = {text = text, ok = ok ~= false, ['until'] = gear.time() + 8}
    while #self.notes > 4 do table.remove(self.notes, 1) end
    gear.log(text)
end

function C:send(msg)
    local me = self:me()
    msg.key, msg.name, msg.secret = me.key, me.name, self:secret(me.key)
    self.send_raw(msg)
end

-- A request that changes something: resent with the same rid until answered. cb(answer).
function C:request(msg, cb)
    msg.rid = msg.rid or self:new_rid()
    self.pending[msg.rid] = {msg = msg, at = gear.time(), cb = cb}
    self:send(msg)
    return msg.rid
end

function C:query(msg)
    self.req = self.req + 1
    msg.req = self.req
    self:send(msg)
    return self.req
end

function C:online()
    return self.info ~= nil and not self.info.problem and gear.time() - self.info_at < 60
end

-- Every frame: hellos while there is no market, resends.
function C:tick()
    local now = gear.time()
    if (not self.info or now - self.info_at > 30) and now - self.hello_at > HELLO_EVERY then
        self.hello_at = now
        self:send({op = 'hello'})
    end
    for _, p in pairs(self.pending) do
        if now - p.at > RESEND then
            p.at = now
            self:send(p.msg)
        end
    end
    if self.session and not self.checked and self:online() then self:crash_check() end
end

function C:receive(msg)
    if type(msg) ~= 'table' then return end
    local op = msg.op
    if op == 'info' then
        local first = not self.info
        self.info, self.info_at = msg, gear.time()
        if msg.problem then self:note('market: ' .. msg.problem, false) end
        -- deliveries the market still holds for us: ask again with their rids
        for _, rid in ipairs(msg.pending or {}) do
            local e = self:entry(rid)
            if e and e.op == 'collect' then self:reask(e) end
        end
        if first then gear.emit('auction.online', msg) end
    elseif op == 'page' then
        self.page = msg
    elseif op == 'mine' then
        self.mine = msg
        if self.info then self.info.wallet = msg.wallet end
    elseif op == 'mail' then
        self.mail = msg
        if self.info then self.info.wallet = msg.wallet end
    elseif op == 'item' then
        if msg.data then self.items[msg.id] = msg.data else self.items[msg.id] = false end
    elseif op == 'history' then
        self.history[msg.type] = msg
    elseif op == 'notify' then
        if msg.kind == 'sold' then
            self:note(('Sold: %s to %s for %d gold (%d after the cut), in your wallet'):format(
                msg.name or '?', msg.buyer or '?', msg.price or 0, msg.net or 0))
        elseif msg.kind == 'expired' then
            self:note(('Not sold: %s is back in your mailbox'):format(msg.name or '?'))
        end
    elseif op == 'result' or op == 'deliver' or op == 'collected' or op == 'revoked' then
        self:answer(msg)
    elseif op == 'error' then
        self:note('market: ' .. tostring(msg.err), false)
    end
    if msg.wallet and self.info and op ~= 'info' then self.info.wallet = msg.wallet end
end

-- A delivery we asked for and have not confirmed: confirm it, or ask for it again with the same rid.
function C:reask(e)
    if e.state == 'received' then
        self:send({op = 'collected', rid = e.rid})
    elseif e.kind == 'gold' and not e.mid then
        self:request({op = 'withdraw', rid = e.rid, gold = e.gold})
    elseif e.mid then
        self:request({op = 'collect', rid = e.rid, mid = e.mid})
    end
end

function C:answer(msg)
    local p = self.pending[msg.rid]
    self.pending[msg.rid] = nil
    local e = self:entry(msg.rid)
    if msg.op == 'deliver' then
        self:delivered(msg, e)
    elseif msg.op == 'collected' then
        if e then self:drop(msg.rid) self:save_journal() end
        self:refresh_mail()
    elseif msg.op == 'revoked' then
        if e then self:drop(msg.rid) self:save_journal() end
    elseif e and e.op == 'sell' then
        if msg.ok then
            e.state, e.id = 'done', msg.id
            self:save_journal()
        else
            self:give_back(e)
        end
    elseif e and e.op == 'deposit' then
        if msg.ok then
            e.state = 'done'
            self:save_journal()
        else
            local hero = world.hero()
            local ok = hero and hero:add_gold(e.gold)
            if ok ~= false then self:drop(e.rid) end
            self:save_journal()
        end
    end
    if p and p.cb then p.cb(msg) end
end

---------------------------------------------------------------------------------------------------------------
-- the game's side of a transfer
---------------------------------------------------------------------------------------------------------------
local function place(bytes)
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then
            local id = inv.add(c, bytes)
            if id then return id, which end
        end
    end
end

-- A refused sale: the item goes back into the inventory (or waits in the journal as 'return').
function C:give_back(e)
    local bytes = inv.unhex(e.data)
    if bytes and place(bytes) then
        self:drop(e.rid)
    else
        e.state = 'return'
    end
    self:save_journal()
end

function C:delivered(msg, e)
    if not e then
        e = {rid = msg.rid, op = 'collect', mid = msg.mid, state = 'asked', session = self.session}
        table.insert(self.journal.entries, e)
    end
    e.mid = e.mid or msg.mid
    if e.state ~= 'received' then
        if msg.kind == 'gold' then
            local hero = world.hero()
            if not hero then return self:note('no hero to give the gold to', false) end
            local ok, err = hero:add_gold(msg.gold or 0)
            if ok == false or ok == nil and err then
                return self:note('the gold could not be added: ' .. tostring(err), false)
            end
            self:note(('%d gold taken out of the market'):format(msg.gold or 0))
        else
            local bytes = msg.data and inv.unhex(msg.data)
            if not bytes then return self:note('the delivered item is damaged; it stays in the mailbox', false) end
            local id, where = place(bytes)
            if not id then
                -- the market keeps it reserved for this rid; collect again with room
                return self:note('no room in the backpack or the chest: make room and collect again', false)
            end
            self:note(('%s is in your %s. Save the game now.'):format(msg.name or 'The item', where))
        end
        e.state = 'received'
        self:save_journal()
    end
    self:send({op = 'collected', rid = msg.rid})
end

---------------------------------------------------------------------------------------------------------------
-- what the panel calls
---------------------------------------------------------------------------------------------------------------
function C:browse(q, sort, desc, page) return self:query({op = 'browse', q = q, sort = sort, desc = desc, page = page}) end
function C:refresh_mine() return self:query({op = 'mine'}) end
function C:refresh_mail() return self:query({op = 'mail'}) end
function C:fetch_item(id)
    if self.items[id] == nil then
        self.items[id] = 'asked'
        self:query({op = 'item', id = id})
    end
    local d = self.items[id]
    return type(d) == 'string' and d ~= 'asked' and d or nil
end
function C:fetch_history(type_id)
    if not self.history[type_id] then
        self.history[type_id] = {asked = true}
        self:query({op = 'history', type = type_id})
    end
    return self.history[type_id]
end

function C:wallet() return self.info and self.info.wallet or 0 end

-- Gold from the hero into the wallet. cb(ok, err).
function C:deposit(gold, cb)
    gold = math.floor(tonumber(gold) or 0)
    local hero = world.hero()
    if not hero then return cb and cb(false, 'no hero') end
    local have = hero:gold() or 0
    if gold <= 0 then return cb and cb(false, 'nothing to deposit') end
    if gold > have then return cb and cb(false, ('you carry %d gold'):format(have)) end
    local rid = self:new_rid()
    local e = {rid = rid, op = 'deposit', state = 'prepared', gold = gold, before = have, session = self.session,
        market = self.info and self.info.market, t = os.time()}
    table.insert(self.journal.entries, e)
    if not self:save_journal() then self:drop(rid) return cb and cb(false, 'cannot write the journal') end
    local ok, err = hero:add_gold(-gold)
    if ok == false or (ok == nil and err) then
        self:drop(rid)
        self:save_journal()
        return cb and cb(false, 'the gold could not be taken: ' .. tostring(err))
    end
    e.after, e.state = hero:gold(), 'sent'
    self:save_journal()
    self:request({op = 'deposit', rid = rid, gold = gold}, function(a) if cb then cb(a.ok, a.err) end end)
end

function C:withdraw(gold, cb)
    gold = math.floor(tonumber(gold) or 0)
    if gold <= 0 then return cb and cb(false, 'nothing to take out') end
    local rid = self:new_rid()
    table.insert(self.journal.entries, {rid = rid, op = 'collect', state = 'asked', kind = 'gold', gold = gold,
        session = self.session, t = os.time()})
    self:save_journal()
    self:request({op = 'withdraw', rid = rid, gold = gold}, function(a)
        if a.op == 'result' and not a.ok then
            self:drop(rid)
            self:save_journal()
        end
        if cb then cb(a.op == 'deliver' or a.ok, a.err) end
    end)
end

-- Calls fn once the wallet holds `need` gold, depositing the difference from the hero first.
function C:with_gold(need, fn)
    local missing = need - self:wallet()
    if missing <= 0 then return fn(true) end
    self:deposit(missing, function(ok, err) if ok then fn(true) else fn(false, err) end end)
end

-- Puts `it` (an item of `container`) up for sale. cb(ok, err).
function C:sell(container, it, meta, price, days, cb)
    local bytes, err = inv.export(it.id)
    if not bytes then return cb(false, err) end
    local fee = 0
    if self.info and self.info.rules then
        local r = self.info.rules
        if (r.fee_per_day or 0) > 0 then fee = math.max(r.fee_min or 0, math.floor(price * r.fee_per_day / 100 * days)) end
    end
    self:with_gold(fee, function(ok, gerr)
        if not ok then return cb(false, 'the listing fee: ' .. tostring(gerr)) end
        local rid = self:new_rid()
        local e = {rid = rid, op = 'sell', state = 'prepared', data = inv.hex(bytes), price = price, days = days,
            meta = meta, session = self.session, market = self.info and self.info.market, t = os.time()}
        table.insert(self.journal.entries, e)
        if not self:save_journal() then self:drop(rid) return cb(false, 'cannot write the journal') end
        local got, rerr = inv.remove(container, it.id)
        if not got then
            self:drop(rid)
            self:save_journal()
            return cb(false, rerr or 'the item could not be taken out')
        end
        e.state = 'sent'
        self:save_journal()
        self:request({op = 'sell', rid = rid, data = e.data, price = price, days = days, meta = meta}, function(a)
            cb(a.ok, a.err)
        end)
    end)
end

function C:buy(row, cb)
    self:with_gold(row.price, function(ok, err)
        if not ok then return cb(false, err) end
        self:request({op = 'buy', id = row.id, price = row.price}, function(a) cb(a.ok, a.err) end)
    end)
end

function C:cancel(id, cb)
    self:request({op = 'cancel', id = id}, function(a) cb(a.ok, a.err) end)
end

function C:collect(mid, cb)
    for _, e in ipairs(self.journal.entries) do
        if e.op == 'collect' and e.mid == mid and e.state == 'asked' then
            -- asked before (no room then?): the same rid again
            self.pending[e.rid] = nil
            return self:request({op = 'collect', rid = e.rid, mid = mid}, function(a) if cb then cb(a.op == 'deliver', a.err) end end)
        end
    end
    local rid = self:new_rid()
    table.insert(self.journal.entries, {rid = rid, op = 'collect', mid = mid, state = 'asked', session = self.session,
        t = os.time()})
    self:save_journal()
    self:request({op = 'collect', rid = rid, mid = mid}, function(a)
        if a.op == 'result' and not a.ok then
            self:drop(rid)
            self:save_journal()
        end
        if cb then cb(a.op == 'deliver', a.err) end
    end)
end

-- Items of refused sales that did not fit back (journal state 'return').
function C:returns()
    local list = {}
    for _, e in ipairs(self.journal.entries) do
        if e.op == 'sell' and e.state == 'return' then list[#list + 1] = e end
    end
    return list
end

function C:take_return(e)
    self:give_back(e)
    return not self:entry(e.rid)
end

---------------------------------------------------------------------------------------------------------------
-- the crash check (DESIGN.md, section 4, step 5)
---------------------------------------------------------------------------------------------------------------
function C:session_start()
    self.session = ('%x%04x'):format(os.time(), math.random(0, 0xFFFF))
    self.checked = nil
end

function C:session_stop()
    self.session, self.checked = nil, nil
end

-- The exports of the items of the backpack and the chest, as hex.
local function inventory_exports()
    local set = {}
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then
            for _, it in ipairs(c:items()) do
                local b = inv.export(it.id)
                if b then set[inv.hex(b)] = true end
            end
        end
    end
    return set
end

function C:crash_check()
    self.checked = true
    local market = self.info and self.info.market
    local have, hero = nil, world.hero()
    local changed = false
    local keep = {}
    for _, e in ipairs(self.journal.entries) do
        local old = e.session ~= self.session
        local here = (not e.market) or e.market == market
        if not old or not here then
            keep[#keep + 1] = e
        elseif e.op == 'sell' and e.state == 'prepared' then
            changed = true      -- never sent; the item went down with the crash: the savegame has it
        elseif e.op == 'sell' and (e.state == 'sent' or e.state == 'done') then
            have = have or inventory_exports()
            if have[e.data] then
                -- the savegame still has the item: the sale must go
                self:send({op = 'revoke', rid = e.rid, what = 'sell'})
                e.state, e.session = 'revoking', self.session
                keep[#keep + 1] = e
                self.pending[e.rid] = {msg = {op = 'revoke', rid = e.rid, what = 'sell'}, at = gear.time()}
                self:note('A sale did not reach your savegame (the game ended before saving): it was taken off the market')
            elseif e.state == 'sent' then
                e.session = self.session
                keep[#keep + 1] = e
                self:request({op = 'sell', rid = e.rid, data = e.data, price = e.price, days = e.days, meta = e.meta})
            end
            changed = true
        elseif e.op == 'deposit' and e.state == 'prepared' then
            changed = true
        elseif e.op == 'deposit' and (e.state == 'sent' or e.state == 'done') then
            if hero and hero:gold() == e.before then
                self:send({op = 'revoke', rid = e.rid, what = 'deposit'})
                e.state, e.session = 'revoking', self.session
                keep[#keep + 1] = e
                self.pending[e.rid] = {msg = {op = 'revoke', rid = e.rid, what = 'deposit'}, at = gear.time()}
                self:note('A gold deposit did not reach your savegame: it was taken back out of your wallet')
            elseif e.state == 'sent' then
                e.session = self.session
                keep[#keep + 1] = e
                self:request({op = 'deposit', rid = e.rid, gold = e.gold})
            end
            changed = true
        elseif e.op == 'collect' then
            e.session = self.session
            keep[#keep + 1] = e
            self:reask(e)
            changed = true
        elseif e.state == 'revoking' then
            e.session = self.session
            keep[#keep + 1] = e
            self.pending[e.rid] = {msg = {op = 'revoke', rid = e.rid, what = e.op}, at = gear.time()}
            self:send({op = 'revoke', rid = e.rid, what = e.op})
            changed = true
        else
            keep[#keep + 1] = e
        end
    end
    if changed then
        self.journal.entries = keep
        self:save_journal()
    end
end

return M
