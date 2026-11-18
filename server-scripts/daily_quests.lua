-- Daily and weekly quests: every day and every Monday the same few quests are up for everybody ("kill 12 orcs today"), each hero
-- works on them on their own, finishing a quest pays gold and/or an item, finishing all quests of a day (week) is one step of
-- a streak, and every few steps in a row the streak pays a bonus. Copy into the server's scripts folder (default ./scripts).
--
--   !quests                      today's and this week's quests, your progress and your streaks (chat)
--   /mods/daily_quests/          the public dashboard page (character names only)
--   /mods/daily_quests/state     the same as JSON (public, with WebUi:PublicApi=true also under /public/mods/...)
--   /mods/daily_quests/config    the admin page: the configuration in force, where each field comes from, errors
--
-- Sacred Gear clients with the "bounty" mod (src/bounty of sacred-gear-mods, panel on Ctrl+Shift+D) show the quests, the progress
-- and the streaks over the custom net channel "bounty:quests" (server_only).
--
-- The quests are drawn from the pool with a seed made of the date and the seed word, so they are stable and a restart or a
-- reload changes nothing. The date is the server's, moved by `utc_offset_minutes` (the reset happens at midnight of that clock).
-- Everything lives in this mod's own storage (script-data/daily_quests.json): the quests of today, each hero's progress and
-- streaks, and the configuration (key "config": daily/weekly slots and pool, the streak bonuses, announce, seed, utc_offset_minutes;
-- the tables below seed it on the first run, then it is data: POST /api/mod-store {"mod":"daily_quests","set":{"config":{...}}}
-- (admin), applied within 2 seconds, no reload; a field that does not validate is ignored with a log line and keeps its default).
--
-- Protocol (channel "bounty:quests"). The client may send anything (e.g. { req = 1 }) to ask for its state; the server answers with,
-- and pushes on every change of the quests or of that hero's progress:
--   { v = 1, daily = { key, left, done, complete, quests = { { id, title, text, target, n, done, claimed, reward, level } } },
--     weekly = { same }, streak = { daily = { count, best, today, every, next_in, bonus }, weekly = { ... } }, pending = 0, totals = { daily, weekly, quests } }
-- `left` is the seconds until the next reset (relative, so clocks need not agree); `n` is the hero's own progress.
server.describe("Daily and weekly quests with a streak bonus: kill N creatures for gold or items, a public dashboard and a panel for Sacred Gear clients.")

-- ---- configuration as data (the same scheme as bounty_board.lua) ---------------------------------------------------------------
local CONFIG, CFG = {}, { loaded = server.time(), reason = "start", rev = 0, errors = {}, source = {} }
local CFG_DEFAULTS, CFG_RULES

local function cfg_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = cfg_copy(x) end
  return out
end

local function cfg_log(text)
  if #CFG.errors < 20 then CFG.errors[#CFG.errors + 1] = text end
  server.log("config: " .. text)
end

local function r_num(lo, hi, whole)
  return function(v)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi then error("needs a number from " .. lo .. " to " .. hi, 0) end
    return whole and math.floor(v) or v
  end
