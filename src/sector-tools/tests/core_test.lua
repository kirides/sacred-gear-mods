-- Unit tests of the sector tools' logic (core.lua). Plain Lua 5.1 / LuaJIT, no game:  luajit tests/core_test.lua  (from the mod's
-- folder). Exit code 0 when everything passes.
package.path = './?.lua;' .. package.path
local core = require('core')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

-- the grid: 64 tiles of 53.6656 units
check(math.abs(core.SECTOR - 3434.6) < 0.1, 'a sector is about 3434.6 units')
local cx, cy = core.cell_of(0, 0); eq(cx, 0, 'origin x'); eq(cy, 0, 'origin y')
cx, cy = core.cell_of(3434.5, 3434.7); eq(cx, 0, 'just inside the first cell'); eq(cy, 1, 'just past the first cell')
cx, cy = core.cell_of(-1, -1); eq(cx, -1, 'negative x is the cell before'); eq(cy, -1, 'negative y')
cx, cy = core.cell_of(45 * core.SECTOR + 10, 67 * core.SECTOR + 10); eq(cx, 45, 'cell 45'); eq(cy, 67, 'cell 67')
local ox, oy = core.cell_origin(45, 67); check(math.abs(ox - 45 * core.SECTOR) < 1e-6 and math.abs(oy - 67 * core.SECTOR) < 1e-6, 'cell origin')

-- the ground projection and its inverse
local px, py = core.project(0, 0, 512, 360); eq(px, 512, 'the hero stays at the anchor x'); eq(py, 360, 'the hero stays at the anchor y')
px, py = core.project(core.TILE, 0, 512, 360); check(math.abs(px - 560) < 1e-9 and math.abs(py - 384) < 1e-9, 'one tile along x is 48 right and 24 down')
px, py = core.project(0, core.TILE, 512, 360); check(math.abs(px - 464) < 1e-9 and math.abs(py - 384) < 1e-9, 'one tile along y is 48 left and 24 down')
local dx, dy = core.unproject(48, 24); check(math.abs(dx - core.TILE) < 1e-9 and math.abs(dy) < 1e-9, 'unproject')
for _, p in ipairs({{123, -456}, {3000, 2000}, {-40, 77}}) do
    local sx, sy = core.project(p[1], p[2], 0, 0)
    local bx, by = core.unproject(sx, sy)
    check(math.abs(bx - p[1]) < 1e-6 and math.abs(by - p[2]) < 1e-6, 'project and unproject agree for ' .. p[1] .. ',' .. p[2])
end

