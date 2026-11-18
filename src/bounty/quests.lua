-- Daily and weekly quests: the pure logic (no `gear` calls, tested in tests/quests_test.lua).
--
-- Every real-world day (local midnight) and every week (Monday) the same rotation comes up: a few quests drawn from a pool with a
-- seed made of the date, so two computers (or two runs) show the same quests. Finishing every quest of a day (or week) is one
-- step of a streak: consecutive days (weeks) completed. Every N steps the streak pays a bonus. A missed day breaks the streak.
--
-- The state of a hero is one plain table (`data`, saved per savegame by main.lua with gear.store.game); every function here
-- takes it, changes it and returns events as plain tables for main.lua to publish and toast:
--   {name = 'started'|'progress'|'completed'|'failed', quest = q, previous = n?}
--   {name = 'streak', period = 'daily'|'weekly', count, best, bonus = true?}    one more day / week in a row
--   {name = 'streak_lost', period, previous}                                    the streak broke
--   {name = 'set_completed', period}                                            every quest of the day / week is done
-- Rewards are not paid here: a finished quest, and the streak bonus, go into `data.pending`; main.lua pays them when the game
-- lets it (`take_pending`), so a reward is never lost because the hero was in a loading screen.

local board = require('localboard')

local M = {}

M.PERIODS = {'daily', 'weekly'}

-- What the quests draw from. `names`: words of the creature's type name (no names: any monster); `gold`: for a hero of level 10
-- (localboard.gold_for scales it); `item`: tier 1 .. 3 of an extra item. The player's quests.json can replace the lists.
M.DEFAULTS = {
    daily = {
        slots = 3,
        pool = {
            {id = 'orcs', title = 'Orc patrol', names = {'orc'}, target = {8, 16}, gold = 400},
            {id = 'undead', title = 'Grave walk', names = {'skeleton', 'zombie', 'mummy', 'ghost'}, target = {10, 20}, gold = 500},
            {id = 'spiders', title = 'Cobwebs', names = {'spider'}, target = {8, 14}, gold = 350},
            {id = 'thieves', title = 'Roadside trouble', names = {'thief', 'pirate'}, target = {8, 15}, gold = 450},
            {id = 'beasts', title = 'Wild beasts', names = {'wolf', 'bear', 'boar'}, target = {8, 15}, gold = 350},
            {id = 'trolls', title = 'Under the bridge', names = {'troll', 'ogre', 'minotaur'}, target = {4, 8}, gold = 700, min_level = 8},
            {id = 'demons', title = 'Demon sighting', names = {'demon', 'gargoyle', 'golem'}, target = {5, 10}, gold = 1000, min_level = 15},
            {id = 'dragons', title = 'Dragon scare', names = {'dragon'}, target = {1, 2}, gold = 2000, min_level = 20},
            {id = 'any', title = 'Monster hunt', names = {}, target = {30, 60}, gold = 600},
        },
    },
    weekly = {
        slots = 2,
        pool = {
            {id = 'orcs', title = 'Orc campaign', names = {'orc'}, target = {60, 100}, gold = 3000, item = 1},
            {id = 'undead', title = 'Cleanse the crypts', names = {'skeleton', 'zombie', 'mummy', 'ghost'}, target = {80, 120}, gold = 3500},
            {id = 'spiders', title = 'Spider season', names = {'spider'}, target = {50, 90}, gold = 2500},
            {id = 'thieves', title = 'Clear the roads', names = {'thief', 'pirate'}, target = {60, 100}, gold = 3000},
            {id = 'beasts', title = 'The great hunt', names = {'wolf', 'bear', 'boar'}, target = {60, 100}, gold = 2500},
            {id = 'trolls', title = 'Bridge keeper', names = {'troll', 'ogre', 'minotaur'}, target = {25, 40}, gold = 5000, item = 1, min_level = 8},
            {id = 'demons', title = 'Demon purge', names = {'demon', 'gargoyle', 'golem'}, target = {30, 50}, gold = 8000, item = 2, min_level = 15},
            {id = 'dragons', title = 'Dragon slayer', names = {'dragon'}, target = {8, 12}, gold = 15000, item = 3, min_level = 20},
            {id = 'any', title = 'Relentless', names = {}, target = {250, 400}, gold = 4000, item = 1},
        },
    },
    -- Every `every` steps in a row: gold (+ gold_step for each bonus after the first, at most max_steps of them) and an item tier.
    streak = {
        daily = {every = 3, gold = 600, gold_step = 200, max_steps = 10, item = 1},
        weekly = {every = 2, gold = 3000, gold_step = 1000, max_steps = 10, item = 2},
    },
    seed = 'sacred',
}

