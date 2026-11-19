-- Custom classes: art copies and chains (stage 3). Until then: nothing.
local M = {}
local ids = {}

function M.load()
    ids = {}
    return {}
end

-- {[ability id] = true}: the ids the art files define (copies and chains)
function M.ids() return ids end

return M
