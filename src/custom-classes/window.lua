-- Custom classes: the class window (what main.lua shows). Drawing and clicks only: taking and leaving a class go back through the
-- functions main.lua passes in (env.take, env.leave).
--
-- Left: the classes of the played hero's body (and, under "Other bodies", the rest). Right: the chosen class: description, skills,
-- arts with their learn mode and portability tier. Buttons: "Take this class" / "Back to the game's class". Everything is a
-- normal window widget, so the controller's D-pad reaches it (the mod menu entry "Class window" opens it).

local profiles_lib = require('profiles')

local M = {}

function M.new(env)
    local ui = gear.ui
    local state, take, leave, assignment = env.state, env.take, env.leave, env.assignment
    local DIM, ACCENT, GOOD, BAD = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040
    local TIER_TEXT = {home = 'own', A = 'works as is', B = 'needs routing', C = 'tied to its class', D = 'not portable'}
    local TIER_COLOR = {home = GOOD, A = GOOD, B = ACCENT, C = BAD, D = BAD}
    local sel = {id = nil}
    local W, H = 640, 470

    local function hero()
        return gear.party.available() and gear.party.leader() or gear.world.hero()
    end

    local function ability_name(id)
        local a = gear.data.abilities[id]
        return (a and gear.text.get(a.name_text)) or ('#' .. id)
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

    local function draw()
        if not ui.panel_open('classes') then return end
        local p = ui.panel('classes', 'Custom classes', 150, 70, W, H, {})
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
        -- list
        local lx, ly, lw = x, y + 28, 200
        local yy = ly
        local function row(prof, dim)
            local label = profiles_lib.text(prof.name, prof.id)
            local on = sel.id == prof.id
            if ui.button('c_' .. prof.id, lx, yy, lw, 24, (current and current.id == prof.id and '* ' or '') .. label,
                {tooltip = profiles_lib.text(prof.description, ''), enabled = true, active = on}) then
                sel.id = prof.id
            end
            yy = yy + 28
        end
        for _, prof in ipairs(mine) do row(prof) end
        if #other > 0 then
            ui.text('Other bodies', lx, yy + 2, {color = DIM, size = 12})
            yy = yy + 20
            for _, prof in ipairs(other) do row(prof, true) end
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
            local ay = ly + 64
            if prof.skills then
                ui.text('Skills: ' .. table.concat(prof.skills.available, ', '), dx, ay, {color = DIM, size = 12, wrap = dw})
                ay = ay + 34
            end
            ui.text('Arts', dx, ay, {color = ACCENT})
            ay = ay + 20
            for _, a in ipairs(prof.arts) do
                local base = (gear.data.abilities[a.id] or {}).base or a.id
                local tier = gear.classes.tier(base, prof.body_id)
                local how = a.learn == 'start' and ('from the start' .. (a.level > 1 and (', level ' .. a.level) or ''))
                    or a.learn == 'level' and ('at hero level ' .. a.level) or 'from its rune'
                ui.text(('%s (%s)'):format(ability_name(a.id), how), dx, ay, {color = 0xFFFFFFFF, size = 12})
                ui.text(TIER_TEXT[tier] or tier, dx + dw - 120, ay, {color = TIER_COLOR[tier] or DIM, size = 12})
                ay = ay + 16
                if ay > y + H - 100 then break end
            end
            local by = y + H - 80
            if not usable then
                ui.text('This class is for the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body; play such a hero to take it.', dx, by - 22, {color = BAD, size = 12})
            end
            if ui.button('take', dx, by, 200, 26, 'Take this class', {enabled = usable and not (current and current.id == prof.id),
                tooltip = 'The hero gets the class\'s starting arts; its skills show in the skill window'}) then
                take(h, prof)
            end
        end
        if current and ui.button('leave', x, y + H - 80, 200, 26, 'Back to the game\'s class',
            {tooltip = 'Keeps the arts the hero learned; the profile\'s skills, runes and routing stop'}) then
            leave(h)
        end
        if ui.button('reload', x + w - 100, y + H - 52, 100, 22, 'Reload files', {tooltip = 'Reads the class and art files again'}) then
            env.reload()
        end
        if #state.problems > 0 then
            ui.text(('%d file problem(s), see the log'):format(#state.problems), x, y + H - 50, {color = BAD, size = 12})
        end
    end

    return {draw = draw}
end

return M
