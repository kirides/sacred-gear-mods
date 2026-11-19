-- Custom classes: the class window (what main.lua shows). Drawing and clicks only: taking and leaving a class go back through the
-- functions main.lua passes in (env.take, env.leave).
--
-- Left: the classes as cards (the played hero's body first, the others under "Other bodies"). Right: the chosen class: description,
-- its skills (the game's names; hover for the description) and its arts as cards: the game's own icon, name, how the hero gets it
-- and the portability tier as a coloured chip. Buttons: "Take this class" / "Back to the game's class" below, "Reload files" in the
-- header. Everything is a normal window widget, so the controller's D-pad reaches it (the mod menu entry "Class window" opens it).
--
-- Layout rules: nothing is positioned by guessing text widths: texts are measured (gear.ui.text_size) and wrapped (text_wrap) or cut with
-- an ellipsis to the box they are in, both columns scroll when they are longer than the window, and everything stays inside the panel.

local profiles_lib = require('profiles')

local M = {}

function M.new(env)
    local ui = gear.ui
    local state, take, leave, assignment = env.state, env.take, env.leave, env.assignment
    local DIM, ACCENT, GOOD, BAD, WARN = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040, 0xFFE0A030
    local TIER_TEXT = {home = 'own', A = 'works as is', B = 'needs routing', C = 'tied to class', D = 'not portable'}
    local TIER_COLOR = {home = GOOD, A = GOOD, B = WARN, C = BAD, D = BAD}
    local TIER_HINT = {
        home = 'An art of the hero\'s own body.',
        A = 'A spell: every body can cast it.',
        B = 'An art of another class: it runs with that class\'s own code and the body plays a clip of its own.',
        C = 'Tied to the state of its class (forms, firearms): it stays with that class.',
        D = 'No hero class runs it.',
    }
    local sel = {id = nil}
    local W, H = 720, 560
    local LEFT_W = 200
    local CARD_BG, CARD_HOVER, CARD_SEL = 0xC0141008, 0xC02A2210, 0xC0382C12
    local SMALL, NORMAL = {size = 11}, {size = 12}

    local function hero()
        return gear.party.available() and gear.party.leader() or gear.world.hero()
    end

    local function ability_name(id)
        local a = gear.data.abilities[id]
        return (a and gear.text.get(a.name_text)) or ('#' .. id)
    end

    local function ability_description(id)
        local a = gear.data.abilities[id]
        return a and gear.text.get(a.description_text) or nil
    end

    -- The width of a text in the layout (a rough guess when the font cannot measure).
    local function width_of(text, opts)
        local w = ui.text_size(text, opts)
        return w or (#text * (opts and opts.size or 13) * 0.55)
    end

    -- The text cut with an ellipsis so that it fits `max` layout units.
    local cache = {}
    local function fit(text, max, opts)
        local key = text .. '|' .. math.floor(max) .. '|' .. tostring(opts and opts.size) .. tostring(opts and opts.bold)
        local hit = cache[key]
        if hit then return hit end
        local out = text
        if width_of(text, opts) > max then
            local n = #text
            while n > 1 and width_of(text:sub(1, n) .. '...', opts) > max do n = n - 1 end
            out = text:sub(1, n) .. '...'
        end
        cache[key] = out
        return out
    end

    local function sorted_profiles(body_id)
        local mine, other = {}, {}
        for _, p in pairs(state.profiles) do
            if body_id and (p.body_id == body_id or (body_id == 7 and p.body_id == 6)) then mine[#mine + 1] = p else other[#other + 1] = p end
        end
        local by_name = function(a, b) return profiles_lib.text(a.name, a.id):lower() < profiles_lib.text(b.name, b.id):lower() end
        table.sort(mine, by_name)
        table.sort(other, by_name)
        return mine, other
    end

    -- A coloured chip with a short text, right-aligned at `right`; returns its width.
    local function chip(text, right, y, color)
        local w = width_of(text, SMALL) + 10
        local x = right - w
        ui.rect(x, y, w, 16, 0xC0000000)
        ui.frame(x, y, w, 16, color, 1)
        ui.text(text, x + 5, y + 1, {color = color, size = 11})
        return w
    end

    -- A card: a box that reacts to the pointer; returns hover, clicked.
    local function card(id, x, y, w, h, tooltip, selected)
        local r = ui.region(id, x, y, w, h, {tooltip = tooltip})
        ui.rect(x, y, w, h, selected and CARD_SEL or (r.hover and CARD_HOVER or CARD_BG))
        ui.frame(x, y, w, h, selected and ACCENT or (r.hover and 0xFF8A7A4C or 0xFF4A3E24), 1)
        return r.hover, r.clicked
    end

    local function art_icon(id, x, y, size)
        local image, tint = gear.classes.art_icon(id)
        if image then
            ui.image(image, x, y, size, size, {color = tint})
        else
            ui.rect(x, y, size, size, 0xFF2A2418)
            ui.frame(x, y, size, size, 0xFF6A5A3C, 1)
        end
    end

    -- A skill: a round glyph with the first letter (the game has no skill icons) and the name; the description is the tooltip.
    local function skill_chip(id, x, y, w)
        local s = gear.classes.skill(id)
        local name = s and s.name or ('Skill ' .. id)
        ui.region('skill' .. id, x, y, w, 20, {tooltip = s and s.description and (name .. '\n' .. s.description) or name})
        ui.rect(x, y, 20, 20, 0xFF2A2418)
        ui.frame(x, y, 20, 20, ACCENT, 1)
        ui.text(name:sub(1, 1):upper(), x + 6, y + 2, {color = ACCENT, bold = true, size = 12})
        ui.text(fit(name, w - 26, NORMAL), x + 25, y + 3, {color = 0xFFFFFFFF, size = 12})
    end

    -- The left column: the class cards; returns the content height.
    local function draw_classes(area, mine, other, current, body)
        local x, w = area.content_x, area.w
        local y = area.content_y
        local top = y
        local function class_card(prof)
            local label = profiles_lib.text(prof.name, prof.id)
            local on = sel.id == prof.id
            local _, clicked = card('c_' .. prof.id, x, y, w, 44, profiles_lib.text(prof.description, ''), on)
            local arts = ('%d arts'):format(#prof.arts)
            ui.text(fit((current and current.id == prof.id and '* ' or '') .. label, w - 16, {size = 13, bold = true}), x + 8, y + 5,
                {color = on and ACCENT or 0xFFFFFFFF, bold = true})
            local aw = width_of(arts, SMALL)
            ui.text(fit(profiles_lib.BODY_LABEL[prof.body] or prof.body, w - aw - 24, SMALL), x + 8, y + 25, {color = DIM, size = 11})
            ui.text(arts, x + w - aw - 8, y + 25, {color = DIM, size = 11})
            if clicked then sel.id = prof.id end
            y = y + 50
        end
        for _, prof in ipairs(mine) do class_card(prof) end
        if #other > 0 then
            ui.text('Other bodies', x, y + 2, {color = DIM, size = 12})
            y = y + 22
            for _, prof in ipairs(other) do class_card(prof) end
        end
        return y - top
    end

    -- The right column: the chosen class; returns the content height.
    local function draw_details(area, prof)
        local x, w = area.content_x, area.w
        local y = area.content_y
        local top = y
        ui.text(fit(profiles_lib.text(prof.name, prof.id) .. ' - ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body), w, {size = 14, bold = true}),
            x, y, {color = ACCENT, bold = true, size = 14})
        y = y + 24
        local d = profiles_lib.text(prof.description, '')
        if d ~= '' then
            local lines, height = ui.text_wrap(d, w, NORMAL)
            for i, line in ipairs(lines) do ui.text(line, x, y + (i - 1) * (height / math.max(1, #lines)), {color = 0xFFFFFFFF, size = 12}) end
            y = y + height + 10
        end
        if prof.skills then
            ui.text('Skills', x, y, {color = ACCENT})
            y = y + 20
            local cols = 3
            local cw = math.floor((w - 4 * (cols - 1)) / cols)
            for i, id in ipairs(prof.skills.available) do
                skill_chip(id, x + ((i - 1) % cols) * (cw + 4), y + math.floor((i - 1) / cols) * 24, cw)
            end
            y = y + math.ceil(#prof.skills.available / cols) * 24 + 8
        end
        ui.text('Arts', x, y, {color = ACCENT})
        y = y + 20
        local cw = math.floor((w - 8) / 2)
        for i, a in ipairs(prof.arts) do
            local cx = x + ((i - 1) % 2) * (cw + 8)
            local cy = y + math.floor((i - 1) / 2) * 52
            local base = (gear.data.abilities[a.id] or {}).base or a.id
            local tier = gear.classes.tier(base, prof.body_id)
            local how = a.learn == 'start' and ('from the start' .. (a.level > 1 and (', level ' .. a.level) or ''))
                or a.learn == 'level' and ('at hero level ' .. a.level) or 'from its rune'
            local tip = ability_description(a.id)
            card('a_' .. prof.id .. '_' .. a.id, cx, cy, cw, 48, (tip and (ability_name(a.id) .. '\n' .. tip .. '\n\n') or '') .. (TIER_HINT[tier] or ''), false)
            art_icon(a.id, cx + 4, cy + 4, 40)
            -- name on the first line (it may use the whole card), the learn mode and the chip on the second
            ui.text(fit(ability_name(a.id), cw - 56, {size = 12, bold = true}), cx + 50, cy + 5, {color = 0xFFFFFFFF, bold = true, size = 12})
            local cwid = chip(TIER_TEXT[tier] or tier, cx + cw - 4, cy + 26, TIER_COLOR[tier] or DIM)
            ui.text(fit(how, cw - 56 - cwid - 6, SMALL), cx + 50, cy + 28, {color = DIM, size = 11})
        end
        y = y + math.ceil(#prof.arts / 2) * 52
        return y - top
    end

    local function draw()
        if not ui.panel_open('classes') then return end
        local p = ui.panel('classes', 'Custom classes', 100, 20, W, H, {resizable = true, min_width = 560, min_height = 360})
        if not p.open then return end
        local x, y, w, h = p.content_x or 0, p.content_y or 0, p.content_w or W - 20, p.content_h or H - 40
        local hr = hero()
        if not hr then
            ui.text('Start or load a game first.', x, y, {color = DIM})
            return
        end
        local name, body = hr:class()
        local current = assignment(hr)
        -- header: who, and the reload button inside the window
        local reload_w = 110
        ui.text(fit(('%s (%s): %s'):format(hr:name() or 'Hero', profiles_lib.BODY_LABEL[name or ''] or '?',
            current and profiles_lib.text(current.name, current.id) or 'the game\'s own class'), w - reload_w - 12, {size = 13, bold = true}),
            x, y + 3, {color = ACCENT, bold = true})
        if ui.button('reload', x + w - reload_w, y, reload_w, 22, 'Reload files', {tooltip = 'Reads the class and art files again'}) then
            env.reload()
        end
        local mine, other = sorted_profiles(body)
        local body_y = y + 30
        local footer_h = 34
        local body_h = h - 30 - footer_h
        if #mine == 0 and #other == 0 then
            ui.text('No class profiles found. Put them in mods\\custom-classes\\classes (see the mod\'s page).', x, body_y, {color = DIM})
        end
        -- columns
        local area = ui.scroll_begin('classes_list', x, body_y, LEFT_W, body_h, {})
        local ch = draw_classes(area, mine, other, current, body)
        ui.scroll_end(ch)
        local prof = sel.id and state.profiles[sel.id]
        local dx = x + LEFT_W + 14
        local dw = w - LEFT_W - 14
        if not prof then
            ui.text('Pick a class on the left.', dx, body_y, {color = DIM})
        else
            local darea = ui.scroll_begin('classes_details', dx, body_y, dw, body_h, {})
            local dh = draw_details(darea, prof)
            ui.scroll_end(dh)
        end
        -- footer: the actions
        local fy = y + h - footer_h + 6
        if current and ui.button('leave', x, fy, 200, 26, 'Back to the game\'s class',
            {tooltip = 'Keeps the arts the hero learned; the profile\'s skills, runes and routing stop'}) then
            leave(hr)
        end
        if prof then
            local usable = (prof.body_id == body) or (body == 7 and prof.body_id == 6)
            if ui.button('take', dx, fy, 200, 26, 'Take this class', {enabled = usable and not (current and current.id == prof.id),
                tooltip = usable and 'The hero gets the class\'s starting arts; its skills show in the skill window'
                    or ('This class is for the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body: play such a hero to take it')}) then
                take(hr, prof)
            end
            if not usable then
                ui.text(fit('For the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body only', dw - 210, NORMAL), dx + 210, fy + 5, {color = BAD, size = 12})
            end
        end
        if #state.problems > 0 then
            ui.text(fit(('%d file problem(s), see the log'):format(#state.problems), 180, NORMAL), x + w - 180, fy + 5, {color = BAD, size = 12})
        end
    end

    return {draw = draw, select = function(id) sel.id = id end}
end

return M
