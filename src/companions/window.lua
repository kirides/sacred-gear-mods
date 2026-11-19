-- Companions: the portraits and the party window (what main.lua shows; main.lua keeps the party itself).
--
-- Portraits: the companions under the game's own portraits, a click plays that hero. The party window (Home): who is in
-- the party (play, name, behaviour, dismiss), recruiting and bringing heroes, the game's mercenaries, and the tactics
-- of one hero.
--
-- Nothing here changes the party by itself: every action goes back through the functions main.lua passes to
-- window.new (env): play, recruit, dismiss, keep, bring, record, store, prefs and the heroes' files. Drawing only.
--   env.play(c)             play that hero             env.recruit(class)   a new companion of that class
--   env.dismiss(c)          dismiss (second click)      env.bring(f)         bring the hero of a hero file
--   env.keep()              keep the hero you play     env.name_of(c)       the companion's name
--   env.record(id)          the stored record (name, behaviour, abilities switched off)
--   env.store, env.prefs    the stores of main.lua (:changed() after a change)
--   env.files, env.refresh_files   the hero files list and its reader
--   env.setting(id, fallback)      a setting of the mod
--   env.NAMES, env.CLASS_LABEL     names per class, class labels
-- Returns {draw_portraits = fn, draw_window = fn}.

local ai = require('ai')

local M = {}

