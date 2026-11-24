-- Spawn rate: multiplies the hostile creatures around the hero (1x to 100x). A creature is multiplied once, the first time the mod
-- sees it: either through Sacred Gear's `creature.created` event (the engine's own spawns: sectors that fill, spawn tables, scripts)
-- or in the periodic look around the hero (creatures a savegame restored, sectors already populated: the engine does not "spawn"
-- those, it reads them, so no event exists for them). For each one the mod makes rate - 1 more of the same type next to it.
-- Safeguards: the extras are made a few per frame from a bounded queue that serves the nearest originals first and fairly (fewer
-- while the frame rate is low), at most `max_extra` live at once, extras are never multiplied again (they are marked, and the marks
-- are kept per savegame so loading a game does not multiply it again), and harmless animals are left alone.

local core = require('core')
local W, S = gear.world, gear.settings

local RING_INNER, RING_OUTER = gear.world.TILE * 1.5, gear.world.TILE * 5   -- where the extras appear around the original
local QUEUE_LIMIT = 4000                                                    -- jobs waiting at most
local PRUNE_EVERY = 2                                                       -- seconds between the checks which extras are gone
local SCAN_EVERY = 1.5                                                      -- seconds between the looks around the hero
local SCAN_RADIUS, SCAN_LIMIT = 3500, 800                                   -- how far and how many creatures one look takes in
local DROP_RADIUS = 7000                                                    -- waiting jobs farther from the hero are given up (and seen again on return)
local NOTICE_RADIUS = 700                                                    -- an extra this close to the hero is told to attack it (natural monsters notice from 450 to 850)
local AWAKEN_EVERY = 0.5                                                    -- seconds between the looks at the extras near the hero
local REORDER_EVERY = 4                                                     -- seconds before an extra that is still near is ordered again
local ORDERS_PER_PASS = 30                                                  -- attack orders at most per look
local DATA = 'multiplied.json'                                              -- the marks, kept per savegame

-- Texts of the "More" page, in the game's language (English as fallback).
local TEXT = {
    en = {
        title_how = 'How it works',
        how = 'Every hostile creature around you brings extra ones of its kind: at 10x, nine more appear around it. That covers the creatures the game spawns (sectors that fill when you arrive, scripted waves) and, if you leave "Creatures already there" on, the ones a savegame or an already visited sector has placed: each creature is multiplied once, the first time the mod sees it, and a loaded savegame is not multiplied again. The nearest creatures come first. Only creatures hostile to your hero are multiplied (not rabbits, doves, birds and other harmless animals), only in single player. Extra creatures are never multiplied again. Extras that are near you are told to attack you, as the creatures the game places would notice you. A higher rate means a fuller world and more to fight, but also a higher load: the safeguards below keep the frame rate up.',
        off = 'The rate is 1x: the mod does nothing.',
        net = 'Not available in a network game: the mod does nothing there.',
        title_status = 'Status',
        rows = {
            {'rate', 'Spawn rate now'}, {'alive', 'Extra creatures alive'}, {'queued', 'Waiting in the queue'},
            {'made', 'Made this session'}, {'from_scan', 'Multiplied: already in the world'}, {'from_events', 'Multiplied: newly spawned'},
            {'refused', 'Not queued (queue full)'}, {'gave_up', 'Given up (too far away)'}, {'failed', 'Not made (no room or error)'},
            {'ordered', 'Attack orders given'},
        },
    },
    de = {
        title_how = 'So funktioniert es',
        how = 'Jede feindliche Kreatur um dich herum bringt weitere ihrer Art mit: bei 10x erscheinen neun zusätzliche um sie herum. Das gilt für Kreaturen, die das Spiel erzeugt (Sektoren, die sich bei deiner Ankunft füllen, Wellen aus Skripten) und, wenn "Schon vorhandene Kreaturen" an ist, auch für die aus einem Spielstand oder einem schon besuchten Sektor: jede Kreatur wird einmal vervielfacht, wenn die Mod sie zum ersten Mal sieht, und ein geladener Spielstand wird nicht noch einmal vervielfacht. Die nächsten Kreaturen kommen zuerst. Vervielfacht werden nur Kreaturen, die deinem Helden feindlich sind (keine Kaninchen, Tauben, Vögel und andere harmlose Tiere), und nur im Einzelspielermodus. Zusätzliche Kreaturen werden nicht noch einmal vervielfacht. Zusätzliche Kreaturen in deiner Nähe greifen dich an, so wie die vom Spiel platzierten dich bemerken würden. Eine höhere Rate bedeutet eine vollere Welt und mehr Kämpfe, aber auch mehr Last: die Schutzgrenzen unten halten die Bildrate hoch.',
        off = 'Die Rate ist 1x: Die Mod tut nichts.',
        net = 'Im Netzwerkspiel nicht verfügbar: Die Mod tut dort nichts.',
        title_status = 'Status',
        rows = {
            {'rate', 'Spawn-Rate jetzt'}, {'alive', 'Zusätzliche Kreaturen am Leben'}, {'queued', 'In der Warteschlange'},
            {'made', 'In dieser Sitzung erzeugt'}, {'from_scan', 'Vervielfacht: schon in der Welt'}, {'from_events', 'Vervielfacht: neu erzeugt'},
            {'refused', 'Nicht eingereiht (Warteschlange voll)'}, {'gave_up', 'Aufgegeben (zu weit weg)'}, {'failed', 'Nicht erzeugt (kein Platz oder Fehler)'},
            {'ordered', 'Angriffsbefehle gegeben'},
        },
    },
}
local function text()
    local lang = tostring(gear.game.config('LANGUAGE') or 'EN'):lower()
    return TEXT[lang] or TEXT.en