---------------------------------------------------------------------------------------------------------------------
-- Calendar: the local date as a day number, so months and years need no special care
---------------------------------------------------------------------------------------------------------------------

-- Days since 1970-01-01 of the civil date y-m-d (Howard Hinnant's algorithm).
function M.days_from_civil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The calendar day (local time) of unix time `t`.
function M.day_of(t)
    local d = os.date('*t', t)
    return M.days_from_civil(d.year, d.month, d.day)
end

-- The week (Monday to Sunday) a day number is in; 1970-01-01 was a Thursday.
function M.week_of_day(day) return math.floor((day + 3) / 7) end

function M.key_of(period, t)
    local day = M.day_of(t)
    return period == 'weekly' and M.week_of_day(day) or day
end

local function seconds_into_day(t)
    local d = os.date('*t', t)
    return d.hour * 3600 + d.min * 60 + d.sec
end

-- Seconds until the period's quests change (local midnight, or midnight before Monday).
function M.seconds_left(period, t)
    local left = 86400 - seconds_into_day(t)
    if period == 'weekly' then left = left + (6 - (M.day_of(t) + 3) % 7) * 86400 end
    return left
end

-- 'YYYY-MM-DD' of a day number (for the panel and the logs).
function M.date_text(day)
    local z = day + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    return ('%04d-%02d-%02d'):format(yoe + era * 400 + (m <= 2 and 1 or 0), m, d)
end

---------------------------------------------------------------------------------------------------------------------
-- The seeded draw: the same date and seed word give the same numbers (Park-Miller, exact in doubles)
---------------------------------------------------------------------------------------------------------------------

local function hash(text)
    local h = 7
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
    return h
end
M.hash = hash

function M.rng(seed_text)
    local s = hash(seed_text) % 2147483646 + 1
    return function(lo, hi)
        s = s * 48271 % 2147483647
        if not lo then return (s - 1) / 2147483646 end
        return lo + math.floor((s - 1) / 2147483646 * (hi - lo + 1))
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Configuration (the player's quests.json over the defaults) and the hero's state
---------------------------------------------------------------------------------------------------------------------

local function num(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end

local function words(list)
    local out = {}
    for _, w in ipairs(type(list) == 'table' and list or {}) do
        if type(w) == 'string' and w:match('%S') then out[#out + 1] = (w:lower():gsub('[^%a]', '')) end
    end
    return out
end

-- A pool entry, or nil: {id, title, names, target = {lo, hi}, gold, item = item spec, min_level}.
function M.clean_entry(d)
    if type(d) ~= 'table' or type(d.id) ~= 'string' or d.id == '' then return nil end
    local t = d.target
    local lo, hi
    if type(t) == 'table' then lo, hi = num(t[1], 1, 100000, nil), num(t[2] or t[1], 1, 100000, nil) else lo = num(t, 1, 100000, nil) hi = lo end
    if not lo then return nil end
    return {
        id = d.id:sub(1, 40), title = tostring(d.title or d.id):sub(1, 40), names = words(d.names),
        target = {math.floor(lo), math.floor(math.max(lo, hi or lo))},
        gold = math.floor(num(d.gold, 0, 2000000000, 0)), item = board.item_spec(d.item),
        min_level = math.floor(num(d.min_level, 1, 1000, 1)),
    }
end

local function clean_streak(s, default)
    s = type(s) == 'table' and s or {}
    local item = default.item
    if s.item ~= nil then item = s.item end        -- false: no item
    if item == false then item = nil end
    return {
        every = math.floor(num(s.every, 1, 365, default.every)), gold = math.floor(num(s.gold, 0, 2000000000, default.gold)),
        gold_step = math.floor(num(s.gold_step, 0, 2000000000, default.gold_step)),
        max_steps = math.floor(num(s.max_steps, 1, 1000, default.max_steps)),
        item = board.item_spec(item),
        off = s.off == true,
    }
end

local function copy_pool(pool)
    local out = {}
    for _, e in ipairs(pool) do out[#out + 1] = M.clean_entry(e) end
    return out
end

-- The configuration for `data` of quests.json (or nil: the defaults). A bad entry is dropped, a missing list keeps the default.
function M.clean_config(data)
    data = type(data) == 'table' and data or {}
    local cfg = {seed = type(data.seed) == 'string' and data.seed ~= '' and data.seed:sub(1, 30) or M.DEFAULTS.seed, streak = {}}
    for _, p in ipairs(M.PERIODS) do
        local src = type(data[p]) == 'table' and data[p] or {}
        local pool = {}
        for _, e in ipairs(type(src.pool) == 'table' and src.pool or {}) do
            local c = M.clean_entry(e)
            if c then pool[#pool + 1] = c end
        end
        if #pool == 0 then pool = copy_pool(M.DEFAULTS[p].pool) end
        cfg[p] = {slots = math.floor(num(src.slots, 0, 12, M.DEFAULTS[p].slots)), pool = pool}
        cfg.streak[p] = clean_streak(type(data.streak) == 'table' and data.streak[p], M.DEFAULTS.streak[p])
    end
    return cfg
end

local function empty_streak() return {count = 0, best = 0, last = 0} end

function M.new_state()
    return {v = 1, daily = {quests = {}}, weekly = {quests = {}}, streak = {daily = empty_streak(), weekly = empty_streak()},
        pending = {}, totals = {daily = 0, weekly = 0, quests = 0}}
end

local function clean_quest(q)
    if type(q) ~= 'table' or type(q.id) ~= 'string' or type(q.title) ~= 'string' or not tonumber(q.target) then return nil end
    local out = {
        id = q.id, def = tostring(q.def or ''), period = q.period == 'weekly' and 'weekly' or 'daily', title = q.title,
        names = words(q.names), target = math.max(1, math.floor(q.target)), min_level = math.max(1, math.floor(tonumber(q.min_level) or 1)),
        gold = math.max(0, math.floor(tonumber(q.gold) or 0)), item = board.item_spec(q.item),
        n = math.max(0, math.floor(tonumber(q.n) or 0)), done = q.done == true, claimed = q.claimed == true,
    }
    out.n = math.min(out.n, out.target)
    out.text = M.what_text(out)
    return out
end

-- Repairs a loaded state (anything may be in a hand-edited or old file); returns a state table, never nil.
function M.sanitize(data)
    local s = M.new_state()
    if type(data) ~= 'table' then return s end
    for _, p in ipairs(M.PERIODS) do
        local src = type(data[p]) == 'table' and data[p] or {}
        s[p].key = tonumber(src.key) and math.floor(src.key) or nil
        s[p].complete = src.complete == true
        for _, q in ipairs(type(src.quests) == 'table' and src.quests or {}) do
            local c = clean_quest(q)
            if c then c.period = p s[p].quests[#s[p].quests + 1] = c end
        end
        local st = type(data.streak) == 'table' and type(data.streak[p]) == 'table' and data.streak[p] or {}
        s.streak[p] = {count = math.max(0, math.floor(tonumber(st.count) or 0)), best = math.max(0, math.floor(tonumber(st.best) or 0)),
            last = math.floor(tonumber(st.last) or 0)}
        s.streak[p].best = math.max(s.streak[p].best, s.streak[p].count)
        local tot = type(data.totals) == 'table' and tonumber(data.totals[p]) or 0
        s.totals[p] = math.max(0, math.floor(tot))
    end
    if type(data.totals) == 'table' then s.totals.quests = math.max(0, math.floor(tonumber(data.totals.quests) or 0)) end
    for _, e in ipairs(type(data.pending) == 'table' and data.pending or {}) do
        if type(e) == 'table' and type(e.id) == 'string' and type(e.title) == 'string' then
            s.pending[#s.pending + 1] = {id = e.id, kind = e.kind == 'bonus' and 'bonus' or 'quest', period = e.period == 'weekly' and 'weekly' or 'daily',
                title = e.title, gold = math.max(0, math.floor(tonumber(e.gold) or 0)), item = board.item_spec(e.item),
                tries = math.floor(tonumber(e.tries) or 0)}
        end
    end
    return s
end

---------------------------------------------------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------------------------------------------------

function M.what_text(q)
    return 'Defeat ' .. q.target .. ' ' .. (#q.names > 0 and table.concat(q.names, '/') .. ' ' or '') .. 'creatures'
end

-- 'N gold and an item' for a gold amount and an item spec.
function M.reward_text(gold, item)
    local parts = {}
    if (gold or 0) > 0 then parts[#parts + 1] = gold .. ' gold' end
    local it = board.item_spec(item)
    if it then
        parts[#parts + 1] = it.mode == 'specific' and (#it.types == 1 and it.types[1].name or ('one of ' .. #it.types .. ' items'))
            or it.mode == 'class' and 'an item for your class' or 'an item'
    end
    return #parts > 0 and table.concat(parts, ' and ') or 'glory'
end

---------------------------------------------------------------------------------------------------------------------
-- Rotation
---------------------------------------------------------------------------------------------------------------------

local function generate(period, key, level, cfg)
    local rng = M.rng(('%s:%s:%d'):format(cfg.seed, period, key))
    local c = cfg[period]
    local candidates = {}
    for _, def in ipairs(c.pool) do
        if def.min_level <= level then candidates[#candidates + 1] = def end
    end
    local list = {}
    local slots = math.min(c.slots, #candidates)
    for _ = 1, slots do
        local i = rng(1, #candidates)
        local def = table.remove(candidates, i)
        local target = def.target[1] == def.target[2] and def.target[1] or rng(def.target[1], def.target[2])
        local q = {
            id = ('%s:%d:%s'):format(period, key, def.id), def = def.id, period = period, title = def.title, names = def.names,
            target = target, min_level = def.min_level, gold = def.gold > 0 and board.gold_for(def.gold, level) or 0,
            item = def.item, n = 0, done = false, claimed = false,
        }
        q.text = M.what_text(q)
        list[#list + 1] = q
    end
    return list
end

-- Brings the state to the date of `now` (unix time): at a new day / week the old quests end (the unfinished ones fail), a broken
-- streak is reset and the new quests are drawn. Never goes back in time. `first` is set in the events of a state that had no
-- quests yet (the first look of a session reports what is running as initial). Returns events.
function M.roll(data, now, level, cfg)
    local events = {}
    for _, period in ipairs(M.PERIODS) do
        local key = M.key_of(period, now)
        local p, st = data[period], data.streak[period]
        if p.key == nil or key > p.key then
            if cfg.streak[period] and st.count > 0 and st.last < key - 1 then
                events[#events + 1] = {name = 'streak_lost', period = period, previous = st.count}
                st.count = 0
            end
            if p.key ~= nil then
                for _, q in ipairs(p.quests) do
                    if not q.done then events[#events + 1] = {name = 'failed', quest = q} end
                end
            end
            p.key, p.complete, p.quests = key, false, generate(period, key, level or 1, cfg)
            for _, q in ipairs(p.quests) do events[#events + 1] = {name = 'started', quest = q, fresh = true} end
        end
    end
    return events
end

-- The bonus of a streak that just reached `count`: nil unless count is a multiple of `every`.
function M.bonus_for(period, count, cfg, level)
    local s = cfg.streak[period]
    if not s or s.off or count <= 0 or count % s.every ~= 0 then return nil end
    local step = math.min(count / s.every, s.max_steps)
    local gold = s.gold + s.gold_step * (step - 1)
    return {gold = gold > 0 and board.gold_for(gold, level or 10) or 0, item = s.item, step = step}
end

local function reward_entry(q)
    return {id = q.id, kind = 'quest', period = q.period, title = q.title, gold = q.gold, item = q.item, tries = 0}
end

-- The set of a period is complete: one more step of the streak. Returns the events and queues the bonus.
local function complete_set(data, period, cfg, level, events)
    local p, st = data[period], data.streak[period]
    p.complete = true
    data.totals[period] = data.totals[period] + 1
    events[#events + 1] = {name = 'set_completed', period = period}
    if st.last == p.key then return end                  -- the same day was already counted
    st.count = (st.last == p.key - 1 and st.count or 0) + 1
    st.best = math.max(st.best, st.count)
    st.last = p.key
    local bonus = M.bonus_for(period, st.count, cfg, level)
    local ev = {name = 'streak', period = period, count = st.count, best = st.best}
    if bonus then
        ev.bonus = true
        data.pending[#data.pending + 1] = {id = ('bonus:%s:%d'):format(period, p.key), kind = 'bonus', period = period,
            title = (period == 'daily' and st.count .. ' days' or st.count .. ' weeks') .. ' in a row', gold = bonus.gold, item = bonus.item, tries = 0}
    end
    events[#events + 1] = ev
end

-- A kill of a creature with these type-name `words` by a hero of `level`. Returns events; finished quests go into data.pending.
function M.kill(data, words_set, level, cfg)
    local events = {}
    for _, period in ipairs(M.PERIODS) do
        local p = data[period]
        local touched = false
        for _, q in ipairs(p.quests) do
            if not q.done and level >= q.min_level then
                local hit = #q.names == 0
                for _, w in ipairs(q.names) do if words_set[w] then hit = true break end end
                if hit then
                    touched = true
                    q.n = q.n + 1
                    events[#events + 1] = {name = 'progress', quest = q, previous = q.n - 1}
                    if q.n >= q.target then
                        q.done = true
                        data.totals.quests = data.totals.quests + 1
                        data.pending[#data.pending + 1] = reward_entry(q)
                        events[#events + 1] = {name = 'completed', quest = q}
                    end
                end
            end
        end
        if touched and not p.complete and #p.quests > 0 then
            local all = true
            for _, q in ipairs(p.quests) do if not q.done then all = false end end
            if all then complete_set(data, period, cfg, level, events) end
        end
    end
    return events
end

-- Hands out the rewards waiting to be paid: returns the list and empties it (a quest of it is marked claimed). The caller pays;
-- `put_back(entry)` can return one that could not be paid.
function M.take_pending(data)
    local list = data.pending
    data.pending = {}
    for _, e in ipairs(list) do
        if e.kind == 'quest' then
            for _, period in ipairs(M.PERIODS) do
                for _, q in ipairs(data[period].quests) do if q.id == e.id then q.claimed = true end end
            end
        end
    end
    return list
end

function M.put_back(data, entry)
    entry.tries = (entry.tries or 0) + 1
    table.insert(data.pending, entry)
    for _, period in ipairs(M.PERIODS) do
        for _, q in ipairs(data[period].quests) do if q.id == entry.id then q.claimed = false end end
    end
end

---------------------------------------------------------------------------------------------------------------------
-- What the panel draws; the server sends the same shape over bounty:quests
---------------------------------------------------------------------------------------------------------------------

-- Steps of the streak left until its next bonus (0: no bonuses).
function M.next_bonus(count, cfg_streak)
    if not cfg_streak or cfg_streak.off then return 0 end
    return cfg_streak.every - count % cfg_streak.every
end

function M.payload(data, now, cfg, level)
    local out = {v = 1, ['local'] = true, pending = #data.pending, totals = data.totals, streak = {}}
    for _, period in ipairs(M.PERIODS) do
        local p, list, done = data[period], {}, 0
        for _, q in ipairs(p.quests) do
            if q.done then done = done + 1 end
            list[#list + 1] = {id = q.id, title = q.title, text = q.text, target = q.target, n = q.n, done = q.done, claimed = q.claimed,
                reward = M.reward_text(q.gold, q.item), level = q.min_level}
        end
        out[period] = {key = p.key, left = M.seconds_left(period, now), quests = list, done = done, complete = p.complete == true}
        local st, cs = data.streak[period], cfg.streak[period]
        -- the streak is "alive" while the last step was today / this week or the one before; it breaks when that one is missed too
        local alive = st.count > 0 and p.key ~= nil and st.last >= p.key - 1
        local nb = M.next_bonus(st.count, cs)
        local bonus = nb > 0 and M.bonus_for(period, st.count + nb, cfg, level)
        out.streak[period] = {count = alive and st.count or 0, best = st.best, today = st.last == p.key, every = cs.every,
            next_in = nb, bonus = bonus and M.reward_text(bonus.gold, bonus.item) or nil}
    end
    return out
end

-- A flat list for hooks.diff: the quests of both periods as bounties with their period.
function M.flatten(payload)
    local list = {}
    for _, period in ipairs(M.PERIODS) do
        for _, q in ipairs(payload[period] and payload[period].quests or {}) do
            list[#list + 1] = {id = q.id, period = period, title = q.title, text = q.text, target = q.target, n = q.n, done = q.done,
                reward = q.reward, level = q.level}
        end
    end
    return {bounties = list}
end

return M
