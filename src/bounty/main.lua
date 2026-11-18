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
ui.show_panel('board', false)       -- closed until Ctrl+J (then the open / closed state is kept)
if ui.persist_panel then ui.persist_panel('editor', false) end

local localboard = require('localboard')
local localgame = require('localgame')
local customs = require('customs')
local hooks = require('hooks')
local editor = require('editor')

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
gear.on('session.start', function()
    if mine then close_mine() end
    board = nil
    ask(true)
    ui.show_panel('editor', false)
end)
gear.on('session.stop', function()
    if mine then close_mine() end
    board = nil
end)
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

local function save_mine()
    if not mine or not mine_file then return end
    local ok, err = gear.save(mine_file, gear.json.encode(mine:save_table()))
    if ok then dirty, last_save = false, gear.time() else print('bounty: cannot save ' .. mine_file .. ': ' .. tostring(err)) end
end

local function open_mine()
    local hero = gear.world.hero()
    local name = hero and hero:name()
    if not name then return end
    mine_hero, mine_file = name, file_for(name)
    local text = gear.read(mine_file)
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

localgame.on_kill(function(type_name)
    if not mine then return end
    local hero = gear.world.hero()
    local level = hero and hero:level() or 1
    local words = localboard.words(type_name)
    local finished = mine:kill(words, level)
    local started = mine:trigger_kill(customs.defs, words, level)
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

customs.load()

gear.every(0.25, function()
    if is_local() and mine then localgame.poll() end
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

local time_text = gear.fmt.span

local function left_of(b) return (b.left or 0) - (gear.time() - received) end

-- One bounty at (x, y) in a width of w; returns its height.
local ROW = 58
local function row(b, x, y, w)
    local done = b.done == true
    local n = math.min(b.n or 0, b.target)
    ui.text(b.title, x, y, {color = done and GREEN or GOLD, size = 15, bold = true})
    ui.text(done and 'done' or (b.endless and 'no limit' or time_text(left_of(b))), x, y, {width = w, align = 'right', color = done and GREEN or GREY})
    ui.text((b.text or '') .. (b.level and b.level > 1 and (' (level ' .. b.level .. '+)') or ''),
        x, y + 17, {color = 0xFFE0E0E0, size = 12})
    local by = y + 33
    ui.rect(x, by, w, 10, ui.rgba(0, 0, 0, 160))
    local frac = b.target > 0 and n / b.target or 0
    if frac > 0 then ui.rect(x, by, math.max(1, math.floor(w * frac)), 10, done and ui.rgba(80, 200, 100, 220) or ui.rgba(210, 160, 60, 220)) end
    ui.frame(x, by, w, 10, ui.rgba(200, 170, 90, 160), 1)
    ui.text(('%d / %d'):format(n, b.target), x, by - 2, {width = w, align = 'center', size = 11, shadow = true})
    ui.text('Reward: ' .. tostring(b.reward or '?'), x, by + 12, {color = GREY, size = 11})
    return ROW
end

local function panel()
    local p = ui.panel('board', 'Bounty board' .. key_hint('panel'), 300, 70, 400, 320, {resizable = true, min_width = 300, min_height = 160})
    if not p.open then return end
    local x, y, w, h = p.content_x, p.content_y, p.content_w, p.content_h
    local own = is_local()
    if not own and (not channel or not net.supported()) then
        local lines = ui.text_wrap('This server has no bounty board (it needs the Sacred Gear game server with bounty_board.lua).', w, {size = 12})
        for i, line in ipairs(lines) do ui.text(line, x, y + (i - 1) * 15, {color = GREY, size = 12}) end
        return
    end
    if not board then
        ui.text(own and 'Looking for your hero...' or 'Waiting for the server...', x, y, {color = GREY})
        return
    end
    if #board.bounties == 0 then
        ui.text('The board is empty.', x, y, {color = GREY})
        if own and ui.button('open-editor', x, y + 24, 110, 20, 'Editor...') then editor.open() end
        return
    end
    local foot = own and 20 or 0
    local area = ui.scroll_begin('bounty-list', x, y, w, h - 4 - foot)
    local cy = area.content_y
    for _, b in ipairs(board.bounties) do
        row(b, area.content_x, cy, area.w - 4)
        cy = cy + ROW + 6
    end
    ui.scroll_end(cy - area.content_y)
    if own then
        ui.text(('Single player: your own board. Finished so far: %d'):format(board.done_count or 0), x, y + h - 14,
            {color = GREY, size = 11})
        if ui.button('open-editor', x + w - 110, y + h - 18, 110, 18, 'Editor...', {tooltip = 'Make your own bounties, start and stop them'}) then
            editor.open()
        end
    end
end

local function tracker()
    if not gear.settings.get('tracker') or not board then return end
    local lines = {}
    for _, b in ipairs(board.bounties) do
        if not b.done then lines[#lines + 1] = b end
    end
    local editing = ui.edit_mode()
    if #lines == 0 and not editing then return end
    -- A bare panel (no window), so the layout editor lists it and the player can move it; cfg.tracker_x / _y are only the default.
    local h = 18 + math.max(1, #lines) * 14
    local p = ui.panel('tracker', 'Bounty tracker', cfg.tracker_x, cfg.tracker_y, 220, h, {bare = true})
    local x, y = p.x, p.y
    ui.text('Bounties', x, y, {color = GOLD, size = 13, bold = true, shadow = true})
    for i, b in ipairs(lines) do
        ui.text(('%s  %d/%d'):format(b.title, math.min(b.n or 0, b.target), b.target), x, y + 4 + i * 14,
            {color = 0xFFE0E0E0, size = 12, shadow = true})
    end
end

gear.on('draw', function(state)
    if not state or state.mode ~= 'game' or state.exclusive then return end
    tracker()
    panel()
    if is_local() and mine then editor.draw(editor_hooks) end
end)

gear.keys.on('panel', function()
    ui.toggle_panel('board')
end)

gear.keys.on('editor', function()
    if is_local() then
        if ui.panel_open('editor') then ui.show_panel('editor', false) else editor.open() end
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
            for _, b in ipairs(mine:trigger_kill(customs.defs, localboard.words(ctx.name), 10)) do toast('Bounty started: ' .. b.title) end
            refresh()
        elseif ctx.op == 'save' then
            save_mine()
        end
        ctx.local_mode, ctx.payload, ctx.file = is_local(), board, mine_file
    end)
end
