-- Screenshots for the README. Needs -gear-auto; the phase comes from config.lua (written by run.ps1):
--   mods     the mod manager (F11)
--   loot     the loot filter's overlay with the labels (Alt) and its settings panel
--   layout   the layout editor (Alt, "Edit layout"), a window selected
--   autosave the note after an autosave
-- (mods: run.ps1 deletes this folder while the game runs, so that the Mods screen does not list it.)
-- Files go to GearAutomation\<instance>\.
if not gear.auto then return end
local A, ui, W = gear.auto, gear.ui, gear.world
local phase = gear.config.phase

local function hero_pos()
    local h = W.hero()
    local x, y, layer = h:position()
    return x, y, layer
end

local function spawn_items()
    local types = gear.data.object_types
    local x, y, layer = hero_pos()
    local n = 0
    for _, kind in ipairs({'SWORD', 'AXE', 'HELMET', 'RING'}) do
        local ok, found = pcall(function() return types:search(kind, 3) end)
        if ok and found then
            for _, r in ipairs(found) do
                n = n + 1
                W.spawn(r.id, x + 70 * math.cos(n * 0.9), y + 70 * math.sin(n * 0.9), {layer = layer})
            end
        end
    end
    for id = 1, types:count() - 1 do
        if types:kind(id) == 9 and n < 16 then
            n = n + 1
            W.spawn(id, x + 70 * math.cos(n * 0.9), y + 70 * math.sin(n * 0.9), {layer = layer})
        end
    end
    return n
end

gear.task(function()
    A.wait_for_menu(120)
    if not A.wait_for_game(180) then A.write('error.txt', 'no game') return A.quit(1) end
    gear.wait(4)
    if phase == 'mods' then
        -- run.ps1 removes this mod's folder once it sees ready.txt, so that the Mods screen lists only the real mods
        A.write('ready.txt', 'ready')
        gear.wait(8)
        A.press('f11')
        gear.wait(1.5)
        A.screenshot('mod-manager')
    elseif phase == 'loot' then
        local n = spawn_items()
        A.write('spawned.txt', tostring(n))
        gear.wait(2)
        A.key_down('alt')
        gear.wait(1)
        A.screenshot('loot-overlay')
        A.key_up('alt')
        gear.wait(0.5)
        A.press('f5')
        gear.wait(1.5)
        A.screenshot('loot-settings')
    elseif phase == 'layout' then
        local s = ui.state()
        A.key_down('alt')
        gear.wait(1)
        A.ui_click(s.screen_left + 44, s.screen_top + 14)
        A.key_up('alt')
        gear.wait(1)
        A.write('edit_mode.txt', tostring(ui.edit_mode()))
        A.press('i')
        gear.wait(1.5)
        A.screenshot('layout-1-edit')
        for _, w in ipairs(ui.windows()) do
            if w.name == 'UI_WND_INVENTORY' and w.drawn then
                A.ui_click(w.x + w.width / 2, w.y + w.height / 2)
                break
            end
        end
        gear.wait(1)
        A.screenshot('layout-2-selected')
    elseif phase == 'autosave' then
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
