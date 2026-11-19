-- The loot filter's self test (main.lua loads it only with -gear-auto):
--     Sacred.exe -gear-auto -gear-load=1 -gear-mods=lootfilter
-- Items spawned at the hero's feet, the rules applied to them, the labels shown, a click on the spot (which picks up
-- what lies there, nearest first), and a check of what is left. `probe` gives access to the filter's state in main.lua.
return function(probe)
    local cfg, ui, W, S = gear.config, gear.ui, gear.world, gear.settings
    local A = gear.auto
    local results = {passed = 0, failed = 0, items = {}}

    local function check(name, ok, detail)
        if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
        print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
    end

    local function describe(it)
        return ('%d %s kind 0x%x %s rarity %d classes [%s]%s%s keep %s %s'):format(it.id, tostring(it.type_name), it.kind,
            it.category, it.rarity, table.concat(it.classes, ','), it.potion and (' potion ' .. it.potion) or '',
            it.set and ' set' or '', tostring(it.keep), it.why or '')
    end

    local function first_type(text)
        for _, r in ipairs(gear.data.object_types:search(text, 50)) do
            if r.kind ~= 0 then return r.id, r.name end
        end
    end

    gear.task(function()
        check('main menu', A.wait_for_menu(120))
        if not A.wait_for_game(180) then
            check('game with a hero', false)
            A.write('lootfilter.json', gear.json.encode(results))
            return A.quit(1)
        end
        gear.wait(3)
        local hero = W.hero()
        local cls = hero:class()
        check('hero class', cls ~= nil, cls)
        results.class = cls

        -- What lies around already.
        probe.refresh()
        for _, it in ipairs(probe.last_items()) do results.items[#results.items + 1] = describe(it) end
        print(('%d items around the hero, %d filtered'):format(probe.stats.near, probe.stats.blocked))
        for i = 1, math.min(#probe.last_items(), 25) do print('  ' .. describe(probe.last_items()[i])) end

        -- The potion types (kind 9), and a few weapons around the hero with their labels before any rule: their
        -- colours against the rarity read.
        local types = gear.data.object_types
        local potions = {}
        for id = 1, types:count() - 1 do
            if types:kind(id) == 9 then potions[#potions + 1] = ('%d %s'):format(id, tostring(types:name(id))) end
        end
        results.potion_types = potions
        print('potion types: ' .. table.concat(potions, '; '))
        local x, y, layer = hero:position()
        cfg.enabled = false
        probe.refresh()
        local swords = {}
        for i, r in ipairs(types:search('SWORD', 6)) do
            local s = W.spawn(r.id, x + 60 * math.cos(i), y + 60 * math.sin(i), {layer = layer})
            local it = s and W.item(s.id)
            if it then swords[#swords + 1] = it; print('sample: ' .. describe(it)) end
        end
        check('no overlay without Alt', not probe.overlay_shown())
        A.screenshot('showtext-off')
        A.key_down('alt')
        gear.wait(0.5)
        check('overlay with Alt', probe.overlay_shown() and ui.state().show_text)
        A.screenshot('lootfilter-samples')
        A.screenshot('showtext-on')
        local function overlay_panel()
            for _, q in ipairs(ui.panels()) do
                if q.key == 'lootfilter:overlay' then return q end
            end
        end
        local op = overlay_panel()
        check('overlay is a layout panel', op ~= nil)
        A.key_up('alt')
        gear.wait(0.8)
        -- The layout editor's edit mode shows it without Alt, and a moved place sticks (set_panel_rect is what the editor calls).
        ui.set_edit_mode(true)
        gear.wait(0.5)
        check('overlay shown in the edit mode without Alt', probe.overlay_shown())
        if op then
            check('moved by the layout editor', ui.set_panel_rect('lootfilter:overlay', op.x + 300, op.y + 100))
            gear.wait(0.5)
            local q = overlay_panel()
            check('overlay at its new place', q and math.abs(q.x - (op.x + 300)) < 3 and math.abs(q.y - (op.y + 100)) < 3,
                q and ('%d,%d -> %d,%d'):format(op.x, op.y, q.x, q.y))
            A.screenshot('lootfilter-edit-moved')
            ui.reset_panel('lootfilter:overlay')
            gear.wait(0.3)
        end
        ui.set_edit_mode(false)
        gear.wait(0.8)
        check('overlay gone again after the edit mode', not probe.overlay_shown())
        -- "Show overlay" off in the mod's settings: not even with Alt.
        S.set('overlay', false)
        gear.wait(0.3)
        A.key_down('alt')
        gear.wait(0.5)
        check('overlay off: not shown with Alt', not probe.overlay_shown() and ui.state().show_text)
        A.screenshot('showtext-overlay-off')
        A.key_up('alt')
        S.set('overlay', true)
        gear.wait(0.3)
        cfg.enabled = true

        -- Two items at the hero's feet: a health potion (kept) and a weapon, refused by a test rule.
        local potion_type, potion_name = 0x13C0, types:name(0x13C0)   -- the small health potion
        if not potion_type and potions[1] then
            potion_type = tonumber(potions[1]:match('^%d+'))
            potion_name = types:name(potion_type)
        end
        local weapon_type, weapon_name = first_type('SWORD')
        results.types = {potion = potion_name, weapon = weapon_name}
        print(('spawning %s and %s'):format(tostring(potion_name), tostring(weapon_name)))
        local potion = potion_type and W.spawn(potion_type, x + 20, y + 20, {layer = layer})
        local weapon = weapon_type and W.spawn(weapon_type, x - 20, y - 20, {layer = layer})
        check('spawned a potion and a weapon', potion ~= nil and weapon ~= nil)
        cfg.categories.weapon = false
        probe.refresh()
        local pi, wi = potion and W.item(potion.id), weapon and W.item(weapon.id)
        if pi then print('potion: ' .. describe(pi)) end
        if wi then print('weapon: ' .. describe(wi)) end
        check('the potion is an item', pi and pi.category == 'potion', pi and pi.category)
        check('the weapon is an item', wi and wi.category == 'weapon', wi and wi.category)
        local blocked_weapon = false
        for _, it in ipairs(probe.last_items()) do
            if wi and it.id == wi.id then blocked_weapon = it.keep == false end
        end
        check('the weapon is filtered', blocked_weapon)

        -- Labels (Alt), then a click where the hero stands: the game walks to the nearest item there.
        A.key_down('alt')
        gear.wait(0.5)
        A.screenshot('lootfilter-labels')
        A.key_up('alt')
        local s = A.state()
        local before = W.pickup_refused()
        for _ = 1, 4 do
            A.click(math.floor(s.width / 2), math.floor(s.height / 2))
            gear.wait(1.5)
        end
        A.screenshot('lootfilter-after')
        local p2, w2 = pi and W.item(pi.id), wi and W.item(wi.id)
        results.after = {potion = p2 and p2.on_ground, weapon = w2 and w2.on_ground, refused = W.pickup_refused() - before}
        print(('after the clicks: potion on the ground %s, weapon on the ground %s, refused %d'):format(
            tostring(p2 and p2.on_ground), tostring(w2 and w2.on_ground), W.pickup_refused() - before))
        check('the weapon stays on the ground', w2 and w2.on_ground)

        -- The settings panel: opened from the overlay's button, a quality picked, a potion unticked, saved.
        local oh = 18 + (7 + #probe.CATEGORIES) * 13
        A.key_down('alt')                           -- the overlay and its button show with the labels
        for _ = 1, 20 do
            if probe.overlay_shown() then break end
            gear.wait(0.1)
        end
        gear.wait(0.2)
        A.ui_click(cfg.overlay_x + 90, cfg.overlay_y + oh + 14)
        A.key_up('alt')
        gear.wait(0.5)
        check('settings panel opens', ui.panel_open('settings'))
        check('it stays open without Alt', ui.panel_open('settings') and not probe.overlay_shown())
        A.screenshot('lootfilter-settings')
        local px, py = 248, 98 + 26 + 90           -- content (248, 98); the quality row
        A.ui_click(px + 190, py + 9)                -- the lowest quality dropdown
        gear.wait(0.5)
        A.screenshot('lootfilter-settings-dropdown')
        A.ui_click(px + 190, py + 18 + 1 + 18 + 9)  -- its second entry: magic
        gear.wait(0.5)
        check('lowest quality from the dropdown', cfg.min_quality == 'magic', cfg.min_quality)
        local potions_y = py + 30 + 4 * 24 + 8 + 18
        A.ui_click(px + 200 + 7, potions_y + 8)     -- the stamina checkbox
        gear.wait(0.5)
        check('potion checkbox', cfg.potions.stamina == false, tostring(cfg.potions.stamina))
        A.screenshot('lootfilter-settings-saved')
        check('settings kept in the mod manager', S.get('min_quality') == 'magic' and S.get('potion_stamina') == false,
            tostring(S.get('min_quality')) .. ' ' .. tostring(S.get('potion_stamina')))
        S.reset()      -- leave the state as it was
        A.write('lootfilter.json', gear.json.encode(results))
        print(('%d passed, %d failed'):format(results.passed, results.failed))
        if cfg.test_quit then A.quit(results.failed == 0 and 0 or 1) end
    end)
end
