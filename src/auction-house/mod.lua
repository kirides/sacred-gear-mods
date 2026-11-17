---@type GearModManifest
return {
    id = 'auction-house',
    name = 'Auction house',
    version = '0.1.0',
    author = 'kirides',
    description = 'Buy and sell items with the other players of a game, from the chest window. The host keeps the market.',
    automation = true,      -- only for its self test (-gear-auto)
    config = {
        enabled = true,
        -- self test only (-gear-auto); see selftest.lua
        selftest = false,
    },
    -- The market's rules apply where the market runs: in single player your own game, in a network game the host's.
    settings = {
        {id = 'durations', type = 'choice', label = 'Listing durations', default = '1,3,7',
         choices = {{value = '1,3,7', label = '1, 3 or 7 days'}, {value = '1,2,3', label = '1, 2 or 3 days'},
                    {value = '1,7,14', label = '1, 7 or 14 days'}, {value = '3,7,30', label = '3, 7 or 30 days'}},
         tooltip = 'Real time on the host\'s clock; unsold items go back to the seller\'s mailbox'},
        {id = 'fee_per_day', type = 'number', label = 'Listing fee, % of the price a day', min = 0, max = 5, step = 0.5,
         default = 0.5, tooltip = 'Paid when listing, not returned (a gold sink against listing spam). 0: none'},
        {id = 'sale_cut', type = 'number', label = 'Cut of a sale, %', min = 0, max = 30, step = 1, default = 5,
         tooltip = 'Taken from the price when an item sells (a gold sink). 0: none'},
        {id = 'max_per_seller', type = 'number', label = 'Listings per player', min = 5, max = 100, step = 5, default = 20},
        {id = 'allow_special', type = 'bool', label = 'Also sell special items', default = false,
         tooltip = 'Horse gear and the like; gold and quest items never sell'},
    },
}
