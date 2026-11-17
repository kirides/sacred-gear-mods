-- The market: listings, wallets, mailboxes, the rules, persistence. Pure Lua: no game calls, so the same code can run
-- in a player's game (single player, the host of a network game), later in GameServer.exe or in the C# GameServer's
-- Lua (DESIGN.md, section 2). Everything it needs comes in `deps`:
--
--   deps.now()               -> seconds (os.time on the machine that runs the market)
--   deps.load()              -> the saved state table, or nil (no market yet), or nil, error (unreadable: read-only)
--   deps.save(state)         -> true | nil, error (must be atomic: temp file + rename)
--   deps.send(slot, msg)     -> sends a message table to a player
--   deps.log(text)           (optional)
--   deps.random_id()         -> a random hex string (optional; the market id)
--
-- Every change is written before its answer is sent. Requests handled in the same tick share one write (`flush`): if
-- that write fails, the whole batch is undone and every changing request of it is refused. Requests that change
-- something carry a request id (rid); the answer to a rid is kept for RID_DAYS days, so a repeated request gets the
-- same answer and changes nothing (DESIGN.md, section 4).
local M = {}
M.VERSION = 1           -- the file format
M.PROTOCOL = 1          -- the messages

local DAY = 86400
local RID_DAYS = 14
local HISTORY = 400     -- sales kept for price discovery
local LOG_KEEP = 200
local MAX_DATA = 16384  -- hex characters of one item's data
local MAX_TEXT = 2000   -- characters of a listing's search text

M.DEFAULT_RULES = {
    durations = {1, 3, 7},          -- days
    fee_per_day = 0.5,              -- percent of the price per listed day, paid from the wallet when listing
    fee_min = 1,                    -- gold, when fee_per_day > 0
    sale_cut = 5,                   -- percent of the price taken when it sells
    max_per_seller = 20,
    max_listings = 400,
    price_min = 1,
    price_max = 2000000000,
    wallet_max = 2000000000,
    page_size = 10,
}

local QUALITY_RANK = {normal = 1, magic = 2, rare = 3, unique = 4, set = 5}
M.QUALITY_RANK = QUALITY_RANK

---------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------
local function copy(v)
    if type(v) ~= 'table' then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
M.copy = copy

local function int(v)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v ~= math.floor(v) then return nil end
    return v
end

local function str(v, max)
    if type(v) ~= 'string' then return nil end
    if max and #v > max then return v:sub(1, max) end
    return v
end

-- The game's tooltip text without its codes: `\c` and `\w` (a colour, 8 hex digits) and `\g` (an image: a colour and
-- an image id, 16 characters, the id padded with spaces).
function M.plain(s)
    if type(s) ~= 'string' then return s end
    s = s:gsub('\\g%x%x%x%x%x%x%x%x[%x ][%x ][%x ][%x ][%x ][%x ][%x ][%x ]', '')
    s = s:gsub('\\[cw]%x%x%x%x%x%x%x%x', '')
    return s
end

local function trim(s) return type(s) == 'string' and (s:gsub('^%s+', ''):gsub('%s+$', '')) or s end

-- The item's type id: the first four bytes of its data, little endian (as gear.inv.export writes it).
function M.type_of(hex)
    if type(hex) ~= 'string' or #hex < 8 then return nil end
    local b = {}
    for i = 0, 3 do
        local v = tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16)
        if not v then return nil end
        b[i + 1] = v
    end
    return b[1] + b[2] * 256 + b[3] * 65536 + b[4] * 16777216
end

local function valid_hex(hex)
    return type(hex) == 'string' and #hex >= 8 and #hex <= MAX_DATA and #hex % 2 == 0 and not hex:find('[^0-9a-f]')
end

local function median(list)
    if #list == 0 then return nil end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    local n = #s
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return math.floor((s[n / 2] + s[n / 2 + 1]) / 2)
end
M.median = median

