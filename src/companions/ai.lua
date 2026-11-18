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
    [1022] = true,  -- Vampirform
    [1023] = true,  -- Ritterform
    [1028] = true, [1029] = true,   -- Zeitbeherrschung
    [1034] = true,  -- Erweckung (needs a corpse)
}
-- Healing: used when a party hero is below half health.
local HEALING = {[7] = true, [42] = true}

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
        s = {target = nil, ordered = -100, ability_at = -100, self_at = {}, fight_since = nil, teleported = -100}
        state[id] = s
    end
    return s
end

-- The enemy a companion fights: living enemies within `engage` of the companion and within `leash` of the leader,
-- the one nearest to the leader first (protect the controlled hero), then the nearest to the companion.
local function pick_target(c, cx, cy, layer, lx, ly, opts)
    local best, best_score
    for _, e in ipairs(W.creatures_near(cx, cy, opts.engage, {layer = layer, limit = 24})) do
        if not e:is_hero() and not e:is_dead() and c:is_enemy(e) then
            local ex, ey = e:position()
            if ex then
                local dl = dist(ex, ey, lx, ly)
                if dl <= opts.leash then
                    local score = dl + 0.5 * dist(ex, ey, cx, cy)
                    if not best_score or score < best_score then best, best_score = e, score end
                end
            end
        end
    end
    return best
end

-- The ability to use now, and on whom ('target' or 'self'), or nil.
local function pick_ability(c, s, now, target, heroes, tactics)
    local hurt = false
    for _, h in ipairs(heroes) do
        if not h:is_dead() and hp_frac(h) < 0.5 then hurt = true end
    end
    local best, best_use, best_score
    for _, a in ipairs(c:abilities() or {}) do
        local use = a.ready and M.use_of(a.id)
        if use and tactics.abilities[a.id] ~= false then
            local ok = true
            if use == 'heal' then
                ok = hurt
            elseif use == 'self' then
                -- an aura or buff: once per fight and then when it ran out (its regeneration time, at least 20 s)
                ok = target ~= nil and now - (s.self_at[a.id] or -1000) >= math.max(20, a.regen_max)
            else
                ok = target ~= nil
            end
            if ok then
                local score = (a.level + a.bonus) + (use == 'heal' and 1000 or use == 'self' and 500 or 0)
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
                if not best_score or score > best_score then best, best_use, best_score = k, 'target', score end
            end
        end
    end
    return best, best_use
end

-- A spot next to the leader for companion number `slot` of `count`, behind it in a fan.
local function formation(lx, ly, slot, count, distance)
    local angle = math.pi * 0.75 + (slot - 0.5) / math.max(count, 1) * math.pi * 0.5
    return lx + math.cos(angle) * distance, ly + math.sin(angle) * distance
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
    -- Left behind (a portal, another level, a teleport): join the leader.
    if cl ~= ll or d > opts.teleport then
        if now - s.teleported > 2 then
            local fx, fy = formation(lx, ly, slot, count, opts.follow * 0.6)
            c:teleport(fx, fy, ll)
            s.teleported, s.target = now, nil
        end
        return
    end
    local behaviour = tactics.behaviour or opts.behaviour
    local action = c:action() or 'idle'
    local target
    if behaviour ~= 'passive' and d <= opts.leash then
        local engage = behaviour == 'defensive' and math.min(opts.engage, 450) or opts.engage
        target = pick_target(c, cx, cy, cl, lx, ly, {engage = engage, leash = behaviour == 'defensive' and 450 or opts.leash})
    end
    if M.debug and target then print(('think %d d=%d action=%s target=%s'):format(c.id, d, action, tostring(target.id))) end
    if target then
        s.fight_since = s.fight_since or now
        -- An ability runs until the game is done with it; a new order would cut it off. Weapon attacks go on by
        -- themselves until the target falls, so they are ordered again only for a new target or an idle hero.
        if action == 'ability' then return end
        if opts.use_abilities and now - s.ability_at > 2 then
            local a, use = pick_ability(c, s, now, target, heroes, tactics)
            if a then
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
    -- No fight: keep up with the leader.
    if s.target then
        s.target = nil
        if action ~= 'idle' then c:order_stop() end
    end
    if d > opts.follow and now - s.ordered > 0.5 then
        local fx, fy = formation(lx, ly, slot, count, opts.follow * 0.6)
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
