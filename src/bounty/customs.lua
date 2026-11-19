-- The player's own bounties (single player): definitions kept in custom.json in the mod's folder, shared by all heroes.
-- A definition says what to kill, for how long, what it pays and optionally when it starts by itself (see localboard.clean_def).
-- The file can be edited by hand as well (Reload in the editor); a bad entry is dropped, the rest is kept.

local board = require('localboard')

local M = {}
local FILE = 'custom.json'

M.defs = {}

function M.load()
    M.defs = {}
    local text = gear.read(FILE)
    local data = text and gear.json.decode(text)
    for _, d in ipairs(type(data) == 'table' and type(data.defs) == 'table' and data.defs or {}) do
        local clean = board.clean_def(d)
        if clean then M.defs[#M.defs + 1] = clean end
    end
end

function M.save()
    local ok, err = gear.save(FILE, gear.json.encode({v = 1, defs = M.defs}))
    if not ok then print('bounty: cannot save ' .. FILE .. ': ' .. tostring(err)) end
    return ok
end

function M.new_id()
    local used = {}
    for _, d in ipairs(M.defs) do used[d.id] = true end
    local n = #M.defs + 1
    while used['c' .. n] do n = n + 1 end
    return 'c' .. n
end

function M.find(id)
    for i, d in ipairs(M.defs) do if d.id == id then return d, i end end
end

-- Adds or replaces (by id) a definition; returns the cleaned one.
function M.put(def)
    local clean = board.clean_def(def)
    if not clean then return nil end
    local old, i = M.find(clean.id)
    if old then M.defs[i] = clean else M.defs[#M.defs + 1] = clean end
    M.save()
    return clean
end

function M.remove(id)
    local _, i = M.find(id)
    if i then table.remove(M.defs, i) M.save() end
end

-- A sentence about what a definition asks for and pays, for the list.
function M.summary(d)
    local what = (#d.names > 0 or #(d.types or {}) > 0) and board.target_text(d.names, d.types) or 'any monster'
    local parts = {}
    if d.gold > 0 then parts[#parts + 1] = d.gold .. ' gold' end
    if d.item then
        local it = d.item
        parts[#parts + 1] = it.mode == 'specific' and (#it.types == 1 and board.item_label(it.types[1]) or (#it.types .. ' chosen items'))
            or it.mode == 'class' and 'class loot' or 'random loot'
    end
    return ('%d x %s -> %s'):format(d.target, what, #parts > 0 and table.concat(parts, ' + ') or 'glory')
end

return M
