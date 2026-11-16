-- Screenshots for the README. Needs -gear-auto; the phase comes from config.lua (written by run.ps1):
--   autosave the note after an autosave
-- Files go to GearAutomation\<instance>\.
if not gear.auto then return end
local A = gear.auto
local phase = gear.config.phase

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
    end
    A.quit(0)
end)
