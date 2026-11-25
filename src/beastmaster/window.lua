-- The Beastmaster window: the animals to take along (allies and pets) and the ones that follow now. RmlUi (ui/beasts.rml) with the
-- shared theme; every button is a stop for the controller.
local M = {}

function M.new(env)
    local ui = gear.ui
    local shown = false
    local doc, last, msg = nil, {}, ''

    local function name_of(sp)
        local ok, n = pcall(function() return gear.data.object_types:label(sp.type) end)
        if ok and type(n) == 'string' and n ~= '' then return n end
        return sp.label
    end

    local function snapshot()
        local m = {open = shown, title = 'Beastmaster', msg = msg, allies = {}, pets = {}, followers = {}}
        m.ally_text = ('%d of %d'):format(env.count('ally'), env.limit('ally'))
        m.pet_text = ('%d of %d'):format(env.count('pet'), env.limit('pet'))
        for _, sp in ipairs(env.species) do
            local row = {id = 'sp-' .. sp.key, name = name_of(sp)}
            table.insert(sp.role == 'ally' and m.allies or m.pets, row)
        end
        for i, e in ipairs(env.followers()) do
            local c = env.object_of(e)
            local nm = e.type
            for _, sp in ipairs(env.species) do
                if sp.key == e.key or (not e.key and sp.type == e.type) then nm = name_of(sp) end
            end
            local hp = c and c:hp() or 0
            local mx = c and c:max_hp() or 1
            m.followers[#m.followers + 1] = {
                id = 'dis-' .. i, name = tostring(nm), role = e.role == 'ally' and 'Ally' or 'Pet',
                hp = e.role == 'ally' and ('%d%%'):format(math.floor(100 * hp / math.max(1, mx))) or '0%', show_hp = e.role == 'ally',
            }
        end
        m.has_followers = #m.followers > 0
        return m
    end

    local function load_doc()
        doc = ui.rml.load('ui/beasts.rml', {dp = true, model = snapshot()})
        if not doc then return end
        local function on(sel, fn) doc:on(sel, 'click', gear.guard('click ' .. sel, fn)) end
        on('[id^=sp-]', function(e)
            local key = tostring(e.current):gsub('^sp%-', '')
            local problem
            gear.emit('beastmaster.recruit', key, function(id, err) problem = err end)
            msg = problem or ''
        end)
        on('[id^=dis-]', function(e)
            local i = tonumber(tostring(e.current):match('^dis%-(%d+)$'))
            if i then env.dismiss(i) end
            msg = ''
        end)
        on('#dismiss-all', function() env.dismiss_all(); msg = '' end)
    end

    local function same(a, b)
        if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
        return gear.json.encode(a) == gear.json.encode(b)
    end

    local function draw()
        if not doc then load_doc() end
        if not doc then return end
        local m = snapshot()
        for k, v in pairs(m) do
            if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
        end
        if shown then doc:draw({layer = 'hud'}) end
    end

    return {draw = draw, toggle = function() shown = not shown end, open = function(on) shown = on ~= false end}
end

return M
