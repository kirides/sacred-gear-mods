-- Key bindings and quick cast.
--
-- Each action of the game has a row with two key slots (declared keys of this mod, changed in the Mods screen under Keys);
-- the defaults are the game's own keys. gear.input turns the key (or mouse button) the player chose into the game's key
-- for that action, and swallows the original key of an action that was moved. The quick cast rows do the same for the
-- key of a combat art slot and then fire one cast at the cursor.

local actions = require('actions')
local DEBUG = gear.config.debug

-- Rules for the current bindings: one per bound slot, plus a block for the game key of every action that is not on it.
local function build()
    local rules, claimed = {}, {}
    local function add(from, to, id)
        rules[#rules + 1] = {from = from, to = to, id = id}
        if not from:find('+', 1, true) then claimed[from] = true end
    end
    for _, a in ipairs(actions.list) do
        for _, slot in ipairs({a[1], a[1] .. '_2'}) do
            local b = gear.keys.binding(slot)
            if b ~= '' then add(b, a[3]) end
        end
    end
    for n, a in ipairs(actions.quick) do
        local art = actions.list[5 + n]
        for _, slot in ipairs({a[1], a[1] .. '_2'}) do
            local b = gear.keys.binding(slot)
            if b ~= '' then add(b, art[3], a[1]) end
        end
    end
    -- The game key of an action whose key is taken elsewhere does nothing (unless another action uses that key).
    for _, a in ipairs(actions.list) do
        if not claimed[a[3]] then
            rules[#rules + 1] = {from = a[3], block = true}
            claimed[a[3]] = true
        end
    end
    return rules
end

local signature
local function apply(force)
    local parts = {}
    for _, group in ipairs({actions.list, actions.quick}) do
        for _, a in ipairs(group) do
            parts[#parts + 1] = gear.keys.binding(a[1]) .. ',' .. gear.keys.binding(a[1] .. '_2')
        end
    end
    local sig = table.concat(parts, ';')
    if sig == signature and not force then return end
    signature = sig
    local rules = build()
    gear.input.remap(rules)
    if DEBUG then gear.log('rules: ' .. #rules) end
end

-- Quick cast: the game selects the slot from the key we gave it; a cast follows only if it did (an empty slot leaves
-- the earlier art selected, which must not fire).
local selected = 0
gear.on('skillslot.select', function(index)
    selected = selected + 1
    if DEBUG then gear.log('slot selected ' .. tostring(index)) end
end)

local function over_window()
    if gear.ui.over_ui() then return true end
    local x, y = gear.ui.mouse()
    for _, w in ipairs(gear.ui.windows()) do
        local n = w.name:upper()
        if w.drawn and w.visible and not (n:find('TASKBAR', 1, true) or n:find('MERC', 1, true) or n:find('TEXTLINES', 1, true) or n:find('CONSOLE', 1, true)) then
            local r = w.bounds or {x = w.x + w.frame_x, y = w.y + w.frame_y, w = w.width, h = w.height}
            if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return true end
        end
    end
    return false
end

local function cast()
    if not gear.settings.get('quickcast') then return end
    if not gear.settings.get('quickcast_ui') and over_window() then return end
    gear.game.cursor_click(true)
    gear.after(0.04, function() gear.game.cursor_click(false) end)
end

gear.input.on(function(id, down, repeating)
    if not down or repeating then return end    -- one cast per press
    local before = selected
    gear.task(function()
        local t0 = gear.time()
        while selected == before and gear.time() - t0 < 0.25 do gear.wait(0.02) end
        if selected ~= before then
            gear.wait(0.03)
            cast()
        elseif DEBUG then
            gear.log('quick cast ' .. id .. ': the slot was not selected, no cast')
        end
    end)
end)

-- For the self test.
gear.on('key-bindings.query', function(out)
    out.list, out.quick = actions.list, actions.quick
    out.binding = function(id) return gear.keys.binding(id) end
    out.set = function(id, binding) return gear.keys.set(id, binding) end
end)

apply(true)
gear.every(0.25, function() apply(false) end)
gear.on('settings.changed', function() apply(true) end)
