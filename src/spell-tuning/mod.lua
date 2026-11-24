---@type GearModManifest
local settings = {}
local LABEL = {hero = 'the hero you play', companion = 'companions', enemy = 'enemies', neutral = 'neutral creatures', trap = 'traps'}
local ROLES = {'hero', 'companion', 'enemy', 'neutral', 'trap'}
for i = 1, #ROLES do
    local role = ROLES[i]
    local sec = 'Spells cast by ' .. LABEL[role]
    settings[#settings + 1] = {id = role .. '_duration', type = 'number', label = 'Duration of root, stun, fear (%)', min = 0, max = 300, step = 5, default = 100,
        section = sec, tooltip = "How long the effect of a crowd control spell lasts on its victim, as a percentage of the game's own (100: unchanged, 50: half as long). Affects Pflanzenkaefig (root), Fleisch zu Stein (stun), Irritation, Bekehrung and the fear spells"}
    settings[#settings + 1] = {id = role .. '_strength', type = 'number', label = 'Strength of attack, defence, speed changes (%)', min = 0, max = 300, step = 5, default = 100,
        section = sec, tooltip = "How strong the spell's changes of attack, defence and speed are, as a percentage of the game's own"}
    settings[#settings + 1] = {id = role .. '_damage', type = 'number', label = 'Damage (%)', min = 0, max = 300, step = 5, default = 100,
        section = sec, tooltip = "The damage of the spell, as a percentage of the game's own"}
end
return {
    id = 'spell-tuning',
    name = 'Spell tuning',
    version = '0.1.0',
    author = 'kirides',
    description = 'Changes what spells do, by who casts them: the hero you play, companions, enemies, neutral creatures or traps. Shorten (or lengthen) root, stun and fear, weaken (or strengthen) the changes of attack, defence and speed, and the damage. Single player only.',
    settings = settings,
}
