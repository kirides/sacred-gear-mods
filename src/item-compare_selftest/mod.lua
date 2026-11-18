---@type GearModManifest
return {
    id = 'item-compare_selftest',
    name = 'Item comparison self test',
    version = '1.0.0',
    requires = {'item-compare'},
    automation = true,
    config = {
        timeout_menu = 120,
        timeout_game = 180,
        quit = true,
        party = true,       -- also bring a companion from a hero file (SaveHero*.pax) and compare with it
    },
}
