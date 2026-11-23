---@type GearModManifest
return {
    id = 'bounty',
    name = 'Bounty board',
    version = '0.5.3',
    author = 'Sacred Gear',
    description = 'Bounties to hunt, plus daily and weekly quests with streak rewards: in single player the mod posts, counts and pays them itself, in a network game it shows the '
        .. 'board of a Sacred.GameServer with scripts-examples/bounty_board.lua. Panel and a small tracker.',
    settings = {
        {id = 'own_board', type = 'bool', label = 'Own board in single player', default = true,
            tooltip = 'Single player: the mod posts bounties for your hero, counts the kills and pays the rewards. Off: no board without a server'},
        {id = 'pool_board', type = 'bool', label = 'Pool bounties', default = true,
            tooltip = 'Single player: post bounties from the built-in list. Off: only your own bounties from the editor'},
        {id = 'tracker', type = 'bool', label = 'Tracker', default = true,
            tooltip = 'A few lines with the progress of your open bounties, at the top right'},
        {id = 'quests', type = 'bool', label = 'Daily and weekly quests', default = true,
            tooltip = 'New quests every day and every Monday, with a streak bonus for days / weeks in a row. Single player: counted here; network: the game server counts them'},
        {id = 'auto_claim', type = 'bool', label = 'Pay quest rewards at once', default = true,
            tooltip = 'Off: finished quests and streak bonuses wait until you press Claim rewards in the quest panel'},
        {id = 'quest_tracker', type = 'bool', label = 'Quest tracker', default = false,
            tooltip = 'A few lines with the open daily and weekly quests (D / W), below the bounty tracker'},
    },
    keys = {
        {id = 'editor', label = 'Open the bounty editor', default = 'ctrl+shift+j'},
        {id = 'panel', label = 'Open the bounty board', default = 'ctrl+j'},
        {id = 'quests', label = 'Open the daily and weekly quests', default = 'ctrl+shift+d'},
    },
    config = {
        tracker_x = 780,    -- the tracker's place in the 1024x768 layout
        tracker_y = 150,
        quest_tracker_x = 780,
        quest_tracker_y = 260,
        refresh = 60,       -- seconds between asking the server for the board (it also pushes every change)
    },
}
