-- Companions: a party of heroes in single player, Dragon Age style.
--
-- A companion is a real hero of the player (gear.party: the hero ids 3..16, as the heroes of a network game): its own
-- backpack, equipment, attributes, skills, combat arts, spells and experience, saved with the savegame. The player
-- plays one hero at a time: a click on a companion's portrait (top right, under the game's own), the 'next' and
-- 'previous' keys (PageDown / PageUp), or the controller's mod menu (LT + LB) switch. Camera, HUD, windows, mouse, keys and pad then serve
-- that hero; the gold goes with control, the mercenaries follow it.
--
-- The others follow and fight on their own (ai.lua): weapon attacks, combat arts and spells on the target as soon as
-- they have regenerated, auras and buffs once a fight starts, healing when someone is hurt. Each companion has a
-- behaviour (aggressive, defensive, passive) and a list of abilities it may use (party window, Home: tactics).
--
-- Names: the game names companions "playername3"; the mod gives them names (one per class, the party window cycles
-- through more) and sets them again after every load, kept per main hero in companions.json.

local ai = require('ai')
local ui = gear.ui
local party = gear.party
local TILE = gear.world.TILE
local cfg = gear.config
local guard = gear.guard
ai.debug = cfg.debug

local CLASS_ORDER = {'seraphim', 'gladiator', 'battlemage', 'darkelf', 'woodelf', 'vampiress', 'dwarf', 'daemon'}
local CLASS_LABEL = {seraphim = 'Seraphim', gladiator = 'Gladiator', battlemage = 'Battle Mage', darkelf = 'Dark Elf',
    woodelf = 'Wood Elf', vampiress = 'Vampiress', dwarf = 'Dwarf', daemon = 'Daemon'}
local NAMES = {
    seraphim = {'Aurelia', 'Seraphine', 'Lumina', 'Celestine', 'Ariel'},
    gladiator = {'Cassian', 'Brutus', 'Varro', 'Marcus', 'Tiberius'},
    battlemage = {'Aldric', 'Theron', 'Malachai', 'Ivo', 'Corvin'},
    darkelf = {'Vael', 'Shaedra', 'Ilvar', 'Nyx', 'Drizan'},
    woodelf = {'Elowen', 'Sylva', 'Faelin', 'Liri', 'Thalia'},
    vampiress = {'Morgana', 'Selene', 'Carmilla', 'Lilith', 'Nerys'},
    dwarf = {'Borin', 'Hilda', 'Thrain', 'Gunnar', 'Brokk'},
    daemon = {'Azra', 'Kezia', 'Nahema', 'Vex', 'Ishtar'},
}
local BEHAVIOURS = {'aggressive', 'defensive', 'passive'}
local BEHAVIOUR_LABEL = {aggressive = 'Aggressive', defensive = 'Defensive', passive = 'Passive', default = 'Default'}

local DIM, ACCENT, GOOD, BAD = 0xFFB0A890, 0xFFE8C878, 0xFF60C060, 0xFFC04040

local function setting(id, fallback)
    local v = gear.settings.get(id)
    if v == nil then return fallback end
    return v
end

local function key_hint(id)
    local k = gear.keys.label(id)
    return k ~= '' and (' (' .. k .. ')') or ''
end

local function toast(text) if gear.toast then gear.toast.show('Companions', text) else print(text) end end

---------------------------------------------------------------------------------------------------------------
-- Stored per main hero: names, behaviour and the abilities switched off, by companion id.
---------------------------------------------------------------------------------------------------------------
-- The party belongs to the savegame: kept per savegame (gear.store.game; an older Gear keeps one file for all of them). The file
-- from before is taken by the first savegame that is loaded. How the game's mercenaries behave is the player's own choice and stays
-- in one file for all games.
local store = (gear.store.game or gear.store.file)('companions.json', {parties = {}}, {every = 10, migrate = true})
local prefs = gear.store.file('companions_prefs.json', {}, {every = 10})
if prefs.data.merc_behaviour == nil then
    local old = gear.store.load('companions.json', {})
    if old.merc_behaviour then prefs.data.merc_behaviour = old.merc_behaviour; prefs:changed() end
end

local function party_key()
    local main = gear.world.object(1)
    if not main or not main:is_hero() then return nil end
    return (main:name() or '?') .. '|' .. (main:class() or '?')
end

