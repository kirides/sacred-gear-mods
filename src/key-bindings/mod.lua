-- No globals here: plain Lua with numeric loops only. The same actions are listed in actions.lua (main.lua uses that);
-- the self test checks that both agree.
local actions = {
    {'weapon1', 'Weapon slot 1', '1'}, {'weapon2', 'Weapon slot 2', '2'}, {'weapon3', 'Weapon slot 3', '3'},
    {'weapon4', 'Weapon slot 4', '4'}, {'weapon5', 'Weapon slot 5', '5'},
    {'art1', 'Combat art 1', '6'}, {'art2', 'Combat art 2', '7'}, {'art3', 'Combat art 3', '8'},
    {'art4', 'Combat art 4', '9'}, {'art5', 'Combat art 5', '0'},
    {'potion_health', 'Healing potion (red)', 'space'}, {'potion_undead', 'Potion of Undead Death (dark)', 'q'},
    {'potion_mentor', 'Potion of the Mentor (blue)', 'w'}, {'potion_antidote', "Viper's Antidote (green)", 'e'},
    {'potion_yellow', 'Potion of Concentration (yellow)', 'r'}, {'heal_companion', 'Heal companions', 'b'},
    {'inventory', 'Inventory', 'i'}, {'arts_window', 'Combat arts window', 'f'}, {'combos', 'Combo window', 'c'},
    {'logbook', 'Log book', 'l'}, {'worldmap', 'World map', 'm'}, {'collect', 'Collect all loot', 'a'},
    {'savemenu', 'Save / Load menu', 's'}, {'help', 'Help', 'h'}, {'options', 'Options', 'o'}, {'pause', 'Pause', 'p'},
    {'netinfo', 'Multiplayer info', 'n'},
    {'show_names', 'Show item names (hold)', 'alt'}, {'stand_still', 'Attack in place (hold)', 'ctrl'},
    {'zoom_in', 'Zoom in (hold)', 'add'}, {'zoom_out', 'Zoom out (hold)', 'subtract'},
    {'qc1', 'Combat art 1, quick cast', ''}, {'qc2', 'Combat art 2, quick cast', ''},
    {'qc3', 'Combat art 3, quick cast', ''}, {'qc4', 'Combat art 4, quick cast', ''},
    {'qc5', 'Combat art 5, quick cast', ''},
}

local keys = {}
for i = 1, #actions do
    local a = actions[i]
    keys[#keys + 1] = {id = a[1], label = a[2], default = a[3]}
    keys[#keys + 1] = {id = a[1] .. '_2', label = a[2] .. ' (second key)', default = ''}
end

return {
    id = 'key-bindings',
    name = 'Key bindings',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = "Choose the keys and mouse buttons of the game's actions (weapons, combat arts, potions, windows), two keys each, with an optional quick cast for combat arts.",
    automation = true,      -- only for its self test (-gear-auto)
    config = {
        debug = false,
    },
    settings = {
        {id = 'quickcast', type = 'bool', label = 'Quick cast', default = true, section = 'Quick cast',
            tooltip = 'On: the keys of the "quick cast" rows select the combat art and cast it once at the cursor. Off: they only select it.'},
        {id = 'quickcast_ui', type = 'bool', label = 'Quick cast over windows', default = false, section = 'Quick cast',
            tooltip = 'Off (default): no cast while the cursor is over an open window or a mod panel, so the click cannot hit an item or button there.'},
    },
    keys = keys,
}
