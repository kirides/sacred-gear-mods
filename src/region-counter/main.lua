-- Region counter: the Region Boss quests come after a number of kills in a region. The game keeps that countdown in
-- memory only (gear.data.regions): it is not in the savegame, and it starts over when you leave the region.
--   * Kills needed: the countdown of every region is set to a share (kill_percent) of the vanilla number.
--   * Progress: the kills done in each region are kept per hero in region_kills.json (the mod's folder) and written
--     back whenever the game starts a region over.
-- Every half second the mod compares the game's "kills left" with what it wrote last: lower means kills (added to
-- the progress), higher means the game started over (the progress is written back, or dropped with keep_progress off).

local W = gear.world
local guard, store = gear.guard, gear.store
local function setting(id, fallback) return gear.settings.get(id, fallback) end

local FILE = 'region_kills.json'
local POLL = 0.5

local hero_name = nil
local track = {}          -- region index -> {id, vanilla, target, done, expect}

-- The kills belong to the savegame: kept per savegame (gear.store.game; an older Gear keeps one file for all of them). The file
-- from before is taken by the first savegame that is loaded.
local file = (store.game or store.file)(FILE, {heroes = {}}, {every = 30, migrate = true, check = function(d)
    if type(d) ~= 'table' or type(d.heroes) ~= 'table' then return {heroes = {}} end
    return d
end, on_change = function()
    -- another game: the regions are counted again from what that game kept
    hero_name = nil
    track = {}
end})
local poll_t = 0

local function regions() return gear.data and gear.data.regions end

local function target_for(vanilla)
    local pct = tonumber(setting('kill_percent', 100)) or 100
    return math.max(1, math.floor(vanilla * pct / 100 + 0.5))
end

local function saved_for(name, id)
    local h = file.data.heroes[name]
    local s = h and h[tostring(id)]
    if type(s) == 'table' and tonumber(s.done) and tonumber(s.of) and s.of > 0 then return s end
end

local function remember(t)
    if not hero_name or not setting('keep_progress', true) then return end
    local h = file.data.heroes[hero_name]
    if not h then h = {}; file.data.heroes[hero_name] = h end
    local s = h[tostring(t.id)]
    if not s or s.done ~= t.done or s.of ~= t.target then
        h[tostring(t.id)] = {done = t.done, of = t.target}
        file:changed()
    end
end

local function clamp(v, hi) return math.max(0, math.min(hi, v)) end

local function apply(r, t)
    t.expect = t.target - t.done
    r.kills_needed = t.target
    r.kills_left = t.expect
end

local function poll()
    local R = regions()
    if not R then return end
    local hero = W.hero()
    if not hero then return end
    local okn, name = pcall(hero.name, hero)
    if not okn or not name then return end
    if name ~= hero_name then hero_name = name; track = {} end
    for i = 1, R:count() - 1 do
        local r = R:get(i)
        local needed, left = r and r.kills_needed, r and r.kills_left
        if needed and left and needed > 0 then
            local t = track[i]
            if not t then
                -- first time this hero's region is seen: vanilla numbers (100 .. 50000 as the game sets them up)
                if needed >= 100 and needed <= 50000 and left <= needed then
                    t = {id = r.id, vanilla = needed, target = target_for(needed)}
                    local s = setting('keep_progress', true) and saved_for(name, r.id)
                    if s then
                        t.done = clamp(math.floor(s.done / s.of * t.target + 0.5), t.target)
                    else
                        t.done = clamp(math.floor((needed - left) * t.target / needed + 0.5), t.target)
                    end
                    track[i] = t
                    apply(r, t)
                    remember(t)
                end
            else
                local target = target_for(t.vanilla)
                if target ~= t.target then
                    t.done = clamp(math.floor(t.done / t.target * target + 0.5), target)
                    t.target = target
                    apply(r, t)
                    remember(t)
                elseif left < t.expect then
                    t.done = clamp(t.done + (t.expect - left), t.target)
                    t.expect = t.target - t.done
                    remember(t)
                elseif left > t.expect or needed ~= t.target then
                    -- the game started the region over (a new region, or a new cycle after the boss)
                    if t.expect == 0 or not setting('keep_progress', true) then t.done = 0 end
                    apply(r, t)
                    remember(t)
                end
            end
        end
    end
end

gear.on('session.start', guard('session.start', function() hero_name = nil; track = {} end))
gear.on('session.stop', guard('session.stop', function() file:flush(); hero_name = nil; track = {} end))
gear.on('unload', guard('unload', function() file:flush() end))

gear.on('frame', guard('frame', function(dt)
    dt = tonumber(dt) or 0
    if dt < 0 or dt > 5 then dt = 0 end
    poll_t = poll_t + dt
    if poll_t >= POLL then poll_t = 0; poll() end
end))
