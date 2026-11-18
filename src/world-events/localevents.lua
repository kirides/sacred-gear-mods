-- World events without a server: the single player / LAN mode. The mod runs the events itself from its own events.json (the format the
-- server's `/mods/world_events/export` writes), counts the hero's kills, fires the hooks (spawn waves, items, gold, messages for the hero)
-- and produces the same state table the server pushes, so the bar shows it unchanged. Plain Lua 5.1 / LuaJIT, no gear.*
-- (tested in tests/localevents_test.lua); localgame.lua does what touches the game.
--
-- events.json: {"v": 1, "config": {"first_delay": 60, "cooldown": 900, "result_hold": 120, "order": "sequence" | "random"},
--   "events": [{"id", "title", "goal": "kill", "target", "duration" (seconds), "names": ["orc"], "types": [38], "sectors": [2909, [2950, 2960]], "regions": [4],
--               "unit", "text", "area" (a label), "hooks": [...]}]}
-- Time counts while the game runs (it stops with the game), so an event never ends while you are away.
local hooks = require('hooks')

local M = {}

M.DEFAULT_CONFIG = {first_delay = 60, cooldown = 900, result_hold = 120, order = 'sequence'}

-- A small built-in rotation for a player who has no events.json yet (the file is written from it, to edit).
M.DEFAULT = {
    v = 1,
    config = M.DEFAULT_CONFIG,
    events = {
        {id = 'orc-hunt', title = 'Orc hunt', goal = 'kill', target = 100, duration = 1800, names = {'orc'}, unit = 'orcs',
         hooks = {
             {at = 50, actions = {{action = 'message', text = 'Halfway! The orcs send help.', target = 'global'},
                                  {action = 'spawn', n = 6, kinds = {{type = 'Orc Warrior', weight = 3}, {type = 'Orc Shaman', weight = 1}}, radius = 500, target = 'owner'}}},
             {on = 'success', actions = {{action = 'gold', amount = 5000, target = 'killer'}}},
         }},
    },
}

local function list_of(v, check)
    local out = {}
    if type(v) == 'table' then
        for _, x in ipairs(v) do
            local c = check(x)
            if c ~= nil then out[#out + 1] = c end
        end
    end
    return out
end

local function range_of(v)
    if type(v) == 'number' then return {v, v} end
    if type(v) == 'table' and tonumber(v[1]) and tonumber(v[2]) then return {math.floor(v[1]), math.floor(v[2])} end
    return nil
end

-- Checks one event definition of events.json: a clean copy or nil and a reason.
function M.clean_event(raw, limits)
    if type(raw) ~= 'table' then return nil, 'not an object' end
    local id = tostring(raw.id or ''):gsub('[^%w_%-]', '')
    if id == '' then return nil, 'an event needs an id' end
    local target = hooks.int_in(raw.target, 1, 100000000)
    local duration = hooks.int_in(raw.duration, 10, 30 * 86400)
    if not target then return nil, id .. ': target must be 1 .. 100000000' end
    if not duration then return nil, id .. ': duration must be 10 seconds to 30 days' end
    local def = {
        id = id, title = tostring(raw.title or id):gsub('%c', ' '):sub(1, 60), goal = 'kill', target = target, duration = duration,
        names = list_of(raw.names, function(x) return type(x) == 'string' and x ~= '' and x:lower():sub(1, 48) or nil end),
        types = list_of(raw.types, function(x) return hooks.int_in(x, 1, 4294967295) end),
        sectors = list_of(raw.sectors, range_of),
        regions = list_of(raw.regions, function(x) return hooks.int_in(x, 1, 255) end),
        unit = tostring(raw.unit or ''):gsub('%c', ' '):sub(1, 24),
        area = tostring(raw.area or ''):gsub('%c', ' '):sub(1, 40),
        text = tostring(raw.text or ''):gsub('%c', ' '):sub(1, 90),
    }
    local clean, refused = hooks.clean(raw.hooks, limits)
    def.hooks = clean
    def.refused = refused
    return def
end

-- Does a kill count for the event? `names` match a part of the creature's name, `types` its type number, no filter counts any creature;
-- `sectors` need the creature's sector when it is known (an unknown place counts).
function M.counts(def, name, type_id, sector, region)
    if #def.names > 0 or #def.types > 0 then
        local ok = false
        for _, n in ipairs(def.names) do
            if type(name) == 'string' and name:lower():find(n, 1, true) then ok = true end
        end
        for _, t in ipairs(def.types) do if t == type_id then ok = true end end
        if not ok then return false end
    end
    if #def.regions > 0 then               -- bound to game regions: the creature's region must be one of them
        local inside = false
        for _, r in ipairs(def.regions) do if r == region then inside = true end end
        if not inside then return false end
    end
    if #def.sectors > 0 and sector and sector > 0 then
        local inside = false
        for _, r in ipairs(def.sectors) do if sector >= r[1] and sector <= r[2] then inside = true end end
        if not inside then return false end
    end
    return true
end

local Local = {}
Local.__index = Local

-- opts: defs (a decoded events.json), store (the persistent table: {seq, index, elapsed, wait, current, result}), rnd(k) -> 1..k,
-- act(action, context, key, index), log(text). `store` is changed in place; `changed` says it must be saved.
function M.new(opts)
    local self = setmetatable({}, Local)
    local file = type(opts.defs) == 'table' and opts.defs or M.DEFAULT
    local config = {}
    for k, v in pairs(M.DEFAULT_CONFIG) do config[k] = v end
    if type(file.config) == 'table' then
        config.first_delay = hooks.int_in(file.config.first_delay, 0, 86400 * 30) or config.first_delay
        config.cooldown = hooks.int_in(file.config.cooldown, 0, 86400 * 30) or config.cooldown
        config.result_hold = hooks.int_in(file.config.result_hold, 0, 3600) or config.result_hold
        if file.config.order == 'random' then config.order = 'random' end
    end
    self.config = config
    self.defs, self.by_id = {}, {}
    self.log = opts.log or function() end
    for i, raw in ipairs(type(file.events) == 'table' and file.events or {}) do
        local def, why = M.clean_event(raw)
        if def then
            self.defs[#self.defs + 1] = def
            self.by_id[def.id] = def
            for _, r in ipairs(def.refused or {}) do self.log('event ' .. def.id .. ': ' .. r) end
        else self.log('event #' .. i .. ' refused: ' .. tostring(why)) end
    end
    self.store = opts.store
    self.store.seq = self.store.seq or 0
    self.store.index = self.store.index or 0
    self.store.wait = self.store.wait or config.first_delay
    self.rnd = opts.rnd or function(k) return math.random(k) end
    self.act = opts.act or function() end
    self.changed = false
    self.runner = nil
    self:attach()
    return self
end

-- Binds the hook engine to the running event (after loading and after a new start).
function Local:attach()
    local cur = self.store.current
    if not cur then self.runner = nil; return end
    local def = self.by_id[cur.id]
    cur.fired, cur.hk = cur.fired or {}, cur.hk or {}
    if not def then self.runner = nil; return end
    self.runner = hooks.runner(def.hooks, cur, function(action, ctx, key, index)
        self.act(action, ctx, key, index, def)
    end)
end

function Local:current()
    local cur = self.store.current
    return cur and self.by_id[cur.id] and cur or nil, cur and self.by_id[cur.id]
end

function Local:begin(def)
    local s = self.store
    s.seq = s.seq + 1
    s.current = {n = s.seq, id = def.id, elapsed = 0, count = 0, fired = {}, hk = {}}
    s.result = nil
    self.changed = true
    self:attach()
    self.log(('event %s begins: %d to defeat in %d seconds'):format(def.title, def.target, def.duration))
    self.runner:on('start', {})
    self:progress({})
end

function Local:finish(success)
    local s = self.store
    local cur, def = self:current()
    if not cur then s.current = nil; return end
    self.runner:on(success and 'success' or 'fail', {})
    s.result = {n = cur.n, id = cur.id, title = def.title, success = success, count = cur.count, target = def.target, hold = self.config.result_hold,
        unit = def.unit, area = def.area, text = def.text}
    s.current = nil
    s.wait = self.config.cooldown
    self.runner = nil
    self.changed = true
end

function Local:progress(ctx)
    local cur, def = self:current()
    if not cur or not self.runner then return end
    self.runner:progress(cur.count * 100 / def.target, cur.elapsed, ctx)
    if self.runner.changed then self.changed = true; self.runner.changed = false end
end

-- `dt` seconds of game time passed (at most 5 are counted: a pause or a slow frame is not an event running out).
function Local:tick(dt)
    dt = math.max(0, math.min(tonumber(dt) or 0, 5))
    local s = self.store
    local cur, def = self:current()
    if s.current and not cur then s.current = nil; self.changed = true end      -- its definition is gone from events.json
    if cur then
        cur.elapsed = cur.elapsed + dt
        self:progress({})
        if cur.count >= def.target then self:finish(true)
        elseif cur.elapsed >= def.duration then self:finish(false) end
        self.changed = true
    else
        if s.result then
            s.result.hold = s.result.hold - dt
            if s.result.hold <= 0 then s.result = nil end
        end
        if #self.defs > 0 then
            s.wait = s.wait - dt
            if s.wait <= 0 then
                local def2
                if self.config.order == 'random' then def2 = self.defs[self.rnd(#self.defs)]
                else s.index = s.index % #self.defs + 1; def2 = self.defs[s.index] end
                self:begin(def2)
            end
        end
        self.changed = true
    end
end

-- A kill of the hero. Returns true when it counted for the running event.
function Local:kill(name, type_id, sector, region)
    local cur, def = self:current()
    if not cur then return false end
    local ctx = {killer = true}
    if self.runner then self.runner:kill(name, type_id, 'me', ctx, region) end
    local counted = M.counts(def, name, type_id, sector, region)
    if counted then
        cur.count = cur.count + 1
        self:progress(ctx)
        if cur.count >= def.target then self:finish(true) end
    end
    if self.runner and self.runner.changed then self.changed = true; self.runner.changed = false end
    self.changed = true
    return counted
end

-- The state for the bar, in the table the server pushes (see core.parse); nil while nothing is shown.
function Local:payload()
    local s = self.store
    local cur, def = self:current()
    if cur then
        local unit = def.unit ~= '' and def.unit or ((def.names[1] or 'creature') .. 's')
        return {
            v = 1, st = 'active', n = cur.n, title = def.title, text = def.text ~= '' and def.text or ('Defeat %d %s'):format(def.target, unit),
            unit = unit, area = def.area, count = cur.count, target = def.target, left = math.max(0, def.duration - cur.elapsed), dur = def.duration,
            here = true, mine = cur.count, need = 0, people = 1, reward = '', hook = hooks.next_text(def.hooks, cur.fired),
        }
    end
    local r = s.result
    if r and r.hold > 0 then
        return {v = 1, st = r.success and 'won' or 'failed', n = r.n, title = r.title, text = r.text or '', unit = r.unit or '', area = r.area or '',
            count = r.count, target = r.target, hold = r.hold, here = true, people = 1}
    end
    return nil
end

return M
