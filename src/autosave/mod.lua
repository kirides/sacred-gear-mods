---@type GearModManifest
return {
    id = 'autosave',
    name = 'Autosave',
    version = '1.0.0',
    -- The defaults; settings.json in this folder (written by the in-game panel, F6) overrides them.
    config = {
        enabled = true,
        -- Minutes of active play between autosaves (fractions are fine: 0.5 is 30 s).
        interval_minutes = 5,
        -- The savegame slots the autosaves rotate through, oldest first: Save\GAME97.PAK, GAME98.PAK, GAME99.PAK.
        -- Slot 0 is the quicksave and the game's own savegame window fills the low numbers, so these stay out of
        -- their way. 1 to 509, at most 8.
        slots = {97, 98, 99},
        -- Savegame display name; %H:%M is replaced with the time.
        name = 'Autosave %H:%M',
        -- A short note on screen after a successful autosave.
        show_confirmation = true,
        -- The key that opens the settings panel.
        settings_key = 'f6',
        -- Where the confirmation is drawn (1024x768 layout).
        note_y = 60,
    },
}
