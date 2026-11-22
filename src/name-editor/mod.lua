---@type GearModManifest
return {
    id = 'name-editor',
    name = 'Name editor',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Build character names with the game\'s colors and little pictures: type, pick colors and icons, or color a name with a gradient, '
        .. 'and copy the raw text (\\cffRRGGBB colors, \\gffffffff00000XXX icons) that Sacred stores. Pasted raw names are read back. '
        .. 'The same editor also runs as a web page (docs/name-editor).',
    keys = {
        {id = 'window', label = 'Name editor', default = 'ctrl+shift+n'},
    },
}
