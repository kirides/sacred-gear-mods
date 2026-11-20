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
local function setting(id, fallback)
    local v = gear.settings.get(id)
    if v == nil then return fallback end
    return v
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

---------------------------------------------------------------------------------------------------------------
-- Separate purses (setting). The game has one purse that goes with control (gear.party.control moves all the gold of the
-- hero you leave to the hero you play). With the setting on, the mod keeps the gold of the heroes you do not play in
-- their record (`purse`, per savegame) and puts it back on the hero when you play them. The hero you play holds their
-- gold in the game as always, so the game's merchants, drops and savegames see it. Turning the setting off gives every
-- stored purse to the hero you play: gold never goes missing.
---------------------------------------------------------------------------------------------------------------
local MAX_GOLD = 2147483646

local function separate() return setting('separate_purses', false) == true end

-- The gold of a hero: the game's for the hero you play, the stored purse for the others.
local function purse_of(c)
    local leader = party.leader()
    if leader and c.id == leader.id then return c:gold() or 0 end
    return record(c.id).purse or 0
end

-- All stored purses to the hero you play. Used when the setting is off (also for a savegame saved with it on), when a
-- companion leaves, and by the toggle itself.
local function merge_purses()
    local key = party_key()
    local p = key and store.data.parties[key]
    local leader = party.leader()
    if not (p and p.heroes and leader) then return end
    local sum, any = 0, false
    for _, r in pairs(p.heroes) do
        if r.purse then any = true; sum = sum + r.purse end
    end
    if not any then return end
    local want = math.min(MAX_GOLD, (leader:gold() or 0) + sum)
    local ok = leader:set_gold(want)
    if not ok then return end   -- try again at the next opportunity: the purses stay stored
    for _, r in pairs(p.heroes) do r.purse = nil end
    store:changed()
    if sum > 0 then toast(('%d gold of the other heroes went to %s'):format(sum, leader:name() or 'you')) end
end

-- After gear.party.control(from, to): the game has put the gold of both in `to` and emptied `from`.
local function purses_on_control(from, to)
    if not separate() then return merge_purses() end
    -- A hero who is not played holds no gold in the game (the game emptied them), so what `to` holds now is all that `from`
    -- had: it goes into `from`'s purse, and `to` gets the purse that was stored for them.
    local rt, rf = record(to.id), record(from.id)
    local mine = to:gold() or 0
    local theirs = rt.purse or 0
    if to:set_gold(theirs) then
        rf.purse = ((rf.purse or 0) + mine) > 0 and math.min(MAX_GOLD, (rf.purse or 0) + mine) or nil
        rt.purse = nil
        store:changed()
    end
end

-- Moves gold between the hero you play and another hero. amount: a number or 'all'.
local function give_gold(c, amount)
    local leader = party.leader()
    if not (separate() and leader and c.id ~= leader.id) then return end
    local have = leader:gold() or 0
    local n = amount == 'all' and have or math.min(amount, have)
    local r = record(c.id)
    n = math.min(n, MAX_GOLD - (r.purse or 0))
    if n <= 0 then return end
    if leader:add_gold(-n) then
        r.purse = (r.purse or 0) + n
        store:changed()
    end
end

local function take_gold(c, amount)
    local leader = party.leader()
    if not (separate() and leader and c.id ~= leader.id) then return end
    local r = record(c.id)
    local have = r.purse or 0
    local n = amount == 'all' and have or math.min(amount, have)
    n = math.min(n, MAX_GOLD - (leader:gold() or 0))
    if n <= 0 then return end
    if leader:add_gold(n) then
        r.purse = have - n > 0 and have - n or nil
        store:changed()
    end
end

