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

--- The render's tiles (ui/megamap/s<scale> (in tiles.gpak)/<row>_<col>.jpg: the whole world drawn offline, 256 px per tile, pixel (u, v) is map pixel
--- (u / scale, v / scale)): the resolution that suits a zoom (layout units per map pixel), and a tile's path.
function P.render_scale(zoom)
    if zoom <= 1 then return 1 elseif zoom <= 2.2 then return 2 end
    return 4
end

function P.render_tile(scale, r, c)
    return ('megamap/s%d/%03d_%03d.jpg'):format(scale, r, c)
end

--- The same file as a path in the mod's folder (for gear.ui.texture.load); `render_tile` is relative to the document in ui/.
function P.render_tile_file(scale, r, c)
    return 'ui/' .. P.render_tile(scale, r, c)
end

--- The picture tiles a view of `w` x `h` layout units at `zoom` (layout units per picture pixel), centred on picture pixel
--- (cx, cy), touches: a list of {r, c} sorted by row then column, with the view's top left in picture pixels in the second result.
--- `scale` (default 1) is the render's resolution: tiles of P.TILE_PX / scale map pixels, 8 * scale columns, 11 * scale rows.
function P.visible_tiles(cx, cy, w, h, zoom, scale)
    scale = scale or 1
    local tile, cols, rows = P.TILE_PX / scale, P.COLS * scale, P.ROWS * scale
    local half_w, half_h = w / 2 / zoom, h / 2 / zoom
    local left, top = cx - half_w, cy - half_h
    local c0 = math.max(0, math.floor(left / tile))
    local c1 = math.min(cols - 1, math.floor((cx + half_w) / tile))
    local r0 = math.max(0, math.floor(top / tile))
    local r1 = math.min(rows - 1, math.floor((cy + half_h) / tile))
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
