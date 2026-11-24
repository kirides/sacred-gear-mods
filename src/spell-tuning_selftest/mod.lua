---@type GearModManifest
return {
    id = 'spell-tuning_selftest',
    name = 'Spell tuning self test',
    version = '1.0.0',
    requires = {'spell-tuning'},
    -- gear.auto: only when the game runs with -gear-auto.
    automation = true,
    config = {quit = true},
}