-- The tactics of a companion for ai.think: behaviour (nil: the default) and abilities switched off (id -> false).
local function tactics(id)
    local r = record(id)
    local off = {}
    for k, v in pairs(r.abilities) do
        if v == false then off[tonumber(k)] = false end
    end
    return {behaviour = r.behaviour, style = r.style, abilities = off}
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
    r.fallen = nil
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
    if setting('prevent_duplicates', false) then
        -- a hero with the same class and name is in the party already (the hero file's name, as the companion is given it)
        local want = (f.name ~= '' and f.name ~= 'Anonymous') and f.name:sub(1, 30) or nil
        for _, h in ipairs(party.heroes()) do
            if want and h:class() == f.class and name_of(h):lower() == want:lower() then
                return toast(want .. ' (' .. (CLASS_LABEL[f.class or ''] or '?') .. ') is in the party already (setting: prevent duplicate recruitments)')
            end
        end
    end
    local c, err = party.recruit_hero(f.file)
    if not c then return toast('Cannot bring ' .. f.name .. ': ' .. tostring(err)) end
    local r = record(c.id)
    r.behaviour = nil
    r.fallen = nil
    r.purse = nil
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
        toast('Dismiss ' .. name_of(c) .. '? Click again: the companion leaves for good, with what they wear.')
        return
    end
    confirm.id = nil
    local name = name_of(c)
    local ok, err = party.dismiss(c)
    if not ok then return toast('Cannot dismiss ' .. name .. ': ' .. tostring(err)) end
    local key = party_key()
    if key and store.data.parties[key] then
        local gone = store.data.parties[key].heroes[tostring(c.id)]
        local leader = party.leader()
        if gone and gone.purse and leader then leader:add_gold(gone.purse) end   -- their gold stays with the party
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

-- Hardcore companions (setting): a companion that falls is out for good. The record (kept per savegame) says so, so a
-- savegame written after the fall keeps it out, and one written before still has it.
local function mark_fallen(c)
    local r = record(c.id)
    if r.fallen then return end
    r.fallen = true
    store:changed()
    toast(name_of(c) .. ' has fallen for good (hardcore companions)')
end

-- Once the game has removed a fallen hero, its record goes too: the next hero in that place is a new one.
local function forget_fallen()
    local key = party_key()
    local p = key and store.data.parties[key]
    if not (p and p.heroes) then return end
    for sid, r in pairs(p.heroes) do
        local o = r.fallen and gear.world.object(tonumber(sid))
        if r.fallen and not (o and o:is_hero()) then
            local leader = party.leader()
            if r.purse and leader then leader:add_gold(r.purse) end   -- the purse of the fallen stays with the party
            p.heroes[sid] = nil
            store:changed()
        end
    end
end

local function ai_opts()
    return {
        engage = setting('engage', 12) * TILE,
        leash = setting('engage', 12) * TILE * 1.6,
        follow = setting('follow', 5) * TILE,
        teleport = 60 * TILE,
        behaviour = setting('behaviour', 'aggressive'),
        use_abilities = setting('use_abilities', true),
        potion_below = setting('potions', 30) / 100,
        heal_priority = setting('heal_priority', 'hero'),
        heal_below = setting('heal_below', 60) / 100,
        buffs = setting('buffs', 'combat'),
        buff_strength = {[2] = setting('buff_2', 50) / 100, [21] = setting('buff_21', 50) / 100,
            [27] = setting('buff_27', 50) / 100, [32] = setting('buff_32', 50) / 100},
    }
end

gear.on('frame', guard('frame', function(dt)
    clock = clock + (dt or 0)
    if not party.available() then return end
    local heroes = party.heroes()
    if clock >= (next_think.fallen_check or 0) then
        next_think.fallen_check = clock + 1
        forget_fallen()
    end
    if #heroes < 2 and #party.mercenaries() == 0 then return end
    if clock >= next_names then
        next_names = clock + 2
        apply_names()
    end
    local leader = heroes[1]
    local hardcore = setting('hardcore', false)
    if hardcore then
        for i = 1, #heroes do
            local c = heroes[i]
            if c.id >= party.FIRST_ID and c:is_dead() then mark_fallen(c) end
        end
    end
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
            if c:is_dead() and not (c.id >= party.FIRST_ID and (hardcore or record(c.id).fallen)) then
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
    if not separate() then merge_purses() end
end))
gear.on('settings.changed', guard('settings', function()
    apply_share()
    if not separate() then merge_purses() end
end))
gear.on('party.control', guard('control', function(from, to)
    ai.reset()
    purses_on_control(from, to)
end))
apply_share()

local window = require('window').new({
    play = play, recruit = recruit, dismiss = dismiss, keep = keep, bring = bring, name_of = name_of, record = record,
    purse_of = purse_of, give_gold = give_gold, take_gold = take_gold, separate = separate,
    setting = setting, store = store, prefs = prefs, files = files, refresh_files = refresh_files,
    NAMES = NAMES, CLASS_LABEL = CLASS_LABEL,
})


gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' or state.mode ~= 'game' or state.exclusive then return end
    window.draw_portraits()
    window.draw_window()
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
