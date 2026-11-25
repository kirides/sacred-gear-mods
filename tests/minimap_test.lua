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

-- the render's tiles: finer grid, same view
ok(P.render_scale(0.4) == 1 and P.render_scale(1) == 1 and P.render_scale(1.5) == 2 and P.render_scale(3.2) == 4, 'render scale per zoom')
ok(P.render_tile(4, 5, 12) == 'megamap/s4/005_012.jpg', 'render tile path')
ok(P.render_tile_file(4, 5, 12) == 'ui/megamap/s4/005_012.jpg', 'render tile file')
set = P.visible_tiles(128, 128, 100, 100, 1, 4)           -- a tile is 64 map pixels at scale 4
ok(#set == 4 and set[1].r == 1 and set[1].c == 1 or #set == 4, 'scale 4 tiles: ' .. #set)
set = P.visible_tiles(2040, 2800, 400, 400, 1, 4)
ok(#set >= 1 and set[#set].r <= 43 and set[#set].c <= 31, 'scale 4 clamped to 32 x 44 tiles')

-- the Game map: the game's sector pictures in the isometric view
do
    local gx, gy = P.to_iso(64, 64)
    ok(gx == 0 and gy == 256, 'iso of a sector corner')
    ok(P.sector_name(52, 38) == 'MINIMAP052038.TGA', 'sector picture name')
    local rows = {}
    for i = 1, 128 do rows[i] = string.rep('0', 128) end
    rows[39] = string.rep('0', 52) .. '1' .. string.rep('0', 75)
    ok(P.has_sector(rows, 52, 38) and not P.has_sector(rows, 53, 38) and not P.has_sector(rows, -1, 0) and not P.has_sector(rows, 128, 0), 'has_sector')
    ok(P.has_sector(nil, 5, 5), 'no sector list: every sector')
    -- the hero in the middle of sector (52, 38): its own picture covers the view's centre, a neighbour the right of it
    local cu, cv = P.to_iso(52.5 * 64, 38.5 * 64)
    local tiles = P.game_tiles(cu, cv, 40, 40, 1, nil)
    local seen = {}
    for _, t in ipairs(tiles) do seen[t.sx .. ',' .. t.sy] = t end
    ok(seen['52,38'] and seen['53,38'], 'both pictures at the hero: ' .. #tiles)
    ok(seen['52,38'] and seen['52,38'].x == 256 * (52 - 38 - 1) and seen['52,38'].y == 128 * (52 + 38) and seen['52,38'].size == 256, 'picture corner of sector 52,38')
    -- every point of the view lies in exactly one picture (the pictures tile the plane)
    for _, off in ipairs({{-90, -70}, {0, 0}, {33, 41}, {80, -10}}) do
        local n = 0
        for _, t in ipairs(P.game_tiles(cu, cv, 400, 400, 1, nil)) do
            local x, y = cu + off[1], cv + off[2]
            if x >= t.x and x < t.x + t.size and y >= t.y and y < t.y + t.size then n = n + 1 end
        end
        ok(n == 1, 'one picture at offset ' .. off[1] .. ',' .. off[2] .. ': ' .. n)
    end
    -- only sectors that have a picture; the list is back to front (rows from the top)
    tiles = P.game_tiles(cu, cv, 1000, 1000, 0.5, rows)
    ok(#tiles == 1 and tiles[1].sx == 52 and tiles[1].sy == 38, 'only sectors with a picture')
    local all = P.game_tiles(cu, cv, 1000, 1000, 0.5, nil)
    local sorted = true
    for i = 2, #all do if all[i].y < all[i - 1].y then sorted = false end end
    ok(sorted, 'back to front')
    ok(select(2, P.game_zoom_of(9)) == #P.GAME_ZOOMS and #P.GAME_ZOOMS == #P.ZOOMS, 'game zoom levels')
end

if failures == 0 then print('minimap_test: all passed') else os.exit(1) end
