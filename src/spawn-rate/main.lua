-- Spawn rate: multiplies the creatures the game spawns (1x to 100x). Sacred Gear's `creature.created` event tells the mod about
-- every creature the engine's own code makes (sector fills, spawn tables, scripts); for each hostile one the mod makes rate - 1 more
-- of the same type next to it. Safeguards: the extras are made a few per frame from a queue (fewer while the frame rate is low),
-- at most `max_extra` live at once, the queue is bounded, and extras are never multiplied again (Gear's own spawns send no event).

local core = require('core')
local W, S = gear.world, gear.settings

local RING_INNER, RING_OUTER = gear.world.TILE * 1.5, gear.world.TILE * 5   -- where the extras appear around the original
local QUEUE_LIMIT = 1500                                                    -- jobs waiting at most
local PRUNE_EVERY = 2                                                       -- seconds between the checks which extras are gone

-- Texts of the "More" page, in the game's language (English as fallback).
local TEXT = {
    en = {
        title_how = 'How it works',
        how = 'Every creature the game spawns for you (sectors that fill when you arrive, scripted waves) brings extra ones of its kind: at 10x, nine more appear around it. Only creatures hostile to your hero are multiplied, only in single player. Extra creatures are never multiplied again. A higher rate means a fuller world and more to fight, but also a higher load: the safeguards below keep the frame rate up.',
        off = 'The rate is 1x: the mod does nothing.',
        net = 'Not available in a network game: the mod does nothing there.',
        title_status = 'Status',
        rows = {
            {'rate', 'Spawn rate now'}, {'alive', 'Extra creatures alive'}, {'queued', 'Waiting in the queue'},
            {'made', 'Made this session'}, {'refused', 'Not made (limit reached)'}, {'failed', 'Not made (no room or error)'},
        },
    },
    de = {
        title_how = 'So funktioniert es',
        how = 'Jede Kreatur, die das Spiel für dich erzeugt (Sektoren, die sich bei deiner Ankunft füllen, Wellen aus Skripten), bringt weitere ihrer Art mit: bei 10x erscheinen neun zusätzliche um sie herum. Vervielfacht werden nur Kreaturen, die deinem Helden feindlich sind, und nur im Einzelspielermodus. Zusätzliche Kreaturen werden nicht noch einmal vervielfacht. Eine höhere Rate bedeutet eine vollere Welt und mehr Kämpfe, aber auch mehr Last: die Schutzgrenzen unten halten die Bildrate hoch.',
        off = 'Die Rate ist 1x: Die Mod tut nichts.',
        net = 'Im Netzwerkspiel nicht verfügbar: Die Mod tut dort nichts.',
        title_status = 'Status',
        rows = {
            {'rate', 'Spawn-Rate jetzt'}, {'alive', 'Zusätzliche Kreaturen am Leben'}, {'queued', 'In der Warteschlange'},
            {'made', 'In dieser Sitzung erzeugt'}, {'refused', 'Nicht erzeugt (Grenze erreicht)'}, {'failed', 'Nicht erzeugt (kein Platz oder Fehler)'},
        },
    },
}
local function text()
    local lang = tostring(gear.game.config('LANGUAGE') or 'EN'):lower()
    return TEXT[lang] or TEXT.en
end

local queue = core.queue(QUEUE_LIMIT)
local alive = {}            -- id -> true: the extras this mod made and that still exist
local alive_count = 0
local stats = {made = 0, refused = 0, failed = 0}
local prune_t = 0

local function rate() return tonumber(S.get('rate', 1)) or 1 end

local function forget_all()
    queue:clear()
    alive, alive_count = {}, 0
end

gear.on('creature.created', gear.guard('creature.created', function(ev)
    local r = rate()
    if r <= 1 or not W.can_change() then return end
    local hero = W.hero()
    local c = ev.creature
    if not hero or not c or c:is_hero() or not c:is_enemy(hero) or c:is_dead() then return end
    local n = core.extras(r, math.random)
    if n > 0 and not queue:push({type = ev.type, x = ev.x, y = ev.y, layer = ev.layer, left = n}) then
        stats.refused = stats.refused + n
    end
end))

local function prune()
    for id in pairs(alive) do
        local c = W.object(id)
        if not c or not c:exists() or c:is_dead() then
            alive[id] = nil
            alive_count = alive_count - 1
        end
    end
end

gear.on('frame', gear.guard('frame', function(dt)
    prune_t = prune_t + dt
    if alive_count > 0 and prune_t >= PRUNE_EVERY then prune_t = 0; prune() end   -- also at 1x: the status page counts what is alive
    if rate() <= 1 then
        if queue.left > 0 then queue:clear() end
        return
    end
    if queue:size() == 0 or not W.can_change() then return end
    local cap = tonumber(S.get('max_extra', 200)) or 200
    local n = core.allowance(tonumber(S.get('budget', 4)) or 4, dt, alive_count, cap)
    if n == 0 and cap > 0 and alive_count >= cap then
        -- full: what waits would only grow the queue; the oldest jobs make room as extras die (prune), so keep a short queue
        while queue.left > cap do local one = queue:take(); if not one then break end; stats.refused = stats.refused + 1 end
    end
    for _ = 1, n do
        local one = queue:take()
        if not one then break end
        local x, y = core.scatter(one.x, one.y, RING_INNER, RING_OUTER, math.random)
        local c = W.spawn(one.type, x, y, {layer = one.layer})
        if c then
            alive[c.id] = true
            alive_count = alive_count + 1
            stats.made = stats.made + 1
        else
            stats.failed = stats.failed + 1
        end
    end
end))

-- Other games and savegames: object ids mean other creatures.
gear.on('savegame.leaving', forget_all)
gear.on('session.stop', forget_all)
gear.on('unload', forget_all)
gear.on('settings.changed', function(id) if id == 'rate' and rate() <= 1 then queue:clear() end end)

-- For the self test and tools: the counters.
gear.on('spawn-rate.stats', function(answer)
    local ids = {}
    for id in pairs(alive) do ids[#ids + 1] = id end
    answer({made = stats.made, refused = stats.refused, failed = stats.failed, alive = alive_count, queued = queue.left, ids = ids})
end)
-- For the self test: sets the numbers without the Mods screen ({rate, max_extra, budget}); the queue and counters can be reset.
gear.on('spawn-rate.configure', function(values)
    for _, id in ipairs({'rate', 'max_extra', 'budget'}) do
        if values[id] ~= nil then S.set(id, values[id]) end
    end
end)

gear.mods.page(function(x, y, w, h)
    local ui = gear.ui
    local T = text()
    local opts = {color = ui.rgba(235, 235, 235, 255), shadow = true, layer = 'top'}
    local head = {color = ui.rgba(255, 220, 120, 255), shadow = true, layer = 'top', bold = true}
    local area = ui.scroll_begin('sr_more_scroll', x, y, w, h, {step = 20, layer = 'top'})
    ui.rect(area.x, area.y, area.w, area.h, ui.rgba(18, 18, 22, 235), {layer = 'top'})
    local cy = 8
    ui.text(T.title_how, area.content_x + 8, area.content_y + cy, head)
    cy = cy + 24
    for _, l in ipairs(ui.text_wrap(T.how, area.w - 16, opts)) do
        ui.text(l, area.content_x + 8, area.content_y + cy, opts)
        cy = cy + 20
    end
    local note = (rate() <= 1 and T.off) or (not W.can_change() and gear.mp and gear.mp.active and gear.mp.active() and T.net) or nil
    if note then
        cy = cy + 6
        ui.text(note, area.content_x + 8, area.content_y + cy, head)
        cy = cy + 20
    end
    cy = cy + 10
    ui.text(T.title_status, area.content_x + 8, area.content_y + cy, head)
    cy = cy + 24
    local values = {rate = ('%gx'):format(rate()), alive = alive_count, queued = queue.left, made = stats.made, refused = stats.refused, failed = stats.failed}
    -- a real grid: names left, numbers right
    local t = ui.table('sr_status', area.content_x + 8, area.content_y + cy, area.w - 16, {
        columns = {'*', {width = 110, align = 'right'}}, spacing = {8, 3},
    })
    for _, row in ipairs(T.rows) do
        t:row()
        t:label(1, row[2], opts)
        t:label(2, tostring(values[row[1]]), opts)
    end
    ui.scroll_end(cy + t:height() + 12)
end)
