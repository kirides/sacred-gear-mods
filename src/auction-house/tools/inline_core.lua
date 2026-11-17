-- Copies core.lua into the C# GameServer's auction_house.lua (SacredEngineRemake Sacred.GameServer/scripts-examples): the server's
-- Lua sandbox has no require, so the market's code is inlined between the "-- >>> core.lua" and "-- <<< core.lua" lines.
--
--   luajit tools/inline_core.lua core.lua <path to auction_house.lua>        (from src/auction-house)
--
-- The block's first line carries the FNV-1a hash of the inlined code (carriage returns removed) so the server's tests can tell
-- that nobody edited it there (ScriptTests: AuctionCoreBlockIsUnedited). Plain Lua 5.1 / LuaJIT.
local core_path, target_path = arg[1], arg[2]
if not core_path or not target_path then
    io.stderr:write('usage: luajit tools/inline_core.lua core.lua <auction_house.lua>\n')
    os.exit(2)
end

local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return s
end

local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        local b = s:byte(i)
        -- h = (h xor b) * 16777619 mod 2^32, without bit operations (16777619 = 2^24 + 403)
        local x, bit = 0, 1
        local hh, bb = h, b
        for _ = 1, 32 do
            local p, q = hh % 2, bb % 2
            if p ~= q then x = x + bit end
            hh, bb, bit = (hh - p) / 2, (bb - q) / 2, bit * 2
        end
        h = ((x % 256) * 16777216 + x * 403) % 4294967296
    end
    return string.format('%08x', h)
end

local core = read(core_path):gsub('\r', '')
if not core:find('\nreturn M%s*$') then error('core.lua must end with "return M"') end
local body = 'local core = (function()\n' .. core:gsub('%s*$', '') .. '\nend)()\n'
local target = read(target_path)
local crlf = target:find('\r\n') ~= nil
target = target:gsub('\r', '')
local start = target:find('\n%-%- >>> core%.lua[^\n]*\n')
local stop = target:find('\n%-%- <<< core%.lua')
if not start or not stop then error('no "-- >>> core.lua" ... "-- <<< core.lua" block in ' .. target_path) end
local header_end = target:find('\n', start + 1)
local second_end = target:find('\n', header_end + 1)       -- the "Regenerate:" line stays
local head = '\n-- >>> core.lua: generated from sacred-gear-mods src/auction-house/core.lua, do not edit here. fnv1a ' .. fnv1a(body) .. '\n'
local out = target:sub(1, start - 1) .. head .. target:sub(header_end + 1, second_end) .. body .. target:sub(stop + 1)
if crlf then out = out:gsub('\n', '\r\n') end
local f = assert(io.open(target_path, 'wb'))
f:write(out)
f:close()
print(('inlined %d lines of core.lua into %s (fnv1a %s)'):format(select(2, body:gsub('\n', '')), target_path, fnv1a(body)))
