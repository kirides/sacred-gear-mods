-- Writes src/balance-editor/defaults.lua: the value of every cataloged field in a vanilla bin\balance.bin.
--   luajit tools/balance_defaults.lua "<game>\bin\balance.bin" > src/balance-editor/defaults.lua
-- (run from the repository root). Only a Sacred Gold file of the catalog's size is accepted.
package.path = 'src/balance-editor/?.lua;' .. package.path
local ffi = require('ffi')
local catalog = require('catalog')
local f = assert(io.open(arg[1], 'rb'))
local data = f:read('*a')
f:close()
assert(#data == catalog.FILE_SIZE, 'not a Sacred Gold balance.bin (size ' .. #data .. ')')
local buf = ffi.new('uint8_t[?]', #data)
ffi.copy(buf, data, #data)
local function word(at) return ffi.cast('int32_t*', buf + at)[0] end
local function float(at) return ffi.cast('float*', buf + at)[0] end
io.write('-- Vanilla values of balance.bin (Sacred Gold), made by tools/balance_defaults.lua. Do not edit.\nreturn {\n')
for _, fld in ipairs(catalog.fields) do
    local at = fld.off + 4
    local v = fld.kind == 'i' and word(at) or float(at)
    io.write(('    [%q] = %s,\n'):format(fld.id, fld.kind == 'i' and tostring(v) or ('%.9g'):format(v)))
end
io.write('}\n')