function M.fee(rules, price, days)
    if (rules.fee_per_day or 0) <= 0 then return 0 end
    return math.max(rules.fee_min or 0, math.floor(price * rules.fee_per_day / 100 * days))
end

function M.cut(rules, price)
    return math.floor(price * (rules.sale_cut or 0) / 100)
end

local function new_state(id)
    return {
        version = M.VERSION, market_id = id, next_id = 1, next_mid = 1,
        listings = {}, mail = {}, wallets = {}, players = {}, sales = {}, rids = {}, log = {},
    }
end

-- Fills in what an older or hand-edited file lacks; nil, error if it is not a market file.
local function normalize(s)
    if type(s) ~= 'table' then return nil, 'not a market file' end
    if type(s.version) ~= 'number' then return nil, 'no version' end
    if s.version > M.VERSION then return nil, 'written by a newer version of the mod (' .. s.version .. ')' end
    for _, k in ipairs({'listings', 'mail', 'sales', 'log'}) do
        if type(s[k]) ~= 'table' then s[k] = {} end
    end
    for _, k in ipairs({'wallets', 'players', 'rids'}) do
        if type(s[k]) ~= 'table' then s[k] = {} end
    end
    s.next_id = int(s.next_id) or 1
    s.next_mid = int(s.next_mid) or 1
    for _, l in ipairs(s.listings) do
        if type(l) ~= 'table' or not int(l.id) or not valid_hex(l.data) then return nil, 'a listing is damaged' end
        if l.id >= s.next_id then s.next_id = l.id + 1 end
    end
    for _, m in ipairs(s.mail) do
        if type(m) ~= 'table' or not int(m.mid) then return nil, 'a mailbox entry is damaged' end
        if m.mid >= s.next_mid then s.next_mid = m.mid + 1 end
    end
    return s
end

---------------------------------------------------------------------------------------------------------------
-- the market object
---------------------------------------------------------------------------------------------------------------
local Market = {}
Market.__index = Market

function M.new(deps, rules)
    local self = setmetatable({deps = deps, rules = {}, out = {}, batch = nil, problem = nil, note = nil,
        online = {}, last_sweep = -1e18}, Market)
    for k, v in pairs(M.DEFAULT_RULES) do self.rules[k] = v end
    for k, v in pairs(rules or {}) do self.rules[k] = v end
    self:load()
    return self
end

function Market:log(text)
    if self.deps.log then self.deps.log(text) end
end

function Market:load()
    local s, err = self.deps.load()
    if s == nil and err then
        self.problem = 'the market file cannot be read (' .. tostring(err) .. '); the market is closed until it is fixed'
        self.state = new_state('broken')
        return
    end
    if s == nil then
        local id = self.deps.random_id and self.deps.random_id() or tostring(self.deps.now())
        self.state = new_state(id)
        return
    end
    local n, why = normalize(s)
    if not n then
        self.problem = 'the market file cannot be used (' .. why .. '); the market is closed until it is fixed'
        self.state = new_state('broken')
        return
    end
    self.state = n
end

function Market:set_rules(rules)
    for k, v in pairs(rules) do self.rules[k] = v end
end

-- Remembers where a player is now (their slot) for notifications.
function Market:seen(key, slot)
    if key then self.online[key] = slot end
end

function Market:left(slot)
    for k, s in pairs(self.online) do
        if s == slot then self.online[k] = nil end
    end
end

