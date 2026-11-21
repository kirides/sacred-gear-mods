-- Periodic autosave for single player games (issue kirides/sacred-bild#10).
--
-- Counts the time the hero actually plays (the game shown, no window, escape menu or message box; frames only run in
-- game, so loading screens and the main menu do not count either), and when the interval is up, saves into the next
-- of a few dedicated slots (default Save\GAME97.PAK .. GAME99.PAK, oldest first) through the game's own save
-- request, `gear.game.save`. Quicksave (GAME00) and the player's manual saves are never touched. A save that cannot
-- start now (a window is open, a cinematic plays, a load is pending ...) waits and is tried again every few
-- seconds; one that fails is logged and retried with growing pauses, never every frame.
--
-- Other mods can steer it: gear.emit('autosave.configure', {enabled = ..., interval_minutes = ..., slots = ...})
-- changes the settings for this session, gear.emit('autosave.query', out) fills `out` with its state.

local ui = gear.ui
local game = gear.game
local cfg = gear.config

local SAVED_KEYS = {'enabled', 'interval_minutes', 'slots', 'name', 'show_confirmation'}   -- autosave.configure
local SETTING_IDS = {'enabled', 'interval_minutes', 'name', 'show_confirmation'}   -- the plain ones of the Mods screen
local DEFAULT_SLOTS = {97, 98, 99}
local MAX_SLOTS = 8
local MIN_INTERVAL, MAX_INTERVAL = 0.05, 240     -- minutes
local RETRY_WAIT = 2          -- seconds between tries while the game is in no state to save
local FAIL_BACKOFF = {10, 30, 60, 120}           -- seconds after the 1st, 2nd ... failure in a row
local NOTE_SECONDS = 4

---------------------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------------------

---@param slots any
---@return integer[]
local function clean_slots(slots)
    local out, seen = {}, {}
    if type(slots) == 'table' then
        for _, s in ipairs(slots) do
            if type(s) == 'number' and s == math.floor(s) and s >= 1 and s <= 32766 and not seen[s]
                and #out < MAX_SLOTS then
                seen[s] = true
                out[#out + 1] = s
            end
        end
    end
    if #out == 0 then
        for i, s in ipairs(DEFAULT_SLOTS) do out[i] = s end
    end
    return out
end

local function check_config()
    cfg.enabled = cfg.enabled ~= false
    if type(cfg.interval_minutes) ~= 'number' then cfg.interval_minutes = 5 end
    cfg.interval_minutes = math.max(MIN_INTERVAL, math.min(MAX_INTERVAL, cfg.interval_minutes))
    cfg.slots = clean_slots(cfg.slots)
    if type(cfg.name) ~= 'string' or cfg.name == '' then cfg.name = 'Autosave %H:%M' end
    cfg.show_confirmation = cfg.show_confirmation ~= false
    -- A manual save (the game's own "new savegame", Better SaveLoad's) never takes one of these numbers first, however
    -- many savegames there are.
    if game.reserve_slots then game.reserve_slots(cfg.slots) end
end

-- The settings are kept by the mod manager (gear.settings, saved in mods\gear_mods.json, changed in its Mods screen);
-- `cfg` is the working copy the rest of the mod reads (gear.config holds what has no screen: note_y).
local S = gear.settings
local pushing = false

--- "97, 98 99" -> {97, 98, 99}
---@param text string
---@return integer[]
local function parse_slots(text)
    local list = {}
    for n in tostring(text):gmatch('%d+') do list[#list + 1] = tonumber(n) end
    return list
end

local function pull()
    for _, k in ipairs(SETTING_IDS) do cfg[k] = S.get(k) end
    cfg.slots = parse_slots(S.get('slots'))
    check_config()
end

--- Writes the working copy back (after autosave.configure with persist).
local function push()
    pushing = true
    for _, k in ipairs(SETTING_IDS) do S.set(k, cfg[k]) end
    S.set('slots', table.concat(cfg.slots, ', '))
    pushing = false
end

pull()
gear.on('settings.changed', function(id, value)
    if pushing then return end
    if id == 'slots' then cfg.slots = parse_slots(value) else cfg[id] = value end
    check_config()
end)

---------------------------------------------------------------------------------------------------------------
-- The timer: active play time since the last autosave
---------------------------------------------------------------------------------------------------------------
local active = 0              -- seconds of active play since the last successful autosave (or the session start)
local total_active = 0        -- ... since the mod loaded
local due = false             -- the interval is up and the save has not happened yet
local next_try = 0            -- gear.time() before which no save is attempted
local fails = 0               -- failures in a row
local waiting_reason = nil    -- why the save waits (can_save's answer), for the panel
local requested = false       -- a save request is out; the result event is pending
local requested_at = 0
local note = nil              -- {text, until, ok}
local last = nil              -- {slot, time, size} of the last successful autosave
local saves = 0

--- Whether the hero is playing right now: the game shown, nothing on top of it.
---@param s GearUiState
local function playing(s)
    return s.available and s.mode == 'game' and not s.exclusive and not s.escape_menu and not s.message_box
        and not s.help
end

local function show_note(text, ok)
    note = {text = text, ['until'] = gear.time() + NOTE_SECONDS, ok = ok}
end

--- The slot to write next: a free one first, else the oldest file.
---@return integer
local function pick_slot()
    local best, best_time
    for _, slot in ipairs(cfg.slots) do
        local info = game.save_info(slot)
        local t = (info and info.exists) and info.mtime or -1
        if not best or t < best_time then best, best_time = slot, t end
    end
    return best
end

local function display_name()
    local ok, text = pcall(os.date, cfg.name)
    return ok and text or 'Autosave'
end

local function fail_pause()
    fails = fails + 1
    local pause = FAIL_BACKOFF[math.min(fails, #FAIL_BACKOFF)]
    next_try = gear.time() + pause
    return pause
end

local function try_save()
    local ok, reason = game.can_save()
    if not ok then
        waiting_reason = reason
        next_try = gear.time() + RETRY_WAIT
        return
    end
    waiting_reason = nil
    local slot = pick_slot()
    local accepted, err = game.save(slot, display_name())
    if accepted then
        requested, requested_at = true, gear.time()
        return
    end
    print(('autosave to slot %d refused: %s (next try in %d s)'):format(slot, tostring(err), fail_pause()))
end

gear.on('game.saved', function(slot, info)
    if not requested then return end    -- a save by another mod
    requested, due, fails, active = false, false, 0, 0
    saves = saves + 1
    last = {slot = slot, time = gear.time(), size = info.size}
    if cfg.show_confirmation then show_note(('Autosaved (slot %d)'):format(slot), true) end
    print(('autosaved to slot %d (%d bytes)'):format(slot, info.size))
end)

gear.on('game.save_failed', function(slot, message)
    if not requested then return end
    requested = false
    print(('autosave to slot %d failed: %s (next try in %d s)'):format(slot, tostring(message), fail_pause()))
    if cfg.show_confirmation then show_note('Autosave failed', false) end
end)

-- A save nobody here asked for (the quicksave, a manual save, the game's own Auto-Save at a script point) also saved
-- the progress: the timer starts over, and a save that was waiting for a valid moment is not needed any more.
gear.on('game.saved_other', function(slot)
    if requested then return end
    active, due, fails = 0, false, 0
    print(('slot %d was saved by the game or the player: timer restarted'):format(slot))
end)

gear.on('session.start', function()
    active, due, fails, requested, next_try, waiting_reason = 0, false, 0, false, 0, nil
end)

gear.on('frame', function(dt)
    local s = ui.state()
    if not cfg.enabled then
        active, due = 0, false
        return
    end
    if playing(s) then
        -- A hitch (a long load inside a frame) must not count as play.
        local step = math.min(dt, 1)
        active = active + step
        total_active = total_active + step
    end
    if requested then
        if gear.time() - requested_at > 90 then
            requested = false           -- the result never came; start over
            print('autosave: no result after 90 s, forgotten')
        end
        return
    end
    if not due and active >= cfg.interval_minutes * 60 then due = true end
    if due and gear.time() >= next_try then try_save() end
end)

---------------------------------------------------------------------------------------------------------------
-- Other mods: gear.emit('autosave.configure', settings) / gear.emit('autosave.query', out)
---------------------------------------------------------------------------------------------------------------
gear.on('autosave.configure', function(settings)
    if type(settings) ~= 'table' then return end
    for _, k in ipairs(SAVED_KEYS) do
        if settings[k] ~= nil then cfg[k] = settings[k] end
    end
    check_config()
    if settings.persist then push() end
end)

gear.on('autosave.query', function(out)
    if type(out) ~= 'table' then return end
    out.enabled, out.interval_minutes, out.slots = cfg.enabled, cfg.interval_minutes, cfg.slots
    out.active_seconds, out.total_active_seconds = active, total_active
    out.due, out.requested, out.fails, out.saves = due, requested, fails, saves
    out.waiting_reason = waiting_reason
    out.last_slot = last and last.slot or nil
end)

---------------------------------------------------------------------------------------------------------------
-- UI: the note after a save, and the state page
---------------------------------------------------------------------------------------------------------------
local function mmss(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

-- ui/note.rml: a small themed line at the top of the screen (cfg.note_y from the top, centred).
local note_doc
---@param s GearUiState
local function draw_note(s)
    if not note or not playing(s) then return end
    if gear.time() > note['until'] then
        note = nil
        return
    end
    if not note_doc then
        local err
        note_doc, err = ui.rml.load('ui/note.rml', {model = {text = note.text, ok = note.ok and true or false}})
        if not note_doc then
            print('autosave: ui/note.rml failed: ' .. tostring(err))
            return
        end
    end
    note_doc.model.text = note.text
    note_doc.model.ok = note.ok and true or false
    note_doc:style('#note', 'top', cfg.note_y .. 'px')
    note_doc:draw({layer = 'top'})
end

-- A "More" tab in the mod's page of the Mods screen (ui/page.rml, the game theme): the state, and Save now.
gear.mods.page_rml('ui/page.rml', {
    model = {status = '', slots = '', last = '', game_autosave = false, requested = false},
    on_load = function(doc)
        doc:on('#now', 'click', function()
            if not requested then due, next_try = true, 0 end
        end)
    end,
    update = function(doc)
        local status
        if not cfg.enabled then status = 'off'
        elseif requested then status = 'saving ...'
        elseif due then status = 'waiting: ' .. tostring(waiting_reason or 'retrying')
        else status = 'next in ' .. mmss(cfg.interval_minutes * 60 - active) end
        local names = {}
        for i, n in ipairs(cfg.slots) do names[i] = ('GAME%02d'):format(n) end
        local m = doc.model
        local function set(k, v) if m[k] ~= v then m[k] = v end end
        set('status', status)
        set('slots', table.concat(names, ', '))
        set('last', last and ('Last: slot %d, %s ago'):format(last.slot, mmss(gear.time() - last.time)) or '')
        set('game_autosave', gear.game.config('AUTOSAVE') == 1)
        set('requested', requested and true or false)
    end,
})

gear.on('draw', function(s)
    if s then draw_note(s) end
end)

gear.keys.on('save_now', function()
    if cfg.enabled and not requested then due, next_try = true, 0 end
end)
