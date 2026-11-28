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
--   env.bring_all()                bring every kept hero that is not in the party (while there is room)
--   env.keep_hero(c), env.keep_all(only_new)   keep one hero / every hero (only the ones not kept yet) for other savegames
--   env.move_to_me(c), env.move_all_to_me()    a stuck companion joins the hero you play
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
    local bring_all, keep_hero, keep_all, move_to_me, move_all_to_me = env.bring_all, env.keep_hero, env.keep_all, env.move_to_me, env.move_all_to_me
    local separate, purse_of, give_gold, take_gold = env.separate, env.purse_of, env.give_gold, env.take_gold
    local store, prefs, files, refresh_files = env.store, env.prefs, env.files, env.refresh_files
    local NAMES, CLASS_LABEL = env.NAMES, env.CLASS_LABEL

    local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
    local BEHAVIOURS = {'aggressive', 'defensive', 'passive', 'hold'}
    local BEHAVIOUR_LABEL = {aggressive = 'Aggressive', defensive = 'Defensive', passive = 'Passive', hold = 'Wait here', default = 'Default'}
    local AMOUNTS = {100, 1000, 10000, 'all'}
    local AMOUNT_LABELS = {'100', '1,000', '10,000', 'All'}
    local MB = {'vanilla', 'assist', 'passive'}
    local ML = {'As the game does', 'Assist (fight the party\'s target)', 'Passive (stay with you)'}
    local USE_LABEL = {target = 'on the target', self = 'in a fight, on themselves', heal = 'when someone is hurt', form = 'when a fight starts (and to change back after it)'}
    local STYLES = {'balanced', 'arts', 'weapon', 'ranged', 'protector'}
    local STYLE_LABEL = {balanced = 'Weapon and combat arts', arts = 'Combat arts only', weapon = 'Weapon first', ranged = 'Ranged weapon',
        protector = 'Protector (guards you)'}
    local STYLE_TIP = 'How they fight: combat arts and spells as soon as they are ready, the weapon in between (default); '
        .. 'combat arts and spells only, keeping back from the fight in between (a battle mage); or the weapon first, '
        .. 'combat arts now and then; or with the ranged weapon of their weapon slots (bow, crossbow, musket), taking it up '
        .. 'when a fight starts; or as a protector: close around you, fighting whatever comes nearest to you'

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
    local open_filter = ''
    local pop_rect            -- the open list's box last frame (its height decides whether it opens above its button)

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
        local x, y
        if w and w.drawn then
            -- the window's own place, not what it drew last frame (its portraits shake when the hero takes heavy damage, and
            -- the column slid sideways with them); its rows: the hero you play and each mercenary
            x = (w.x or 0) + (w.frame_x or 0)
            y = (w.y or 0) + (w.frame_y or 0) + 16 + (1 + #ai.mercenaries()) * ROW
        elseif w then
            local st = ui.state()
            x, y = (st.screen_right or 1024) - PW, 16
        else
            return nil
        end
        return math.floor(x + 0.5), math.floor(y + 0.5) - 2
    end

    local function same(a, b)
        if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
        if #a ~= #b then return false end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        return true
    end

    local function portraits_model(m)
        -- Hidden while the party window is open: it lists every hero, and with many companions the portrait columns reach under
        -- the window, whose frame is drawn behind the document (the portraits would show through it).
        if shown or not setting('portraits', true) or not party.available() then return end
        local list = party.companions()
        if #list == 0 then return end
        m.portraits_on = true
        local x, y = column_place()
        m.px, m.py = px(x or cfg.portraits_x or 932), px(y or cfg.portraits_y or 260)
        -- The size (setting) scales the whole grid. Under the game's column: as many rows as fit down the screen's right edge
        -- (the taskbar is in the middle), then a further column to the left. Placed by hand: a grid of the columns setting,
        -- left to right, then top to bottom (1 column: one under the other).
        local scale = math.max(0.3, math.min(1, setting('portrait_size', 100) / 100))
        local follow = setting('portraits_follow', true) and x ~= nil
        local CW = PW + 6
        local rows, cols
        if follow then
            local st = ui.state()
            rows = math.max(1, math.floor(((st.screen_bottom or 768) - 24 - y) / (ROW * scale)))
            cols = math.ceil(#list / rows)
        else
            cols = math.max(1, math.min(#list, setting('portrait_columns', 1)))
            -- no wider than the screen (the layout then keeps the whole grid on it, as the game keeps its windows): wraps earlier
            local st = ui.state()
            local fit = math.floor(((st.screen_right or 1024) - (st.screen_left or 0)) / (CW * scale))
            cols = math.max(1, math.min(cols, fit))
            rows = math.ceil(#list / cols)
        end
        m.pfollow = follow
        m.pscale = ('scale(%.3f)'):format(scale)
        m.pwidth = follow and px(PW - 4) or px(cols * CW * scale)
        m.pinner = follow and px(PW - 4) or px(cols * CW)
        m.pheight = px(math.min(#list, rows) * ROW * scale)
        local function place_of(i)
            if follow then return -math.floor((i - 1) / rows) * CW, ((i - 1) % rows) * ROW end
            return ((i - 1) % cols) * CW, math.floor((i - 1) / cols) * ROW
        end
        for i, c in ipairs(list) do
            local dead = c:is_dead()
            local hp, max = c:hp() or 0, c:max_hp() or 1
            local frac = dead and 0 or math.min(1, math.max(0, hp / math.max(1, max)))
            local top = frac >= 1 and 0 or RING_TOP + (1 - frac) * (RING_BOTTOM - RING_TOP)
            local id = 'pt' .. c.id
            by_id[id] = c
            m.portraits[#m.portraits + 1] = {
                id = id, dead = dead, image = image_url(c:portrait()), level = tostring(c:level() or ''),
                left = px((place_of(i))), top = px(select(2, place_of(i))),
                xp = px(71 * xp_fraction(c)), red_top = px(top * RH), red_h = frac > 0 and px(RH - top * RH) or '0dp',
                tip = name_of(c) .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level())
                    .. ')\n' .. (dead and 'Fallen' or ('Click to play' .. key_hint('next'))),
            }
        end
        if follow and (not placed_at or placed_at[1] ~= x or placed_at[2] ~= y) then
            if ui.set_panel_rect('companions:portraits', x, y) then placed_at = {x, y} end
        end
    end

    -- The abilities of a hero for the tactics list: the ones the AI uses, in their priority (the top one first), then the others.
    local FLEE_STEPS = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60}
    local function ability_entries(c)
        local r = record(c.id)
        local list = c:abilities() or {}
        for _, k in ipairs(c:combos() or {}) do
            local names = {}
            for _, a in ipairs(k.arts) do names[#names + 1] = ai.ability_info(a).name end
            list[#list + 1] = {id = k.id, level = 0, bonus = 0, combo = 'Combo ' .. (k.slot + 1) .. ': ' .. table.concat(names, ', ')}
        end
        local rank = {}
        for i, id in ipairs(r.order or {}) do rank[id] = i end
        local used, unused = {}, {}
        for i, a in ipairs(list) do
            a.natural = i
            local use = a.combo and 'target' or ai.use_of(a.id)
            a.use = use
            if use then used[#used + 1] = a else unused[#unused + 1] = a end
        end
        table.sort(used, function(x, y)
            local rx, ry = rank[x.id] or (10000 + x.natural), rank[y.id] or (10000 + y.natural)
            return rx < ry
        end)
        return used, unused
    end

    local function flee_index(r)
        for i, v in ipairs(FLEE_STEPS) do if r.flee and math.abs(r.flee * 100 - v) < 1 then return i end end
        return 0
    end

    local function tactics_model(m, c)
        local r = record(c.id)
        local t = {title = 'Tactics of ' .. name_of(c), style = STYLE_LABEL[r.style or 'balanced'], style_tip = STYLE_TIP, none = false, abilities = {},
            repos = r.reposition == true}
        local flee_at = flee_index(r)
        t.flee_text = flee_at == 0 and 'Never' or ('Below %d%% health'):format(FLEE_STEPS[flee_at])
        t.flee_prev_off, t.flee_next_off = flee_at == 0, flee_at == #FLEE_STEPS
        local used, unused = ability_entries(c)
        t.none = #used + #unused == 0
        for i, a in ipairs(used) do
            local info = a.combo and {name = a.combo} or ai.ability_info(a.id)
            local id = 'use' .. c.id .. '_' .. a.id
            by_id[id] = {hero = c, ability = a.id}
            by_id['mup' .. c.id .. '_' .. a.id] = {hero = c, ability = a.id}
            by_id['mdn' .. c.id .. '_' .. a.id] = {hero = c, ability = a.id}
            t.abilities[#t.abilities + 1] = {id = id, used = true, on = r.abilities[tostring(a.id)] ~= false,
                id_up = 'mup' .. c.id .. '_' .. a.id, id_dn = 'mdn' .. c.id .. '_' .. a.id, off_up = i == 1, off_dn = i == #used,
                text = a.combo and info.name or ('%s (level %d)'):format(info.name, a.level + a.bonus),
                tip = ('Used %s. Priority %d of %d: the arrows move it up or down, the one at the top is used first'):format(USE_LABEL[a.use], i, #used)}
        end
        for _, a in ipairs(unused) do
            local info = ai.ability_info(a.id)
            t.abilities[#t.abilities + 1] = {id = 'use' .. c.id .. '_' .. a.id, used = false, on = false, text = info.name, tip = ''}
        end
        m.tac = t
        m.tac_on = true
    end

    local function hero_by_id(id)
        for _, h in ipairs(party.heroes()) do if h.id == id then return h end end
    end

    local function arts_of(c, on)
        local r = record(c.id)
        r.abilities = {}
        if not on then
            local used = ability_entries(c)
            for _, a in ipairs(used) do r.abilities[tostring(a.id)] = false end
        end
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
            by_id['tome' .. c.id], by_id['kp' .. c.id] = c, c
            local kept_text = not r.kept and 'Not kept yet: it is not in a hero file another savegame can bring' or
                (r.kept.level == (c:level() or 0) and 'Kept for other savegames (click to write it again)' or
                ('Kept at level ' .. tostring(r.kept.level) .. ' (click to write the hero as they are now)'))
            local gold = separate() and purse_of(c) or (controlled and (c:gold() or 0) or nil)
            local can_dismiss = companion and not controlled
            local behaviour_options = {}
            behaviour_options[1] = {id = 'beh-' .. c.id .. '-0', label = BEHAVIOUR_LABEL.default, on = r.behaviour == nil}
            for i, behaviour in ipairs(BEHAVIOURS) do
                behaviour_options[i + 1] = {id = 'beh-' .. c.id .. '-' .. i, label = BEHAVIOUR_LABEL[behaviour], on = r.behaviour == behaviour}
            end
            m.heroes[#m.heroes + 1] = {
                id_play = 'play' .. c.id, id_name = 'name' .. c.id, id_beh = 'beh' .. c.id, id_tac = 'tac' .. c.id, id_dis = 'dis' .. c.id,
                id_me = 'tome' .. c.id, id_kp = 'kp' .. c.id, can_me = not controlled and not dead,
                keep_text = not r.kept and 'Keep' or (r.kept.level == (c:level() or 0) and 'Kept' or 'Keep again'), kept_new = not r.kept, can_keep = not dead,
                tip_kp = kept_text .. '. Keeping writes this hero to a hero file, with their tactics, that another savegame can bring into its party',
                image = image_url(c:portrait()), name = name_of(c), controlled = controlled, dead = dead,
                sub = ('%s, level %s%s%s'):format(CLASS_LABEL[c:class() or ''] or '?', tostring(c:level()), dead and ', fallen' or '',
                    gold and (separate() or controlled) and (', ' .. group(gold) .. ' gold' .. '') or ''),
                hp = px(130 * math.min(1, math.max(0, (c:hp() or 0) / math.max(1, c:max_hp() or 1)))),
                play = controlled and 'Playing' or 'Play', can_play = not controlled and not dead,
                tip_play = controlled and 'You play this hero' or 'Play this hero',
                can_name = companion, tip_name = companion and 'Another name for this companion' or 'Your own hero keeps the name you gave it',
                behaviour = index == 1 and BEHAVIOUR_LABEL.default or BEHAVIOUR_LABEL[BEHAVIOURS[index - 1]],
                beh_dd = 'beh-' .. c.id, beh_options = behaviour_options,
                tactics = win.tactics == c.id and 'Close' or 'Tactics',
                can_dismiss = can_dismiss, tip_dismiss = can_dismiss and 'Leaves the party for good, with what they wear (empty their backpack first)'
                    or 'Play another hero to dismiss this one',
            }
            if win.tactics == c.id then tactics_model(m, c) end
        end
        local full = #party.companions() >= setting('max_companions', 3)
        m.class_name = CLASS_LABEL[CLASS_ORDER[win.class]] or '?'
        for i, class in ipairs(CLASS_ORDER) do m.dd_classes[i] = {id = 'class-' .. i, label = CLASS_LABEL[class] or class, on = i == win.class} end
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
            for i, file in ipairs(files.list) do
                local flabel = files.labels[i] or '?'
                m.dd_files[i] = {id = 'file-' .. i, label = may_be_in_party(file) and ('! ' .. flabel) or flabel, on = i == files.index}
            end
        end
        m.can_bring = not full and #files.list > 0
        m.bring_tip = (maybe and 'A hero with this class and name is in the party already: this may be a second copy. ' or '')
            .. 'A copy of this hero joins where you stand, with their level, skills, equipment and backpack'
        if picked then
            m.picked = ('%s, %s, level %d'):format(picked.name ~= '' and picked.name or '?', CLASS_LABEL[picked.class or ''] or '?', picked.level or 0)
        end
        m.keep_label = 'Keep ' .. name_of(leader)
        m.can_bring_all = not full and #files.list > 0
        local mi = 1
        for i, b in ipairs(MB) do if prefs.data.merc_behaviour == b then mi = i end end
        m.merc_label = ML[mi]
        for i, label in ipairs(ML) do m.dd_mercs[i] = {id = 'merc-' .. i, label = label, on = i == mi} end
        m.merc_count = ('%d with the party'):format(#ai.mercenaries())
        m.purses_on = separate() and true or false
        if m.purses_on then
            m.amount_label = AMOUNT_LABELS[win.amount]
            for i, label in ipairs(AMOUNT_LABELS) do m.dd_amounts[i] = {id = 'amount-' .. i, label = label, on = i == win.amount} end
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
        local m = {portraits_on = false, px = '932dp', py = '260dp', pheight = '132dp', pwidth = '92dp', pinner = '92dp', pscale = 'scale(1)', pfollow = true, portraits = {}, open = false, title = '', msg = '', heroes = {},
            class_name = '', full = false, companions_text = '', no_files = true, file_label = '', can_bring = false, bring_tip = '', maybe = false,
            picked = '', keep_label = '', can_bring_all = false, merc_label = '', merc_count = '', purses_on = false, amount_label = '', purses = {},
            dd = open_filter, dd_classes = {}, dd_files = {}, dd_mercs = {}, dd_amounts = {}, dd_styles = {},
            pop = {open = false, left = '0dp', top = '0dp', width = '150dp', options = {{id = '', label = '', on = false}}},
            tac_on = false, tac = {title = '', style = '', style_tip = '', none = false, abilities = {}, flee_text = '', flee_prev_off = true, flee_next_off = false, repos = false}}
        by_id = {}
        portraits_model(m)
        window_model(m)
        for i, style in ipairs(STYLES) do
            local r
            for _, h in ipairs(party.heroes()) do if h.id == win.tactics then r = record(h.id) end end
            m.dd_styles[i] = {id = 'style-' .. i, label = STYLE_LABEL[style], on = r and (r.style or 'balanced') == style or (not r and style == 'balanced')}
        end
        -- the list of the open drop-down, under its button (above it when it would reach past the screen's bottom)
        if open_filter ~= '' and doc then
            local button, options
            local lists = {class = m.dd_classes, heroes = m.dd_files, mercs = m.dd_mercs, goldamount = m.dd_amounts, style = m.dd_styles}
            if lists[open_filter] then button, options = '#' .. open_filter, lists[open_filter] end
            for _, h in ipairs(m.heroes) do
                if h.beh_dd == open_filter then button, options = '#' .. h.id_beh, h.beh_options end
            end
            local b, o = button and doc:query(button), doc:query('#party-origin')
            local br, orr = b and b:exists() and b:rect(), o and o:rect()
            if br and orr and options and #options > 0 then
                local pr = pop_rect or {h = #options * 30 + 8}
                local top = br.y + br.h
                local st = ui.state()
                if top + pr.h > (st.screen_bottom or 768) - 4 and br.y - pr.h >= (st.screen_top or 0) then top = br.y - pr.h end
                -- as wide as its button, or as its longest entry (an absolute box does not grow with its text in RmlUi)
                local chars = 0
                for _, o in ipairs(options) do chars = math.max(chars, #o.label) end
                m.pop = {open = true, left = ('%ddp'):format(math.floor(br.x - orr.x)), top = ('%ddp'):format(math.floor(top - orr.y)),
                    width = ('%ddp'):format(math.floor(math.max(br.w, chars * 7.5 + 28))), options = options}
            end
        end
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
            if c then open_filter = open_filter == 'beh-' .. c.id and '' or 'beh-' .. c.id end
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
        on('#party-ddshade', function() open_filter = '' end)
        on('#class', function() open_filter = open_filter == 'class' and '' or 'class' end)
        on('.party-ddlist .opt', function(e)
            local id = tostring(e.current)
            local i
            i = tonumber(id:match('^class%-([%d]+)$'))
            if i and CLASS_ORDER[i] then win.class = i
            else
                i = tonumber(id:match('^file%-([%d]+)$'))
                if i and files.list[i] then files.index = i
                else
                    i = tonumber(id:match('^merc%-([%d]+)$'))
                    if i and MB[i] then prefs.data.merc_behaviour = MB[i]; prefs:changed()
                    else
                        i = tonumber(id:match('^amount%-([%d]+)$'))
                        if i and AMOUNTS[i] then win.amount = i
                        else
                            i = tonumber(id:match('^style%-([%d]+)$'))
                            if i and STYLES[i] then
                                local c
                                for _, h in ipairs(party.heroes()) do if h.id == win.tactics then c = h end end
                                if c then
                                    local r = record(c.id)
                                    r.style = STYLES[i] ~= 'balanced' and STYLES[i] or nil
                                    store:changed()
                                end
                            else
                                local cid, bi = id:match('^beh%-([%d]+)%-([%d]+)$')
                                cid, bi = tonumber(cid), tonumber(bi)
                                if cid then
                                    local c
                                    for _, h in ipairs(party.heroes()) do if h.id == cid then c = h end end
                                    if c then
                                        local r = record(c.id)
                                        r.behaviour = bi > 0 and BEHAVIOURS[bi] or nil
                                        store:changed()
                                    end
                                end
                            end
                        end
                    end
                end
            end
            open_filter = ''
        end)
        on('#recruit', function()
            if #party.companions() < setting('max_companions', 3) then recruit(CLASS_ORDER[win.class]) end
        end)
        on('#heroes', function() open_filter = open_filter == 'heroes' and '' or 'heroes' end)
        on('#bring', function()
            if #party.companions() < setting('max_companions', 3) and files.list[files.index] then bring(files.list[files.index]) end
        end)
        on('#keep', function() keep() end)
        on('#mercs', function() open_filter = open_filter == 'mercs' and '' or 'mercs' end)
        on('#goldamount', function() open_filter = open_filter == 'goldamount' and '' or 'goldamount' end)
        on('[id^=give]', function(e)
            local c, leader = target(e), leader_of()
            if c and c ~= leader and (leader:gold() or 0) > 0 then give_gold(c, AMOUNTS[win.amount]) end
        end)
        on('[id^=take]', function(e)
            local c, leader = target(e), leader_of()
            if c and c ~= leader and purse_of(c) > 0 then take_gold(c, AMOUNTS[win.amount]) end
        end)
        on('#bringall', function() bring_all() end)
        on('#keepall', function() keep_all(false) end)
        on('#keepnew', function() keep_all(true) end)
        on('#allme', function() move_all_to_me() end)
        on('#artsoff', function() for _, c in ipairs(party.companions()) do arts_of(c, false) end store:changed() end)
        on('#artson', function() for _, c in ipairs(party.companions()) do arts_of(c, true) end store:changed() end)
        on('[id^=tome]', function(e) local c = target(e); if c then move_to_me(c) end end)
        on('[id^=kp]', function(e) local c = target(e); if c and not c:is_dead() then keep_hero(c); refresh_files() end end)
        -- the tactics of the hero in the list
        local function tac_hero() return win.tactics and hero_by_id(win.tactics) end
        local function flee_step(by)
            local c = tac_hero(); if not c then return end
            local r = record(c.id)
            local at = math.max(0, math.min(#FLEE_STEPS, flee_index(r) + by))
            r.flee = at > 0 and FLEE_STEPS[at] / 100 or nil
            store:changed()
        end
        on('#fleeprev', function() flee_step(-1) end)
        on('#fleenext', function() flee_step(1) end)
        on('#repos', function()
            local c = tac_hero(); if not c then return end
            local r = record(c.id)
            r.reposition = (not r.reposition) or nil
            store:changed()
        end)
        on('#heroartsoff', function() local c = tac_hero(); if c then arts_of(c, false); store:changed() end end)
        on('#heroartson', function() local c = tac_hero(); if c then arts_of(c, true); store:changed() end end)
        on('#prioreset', function() local c = tac_hero(); if c then record(c.id).order = nil; store:changed() end end)
        local function move(e, step)
            local t = target(e)
            if not t then return end
            local used = ability_entries(t.hero)
            local order, at = {}, nil
            for i, a in ipairs(used) do order[i] = a.id; if a.id == t.ability then at = i end end
            local to = at and at + step
            if not at or to < 1 or to > #order then return end
            order[at], order[to] = order[to], order[at]
            record(t.hero.id).order = order
            store:changed()
        end
        on('[id^=mup]', function(e) move(e, -1) end)
        on('[id^=mdn]', function(e) move(e, 1) end)
        on('#style', function() open_filter = open_filter == 'style' and '' or 'style' end)
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
        local e = m.pop.open and doc:query('#party-pop')
        pop_rect = e and e:exists() and e:rect() or nil
    end

    return {draw = draw,
        open = function(on) shown = on ~= false end, toggle = function() shown = not shown end,
        rect = function(sel) local e = doc and doc:query(sel); return e and e:rect() or nil end}
end

return M
