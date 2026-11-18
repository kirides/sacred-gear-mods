-- The game's actions this mod can rebind, with the key each has in the game (these are the defaults of the rows).
-- mod.lua has the same list (it cannot load files); the self test checks that they agree.
local A = {}

-- {id, label, the game's key}
A.list = {
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
}

-- Quick cast rows (unbound by default): the key selects combat art slot n and casts it once at the cursor.
A.quick = {
    {'qc1', 'Combat art 1, quick cast'}, {'qc2', 'Combat art 2, quick cast'}, {'qc3', 'Combat art 3, quick cast'},
    {'qc4', 'Combat art 4, quick cast'}, {'qc5', 'Combat art 5, quick cast'},
}

return A
