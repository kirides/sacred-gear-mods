-- The creatures a bounty can ask for, for the editor's picker: nobody knows the game's creature names, so they come from Gear's
-- lookup kind 'creature' (words of the monster type names: ORC_WARRIOR.GRN has orc and warrior, the same words a bounty matches
-- on). The groups bundle several words.

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

-- Options of the "add creature" dropdown for a filter text: the groups that match, then the creatures of Gear's lookup kind
-- 'creature' (forgiving search, best first; see gear.lookup). Returns labels and a parallel list of {words = {...}} entries;
-- entry 1 is the placeholder.
local memo_filter, memo_labels, memo_entries
function M.options(filter)
    if filter == memo_filter and memo_labels then return memo_labels, memo_entries end
    local labels, entries = {'+ Add a creature...'}, {false}
    local lookup = gear.lookup
    local q = lookup.words(filter)
    for _, g in ipairs(M.GROUPS) do
        if #q == 0 or lookup.score(q, lookup.words(g.label .. ' ' .. table.concat(g.words, ' '))) then
            labels[#labels + 1] = '[Group] ' .. g.label
            entries[#entries + 1] = {words = g.words}
        end
    end
    for _, t in ipairs(lookup.search('creature', filter, 200)) do
        labels[#labels + 1] = ('%s (%d)'):format(t.name, t.count)
        entries[#entries + 1] = {words = {t.word}}
    end
    if #labels == 1 then labels[2], entries[2] = 'Nothing matches', false end
    memo_filter, memo_labels, memo_entries = filter, labels, entries
    return labels, entries
end

function M.label(word)
    return (word:gsub('^%l', string.upper))
end

return M
