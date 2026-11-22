-- Bounty board. Two sources, one panel:
--   * network game: the bounties a game server posts (Sacred.GameServer, scripts-examples/bounty_board.lua) and the hero's own
--     progress. The server pushes the board over the custom net channel 'bounty:state' (gear.net, so the server must be the
--     Sacred Gear game server; the original GameServer.exe never answers and the panel says so).
--   * single player: this computer posts, counts and pays the bounties of the hero itself (localboard.lua: the board,
--     localgame.lua: kills and rewards), saved per hero in the mod's folder. Switch off with the setting "Own board".
--
--   Ctrl+J (rebindable in the Mods screen)   the bounty panel: every bounty with a progress bar, time left and reward
--   a small tracker with the open bounties (setting "Tracker")
--
-- Protocol: the server sends { v = 1, next_in, bounties = { { id, title, text, region, target, n, done, left, reward, claims, level } } }
-- to a client that said HELLO (the library does that after joining); this mod also asks with { req = 1 } now and then.
-- `left` is relative (seconds), so this computer's clock does not matter. Nothing in the payload is trusted for anything but display.

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local cfg = gear.config
local ui, net = gear.ui, gear.net

local localboard = require('localboard')
local localgame = require('localgame')
local customs = require('customs')
local hooks = require('hooks')
local editor = require('editor')
local quests = require('questsmain')     -- daily and weekly quests (own panel, own state per savegame)

local channel = net and net.channel('bounty:state')
local board = nil          -- the last payload (the server's, or the local board's)
local received = 0         -- gear.time() when it arrived
local asked = -1e9
local is_local          -- defined below: whether this is the single player board

local GOLD, GREEN, GREY = 0xFFFFD780, 0xFF80FF80, 0xFFB0B0B0

-- Hooks for other mods (README: Hooks). Declared once; the board that arrives is compared with the one before.
if gear.events then for _, e in ipairs(hooks.EVENTS) do gear.events.declare(e[1], {doc = e[2], args = hooks.ARGS}) end end

local function set_board(new, source)
    local old = board
    board, received = new, gear.time()
    hooks.diff(old, new, gear.emit, {source = source, claim_on_done = source == 'server'})
end

local function valid(payload)
    if type(payload) ~= 'table' or payload.v ~= 1 or type(payload.bounties) ~= 'table' then return false end
    for _, b in ipairs(payload.bounties) do
        if type(b) ~= 'table' or type(b.title) ~= 'string' or type(b.target) ~= 'number' then return false end
    end
    return true
end

if channel then
    channel:on(function(from, payload)
        if valid(payload) then set_board(payload, 'server') end
    end)
end

local function ask(force)
    if is_local() then return end
    if not channel or not net.supported() then return end
    local t = gear.time()
    if not force and t - asked < cfg.refresh then return end
    asked = t
    channel:send({req = 1}, 'server')
end

gear.on('net_caps', function(caps) if caps and caps.supported then ask(true) end end)
gear.every(5, function() ask(false) end)

---------------------------------------------------------------------------------------------------------------
-- Single player: the hero's own board
---------------------------------------------------------------------------------------------------------------
local mine = nil           -- localboard.Board of the hero, or nil
local mine_file = nil
local mine_hero = nil
local dirty, last_tick, last_save = false, nil, 0

is_local = function()
    return gear.settings.get('own_board') ~= false and not (gear.mp and gear.mp.active())
end

local function toast(title, ...) gear.toast.show(title, ...) end

local function rng(lo, hi) return math.random(lo, hi) end

local function file_for(name)
    local clean = name:gsub('[^%w]', '_')
    local h = 2166136261
    -- FNV-1a, exactly: LuaJIT has no ~ operator (bit.bxor), and a double cannot hold h * 16777619, so the multiplication by
    -- 2^24 + 403 is split: (h * 2^24) mod 2^32 only keeps the low byte of h.
    for i = 1, #name do
        h = bit.bxor(h, name:byte(i)) % 4294967296
        h = (h * 403 + (h % 256) * 16777216) % 4294967296
    end
    return ('board_%s_%08x.json'):format(clean:sub(1, 24), h)
end

local function refresh()
    if mine then set_board(mine:payload(), 'local') end
end

-- The board belongs to the savegame (gear.savegame): board.json of the running game's data, so another savegame or character of
-- the same name has its own bounties. Without it (an older Gear, or a game whose load Gear did not see) the board is kept in a file
-- of the hero's name as before. The file from before is taken once per hero by the first savegame that is loaded.
local BOARD = 'board.json'
local function per_game() return gear.savegame ~= nil and gear.savegame.kind() ~= nil end

local function read_board(name)
    if not per_game() then return gear.read(file_for(name)) end
    local text = gear.savegame.read(BOARD)
    if text then return text end
    local kind, legacy = gear.savegame.kind(), file_for(name)
    if kind == 'load' or kind == 'hero' then
        local marker = legacy:gsub('%.json$', '') .. '.migrated.txt'
        local old = gear.read(legacy)
        if old and not gear.read(marker) then
            gear.save(marker, tostring(gear.savegame.scope()))
            return old
        end
    end
    return nil
