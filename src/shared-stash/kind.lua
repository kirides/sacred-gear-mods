-- The kind of game, for the stash: where it lives. Closed Net when the engine says so (gear.mp.mode) or when the game server
-- itself said so over the channel (remote.lua sets server_closed after an `info` with closed = true), whatever the engine's flags
-- say. Nothing else decides, so a server that keeps the stash can never be bypassed by a local one.
local M = {server_closed = false}

function M.mode() return (gear.mp and gear.mp.mode and gear.mp.mode()) or 'single' end
function M.closed() return M.server_closed or M.mode() == 'closed' end
function M.reset() M.server_closed = false end

return M
