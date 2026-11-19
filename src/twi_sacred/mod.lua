---@type GearModManifest
return {
    id = 'twi_sacred',
    name = 'Twitch Integration: actions',
    version = '0.2.0',
    author = 'Sacred Gear',
    description = 'Twitch viewers spawn monsters, give gold, heal or teleport the hero.',
    requires = {'twitch_integration'},
    config = {
        -- Object types (type ids; names also work) the monster actions pick from; ones that are not found are
        -- logged and left out. Run the selftest example once: it writes every type name to GearAutomation\types.txt.
        -- object type names of the game (the .GRN model names); the label shows them in plain words
        monsters = {'WOLF.GRN', 'ORC_WARRIOR.GRN', 'ZOMBIE.GRN', 'SKELETON_WARRIOR_HEADLESS.GRN', 'small_spider.grn'},
    },
    settings = {
        -- How far from the hero spawned monsters appear, in world units (a tile is about 54; the screen shows
        -- about 534 x 400 around the hero): just out of sight.
        {id = 'spawn_min', type = 'number', label = 'Spawn at least this far away', min = 0, max = 2000, step = 10, default = 380},
        {id = 'spawn_max', type = 'number', label = 'Spawn at most this far away', min = 0, max = 2000, step = 10, default = 520},
    },
}
