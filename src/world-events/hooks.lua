-- World events, hooks without the game: the checking of hooks (the same format and limits as the server's world_events.lua), the
-- engine that fires them (used by the local single player mode), the parsing of the server's spawn messages, the weighted choice
-- of creature kinds and the places of a wave. Plain Lua 5.1 / LuaJIT, no gear.* (tested in tests/hooks_test.lua).
--
-- A hook is a TRIGGER with a list of ACTIONS:
--   triggers  at = percent of the goal | at_time = seconds into the event | on = 'start' | 'success' | 'fail' |
--             kills = {creature = 'Orc Shaman' (a name part or a type number), count = 5, per_player = false}
--   actions   {action = 'spawn', n, per_player, kinds = {{type = 'Orc Warrior', weight = 3}, ...}, radius, target, text}
--             {action = 'item', spec = {type | quality, category, level}, n, target}   {action = 'message', text, target}
--             {action = 'gold', amount, target}
--             {action = 'boss', name, kinds = {{type, weight}} | near = 'Orc', radius, health, damage, taken, deflect, reflect, regen, reward = {gold, item = spec, text}, text, target}
--   targets   killer, host, random, owner, players, global  (alone in a single player game they are all the hero)
local M = {}

M.LIMITS = {hooks = 12, actions = 6, kinds = 8, spawn_n = 40, item_n = 10}
M.ACTIONS = {spawn = true, item = true, message = true, gold = true, boss = true}
M.TARGETS = {killer = true, host = true, random = true, owner = true, players = true, global = true}
M.DEFAULT_TARGET = {spawn = 'owner', item = 'killer', message = 'global', gold = 'killer', boss = 'owner'}

-- What a boss may be made of (the same limits as the server's world_events.lua): name = {lowest, highest, default}.
M.BOSS = {health = {1, 1000, 10}, damage = {0, 50, 2}, taken = {0.05, 10, 1}, deflect = {0, 0.9, 0}, reflect = {0, 1, 0}, regen = {0, 0.2, 0}}

local function int_in(v, low, high)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    v = math.floor(v)
    if v < low or v > high then return nil end
    return v
end
M.int_in = int_in

-- A number brought into low..high (a value outside is clamped, not replaced); `default` for something that is no number.
local function clamp_int(v, low, high, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(low, math.min(high, math.floor(v)))
end

-- Text from outside: no control characters, no game markup (a backslash would start a code), a length limit.
local function text_of(v, limit)
    local t = tostring(v or ''):gsub('%c', ' '):gsub('\\', ' ')
    return t:sub(1, limit)
end

local function trim(s) return (s:match('^%s*(.-)%s*$')) end

-- A creature kind {type = name or number, weight} or nil.
local function clean_kind(raw)
    if type(raw) ~= 'table' then return nil end
    local t = raw.type
    if type(t) == 'number' then t = int_in(t, 1, 4294967295)
    elseif type(t) == 'string' and t:match('%S') then t = trim(text_of(t, 48))
    else t = nil end
    if t == nil or t == '' then return nil end
    return {type = t, weight = int_in(raw.weight, 1, 1000) or 1}
end

-- A number brought into low..high, `default` for something that is no number.
local function clamp_num(v, low, high, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(low, math.min(high, v))
end

-- The boss part of a `boss` action or of the server's spawn message (a table): name, what it is made of (`kinds` to spawn, or `near`: the
-- nearest creature whose name has these words is promoted), the multipliers, the reward and the announcement. Returns the clean boss or nil and a reason.
function M.clean_boss(raw, limits)
    limits = limits or M.LIMITS
    if type(raw) ~= 'table' then return nil, 'not an object' end
    local b = {kinds = {}}
    for _, k in ipairs(type(raw.kinds) == 'table' and raw.kinds or {}) do
        local entry = clean_kind(k)
        if entry and #b.kinds < limits.kinds then b.kinds[#b.kinds + 1] = entry end
    end
    if type(raw.near) == 'string' and raw.near:match('%S') then b.near = trim(text_of(raw.near, 48)) end
    if #b.kinds == 0 and not b.near then return nil, 'a boss needs a creature kind (kinds) or creatures to promote (near)' end
    local first = b.kinds[1] and tostring(b.kinds[1].type) or b.near
    b.name = trim(text_of(raw.name ~= nil and raw.name or first, 40))
    if b.name == '' then b.name = trim(text_of(first, 40)) end
    b.radius = clamp_int(raw.radius, 50, 3000, 400)
    for key, range in pairs(M.BOSS) do b[key] = clamp_num(raw[key], range[1], range[2], range[3]) end
    if type(raw.reward) == 'table' then
        local r = {}
        r.gold = int_in(raw.reward.gold, 1, 2000000000)
        if type(raw.reward.item) == 'table' then
            local spec, item = raw.reward.item, {}
            if type(spec.type) == 'string' and spec.type:match('%S') then item.type = text_of(spec.type, 48)
            elseif type(spec.type) == 'number' then item.type = int_in(spec.type, 1, 4294967295) end
            if spec.quality ~= nil then item.quality = int_in(spec.quality, 0, 14) end
            if type(spec.category) == 'string' and spec.category ~= '' then item.category = text_of(spec.category, 20):lower() end
            if spec.level ~= nil then item.level = int_in(spec.level, 1, 200) end
            if next(item) ~= nil then r.item = item end
        end
        if raw.reward.text ~= nil and tostring(raw.reward.text):match('%S') then r.text = text_of(raw.reward.text, 120) end
        if r.gold or r.item then b.reward = r end
    end
    return b
end

local function clean_action(raw, limits)
    if type(raw) ~= 'table' then return nil, 'not an object' end
    local kind = raw.action
    if not M.ACTIONS[kind] then return nil, 'unknown action ' .. tostring(kind) end
    local a = {action = kind, target = M.TARGETS[raw.target] and raw.target or M.DEFAULT_TARGET[kind]}
    if kind == 'spawn' then
        a.n = clamp_int(raw.n, 1, limits.spawn_n, 1)
        a.per_player = raw.per_player ~= false
        a.radius = clamp_int(raw.radius, 50, 3000, 400)
        a.kinds = {}
        for _, k in ipairs(type(raw.kinds) == 'table' and raw.kinds or {}) do
            local entry = clean_kind(k)
            if entry and #a.kinds < limits.kinds then a.kinds[#a.kinds + 1] = entry end
        end
        if #a.kinds == 0 then return nil, 'a spawn needs at least one creature kind' end
    elseif kind == 'boss' then
        local boss, why = M.clean_boss(raw, limits)
        if not boss then return nil, why end
        a.boss = boss
        a.n = 1
    elseif kind == 'item' then
        local spec = type(raw.spec) == 'table' and raw.spec or {}
        a.spec = {}
        if type(spec.type) == 'string' and spec.type:match('%S') then a.spec.type = text_of(spec.type, 48)
        elseif type(spec.type) == 'number' then a.spec.type = int_in(spec.type, 1, 4294967295) end
        if spec.quality ~= nil then a.spec.quality = int_in(spec.quality, 0, 14) end
        if type(spec.category) == 'string' and spec.category ~= '' then a.spec.category = text_of(spec.category, 20):lower() end
        if spec.level ~= nil then a.spec.level = int_in(spec.level, 1, 200) end
        if next(a.spec) == nil then return nil, 'an item needs a type or a quality / category / level' end
        a.n = clamp_int(raw.n, 1, limits.item_n, 1)
    elseif kind == 'gold' then
        a.amount = int_in(raw.amount, 1, 2000000000)
        if not a.amount then return nil, 'gold needs an amount' end
    end
    if raw.text ~= nil and tostring(raw.text):match('%S') then a.text = text_of(raw.text, 160) end
    if kind == 'message' and not a.text then return nil, 'a message needs a text' end
    return a
end

-- The hooks of an event definition, checked and cleaned (the same rules as the server). Returns the list (nil when there is none)
-- and a list of reasons for what was refused. `limits` overrides M.LIMITS.
function M.clean(raw, limits)
    limits = limits or M.LIMITS
    local refused = {}
    if type(raw) ~= 'table' then return nil, refused end
    local out = {}
    for i, h in ipairs(raw) do
        if #out >= limits.hooks then refused[#refused + 1] = ('more than %d hooks, the rest is ignored'):format(limits.hooks); break end
        local hook, why = {}, nil
        if type(h) ~= 'table' then why = 'not an object'
        else
            if h.on == 'start' or h.on == 'success' or h.on == 'fail' then hook.on = h.on
            elseif type(h.kills) == 'table' then
                local creature = h.kills.creature
                if type(creature) == 'string' and creature:match('%S') then creature = trim(text_of(creature, 48))
                elseif type(creature) == 'number' then creature = int_in(creature, 1, 4294967295) else creature = nil end
                local count = int_in(h.kills.count, 1, 100000)
                if creature and count then hook.kills = {creature = creature, count = count, per_player = h.kills.per_player == true, region = int_in(h.kills.region, 1, 255)}
                else why = 'kills needs a creature and a count' end
            elseif tonumber(h.at_time) then
                hook.at_time = int_in(h.at_time, 1, 30 * 86400)
                if not hook.at_time then why = 'at_time must be 1 second to 30 days' end
            elseif tonumber(h.at) then
                local at = tonumber(h.at)
                if at > 0 and at <= 100 then hook.at = at else why = 'at must be a percent above 0 up to 100' end
            else why = 'no trigger (at, at_time, on or kills)' end
            if not why then
                hook.actions = {}
                for j, raw_action in ipairs(type(h.actions) == 'table' and h.actions or {}) do
                    if #hook.actions >= limits.actions then break end
                    local action, action_why = clean_action(raw_action, limits)
                    if action then hook.actions[#hook.actions + 1] = action
                    else refused[#refused + 1] = ('hook #%d action #%d refused: %s'):format(i, j, tostring(action_why)) end
                end
                if #hook.actions == 0 then why = 'no valid action' end
            end
        end
        if why then refused[#refused + 1] = ('hook #%d refused: %s'):format(i, why) else out[#out + 1] = hook end
    end
    if #out == 0 then return nil, refused end
    return out, refused
end

---------------------------------------------------------------------------------------------------------------
-- texts (the same words as the server's dashboard)
---------------------------------------------------------------------------------------------------------------
local function percent_text(p)
    local t = ('%.1f'):format(p):gsub('%.0$', '')
    return t .. '%'
end

local function duration_text(s)
    s = math.floor(s)
    local h, m, sec = math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60
    if h > 0 then return ('%dh %02dm'):format(h, m) end
    return ('%dm %02ds'):format(m, sec)
end

-- A creature kind for the player: a type id shows its localized name (M.labeler, set by main.lua), a name as it is.
M.labeler = nil
local function shown(v)
    if type(v) == 'number' and M.labeler then return M.labeler(v) or tostring(v) end
    return tostring(v)
end

function M.trigger_text(h)
    if h.on == 'start' then return 'When the event starts'
    elseif h.on == 'success' then return 'When the goal is reached'
    elseif h.on == 'fail' then return 'When the time runs out'
    elseif h.kills then
        return ('When %s has defeated %d x %s%s'):format(h.kills.per_player and 'a hero' or 'the realm', h.kills.count, shown(h.kills.creature),
            h.kills.region and (' in region ' .. h.kills.region) or '')
    elseif h.at_time then return 'After ' .. duration_text(h.at_time) end
    return 'At ' .. percent_text(h.at) .. ' of the goal'
end

local function kind_text(kinds)
    local parts = {}
    for _, k in ipairs(kinds) do parts[#parts + 1] = shown(k.type) .. (k.weight > 1 and (' x' .. k.weight) or '') end
    return table.concat(parts, ' / ')
end

-- 2, 1.5 (no trailing zeros)
function M.num_text(v)
    local t = ('%.2f'):format(v):gsub('0+$', ''):gsub('%.$', '')
    return t
end

function M.action_text(a)
    if a.action == 'spawn' then
        return ('%d of %s appear around you'):format(a.n, kind_text(a.kinds))
    elseif a.action == 'boss' then
        local b = a.boss
        return ('the boss %s (%s health, %s damage) %s'):format(b.name, 'x' .. M.num_text(b.health), 'x' .. M.num_text(b.damage),
            b.near and ('rises from the nearest ' .. b.near) or 'appears around you')
    elseif a.action == 'item' then
        local s = a.spec
        local what = s.type and tostring(s.type) or ('an item' .. (s.quality and (' of quality ' .. s.quality) or '')
            .. (s.category and (', ' .. s.category) or '') .. (s.level and (', level ' .. s.level) or ''))
        return ('%s%s drops for you'):format(a.n > 1 and (a.n .. ' x ') or '', what)
    elseif a.action == 'gold' then
        return ('%d gold drops for you'):format(a.amount)
    end
    return '"' .. tostring(a.text) .. '"'
end

-- The next hook of `def` that has not fired and starts at a percent or a time, in one short line ("At 30% of the goal: ...").
function M.next_text(hooks, fired)
    for i, h in ipairs(hooks or {}) do
        if not (fired and fired['h' .. i]) and (h.at or h.at_time) then
            local text = M.trigger_text(h) .. ': ' .. M.action_text(h.actions[1])
            return (#text > 150) and (text:sub(1, 147) .. '...') or text
        end
    end
    return nil
end

---------------------------------------------------------------------------------------------------------------
-- the engine: fires hooks once, catches up, counts kills (the local single player mode)
---------------------------------------------------------------------------------------------------------------
local Runner = {}
Runner.__index = Runner

-- `state` is a plain table kept with the event: {fired = {h1 = true}, hk = {h2 = {all = 3}}} (it is changed in place, save it
-- afterwards). `act(action, context, key, index)` runs one action (errors are caught here).
function M.runner(hooks, state, act)
    state.fired = state.fired or {}
    state.hk = state.hk or {}
    return setmetatable({hooks = hooks or {}, state = state, act = act, changed = false}, Runner)
end

function Runner:fire(number, hook, ctx)
    local key = 'h' .. number
    if self.state.fired[key] then return false end
    self.state.fired[key] = true
    self.changed = true
    for index, action in ipairs(hook.actions) do
        local ok = pcall(self.act, action, ctx or {}, key, index)
        if not ok then self.failed = (self.failed or 0) + 1 end
    end
    return true
end

function Runner:run(test, ctx)
    local fired = 0
    for number, hook in ipairs(self.hooks) do
        if not self.state.fired['h' .. number] and test(hook) then
            if self:fire(number, hook, ctx) then fired = fired + 1 end
        end
    end
    return fired
end

-- Progress or time passed: every `at` the percent reached and every `at_time` the elapsed seconds reached fires (all of them, if
-- the progress jumped past several).
function Runner:progress(percent, elapsed, ctx)
    return self:run(function(h) return (h.at and percent >= h.at) or (h.at_time and elapsed >= h.at_time) end, ctx)
end

function Runner:on(which, ctx)
    return self:run(function(h) return h.on == which end, ctx)
end

-- Does a defeated creature (name and type number) match what a `kills` trigger asks for?
function M.matches(creature, name, type_id)
    if type(creature) == 'number' then return type_id == creature end
    if type(name) ~= 'string' or name == '' then return false end
    return name:lower():find(tostring(creature):lower(), 1, true) ~= nil
end

-- A kill of `name` / `type_id` by `who` (a string id for per_player counting).
function Runner:kill(name, type_id, who, ctx, region)
    local fired = 0
    for number, hook in ipairs(self.hooks) do
        local k, key = hook.kills, 'h' .. number
        if k and not self.state.fired[key] and (not k.region or k.region == region) and M.matches(k.creature, name, type_id) then
            local counters = self.state.hk[key] or {}
            self.state.hk[key] = counters
            local slot = k.per_player and tostring(who) or 'all'
            counters[slot] = (counters[slot] or 0) + 1
            self.changed = true
            if counters[slot] >= k.count and self:fire(number, hook, ctx) then fired = fired + 1 end
        end
    end
    return fired
end

---------------------------------------------------------------------------------------------------------------
-- the server's spawn message and the wave
---------------------------------------------------------------------------------------------------------------
-- Checks a 'worldevents:spawn' payload: {v = 1, id, event, n, radius, kinds = {{type, weight}}, text}. Returns the clean wave or nil and a reason.
function M.parse_spawn(payload, limits)
    limits = limits or M.LIMITS
    if type(payload) ~= 'table' then return nil, 'not a table' end
    local id = type(payload.id) == 'string' and payload.id or nil
    if not id or id == '' or #id > 64 then return nil, 'no wave id' end
    local n = int_in(payload.n, 1, limits.spawn_n)
    if not n and payload.boss == nil then return nil, 'bad creature count' end
    local kinds = {}
    for _, k in ipairs(type(payload.kinds) == 'table' and payload.kinds or {}) do
        local entry = clean_kind(k)
        if entry and #kinds < limits.kinds then kinds[#kinds + 1] = entry end
    end
    if #kinds == 0 and payload.boss == nil then return nil, 'no creature kinds' end
    local text = payload.text ~= nil and tostring(payload.text):match('%S') and text_of(payload.text, 160) or nil
    local boss = nil
    if payload.boss ~= nil then
        boss = M.clean_boss(payload.boss, limits)
        if not boss then return nil, 'bad boss' end
        n = 1
    end
    return {boss = boss, id = id, n = n, radius = int_in(payload.radius, 50, 3000) or 400, kinds = kinds, text = text, event = text_of(payload.event or '', 60)}
end

-- `n` kinds drawn by weight (`rnd(k)` returns an integer 1..k).
function M.pick_kinds(kinds, n, rnd)
    local total = 0
    for _, k in ipairs(kinds) do total = total + (k.weight or 1) end
    local out = {}
    if total <= 0 then return out end
    for i = 1, n do
        local r = rnd(total)
        for _, k in ipairs(kinds) do
            r = r - (k.weight or 1)
            if r <= 0 then out[i] = k.type; break end
        end
        out[i] = out[i] or kinds[#kinds].type
    end
    return out
end

-- `n` offsets (dx, dy) around a point: spread over the ring between 40 % and 100 % of the radius, `rnd(k)` as above.
function M.offsets(n, radius, rnd)
    local out = {}
    local steps = 1000
    local first = rnd(steps) / steps * 2 * math.pi
    for i = 1, n do
        local angle = first + (i - 1) * 2 * math.pi / n + (rnd(steps) / steps - 0.5) * 0.5
        local dist = radius * (0.4 + 0.6 * rnd(steps) / steps)
        out[i] = {math.floor(math.cos(angle) * dist + 0.5), math.floor(math.sin(angle) * dist + 0.5)}
    end
    return out
end

-- Remembers the last `cap` wave ids: a wave that arrives twice (a resend) spawns once.
local Seen = {}
Seen.__index = Seen
function M.seen(cap)
    return setmetatable({cap = cap or 200, order = {}, set = {}}, Seen)
end
-- true when `id` is new (and now remembered).
function Seen:add(id)
    if self.set[id] then return false end
    self.set[id] = true
    self.order[#self.order + 1] = id
    if #self.order > self.cap then self.set[table.remove(self.order, 1)] = nil end
    return true
end

return M
