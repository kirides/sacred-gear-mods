---@type GearModManifest
-- Art bars: extra rows of slots for combat arts and spells (also copies and chains of the custom-classes mod), used with their own
-- keys and the controller. The keys are generated: bar 1 and 2 have defaults (Ctrl+1 ... Ctrl+8, Ctrl+Shift+1 ... Ctrl+Shift+8), the
-- rest is unbound until the player picks keys on the mod's Keys page.
local keys = {
    {id = 'page_next', label = 'Next bar (with "One bar with pages")', default = 'ctrl+pagedown'},
    {id = 'page_previous', label = 'Previous bar (with "One bar with pages")', default = 'ctrl+pageup'},
    {id = 'edit', label = 'Edit the bars (fill slots)', default = 'ctrl+e'},
}
local DIGITS = {'1', '2', '3', '4', '5', '6', '7', '8', '9', '0'}
for bar = 1, 3 do
    for slot = 1, 12 do
        local default
        if slot <= 10 and bar == 1 then default = 'ctrl+' .. DIGITS[slot] end
        if slot <= 10 and bar == 2 then default = 'ctrl+shift+' .. DIGITS[slot] end
        keys[#keys + 1] = {id = ('bar%d_%d'):format(bar, slot), label = ('Art bar %d, slot %d'):format(bar, slot), default = default}
    end
end

return {
    id = 'art-bars',
    name = 'Art bars',
    version = '0.2.3',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'More combat arts at hand than the game\'s skill bar holds: extra bars of slots for your hero\'s combat arts and spells '
        .. '(copies and chains of the Custom classes mod too), with keys, cooldowns and the controller. Single player.',
    settings = {
        {id = 'bars', type = 'number', label = 'Bars', min = 1, max = 3, step = 1, default = 2, section = 'Bars',
            tooltip = 'How many extra bars'},
        {id = 'slots', type = 'number', label = 'Slots per bar', min = 4, max = 12, step = 1, default = 8, section = 'Bars'},
        {id = 'paging', type = 'bool', label = 'One bar with pages', default = false, section = 'Bars',
            tooltip = 'Show one bar at a time; the page keys switch between the bars and the slot keys of bar 1 use the shown one'},
        {id = 'size', type = 'number', label = 'Slot size', min = 32, max = 64, step = 4, default = 44, section = 'Look'},
        {id = 'keys_shown', type = 'bool', label = 'Show the keys on the slots', default = true, section = 'Look'},
        {id = 'show_empty', type = 'bool', label = 'Show empty slots', default = true, section = 'Look'},
        {id = 'debug', type = 'bool', label = 'Log what the keys do', default = false, section = 'Look'},
    },
    keys = keys,
    config = {
        bar_x = 300,    -- the first bar's place in the 1024x768 layout (the layout editor, hold Alt, moves the bars)
        bar_y = 560,
    },
}
