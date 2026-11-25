-- The Beastmaster window: every animal of the game (a scrolling list), taken along as an ally or a pet, with its base size changed per
-- species, and the animals that follow now, each with its orders (a drop-down as the party window's behaviours: Aggressive, Defensive, Passive,
-- Wait here; a pet Follow or Wait here), To me and Dismiss. RmlUi (ui/beasts.rml) with the shared theme; every button is a stop for the controller.
local M = {}

function M.new(env)
    local ui = gear.ui
    local shown = false
    local mode = 'ally'                 -- what a click on an animal makes
    local doc, last, msg, refresh_at = nil, {}, '', 0
    local q = ''                        -- the filter text
    local kb = gear.kit.osk and gear.kit.osk{}      -- the on-screen keyboard (gear.kit.osk)
    local function set_q(t)
        q = t:sub(1, 30)
        if doc then doc.model.q_text = q; last.q_text = q end
    end
    local function open_osk(on)
        if not kb then return end
        if on == false then kb:close() return end
        if on == true and kb:is_open() then return end
        kb:toggle{title = 'Filter', text = q, max = 30, on_change = set_q, get = function() return q end}
    end
    local lookup = gear.lookup
    local core = require('core')
    local open_dd = ''                  -- the open drop-down: 'ord-<i>' (one animal), 'oall' (all of them), or ''
    local pop_rect                      -- the open list's box last frame (its height decides whether it opens above its button)
    local ui_state = ui.state
    -- the orders in a drop-down: the first entry (0) is the default of the Mods screen
    local function order_list(role) return role == 'pet' and core.PET_ORDERS or core.ORDERS end
    local function order_options(prefix, role, current)
        local list = {{id = prefix .. '-0', label = 'Default', on = current == nil}}
        for k, o in ipairs(order_list(role)) do
            list[#list + 1] = {id = prefix .. '-' .. k, label = core.order_label(role, o), on = current == o}
        end
        return list
    end

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
        local m = {open = shown, title = 'Beastmaster', msg = msg, all_order = 'Default', dd = '', species = {}, followers = {}, mode_ally = mode == 'ally', mode_pet = mode == 'pet'}
        m.ally_text = ('%d of %d'):format(env.count('ally'), env.limit('ally'))
        m.pet_text = ('%d of %d'):format(env.count('pet'), env.limit('pet'))
        m.mode_text = mode == 'ally' and 'a fighting ally' or 'a pet'
        m.q_text = q
        m.none = false
        if shown then
            -- every animal with its name (two of the same name get (2), (3)), then the ones the filter keeps, the best match first:
            -- a forgiving search (words in any order, a beginning is enough, one typo is forgiven) over the name and the family
            local used, rows = {}, {}
            local query = lookup.words(q)
            for n, sp in ipairs(ordered) do
                local label = name_of(sp.type, sp.family)
                used[label] = (used[label] or 0) + 1
                local score = 0
                if #query > 0 then
                    score = lookup.score(query, lookup.words(label .. ' ' .. sp.family:gsub('_', ' ') .. ' ' .. tostring(sp.type)))
                end
                if score then
                    rows[#rows + 1] = {n = n, score = score, row = {
                        id = 'sp-' .. sp.type, minus = 'mn-' .. sp.type, plus = 'pl-' .. sp.type,
                        name = used[label] > 1 and ('%s (%d)'):format(label, used[label]) or label,
                        scale = ('%d%%'):format(math.floor(env.base_scale(sp.type) * 100 + 0.5)),
                    }}
                end
            end
            if #query > 0 then
                table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.n < b.n end)
            end
            for _, r in ipairs(rows) do m.species[#m.species + 1] = r.row end
            m.none = #rows == 0
        end
        m.dd = open_dd
        m.pop = {open = false, left = '0dp', top = '0dp', width = '150dp', options = {{id = '', label = '', on = false}}}
        local lists, shared, mixed = {}, nil, false
        for i, e in ipairs(env.followers()) do
            local c = env.object_of(e)
            local hp = c and c:hp() or 0
            local mx = c and c:max_hp() or 1
            m.followers[#m.followers + 1] = {
                id = 'dis-' .. i, name = name_of(tonumber(e.type)), role = e.role == 'ally' and 'Ally' or 'Pet',
                level = (e.role == 'ally' and c and c:level()) and ('lvl %d'):format(c:level()) or '',
                hp = e.role == 'ally' and ('%d%%'):format(math.floor(100 * hp / math.max(1, mx))) or '0%', show_hp = e.role == 'ally',
                id_ord = 'ord-' .. i, id_me = 'me-' .. i, ord_dd = 'ord-' .. i,
                order = e.order and core.order_label(e.role, env.order_of(e)) or 'Default',
                tip_order = e.role == 'ally' and 'What this ally does: fight what comes near you, only what comes close, only follow, or wait where it stands'
                    or 'A pet follows you or waits where it stands',
            }
            lists['ord-' .. i] = {button = '#ord-' .. i, options = order_options('op-' .. i, e.role, e.order)}
            local own = e.order or false
            if shared == nil then shared = own elseif shared ~= own then mixed = true end
        end
        m.has_followers = #m.followers > 0
        m.all_order = mixed and 'Mixed' or (shared and core.ORDER_LABEL[shared] or 'Default')
        lists.oall = {button = '#oall', options = order_options('opall', 'ally', (not mixed and shared) or nil)}
        -- the list of the open drop-down, under its button (above it when it would reach past the screen's bottom)
        local open = lists[open_dd]
        if open and doc then
            local b, o = doc:query(open.button), doc:query('#beasts-origin')
            local br, orr = b and b:exists() and b:rect(), o and o:rect()
            if br and orr then
                local pr = pop_rect or {h = #open.options * 30 + 8}
                local top = br.y + br.h
                local st = ui_state()
                if top + pr.h > (st.screen_bottom or 768) - 4 and br.y - pr.h >= (st.screen_top or 0) then top = br.y - pr.h end
                -- as wide as its button, or as its longest entry (an absolute box does not grow with its text in RmlUi)
                local chars = 0
                for _, opt in ipairs(open.options) do chars = math.max(chars, #opt.label) end
                m.pop = {open = true, left = ('%ddp'):format(math.floor(br.x - orr.x)), top = ('%ddp'):format(math.floor(top - orr.y)),
                    width = ('%ddp'):format(math.floor(math.max(br.w, chars * 7.5 + 28))), options = open.options}
            end
        end
        return m
    end

    local function load_doc()
        doc = ui.rml.load('ui/beasts.rml', {dp = true, model = snapshot(), on_change = function(_, model)
            local t = tostring(model.q_text or '')
            if t ~= q then q = t; last.q_text = t end
        end})
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
        if kb then kb:attach(doc, {field = '#search', button = '#kbd-q', open = function() open_osk(true) end}) end   -- (the button shows only while the pad is the input)
        on('#clear-q', function() set_q('') end)
        on('#mode-ally', function() mode = 'ally' end)
        on('#mode-pet', function() mode = 'pet' end)
        on('#dismiss-all', function() env.dismiss_all(); msg = ''; open_dd = '' end)
        on('[id^=ord-]', function(e)
            local id = tostring(e.current)
            open_dd = open_dd == id and '' or id
        end)
        on('#oall', function() open_dd = open_dd == 'oall' and '' or 'oall' end)
        on('#beasts-ddshade', function() open_dd = '' end)
        on('[id^=me-]', function(e)
            local i = tonumber(tostring(e.current):match('^me%-(%d+)$'))
            if i then env.bring(i) end
        end)
        on('#bring-all', function() env.bring_all() end)
        on('.dd-list .opt', function(e)
            local id = tostring(e.current)
            local i, k = id:match('^op%-(%d+)%-(%d+)$')
            local followers = env.followers()
            if i then
                local f = followers[tonumber(i)]
                if f then env.set_order(tonumber(i), tonumber(k) > 0 and order_list(f.role)[tonumber(k)] or nil) end
            else
                k = id:match('^opall%-(%d+)$')
                if k then
                    k = tonumber(k)
                    -- every ally gets the order; a pet the one it can take (Wait here stays, any other: follow)
                    for j, f in ipairs(followers) do
                        local o = k > 0 and core.ORDERS[k] or nil
                        if f.role == 'pet' and o then o = core.order_of('pet', o) end
                        env.set_order(j, o)
                    end
                end
            end
            open_dd = ''
        end)
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
        if kb then
            if not shown then kb:close() end
            kb:draw()
        end
        local pe = shown and last.pop and last.pop.open and doc:query('#beasts-pop')
        pop_rect = pe and pe:exists() and pe:rect() or nil
    end

    -- For the self test: sets the filter text and returns the names that remain.
    local function set_filter(t)
        q = tostring(t or '')
        if doc then doc.model.q_text = q; last.q_text = q end
        local was = shown
        shown = true
        local names_ = {}
        for _, r in ipairs(snapshot().species) do names_[#names_ + 1] = r.name end
        shown = was
        return names_
    end

    return {draw = draw, set_filter = set_filter, set_osk = function(on) open_osk(on ~= false) end, toggle = function() shown = not shown; open_dd = ''; refresh_at = 0 end,
        open = function(on) shown = on ~= false; open_dd = ''; refresh_at = 0 end,
        open_dropdown = function(id) open_dd = id or ''; refresh_at = 0 end}
end

return M
