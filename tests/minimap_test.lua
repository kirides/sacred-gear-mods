-- Logic test of the minimap's geometry outside the game. From the repository root:
--     luajit tests/minimap_test.lua
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local P = dofile('src/minimap/projection.lua')

-- the transform and its inverse agree
for _, t in ipairs({{100, 200}, {1500, 900}, {2400, 2400}, {0, 0}}) do
    local px, py = P.to_map(t[1], t[2])
    local x, y = P.to_tile(px, py)
    ok(near(x, t[1], 1e-6) and near(y, t[2], 1e-6), 'round trip ' .. t[1] .. ',' .. t[2])
end

-- tile names: the Underworld on top, Ancaria below
ok(P.tile_name(0, 0) == 'UI_WORLDMAPUW00.TGA', 'underworld tile')
ok(P.tile_name(2, 7) == 'UI_WORLDMAPUW27.TGA', 'last underworld row')
ok(P.tile_name(3, 0) == 'UI_WORLDMAPX00.TGA', 'first ancaria tile')
ok(P.tile_name(10, 7) == 'UI_WORLDMAPX77.TGA', 'last ancaria tile')

-- a view in the middle of one tile needs that tile only; on a corner it needs four
local set = P.visible_tiles(128 + 256 * 3, 128 + 256 * 5, 100, 100, 1)
ok(#set == 1 and set[1].r == 5 and set[1].c == 3, 'one tile')
set = P.visible_tiles(256 * 3, 256 * 5, 100, 100, 1)
ok(#set == 4, 'four tiles at a corner: ' .. #set)
-- the view is clamped to the picture
set = P.visible_tiles(5, 5, 400, 400, 1)
ok(#set == 1 and set[1].r == 0 and set[1].c == 0, 'clamped at the corner: ' .. #set)
-- zooming out takes in more tiles
local wide = P.visible_tiles(1024, 1400, 200, 200, P.ZOOMS[1])
local close = P.visible_tiles(1024, 1400, 200, 200, P.ZOOMS[#P.ZOOMS])
ok(#wide >= #close, 'widest level sees at least as many tiles')

-- zoom levels: clamped, rounded, ascending
ok(P.zoom_of(0) == P.ZOOMS[1] and P.zoom_of(99) == P.ZOOMS[#P.ZOOMS], 'zoom clamps')
for i = 2, #P.ZOOMS do ok(P.ZOOMS[i] > P.ZOOMS[i - 1], 'zooms ascend') end

-- the circle: symmetric strips, widest in the middle, never outside the circle
local strips = P.circle_strips(200, 4)
ok(#strips == 50, 'fifty strips')
local mid = strips[25]
ok(mid.w > 195, 'middle strip is wide')
ok(strips[1].w < strips[25].w and near(strips[1].w, strips[50].w, 1e-6), 'strips narrow to the ends symmetrically')
for i, s in ipairs(strips) do
    ok(near(s.x + s.w / 2, 100, 1e-6), 'strip ' .. i .. ' is centred')
    ok(s.x >= -1e-9 and s.x + s.w <= 200 + 1e-9, 'strip ' .. i .. ' inside the box')
end

if failures == 0 then print('minimap_test: all passed') else os.exit(1) end
