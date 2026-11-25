-- Self test of npc-example (Sacred.exe -gear-auto -gear-load=10 -gear-mods=npc-example,npc-example_selftest, in a copy of the game folder).
local A = gear.auto
local results = {}
local function check(name, ok, detail)
    results[#results + 1] = {name = name, ok = ok and true or false, detail = detail}
    gear.log(('npc-example selftest: %s %s %s'):format(ok and 'PASS' or 'FAIL', name, detail or ''))
end
local function finish()
    local failed = 0
    for _, r in ipairs(results) do if not r.ok then failed = failed + 1 end end
    A.write('result.json', gear.json.encode(results))
    A.quit(failed == 0 and 0 or 1)
end

gear.task(function()
    A.wait_for_menu(120)
    A.wait_for_game(180)
    local hero = gear.world.hero()
    local nirael
    gear.wait_until(function()
        local hx, hy = hero:position()
        for _, c in ipairs(gear.world.creatures_near(hx, hy, 1500, {limit = 60})) do
            local n = c:display_name()
            if n == 'Nirael the Collector' or n == 'Nirael die Sammlerin' then nirael = c return true end
        end
    end, 40)
    check('Nirael is placed with her own name', nirael ~= nil)
    if not nirael then return finish() end
    gear.wait(1)
    -- a click on her: the world pick does not see injected input in an isolated run (see gear/examples/npctest), so the mod is asked to open the dialog
    gear.emit('npc-example.talk')
    gear.wait(1)
    A.screenshot('npc-example-dialog')
    local x, y, w, h = A.widget('opt1', 'npc-example')
    check('the dialog is open with its first button', x ~= nil)
    if x then A.ui_click(x + w / 2, y + h / 2) gear.wait(1) end
    local px = A.widget('close', 'npc-example')
    check("the button opened the mod's own window", px ~= nil)
    A.screenshot('npc-example-window')
    finish()
end)
