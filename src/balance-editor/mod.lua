---@type GearModManifest
return {
    id = 'balance-editor',
    name = 'Balance editor',
    version = '0.2.0',
    author = 'kirides',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'Edit the game\'s balance.bin from inside the game: difficulty multipliers and levels, creature health, skill curves, loot chances, '
        .. 'item prices, movement speed and more, with the game\'s own value next to yours. Your changes live in this mod only, as an overlay the game '
        .. 'reads instead of its file (switch the mod off or delete it and the game is as before); the game\'s own balance.bin is never touched. '
        .. 'Changes apply the next time the game starts. Balance patches can be exported and imported as plain data files.',
    keys = {
        {id = 'toggle', label = 'Open the balance editor', default = 'ctrl+shift+b'},
    },
}
