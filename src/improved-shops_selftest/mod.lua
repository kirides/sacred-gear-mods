---@type GearModManifest
return {
    id = 'improved-shops_selftest',
    name = 'Improved shops self test',
    version = '0.1.0',
    author = 'kirides',
    description = 'Walks to a merchant in a loaded savegame, opens the shop twice and checks that the stock stays the same and that the finds of Improved shops are in it.',
    requires = {'improved-shops'},
    automation = true,
    config = {
        merchant = nil,     -- a creature id to walk to (default: the nearest merchant found by type name)
        walk_to = nil,      -- {x, y} world position to walk towards first
    },
}