end
local function r_bool(v) if type(v) ~= "boolean" then error("needs true or false", 0) end return v end
local function r_text(v) if type(v) ~= "string" or v == "" or #v > 60 then error("needs a short text", 0) end return v end
local function r_list(item, min)
  return function(v)
    if type(v) ~= "table" then error("needs a list", 0) end
    local out = {}
    for i, x in ipairs(v) do
      local ok, clean = pcall(item, x)
      if ok and clean ~= nil then out[#out + 1] = clean else cfg_log("item #" .. i .. " refused: " .. tostring(ok and "invalid" or clean)) end
    end
    if #out < (min or 0) then error("needs at least " .. (min or 0) .. " valid item(s)", 0) end
    return out
  end
end

local function cfg_rev() local ok, v = pcall(server.load, "config_rev", 0); return ok and tonumber(v) or 0 end

local function config_read()
  CFG.errors, CFG.source = {}, {}
  local ok, stored = pcall(server.load, "config", nil)
  if not ok or type(stored) ~= "table" then
    if ok and stored ~= nil then cfg_log("the storage key config is not a table: defaults used") end
    stored = {}
  end
  for key, rule in pairs(CFG_RULES) do
    local value
    if stored[key] ~= nil then
      local good, result = pcall(rule, stored[key])
      if good and result ~= nil then value, CFG.source[key] = result, "storage"
      else cfg_log(key .. ": " .. tostring(good and "invalid" or result) .. " - default kept") end
    end
    if value == nil then value, CFG.source[key] = cfg_copy(CFG_DEFAULTS[key]), "default" end
    CONFIG[key] = value
  end
  for key in pairs(stored) do if CFG_RULES[key] == nil then cfg_log("unknown field " .. tostring(key) .. " ignored") end end
  CFG.rev = cfg_rev()
end

local function config_seed()
  local ok, seeded = pcall(server.load, "config_seeded", false)
  if ok and seeded == true then return end
  local has, stored = pcall(server.load, "config", nil)
  if has and stored == nil then pcall(server.save, "config", cfg_copy(CFG_DEFAULTS)) end
  pcall(server.save, "config_seeded", true)
end

local function config_start(defaults, rules, apply)
  CFG_DEFAULTS, CFG_RULES = defaults, rules
  local ok, life = pcall(server.load, "_lifecycle", nil)
  if ok and type(life) == "table" then CFG.reason = life.reason == "reload" and "reload" or "restart" end
  pcall(server.delete, "_lifecycle")
  config_seed()
  config_read()
  apply()
  server.every(2, function()
    if cfg_rev() == CFG.rev then return end
    config_read()
    CFG.applied = server.time()
    local good, err = pcall(apply)
    if not good then cfg_log("applying the new config failed: " .. tostring(err)) end
    server.log("config changed by an edit and applied")
  end)
end

local function config_unload(reason)
  pcall(server.save, "_lifecycle", { reason = reason, at = server.time() })
  pcall(server.flush)
end

local function cfg_stamp(t)
  t = math.floor(t)
  local z = math.floor(t / 86400) + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local day = doy - math.floor((153 * mp + 2) / 5) + 1
  local month = mp < 10 and mp + 3 or mp - 9
  local secs = t % 86400
  return string.format("%04d-%02d-%02d %02d:%02d:%02d UTC", yoe + era * 400 + (month <= 2 and 1 or 0), month, day,
    math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60)
end

server.page("config", function()
  local h, rows, names = server.html, {}, {}
  for key in pairs(CFG_RULES) do names[#names + 1] = key end
  table.sort(names)
  for _, key in ipairs(names) do
    local value = CONFIG[key]
    local text = tostring(value)
    if type(value) == "table" then
      local ok, json = pcall(server.json, value)
      text = ok and json or "(table)"
    end
    if #text > 3000 then text = text:sub(1, 3000) .. " ..." end
    rows[#rows + 1] = "<tr><td>" .. h(key) .. "</td><td>" .. h(CFG.source[key] or "default") .. "</td><td><code>" .. h(text) .. "</code></td></tr>"
  end
  local errors = {}
  for _, e in ipairs(CFG.errors) do errors[#errors + 1] = "<li>" .. h(e) .. "</li>" end
  return table.concat({
    '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>daily_quests configuration</title>',
    "<style>body{margin:0;font:14px/1.4 system-ui,sans-serif;background:#15110d;color:#efe6d6;padding:1rem 1.2rem}h1{font-size:1.2rem;color:#e0a944}",
    "table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #3b3025;padding:.3rem .5rem;text-align:left;vertical-align:top}",
    "code{white-space:pre-wrap;word-break:break-all}small{color:#a39683}.err{color:#ff9a8a}</style></head><body><h1>daily_quests: configuration</h1>",
    "<p>Revision ", tostring(CFG.rev), ". Loaded ", h(cfg_stamp(CFG.loaded)), ", last reload reason: <b>", h(CFG.reason), "</b>",
    CFG.applied and (", last live edit applied " .. h(cfg_stamp(CFG.applied))) or "", ".</p>",
    #errors > 0 and ("<p class='err'>Config errors (those fields use their defaults):</p><ul>" .. table.concat(errors) .. "</ul>") or "<p><small>No config errors.</small></p>",
    "<table><tr><th>field</th><th>from</th><th>active value</th></tr>", table.concat(rows), "</table>",
    "<p><small>Edit: POST /api/mod-store {\"mod\":\"daily_quests\",\"set\":{\"config\":{...}}} (admin); applied within 2 seconds, no reload needed. ",
    "Delete a field inside config to get its default back.</small></p></body></html>",
  })
end, { title = "daily_quests configuration" })

-- ---- configuration -----------------------------------------------------------------------------------------------------------

-- `pool` entries: id, title, names (words of the creature name; needs --game-dir) or types (creature types), target (a number or
-- { min, max }, drawn from the day's seed), reward = { gold = coins at hero level 10 (scaled by the hero's level), item = { quality = .. } }.
local DEFAULTS = {
  announce = true,           -- broadcast when new quests are up and when a hero finishes a set
  seed = "sacred",           -- changes every day's draw
  utc_offset_minutes = 0,    -- the day changes at midnight of the server clock moved by this
  history = 10,              -- completions kept for the dashboard
  max_players = 5000,        -- heroes remembered (more can still play, their progress is just not kept)
  daily_slots = 3,
  weekly_slots = 2,
  daily_pool = {
    { id = "orcs", title = "Orc patrol", names = { "orc" }, target = { 8, 16 }, reward = { gold = 400 } },
    { id = "undead", title = "Grave walk", names = { "skeleton", "zombie", "ghoul" }, target = { 10, 20 }, reward = { gold = 500 } },
    { id = "spiders", title = "Cobwebs", names = { "spider" }, target = { 8, 14 }, reward = { gold = 350 } },
    { id = "brigands", title = "Roadside trouble", names = { "brigand", "thief", "bandit" }, target = { 8, 15 }, reward = { gold = 450 } },
    { id = "beasts", title = "Wild beasts", names = { "wolf", "bear", "boar" }, target = { 8, 15 }, reward = { gold = 350 } },
    { id = "any", title = "Monster hunt", names = {}, target = { 30, 60 }, reward = { gold = 600 } },
  },
  weekly_pool = {
    { id = "orcs", title = "Orc campaign", names = { "orc" }, target = { 60, 100 }, reward = { gold = 3000, item = { quality = 3 } } },
    { id = "undead", title = "Cleanse the crypts", names = { "skeleton", "zombie", "ghoul" }, target = { 80, 120 }, reward = { gold = 3500 } },
    { id = "spiders", title = "Spider season", names = { "spider" }, target = { 50, 90 }, reward = { gold = 2500 } },
    { id = "any", title = "Relentless", names = {}, target = { 250, 400 }, reward = { gold = 4000, item = { quality = 3 } } },
  },
  -- Every `every` steps (days / weeks) in a row: gold + gold_step for each bonus after the first (at most max_steps of them), and
  -- an item (nil: none). A step is a day (week) in which the hero finished all quests.
  daily_streak = { every = 3, gold = 600, gold_step = 200, max_steps = 10, item = { quality = 3 } },
  weekly_streak = { every = 2, gold = 3000, gold_step = 1000, max_steps = 10, item = { quality = 5 } },
}

local function pool_entry(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" or not (def.names or def.types) or def.target == nil then
    error("needs an id, names or types and a target", 0)
  end
  if type(def.target) ~= "number" and not (type(def.target) == "table" and tonumber(def.target[1])) then error("target is a number or { min, max }", 0) end
  return def
end

local function streak_rule(v)
  if type(v) ~= "table" then error("needs a table { every, gold, gold_step, max_steps, item }", 0) end
  local out = {
    every = math.floor(tonumber(v.every) or 3), gold = math.max(0, math.floor(tonumber(v.gold) or 0)),
    gold_step = math.max(0, math.floor(tonumber(v.gold_step) or 0)), max_steps = math.max(1, math.floor(tonumber(v.max_steps) or 10)),
    item = type(v.item) == "table" and v.item or nil, off = v.off == true,
  }
  if out.every < 1 or out.every > 365 then error("every is a number from 1 to 365", 0) end
  return out
end

local RULES = {
  announce = r_bool, seed = r_text, utc_offset_minutes = r_num(-720, 840, true), history = r_num(0, 200, true),
  max_players = r_num(1, 100000, true), daily_slots = r_num(0, 12, true), weekly_slots = r_num(0, 12, true),
  daily_pool = r_list(pool_entry, 1), weekly_pool = r_list(pool_entry, 1), daily_streak = streak_rule, weekly_streak = streak_rule,
}

config_start(DEFAULTS, RULES, function() end)

-- ---- helpers -----------------------------------------------------------------------------------------------------------------

local PREFIX = "[Quests] "
local NOW = server.time
local PERIODS = { "daily", "weekly" }

local function say(text) if CONFIG.announce then pcall(server.broadcast, PREFIX .. text) end end

local function duration_text(seconds)
  seconds = math.max(0, math.floor(seconds + 0.5))
  if seconds >= 86400 then return string.format("%dd %02dh", math.floor(seconds / 86400), math.floor((seconds % 86400) / 3600)) end
  if seconds >= 3600 then return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)) end
  if seconds >= 60 then return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60) end
  return seconds .. "s"
end

local function lower_of(v) return type(v) == "string" and v ~= "" and v:lower() or nil end

local function copy_list(list, convert)
  if type(list) ~= "table" then return nil end
  local out = {}
  for _, v in ipairs(list) do
    if convert then v = convert(v) end
    if v ~= nil then out[#out + 1] = v end
  end
  return #out > 0 and out or nil
end

-- Gold of a quest for a hero of `level`: the pool's amount is for level 10, level 1 gets 60 %, level 50 gets 5 times as much.
local function gold_for(base, level)
  if (base or 0) <= 0 then return 0 end
  return math.max(10, math.floor(base * (0.5 + 0.1 * math.max(1, level or 10)) / 1.5 / 10 + 0.5) * 10)
end

local function reward_text(gold, item)
  local parts = {}
  if (gold or 0) > 0 then parts[#parts + 1] = gold .. " gold" end
  if item then parts[#parts + 1] = "an item" end
  return #parts > 0 and table.concat(parts, " and ") or "glory"
end

-- ---- the calendar: the server clock moved by the configured offset, pure arithmetic ---------------------------------------------

local function local_time() return NOW() + CONFIG.utc_offset_minutes * 60 end
local function day_number(t) return math.floor((t or local_time()) / 86400) end
local function week_number(day) return math.floor((day + 3) / 7) end          -- 1970-01-01 was a Thursday; weeks start on Monday
local function key_of(period) local d = day_number() return period == "weekly" and week_number(d) or d end
local function seconds_left(period)
  local t = local_time()
  local left = 86400 - t % 86400
  if period == "weekly" then left = left + (6 - (day_number(t) + 3) % 7) * 86400 end
  return left
end

-- Park-Miller from a text: the same date and seed word always give the same numbers.
local function rng_for(text)
  local h = 7
  for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
  local s = h % 2147483646 + 1
  return function(lo, hi)
    s = s * 48271 % 2147483647
    return lo + math.floor((s - 1) / 2147483646 * (hi - lo + 1))
  end
end

local function draw_target(rng, spec)
  if type(spec) == "table" then
    local lo = math.max(1, math.floor(tonumber(spec[1]) or 1))
    local hi = math.max(lo, math.floor(tonumber(spec[2]) or lo))
    return lo == hi and lo or rng(lo, hi)
  end
  return math.max(1, math.floor(tonumber(spec) or 10))
end

-- ---- state -------------------------------------------------------------------------------------------------------------------
-- state.current[period] = { key, quests = { { id, def, title, names, types, target, gold, item } } } the same for everybody;
-- state.players[uid] = { name, daily = { key, n = { [quest id] = count }, done = { [quest id] = true }, complete }, weekly = ..,
--   streak = { daily = { count, best, last }, weekly = ... }, totals = { daily, weekly, quests } }

local function load_state()
  local ok, value = pcall(server.load, "state", nil)
  if not ok or type(value) ~= "table" then value = {} end
  value.current = type(value.current) == "table" and value.current or {}
  value.players = type(value.players) == "table" and value.players or {}
  value.history = type(value.history) == "table" and value.history or {}
  return value
end

local state = load_state()
local dirty = false

local function save_state()
  local ok, err = pcall(server.save, "state", state)
  if ok then dirty = false else server.log("cannot save the quests: " .. tostring(err)) end
end

local function hero_of(player)
  local p = state.players[player.uid]
  if not p then
    local n = 0
    for _ in pairs(state.players) do n = n + 1 end
    if n >= CONFIG.max_players then return nil end
    p = { name = player.character, daily = { n = {}, done = {} }, weekly = { n = {}, done = {} },
      streak = { daily = { count = 0, best = 0, last = 0 }, weekly = { count = 0, best = 0, last = 0 } },
      totals = { daily = 0, weekly = 0, quests = 0 } }
    state.players[player.uid] = p
  end
  p.name = player.character or p.name
  return p
end

-- A period that moved on: the hero's counters of the old one go, a streak that missed a period is over.
local function sync_hero(p, period)
  local cur = state.current[period]
  if not cur then return end
  local h, st = p[period], p.streak[period]
  if h.key ~= cur.key then
    h.key, h.n, h.done, h.complete = cur.key, {}, {}, false
  end
  if st.count > 0 and st.last < cur.key - 1 then st.count = 0 end
end

local function generate(period)
  local key = key_of(period)
  local rng = rng_for(CONFIG.seed .. ":" .. period .. ":" .. key)
  local candidates = {}
  for _, def in ipairs(CONFIG[period .. "_pool"]) do candidates[#candidates + 1] = def end
  local slots = math.min(CONFIG[period .. "_slots"], #candidates)
  local quests = {}
  for _ = 1, slots do
    local def = table.remove(candidates, rng(1, #candidates))
    local reward = type(def.reward) == "table" and def.reward or {}
    local names = copy_list(def.names, lower_of)
    local target = draw_target(rng, def.target)
    quests[#quests + 1] = {
      id = period .. ":" .. key .. ":" .. tostring(def.id), def = tostring(def.id), title = tostring(def.title or def.id),
      names = names, types = copy_list(def.types, tonumber), target = target,
      gold = math.max(0, math.floor(tonumber(reward.gold) or 0)), item = type(reward.item) == "table" and reward.item or nil,
      text = "Defeat " .. target .. " " .. (names and (table.concat(names, "/") .. " ") or "") .. "creatures",
    }
  end
  state.current[period] = { key = key, quests = quests }
end

-- ---- net: the panel of the clients ---------------------------------------------------------------------------------------------

local channel = net and net.channel("bounty:quests", { server_only = true })

local function bonus_for(period, count, level)
  local s = CONFIG[period .. "_streak"]
  if s.off or count <= 0 or count % s.every ~= 0 then return nil end
  local step = math.min(count / s.every, s.max_steps)
  return { gold = gold_for(s.gold + s.gold_step * (step - 1), level), item = s.item, step = step }
end

local function payload_for(player)
  local p = hero_of(player)
  local out = { v = 1, pending = 0, streak = {}, totals = p and p.totals or { daily = 0, weekly = 0, quests = 0 } }
  for _, period in ipairs(PERIODS) do
    local cur = state.current[period] or { key = key_of(period), quests = {} }
    if p then sync_hero(p, period) end
    local h = p and p[period]
    local list, done = {}, 0
    for _, q in ipairs(cur.quests) do
      local d = h and h.done[q.id] or false
      if d then done = done + 1 end
      list[#list + 1] = { id = q.id, title = q.title, text = q.text, target = q.target, n = h and math.min(h.n[q.id] or 0, q.target) or 0,
        done = d, claimed = d, reward = reward_text(gold_for(q.gold, player.level), q.item) }
    end
    out[period] = { key = cur.key, left = seconds_left(period), quests = list, done = done, complete = h and h.complete or false }
    local st = p and p.streak[period] or { count = 0, best = 0, last = 0 }
    local s = CONFIG[period .. "_streak"]
    local nb = s.off and 0 or (s.every - st.count % s.every)
    local bonus = nb > 0 and bonus_for(period, st.count + nb, player.level)
    out.streak[period] = { count = st.count, best = st.best, today = st.last == cur.key, every = s.every, next_in = nb,
      bonus = bonus and reward_text(bonus.gold, bonus.item) or nil }
  end
  return out
end

local function push(player)
  if not channel or not player or not net.supports(player) then return end
  local ok, err = pcall(channel.send, channel, player, payload_for(player))
  if not ok then server.log("cannot push the quests: " .. tostring(err)) end
end

local function push_all()
  if not channel then return end
  for _, player in ipairs(server.players()) do push(player) end
end

-- Kills can come many per second: progress is pushed at most once a second per hero.
local push_due = {}
server.every(1, function()
  if next(push_due) == nil then return end
  local due = push_due
  push_due = {}
  for _, player in ipairs(server.players()) do
    if due[player.slot] then push(player) end
  end
end)

if channel then channel:on(function(player) push(player) end) end

-- ---- rotation ------------------------------------------------------------------------------------------------------------------

local function remember(entry)
  table.insert(state.history, 1, entry)
  while #state.history > CONFIG.history do table.remove(state.history) end
end

local function rotate()
  local changed = false
  for _, period in ipairs(PERIODS) do
    local cur = state.current[period]
    if not cur or cur.key ~= key_of(period) or (#cur.quests == 0 and CONFIG[period .. "_slots"] > 0) then
      generate(period)
      changed = true
      if #state.current[period].quests > 0 then
        say("New " .. period .. " quests are up: " .. #state.current[period].quests .. " quests. Type !quests.")
      end
    end
  end
  return changed
end

local function tick()
  local changed = rotate()
  if changed then save_state(); push_all() elseif dirty then save_state() end
end

server.on("unload", function(reason)
  pcall(save_state)
  config_unload(reason)
end)
server.every(5, function() local ok, err = pcall(tick); if not ok then server.log("tick: " .. tostring(err)) end end)
server.on("start", function() local ok, err = pcall(tick); if not ok then server.log("start: " .. tostring(err)) end end)

-- ---- kills and rewards -------------------------------------------------------------------------------------------------------

local function counts(q, monster)
  if q.names and monster.name then
    local name = monster.name:lower()
    for _, word in ipairs(q.names) do if name:find(word, 1, true) then return true end end
  end
  if q.types and monster.type then
    for _, t in ipairs(q.types) do if t == monster.type then return true end end
  end
  return not q.names and not q.types      -- no names and no types: any monster
end

local function pay(player, gold, item)
  if (gold or 0) > 0 then
    local ok, drop, err = pcall(server.drop_gold, player, gold)
    if not ok or not drop then server.log("no gold for " .. tostring(player.character) .. ": " .. tostring(ok and err or drop)) end
  end
  if item then
    local ok, got, err = pcall(server.drop_item, player, item)
    if not ok or not got then server.log("no item for " .. tostring(player.character) .. ": " .. tostring(ok and err or got)) end
  end
end

-- Every quest of the hero's day / week is done: one more step of the streak (once per period), and the bonus when it is due.
local function complete_set(player, p, period)
  local h, st = p[period], p.streak[period]
  h.complete = true
  p.totals[period] = p.totals[period] + 1
  server.add(player, period == "daily" and "quest_days" or "quest_weeks")
  local cur = state.current[period]
  if st.last == cur.key then return end
  st.count = (st.last == cur.key - 1 and st.count or 0) + 1
  st.best = math.max(st.best, st.count)
  st.last = cur.key
  local unit = period == "daily" and "days" or "weeks"
  pcall(server.message, player, PREFIX .. "All " .. period .. " quests done! Streak: " .. st.count .. " " .. unit .. " in a row.")
  remember({ kind = "set", period = period, hero = player.character, count = st.count, time = NOW() })
  local bonus = bonus_for(period, st.count, player.level)
  if bonus then
    pcall(server.message, player, PREFIX .. "Streak bonus: " .. reward_text(bonus.gold, bonus.item) .. "!")
    say(player.character .. " is on a " .. st.count .. " " .. unit .. " " .. period .. " streak.")
    pay(player, bonus.gold, bonus.item)
  end
end

server.on("kill", function(player, monster)
  if type(monster) ~= "table" then return end
  local p
  for _, period in ipairs(PERIODS) do
    local cur = state.current[period]
    if cur then
      for _, q in ipairs(cur.quests) do
        if counts(q, monster) then
          p = p or hero_of(player)
          if not p then return end
          sync_hero(p, period)
          local h = p[period]
          if not h.done[q.id] then
            h.n[q.id] = (h.n[q.id] or 0) + 1
            dirty, push_due[player.slot] = true, true
            if h.n[q.id] >= q.target then
              h.done[q.id] = true
              p.totals.quests = p.totals.quests + 1
              pcall(server.message, player, PREFIX .. "Quest complete: " .. q.title .. "! Reward: " .. reward_text(gold_for(q.gold, player.level), q.item) .. ".")
              pay(player, gold_for(q.gold, player.level), q.item)
              local all = true
              for _, other in ipairs(cur.quests) do if not h.done[other.id] then all = false end end
              if all and not h.complete then complete_set(player, p, period) end
              save_state()
            end
          end
        end
      end
    end
  end
end)

server.on("enter", function(player)
  local p = hero_of(player)
  if p then
    for _, period in ipairs(PERIODS) do sync_hero(p, period) end
    pcall(server.message, player, PREFIX .. "Daily and weekly quests are up. Type !quests.")
  end
  push(player)
end)

server.on("chat", function(player, text)
  if text ~= "!quests" and text ~= "!quest" then return end
  local v = payload_for(player)
  for _, period in ipairs(PERIODS) do
    local s = v[period]
    server.message(player, string.format("%s quests (new in %s):", period == "daily" and "Daily" or "Weekly", duration_text(s.left)))
    for _, q in ipairs(s.quests) do
      server.message(player, string.format("  %s: %s - %s. Reward: %s.", q.title, q.text, q.done and "done" or (q.n .. "/" .. q.target), q.reward))
    end
    local st = v.streak[period]
    server.message(player, string.format("  Streak: %d in a row (best %d)%s", st.count, st.best,
      st.next_in > 0 and (", bonus in " .. st.next_in .. ": " .. tostring(st.bonus)) or ""))
  end
  return true
end)

-- ---- endpoints and the dashboard (character names only) ---------------------------------------------------------------------------

local function public_state()
  local out = { daily = {}, weekly = {}, left = { daily = seconds_left("daily"), weekly = seconds_left("weekly") }, top = {}, recent = {} }
  for _, period in ipairs(PERIODS) do
    for _, q in ipairs(state.current[period] and state.current[period].quests or {}) do
      local finished = 0
      for _, p in pairs(state.players) do if p[period] and p[period].key == state.current[period].key and p[period].done[q.id] then finished = finished + 1 end end
      out[period][#out[period] + 1] = { title = q.title, text = q.text, reward = reward_text(q.gold, q.item), finished = finished }
    end
  end
  local rows = {}
  for _, p in pairs(state.players) do
    local best = math.max(p.streak.daily.best, 0)
    if best > 0 or p.streak.weekly.best > 0 then rows[#rows + 1] = { name = p.name, daily = p.streak.daily.count, best = best, weekly = p.streak.weekly.best } end
  end
  table.sort(rows, function(a, b) if a.best ~= b.best then return a.best > b.best end return tostring(a.name) < tostring(b.name) end)
  for i = 1, math.min(10, #rows) do out.top[i] = rows[i] end
  local t = NOW()
  for _, h in ipairs(state.history) do
    out.recent[#out.recent + 1] = { period = h.period, hero = h.hero, count = h.count, ago = math.max(0, math.floor(t - (h.time or t))) }
  end
  return out
end

server.endpoint("rules", function() return CONFIG end,
  { description = "the daily quests configuration in force (JSON; the editor page writes it back under config in the mod's storage)" })
server.endpoint("state", function() return public_state() end,
  { public = true, description = "today's and this week's quests, the best streaks and the latest completed sets as JSON" })

local style = [[
body{margin:0;font:15px/1.4 system-ui,sans-serif;background:#15110d;color:#efe6d6}h1{margin:0;padding:1rem 1.2rem;font-size:1.3rem;color:#e0a944}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(19rem,1fr));gap:1rem;padding:0 1.2rem 1.2rem}
section{background:#241d16;border:1px solid #3b3025;border-radius:10px;padding:.8rem 1rem}h2{margin:0 0 .5rem;font-size:1rem;color:#f2c36b}
ol,ul{margin:0;padding-left:1.3rem}li{margin:.15rem 0}b{color:#fff}small{color:#a39683}p{margin:.2rem 0}]]

server.page("", function()
  local h = server.html
  local data = public_state()
  local parts = {
    '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta http-equiv="refresh" content="60"><title>Sacred daily quests</title><style>', style, '</style></head><body><h1>Daily and weekly quests</h1><main>',
  }
  for _, period in ipairs(PERIODS) do
    parts[#parts + 1] = "<section><h2>" .. (period == "daily" and "Today" or "This week") .. " <small>(new in " .. h(duration_text(data.left[period])) .. ")</small></h2>"
    if #data[period] == 0 then parts[#parts + 1] = "<small>nothing posted</small>" end
    for _, q in ipairs(data[period]) do
      parts[#parts + 1] = "<p><b>" .. h(q.title) .. "</b>: " .. h(q.text) .. "<br><small>Reward: " .. h(q.reward) .. ", " .. q.finished .. " finished</small></p>"
    end
    parts[#parts + 1] = "</section>"
  end
  parts[#parts + 1] = "<section><h2>Best streaks</h2>"
  if #data.top == 0 then parts[#parts + 1] = "<small>nobody yet</small>" else
    parts[#parts + 1] = "<ol>"
    for _, r in ipairs(data.top) do
      parts[#parts + 1] = "<li><b>" .. h(r.name or "?") .. "</b> " .. r.best .. " days <small>(now " .. r.daily .. ", weeks " .. r.weekly .. ")</small></li>"
    end
    parts[#parts + 1] = "</ol>"
  end
  parts[#parts + 1] = "</section><section><h2>Recent</h2>"
  if #data.recent == 0 then parts[#parts + 1] = "<small>nothing yet</small>" else
    parts[#parts + 1] = "<ul>"
    for _, r in ipairs(data.recent) do
      parts[#parts + 1] = "<li><b>" .. h(r.hero or "?") .. "</b> finished all " .. h(r.period or "") .. " quests, streak " .. (r.count or 0) .. " <small>" .. h(duration_text(r.ago)) .. " ago</small></li>"
    end
    parts[#parts + 1] = "</ul>"
  end
  parts[#parts + 1] = "</section></main></body></html>"
  return table.concat(parts)
end, { public = true, title = "Daily quests" })
