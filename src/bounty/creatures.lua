-- The creatures a bounty can ask for, for the editor's picker: nobody knows the game's creature names, so they are read from
-- the game's own object types. A "creature" here is a word of a monster's type name (ORC_WARRIOR.GRN has orc and warrior), the
-- same words the bounty matches on, shown with a readable label and how many monster types carry it. Groups bundle several words.

local fuzzy = require('fuzzy')

local M = {}

M.GROUPS = {
    {label = 'Orcs', words = {'orc'}},
    {label = 'Undead', words = {'skeleton', 'zombie', 'mummy', 'ghost'}},
    {label = 'Spiders', words = {'spider'}},
    {label = 'Thieves and pirates', words = {'thief', 'pirate'}},
    {label = 'Wolves, bears and boars', words = {'wolf', 'bear', 'boar'}},
    {label = 'Trolls and ogres', words = {'troll', 'ogre', 'minotaur'}},
    {label = 'Demons and golems', words = {'demon', 'gargoyle', 'golem'}},
    {label = 'Dragons', words = {'dragon'}},
    {label = 'Scorpions and snakes', words = {'scorpion', 'snake'}},
}

local KIND_MONSTER = 3
local SKIP = {grn = true, fem = true, mal = true, male = true, female = true, new = true, old = true, big = true, small = true,
    med = true, tiny = true, var = true, npc = true, boss = true, spawn = true, anim = true, ani = true}

local list, by_word

local function label_of(word)
    return (word:gsub('^%l', string.upper))
end
M.label_of = label_of

-- Reads the monster types once. Returns the sorted list {word, label, count}.
function M.catalog()
    if list then return list end
    local counts = {}
    local types = gear.data.object_types
    for id = 1, 0x7E5F do
        if types:kind(id) == KIND_MONSTER then
            local name = types:name(id)
            if name then
                local seen = {}
                for w in name:lower():gmatch('%a+') do
                    if #w >= 3 and not SKIP[w] and not seen[w] then
                        seen[w] = true
                        counts[w] = (counts[w] or 0) + 1
                    end
                end
            end
        end
    end
    list, by_word = {}, {}
    for w, n in pairs(counts) do
        local e = {word = w, label = label_of(w), count = n}
        list[#list + 1] = e
        by_word[w] = e
    end
    table.sort(list, function(a, b) return a.word < b.word end)
    return list
end

-- Options of the "add creature" dropdown for a filter text (fuzzy, see fuzzy.lua): without a filter the groups, then every word
-- in order; with one the best matches first. Returns labels and a parallel list of {words = {...}} entries; entry 1 is the
-- placeholder.
local entries_cache
local function all_entries()
    if entries_cache then return entries_cache end
    entries_cache = {}
    for _, g in ipairs(M.GROUPS) do
        entries_cache[#entries_cache + 1] = {label = '[Group] ' .. g.label, pick = g.words, words = fuzzy.words(g.label .. ' ' .. table.concat(g.words, ' '))}
    end
    for _, e in ipairs(M.catalog()) do
        entries_cache[#entries_cache + 1] = {label = ('%s (%d)'):format(e.label, e.count), pick = {e.word}, words = fuzzy.words(e.word)}
    end
    return entries_cache
end

local memo_filter, memo_labels, memo_entries
function M.options(filter)
    if filter == memo_filter and memo_labels then return memo_labels, memo_entries end
    local labels, entries = {'+ Add a creature...'}, {false}
    local list = all_entries()
    if #fuzzy.words(filter) > 0 then list = fuzzy.rank(list, filter, 60) end
    for _, e in ipairs(list) do
        labels[#labels + 1] = e.label
        entries[#entries + 1] = {words = e.pick}
    end
    if #labels == 1 then labels[2], entries[2] = 'Nothing matches', false end
    memo_filter, memo_labels, memo_entries = filter, labels, entries
    return labels, entries
end

function M.label(word)
    M.catalog()
    local e = by_word[word]
    return e and e.label or label_of(word)
end

return M
