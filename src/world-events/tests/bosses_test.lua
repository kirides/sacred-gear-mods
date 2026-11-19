-- Unit tests of bosses.lua (the list of bosses the bar shows, the server's boss message) and events.boss_payload.
-- Plain Lua 5.1 / LuaJIT, no game:  luajit tests/bosses_test.lua  (from the mod's folder). Exit code 0 when everything passes.
package.path = './?.lua;' .. package.path
local bosses = require('bosses')
local events = require('events')

local passed, failed = 0, 0
local function check(cond, what)
    if cond then passed = passed + 1 else failed = failed + 1 print('FAIL: ' .. what) end
end
local function eq(a, b, what) check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')') end

eq(bosses.thousands(0), '0', 'thousands 0')
eq(bosses.thousands(999), '999', 'thousands 999')
eq(bosses.thousands(1000), '1,000', 'thousands 1000')
eq(bosses.thousands(123456), '123,456', 'thousands 123456')
eq(bosses.thousands(1234567), '1,234,567', 'thousands 1234567')

-- the server's message
local rec = bosses.parse({v = 1, id = 'e:h1:1', st = 'active', name = 'Grakk\nthe\\Test', event = 'Orc hunt', hp = 500, max = 1000, reward = '777 gold'})
check(rec ~= nil, 'a good message')
eq(rec.name, 'Grakk the Test', 'control characters and backslashes are removed from the name')
eq(rec.hp, 500, 'hp')
eq(rec.max, 1000, 'max')
eq(rec.source, 'server', 'source')
eq(bosses.parse({v = 1, id = 'x', st = 'nope', name = 'A'}), nil, 'a bad state')
eq(bosses.parse({v = 1, st = 'active', name = 'A'}), nil, 'no id')
eq(bosses.parse({v = 1, id = 'x', st = 'active', name = '  '}), nil, 'no name')
eq(bosses.parse('x'), nil, 'not a table')
local clipped = bosses.parse({id = 'x', st = 'active', name = string.rep('n', 200), hp = 5000, max = 100})
eq(#clipped.name, 40, 'the name is clipped')
eq(clipped.hp, 100, 'hp never above max')
local frac = bosses.parse({id = 'x', st = 'active', name = 'A', frac = 7})
eq(frac.frac, 1, 'frac is clamped')
eq(frac.max, nil, 'no numbers: no max')

-- the tracker
local t = bosses.tracker()
t:set({key = 'a', name = 'Alpha', hp = 100, max = 100, st = 'active', source = 'local'}, 10)
t:set({key = 'b', name = 'Beta', frac = 0.5, st = 'active', source = 'server'}, 11)
local views, more = t:views(12)
eq(#views, 2, 'two bars')
eq(more, 0, 'none left out')
eq(views[1].key, 'b', 'the newest first')
eq(views[1].hp_text, '50%', 'no numbers: a percent')
eq(views[2].hp_text, '100 / 100', 'numbers')
eq(views[2].frac, 1, 'full')
check(t:health('a', 25, 100), 'health of a live boss')
eq(t:views(12)[2].frac, 0.25, 'the bar follows the health')
check(not t:health('zzz', 1, 1), 'no such boss')
eq(t:active(), 2, 'two active')
local b = t:finish('a', 'defeated', 20, 'Bob')
check(b ~= nil and b.st == 'defeated' and b.by == 'Bob', 'finish')
eq(t:finish('a', 'defeated', 21), nil, 'a finished boss cannot be finished again')
local v = bosses.view(t.by_key.a, 21)
eq(v.hp_text, 'Defeated', 'defeated text')
eq(v.frac, 0, 'defeated: empty bar')
check(v.alpha == 1, 'fully visible at first')
check(bosses.view(t.by_key.a, 20 + bosses.HOLD - 1).alpha < 1, 'fades at the end')
eq(t:views(21)[1].key, 'b', 'active ones first')
t:expire(21)
eq(#t.list, 2, 'still held')
t:expire(20 + bosses.HOLD + 1)
eq(#t.list, 1, 'a defeated boss is forgotten after the hold')
-- an active record again after a finish starts over
t:set({key = 'b', name = 'Beta', st = 'defeated'}, 30)
eq(t.by_key.b.st, 'defeated', 'the server ends a boss')
t:set({key = 'b', name = 'Beta', st = 'active'}, 31)
check(t.by_key.b.st == 'active' and t.by_key.b.ended == nil, 'and starts it again')
t:set({key = 'g', name = 'Gone', st = 'gone'}, 32)
t:expire(32)
eq(t.by_key.g, nil, 'a gone boss goes at once')
-- more than MAX_BARS bosses
local many = bosses.tracker()
for i = 1, 5 do many:set({key = 'k' .. i, name = 'B' .. i, st = 'active', frac = 1}, i) end
local mv, mmore = many:views(10)
eq(#mv, bosses.MAX_BARS, 'at most MAX_BARS bars')
eq(mmore, 2, 'the others are counted')
for i = 1, bosses.MAX_TRACKED + 5 do many:set({key = 'm' .. i, name = 'M', st = 'active', frac = 1}, 100 + i) end
check(#many.list <= bosses.MAX_TRACKED, 'the list is bounded')
many:clear()
eq(#many.list, 0, 'clear')

eq(bosses.reward_text({gold = 5000, item = {type = 'Healing Potion'}}), '5,000 gold, Healing Potion', 'reward text')
eq(bosses.reward_text({item = {category = 'weapon'}}), 'an item (weapon)', 'reward text of a category')
eq(bosses.reward_text(nil), '', 'no reward')

-- events: the payload of the boss hooks
local p = events.boss_payload({key = 'local:1:1', name = 'Grakk', event = 'E', type = 38, type_name = 'ORC_WARRIOR.GRN', creature = 981, max_hp = 1000,
    mods = {damage = 3, taken = 0.5, deflect = 0, reflect = 0.2, regen = 0}, reward_text = '777 gold'}, 'local', {initial = true})
eq(p.id, 'local:1:1', 'payload id')
eq(p.health, 1000, 'payload health')
eq(p.damage, 3, 'payload damage')
eq(p.reward, '777 gold', 'payload reward')
eq(p.initial, true, 'extra fields')
eq(p.source, 'local', 'source')
local names = {}
for _, e in ipairs(events.EVENTS) do names[e[1]] = e end
check(names['worldevent.boss.spawned'] ~= nil and names['worldevent.boss.defeated'] ~= nil, 'the boss events are declared')
check(names['worldevent.boss.spawned'][3] ~= nil, 'with their own arguments')

print(('bosses tests: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