local function record(id)
    local key = party_key()
    if not key then return {abilities = {}} end
    local parties = store.data.parties
    parties[key] = parties[key] or {heroes = {}}
    local heroes = parties[key].heroes
    local r = heroes[tostring(id)]
    if not r then
        r = {abilities = {}}
        heroes[tostring(id)] = r
        store:changed()
    end
    r.abilities = r.abilities or {}
    return r
end

-- The tactics of a companion for ai.think: behaviour (nil: the default) and abilities switched off (id -> false).
local function tactics(id)
    local r = record(id)
    local off = {}
    for k, v in pairs(r.abilities) do
        if v == false then off[tonumber(k)] = false end
    end
    return {behaviour = r.behaviour, abilities = off}
end

local function default_name(c)
    local class = c:class() or 'darkelf'
    local list = NAMES[class] or {'Companion'}
    -- the first name of the class no other companion has
    local used = {}
    for _, h in ipairs(party.heroes()) do
        if h ~= c then used[record(h.id).name or ''] = true end
    end
    for _, n in ipairs(list) do
        if not used[n] then return n end
    end
    return list[1]
end

local function name_of(c)
    if c.id == 1 then return c:name() or 'Hero' end
    return record(c.id).name or default_name(c)
end

-- The game forgets a companion's name on every load: give it again whenever it differs.
local function apply_names()
    for _, c in ipairs(party.heroes()) do
        if c.id >= party.FIRST_ID then
            local r = record(c.id)
            if not r.name then
                r.name = default_name(c)
                store:changed()
            end
            if c:name() ~= r.name then c:set_name(r.name) end
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Switching
---------------------------------------------------------------------------------------------------------------
local function play(c)
    if not c or c:is_dead() then return false end
    local ok, err = party.control(c)
    if not ok then toast('Cannot play ' .. name_of(c) .. ': ' .. tostring(err)) end
    return ok
end

local function cycle(step)
    local heroes = party.heroes()
    if #heroes < 2 then return end
    -- heroes() puts the controlled one first; walk in id order from it
    table.sort(heroes, function(a, b) return a.id < b.id end)
    local current = party.leader()
    local at = 1
    for i, h in ipairs(heroes) do if h == current then at = i end end
    for k = 1, #heroes - 1 do
        local c = heroes[(at - 1 + k * step) % #heroes + 1]
        if not c:is_dead() then return play(c) end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Recruiting and dismissing
---------------------------------------------------------------------------------------------------------------
local function recruit(class)
    local ok, why = party.available()
    if not ok then return toast(why or 'Not now') end
    if #party.companions() >= setting('max_companions', 3) then
        return toast('The party is full (setting: companions at most)')
    end
    local leader = party.leader()
    local exp = 0
    local start = setting('start_level', 'leader')
    if start == 'leader' then exp = leader:experience() or 0 elseif start == 'half' then exp = math.floor((leader:experience() or 0) / 2) end
    local c, err = party.recruit(class, {experience = exp})
    if not c then return toast('Cannot recruit: ' .. tostring(err)) end
    local r = record(c.id)
    r.name = nil
    r.behaviour = nil
    r.abilities = {}
    r.name = default_name(c)
    store:changed()
    c:set_name(r.name)
    toast(r.name .. ' (' .. CLASS_LABEL[class] .. ', level ' .. tostring(c:level()) .. ') joins the party')
    return c
end

-- Heroes from elsewhere: the network game's characters (Save\HeroNN.pax) and heroes kept from other savegames.
local files = {list = {}, labels = {}, index = 1, loaded = false}

local function refresh_files()
    files.list = party.hero_files() or {}
    files.labels = {}
    for i, f in ipairs(files.list) do
        files.labels[i] = ('%s (%s, level %d)%s'):format(f.name ~= '' and f.name or '?', CLASS_LABEL[f.class or ''] or '?', f.level,
            f.file:sub(1, 5) == 'save:' and ', network' or '')
    end
    if files.index > #files.list then files.index = 1 end
    files.loaded = true
end

local function bring(f)
    local ok, why = party.available()
    if not ok then return toast(why or 'Not now') end
    if #party.companions() >= setting('max_companions', 3) then
        return toast('The party is full (setting: companions at most)')
    end
    local c, err = party.recruit_hero(f.file)
    if not c then return toast('Cannot bring ' .. f.name .. ': ' .. tostring(err)) end
    local r = record(c.id)
    r.behaviour = nil
    r.abilities = {}
    r.name = (f.name ~= '' and f.name ~= 'Anonymous') and f.name:sub(1, 30) or default_name(c)
    store:changed()
    c:set_name(r.name)
    toast(r.name .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level()) .. ') joins the party')
    return c
end

