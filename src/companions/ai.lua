-- Companion AI: what the heroes the player does not control do, a few times a second. They follow the controlled hero,
-- fight what threatens the party with their weapon, and use their combat arts and spells the way a player would: an
-- attack art or spell on the target as soon as it has regenerated, an aura or self buff once a fight starts, a healing
-- spell when someone is hurt. Orders go through gear.party (the engine's own creature orders), so the game decides
-- reach, animation, damage and regeneration exactly as for the player.
--
-- The abilities are sorted by how the game aims them (gear.data.abilities[id].target_mode, read from the exe):
--   0 a direction (projectiles), 1 a creature, 3 a spot (areas, summons): used on the target;
--   2 the hero itself (buffs, auras), 5 around the hero (rings, aura bursts): used during a fight, on the hero;
--   4 a corpse (Erweckung): not used.
-- Shape changes and movement tricks the AI would only misuse are left out (NEVER below); the player switches any other
-- ability off per companion in the party window (tactics).

local M = {}

M.HURT_SECONDS = 6      -- after a hit, the attacker is fought regardless of the leader's distance
M.HURT_ENGAGE = 700     -- how far the one who hit a companion may stand
M.HOLD_ENGAGE = 450     -- a held companion fights what comes this close to its spot
M.HOLD_RETURN = 200     -- and walks back when a fight took it farther than this

local W = gear.world

-- Combos are the combo master's slots: ids 0x200 + slot (creature:combos()).
function M.is_combo(id) return id >= 0x200 and id < 0x204 end

-- Abilities the AI never uses: shape changes, teleports, burrowing, acrobatics, corpses, time stops.
local NEVER = {
    [1] = true,     -- Phasenverschiebung (teleport)
    [4] = true,     -- Wasserform
    [10] = true,    -- Morph
    [36] = true,    -- Verwandlung
    [46] = true, [57] = true,   -- Eingraben
    [1021] = true,  -- Flic-Flac
    [1023] = true,  -- Ritterform
    [1028] = true, [1029] = true,   -- Zeitbeherrschung
    [1034] = true,  -- Erweckung (needs a corpse)
}
-- Healing: used when a party hero is below half health.
local HEALING = {[7] = true, [42] = true}

-- Shape changes the AI handles: the Vampiress's vampire form (1022) makes her type 7 until she uses it again. She
-- changes when a fight starts and she is above half health, and back once no enemy is near or below a third of her
-- health (in daylight the form costs health).
local FORMS = {[1022] = {type = 7}}
M.FORMS = FORMS

M.NEVER, M.HEALING = NEVER, HEALING

local info_cache = {}       -- ability id -> {mode, name}
function M.ability_info(id)
    local c = info_cache[id]
    if c then return c end
    local rec = gear.data.abilities[id]
    local mode = rec and rec.target_mode or 1
    local name = rec and rec.name_text and gear.text.get(rec.name_text) or ('#' .. id)
    c = {mode = mode, name = name}
    info_cache[id] = c
    return c
end

-- How the AI would use an ability: 'target', 'self', 'heal' or nil (never).
function M.use_of(id)
    if NEVER[id] then return nil end
    if FORMS[id] then return 'form' end
    if HEALING[id] then return 'heal' end
    local mode = M.ability_info(id).mode
    if mode == 0 or mode == 1 or mode == 3 then return 'target' end
    if mode == 2 or mode == 5 then return 'self' end
    return nil
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function hp_frac(c)
    local hp, max = c:hp(), c:max_hp()
    if not hp or not max or max <= 0 then return 1 end
    return hp / max
end

-- Per companion state (by id): the target, when it last got an order, when it last used a self ability.
local state = {}
function M.reset() state = {} end

local function st(id)
    local s = state[id]
    if not s then
        s = {target = nil, ordered = -100, ability_at = -100, self_at = {}, fight_since = nil, teleported = -100,
            heal_amount = {}, heal_at = {}}
        state[id] = s
    end
    return s
end

-- The enemy a companion fights: living enemies within `engage` of the companion and within `leash` of the leader,
-- the one nearest to the leader first (protect the controlled hero), then the nearest to the companion.
-- opts.focus: the most wounded enemy near the leader first (the game does not tell the mod the target of the hero you
-- play; the one being fought is usually the wounded one). opts.taken: enemy id -> true, the other companions' targets,
-- left to them while another enemy is there (one enemy each); with one enemy left, all take it.
local function pick_target(c, cx, cy, layer, lx, ly, opts)
    local function search(skip_taken)
        local best, best_score
        for _, e in ipairs(W.creatures_near(cx, cy, opts.engage, {layer = layer, limit = 24})) do
            local free = not (skip_taken and opts.taken and opts.taken[e.id])
            if free and not e:is_hero() and not e:is_dead() and c:is_enemy(e) then
                local ex, ey = e:position()
                if ex then
                    local dl = dist(ex, ey, lx, ly)
                    if dl <= opts.leash then
                        local score = dl + 0.5 * dist(ex, ey, cx, cy)
                        if opts.focus then score = hp_frac(e) * 4000 + dl end
                        if not best_score or score < best_score then best, best_score = e, score end
                    end
                end
            end
        end
        return best
    end
    if opts.taken then return search(true) or search(false) end
    return search(false)
end

-- Whether a living enemy of `c` is within `radius` of it.
function M.enemy_near(c, radius)
    local x, y, l = c:position()
    if not x then return false end
    for _, e in ipairs(W.creatures_near(x, y, radius, {layer = l, limit = 24})) do
        if not e:is_hero() and not e:is_dead() and c:is_enemy(e) then return true end
    end
    return false
end

-- With a priority list (the party window's tactics: the arrows move an ability up or down) the ability nearest the top that
-- is ready is used; abilities not in the list come after it.
function M.priority_score(tactics, id)
    return 100000 - (tactics.priority[id] or 50000)
end

-- The ability to use now, and on whom ('target' or 'self'), or nil.
local function pick_ability(c, s, now, target, heroes, tactics, opts)
    local best, best_use, best_score
    for _, a in ipairs(c:abilities() or {}) do
        local use = a.ready and M.use_of(a.id)
        if use and use ~= 'form' and use ~= 'heal' and tactics.abilities[a.id] ~= false then
            local ok = true
            if use == 'self' then
                -- an aura or buff: in a fight (or always, setting) once and then again when it ran out (its regeneration
                -- time, at least 20 s)
                ok = (target ~= nil or opts.buffs == 'always') and now - (s.self_at[a.id] or -1000) >= math.max(20, a.regen_max)
            else
                ok = target ~= nil
            end
            if ok then
                local score = (a.level + a.bonus) + (use == 'self' and 500 or 0)
                if tactics.priority then score = M.priority_score(tactics, a.id) end
                if not best_score or score > best_score then best, best_use, best_score = a, use, score end
            end
        end
    end
    -- A combo (the combo master's arts in a row) beats a single art on the target.
    if target then
        for _, k in ipairs(c:combos() or {}) do
            if k.ready and tactics.abilities[k.id] ~= false then
                local score = 800
                for _, l in ipairs(k.levels) do score = score + l end
                if tactics.priority then score = M.priority_score(tactics, k.id) end
                if not best_score or score > best_score then best, best_use, best_score = k, 'target', score end
            end
        end
    end
    return best, best_use
end

-- Ranged weapons by their type names (the game keeps no flag the mod can read): bows, crossbows, the dwarf's guns.
local RANGED = {'bow', 'armbrust', 'musket', 'muskete', 'gun', 'rifle', 'pistol', 'cannon', 'kanone', 'sling'}
function M.is_ranged(item)
    local n = item and item.type_name and item.type_name:lower()
    if not n then return false end
    for _, k in ipairs(RANGED) do if n:find(k, 1, true) then return true end end
    return false
end

-- Style 'ranged': take up the weapon slot that holds a ranged weapon (true when the hero holds one now).
local function take_ranged(c, s, now)
    if not c.weapon_slots then return false end
    local w = c:weapon_slots()
    if not w then return false end
    local cur = w.slots[w.active]
    if cur and M.is_ranged(cur.main) then return true end
    if now - (s.weapon_at or -100) < 3 then return false end
    for i, sl in ipairs(w.slots) do
        if M.is_ranged(sl.main) then
            s.weapon_at = now
            local ok = c:use_weapon_slot(i)
            if M.debug then print('ranged slot', c.id, i, ok) end
            return ok and true or false
        end
    end
    return false
end

-- A shape change to use now (into the form for a fight, out of it after), or nil.
local function pick_form(c, s, now, fighting, tactics)
    local hp = hp_frac(c)
    local type_ = c:type()
    for _, a in ipairs(c:abilities() or {}) do
        local f = FORMS[a.id]
        if f and a.ready and tactics.abilities[a.id] ~= false then
            local shaped = type_ == f.type
            if not shaped and fighting and hp > 0.5 then return a end
            if shaped and (hp < 0.33 or not fighting and now - (s.fight_end or now) > 3) then return a end
        end
    end
end

-- Healing. The game casts a companion's healing spell (Genesung, Spirituelle Heilkraft) only on the caster: its own AI
-- does the same, and an order onto another hero is dropped. So a companion heals another hero by casting the spell on
-- themselves (animation, mana, regeneration as usual) and the other hero gets the health the spell gives: what it
-- gave the caster last time (seen when the caster was hurt), until then a third of the healed hero's health.
local HEAL_RANGE = 10 * (W.TILE or 64)

-- Who needs healing most, by the priority: 'hero' (the hero you play, then the caster, then the lowest), 'self' (the
-- caster, then the hero you play, then the lowest) or 'lowest'. Only heroes below `below` and near the caster.
local function heal_target(c, leader, heroes, priority, below)
    local cx, cy = c:position()
    local hurt = {}
    for _, h in ipairs(heroes) do
        local hx, hy = h:position()
        if not h:is_dead() and hx and hp_frac(h) < below and dist(cx, cy, hx, hy) <= HEAL_RANGE then hurt[#hurt + 1] = h end
    end
    if #hurt == 0 then return nil end
    local function has(x) for _, h in ipairs(hurt) do if h == x then return x end end end
    if priority == 'hero' and has(leader) then return leader end
    if priority ~= 'lowest' and has(c) then return c end
    if priority == 'self' and has(leader) then return leader end
    table.sort(hurt, function(a, b) return hp_frac(a) < hp_frac(b) end)
    return hurt[1]
end

-- A heal in flight: once the caster had time to cast it, what it gave the caster is noted (when the caster was
-- hurt enough to show it) and another hero it was meant for gets that health.
local function finish_heal(c, s, now)
    local t = s.transfer
    if not t or now - t.at < 0.8 then return end
    local hp, max = c:hp() or 0, c:max_hp() or 0
    local gained = hp - t.hp0
    if gained > 1 and hp < max then s.heal_amount[t.ability] = gained end
    local to = t.to ~= c.id and W.object(t.to)
    if to and not to:is_dead() then
        local tmax = to:max_hp() or 0
        local amount = s.heal_amount[t.ability] or math.floor(tmax / 3)
        to:set_hp(math.min(tmax, (to:hp() or 0) + amount))
        if M.debug then print('heal', c.id, '->', t.to, amount) end
    end
    s.transfer = nil
end

-- Buffs the game meant for others too ("or a chosen companion": Steinhaut, Glaubensstaerke, Katarakt der Wendigkeit,
-- Reiki) but casts only on the caster: Gear's buffs (gear.buffs) pass them on to the other heroes near the caster, at
-- the setting's strength, for as long as the caster's own lasts. What a cast gave the caster (its values before and
-- after) is what the others get.
M.ALLY_BUFFS = {[2] = true, [21] = true, [27] = true, [32] = true}

local function share_end(s)
    local sh = s.share
    if sh and sh.targets then
        for _, id in ipairs(sh.targets) do gear.buffs.remove(id, sh.key) end
    end
    s.share = nil
end

local function share_start(c, s, a, now, opts)
    if not (gear.buffs and M.ALLY_BUFFS[a.id] and (opts.buff_strength[a.id] or 0) > 0) then return end
    share_end(s)
    s.share = {ability = a.id, before = gear.buffs.fields(c), at = now}
end

-- After the cast: the others get it; once the caster's own has ended, theirs ends too.
local function share_step(c, s, now, heroes, opts)
    local sh = s.share
    if not sh then return end
    if not sh.targets then
        if now - sh.at < 1.5 then return end
        local after = gear.buffs.fields(c)
        local stats, factors = gear.buffs.change(sh.before or {}, after or {})
        local probe = next(stats) or next(factors)
        if not probe then
            if now - sh.at > 4 then s.share = nil end
            return
        end
        local overlay, seconds = gear.buffs.overlay(c)
        local def = {id = 'shared_' .. sh.ability, name = M.ability_info(sh.ability).name, stats = stats, factors = factors,
            overlay = overlay or 0}
        sh.key = 'companions:' .. c.id .. ':' .. sh.ability
        sh.probe, sh.was, sh.now = probe, sh.before[probe], after[probe]
        sh.targets = {}
        local cx, cy = c:position()
        for _, h in ipairs(heroes) do
            local hx, hy = h:position()
            if h ~= c and not h:is_dead() and hx and dist(cx, cy, hx, hy) <= HEAL_RANGE then
                local ok = gear.buffs.apply(h, def, {key = sh.key, strength = opts.buff_strength[sh.ability] or 0.5,
                    seconds = overlay and overlay > 0 and seconds or 0, source = c, ability = sh.ability})
                if ok then sh.targets[#sh.targets + 1] = h.id end
                if M.debug then print('share', c.id, '->', h.id, sh.ability, ok) end
            end
        end
        return
    end
    local f = gear.buffs.fields(c)
    local v = f and f[sh.probe]
    if not v or c:is_dead() or math.abs(v - sh.now) > math.abs(v - sh.was) then share_end(s) end
end

-- Casts a heal when a hero near the caster is below the setting's health. True when it did.
local function heal_step(c, s, now, leader, heroes, opts, tactics)
    if not opts.use_abilities or now - s.ability_at < 1.5 or s.transfer then return false end
    local who = heal_target(c, leader, heroes, opts.heal_priority, opts.heal_below)
    if not who then return false end
    for _, a in ipairs(c:abilities() or {}) do
        -- (the game reports a spell as ready while it regenerates: wait its regeneration time between two casts)
        if HEALING[a.id] and a.ready and tactics.abilities[a.id] ~= false and now - (s.heal_at[a.id] or -1000) >= math.max(5, a.regen_max) then
            local hp0, max = c:hp() or 0, c:max_hp() or 0
            -- the game does not cast a heal on a caster at full health: one point less is enough
            if who ~= c and max > 1 and hp0 >= max then
                hp0 = max - 1
                c:set_hp(hp0)
            end
            if c:order_ability(a.id, c) then
                s.ability_at, s.ordered = now, now
                s.heal_at[a.id] = now
                s.transfer = {to = who.id, ability = a.id, hp0 = hp0, at = now}
                return true
            end
        end
    end
    return false
end

-- A spot next to the leader for companion number `slot` of `count`, behind it in a fan.
local function formation(lx, ly, slot, count, distance, spread)
    local angle = math.pi * 0.75 + (slot - 0.5) / math.max(count, 1) * math.pi * 0.5
    local fx, fy = lx + math.cos(angle) * distance, ly + math.sin(angle) * distance
    if spread and spread > 0 then
        -- spread sideways: each one a step further from the middle of the party
        local k = slot - (count + 1) / 2
        fx, fy = fx - math.sin(angle) * k * spread, fy + math.cos(angle) * k * spread
    end
    return fx, fy
end

-- Line and square formations (setting). The front faces the nearest enemy of the hero you play (kept while none is
-- near). Roles from the companion's combat style: weapon users (melee), ranged weapon, combat arts only.
--   line:   melee in a row in front, ranged and combat arts in a row behind
--   square: combat arts in the middle, melee and ranged in a ring around them
local front_angle = math.pi * 0.25

-- Once per think round: the front, from the hero you play to its nearest enemy.
function M.begin_round(leader, opts)
    if not opts.formation or opts.formation == 'none' then return end
    local lx, ly, ll = leader:position()
    if not lx then return end
    local t = pick_target(leader, lx, ly, ll, lx, ly, {engage = opts.engage, leash = opts.leash})
    if t then
        local ex, ey = t:position()
        if ex then front_angle = math.atan2(ey - ly, ex - lx) end
    end
end

local function role_of(id, opts)
    local s = opts.styles and opts.styles[id]
    if s == 'ranged' or s == 'arts' then return s end
    return 'melee'
end

local function formation_spot(c, lx, ly, heroes, opts)
    local ids = {}
    for i = 2, #heroes do ids[#ids + 1] = heroes[i].id end
    table.sort(ids)
    local melee, back, arts, ring = {}, {}, {}, {}
    for _, id in ipairs(ids) do
        local r = role_of(id, opts)
        if r == 'melee' then melee[#melee + 1] = id else back[#back + 1] = id end
        if r == 'arts' then arts[#arts + 1] = id else ring[#ring + 1] = id end
    end
    local function index_of(list)
        for i, id in ipairs(list) do if id == c.id then return i, #list end end
    end
    local tile = W.TILE or 54
    local D = opts.follow * 0.6
    local fx_, fy_ = math.cos(front_angle), math.sin(front_angle)
    local px, py = -fy_, fx_
    local role = role_of(c.id, opts)
    if opts.formation == 'line' then
        local list, dir = melee, 1
        if role ~= 'melee' then list, dir = back, -1 end
        local i, n = index_of(list)
        if not i then return nil end
        local L = math.max(opts.spread or 0, tile * 1.2)
        local k = i - (n + 1) / 2
        return lx + fx_ * D * dir + px * k * L, ly + fy_ * D * dir + py * k * L
    end
    if role == 'arts' then
        local i, n = index_of(arts)
        if not i then return nil end
        local k = i - (n + 1) / 2
        local d = tile * 0.8
        return lx - fx_ * d + px * k * d, ly - fy_ * d + py * k * d
    end
    local j, n = index_of(ring)
    if not j then return nil end
    local angle = front_angle + 2 * math.pi * (j - 1) / math.max(n, 1)
    return lx + math.cos(angle) * D, ly + math.sin(angle) * D
end

-- Where a companion stands while following: its place in the formation, else the loose fan behind the leader.
local function place(c, lx, ly, heroes, opts, slot, count)
    if opts.formation == 'line' or opts.formation == 'square' then
        local fx, fy = formation_spot(c, lx, ly, heroes, opts)
        if fx then return fx, fy end
    end
    return formation(lx, ly, slot, count, opts.follow * 0.6, opts.spread)
end

-- Protector style: a slow round about the hero it guards, attacking the enemy that comes nearest to that hero.
local function protect(c, s, now, lx, ly, ll, slot, count, opts)
    local radius = opts.follow * 0.5
    local angle = now * 0.6 + slot / math.max(count, 1) * math.pi * 2
    local fx, fy = lx + math.cos(angle) * radius, ly + math.sin(angle) * radius
    local best, best_d
    for _, e in ipairs(W.creatures_near(lx, ly, opts.protect_range, {layer = ll, limit = 24})) do
        if not e:is_hero() and not e:is_dead() and c:is_enemy(e) then
            local ex, ey = e:position()
            if ex then
                local dl = dist(ex, ey, lx, ly)
                if not best_d or dl < best_d then best, best_d = e, dl end
            end
        end
    end
    local action = c:action() or 'idle'
    if best then
        if action == 'ability' then return end
        if s.target ~= best.id or action == 'idle' then
            if c:order_attack(best) then s.target, s.ordered = best.id, now end
        end
        return
    end
    s.target = nil
    local cx, cy = c:position()
    if cx and now - s.ordered > 0.5 and dist(cx, cy, fx, fy) > (W.TILE or 54) * 0.7 then
        if action == 'attacking' then c:order_stop() end
        if c:order_move(fx, fy) then s.ordered = now end
    end
end

-- Puts a companion beside the leader: its place in the loose fan, else right beside them, else on their spot (a cave has
-- little room: the first may lie in rock).
function M.join(c, lx, ly, ll, slot, count, follow)
    local fx, fy = formation(lx, ly, slot, count, math.min(follow * 0.6, 120))
    local spots = {{fx, fy}, {lx + 40, ly + 40}, {lx - 40, ly + 40}, {lx, ly}}
    for _, p in ipairs(spots) do
        if c:teleport(p[1], p[2], ll) then
            local nx, ny, nl = c:position()
            if nl == ll and nx and dist(nx, ny, lx, ly) < 400 then return true end
        end
    end
    return false
end

-- "Move to me": a companion who is stuck joins the leader at once.
function M.move_to_me(c, leader, slot, count, follow)
    local lx, ly, ll = leader:position()
    if not lx or c:is_dead() then return false end
    local s = st(c.id)
    s.target, s.stuck_at, s.teleported = nil, nil, os.clock()
    return M.join(c, lx, ly, ll, slot, count, follow)
end

-- Run away (tactics: below a share of health): from the nearest enemy to the leader's far side, until the health is back
-- (the threshold and 20 points) or no enemy is near. True while running.
local function flee_step(c, s, now, lx, ly, opts, tactics)
    local thr = tactics.flee
    if not thr then s.fleeing = nil return false end
    local f = hp_frac(c)
    local enemy_near = M.enemy_near(c, opts.engage)
    if s.fleeing then
        if f >= math.max(0.6, thr + 0.1) or not enemy_near then s.fleeing = nil end
    elseif f < thr and enemy_near then
        s.fleeing = true
    end
    if not s.fleeing then return false end
    local cx, cy, cl = c:position()
    local nearest, nd
    for _, e in ipairs(W.creatures_near(cx, cy, opts.engage, {layer = cl, limit = 24})) do
        if not e:is_hero() and not e:is_dead() and c:is_enemy(e) then
            local ex, ey = e:position()
            local de = ex and dist(ex, ey, cx, cy)
            if de and (not nd or de < nd) then nearest, nd = {ex, ey}, de end
        end
    end
    s.target = nil
    local tx, ty = lx, ly
    if nearest then
        -- the leader's side, one step further from the enemy than the leader
        local ax, ay = lx - nearest[1], ly - nearest[2]
        local len = math.max(1, math.sqrt(ax * ax + ay * ay))
        local tile = W.TILE or 54
        tx, ty = lx + ax / len * tile * 2, ly + ay / len * tile * 2
    end
    local action = c:action() or 'idle'
    if action ~= 'ability' and dist(cx, cy, tx, ty) > (W.TILE or 54) * 1.2 and now - s.ordered > 0.7 then
        if c:order_move(tx, ty) then s.ordered = now end
    end
    return true
end

-- Shots that miss (tactics, ranged weapons only): a target whose health has not moved for 3 s while the companion attacks it
-- is out of reach of the shots (a wall, a rock, a corner): the companion goes to a spot 4 to 6 tiles around the target, the nearest
-- one first. A spot not reached within 4 s counts as blocked for 30 s and another one is tried. (The idea of the player's fork.)
local function ranged_now(c, tactics)
    if tactics.style == 'ranged' then return true end
    local w = c.weapon_slots and c:weapon_slots()
    local cur = w and w.slots and w.slots[w.active]
    return cur and M.is_ranged(cur.main) or false
end

-- True while the companion walks to a new spot (the caller leaves it alone).
local function reposition_step(c, s, now, target, action, tactics, lx, ly, opts)
    if not tactics.reposition or not ranged_now(c, tactics) then s.rep, s.repos = nil, nil return false end
    local tile = W.TILE or 54
    local cx, cy = c:position()
    if s.repos then
        local rp = s.repos
        if cx and dist(cx, cy, rp.x, rp.y) < tile * 1.2 then s.repos, s.rep = nil, nil return false end
        if now - rp.since > 4 then
            s.bad_spots[rp.key] = now + 30
            s.repos = nil
        else
            return true
        end
    end
    if action == 'ability' then return false end
    local hp = target:hp() or 0
    local r = s.rep
    if not r or r.id ~= target.id or hp < r.hp - 0.5 then
        s.rep = {id = target.id, hp = hp, since = now}
        return false
    end
    if now - r.since < 3 then return false end
    local tx, ty = target:position()
    if not tx or not cx then return false end
    s.bad_spots = s.bad_spots or {}
    local best, best_score
    for _, rad in ipairs({4, 6}) do
        for k = 0, 7 do
            local a = k * math.pi / 4 + (math.random() - 0.5) * 0.3
            local x, y = tx + math.cos(a) * rad * tile, ty + math.sin(a) * rad * tile
            local key = math.floor(x / tile) .. ':' .. math.floor(y / tile)
            local bad = s.bad_spots[key] and now < s.bad_spots[key]
            if not bad and dist(x, y, lx, ly) <= opts.leash then
                local score = dist(x, y, cx, cy) + (rad == 4 and 0 or 2 * tile)
                if not best_score or score < best_score then best, best_score = {x = x, y = y, key = key}, score end
            end
        end
    end
    s.rep = nil
    if best and c:order_move(best.x, best.y) then
        best.since = now
        s.repos, s.ordered, s.target = best, now, nil
        return true
    end
    return false
end

-- One think of companion `c`. opts: engage, leash, follow, teleport, behaviour ('aggressive', 'defensive',
-- 'passive'), use_abilities; tactics: {abilities = {[id] = false}}.
function M.think(c, leader, slot, count, now, heroes, opts, tactics)
    if c:is_dead() or leader:is_dead() then return end
    local s = st(c.id)
    local cx, cy, cl = c:position()
    local lx, ly, ll = leader:position()
    if not cx or not lx then return end
    local d = dist(cx, cy, lx, ly)
    local behaviour = tactics.behaviour or opts.behaviour
    local holding = behaviour == 'hold'
    if holding then s.hold = s.hold or {x = cx, y = cy} else s.hold = nil end
    -- Hit since the last think: for a few seconds the one who hit them is fought wherever it stands, instead of running back
    -- to the leader (they were seen to run away from a fight with the leader out of reach)
    local hp = c:hp() or 0
    if s.hp and hp < s.hp - 0.5 then s.hurt_at = now end
    s.hp = hp
    local hurt = s.hurt_at ~= nil and now - s.hurt_at < M.HURT_SECONDS
    -- Stuck (a cave's narrow ways, a wall between them): no headway toward a leader far off for 6 s.
    local stuck = false
    local act0 = c:action()
    if not holding and d > opts.follow * 2 and (act0 == 'walking' or act0 == 'idle') then
        if not s.stuck_at or math.abs(cx - s.stuck_x) + math.abs(cy - s.stuck_y) > 40 then
            s.stuck_at, s.stuck_x, s.stuck_y = now, cx, cy
        elseif now - s.stuck_at > 6 then
            stuck = true
        end
    else
        s.stuck_at = nil
    end
    -- Left behind (a portal, another level, a cave, a teleport) or stuck: join the leader, close to them (a cave has
    -- little room: the spot in the formation may lie in rock, then right beside the leader, then on the leader's spot).
    if cl ~= ll or (not holding and (d > opts.teleport or stuck)) then
        if now - s.teleported > 2 then
            M.join(c, lx, ly, ll, slot, count, opts.follow)
            s.teleported, s.target, s.stuck_at = now, nil, nil
        end
        return
    end
    -- Low on health: a healing potion from its own backpack, like the player's Space.
    if opts.potion_below > 0 and hp_frac(c) < opts.potion_below and now - (s.potion_at or -100) > 5 then
        s.potion_at = c:drink_potion() and now or now + 10   -- none: ask again in 15 s
    end
    local action = c:action() or 'idle'
    finish_heal(c, s, now)
    share_step(c, s, now, heroes, opts)
    if action ~= 'ability' and heal_step(c, s, now, leader, heroes, opts, tactics) then return end
    if flee_step(c, s, now, lx, ly, opts, tactics) then return end
    local target
    if tactics.style == 'protector' and behaviour ~= 'passive' and not holding then
        return protect(c, s, now, lx, ly, ll, slot, count, opts)
    end
    local taken
    if opts.separate then
        taken = {}
        for _, h in ipairs(heroes) do
            local o = h.id ~= c.id and state[h.id]
            if o and o.target then taken[o.target] = true end
        end
    end
    if hurt and behaviour ~= 'passive' then
        -- no leash: the nearest enemy to the companion (the leader's position does not matter when one is hit)
        target = pick_target(c, cx, cy, cl, cx, cy, {engage = math.max(opts.engage, M.HURT_ENGAGE), leash = math.huge})
    elseif holding then
        -- on guard at the spot: only what comes close
        target = pick_target(c, cx, cy, cl, s.hold.x, s.hold.y, {engage = M.HOLD_ENGAGE, leash = M.HOLD_ENGAGE * 1.5})
    elseif behaviour ~= 'passive' and d <= opts.leash then
        local engage = behaviour == 'defensive' and math.min(opts.engage, 450) or opts.engage
        target = pick_target(c, cx, cy, cl, lx, ly, {engage = engage, leash = behaviour == 'defensive' and 450 or opts.leash,
            focus = opts.focus, taken = taken})
    end
    if M.debug and target then print(('think %d d=%d action=%s target=%s'):format(c.id, d, action, tostring(target.id))) end
    if target then
        s.fight_since = s.fight_since or now
        -- An ability runs until the game is done with it; a new order would cut it off. Weapon attacks go on by
        -- themselves until the target falls, so they are ordered again only for a new target or an idle hero.
        if action == 'ability' then return end
        s.fight_end = nil
        local style = tactics.style or 'balanced'
        if reposition_step(c, s, now, target, action, tactics, lx, ly, opts) then return end   -- walking to another spot
        if style == 'ranged' then take_ranged(c, s, now) end
        -- weapon first: combat arts and spells only every 8 s
        local gap = style == 'weapon' and 8 or 2
        if opts.use_abilities and now - s.ability_at > gap then
            local form = pick_form(c, s, now, true, tactics)
            if form and c:order_ability(form.id, c) then
                s.ability_at, s.ordered = now, now
                return
            end
            local a, use = pick_ability(c, s, now, target, heroes, tactics, opts)
            if a then
                if use == 'self' then share_start(c, s, a, now, opts) end
                local ok, err = c:order_ability(a.id, use == 'target' and target or c)
                if M.debug then print('ability', a.id, use, ok, err) end
                if ok then
                    s.ability_at, s.ordered = now, now
                    if use ~= 'target' then s.self_at[a.id] = now end
                    s.target = target.id
                    return
                end
            end
        end
        if style == 'arts' then
            -- combat arts only: no weapon; between casts they keep back with the hero they protect
            if action == 'attacking' then c:order_stop() end
            s.target = target.id
            if d > opts.follow and now - s.ordered > 0.5 then
                local fx, fy = place(c, lx, ly, heroes, opts, slot, count)
                if c:order_move(fx, fy) then s.ordered = now end
            end
            return
        end
        if s.target ~= target.id or action == 'idle' then
            local ok, err = c:order_attack(target)
            if M.debug then print('attack', target.id, ok, err) end
            if ok then
                s.target, s.ordered = target.id, now
            end
        end
        return
    end
    s.fight_since = nil
    s.fight_end = s.fight_end or now
    -- After a fight: back out of a shape change.
    if opts.use_abilities and action ~= 'ability' and now - s.ability_at > 2 then
        local form = pick_form(c, s, now, false, tactics)
        if form and c:order_ability(form.id, c) then
            s.ability_at, s.ordered = now, now
            return
        end
    end
    -- Buffs whenever they are ready (setting), also outside fights.
    if opts.use_abilities and opts.buffs == 'always' and action ~= 'ability' and now - s.ability_at > 2 then
        local a, use = pick_ability(c, s, now, nil, heroes, tactics, opts)
        if a and use == 'self' then share_start(c, s, a, now, opts) end
        if a and use == 'self' and c:order_ability(a.id, c) then
            s.ability_at, s.ordered = now, now
            s.self_at[a.id] = now
            return
        end
    end
    -- No fight: keep up with the leader (a held companion goes back to its spot instead and waits there).
    if s.target then
        s.target = nil
        if action ~= 'idle' then c:order_stop() end
    end
    if holding then
        local h = s.hold
        if h and dist(cx, cy, h.x, h.y) > M.HOLD_RETURN and now - s.ordered > 1 and action == 'idle' then
            if c:order_move(h.x, h.y) then s.ordered = now end
        end
        return
    end
    if opts.formation == 'line' or opts.formation == 'square' then
        -- a formation: each to their own spot, also near the leader (the loose way only moves when left behind)
        local fx, fy = place(c, lx, ly, heroes, opts, slot, count)
        if dist(cx, cy, fx, fy) > (W.TILE or 54) * 1.2 and now - s.ordered > 0.7 then
            if c:order_move(fx, fy) then s.ordered = now end
        end
    elseif d > opts.follow and now - s.ordered > 0.5 then
        local fx, fy = place(c, lx, ly, heroes, opts, slot, count)
        if c:order_move(fx, fy) then s.ordered = now end
    end
end

-- One think of a mercenary (the game's own, following the party). Its own AI keeps running; 'assist' only points it
-- at the enemy the party fights (the nearest to the hero you play) when it stands idle or fights something else far
-- away, 'passive' calls it back to you when it strays into a fight. Nothing is teleported or scripted: escorts and
-- quest followers stay the game's.
function M.think_merc(m, leader, now, opts, behaviour)
    if behaviour == 'vanilla' or m:is_dead() or leader:is_dead() then return end
    local s = st(m.id)
    local mx, my, ml = m:position()
    local lx, ly, ll = leader:position()
    if not mx or not lx or ml ~= ll then return end
    local d = dist(mx, my, lx, ly)
    local action = m:action() or 'idle'
    if behaviour == 'passive' then
        if d > opts.follow * 2 and now - s.ordered > 1.5 then
            local fx, fy = formation(lx, ly, 1, 1, opts.follow * 0.6)
            if m:order_move(fx, fy) then s.ordered = now end
        end
        return
    end
    if d > opts.leash then return end
    local target = pick_target(m, mx, my, ml, lx, ly, {engage = opts.engage, leash = opts.leash})
    if target and action ~= 'ability' and (action == 'idle' or (s.target ~= target.id and now - s.ordered > 3)) then
        if m:order_attack(target) then s.target, s.ordered = target.id, now end
    elseif not target then
        s.target = nil
    end
end

return M
