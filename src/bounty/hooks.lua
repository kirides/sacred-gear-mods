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
        n = math.min(b.n or 0, b.target), reward = b.reward, custom = b.custom, period = b.period, source = source}
end

M.payload = payload

local function key(b) return b.id ~= nil and b.id or b.title end

-- Calls emit(name, payload) for what changed between `old` (a payload of bounties, or nil at the first board) and `new`.
-- opts.source: 'local' | 'server'; opts.claim_on_done: also emit bounty.claimed with completed (server boards);
-- opts.prefix: the event family ('bounty', or 'quest' for the daily / weekly quests, whose entries carry `period`).
function M.diff(old, new, emit, opts)
    opts = opts or {}
    local source = opts.source or 'local'
    local pre = opts.prefix or 'bounty'
    local before, seen = {}, {}
    for _, b in ipairs(old and old.bounties or {}) do before[key(b)] = b end
    local function completed(p)
        emit(pre .. '.completed', p)
        if opts.claim_on_done then emit(pre .. '.claimed', p) end
    end
    for _, b in ipairs(new.bounties or {}) do
        local k = key(b)
        seen[k] = true
        local p = payload(b, source)
        local o = before[k]
        if not o then
            if not b.done then
                p.initial = (old == nil) or nil
                emit(pre .. '.started', p)
            elseif old then
                emit(pre .. '.started', p)
                completed(p)
            end
        else
            local on = math.min(o.n or 0, o.target)
            if p.n > on then
                local q = payload(b, source)
                q.previous = on
                emit(pre .. '.progress', q)
            end
            if b.done and not o.done then completed(p) end
        end
    end
    for _, o in ipairs(old and old.bounties or {}) do
        if not seen[key(o)] and not o.done then emit(pre .. '.failed', payload(o, source)) end
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Daily and weekly quests (quests.lua): the same payload shape, other names
--   quest.started    a quest is up (a new day / week; every running one when the first state of a session arrives, initial = true)
--   quest.progress   its counter went up
--   quest.completed  its target is reached
--   quest.claimed    its reward was paid (a streak bonus too: bonus = true, id 'bonus:<period>:<n>')
--   quest.failed     the day / week ended before it was done
--   quest.streak     one more day / week in a row: {period, count, best, bonus?, source}
--   quest.streak_lost  the streak broke: {period, previous, source}
--   quest.set_completed  every quest of the day / week is done: {period, count, source}
-- The payload of the first five is the bounty one plus `period = 'daily' | 'weekly'`.
---------------------------------------------------------------------------------------------------------------------
M.QUEST_ARGS = 'id, period = "daily"|"weekly", title, text, target, n, previous? (progress), reward?, level?, source = "local"|"server", initial? (started), bonus? (claimed)'
M.QUEST_EVENTS = {
    {'quest.started', 'A daily or weekly quest is up (every running one when the first state of a session arrives, initial = true).'},
    {'quest.progress', 'The counter of a quest went up (n is the new count, previous the old one).'},
    {'quest.completed', 'The target of a quest is reached.'},
    {'quest.claimed', 'The reward of a quest, or a streak bonus (bonus = true), was paid.'},
    {'quest.failed', 'The day or week ended before the quest was done.'},
    {'quest.set_completed', 'Every quest of the day or week is done (period, count of completed days / weeks in a row).'},
    {'quest.streak', 'One more day or week in a row (period, count, best, bonus = true when this step pays a streak bonus).'},
    {'quest.streak_lost', 'A day or week was missed: the streak is back to zero (period, previous).'},
}
M.STREAK_ARGS = 'period = "daily"|"weekly", count, best, bonus?, previous? (streak_lost), source'

-- Compares the streaks of two quest payloads of a server ({streak = {daily = {count, best, next_in}, weekly = ...}}): emits
-- quest.streak when a count went up, quest.streak_lost when it fell, quest.set_completed when `today` turned true.
function M.diff_streak(old, new, emit, opts)
    opts = opts or {}
    local source = opts.source or 'server'
    if not old or not new or not old.streak or not new.streak then return end
    for _, period in ipairs({'daily', 'weekly'}) do
        local o, n = old.streak[period], new.streak[period]
        if o and n then
            if n.today and not o.today then emit('quest.set_completed', {period = period, count = n.count, source = source}) end
            if n.count > o.count then
                emit('quest.streak', {period = period, count = n.count, best = n.best or n.count, bonus = (n.next_in ~= nil and n.every ~= nil and n.next_in == n.every) or nil, source = source})
            elseif n.count < o.count then
                emit('quest.streak_lost', {period = period, previous = o.count, source = source})
            end
        end
    end
end

return M
