-- The local bounty board for single player: no server, so this computer posts the bounties, counts the kills and pays.
--
-- Pure board logic (generation from the pool, progress, expiry, saving as a table); main.lua feeds it kills and time and
-- shows it, kills.lua finds the kills, rewards.lua pays. Nothing here touches the game, so it can be tested alone.
--
-- A hero's board is saved in the mod folder (`board_<hero>.json`, see main.lua). Time runs only while the hero plays:
-- a bounty's `left` counts down in game time, so being away (or loading an old save) does not use it up.

local M = {}

-- What the board draws from, like the server's pool. `names` are words in the creature's type name (ORC_WARRIOR.GRN has
-- "orc" and "warrior"; whole words only, so SORCERESS is not an orc). `gold` is the reward for a hero of level 10; it
-- grows and shrinks with the hero's level (M.gold_for). `item` is the quality tier of an extra item (1 good .. 3 rare).
M.POOL = {
    {id = 'orcs', title = 'Orc slayer', names = {'orc'}, target = {20, 40}, gold = 1200},
    {id = 'undead', title = 'Grave watch', names = {'skeleton', 'zombie', 'mummy', 'ghost'}, target = {25, 50}, gold = 1500},
    {id = 'spiders', title = 'Web cleaner', names = {'spider'}, target = {15, 30}, gold = 800, item = 1},
    {id = 'thieves', title = 'Road safety', names = {'thief', 'pirate'}, target = {20, 35}, gold = 1300},
    {id = 'beasts', title = 'Beast hunter', names = {'wolf', 'bear', 'boar'}, target = {15, 30}, gold = 800},
    {id = 'trolls', title = 'Troll bridge', names = {'troll', 'ogre', 'minotaur'}, target = {8, 15}, gold = 2000, min_level = 8, item = 1},
    {id = 'demons', title = 'Demon watch', names = {'demon', 'gargoyle', 'golem'}, target = {10, 20}, gold = 3000, min_level = 15, item = 2},
    {id = 'dragons', title = 'Dragon hunter', names = {'dragon'}, target = {3, 6}, gold = 6000, min_level = 20, item = 3},
}

M.SLOTS = 3
M.DURATION = 3 * 3600         -- seconds of play

local function ids_of(list)
    local set = {}
    for _, b in ipairs(list) do set[b.def] = true end
    return set
end

-- Gold for a hero of `level`: the pool's amount is for level 10, a level 1 hero gets 60 %, level 50 gets 5 times as much.
function M.gold_for(base, level)
    return math.max(10, math.floor(base * (0.5 + 0.1 * math.max(1, level)) / 1.5 / 10 + 0.5) * 10)
end

