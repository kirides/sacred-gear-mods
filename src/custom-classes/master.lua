-- Custom classes: the combo master's window (UI_WND_MASTER) with custom arts.
--
-- The game's window lists the hero's arts in a fixed layout per class and builds combos from them, and its rune exchange only knows the game's own
-- runes. With custom arts in the game (copies and chains of the art files) this mod shows its own window in its place, while the combo
-- master is open: the same two jobs, with every art the hero knows.
--   Combo:    up to four of the hero's combat arts become a combo in one of the four combo slots (`creature:set_combo`); the game works out
--             its regeneration (at least the sum of the arts') and the combo is used like an art (combo ids 0x200 + slot).
--   Exchange: two to four runes of the backpack become another rune, like the game's exchange: 2 runes: a random rune of any class;
--             3 runes: a random rune of the hero's class; 4 runes: a rune of the hero's class that you choose. Custom runes (art files with
--             `rune.combo_master`) are among the offered ones, and only runes the hero's class may read (the class profile) are offered to the
--             hero. The fee is the mod's own (settings), the game's price formula is not known.
-- Drawn with gear.ui.table where rows need columns; everything is a window widget, so the controller's D-pad reaches it.

local profiles_lib = require('profiles')
local arts = require('arts')

local M = {}

function M.new(env)
    local ui = gear.ui
    local setting, assignment = env.setting, env.assignment
    local DIM, ACCENT, GOOD, BAD = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040
    local NAME = 'UI_WND_MASTER'
    local W, H = 700, 520
    local st = {tab = 'combo', slot = 0, draft = {}, picks = {}, choice = 1, message = nil, message_time = 0}

    local function hero()
        return gear.party.available() and gear.party.leader() or gear.world.hero()
    end

    local function name_of(id)
        local a = gear.data.abilities[id]
        return (a and gear.text.get(a.name_text)) or ('#' .. id)
    end

    local function say(text, good)
        st.message, st.good, st.message_time = text, good, gear.time()
        print('[custom-classes] master: ' .. text)
    end

    -- Whether to take the game's window's place: only when custom arts exist (else the game's own works as always).
    function M.active()
        if not setting('replace_master', true) then return false end
        for _ in pairs(arts.ids()) do return true end
        return false
    end

    ---------------------------------------------------------------------------------------------------------------------
    -- Combo
    ---------------------------------------------------------------------------------------------------------------------
    -- The combat arts a combo can hold: known arts from 1000 on, not aimed at the hero or a corpse.
    local function combinable(h)
        local out = {}
        for _, a in ipairs(h:abilities() or {}) do
            local rec = a.id >= 1000 and gear.data.abilities[a.id]
            if rec and rec.target_mode ~= 2 and rec.target_mode ~= 4 then out[#out + 1] = a end
        end
        return out
    end

    local function load_draft(h)
        st.draft = {}
        for _, k in ipairs(h:combos() or {}) do
            if k.slot == st.slot then for _, id in ipairs(k.arts) do st.draft[#st.draft + 1] = id end end
        end
    end

    local function regen_sum(h)
        local sum = 0
        for _, id in ipairs(st.draft) do
            local a = h:ability(id)
            sum = sum + (a and a.regen_max or 0)
        end
        return sum
    end

    local function draw_combo(h, x, y, w, hh)
        local bottom = y + hh
        -- the four combo slots
        local slots = ui.table('master_slots', x, y, w, {columns = {'*', '*', '*', '*'}, row_height = 26, spacing = {6, 4}})
        slots:row()
        for s = 0, 3 do
            local k
            for _, c in ipairs(h:combos() or {}) do if c.slot == s then k = c end end
            local label = ('Combo %d%s'):format(s + 1, k and (' (%d arts)'):format(#k.arts) or ' (empty)')
            if slots:button(s + 1, (st.slot == s and '> ' or '') .. label, {tooltip = k and ('Regeneration %.0f s'):format(k.total) or 'An empty combo slot'}) then
                st.slot = s
                load_draft(h)
            end
        end
        y = y + slots:height() + 10
        local half = math.floor((w - 16) / 2)
        -- left: the arts to choose from; right: this combo
        ui.text('Combat arts of the hero (click to add)', x, y, {color = ACCENT})
        ui.text(('Combo %d: up to four arts, used one after the other'):format(st.slot + 1), x + half + 16, y, {color = ACCENT})
        y = y + 20
        local list = combinable(h)
        local area = ui.scroll_begin('master_arts', x, y, half, bottom - y - 4, {})
        local t = ui.table('master_arts_rows', area.content_x, area.content_y, area.w, {
            columns = {40, '*', {width = 'auto', align = 'right'}}, spacing = {6, 3}, row_height = 40, stripes = true})
        for _, a in ipairs(list) do
            t:row()
            local image, tint = gear.classes.art_icon(a.id)
            if image then t:image(1, image, {color = tint, width = 36, height = 36}) end
            local rec = gear.data.abilities[a.id]
            t:label(2, name_of(a.id) .. '\n' .. ('regen %.1f s'):format(a.regen_max or 0), {size = 12, bold = true,
                tooltip = gear.text.get((rec or {}).description_text or 0)})
            if t:button(3, 'Add', {enabled = #st.draft < 4}) then st.draft[#st.draft + 1] = a.id end
        end
        ui.scroll_end(t:height())
        -- the draft
        local dx = x + half + 16
        local d = ui.table('master_draft', dx, y, half, {columns = {40, '*', 26}, spacing = {6, 3}, row_height = 40, stripes = true})
        for i, id in ipairs(st.draft) do
            d:row()
            local image, tint = gear.classes.art_icon(id)
            if image then d:image(1, image, {color = tint, width = 36, height = 36}) end
            d:label(2, ('%d. %s'):format(i, name_of(id)), {size = 12, bold = true})
            if d:button(3, 'x', {tooltip = 'Remove from the combo'}) then table.remove(st.draft, i) break end
        end
        if #st.draft == 0 then ui.text('Add arts from the list.', dx, y + 2, {color = DIM, size = 12}) end
        local by = y + math.max(1, #st.draft) * 43 + 10
        ui.text(('Regeneration of the arts together: %.1f s (the combo takes at least that long)'):format(regen_sum(h)), dx, by, {color = DIM, size = 11})
        by = by + 22
        if ui.button('master_make', dx, by, half, 26, 'Create combo', {enabled = #st.draft >= 1,
            tooltip = 'Writes the arts into the combo slot; the game works out its regeneration'}) then
            local ok, why = h:set_combo(st.slot, st.draft)
            say(ok and ('Combo %d created'):format(st.slot + 1) or ('Not possible: ' .. tostring(why)), ok)
        end
        if ui.button('master_clear', dx, by + 30, half, 26, 'Empty this combo slot', {}) then
            local ok, why = h:set_combo(st.slot, {})
            st.draft = {}
            say(ok and ('Combo %d emptied'):format(st.slot + 1) or tostring(why), ok)
        end
    end

    ---------------------------------------------------------------------------------------------------------------------
    -- Rune exchange
    ---------------------------------------------------------------------------------------------------------------------
    local CLASS_BITS = {[1] = 0x1, [2] = 0x2, [3] = 0x4, [4] = 0x8, [5] = 0x10, [6] = 0x20, [7] = 0x20, [8] = 0x400000, [9] = 0x800000}

    local function may_learn(h, art)
        local rec = gear.data.abilities[art]
        if not rec then return false end
        local p = assignment(h)
        if p then
            for _, a in ipairs(p.arts) do if a.id == art then return true end end
            return false
        end
        local _, body = h:class()
        local mask = rec.class_mask or 0
        return mask ~= 0 and bit.band(mask, CLASS_BITS[body] or 0) ~= 0
    end

    -- The runes in the backpack: {item, art}.
    local function backpack_runes(h)
        local out = {}
        local c = gear.inv.container(h.id)
        for _, it in ipairs(c and c:items() or {}) do
            local art = gear.classes.rune_art_of_type(it.type)
            if art then out[#out + 1] = {item = it, art = art} end
        end
        return out
    end

    -- Rune types that can come out of an exchange: {art, type}; custom runes only when their art file allows it.
    local function pool(h, own)
        local out = {}
        local custom = {}
        for art, r in pairs(arts.runes) do custom[art] = r end
        for art, types in pairs(gear.classes.runes()) do
            local t = types[1]
            local c = custom[art]
            local offered = (not arts.ids()[art]) or (c and c.combo_master)
            if t and offered and gear.data.abilities[art] and (not own or may_learn(h, art)) and not (h:ability(art) and own) then
                out[#out + 1] = {art = art, type = t}
            end
        end
        table.sort(out, function(a, b) return a.art < b.art end)
        return out
    end

    -- The fee: the setting for the number of runes; a custom rune with a `price` in its art file costs that instead.
    local function fee_for(n, result)
        local custom = result and arts.runes[result.art]
        if custom and custom.price and custom.price > 0 then return custom.price end
        return setting('exchange_fee_' .. n, ({[2] = 500, [3] = 2000, [4] = 5000})[n])
    end

    local function give_rune(h, item_type)
        local x, y = h:position()
        local id, err = gear.world.spawn(item_type, x + 30, y, {})
        if not id then return nil, err end
        gear.wait(0.2)
        local found
        for _, it in ipairs(gear.world.items_near(x, y, 300, {})) do if it.type == item_type then found = it end end
        if not found then return nil, 'the rune did not appear' end
        local new = gear.inv.add(gear.inv.container(h.id), gear.inv.export(found.id))
        gear.inv.destroy(found.id)
        return new
    end

    local function do_exchange(h, picked, result)
        local c = gear.inv.container(h.id)
        local fee = fee_for(#picked, result)
        if (h:gold() or 0) < fee then say(('Not enough gold: %d needed'):format(fee), false) return end
        gear.task(function()
            local new, err = give_rune(h, result.type)
            if not new then say('The exchange failed: ' .. tostring(err), false) return end
            for _, p in ipairs(picked) do gear.inv.remove(c, p.item.id) end
            if fee > 0 then h:add_gold(-fee) end
            st.picks = {}
            st.last_new = new
            say(('You got the rune of %s'):format(name_of(result.art)), true)
        end)
    end

    local function draw_exchange(h, x, y, w, hh)
        local bottom = y + hh
        local lines, lh = ui.text_wrap('Put two to four runes in the exchange: 2 give a random rune of any class, 3 a random rune of your class, 4 a rune of your class you choose.', w,
            {size = 11})
        for i, line in ipairs(lines) do ui.text(line, x, y + (i - 1) * (lh / math.max(1, #lines)), {color = DIM, size = 11}) end
        y = y + lh + 6
        local runes = backpack_runes(h)
        local half = math.floor((w - 16) / 2)
        ui.text('Runes in the backpack', x, y, {color = ACCENT})
        ui.text('Result', x + half + 16, y, {color = ACCENT})
        y = y + 20
        local area = ui.scroll_begin('master_runes', x, y, half, bottom - y - 4, {})
        local t = ui.table('master_runes_rows', area.content_x, area.content_y, area.w, {
            columns = {40, '*', {width = 'auto', align = 'right'}}, spacing = {6, 3}, row_height = 40, stripes = true})
        local picked = {}
        for _, r in ipairs(runes) do
            t:row()
            local image, tint = gear.classes.art_icon(r.art)
            if image then t:image(1, image, {color = tint, width = 36, height = 36}) end
            t:label(2, name_of(r.art), {size = 12, bold = true})
            local on = st.picks[r.item.id] == true
            local _, now = t:checkbox(3, '', on)
            if now ~= on then
                local count = 0
                for _ in pairs(st.picks) do count = count + 1 end
                if now and count >= 4 then now = false end
                st.picks[r.item.id] = now or nil
            end
            if st.picks[r.item.id] then picked[#picked + 1] = r end
        end
        ui.scroll_end(t:height())
        if #runes == 0 then ui.text('No runes in the backpack.', x, y + 4, {color = DIM, size = 12}) end
        -- the result
        local dx = x + half + 16
        local n = #picked
        local options = n >= 4 and pool(h, true) or {}
        local result
        if n >= 2 then
            if n == 4 then
                result = options[math.min(st.choice, #options)]
            else
                -- a random one, chosen when the picks change
                local key = n .. ':' .. table.concat((function() local ids = {} for _, r in ipairs(picked) do ids[#ids + 1] = r.item.id end table.sort(ids) return ids end)(), ',')
                if st.roll_key ~= key then
                    st.roll_key = key
                    local candidates = pool(h, n == 3)
                    st.roll = candidates[math.random(#candidates)]
                end
                result = st.roll
            end
        else
            st.roll_key = nil
        end
        if n < 2 then
            ui.text('Choose at least two runes.', dx, y, {color = DIM, size = 12})
        elseif not result then
            ui.text('No rune to get.', dx, y, {color = BAD, size = 12})
        else
            local image, tint = gear.classes.art_icon(result.art)
            if image then ui.image(image, dx, y, 48, 48, {color = tint}) end
            if n == 4 then
                ui.text('Choose the rune:', dx + 56, y, {color = ACCENT, size = 12})
                local labels = {}
                for i, o in ipairs(options) do labels[i] = name_of(o.art) end
                local changed, idx = ui.dropdown('master_choice', dx + 56, y + 20, half - 56, labels, math.min(st.choice, #labels))
                if changed then st.choice = idx end
            else
                ui.text(n == 2 and 'A random rune of any class' or 'A random rune of your class', dx + 56, y, {color = DIM, size = 12})
                ui.text(name_of(result.art), dx + 56, y + 20, {color = 0xFFFFFFFF, bold = true})
                if ui.button('master_reroll', dx + 56, y + 46, 110, 22, 'Another one', {}) then st.roll_key = nil end
            end
            local fee = fee_for(n, result)
            local py = y + 80
            ui.text(('Price: %d gold (you have %d)'):format(fee, h:gold() or 0), dx, py, {color = (h:gold() or 0) >= fee and GOOD or BAD, size = 12})
            if ui.button('master_exchange', dx, py + 24, half, 28, 'Exchange runes', {enabled = (h:gold() or 0) >= fee}) then
                do_exchange(h, picked, result)
            end
        end
        if st.last_new then
            if ui.button('master_read', dx, y + 190, half, 26, 'Read the new rune now', {tooltip = 'The hero learns the art at once if the class may'}) then
                local ok, why = h:use_item(st.last_new)
                say(ok and 'The art is learned' or ('Not possible: ' .. tostring(why)), ok)
                if ok then st.last_new = nil end
            end
        end
    end

    ---------------------------------------------------------------------------------------------------------------------
    local function draw()
        if not M.active() then return end
        if not st.registered then
            st.registered = true
            ui.replace_window(NAME, true)
        end
        if not ui.replaced(NAME) then return end
        local p = ui.panel('master', 'Combo master', 40, 20, W, H, {resizable = true, min_width = 560, min_height = 380, back = true})
        if not p.open then
            ui.close_window(NAME)
            return
        end
        local x, y, w, h = p.content_x or 0, p.content_y or 0, p.content_w or W - 20, p.content_h or H - 40
        local hr = hero()
        if not hr then ui.text('No hero.', x, y, {color = DIM}) return end
        local head = ui.table('master_tabs', x, y, w, {columns = {120, 120, '*'}, row_height = 24, spacing = {6, 4}})
        head:row()
        if head:button(1, (st.tab == 'combo' and '> ' or '') .. 'Combo') then st.tab = 'combo' load_draft(hr) end
        if head:button(2, (st.tab == 'exchange' and '> ' or '') .. 'Exchange') then st.tab = 'exchange' end
        head:label(3, hr:name() or 'Hero', {align = 'right', color = ACCENT, bold = true})
        if st.loaded_for ~= hr.id then st.loaded_for = hr.id; load_draft(hr); st.picks = {}; st.last_new = nil end
        local by = y + 32
        if st.tab == 'combo' then draw_combo(hr, x, by, w, h - 32 - 24) else draw_exchange(hr, x, by, w, h - 32 - 24) end
        if st.message and gear.time() - st.message_time < 6 then
            ui.text(st.message, x, y + h - 18, {color = st.good and GOOD or BAD, size = 12})
        end
    end

    -- For tests and other mods: the window's actions without a mouse.
    --   command('tab', 'combo'|'exchange'), ('slot', 0..3), ('add', art id), ('make'), ('pick', {item ids}), ('choose', index), ('exchange')
    local function command(cmd, a)
        local h = hero()
        if not h then return end
        if cmd == 'tab' then st.tab = a if a == 'combo' then load_draft(h) end
        elseif cmd == 'slot' then st.slot = a load_draft(h)
        elseif cmd == 'add' then if #st.draft < 4 then st.draft[#st.draft + 1] = a end
        elseif cmd == 'make' then local ok, why = h:set_combo(st.slot, st.draft) say(ok and 'created' or tostring(why), ok)
        elseif cmd == 'pick' then st.picks = {} for _, id in ipairs(a) do st.picks[id] = true end
        elseif cmd == 'choose' then st.choice = a
        elseif cmd == 'exchange' then
            local picked = {}
            for _, r in ipairs(backpack_runes(h)) do if st.picks[r.item.id] then picked[#picked + 1] = r end end
            local n = #picked
            local result
            if n == 4 then result = pool(h, true)[math.min(st.choice, #pool(h, true))]
            elseif n >= 2 then local c = pool(h, n == 3) result = c[math.random(#c)] end
            if result then do_exchange(h, picked, result) else say('nothing to exchange', false) end
        end
    end

    return {draw = draw, active = M.active, state = st, command = command}
end

return M
