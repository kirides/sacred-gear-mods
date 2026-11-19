-- Self test: a battle mage companion's Steinhaut reaches the hero you play at half strength, with the stone look,
-- and ends with the mage's own. Needs the companions setting buffs = always (seed GearAutomation<instance>gear_mods.json)
-- and Gear with gear.buffs.
if not gear.auto then return end
local A, party, B = gear.auto, gear.party, gear.buffs
local res = {passed = 0, failed = 0}
local function check(n, ok, d) if ok then res.passed = res.passed + 1 else res.failed = res.failed + 1 end print((ok and 'PASS ' or 'FAIL ') .. n .. (d ~= nil and (': ' .. tostring(d)) or '')) end
gear.task(function()
  A.wait_for_menu(120)
  A.wait_for_game(180)
  gear.wait(2)
  local h = party.leader()
  local f0 = B.fields(h)
  local m = party.recruit('battlemage', {experience = 500000})
  gear.wait(1)
  m:learn(2, 10)
  local got = gear.wait_until(function() return #h:buffs() > 0 end, 60)
  check('the hero gets the mage\'s Steinhaut', got)
  if got then
    local b = h:buffs()[1]
    local f1 = B.fields(h)
    print('buff', b.key, b.id, b.strength, b.seconds, b.overlay)
    for _, md in ipairs(b.mods) do print('mod', string.format('%x', md[1]), md[2], md[3]) end
    check('at half strength', b.strength == 0.5, b.strength)
    check('stone look', (B.overlay(h)) == 7, B.overlay(h))
    check('resistance up', f1[B.STATS.resist_physical] > f0[B.STATS.resist_physical], f0[B.STATS.resist_physical] .. ' -> ' .. f1[B.STATS.resist_physical])
    gear.wait(1)
    A.screenshot('share-stone')
    local gone = gear.wait_until(function() return #h:buffs() == 0 end, 90)
    check('ends with the mage\'s own', gone)
  end
  A.write('share.json', gear.json.encode(res))
  print(('%d passed, %d failed'):format(res.passed, res.failed))
  A.quit(res.failed == 0 and 0 or 1)
end)
