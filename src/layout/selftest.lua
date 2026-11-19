-- The layout editor's self test (main.lua loads it only with -gear-auto). Run it twice:
--     Sacred.exe -gear-auto -gear-load=1 -gear-mods=layout -gear-shared-input
-- The first run selects, drags, nudges and resizes, and quits; the second checks the places came back, takes
-- screenshots and resets the layout. `probe` gives read access to the editor's state in main.lua.
return function(probe)
    local ui = gear.ui
    local A = gear.auto
    local results = {passed = 0, failed = 0}

    local function check(name, ok, detail)
        if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
        print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail and (': ' .. tostring(detail)) or ''))
    end

    local function drag_ui(x0, y0, x1, y1)
        local px, py = A.ui_to_pixels(x0, y0)
        A.move(px, py); gear.wait(0.15); A.down(); gear.wait(0.2)
        for i = 1, 6 do
            local mx, my = A.ui_to_pixels(x0 + (x1 - x0) * i / 6, y0 + (y1 - y0) * i / 6)
            A.move(mx, my); gear.wait(0.1)
        end
        A.up(); gear.wait(0.5)
    end

    local function inventory()
        local w = ui.window('UI_WND_INVENTORY')
        if w then return w, w.x + w.frame_x, w.y + w.frame_y end
    end

    local function sample()
        for _, p in ipairs(ui.panels()) do
            if p.key == 'layout:sample' then return p end
        end
    end

    -- A point on no frame, toolbar or popup.
    local function empty_spot()
        local s = ui.state()
        local rects = probe.collect()
        if probe.toolbar_rect() then rects[#rects + 1] = probe.toolbar_rect() end
        if probe.popup_rect() then rects[#rects + 1] = probe.popup_rect() end
        for y = s.screen_top + 40, s.screen_bottom - 40, 24 do
            for x = s.screen_left + 120, s.screen_right - 40, 24 do
                local free = true
                for _, r in ipairs(rects) do
                    if x >= r.x - 4 and y >= r.y - 4 and x < r.x + r.w + 4 and y < r.y + r.h + 4 then free = false break end
                end
                if free then return x, y end
            end
        end
    end

    gear.task(function()
        check('main menu', A.wait_for_menu(120))
        if not A.wait_for_game(180) then
            check('game with a hero', false)
            return A.quit(1)
        end
        gear.wait(3)
        check('game windows can move (SacredBild)', ui.can_move_windows())
        -- The "Edit layout" button shows only while the game shows its labels (Alt held).
        gear.wait(0.5)
        check('no edit button without Alt', not ui.state().show_text and not probe.edit_button_shown())
        A.screenshot('showtext-off')
        A.key_down('alt')
        gear.wait(0.6)
        check('Alt: show_text', ui.state().show_text)
        check('Alt: edit button shown', probe.edit_button_shown())
        A.screenshot('showtext-on')
        A.key_up('alt')
        gear.wait(0.8)
        check('Alt released: button gone', not probe.edit_button_shown())
        A.press('i')
        gear.wait(1.5)
        local lay = ui.layout()
        local second = lay['layout:sample'] ~= nil and lay['game:UI_WND_INVENTORY'] ~= nil
        results.run = second and 'second' or 'first'
        print('run: ' .. results.run .. ', layout: ' .. gear.json.encode(lay))
        if not second then
            local w, x, y = inventory()
            check('inventory open', w and w.drawn)
            -- The cursor on the inventory's first item: the game shows its tooltip, but not under the edit mode.
            local hx, hy = A.ui_to_pixels(x + 18, y + 24)
            A.move(hx, hy)
            gear.wait(1.2)
            A.screenshot('hover-normal')
            -- In through the "Edit layout" button, which shows while Alt is held.
            local s = ui.state()
            A.key_down('alt')
            for _ = 1, 20 do
                if probe.edit_button_shown() then break end
                gear.wait(0.1)
            end
            A.ui_click(s.screen_left + 44, s.screen_top + 14)
            A.key_up('alt')
            gear.wait(0.6)
            check('the Edit layout button turns the edit mode on', ui.edit_mode())
            A.move(hx + 1, hy)
            gear.wait(1.2)
            A.screenshot('editmode-hover')
            A.screenshot('editmode-on')
            for _, ww in ipairs(ui.windows()) do
                if ww.visible or ww.bounds then
                    local b = ww.bounds
                    print(('window %s slot %d visible %s drawn %s movable %s rect %d,%d %dx%d frame %d,%d bounds %s'):format(
                        ww.name, ww.slot, tostring(ww.visible), tostring(ww.drawn), tostring(ww.movable), ww.x, ww.y,
                        ww.width, ww.height, ww.frame_x, ww.frame_y,
                        b and ('%d,%d %dx%d'):format(b.x, b.y, b.w, b.h) or '-'))
                end
            end
            local inv
            for _, fr in ipairs(probe.collect()) do
                print(('frame %s %q at %d,%d %dx%d'):format(fr.key, fr.name, fr.x, fr.y, fr.w, fr.h))
                if fr.key == 'game:UI_WND_INVENTORY' then inv = fr end
            end
            check('inventory overlay covers its tabs', inv and inv.y < y - 8, inv and ('overlay y %d, window y %d'):format(inv.y, y))

            -- A click selects (and moves nothing).
            A.ui_click(x + w.width / 2, y + w.height / 2)
            gear.wait(0.5)
            local _, xs, ys = inventory()
            check('click selects the inventory', probe.selected() == 'game:UI_WND_INVENTORY', probe.selected())
            check('a click does not move it', xs and math.abs(xs - x) < 1 and math.abs(ys - y) < 1)
            A.screenshot('editmode-selected')

            -- A drag anywhere on the overlay moves it (snapping may pull it a few units).
            -- (Not over the sample panel: the selected frame lies on top of the others.)
            drag_ui(x + 300, y + 120, x + 300 + 250, y + 120 - 100)
            local _, x2, y2 = inventory()
            check('inventory dragged', x2 and math.abs(x2 - (x + 250)) <= probe.SNAP + 1 and math.abs(y2 - (y - 100)) <= probe.SNAP + 1,
                ('%s,%s -> %s,%s'):format(x, y, tostring(x2), tostring(y2)))
            A.screenshot('editmode-dragged')

            -- Arrow keys nudge by one virtual unit.
            local before = ui.layout()['game:UI_WND_INVENTORY']
            A.press('right'); gear.wait(0.2); A.press('down'); gear.wait(0.4)
            local after = ui.layout()['game:UI_WND_INVENTORY']
            check('arrows nudge by one unit', before and after and math.abs(after.x - before.x - 1) < 0.01
                and math.abs(after.y - before.y - 1) < 0.01,
                before and after and ('%.2f,%.2f -> %.2f,%.2f'):format(before.x, before.y, after.x, after.y))

            -- A mod panel: select it, resize it at its corner.
            local p = sample()
            check('sample panel listed', p ~= nil)
            if p then
                A.ui_click(p.x + p.w / 2, p.y + p.h / 2)
                gear.wait(0.5)
                check('click selects the panel', probe.selected() == 'layout:sample', probe.selected())
                drag_ui(p.x + p.w - 6, p.y + p.h - 6, p.x + p.w - 6 + 60, p.y + p.h - 6 + 30)
                gear.wait(0.3)
                local q = sample()
                check('panel resized at its corner', q and math.abs(q.w - (p.w + 60)) < 3 and math.abs(q.h - (p.h + 30)) < 3,
                    q and ('%dx%d -> %dx%d'):format(p.w, p.h, q.w, q.h))
                -- The popup's Width and Height sliders (a click at their middle) and its Reset button.
                gear.wait(0.3)
                local st = ui.state()
                local pr = probe.popup_rect()
                check('popup shown', pr ~= nil)
                if pr then
                    A.ui_click(pr.x + 58 + 60, pr.y + 66 + 8)
                    gear.wait(0.5)
                    q = sample()
                    local ew = p.min_width + 0.5 * (math.floor(st.screen_right - st.screen_left) - p.min_width)
                    check('width slider', q and math.abs(q.w - ew) <= 4, q and ('%d, expected %.0f'):format(q.w, ew))
                    pr = probe.popup_rect()
                    A.ui_click(pr.x + 58 + 60, pr.y + 88 + 8)
                    gear.wait(0.5)
                    q = sample()
                    local eh = p.min_height + 0.5 * (math.floor(st.screen_bottom - st.screen_top) - p.min_height)
                    check('height slider', q and math.abs(q.h - eh) <= 4, q and ('%d, expected %.0f'):format(q.h, eh))
                    A.screenshot('editmode-sliders')
                    pr = probe.popup_rect()
                    A.ui_click(pr.x + 8 + 60, pr.y + 112 + 11)
                    gear.wait(0.5)
                    q = sample()
                    check('reset button', q and math.abs(q.x - 60) < 1 and math.abs(q.y - 120) < 1 and math.abs(q.w - 200) < 1
                        and math.abs(q.h - 110) < 1,
                        q and ('%d,%d %dx%d'):format(q.x, q.y, q.w, q.h))
                    check('still selected after reset', probe.selected() == 'layout:sample', probe.selected())
                end
                p = sample()
                drag_ui(p.x + 40, p.y + 40, p.x + 40 + 200, p.y + 40 + 150)
                gear.wait(0.3)
                q = sample()
                check('panel dragged', q and math.abs(q.x - (p.x + 200)) <= probe.SNAP + 1 and math.abs(q.y - (p.y + 150)) <= probe.SNAP + 1,
                    q and ('%d,%d -> %d,%d'):format(p.x, p.y, q.x, q.y))
                A.screenshot('editmode-popup')
            end

            -- A click on empty space deselects.
            local ex, ey = empty_spot()
            check('found an empty spot', ex ~= nil)
            if ex then
                A.ui_click(ex, ey)
                gear.wait(0.5)
                check('click on empty space deselects', probe.selected() == nil, probe.selected())
            end
            A.screenshot('editmode-deselected')

            -- The toolbar keeps its own title bar drag.
            local t = probe.toolbar_rect()
            if t then
                drag_ui(t.x + 40, t.y + 10, t.x + 40 + 250, t.y + 10 + 120)
                local t2 = probe.toolbar_rect()
                check('toolbar dragged', t2 and math.abs(t2.x - (t.x + 250)) < 3, t2 and ('%d -> %d'):format(t.x, t2.x))
            end
            local d = probe.done_rect()
            if d then A.ui_click(d.x + d.w / 2, d.y + d.h / 2) end
            gear.wait(0.8)
            check('Done ends the edit mode', not ui.edit_mode())
            A.screenshot('editmode-done')
            local l2 = ui.layout()
            check('stored', l2['game:UI_WND_INVENTORY'] ~= nil and l2['layout:sample'] ~= nil and l2['layout:toolbar'] ~= nil,
                gear.json.encode(l2))
        else
            local w, x, y = inventory()
            local e = lay['game:UI_WND_INVENTORY']
            local ex, ey = ui.from_virtual(e.x, e.y)
            check('inventory where it was left', x and math.abs(x - ex) < 3 and math.abs(y - ey) < 3,
                ('%s,%s expected %.0f,%.0f'):format(tostring(x), tostring(y), ex, ey))
            local p, s = sample(), lay['layout:sample']
            local sx, sy = ui.from_virtual(s.x, s.y)
            check('panel where it was left', p and math.abs(p.x - sx) < 3 and math.abs(p.y - sy) < 3)
            A.screenshot('editmode-restored')
            ui.set_edit_mode(true)
            gear.wait(0.5)
            A.screenshot('editmode-restored-on')
            ui.reset_layout()
            ui.set_edit_mode(false)
            gear.wait(0.8)
            local _, x3, y3 = inventory()
            check('reset puts it back', x3 and (math.abs(x3 - x) > 3 or math.abs(y3 - y) > 3),
                ('%s,%s -> %s,%s'):format(tostring(x), tostring(y), tostring(x3), tostring(y3)))
            A.screenshot('editmode-reset')
        end
        A.press('i')
        gear.wait(0.5)
        print(('%d passed, %d failed'):format(results.passed, results.failed))
        A.quit(results.failed == 0 and 0 or 1)
    end)
end
