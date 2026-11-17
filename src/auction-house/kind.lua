-- The kind of game, for the market: where it may live. Closed Net when the engine says so (gear.mp.mode, which reads closed whenever
-- nothing proves another kind: default-deny) or when the game server itself said so (an `info` with closed = true sets server_closed),
-- whatever the engine's flags say. In a network game of an engine that cannot tell (no gear.mp.mode) the kind is unknown and reads
-- closed too. In Closed Net the host's market and a market in this game never run: only the game server's market, or none (closed).
local M = {server_closed = false}

function M.mode()
    local mp = gear.mp
    if mp and mp.mode then return mp.mode() or 'single' end
    if mp and mp.active and mp.active() then return 'closed' end
    return 'single'
end
function M.closed() return M.server_closed or M.mode() == 'closed' end
function M.reset() M.server_closed = false end

return M
