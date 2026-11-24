-- Balance editor, the logic without the game: values, the patch file the game reads, and shareable "balance patches" (export, import).
-- A balance patch is plain data: {format = 'sacred-balance-patch', version = 1, name, note, changes = {{id = 'diff.hp.gold', value = 1.5}, ...}}.
-- Nothing in it is ever run; an import takes only the ids of the catalog and numbers, checks each against its range and shows the result
-- before anything changes.
local catalog = require('catalog')
local defaults = require('defaults')
local M = {}

M.FORMAT = 'sacred-balance-patch'
M.VERSION = 1
M.MAX_CHANGES = 1000          -- an import with more changes than this is refused (the catalog has fewer fields)
M.MAX_TEXT = 200000           -- bytes of an import's text

local function round_to(v, digits)
    local m = 10 ^ digits
    return math.floor(v * m + 0.5) / m
end

-- Decimals worth showing for a step: 1 -> 0, 0.05 -> 2, 0.5 -> 1.
local function decimals(step)
    if step >= 1 then return 0 end
    local d = 0
    local s = step
    while s < 1 - 1e-9 and d < 4 do s = s * 10; d = d + 1 end
    return d
end

function M.default(id) return defaults[id] end

-- The vanilla value rounded to what the screen shows (the file holds float32 numbers such as 0.649999976).
function M.vanilla(f)
    local v = defaults[f.id]
    if v == nil then return nil end
    if f.kind == 'i' then return v end
    return round_to(v, math.max(decimals(f.step), 3))
end

-- Readable text of a value of field f.
function M.format(f, v)
    if v == nil then return '' end
    if f.kind == 'i' then return ('%d'):format(v) end
    local d = math.max(decimals(f.step), 2)
    local s = ('%.' .. d .. 'f'):format(v)
    s = s:gsub('(%..-)0+$', '%1'):gsub('%.$', '')
    return s
end

function M.same(f, a, b)
    if a == nil or b == nil then return a == b end
    if f.kind == 'i' then return a == b end
    return math.abs(a - b) <= 1e-5 * math.max(1, math.abs(a), math.abs(b))
end

-- Is `v` a number this field can hold: returns the value cleaned up (integers whole), or nil and why.
function M.check(f, v)
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil, 'not a number' end
    if f.kind == 'i' then
        if v ~= math.floor(v) then return nil, 'must be a whole number' end
    else
        v = round_to(v, 6)
    end
    if v < f.min or v > f.max then
        return nil, ('out of range (%s to %s)'):format(M.format(f, f.min), M.format(f, f.max))
    end
    return v
end

-- Forces v into the field's range (for sliders and buttons): integers whole.
function M.clamp(f, v)
    if f.kind == 'i' then v = math.floor(v + 0.5) else v = round_to(v, 6) end
    if v < f.min then v = f.min elseif v > f.max then v = f.max end
    return v
end

-- edits: id -> value. Drops the entries that equal the game's value; returns how many are left.
function M.prune(edits)
    local n = 0
    for id, v in pairs(edits) do
        local f = catalog.by_id[id]
        if not f or M.same(f, v, M.vanilla(f)) then edits[id] = nil else n = n + 1 end
    end
    return n
end

