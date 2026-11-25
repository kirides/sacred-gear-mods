---@type GearModManifest
return {
    id = 'improved-shops',
    name = 'Improved shops',
    version = '0.1.0',
    author = 'kirides',
    description = 'Merchants that sell gear sometimes stock a few better pieces, picked for your hero\'s level: magic and rare items you would otherwise only find as drops. The extras come when the game fills a shop, and the shop keeps them until the game itself resets its stock, so reopening it shows the same wares.',
    settings = {
        {id = 'chance_new', type = 'number', label = 'Chance a shop has finds (%)', min = 0, max = 100, step = 5, default = 60,
         section = 'How often',
         tooltip = 'Each time the game fills a shop with new wares (you open a merchant other than the one you saw last) this is the chance that it also gets better pieces. 0 turns the mod off'},
        {id = 'chance_restock', type = 'number', label = 'Chance after a restock (%)', min = 0, max = 100, step = 5, default = 0,
         tooltip = 'The game often swaps a few wares when you come back to the same merchant. This is the chance that such a restock brings better pieces too. 0 (the default) leaves the stock to the game, so a merchant you come back to is not rerolled; every restock with a chance above 0 can add more finds'},
        {id = 'count', type = 'number', label = 'Most finds per shop', min = 1, max = 6, step = 1, default = 2,
         tooltip = 'A shop with finds gets between one and this many extra pieces'},
        {id = 'quality_min', type = 'number', label = 'Lowest quality', min = 0, max = 14, step = 1, default = 7,
         section = 'What',
         tooltip = 'The quality tier the game rolls an item with: 0 plain, 5 to 11 magic, 12 to 14 rare. Finds are drawn between the lowest and the highest, the lower ones more often'},
        {id = 'quality_max', type = 'number', label = 'Highest quality', min = 0, max = 14, step = 1, default = 14},
        {id = 'level_offset', type = 'number', label = 'Level against your hero', min = -10, max = 10, step = 1, default = 0,
         tooltip = '0 makes the finds items of your hero\'s level, 3 three levels above it, -3 below'},
    },
}
