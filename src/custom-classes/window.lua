-- Custom classes: the class window (what main.lua shows). Drawing and clicks only: taking and leaving a class go back through the
-- functions main.lua passes in (env.take, env.leave).
--
-- Left: the classes as cards (the played hero's body first, the others under "Other bodies"). Right: the chosen class: description,
-- its skills (the game's names; hover for the description) and its arts as cards: the game's own icon, name, how the hero gets it
-- and the portability tier as a coloured chip. Buttons: "Take this class" / "Back to the game's class". Everything is a normal window
-- widget, so the controller's D-pad reaches it (the mod menu entry "Class window" opens it).

local profiles_lib = require('profiles')

local M = {}

function M.new(env)
    local ui = gear.ui
    local state, take, leave, assignment = env.state, env.take, env.leave, env.assignment
    local DIM, ACCENT, GOOD, BAD, WARN = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040, 0xFFE0A030
    local TIER_TEXT = {home = 'own', A = 'works as is', B = 'needs routing', C = 'tied to its class', D = 'not portable'}
    local TIER_COLOR = {home = GOOD, A = GOOD, B = WARN, C = BAD, D = BAD}
    local TIER_HINT = {
        home = 'An art of the hero\'s own body.',
        A = 'A spell: every body can cast it.',
        B = 'An art of another class: it runs with that class\'s own code and the body plays a clip of its own.',
        C = 'Tied to the state of its class (forms, firearms): it stays with that class.',
        D = 'No hero class runs it.',
    }
    local sel = {id = nil}
    local W, H = 700, 540
    local CARD_BG, CARD_HOVER, CARD_SEL = 0xC0141008, 0xC02A2210, 0xC0382C12

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

    -- A coloured chip with a short text.
    local function chip(text, x, y, color)
        local w = 8 + #text * 6
        ui.rect(x, y, w, 15, 0xC0000000)
        ui.frame(x, y, w, 15, color, 1)
        ui.text(text, x + 4, y + 1, {color = color, size = 11})
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

    -- A skill chip: a round glyph with the first letter (the game has no skill icons) and the name; the description is the tooltip.
    local function skill_chip(id, x, y, w)
        local s = gear.classes.skill(id)
        local name = s and s.name or ('Skill ' .. id)
        ui.region('skill' .. id, x, y, w, 20, {tooltip = s and s.description and (name .. '\n' .. s.description) or name})
        ui.rect(x, y, 20, 20, 0xFF2A2418)
        ui.frame(x, y, 20, 20, ACCENT, 1)
        ui.text(name:sub(1, 1):upper(), x + 6, y + 2, {color = ACCENT, bold = true, size = 12})
        ui.text(name, x + 25, y + 3, {color = 0xFFFFFFFF, size = 12})
    end

    local function draw()
        if not ui.panel_open('classes') then return end
        local p = ui.panel('classes', 'Custom classes', 120, 60, W, H, {})
        if not p.open then return end
        local x, y, w = p.content_x or 0, p.content_y or 0, p.content_w or W - 20
        local h = hero()
        if not h then
            ui.text('Start or load a game first.', x, y, {color = DIM})
            return
        end
        local name, body = h:class()
        local current = assignment(h)
        ui.text(('%s (%s): %s'):format(h:name() or 'Hero', profiles_lib.BODY_LABEL[name or ''] or '?',
            current and profiles_lib.text(current.name, current.id) or 'the game\'s own class'), x, y, {color = ACCENT, bold = true})
        local mine, other = sorted_profiles(body)
        if #mine == 0 and #other == 0 then
            ui.text('No class profiles found. Put them in mods\\custom-classes\\classes (see the mod\'s page).', x, y + 28, {color = DIM})
        end
        -- the class cards
        local lx, ly, lw = x, y + 28, 210
        local yy = ly
        local function class_card(prof)
            local label = profiles_lib.text(prof.name, prof.id)
            local on = sel.id == prof.id
            local _, clicked = card('c_' .. prof.id, lx, yy, lw, 44, profiles_lib.text(prof.description, ''), on)
            ui.text((current and current.id == prof.id and '* ' or '') .. label, lx + 8, yy + 6, {color = on and ACCENT or 0xFFFFFFFF, bold = true})
            ui.text(profiles_lib.BODY_LABEL[prof.body] or prof.body, lx + 8, yy + 24, {color = DIM, size = 11})
            ui.text(('%d arts'):format(#prof.arts), lx + lw - 56, yy + 24, {color = DIM, size = 11})
            if clicked then sel.id = prof.id end
            yy = yy + 50
        end
        for _, prof in ipairs(mine) do class_card(prof) end
        if #other > 0 then
            ui.text('Other bodies', lx, yy + 2, {color = DIM, size = 12})
            yy = yy + 20
            for _, prof in ipairs(other) do class_card(prof) end
        end
        -- details
        local dx = x + lw + 16
        local dw = w - lw - 16
        local prof = sel.id and state.profiles[sel.id]
        if not prof then
            ui.text('Pick a class on the left.', dx, ly, {color = DIM})
        else
            local usable = (prof.body_id == body) or (body == 7 and prof.body_id == 6)
            ui.text(profiles_lib.text(prof.name, prof.id) .. ' - ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body), dx, ly, {color = ACCENT, bold = true})
            local d = profiles_lib.text(prof.description, '')
            if d ~= '' then ui.text(d, dx, ly + 20, {color = 0xFFFFFFFF, size = 12, wrap = dw}) end
            local ay = ly + 58
            if prof.skills then
                ui.text('Skills', dx, ay, {color = ACCENT})
                ay = ay + 20
                local col = 0
                for _, id in ipairs(prof.skills.available) do
                    skill_chip(id, dx + (col % 2) * (dw / 2), ay + math.floor(col / 2) * 24, dw / 2 - 6)
                    col = col + 1
                end
                ay = ay + math.ceil(col / 2) * 24 + 6
            end
            ui.text('Arts', dx, ay, {color = ACCENT})
            ay = ay + 20
            local shown = 0
            local cw = dw / 2 - 4
            for i, a in ipairs(prof.arts) do
                local cy = ay + math.floor((i - 1) / 2) * 50
                if cy + 46 > y + H - 70 then break end
                local cx = dx + ((i - 1) % 2) * (cw + 8)
                local base = (gear.data.abilities[a.id] or {}).base or a.id
                local tier = gear.classes.tier(base, prof.body_id)
                local how = a.learn == 'start' and ('from the start' .. (a.level > 1 and (', level ' .. a.level) or ''))
                    or a.learn == 'level' and ('at hero level ' .. a.level) or 'from its rune'
                local tip = ability_description(a.id)
                card('a_' .. prof.id .. '_' .. a.id, cx, cy, cw, 46, (tip and (ability_name(a.id) .. '\n' .. tip .. '\n\n') or '') .. (TIER_HINT[tier] or ''), false)
                art_icon(a.id, cx + 4, cy + 3, 40)
                ui.text(ability_name(a.id), cx + 50, cy + 5, {color = 0xFFFFFFFF, bold = true, size = 12})
                ui.text(how, cx + 50, cy + 24, {color = DIM, size = 11})
                chip(TIER_TEXT[tier] or tier, cx + cw - (8 + #(TIER_TEXT[tier] or tier) * 6) - 4, cy + 4, TIER_COLOR[tier] or DIM)
                shown = shown + 1
            end
            if shown < #prof.arts then
                ui.text(('+ %d more'):format(#prof.arts - shown), dx, y + H - 90, {color = DIM, size = 12})
            end
            local by = y + H - 62
            if not usable then
                ui.text('This class is for the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body; play such a hero to take it.', dx, by - 20, {color = BAD, size = 12})
            end
            if ui.button('take', dx, by, 200, 26, 'Take this class', {enabled = usable and not (current and current.id == prof.id),
                tooltip = 'The hero gets the class\'s starting arts; its skills show in the skill window'}) then
                take(h, prof)
            end
        end
        if current and ui.button('leave', x, y + H - 62, 200, 26, 'Back to the game\'s class',
            {tooltip = 'Keeps the arts the hero learned; the profile\'s skills, runes and routing stop'}) then
            leave(h)
        end
        if ui.button('reload', x + w - 100, y + H - 32, 100, 22, 'Reload files', {tooltip = 'Reads the class and art files again'}) then
            env.reload()
        end
        if #state.problems > 0 then
            ui.text(('%d file problem(s), see the log'):format(#state.problems), x, y + H - 30, {color = BAD, size = 12})
        end
    end

    return {draw = draw, select = function(id) sel.id = id end}
end

return M
