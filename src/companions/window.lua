-- Companions: the portraits and the party window (what main.lua shows; main.lua keeps the party itself).
--
-- Portraits: the companions under the game's own portraits, a click plays that hero. The party window (Home): who is in
-- the party (play, name, behaviour, dismiss), recruiting and bringing heroes, the game's mercenaries, and the tactics
-- of one hero.
--
-- Both are ui/party.rml (the game theme): one model of ready-made values, rebuilt every frame (only what changed is written), and
-- delegated click listeners. Nothing here changes the party by itself: every action goes back through the functions main.lua
-- passes to window.new (env): play, recruit, dismiss, keep, bring, record, store, prefs and the heroes' files.
--   env.play(c)             play that hero             env.recruit(class)   a new companion of that class
--   env.dismiss(c)          dismiss                     env.bring(f)         bring the hero of a hero file
--   env.keep()              keep the hero you play     env.name_of(c)       the companion's name
--   env.record(id)          the stored record (name, behaviour, abilities switched off)
--   env.store, env.prefs    the stores of main.lua (:changed() after a change)
--   env.files, env.refresh_files   the hero files list and its reader
--   env.setting(id, fallback)      a setting of the mod
--   env.may_be_in_party(f)         a hero file whose class and name match a hero of the party (a warning, not a block)
--   env.separate(), env.purse_of(c), env.give_gold(c, n|'all'), env.take_gold(c, n|'all')   separate purses (setting)
--   env.NAMES, env.CLASS_LABEL     names per class, class labels
-- Returns {draw = fn, open = fn, toggle = fn, rect = fn}.

local ai = require('ai')

local M = {}

