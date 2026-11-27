---@type GearModManifest
return {
    id = 'town-portal_selftest',
    name = 'Town Portal self test',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Reads a Town Portal Potion in a loaded savegame, picks a portal, checks the portal and the way back, and takes the pictures for the docs.',
    requires = {'town-portal'},
    automation = true,
    config = {
        shots = false,      -- true: also takes the pictures of the docs
    },
}
