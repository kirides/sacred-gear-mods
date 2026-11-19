-- Self test of the bounty mod's single player board. Needs -gear-auto and a savegame (-gear-load) with a hero in a safe
-- place; run with -gear-mods=bounty,bounty_selftest. Result: GearAutomation\<instance>\bounty_selftest.txt (PASS / FAIL lines)
-- and pictures (config.shots).
if not gear.auto then return end
local A = gear.auto
local W = gear.world
local lines, failed = {}, false

local function say(s) lines[#lines + 1] = s; A.write('bounty_selftest.txt', table.concat(lines, '\n')) end
local function check(name, ok, detail)
    say((ok and 'PASS ' or 'FAIL ') .. name .. (detail and (' (' .. tostring(detail) .. ')') or ''))
    if not ok then failed = true end
end
local function query() local ctx = {op = 'query'} gear.emit('bounty.test', ctx) return ctx end

local function bounty(id, def, title, names, target, n, gold, item, left, types)
    return {id = id, def = def, title = title, names = names, types = types or {}, target = target, min_level = 1, gold = gold, item = item,
        left = left, n = n, done = false, text = 'Defeat ' .. target .. ' ' .. table.concat(names, '/') .. ' creatures'}
end

-- Fights the spawned zombies until `done()` is true (true) or `rounds` pass (false). The hero is ordered to attack the nearest one
-- (the order of a click on it): a click at a fixed screen position only hit when a zombie happened to stand there, so some runs
-- killed one zombie in a minute and failed the kill and gold checks. When the order is refused the old click is the fallback.
-- New zombies come when none is left.
local function fight(done, rounds)
    for i = 1, rounds do
        local h = W.hero()
        if h then
            h:set_hp(99999)
            local px, py, layer = h:position()
            local best, best_d
            for _, c in ipairs(W.creatures_near(px, py, 1200, {limit = 64, layer = layer}) or {}) do
                if c.id > 16 and not c:is_dead() and c:label() == 'bounty' and c:type_name() == 'ZOMBIE.GRN' then
                    local x, y = c:position()
                    local d = x and ((x - px) ^ 2 + (y - py) ^ 2) or nil
                    if d and (not best_d or d < best_d) then best, best_d = c, d end
                end
            end
            if not best then
                for k = 1, 2 do W.spawn('ZOMBIE.GRN', px + 50 * k, py + 40, {label = 'bounty', layer = layer}) end
            elseif not h:order_attack(best) then
                A.click(830, 475)
            end
        end
        gear.wait(0.6)
        if done() then return true end
    end
    return false
end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then say('FAIL no game') return A.quit(1) end
    gear.wait(4)
    local hero = W.hero()
    local ctx
    gear.wait_until(function() ctx = query() return ctx.payload ~= nil end, 15)
    say('ctx ' .. gear.json.encode({lm = ctx.local_mode, file = ctx.file, has = ctx.payload ~= nil}))
    check('single player board is up', ctx.local_mode and ctx.payload and #ctx.payload.bounties == 3,
        ctx.payload and #ctx.payload.bounties)
    -- known bounties: three zombies for gold and an item, a wolf bounty and spiders
    gear.emit('bounty.test', {op = 'set', list = {
        bounty(901, 'undead', 'Grave watch', {'zombie'}, 2, 0, 500, 1, 7200),
        bounty(902, 'beasts', 'Beast hunter', {'wolf', 'bear'}, 20, 8, 700, nil, 4800),
        bounty(903, 'spiders', 'Web cleaner', {'spider'}, 15, 5, 800, 1, 9000),
        -- the same kills by type id (no words): what a bounty picked by name is saved as
        bounty(904, 'zombies-by-id', 'Zombie by id', {}, 2, 0, 0, nil, 7200, {gear.data.object_types:find('ZOMBIE.GRN')}),
    }})
    if gear.config.phase == 'shots' then
        -- the README picture: the real panel and tracker with a board in progress (the numbers are examples)
        gear.emit('bounty.test', {op = 'set', list = {
            bounty(911, 'orcs', 'Orc slayer', {'orc'}, 32, 21, 1200, nil, 6300),
            bounty(912, 'spiders', 'Web cleaner', {'spider'}, 18, 18, 800, 1, 4100),
            bounty(913, 'undead', 'Grave watch', {'skeleton', 'zombie', 'mummy', 'ghost'}, 40, 7, 1500, nil, 9400),
        }})
        gear.emit('bounty.test', {op = 'set_done', id = 912})
        A.key_down('control'); A.press('j'); A.key_up('control')
        gear.wait(2)
        A.screenshot('bounty-panel')
        return A.quit(0)
    end
    if gear.config.phase == 'fuzzy' then
        for _, q in ipairs({'schwert', 'scwert', 'sword bastard', 'drgn', 'dragn', 'orcs', 'zombi', 'heiltrank', 'trank heil', 'flugel', 'leather elf', 'xyzq'}) do
            local c = {op = 'fuzzy', q = q}
            gear.emit('bounty.test', c)
            local items = {}
            for i = 1, math.min(5, #c.items) do items[i] = c.items[i] end
            local cr = {}
            for i = 2, math.min(5, #c.creatures) do cr[#cr + 1] = c.creatures[i] end
            say(('%s => items(%d): %s | creatures: %s'):format(q, #c.items, table.concat(items, '; '), table.concat(cr, ', ')))
        end
        return A.quit(0)
    end
    if gear.config.phase == 'toasts' then
        gear.emit('bounty.test', {op = 'toast', title = 'Bounty complete: Orc slayer', lines = {'Reward: 1500 gold and an item'}})
        gear.emit('bounty.test', {op = 'toast', title = 'New bounty', lines = {'Web cleaner', 'Defeat 18 spider creatures, or as many as the long text needs to wrap onto a second line'}})
        gear.emit('bounty.test', {op = 'toast', title = 'Bounty ended', lines = {}})
        gear.wait(1)
        A.screenshot('toasts')
        return A.quit(0)
    end
    if gear.config.phase == 'editor' then
        gear.emit('bounty.test', {op = 'start_custom', def = {id = 'orc-challenge', title = 'Orc challenge', names = {'orc'}, target = 25,
            minutes = 0, min_level = 1, gold = 2500, item = {mode = 'specific', tier = 1, types = {{id = 1, name = 'Sword of the stream'}}},
            trigger = {on = true, names = {'orc'}, count = 10, cooldown = 30}}})
        gear.emit('bounty.test', {op = 'open_editor'})
        gear.wait(7)        -- the toast of the start is gone
        A.screenshot('editor-list')
        gear.emit('bounty.test', {op = 'open_form', def = 'orc-challenge'})
        gear.wait(1)
        if gear.config.type_test then
            A.click(780, 321) -- (type test)
            gear.wait(0.5)
            A.screenshot('editor-click')
            A.type(gear.config.type_text or 'klinge')
            gear.wait(1)
            A.screenshot('editor-search')
        end
        A.screenshot('editor-form')
        -- the creature picker: open the dropdown, pick the third entry, look at the chips
        A.click(800, 152)
        gear.wait(1)
        A.screenshot('editor-dropdown')
        A.click(800, 152 + 22 * 4)
        gear.wait(1)
        A.screenshot('editor-added')
        return A.quit(0)
    end
    if gear.config.phase == 'custom' then
        local def = {id = 'ta', title = 'Zombie test', names = {'zombie'}, target = 1, minutes = 0, min_level = 1, gold = 300,
            item = {mode = 'class', tier = 2, types = {}}, trigger = {on = true, names = {'orc'}, count = 3, cooldown = 30}}
        local gold0 = hero:gold()
        gear.emit('bounty.test', {op = 'start_custom', def = def})
        ctx = query()
        local b = ctx.payload.bounties[1]
        check('custom bounty started', b and b.custom and b.def == 'ta' and b.endless and not b.done)
        local hx, hy = hero:position()
        for i = 1, 4 do W.spawn('ZOMBIE.GRN', hx + 60 * i, hy + 40, {label = 'bounty'}) end
        gear.wait(2)
        fight(function() ctx = query() return ctx.payload.bounties[1].done end, 200)
        A.screenshot('after-fight')
        ctx = query()
        check('custom bounty done', ctx.payload.bounties[1].done, ctx.payload.bounties[1].n)
        gear.wait(8)
        check('gold paid', W.hero():gold() >= gold0 + 300, W.hero():gold() - gold0)
        local px, py = W.hero():position()
        local usable, total = 0, 0
        for _, it in ipairs(W.items_near(px, py, 500, {limit = 64})) do
            total = total + 1
            if W.usable_by(it, W.hero():class()) then usable = usable + 1 end
        end
        check('class item dropped', usable > 0, usable .. ' of ' .. total)
        local chickens = 0
        for _, c in ipairs(W.creatures_near(px, py, 700, {limit = 64})) do
            if c:type_name() == 'HORSE.GRN' and c:label() == 'bounty' then chickens = chickens + 1 end
        end
        check('the loot carrier is removed', chickens == 0, chickens)
        -- the trigger: 3 orc kills start the finished bounty again, 3 more do nothing, after Stop the cooldown holds
        for _ = 1, 3 do gear.emit('bounty.test', {op = 'trigger_kill', name = 'ORC_WARRIOR.GRN'}) end
        ctx = query()
        b = ctx.payload.bounties[1]
        check('trigger started it', b.def == 'ta' and not b.done and b.n == 0)
        gear.emit('bounty.test', {op = 'stop_custom', id = 'ta'})
        for _ = 1, 3 do gear.emit('bounty.test', {op = 'trigger_kill', name = 'ORC_WARRIOR.GRN'}) end
        ctx = query()
        local running = false
        for _, x in ipairs(ctx.payload.bounties) do if x.def == 'ta' then running = true end end
        check('cooldown blocks the trigger', not running)
        -- a chosen item type: the drop must be that type
        local sword = gear.data.object_types:find('SWORD_BASTARD.GRN')
        local drop = {op = 'drop', spec = {mode = 'specific', tier = 1, types = {{id = sword, name = 'SWORD_BASTARD.GRN'}}}}
        gear.emit('bounty.test', drop)
        gear.wait_until(function() return not drop.running end, 30)
        gear.wait(1)
        local px2, py2 = W.hero():position()
        local found = false
        for _, it in ipairs(W.items_near(px2, py2, 500, {limit = 64})) do if it.type == sword then found = true end end
        local seen = {} for _, it in ipairs(W.items_near(px2, py2, 500, {limit = 64})) do seen[#seen + 1] = tostring(it.type) .. ':' .. tostring(it.type_name) end
        check('chosen item type dropped', drop.ok and found, tostring(sword) .. ' -> ' .. table.concat(seen, ' '))
        say(failed and 'FAILED' or 'PASSED')
        return A.quit(failed and 1 or 0)
    end
    local gold0 = hero:gold()
    local hx, hy = hero:position()
    for i = 1, 4 do W.spawn('ZOMBIE.GRN', hx + 60 * i, hy + 40, {label = 'bounty'}) end
    gear.wait(2)
    fight(function() ctx = query() return ctx.payload.bounties[1].done and ctx.payload.bounties[4].done end, 160)
    ctx = query()
    local z = ctx.payload.bounties[1]
    check('zombie kills counted', z and z.n >= 2 and z.done, z and (z.n .. '/' .. z.target))
    local zi = ctx.payload.bounties[4]
    check('kills counted for a bounty by type id', zi and zi.n >= 2 and zi.done, zi and (zi.n .. '/' .. zi.target))
    check('other bounties untouched', ctx.payload.bounties[2].n == 8 and ctx.payload.bounties[3].n == 5)
    gear.wait(3)
    check('gold paid', W.hero():gold() >= gold0 + 500, W.hero():gold() - gold0)
    local items = 0
    local px, py = W.hero():position()
    for _ in ipairs(W.items_near(px, py, 500, {limit = 64})) do items = items + 1 end
    check('item rolled at the hero\'s feet', items > 0, items)
    A.key_down('control'); A.press('j'); A.key_up('control')
    gear.wait(1)
    if gear.config.shots then A.screenshot('bounty-panel') end
    gear.emit('bounty.test', {op = 'save'})
    say(failed and 'FAILED' or 'PASSED')
    A.quit(failed and 1 or 0)
end)
