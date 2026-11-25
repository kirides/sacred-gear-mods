-- The world map's geometry (pure functions, tested outside the game: tests/minimap_test.lua).
--
-- The game's map is one picture of 8 x 11 tiles of 256 x 256 pixels, 2048 x 2816: the Underworld (UI_WORLDMAPUW<row><col>.TGA,
-- rows 0 to 2) lies above Ancaria (UI_WORLDMAPX<row><col>.TGA, rows 3 to 10 of the picture). A position in tiles (world units
-- / 53.66563) goes to the picture with the game's own affine transform (the engine's worldToMap, 0x6CB3B0, as the engine remake
-- documents it). The Underworld lies in the upper 768 pixels (Ancaria alone is the picture minus them: the engine subtracts 768 for it, this picture keeps them).
local P = {}

P.TILE = 53.66563034057617
P.COLS, P.ROWS = 8, 11
P.TILE_PX = 256
P.WIDTH, P.HEIGHT = 2048, 2816
P.UW_ROWS = 3
local STEP_X = 48 * 0.007446
local STEP_Y = 24 * 0.014914
local ORIGIN_X, ORIGIN_Y = 1018.7499389648438, -186.9473876953125

--- Tile position (tx, ty) -> picture pixel (px, py).
function P.to_map(tx, ty)
    return ORIGIN_X + (tx - ty) * STEP_X, ORIGIN_Y + (tx + ty) * STEP_Y
end

--- Picture pixel -> tile position (the inverse).
function P.to_tile(px, py)
    local d = (px - ORIGIN_X) / STEP_X
    local s = (py - ORIGIN_Y) / STEP_Y
    return (s + d) / 2, (s - d) / 2
end

--- The texture name of the picture tile at row r (0 .. 10), column c (0 .. 7).
function P.tile_name(r, c)
    if r < P.UW_ROWS then return ('UI_WORLDMAPUW%d%d.TGA'):format(r, c) end
    return ('UI_WORLDMAPX%d%d.TGA'):format(r - P.UW_ROWS, c)
end

--- The picture tiles a view of `w` x `h` layout units at `zoom` (layout units per picture pixel), centred on picture pixel
--- (cx, cy), touches: a list of {r, c} sorted by row then column, with the view's top left in picture pixels in the second result.
function P.visible_tiles(cx, cy, w, h, zoom)
    local half_w, half_h = w / 2 / zoom, h / 2 / zoom
    local left, top = cx - half_w, cy - half_h
    local c0 = math.max(0, math.floor(left / P.TILE_PX))
    local c1 = math.min(P.COLS - 1, math.floor((cx + half_w) / P.TILE_PX))
    local r0 = math.max(0, math.floor(top / P.TILE_PX))
    local r1 = math.min(P.ROWS - 1, math.floor((cy + half_h) / P.TILE_PX))
    local out = {}
    for r = r0, r1 do
        for c = c0, c1 do out[#out + 1] = {r = r, c = c} end
    end
    return out, left, top
end

--- The zoom levels, layout units per picture pixel: level 1 is the widest.
P.ZOOMS = {0.4, 0.7, 1, 1.5, 2.2, 3.2}

function P.zoom_of(level)
    level = math.max(1, math.min(#P.ZOOMS, math.floor((tonumber(level) or 3) + 0.5)))
    return P.ZOOMS[level], level
end

--- The horizontal strips that clip a circle of diameter `d` (an element cannot be cut round, so the circle is stacked from
--- thin full-clipped rows): a list of {y, h, x, w} in layout units from the circle's top left corner.
function P.circle_strips(d, step)
    step = step or 4
    local r = d / 2
    local out = {}
    local y = 0
    while y < d do
        local h = math.min(step, d - y)
        local mid = y + h / 2 - r
        local half = math.sqrt(math.max(0, r * r - mid * mid))
        local x = r - half
        out[#out + 1] = {y = y, h = h, x = x, w = half * 2}
        y = y + h
    end
    return out
end

return P
