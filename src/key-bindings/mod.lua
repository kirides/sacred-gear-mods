-- No globals here: plain Lua with numeric loops only. The same actions are listed in actions.lua (main.lua uses that);
-- the self test checks that both agree. Order and sections are what the Keys page shows: each quick cast row stands
-- right under its combat art. Every action has a second key (`<id>_2`) that shares its row.
local actions = {
    {'weapon1', 'Weapon slot 1', '1', 'Weapons'}, {'weapon2', 'Weapon slot 2', '2', 'Weapons'},
    {'weapon3', 'Weapon slot 3', '3', 'Weapons'}, {'weapon4', 'Weapon slot 4', '4', 'Weapons'},
    {'weapon5', 'Weapon slot 5', '5', 'Weapons'},
    {'art1', 'Combat art 1', '6', 'Combat arts and quick cast'}, {'qc1', 'Combat art 1, quick cast', '', 'Combat arts and quick cast'},
    {'art2', 'Combat art 2', '7', 'Combat arts and quick cast'}, {'qc2', 'Combat art 2, quick cast', '', 'Combat arts and quick cast'},
    {'art3', 'Combat art 3', '8', 'Combat arts and quick cast'}, {'qc3', 'Combat art 3, quick cast', '', 'Combat arts and quick cast'},
    {'art4', 'Combat art 4', '9', 'Combat arts and quick cast'}, {'qc4', 'Combat art 4, quick cast', '', 'Combat arts and quick cast'},
    {'art5', 'Combat art 5', '0', 'Combat arts and quick cast'}, {'qc5', 'Combat art 5, quick cast', '', 'Combat arts and quick cast'},
    {'potion_health', 'Healing potion (red)', 'space', 'Potions'},
    {'potion_undead', 'Potion of Undead Death (dark)', 'q', 'Potions'},
    {'potion_mentor', 'Potion of the Mentor (blue)', 'w', 'Potions'},
    {'potion_antidote', "Viper's Antidote (green)", 'e', 'Potions'},
    {'potion_yellow', 'Potion of Concentration (yellow)', 'r', 'Potions'},
    {'heal_companion', 'Heal companions', 'b', 'Potions'},
    {'inventory', 'Inventory', 'i', 'Windows'}, {'arts_window', 'Combat arts window', 'f', 'Windows'},
    {'combos', 'Combo window', 'c', 'Windows'}, {'logbook', 'Log book', 'l', 'Windows'},
    {'worldmap', 'World map', 'm', 'Windows'}, {'savemenu', 'Save / Load menu', 's', 'Windows'},
    {'help', 'Help', 'h', 'Windows'}, {'options', 'Options', 'o', 'Windows'},
    {'netinfo', 'Multiplayer info', 'n', 'Windows'},
    {'collect', 'Collect all loot', 'a', 'Game'}, {'pause', 'Pause', 'p', 'Game'},
    {'show_names', 'Show item names (hold)', 'alt', 'Game'}, {'stand_still', 'Attack in place (hold)', 'ctrl', 'Game'},
    {'zoom_in', 'Zoom in (hold)', 'add', 'Game'}, {'zoom_out', 'Zoom out (hold)', 'subtract', 'Game'},
}

local keys = {}
for i = 1, #actions do
    local a = actions[i]
    keys[#keys + 1] = {id = a[1], label = a[2], default = a[3], section = a[4], second = a[1] .. '_2'}
    keys[#keys + 1] = {id = a[1] .. '_2', label = a[2] .. ' (second key)', default = '', section = a[4]}
end

---@type GearModManifest
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