-- Messages to send after the batch is written: {slot, msg, changing}.
function Market:reply(slot, msg, changing)
    self.out[#self.out + 1] = {slot = slot, msg = msg, changing = changing}
end

-- Called before the first change of a batch: keeps the state to roll back to.
function Market:begin()
    if not self.batch then self.batch = copy(self.state) end
end

function Market:add_log(kind, text)
    local log = self.state.log
    log[#log + 1] = {t = self.deps.now(), kind = kind, text = text}
    while #log > LOG_KEEP do table.remove(log, 1) end
    self:log(kind .. ': ' .. text)
end

-- Writes the batch (if anything changed) and sends the answers. On a failed write the state goes back to where the
-- batch began and every changing answer becomes a refusal.
function Market:flush()
    local out = self.out
    self.out = {}
    if self.batch then
        local ok, err = self.deps.save(self.state)
        if not ok then
            self.state = self.batch
            self:log('market write failed: ' .. tostring(err))
            for _, o in ipairs(out) do
                if o.changing then
                    o.msg = {op = 'result', rid = o.msg.rid, ok = false, err = 'the market could not save; nothing changed'}
                end
            end
            -- notifications of the failed batch must not go out
            local kept = {}
            for _, o in ipairs(out) do if o.msg.op ~= 'notify' then kept[#kept + 1] = o end end
            out = kept
        end
        self.batch = nil
    end
    for _, o in ipairs(out) do self.deps.send(o.slot, o.msg) end
end

---------------------------------------------------------------------------------------------------------------
-- request ids
---------------------------------------------------------------------------------------------------------------
function Market:rid_record(key, rid)
    local r = self.state.rids[key]
    return r and r[rid]
end

function Market:remember(key, rid, rec)
    local r = self.state.rids[key]
    if not r then r = {} self.state.rids[key] = r end
    rec.t = self.deps.now()
    r[rid] = rec
end

---------------------------------------------------------------------------------------------------------------
-- lookups
---------------------------------------------------------------------------------------------------------------
function Market:listing(id)
    for i, l in ipairs(self.state.listings) do
        if l.id == id then return l, i end
    end
end

function Market:mail_entry(mid)
    for i, m in ipairs(self.state.mail) do
        if m.mid == mid then return m, i end
    end
end

function Market:count_seller(key)
    local n = 0
    for _, l in ipairs(self.state.listings) do if l.seller == key then n = n + 1 end end
    return n
end

function Market:wallet(key)
    return self.state.wallets[key] or 0
end

function Market:add_mail(owner, kind, fields)
    local s = self.state
    local m = {mid = s.next_mid, owner = owner, kind = kind, t = self.deps.now()}
    s.next_mid = s.next_mid + 1
    for k, v in pairs(fields) do m[k] = v end
    s.mail[#s.mail + 1] = m
    return m
end

local function item_mail_fields(l, reason)
    return {reason = reason, data = l.data, type = l.type, name = l.meta.name, quality = l.meta.quality,
        category = l.meta.category, w = l.meta.w, h = l.meta.h, price = l.price}
end

function Market:notify(key, msg)
    local slot = self.online[key]
    if slot then
        msg.op = 'notify'
        self:reply(slot, msg, false)
    end
end

---------------------------------------------------------------------------------------------------------------
-- expiry and pruning
---------------------------------------------------------------------------------------------------------------
-- Moves listings whose time is up to their sellers' mailboxes and forgets old request ids. Call it now and then
-- (every minute is plenty); it starts a batch only if something changes.
function Market:sweep(force)
    if self.problem then return end
    local now = self.deps.now()
    if not force and now - self.last_sweep < 60 then return end
    self.last_sweep = now
    local s = self.state
    local i = 1
    while i <= #s.listings do
        local l = s.listings[i]
        if l.ends <= now then
            self:begin()
            table.remove(s.listings, i)
            self:add_mail(l.seller, 'item', item_mail_fields(l, 'expired'))
            self:notify(l.seller, {kind = 'expired', name = l.meta.name})
        else
            i = i + 1
        end
    end
    local old = now - RID_DAYS * DAY
    for key, r in pairs(s.rids) do
        for rid, rec in pairs(r) do
            -- a delivery that is still waiting for its confirmation stays
            if (rec.t or 0) < old and not rec.pending then
                self:begin()
                r[rid] = nil
            end
        end
        if next(r) == nil then
            self:begin()
            s.rids[key] = nil
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- browsing
---------------------------------------------------------------------------------------------------------------
local function lower(s) return type(s) == 'string' and s:lower() or '' end

local function matches(l, q, now)
    if l.ends <= now then return false end
    local m = l.meta
    if q.text and q.text ~= '' then
        local hay = lower(m.name) .. '\n' .. lower(m.text) .. '\n' .. lower(l.seller_name)
        for word in q.text:lower():gmatch('%S+') do
            if not hay:find(word, 1, true) then return false end
        end
    end
    if q.category and q.category ~= '' and m.category ~= q.category then return false end
    if q.quality and q.quality ~= '' and m.quality ~= q.quality then return false end
    if q.min_quality and (QUALITY_RANK[m.quality] or 0) < (QUALITY_RANK[q.min_quality] or 0) then return false end
    if q.class and q.class ~= '' and type(m.classes) == 'table' and #m.classes > 0 then
        local ok = false
        for _, c in ipairs(m.classes) do if c == q.class then ok = true break end end
        if not ok then return false end
    end
    local lvl = m.level or 0
    if q.min_level and lvl < q.min_level then return false end
    if q.max_level and lvl > q.max_level then return false end
    if q.min_price and l.price < q.min_price then return false end
    if q.max_price and l.price > q.max_price then return false end
    if q.seller and q.seller ~= '' and l.seller ~= q.seller then return false end
    if q.not_seller and l.seller == q.not_seller then return false end
    if q.type and l.type ~= q.type then return false end
    return true
end

local SORTS = {
    price = function(l) return l.price end,
    ppl = function(l) return l.price / math.max(1, l.meta.level or 1) end,
    ends = function(l) return l.ends end,
    newest = function(l) return -l.created end,
    name = function(l) return lower(l.meta.name) end,
    level = function(l) return l.meta.level or 0 end,
    quality = function(l) return QUALITY_RANK[l.meta.quality] or 0 end,
}
M.SORTS = {'price', 'ppl', 'ends', 'newest', 'name', 'level', 'quality'}

function Market:row(l)
    local m = l.meta
    return {id = l.id, type = l.type, name = m.name, quality = m.quality, category = m.category, w = m.w, h = m.h,
        level = m.level, classes = m.classes, price = l.price, seller = l.seller_name, seller_key = l.seller,
        ends = l.ends, created = l.created, median = self:median_of(l.type)}
end

function Market:median_of(type_id)
    local prices = {}
    local sales = self.state.sales
    for i = #sales, 1, -1 do
        local s = sales[i]
        if s.type == type_id then
            prices[#prices + 1] = s.price
            if #prices >= 10 then break end
        end
    end
    return median(prices), #prices
end

function Market:browse(q, sort, desc, page)
    q = type(q) == 'table' and q or {}
    local now = self.deps.now()
    local list = {}
    for _, l in ipairs(self.state.listings) do
        if matches(l, q, now) then list[#list + 1] = l end
    end
    local key = SORTS[sort] or SORTS.price
    table.sort(list, function(a, b)
        local ka, kb = key(a), key(b)
        if ka == kb then return a.id < b.id end
        if desc then return ka > kb end
        return ka < kb
    end)
    local per = self.rules.page_size
    local pages = math.max(1, math.ceil(#list / per))
    page = math.max(1, math.min(int(page) or 1, pages))
    local rows = {}
    for i = (page - 1) * per + 1, math.min(#list, page * per) do rows[#rows + 1] = self:row(list[i]) end
    return {rows = rows, total = #list, page = page, pages = pages}
end

---------------------------------------------------------------------------------------------------------------
-- requests
---------------------------------------------------------------------------------------------------------------
local function result(rid, ok, err, extra)
    local r = {op = 'result', rid = rid, ok = ok, err = err}
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

function Market:info(key)
    local mine, mail = 0, 0
    for _, l in ipairs(self.state.listings) do if l.seller == key then mine = mine + 1 end end
    local pending = {}
    for _, m in ipairs(self.state.mail) do
        if m.owner == key then
            mail = mail + 1
            if m.delivering then pending[#pending + 1] = m.delivering end
        end
    end
    local r = self.rules
    return {op = 'info', v = M.PROTOCOL, market = self.state.market_id, now = self.deps.now(), problem = self.problem,
        rules = {durations = r.durations, fee_per_day = r.fee_per_day, fee_min = r.fee_min, sale_cut = r.sale_cut,
            max_per_seller = r.max_per_seller, max_listings = r.max_listings, price_min = r.price_min,
            price_max = r.price_max, page_size = r.page_size},
        wallet = self:wallet(key), mine = mine, mail = mail, listings = #self.state.listings, pending = pending}
end

-- Checks the player's key and secret: the first request with a key binds the secret to it.
function Market:identify(from, msg)
    local key = from.key or str(msg.key, 80)
    if not key or key == '' then return nil, 'no player identity' end
    local secret = str(msg.secret, 80)
    if not secret or #secret < 8 then return nil, 'no player secret' end
    local p = self.state.players[key]
    local name = from.name or str(msg.name, 40) or key
    if not p then
        self:begin()
        self.state.players[key] = {name = name, secret = secret, first = self.deps.now(), seen = self.deps.now()}
        return key, name, true
    end
    if p.secret ~= secret then return nil, 'this hero name is taken by another player on this market' end
    if p.name ~= name then
        self:begin()
        p.name = name
    end
    return key, name
end

-- Handles one message from a player. `from`: {slot, key?, name?} (key and name as the receiving game sees that
-- player's hero; for a message from the local game the same). Answers are queued; call flush() after the tick.
function Market:handle(from, msg)
    if type(msg) ~= 'table' or type(msg.op) ~= 'string' then return end
    local slot = from.slot
    if self.problem then
        if msg.rid then
            self:reply(slot, result(msg.rid, false, self.problem))
        else
            self:reply(slot, {op = 'info', v = M.PROTOCOL, problem = self.problem, market = self.state.market_id})
        end
        return
    end
    local key, name = self:identify(from, msg)
    if not key then
        if msg.rid then self:reply(slot, result(msg.rid, false, name)) else
            self:reply(slot, {op = 'error', err = name, req = msg.req})
        end
        return
    end
    self:seen(key, slot)
    local fn = self['op_' .. msg.op]
    if not fn then
        self:reply(slot, {op = 'error', err = 'unknown request ' .. msg.op, req = msg.req})
        return
    end
    -- a changing request that was answered before gets the same answer again
    if msg.rid then
        local rid = str(msg.rid, 64)
        if not rid then return end
        local rec = self:rid_record(key, rid)
        if rec and rec.reply and msg.op ~= 'revoke' and msg.op ~= 'collected' then
            self:reply(slot, rec.reply, false)
            return
        end
    end
    fn(self, slot, key, name, msg)
end

function Market:op_hello(slot, key)
    self:reply(slot, self:info(key))
end

function Market:op_browse(slot, key, _, msg)
    local q = type(msg.q) == 'table' and msg.q or {}
    if q.mine then q.seller = key end
    local r = self:browse(q, msg.sort, msg.desc, msg.page)
    r.op, r.req = 'page', msg.req
    self:reply(slot, r)
end

function Market:op_item(slot, _, _, msg)
    local l = self:listing(int(msg.id) or -1)
    if not l then
        self:reply(slot, {op = 'item', id = msg.id, missing = true, req = msg.req})
        return
    end
    self:reply(slot, {op = 'item', id = l.id, data = l.data, req = msg.req})
end

function Market:op_history(slot, _, _, msg)
    local t = int(msg.type)
    local prices = {}
    local sales = self.state.sales
    for i = #sales, 1, -1 do
        if sales[i].type == t then
            prices[#prices + 1] = {price = sales[i].price, t = sales[i].t}
            if #prices >= 10 then break end
        end
    end
    local list = {}
    for i, p in ipairs(prices) do list[i] = p.price end
    self:reply(slot, {op = 'history', type = t, sales = prices, median = median(list), req = msg.req})
end

function Market:op_mail(slot, key, _, msg)
    local list = {}
    for _, m in ipairs(self.state.mail) do
        if m.owner == key then
            list[#list + 1] = {mid = m.mid, kind = m.kind, reason = m.reason, name = m.name, quality = m.quality,
                type = m.type, w = m.w, h = m.h, gold = m.gold, price = m.price, t = m.t, delivering = m.delivering}
        end
    end
    self:reply(slot, {op = 'mail', entries = list, wallet = self:wallet(key), req = msg.req})
end

function Market:op_mine(slot, key, _, msg)
    local rows = {}
    for _, l in ipairs(self.state.listings) do
        if l.seller == key then rows[#rows + 1] = self:row(l) end
    end
    table.sort(rows, function(a, b) return a.ends < b.ends end)
    self:reply(slot, {op = 'mine', rows = rows, wallet = self:wallet(key), req = msg.req})
end

local function clean_meta(meta, data_type)
    meta = type(meta) == 'table' and meta or {}
    local classes = {}
    if type(meta.classes) == 'table' then
        for _, c in ipairs(meta.classes) do
            if type(c) == 'string' and #c <= 20 then classes[#classes + 1] = c end
        end
    end
    local q = QUALITY_RANK[meta.quality] and meta.quality or 'normal'
    local name = trim(M.plain(meta.name))
    return {
        name = str(name ~= '' and name or nil, 80) or ('item ' .. tostring(data_type)),
        quality = q,
        category = str(meta.category, 20) or 'other',
        w = math.max(1, math.min(4, int(meta.w) or 1)),
        h = math.max(1, math.min(6, int(meta.h) or 1)),
        level = math.max(0, math.min(999, int(meta.level) or 0)),
        classes = classes,
        text = str(M.plain(meta.text), MAX_TEXT) or '',
    }
end

function Market:op_sell(slot, key, name, msg)
    local rid, r = msg.rid, self.rules
    local function refuse(err)
        self:begin()
        local rep = result(rid, false, err)
        self:remember(key, rid, {op = 'sell', reply = rep})
        self:reply(slot, rep, true)
    end
    if not rid then return self:reply(slot, {op = 'error', err = 'a sale needs a request id'}) end
    local rec = self:rid_record(key, rid)
    if rec and rec.revoked then return refuse('this sale was withdrawn') end
    if not valid_hex(msg.data) then return refuse('the item data is damaged') end
    local price, days = int(msg.price), int(msg.days)
    if not price or price < r.price_min or price > r.price_max then
        return refuse(('the price must be %d to %d gold'):format(r.price_min, r.price_max))
    end
    local okdays = false
    for _, d in ipairs(r.durations) do if d == days then okdays = true end end
    if not okdays then return refuse('that duration is not offered here') end
    if #self.state.listings >= r.max_listings then return refuse('the market is full') end
    if self:count_seller(key) >= r.max_per_seller then
        return refuse(('you have %d listings already, the most allowed'):format(r.max_per_seller))
    end
    local t = M.type_of(msg.data)
    local meta = clean_meta(msg.meta, t)
    if msg.meta and msg.meta.type and int(msg.meta.type) ~= t then return refuse('the item data does not match its type') end
    local fee = M.fee(r, price, days)
    if self:wallet(key) < fee then return refuse(('the listing fee is %d gold; your wallet has %d'):format(fee, self:wallet(key))) end
    self:begin()
    local s = self.state
    local now = self.deps.now()
    s.wallets[key] = self:wallet(key) - fee
    local l = {id = s.next_id, seller = key, seller_name = name, data = msg.data, type = t, meta = meta, price = price,
        created = now, ends = now + days * DAY, fee = fee, rid = rid}
    s.next_id = s.next_id + 1
    s.listings[#s.listings + 1] = l
    local rep = result(rid, true, nil, {id = l.id, fee = fee, wallet = s.wallets[key], ends = l.ends})
    self:remember(key, rid, {op = 'sell', reply = rep, listing = l.id})
    self:reply(slot, rep, true)
end

function Market:op_cancel(slot, key, _, msg)
    local rid = msg.rid
    if not rid then return end
    self:begin()
    local l, i = self:listing(int(msg.id) or -1)
    local rep
    if not l or l.seller ~= key then
        rep = result(rid, false, 'no such listing of yours (sold or expired already?)')
    else
        table.remove(self.state.listings, i)
        local m = self:add_mail(key, 'item', item_mail_fields(l, 'cancelled'))
        rep = result(rid, true, nil, {mid = m.mid})
    end
    self:remember(key, rid, {op = 'cancel', reply = rep})
    self:reply(slot, rep, true)
end

function Market:op_buy(slot, key, name, msg)
    local rid = msg.rid
    if not rid then return end
    self:begin()
    local s = self.state
    local l, i = self:listing(int(msg.id) or -1)
    local rep
    if not l or l.ends <= self.deps.now() then
        rep = result(rid, false, 'this item is no longer for sale')
    elseif l.seller == key then
        rep = result(rid, false, 'you cannot buy your own item')
    elseif int(msg.price) ~= l.price then
        rep = result(rid, false, 'the price is not what you saw')
    elseif self:wallet(key) < l.price then
        rep = result(rid, false, ('it costs %d gold; your wallet has %d'):format(l.price, self:wallet(key)))
    else
        table.remove(s.listings, i)
        s.wallets[key] = self:wallet(key) - l.price
        local net = l.price - M.cut(self.rules, l.price)
        s.wallets[l.seller] = math.min(self.rules.wallet_max, self:wallet(l.seller) + net)
        local m = self:add_mail(key, 'item', item_mail_fields(l, 'bought'))
        m.seller_name = l.seller_name
        s.sales[#s.sales + 1] = {type = l.type, name = l.meta.name, quality = l.meta.quality, price = l.price,
            t = self.deps.now(), seller = l.seller, buyer = key}
        while #s.sales > HISTORY do table.remove(s.sales, 1) end
        rep = result(rid, true, nil, {mid = m.mid, wallet = s.wallets[key]})
        self:notify(l.seller, {kind = 'sold', name = l.meta.name, price = l.price, net = net, buyer = name})
        self:add_log('sale', ('%s bought %s from %s for %d'):format(key, l.meta.name, l.seller, l.price))
    end
    self:remember(key, rid, {op = 'buy', reply = rep})
    self:reply(slot, rep, true)
end

function Market:op_deposit(slot, key, _, msg)
    local rid = msg.rid
    if not rid then return end
    self:begin()
    local gold = int(msg.gold)
    local rep
    local rec = self:rid_record(key, rid)
    if rec and rec.revoked then
        rep = result(rid, false, 'this deposit was withdrawn')
    elseif not gold or gold <= 0 then
        rep = result(rid, false, 'nothing to deposit')
    elseif self:wallet(key) + gold > self.rules.wallet_max then
        rep = result(rid, false, 'the wallet cannot hold that much')
    else
        self.state.wallets[key] = self:wallet(key) + gold
        rep = result(rid, true, nil, {wallet = self.state.wallets[key]})
    end
    self:remember(key, rid, {op = 'deposit', reply = rep, gold = rep.ok and gold or nil})
    self:reply(slot, rep, true)
end

-- Gold out of the wallet: it becomes a mailbox entry that is delivered at once (the same path as an item).
function Market:op_withdraw(slot, key, _, msg)
    local rid = msg.rid
    if not rid then return end
    self:begin()
    local gold = int(msg.gold)
    local rep
    if not gold or gold <= 0 then
        rep = result(rid, false, 'nothing to take out')
    elseif self:wallet(key) < gold then
        rep = result(rid, false, ('your wallet has %d gold'):format(self:wallet(key)))
    else
        self.state.wallets[key] = self:wallet(key) - gold
        local m = self:add_mail(key, 'gold', {reason = 'withdrawn', gold = gold, name = 'Gold'})
        m.delivering = rid
        rep = {op = 'deliver', rid = rid, mid = m.mid, kind = 'gold', gold = gold, wallet = self.state.wallets[key]}
        self:remember(key, rid, {op = 'withdraw', reply = rep, pending = true, mid = m.mid})
        self:reply(slot, rep, true)
        return
    end
    self:remember(key, rid, {op = 'withdraw', reply = rep})
    self:reply(slot, rep, true)
end

-- A mailbox entry to the player: reserved for this rid until `collected`.
function Market:op_collect(slot, key, _, msg)
    local rid = msg.rid
    if not rid then return end
    local m = self:mail_entry(int(msg.mid) or -1)
    if not m or m.owner ~= key then
        self:begin()
        local rep = result(rid, false, 'nothing like that in your mailbox')
        self:remember(key, rid, {op = 'collect', reply = rep})
        return self:reply(slot, rep, true)
    end
    if m.delivering and m.delivering ~= rid then
        -- already on its way under another request id (an earlier attempt): hand out that delivery again
        local rec = self:rid_record(key, m.delivering)
        if rec and rec.reply then return self:reply(slot, rec.reply, false) end
    end
    self:begin()
    m.delivering = rid
    local rep = {op = 'deliver', rid = rid, mid = m.mid, kind = m.kind, data = m.data, gold = m.gold, name = m.name}
    self:remember(key, rid, {op = 'collect', reply = rep, pending = true, mid = m.mid})
    self:reply(slot, rep, true)
end

-- The player has the delivery: the entry goes.
function Market:op_collected(slot, key, _, msg)
    local rid = str(msg.rid, 64)
    if not rid then return end
    local rec = self:rid_record(key, rid)
    local done = false
    for i, m in ipairs(self.state.mail) do
        if m.owner == key and m.delivering == rid then
            self:begin()
            table.remove(self.state.mail, i)
            done = true
            break
        end
    end
    if rec and rec.pending then
        self:begin()
        rec.pending = nil
    end
    self:reply(slot, {op = 'collected', rid = rid, ok = true, removed = done, wallet = self:wallet(key)}, done)
end

-- The client found, at a game load, that a sale or deposit never reached its savegame (the item is back in the
-- inventory, or the gold): the listing is taken off (its item is dropped: the savegame has it) or the gold taken
-- back out of the wallet. An unknown rid is remembered as withdrawn so a late request with it is refused.
function Market:op_revoke(slot, key, _, msg)
    local rid = str(msg.rid, 64)
    if not rid then return end
    self:begin()
    local rec = self:rid_record(key, rid)
    local what
    if not rec then
        self:remember(key, rid, {op = msg.what or 'sell', revoked = true})
        what = 'unknown'
    elseif rec.revoked then
        what = 'again'
    elseif rec.op == 'sell' and rec.listing then
        local l, i = self:listing(rec.listing)
        if l then
            table.remove(self.state.listings, i)
            what = 'listing removed'
        else
            what = 'already sold or expired'
            self:add_log('duplicate', ('%s: sale %s (listing %d) was not in the savegame but is gone already')
                :format(key, rid, rec.listing))
        end
        rec.revoked = true
    elseif rec.op == 'deposit' and rec.gold then
        self.state.wallets[key] = self:wallet(key) - rec.gold
        what = 'gold taken back'
        rec.revoked = true
    else
        rec.revoked = true
        what = 'nothing to undo'
    end
    self:add_log('revoke', ('%s %s: %s'):format(key, rid, what))
    self:reply(slot, {op = 'revoked', rid = rid, what = what, wallet = self:wallet(key)}, true)
end

-- For the host's own view (and tests).
function Market:stats()
    local s = self.state
    local gold = 0
    for _, v in pairs(s.wallets) do gold = gold + v end
    return {listings = #s.listings, mail = #s.mail, wallets = gold, sales = #s.sales}
end

return M
