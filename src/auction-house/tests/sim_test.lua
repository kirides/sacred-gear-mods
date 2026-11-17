-- A headless run of the whole mod (main.lua, client.lua, ui.lua, core.lua) against a fake `gear`: single player,
-- the market in the same game. Drives the client's calls the panel makes, draws every tab, restarts the game to run
-- the crash check. Plain LuaJIT:  luajit tests/sim_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end

---------------------------------------------------------------------------------------------------------------
-- a tiny JSON (enough for the mod's tables)
---------------------------------------------------------------------------------------------------------------
local json = {}
local function enc(v, out)
    local t = type(v)
    if t == 'nil' then out[#out + 1] = 'null'
    elseif t == 'boolean' then out[#out + 1] = tostring(v)
    elseif t == 'number' then out[#out + 1] = (v == math.floor(v) and ('%d'):format(v) or ('%.17g'):format(v))
    elseif t == 'string' then out[#out + 1] = ('%q'):format(v):gsub('\\\n', '\\n')
    elseif t == 'table' then
        local n = #v
        local is_arr = n > 0 or next(v) == nil
        if is_arr then
            out[#out + 1] = '['
            for i = 1, n do if i > 1 then out[#out + 1] = ',' end enc(v[i], out) end
            out[#out + 1] = ']'
        else
            out[#out + 1] = '{'
            local first = true
            for k, x in pairs(v) do
                assert(type(k) == 'string', 'json: non-string key ' .. tostring(k))
                if not first then out[#out + 1] = ',' end
                first = false
                enc(k, out) out[#out + 1] = ':' enc(x, out)
            end
            out[#out + 1] = '}'
        end
    else error('json: cannot encode ' .. t) end
end
function json.encode(v) local out = {} enc(v, out) return table.concat(out) end
function json.decode(s)
    -- the encoder above writes Lua-compatible literals except for [] {} : null
    local lua = s:gsub('%[', '{'):gsub('%]', '}'):gsub('null', 'nil')
    lua = lua:gsub('("[^"]-")%s*:', '[%1]=')
    local f = loadstring('return ' .. lua)
    if not f then return nil, 'bad json' end
    local ok, v = pcall(f)
    if not ok then return nil, v end
    return v
end

---------------------------------------------------------------------------------------------------------------
-- the fake game
---------------------------------------------------------------------------------------------------------------
local files = {}
local clock = 0
local handlers = {}
local hero_gold = 10000

local function hex(b) return (b:gsub('.', function(c) return ('%02x'):format(c:byte()) end)) end
local function unhex(t)
    if type(t) ~= 'string' or #t % 2 == 1 or t:find('[^0-9a-f]') then return nil end
    return (t:gsub('..', function(h) return string.char(tonumber(h, 16)) end))
end

local next_id = 100
local containers = {backpack = {list = {}}, chest = {list = {}}}
local function make_item(bytes)
    next_id = next_id + 1
    local t = bytes:byte(1) + bytes:byte(2) * 256
    return {id = next_id, bytes = bytes, type = t, type_name = 'sword_' .. t .. '.itm', quality = 'rare',
        category = 'weapon', w = 1, h = 3, classes = {}, gold = false, quest = false}
end
for name, c in pairs(containers) do
    c.index = name == 'chest' and 17 or 1
    function c:items() local l = {} for _, it in ipairs(self.list) do l[#l + 1] = it end return l end
end
local function find(id)
    for _, c in pairs(containers) do
        for i, it in ipairs(c.list) do if it.id == id then return it, c, i end end
    end
end
table.insert(containers.backpack.list, make_item(string.char(0x2a, 0x01, 0, 0) .. string.rep('\171', 40)))
table.insert(containers.backpack.list, make_item(string.char(0x2b, 0x01, 0, 0) .. string.rep('\205', 40)))

local hero = {}
function hero:name() return 'Anna' end
function hero:class() return 'seraphim' end
function hero:gold() return hero_gold end
function hero:add_gold(n)
    if hero_gold + n < 0 then return nil, 'not enough' end
    hero_gold = hero_gold + n
    return true
end
function hero:is_dead() return false end

local clicks = {}
gear = {
    config = {enabled = true},
    time = function() return clock end,
    log = function(...) end,
    read = function(n) return files[n] end,
    save = function(n, t) files[n] = t return true end,
    json = json,
    emit = function() end,
    on = function(ev, fn) handlers[ev] = handlers[ev] or {} table.insert(handlers[ev], fn) end,
    settings = {get = function(id)
        return ({durations = '1,3,7', fee_per_day = 0.5, sale_cut = 5, max_per_seller = 20, allow_special = false})[id]
    end},
    world = {hero = function() return hero end},
    inv = {
        container = function(w) return containers[w] end,
        export = function(id) local it = find(id) return it and it.bytes or nil, 'no item' end,
        remove = function(c, id)
            for i, it in ipairs(c.list) do if it.id == id then table.remove(c.list, i) return it.bytes end end
            return nil, 'not there'
        end,
        add = function(c, bytes)
            if #c.list >= 20 then return nil, 'full' end
            local it = make_item(bytes)
            table.insert(c.list, it)
            return it.id, 0, 0
        end,
        size = function(id) local it = find(id) if it then return it.w, it.h end end,
        hex = hex, unhex = unhex,
    },
    ui = {
        COLORS = {accent = 0xFFC8A060},
        panel = function(id, title, x, y, w, h) return {open = true, content_x = x, content_y = y + 20, content_w = w, content_h = h - 20, w = w, h = h} end,
        button = function(id) if clicks[id] then clicks[id] = nil return true end return false end,
        dropdown = function(id, x, y, w, options, index) return false, index end,
        checkbox = function(id, x, y, text, checked) return false, checked end,
        label = function() end, text = function() end, rect = function() end, frame = function() end,
        region = function() return {hover = false, clicked = false} end,
        item_icon = function() end,
        item_tooltip = function() return true, 300, 200 end,
        item_tooltip_text = function() return '\\cffefefefSword of Tests\nDamage 10-20\nLevel: 12\nMinimum Level: 8' end,
        tooltip_rect = function() return 0, 0 end,
        key_pressed = function() return false end, key_down = function() return false end,
        show_panel = function() end, panel_open = function() return true end, edit_mode = function() return false end,
        window = function() return {drawn = true} end,
    },
}
os.time = function() return 1800000000 + math.floor(clock) end

local function fire(ev, ...)
    for _, fn in ipairs(handlers[ev] or {}) do fn(...) end
end
local function frames(n)
    for _ = 1, n or 1 do
        clock = clock + 0.05
        fire('frame', 0.05)
        fire('draw', {mode = 'game'})
    end
end

---------------------------------------------------------------------------------------------------------------
-- a game session
---------------------------------------------------------------------------------------------------------------
local function boot()
    handlers = {}
    package.loaded.main, package.loaded.client, package.loaded.ui, package.loaded.core = nil, nil, nil, nil
    dofile('main.lua')
    fire('session.start', hero)
    frames(5)
end

-- the main chunk returns nothing; get the client through the ui module's view and the client module
boot()
local panel = package.loaded.ui
check(panel ~= nil, 'ui loaded')

-- reach the client: main.lua passes it to the panel functions; capture it through a wrapped panel()
local client
local orig = panel.panel
panel.panel = function(c, cfg) client = c return orig(c, cfg) end
frames(2)
check(client ~= nil and client:online(), 'the client talks to the market in this game')

-- deposit and sell
local done = {}
client:deposit(500, function(ok, err) done.dep = {ok, err} end)
frames(3)
check(done.dep and done.dep[1], 'deposit: ' .. tostring(done.dep and done.dep[2]))
check(hero_gold == 9500, 'gold left the hero')
check(client:wallet() == 500, 'wallet 500 (' .. tostring(client:wallet()) .. ')')

local it = containers.backpack.list[1]
local meta = panel.meta_of(it, it.bytes)
check(meta.name == 'Sword of Tests' and meta.level == 12, 'meta from the tooltip text')
client:sell(containers.backpack, it, meta, 2000, 3, function(ok, err) done.sell = {ok, err} end)
frames(3)
check(done.sell and done.sell[1], 'sell: ' .. tostring(done.sell and done.sell[2]))
check(#containers.backpack.list == 1, 'the item left the backpack')
check(client:wallet() == 470, 'fee 30 paid (' .. client:wallet() .. ')')

-- every tab draws
for _, tab in ipairs({'browse', 'sell', 'mine', 'mail'}) do
    panel.view.tab = tab
    local ok, err = pcall(frames, 3)
    check(ok, 'tab ' .. tab .. ' draws: ' .. tostring(err))
end
panel.view.tab = 'browse'
panel.search(client, 1)
frames(2)
check(client.page and client.page.total == 1, 'browse finds the listing')

-- a second player buys it (straight into the market of this game)
local market = client and nil
for _, fn in ipairs(handlers.frame) do end
local m = package.loaded.core and nil
-- the market object is internal to main.lua: reach it through the module table main returns in self tests;
-- here we use a second client identity talking to the same queue
local core = require('core')
local mk
do
    -- find the market: the only core market created is held in main's upvalue; send through the client's channel
    local other = {key = 'bert:dwarf', name = 'Bert', secret = 'bert-secret-123'}
    local answers = {}
    local function as_bert(msg)
        for k, v in pairs(other) do msg[k] = v end
        client.send_raw(msg)
    end
    -- the local queue only knows one player (the local hero), so Bert's requests carry their own key; the market
    -- takes `from.key` from the game when there is one: in single player it is the local hero. So test Bert with a
    -- separate market instance on the same file instead.
    local w = {}
    mk = core.new({now = os.time, load = function() return json.decode(files['market.json']) end,
        save = function(s) files['market.json'] = json.encode(s) return true end,
        send = function(slot, msg) answers[#answers + 1] = msg end})
    mk:handle({slot = 2, key = 'bert:dwarf', name = 'Bert'}, {op = 'deposit', rid = 'b1', gold = 5000, secret = other.secret})
    local id = mk.state.listings[1].id
    mk:handle({slot = 2, key = 'bert:dwarf', name = 'Bert'}, {op = 'buy', rid = 'b2', id = id, price = 2000, secret = other.secret})
    mk:flush()
    check(answers[2] and answers[2].ok, 'Bert bought it')
end

-- the game is restarted: the market reloads the file Bert's market wrote; the seller collects the gold
boot()
panel = package.loaded.ui
panel.panel = function(c, cfg) client = c return orig(c, cfg) end
frames(3)
check(client:wallet() == 470 + 1900, 'the seller got the price minus the cut (' .. client:wallet() .. ')')
client:withdraw(2370, function(ok) done.wd = ok end)
frames(4)
check(done.wd, 'withdraw')
check(hero_gold == 9500 + 2370, 'gold back on the hero (' .. hero_gold .. ')')

-- crash check: sell, then "the game ends before saving" (the savegame still has the item), restart
local it2 = containers.backpack.list[1]
local bytes2 = it2.bytes
client:sell(containers.backpack, it2, panel.meta_of(it2, bytes2), 100, 1, function(ok) done.s2 = ok end)
frames(3)
check(done.s2, 'second sale')
check(#containers.backpack.list == 0, 'backpack empty')
-- the restart loads the old savegame: the item is back in the backpack
table.insert(containers.backpack.list, make_item(bytes2))
boot()
panel = package.loaded.ui
panel.panel = function(c, cfg) client = c return orig(c, cfg) end
frames(5)
local mk2 = core.new({now = os.time, load = function() return json.decode(files['market.json']) end,
    save = function() return true end, send = function() end})
check(#mk2.state.listings == 0, 'the sale that never reached the savegame was taken off the market')
check(#containers.backpack.list == 1, 'the item stays in the backpack (from the savegame)')

-- the cancelled item comes back through the mailbox, byte for byte
local it3 = containers.backpack.list[1]
client:sell(containers.backpack, it3, panel.meta_of(it3, it3.bytes), 100, 1, function(ok) done.s3 = ok end)
frames(3)
local lid
client:refresh_mine()
frames(2)
lid = client.mine and client.mine.rows[1] and client.mine.rows[1].id
client:cancel(lid, function(ok) done.c3 = ok end)
frames(3)
check(done.c3, 'cancel')
client:refresh_mail()
frames(2)
local mid = client.mail and client.mail.entries[1] and client.mail.entries[1].mid
check(mid ~= nil, 'cancelled item in the mailbox')
client:collect(mid, function(ok) done.col = ok end)
frames(4)
check(done.col, 'collected')
check(#containers.backpack.list == 1 and containers.backpack.list[1].bytes == it3.bytes, 'the same item came back')
client:refresh_mail()
frames(2)
check(client.mail and #client.mail.entries == 0, 'mailbox empty')
local open = 0
for _, e in ipairs(client.journal.entries) do if e.op == 'collect' then open = open + 1 end end
check(open == 0, 'no open collect in the journal')

print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