end

local queue = core.queue(QUEUE_LIMIT)
local alive = {}            -- id -> type: the extras this mod made and that still exist
local alive_count = 0
local known = {}            -- 'id:type' -> true: the originals handled and the extras (never multiplied again)
local pending = {}          -- original id -> true while its extras wait in the queue
local resume = {}           -- 'id:type' -> extras still owed (from a savegame: the original was only partly done when it was saved)
local stats = {made = 0, refused = 0, failed = 0, gave_up = 0, from_scan = 0, from_events = 0, ordered = 0}
local prune_t, scan_t, drop_t, awaken_t, clock = 0, 0, 0, 0, 0
local ordered = {}          -- extra id -> clock when it was last ordered to attack
local order_failed_logged, like_failed_logged = false, false

local function rate() return tonumber(S.get('rate', 1)) or 1 end
local function key(id, ty) return id .. ':' .. tostring(ty) end

local function forget_all()
    queue:clear()
    alive, alive_count, known, pending, resume, ordered = {}, 0, {}, {}, {}, {}
end

-- The first sight of a hostile creature: it is marked and its extras are queued. `how`: 'from_scan' or 'from_events'.
local function consider(c, id, ty, x, y, layer, how)
    local k = key(id, ty)
    if known[k] then return end
    local hero = W.hero()
    if not hero or not c or c:is_hero() or c:is_dead() or c:is_enemy(hero) ~= true then return end
    if not core.multipliable(c:type_name()) then return end   -- bunnies, doves, birds and the like stay as they are
    known[k] = true
    local n = resume[k] or core.extras(rate(), math.random)
    resume[k] = nil
    if n <= 0 then return end
    if queue:push({type = ty, x = x, y = y, layer = layer, left = n, origin = id}) then
        pending[id] = true
        stats[how] = stats[how] + 1
    else
        known[k] = nil              -- the queue is full: look at it again later
        stats.refused = stats.refused + 1
    end
end

gear.on('creature.created', gear.guard('creature.created', function(ev)
    if rate() <= 1 or not W.can_change() then return end
    consider(ev.creature, ev.id, ev.type, ev.x, ev.y, ev.layer, 'from_events')
end))

-- A look around the hero: the hostile creatures the mod has not seen (restored from a savegame, in sectors already populated).
local function scan()
    local hero = W.hero()
    if not hero then return end
    local hx, hy, layer = hero:position()
    for _, c in ipairs(W.creatures_near(hx, hy, SCAN_RADIUS, {layer = layer, limit = SCAN_LIMIT})) do
        local ty = c:type()
        if c.id ~= hero.id and ty and not known[key(c.id, ty)] then
            local x, y, l = c:position()
            if x then consider(c, c.id, ty, x, y, l, 'from_scan') end
        end
    end
end

