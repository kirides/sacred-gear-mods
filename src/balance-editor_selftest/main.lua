-- Self test of the Balance editor, for runs without a player, in a COPY of the game folder (it writes the mod's balance.lua):
--
--     Sacred.exe -gear-auto -gear-load=10 -gear-instance=balance -gear-mods=sacred-theme,balance-editor,balance-editor_selftest
--
-- Opens the screen, changes values by event and by a click on a slider, resets them, reads a balance patch (valid, out of range, unknown
-- ids) and checks what the editor keeps. A second run with the same mods checks that the game read the patch at its start
-- (state.served > 0; the log shows "patched bin\balance.bin").
if not gear.auto then print('no automation (start the game with -gear-auto): nothing to do') return end
local A, results = gear.auto, {checks = {}, passed = 0, failed = 0}

local function check(name, ok, detail)
    results.checks[#results.checks + 1] = {name = name, ok = ok and true or false, detail = detail}
    if ok then results.passed = results.passed + 1 else results.failed = results.failed + 1 end
    print(('%s %s%s'):format(ok and 'PASS' or 'FAIL', name, detail ~= nil and (': ' .. tostring(detail)) or ''))
end
local function state() local s = {}; gear.emit('balance-editor.state', function(r) s = r end); return s end
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function doc() local d = A.rml_docs('balance-editor'); return d[1] and d[1].doc end
local function click(sel)
    local d = doc(); local el = d and d:query(sel); local r = el and el:rect()
    if not r then return false end
    A.ui_click(r.x + r.w / 2, r.y + r.h / 2)
    gear.wait(0.5)
    return true
end

gear.task(function()
    if not A.wait_for_game(180) then return A.quit(1) end
    gear.wait(4)
    local start = state()
    check('starts with the saved changes', type(start.edits) == 'table', count(start.edits) .. ' changes')
    gear.emit('balance-editor.open', true, 'difficulty')
    gear.wait(2)
    check('the screen opens', doc() ~= nil)
    gear.emit('balance-editor.set', 'diff.hp.gold', 2.5)
    gear.emit('balance-editor.set', 'loot.rolls', 3)
    gear.wait(0.5)
    local s = state()
    check('values set', s.edits['diff.hp.gold'] == 2.5 and s.edits['loot.rolls'] == 3)
    gear.wait(1)
    check('a change waits for a restart', state().pending == true or (start.edits['diff.hp.gold'] == 2.5 and start.edits['loot.rolls'] == 3))
    -- a click on a slider is the player's move; rebuilding the list (tab, group, search) must not change anything by itself
    local before = count(state().edits)
    click('#tab-loot'); click('#tab-hero'); click('#tab-difficulty'); click('#group'); click('#bal-group-3')
    check('changing the view changes no value', count(state().edits) == before, count(state().edits) .. ' vs ' .. before)
    click('#only-changed'); click('#only-changed')
    check('the changed-only filter changes no value', count(state().edits) == before)
    local d = doc(); local el = d and d:query('.bal-slider'); local r = el and el:rect()
    if r then A.ui_click(r.x + r.w * 0.8, r.y + r.h / 2); gear.wait(1) end
    check('a click on a slider sets a value', count(state().edits) == before + 1, count(state().edits))
    click('.bal-reset'); gear.wait(0.5)
    -- the reset button of the first changed row is the first enabled one: use the group reset for a sure result
    gear.emit('balance-editor.set', 'diff.hp.gold', 1.25)
    check('the game value is no change', state().edits['diff.hp.gold'] == nil)
    -- imports: nothing runs, only numbers of known fields in range count
    local text = gear.json.encode({format = 'sacred-balance-patch', version = 1, name = 'T', changes = {
        {id = 'diff.dmg.gold', value = 1.9}, {id = 'loot.base', value = 99999}, {id = 'no.such', value = 1}, {id = 'loot.rolls', value = 1.5}}})
    local n_import = count(state().edits)
    gear.emit('balance-editor.import', text)
    gear.wait(0.5)
    check('an import shows a preview and changes nothing yet', count(state().edits) == n_import)
    gear.emit('balance-editor.apply')
    gear.wait(0.5)
    local after = state().edits
    check('only the valid entry of the import was applied', after['diff.dmg.gold'] == 1.9 and after['loot.base'] == nil and after['no.such'] == nil)
    local junk = gear.json.encode({format = 'something', version = 1, changes = {}})
    local n0 = count(state().edits)
    gear.emit('balance-editor.import', junk); gear.emit('balance-editor.apply')
    check('a file that is no balance patch changes nothing', count(state().edits) == n0)
    if count(start.edits) > 0 and not start.pending then check('the game read the patch at its start (second run)', start.served > 0, 'served ' .. tostring(start.served)) end
    A.write('balance.json', gear.json.encode(results))
    print(('%d passed, %d failed'):format(results.passed, results.failed))
    if gear.config.quit then A.quit(results.failed == 0 and 0 or 1) end
end)
