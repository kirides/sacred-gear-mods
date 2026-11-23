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
--   * The game's text codes in a line (see parse_codes): colours (\c \w \d), \r, \n and inline UI images (\g); drops near the hero (gear.world.items_near,
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
-- The collapsed state (tabs only) is kept across starts (state.json of the mod's folder).
local state_file = gear.store.file('state.json', {minimized = false}, {every = 5})
view.minimized = type(state_file.data) == 'table' and state_file.data.minimized == true

local function setting(id, default) return S.get(id, default) end

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

---------------------------------------------------------------------------------------------------------------
-- The game's text codes (the parser of its fonts, Sacred.exe 0x650c30 / 0x650aa0, and the drawing loop of cFontTTF2 0x64e9c0).
-- A backslash and a letter start a code; a code that does not fit (too short, other characters) stays visible as text:
--   \cAARRGGBB  the colour of the letters that follow       \wAARRGGBB  the same colour code (the game also marks the text as "wide")
--   \dAARRGGBB  a colour that applies even where the line says no colour codes (a name plate)
--   \r          back to the line's own colour               \n          nothing (the game takes the code and draws nothing for it)
--   \gAARRGGBBIIIIIIII  a UI image (gear:image/I, I = 8 hex digits, 1 to 1885) tinted with AARRGGBB, drawn in the line like a letter
-- The 8 or 16 characters after the letter are hex digits or spaces (spaces count as the end of the number).
---------------------------------------------------------------------------------------------------------------
local MAX_IMAGE = 1885

-- 8 characters of a code as a number: the hex digits up to the first space (the game reads them with sscanf %x)
local function code_number(s)
    local digits = s:match('^%x*')
    return digits ~= '' and tonumber(digits, 16) or 0
end

-- text, the line's colour (ARGB) -> runs {text, color} | {icon = image id, color = tint}, and the plain text (icons as nothing)
local function parse_codes(text, base)
    local runs, plain, cur, buf = {}, {}, base, {}
    local function flush()
        if #buf > 0 then
            local s, last = table.concat(buf), runs[#runs]
            if last and last.text and last.color == cur then last.text = last.text .. s else runs[#runs + 1] = {text = s, color = cur} end
            plain[#plain + 1] = s
            buf = {}
        end
    end
    local i, n = 1, #text
    while i <= n do
        local b = text:find('\\', i, true)
        if not b then buf[#buf + 1] = text:sub(i) break end
        if b > i then buf[#buf + 1] = text:sub(i, b - 1) end
        local code = text:sub(b + 1, b + 1)
        local arg8 = (code == 'c' or code == 'w' or code == 'd') and text:match('^[%x ]+', b + 2)
        if arg8 and #arg8 >= 8 then
            flush()
            cur = code_number(text:sub(b + 2, b + 9))
            i = b + 10
        elseif code == 'r' then
            flush() cur = base i = b + 2
        elseif code == 'n' then
            i = b + 2
        elseif code == 'g' and #(text:match('^[%x ]+', b + 2) or '') >= 16 then
            flush()
            local id = code_number(text:sub(b + 10, b + 17))
            if id > MAX_IMAGE then id = 205 end        -- the game's stand-in for an image number it does not have
            if id >= 1 then runs[#runs + 1] = {icon = id, color = code_number(text:sub(b + 2, b + 9))} end
            i = b + 18
        else
            buf[#buf + 1] = '\\' i = b + 1
        end
    end
    flush()
    return runs, table.concat(plain)
end

local function from_line(l)
    if l.channel == 0 then return end
    local runs, plain = parse_codes(l.text or '', l.color or 0xFFFFFFFF)
    add_entry({kind = l.kind, sender = l.sender, runs = runs, plain = plain, stamp = stamp()})
end

-- What to show for an item whose tooltip gave no name: the localized type name, the internal one on an older Gear.
local function type_label(it)
    local ok, n = pcall(function() return gear.data.object_types:label(it.type) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return it.type_name or ('item ' .. tostring(it.type))
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
    return type_label(item)
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
-- The window: ui/chat.rml (the game theme)
---------------------------------------------------------------------------------------------------------------
-- A model of ready-made lines (runs with their colours), rebuilt when the entries, the tab or the filter change; the document wraps
-- and scrolls them. The list sticks to the newest line (element:scroll('end')) until the player scrolls up; "N new" brings it back.
local doc
local last = {}
local sig                    -- what the lines were built from
local dd_open = false
local line_items = {}        -- line element id -> item object id (a drop: the game's tooltip while the cursor rests on it)
local hover_item

local function css_color(argb)
    argb = argb or 0xFFFFFFFF
    return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
end

local function tab_label(i)
    return TABS[i].label .. (view.unread[i] and ' \u{2022}' or '')
end

local function lines_model()
    local stamps = setting('timestamps', false) == true
    local out = {}
    line_items = {}
    for i, e in ipairs(entries) do
        if shown(e, view.player_name) then
            local id = 'L' .. i
            local runs = {}
            if stamps and e.stamp then runs[1] = {t = '[' .. e.stamp .. '] ', c = css_color(STAMP)} end
            for _, r in ipairs(e.runs or {}) do
                if r.icon then
                    runs[#runs + 1] = {t = '', c = '#ffffffff', ic = true, deco = ('image(gear:image/%d?dp contain)'):format(r.icon), tint = css_color(r.color)}
                else
                    runs[#runs + 1] = {t = r.text, c = css_color(r.color), ic = false, deco = 'none', tint = '#ffffffff'}
                end
            end
            if e.item then line_items[id] = e.item end
            out[#out + 1] = {id = id, item = e.item ~= nil, runs = runs}
        end
    end
    view.shown = #out
    return out
end

local function snapshot()
    local fs = math.floor(setting('font_size', 13))
    local names = network_game() and not view.minimized and players() or nil
    if names then
        if view.player > #names then view.player = 1 end
        view.player_name = view.player > 1 and names[view.player] or nil
    else
        view.player, view.player_name = 1, nil
    end
    local width = math.floor(setting('window_width', 420))
    local height = math.floor(setting('window_height', 200))
    local m = {
        open = true, minimized = view.minimized, fs = fs .. 'dp', bg = ('#000000%02x'):format(math.floor(setting('opacity', 140))),
        box_h = (view.minimized and 24 or height) .. 'dp', box_w = width .. 'dp',
        min_label = view.minimized and '+' or '-', min_tip = view.minimized and 'Show the lines' or 'Only the tabs',
        tabs = {}, show_player = names ~= nil, player_label = view.player_name or 'All players',
        dd_open = dd_open, players = {},
        lines = last.lines or {}, new_label = view.new_below > 0 and ('%d new \u{25BC}'):format(view.new_below) or '',
    }
    if names then
        for i, name in ipairs(names) do m.players[i] = {id = 'player-' .. i, label = name, on = i == view.player} end
    end
    for i = 1, #TABS do m.tabs[i] = {id = 'tab' .. i, label = tab_label(i), on = i == view.tab} end
    local s = table.concat({#entries, tostring(entries[#entries]), view.tab, tostring(view.player_name), tostring(setting('timestamps', false))}, '|')
    if s ~= sig then
        sig = s
        m.lines = lines_model()
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
    sig = nil
    local m = snapshot()
    last = m
    local err
    doc, err = ui.rml.load('ui/chat.rml', {dp = true, model = m})
    if not doc then gear.log('Enhanced Chat: ui/chat.rml failed: ' .. tostring(err)) return end
    doc:style('#chat', 'width', m.box_w)
    local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
    on('.tab', function(e)
        local id = tostring(e.current)
        local i = tonumber(id:match('^tab(%d+)$'))
        if i then
            view.tab = i
            view.unread[i] = nil
            view.stick, view.content_h = true, nil
        elseif id == 'min' then
            view.minimized = not view.minimized
            state_file.data.minimized = view.minimized
            state_file:changed()
        elseif id == 'player' then
            dd_open = not dd_open
        elseif id == 'newer' then
            view.stick, view.new_below, view.content_h = true, 0, nil
        end
    end)
    on('.chat-ddlist .opt', function(e)
        local i = tonumber(tostring(e.current):match('^player%-([%d]+)$'))
        local names = players()
        if i and names[i] then
            view.player = i
            view.player_name = i > 1 and names[i] or nil
            view.stick = true
        end
        dd_open = false
    end)
    doc:on('.line', 'mouseover', function(e) hover_item = line_items[tostring(e.current)] end)
    doc:on('.line', 'mouseout', function() hover_item = nil end)
end

local function draw_window()
    if not doc then load_doc() end
    if not doc then return end
    local m = snapshot()
    for k, v in pairs(m) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    if m.box_w ~= last.applied_w then
        last.applied_w = m.box_w
        doc:style('#chat', 'width', m.box_w)
    end
    -- follow the newest line unless the player scrolled up
    local list = doc:query('#lines')
    if list and not view.minimized then
        local lines_before = view.shown
        if view.stick then list:scroll('end') end
        if lines_before ~= view.last_count then
            if not view.stick then view.new_below = view.new_below + math.max(0, lines_before - view.last_count) end
            view.last_count = lines_before
        end
    end
    doc:draw({layer = 'hud'})
    list = doc:query('#lines')
    if list and not view.minimized then
        local top, height, client = list:scroll()
        if top then
            local bottom = math.max(0, height - client)
            if view.stick and view.content_h ~= height then
                -- the content grew (or was rebuilt) this frame: stay with the newest line, this is not the player scrolling
                top = list:scroll('end') or top
                bottom = math.max(0, height - client)
            elseif top < bottom - 2 then
                view.stick = false
            elseif top >= bottom - 2 then
                view.stick = true
            end
            view.content_h = height
            view.max, view.offset = bottom, top
            if view.stick then view.new_below = 0 end
        end
    end
    if hover_item and not view.minimized then
        -- placed beside the cursor with the size the tooltip took last time (the game lays it out when it draws)
        local tx, ty = ui.tooltip_rect(view.tip_w or 260, view.tip_h or 160)
        local shown_ok, tw, th = ui.item_tooltip(hover_item, tx, ty)
        if shown_ok and type(tw) == 'number' and tw > 0 then view.tip_w, view.tip_h = tw, th end
    end
end

local function rect_of(sel)
    local e = doc and doc:query(sel)
    return e and e:rect() or nil
end

local function visible() return setting('visible', true) ~= false end

-- 'Hide in Singleplayer' (on by default): no window in a single player game, the game shows its own lines there.
local function hidden_here() return setting('hide_in_singleplayer', true) ~= false and not network_game() end

-- Whether the window is shown in this game at all.
local function active() return visible() and not hidden_here() end

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
    if type(state) ~= 'table' or state.mode ~= 'game' or not active() then return end
    if setting('replace_overlay', true) ~= false then chat.replace_overlay() end
    if not state.exclusive then draw_window() end
end)

-- For the self test (enhanced-chat_selftest): the window's state, and `set_visible` / `tab` to change it.
gear.on('enhanced-chat.query', function(out)
    if type(out) ~= 'table' then return end
    out.parse = parse_codes      -- for the self test
    if out.set_visible ~= nil then S.set('visible', out.set_visible and true or false) end
    if out.set_hide_sp ~= nil then S.set('hide_in_singleplayer', out.set_hide_sp and true or false) end
    if out.tab then view.tab = out.tab; view.unread[view.tab] = nil end
    if out.set_player ~= nil then
        view.player = 1
        for i, n in ipairs(players()) do if n == out.set_player then view.player = i end end
        view.player_name = view.player > 1 and out.set_player or nil
    end
    out.players = players()
    out.network = network_game()
    out.active = active()
    out.visible, out.tab, out.entries, out.shown, out.minimized = visible(), view.tab, #entries, view.shown or 0, view.minimized
    out.last = entries[#entries]
    out.tabs = {}
    for i = 1, #TABS do out.tabs[i] = rect_of('#tab' .. i) end
    out.lines = rect_of('#lines')
    out.newer = rect_of('#newer')
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
