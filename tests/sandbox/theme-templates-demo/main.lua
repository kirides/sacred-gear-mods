-- A screen built only from sacred-theme's shared templates; the sandbox script (tests/sandbox/theme_templates.lua) looks at it and clicks its drop-down.
local model = {
    title = 'Shared templates',
    n = 0,
    dd = '',
    key = 'sort', label = 'Sort: name', title_tip = 'Sort order',
    options = {{id = 'o-name', label = 'Name', on = true}, {id = 'o-level', label = 'Level', on = false}, {id = 'o-gold', label = 'Gold', on = false}},
}
local doc
local function open()
    local err
    doc, err = gear.ui.rml.load('ui/demo.rml', {dp = true, model = model, calls = {}})
    if not doc then gear.log('demo: ' .. tostring(err)) return end
    doc:on('#close-x', 'click', function() doc:hide() end)
    doc:on('#sort', 'click', function() model.dd = model.dd == 'sort' and '' or 'sort'; doc.model.dd = model.dd end)
    for _, o in ipairs(model.options) do
        doc:on('#' .. o.id, 'click', function()
            model.dd = ''; doc.model.dd = ''
            doc.model.label = 'Sort: ' .. o.label
        end)
    end
end
gear.on('draw', function()
    if not doc then open() end
    if doc then doc:draw({layer = 'top'}) end
end)
