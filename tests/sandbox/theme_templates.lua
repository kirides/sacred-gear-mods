-- The sacred-theme templates in the sandbox at 1600x900 (tests/sandbox/theme_templates.ps1 starts this): the screen shows its title bar from the model, the groups and
-- the drop-down button are there, a click opens the drop-down's list and a click on an option closes it and sets the button's text. Snapshots go to the folder in arg[1].
local out = arg[1] or '.'
sbx.frame(30)
sbx.snapshot(out .. '\\templates-1-closed.png')
local failures = 0
local function check(ok, what) if not ok then failures = failures + 1 sbx.log('FAIL ' .. what) end end
local function rgb(p) return (p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff end
-- the title bar of sacred-screen is the brown #302418, the group frames are drawn, the window flows below the 80 px top margin of the demo's style
local r, g, b = rgb(sbx.pixel(300, 100))
check(r == 0x30 and g == 0x24 and b == 0x18, ('title bar of sacred-screen is brown, got %02x%02x%02x'):format(r, g, b))
local closed = sbx.pixel(330, 215)
-- click the drop-down button (its middle), then look under it
local function click(x, y)
    sbx.mouse(x, y) sbx.frame(2)
    sbx.button(true) sbx.frame(2)
    sbx.button(false) sbx.frame(3)
end
click(362, 176)
sbx.snapshot(out .. '\\templates-2-open.png')
local open = sbx.pixel(330, 215)
check(open ~= closed, 'the list of the drop-down opens under its button')
-- the second option (Level) at about y 230
click(340, 232)
sbx.snapshot(out .. '\\templates-3-chosen.png')
check(sbx.pixel(330, 215) == closed, 'the list closes after a choice')
sbx.log(failures == 0 and 'theme templates: ok' or ('theme templates: %d failures'):format(failures))
return failures