-- An extra made by gear.world.spawn is hostile by faction (is_enemy is true for it, as for its original) but never notices the
-- hero on its own: the engine's sector fill leaves natural monsters in a state a plain create does not (measured: the same
-- type 420 units from the hero stands still for 14 s, a natural one charges from 450). So the extras near the hero get the
-- order a script would give: attack the hero. Needs Sacred Gear's creature:order_attack on non-party creatures.
local function awaken(hero, hx, hy, hlayer)
    local r2, sent = NOTICE_RADIUS * NOTICE_RADIUS, 0
    for id in pairs(alive) do
        if sent >= ORDERS_PER_PASS then break end
        if not ordered[id] or clock - ordered[id] >= REORDER_EVERY then
            local c = W.object(id)
            if c and c:exists() and not c:is_dead() then
                local x, y, l = c:position()
                if x and l == hlayer and (x - hx) ^ 2 + (y - hy) ^ 2 <= r2 then
                    local ok, err = c:order_attack(hero)
                    ordered[id] = clock
                    sent = sent + 1
                    stats.ordered = stats.ordered + 1
                    if not ok and not order_failed_logged then
                        order_failed_logged = true
                        print('spawn-rate: the attack order was refused (' .. tostring(err) .. '): update Sacred Gear')
                    end
                end
            end
        end
    end
end

local function prune()
    for id in pairs(alive) do
        local c = W.object(id)
        if not c or not c:exists() or c:is_dead() then
            alive[id] = nil
            ordered[id] = nil
            alive_count = alive_count - 1
        end
    end
end

