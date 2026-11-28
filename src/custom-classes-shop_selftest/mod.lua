return {
    id = 'custom-classes-shop_selftest',
    name = 'Custom classes shop self test',
    version = '0.1.0',
    author = 'Sacred Gear',
    description = 'Walks to a merchant of a loaded savegame and checks that the rune of a test art (rune.shop_weight 100) is in the stock. '
        .. 'Run: Sacred.exe -gear-auto -gear-load=N -gear-mods=custom-classes,custom-classes-shop_selftest',
    requires = {'custom-classes'},
    automation = true,
    config = {quit = true},
}
