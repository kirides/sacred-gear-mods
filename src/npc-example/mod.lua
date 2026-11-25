---@type GearModManifest
return {
    id = 'npc-example',
    name = 'NPC example',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'An example of gear.npc, Sacred Gear\'s custom NPCs: Nirael the Collector stands near your hero, uses a model of the game, has a name of her own, talks in dialog pages, opens a window of the mod from her buttons and walks between two places by the game\'s clock. Copy it as the start of an NPC mod of your own.',
    settings = {
        {id = 'auto_spawn', type = 'bool', label = 'Place Nirael in a new game', default = true,
            tooltip = 'Single player: the first time the mod runs in a savegame it puts her near your hero. Switched off, press the key (default Ctrl+Shift+M) to call her'},
    },
    keys = {
        {id = 'call', label = 'Call Nirael to the hero', default = 'ctrl+shift+m'},
    },
}
