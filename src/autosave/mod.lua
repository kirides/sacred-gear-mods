---@type GearModManifest
return {
    id = 'autosave',
    name = 'Autosave',
    version = '1.1.0',
    author = 'kirides',
    description = 'Saves the game every few minutes of play into its own slots.',
    -- The defaults; the player's choices (Mods screen, F11) override them. Saved in mods\gear_mods.json.
    config = {
        enabled = true,
        -- Minutes of active play between autosaves (fractions are fine: 0.5 is 30 s).
        interval_minutes = 5,
        -- Savegame display name; %H:%M is replaced with the time.
        name = 'Autosave %H:%M',
        -- A short note on screen after a successful autosave.
        show_confirmation = true,
        -- Where the confirmation is drawn (1024x768 layout).
        note_y = 60,
    },
    settings = {
        {id = 'enabled', type = 'bool', label = 'Autosave on', default = true},
        {id = 'interval_minutes', type = 'number', label = 'Minutes of play between autosaves', min = 1, max = 60,
         step = 1, default = 5},
        {id = 'show_confirmation', type = 'bool', label = 'Show a note after each autosave', default = true},
        -- The slots the autosaves rotate through, oldest first: Save\GAME97.PAK, GAME98.PAK, GAME99.PAK. Slot 0 is the
        -- quicksave and the game's own savegame window fills the low numbers, so these stay out of their way.
        -- 1 to 32766, at most 8, separated by commas.
        {id = 'slots', type = 'text', label = 'Savegame slots (oldest is reused first)', default = '97, 98, 99',
         max_length = 40, tooltip = 'Numbers 1 to 32766 separated by commas (97 is GAME97.PAK)'},
        {id = 'name', type = 'text', label = 'Savegame name', default = 'Autosave %H:%M', max_length = 40,
         tooltip = '%H:%M is replaced with the time'},
    },
    keys = {
        {id = 'save_now', label = 'Autosave now', default = 'f6'},
    },
}
