-- Forgiving search for the editor's lookups (items, creatures): several words in any order, upper or lower case, accents
-- ignored (ä = a, ß = ss), a word may be a beginning ("swo" finds Sword) or sit inside another, one typo is forgiven
-- ("scwert" finds Schwert) and the letters of a word may be spread out ("drgn" finds Dragon). Results are ranked.

local M = {}

local FOLD = {
    ['ä'] = 'a', ['Ä'] = 'a', ['ö'] = 'o', ['Ö'] = 'o', ['ü'] = 'u', ['Ü'] = 'u', ['ß'] = 'ss',
    ['à'] = 'a', ['á'] = 'a', ['â'] = 'a', ['ã'] = 'a', ['å'] = 'a', ['è'] = 'e', ['é'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
    ['ì'] = 'i', ['í'] = 'i', ['î'] = 'i', ['ï'] = 'i', ['ò'] = 'o', ['ó'] = 'o', ['ô'] = 'o', ['õ'] = 'o',
    ['ù'] = 'u', ['ú'] = 'u', ['û'] = 'u', ['ñ'] = 'n', ['ç'] = 'c', ['ý'] = 'y',
    ['À'] = 'a', ['Á'] = 'a', ['Â'] = 'a', ['È'] = 'e', ['É'] = 'e', ['Ê'] = 'e', ['Ì'] = 'i', ['Í'] = 'i',
    ['Ò'] = 'o', ['Ó'] = 'o', ['Ù'] = 'u', ['Ú'] = 'u', ['Ñ'] = 'n', ['Ç'] = 'c',
}

-- The words of a text: lower case, accents folded, letters and digits only.
function M.words(text)
    local s = tostring(text or '')
    s = s:gsub('[\195][\128-\191]', function(c) return FOLD[c] or c end):lower()
    local list = {}
    for w in s:gmatch('[%w]+') do list[#list + 1] = w end
    return list
end

-- Edit distance of a and b, but at most `limit` + 1 (cheap exit).
local function distance(a, b, limit)
    local la, lb = #a, #b
    if math.abs(la - lb) > limit then return limit + 1 end
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = {[0] = i}
        local best = cur[0]
        for j = 1, lb do
            local cost = a:byte(i) == b:byte(j) and 0 or 1
            local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            cur[j] = v
            if v < best then best = v end
        end
        if best > limit then return limit + 1 end
        prev = cur
    end
    return prev[lb]
end

local function subsequence(q, w)
    local at = 1
    for i = 1, #q do
        local found = w:find(q:sub(i, i), at, true)
        if not found then return false end
        at = found + 1
    end
    return true
end

-- How well query word q matches text word w: 0 for not at all.
local function word_score(q, w)
    if w == q then return 100 end
    if w:sub(1, #q) == q then return 85 - math.min(20, #w - #q) end
    if w:find(q, 1, true) then return 60 end
    return 0
end

local function loose_score(q, w)
    if #q >= 4 then
        local d = math.min(distance(q, w, 1), distance(q, w:sub(1, #q), 1))
        if d <= 1 then return 45 end
    end
    if #q >= 4 and #w <= #q * 2 and subsequence(q, w) then return 25 end
    return 0
end

-- `query` is a text or the list from M.words; `words` the list of a text. Returns a score (higher is better) or nil.
function M.score(query, words)
    local qs = type(query) == 'table' and query or M.words(query)
    if #qs == 0 then return 0 end
    local total = 0
    for _, q in ipairs(qs) do
        local best = 0
        for _, w in ipairs(words) do
            local s = word_score(q, w)
            if s > best then best = s end
        end
        if best == 0 then
            for _, w in ipairs(words) do
                local s = loose_score(q, w)
                if s > best then best = s end
            end
        end
        if best == 0 then return nil end
        total = total + best
    end
    return total / #qs
end

-- Ranks entries (each with a `words` list from M.words) for the query: best first, ties by shorter text then order.
-- Returns at most `limit` entries.
function M.rank(entries, query, limit)
    local qs = M.words(query)
    local out = {}
    for i, e in ipairs(entries) do
        local s = M.score(qs, e.words)
        if s then out[#out + 1] = {entry = e, score = s, order = i} end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        local la, lb = #a.entry.words, #b.entry.words
        if la ~= lb then return la < lb end
        return a.order < b.order
    end)
    local list = {}
    for i = 1, math.min(#out, limit or #out) do list[i] = out[i].entry end
    return list
end

return M