-- edges near a coordinate
local edges = core.edges_near(core.SECTOR * 3 + 1500, 500)
eq(#edges, 0, 'no edge within 500 units of a cell\'s inside')
edges = core.edges_near(core.SECTOR * 3 - 100, 500); eq(#edges, 1, 'one edge close by'); eq(edges[1], 3, 'it is the edge 3')
edges = core.edges_near(core.SECTOR * 3, 5000); eq(#edges, 3, 'a wide reach: three edges')

-- compaction of sector lists
local function compact_text(ids) return core.compact_text(core.compact(core.sorted(ids))) end
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
eq(compact_text(set({})), '', 'empty')
eq(compact_text(set({2909})), '2909', 'one')
eq(compact_text(set({2909, 2910})), '2909, 2910', 'two in a row stay single')
eq(compact_text(set({2910, 2911, 2912})), '{2910, 2912}', 'three in a row make a range')
eq(compact_text(set({2909, 2911, 2912, 2913, 2920, 2921, 2922, 2923, 2930})), '2909, {2911, 2913}, {2920, 2923}, 2930', 'mixed')
eq(compact_text(set({5, 3, 4, 1})), '1, {3, 5}', 'unordered input')

-- names and the line for the server
eq(core.lua_string('Silver Creek'), '"Silver Creek"', 'plain name')
eq(core.lua_string('Say "hi" \\ there'), '"Say \\"hi\\" \\\\ there"', 'quotes and backslashes')
eq(core.lua_string('a\nb\tc'), '"a b c"', 'control characters')
eq(core.lua_string(nil), '""', 'nil')
eq(core.slug('Silver Creek'), 'silver_creek', 'slug')
eq(core.slug('  Fort  Dun-Mor! '), 'fort_dun_mor', 'slug of punctuation')
eq(core.slug('123 Gate'), 'area_123_gate', 'a slug does not start with a digit')
eq(core.slug('!!!'), 'area', 'a slug of nothing')
-- the same text the server's "!area show" prints (WorldEventsScriptTests.AdminsRecordAreasByWalking...)
eq(core.snippet({id = 'silver_creek', name = 'Silver "Creek"', ids = set({2910, 2911, 2912, 2920, 2915}), circle = {x = 5000, y = 6000, r = 800}}),
    'silver_creek = { name = "Silver \\"Creek\\"", sectors = {{2910, 2912}, 2915, 2920}, circle = { x = 5000, y = 6000, r = 800 } },', 'full snippet')
eq(core.snippet({id = 'town', name = 'Town', ids = set({1, 2})}), 'town = { name = "Town", sectors = {1, 2} },', 'sectors only')
eq(core.snippet({id = 'spot', name = 'Spot', ids = {}, circle = {x = 10.4, y = 20.6, r = 1500}}), 'spot = { name = "Spot", circle = { x = 10, y = 21, r = 1500 } },', 'circle only, rounded')
eq(core.snippet({id = 'r', name = 'R', ids = {}, regions = {4, 2, 4}}), 'r = { name = "R", regions = {2, 4} },', 'regions of an area, sorted, no repeats')
eq(core.region_text({id = 4, name = 'Desert'}, 9), 'Desert (id 4, code 9)', 'region text')
eq(core.region_text({id = 4, name = ''}), 'Region 4 (id 4)', 'a nameless region')
eq(core.region_text(nil), 'no region', 'no region')
eq(core.region_line({id = 4, name = 'Desert'}), 'regions = { 4 },  -- Desert', 'the region line for a config')
eq(core.region_line({id = 3, name = 'A' .. string.char(10) .. 'B -- C'}), 'regions = { 3 },  -- A B - - C', 'comment text is cleaned')
eq(core.region_line(nil), nil, 'no region, no line')
-- region names from text keys (the same hash as the game / the server)
eq(core.text_hash('UI_REGION_SOUTHKERN'), 280942659, 'text hash'); eq(core.text_hash('UI_REGION_WUSTE'), 1628257094, 'text hash 2')
local texts = {[280942659 + 2147483648] = 'Southern Core Region'}
eq(core.region_name({id = 1, name = 'UI_REGION_SOUTHKERN'}, function(id) return texts[id] end), 'Southern Core Region', 'a key is resolved through the texts')
eq(core.region_name({id = 1, name = 'UI_REGION_SOUTHKERN'}, function() return nil end), 'Southkern', 'no text: the readable key')
eq(core.region_name({id = 1, name = 'UI_REGION_SOUTHKERN'}), 'Southkern', 'no text function: the readable key')
eq(core.region_name({id = 1, name = 'UI_REGION_SOUTHKERN'}, function() error('x') end), 'Southkern', 'a failing lookup never throws')
eq(core.region_name({id = 9, name = ''}), 'Region 9', 'never empty'); eq(core.region_name({id = 4, name = 'Desert'}), 'Desert', 'a plain name stays')
eq(core.region_text({id = 1, name = 'UI_REGION_SOUTHKERN'}, 3, function(id) return texts[id] end), 'Southern Core Region (id 1, code 3)', 'panel text with the localized name')
eq(core.region_line({id = 1, name = 'UI_REGION_SOUTHKERN'}, function(id) return texts[id] end), 'regions = { 1 },  -- Southern Core Region', 'config line with the localized name')
eq(core.region_line({id = 1, name = 'UI_REGION_SOUTHKERN'}), 'regions = { 1 },  -- Southkern', 'config line without text')

eq(core.snippet({id = 'a', name = 'A', ids = set({7}), near = 2}), 'a = { name = "A", sectors = {7}, near = 2 },', 'near')
eq(core.snippet({name = 'No Id', ids = set({7})}), 'no_id = { name = "No Id", sectors = {7} },', 'the id from the name')

print(('sector-tools core: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
