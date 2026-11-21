-- Screenshots for the README. Needs -gear-auto; the phase comes from config.lua (written by run.ps1):
--   autosave        the note after an autosave
--   types           writes some object type ids (to find a monster name)
--   fight           a real fight, then pictures of the damage meter, loot log and session tracker
--   lootfilter      the filter panel
--   layout          the layout editor's button (Alt held)
--   modscreen       the Mods screen (F11)
--   menumods        the Mods screen from the start menu (run without -gear-load)
--   gold            gives the hero config.gold (for a self test that needs gold)
-- Files go to GearAutomation\<instance>\.
if not gear.auto then return end
local A = gear.auto
local phase = gear.config.phase

local function shot(name) gear.wait(1); A.screenshot(name) end
local function chord(mod, key) A.key_down(mod); A.press(key); A.key_up(mod) end

gear.task(function()
    A.wait_for_menu(120)
    if phase == 'menumods' then
        -- the Mods screen from the start menu (no savegame loaded): for pages that are only live outside a game (the realm picker)
        if gear.config.realm then gear.realm.add(gear.config.realm) end
        gear.wait(3)
        A.press('f11')
        gear.wait(1)
        for _, c in ipairs(gear.config.clicks or {}) do A.click(c[1], c[2]); gear.wait(1.2) end
        gear.wait(3)
        shot('menumods')
        return A.quit(0)
    end
    if not A.wait_for_game(180) then A.write('error.txt', 'no game') return A.quit(1) end
    if phase == 'gold' then
        -- gives the hero gold and stays out of the way (for self tests that need some: the auction house)
        gear.world.hero():set_gold(gear.config.gold or 50000)
        return
    end
    gear.wait(4)
    if phase == 'autosave' then
        gear.emit('autosave.configure', {enabled = true, interval_minutes = 0.05, persist = false})
        for i = 1, 40 do
            gear.wait(0.5)
            local out = {}
            gear.emit('autosave.query', out)
            if (out.saves or 0) > 0 then
                gear.wait(1)
                A.screenshot('autosave-note')
                A.write('autosave.txt', gear.json.encode(out))
                break
            end
        end
    elseif phase == 'types' then
        local found = {}
        for _, q in ipairs({'wolf', 'goblin', 'skeleton', 'orc', 'zombie', 'spider', 'rat'}) do
            for _, m in ipairs(gear.data.object_types:search(q, 8)) do
                found[#found + 1] = tostring(m.id) .. ' ' .. tostring(m.name) .. ' kind ' .. tostring(m.kind)
            end
        end
        A.write('types.txt', table.concat(found, ' | '))
    elseif phase == 'findtest' then
        -- which of config.names are object types the game can spawn?
        local res = {}
        for _, n in ipairs(gear.config.names or {}) do
            local id = gear.data.object_types:find(n)
            local hero = gear.world.hero()
            local hx, hy = hero:position()
            local c, why = gear.world.spawn(id or n, hx + 200, hy + 200, {label = 'shot'})
            res[#res + 1] = n .. ' id=' .. tostring(id) .. ' spawn=' .. (c and 'ok' or tostring(why))
        end
        A.write('findtest.txt', table.concat(res, ' ; '))
    elseif phase == 'twitch' then
        -- the action mod answers twitch.command events (a viewer's raid); monsters carry the viewer's name
        local ctx = {command = 'TWI_Raid', argv = {'3'}, user = 'Viewer42'}
        gear.emit('twitch.command', ctx)
        A.write('twitch.txt', 'handled=' .. tostring(ctx.handled) .. ' defer=' .. tostring(ctx.defer))
        gear.wait(2)
        A.key_down('alt')
        gear.wait(1)
        A.screenshot('twitch')
        A.release()
    elseif phase == 'server' then
        -- The server mods without a server: what the game server's script would send is handed to the mod's own channel
        -- handlers (the real mod draws it). config.which: achievements, bounty, buildsharer, questhelper, serverfeed.
        local function say(name, payload)
            local ch = gear.net.channel(name)
            local list = {}
            for i, fn in ipairs(ch.handlers) do list[i] = fn end
            for _, fn in ipairs(list) do fn({slot = 0}, payload) end
        end
        local w = gear.config.which
        -- the quest helper's records tab needs a network game: let the mod believe in one
        if w == 'questhelper' and gear.mp and gear.mp.force_network then gear.mp.force_network(true) end
        if w == 'achievements' then
            say('achievements:sync', {op = 'state', streak = 5, best = 9, days = 23, claimed = true, next = '250 gold', ach = {
                {name = 'Monster Hunter', desc = 'Kill 100 monsters', done = true},
                {name = 'Deep Delver', desc = 'Reach the second dungeon level', need = 5, have = 3},
                {name = 'Gold Hoarder', desc = 'Carry 10000 gold', need = 10000, have = 4200},
                {name = 'Collector', desc = 'Find 10 magic items', need = 10, have = 7},
            }})
            say('achievements:sync', {op = 'unlock', name = 'Monster Hunter', desc = 'Kill 100 monsters', reward = '500 gold'})
            if gear.config.press then A.key_down('control'); A.press('g'); A.key_up('control') end
        elseif w == 'bounty' then
            say('bounty:state', {v = 1, bounties = {
                {title = 'Wolf hunt', text = 'Kill wolves near the village', n = 12, target = 20, left = 4800, reward = '500 gold'},
                {title = 'The orc chief', text = 'Slay the orc chief', n = 0, target = 1, left = 11100, reward = 'A rare weapon', level = 10},
                {title = 'Pest control', text = 'Kill giant spiders', n = 8, target = 8, done = true, left = 600, reward = '200 gold'},
            }})
            if gear.config.press then A.key_down('control'); A.press('j'); A.key_up('control') end
        elseif w == 'buildsharer' then
            say('buildsharer', {op = 'list', total = 3, page = 1, pages = 1, builds = {
                {id = 'b1', name = 'Ria', class_name = 'Seraphim', level = 42, title = 'Fire storm', verified = true},
                {id = 'b2', name = 'Kell', class_name = 'Gladiator', level = 37, title = 'Tank for two', verified = true},
                {id = 'b3', name = 'Tomm', class_name = 'Wood Elf', level = 44, title = 'Bow and traps', verified = false},
            }})
            if gear.config.press then gear.ui.show_panel('buildsharer:main', true) end
        elseif w == 'questhelper' then
            say('questhelper', {op = 'state', available = true, total = 2, known = 2, catalog = 2, records = {
                {key = 100, value = 1, name = 'The lost sword', area = 'Ancaria', hint = 'Ask the smith.', label = 'started', known = true},
                {key = 101, value = 2, name = 'The lost caravan', area = 'Ancaria', hint = 'Look near the east bridge.', label = 'step 2', known = true},
            }})
            if gear.config.press then gear.ui.show_panel('questhelper:main', true) end
        elseif w == 'serverfeed' then
            say('rare_drops:feed', {kind = 'drop', drop = {item = 'Ancient Sword of Fire', tier = 'unique', rarity = 15, by = 'Ria', from = 'Orc chief'}})
            say('graveyard:feed', {kind = 'death', name = 'Kell', level = 37, by = 'Zombie', killer_kind = 'monster'})
            say('rare_drops:feed', {kind = 'drop', drop = {item = 'Ring of Quickness', tier = 'rare', rarity = 12, by = 'Tomm'}})
        end
        gear.wait(1.5)
        for _, c in ipairs(gear.config.clicks or {}) do A.click(c[1], c[2]); gear.wait(1) end
        gear.wait(gear.config.wait or 0)
        shot('server-' .. tostring(w))
    elseif phase == 'fight' then
        -- a real fight: zombies spawned next to the hero; the hero attacks them (and is kept alive) until they are dead. The damage
        -- meter (Ctrl+D), the loot log (F3) and the session tracker (F2, open by default) record it; one picture of each follows.
        local hero = gear.world.hero()
        local hx, hy, layer = hero:position()
        for i = 1, (gear.config.count or 5) do
            local c, why = gear.world.spawn(gear.config.monster or 'ZOMBIE.GRN', hx + 90 + 40 * (i % 3), hy + 40 * i - 100, {label = 'shot', layer = layer})
            A.write('spawn' .. i .. '.txt', c and 'ok' or tostring(why))
        end
        gear.wait(2)
        chord('control', 'd')
        for i = 1, 120 do
            local h = gear.world.hero()
            if h then h:set_hp(99999) end
            local best, bd
            local x, y = h:position()
            for _, c in ipairs(gear.world.creatures_near(x, y, 2500, {layer = layer})) do
                if not c:is_dead() and h:is_enemy(c) and not c:is_hero() then
                    local cx, cy = c:position()
                    local d = (cx - x) ^ 2 + (cy - y) ^ 2
                    if not bd or d < bd then best, bd = c, d end
                end
            end
            if not best then break end
            if gear.config.foe_hp and (best:hp() or 0) > gear.config.foe_hp then best:set_hp(gear.config.foe_hp) end
            h:order_attack(best)
            gear.wait(0.7)
            if i == (gear.config.meter_at or 14) then A.screenshot('damagemeter') end
        end
        gear.wait(2)
        chord('control', 'd')
        A.press('f3')
        shot('lootlog')
        A.press('f3')
        shot('sessiontracker')
    elseif phase == 'lootfilter' then
        A.press('f5')
        shot('lootfilter')
    elseif phase == 'layout' then
        A.key_down('alt')
        gear.wait(1)
        A.screenshot('layout-alt')
        A.release()
    elseif phase == 'modscreen' then
        -- the Mods screen, then clicks (config.clicks = {{x, y}, ...} in client pixels), then the picture
        if gear.config.realm then gear.realm.add(gear.config.realm) end
        A.press('f11')
        gear.wait(1)
        -- {x, y} clicks; {x, y, wheel = n} moves there and turns the mouse wheel n notches (negative: down)
        for _, c in ipairs(gear.config.clicks or {}) do
            if c.wheel then A.move(c[1], c[2]); gear.wait(0.3); A.wheel(c.wheel) else A.click(c[1], c[2]) end
            gear.wait(1.2)
        end
        gear.wait(5)
        shot('modscreen')
    end
    A.quit(0)
end)
