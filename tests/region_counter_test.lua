-- Logic test of the region-counter mod outside the game (fake gear.data.regions). From the repository root:
--     luajit tests/region_counter_test.lua      (libraries from $SACRED_BILD, else ../sacred-bild)
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

local libs = dofile('tests/gear_libs.lua')

local function make(settings, disk)
    local G = {handlers = {}, settings = settings or {}, rec = {}, saved = {}}
    for i = 1, 31 do G.rec[i] = {index = i, id = i, name = '', boss = false, kills_needed = 0, kills_left = 0} end
    G.rec[1].kills_needed, G.rec[1].kills_left, G.rec[1].id, G.rec[1].name = 1000, 1000, 5, 'Test'
    local regions = {count = function() return 32 end, get = function(_, i) return G.rec[i] end}
    local hero = {name = function() return G.hero_name end}
    G.hero_name = 'Aria'
    local gear = {
        mod = {id = 'region-counter'}, data = {regions = regions}, world = {hero = function() return hero end},
        on = function(e, f) G.handlers[e] = G.handlers[e] or {}; table.insert(G.handlers[e], f) end,
        keys = {on = function() end},
        settings = {get = function(id, fb) local v = G.settings[id]; if v == nil then return fb end return v end},
        guard = function(_, fn) return function(...) local g, e = pcall(fn, ...); if not g then error(e) end return e end end,
        ui = {panel = function() return {open = false} end, show_panel = function() end, toggle_panel = function() end,
              text = function() end},
        log = function() end, every = function() end,
    }
    libs.install(gear, {'store'})
    -- keep the store in memory
    G.disk = disk or {}
    gear.store.load = function(n, d) return G.disk[n] or d end
    gear.store.save = function(n, v) G.disk[n] = v; return true end
    G.gear = gear
    local chunk = assert(loadfile('src/region-counter/main.lua'))
    setfenv(chunk, setmetatable({gear = gear}, {__index = _G}))
    chunk()
    return G
end
local function frames(G, n) for _ = 1, n do for _, f in ipairs(G.handlers.frame or {}) do f(0.5) end end end

do   -- 50 %: 500 needed, kills are counted, a reset by the game is undone
    local G = make({kill_percent = 50})
    frames(G, 1)
    ok(G.rec[1].kills_needed == 500 and G.rec[1].kills_left == 500, 'target set to 50 percent')
    G.rec[1].kills_left = 450; frames(G, 1)             -- 50 kills
    G.rec[1].kills_left = 1000; G.rec[1].kills_needed = 1000; frames(G, 1)   -- the game starts the region over
    ok(G.rec[1].kills_needed == 500 and G.rec[1].kills_left == 450, 'progress written back after a reset')
    G.rec[1].kills_left = 0; frames(G, 1)               -- the boss comes
    G.rec[1].kills_left = 1000; frames(G, 1)            -- a new cycle
    ok(G.rec[1].kills_left == 500, 'new cycle after the boss')
    for _, f in ipairs(G.handlers['session.stop'] or {}) do f() end
    ok(G.disk['region_kills.json'] ~= nil, 'progress saved')
end

do   -- progress is restored for the hero in a later session; another hero starts fresh
    local G = make({kill_percent = 100})
    frames(G, 1); G.rec[1].kills_left = 700; frames(G, 1)
    for _, f in ipairs(G.handlers['session.stop'] or {}) do f() end
    local G2 = make({kill_percent = 100}, G.disk)          -- the game started the region over at 1000
    frames(G2, 1)
    ok(G2.rec[1].kills_left == 700, 'progress restored for the hero')
    local G3 = make({kill_percent = 100}, G.disk); G3.hero_name = 'Bob'
    frames(G3, 1)
    ok(G3.rec[1].kills_left == 1000, 'another hero starts fresh')
end

do   -- changing the percent keeps the share
    local G = make({kill_percent = 100})
    frames(G, 1); G.rec[1].kills_left = 500; frames(G, 1)    -- half done
    G.settings.kill_percent = 50; frames(G, 1)
    ok(G.rec[1].kills_needed == 500 and G.rec[1].kills_left == 250, 'share kept when the percent changes')
end

print(failures == 0 and 'all passed' or (failures .. ' failed'))
os.exit(failures == 0 and 0 or 1)
