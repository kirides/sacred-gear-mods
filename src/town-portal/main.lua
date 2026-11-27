-- Town Portal (Sacred Gear 0.16.0 or later). The Town Portal Potion is an item type of its own (gear.inv.define_type, a copy of one of the game's potions:
-- the game's potions are logbook entries and cannot be used up). Using it (`item.use` when it is drunk, or the key) saves where the hero stands and opens a window that lists the game's teleport portals (the ones the hero has
-- found: gear.world.portals) in the manner of the game's own "Transferportal" list. A pick teleports the hero there, uses the potion up and puts a
-- portal (an NPC of the mod, gear.npc) near the arrival; talking to the portal and stepping through takes the hero back to the saved spot and removes
-- the portal. The saved spot is kept with the savegame (gear.store.game); the portal is a creature of the savegame (gear.npc keeps it).
local S = gear.settings
local spots = require('spots')

local SCROLL_BASE = 5144            -- a potion of the game (blue-green bottle): the model and size of the new item
local SCROLL_TYPE = 16000           -- the mod's item type (gear.inv.TYPE_FIRST .. TYPE_LAST)
local KIND = 'town-portal.gate'
local ANIM_WAIT = 1.0               -- seconds the game needs to put the hero in the new place before the portal is made

local text_name = gear.text.key('town-portal.scroll', {en = 'Town Portal Potion', de = 'Stadtportal-Trank'})
local texts = {}
-- A text of the mod in the game's language (en / de; others get en).
local function L(key, en, de)
    local t = texts[key]
    if not t then
        local id = gear.text.key('town-portal.' .. key, {en = en, de = de})
        t = id or false
        texts[key] = t
    end
    return t and gear.text.get(t) or en
end

-- The game's type table exists only once the game runs: the type is defined as soon as it does, every session (a savegame keeps the id).
local type_defined = false
local function ensure_type()
    if type_defined then return end
    local ok, err = gear.inv.define_type(SCROLL_TYPE, SCROLL_BASE, text_name)
    if ok then
        type_defined = true
    elseif not tostring(err):find('type table is not there', 1, true) then
        type_defined = true     -- the record is taken by the game: no use trying again
        gear.log('town-portal: could not define the potion type: ' .. tostring(err))
    end
end
ensure_type()
gear.every(0.5, gear.guard('type', ensure_type))
gear.on('session.start', ensure_type)

-- What the mod keeps per savegame: the spot the hero left (nil: no portal is open) and where the portal stands.
local store = gear.store.game('state.json', {}, {every = 10, check = function(d)
    if type(d) ~= 'table' then return {} end
    return d
end})

-- Points of the player's own (the window adds and removes them; all games share them) and of an optional custom_teleports.lua in the mod's folder:
-- `return {{name = 'My tower', x = 150000, y = 120000, layer = 0}, ...}` (a name may be {en = ..., de = ...}); those cannot be removed in the window.
local points = gear.store.file('custom_points.json', {list = {}}, {every = 5, check = function(d)
    if type(d) ~= 'table' or type(d.list) ~= 'table' then return {list = {}} end
    return d
end})
local MAX_POINTS = 40
local function file_points()
    local ok, list = pcall(require, 'custom_teleports')
    if not ok or type(list) ~= 'table' then
        if not ok and not tostring(list):find("module 'custom_teleports' not found", 1, true) then
            gear.log('town-portal: custom_teleports.lua: ' .. tostring(list))
        end
        return {}
    end
    return list
end

local dialog_open, message = false, ''
local edit_only = false                       -- opened by the key to edit the points: nothing to travel with
local new_name = ''
local test_ignore_combat = false          -- for the self test (the test savegame has wolves about)
local doc

-- Texts ---------------------------------------------------------------------------------------------------------------------------------------------

local spot_text = {}
for i, s in ipairs(spots) do
    local id = gear.text.key('town-portal.spot.' .. s.bit, s.name)
    spot_text[i] = id
end
local function spot_name(i)
    local id = spot_text[i]
    return id and gear.text.get(id) or spots[i].name.en
end

-- Every point of the window: the game's portals (found ones only can be used), then the mod's file, then the player's own.
local function entries()
    local mask = gear.world.portals() or 0
    local out = {}
    for i, sp in ipairs(spots) do
        out[#out + 1] = {name = spot_name(i), x = sp.x, y = sp.y, layer = 0, known = (mask & (1 << sp.bit)) ~= 0}
    end
    for n, p in ipairs(file_points()) do
        if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) then
            local nm = type(p.name) == 'table' and (gear.text.get(gear.text.key('town-portal.file.' .. n, p.name) or 0) or p.name.en) or tostring(p.name or 'Point ' .. n)
            out[#out + 1] = {name = nm, x = p.x, y = p.y, layer = p.layer or 0, known = true, custom = true}
        end
    end
    for n, p in ipairs(points.data.list) do
        out[#out + 1] = {name = p.name, x = p.x, y = p.y, layer = p.layer or 0, known = true, custom = true, own = n}
    end
    return out
end

local function title_text() return gear.text.get(802) or 'Transfer portal' end

local function say(...)
    gear.toast.show(L('title', 'Town Portal', 'Stadtportal'), ...)
end

-- The hero and the potion ---------------------------------------------------------------------------------------------------------------------------

local function hero() return gear.world.hero() end

local function find_scroll()
    local c = gear.inv.container('backpack')
    if not c then return nil, nil end
    for _, it in ipairs(c:items()) do
        if it.type == SCROLL_TYPE then return it.id, c end
    end
    return nil, c
end

local function portal_creature()
    local list = gear.npc.list(KIND)
    return list[1] and list[1].creature or nil
end

local function can_read()
    if not gear.world.can_change() then return false, L('sp', 'The potion works in single player games only.', 'Der Trank wirkt nur im Einzelspieler.') end
    local h = hero()
    if not h then return false, L('nohero', 'There is no hero.', 'Es gibt keinen Helden.') end
    if store.data.home then return false, L('open', 'A portal is open already: step through it to come back first.', 'Ein Portal ist schon offen: geh erst hindurch, um zurückzukehren.') end
    if S.get('block_in_combat') and not test_ignore_combat and h:in_combat() then return false, L('enemy', 'Enemies are near: the potion does nothing.', 'Feinde in der Nähe: der Trank wirkt nicht.') end
    return true
end

-- Teleport list window ---------------------------------------------------------------------------------------------------------------------------------

local function snapshot()
    local m = {open = dialog_open, title = title_text(), msg = message, spots = {}, any = false, cancel = L('cancel', 'Cancel', 'Abbrechen'), nothing = L('nothing', 'You have not found a portal yet.', 'Du hast noch kein Portal gefunden.'),
        new_name = new_name, add = L('add', 'Add this spot', 'Diesen Ort hinzufügen'), placeholder = L('placeholder', 'Name of this spot', 'Name dieses Ortes'),
        edit_only = edit_only, own_title = L('own', 'Your own points', 'Eigene Punkte'), has_own = false}
    local es = entries()
    for i, e in ipairs(es) do
        if e.known then m.any = true end
        m.spots[#m.spots + 1] = {id = 'spot-' .. i, del = 'del-' .. i, name = e.name, locked = not e.known or edit_only, own = e.own ~= nil, sep = e.custom and not es[i - 1].custom or false}
        if e.own then m.has_own = true end
    end
    m.none = not m.any
    return m
end

local function close_dialog()
    dialog_open = false
    message = ''
end

local function travel(i)
    local s = entries()[i]
    if not s or not s.known or edit_only then return end
    local ok, why = can_read()
    if not ok then message = why return end
    local scroll, container = find_scroll()
    if not scroll then message = L('gone', 'The potion is gone from your backpack.', 'Der Trank ist nicht mehr im Rucksack.') return end
    local h = hero()
    local hx, hy, hl = h:position()
    local done, err = h:teleport(s.x, s.y, s.layer or 0)
    if not done then message = L('refused', 'The game refused the teleport: ', 'Das Spiel hat die Teleportation abgelehnt: ') .. tostring(err) return end
    gear.inv.remove(container, scroll)
    store.data.home = {x = hx, y = hy, layer = hl}
    store.data.portal = nil
    store:changed()
    close_dialog()
    gear.task(function()
        gear.wait(ANIM_WAIT)
        local h2 = hero()
        if not h2 then return end
        local ax, ay, al = h2:position()
        local px, py = gear.world.around(ax, ay, 110, 170)
        local c, perr = gear.npc.spawn(KIND, px, py, {layer = al})
        if not c then
            gear.log('town-portal: could not open the portal: ' .. tostring(perr))
            say(L('noportal', 'The portal did not open.', 'Das Portal hat sich nicht geöffnet.'), tostring(perr))
            store.data.home = nil
            store:changed()
            return
        end
        store.data.portal = {x = px, y = py, layer = al}
        store:changed()
        say(L('opens', 'A portal opens.', 'Ein Portal öffnet sich.'), L('opens2', 'Talk to it to step back to where you drank the potion.', 'Sprich es an, um dorthin zurückzukehren, wo du den Trank getrunken hast.'))
    end)
end

local kb = gear.kit.osk and gear.kit.osk{}
local function set_name(t)
    new_name = tostring(t or ''):sub(1, 32)
    if doc then doc.model.new_name = new_name end
end
local function open_osk()
    if kb then kb:toggle{title = L('placeholder', 'Name of this spot', 'Name dieses Ortes'), text = new_name, max = 32, on_change = set_name, get = function() return new_name end} end
end

-- Adds the hero's place as a point of the player's own.
local function add_point()
    local h = hero()
    local name = new_name:gsub('^%s+', ''):gsub('%s+$', '')
    if not h then return end
    if name == '' then message = L('needname', 'Give the spot a name first.', 'Gib dem Ort zuerst einen Namen.') return end
    if #points.data.list >= MAX_POINTS then message = L('full', 'That is enough points.', 'Das sind genug Punkte.') return end
    local x, y, layer = h:position()
    points.data.list[#points.data.list + 1] = {name = name, x = math.floor(x), y = math.floor(y), layer = layer}
    points:changed()
    set_name('')
    message = ''
end

local function load_doc()
    doc = gear.ui.rml.load('ui/portal.rml', {dp = true, model = snapshot(), on_change = function(_, model) new_name = tostring(model.new_name or '') end})
    if not doc then return end
    doc:on('[id^=spot-]', 'click', gear.guard('spot', function(e)
        local i = tonumber(tostring(e.current):match('^spot%-(%d+)$'))
        if i then travel(i) end
    end))
    doc:on('#cancel', 'click', gear.guard('cancel', close_dialog))
    doc:on('[id^=del-]', 'click', gear.guard('del', function(e)
        local i = tonumber(tostring(e.current):match('^del%-(%d+)$'))
        local en = i and entries()[i]
        if en and en.own then table.remove(points.data.list, en.own) points:changed() end
    end))
    doc:on('#add', 'click', gear.guard('add', function() add_point() end))
    if kb then kb:attach(doc, {field = '#name', button = '#kbd-name', open = function() open_osk() end}) end
end

local last = {}
local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    return gear.json.encode(a) == gear.json.encode(b)
end

local function draw()
    if kb then
        if not dialog_open then kb:close() end
        kb:draw()
    end
    if not dialog_open then return end
    if not doc then load_doc() end
    if not doc then return end
    local m = snapshot()
    for k, v in pairs(m) do
        if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
    end
    doc:draw({layer = 'hud'})
end

local function open_dialog(edit)
    edit_only = edit == true
    local ok, why = true, nil
    if not edit_only then ok, why = can_read() end
    if not ok then gear.log('town-portal: ' .. why) say(why) return false end
    message = ''
    dialog_open = true
    return true
end

-- Reading the potion -------------------------------------------------------------------------------------------------------------------------------

-- The potion stays in the pack until a portal was picked; the dialog uses it up.
gear.on('item.use', function(e)
    if e.type ~= SCROLL_TYPE then return nil end
    open_dialog()
    return 'keep'
end)

gear.keys.on('read', gear.guard('read', function()
    if dialog_open then return end
    if not find_scroll() then say(L('none', 'You carry no Town Portal Potion.', 'Du trägst keinen Stadtportal-Trank.')) return end
    open_dialog()
end))
gear.keys.on('close', gear.guard('close', close_dialog))
gear.keys.on('points', gear.guard('points', function() if dialog_open then close_dialog() else open_dialog(true) end end))

-- The portal -------------------------------------------------------------------------------------------------------------------------------------

local function step_through(e)
    local home = store.data.home
    local h = hero()
    if not home or not h then return end
    local ok, err = h:teleport(home.x, home.y, home.layer)
    if not ok then say(L('deny', 'The portal does not let you through.', 'Das Portal lässt dich nicht durch.'), tostring(err)) return end
    local c = portal_creature()
    if c then gear.npc.remove(c) end
    store.data.home, store.data.portal = nil, nil
    store:changed()
end

gear.npc.define(KIND, {
    type = 'GHOST.GRN',
    name = {en = 'Town Portal', de = 'Stadtportal'},
    stance = 'friendly',
    talk_range = 260,
    tint = 0xFF70B8FF,
    dialog = {
        start = 'gate',
        pages = {
            gate = {
                text = function() return L('gate', 'A shimmering gate. It leads back to the place where you drank the potion.', 'Ein schimmerndes Tor. Es führt zurück zu dem Ort, an dem du den Trank getrunken hast.') end,
                options = {
                    {id = 'enter', label = function() return L('step', 'Step through', 'Hindurchgehen') end, on = step_through, close = true},
                    {id = 'stay', label = function() return L('notyet', 'Not yet', 'Noch nicht') end, close = true},
                },
            },
        },
    },
})

-- Keeps the portal and the saved spot together: after a load a portal that is in the savegame stays; one the game lost is made again; a spot
-- without a portal (a failed spawn, a portal the game removed) is dropped so the potion works again.
local checked = false
gear.on('session.start', function() checked = false end)
gear.on('savegame.changed', function() checked = false; dialog_open = false end)
gear.every(2, gear.guard('check', function()
    if checked or not hero() or not gear.world.can_change() then return end
    checked = true
    local d = store.data
    if not d.home then
        local c = portal_creature()
        if c then gear.npc.remove(c) end        -- a portal without a spot (an older game): it leads nowhere
        return
    end
    if portal_creature() then return end
    local p = d.portal
    if not p then d.home = nil store:changed() return end
    local c = gear.npc.spawn(KIND, p.x, p.y, {layer = p.layer})
    if not c then d.home, d.portal = nil, nil store:changed() end
end))

-- Merchants -----------------------------------------------------------------------------------------------------------------------------------------

local batch = {merchant = 0, last = 0, rolled = false}
gear.on('shop.stock', function(e)
    if not S.get('in_shops') then return end
    local info = gear.shop.info()
    if not info then return end
    if e.merchant ~= batch.merchant or e.container <= batch.last then
        batch = {merchant = e.merchant, last = 0, rolled = false}
    end
    batch.last = e.container
    if batch.rolled or e.reason == 'restock' then return end
    local page
    for _, p in ipairs(info.pages) do
        if p.container == e.container then page = p end
    end
    if not page then return end
    local sells_potions = false
    for _, c in ipairs(page.categories) do
        if c.category == gear.shop.CATEGORY.POTION then sells_potions = true end
    end
    if not sells_potions then return end
    batch.rolled = true
    if math.random() * 100 >= (S.get('shop_chance') or 70) then return end
    for _ = 1, math.random(1, math.max(1, math.floor(S.get('shop_count') or 2))) do
        local id, err = gear.shop.add{container = page.container, type = SCROLL_TYPE, quality = 0}
        if not id then gear.log('town-portal: could not stock a potion: ' .. tostring(err)) break end
    end
end)

-- For the self test.
gear.on('town-portal.state', function(answer)
    answer({open = dialog_open, home = store.data.home, portal = store.data.portal, scroll_type = SCROLL_TYPE, has_portal = portal_creature() ~= nil})
end)
gear.on('town-portal.read', gear.guard('read event', function() open_dialog() end))
gear.on('town-portal.travel', gear.guard('travel event', function(i) travel(i) end))
gear.on('town-portal.combat', gear.guard('combat', function(off) test_ignore_combat = off end))
gear.on('town-portal.talk', gear.guard('talk event', function() local c = portal_creature() if c then gear.npc.talk(c) end end))
gear.on('town-portal.addpoint', gear.guard('addpoint', function(name) new_name = name add_point() end))
gear.on('town-portal.entries', gear.guard('entries', function(answer) local out = {} for _, e in ipairs(entries()) do out[#out + 1] = {name = e.name, known = e.known, own = e.own, x = e.x, y = e.y} end answer(out) end))
gear.on('town-portal.remove', gear.guard('remove', function(i) local e = entries()[i] if e and e.own then table.remove(points.data.list, e.own) points:changed() end end))
gear.on('town-portal.edit', gear.guard('edit', function() open_dialog(true) end))
gear.on('town-portal.cancel', function() close_dialog() end)
gear.on('town-portal.step', gear.guard('step event', function() step_through() end))

gear.on('draw', gear.guard('draw', draw))
