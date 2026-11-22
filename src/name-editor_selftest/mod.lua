---@type GearModManifest
return {
    id = 'name-editor_selftest',
    name = 'Name editor self test',
    version = '1.0.0',
    author = 'Sacred Gear',
    description = 'Automation only: types into the name editor, picks colors and icons, applies a gradient and takes the pictures of the mod\'s page.',
    requires = {'name-editor'},
    automation = true,
    priority = 200,
}