-- The marks per savegame: what was multiplied (so a loaded game is not multiplied again) and which creatures are extras.
local function write_marks()
    local marks, extras, owed = {}, {}, {}
    for _, job in ipairs(queue.jobs) do            -- an original whose extras still wait: the rest is made after a load
        owed[#owed + 1] = job.origin; owed[#owed + 1] = job.type; owed[#owed + 1] = job.left
    end
    for k in pairs(known) do
        local id, ty = k:match('^(%d+):(%d+)$')
        id, ty = tonumber(id), tonumber(ty)
        if id and not pending[id] then
            local c = W.object(id)
            if c and c:exists() and c:type() == ty then marks[#marks + 1] = id; marks[#marks + 1] = ty end
        end
    end
    for id, ty in pairs(alive) do extras[#extras + 1] = id; extras[#extras + 1] = ty end
    gear.savegame.write(DATA, gear.json.encode({marks = marks, extras = extras, owed = owed}))
end

local function read_marks()
    forget_all()
    local raw = gear.savegame.read(DATA)
    if not raw then return end
    local ok, data = pcall(gear.json.decode, raw)
    if not ok or type(data) ~= 'table' then return end
    local marks, extras, owed = data.marks or {}, data.extras or {}, data.owed or {}
    for i = 1, #owed, 3 do resume[key(owed[i], owed[i + 1])] = owed[i + 2] end
    for i = 1, #marks, 2 do known[key(marks[i], marks[i + 1])] = true end
    for i = 1, #extras, 2 do
        local id, ty = extras[i], extras[i + 1]
        known[key(id, ty)] = true
        local c = W.object(id)
        if c and c:exists() and c:type() == ty then alive[id] = ty; alive_count = alive_count + 1 end
    end
end

gear.on('frame', gear.guard('frame', function(dt)
    prune_t = prune_t + dt
    clock = clock + dt
    if alive_count > 0 and prune_t >= PRUNE_EVERY then prune_t = 0; prune() end   -- also at 1x: the status page counts what is alive
    if rate() <= 1 then
        if queue.left > 0 then queue:clear(); pending = {} end
        return
    end
    if not W.can_change() then return end
    local hero = W.hero()
    if not hero then return end
    local hx, hy, hlayer = hero:position()
    if S.get('existing', true) then
        scan_t = scan_t + dt
        if scan_t >= SCAN_EVERY then scan_t = 0; scan() end
    end
    awaken_t = awaken_t + dt
    if awaken_t >= AWAKEN_EVERY then
        awaken_t = 0
        if alive_count > 0 and (hero:hp() or 1) > 0 then awaken(hero, hx, hy, hlayer) end
    end
    if queue:size() == 0 then return end
    -- jobs far from the hero (or on another layer) are given up; their originals are seen again when the hero comes back
    drop_t = drop_t + dt
    if drop_t >= 1 then
        drop_t = 0
        local r2 = DROP_RADIUS * DROP_RADIUS
        for _, job in ipairs(queue:drop_if(function(j) return j.layer ~= hlayer or (j.x - hx) ^ 2 + (j.y - hy) ^ 2 > r2 end)) do
            known[key(job.origin, job.type)] = nil
            pending[job.origin] = nil
            stats.gave_up = stats.gave_up + 1
        end
    end
    local cap = tonumber(S.get('max_extra', 200)) or 200
    local n = core.allowance(tonumber(S.get('budget', 4)) or 4, dt, alive_count, cap)
    for _ = 1, n do
        local one = queue:take(hx, hy)
        if not one then break end
        -- the extra takes the faction and aggression of its original (a plain create has the faction of the type, which can differ:
        -- a soldier the game placed is hostile, a soldier made by a plain create is neutral); an original that is gone makes none
        local original = W.object(one.origin)
        if not original or not original:exists() or original:is_dead() then
            for _, job in ipairs(queue:drop_if(function(j) return j.origin == one.origin end)) do
                pending[job.origin] = nil
            end
            pending[one.origin] = nil
            stats.failed = stats.failed + 1
            goto next_extra
        end
        do
            local x, y = core.scatter(one.x, one.y, RING_INNER, RING_OUTER, math.random)
            local c, err = W.spawn(one.type, x, y, {layer = one.layer, like = original})
            if c then
                alive[c.id] = one.type
                alive_count = alive_count + 1
                known[key(c.id, one.type)] = true
                stats.made = stats.made + 1
            else
                stats.failed = stats.failed + 1
                if err and not like_failed_logged then
                    like_failed_logged = true
                    print('spawn-rate: spawning failed (' .. tostring(err) .. '): needs a Sacred Gear with spawn opts.like')
                end
            end
        end
        ::next_extra::
        if queue:size() == 0 then pending = {} end
    end
end))


-- Savegames: the marks are written with the save and read again with the load.
gear.on('savegame.saving', gear.guard('savegame.saving', write_marks))
gear.on('savegame.leaving', forget_all)
gear.on('savegame.changed', gear.guard('savegame.changed', read_marks))
-- Not 'session.stop': Sacred Gear sends it whenever the hero id changes, also when the player takes control of a companion
-- (gear.party.control). Forgetting then made every creature around look new and multiplied it again at each switch. A game that
-- really ends or changes is covered by savegame.leaving / savegame.changed.
gear.on('unload', forget_all)
gear.on('settings.changed', function(id) if id == 'rate' and rate() <= 1 then queue:clear(); pending = {} end end)

-- For the self test and tools: the counters.
gear.on('spawn-rate.stats', function(answer)
    local ids = {}
    for id in pairs(alive) do ids[#ids + 1] = id end
    answer({made = stats.made, refused = stats.refused, failed = stats.failed, gave_up = stats.gave_up, from_scan = stats.from_scan,
            from_events = stats.from_events, ordered = stats.ordered, alive = alive_count, queued = queue.left, ids = ids})
end)
-- For the self test: sets the numbers without the Mods screen ({rate, max_extra, budget, existing}).
gear.on('spawn-rate.configure', function(values)
    for _, id in ipairs({'rate', 'max_extra', 'budget', 'existing'}) do
        if values[id] ~= nil then S.set(id, values[id]) end
    end
end)
-- For the self test: forgets everything the mod knows (a fresh start of the same game).
gear.on('spawn-rate.reset', function()
    forget_all()
    stats = {made = 0, refused = 0, failed = 0, gave_up = 0, from_scan = 0, from_events = 0, ordered = 0}
end)
-- For the self test: 'write' keeps the marks as a save does, 'read' reads them as a load does.
gear.on('spawn-rate.marks', function(action) if action == 'write' then write_marks() else read_marks() end end)

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
    local values = {rate = ('%gx'):format(rate()), alive = alive_count, queued = queue.left, made = stats.made, refused = stats.refused,
                    failed = stats.failed, gave_up = stats.gave_up, from_scan = stats.from_scan, from_events = stats.from_events, ordered = stats.ordered}
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
