-- World events: the region boss pill, the logic without the game. The game counts kills in the region the hero stands in (gear.data.regions:
-- `kills_needed` / `kills_left`; when `kills_left` reaches 0 the Region Boss comes). This turns such a record into a view for the stack of
-- pills (the same shape as core.lua's views, kind 'region'). The numbers are the game's own, so a custom "kills needed" set by the
-- region-counter mod (which writes into the same records) shows here without any link between the two mods.
-- Plain Lua 5.1 / LuaJIT, no gear.* (tested in tests/regions_test.lua).
local core = require('core')

local M = {}

-- Is a record worth showing: the game set it up (kills needed above 0) and the numbers make sense.
function M.valid(r)
    if type(r) ~= 'table' then return false end
    local needed, left = tonumber(r.kills_needed), tonumber(r.kills_left)
    return needed ~= nil and left ~= nil and needed >= 1 and needed <= 1000000 and left >= 0 and left <= 1000000
end

function M.name_of(r)
    local name = core.clean(r.name or '', 40)
    if name:match('%S') then return name end
    return 'Region ' .. tostring(r.id or r.index or '?')
end

-- A view of region record `r` for the pill; `others` (optional) are the other records of the table, listed in the tooltip when they have progress.
function M.view(r, others)
    if not M.valid(r) then return nil end
    local needed, left = math.floor(r.kills_needed), math.floor(r.kills_left)
    local done = math.max(0, math.min(needed, needed - left))
    local pct = core.percent(done, needed)
    local name = M.name_of(r)
    local ready = left <= 0
    local count_text = core.group(done) .. ' / ' .. core.group(needed)
    local tip = {name, ready and 'The region boss is due' or ('%s kills (%d%%)'):format(count_text, pct)}
    if not ready then tip[#tip + 1] = core.group(left) .. ' kills until the region boss' end
    tip[#tip + 1] = "The game's own count: it starts over when you leave the region."
    local listed = {}
    for _, o in ipairs(others or {}) do
        if o ~= r and M.valid(o) and o.id ~= r.id and o.kills_left < o.kills_needed then
            listed[#listed + 1] = ('  %s: %s / %s'):format(M.name_of(o), core.group(o.kills_needed - o.kills_left), core.group(o.kills_needed))
        end
    end
    if #listed > 0 then
        tip[#tip + 1] = 'Other regions this session:'
        for i = 1, math.min(#listed, 6) do tip[#tip + 1] = listed[i] end
    end
    return {
        kind = 'region', title = name, text = '', count = done, target = needed, unit = 'kills', area = '', percent = pct,
        frac = core.clamp(done / needed, 0, 1), left = nil, time_frac = 0, time_text = '', count_text = count_text,
        line2 = ready and 'Boss time!' or (count_text .. ' kills'), alpha = 1, late = false, tip = tip, ready = ready,
        id = r.id,
    }
end

-- The pills for the region the hero stands in. `api` is gear.data.regions, `hero` the hero's creature; either may be nil.
-- Never throws: a game or a Gear without the table just gives nothing.
function M.collect(api, hero)
    if not (api and hero and api.of_creature) then return {} end
    local ok, r = pcall(api.of_creature, api, hero)
    if not ok or not M.valid(r) then return {} end
    local others = {}
    if api.count and api.get then
        local okc, n = pcall(api.count, api)
        for i = 1, okc and tonumber(n) and math.min(n - 1, 40) or 0 do
            local okg, rec = pcall(api.get, api, i)
            if okg and M.valid(rec) then others[#others + 1] = rec end
        end
    end
    local v = M.view(r, others)
    return v and {v} or {}
end

-- The order of the stack: events (as Model:views gives them) first, then the region pills by progress, most progress first.
function M.stack(event_views, region_views, cap)
    local out = {}
    for _, v in ipairs(event_views) do out[#out + 1] = v end
    local regions = {}
    for _, v in ipairs(region_views) do regions[#regions + 1] = v end
    table.sort(regions, function(a, b) return (a.frac or 0) > (b.frac or 0) end)
    for _, v in ipairs(regions) do out[#out + 1] = v end
    cap = cap or 4
    local more = 0
    if #out > cap then more = #out - cap; for i = #out, cap + 1, -1 do out[i] = nil end end
    return out, more
end

-- A sample for the layout editor.
M.SAMPLE = {id = 4, index = 4, name = 'Desert', kills_needed = 8500, kills_left = 5200}

return M
