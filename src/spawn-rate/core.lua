-- Spawn rate: the logic without the game (tests/spawn_rate_test.lua runs it outside the game).

local M = {}

-- How many extra creatures one spawned creature brings at `rate` (1 .. 100): rate - 1, and a fractional rate is the chance of
-- one more. `rnd` is math.random.
function M.extras(rate, rnd)
    rate = tonumber(rate) or 1
    if rate <= 1 then return 0 end
    rate = math.min(rate, 100)
    local whole = math.floor(rate - 1)
    local frac = (rate - 1) - whole
    if frac > 0 and (rnd or math.random)() < frac then whole = whole + 1 end
    return whole
end

-- How many extras may be made in this frame: the budget, cut while the frame time `dt` (seconds) is high (below 30 fps one
-- per frame, below 15 fps none) and limited by the room under the cap (`alive` extras now, `cap` the most; 0 = no limit).
function M.allowance(budget, dt, alive, cap)
    local n = budget
    if dt and dt > 0.066 then n = 0 elseif dt and dt > 0.033 then n = math.min(n, 1) end
    if cap and cap > 0 then n = math.min(n, math.max(0, cap - alive)) end
    return math.max(0, n)
end

-- A queue of waiting jobs {type, x, y, layer, left}: `left` more creatures of that type near (x, y). A job is worked off one
-- creature at a time; the queue holds `limit` jobs at most, a new job beyond that is refused (counted by the caller).
local Queue = {}
Queue.__index = Queue

function M.queue(limit)
    return setmetatable({first = 1, last = 0, jobs = {}, limit = limit or 1000, left = 0}, Queue)
end

function Queue:size() return self.last - self.first + 1 end

function Queue:push(job)
    if self:size() >= self.limit then return false end
    self.last = self.last + 1
    self.jobs[self.last] = job
    self.left = self.left + job.left
    return true
end

-- The next creature to make: the job (its `left` already reduced), nil when the queue is empty. The job leaves when it is done.
function Queue:take()
    if self.first > self.last then return nil end
    local job = self.jobs[self.first]
    job.left = job.left - 1
    self.left = self.left - 1
    local one = {type = job.type, x = job.x, y = job.y, layer = job.layer}
    if job.left <= 0 then
        self.jobs[self.first] = nil
        self.first = self.first + 1
    end
    return one
end

function Queue:clear()
    self.first, self.last, self.jobs, self.left = 1, 0, {}, 0
end

-- A place near (x, y) for an extra creature: a random point of the ring between `inner` and `outer` world units.
function M.scatter(x, y, inner, outer, rnd)
    rnd = rnd or math.random
    local angle = rnd() * 2 * math.pi
    local r = inner + (outer - inner) * rnd()
    return math.floor(x + math.cos(angle) * r + 0.5), math.floor(y + math.sin(angle) * r + 0.5)
end

return M
