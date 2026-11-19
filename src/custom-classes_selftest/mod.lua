return {
    id = 'custom-classes_selftest',
    name = 'Custom classes self test',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Automation run of the custom-classes mod: profiles load, a Seraphim takes Spellblade (arts granted, skills while played, '
        .. 'a Gladiator art routed), a Gladiator takes Battle Caster (casts without cast clips). Needs a single player savegame with '
        .. 'hostile creatures nearby: Sacred.exe -gear-auto -gear-load=N -gear-mods=custom-classes,custom-classes_selftest',
    requires = {'custom-classes'},
    automation = true,
    config = { quit = true },
}
