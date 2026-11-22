return {
    id = 'custom-classes-fx_selftest',
    name = 'Custom classes effects self test',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Automation run of the effect rules of custom-classes: a copy of Poison Mist with a red cloud (arts/red-mist.json, the file the '
        .. 'Sacred Class Editor writes) is cast next to the original; screenshots 0.6, 1.4 and 2.4 s after each cast. Needs a single player '
        .. 'savegame: Sacred.exe -gear-auto -gear-load=N -gear-mods=custom-classes,custom-classes-fx_selftest',
    requires = {'custom-classes'},
    automation = true,
    config = { quit = true },
}
