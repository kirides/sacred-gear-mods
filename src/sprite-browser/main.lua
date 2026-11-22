-- Sprite browser: all UI images of the game (gear.ui.images) in a grid with their numbers, 24 to a page, in the "Sprites" tab of the
-- mod's page in the Mods screen (ui/page.rml). Each picture is a `.sprite-N` class of the Sacred theme mod (add it to the mods that run the browser);
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
        cells[#cells + 1] = {id = 'sp' .. im.id, n = tostring(im.id), cls = 'sprite sprite-' .. im.id, size = ('%dx%d'):format(im.w, im.h),
            tip = ('.sprite-%d  %dx%d  %s  (code %03X)'):format(im.id, im.w, im.h, im.sheet, im.id)}
    end
    local first, last = cells[1] and tonumber(cells[1].n) or 0, cells[#cells] and tonumber(cells[#cells].n) or 0
    return {cells = cells, title = ('Images %d to %d of %d  ·  page %d of %d'):format(first, last, #all, state.page, pages()), copied = state.copied or ''}
end

gear.mods.page_rml('ui/page.rml', {
    model = {cells = {}, title = '', copied = ''},
    on_load = function(doc)
        local function step(d) return function() state.page = state.page + d state.copied = '' end end
        doc:on('#first', 'click', function() state.page = 1 state.copied = '' end)
        doc:on('#prev10', 'click', step(-10))
        doc:on('#prev', 'click', step(-1))
        doc:on('#next', 'click', step(1))
        doc:on('#next10', 'click', step(10))
        doc:on('#last', 'click', function() state.page = pages() state.copied = '' end)
        doc:on('.cell', 'click', function(e)
            local n = tostring(e.current):match('^sp(%d+)$')
            if n then
                gear.clipboard.set('sprite-' .. n)
                state.copied = 'Copied sprite-' .. n
            end
        end)
    end,
    update = function(doc)
        local m = doc.model
        local b = build()
        if m.title ~= b.title then m.cells = b.cells m.title = b.title end
        if m.copied ~= b.copied then m.copied = b.copied end
    end,
})
