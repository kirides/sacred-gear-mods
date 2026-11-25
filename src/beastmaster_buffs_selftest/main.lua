-- A battle mage companion's Steinhaut (shared by the companions mod with the hero you play) also reaches a Beastmaster ally and ends with it.
-- Needs the companions setting buffs = always (seed GearAutomation\<instance>\gear_mods.json: {"mods":{"companions":{"settings":{"buffs":"always"}}}}):
--     Sacred.exe -gear-auto -gear-instance=bbuffs -gear-load=10 -gear-mods=sacred-theme,companions,beastmaster,beastmaster_buffs_selftest
if not gear.auto then return end
local A, party, B = gear.auto, gear.party, gear.buffs
local res = {passed = 0, failed = 0}
local function check(n, ok, d)
    if ok then res.passed = res.passed + 1 else res.failed = res.failed + 1 end
    print((ok and 'PASS ' or 'FAIL ') .. n .. (d ~= nil and (': ' .. tostring(d)) or ''))
end
local function has(id)
    for _, b in ipairs(B.list(id) or {}) do
        if tostring(b.key):find('beastmaster:', 1, true) then return true end
    end
    return false
end
gear.task(function()
    A.wait_for_menu(120)
    A.wait_for_game(180)
    gear.wait(2)
    local h = party.leader()
    local ally_id, pet_id
    gear.emit('beastmaster.recruit', 567, 'ally', function(i) ally_id = i end)
    gear.emit('beastmaster.recruit', 516, 'pet', function(i) pet_id = i end)
    check('an ally and a pet were taken along', ally_id ~= nil and pet_id ~= nil)
    local m = party.recruit('battlemage', {experience = 500000})
    gear.wait(1)
    m:learn(2, 10)
    local got = gear.wait_until(function() return #h:buffs() > 0 end, 60)
    check('the hero gets the mage\'s Steinhaut', got)
    gear.wait(1)
    check('the ally gets it too', ally_id ~= nil and has(ally_id))
    check('the pet does not (no speed part in Steinhaut)', pet_id ~= nil and not has(pet_id))
    local b = ally_id and B.list(ally_id)[1]
    check('the ally\'s buff runs at half strength like the hero\'s', b ~= nil and math.abs((b.strength or 0) - 0.5) < 0.01, b and b.strength)
    A.screenshot('beasts-stone')
    local gone = gear.wait_until(function() return #h:buffs() == 0 end, 90)
    gear.wait(1)
    check('it ends for the ally with the mage\'s own', gone and ally_id ~= nil and not has(ally_id))
    A.write('beastmaster-buffs.json', gear.json.encode(res))
    print(('%d passed, %d failed'):format(res.passed, res.failed))
    A.quit(res.failed == 0 and 0 or 1)
end)
