-- The realm picker: a page of this mod in the mod manager (F11, or LT+LB on a pad: Mods > Realm > More). It lists the
-- realms and makes one the online play server: the next time Closed or Open Internet is opened in the multiplayer
-- menu, register and login go to that realm (LAN is not touched). It binds no key and uses only Gear widgets, so the
-- pad and the mouse work the same.
--
-- Add realms from a mod with gear.realm.add{id = ..., name = ..., host = ..., port = ...}, or edit mods\gear_realms.json:
--     {"version": 1, "realms": [{"id": "private", "name": "Private realm", "host": "realm.example.com", "port": 7066}]}

local ui = gear.ui
local C = ui.COLORS

local message
local function note(text) message = text end
local dd_open = false

-- The page is ui/page.rml (the game theme): the realm button steps through the realms.
gear.mods.page_rml('ui/page.rml', {
    model = {realm = '', host = '', message = '', dd_open = false, realms = {}},
    on_load = function(doc)
        doc:on('#realm', 'click', function()
            dd_open = not dd_open
        end)
        doc:on('.realm-ddlist .opt', 'click', function(e)
            local i = tonumber(tostring(e.current):match('^realm%-([%d]+)$'))
            local realms = gear.realm.list()
            local pick = i and realms[i]
            dd_open = false
            if not pick then return end
            local ok, why = gear.realm.use(pick.id)
            note(ok and ('Realm: ' .. pick.name) or ('Not changed: ' .. tostring(why)))
        end)
    end,
    update = function(doc)
        local current = gear.realm.current()
        local r
        for _, x in ipairs(gear.realm.list()) do if x.id == current.id then r = x end end
        r = r or current
        local host = (r.host and r.host ~= '') and r.host or '(from Settings.cfg)'
        local m = doc.model
        m.dd_open = dd_open
        m.realms = {}
        local realms = gear.realm.list()
        for i, realm in ipairs(realms) do m.realms[i] = {id = 'realm-' .. i, label = realm.name, on = realm.id == r.id} end
        if m.realm ~= r.name then m.realm = r.name end
        local h = host .. (r.port and (':' .. r.port) or '')
        if m.host ~= h then m.host = h end
        if m.message ~= (message or '') then m.message = message or '' end
    end,
})
