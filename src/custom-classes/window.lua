-- Custom classes: the class window (what main.lua shows). Drawing and clicks only: taking and leaving a class go back through the
-- functions main.lua passes in (env.take, env.leave).
--
-- The window is ui/classes.rml (the game theme): a model of ready-made strings (rebuilt every frame, only what changed is written) and
-- delegated click listeners. Left: the classes (the played hero's body first, the others under "Other bodies"). Right: the chosen class:
-- description, skills (the game's names, the description as tooltip) and arts (the game's own icon, name, how the hero gets it, the
-- portability tier). Everything is a button or link the controller's D-pad reaches (the mod menu entry "Class window" opens it).

local profiles_lib = require('profiles')

local M = {}

function M.new(env)
    local ui = gear.ui
    local state, take, leave, assignment = env.state, env.take, env.leave, env.assignment
    local TIER_TEXT = {home = 'own', A = 'works as is', B = 'needs routing', C = 'tied to class', D = 'not portable'}
    local TIER_GOOD = {home = true, A = true}
    local TIER_WARN = {B = true}
    local TIER_HINT = {
        home = 'An art of the hero\'s own body.',
        A = 'A spell: every body can cast it.',
        B = 'An art of another class: it runs with that class\'s own code and the body plays a clip of its own.',
        C = 'Tied to the state of its class (forms, firearms): it stays with that class.',
        D = 'No hero class runs it.',
    }
    local sel = {id = nil}
    local shown = false
    local doc
    local last = {}
    local rows = {}          -- row id ('c1' ...) -> profile id

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

    local function css_color(argb)
        argb = argb or 0xFFFFFFFF
        return ('#%02x%02x%02x%02x'):format(math.floor(argb / 65536) % 256, math.floor(argb / 256) % 256, argb % 256, math.floor(argb / 16777216) % 256)
    end

    local function details(prof)
        local d = {title = profiles_lib.text(prof.name, prof.id) .. ' - ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body),
            desc = profiles_lib.text(prof.description, ''), has_skills = false, skills = {}, arts = {}}
        if prof.skills then
            d.has_skills = true
            for _, id in ipairs(prof.skills.available) do
                local s = gear.classes.skill(id)
                local name = s and s.name or ('Skill ' .. id)
                d.skills[#d.skills + 1] = {name = name, tip = s and s.description and (name .. '\n' .. s.description) or name}
            end
        end
        for _, a in ipairs(prof.arts) do
            local base = (gear.data.abilities[a.id] or {}).base or a.id
            local tier = gear.classes.tier(base, prof.body_id)
            local how = a.learn == 'start' and ('from the start' .. (a.level > 1 and (', level ' .. a.level) or ''))
                or a.learn == 'level' and ('at hero level ' .. a.level) or 'from its rune'
            local image, tint = gear.classes.art_icon(a.id)
            local tip = ability_description(a.id)
            d.arts[#d.arts + 1] = {
                icon = image and ('gear:image/' .. image) or '', tint = css_color(tint), name = ability_name(a.id), how = how,
                tier_text = TIER_TEXT[tier] or tostring(tier), good = TIER_GOOD[tier] or false, warn = TIER_WARN[tier] or false,
                bad = not (TIER_GOOD[tier] or TIER_WARN[tier]), tier_tip = TIER_HINT[tier] or '',
                tip = (tip and (ability_name(a.id) .. '\n' .. tip .. '\n\n') or '') .. (TIER_HINT[tier] or ''),
            }
        end
        return d
    end

    local function snapshot()
        local m = {open = shown, nohero = false, head = '', no_profiles = false, mine = {}, other = {}, has_other = false, sel = false,
            d = {title = '', desc = '', has_skills = false, skills = {}, arts = {}}, can_leave = false, usable = true,
            not_usable = '', take_tip = '', problems = ''}
        local hr = hero()
        if not hr then m.nohero = true return m end
        local name, body = hr:class()
        local current = assignment(hr)
        m.head = ('%s (%s): %s'):format(hr:name() or 'Hero', profiles_lib.BODY_LABEL[name or ''] or '?',
            current and profiles_lib.text(current.name, current.id) or "the game's own class")
        local mine, other = sorted_profiles(body)
        m.no_profiles = #mine == 0 and #other == 0
        m.has_other = #other > 0
        rows = {}
        local n = 0
        local function class_row(prof)
            n = n + 1
            local id = 'c' .. n
            rows[id] = prof.id
            return {id = id, on = sel.id == prof.id, mark = (current and current.id == prof.id) and '* ' or '',
                name = profiles_lib.text(prof.name, prof.id), body = profiles_lib.BODY_LABEL[prof.body] or tostring(prof.body),
                count = ('%d arts'):format(#prof.arts), tip = profiles_lib.text(prof.description, '')}
        end
        for _, p in ipairs(mine) do m.mine[#m.mine + 1] = class_row(p) end
        for _, p in ipairs(other) do m.other[#m.other + 1] = class_row(p) end
        local prof = sel.id and state.profiles[sel.id]
        if prof then
            m.sel = true
            m.d = details(prof)
            m.usable = (prof.body_id == body) or (body == 7 and prof.body_id == 6)
            m.take_tip = m.usable and "The hero gets the class's starting arts; its skills show in the skill window"
                or ('This class is for the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body: play such a hero to take it')
            m.not_usable = 'For the ' .. (profiles_lib.BODY_LABEL[prof.body] or prof.body) .. ' body only'
        end
        m.can_leave = current ~= nil
        if #state.problems > 0 then m.problems = ('%d file problem(s), see the log'):format(#state.problems) end
        return m
    end

    local function same(a, b)
        if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
        if #a ~= #b then return false end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        return true
    end

    local function load_doc()
        local m = snapshot()
        last = m
        local err
        doc, err = ui.rml.load('ui/classes.rml', {model = m})
        if not doc then gear.log('custom classes: ui/classes.rml failed: ' .. tostring(err)) return end
        local function on(sel_, fn) doc:on(sel_, 'click', gear.guard('click ' .. sel_, fn)) end
        on('.crow', function(e) local id = rows[tostring(e.current)]; if id then sel.id = id end end)
        on('#reload', function() env.reload() end)
        on('#leave', function() local hr = hero(); if hr then leave(hr) end end)
        on('#take', function()
            local hr = hero()
            local prof = sel.id and state.profiles[sel.id]
            if not (hr and prof) then return end
            local _, body = hr:class()
            local current = assignment(hr)
            local usable = (prof.body_id == body) or (body == 7 and prof.body_id == 6)
            if usable and not (current and current.id == prof.id) then take(hr, prof) end
        end)
    end

    local function draw()
        if not shown then return end
        if not doc then load_doc() end
        if not doc then return end
        for k, v in pairs(snapshot()) do
            if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
        end
        doc:draw({layer = 'hud'})
    end

    return {draw = draw, select = function(id) sel.id = id end,
        open = function(on) shown = on ~= false end, toggle = function() shown = not shown end}
end

return M
