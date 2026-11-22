-- Logic test of src/custom-classes/fx.lua (the effect rules of art files) against a recording fake of gear.pfx. From tests/modmock:
--     dotnet build
--     dotnet run --no-build -- gear.lua fxmod=../../src/custom-classes/fx.lua fx_scenario.lua
-- (gear.lua only makes the `gear` global; the fxmod=path argument runs fx.lua and puts what it returns at gear.fxmod.)
local fx = gear.fxmod
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) else print('pass: ' .. name) end end

-- ---- check: the same messages as the Sacred Class Editor (FxRules.cs) ----
local function problem(list) return fx.check(list) end
ok(problem(nil) == nil, 'no fx is fine')
ok(problem({}) == nil, 'an empty list is fine')
ok(problem(5) == 'fx must be a list', 'fx must be a list')
ok(problem({3}) == 'fx[1] is not an object', 'rule not an object')
ok(problem({{fx = 792}}) == 'fx[1].fx must be a list of effect types', 'fx must be a list of types')
ok(problem({{fx = {767}}}) == 'fx[1].fx: 767 is not an effect type (0x300..0x49D)', 'type below range')
ok(problem({{fx = {1182}}}) == 'fx[1].fx: 1182 is not an effect type (0x300..0x49D)', 'type above range')
ok(problem({{min_level = 0}}) == 'fx[1].min_level must be a whole number 1..200', 'min_level 0')
ok(problem({{max_level = 201}}) == 'fx[1].max_level must be a whole number 1..200', 'max_level 201')
ok(problem({{min_level = 9, max_level = 3}}) == 'fx[1]: min_level 9 is above max_level 3', 'min above max')
ok(problem({{hue = 400}}) == 'fx[1].hue must be a number -360..360', 'hue range')
ok(problem({{alpha = 5}}) == 'fx[1].alpha must be a number 0..4', 'alpha range')
ok(problem({{speed = 0}}) == 'fx[1].speed must be a number 0.01..100', 'speed 0')
ok(problem({{speed = 101}}) == 'fx[1].speed must be a number 0.01..100', 'speed 101')
ok(problem({{colorize = 'red'}}) == 'fx[1].colorize must be a colour text like "#RRGGBB"', 'colorize text')
ok(problem({{multiply = '#FFFFFF'}}) == 'fx[1].multiply must be a colour text like "#AARRGGBB"', 'multiply needs 8 digits')
ok(problem({{textures = 1}}) == 'fx[1].textures must be an object (texture name to texture name)', 'textures object')
ok(problem({{hue = 1}, {speed = -1}}) == 'fx[2].speed must be a number 0.01..100', 'second rule reported')
local many = {}
for i = 1, 65 do many[i] = {hue = 1} end
ok(problem(many) == 'fx has more than 64 rules', 'at most 64 rules')
ok(problem({{fx = {792, 791}, min_level = 1, max_level = 200, hue = -360, colorize = '#FF2020', multiply = '#80FFFFFF',
    alpha = 4, speed = 0.01, textures = {['PARTICLE_GLOW01.TGA'] = 'PARTICLE_SMOKE01.TGA'}}, {}}) == nil, 'a full rule passes')
ok(problem({{colorize = 'ff2020'}}) == nil and problem({{colorize = '0xFF2020'}}) == nil, 'colour texts without # or with 0x')

-- ---- definition: the colour texts become numbers ----
local d = fx.definition(7, {hue = -120, colorize = '#FF2020', multiply = '#80FFFFFF', alpha = 1.5, speed = 0.5, textures = {A = 'B'}})
ok(d.id == 7 and d.hue == -120 and d.colorize == 0xFF2020 and d.multiply == 0x80FFFFFF and d.alpha == 1.5 and d.speed == 0.5 and d.textures.A == 'B', 'definition fields')
local e = fx.definition(8, {})
ok(e.id == 8 and e.hue == nil and e.colorize == nil and e.textures == nil, 'an empty rule defines nothing but the id')
ok(fx.variant_id(2010, 1) == 200000 + 2010 * 64 and fx.variant_id(2010, 3) == fx.variant_id(2010, 1) + 2, 'variant ids are a block per art')
ok(fx.variant_id(2010, 64) < fx.variant_id(2011, 1), 'blocks do not overlap')

