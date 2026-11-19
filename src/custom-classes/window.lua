-- Custom classes: the class window (what main.lua shows). Drawing and clicks only: taking and leaving a class go back through the
-- functions main.lua passes in (env.take, env.leave).
--
-- Laid out with gear.ui.table where rows and columns need alignment: the class list, the skills and the arts. Single texts and the buttons stay plain
-- ui.text (cut with an ellipsis) and ui.button. The table cells cut long texts with an ellipsis (the whole text is the tooltip) and nothing leaves its cell.
-- Left: the classes (the played hero's body first, the others under "Other bodies"). Right: the chosen class: description, skills (the
-- game's names, the description as tooltip) and arts (the game's own icon, name, how the hero gets it, the portability tier). Everything
-- is a normal window widget: the controller's D-pad reaches it (the mod menu entry "Class window" opens it).

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
    local NORMAL = {size = 12}

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

    -- Single texts stay plain ui.text, cut with an ellipsis to the room they have.
    local function width_of(text, opts)
        local w = ui.text_size(text, opts)
        return w or (#text * (opts and opts.size or 13) * 0.55)
    end
    local fit_cache = {}
    local function fit(text, max, opts)
        local key = text .. '|' .. math.floor(max) .. '|' .. tostring(opts and opts.size) .. tostring(opts and opts.bold)
        local hit = fit_cache[key]
        if hit then return hit end
        local out = text
        if width_of(text, opts) > max then
            local n = #text
            while n > 1 and width_of(text:sub(1, n) .. '...', opts) > max do n = n - 1 end
            out = text:sub(1, n) .. '...'
        end
        fit_cache[key] = out
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

    -- The left column: a table of the classes; returns the content height.
    local function draw_classes(area, mine, other, current)
        local t = ui.table('classes_list', area.content_x, area.content_y, area.w, {
            columns = {'*', {width = 'auto', align = 'right'}},
            spacing = {6, 4},
            row_height = 40,
        })
        local function class_row(prof)
            t:row()
            local label = profiles_lib.text(prof.name, prof.id)
            local mark = (current and current.id == prof.id) and '* ' or (sel.id == prof.id and '> ' or '')
            if t:button(1, mark .. label .. '\n' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body), {tooltip = profiles_lib.text(prof.description, '')}) then
                sel.id = prof.id
            end
            t:label(2, ('%d arts'):format(#prof.arts), {color = DIM, size = 11})
        end
        for _, prof in ipairs(mine) do class_row(prof) end
        if #other > 0 then
            t:row(24)
            t:label(1, 'Other bodies', {span = 2, color = DIM, size = 12})
            for _, prof in ipairs(other) do class_row(prof) end
        end
        return t:height()
    end

    -- The right column: the chosen class; returns the content height.
    local function draw_details(area, prof)
        local x, w = area.content_x, area.w
        local y = area.content_y
        ui.text(profiles_lib.text(prof.name, prof.id) .. ' - ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body), x, y,
            {color = ACCENT, bold = true, size = 14})
        y = y + 24
        local d = profiles_lib.text(prof.description, '')
        if d ~= '' then
            local lines, height = ui.text_wrap(d, w, NORMAL)
            local line_h = height / math.max(1, #lines)
            for i, line in ipairs(lines) do ui.text(line, x, y + (i - 1) * line_h, {color = 0xFFFFFFFF, size = 12}) end
            y = y + height + 10
        end
        if prof.skills then
            ui.text('Skills', x, y, {color = ACCENT})
            y = y + 20
            local st = ui.table('skills', x, y, w, {columns = {'*', '*', '*'}, spacing = {6, 2}, row_height = 20})
            for i, id in ipairs(prof.skills.available) do
                if (i - 1) % 3 == 0 then st:row() end
                local s = gear.classes.skill(id)
                local name = s and s.name or ('Skill ' .. id)
                st:label((i - 1) % 3 + 1, name, {tooltip = s and s.description and (name .. '\n' .. s.description) or name, size = 12})
            end
            y = y + st:height() + 8
        end
        ui.text('Arts', x, y, {color = ACCENT})
        y = y + 20
        local at = ui.table('arts', x, y, w, {
            columns = {44, '*', {width = 'auto', align = 'right', max = 150}},
            spacing = {8, 4},
            row_height = 44,
            stripes = true,
        })
        for _, a in ipairs(prof.arts) do
            at:row()
            local base = (gear.data.abilities[a.id] or {}).base or a.id
            local tier = gear.classes.tier(base, prof.body_id)
            local how = a.learn == 'start' and ('from the start' .. (a.level > 1 and (', level ' .. a.level) or ''))
                or a.learn == 'level' and ('at hero level ' .. a.level) or 'from its rune'
            local image, tint = gear.classes.art_icon(a.id)
            if image then at:image(1, image, {color = tint, width = 40, height = 40}) end
            local tip = ability_description(a.id)
            at:label(2, ability_name(a.id) .. '\n' .. how, {bold = true, size = 12,
                tooltip = (tip and (ability_name(a.id) .. '\n' .. tip .. '\n\n') or '') .. (TIER_HINT[tier] or '')})
            at:label(3, TIER_TEXT[tier] or tier, {color = TIER_COLOR[tier] or DIM, size = 11, tooltip = TIER_HINT[tier]})
        end
        y = y + at:height()
        return y - area.content_y
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
        -- header: the hero and class (plain text) and the reload button
        local reload_w = 110
        ui.text(fit(('%s (%s): %s'):format(hr:name() or 'Hero', profiles_lib.BODY_LABEL[name or ''] or '?',
            current and profiles_lib.text(current.name, current.id) or "the game's own class"), w - reload_w - 12, {size = 13, bold = true}),
            x, y + 3, {color = ACCENT, bold = true})
        if ui.button('reload', x + w - reload_w, y, reload_w, 22, 'Reload files', {tooltip = 'Reads the class and art files again'}) then env.reload() end
        local mine, other = sorted_profiles(body)
        local body_y = y + 30
        local footer_h = 34
        local body_h = h - 30 - footer_h
        if #mine == 0 and #other == 0 then
            ui.text('No class profiles found. Put them in mods\\custom-classes\\classes (see the mod\'s page).', x, body_y, {color = DIM})
        end
        local area = ui.scroll_begin('classes_scroll', x, body_y, LEFT_W, body_h, {})
        ui.scroll_end(draw_classes(area, mine, other, current))
        local prof = sel.id and state.profiles[sel.id]
        local dx = x + LEFT_W + 14
        local dw = w - LEFT_W - 14
        if not prof then
            ui.text('Pick a class on the left.', dx, body_y, {color = DIM})
        else
            local darea = ui.scroll_begin('classes_details', dx, body_y, dw, body_h, {})
            ui.scroll_end(draw_details(darea, prof))
        end
        -- footer
        local usable = prof and ((prof.body_id == body) or (body == 7 and prof.body_id == 6))
        local fy = y + h - footer_h + 6
        if current and ui.button('leave', x, fy, LEFT_W, 26, "Back to the game's class",
            {tooltip = "Keeps the arts the hero learned; the profile's skills, runes and routing stop"}) then
            leave(hr)
        end
        if prof then
            if ui.button('take', dx, fy, 200, 26, 'Take this class', {enabled = usable and not (current and current.id == prof.id),
                tooltip = usable and "The hero gets the class's starting arts; its skills show in the skill window"
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
