-- World events, world bosses without the game: the list of bosses the bar shows (live health, defeated for a few seconds) and the view of
-- one boss bar. Plain Lua 5.1 / LuaJIT, no gear.* (tested in tests/bosses_test.lua). localgame.lua makes the bosses and reads their
-- health from the game; the server's `worldevents:boss` messages (parse) feed the same list in a game the mod cannot spawn in.
--
-- A boss record: {key, name, hp, max, st = 'active' | 'defeated' | 'gone', source = 'local' | 'server', text?, event?, area?, by?, reward?, frac?}
-- `frac` (0..1) is used when no hp / max are known (a server that only knows the boss is alive: the bar shows its name, no numbers).
local M = {}

M.HOLD = 6          -- seconds a defeated boss stays on the bar
M.MAX_BARS = 3      -- bars at once; more bosses are a line "+N more"
M.MAX_TRACKED = 12

local function int_in(v, low, high)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < low or v > high then return nil end
    return v
end

local function text_of(v, limit)
    local t = tostring(v or ''):gsub('%c', ' '):gsub('\\', ' ')
    return t:sub(1, limit)
end

-- 12345 -> "12,345"
function M.thousands(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

-- Checks a server message of the channel `worldevents:boss`:
--   {v = 1, id = '<event>:<hook>:<n>', st = 'active' | 'defeated' | 'gone', name, hp?, max?, frac?, text?, event?, area?, by?, reward?}
-- Returns a clean record or nil and a reason.
function M.parse(payload)
    if type(payload) ~= 'table' then return nil, 'not a table' end
    local key = type(payload.id) == 'string' and payload.id or nil
    if not key or key == '' or #key > 64 then return nil, 'no boss id' end
    local st = payload.st
    if st ~= 'active' and st ~= 'defeated' and st ~= 'gone' then return nil, 'bad state' end
    local name = text_of(payload.name, 40)
    if not name:match('%S') then return nil, 'no name' end
    local rec = {key = key, st = st, name = name, source = 'server', text = text_of(payload.text, 160), event = text_of(payload.event, 60),
        area = text_of(payload.area, 40), by = text_of(payload.by, 40), reward = text_of(payload.reward, 80)}
    local max = int_in(payload.max, 1, 2000000000)
    local hp = int_in(payload.hp, 0, 2000000000)
    if max and hp then rec.max, rec.hp = max, math.min(hp, max) end
    local frac = tonumber(payload.frac)
    if frac and frac == frac then rec.frac = math.max(0, math.min(1, frac)) end
    return rec
end

local Tracker = {}
Tracker.__index = Tracker

function M.tracker()
    return setmetatable({list = {}, by_key = {}}, Tracker)
end

local function find(t, key) return t.by_key[key] end

-- Adds or replaces the boss with the record's key (an `active` record again after `defeated` starts it over).
function Tracker:set(rec, now)
    local old = find(self, rec.key)
    if old then
        for k, v in pairs(rec) do old[k] = v end
        if rec.st ~= 'active' and not old.ended then old.ended = now end
        if rec.st == 'active' then old.ended = nil end
        return old
    end
    if #self.list >= M.MAX_TRACKED then
        -- the oldest finished one goes first, else the oldest
        local drop = 1
        for i, b in ipairs(self.list) do if b.st ~= 'active' then drop = i break end end
        local gone = table.remove(self.list, drop)
        self.by_key[gone.key] = nil
    end
    local b = {}
    for k, v in pairs(rec) do b[k] = v end
    b.since = now
    if b.st ~= 'active' then b.ended = now end
    self.list[#self.list + 1] = b
    self.by_key[b.key] = b
    return b
end

-- New health of a live boss.
function Tracker:health(key, hp, max)
    local b = find(self, key)
    if not b or b.st ~= 'active' then return false end
    b.hp, b.max = math.max(0, hp), math.max(1, max)
    return true
end

function Tracker:finish(key, st, now, by)
    local b = find(self, key)
    if not b or b.st ~= 'active' then return nil end
    b.st, b.ended, b.by = st, now, by or b.by
    if st == 'defeated' and b.max then b.hp = 0 end
    return b
end

function Tracker:remove(key)
    local b = find(self, key)
    if not b then return end
    self.by_key[key] = nil
    for i, x in ipairs(self.list) do if x == b then table.remove(self.list, i) break end end
end

function Tracker:clear()
    self.list, self.by_key = {}, {}
end

function Tracker:active()
    local n = 0
    for _, b in ipairs(self.list) do if b.st == 'active' then n = n + 1 end end
    return n
end

-- Forgets what is over (a defeated boss after HOLD seconds, a boss that is gone at once).
function Tracker:expire(now)
    for i = #self.list, 1, -1 do
        local b = self.list[i]
        if b.st == 'gone' or (b.st == 'defeated' and now - (b.ended or now) > M.HOLD) then
            self.by_key[b.key] = nil
            table.remove(self.list, i)
        end
    end
end

-- The bar of one boss: {key, name, frac, hp_text, st, alpha, text, area, by, reward, source}.
function M.view(b, now)
    local frac = b.frac
    if b.max and b.max > 0 then frac = math.max(0, math.min(1, (b.hp or 0) / b.max)) end
    frac = frac or 1
    local alpha = 1
    if b.st == 'defeated' then
        local left = M.HOLD - (now - (b.ended or now))
        alpha = math.max(0, math.min(1, left / 2))          -- fades during the last two seconds
        frac = 0
    end
    local hp_text = ''
    if b.st == 'defeated' then hp_text = 'Defeated'
    elseif b.max then hp_text = M.thousands(b.hp or 0) .. ' / ' .. M.thousands(b.max)
    else hp_text = math.floor(frac * 100 + 0.5) .. '%' end
    return {key = b.key, name = b.name, frac = frac, hp_text = hp_text, st = b.st, alpha = alpha, text = b.text, area = b.area, by = b.by,
        reward = b.reward, source = b.source, event = b.event, percent = math.floor(frac * 100 + 0.5)}
end

-- The bars to draw (at most MAX_BARS, active first, the newest first) and the number of bosses left out.
function Tracker:views(now)
    local order = {}
    for _, b in ipairs(self.list) do order[#order + 1] = b end
    table.sort(order, function(a, b)
        local ra, rb = a.st == 'active' and 0 or 1, b.st == 'active' and 0 or 1
        if ra ~= rb then return ra < rb end
        return (a.since or 0) > (b.since or 0)
    end)
    local out = {}
    for i = 1, math.min(#order, M.MAX_BARS) do out[i] = M.view(order[i], now) end
    return out, math.max(0, #order - M.MAX_BARS)
end

-- The reward line of a clean boss reward ("5,000 gold, Epic item") for the announcement and the tooltip.
function M.reward_text(reward)
    if type(reward) ~= 'table' then return '' end
    local parts = {}
    if reward.gold then parts[#parts + 1] = M.thousands(reward.gold) .. ' gold' end
    if reward.item then
        local s = reward.item
        parts[#parts + 1] = s.type and tostring(s.type) or ('an item' .. (s.category and (' (' .. s.category .. ')') or ''))
    end
    return table.concat(parts, ', ')
end

return M
