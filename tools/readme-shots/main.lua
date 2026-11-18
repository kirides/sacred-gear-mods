-- Screenshots for the README. Needs -gear-auto; the phase comes from config.lua (written by run.ps1):
--   autosave        the note after an autosave
--   types           writes some object type ids (to find a monster name)
--   fight           a real fight, then pictures of the damage meter, loot log and session tracker
--   lootfilter      the filter panel
--   layout          the layout editor's button (Alt held)
--   modscreen       the Mods screen (F11)
-- Files go to GearAutomation\<instance>\.
if not gear.auto then return end
local A = gear.auto
local phase = gear.config.phase

local function shot(name) gear.wait(1); A.screenshot(name) end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then A.write('error.txt', 'no game') return A.quit(1) end
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
    elseif phase == 'fight' then
        -- a real fight: zombies spawned next to the hero, the hero attacks them (clicks) and is kept alive.
        -- The damage meter, the loot log and the session tracker record it; one picture of each follows.
        local hero = gear.world.hero()
        local hx, hy = hero:position()
        A.press('f7')
        for i = 1, 4 do
            local c, why = gear.world.spawn(gear.config.monster or 'ZOMBIE.GRN', hx + 60 * i, hy + 40, {label = 'shot'})
            A.write('spawn' .. i .. '.txt', c and 'ok' or tostring(why))
        end
        gear.wait(2)
        for i = 1, 40 do
            local h = gear.world.hero()
            if h then h:set_hp(99999) end
            A.click(830, 475)
            gear.wait(0.6)
        end
        shot('damagemeter')
        A.press('f7')
        A.press('f3')
        shot('lootlog')
        A.press('f3')
        A.press('f2')
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
        for _, c in ipairs(gear.config.clicks or {}) do A.click(c[1], c[2]); gear.wait(1.2) end
        gear.wait(5)
        shot('modscreen')
    end
    A.quit(0)
end)
