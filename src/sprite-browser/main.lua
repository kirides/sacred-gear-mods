-- Sprite browser: all UI images of the game (gear.ui.images) in a grid with their numbers, 24 to a page, in the "Sprites" tab of the
-- mod's page in the Mods screen (ui/page.rml). Each picture is scaled to fit its cell; N is the `.sprite-N` class of the Sacred theme mod;
-- a click copies the class name to the clipboard. The numbers are also the N of gear:image/N and of the \gffffffff00000XXX codes of names (XXX is N in hex).

local PER = 24
local list              -- {id, w, h, sheet} by id, built on first use
local state = {page = 1}

local function images()
    if list then return list end
    list = {}
    for _, im in ipairs(gear.ui.images() or {}) do list[#list + 1] = {id = im.id, w = im.width, h = im.height, sheet = im.sheet} end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function pages() return math.max(1, math.ceil(#images() / PER)) end

local function build()
    local all = images()
    state.page = math.min(math.max(state.page, 1), pages())
    local cells = {}
    for i = (state.page - 1) * PER + 1, math.min(state.page * PER, #all) do
        local im = all[i]
        cells[#cells + 1] = {id = 'sp' .. im.id, n = tostring(im.id), deco = ('image(gear:image/%d?dp contain)'):format(im.id), size = ('%dx%d'):format(im.w, im.h),
            tip = ('.sprite-%d  %dx%d  %s  (code %03X)'):format(im.id, im.w, im.h, im.sheet, im.id)}
    end
    local first, last = cells[1] and tonumber(cells[1].n) or 0, cells[#cells] and tonumber(cells[#cells].n) or 0
    local b = {cells = cells, title = ('Images %d to %d of %d  ·  page %d of %d'):format(first, last, #all, state.page, pages()), copied = state.copied or '',
        view = state.view ~= nil}
    local im = state.view and all[state.view]
    if im then
        b.v_title = ('sprite-%d'):format(im.id)
        b.v_info = ('%dx%d  ·  %s  ·  code %03X  ·  %d of %d'):format(im.w, im.h, im.sheet, im.id, state.view, #all)
        b.v_deco = ('image(gear:image/%d?dp contain)'):format(im.id)
    else
        b.v_title, b.v_info, b.v_deco = '', '', 'none'
    end
    return b
end

-- the preview box: open on a sprite (an index of the list), step through the sprites with the arrows, close by a click on the picture, C or the pad's B
local function show(i)
    local n = #images()
    state.view = ((i - 1) % n) + 1
    state.page = math.ceil(state.view / PER)       -- the grid behind it follows
    state.copied = ''
end

gear.mods.page_rml('ui/page.rml', {
    model = {cells = {}, title = '', copied = '', view = false, v_title = '', v_info = '', v_deco = 'none'},
    on_load = function(doc)
        local function step(d) return function() state.page = state.page + d state.copied = '' end end
        doc:on('#first', 'click', function() state.page = 1 state.copied = '' end)
        doc:on('#prev10', 'click', step(-10))
        doc:on('#prev', 'click', step(-1))
        doc:on('#next', 'click', step(1))
        doc:on('#next10', 'click', step(10))
        doc:on('#last', 'click', function() state.page = pages() state.copied = '' end)
        doc:on('.cell', 'click', function(e)
            local n = tonumber(tostring(e.current):match('^sp(%d+)$'))
            if n then
                for i, im in ipairs(images()) do if im.id == n then show(i) break end end
            end
        end)
        doc:on('#vprev', 'click', function() show(state.view - 1) end)
        doc:on('#vnext', 'click', function() show(state.view + 1) end)
        doc:on('#vpic', 'click', function() state.view = nil end)
        doc:on('#vclose', 'click', function() state.view = nil end)
        doc:on('#vcopy', 'click', function()
            local im = state.view and images()[state.view]
            if im then
                gear.clipboard.set('sprite-' .. im.id)
                state.copied = 'Copied sprite-' .. im.id
            end
        end)
    end,
    update = function(doc)
        if state.view then
            if gear.ui.key_pressed('c') or gear.ui.back_pressed() then state.view = nil end
            if state.view and gear.ui.key_pressed('left') then show(state.view - 1) end
            if state.view and gear.ui.key_pressed('right') then show(state.view + 1) end
        end
        local m = doc.model
        local b = build()
        if m.title ~= b.title then m.cells = b.cells m.title = b.title end
        for _, k in ipairs({'copied', 'view', 'v_title', 'v_info', 'v_deco'}) do
            if m[k] ~= b[k] then m[k] = b[k] end
        end
    end,
})
