-- Wiring test of main.lua against a fake `gear`: when the tools show, recording by walking, the buttons, the clipboard line, the
-- controller menu. Plain Lua 5.1 / LuaJIT, no game:  luajit tests/main_test.lua  (from the mod's folder).
package.path = './?.lua;' .. package.path

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end

local SECTOR = 64 * 53.66563034057617

local function new_gear()
    local g = {now = 100, handlers = {}, calls = {}, files = {}, clip = nil, menu = {}, pressed = {}, mouse = {0, 0},
        settings = {area_name = 'Silver Creek', radius = 1500, near = 0, labels = true, anchor_x = 0, anchor_y = 0},
        hero = {x = SECTOR * 45 + 100, y = SECTOR * 67 + 100, layer = 0, sector = 2909}, near = {}, panels = {}}
    g.on = function(event, fn) g.handlers[event] = g.handlers[event] or {}; table.insert(g.handlers[event], fn) end
    g.fire = function(event, ...) for _, fn in ipairs(g.handlers[event] or {}) do fn(...) end end
    local hero_obj = {
        position = function() if g.hero then return g.hero.x, g.hero.y, g.hero.layer end end,
        sector = function() return g.hero and g.hero.sector end,
    }
    local function creature(x, y, sector)
        return {position = function() return x, y, 0 end, sector = function() return sector end}
    end
    g.creature = creature
    g.gear = {
        on = g.on, time = function() return g.now end, log = function() end,
        read = function(name) return g.files[name] end,
        save = function(name, text) g.files[name] = text; return true end,
        json = {
            encode = function(v)
                -- enough JSON for the two files: numbers, booleans, strings, arrays and objects
                local function enc(x)
                    if type(x) == 'table' then
                        if #x > 0 or next(x) == nil then
                            local parts = {}
                            for _, e in ipairs(x) do parts[#parts + 1] = enc(e) end
                            return '[' .. table.concat(parts, ',') .. ']'
                        end
                        local parts = {}
                        for k, e in pairs(x) do parts[#parts + 1] = ('%q:%s'):format(tostring(k), enc(e)) end
                        table.sort(parts)
                        return '{' .. table.concat(parts, ',') .. '}'
                    elseif type(x) == 'string' then return ('%q'):format(x)
                    else return tostring(x) end
                end
                return enc(v)
            end,
            decode = function(text)
                -- the test's own files only: through load with the JSON syntax mapped to Lua
                local lua = text:gsub('%[', '{'):gsub('%]', '}'):gsub('"([^"]-)":', '["%1"]=')
                local f = loadstring('return ' .. lua)
                return f and f()
            end,
        },
        settings = {get = function(id) return g.settings[id] end, set = function(id, v) g.settings[id] = v end},
        clipboard = {set = function(text) g.clip = text; return true end, get = function() return g.clip end},
        world = {
            hero = function() if g.hero then return hero_obj end end,
            creatures_near = function() return g.near end,
            items_near = function() return {} end,
        },
        ui = {
            panel = function(id, title, x, y, w, h)
                table.insert(g.panels, {id = id, title = title})
                return {open = true, key = 'sector-tools:' .. id, x = x, y = y, w = w, h = h, content_x = x + 8, content_y = y + 28, content_w = w - 16}
            end,
            button = function(id, x, y, w, h, text) g.buttons[id] = text; local p = g.pressed[id]; g.pressed[id] = nil; return p == true end,
            slider = function(id, x, y, w, min, max, value) return false, value end,
            text = function(t) table.insert(g.calls, 'text:' .. tostring(t)) end,
            rect = function() g.rects = g.rects + 1 end,
            text_wrap = function(t) return {t}, 14 end,
            mouse = function() return g.mouse[1], g.mouse[2] end,
            edit_mode = function() return false end,
            menu_item = function(id, label, fn) g.menu[id] = {label = label, fn = fn} end,
        },
    }
    g.buttons, g.rects = {}, 0
    return g
end

local function load_mod(g)
    package.loaded['core'] = nil
    _G.gear = g.gear
    _G.loadstring = loadstring
    return assert(loadfile('main.lua'))()
end

local function frame(g) g.fire('frame', 0.016) end
local function draw(g, state)
    g.calls, g.panels, g.rects = {}, {}, 0
    g.fire('draw', state or {mode = 'game', show_text = false, screen_left = 0, screen_top = 0, screen_right = 1024, screen_bottom = 768})
end
local function has(g, needle)
    for _, c in ipairs(g.calls) do if c:find(needle, 1, true) then return true end end
    return false
end
local function command(g, op) local c = {op = op}; g.fire('sector-tools.command', c); return c end
local function query(g) local q = {}; g.fire('sector-tools.query', q); return q end

local g = new_gear()
load_mod(g)
check(g.menu.show and g.menu.labels and g.menu.copy, 'controller menu entries: show, lines, copy')
frame(g)
local q = query(g)
check(q.sector == 2909 and q.cx == 45 and q.cy == 67, 'the hero\'s sector and cell are followed')
check(q.known['0:45,67'] == 2909, 'the id of the hero\'s cell is learned')

-- shown only with Alt, pinned, or just after Alt
draw(g)
check(#g.panels == 0, 'hidden by default')
draw(g, {mode = 'game', show_text = true, screen_left = 0, screen_top = 0, screen_right = 1024, screen_bottom = 768})
check(#g.panels == 1 and g.panels[1].id == 'panel', 'Alt shows the panel')
check(has(g, 'text:Sector 2909   cell 45,67   layer 0'), 'the panel shows the sector, the cell and the layer')
check(has(g, 'text:Sector 2909'), 'the ground label of the hero\'s own sector')
check(g.rects > 0, 'ground lines or dots are drawn')
g.now = g.now + 1
draw(g)
check(#g.panels == 1, 'it stays a moment after Alt is released')
g.now = g.now + 5
draw(g)
check(#g.panels == 0, 'and goes')
g.menu.show.fn()
draw(g)
check(#g.panels == 1, 'pinned from the controller menu')
g.menu.show.fn()
draw(g)
check(#g.panels == 0, 'unpinned')
draw(g, {mode = 'menus'})
check(#g.panels == 0, 'nothing in the menus')

-- ground lines off
g.menu.show.fn()
g.settings.labels = false
draw(g)
local without = g.rects
g.settings.labels = true
draw(g)
check(g.rects > without, 'the ground lines can be switched off')
g.menu.labels.fn()
check(g.settings.labels == false, 'the menu entry switches the lines')
g.menu.labels.fn()

-- recording by walking
check(not command(g, 'copy').ok, 'nothing to copy yet')
command(g, 'start')
q = query(g)
check(q.recording and #q.ids == 1 and q.ids[1] == 2909, 'start records the sector of the hero')
for _, id in ipairs({2910, 2911, 2912, 2920, 2915, 2911}) do g.hero.sector = id; frame(g) end
q = query(g)
check(#q.ids == 6, 'every sector walked into is added once: ' .. #q.ids)
command(g, 'stop')
g.hero.sector = 3000; frame(g)
check(#query(g).ids == 6, 'after stop nothing more is added')
g.hero.sector = 2909; frame(g)
command(g, 'circle')
q = query(g)
check(q.circle and q.circle.r == 1500 and q.circle.x == g.hero.x, 'a circle at the hero with the radius setting')
local copied = command(g, 'copy')
check(copied.ok, 'copy works')
check(g.clip:find('silver_creek = { name = "Silver Creek", sectors = {{2909, 2912}, 2915, 2920}, circle = { x = ', 1, true) == 1
    and g.clip:find(', r = 1500 } },', 1, true), 'the clipboard has the line for world_events.lua: ' .. tostring(g.clip))
g.settings.near = 2
command(g, 'copy')
check(g.clip:find('near = 2', 1, true) ~= nil, 'near goes into the line')
command(g, 'copy_id')
check(g.clip == '2909', 'copy id: the sector number')
g.hero.sector = 0; frame(g)
check(not command(g, 'copy_id').ok, 'no sector, no id')
g.hero.sector = 2909; frame(g)
-- the buttons do the same (the tools are still pinned from above)
g.pressed.clear = true
draw(g)
q = query(g)
check(#q.ids == 0 and q.circle == nil, 'the Clear button clears')
g.pressed.rec = true
draw(g)
check(query(g).recording, 'the Start button starts')
g.pressed.add = true; g.hero.sector = 2921; frame(g); draw(g)
check(#query(g).ids >= 1, 'the Add button adds')
g.pressed.copy = true; draw(g)
check(g.clip:find('sectors = {', 1, true) ~= nil, 'the Copy button copies')

-- the recording is kept in a file
g.now = g.now + 3
frame(g)
check(g.files['state.json'] ~= nil, 'the recording is saved')
local g2 = new_gear()
g2.files['state.json'] = g.files['state.json']
local m = load_mod(g2)
check(next(m.rec.ids) ~= nil, 'and read again at the next start')

-- unknown cells: the neighbours' sectors come from creatures nearby
local g3 = new_gear()
g3.near = {g3.creature(SECTOR * 46 + 50, SECTOR * 67 + 50, 2910)}
load_mod(g3)
frame(g3)
check(query(g3).known['0:46,67'] == 2910, 'a creature next door teaches the id of its cell')

-- no hero
local g4 = new_gear()
g4.hero = nil
load_mod(g4)
frame(g4)
g4.menu.show.fn()
draw(g4)
check(#g4.panels == 1 and has(g4, 'text:No hero yet.'), 'the panel says so without a hero')
check(not command(g4, 'copy_id').ok and not command(g4, 'circle').ok, 'no hero: nothing to copy')

-- the game region of the hero (gear.data.regions): shown in the panel, copied as a config line
local g5 = new_gear()
g5.gear.data = {regions = {of_sector = function(_, sector) if sector == 2909 then return {id = 4, name = 'Desert'}, 9 end end}}
load_mod(g5)
frame(g5)
g5.menu.show.fn()
draw(g5)
check(has(g5, 'text:Region: Desert (id 4, code 9)'), 'the panel shows the region')
check(query(g5).region.id == 4 and query(g5).region_code == 9, 'the query has the region')
local c5 = command(g5, 'copy_region')
check(c5.ok and c5.text == 'regions = { 4 },  -- Desert' and g5.clip == c5.text, 'copy region puts the config line on the clipboard')
g5.hero.sector = 5000
frame(g5)
draw(g5)
check(has(g5, 'text:Region: no region'), 'outside a region the panel says so')
check(not command(g5, 'copy_region').ok, 'and there is nothing to copy')
-- an older Gear without gear.data.regions: no region, no error
frame(g); draw(g)
check(has(g, 'text:Region: no region'), 'without the region API: no region')

print(('sector-tools main: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
