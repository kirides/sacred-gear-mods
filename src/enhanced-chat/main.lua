-- Enhanced Chat: a chat window in place of the game's message lines at the top of the screen.
--
--   * Every line the game adds to its message list comes from gear.chat ('chat.line', and the session's history when
--     the mod loads): chat from other players (global, team, private) with the sender's name, the server's messages,
--     the game's own lines and the player's own. The window keeps the last `lines` of them and scrolls.
--   * While the window shows, gear.chat.replace_overlay keeps the game's own lines off the screen; they come back by
--     themselves when the window is hidden, the mod is switched off or stops with an error.
--   * Tabs: All, Global (global, team and your own lines), Private, System (the game's and the server's lines and
--     the drops); a tab that got a line since it was last open shows a dot. In a network game a dropdown narrows
--     every tab to one player.
--   * Colours: the game's own colour codes in a line (\c...\r) are kept; drops near the hero (gear.world.items_near,
--     twice a second, as the loot log does) become a line with the item's name in its label colour; resting the
--     cursor on such a line shows the game's tooltip of the item while it still exists.
--   * The window is a bare panel: the layout editor moves and resizes it. Its tabs and buttons are D-pad stops, the
--     line area scrolls with the D-pad and the right stick; the controller's mod menu shows / hides it.
local ui, S, W = gear.ui, gear.settings, gear.world
local chat = gear.chat

local TABS = {
    {id = 'all', label = 'All'},
    {id = 'global', label = 'Global'},
    {id = 'private', label = 'Private'},
    {id = 'system', label = 'System'},
}
local TAB_OF = {global = 'global', team = 'global', own = 'global', private = 'private',
                server = 'system', system = 'system', notice = 'system', loot = 'system'}
local RANK = {normal = 1, magic = 2, rare = 3, set = 4, unique = 5}
local LOOT_MIN = {magic = 2, rare = 3, set = 4, unique = 5}
local DIM, STAMP, TAB_H = 0xFFB8B8B8, 0xFF8C8C8C, 18
local SCAN = 0.5

local entries = {}          -- {kind, sender, runs, plain, stamp, item}, oldest first
local layout_cache = setmetatable({}, {__mode = 'k'})   -- entry -> {w, fs, rows}
local view = {tab = 1, player = 1, unread = {}, minimized = false, stick = true, new_below = 0, last_count = 0}
local loot = {seen = {}, baseline = true, t = 0, clock = 0}

local function setting(id, default)
    local ok, v = pcall(S.get, id)
    if ok and v ~= nil then return v end
    return default
end

local function stamp()
    return os.date('%H:%M')
end

