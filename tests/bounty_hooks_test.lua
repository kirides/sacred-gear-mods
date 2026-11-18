-- Bounty hooks (src/bounty/hooks.lua) outside the game. From the repository root:  luajit tests/bounty_hooks_test.lua
package.path = 'src/bounty/?.lua;' .. package.path
local hooks = require('hooks')
local failures = 0
local function ok(c, name) if not c then failures = failures + 1; print('FAIL ' .. name) end end

local function run(old, new, opts)
    local out = {}
    hooks.diff(old, new, function(name, p) out[#out + 1] = name .. ':' .. p.id .. (p.previous and ('<' .. p.previous) or '') .. (p.initial and '!' or '') end, opts)
    return table.concat(out, ' ')
end
local function b(id, n, done) return {id = id, title = 'T' .. id, target = 3, n = n, done = done} end

ok(run(nil, {bounties = {b(1, 1), b(2, 0, false)}}) == 'bounty.started:1! bounty.started:2!', 'first board: open bounties start, initial')
ok(run(nil, {bounties = {b(1, 3, true)}}) == '', 'first board: done ones are silent')
ok(run({bounties = {b(1, 0)}}, {bounties = {b(1, 0), b(2, 0)}}) == 'bounty.started:2', 'new bounty starts')
ok(run({bounties = {b(1, 0)}}, {bounties = {b(1, 2)}}) == 'bounty.progress:1<0', 'progress with previous')
ok(run({bounties = {b(1, 2)}}, {bounties = {b(1, 3, true)}}) == 'bounty.progress:1<2 bounty.completed:1', 'progress then completed')
ok(run({bounties = {b(1, 2)}}, {bounties = {b(1, 3, true)}}, {claim_on_done = true}) == 'bounty.progress:1<2 bounty.completed:1 bounty.claimed:1', 'server: claimed with completed')
ok(run({bounties = {b(1, 2), b(2, 0)}}, {bounties = {b(2, 0)}}) == 'bounty.failed:1', 'unfinished bounty that left')
ok(run({bounties = {b(1, 3, true)}}, {bounties = {}}) == '', 'done bounty that left is no failure')
ok(run({bounties = {b(1, 1)}}, {bounties = {b(1, 1)}}) == '', 'no change, no events')
ok(run({bounties = {}}, {bounties = {b(4, 3, true)}}) == 'bounty.started:4 bounty.completed:4', 'finished before the first look')
if failures == 0 then print('bounty hooks: ok') os.exit(0) end
os.exit(1)
