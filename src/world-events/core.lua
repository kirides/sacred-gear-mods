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
    if st == 'active' then
        s.left = math.max(0, tonumber(payload.left) or 0)
        s.dur = math.max(1, tonumber(payload.dur) or 1)
        s.mine = math.max(0, tonumber(payload.mine) or 0)
        s.need = math.max(0, tonumber(payload.need) or 0)
        s.reward = M.clean(payload.reward, 60)
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
function Model:receive(payload, now)
    local s, err = M.parse(payload)
    if not s then self.error = err; return false end
    self.error = nil
    s.at = now
    local old, crossed = self.state, nil
    if old and old.st == 'active' and s.st == 'active' and old.n == s.n then
        local before, after = M.percent(old.count, old.target), M.percent(s.count, s.target)
        for _, mark in ipairs(M.MARKS) do
            if before < mark and after >= mark then crossed = mark end
        end
    end
    self.state = s
    return true, crossed
end

function Model:reset()
    self.state = nil
    self.error = nil
end

-- A sample for the layout editor: what an event looks like.
M.SAMPLE = {
    st = 'active', title = 'Orc hunt', text = 'Slay 1000 orcs', unit = 'orcs', count = 370, target = 1000, left = 4325, dur = 7200,
    here = true, mine = 12, need = 10, people = 5, reward = 'gold, an item', n = 1,
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
    opts = opts or {}
    local s = self.state
    if s and (now - s.at) > M.STALE then s = nil end
    if (not s or s.st == 'idle') and opts.preview then
        s = M.parse(M.SAMPLE) or {st = 'idle', at = now}
        s.at = now
    end
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
        if s.text ~= '' then tip[#tip + 1] = s.text end
        tip[#tip + 1] = ('%s%s (%d%%)'):format(count_text, unit, pct)
        tip[#tip + 1] = 'Time left: ' .. time_text
        tip[#tip + 1] = mine_text
        if s.reward ~= '' then tip[#tip + 1] = 'Reward: ' .. s.reward end
        return {
            kind = 'active', title = s.title, text = s.text, count = s.count, target = s.target, unit = s.unit,
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
    local tip = {s.title, won and 'Completed!' or 'Failed', ('%s%s (%d%%)'):format(count_text, unit, pct)}
    if won and s.people > 0 then tip[#tip + 1] = ('%d heroes took part'):format(s.people) end
    return {
        kind = s.st, title = s.title, text = won and 'Completed!' or 'Failed', count = s.count, target = s.target, unit = s.unit,
        percent = pct, frac = M.clamp(s.count / s.target, 0, 1), left = 0, time_frac = 0, time_text = '',
        count_text = count_text, line2 = won and 'Completed!' or 'Failed', people = s.people, qualifies = won, tip = tip,
        alpha = M.clamp(remaining / M.FADE, 0, 1), mine_text = '',
    }
end

return M
