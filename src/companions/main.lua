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
    local priority
    if r.order then
        priority = {}
        for i, id in ipairs(r.order) do priority[id] = i end
    end
    return {behaviour = r.behaviour, style = r.style, abilities = off, priority = priority, flee = r.flee, reposition = r.reposition}
end

-- The tactics a hero file carries: kept next to the file (per mod, all savegames) when a hero is kept, given back when they are
-- brought again, so a hero keeps their tactics from one session to the next.
local TACTIC_KEYS = {'name', 'behaviour', 'style', 'abilities', 'order', 'flee', 'reposition'}
local function tactics_copy(r)
    local t = {}
    for _, k in ipairs(TACTIC_KEYS) do
        local v = r[k]
        if type(v) == 'table' then
            local c = {}
            for a, b in pairs(v) do c[a] = b end
            v = c
        end
        t[k] = v
    end
    return t
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

-- A name without the padding the hero files and older saves left on it: no NUL characters, no spaces (also the no-break space) or line breaks at
-- either end. (The name plate over the head shows trailing spaces.) Colour codes inside the name stay as they are.
local function clean_name(s)
    local NBSP = '\194\160'     -- UTF-8 of the no-break space
    s = tostring(s or ''):gsub('%z', '')
    while true do
        local before = s
        s = s:gsub('^%s+', ''):gsub('%s+$', '')
        if s:sub(1, 2) == NBSP then s = s:sub(3) end
        if s:sub(-2) == NBSP then s = s:sub(1, -3) end
        if s == before then return s end
    end
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
            local clean = clean_name(r.name)
            if clean ~= r.name then          -- a name saved with trailing spaces
                r.name = clean ~= '' and clean or default_name(c)
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
    r.kept, r.order, r.flee, r.reposition, r.style = nil, nil, nil, nil, nil
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

-- A hero file whose class and name match a hero of the party: the hero MAY have been brought from it already (a warning
-- only; the mod has no way to tell for sure). The companions carry the file's name when brought.
local function may_be_in_party(f)
    if not f or clean_name(f.name) == '' or f.name == 'Anonymous' then return false end
    local want = clean_name(clean_name(f.name):sub(1, 30)):lower()
    for _, h in ipairs(party.heroes()) do
        if h:class() == f.class and name_of(h):lower() == want then return true end
    end
    return false
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
    r.fallen = nil
    r.purse = nil
    r.abilities = {}
    r.kept, r.order, r.flee, r.reposition, r.style = nil, nil, nil, nil, nil
    local file_name = clean_name(f.name)
    r.name = (file_name ~= '' and file_name ~= 'Anonymous') and clean_name(file_name:sub(1, 30)) or default_name(c)
    local kept = prefs.data.kept and prefs.data.kept[f.file]
    if kept then
        -- tactics kept with the hero file (their name too, unless another companion has it)
        for _, k in ipairs(TACTIC_KEYS) do
            if k ~= 'name' then r[k] = kept[k] end
        end
        r.abilities = r.abilities or {}
        r.kept = {level = c:level() or 0}
    end
    store:changed()
    c:set_name(r.name)
    toast(r.name .. ' (' .. (CLASS_LABEL[c:class() or ''] or '?') .. ', level ' .. tostring(c:level()) .. ') joins the party')
    return c
end

-- Everything in kept hero files that is not in the party yet (a file matching class and name of a party hero is left out).
local function bring_all()
    local ok, why = party.available()
    if not ok then return toast(why or 'Not now') end
    refresh_files()
    local n, skipped = 0, 0
    for _, f in ipairs(files.list) do
        if #party.companions() >= setting('max_companions', 3) then break end
        if may_be_in_party(f) then skipped = skipped + 1 elseif bring(f) then n = n + 1 end
    end
    toast(('%d heroes joined%s'):format(n, skipped > 0 and (', %d already in the party'):format(skipped) or ''))
end

-- Keeps a hero for other savegames: a hero file in the mod's heroes folder, with their tactics next to it. The game writes the
-- hero it is played by, so another hero is played for a moment (the leader gets control back). True when written.
local function keep_hero(c, quiet)
    local leader = party.leader()
    if not c or not leader or c:is_dead() then return false end
    local name = name_of(c)
    local switched = c ~= leader
    if switched and not party.control(c) then return false end
    local file, err = party.export_hero((name .. '_' .. (c:class() or 'hero')):gsub('[^%w_%-]', '_'))
    if switched then party.control(leader) end
    if not file then toast('Cannot keep ' .. name .. ': ' .. tostring(err)) return false end
    local r = record(c.id)
    r.kept = {level = c:level() or 0, file = file}
    prefs.data.kept = prefs.data.kept or {}
    prefs.data.kept[file] = tactics_copy(r)
    prefs:changed()
    store:changed()
    if not quiet then toast(name .. ' is kept: another savegame can bring this hero into its party (party window, Bring)') end
    return true
