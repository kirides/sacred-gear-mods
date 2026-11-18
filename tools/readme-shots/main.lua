-- Screenshots for the README. Needs -gear-auto; the phase comes from config.lua (written by run.ps1):
--   autosave        the note after an autosave
--   types           writes some object type ids (to find a monster name)
--   damagemeter     the meter after a real fight (monsters spawned next to the hero)
--   sessiontracker  the session panel
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
    elseif phase == 'damagemeter' then
        -- a real fight: monsters spawned next to the hero hit it; the hero is healed so it stays alive
        local hero = gear.world.hero()
        local hx, hy = hero:position()
        A.press('f7')
        for i = 1, 3 do
            local c, why = gear.world.spawn(gear.config.monster or 'Goblin', hx + 60 * i, hy + 40, {label = 'shot'})
            A.write('spawn' .. i .. '.txt', c and 'ok' or tostring(why))
        end
        gear.wait(2)
        for i = 1, 25 do
            local h = gear.world.hero()
            if h then h:set_hp(99999) end
            A.click(820, 478)          -- the hero attacks the wolves standing there
            gear.wait(0.6)
        end
        shot('damagemeter')
    elseif phase == 'sessiontracker' then
        A.press('f2')
        gear.wait(40)
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
        A.press('f11')
        shot('modscreen')
    end
    A.quit(0)
end)
