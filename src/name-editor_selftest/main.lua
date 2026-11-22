-- A self test of the name editor, for runs without a player (a copy of the game folder):
--
--     Sacred.exe -gear-auto -gear-instance=name-editor -gear-mods=name-editor,name-editor_selftest,sacred-theme
--
-- In the start menu: opens the editor, types, moves the cursor, picks colors and icons, applies a gradient, pastes a raw name,
-- switches the tabs and takes pictures. Results: GearAutomation\<instance>\name_editor_selftest.txt (PASS / FAIL lines).
if not gear.auto then return end
local A = gear.auto
local CF, GF = '\\cff', '\\gffffffff00000'      -- the raw codes: color, icon (+ 3 hex digits)
local lines, failed = {}, false
local function say(s) lines[#lines + 1] = s A.write('name_editor_selftest.txt', table.concat(lines, '\n')) end
local function check(name, ok, detail)
    say((ok and 'PASS ' or 'FAIL ') .. name .. (detail ~= nil and (' (' .. tostring(detail) .. ')') or ''))
    if not ok then failed = true end
end
local function query() local o = {} gear.emit('name-editor.query', o) return o end
local function press(id) local t = {id = id} gear.emit('name-editor.press', t) gear.wait(0.3) end
local function shot(n) gear.wait(0.8) A.screenshot(n) end
local function count(s, sub) local n, i = 0, 1 while true do local a, b = s:find(sub, i, true) if not a then return n end n = n + 1 i = b + 1 end end

gear.task(function()
    A.wait_for_menu(120)
    gear.wait(3)
    gear.emit('name-editor.set', {shown = true})
    gear.wait(1.5)
    check('the window opens', query().shown == true)
    check('it starts empty', query().raw == '', query().raw)
    shot('0-empty')

    A.type('Raven')
    gear.wait(0.5)
    check('typed letters', query().raw == 'Raven', query().raw)
    A.press('left') A.press('left')
    gear.wait(0.3)
    check('cursor left', query().caret == 3, query().caret)
    A.press('backspace')
    gear.wait(0.3)
    check('Backspace', query().raw == 'Raen', query().raw)
    A.press('end')
    gear.wait(0.3)
    check('End', query().caret == 4, query().caret)

    press('sw-ED1C24')
    A.type('Hero')
    gear.wait(0.4)
    check('a color code before the letters', query().raw == 'Raen' .. CF .. 'ED1C24Hero', query().raw)
    press('ic-0DA')
    check('an icon', query().raw == 'Raen' .. CF .. 'ED1C24Hero' .. GF .. '0DA', query().raw)
    check('recent colors', query().recent[1] == 'ED1C24')

    press('act-clear')
    press('act-example')
    local ex = query().raw
    check('the example is read back', count(ex, GF) == 2 and count(ex, CF) == 5, ex)
    shot('1-colors')
    gear.emit('name-editor.set', {raw = ex})
    check('raw in, raw out', query().raw == ex)

    press('tab-ico')
    check('the icons tab', query().tab == 'ico')
    shot('2-icons')

    press('tab-grd')
    check('the gradient tab', query().tab == 'grd')
    gear.emit('name-editor.set', {raw = 'Gradient Name'})
    press('pre-1')
    check('a preset sets both ends', query().gA == 'BA060B' and query().gB == 'FFF14E', query().gA .. ' ' .. query().gB)
    press('act-apply')
    local r = query().raw
    check('one code per letter, spaces skipped', count(r, CF) == 12, count(r, CF))
    check('first letter takes the start color', r:sub(1, #CF + 6) == CF .. 'BA060B', r)
    shot('3-gradient')
    press('act-nocol')
    check('remove colors', query().raw == 'Gradient Name', query().raw)

    gear.emit('name-editor.set', {raw = 'Gradient Name', caret = 3})
    press('scope-cursor')
    press('act-apply')
    check('from the cursor: the letters before stay plain', query().raw:sub(1, 3) == 'Gra' and count(query().raw, CF) == 9, query().raw)
    press('act-swap')
    check('swap', query().gA == 'FFF14E' and query().gB == 'BA060B')

    A.press('escape')
    gear.wait(0.5)
    check('Escape closes the window', query().shown == false)
    say(failed and 'FAILED' or 'ALL PASSED')
    A.quit(failed and 1 or 0)
end)
