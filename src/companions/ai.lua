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

-- Whether a living enemy of `c` is within `radius` of it.
function M.enemy_near(c, radius)
    local x, y, l = c:position()
    if not x then return false end
    for _, e in ipairs(W.creatures_near(x, y, radius, {layer = l, limit = 24})) do
        if not e:is_hero() and not e:is_dead() and c:is_enemy(e) then return true end
    end
    return false
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
    -- Low on health: a healing potion from its own backpack, like the player's Space.
    if opts.potion_below > 0 and hp_frac(c) < opts.potion_below and now - (s.potion_at or -100) > 5 then
        s.potion_at = c:drink_potion() and now or now + 10   -- none: ask again in 15 s
    end
    local behaviour = tactics.behaviour or opts.behaviour
    local action = c:action() or 'idle'
    finish_heal(c, s, now)
    share_step(c, s, now, heroes, opts)
    if action ~= 'ability' and heal_step(c, s, now, leader, heroes, opts, tactics) then return end
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
        s.fight_end = nil
        local style = tactics.style or 'balanced'
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
                local fx, fy = formation(lx, ly, slot, count, opts.follow * 0.6)
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