-- Keeps the hero you play for other savegames: a hero file in the mod's heroes folder.
local function keep()
    local c = party.leader()
    if not c then return end
    local name = name_of(c)
    local file, err = party.export_hero((name .. '_' .. (c:class() or 'hero')):gsub('[^%w_%-]', '_'))
    if not file then return toast('Cannot keep ' .. name .. ': ' .. tostring(err)) end
    toast(name .. ' is kept: another savegame can bring this hero into its party (party window, Bring)')
    refresh_files()
end

local confirm = {id = nil, at = 0}   -- a dismiss waits for a second click
local function dismiss(c)
    local now = os.clock()
    if confirm.id ~= c.id or now - confirm.at > 4 then
        confirm.id, confirm.at = c.id, now
        toast('Dismiss ' .. name_of(c) .. '? Click again: the companion leaves for good, with what it wears.')
        return
    end
    confirm.id = nil
    local name = name_of(c)
    local ok, err = party.dismiss(c)
    if not ok then return toast('Cannot dismiss ' .. name .. ': ' .. tostring(err)) end
    local key = party_key()
    if key and store.data.parties[key] then
        store.data.parties[key].heroes[tostring(c.id)] = nil
        store:changed()
    end
    ai.reset()
    toast(name .. ' left the party')
end

---------------------------------------------------------------------------------------------------------------
-- The party's brain: experience sharing, AI, a fallen leader.
---------------------------------------------------------------------------------------------------------------
local function apply_share()
    party.share_experience(setting('share_xp', 100) / 100, setting('share_radius', 40) * TILE)
end

local clock, next_think, next_names = 0, {}, 0
local fallen = {}   -- companion id -> when it fell

local function ai_opts()
    return {
        engage = setting('engage', 12) * TILE,
        leash = setting('engage', 12) * TILE * 1.6,
        follow = setting('follow', 5) * TILE,
        teleport = 60 * TILE,
        behaviour = setting('behaviour', 'aggressive'),
        use_abilities = setting('use_abilities', true),
        potion_below = setting('potions', 30) / 100,
    }
end

gear.on('frame', guard('frame', function(dt)
    clock = clock + (dt or 0)
    if not party.available() then return end
    local heroes = party.heroes()
    if #heroes < 2 and #party.mercenaries() == 0 then return end
    if clock >= next_names then
        next_names = clock + 2
        apply_names()
    end
    local leader = heroes[1]
    if leader:is_dead() then
        if setting('switch_on_death', true) then
            for i = 2, #heroes do
                if not heroes[i]:is_dead() and play(heroes[i]) then
                    toast(name_of(heroes[i]) .. ' takes the lead')
                    break
                end
            end
        end
        return
    end
    -- Fallen companions: the game removes a fallen companion (with what it carries) about 25 s after it fell, so the
    -- mod helps it up at the leader's side once the fight is over, or after 12 s at the latest.
    if setting('revive', true) then
        for i = 2, #heroes do
            local c = heroes[i]
            if c:is_dead() then
                fallen[c.id] = fallen[c.id] or clock
                local x, y, l = leader:position()
                local quiet = not ai.enemy_near(leader, setting('engage', 12) * TILE)
                if x and (quiet and clock - fallen[c.id] > 3 or clock - fallen[c.id] > 12) then
                    if c:revive() then
                        c:teleport(x + 60, y + 60, l)
                        fallen[c.id] = nil
                        toast(name_of(c) .. ' is back on their feet')
                    end
                end
            else
                fallen[c.id] = nil
            end
        end
    end
    if not setting('ai', true) then return end
    local opts = ai_opts()
    local merc_behaviour = prefs.data.merc_behaviour or 'vanilla'
    if merc_behaviour ~= 'vanilla' and clock >= (next_think.mercs or 0) then
        next_think.mercs = clock + 0.5
        for _, m in ipairs(party.mercenaries()) do ai.think_merc(m, leader, clock, opts, merc_behaviour) end
    end
    local step = cfg.think or 0.25
    for i = 2, #heroes do
        local c = heroes[i]
        if not next_think[c.id] then next_think[c.id] = clock + (i - 1) * step / #heroes end
        if clock >= next_think[c.id] then
            next_think[c.id] = clock + step
            ai.think(c, leader, i - 1, #heroes - 1, clock, heroes, opts, tactics(c.id))
        end
    end
end))

gear.on('session.start', guard('session', function()
    next_think, next_names = {}, 0
    files.loaded = false
    ai.reset()
    apply_share()
end))
gear.on('settings.changed', guard('settings', function() apply_share() end))
gear.on('party.control', guard('control', function() ai.reset() end))
apply_share()

---------------------------------------------------------------------------------------------------------------
-- Portraits: the companions under the game's own portraits. A click plays that hero; the controller's D-pad stops on
-- them like on any window button.
---------------------------------------------------------------------------------------------------------------
local PW, PH, ROW = 62, 62, 76

local function bar(x, y, w, h, frac, color)
    ui.rect(x, y, w, h, 0xC0000000)
    ui.rect(x + 1, y + 1, math.max(0, (w - 2) * math.min(1, math.max(0, frac))), h - 2, color)
end

local function draw_portrait(c, x, y)
    local dead = c:is_dead()
    local r = ui.region('portrait' .. c.id, x, y, PW, ROW - 6, {
        tooltip = name_of(c) .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level())
            .. ')\n' .. (dead and 'Fallen' or ('Click to play' .. key_hint('next')))})
    ui.rect(x, y, PW, PH, r.hover and 0xD0302818 or 0xB0000000)
    local img = c:portrait()
    if img then ui.image(img, x + 3, y + 3, PW - 6, PH - 6, {fit = 'contain', color = dead and 0xFF505050 or 0xFFFFFFFF}) end
    ui.frame(x, y, PW, PH, r.hover and ACCENT or 0xFF6A5A3C, 1)
    local hp, max = c:hp() or 0, c:max_hp() or 1
    bar(x, y + PH + 1, PW, 6, hp / math.max(1, max), dead and BAD or (hp / max < 0.3 and 0xFFE0A030 or GOOD))
    ui.text(tostring(c:level() or ''), x + 3, y + 2, {color = ACCENT, size = 11})
    if r.clicked and not dead then play(c) end
