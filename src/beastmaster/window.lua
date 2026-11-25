-- The Beastmaster window: every animal of the game (a scrolling list), taken along as an ally or a pet, with its base size changed per
-- species, and the animals that follow now. RmlUi (ui/beasts.rml) with the shared theme; every button is a stop for the controller.
local M = {}

function M.new(env)
    local ui = gear.ui
    local shown = false
    local mode = 'ally'                 -- what a click on an animal makes
    local doc, last, msg, refresh_at = nil, {}, '', 0

    local names = {}
    local function name_of(type_id, fallback)
        type_id = tonumber(type_id)
        if names[type_id] then return names[type_id] end
        local ok, n = pcall(function() return gear.data.object_types:label(type_id) end)
        -- (before the game's texts are loaded the label is a placeholder such as 'type 567': not kept)
        if ok and type(n) == 'string' and n ~= '' and not n:match('^type %d+$') then
            names[type_id] = n
            return n
        end
        return fallback or ('type ' .. tostring(type_id))   -- not kept: the game's names may not be there yet
    end

    -- the list sorted by the family's name, then by type: the species of a kind stand together (all wolves, all spiders)
    local ordered = {}
    for _, sp in ipairs(env.species) do ordered[#ordered + 1] = sp end
    table.sort(ordered, function(a, b)
        if a.family ~= b.family then return a.family < b.family end
        return a.type < b.type
    end)

    local function snapshot()
        local m = {open = shown, title = 'Beastmaster', msg = msg, species = {}, followers = {}, mode_ally = mode == 'ally', mode_pet = mode == 'pet'}
        m.ally_text = ('%d of %d'):format(env.count('ally'), env.limit('ally'))
        m.pet_text = ('%d of %d'):format(env.count('pet'), env.limit('pet'))
        m.mode_text = mode == 'ally' and 'a fighting ally' or 'a pet'
        if shown then
            local used = {}
            for _, sp in ipairs(ordered) do
                local label = name_of(sp.type, sp.family)
                used[label] = (used[label] or 0) + 1
                m.species[#m.species + 1] = {
                    id = 'sp-' .. sp.type, minus = 'mn-' .. sp.type, plus = 'pl-' .. sp.type,
                    name = used[label] > 1 and ('%s (%d)'):format(label, used[label]) or label,
                    scale = ('%d%%'):format(math.floor(env.base_scale(sp.type) * 100 + 0.5)),
                }
            end
        end
        for i, e in ipairs(env.followers()) do
            local c = env.object_of(e)
            local hp = c and c:hp() or 0
            local mx = c and c:max_hp() or 1
            m.followers[#m.followers + 1] = {
                id = 'dis-' .. i, name = name_of(tonumber(e.type)), role = e.role == 'ally' and 'Ally' or 'Pet',
                level = (e.role == 'ally' and c and c:level()) and ('lvl %d'):format(c:level()) or '',
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
        local function type_of(e, prefix) return tonumber(tostring(e.current):match('^' .. prefix .. '%-(%d+)$')) end
        on('[id^=sp-]', function(e)
            local id = type_of(e, 'sp')
            if not id then return end
            local problem
            gear.emit('beastmaster.recruit', id, mode, function(_, err) problem = err end)
            msg = problem or ''
        end)
        on('[id^=mn-]', function(e)
            local id = type_of(e, 'mn')
            if id then env.set_base_scale(id, env.base_scale(id) - 0.05) end
        end)
        on('[id^=pl-]', function(e)
            local id = type_of(e, 'pl')
            if id then env.set_base_scale(id, env.base_scale(id) + 0.05) end
        end)
        on('[id^=dis-]', function(e)
            local i = tonumber(tostring(e.current):match('^dis%-(%d+)$'))
            if i then env.dismiss(i) end
            msg = ''
        end)
        on('#mode-ally', function() mode = 'ally' end)
        on('#mode-pet', function() mode = 'pet' end)
        on('#dismiss-all', function() env.dismiss_all(); msg = '' end)
    end

    local function same(a, b)
        if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
        return gear.json.encode(a) == gear.json.encode(b)
    end

    local function draw()
        if not doc then load_doc() end
        if not doc then return end
        local now = gear.time()
        if now >= refresh_at or not next(last) then
            refresh_at = now + 0.15
            local m = snapshot()
            for k, v in pairs(m) do
                if not same(v, last[k]) then doc.model[k] = v; last[k] = v end
            end
        end
        if shown then doc:draw({layer = 'hud'}) end
    end

    return {draw = draw, toggle = function() shown = not shown; refresh_at = 0 end, open = function(on) shown = on ~= false; refresh_at = 0 end}
end

return M