local function reward_text(b)
    local parts = {}
    if (b.gold or 0) > 0 then parts[#parts + 1] = b.gold .. ' gold' end
    if b.item then parts[#parts + 1] = 'an item' end
    return #parts > 0 and table.concat(parts, ' and ') or 'glory'
end

local function what_text(b)
    return 'Defeat ' .. b.target .. ' ' .. table.concat(b.names, '/') .. ' creatures'
end

local Board = {}
Board.__index = Board

-- `rng(lo, hi)` returns an integer in [lo, hi]; `pool` defaults to M.POOL.
function M.new(rng, pool)
    return setmetatable({seq = 0, list = {}, done_count = 0, rng = rng, pool = pool or M.POOL}, Board)
end

-- Words of the creature's type name, lower case: 'ORC_WARRIOR.GRN' -> orc, warrior, grn.
function M.words(type_name)
    local set = {}
    for w in tostring(type_name or ''):lower():gmatch('%a+') do set[w] = true end
    return set
end

local function draw_target(self, spec)
    if type(spec) == 'table' then
        local lo, hi = math.max(1, spec[1]), math.max(spec[1], spec[2] or spec[1])
        return lo == hi and lo or self.rng(lo, hi)
    end
    return math.max(1, spec)
end

-- Posts bounties until the board is full. `level` is the hero's level (a pool entry with a higher min_level stays out).
-- `first` staggers the end times so the board does not expire all at once. Returns the bounties posted.
function Board:fill(level, first)
    local posted = {}
    while #self.list < M.SLOTS do
        local taken, candidates = ids_of(self.list), {}
        for _, def in ipairs(self.pool) do
            if not taken[def.id] and (def.min_level or 1) <= level then candidates[#candidates + 1] = def end
        end
        if #candidates == 0 then break end
        local def = candidates[self.rng(1, #candidates)]
        local duration = M.DURATION
        if first then duration = duration * (0.4 + 0.6 * (#self.list + 1) / M.SLOTS) end
        self.seq = self.seq + 1
        local b = {
            id = self.seq, def = def.id, title = def.title, names = def.names, target = draw_target(self, def.target),
            min_level = def.min_level or 1, gold = M.gold_for(def.gold or 0, level), item = def.item, left = duration, n = 0,
            done = false,
        }
        b.text = what_text(b)
        self.list[#self.list + 1] = b
        posted[#posted + 1] = b
    end
    return posted
end

-- Game time passes. Expired bounties go (a finished one stays until it runs out too, so its "done" can be seen).
-- Returns the bounties that ended.
function Board:tick(dt)
    local gone, kept = {}, {}
    for _, b in ipairs(self.list) do
        b.left = b.left - dt
        if b.left <= 0 then gone[#gone + 1] = b else kept[#kept + 1] = b end
    end
    self.list = kept
    return gone
end

-- A kill of a creature with these type-name `words` by a hero of `level`. Returns the bounties it completed.
function Board:kill(words, level)
    local finished = {}
    for _, b in ipairs(self.list) do
        if not b.done and level >= b.min_level then
            for _, w in ipairs(b.names) do
                if words[w] then
                    b.n = b.n + 1
                    if b.n >= b.target then
                        b.done = true
                        self.done_count = self.done_count + 1
                        finished[#finished + 1] = b
                    end
                    break
                end
            end
        end
    end
    return finished
end

-- The payload the mod's panel draws (the same shape the server sends over bounty:state).
function Board:payload()
    local list = {}
    for _, b in ipairs(self.list) do
        list[#list + 1] = {
            id = b.id, title = b.title, text = b.text, target = b.target, n = b.n, done = b.done,
            left = math.max(0, math.floor(b.left)), reward = reward_text(b), claims = b.done and 1 or 0, level = b.min_level,
        }
    end
    return {v = 1, bounties = list, count = #list, done_count = self.done_count, ['local'] = true}
end

function Board:save_table()
    local list = {}
    for _, b in ipairs(self.list) do
        list[#list + 1] = {id = b.id, def = b.def, title = b.title, names = b.names, target = b.target, min_level = b.min_level,
            gold = b.gold, item = b.item, left = b.left, n = b.n, done = b.done}
    end
    return {v = 1, seq = self.seq, done_count = self.done_count, board = list}
end

local function is_names(t)
    if type(t) ~= 'table' or #t == 0 then return false end
    for _, w in ipairs(t) do if type(w) ~= 'string' then return false end end
    return true
end

-- Rebuilds a board from `save_table`'s result; everything is checked, a bad entry is dropped.
function M.load(data, rng, pool)
    local self = M.new(rng, pool)
    if type(data) ~= 'table' then return self end
    self.seq = math.max(0, math.floor(tonumber(data.seq) or 0))
    self.done_count = math.max(0, math.floor(tonumber(data.done_count) or 0))
    for _, e in ipairs(type(data.board) == 'table' and data.board or {}) do
        if type(e) == 'table' and type(e.def) == 'string' and type(e.title) == 'string' and is_names(e.names)
            and tonumber(e.target) and tonumber(e.left) and tonumber(e.left) > 0 then
            local b = {
                id = tonumber(e.id) or 0, def = e.def, title = e.title, names = e.names, target = math.max(1, math.floor(e.target)),
                min_level = math.max(1, math.floor(tonumber(e.min_level) or 1)), gold = math.max(0, math.floor(tonumber(e.gold) or 0)),
                item = tonumber(e.item), left = math.min(tonumber(e.left), M.DURATION), n = math.max(0, math.floor(tonumber(e.n) or 0)),
                done = e.done == true,
            }
            b.n = math.min(b.n, b.target)
            b.text = what_text(b)
            self.list[#self.list + 1] = b
        end
    end
    return self
end

return M
