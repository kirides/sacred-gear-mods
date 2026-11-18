---@type GearModManifest
return {
    id = 'quests_selftest',
    name = 'Daily quests self test',
    version = '1.0.0',
    author = 'Sacred Gear',
    description = 'Automation only: the daily and weekly quests of the bounty mod (rollover, streaks, rewards, per savegame data).',
    automation = true,
    priority = 200,
    config = {slot_a = 91, slot_b = 10},
}
