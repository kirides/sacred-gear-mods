return {
    id = 'bounty',
    name = 'Bounty board',
    version = '0.2.0',
    author = 'Sacred Gear',
    description = 'Bounties to hunt: in single player the mod posts, counts and pays them itself, in a network game it shows the '
        .. 'board of a Sacred.GameServer with scripts-examples/bounty_board.lua. Panel (Ctrl+J) and a small tracker.',
    settings = {
        {id = 'own_board', type = 'bool', label = 'Own board in single player', default = true,
            tooltip = 'Single player: the mod posts bounties for your hero, counts the kills and pays the rewards. Off: no board without a server'},
        {id = 'tracker', type = 'bool', label = 'Tracker', default = true,
            tooltip = 'A few lines with the progress of your open bounties, at the top right'},
    },
    keys = {
        {id = 'panel', label = 'Open the bounty board', default = 'ctrl+j'},
    },
    config = {
        tracker_x = 780,    -- the tracker's place in the 1024x768 layout
        tracker_y = 150,
        refresh = 60,       -- seconds between asking the server for the board (it also pushes every change)
    },
}
