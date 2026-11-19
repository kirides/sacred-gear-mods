-- World event hooks for other mods (gear.emit): turns each state the bar receives (a server's push or the local mode's) into events
-- by comparing it with the states before. Plain Lua 5.1, no gear.* (tested in tests/events_test.lua).
--
--   worldevent.started    an event began (every running event when the first state of a session arrives, initial = true)
--   worldevent.progress   the realm's count went up
--   worldevent.completed  the goal was reached
--   worldevent.failed     the time ran out
--   worldevent.hook       a trigger of the event fired its actions (local mode, or a spawn wave the server asked for)
-- The payload is one table: {id (the event's number), title, text, unit, area, count, target, percent, here, source = 'local'|'server'}.
-- worldevent.hook adds {action = 'spawn'|'item'|'message'|'gold'|'boss', text?}.
--   worldevent.boss.spawned    a world boss appeared (a hook's `boss` action; a server's announcement; initial = true when a boss from the savegame came back)
--   worldevent.boss.defeated   it was defeated (gone = true: it left the world without dying as far as the mod can tell)
-- Their payload is {id (a string), name, event (the event's title), type?, type_name?, creature (object id, local only), health (maximum), damage, taken,
-- deflect, reflect, regen (the multipliers), reward (text), by? (the hero who defeated it, server), source}.
local M = {}

M.EVENTS = {
    {'worldevent.started', 'A world event began (every running one when the first state of a session arrives, initial = true).'},
    {'worldevent.progress', 'The count of a running event went up (count, target, percent, previous).'},
    {'worldevent.completed', 'The goal of an event was reached.'},
    {'worldevent.failed', 'The time of an event ran out before the goal.'},
    {'worldevent.hook', 'A trigger of an event fired its actions (action: spawn, item, message, gold or boss).'},
    {'worldevent.boss.spawned', "A world boss appeared (a boss action of an event, or a server's announcement).", 'id, name, event, type?, type_name?, creature?, health?, damage?, taken?, deflect?, reflect?, regen?, reward?, source = "local"|"server", initial?'},
    {'worldevent.boss.defeated', 'A world boss was defeated (gone = true: it left the world without dying as far as can be told).', 'id, name, event, type?, type_name?, creature?, health?, reward?, by?, gone?, source = "local"|"server"'},
}
M.ARGS = 'id, title, text, unit, area, count, target, percent, here, source = "local"|"server", previous? (progress), initial? (started), action? (hook)'

-- The payload of worldevent.boss.* for a boss record (what localgame.make_boss returns, or a server's boss record).
function M.boss_payload(rec, source, extra)
    local mods = rec.mods or {}
    local p = {id = rec.key, name = rec.name, event = rec.event or '', type = rec.type, type_name = rec.type_name, creature = rec.creature,
        health = rec.max_hp or rec.max, damage = mods.damage, taken = mods.taken, deflect = mods.deflect, reflect = mods.reflect, regen = mods.regen,
        reward = rec.reward_text, by = rec.by, source = source}
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

function M.payload(s, source)
    local percent = (s.target or 0) > 0 and math.min(100, math.floor((s.count or 0) * 100 / s.target)) or 0
    return {id = s.n, title = s.title, text = s.text, unit = s.unit, area = s.area, count = s.count, target = s.target,
        percent = percent, here = s.here, source = source}
end

local function key(s) return tostring(s.n) .. '|' .. tostring(s.title) end

-- Calls emit(name, payload) for what changed between the states `old` (nil before the first one) and `new` (lists of parsed states).
function M.diff(old, new, emit, source)
    source = source or 'server'
    local before, seen = {}, {}
    for _, s in ipairs(old or {}) do before[key(s)] = s end
    for _, s in ipairs(new or {}) do
        if s.st ~= 'idle' then
            local k = key(s)
            seen[k] = true
            local o = before[k]
            local p = M.payload(s, source)
            if not o then
                if s.st == 'active' then
                    p.initial = (old == nil) or nil
                    emit('worldevent.started', p)
                elseif old then
                    emit('worldevent.started', M.payload(s, source))
                    emit(s.st == 'won' and 'worldevent.completed' or 'worldevent.failed', p)
                end
            else
                if s.st == 'active' and (s.count or 0) > (o.count or 0) then
                    local q = M.payload(s, source)
                    q.previous = o.count
                    emit('worldevent.progress', q)
                end
                if o.st == 'active' and s.st == 'won' then emit('worldevent.completed', p)
                elseif o.st == 'active' and s.st == 'failed' then emit('worldevent.failed', p) end
            end
        end
    end
end

return M
