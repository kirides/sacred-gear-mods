-- Bounty hooks for other mods (gear.emit): turns each new board (the server's push or the local one) into events by comparing it
-- with the board before. Plain Lua 5.1, no gear.* (tested in tests/bounty_hooks_test.lua).
--
--   bounty.started    a bounty is on the board (also: every open bounty when the first board of a session arrives, initial = true)
--   bounty.progress   its counter went up
--   bounty.completed  the target is reached
--   bounty.claimed    the reward was paid (single player: this mod pays it; network: the server does, same moment as completed)
--   bounty.failed     it left the board unfinished (time ran out, the player stopped it)
-- The payload is one table: {id, title, text, region, level, target, n, reward, custom, source = 'local'|'server', initial?}.
local M = {}

M.EVENTS = {
    {'bounty.started', 'A bounty is on the board (every open one when the first board of a session arrives, initial = true).'},
    {'bounty.progress', 'The counter of a bounty went up (n is the new count, previous the old one).'},
    {'bounty.completed', 'The target of a bounty is reached.'},
    {'bounty.claimed', 'The reward of a bounty was paid.'},
    {'bounty.failed', 'A bounty left the board unfinished (time ran out or it was stopped).'},
}
M.ARGS = 'id, title, text, region?, level?, target, n, previous? (progress), reward?, custom?, source = "local"|"server", initial? (started)'

local function payload(b, source)
    return {id = b.id, title = b.title, text = b.text, region = b.region, level = b.level, target = b.target,
        n = math.min(b.n or 0, b.target), reward = b.reward, custom = b.custom, source = source}
end

M.payload = payload

local function key(b) return b.id ~= nil and b.id or b.title end

-- Calls emit(name, payload) for what changed between `old` (a payload of bounties, or nil at the first board) and `new`.
-- opts.source: 'local' | 'server'; opts.claim_on_done: also emit bounty.claimed with completed (server boards).
function M.diff(old, new, emit, opts)
    opts = opts or {}
    local source = opts.source or 'local'
    local before, seen = {}, {}
    for _, b in ipairs(old and old.bounties or {}) do before[key(b)] = b end
    local function completed(p)
        emit('bounty.completed', p)
        if opts.claim_on_done then emit('bounty.claimed', p) end
    end
    for _, b in ipairs(new.bounties or {}) do
        local k = key(b)
        seen[k] = true
        local p = payload(b, source)
        local o = before[k]
        if not o then
            if not b.done then
                p.initial = (old == nil) or nil
                emit('bounty.started', p)
            elseif old then
                emit('bounty.started', p)
                completed(p)
            end
        else
            local on = math.min(o.n or 0, o.target)
            if p.n > on then
                local q = payload(b, source)
                q.previous = on
                emit('bounty.progress', q)
            end
            if b.done and not o.done then completed(p) end
        end
    end
    for _, o in ipairs(old and old.bounties or {}) do
        if not seen[key(o)] and not o.done then emit('bounty.failed', payload(o, source)) end
    end
end

return M
