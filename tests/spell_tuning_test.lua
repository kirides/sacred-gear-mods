-- Logic test of the spell-tuning mod outside the game (src/spell-tuning/core.lua). From the repository root:
--     luajit tests/spell_tuning_test.lua
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

package.path = 'src/spell-tuning/?.lua;' .. package.path
local core = require('core')

ok(core.role({hero = true, played = true}) == 'hero', 'played hero')
ok(core.role({hero = true, played = false}) == 'companion', 'companion')
ok(core.role({enemy = true, name = 'WOLF.GRN'}) == 'enemy', 'enemy')
ok(core.role({enemy = false, name = 'VILLAGER'}) == 'neutral', 'neutral')
ok(core.role({enemy = true, name = 'SpikeTrap'}) == 'trap', 'trap by name')

ok(core.scale(15, 100) == 15 and core.scale(15, 50) == 8 and core.scale(15, 0) == 0 and core.scale(10, 150) == 15, 'scale')

local rec = {param0_base = 14, param0_per_level = 1, value0_base = 10, attack_mod_base = 20}
local p = core.plan(40, rec, {duration = 50, strength = 100, damage = 200})
ok(p.param0_base == 7 and p.param0_per_level == 1, 'duration of a root halves (per level 1 rounds to 1)')
ok(p.value0_base == 20, 'damage doubles')
ok(p.attack_mod_base == 20, 'strength unchanged at 100')
-- a spell that is not a crowd control spell keeps its parameter 0 (healing amounts live there)
local heal = core.plan(7, {param0_base = 10, param0_per_level = 50}, {duration = 50, strength = 100, damage = 100})
ok(heal.param0_base == nil and heal.param0_per_level == nil, 'duration leaves other spells alone')
-- never below one second while the player left it above 0 %
ok(core.plan(40, {param0_base = 1}, {duration = 10, strength = 100, damage = 100}).param0_base == 1, 'at least one second')
ok(core.plan(40, {param0_base = 14}, {duration = 0, strength = 100, damage = 100}).param0_base == 0, '0 percent removes it')

if failures == 0 then print('spell-tuning: all tests passed') else os.exit(1) end