end

local function write_board(text)
    if per_game() then return gear.savegame.write(BOARD, text) end
    return gear.save(mine_file, text)
end

local function save_mine()
    if not mine or not mine_file then return end
    local ok, err = write_board(gear.json.encode(mine:save_table()))
    if ok then dirty, last_save = false, gear.time() else print('bounty: cannot save ' .. mine_file .. ': ' .. tostring(err)) end
end

local function open_mine()
    local hero = gear.world.hero()
    local name = hero and hero:name()
    if not name then return end
    mine_hero, mine_file = name, file_for(name)
    local text = read_board(name)
    local data = text and gear.json.decode(text)
    mine = localboard.load(data, rng)
    local level = hero:level() or 1
    local posted = gear.settings.get('pool_board') ~= false and mine:fill(level, mine:pool_count() == 0) or {}
    last_tick = gear.time()
    if #posted > 0 then dirty = true end
    refresh()
    save_mine()
end

local function close_mine()
    save_mine()
    mine, mine_file, mine_hero, board = nil, nil, nil, nil
    localgame.reset()
end

-- A game starts or ends: the board of the game before is saved and closed (the next tick opens the new hero's).
-- (These handlers must come after the locals mine and close_mine: above them those names would be globals, always nil.)
gear.on('session.start', function()
    if mine then close_mine() end
    board = nil
    ask(true)
    editor.close()
end)
gear.on('session.stop', function()
    if mine then close_mine() end
    board = nil
end)

local function reward(b)
    local p
    for _, e in ipairs(board and board.bounties or {}) do if e.id == b.id then p = hooks.payload(e, 'local') end end
    gear.emit('bounty.claimed', p or hooks.payload({id = b.id, title = b.title, text = b.text, target = b.target, n = b.n,
        level = b.min_level, custom = b.custom}, 'local'))
    local parts = {}
    if (b.gold or 0) > 0 and localgame.gold(b.gold) then parts[#parts + 1] = b.gold .. ' gold' end
    if b.item then
        localgame.drop_item(b.item, function(ok)
            toast(ok and 'Bounty reward' or 'Bounty reward failed', ok and 'An item dropped at your feet' or 'No item could be made')
        end)
        parts[#parts + 1] = 'an item'
    end
    toast('Bounty complete: ' .. b.title, #parts > 0 and ('Reward: ' .. table.concat(parts, ' and ')) or nil)
end

localgame.on_kill(function(type_name, type_id)
    if not mine then return end
    local hero = gear.world.hero()
    local level = hero and hero:level() or 1
    local words = localboard.words(type_name)
    local finished = mine:kill(words, level, type_id)
    local started = mine:trigger_kill(customs.defs, words, level, type_id)
    refresh()        -- bounty.progress / completed / started go out first, then the rewards (bounty.claimed)
    for _, b in ipairs(finished) do reward(b) end
    for _, b in ipairs(started) do toast('Bounty started: ' .. b.title, b.text) end
    dirty = true
    if gear.time() - last_save > 5 then save_mine() end
end)

local editor_hooks = {
    active = function(id) return mine and mine:active(id) end,
    start = function(def)
        if not mine then return end
        local b = mine:start(def)
        toast('Bounty started: ' .. b.title, b.text)
        dirty = true
        refresh()
        save_mine()
    end,
    stop = function(id)
        if mine and mine:stop(id) then dirty = true refresh() save_mine() end
    end,
    trigger_state = function(id) if mine then return mine:trigger_state(id) end return 0, 0 end,
}

-- Names a bounty file of an older version holds become type ids (Gear's object_types:resolve); the player sees localized names.
do
    local T = gear.data and gear.data.object_types
    if T and T.resolve then localboard.resolver = function(text) local ok, id = pcall(T.resolve, T, text) return ok and id or nil end end
    if T and T.label then localboard.labeler = function(id) local ok, n = pcall(T.label, T, id) return ok and n or nil end end
end
customs.load()

gear.every(0.25, function()
    if (is_local() and mine) or quests.wants_poll() then localgame.poll() end
end)

gear.every(1, function()
    if not is_local() then
        if mine then close_mine() end
        return
    end
    if not mine then open_mine() return end
    local hero = gear.world.hero()
    if not hero then return end
    if hero:name() ~= mine_hero then close_mine() open_mine() return end
    local t = gear.time()
    local dt = math.min(3, math.max(0, t - (last_tick or t)))
    last_tick = t
    local gone = mine:tick(dt)
    local posted = gear.settings.get('pool_board') ~= false and mine:fill(hero:level() or 1, false) or {}
    if gear.settings.get('pool_board') == false then
        -- the pool bounties are switched off: only the player's own stay
        local kept = {}
        for _, b in ipairs(mine.list) do if b.custom then kept[#kept + 1] = b end end
        if #kept ~= #mine.list then mine.list, dirty = kept, true end
    end
    for _, b in ipairs(gone) do
        if not b.done then toast('Bounty ended', b.title) end
    end
    for _, b in ipairs(posted) do toast('New bounty', b.title, b.text) end
    if #gone > 0 or #posted > 0 then dirty = true end
    refresh()
    if dirty and t - last_save > 20 then save_mine() end
end)

gear.on('unload', function() if mine then save_mine() end end)

-- A savegame is written: its board is kept for it. Another game loads: its board is read (the next tick), what this one had not
-- saved is gone with it.
gear.on('savegame.saving', function() if mine and dirty then save_mine() end end)
gear.on('savegame.changed', function()
    mine, mine_file, mine_hero, board, dirty = nil, nil, nil, nil, false
    localgame.reset()
end)

local time_text = gear.fmt.span

local function left_of(b) return (b.left or 0) - (gear.time() - received) end

-- The board and the tracker are ui/board.rml (the game theme): a model of ready-made strings, rebuilt every frame; each frame writes
-- what changed. (bounty-rows.lua turns one bounty into a row for this and for the quests window.)
local rows_lib = require('bounty-rows')
local doc
local last = {}
local board_open = false

local function snapshot()
    local own = is_local()
    local m = {open = board_open, title = 'Bounty board' .. key_hint('panel'), msg = '', rows = {}, own = own and true or false, own_line = '',
        tracker_on = false, tracker_lines = {}}
    if not own and (not channel or not net.supported()) then
        m.msg = 'This server has no bounty board (it needs the Sacred Gear game server with bounty_board.lua).'
    elseif not board then
        m.msg = own and 'Looking for your hero...' or 'Waiting for the server...'
    elseif #board.bounties == 0 then
        m.msg = 'The board is empty.'
    else
        for i, b in ipairs(board.bounties) do
            m.rows[i] = rows_lib.row(b, {state = b.done and 'done' or (b.endless and 'no limit' or time_text(left_of(b)))})
        end
        m.own_line = ('Single player: your own board. Finished so far: %d'):format(board.done_count or 0)
    end
    if gear.settings.get('tracker') and board then
        for _, b in ipairs(board.bounties) do
            if not b.done then m.tracker_lines[#m.tracker_lines + 1] = ('%s  %d/%d'):format(b.title, math.min(b.n or 0, b.target), b.target) end
        end
        m.tracker_on = #m.tracker_lines > 0 or ui.edit_mode()
    end
    return m
end

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    return true
end

local function load_doc()
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/board.rml', {dp = true, model = m})
    if not doc then gear.log('bounty: ui/board.rml failed: ' .. tostring(err)) return end
    doc:on('#open-editor', 'click', gear.guard('editor', function() editor.open() end))
    doc:on('#open-editor2', 'click', gear.guard('editor', function() editor.open() end))
end

gear.on('draw', function(state)
    if not state or state.mode ~= 'game' or state.exclusive then return end
    if not doc then load_doc() end
    if doc then
        for k, v in pairs(snapshot()) do
            if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
        end
        doc:draw({layer = 'hud'})
    end
    if is_local() and mine then editor.draw(editor_hooks) end
end)

gear.keys.on('panel', function()
    board_open = not board_open
end)

gear.keys.on('editor', function()
    if is_local() then
        if editor.is_open() then editor.close() else editor.open() end
    end
end)

-- Test aid for bounty_selftest (it only answers the self test): ask for the state, or set the local bounties.
do
    gear.on('bounty.test', function(ctx)
        if ctx.op == 'set' and mine then
            mine.list = ctx.list
            refresh()
        elseif ctx.op == 'set_done' and mine then
            for _, b in ipairs(mine.list) do if b.id == ctx.id then b.done = true b.n = b.target mine.done_count = mine.done_count + 1 end end
            refresh()
        elseif ctx.op == 'start_custom' and mine then
            local d = customs.put(ctx.def)
            if d then editor_hooks.start(d) end
        elseif ctx.op == 'stop_custom' and mine then
            editor_hooks.stop(ctx.id)
        elseif ctx.op == 'drop' then
            ctx.running = true
            localgame.drop_item(ctx.spec, function(ok) ctx.running, ctx.ok = false, ok end)
        elseif ctx.op == 'fuzzy' then
            local r = gear.lookup.search('item', ctx.q, 40)
            ctx.items = {}
            for i, t in ipairs(r) do ctx.items[i] = t.name end
            ctx.creatures = require('creatures').options(ctx.q)
        elseif ctx.op == 'toast' then
            toast(ctx.title, unpack(ctx.lines or {}))
        elseif ctx.op == 'open_form' then
            editor.open_form(ctx.def and customs.find(ctx.def))
        elseif ctx.op == 'open_editor' then
            editor.open()
        elseif ctx.op == 'trigger_kill' and mine then
            for _, b in ipairs(mine:trigger_kill(customs.defs, localboard.words(ctx.name), 10, ctx.type)) do toast('Bounty started: ' .. b.title) end
            refresh()
        elseif ctx.op == 'save' then
            save_mine()
        end
        ctx.local_mode, ctx.payload, ctx.file = is_local(), board, mine_file
    end)
end
