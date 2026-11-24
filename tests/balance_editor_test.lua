-- Logic test of the balance editor outside the game (src/balance-editor/core.lua, catalog.lua). From the repository root:
--     luajit tests/balance_editor_test.lua [path to a vanilla bin\balance.bin]
-- With the path it also applies the generated patch the way Sacred Gear does and checks the bytes.
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

package.path = 'src/balance-editor/?.lua;' .. package.path
local catalog = require('catalog')
local core = require('core')
local defaults = require('defaults')

-- catalog: unique ids and positions, every field has a vanilla value, its range holds it, offsets are word aligned and inside the block
local at = {}
for _, f in ipairs(catalog.fields) do
    ok(defaults[f.id] ~= nil, 'default of ' .. f.id)
    local d = core.vanilla(f)
    ok(d and d >= f.min - 1e-9 and d <= f.max + 1e-9, 'range holds the vanilla value of ' .. f.id .. ' ' .. tostring(d))
    ok(f.off % 4 == 0 and f.off >= 0 and f.off + 4 <= 0x1320, 'offset of ' .. f.id)
    ok(not at[f.off], 'two fields at ' .. string.format('%x', f.off) .. ': ' .. f.id .. ' and ' .. tostring(at[f.off] and at[f.off].id))
    at[f.off] = f
    ok(f.step > 0 and f.max > f.min, 'step of ' .. f.id)
end
ok(#catalog.fields > 200, 'many fields')
for _, t in ipairs(catalog.TABS) do ok(catalog.groups[t.id] and #catalog.groups[t.id] > 0, 'tab has groups ' .. t.id) end

-- vanilla edits change nothing
local edits = {}
for _, f in ipairs(catalog.fields) do edits[f.id] = core.vanilla(f) end
ok(core.prune(edits) == 0, 'vanilla values are pruned')
local text, n = core.build_patch({})
ok(n == 0 and text:find('ops = {\n}}', 1, true), 'empty patch')

-- a patch: adjacent words merge into one run, floats are {f = x}, order ascending
edits = {['diff.hp.silver'] = 2, ['diff.hp.gold'] = 3.5, ['diff.minlvl.bronze'] = 25, ['loot.rolls'] = 3}
text, n = core.build_patch(edits)
ok(n == 4, 'four changes')
local chunk = assert(loadstring(text))
local patch = chunk()
ok(patch.kind == 'words' and patch.size == 24328, 'patch header')
local words = {}
for _, op in ipairs(patch.ops) do for k, v in ipairs(op[2]) do words[op[1] + k - 1] = v end end
local function w(id) return words[catalog.word(catalog.by_id[id])] end
ok(type(w('diff.hp.silver')) == 'table' and w('diff.hp.silver').f == 2, 'silver hp')
ok(w('diff.hp.gold').f == 3.5 and w('loot.rolls') == 3 and w('diff.minlvl.bronze') == 25, 'other values')
local runs = 0
for _ in ipairs(patch.ops) do runs = runs + 1 end
ok(runs == 3, 'silver and gold hp share a run: ' .. runs)

-- export, import
local exp = core.export(edits, {name = 'Hard mode', note = 'x'})
ok(exp.format == core.FORMAT and #exp.changes == 4 and exp.name == 'Hard mode', 'export')
local rep = core.read_import(exp, {})
ok(rep.ok and rep.counts.change == 4 and rep.counts.rejected == 0, 'import of an export')
local applied = {}
ok(core.apply_import(applied, rep) == 4, 'applied four')
ok(applied['diff.hp.silver'] == 2, 'applied value')
rep = core.read_import(exp, applied)
ok(rep.counts.same == 4 and rep.counts.change == 0, 'importing again changes nothing')

-- hostile imports: no code, no unknown ids, no values out of range, no NaN
ok(not core.read_import('return os.execute("x")', {}).ok, 'a string is no patch')
ok(not core.read_import({format = 'other', version = 1, changes = {}}, {}).ok, 'wrong format')
ok(not core.read_import({format = core.FORMAT, version = 99, changes = {}}, {}).ok, 'newer version')
rep = core.read_import({format = core.FORMAT, version = 1, changes = {
    {id = 'diff.hp.gold', value = 1e9}, {id = 'no.such', value = 1}, {id = 'loot.rolls', value = 1.5}, {id = 'diff.hp.silver', value = 0 / 0},
    {id = 'loot.rolls', value = 2}, {id = 'loot.rolls', value = 4}, 'junk', {id = 5}, {id = 'diff.hp.silver', value = 'high'}}}, {})
ok(rep.ok and rep.counts.change == 1 and rep.counts.rejected == 7 and rep.counts.unknown == 1, 'validation counts ' .. rep.counts.change .. '/' .. rep.counts.rejected .. '/' .. rep.counts.unknown)
ok(rep.accepted['loot.rolls'] == 2 and rep.accepted['diff.hp.gold'] == nil, 'only valid values are accepted')

-- optional: apply to a real file the way Gear's word patch does
local path = arg and arg[1]
if path then
    local f = assert(io.open(path, 'rb')); local data = f:read('*a'); f:close()
    ok(#data == patch.size, 'file size')
    local ffi = require('ffi')
    local buf = ffi.new('uint8_t[?]', #data); ffi.copy(buf, data, #data)
    local u = ffi.cast('int32_t*', buf); local fl = ffi.cast('float*', buf)
    for _, op in ipairs(patch.ops) do
        for k, v in ipairs(op[2]) do
            local i = op[1] + k - 1
            if type(v) == 'table' then fl[i] = v.f else u[i] = v end
        end
    end
    for id, v in pairs(edits) do
        local fld = catalog.by_id[id]
        local i = catalog.word(fld)
        local got = fld.kind == 'i' and u[i] or fl[i]
        ok(math.abs(got - v) < 1e-6, 'bytes of ' .. id)
    end
    local before = ffi.new('uint8_t[?]', #data); ffi.copy(before, data, #data)
    local changed = 0
    for i = 0, #data - 1 do if before[i] ~= buf[i] then changed = changed + 1 end end
    ok(changed > 0 and changed <= 16, 'only a few bytes differ: ' .. changed)
    -- every cataloged field reads its vanilla value from the file (offsets, kinds)
    local u0 = ffi.cast('int32_t*', before); local f0 = ffi.cast('float*', before)
    for _, fld in ipairs(catalog.fields) do
        local i = catalog.word(fld)
        local got = fld.kind == 'i' and u0[i] or f0[i]
        ok(math.abs(got - defaults[fld.id]) < 1e-5 * math.max(1, math.abs(got)), 'vanilla ' .. fld.id)
    end
end

print(failures == 0 and 'balance editor: all checks passed' or ('balance editor: ' .. failures .. ' FAILED'))
os.exit(failures == 0 and 0 or 1)
