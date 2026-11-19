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
    local function health_bar(x, y, frac, dead)
        frac = math.min(1, math.max(0, frac))
        if not ui.image(IMG_BAR, x, y, BW, BH) then
            return bar(x, y, BW, BH - 2, frac, dead and BAD or GOOD)
        end
        if dead then return end
        local ix, iw = x + 1, BW - 2
        ui.image(IMG_BAR_FILL, ix, y + 1, iw, BH - 2, {color = frac < 0.3 and 0xFFFFC060 or 0xFFFFFFFF})
        local lost = iw * (1 - frac)
        if lost > 0.5 then ui.rect(ix + iw - lost, y + 1, lost, BH - 2, 0xD8101010) end
    end

    local function draw_portrait(c, x, y)
        local dead = c:is_dead()
        local r = ui.region('portrait' .. c.id, x, y + 6, RW - 8, BY + BH - 6, {
            tooltip = name_of(c) .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level())
                .. ')\n' .. (dead and 'Fallen' or ('Click to play' .. key_hint('next')))})
        -- as the game draws it: the ring (its hole is tinted glass), the portrait over it
        local ring = dead and IMG_RING_GREY or (r.hover and IMG_RING_GREY or IMG_RING)
        local tint = dead and 0xFF808080 or (r.hover and 0xFFFFD27A or 0xFFFFFFFF)
        local drawn = ui.image(ring, x, y, RW, RH, {color = tint})
        local img = c:portrait()
        if img then
            ui.image(img, x + PX, y + PY, PIW, PIH, {color = dead and 0xFF606060 or 0xFFFFFFFF})
        end
        if not drawn then ui.frame(x + 8, y + 12, RW - 18, RH - 18, r.hover and ACCENT or 0xFF6A5A3C, 1) end
        local hp, max = c:hp() or 0, c:max_hp() or 1
        health_bar(x + BX, y + BY, hp / math.max(1, max), dead)
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
    local WIN_W = 600

    local function hero_row(c, x, y, w, leader)
        local controlled = c == leader
        local dead = c:is_dead()
        local img = c:portrait()
        if img then ui.image(img, x, y, 40, 40, {fit = 'contain'}) end
        ui.frame(x, y, 40, 40, controlled and ACCENT or 0xFF6A5A3C, 1)
        ui.text(name_of(c), x + 48, y, {color = controlled and ACCENT or 0xFFFFFFFF, bold = true})
        ui.text(('%s, level %s%s'):format(CLASS_LABEL[c:class() or ''] or '?', tostring(c:level()), dead and ', fallen' or ''),
            x + 48, y + 16, {color = DIM, size = 12})
        bar(x + 48, y + 33, 130, 6, (c:hp() or 0) / math.max(1, c:max_hp() or 1), dead and BAD or GOOD)
        local bx = x + 190
        if controlled then
            ui.text('You play this hero', bx, y + 12, {color = DIM, size = 12})
        elseif ui.button('play' .. c.id, bx, y + 8, 64, 22, 'Play', {enabled = not dead}) then
            play(c)
        end
        bx = bx + 70
        if c.id >= party.FIRST_ID then
            if ui.button('name' .. c.id, bx, y + 8, 64, 22, 'Name', {tooltip = 'Another name for this companion'}) then
                local list = NAMES[c:class() or ''] or {'Companion'}
                local cur, at = name_of(c), 0
                for i, n in ipairs(list) do if n == cur then at = i end end
                local r = record(c.id)
                r.name = list[at % #list + 1]
                store:changed()
                c:set_name(r.name)
            end
        end
        bx = bx + 70
        local r = record(c.id)
        local opts = {'Default'}
        for _, b in ipairs(BEHAVIOURS) do opts[#opts + 1] = BEHAVIOUR_LABEL[b] end
        local index = 1
        for i, b in ipairs(BEHAVIOURS) do if r.behaviour == b then index = i + 1 end end
        local changed, new = ui.dropdown('behaviour' .. c.id, bx, y + 8, 110, opts, index,
            {tooltip = 'What this hero does while you play another one'})
        if changed then
            r.behaviour = new > 1 and BEHAVIOURS[new - 1] or nil
            store:changed()
        end
        bx = bx + 116
        if ui.button('tactics' .. c.id, bx, y + 8, 64, 22, 'Tactics', {tooltip = 'The combat arts and spells this hero uses on their own'}) then
            win.tactics = win.tactics == c.id and nil or c.id
        end
        bx = bx + 70
        if c.id >= party.FIRST_ID and not controlled then
            if ui.button('dismiss' .. c.id, bx, y + 8, 64, 22, 'Dismiss', {tooltip = 'Leaves the party for good, with what they wear (empty their backpack first)'}) then
                dismiss(c)
            end
        end
    end

    local USE_LABEL = {target = 'on the target', self = 'in a fight, on themselves', heal = 'when someone is hurt', form = 'when a fight starts (and to change back after it)'}

    local function tactics_area(c, x, y, w)
        ui.text('Tactics of ' .. name_of(c) .. ': the abilities they use on their own', x, y, {color = ACCENT})
        local list = c:abilities() or {}
        for _, k in ipairs(c:combos() or {}) do
            local names = {}
            for _, a in ipairs(k.arts) do names[#names + 1] = ai.ability_info(a).name end
            list[#list + 1] = {id = k.id, level = 0, bonus = 0, combo = 'Combo ' .. (k.slot + 1) .. ': ' .. table.concat(names, ', ')}
        end
        if #list == 0 then
            ui.text('No combat arts or spells learned yet.', x, y + 22, {color = DIM})
            return 44
        end
        local r = record(c.id)
        local row = 0
        for _, a in ipairs(list) do
            local info = a.combo and {name = a.combo} or ai.ability_info(a.id)
            local use = a.combo and 'target' or ai.use_of(a.id)
            local yy = y + 22 + row * 22
            local col = (row % 2 == 0) and 0 or 0
            if use then
                local on = r.abilities[tostring(a.id)] ~= false
                local label = a.combo and info.name or ('%s (level %d)'):format(info.name, a.level + a.bonus)
                local changed, checked = ui.checkbox('use' .. c.id .. '_' .. a.id, x + col, yy, label, on,
                    {tooltip = 'Used ' .. USE_LABEL[use]})
                if changed then
                    r.abilities[tostring(a.id)] = checked and nil or false
                    store:changed()
                end
            else
                ui.text(('%s: not used by the AI'):format(info.name), x + col, yy + 2, {color = DIM, size = 12})
            end
            row = row + 1
        end
        return 22 + row * 22 + 4
    end

    local function draw_window()
        if not ui.panel_open('party') then return end
        local heroes = party.heroes()
        local leader = heroes[1]
        local tactics_hero
        for _, h in ipairs(heroes) do if h.id == win.tactics then tactics_hero = h end end
        local tactics_h = tactics_hero and math.min(360, 44 + (#(tactics_hero:abilities() or {}) + #(tactics_hero:combos() or {})) * 22) or 0
        local h = 40 + #heroes * 52 + 160 + tactics_h
        local p = ui.panel('party', 'Party' .. key_hint('window'), 212, 90, WIN_W, h, {})
        if not p.open then return end
        local x, y, w = p.content_x or 0, p.content_y or 0, p.content_w or WIN_W - 20
        local ok, why = party.available()
        if not ok then
            ui.text(why or 'The party works in single player only.', x, y, {color = DIM})
            return
        end
        for i, c in ipairs(heroes) do hero_row(c, x, y + (i - 1) * 52, w, leader) end
        local yy = y + #heroes * 52 + 6
        ui.rect(x, yy - 4, w, 1, 0x806A5A3C)
        local labels = {}
        for i, c in ipairs(CLASS_ORDER) do labels[i] = CLASS_LABEL[c] end
        ui.text('Recruit', x, yy + 4, {color = ACCENT})
        local changed, index = ui.dropdown('class', x + 70, yy, 140, labels, win.class)
        if changed then win.class = index end
        local full = #party.companions() >= setting('max_companions', 3)
        if ui.button('recruit', x + 220, yy, 90, 22, 'Recruit', {enabled = not full,
            tooltip = 'A new hero of this class joins where you stand'}) then
            recruit(CLASS_ORDER[win.class])
        end
        ui.text(('%d of %d companions'):format(#party.companions(), setting('max_companions', 3)), x + 320, yy + 4, {color = DIM, size = 12})
        -- Bring a hero from a hero file; keep the hero you play for other savegames.
        if not files.loaded then refresh_files() end
        ui.text('Bring', x, yy + 34, {color = ACCENT})
        if #files.list > 0 then
            local fchanged, findex = ui.dropdown('heroes', x + 70, yy + 30, 300, files.labels, files.index,
                {tooltip = 'Heroes kept from other savegames, and your network characters'})
            if fchanged then files.index = findex end
            if ui.button('bring', x + 380, yy + 30, 90, 22, 'Bring', {enabled = not full,
                tooltip = 'A copy of this hero joins where you stand, with their level, skills, equipment and backpack'}) then
                bring(files.list[files.index])
            end
        else
            ui.text('No kept heroes yet: play a savegame, then "Keep" your hero here.', x + 70, yy + 34, {color = DIM, size = 12})
        end
        if ui.button('keep', x + 70, yy + 60, 300, 22, 'Keep ' .. name_of(leader) .. ' for other savegames',
            {tooltip = 'Writes the hero you play to a hero file another savegame can bring into its party'}) then
            keep()
        end
        -- The game's own mercenaries.
        local mercs = party.mercenaries()
        ui.text('Mercenaries', x, yy + 94, {color = ACCENT})
        local MB = {'vanilla', 'assist', 'passive'}
        local ML = {'As the game does', 'Assist (fight the party\'s target)', 'Passive (stay with you)'}
        local mi = 1
        for i, b in ipairs(MB) do if prefs.data.merc_behaviour == b then mi = i end end
        local mchanged, mnew = ui.dropdown('mercs', x + 100, yy + 90, 230, ML, mi,
            {tooltip = 'What the game\'s own mercenaries do (they follow the hero you play). Escorts and quest followers keep their scripts'})
        if mchanged then
            prefs.data.merc_behaviour = MB[mnew]
            prefs:changed()
        end
        ui.text(('%d with the party'):format(#mercs), x + 340, yy + 94, {color = DIM, size = 12})
        if tactics_hero then
            tactics_area(tactics_hero, x, yy + 126, w)
        end
    end

    return {draw_portraits = draw_portraits, draw_window = draw_window}
end

return M
