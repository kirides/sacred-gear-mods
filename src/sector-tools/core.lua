-- Sector tools, the logic without the game: the sector grid (cells of 64 tiles), the ground projection, range compaction of sector
-- lists and the Lua snippet for a server's world_events.lua areas. Plain Lua 5.1 / LuaJIT, no gear.* (tests/core_test.lua).
local M = {}

M.TILE = 53.66563034057617          -- world units per tile
M.SECTOR = 64 * M.TILE              -- world units per sector cell side (64 x 64 tiles)

-- The sector grid cell of a world position (the game's 128 x 128 grid; ids of the sector table are NOT cell numbers).
function M.cell_of(x, y)
    return math.floor(x / M.SECTOR), math.floor(y / M.SECTOR)
end

-- The world position of the lower corner of a cell.
function M.cell_origin(cx, cy)
    return cx * M.SECTOR, cy * M.SECTOR
end

-- Ground to screen: the game draws the world isometrically, a tile is 96 x 48 pixels of the 1024 x 768 layout: from the hero's
-- position (its screen anchor ax, ay) a point dx, dy world units away lies at
--   x = ax + (dx - dy) * 48 / TILE,  y = ay + (dx + dy) * 24 / TILE.
-- An approximation: Gear has no world-to-screen call, so the anchor is a setting.
function M.project(dx, dy, ax, ay)
    return ax + (dx - dy) * 48 / M.TILE, ay + (dx + dy) * 24 / M.TILE
end

-- The other way: a screen offset to the world offset.
function M.unproject(sx, sy)
    local u, v = sx * M.TILE / 48, sy * M.TILE / 24      -- dx - dy, dx + dy
    return (u + v) / 2, (v - u) / 2
end

-- A sorted list of sector ids, de-duplicated.
function M.sorted(set)
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return list
end

-- Runs of three or more consecutive ids become { first, last }, the rest stay numbers: 2909, {2911, 2913}.
function M.compact(ids)
    local out, i = {}, 1
    while i <= #ids do
        local j = i
        while ids[j + 1] == ids[j] + 1 do j = j + 1 end
        if j - i >= 2 then
            out[#out + 1] = {ids[i], ids[j]}
        else
            for k = i, j do out[#out + 1] = ids[k] end
        end
        i = j + 1
    end
    return out
end

-- "2909, {2911, 2913}" for a compact list.
function M.compact_text(list)
    local parts = {}
    for _, v in ipairs(list) do
        parts[#parts + 1] = type(v) == 'table' and ('{%d, %d}'):format(v[1], v[2]) or ('%d'):format(v)
    end
    return table.concat(parts, ', ')
end

-- A string literal for Lua source: no control characters, backslash and quote escaped.
function M.lua_string(text)
    text = tostring(text or ''):gsub('%c', ' '):gsub('\\', '\\\\'):gsub('"', '\\"')
    return '"' .. text .. '"'
end

-- An area id from a name: lower case, letters and digits, the rest an underscore ("Silver Creek" -> silver_creek).
function M.slug(name)
    local id = tostring(name or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if id == '' then id = 'area' end
    if id:match('^%d') then id = 'area_' .. id end
    return id
end

local function whole(v) return math.floor(v + 0.5) end

-- The numbers of a list, ascending and without repeats (a set of ids is turned into a list with M.sorted first).
function M.sorted_numbers(v)
    local out = {}
    if type(v) ~= 'table' then return out end
    for _, x in ipairs(v) do
        local n = tonumber(x)
        if n then out[#out + 1] = math.floor(n) end
    end
    table.sort(out)
    local unique = {}
    for _, n in ipairs(out) do if unique[#unique] ~= n then unique[#unique + 1] = n end end
    return unique
end

-- What a hero's region looks like in the panel and in a config: `r` is a gear.data.regions record ({id, name}) or nil.
function M.region_text(r, code)
    if type(r) ~= 'table' or not r.id then return 'no region' end
    local name = tostring(r.name or ''):gsub('%c', ' ')
    if name == '' then name = 'region ' .. tostring(r.id) end
    return ('%s (id %d%s)'):format(name, r.id, code and (', code ' .. tostring(code)) or '')
end

-- The line to put into an area or an event: `regions = { 4 },  -- Desert` (nil without a region).
function M.region_line(r)
    if type(r) ~= 'table' or not r.id then return nil end
    local name = tostring(r.name or ''):gsub('%c', ' '):gsub('%-%-', '- -')
    return ('regions = { %d },%s'):format(r.id, name ~= '' and ('  -- ' .. name) or '')
end

-- The line for world_events.lua's `areas` table (the same text the server's "!area show" prints):
--   silver_creek = { name = "Silver Creek", sectors = {2909, {2911, 2913}}, circle = { x = 1, y = 2, r = 3 } },
-- area = { id, name, ids = { [sector] = true }, circle = { x, y, r } | nil, near = n | nil }
function M.snippet(area)
    local parts = {'name = ' .. M.lua_string(area.name or area.id)}
    local ids = M.sorted(area.ids or {})
    if #ids > 0 then parts[#parts + 1] = 'sectors = {' .. M.compact_text(M.compact(ids)) .. '}' end
    if area.near and area.near > 0 then parts[#parts + 1] = 'near = ' .. whole(area.near) end
    local regions = M.sorted_numbers(area.regions)
    if #regions > 0 then parts[#parts + 1] = 'regions = {' .. table.concat(regions, ', ') .. '}' end
    if area.circle then
        parts[#parts + 1] = ('circle = { x = %d, y = %d, r = %d }'):format(whole(area.circle.x), whole(area.circle.y), whole(area.circle.r))
    end
    return (area.id or M.slug(area.name)) .. ' = { ' .. table.concat(parts, ', ') .. ' },'
end

-- Where a boundary line of the grid lies: the world coordinate of the nearest cell edge on one axis at or beyond `v`, and the
-- edges within `reach` world units of it (a list of edge indexes k: the edge is at k * SECTOR).
function M.edges_near(v, reach)
    local first = math.ceil((v - reach) / M.SECTOR)
    local last = math.floor((v + reach) / M.SECTOR)
    local list = {}
    for k = first, last do list[#list + 1] = k end
    return list
end

return M