---------------------------------------------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------------------------------------------
local function add_entry(e)
    entries[#entries + 1] = e
    local max = math.floor(setting('lines', 200))
    while #entries > max do table.remove(entries, 1) end
    local tab = TAB_OF[e.kind] or 'system'
    local open = TABS[view.tab].id
    -- a dot on the line's own tab when the open one does not show it
    for i, t in ipairs(TABS) do
        if open ~= 'all' and open ~= tab and t.id == tab then view.unread[i] = true end
    end
end

local function from_line(l)
    if l.channel == 0 then return end
    add_entry({kind = l.kind, sender = l.sender, runs = l.runs, plain = l.plain, stamp = stamp()})
end

-- The first line of the game's tooltip of an item, without its markup: its localized name.
local function item_name(item)
    local ok, text = pcall(ui.item_tooltip_text, item)
    if ok and type(text) == 'string' then
        local line = text:match('^[^\r\n]+')
        if line and chat then
            local _, plain = chat.segments(line)
            plain = plain:gsub('^%s+', ''):gsub('%s+$', '')
            if plain ~= '' and not plain:find('\\', 1, true) then return plain end
        end
    end
    return item.type_name or ('item ' .. tostring(item.type))
end

local function item_color(item)
    local c = W.item_color and W.item_color(item)
    if c then return c end
    if W.quality_color then return W.quality_color(item.quality or 'normal') end
    return 0xFFFFFFFF
end

local function add_drop(item)
    local name = item_name(item)
    local runs = {{text = 'Dropped: ', color = DIM}, {text = name, color = item_color(item)}}
    add_entry({kind = 'loot', runs = runs, plain = 'Dropped: ' .. name, stamp = stamp(), item = item.id})
end

local function scan_drops()
    local min = LOOT_MIN[setting('loot', 'rare')]
    local hero = W.hero()
    if not min or not hero then return end
    local x, y, layer = hero:position()
    if not x then return end
    local ok, near = pcall(W.items_near, x, y, setting('loot_radius', 25) * (W.TILE or 53.7), {layer = layer or 0, limit = 64})
    if not ok or type(near) ~= 'table' then return end
    for _, it in ipairs(near) do
        local seen = loot.seen[it.id]
        if not (seen and seen.type == it.type) then
            if not loot.baseline and not it.gold and (RANK[it.quality] or 1) >= min then add_drop(it) end
        end
        loot.seen[it.id] = {type = it.type, t = loot.clock}
    end
    loot.baseline = false
    for id, s in pairs(loot.seen) do
        if loot.clock - s.t > 600 then loot.seen[id] = nil end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------------------------------------------
local function players()
    local names, have = {'All players'}, {}
    local function add(n)
        if type(n) == 'string' and n ~= '' and not have[n] then have[n] = true; names[#names + 1] = n end
    end
    local ok, list = pcall(gear.mp.players)
    if ok and type(list) == 'table' then
        for _, p in ipairs(list) do if not p.is_local then add(p.name) end end
    end
    for _, e in ipairs(entries) do add(e.sender) end
    return names
end

local function network_game()
    local ok, mode = pcall(gear.mp.mode)
    return ok and mode ~= nil and mode ~= 'single'
end

local function shown(e, player)
    local tab = TABS[view.tab].id
    if tab ~= 'all' and (TAB_OF[e.kind] or 'system') ~= tab then return false end
    if player and e.sender ~= player then return false end
    return true
end

---------------------------------------------------------------------------------------------------------------
-- Layout of a line: runs broken into rows that fit the width (at spaces; a word wider than the row gets its own)
---------------------------------------------------------------------------------------------------------------
local function measure(text, fs)
    local w = ui.text_size(text, {size = fs})
    return w or (#text * fs * 0.5)
end

local function lay_out(e, width, fs, stamps)
    local c = layout_cache[e]
    if c and c.w == width and c.fs == fs and c.stamps == stamps then return c.rows end
    local rows, row, x = {}, {}, 0
    local function put(text, color)
        local tw = measure(text, fs)
        if x > 0 and x + tw > width and text:find('%S') then
            rows[#rows + 1] = row
            row, x = {}, 0
            text = text:gsub('^%s+', '')
            tw = measure(text, fs)
        end
        row[#row + 1] = {text = text, x = x, color = color}
        x = x + tw
    end
    if stamps and e.stamp then put('[' .. e.stamp .. '] ', STAMP) end
    for _, r in ipairs(e.runs or {}) do
        for piece in r.text:gmatch('%s*%S+%s*') do put(piece, r.color) end
        if not r.text:find('%S') and r.text ~= '' then put(r.text, r.color) end
    end
    rows[#rows + 1] = row
    layout_cache[e] = {w = width, fs = fs, stamps = stamps, rows = rows}
    return rows
end

---------------------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------------------
local function tab_label(i)
    return TABS[i].label .. (view.unread[i] and ' \u{2022}' or '')
end

local function draw_tabs(x, y, w)
    local cx = x + 2
    view.tab_rects = {}
    for i = 1, #TABS do
        local label = tab_label(i)
        local bw = math.floor(measure(label, 12) + 14)
        view.tab_rects[i] = {x = cx, y = y, w = bw, h = TAB_H}
        if ui.button('tab' .. i, cx, y, bw, TAB_H, label, {tooltip = i == 1 and 'Every line' or nil}) then
            view.tab = i
            view.unread[i] = nil
            view.stick = true
        end
        if i == view.tab then ui.rect(cx + 2, y + TAB_H - 2, bw - 4, 2, ui.COLORS and ui.COLORS.accent or 0xFFE0C060) end
        cx = cx + bw + 2
    end
    local right = x + w - 2
    if ui.button('min', right - TAB_H, y, TAB_H, TAB_H, view.minimized and '+' or '-',
        {tooltip = view.minimized and 'Show the lines' or 'Only the tabs'}) then
        view.minimized = not view.minimized
    end
    right = right - TAB_H - 4
    if network_game() and not view.minimized then
        local names = players()
        if view.player > #names then view.player = 1 end
        local dw = math.min(130, right - cx - 4)
        if dw >= 70 then
            local _, i = ui.dropdown('player', right - dw, y, dw, names, view.player, {tooltip = 'Only the lines of this player'})
            view.player = i
            view.player_name = i > 1 and names[i] or nil
        end
    else
        view.player, view.player_name = 1, nil
    end
end

local function draw_lines(x, y, w, h, fs)
    local stamps = setting('timestamps', false) == true
    local row_h = math.floor(fs * 1.35 + 0.5)
    local list = {}
    for _, e in ipairs(entries) do
        if shown(e, view.player_name) then list[#list + 1] = e end
    end
    view.shown = #list
    -- follow the newest line unless the player scrolled up
    -- (scroll_begin clamps to the last frame's height and adds the wheel to the offset: set the last bottom, every frame)
    if view.stick then ui.scroll_to('lines', view.max or 0) end
    if #list ~= view.last_count then
        if not view.stick then view.new_below = view.new_below + math.max(0, #list - view.last_count) end
        view.last_count = #list
    end
    local area = ui.scroll_begin('lines', x, y, w, h, {step = row_h})
    view.lines_rect = {x = x, y = y, w = w, h = h}
    local inner = (area.w or w) - 4
    local cy, top, bottom = 0, area.offset or 0, (area.offset or 0) + (area.h or h)
    local mx, my = ui.mouse()
    local hover_item
    for _, e in ipairs(list) do
        local rows = lay_out(e, inner, fs, stamps)
        local eh = #rows * row_h
        if cy + eh >= top and cy <= bottom then
            for r, row in ipairs(rows) do
                local ry = cy + (r - 1) * row_h
                if ry + row_h >= top and ry <= bottom then
                    for _, piece in ipairs(row) do
                        ui.text(piece.text, area.content_x + 2 + piece.x, area.content_y + ry, {size = fs, color = piece.color, shadow = true})
                    end
                end
            end
            if e.item and mx >= area.x and mx < area.x + area.w and my >= area.content_y + cy and my < area.content_y + cy + eh
                and my >= area.y and my < area.y + area.h then
                hover_item = e.item
            end
        end
        cy = cy + eh
    end
    local o, m = ui.scroll_end(cy)
    -- scrolled up by the player: stop following; back at the bottom: follow again
    if o < (view.max or 0) - 2 then view.stick = false elseif o >= m - 2 then view.stick = true end
    view.max, view.offset = m, o
    if view.stick then view.new_below = 0 end
    view.newer_rect = nil
    if view.new_below > 0 then
        local label = ('%d new \u{25BC}'):format(view.new_below)
        local bw = math.floor(measure(label, 12) + 14)
        view.newer_rect = {x = x + w - bw - 16, y = y + h - TAB_H - 2, w = bw, h = TAB_H}
        if ui.button('newer', x + w - bw - 16, y + h - TAB_H - 2, bw, TAB_H, label, {tooltip = 'To the newest line'}) then
            ui.scroll_to('lines', 1e9)
            view.stick, view.new_below = true, 0
        end
    end
    if hover_item then
        -- placed beside the cursor with the size the tooltip took last time (the game lays it out when it draws)
        local tx, ty = ui.tooltip_rect(view.tip_w or 260, view.tip_h or 160)
        local shown_ok, tw, th = ui.item_tooltip(hover_item, tx, ty)
        if shown_ok and type(tw) == 'number' and tw > 0 then view.tip_w, view.tip_h = tw, th end
    end
end

local function draw_window()
    local fs = math.floor(setting('font_size', 13))
    local p = ui.panel('chat', 'Chat', 8, 420, 420, 200, {bare = true, resizable = true, min_width = 240, min_height = 80})
    if not p.open then return end
    local x, y, w, h = p.x, p.y, p.w, p.h
    local alpha = math.floor(setting('opacity', 140))
    if view.minimized then
        if alpha > 0 then ui.rect(x, y, w, TAB_H + 4, ui.rgba(0, 0, 0, alpha)) end
        draw_tabs(x, y + 2, w)
        return
    end
    if alpha > 0 then ui.rect(x, y, w, h, ui.rgba(0, 0, 0, alpha)) end
    draw_tabs(x, y + 2, w)
    draw_lines(x + 2, y + TAB_H + 6, w - 4, h - TAB_H - 8, fs)
end

local function visible() return setting('visible', true) ~= false end

local function toggle() S.set('visible', not visible()) end

local function next_tab()
    view.tab = view.tab % #TABS + 1
    view.unread[view.tab] = nil
    view.stick = true
end

---------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------
if not chat then
    gear.log('Enhanced Chat needs a Sacred Gear with gear.chat (the chat lines); it stays idle')
    return
end

for _, l in ipairs(chat.history()) do from_line(l) end
view.unread = {}

gear.on('chat.line', from_line)

gear.on('session.start', function()
    loot.seen, loot.baseline, loot.clock = {}, true, 0
end)

gear.on('frame', function(dt)
    dt = tonumber(dt) or 0
    if dt < 0 or dt > 5 then dt = 0 end
    loot.clock = loot.clock + dt
    loot.t = loot.t + dt
    if loot.t >= SCAN then loot.t = 0; scan_drops() end
end)

gear.on('settings.changed', function(id)
    if id == 'lines' then
        local max = math.floor(setting('lines', 200))
        while #entries > max do table.remove(entries, 1) end
    end
end)

gear.on('draw', function(state)
    if type(state) ~= 'table' or state.mode ~= 'game' or not visible() then return end
    if setting('replace_overlay', true) ~= false then chat.replace_overlay() end
    if not state.exclusive then draw_window() end
end)

-- For the self test (enhanced-chat_selftest): the window's state, and `set_visible` / `tab` to change it.
gear.on('enhanced-chat.query', function(out)
    if type(out) ~= 'table' then return end
    if out.set_visible ~= nil then S.set('visible', out.set_visible and true or false) end
    if out.tab then view.tab = out.tab; view.unread[view.tab] = nil end
    if out.set_player ~= nil then
        view.player = 1
        for i, n in ipairs(players()) do if n == out.set_player then view.player = i end end
        view.player_name = view.player > 1 and out.set_player or nil
    end
    out.players = players()
    out.network = network_game()
    out.visible, out.tab, out.entries, out.shown, out.minimized = visible(), view.tab, #entries, view.shown or 0, view.minimized
    out.last = entries[#entries]
    out.tabs = view.tab_rects
    out.lines = view.lines_rect
    out.newer = view.newer_rect
    out.new_below = view.new_below
    out.scroll_offset, out.scroll_max, out.following = view.offset or 0, view.max or 0, view.stick
    out.unread = view.unread
end)

gear.keys.on('toggle', toggle)
gear.keys.on('next_tab', next_tab)
if ui.menu_item then
    pcall(ui.menu_item, 'chat', 'Chat window: show / hide', toggle)
    pcall(ui.menu_item, 'chat_tab', 'Chat window: next tab', next_tab)
end
