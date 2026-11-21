-- One bounty (or quest) as a row of the RmlUi board / quests window: ready-made strings and the bar's width.
local M = {}

-- `b` has title, text, level, target, n, done, reward; `extra.state` is the text at the right of the title.
function M.row(b, extra)
    local done = b.done == true
    local n = math.min(b.n or 0, b.target)
    local frac = b.target > 0 and n / b.target or 0
    return {
        title = tostring(b.title), state = extra.state or '', done = done,
        text = (b.text or '') .. (b.level and b.level > 1 and (' (level ' .. b.level .. '+)') or ''),
        pct = ('%d%%'):format(math.floor(frac * 100)), prog = ('%d / %d'):format(n, b.target),
        reward = 'Reward: ' .. tostring(b.reward or '?'),
    }
end

return M
