-- World events: a movable progress bar for the realm-wide goal the game server runs (the server script world_events.lua,
-- see README.md). The server pushes the state over the custom net channel 'worldevents:state'; this mod only displays it.
-- It binds no key and has no buttons: the bar is moved in the layout editor (hold Alt, "Edit layout"), its settings are on
-- its page of the Mods screen, and the controller's mod menu has an entry that switches "always" and "only while Alt".
local core = require('core')
local ui, S = gear.ui, gear.settings

local CHANNEL = 'worldevents:state'
local HELLO_EVERY = 30      -- seconds: asks the server for the state again (a lost push, a server that restarted)

local model = core.new()
local channel
local last_hello = -1e9

local function ensure_channel()
    if channel then return channel end
    local net = gear.net
    if not (net and net.channel) then return nil end
    local ch, err = net.channel(CHANNEL)
    if not ch then
        gear.log('world-events: no channel (' .. tostring(err) .. ')')
        return nil
    end
    ch:on(function(from, payload)
        -- only the server pushes states (slot 0); a message from another player is ignored
        if from and from.slot == 0 and type(payload) == 'table' then
            model:receive(payload, gear.time())
        end
    end)
    channel = ch
    return ch
end

local function hello(force)
    local now = gear.time()
    if not force and now - last_hello < HELLO_EVERY then return end
    local net = gear.net
    if not (net and net.supported and net.supported()) then return end
    local ch = ensure_channel()
    if not ch then return end
    last_hello = now
    ch:send({hello = 1, v = 1}, 'server')
end

ensure_channel()

gear.on('net_caps', function() hello(true) end)
gear.on('session.start', function() model:reset(); hello(true) end)
gear.on('session.stop', function() model:reset(); last_hello = -1e9 end)
gear.on('frame', function() hello(false) end)

-- Other mods (and tests) can feed a state: gear.emit('world-events.state', {st = 'active', ...}).
gear.on('world-events.state', function(payload) model:receive(payload, gear.time()) end)

---------------------------------------------------------------------------------------------------------------
-- the bar
---------------------------------------------------------------------------------------------------------------
local W, H = 300, 86                -- the panel's default size (layout units); it can be resized in the layout editor
local X, Y = 362, 48                -- top centre, clear of the minimap and the action bar

local COLOR = {
    back = 0xFF14100B, edge = 0xFF5A4A36, fill = 0xFFD9A441, fill_late = 0xFFD2603A, fill_won = 0xFF58B45A,
    fill_failed = 0xFF8A4A4A, text = 0xFFEFE6D6, dim = 0xFFB4A78F, good = 0xFF8FD08F, shadow = 0xD0000000,
}

local function fill_color(view)
    if view.kind == 'won' then return COLOR.fill_won end
    if view.kind == 'failed' then return COLOR.fill_failed end
    return view.late and COLOR.fill_late or COLOR.fill
end

local function draw_bar(view)
    local panel = ui.panel('bar', view.title ~= '' and view.title or 'World event', X, Y, W, H,
        {closable = false, draggable = true, resizable = true, min_width = 220, min_height = 70, passive = true})
    if not panel or not panel.open then return end
    local x, y = panel.content_x or 0, panel.content_y or 0
    local w = panel.content_w or ((panel.w or W) - 12)
    -- the goal on the left, the time left on the right
    ui.text(view.text, x, y, {size = 12, color = COLOR.text, shadow = true, width = w - 56, height = 16})
    if view.time_text ~= '' then
        ui.text(view.time_text, x, y, {size = 12, color = view.late and COLOR.fill_late or COLOR.dim, shadow = true, width = w,
            align = 'right', height = 16})
    end
    -- the bar with the percentage and the counts in it
    local by, bh = y + 20, 18
    ui.rect(x, by, w, bh, COLOR.back)
    ui.rect(x, by, math.floor(w * view.frac + 0.5), bh, fill_color(view))
    ui.frame(x, by, w, bh, COLOR.edge, 1)
    ui.text(('%d%%   %s'):format(view.percent, view.count_text), x, by, {
        size = 12, bold = true, color = 0xFFFFFFFF, outline = true, width = w, height = bh, align = 'center', valign = 'middle'})
    -- your share
    if view.mine_text ~= '' then
        ui.text(view.mine_text, x, by + bh + 4, {size = 11, color = (view.qualifies == false) and COLOR.dim or COLOR.good,
            shadow = true, width = w, height = 14})
    end
end

ui.show_panel('bar', true)

gear.on('draw', function(state)
    if state.mode ~= 'game' or state.exclusive then return end
    local editing = ui.edit_mode()
    local view = model:view(gear.time(), {area = S.get('area'), results = S.get('results'), preview = editing})
    if not view then return end
    if not editing and S.get('visibility') == 'alt' and not state.show_text then return end
    draw_bar(view)
end)

-- The controller's mod menu: the same switch as the setting, for players without a keyboard.
if ui.menu_item then
    ui.menu_item('visibility', 'World events: bar always / only with Alt', function()
        S.set('visibility', S.get('visibility') == 'alt' and 'always' or 'alt')
    end)
end

local M = {model = model}
return M
