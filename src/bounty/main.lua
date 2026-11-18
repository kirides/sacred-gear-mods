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

local cfg = gear.config
local ui, net = gear.ui, gear.net

local localboard = require('localboard')
local localgame = require('localgame')

local channel = net and net.channel('bounty:state')
local board = nil          -- the last payload (the server's, or the local board's)
local received = 0         -- gear.time() when it arrived
local asked = -1e9
local is_local          -- defined below: whether this is the single player board

local GOLD, GREEN, GREY = 0xFFFFD780, 0xFF80FF80, 0xFFB0B0B0

local function valid(payload)
    if type(payload) ~= 'table' or payload.v ~= 1 or type(payload.bounties) ~= 'table' then return false end
    for _, b in ipairs(payload.bounties) do
        if type(b) ~= 'table' or type(b.title) ~= 'string' or type(b.target) ~= 'number' then return false end
    end
    return true
end

if channel then
    channel:on(function(from, payload)
        if valid(payload) then board, received = payload, gear.time() end
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
    ui.show_panel('board', false)       -- closed until Ctrl+J
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
local toasts, now = {}, 0

is_local = function()
    return gear.settings.get('own_board') ~= false and not (gear.mp and gear.mp.active())
end

local function toast(title, ...)
    local lines = {}
    for i = 1, select('#', ...) do
        local line = select(i, ...)
        if line and line ~= '' then lines[#lines + 1] = line end
    end
    toasts[#toasts + 1] = {title = title, lines = lines, born = now}
    while #toasts > 4 do table.remove(toasts, 1) end
end

local function rng(lo, hi) return math.random(lo, hi) end

local function file_for(name)
    local clean = name:gsub('[^%w]', '_')
    local h = 2166136261
    for i = 1, #name do h = (h ~ name:byte(i)) * 16777619 % 4294967296 end
    return ('board_%s_%08x.json'):format(clean:sub(1, 24), h)
end

local function refresh()
    if mine then board, received = mine:payload(), gear.time() end
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
    local posted = mine:fill(level, #mine.list == 0)
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
    local hero = gear.world.hero()
    local parts = {}
    if (b.gold or 0) > 0 and localgame.gold(b.gold) then parts[#parts + 1] = b.gold .. ' gold' end
    if b.item then
        localgame.drop_item(b.item, function(ok)
            if ok then toast('Bounty reward', 'An item dropped at your feet') end
        end)
        parts[#parts + 1] = 'an item'
    end
    toast('Bounty complete: ' .. b.title, #parts > 0 and ('Reward: ' .. table.concat(parts, ' and ')) or nil)
    return hero
end

localgame.on_kill(function(type_name)
    if not mine then return end
    local hero = gear.world.hero()
    local level = hero and hero:level() or 1
    for _, b in ipairs(mine:kill(localboard.words(type_name), level)) do reward(b) end
    dirty = true
    refresh()
    if gear.time() - last_save > 5 then save_mine() end
end)

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
    local posted = mine:fill(hero:level() or 1, false)
    for _, b in ipairs(gone) do
        if not b.done then toast('Bounty ended', b.title) end
    end
    for _, b in ipairs(posted) do toast('New bounty', b.title, b.text) end
    if #gone > 0 or #posted > 0 then dirty = true end
    refresh()
    if dirty and t - last_save > 20 then save_mine() end
end)

gear.on('frame', function(dt) now = now + (dt or 0) end)
gear.on('unload', function() if mine then save_mine() end end)

local function draw_toasts()
    local life = 6
    local y = 14
    local keep = {}
    local TW = 340
    for _, t in ipairs(toasts) do
        local age = now - t.born
        if age < life then
            keep[#keep + 1] = t
            local alpha = math.max(0, math.min(1, (life - age) / 0.6, age / 0.2 + 0.2))
            local x = 512 - TW / 2
            local th = 24 + 14 * #t.lines
            ui.rect(x, y, TW, th, ui.rgba(0, 0, 0, math.floor(190 * alpha)), {layer = 'top'})
            ui.frame(x, y, TW, th, ui.rgba(200, 170, 90, math.floor(230 * alpha)), 1, {layer = 'top'})
            ui.text(t.title, x + 10, y + 5, {color = ui.rgba(240, 200, 110, math.floor(255 * alpha)), bold = true, layer = 'top'})
            local ly = y + 24
            for _, line in ipairs(t.lines) do
                ui.text(line, x + 10, ly, {color = ui.rgba(255, 255, 255, math.floor(230 * alpha)), size = 12, layer = 'top'})
                ly = ly + 14
            end
            y = y + th + 6
        end
    end
    toasts = keep
end

local function time_text(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then return ('%dh %02dm'):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    if seconds >= 60 then return ('%dm %02ds'):format(math.floor(seconds / 60), seconds % 60) end
    return seconds .. 's'
end

local function left_of(b) return (b.left or 0) - (gear.time() - received) end

-- One bounty at (x, y) in a width of w; returns its height.
local ROW = 58
local function row(b, x, y, w)
    local done = b.done == true
    local n = math.min(b.n or 0, b.target)
    ui.text(b.title, x, y, {color = done and GREEN or GOLD, size = 15, bold = true})
    ui.text(done and 'done' or time_text(left_of(b)), x, y, {width = w, align = 'right', color = done and GREEN or GREY})
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
    local p = ui.panel('board', 'Bounty board (Ctrl+J)', 300, 70, 400, 320, {resizable = true, min_width = 300, min_height = 160})
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
        return
    end
    local foot = own and 14 or 0
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
    draw_toasts()
end)

gear.keys.on('panel', function()
    ui.show_panel('board', not ui.panel_open('board'))
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
        elseif ctx.op == 'save' then
            save_mine()
        end
        ctx.local_mode, ctx.payload, ctx.file = is_local(), board, mine_file
    end)
end
