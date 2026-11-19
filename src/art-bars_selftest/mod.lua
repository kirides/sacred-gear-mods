return {
    id = 'art-bars_selftest',
    name = 'Art bars self test',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Automation run of the art-bars mod: fills slots, uses them by key path, checks the regeneration shows, takes screenshots. '
        .. 'Needs a single player savegame with hostile creatures nearby: Sacred.exe -gear-auto -gear-load=N -gear-mods=art-bars,art-bars_selftest',
    requires = {'art-bars'},
    automation = true,
    config = { quit = true },
}
