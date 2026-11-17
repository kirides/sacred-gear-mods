-- Unit tests of the market (core.lua). Plain Lua 5.1 / LuaJIT, no game:  luajit tests/core_test.lua  (from the mod's
-- folder). Exit code 0 when everything passes.
package.path = './?.lua;' .. package.path
local core = require('core')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

-- a fake world: a clock, a disk (stored by copy, as a JSON round trip would) and an outbox per slot
local function world()
    local w = {t = 1000000, disk = nil, fail_save = false, saves = 0, inbox = {}}
    w.deps = {
        now = function() return w.t end,
        load = function() return w.disk and core.copy(w.disk) or nil end,
        save = function(state)
            if w.fail_save then return nil, 'disk full' end
            w.saves = w.saves + 1
            w.disk = core.copy(state)
            return true
        end,
        send = function(slot, msg)
            w.inbox[slot] = w.inbox[slot] or {}
            table.insert(w.inbox[slot], msg)
        end,
        random_id = function() return 'm1' end,
    }
    function w.take(slot)
        local list = w.inbox[slot] or {}
        w.inbox[slot] = {}
        return list
    end
    function w.last(slot)
        local list = w.take(slot)
        return list[#list]
    end
    return w
end

local HEX = '2a010000' .. string.rep('ab', 60)     -- type 0x12A
local A = {slot = 1, key = 'anna:seraphim', name = 'Anna'}
local B = {slot = 2, key = 'bert:dwarf', name = 'Bert'}
local function req(m, from, msg)
    msg.secret = msg.secret or ('secret-' .. from.key)
    m:handle(from, msg)
    m:flush()
end

-- identity
do
    local w = world()
    local m = core.new(w.deps)
    req(m, A, {op = 'hello'})
    local info = w.last(1)
    eq(info.op, 'info', 'hello answers info')
    eq(info.market, 'm1', 'market id')
    eq(info.wallet, 0, 'empty wallet')
    m:handle({slot = 3, key = A.key, name = 'Anna'}, {op = 'hello', secret = 'another-secret'})
    m:flush()
    eq(w.last(3).op, 'error', 'a second player with the same hero key but another secret is refused')
end

-- deposit, sell, browse, buy, collect
do
    local w = world()
    local m = core.new(w.deps)
    req(m, A, {op = 'deposit', rid = 'a1', gold = 100})
    local r = w.last(1)
    check(r.ok and r.wallet == 100, 'deposit 100')
    req(m, A, {op = 'deposit', rid = 'a1', gold = 100})
    eq(w.last(1).wallet, 100, 'a repeated deposit (same rid) changes nothing')
    eq(m:wallet(A.key), 100, 'wallet still 100')

    req(m, A, {op = 'sell', rid = 'a2', data = HEX, price = 1000, days = 3,
        meta = {name = 'Sword of Tests', quality = 'rare', category = 'weapon', w = 1, h = 3, level = 12,
            classes = {'seraphim'}, text = 'Sword of Tests\nDamage 10-20\nLevel 12'}})
    r = w.last(1)
    check(r.ok, 'sell ok: ' .. tostring(r.err))
    eq(r.fee, 15, 'fee 0.5% x 3 days of 1000')
    eq(r.wallet, 85, 'fee paid from the wallet')
    local id = r.id
    req(m, A, {op = 'sell', rid = 'a2', data = HEX, price = 1000, days = 3})
    eq(#m.state.listings, 1, 'a repeated sale (same rid) lists once')

    req(m, B, {op = 'browse', q = {text = 'damage sword'}, sort = 'price'})
    local p = w.last(2)
    eq(p.total, 1, 'text search finds it (words in any order, tooltip lines)')
    eq(p.rows[1].seller, 'Anna', 'the seller name is shown')
    req(m, B, {op = 'browse', q = {category = 'armor'}})
    eq(w.last(2).total, 0, 'category filter')
    req(m, B, {op = 'browse', q = {class = 'dwarf'}})
    eq(w.last(2).total, 0, 'class filter')
    req(m, B, {op = 'browse', q = {min_level = 10, max_level = 15, min_quality = 'magic'}})
    eq(w.last(2).total, 1, 'level and quality filters')

    req(m, B, {op = 'item', id = id})
    eq(w.last(2).data, HEX, 'item data for the tooltip')

    req(m, B, {op = 'buy', rid = 'b1', id = id, price = 1000})
    r = w.last(2)
    check(not r.ok and r.err:find('wallet'), 'buying without gold is refused')
    -- a refused request is remembered too: a new attempt needs a new rid
    req(m, B, {op = 'deposit', rid = 'b2', gold = 5000})
    req(m, B, {op = 'buy', rid = 'b3', id = id, price = 999})
    check(not w.last(2).ok, 'a wrong price is refused')
    req(m, A, {op = 'buy', rid = 'a3', id = id, price = 1000})
    check(not w.last(1).ok, 'the seller cannot buy their own item')

    m:seen(A.key, 1)
    w.take(1)
    req(m, B, {op = 'buy', rid = 'b4', id = id, price = 1000})
    r = w.last(2)
    check(r.ok, 'buy ok')
    eq(r.wallet, 4000, 'price left the buyer wallet')
    eq(m:wallet(A.key), 85 + 950, 'seller got the price minus 5%')
    local n = w.take(1)
    eq(n[1] and n[1].kind, 'sold', 'the seller is told')
    eq(#m.state.listings, 0, 'listing gone')
    req(m, B, {op = 'buy', rid = 'b5', id = id, price = 1000})
    check(not w.last(2).ok, 'it cannot be bought twice')
    req(m, B, {op = 'buy', rid = 'b4', id = id, price = 1000})
    check(w.last(2).ok, 'the same rid gets the same (ok) answer')
    eq(m:wallet(B.key), 4000, '...and pays once')

    req(m, B, {op = 'mail'})
    local mail = w.last(2)
    eq(#mail.entries, 1, 'the bought item is in the mailbox')
    local mid = mail.entries[1].mid
    req(m, B, {op = 'collect', rid = 'b6', mid = mid})
    local d = w.last(2)
    eq(d.op, 'deliver', 'collect delivers')
    eq(d.data, HEX, 'the same item data')
    req(m, B, {op = 'collect', rid = 'b7', mid = mid})
    eq(w.last(2).rid, 'b6', 'a second collect gets the first delivery again (no second copy)')
    req(m, B, {op = 'collected', rid = 'b6'})
    check(w.last(2).removed, 'collected removes the entry')
    req(m, B, {op = 'collected', rid = 'b6'})
    local again = w.last(2)
    check(again.ok and not again.removed, 'collected again is harmless')
    req(m, B, {op = 'collect', rid = 'b8', mid = mid})
    check(not w.last(2).ok, 'nothing left to collect')

    -- price history
    req(m, B, {op = 'history', type = 0x12A})
    eq(w.last(2).median, 1000, 'median of recent sales')

    -- withdraw gold
    req(m, B, {op = 'withdraw', rid = 'b9', gold = 500})
    d = w.last(2)
    check(d.op == 'deliver' and d.kind == 'gold' and d.gold == 500, 'withdraw delivers gold')
    eq(m:wallet(B.key), 3500, 'wallet down')
    req(m, B, {op = 'withdraw', rid = 'b9', gold = 500})
    eq(m:wallet(B.key), 3500, 'a repeated withdraw pays once')
    req(m, B, {op = 'hello'})
    eq(#w.last(2).pending, 1, 'an unconfirmed delivery is listed at hello')
    req(m, B, {op = 'collected', rid = 'b9'})
    req(m, B, {op = 'hello'})
    eq(#w.last(2).pending, 0, 'confirmed')

    -- everything survives a restart
    local m2 = core.new(w.deps)
    eq(m2:wallet(B.key), 3500, 'restart keeps wallets')
    eq(m2.state.next_mid, m.state.next_mid, 'restart keeps ids')
end

-- expiry, cancel, limits
do
    local w = world()
    local m = core.new(w.deps, {fee_per_day = 0, max_per_seller = 2})
    req(m, A, {op = 'sell', rid = 's1', data = HEX, price = 10, days = 1, meta = {name = 'One'}})
    req(m, A, {op = 'sell', rid = 's2', data = HEX, price = 10, days = 7, meta = {name = 'Two'}})
    local r
    req(m, A, {op = 'sell', rid = 's3', data = HEX, price = 10, days = 7})
    r = w.last(1)
    check(not r.ok and r.err:find('listings'), 'per-seller limit')
    req(m, A, {op = 'sell', rid = 's4', data = HEX, price = 10, days = 2})
    check(not w.last(1).ok, 'an unknown duration is refused')
    req(m, A, {op = 'sell', rid = 's5', data = 'zz' .. HEX, price = 10, days = 1})
    check(not w.last(1).ok, 'damaged data is refused')
    req(m, A, {op = 'sell', rid = 's6', data = HEX, price = 0, days = 1})
    check(not w.last(1).ok, 'price 0 is refused')
    req(m, A, {op = 'sell', rid = 's7', data = HEX, price = 10, days = 1, meta = {type = 5}})
    check(not w.last(1).ok, 'a meta type that does not match the data is refused')

    w.t = w.t + 86400 + 1
    m:sweep(true)
    m:flush()
    eq(#m.state.listings, 1, 'the 1-day listing expired')
    eq(#m.state.mail, 1, '...into the mailbox')
    eq(m.state.mail[1].reason, 'expired', 'reason expired')
    req(m, B, {op = 'browse', q = {}})
    eq(w.last(2).total, 1, 'expired listings are not shown')

    local id = m.state.listings[1].id
    req(m, B, {op = 'cancel', rid = 'c1', id = id})
    check(not w.last(2).ok, 'only the seller can cancel')
    req(m, A, {op = 'cancel', rid = 'c2', id = id})
    check(w.last(1).ok, 'cancel')
    eq(#m.state.mail, 2, 'the cancelled item is in the mailbox')
end

-- a failed write undoes the whole batch
do
    local w = world()
    local m = core.new(w.deps, {fee_per_day = 0})
    req(m, A, {op = 'deposit', rid = 'd1', gold = 100})
    w.take(1)
    w.fail_save = true
    m:handle(A, {op = 'deposit', rid = 'd2', gold = 50, secret = 'secret-' .. A.key})
    m:handle(A, {op = 'sell', rid = 'd3', data = HEX, price = 10, days = 1, secret = 'secret-' .. A.key})
    m:handle(B, {op = 'hello', secret = 'secret-' .. B.key})
    m:flush()
    local out = w.take(1)
    check(not out[1].ok and not out[2].ok, 'both changing answers become refusals')
    eq(m:wallet(A.key), 100, 'wallet as before the batch')
    eq(#m.state.listings, 0, 'no listing')
    eq(w.last(2).op, 'info', 'a read-only answer still goes out')
    w.fail_save = false
    req(m, A, {op = 'deposit', rid = 'd2', gold = 50})
    check(w.last(1).ok, 'the same rid works once the disk is back (the refusal was not remembered)')
    eq(m:wallet(A.key), 150, 'deposited')
end

-- revoke: the sale never reached the savegame
do
    local w = world()
    local m = core.new(w.deps, {fee_per_day = 0})
    req(m, A, {op = 'sell', rid = 'r1', data = HEX, price = 10, days = 1})
    req(m, A, {op = 'revoke', rid = 'r1'})
    eq(w.last(1).what, 'listing removed', 'revoke takes an unsold listing off')
    eq(#m.state.listings, 0, 'gone')
    eq(#m.state.mail, 0, 'and not mailed back (the savegame has the item)')
    req(m, A, {op = 'revoke', rid = 'r2'})
    eq(w.last(1).what, 'unknown', 'revoke of a sale that never arrived')
    req(m, A, {op = 'sell', rid = 'r2', data = HEX, price = 10, days = 1})
    check(not w.last(1).ok, '...so the late sale is refused')
    req(m, A, {op = 'deposit', rid = 'r3', gold = 70})
    req(m, A, {op = 'revoke', rid = 'r3'})
    eq(m:wallet(A.key), 0, 'revoke of a deposit takes the gold back')
    req(m, A, {op = 'revoke', rid = 'r3'})
    eq(m:wallet(A.key), 0, 'only once')
end

-- sorting and paging
do
    local w = world()
    local m = core.new(w.deps, {fee_per_day = 0, max_per_seller = 100, page_size = 10})
    for i = 1, 25 do
        req(m, A, {op = 'sell', rid = 'p' .. i, data = HEX, price = 100 + (i * 37) % 50, days = 7,
            meta = {name = 'Item ' .. i, level = i}})
        w.t = w.t + 1
    end
    req(m, B, {op = 'browse', q = {}, sort = 'price', page = 3})
    local p = w.last(2)
    eq(p.pages, 3, 'three pages')
    eq(#p.rows, 5, 'last page has 5')
    req(m, B, {op = 'browse', q = {}, sort = 'price'})
    p = w.last(2)
    local sorted = true
    for i = 2, #p.rows do if p.rows[i].price < p.rows[i - 1].price then sorted = false end end
    check(sorted, 'sorted by price ascending')
    req(m, B, {op = 'browse', q = {}, sort = 'newest'})
    eq(w.last(2).rows[1].name, 'Item 25', 'newest first')
    req(m, B, {op = 'browse', q = {}, sort = 'level', desc = true})
    eq(w.last(2).rows[1].level, 25, 'level descending')
    req(m, B, {op = 'browse', q = {mine = true}})
    eq(w.last(2).total, 0, 'mine: none of B')
    req(m, A, {op = 'mine'})
    eq(#w.last(1).rows, 25, 'my listings')
end

-- an unreadable file closes the market instead of overwriting it
do
    local w = world()
    w.deps.load = function() return nil, 'bad json' end
    local m = core.new(w.deps)
    check(m.problem ~= nil, 'problem set')
    req(m, A, {op = 'deposit', rid = 'x', gold = 1})
    check(not w.last(1).ok, 'refused')
    eq(w.saves, 0, 'nothing written')
end

print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
