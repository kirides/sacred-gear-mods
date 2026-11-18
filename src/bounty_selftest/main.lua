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

local function bounty(id, def, title, names, target, n, gold, item, left)
    return {id = id, def = def, title = title, names = names, target = target, min_level = 1, gold = gold, item = item,
        left = left, n = n, done = false, text = 'Defeat ' .. target .. ' ' .. table.concat(names, '/') .. ' creatures'}
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
    local gold0 = hero:gold()
    local hx, hy = hero:position()
    for i = 1, 4 do W.spawn('ZOMBIE.GRN', hx + 60 * i, hy + 40, {label = 'bounty'}) end
    gear.wait(2)
    for _ = 1, 160 do
        local h = W.hero()
        if h then h:set_hp(99999) end
        A.click(830, 475)
        gear.wait(0.6)
        ctx = query()
        if ctx.payload.bounties[1].done then break end
    end
    ctx = query()
    local z = ctx.payload.bounties[1]
    check('zombie kills counted', z and z.n >= 2 and z.done, z and (z.n .. '/' .. z.target))
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
