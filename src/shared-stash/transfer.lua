-- Moving items between the hero's backpack / chest and the stash file.
--
-- Order of the steps, so that a crash or a failed write can leave an item in both places but never in neither:
--   deposit:  write the stash file (with the item) -> take the item out of the character
--   withdraw: put the item into the character     -> write the stash file (without it)
-- If the second step of either fails, the first is undone. See README.md for the policy on older savegames.
local stash = require('stash')

local M = {}
local cfg = gear.config
local inv, world = gear.inv, gear.world

-- Whether an item may move: gold, quest items and (unless config.allow_special) "special" items never do.
function M.transferable(it)
    if it.gold then return false, 'gold cannot be stashed' end
    if it.quest then return false, 'quest items cannot be stashed' end
    if it.category == 'special' and not cfg.allow_special then return false, 'special items are not moved' end
    return true
end

function M.pretty_name(it)
    local n = (it.type_name or ('type ' .. tostring(it.type))):gsub('%.%w+$', ''):gsub('_', ' ')
    return n
end

local function entry_of(it, bytes)
    local hero = world.hero()
    return {
        name = M.pretty_name(it), quality = it.quality, category = it.category, w = it.w, h = it.h,
        class = it.classes[1] and table.concat(it.classes, ',') or 'any',
        from = hero and hero:class() or nil, time = os.time(),
        data = inv.hex(bytes),
    }
end

-- The containers whose items may be stashed, in order.
function M.sources()
    local list = {}
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then list[#list + 1] = {name = which, container = c} end
    end
    return list
end

-- Deposits item `it` (an entry of container:items()) of `container`. true | nil, message.
function M.deposit(container, it)
    if not world.can_change() then return nil, 'only in a single player game' end
    if stash.problem then return nil, stash.problem end
    local ok, why = M.transferable(it)
    if not ok then return nil, why end
    local bytes, err = inv.export(it.id)
    if not bytes then return nil, err end
    local entry, aerr = stash.add(entry_of(it, bytes), cfg.max_items)
    if not entry then return nil, aerr end
    local got, rerr = inv.remove(container, it.id)
    if not got then
        stash.discard(entry.uid)
        return nil, rerr
    end
    return true
end

-- Withdraws stash entry `entry` into the backpack (or the chest when the backpack has no room). true, where | nil,
-- message.
function M.withdraw(entry)
    if not world.can_change() then return nil, 'only in a single player game' end
    if stash.problem then return nil, stash.problem end
    local bytes = inv.unhex(entry.data)
    if not bytes then return nil, 'the stash entry is damaged' end
    local placed, where
    for _, which in ipairs({'backpack', 'chest'}) do
        local c = inv.container(which)
        if c then
            local id = inv.add(c, bytes)
            if id then placed, where = {c, id}, which break end
        end
    end
    if not placed then return nil, 'no room in the backpack or the chest' end
    local taken, terr = stash.take(entry.uid, cfg.recent)
    if not taken then
        inv.remove(placed[1], placed[2])
        return nil, terr
    end
    return true, where
end

-- Puts a recently withdrawn entry back into the stash file only (the item in the character stays where it is).
function M.restore(entry)
    if stash.problem then return nil, stash.problem end
    return stash.restore(entry.uid, cfg.max_items)
end

return M
