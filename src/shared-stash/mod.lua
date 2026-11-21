---@type GearModManifest
return {
    id = 'shared-stash',
    name = 'Shared stash',
    version = '0.3.0',
    author = 'kirides',
    description = 'A stash shared by all your heroes, in a panel beside the chest window.',
    automation = true,      -- only for its self test (-gear-auto)
    -- The defaults; config.lua in this folder overrides them. The settings below are changed in the Mods screen.
    config = {
        enabled = true,
        -- self test only (-gear-auto): 'deposit', 'withdraw', 'ui' or 'roundtrip'; see selftest.lua
        selftest = false,
    },
    settings = {
        {id = 'max_items', type = 'number', label = 'Items the stash holds', min = 10, max = 200, step = 10, default = 200,
         tooltip = 'The stash file is limited to 1 MB'},
        {id = 'allow_special', type = 'bool', label = 'Also move special items', default = false,
         tooltip = 'Horse gear and the like; quest items and gold never move'},
    },
}