end

local function draw_portraits()
    if not setting('portraits', true) or not party.available() then return end
    local list = party.companions()
    if #list == 0 then return end
    local p = ui.panel('portraits', 'Companions', cfg.portraits_x or 948, cfg.portraits_y or 300, PW + 4, #list * ROW + 4, {bare = true})
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
    if ui.button('tactics' .. c.id, bx, y + 8, 64, 22, 'Tactics', {tooltip = 'The combat arts and spells this hero uses on its own'}) then
        win.tactics = win.tactics == c.id and nil or c.id
    end
    bx = bx + 70
    if c.id >= party.FIRST_ID and not controlled then
        if ui.button('dismiss' .. c.id, bx, y + 8, 64, 22, 'Dismiss', {tooltip = 'Leaves the party for good, with what it wears (empty its backpack first)'}) then
            dismiss(c)
        end
    end
end

local USE_LABEL = {target = 'on the target', self = 'in a fight, on itself', heal = 'when someone is hurt'}

local function tactics_area(c, x, y, w)
    ui.text('Tactics of ' .. name_of(c) .. ': the abilities it uses on its own', x, y, {color = ACCENT})
    local list = c:abilities() or {}
    for _, k in ipairs(c:combos() or {}) do
        local names = {}
        for _, a in ipairs(k.arts) do names[#names + 1] = ai.ability_info(a).name end
        list[#list + 1] = {id = k.id, level = 0, bonus = 0, combo = 'Combo ' .. (k.slot + 1) .. ': ' .. table.concat(names, ', ')}
    end
    if #list == 0 then
        ui.text('It knows no combat arts or spells yet.', x, y + 22, {color = DIM})
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
            tooltip = 'A copy of this hero joins where you stand, with its level, skills, equipment and backpack'}) then
            bring(files.list[files.index])
        end
    else
        ui.text('No kept heroes yet: play a savegame, then "Keep" its hero here.', x + 70, yy + 34, {color = DIM, size = 12})
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

gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' or state.mode ~= 'game' or state.exclusive then return end
    draw_portraits()
    draw_window()
end))

ui.show_panel('party', false)
gear.keys.on('next', guard('key', function() cycle(1) end))
gear.keys.on('previous', guard('key', function() cycle(-1) end))
gear.keys.on('window', guard('key', function() ui.toggle_panel('party') end))

-- The controller's mod menu (LT + LB) reaches the same.
if ui.menu_item then
    pcall(ui.menu_item, 'party', 'Party window (recruit, tactics)', function() ui.toggle_panel('party') end)
    pcall(ui.menu_item, 'next', 'Play the next hero', function() cycle(1) end)
    pcall(ui.menu_item, 'previous', 'Play the previous hero', function() cycle(-1) end)
end
