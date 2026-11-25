-- NPC example: one NPC made with gear.npc (Sacred Gear 0.14.0 or later), kept short so it can be copied.
--   * a kind (npc.define): the model of an object type the game has, a name of her own, dialog pages, a daily routine
--   * the creature is made with npc.spawn and belongs to the savegame (the game keeps her name text, the mod's per savegame data her entry)
--   * the buttons of the dialog: some only go to another page, "Browse pets" and "Trade in rare materials" call the mod's own code, which
--     opens a window of the mod (a gear.ui panel) the way any mod's window opens

local npc = gear.npc
local ui = gear.ui
local KIND = 'npc-example.nirael'

local TYPE = 'DARKELVENPC.GRN'      -- a dark elf woman of the game: any object type name or id will do

local window = nil                  -- 'pets' or 'materials' while the mod's own window is open

local function open_window(which, e)
    e.close()                       -- the dialog ends after the button's handlers; the mod's window takes over
    window = which
end

npc.define(KIND, {
    type = TYPE,
    name = {en = 'Nirael the Collector', de = 'Nirael die Sammlerin'},
    talk_range = 160,
    -- Stands where she was put until 18:00 (the game's clock), then walks to a spot 250 units east, and back at 06:00. When the hero
    -- is far away she is put there at once; when something blocks her walk she is put there after a few seconds.
    -- (The base point is the place she was spawned at: see `spawn_near`.)
    dialog = {
        start = 'greeting',
        pages = {
            greeting = {
                text = 'Welcome, traveller. I collect what others throw away: pets that lost their masters, and rare materials. What brings you?',
                options = {
                    {id = 'pets', label = 'Browse pets', on = function(e) open_window('pets', e) end},
                    {id = 'trade', label = 'Trade in rare materials', on = function(e) open_window('materials', e) end},
                    {id = 'about', label = 'Who are you?', go = 'about'},
                    {id = 'bye', label = 'Goodbye', close = true},
                },
            },
            about = {
                text = function(e)
                    local m, h, min = gear.world.clock()
                    return ('Nirael, they call me. It is %02d:%02d, and I keep a spot by the road in the daytime and another one at night.'):format(h or 0, min or 0)
                end,
                options = {{label = 'Back', go = 'greeting'}},
            },
        },
    },
})

-- The two places of her routine, kept with her entry in the savegame data (`data`) so a loaded game has the same ones.
local function routine_around(x, y, layer)
    return {
        {time = '06:00', x = x, y = y, layer = layer},
        {time = '18:00', x = x + 250, y = y, layer = layer},
    }
end

local function spawn_near(hero)
    local x, y, layer = hero:position()
    local c, err = npc.spawn(KIND, x + 120, y + 40, {layer = layer, routine = routine_around(x + 120, y + 40, layer)})
    if not c then gear.log('npc-example: ' .. tostring(err)) end
    return c
end

-- One NPC per savegame: spawn her when this savegame has none (also after a load, once the world is there).
local function ensure(force)
    if not gear.world.can_change() then return end
    local hero = gear.world.hero()
    if not hero then return end
    local list = npc.list(KIND)
    if #list > 0 then return list[1].creature end
    if force or gear.settings.get('auto_spawn') then return spawn_near(hero) end
end

local checked = false
gear.on('session.start', function() checked = false end)
gear.on('savegame.changed', function() checked = false end)
gear.every(2, function()
    if checked then return end
    if gear.world.hero() and gear.world.can_change() then
        checked = true
        ensure(false)
    end
end)

gear.keys.on('call', function()
    local hero = gear.world.hero()
    if not hero then return end
    local list = npc.list(KIND)
    if #list == 0 then
        ensure(true)
    else
        local x, y, layer = hero:position()
        list[1].creature:teleport(x + 120, y + 40, layer)
    end
end)

-- For the self test (another mod has its own gear.npc, so it asks this one): opens Nirael's dialog without a click.
gear.on('npc-example.talk', function()
    local list = npc.list(KIND)
    if list[1] then npc.talk(list[1].creature) end
end)

-- The mod's own windows, opened from the dialog's buttons.
gear.on('draw', function(state)
    if not window or state.mode ~= 'game' then return end
    if window == 'pets' then
        local p = ui.panel('pets', 'Nirael: pets', 330, 220, 360, 150)
        if not p.open then window = nil return end
        ui.text('A real shop would list pets here and take gold,', p.content_x + 8, p.content_y + 8, {})
        ui.text('then call gear.world.spawn for the one you buy.', p.content_x + 8, p.content_y + 26, {})
        if ui.button('close', p.content_x + 8, p.content_y + 80, 120, 24, 'Close') then window = nil end
    else
        local p = ui.panel('materials', 'Nirael: rare materials', 330, 220, 360, 150)
        if not p.open then window = nil return end
        ui.text('Here you would pick the materials to trade in,', p.content_x + 8, p.content_y + 8, {})
        ui.text('and get gold or an item for them.', p.content_x + 8, p.content_y + 26, {})
        if ui.button('close', p.content_x + 8, p.content_y + 80, 120, 24, 'Close') then window = nil end
    end
end)
