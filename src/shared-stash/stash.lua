-- The shared stash's file: stash.json (and stash.bak.json, the version before the last write) in this mod's folder.
--
-- {"version": 1, "next_uid": N, "items": [entry...], "recent": [entry...]}
-- entry = {uid, name, quality, category, w, h, class, from, time, data}: `data` is the item as hex (gear.inv.export).
-- `recent` holds the last withdrawn items so a withdrawal can be undone after loading an older savegame.
--
-- Writes go through gear.save, which replaces the file atomically; the previous file is copied to stash.bak.json
-- first. A file that cannot be read (and has no readable backup) or that a newer version of the mod wrote puts the
-- stash in read-only mode: nothing is ever overwritten that was not understood.
local M = {}

local FILE, BACKUP = 'stash.json', 'stash.bak.json'
local VERSION = 1
local LIMIT = 1000000   -- gear.save refuses more than 1 MB

local state = {items = {}, recent = {}, next_uid = 1}
M.problem = nil         -- text when the stash cannot be used (shown in the panel); transfers are off
M.note = nil            -- text about what load() did (restored from the backup ...)

local function empty(t) return type(t) ~= 'table' or next(t) == nil end

local function parse(text)
    local v = gear.json.decode(text)
    if type(v) ~= 'table' then return nil, 'not a stash file' end
    if type(v.version) ~= 'number' then return nil, 'no version' end
    if v.version > VERSION then return nil, 'written by a newer version of the mod (' .. v.version .. ')' end
    local items, recent = {}, {}
    local next_uid = tonumber(v.next_uid) or 1
    for _, list in ipairs({{v.items, items}, {v.recent, recent}}) do
        if not empty(list[1]) then
            for _, e in ipairs(list[1]) do
                if type(e) ~= 'table' or type(e.data) ~= 'string' or type(e.uid) ~= 'number' then
                    return nil, 'an entry is damaged'
                end
                list[2][#list[2] + 1] = e
                if e.uid >= next_uid then next_uid = e.uid + 1 end
            end
        end
    end
    return {items = items, recent = recent, next_uid = next_uid}
end

function M.load()
    M.problem, M.note = nil, nil
    state = {items = {}, recent = {}, next_uid = 1}
    local text = gear.read(FILE)
    if not text then
        local btext = gear.read(BACKUP)
        if btext then
            local s = parse(btext)
            if s then
                state = s
                M.note = 'stash.json was missing: using stash.bak.json'
            else
                M.problem = 'stash.json is missing and stash.bak.json cannot be read'
            end
        end
        return
    end
    local s, why = parse(text)
    if s then state = s return end
    local btext = gear.read(BACKUP)
    local b = btext and parse(btext)
    if b then
        state = b
        M.note = 'stash.json cannot be read (' .. why .. '): using stash.bak.json; the next change replaces stash.json'
    else
        M.problem = 'stash.json cannot be read (' .. why .. '); nothing is changed until it is fixed or removed'
    end
end

local function save()
    if M.problem then return nil, M.problem end
    local text = gear.json.encode({
        version = VERSION, next_uid = state.next_uid, items = state.items, recent = state.recent,
    })
    if #text > LIMIT then return nil, 'the stash file would be larger than 1 MB' end
    local previous = gear.read(FILE)
    if previous and parse(previous) then gear.save(BACKUP, previous) end
    local ok, err = gear.save(FILE, text)
    if not ok then return nil, 'cannot write stash.json: ' .. tostring(err) end
    return true
end

function M.items() return state.items end
function M.recent() return state.recent end

local function index_of(list, uid)
    for i, e in ipairs(list) do if e.uid == uid then return i end end
end

-- Adds an entry (uid is assigned) and writes the file; nil, message if it could not be written (nothing changed).
function M.add(entry, max_items)
    if M.problem then return nil, M.problem end
    if #state.items >= max_items then return nil, 'the stash is full (' .. max_items .. ' items)' end
    entry.uid = state.next_uid
    state.next_uid = state.next_uid + 1
    state.items[#state.items + 1] = entry
    local ok, err = save()
    if not ok then
        state.items[#state.items] = nil
        return nil, err
    end
    return entry
end

-- Removes an entry without a trace (a deposit that did not work out).
function M.discard(uid)
    local i = index_of(state.items, uid)
    if not i then return true end
    local e = table.remove(state.items, i)
    local ok, err = save()
    if not ok then table.insert(state.items, i, e) return nil, err end
    return true
end

-- Moves an entry to `recent` (a withdrawal) and writes the file; nil, message and no change if that fails.
function M.take(uid, keep_recent)
    local i = index_of(state.items, uid)
    if not i then return nil, 'no such entry' end
    local e = table.remove(state.items, i)
    local old_recent = state.recent
    local copy = {}
    for k, v in pairs(e) do copy[k] = v end
    copy.withdrawn = os.time()
    local recent = {copy}
    for _, r in ipairs(old_recent) do
        if #recent >= keep_recent then break end
        recent[#recent + 1] = r
    end
    state.recent = recent
    local ok, err = save()
    if not ok then
        table.insert(state.items, i, e)
        state.recent = old_recent
        return nil, err
    end
    return e
end

-- Moves an entry from `recent` back into the stash.
function M.restore(uid, max_items)
    local i = index_of(state.recent, uid)
    if not i then return nil, 'no such entry' end
    if #state.items >= max_items then return nil, 'the stash is full (' .. max_items .. ' items)' end
    local e = table.remove(state.recent, i)
    e.withdrawn = nil
    state.items[#state.items + 1] = e
    local ok, err = save()
    if not ok then
        state.items[#state.items] = nil
        table.insert(state.recent, i, e)
        return nil, err
    end
    return e
end

return M