end

local function keep() if keep_hero(party.leader()) then refresh_files() end end

-- Every hero of the party: the ones not kept yet, or all (again, for the level they have now).
local function keep_all(only_new)
    local n = 0
    for _, c in ipairs(party.heroes()) do
        local r = record(c.id)
        if not (only_new and r.kept) and keep_hero(c, true) then n = n + 1 end
    end
    refresh_files()
    toast(('%d heroes kept for other savegames'):format(n))
end

-- "Move to me": a companion who is stuck joins the hero you play at once.
local function move_to_me(c)
    local leader = party.leader()
    if not leader or not c or c == leader then return end
    local heroes = party.heroes()
    local slot = 1
    for i, h in ipairs(heroes) do if h == c then slot = i - 1 end end
    if not ai.move_to_me(c, leader, math.max(1, slot), math.max(1, #heroes - 1), setting('follow', 5) * TILE) then
        toast(name_of(c) .. ' cannot move to you from there')
    end
end
local function move_all_to_me()
    for _, c in ipairs(party.companions()) do move_to_me(c) end
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
        focus = setting('focus', false),
        separate = setting('separate', false),
        spread = setting('spread', 1) * TILE,
        formation = setting('formation', 'none'),
        protect_range = 5 * TILE,
        heal_below = setting('heal_below', 60) / 100,
        buffs = setting('buffs', 'combat'),
        buff_strength = {[2] = setting('buff_2', 50) / 100, [21] = setting('buff_21', 50) / 100,
            [27] = setting('buff_27', 50) / 100, [32] = setting('buff_32', 50) / 100, [37] = setting('buff_37', 50) / 100},
    }
end

-- Gear watchdog (diagnosis): players report companions that suddenly stand there without their worn gear (the backpack and the
-- other weapon slots stay), once with a creature (a goblin) in the weapon slot where the weapon was. The game frees the objects
-- of the lost items and later reuses their ids. This watches every hero once a second and, when worn items vanish or a weapon
-- slot points at a creature, writes what happened shortly before (falls, get-ups, control changes, weapon switches) to the log.
local events = {}   -- the last few things that happened to the party: {clock, text}
local function note(text)
    events[#events + 1] = {clock, text}
    if #events > 14 then table.remove(events, 1) end
end
local gear_seen = {}   -- hero id -> {worn = {slot = item id}, count = n}
ai.note = note
local function recent_events()
    local out = {}
    for _, e in ipairs(events) do out[#out + 1] = string.format('-%.1fs %s', clock - e[1], e[2]) end
    return table.concat(out, '; ')
end
local function watch_gear(c)
    local worn, count = {}, 0
    for _, e in ipairs(c:equipment() or {}) do
        if e.item then worn[e.slot] = e.item.id; count = count + 1 end
    end
    local before = gear_seen[c.id]
    gear_seen[c.id] = {worn = worn, count = count}
    if before and before.count >= 3 and count <= before.count - 3 then
        local gone = {}
        for slot, id in pairs(before.worn) do if worn[slot] ~= id then gone[#gone + 1] = slot .. '=' .. tostring(id) end end
        print(string.format('[companions] GEAR LOST on hero %d (%s): %d worn items -> %d, gone: %s; hp %s, dead %s; events: %s',
            c.id, tostring(c:class()), before.count, count, table.concat(gone, ' '), tostring(c:hp()), tostring(c:is_dead()), recent_events()))
    end
    local ws = c:weapon_slots()
    if ws then
        for i, sl in ipairs(ws.slots) do
            for _, it in ipairs({sl.main or false, sl.off or false}) do
                local o = it and gear.world.object(it.id)
                if o and o.is_creature and o:is_creature() then
                    print(string.format('[companions] WEAPON SLOT %d of hero %d holds a creature (id %d), not a weapon; events: %s', i, c.id, it.id, recent_events()))
                end
            end
        end
    end
end

-- Fallen companions: the game removes a fallen companion (with what they wear and carry) 25 s after they fell. The mod helps
-- them up at the side of a living hero once the fight is over (3 s), or after 12 s at the latest. A failure of one companion's
-- check never stops the others, and the first failure of each fall is written to the log.
local failed = {}   -- companion id -> the failure already logged for this fall
local function revive_fallen(heroes, leader, hardcore)
    if not setting('revive', true) then return end
    -- the anchor: the leader, or a living companion while the leader is down (none: a wiped party stays down)
    local anchor = leader
    if leader:is_dead() then
        anchor = nil
        for i = 2, #heroes do
            if not heroes[i]:is_dead() then anchor = heroes[i] break end
        end
    end
    for i = 2, #heroes do
        local c = heroes[i]
        local ok, err = pcall(function()
            if c:is_dead() and not (c.id >= party.FIRST_ID and (hardcore or record(c.id).fallen)) then
                if not anchor then fallen[c.id] = nil return end
                if not fallen[c.id] then note('hero ' .. c.id .. ' fell') end
                fallen[c.id] = fallen[c.id] or clock
                local x, y, l = anchor:position()
                local near_ok, near = pcall(ai.enemy_near, anchor, setting('engage', 12) * TILE)
                local quiet = near_ok and not near
                local waited = clock - fallen[c.id]
                if quiet and waited > 3 or waited > 12 then
                    local revived, why = c:revive()
                    if revived then
                        note('hero ' .. c.id .. ' got up after ' .. string.format('%.0f', waited) .. ' s')
                        -- a companion told to wait is helped up where they fell
                        if x and (tactics(c.id).behaviour or setting('behaviour', 'aggressive')) ~= 'hold' then c:teleport(x + 60, y + 60, l) end
                        fallen[c.id] = nil
                        failed[c.id] = nil
                        toast(name_of(c) .. ' is back on their feet')
                    elseif failed[c.id] ~= why then
                        failed[c.id] = why
                        print('[companions] cannot help ' .. tostring(c.id) .. ' up after ' .. string.format('%.0f', waited) .. ' s: ' .. tostring(why))
                    end
                end
            else
                fallen[c.id] = nil
                failed[c.id] = nil
            end
        end)
        if not ok and failed[c.id] ~= err then
            failed[c.id] = err
            print('[companions] revive check failed for ' .. tostring(c.id) .. ': ' .. tostring(err))
        end
    end
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
    if setting('war_cry', true) then ai.war_cry_step(heroes) end
    if clock >= (next_think.gear_watch or 0) then
        next_think.gear_watch = clock + 1
        for i = 1, #heroes do
            local ok, err = pcall(watch_gear, heroes[i])
            if not ok and not next_think.gear_watch_err then next_think.gear_watch_err = true; print('[companions] gear watch failed: ' .. tostring(err)) end
        end
    end
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
        -- the fallen companions still get up while the leader is down (the game removes them, with what they carry, 25 s
        -- after they fell, whatever happens to the leader)
        revive_fallen(heroes, leader, hardcore)
        return
    end
    revive_fallen(heroes, leader, hardcore)
    if not setting('ai', true) then return end
    local opts = ai_opts()
    local merc_behaviour = prefs.data.merc_behaviour or 'vanilla'
    if merc_behaviour ~= 'vanilla' and clock >= (next_think.mercs or 0) then
        next_think.mercs = clock + 0.5
        for _, m in ipairs(party.mercenaries()) do ai.think_merc(m, leader, clock, opts, merc_behaviour) end
    end
    -- the formation's roles (combat styles) and its front, once per round
    opts.styles = {}
    for i = 2, #heroes do opts.styles[heroes[i].id] = tactics(heroes[i].id).style or 'balanced' end
    ai.begin_round(leader, opts)
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
    note('control ' .. tostring(type(from) == 'table' and from.id or from) .. ' -> ' .. tostring(type(to) == 'table' and to.id or to))
    ai.reset()
    purses_on_control(from, to)
end))
apply_share()

local window = require('window').new({
    play = play, recruit = recruit, dismiss = dismiss, keep = keep, bring = bring, bring_all = bring_all, keep_hero = keep_hero,
    keep_all = keep_all, move_to_me = move_to_me, move_all_to_me = move_all_to_me, name_of = name_of, record = record,
    may_be_in_party = may_be_in_party, purse_of = purse_of, give_gold = give_gold, take_gold = take_gold, separate = separate,
    setting = setting, store = store, prefs = prefs, files = files, refresh_files = refresh_files,
    NAMES = NAMES, CLASS_LABEL = CLASS_LABEL,
})


-- For the self test: sets a companion's behaviour like the party window ({id = hero id, behaviour = 'hold' | nil}).
gear.on('companions.set', function(v)
    if type(v) == 'table' and v.id then record(v.id).behaviour = v.behaviour; store:changed() end
end)
gear.on('companions.rect', function(out) out.rect = window.rect end)   -- for the self test
gear.on('companions.record', function(out) out.record, out.tactics = record, tactics end)

gear.on('draw', guard('draw', function(state)
    if type(state) ~= 'table' or state.mode ~= 'game' or state.exclusive then return end
    window.draw()
end))

gear.keys.on('next', guard('key', function() cycle(1) end))
gear.keys.on('previous', guard('key', function() cycle(-1) end))
gear.keys.on('window', guard('key', function() window.toggle() end))

-- The controller's mod menu (LT + LB) reaches the same.
if ui.menu_item then
    pcall(ui.menu_item, 'party', 'Party window (recruit, tactics)', function() window.toggle() end)
    pcall(ui.menu_item, 'next', 'Play the next hero', function() cycle(1) end)
    pcall(ui.menu_item, 'previous', 'Play the previous hero', function() cycle(-1) end)
end
