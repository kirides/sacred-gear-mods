-- World events, the logic without the game: the state the server pushes (channel 'worldevents:state'), what the bar shows
-- from it, and the number formats. Plain Lua 5.1 / LuaJIT, no gear.* (tested in tests/core_test.lua).
local M = {}

-- The server pushes every few seconds while an event runs; without a push for this long (a server that went away) the
-- bar disappears.
M.STALE = 120

function M.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- A percent as the server sends it: 30, or 12.5 (nothing for a missing one).
function M.number(value)
    value = tonumber(value)
    if not value then return '?' end
    local text = ('%.1f'):format(value):gsub('%.0$', '')
    return text
end

-- Seconds as 1:12:05, 12:30 or 0:45.
function M.format_time(seconds)
    seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then return ('%d:%02d:%02d'):format(h, m, s) end
    return ('%d:%02d'):format(m, s)
end

-- Whole percent, rounded down (99.9 % is 99: only a finished goal shows 100); 0 for a bad target.
function M.percent(count, target)
    count, target = tonumber(count) or 0, tonumber(target) or 0
    if target <= 0 then return 0 end
    return M.clamp(math.floor(count * 100 / target), 0, 100)
end

-- 12345 as 12,345.
function M.group(n)
    local s = ('%d'):format(math.floor((tonumber(n) or 0) + 0.5))
    local sign, digits = s:match('^(-?)(%d+)$')
    if not digits then return s end
    digits = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return sign .. (digits:gsub('^,', ''))
end

-- Text from the server: no control characters, no game markup (a backslash would start a code), a length limit.
function M.clean(text, max)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('%c', ' '):gsub('\\', '/')
    max = max or 80
    if #text > max then text = text:sub(1, max - 3) .. '...' end
    return text
end

local STATES = {active = true, won = true, failed = true, idle = true}

-- Checks a pushed table and returns the numbers and strings the bar needs (nil and a reason for anything else). The
-- server is trusted for its rules, not for its types: a malformed field never reaches a draw call.
function M.parse(payload)
    if type(payload) ~= 'table' then return nil, 'not a table' end
    local st = payload.st
    if not STATES[st] then return nil, 'unknown state' end
    local s = {st = st, here = payload.here == true}
    if st == 'idle' then
        s.next_in = tonumber(payload.next_in)
        s.here = false
        return s
    end
    s.title = M.clean(payload.title, 48)
    s.text = M.clean(payload.text, 90)
    s.count = math.max(0, tonumber(payload.count) or 0)
    s.target = math.max(1, tonumber(payload.target) or 1)
    s.n = tonumber(payload.n) or 0
    s.people = tonumber(payload.people) or 0
    s.unit = M.clean(payload.unit, 24)
    s.area = M.clean(payload.area, 40)
    if st == 'active' then
        s.left = math.max(0, tonumber(payload.left) or 0)
        s.dur = math.max(1, tonumber(payload.dur) or 1)
        s.mine = math.max(0, tonumber(payload.mine) or 0)
        s.need = math.max(0, tonumber(payload.need) or 0)
        s.reward = M.clean(payload.reward, 60)
        -- the reward odds (text from the server: the current row and the next one) and the percent they start at
        s.odds = M.clean(payload.odds, 120)
        s.odds_at = tonumber(payload.odds_at)
        s.odds_next = M.clean(payload.odds_next, 120)
        s.odds_next_at = tonumber(payload.odds_next_at)
        s.hook = M.clean(payload.hook, 150)     -- the next hook ("At 30% of the goal: 12 of Orc Warrior appear ..."), if the event has some
    else
        s.hold = math.max(0, tonumber(payload.hold) or 0)
    end
    return s
end

local Model = {}
Model.__index = Model

function M.new()
    return setmetatable({}, Model)
end

-- The marks at which the bar pulses.
M.MARKS = {25, 50, 75}

-- A state arrived at time `now` (seconds, any steady clock). Returns true when it was understood, and the mark (25, 50 or
-- 75) that this push of the same event just crossed, if any.
-- Several events can run at once: a push is one state, or {v = 1, list = {state, state, ...}} (at most M.MAX_STATES, each checked like a single one).
M.MAX_STATES = 8

local function crossed_mark(old, s)
    if old and old.st == 'active' and s.st == 'active' and old.n == s.n then
        local before, after = M.percent(old.count, old.target), M.percent(s.count, s.target)
        local crossed
        for _, mark in ipairs(M.MARKS) do
            if before < mark and after >= mark then crossed = mark end
        end
        return crossed
    end
end

