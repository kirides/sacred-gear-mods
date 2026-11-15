---@type GearModManifest
return {
    id = 'shared-stash',
    name = 'Shared stash',
    version = '0.1.0',
    automation = true,      -- only for its self test (-gear-auto)
    -- The defaults; config.lua in this folder overrides them.
    config = {
        enabled = true,
        hotkey = 'f10',         -- opens and closes the stash panel in game ('' for none)
        max_items = 200,        -- the stash holds at most this many items (its file is limited to 1 MB)
        allow_special = false,  -- also move "special" items (horse gear, ...); quest items and gold never move
        recent = 30,            -- how many withdrawn items the file remembers for "Recent withdrawals"
        -- self test only (-gear-auto): 'deposit', 'withdraw', 'ui' or 'roundtrip'; see selftest.lua
        selftest = false,
    },
}