-- The changed fields in catalog order: {{field, value}, ...}
function M.changed(edits)
    local list = {}
    for _, f in ipairs(catalog.fields) do
        local v = edits[f.id]
        if v ~= nil and not M.same(f, v, M.vanilla(f)) then list[#list + 1] = {f, v} end
    end
    return list
end

local function word_text(f, v)
    if f.kind == 'i' then return ('%d'):format(v) end
    return ('{f = %.9g}'):format(v)
end

-- The text of the patch file Sacred Gear reads (kind 'words': edits to the 32 bit words of balance.bin) and how many values it sets.
function M.build_patch(edits)
    local list = M.changed(edits)
    table.sort(list, function(a, b) return a[1].off < b[1].off end)
    local out = {
        '-- Written by the Balance editor mod: the values you changed, nothing else. Do not edit by hand; use the editor (or delete this',
        '-- mod to get the game\'s own balance.bin back).',
        ('-- changes: %d'):format(#list),
        'return {kind = \'words\', size = ' .. catalog.FILE_SIZE .. ', ops = {',
    }
    local i = 1
    while i <= #list do
        local first = catalog.word(list[i][1])
        local run, j = {word_text(list[i][1], list[i][2])}, i
        while list[j + 1] and catalog.word(list[j + 1][1]) == first + #run do
            j = j + 1
            run[#run + 1] = word_text(list[j][1], list[j][2])
        end
        out[#out + 1] = ('    {%d, {%s}},'):format(first, table.concat(run, ', '))
        i = j + 1
    end
    out[#out + 1] = '}}'
    return table.concat(out, '\n') .. '\n', #list
end

-- A balance patch (a table, to be written as JSON) of the changed values. meta: {name, note}.
function M.export(edits, meta)
    meta = meta or {}
    local changes = {}
    for _, e in ipairs(M.changed(edits)) do
        local f, v = e[1], e[2]
        changes[#changes + 1] = {id = f.id, value = v, label = f.group .. ': ' .. f.label, was = M.vanilla(f)}
    end
    return {format = M.FORMAT, version = M.VERSION, game = 'Sacred Gold', name = tostring(meta.name or ''):sub(1, 60),
        note = tostring(meta.note or ''):sub(1, 400), changes = changes}
end

-- Reads a decoded balance patch. Returns a report:
--   ok       the file is a balance patch this version understands (false: `error` says why)
--   rows     {{id, label, group, tab, current, new, vanilla, status = 'change' | 'same' | 'rejected' | 'unknown', why}, ...}
--   accepted id -> value of the rows with status 'change' or 'same' (what an import sets)
--   counts   {change, same, rejected, unknown}
-- `edits` is what is set now (to show current values and to find rows that change nothing).
function M.read_import(data, edits)
    local report = {ok = false, rows = {}, accepted = {}, counts = {change = 0, same = 0, rejected = 0, unknown = 0}}
    if type(data) ~= 'table' then report.error = 'not a balance patch'; return report end
    if data.format ~= M.FORMAT then report.error = 'not a balance patch (format is not ' .. M.FORMAT .. ')'; return report end
    if type(data.version) ~= 'number' or data.version > M.VERSION or data.version < 1 then
        report.error = 'a newer balance patch version than this editor knows'; return report
    end
    if type(data.changes) ~= 'table' then report.error = 'the patch has no list of changes'; return report end
    if #data.changes > M.MAX_CHANGES then report.error = 'too many changes'; return report end
    report.ok = true
    report.name = type(data.name) == 'string' and data.name:sub(1, 60) or ''
    report.note = type(data.note) == 'string' and data.note:sub(1, 400) or ''
    local seen = {}
    for _, c in ipairs(data.changes) do
        local row = {status = 'rejected'}
        if type(c) ~= 'table' or type(c.id) ~= 'string' then
            row.id, row.label, row.why = '?', '(an entry without an id)', 'not an entry'
        else
            local id = c.id:sub(1, 60)
            local f = catalog.by_id[id]
            row.id = id
            if not f then
                row.label, row.status, row.why = id, 'unknown', 'this editor has no such value'
            else
                row.label, row.group, row.tab = f.label, f.group, f.tab
                row.vanilla = M.vanilla(f)
                local cur = edits[id]
                row.current = cur ~= nil and cur or row.vanilla
                if seen[id] then
                    row.why = 'listed twice, the later one is ignored'
                else
                    local v, why = M.check(f, c.value)
                    if v == nil then
                        row.why = why
                    else
                        seen[id] = true
                        row.new = v
                        row.status = M.same(f, v, row.current) and 'same' or 'change'
                        report.accepted[id] = v
                    end
                end
            end
        end
        report.counts[row.status] = report.counts[row.status] + 1
        report.rows[#report.rows + 1] = row
    end
    return report
end

-- Applies an accepted import to `edits`: replaces the values of the rows that will change. Returns the number of changes.
function M.apply_import(edits, report)
    local n = 0
    for id, v in pairs(report.accepted) do
        local f = catalog.by_id[id]
        if f and not M.same(f, edits[id] ~= nil and edits[id] or M.vanilla(f), v) then n = n + 1 end
        edits[id] = v
    end
    M.prune(edits)
    return n
end

return M
