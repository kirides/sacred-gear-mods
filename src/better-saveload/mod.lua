---@type GearModManifest
return {
    id = 'better-saveload',
    name = 'Better SaveLoad',
    version = '1.1.0',
    author = 'kirides',
    description = 'The savegame screen made new: hero, class, level and picture of every savegame, filters by '
        .. 'character and class, newest first or by file name. Works with the mouse, the keyboard and the controller.',
    settings = {
        {id = 'in_game', type = 'bool', label = 'Replace the savegame window in game', default = true,
         tooltip = 'Off: the game\'s own savegame window'},
        {id = 'in_menus', type = 'bool', label = 'Replace the Load game screen of the start menu', default = true,
         tooltip = 'Off: the game\'s own Load game screen'},
        {id = 'sort', type = 'choice', label = 'Order', default = 'newest',
         choices = {{value = 'newest', label = 'Newest first'}, {value = 'file', label = 'By file name (as the game)'}}},
        {id = 'current_hero', type = 'bool', label = 'In game, show the current hero\'s savegames first', default = false,
         tooltip = 'The character filter starts on the hero you play'},
        {id = 'confirm_load', type = 'bool', label = 'Ask before loading in game', default = true,
         tooltip = 'What was not saved is lost when another savegame loads'},
        {id = 'save_name', type = 'text', label = 'Default name of new savegames', default = '%hero% %Y-%m-%d %H:%M',
         max_length = 60, tooltip = '%hero% is the hero\'s name, %level% the level; %Y %m %d %H %M the date and time'},
    },
}
