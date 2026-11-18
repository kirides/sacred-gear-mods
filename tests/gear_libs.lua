-- The libraries Sacred Gear ships in SacredGear.dll (gear.fmt, gear.store, gear.toast, gear.lookup) for the tests outside
-- the game: they are read from a sacred-bild checkout (gear/lua/<name>.lua) and run against the test's fake `gear`, as the
-- kernel runs them in a mod's environment. The checkout is $SACRED_BILD, else ../sacred-bild next to this repository.
--     local libs = dofile('tests/gear_libs.lua')
--     libs.install(gear, {'fmt', 'store'})
local M = {}

function M.root()
    return os.getenv('SACRED_BILD') or '../sacred-bild'
end

function M.load(gear, name)
    local path = M.root() .. '/gear/lua/' .. name .. '.lua'
    local chunk, err = loadfile(path)
    if not chunk then error('gear library ' .. name .. ' not found (' .. tostring(err) .. '); set SACRED_BILD to a sacred-bild checkout', 2) end
    setfenv(chunk, setmetatable({gear = gear}, {__index = _G}))
    return chunk()
end

function M.install(gear, names)
    for _, name in ipairs(names) do gear[name] = M.load(gear, name) end
end

return M
