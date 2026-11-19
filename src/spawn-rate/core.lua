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

-- Harmless wildlife and farm animals are never multiplied, whatever the game thinks of them: a name (RABBIT.GRN, dove_white.grn)
-- is split into words and each is compared to this list.
local AMBIENT = {}
for word in ([[rabbit bunny hare dove pigeon bird crow raven seagull gull sparrow chicken hen rooster chick duck goose swan parrot
    butterfly firefly dragonfly bee frog toad fish squirrel deer cow pig sheep goat horse donkey cat dog]]):gmatch('%a+') do AMBIENT[word] = true end

-- Whether a creature of this type name may be multiplied: not harmless wildlife; an unknown name (nil) is not multiplied either.
function M.multipliable(name)
    if type(name) ~= 'string' or name == '' then return false end
    for word in name:lower():gmatch('%a+') do
        if AMBIENT[word] then return false end
    end
    return true
end

-- A queue of waiting jobs {type, x, y, layer, left, origin}: `left` more creatures of that type near (x, y). The jobs are served
-- fairly: round robin over all jobs, the nearest to the hero first (the order is refreshed every `REFRESH` takes at most), one
-- creature per job per round, so a crowd far away never starves the creatures next to the hero and no single original takes
-- the whole cap. The queue holds `limit` jobs at most, a new job beyond that is refused (the caller tries it again later).
local Queue = {}
Queue.__index = Queue

function M.queue(limit)
    return setmetatable({jobs = {}, order = {}, cursor = 1, stale = true, limit = limit or 1000, left = 0}, Queue)
end

function Queue:size() return #self.jobs end

function Queue:push(job)
    if #self.jobs >= self.limit then return false end
    self.jobs[#self.jobs + 1] = job
    self.left = self.left + job.left
    self.stale = true
    return true
end

local function reorder(self, hx, hy)
    local order = {}
    for i, job in ipairs(self.jobs) do
        local dx, dy = job.x - (hx or job.x), job.y - (hy or job.y)
        order[i] = {job = job, d = dx * dx + dy * dy}
    end
    table.sort(order, function(a, b) return a.d < b.d end)
    for i, e in ipairs(order) do order[i] = e.job end
    self.order, self.cursor, self.stale = order, 1, false
end

-- The next creature to make: {type, x, y, layer, origin} (the job's `left` already reduced), nil when the queue is empty. A
-- job leaves when it is done. (hx, hy) is where the hero is.
function Queue:take(hx, hy)
    if #self.jobs == 0 then return nil end
    if self.stale or self.cursor > #self.order then reorder(self, hx, hy) end
    local job = self.order[self.cursor]
    self.cursor = self.cursor + 1
    job.left = job.left - 1
    self.left = self.left - 1
    if job.left <= 0 then
        for i = #self.jobs, 1, -1 do
            if self.jobs[i] == job then table.remove(self.jobs, i); break end
        end
        self.stale = true
        self.cursor = 1
    end
    return {type = job.type, x = job.x, y = job.y, layer = job.layer, origin = job.origin}
end

-- Drops the jobs for which `drop(job)` is true; returns them (the caller forgets their originals again).
function Queue:drop_if(drop)
    local gone, kept = {}, {}
    for _, job in ipairs(self.jobs) do
        if drop(job) then gone[#gone + 1] = job; self.left = self.left - job.left else kept[#kept + 1] = job end
    end
    if #gone > 0 then self.jobs, self.stale = kept, true end
    return gone
end

function Queue:clear()
    self.jobs, self.order, self.cursor, self.stale, self.left = {}, {}, 1, true, 0
end

-- A place near (x, y) for an extra creature: a random point of the ring between `inner` and `outer` world units.
function M.scatter(x, y, inner, outer, rnd)
    rnd = rnd or math.random
    local angle = rnd() * 2 * math.pi
    local r = inner + (outer - inner) * rnd()
    return math.floor(x + math.cos(angle) * r + 0.5), math.floor(y + math.sin(angle) * r + 0.5)
end

return M
