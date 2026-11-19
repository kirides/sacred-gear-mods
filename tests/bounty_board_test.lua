-- The local bounty board's creature targets (src/bounty/localboard.lua, creatures.lua) outside the game: ids are saved, old names
-- migrate, the picker finds a creature by its localized name. From the repository root:  luajit tests/bounty_board_test.lua
package.path = 'src/bounty/?.lua;' .. package.path
local board = require('localboard')
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

-- A stand-in for gear.data.object_types: type 38 is ORC_WARRIOR.GRN, shown as "Orkkrieger".
local INTERNAL = {['orc_warrior.grn'] = 38, ['wolf.grn'] = 512}
local SHOWN = {[38] = 'Orkkrieger', [512] = 'Silber-Wolf'}
board.resolver = function(text) return INTERNAL[text:lower()] or (function() for id, n in pairs(SHOWN) do if n:lower() == text:lower() then return id end end end)() end
board.labeler = function(id) return SHOWN[id] or ('type ' .. id) end

local function rng(lo) return lo end

-- migration of a bounty file of an older version: names became ids, words stay words, unknown names are kept
local d = board.clean_def({id = 'c1', title = 'Old', names = {'ORC_WARRIOR.GRN', 'orc', 'Silber-Wolf', 'No-Such-Thing'}, target = 5,
    trigger = {on = true, names = {'wolf.grn'}, count = 3}})
ok(d and #d.types == 2 and d.types[1] == 38 and d.types[2] == 512, 'a model name and a localized name became type ids')
ok(d and #d.names == 2 and d.names[1] == 'orc' and d.names[2] == 'nosuchthing', 'a family word stays, an unknown name is kept: ' .. table.concat(d and d.names or {}, ','))
ok(d and #d.trigger.types == 1 and d.trigger.types[1] == 512, 'the trigger migrates as well')
ok(board.clean_def({id = 'c2', names = {'orc'}, types = {38, 38, 'x', 0}}).types[1] == 38 and #board.clean_def({id = 'c2', types = {38, 38, 'x', 0}}).types == 1,
    'ids are checked and not repeated')

-- the new form is written with the next save, and reads back unchanged
local b = board.new(rng, {})
b:start(d)
local saved = b:save_table()
ok(saved.board[1].types[1] == 38 and saved.board[1].types[2] == 512, 'the saved bounty holds the ids')
local again = board.load(saved, rng, {})
ok(#again.list == 1 and again.list[1].types[2] == 512, 'ids survive a save and a load')

-- an old board.json (names only) loads and migrates
local old = {v = 1, seq = 1, board = {{id = 1, def = 'c9', title = 'T', names = {'ORC_WARRIOR.GRN'}, target = 2, left = 100, n = 0}}}
local loaded = board.load(old, rng, {})
ok(#loaded.list == 1 and loaded.list[1].types[1] == 38 and #loaded.list[1].names == 0, 'an old saved bounty migrates to ids')

-- matching: by id, by family word, by neither, and any
local function kill_count(def, words_of, id)
    local bd = board.new(rng, {})
    bd:start(board.clean_def(def))
    bd:kill(board.words(words_of), 10, id)
    return bd.list[1].n
end
ok(kill_count({id = 'a', types = {38}, target = 9}, 'ORC_WARRIOR.GRN', 38) == 1, 'a listed type counts')
ok(kill_count({id = 'a', types = {38}, target = 9}, 'WOLF.GRN', 512) == 0, 'another type does not count')
ok(kill_count({id = 'a', names = {'wolf'}, target = 9}, 'WOLF.GRN', 512) == 1, 'a family word counts')
ok(kill_count({id = 'a', target = 9}, 'WOLF.GRN', 512) == 1, 'no filter counts any creature')
ok(kill_count({id = 'a', types = {38}, target = 9}, 'ORC_WARRIOR.GRN', nil) == 0, 'no type id: only words can match')

-- what the player reads is the localized name
ok(board.target_text({'orc'}, {38, 512}) == 'orc/Orkkrieger/Silber-Wolf', 'the target text shows localized names: ' .. board.target_text({'orc'}, {38, 512}))
ok(board.target_text({}, {1, 2, 3, 4, 5}) == 'type 1/type 2/type 3/+2', 'a long list is shortened')
ok(board.item_label({id = 38, name = 'saved'}) == 'Orkkrieger' and board.item_label({id = 999, name = 'saved'}) == 'saved', 'an item reward shows the localized name, the saved one without')
local started = board.new(rng, {})
started:start(d)
ok(started.list[1].text:find('Orkkrieger', 1, true) ~= nil, 'the bounty text has the localized name: ' .. started.list[1].text)

-- the picker: a filter finds a creature type by its localized name, and picking it gives an id
local creatures
do
    local fake = {}
    function fake.words(text) local t = {} for w in tostring(text or ''):lower():gmatch('%a+') do t[#t + 1] = w end return t end
    function fake.score(q, words) for _, w in ipairs(q) do for _, x in ipairs(words) do if x:find(w, 1, true) then return 1 end end end end
    function fake.search(kind, text)
        local out = {}
        if kind == 'creature_type' then
            for id, shown in pairs(SHOWN) do if shown:lower():find(text:lower(), 1, true) then out[#out + 1] = {id = id, name = shown, internal = 'X'} end end
        end
        return out
    end
    gear = {lookup = fake}
    creatures = require('creatures')
end
local labels, entries = creatures.options('orkkr')
local picked
for i, e in ipairs(entries) do if e and e.types and e.types[1] == 38 then picked = labels[i] end end
ok(picked == 'Orkkrieger', 'the picker finds a creature by its localized name and offers its id: ' .. tostring(picked))

if failures == 0 then print('bounty board: ok') else os.exit(1) end
