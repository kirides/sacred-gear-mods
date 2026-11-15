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

local SAVED_KEYS = {'enabled', 'interval_minutes', 'slots', 'name', 'show_confirmation'}
local SETTING_IDS = {'enabled', 'interval_minutes', 'name', 'show_confirmation'}   -- those the Mods screen lists
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
            if type(s) == 'number' and s == math.floor(s) and s >= 1 and s <= 509 and not seen[s]
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
end

-- The settings are kept by the mod manager (gear.settings, saved in gear_mods.json); `cfg` is the working copy the
-- rest of the mod reads. pull() takes the player's values into it, push() writes it back (the panel, 'persist').
local S = gear.settings
local pushing = false

local function pull()
    for _, k in ipairs(SETTING_IDS) do
        if S.is_set(k) then cfg[k] = S.get(k) end
    end
    check_config()
end

local function push()
    pushing = true
    for _, k in ipairs(SETTING_IDS) do S.set(k, cfg[k]) end
    pushing = false
end

local function save_settings() push() end

-- The old settings.json of this folder (written by the panel's Save button), once.
S.migrate('settings.json', function(old)
    for _, k in ipairs(SAVED_KEYS) do
        if old[k] ~= nil then cfg[k] = old[k] end
    end
    check_config()
    push()
    if type(old.settings_key) == 'string' then gear.keys.set('panel', old.settings_key) end
    print('settings.json migrated to the mod manager')
end)
pull()
check_config()
gear.on('settings.changed', function(id, value)
    if pushing then return end
    cfg[id] = value
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
    if settings.persist then save_settings() end
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
-- UI: the note after a save, and the settings panel
---------------------------------------------------------------------------------------------------------------
ui.show_panel('settings', false)

local function mmss(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

---@param s GearUiState
local function draw_note(s)
    if not note or not playing(s) then return end
    if gear.time() > note['until'] then
        note = nil
        return
    end
    local w = 190
    local x = (1024 - w) / 2
    local y = cfg.note_y
    ui.rect(x, y, w, 22, ui.rgba(0, 0, 0, 150))
    ui.frame(x, y, w, 22, note.ok and ui.rgba(120, 200, 120, 200) or ui.rgba(220, 110, 90, 200))
    ui.text(note.text, x, y, {width = w, height = 22, align = 'center', valign = 'middle', size = 13,
        color = note.ok and 0xFFA0FFA0 or 0xFFFF9080})
end

local function settings_panel()
    local p = ui.panel('settings', 'Autosave', 300, 120, 360, 232)
    if not p.open then return end
    local x, y = p.content_x, p.content_y
    local changed, c = false, nil
    c, cfg.enabled = ui.checkbox('enabled', x, y, 'Autosave on', cfg.enabled,
        {tooltip = 'Saves into its own slots every few minutes of play'})
    changed = changed or c
    ui.text('Every', x, y + 30, {height = 18, valign = 'middle'})
    c, cfg.interval_minutes = ui.slider('interval', x + 50, y + 30, 200, 1, 60, math.floor(cfg.interval_minutes + 0.5),
        {step = 1, tooltip = 'Minutes of active play between autosaves'})
    changed = changed or c
    ui.text(('%d min'):format(math.floor(cfg.interval_minutes + 0.5)), x + 262, y + 30,
        {height = 18, valign = 'middle'})
    c, cfg.show_confirmation = ui.checkbox('confirm', x, y + 58, 'Show a note after each autosave',
        cfg.show_confirmation)
    changed = changed or c

    local slots = {}
    for i, s in ipairs(cfg.slots) do slots[i] = ('GAME%02d'):format(s) end
    ui.text('Slots: ' .. table.concat(slots, ', '), x, y + 84, {color = 0xFFC0C0C0, size = 11})
    local status
    if not cfg.enabled then status = 'off'
    elseif requested then status = 'saving ...'
    elseif due then status = 'waiting: ' .. tostring(waiting_reason or 'retrying')
    else status = 'next in ' .. mmss(cfg.interval_minutes * 60 - active) end
    ui.text('Status: ' .. status, x, y + 100, {color = 0xFFC0C0C0, size = 11})
    if last then
        ui.text(('Last: slot %d, %s ago'):format(last.slot, mmss(gear.time() - last.time)), x, y + 114,
            {color = 0xFFC0C0C0, size = 11})
    end
    if changed then check_config(); push() end

    if ui.button('now', x, y + 138, 100, 22, 'Save now', {enabled = not requested,
        tooltip = 'Autosave right away (into the next slot)'}) then
        due, next_try = true, 0
    end
    if ui.button('close', x + 110, y + 138, 100, 22, 'Close') then ui.show_panel('settings', false) end
    ui.text('Also in the Mods screen (F11)', x, y + 166, {color = 0xFFC0C0C0, size = 11})
end

gear.on('draw', function(s)
    if not s then return end
    draw_note(s)
    if s.mode == 'game' and not s.exclusive then
        settings_panel()
    end
end)

gear.keys.on('panel', function()
    ui.show_panel('settings', not ui.panel_open('settings'))
end)