function Model:receive(payload, now)
    local incoming = {}
    if type(payload) == 'table' and type(payload.list) == 'table' then
        for _, entry in ipairs(payload.list) do
            if #incoming >= M.MAX_STATES then break end
            local s = M.parse(entry)
            if s and s.st ~= 'idle' then incoming[#incoming + 1] = s end
        end
        if #incoming == 0 then
            self.error = 'no valid state in the list'
            if #payload.list == 0 then self.states, self.state, self.error = {}, nil, nil; return true end
            return false
        end
    else
        local s, err = M.parse(payload)
        if not s then self.error = err; return false end
        incoming[1] = s
    end
    self.error = nil
    local crossed
    local olds = self.states or (self.state and {self.state}) or {}
    for _, s in ipairs(incoming) do
        s.at = now
        for _, old in ipairs(olds) do crossed = crossed_mark(old, s) or crossed end
    end
    self.states = incoming
    self.state = incoming[1]
    return true, crossed
end

function Model:reset()
    self.state = nil
    self.states = nil
    self.error = nil
end

-- A sample for the layout editor: what an event looks like.
M.SAMPLE = {
    st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', unit = 'orcs', count = 370, target = 1000, left = 4325, dur = 7200,
    here = true, mine = 12, need = 10, people = 5, reward = 'gold, an item', n = 1,
    odds = 'Rare 20%, Magic 30%, Common 50%', odds_at = 30, odds_next = 'Legendary 2%, Epic 8%, Rare 25%, Magic 30%, Common 35%',
    odds_next_at = 80, hook = 'At 50% of the goal: 6 of Orc Warrior x3 / Orc Shaman appear around you',
}

-- The seconds over which a result fades out at the end of its hold.
M.FADE = 6

-- What to draw at time `now`, or nil for nothing.
--   opts.area     'sector' (only where the server says the event counts) or 'everywhere'
--   opts.results  show the result of a finished event for the time the server says
--   opts.preview  show the sample when there is no event (the layout editor)
-- The time left is counted down here between pushes, from the push's own clock reading, so the computers' clocks
-- do not matter. The view has the pill's two lines (title; count and time) and `tip`, the lines of the details tooltip.
function Model:view(now, opts)
    return (self:views(now, opts))[1]
end

-- All the pills to show: the active events first (the least time left first), then results; the sample in the layout editor when there is none.
function Model:views(now, opts)
    opts = opts or {}
    local out = {}
    local states = self.states or (self.state and {self.state}) or {}
    for _, s in ipairs(states) do
        if (now - s.at) <= M.STALE and s.st ~= 'idle' then
            local v = self:view_of(s, now, opts)
            if v then out[#out + 1] = v end
        end
    end
    if #out == 0 and opts.preview then
        local s = M.parse(M.SAMPLE)
        s.at = now
        out[1] = self:view_of(s, now, opts)
    end
    table.sort(out, function(a, b)
        local ra, rb = a.kind == 'active' and 0 or 1, b.kind == 'active' and 0 or 1
        if ra ~= rb then return ra < rb end
        return (a.left or 0) < (b.left or 0)
    end)
    return out
end

function Model:view_of(s, now, opts)
    opts = opts or {}
    if not s or s.st == 'idle' then return nil end
    local unit = s.unit ~= '' and (' ' .. s.unit) or ''
    local pct = M.percent(s.count, s.target)
    local count_text = M.group(s.count) .. ' / ' .. M.group(s.target)
    if s.st == 'active' then
        if opts.area ~= 'everywhere' and not s.here and not opts.preview then return nil end
        local left = math.max(0, s.left - (now - s.at))
        local qualifies = s.need <= 0 or s.mine >= s.need
        local time_text = M.format_time(left)
        local mine_text = (s.need > 0 and s.mine < s.need)
            and ('Your share: %d (%d needed for the reward)'):format(s.mine, s.need) or ('Your share: %d'):format(s.mine)
        local tip = {s.title}
        if s.area ~= '' then tip[#tip + 1] = 'Around ' .. s.area end
        if s.text ~= '' then tip[#tip + 1] = s.text end
        tip[#tip + 1] = ('%s%s (%d%%)'):format(count_text, unit, pct)
        tip[#tip + 1] = 'Time left: ' .. time_text
        tip[#tip + 1] = mine_text
        if s.reward ~= '' then tip[#tip + 1] = 'Reward: ' .. s.reward end
        if s.hook ~= '' then tip[#tip + 1] = 'Next: ' .. s.hook end
        if s.odds ~= '' or s.odds_next ~= '' then
            tip[#tip + 1] = 'Item odds:'
            if s.odds ~= '' then tip[#tip + 1] = ('  from %s%%: %s'):format(M.number(s.odds_at), s.odds) end
            if s.odds_next ~= '' then tip[#tip + 1] = ('  from %s%%: %s'):format(M.number(s.odds_next_at), s.odds_next) end
            tip[#tip + 1] = 'Rolled when the event ends, with the highest row reached.'
        end
        return {
            kind = 'active', title = s.title, text = s.text, count = s.count, target = s.target, unit = s.unit, area = s.area,
            percent = pct, frac = M.clamp(s.count / s.target, 0, 1), left = left, time_frac = M.clamp(left / s.dur, 0, 1),
            time_text = time_text, count_text = count_text, line2 = count_text .. unit, alpha = 1,
            late = left <= 60 and s.count < s.target, mine = s.mine, need = s.need, qualifies = qualifies,
            people = s.people, reward = s.reward, mine_text = mine_text, tip = tip,
        }
    end
    -- a result: one short line that fades out at the end of its hold
    if not opts.results then return nil end
    local remaining = s.hold - (now - s.at)
    if remaining <= 0 then return nil end
    if opts.area ~= 'everywhere' and not s.here then return nil end
    local won = s.st == 'won'
    local tip = {s.title}
    if s.area ~= '' then tip[#tip + 1] = 'Around ' .. s.area end
    tip[#tip + 1] = won and 'Completed!' or 'Failed'
    tip[#tip + 1] = ('%s%s (%d%%)'):format(count_text, unit, pct)
    if won and s.people > 0 then tip[#tip + 1] = ('%d heroes took part'):format(s.people) end
    return {
        kind = s.st, title = s.title, text = won and 'Completed!' or 'Failed', count = s.count, target = s.target, unit = s.unit, area = s.area,
        percent = pct, frac = M.clamp(s.count / s.target, 0, 1), left = 0, time_frac = 0, time_text = '',
        count_text = count_text, line2 = won and 'Completed!' or 'Failed', people = s.people, qualifies = won, tip = tip,
        alpha = M.clamp(remaining / M.FADE, 0, 1), mine_text = '',
    }
end

return M
