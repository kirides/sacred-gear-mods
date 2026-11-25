---@type GearModManifest
return {
    id = 'sprite-browser',
    name = 'Sprite browser',
    version = '0.1.3',
    author = 'Sacred Gear',
    recommended = {'sacred-theme'}, -- optional: the look of the game for the windows (the manager offers it on install)
    description = 'Every UI image of the game in a grid with its number, in the mod\'s page of the Mods screen. The numbers are the N of the '
        .. '.sprite-N classes of the Sacred theme and of gear:image/N: a quick lookup for modders. Click a picture to copy its class.',
}