function M.new(env)
    local ui = gear.ui
    local party = gear.party
    local cfg = gear.config
    local play, recruit, dismiss, keep, bring = env.play, env.recruit, env.dismiss, env.keep, env.bring
    local name_of, record, setting = env.name_of, env.record, env.setting
    local may_be_in_party = env.may_be_in_party
    local separate, purse_of, give_gold, take_gold = env.separate, env.purse_of, env.give_gold, env.take_gold
    local store, prefs, files, refresh_files = env.store, env.prefs, env.files, env.refresh_files
    local NAMES, CLASS_LABEL = env.NAMES, env.CLASS_LABEL

    local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
    local BEHAVIOURS = {'aggressive', 'defensive', 'passive'}
    local BEHAVIOUR_LABEL = {aggressive = 'Aggressive', defensive = 'Defensive', passive = 'Passive', default = 'Default'}
    local AMOUNTS = {100, 1000, 10000, 'all'}
    local AMOUNT_LABELS = {'100', '1,000', '10,000', 'All'}
    local MB = {'vanilla', 'assist', 'passive'}
    local ML = {'As the game does', 'Assist (fight the party\'s target)', 'Passive (stay with you)'}
    local USE_LABEL = {target = 'on the target', self = 'in a fight, on themselves', heal = 'when someone is hurt', form = 'when a fight starts (and to change back after it)'}
    local STYLES = {'balanced', 'arts', 'weapon', 'ranged'}
    local STYLE_LABEL = {balanced = 'Weapon and combat arts', arts = 'Combat arts only', weapon = 'Weapon first', ranged = 'Ranged weapon'}
    local STYLE_TIP = 'How they fight: combat arts and spells as soon as they are ready, the weapon in between (default); '
        .. 'combat arts and spells only, keeping back from the fight in between (a battle mage); or the weapon first, '
        .. 'combat arts now and then; or with the ranged weapon of their weapon slots (bow, crossbow, musket), taking it up '
        .. 'when a fight starts'

    local function key_hint(id)
        local k = gear.keys.label(id)
        return k ~= '' and (' (' .. k .. ')') or ''
    end

    local function group(n)   -- 1234567 -> 1,234,567
        local t = tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse()
        return (t:gsub('^,', ''))
    end

    local win = {class = 4, tactics = nil, amount = 2}
    local shown = false
    local doc
    local last = {}
    local by_id = {}          -- element id -> hero / ability, for the click handlers

    -- Experience toward the next level: the game's levels (gear's experience_range), cached per hero and level.
    local xp_cache = {}
    local function xp_fraction(c)
        if not c.experience_range then return 0 end
        local lvl = c:level() or 0
        local e = xp_cache[c.id]
        if not e or e.level ~= lvl then
            local _, from, to = c:experience_range()
            e = {level = lvl, from = from, to = to}
            xp_cache[c.id] = e
        end
        local now = c:experience() or 0
        if not e.from or not e.to or e.to <= e.from then return 0 end
        return math.min(1, math.max(0, (now - e.from) / (e.to - e.from)))
    end

    -- The portrait ring: grey where health is lost, red for what is left, filled from the bottom as the game's ring does.
    local RING_TOP, RING_BOTTOM, RH = 0.09, 0.95, 108
    local PW, ROW = 96, 132

    local function image_url(id) return id and ('gear:image/' .. id) or '' end

    local function px(n) return ('%ddp'):format(math.floor(n + 0.5)) end

    -- Where the column goes: under the game's own portraits (its UI_WND_MERC at the screen's right edge).
    local placed_at
    local function column_place()
        local w = ui.window('UI_WND_MERC')
        local b = w and w.drawn and w.bounds
        local x, y
        if b and b.w and b.w > 0 then
            x, y = b.x, b.y + 2 + math.floor(b.h / 120 + 0.5) * ROW
        elseif w then
            local st = ui.state()
            x, y = (st.screen_right or 1024) - PW, 16
        else
            return nil
        end
        return math.floor(x + 0.5) - 2, math.floor(y + 0.5) - 2
    end

    local function same(a, b)
        if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
        if #a ~= #b then return false end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        return true
    end

    local function portraits_model(m)
        if not setting('portraits', true) or not party.available() then return end
        local list = party.companions()
        if #list == 0 then return end
        m.portraits_on = true
        local x, y = column_place()
        m.px, m.py = px(x or cfg.portraits_x or 932), px(y or cfg.portraits_y or 260)
        for _, c in ipairs(list) do
            local dead = c:is_dead()
            local hp, max = c:hp() or 0, c:max_hp() or 1
            local frac = dead and 0 or math.min(1, math.max(0, hp / math.max(1, max)))
            local top = frac >= 1 and 0 or RING_TOP + (1 - frac) * (RING_BOTTOM - RING_TOP)
            local id = 'pt' .. c.id
            by_id[id] = c
            m.portraits[#m.portraits + 1] = {
                id = id, dead = dead, image = image_url(c:portrait()), level = tostring(c:level() or ''),
                xp = px(71 * xp_fraction(c)), red_top = px(top * RH), red_h = frac > 0 and px(RH - top * RH) or '0dp',
                tip = name_of(c) .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level())
                    .. ')\n' .. (dead and 'Fallen' or ('Click to play' .. key_hint('next'))),
            }
        end
        if x and setting('portraits_follow', true) and (not placed_at or placed_at[1] ~= x or placed_at[2] ~= y) then
            if ui.set_panel_rect('companions:portraits', x, y) then placed_at = {x, y} end
        end
    end

    local function tactics_model(m, c)
        local r = record(c.id)
        local t = {title = 'Tactics of ' .. name_of(c), style = STYLE_LABEL[r.style or 'balanced'], style_tip = STYLE_TIP, none = false, abilities = {}}
        local list = c:abilities() or {}
        for _, k in ipairs(c:combos() or {}) do
            local names = {}
            for _, a in ipairs(k.arts) do names[#names + 1] = ai.ability_info(a).name end
            list[#list + 1] = {id = k.id, level = 0, bonus = 0, combo = 'Combo ' .. (k.slot + 1) .. ': ' .. table.concat(names, ', ')}
        end
        t.none = #list == 0
        for _, a in ipairs(list) do
            local info = a.combo and {name = a.combo} or ai.ability_info(a.id)
            local use = a.combo and 'target' or ai.use_of(a.id)
            local id = 'use' .. c.id .. '_' .. a.id
            if use then
                by_id[id] = {hero = c, ability = a.id}
                t.abilities[#t.abilities + 1] = {id = id, used = true, on = r.abilities[tostring(a.id)] ~= false,
                    text = a.combo and info.name or ('%s (level %d)'):format(info.name, a.level + a.bonus), tip = 'Used ' .. USE_LABEL[use]}
            else
                t.abilities[#t.abilities + 1] = {id = id, used = false, on = false, text = info.name, tip = ''}
            end
        end
        m.tac = t
        m.tac_on = true
    end

    local function window_model(m)
        m.open = shown
        m.title = 'Party' .. key_hint('window')
        if not shown then return end
        local ok, why = party.available()
        if not ok then m.msg = why or 'The party works in single player only.' return end
        local heroes = party.heroes()
        local leader = heroes[1]
        for _, c in ipairs(heroes) do
            local controlled = c == leader
            local dead = c:is_dead()
            local companion = c.id >= party.FIRST_ID
            local r = record(c.id)
            local index = 1
            for i, b in ipairs(BEHAVIOURS) do if r.behaviour == b then index = i + 1 end end
            by_id['play' .. c.id], by_id['name' .. c.id], by_id['beh' .. c.id] = c, c, c
            by_id['tac' .. c.id], by_id['dis' .. c.id] = c, c
            local can_dismiss = companion and not controlled
            m.heroes[#m.heroes + 1] = {
                id_play = 'play' .. c.id, id_name = 'name' .. c.id, id_beh = 'beh' .. c.id, id_tac = 'tac' .. c.id, id_dis = 'dis' .. c.id,
                image = image_url(c:portrait()), name = name_of(c), controlled = controlled, dead = dead,
                sub = ('%s, level %s%s'):format(CLASS_LABEL[c:class() or ''] or '?', tostring(c:level()), dead and ', fallen' or ''),
                hp = px(130 * math.min(1, math.max(0, (c:hp() or 0) / math.max(1, c:max_hp() or 1)))),
                play = controlled and 'Playing' or 'Play', can_play = not controlled and not dead,
                tip_play = controlled and 'You play this hero' or 'Play this hero',
                can_name = companion, tip_name = companion and 'Another name for this companion' or 'Your own hero keeps the name you gave it',
                behaviour = index == 1 and BEHAVIOUR_LABEL.default or BEHAVIOUR_LABEL[BEHAVIOURS[index - 1]],
                tactics = win.tactics == c.id and 'Close' or 'Tactics',
                can_dismiss = can_dismiss, tip_dismiss = can_dismiss and 'Leaves the party for good, with what they wear (empty their backpack first)'
                    or 'Play another hero to dismiss this one',
            }
            if win.tactics == c.id then tactics_model(m, c) end
        end
        local full = #party.companions() >= setting('max_companions', 3)
        m.class_name = CLASS_LABEL[CLASS_ORDER[win.class]] or '?'
        m.full = full
        m.companions_text = ('%d of %d companions'):format(#party.companions(), setting('max_companions', 3))
        if not files.loaded then refresh_files() end
        m.no_files = #files.list == 0
        local picked = files.list[files.index]
        local maybe = may_be_in_party(picked)
        m.maybe = maybe and true or false
        if #files.list > 0 then
            local label = files.labels[files.index] or '?'
            m.file_label = maybe and ('! ' .. label) or label
        end
        m.can_bring = not full and #files.list > 0
        m.bring_tip = (maybe and 'A hero with this class and name is in the party already: this may be a second copy. ' or '')
            .. 'A copy of this hero joins where you stand, with their level, skills, equipment and backpack'
        if picked then
            m.picked = ('%s, %s, level %d'):format(picked.name ~= '' and picked.name or '?', CLASS_LABEL[picked.class or ''] or '?', picked.level or 0)
        end
        m.keep_label = 'Keep ' .. name_of(leader) .. ' for other savegames'
        local mi = 1
        for i, b in ipairs(MB) do if prefs.data.merc_behaviour == b then mi = i end end
        m.merc_label = ML[mi]
        m.merc_count = ('%d with the party'):format(#party.mercenaries())
        m.purses_on = separate() and true or false
        if m.purses_on then
            m.amount_label = AMOUNT_LABELS[win.amount]
            for _, c in ipairs(heroes) do
                local controlled = c == leader
                by_id['give' .. c.id], by_id['take' .. c.id] = c, c
                m.purses[#m.purses + 1] = {
                    id_give = 'give' .. c.id, id_take = 'take' .. c.id, controlled = controlled,
                    text = ('%s%s: %s gold'):format(controlled and 'Playing: ' or '', name_of(c), group(purse_of(c))),
                    can_give = not controlled and (leader:gold() or 0) > 0, can_take = not controlled and purse_of(c) > 0,
                    tip_give = controlled and 'Pick another hero to give gold to' or ('Gives gold of the hero you play to ' .. name_of(c)),
                    tip_take = controlled and 'This is the hero you play' or ('Takes gold from ' .. name_of(c) .. ' to the hero you play'),
                }
            end
        end
    end

    local function snapshot()
        local m = {portraits_on = false, px = '932dp', py = '260dp', portraits = {}, open = false, title = '', msg = '', heroes = {},
            class_name = '', full = false, companions_text = '', no_files = true, file_label = '', can_bring = false, bring_tip = '', maybe = false,
            picked = '', keep_label = '', merc_label = '', merc_count = '', purses_on = false, amount_label = '', purses = {},
            tac_on = false, tac = {title = '', style = '', style_tip = '', none = false, abilities = {}}}
        by_id = {}
        portraits_model(m)
        window_model(m)
        return m
    end

    local function leader_of() local h = party.heroes(); return h[1] end

    local function load_doc()
        local m = snapshot()
        last = m
        local err
        doc, err = ui.rml.load('ui/party.rml', {dp = true, model = m})
        if not doc then gear.log('companions: ui/party.rml failed: ' .. tostring(err)) return end
        local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
        local function target(e) return by_id[tostring(e.current)] end
        on('.pt', function(e) local c = target(e); if c and not c:is_dead() then play(c) end end)
        on('[id^=play]', function(e) local c = target(e); if c and c ~= leader_of() and not c:is_dead() then play(c) end end)
        on('[id^=name]', function(e)
            local c = target(e)
            if not c or c.id < party.FIRST_ID then return end
            local list = NAMES[c:class() or ''] or {'Companion'}
            local cur, at = name_of(c), 0
            for i, n in ipairs(list) do if n == cur then at = i end end
            local r = record(c.id)
            r.name = list[at % #list + 1]
            store:changed()
            c:set_name(r.name)
        end)
        on('[id^=beh]', function(e)
            local c = target(e)
            if not c then return end
            local r = record(c.id)
            local index = 1
            for i, b in ipairs(BEHAVIOURS) do if r.behaviour == b then index = i + 1 end end
            local new = index % (#BEHAVIOURS + 1) + 1
            r.behaviour = new > 1 and BEHAVIOURS[new - 1] or nil
            store:changed()
        end)
        on('[id^=tac]', function(e)
            local c = target(e)
            if not c then return end
            if win.tactics == c.id then win.tactics = nil else win.tactics = c.id end
        end)
        on('[id^=dis]', function(e)
            local c = target(e)
            if c and c.id >= party.FIRST_ID and c ~= leader_of() then dismiss(c) end
        end)
        on('#class', function() win.class = win.class % #CLASS_ORDER + 1 end)
        on('#recruit', function()
            if #party.companions() < setting('max_companions', 3) then recruit(CLASS_ORDER[win.class]) end
        end)
        on('#heroes', function() if #files.list > 0 then files.index = files.index % #files.list + 1 end end)
        on('#bring', function()
            if #party.companions() < setting('max_companions', 3) and files.list[files.index] then bring(files.list[files.index]) end
        end)
        on('#keep', function() keep() end)
        on('#mercs', function()
            local mi = 1
            for i, b in ipairs(MB) do if prefs.data.merc_behaviour == b then mi = i end end
            prefs.data.merc_behaviour = MB[mi % #MB + 1]
            prefs:changed()
        end)
        on('#goldamount', function() win.amount = win.amount % #AMOUNTS + 1 end)
        on('[id^=give]', function(e)
            local c, leader = target(e), leader_of()
            if c and c ~= leader and (leader:gold() or 0) > 0 then give_gold(c, AMOUNTS[win.amount]) end
        end)
        on('[id^=take]', function(e)
            local c, leader = target(e), leader_of()
            if c and c ~= leader and purse_of(c) > 0 then take_gold(c, AMOUNTS[win.amount]) end
        end)
        on('#style', function()
            local c
            for _, h in ipairs(party.heroes()) do if h.id == win.tactics then c = h end end
            if not c then return end
            local r = record(c.id)
            local index = 1
            for i, st in ipairs(STYLES) do if (r.style or 'balanced') == st then index = i end end
            local new = STYLES[index % #STYLES + 1]
            r.style = new ~= 'balanced' and new or nil
            store:changed()
        end)
        on('[id^=use]', function(e)
            local t = target(e)
            if not t then return end
            local r = record(t.hero.id)
            local key = tostring(t.ability)
            if r.abilities[key] == false then r.abilities[key] = nil else r.abilities[key] = false end
            store:changed()
        end)
    end

    local function draw()
        if not doc then load_doc() end
        if not doc then return end
        local m = snapshot()
        for k, v in pairs(m) do
            if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
        end
        doc:draw({layer = 'hud'})
    end

    return {draw = draw,
        open = function(on) shown = on ~= false end, toggle = function() shown = not shown end,
        rect = function(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end}
end

return M