-- ---- apply and clear against a recording fake of gear.pfx ----
local now = 100
gear.time = function() return now end
local route_handlers = {}
gear.on = function(event, fn) route_handlers[event] = fn; return {event = event} end
local rec = {defs = {}, rules = {}, removed = {}, undefined = {}}
gear.pfx = {
    define = function(def)
        if def.hue == 999 then error('bad hue') end
        rec.defs[def.id] = def
        return def.id
    end,
    rule = function(r)
        local h = {rule = r}
        rec.rules[#rec.rules + 1] = h
        return h
    end,
    remove_rule = function(h) rec.removed[#rec.removed + 1] = h end,
    undefine = function(id) rec.undefined[#rec.undefined + 1] = id; rec.defs[id] = nil; return true end,
}
local list = {
    {fx = {792}, min_level = 10, hue = -120},
    {colorize = '#40D0FF', speed = 0.5},
    {fx = {}, hue = 5},
}
local made, probs = fx.apply(2010, list, 'm/arts/mist.json')
ok(made == 3 and #probs == 0, 'three rules made')
local r1, r2, r3 = rec.rules[1].rule, rec.rules[2].rule, rec.rules[3].rule
ok(r1.fx[1] == 792 and r1.min_level == 10 and r1.select ~= nil, 'rule 1: type, level, select function')
ok(r1.select({fx = 792, ability = 2010, creature = {}}) == fx.variant_id(2010, 1), 'the art in flight gets variant 1')
ok(r1.select({fx = 792, ability = 1052}) == nil, 'another art does not')
ok(r1.select({fx = 792}) == nil, 'a creature-less effect without a recent use of the art does not')
fx.used(2010)
ok(r1.select({fx = 792, level = 5}) == fx.variant_id(2010, 1), 'a creature-less effect of a named type right after a use gets it')
ok(r2.select({fx = 100}) == nil, 'a rule without types does not take creature-less effects')
ok(r1.select({fx = 792, creature = {id = 3}}) == nil, 'an effect of another creature without the ability does not')
now = now + 5
ok(r1.select({fx = 792}) == nil, 'the window has closed')
fx.used(1052)
now = now + 1
ok(r1.select({fx = 792}) == nil, 'the use of an art without rules is not noted')
ok(r2.fx == nil and r2.min_level == nil and r2.select({fx = 5, ability = 2010}) == fx.variant_id(2010, 2), 'rule 2 applies to every effect of the art in flight')
ok(r3.fx == nil, 'an empty type list means every effect')
ok(r1.priority > r2.priority and r2.priority > r3.priority, 'the first rule has the highest priority')
ok(rec.defs[fx.variant_id(2010, 2)].colorize == 0x40D0FF, 'variant 2 defined')

made, probs = fx.apply(2011, {{hue = 999}, {hue = 1}}, 'm/arts/x.json')
ok(made == 1 and #probs == 1 and probs[1]:find('fx%[1%]: .*bad hue'), 'a define error is reported and the next rule still made')

fx.clear()
ok(#rec.removed == 4 and #rec.undefined == 4, 'clear removes every rule and variant made')
fx.clear()
ok(#rec.removed == 4, 'clear twice does nothing more')

gear.pfx = nil
made, probs = fx.apply(2010, list, 'm/arts/mist.json')
ok(made == 0 and #probs == 1 and probs[1]:find('no gear.pfx'), 'without gear.pfx nothing is made and it is said')
fx.clear()

if failures > 0 then error(failures .. ' failures') end