function M.new(env)
    local ui = gear.ui
    local party = gear.party
    local cfg = gear.config
    local play, recruit, dismiss, keep, bring = env.play, env.recruit, env.dismiss, env.keep, env.bring
    local name_of, record, setting = env.name_of, env.record, env.setting
    local store, prefs, files, refresh_files = env.store, env.prefs, env.files, env.refresh_files
    local NAMES, CLASS_LABEL = env.NAMES, env.CLASS_LABEL

    local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
    local BEHAVIOURS = {'aggressive', 'defensive', 'passive'}
    local BEHAVIOUR_LABEL = {aggressive = 'Aggressive', defensive = 'Defensive', passive = 'Passive', default = 'Default'}

    local DIM, ACCENT, GOOD, BAD = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040

    local function key_hint(id)
        local k = gear.keys.label(id)
        return k ~= '' and (' (' .. k .. ')') or ''
    end


    ---------------------------------------------------------------------------------------------------------------
    -- Portraits: the companions under the game's own portraits. A click plays that hero; the controller's D-pad stops on
    -- them like on any window button.
    ---------------------------------------------------------------------------------------------------------------
    -- The portraits look like the game's own (its mercenaries' at the top right): the portrait ring of GUI_main_02 (red;
    -- grey when fallen, gilded under the cursor) with the round portrait inside, the game's health bar under it.
    local IMG_RING, IMG_RING_GREY, IMG_BAR, IMG_BAR_FILL = 41, 42, 66, 67
    -- Measured against the game's own portraits: the ring at its own size, the portrait over its hole (stretched as the
    -- game does), the health bar under it, the rows 128 apart from the top of the game's column.
    local RW, RH = 96, 108              -- the ring
    local PX, PY, PIW, PIH = 8, 20, 66, 72  -- the portrait
    local BX, BY, BW, BH = 7, 105, 73, 9    -- the health bar
    local PW, ROW = RW, 132

    local function bar(x, y, w, h, frac, color)
        ui.rect(x, y, w, h, 0xC0000000)
        ui.rect(x + 1, y + 1, math.max(0, (w - 2) * math.min(1, math.max(0, frac))), h - 2, color)
    end

    -- The game's health bar: its frame, the green beads, the lost part dimmed.
    -- The game's bead bar: its frame, the green beads up to `frac` (experience toward the next level, as the game shows
    -- its own heroes'), the rest dark.
    local function bead_bar(x, y, frac)
        frac = math.min(1, math.max(0, frac))
        if not ui.image(IMG_BAR, x, y, BW, BH) then
            return bar(x, y, BW, BH - 2, frac, GOOD)
        end
        if frac > 0 then
            ui.image(IMG_BAR_FILL, x + 1, y + 1, BW - 2, BH - 2, {crop = {0, 0, frac, 1}})
        end
    end

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
        return (now - e.from) / (e.to - e.from)
    end

    -- The ring's circle within its image (the hanger above it, the ornament beside it): the health gauge fills it from
    -- the bottom as the game's ring does.
    local RING_TOP, RING_BOTTOM = 0.09, 0.95

    local function draw_portrait(c, x, y)
        local dead = c:is_dead()
        local r = ui.region('portrait' .. c.id, x, y + 6, RW - 8, BY + BH - 6, {
            tooltip = name_of(c) .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level())
                .. ')\n' .. (dead and 'Fallen' or ('Click to play' .. key_hint('next')))})
        -- as the game draws it: the ring, grey where health is lost and red for what is left (gilded under the cursor),
        -- the portrait over it, the experience beads below
        local hp, max = c:hp() or 0, c:max_hp() or 1
        local frac = dead and 0 or math.min(1, math.max(0, hp / math.max(1, max)))
        local drawn = ui.image(IMG_RING_GREY, x, y, RW, RH, {color = dead and 0xFF808080 or (r.hover and 0xFFFFD27A or 0xFFFFFFFF)})
        if drawn and frac > 0 then
            local top = RING_TOP + (1 - frac) * (RING_BOTTOM - RING_TOP)
            ui.image(IMG_RING, x, y, RW, RH, {crop = {0, frac >= 1 and 0 or top, 1, 1},
                color = r.hover and 0xFFFFE0A0 or 0xFFFFFFFF})
        end
        local img = c:portrait()
        if img then
            ui.image(img, x + PX, y + PY, PIW, PIH, {color = dead and 0xFF606060 or 0xFFFFFFFF})
        end
        if not drawn then ui.frame(x + 8, y + 12, RW - 18, RH - 18, r.hover and ACCENT or 0xFF6A5A3C, 1) end
        bead_bar(x + BX, y + BY, xp_fraction(c))
        local lvl = tostring(c:level() or '')
        ui.text(lvl, x + 13, y + 79, {color = 0xFF000000, size = 12})
        ui.text(lvl, x + 12, y + 78, {color = ACCENT, size = 12})
        if r.clicked and not dead then play(c) end
    end

    -- Where the column goes: under the game's own portraits (its UI_WND_MERC at the screen's right edge), so the
    -- companions continue that column; the layout's 1024x768 place from the config when the game's is not known.
    local placed_at
    local function column_place()
        local w = ui.window('UI_WND_MERC')
        local b = w and w.drawn and w.bounds
        local x, y
        if b and b.w and b.w > 0 then
            -- its rows: 120 high in its bounds, the rings 132 apart
            x, y = b.x, b.y + 2 + math.floor(b.h / 120 + 0.5) * ROW
        elseif w then
            local st = ui.state()
            x, y = (st.screen_right or 1024) - PW, 16
        else
            return nil
        end
        return math.floor(x + 0.5) - 2, math.floor(y + 0.5) - 2
    end

    local function draw_portraits()
        if not setting('portraits', true) or not party.available() then return end
        local list = party.companions()
        if #list == 0 then return end
        local x, y = column_place()
        if x and setting('portraits_follow', true) and (not placed_at or placed_at[1] ~= x or placed_at[2] ~= y) then
            if ui.set_panel_rect('companions:portraits', x, y) then placed_at = {x, y} end
        end
        local p = ui.panel('portraits', 'Companions', x or cfg.portraits_x or 932, y or cfg.portraits_y or 260, PW + 4, #list * ROW + 4, {bare = true, min_width = PW + 4, min_height = ROW})
        if not p.open then return end
        for i, c in ipairs(list) do
            draw_portrait(c, (p.content_x or 0) + 2, (p.content_y or 0) + 2 + (i - 1) * ROW)
        end
    end

    ---------------------------------------------------------------------------------------------------------------
    -- The party window: who is in the party, play / name / behaviour / dismiss, recruiting, and the tactics of one hero.
    ---------------------------------------------------------------------------------------------------------------
    local win = {class = 4, tactics = nil}
    -- One grid for the whole window: every control 22 high, buttons 72 wide, the hero rows' columns fixed, and below
    -- them a label column, a field column (300) and a button column (100). Missing controls keep their place (a greyed
    -- button), so the columns line up in every row.
    local G = {
        WIN_W = 640, CTRL_H = 22, BTN_W = 72, DD_W = 112, ROW_H = 52, GAP = 6,
        COLS = {190, 268, 346, 464, 542},   -- Play, Name, behaviour, Tactics, Dismiss (x in the content)
        LABEL_W = 96, FIELD_W = 300, BUTTON_W = 100, LINE = 30,
    }
    G.FIELD_X = G.LABEL_W
    G.BUTTON_X = G.FIELD_X + G.FIELD_W + G.GAP
    G.INFO_X = G.BUTTON_X + G.BUTTON_W + 10
    M.GRID = G
    local WIN_W = G.WIN_W

    local function label(text, x, y, opts)
        opts = opts or {}
        ui.text(text, x, y, {height = G.CTRL_H, valign = 'middle', color = opts.color or ACCENT, size = opts.size})
    end

    local function hero_row(c, x, y, w, leader)
        local controlled = c == leader
        local dead = c:is_dead()
        local img = c:portrait()
        if img then ui.image(img, x, y + 6, 40, 40, {fit = 'contain'}) end
        ui.frame(x, y + 6, 40, 40, controlled and ACCENT or 0xFF6A5A3C, 1)
        ui.text(name_of(c), x + 48, y + 6, {color = controlled and ACCENT or 0xFFFFFFFF, bold = true})
        ui.text(('%s, level %s%s'):format(CLASS_LABEL[c:class() or ''] or '?', tostring(c:level()), dead and ', fallen' or ''),
            x + 48, y + 22, {color = DIM, size = 12})
        bar(x + 48, y + 39, 130, 6, (c:hp() or 0) / math.max(1, c:max_hp() or 1), dead and BAD or GOOD)
        local cy = y + math.floor((G.ROW_H - G.CTRL_H) / 2)
        local col = function(i) return x + G.COLS[i] end
        local companion = c.id >= party.FIRST_ID
        if ui.button('play' .. c.id, col(1), cy, G.BTN_W, G.CTRL_H, controlled and 'Playing' or 'Play',
            {enabled = not controlled and not dead, tooltip = controlled and 'You play this hero' or 'Play this hero'}) then
            play(c)
        end
        if ui.button('name' .. c.id, col(2), cy, G.BTN_W, G.CTRL_H, 'Name', {enabled = companion,
            tooltip = companion and 'Another name for this companion' or 'Your own hero keeps the name you gave it'}) then
            local list = NAMES[c:class() or ''] or {'Companion'}
            local cur, at = name_of(c), 0
            for i, n in ipairs(list) do if n == cur then at = i end end
            local r = record(c.id)
            r.name = list[at % #list + 1]
            store:changed()
            c:set_name(r.name)
        end
        local r = record(c.id)
        local opts = {'Default'}
        for _, b in ipairs(BEHAVIOURS) do opts[#opts + 1] = BEHAVIOUR_LABEL[b] end
        local index = 1
        for i, b in ipairs(BEHAVIOURS) do if r.behaviour == b then index = i + 1 end end
        local changed, new = ui.dropdown('behaviour' .. c.id, col(3), cy, G.DD_W, opts, index,
            {height = G.CTRL_H, tooltip = 'What this hero does while you play another one'})
        if changed then
            r.behaviour = new > 1 and BEHAVIOURS[new - 1] or nil
            store:changed()
        end
        if ui.button('tactics' .. c.id, col(4), cy, G.BTN_W, G.CTRL_H, win.tactics == c.id and 'Close' or 'Tactics',
            {tooltip = 'How this hero fights and the combat arts and spells they use on their own'}) then
            if win.tactics == c.id then win.tactics = nil else win.tactics = c.id end
        end
        local can_dismiss = companion and not controlled
        if ui.button('dismiss' .. c.id, col(5), cy, G.BTN_W, G.CTRL_H, 'Dismiss', {enabled = can_dismiss,
            tooltip = can_dismiss and 'Leaves the party for good, with what they wear (empty their backpack first)'
                or 'Play another hero to dismiss this one'}) then
            dismiss(c)
        end
    end

    local USE_LABEL = {target = 'on the target', self = 'in a fight, on themselves', heal = 'when someone is hurt', form = 'when a fight starts (and to change back after it)'}

    local STYLES = {'balanced', 'arts', 'weapon', 'ranged'}
    local STYLE_LABEL = {balanced = 'Weapon and combat arts', arts = 'Combat arts only', weapon = 'Weapon first',
        ranged = 'Ranged weapon'}
    local STYLE_TIP = 'How they fight: combat arts and spells as soon as they are ready, the weapon in between (default); '
        .. 'combat arts and spells only, keeping back from the fight in between (a battle mage); or the weapon first, '
        .. 'combat arts now and then; or with the ranged weapon of their weapon slots (bow, crossbow, musket), taking it up '
        .. 'when a fight starts'

    -- The tactics of one hero, under the rest: its combat style on the grid, then its abilities. Returns its height.
    local function tactics_area(c, x, y, w)
        local r0 = record(c.id)
        label('Tactics of ' .. name_of(c), x, y)
        y = y + G.LINE
        label('Fights with', x, y, {color = DIM, size = 12})
        local labels, index = {}, 1
        for i, st in ipairs(STYLES) do
            labels[i] = STYLE_LABEL[st]
            if (r0.style or 'balanced') == st then index = i end
        end
        local schanged, snew = ui.dropdown('style' .. c.id, x + G.FIELD_X, y, G.FIELD_W, labels, index,
            {height = G.CTRL_H, tooltip = STYLE_TIP})
        if schanged then
            r0.style = STYLES[snew] ~= 'balanced' and STYLES[snew] or nil
            store:changed()
        end
        y = y + G.LINE
        label('Abilities', x, y, {color = DIM, size = 12})
        local list = c:abilities() or {}
        for _, k in ipairs(c:combos() or {}) do
            local names = {}
            for _, a in ipairs(k.arts) do names[#names + 1] = ai.ability_info(a).name end
            list[#list + 1] = {id = k.id, level = 0, bonus = 0, combo = 'Combo ' .. (k.slot + 1) .. ': ' .. table.concat(names, ', ')}
        end
        if #list == 0 then
            label('No combat arts or spells learned yet.', x + G.FIELD_X, y, {color = DIM, size = 12})
            return 3 * G.LINE
        end
        local r = record(c.id)
        local row = 0
        for _, a in ipairs(list) do
            local info = a.combo and {name = a.combo} or ai.ability_info(a.id)
            local use = a.combo and 'target' or ai.use_of(a.id)
            local yy = y + row * 22 + 2
            if use then
                local on = r.abilities[tostring(a.id)] ~= false
                local text = a.combo and info.name or ('%s (level %d)'):format(info.name, a.level + a.bonus)
                local changed, checked = ui.checkbox('use' .. c.id .. '_' .. a.id, x + G.FIELD_X, yy, text, on,
                    {tooltip = 'Used ' .. USE_LABEL[use]})
                if changed then
                    -- (not `checked and nil or false`: that is always false)
                    if checked then r.abilities[tostring(a.id)] = nil else r.abilities[tostring(a.id)] = false end
                    store:changed()
                end
            else
                ui.text(('%s: not used by the AI'):format(info.name), x + G.FIELD_X, yy + 2, {color = DIM, size = 12})
            end
            row = row + 1
        end
        return 2 * G.LINE + row * 22 + 6
    end

    local function draw_window()
        if not ui.panel_open('party') then return end
        local heroes = party.heroes()
        local leader = heroes[1]
        local tactics_hero
        for _, h in ipairs(heroes) do if h.id == win.tactics then tactics_hero = h end end
        local tactics_h = tactics_hero and math.min(420, 3 * G.LINE + 16 + (#(tactics_hero:abilities() or {}) + #(tactics_hero:combos() or {})) * 22) or 0
        local h = 40 + #heroes * G.ROW_H + 4 * G.LINE + 16 + tactics_h
        local p = ui.panel('party', 'Party' .. key_hint('window'), 192, 90, WIN_W, h, {})
        if not p.open then return end
        local x, y, w = p.content_x or 0, p.content_y or 0, p.content_w or WIN_W - 20
        local ok, why = party.available()
        if not ok then
            ui.text(why or 'The party works in single player only.', x, y, {color = DIM})
            return
        end
        for i, c in ipairs(heroes) do hero_row(c, x, y + (i - 1) * G.ROW_H, w, leader) end
        local yy = y + #heroes * G.ROW_H + 8
        ui.rect(x, yy - 5, w, 1, 0x806A5A3C)
        local fx, bx, ix = x + G.FIELD_X, x + G.BUTTON_X, x + G.INFO_X
        -- Recruit a new hero of a class.
        local labels = {}
        for i, c in ipairs(CLASS_ORDER) do labels[i] = CLASS_LABEL[c] end
        label('Recruit', x, yy)
        local changed, index = ui.dropdown('class', fx, yy, G.FIELD_W, labels, win.class, {height = G.CTRL_H})
        if changed then win.class = index end
        local full = #party.companions() >= setting('max_companions', 3)
        if ui.button('recruit', bx, yy, G.BUTTON_W, G.CTRL_H, 'Recruit', {enabled = not full,
            tooltip = 'A new hero of this class joins where you stand'}) then
            recruit(CLASS_ORDER[win.class])
        end
        label(('%d of %d companions'):format(#party.companions(), setting('max_companions', 3)), ix, yy, {color = DIM, size = 12})
        -- Bring a hero from a hero file; keep the hero you play for other savegames.
        yy = yy + G.LINE
        if not files.loaded then refresh_files() end
        label('Bring', x, yy)
        if #files.list > 0 then
            local fchanged, findex = ui.dropdown('heroes', fx, yy, G.FIELD_W, files.labels, files.index,
                {height = G.CTRL_H, tooltip = 'Heroes kept from other savegames, and your network characters'})
            if fchanged then files.index = findex end
        else
            label('No kept heroes yet: "Keep" your hero below.', fx, yy, {color = DIM, size = 12})
        end
        if ui.button('bring', bx, yy, G.BUTTON_W, G.CTRL_H, 'Bring', {enabled = not full and #files.list > 0,
            tooltip = 'A copy of this hero joins where you stand, with their level, skills, equipment and backpack'}) then
            bring(files.list[files.index])
        end
        yy = yy + G.LINE
        label('Keep', x, yy)
        if ui.button('keep', fx, yy, G.FIELD_W, G.CTRL_H, 'Keep ' .. name_of(leader) .. ' for other savegames',
            {tooltip = 'Writes the hero you play to a hero file another savegame can bring into its party'}) then
            keep()
        end
        -- The game's own mercenaries.
        yy = yy + G.LINE
        local mercs = party.mercenaries()
        label('Mercenaries', x, yy)
        local MB = {'vanilla', 'assist', 'passive'}
        local ML = {'As the game does', 'Assist (fight the party\'s target)', 'Passive (stay with you)'}
        local mi = 1
        for i, b in ipairs(MB) do if prefs.data.merc_behaviour == b then mi = i end end
        local mchanged, mnew = ui.dropdown('mercs', fx, yy, G.FIELD_W, ML, mi, {height = G.CTRL_H,
            tooltip = 'What the game\'s own mercenaries do (they follow the hero you play). Escorts and quest followers keep their scripts'})
        if mchanged then
            prefs.data.merc_behaviour = MB[mnew]
            prefs:changed()
        end
        label(('%d with the party'):format(#mercs), bx, yy, {color = DIM, size = 12})
        if tactics_hero then
            yy = yy + G.LINE + 8
            ui.rect(x, yy - 5, w, 1, 0x806A5A3C)
            tactics_area(tactics_hero, x, yy, w)
        end
    end

    return {draw_portraits = draw_portraits, draw_window = draw_window}
end

return M
