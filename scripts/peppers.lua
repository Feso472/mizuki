-- Native flame entities; only the blindfolded weapon's proc scheduling is ours.
-- One opportunity per real attack, never per multishot laser. Echoes replay the
-- recorded outcome (including misses) without drawing from the player's RNG.
local BLUE = CollectibleType.COLLECTIBLE_GHOST_PEPPER
local RED = CollectibleType.COLLECTIBLE_BIRDS_EYE
local PERIOD = 4
local attachedFlames = {}
local runtime = {}

local function sameEntity(entity, seed, hash)
    return entity and entity:Exists() and entity.InitSeed == seed and GetPtrHash(entity) == hash
end

local function ownedKnife(knife, player, echo)
    if not knife or not knife:Exists() then return false end
    local data = knife:GetData()
    if echo then
        local child = data.MizukiEchoChild
        return data.MizukiEchoKnife == true and data.MizukiEchoFired == true
            and child and child.Shot and not child.Shot.Removed and child.Shot.Player
            and child.Shot.Player.InitSeed == player.InitSeed
            and GetPtrHash(child.Shot.Player) == GetPtrHash(player)
    end
    return data.MizukiCannonKnife == true and data.MizukiCannonKnifeAuxiliary ~= true
        and sameEntity(data.MizukiCannonKnifeOwner, data.MizukiCannonKnifeOwnerInitSeed,
            data.MizukiCannonKnifeOwnerPtrHash)
        and GetPtrHash(data.MizukiCannonKnifeOwner) == GetPtrHash(player)
end

local function originalKnife(player, beams)
    for _, beam in ipairs(beams) do
        if beam.MomKnifeDriven then
            local knife = beam.MomKnife
            if not knife or not knife:Exists() or knife.InitSeed ~= beam.MomKnifeInitSeed then
                return nil, true
            end
            local data = knife:GetData()
            if data.MizukiCannonKnifeAuxiliary == true then
                knife = data.MizukiCannonKnifeMotionSource
                if not sameEntity(knife, data.MizukiCannonKnifeMotionSourceInitSeed,
                    data.MizukiCannonKnifeMotionSourcePtrHash) then return nil, true end
            end
            -- Resolve the persistent body, even when this volley only added
            -- auxiliary knives. Do not choose a new knife by angular proximity.
            return ownedKnife(knife, player, false) and knife or nil, true
        end
    end
end

local function ownedFlame(record)
    return sameEntity(record.Flame, record.FlameSeed, record.FlameHash)
        and record.Flame:GetData().MizukiPepperKnifeFlame == true
end

local function removeAttachedFlame(record)
    -- The explicit flame identity guards deletion; never remove the anchor.
    if ownedFlame(record) then record.Flame:Remove() end
end

local function syncAttachedFlame(record)
    if not ownedFlame(record) then return false end
    local knife, player = record.Knife, record.Player
    if not sameEntity(player, record.PlayerSeed, record.PlayerHash) or player:IsDead()
        or not sameEntity(knife, record.KnifeSeed, record.KnifeHash)
        or not ownedKnife(knife, player, record.Echo)
        or (not record.Echo and knife:GetData().MizukiCannonKnifeState == "follow")
        or (not knife:IsFlying() and record.BornFrame ~= Game():GetFrameCount()) then
        removeAttachedFlame(record)
        return false
    end
    -- The attachment uses the knife's grid rule, not the free flame's push-out
    -- rule. Keep enemy collision, flame size/damage and native fading intact.
    record.Flame.GridCollisionClass = knife.GridCollisionClass
    -- FollowParent owns movement in the native effect physics pass. Do not
    -- teleport it back or clear its velocity after native wall/interpolation
    -- handling. ParentOffset is zero; knife sprite height is never inherited.
    return true
end

local function hasPeppers(player)
    return player:HasCollectible(BLUE) or player:HasCollectible(RED)
end

local function getState(data)
    local state = data.MizukiPepperState
    if not state or state.Runtime ~= runtime then
        state = { Shots = {}, Continuous = {}, DelayClocks = {},
            EchoShots = {}, ReplayEvents = {}, Runtime = runtime }
        data.MizukiPepperState = state
    end
    return state
end

local function rollFlame(player, direction, towardCannon)
    if not direction or direction:LengthSquared() <= 0.000001 then return {Fired = false} end
    local blue, red = player:HasCollectible(BLUE), player:HasCollectible(RED)
    if not blue and not red then return {Fired = false} end
    -- Native weapon code converts luck to an integer by truncating toward zero.
    local luck = player.Luck >= 0 and math.floor(player.Luck) or math.ceil(player.Luck)
    local denominator = blue and red and math.max(1, 8 - luck) or math.max(2, 12 - luck)
    local rng = player:GetCollectibleRNG(blue and BLUE or RED)
    if rng:RandomInt(denominator) ~= 0 then return {Fired = false} end
    -- Both peppers share the opportunity: one flame, with an equal color roll.
    local useBlue = blue and (not red or rng:RandomInt(2) == 1)
    local aim = direction:Normalized()
    -- Native pepper velocity is (aim * 10 + tear movement inheritance) * 1.4.
    -- Targeted flames must point exactly at the cannon, without movement drift.
    local velocity = towardCannon and aim * 14
        or (aim * 10 + player:GetTearMovementInheritance(aim)) * 1.4
    -- Native pepper creation uses the normal tear's scale, before applying its
    -- 4x/6x flame damage. Set it once; the effect retains its native fading.
    local tearScale = player:GetTearHitParams(WeaponType.WEAPON_TEARS, 1, 1).TearScale
    return { Fired = true,
        Variant = useBlue and EffectVariant.BLUE_FLAME or EffectVariant.RED_CANDLE_FLAME,
        Damage = player.Damage * (useBlue and 6 or 4), Scale = tearScale,
        Timeout = useBlue and 60 or 300, Velocity = Vector(velocity.X, velocity.Y) }
end

local function spawnFlame(player, result, origin, knife, echoMode)
    if not result or not result.Fired then return end
    local flame = Isaac.Spawn(EntityType.ENTITY_EFFECT,
        result.Variant, 0, knife and knife.Position or origin,
        knife and Vector.Zero or Vector(result.Velocity.X, result.Velocity.Y), player):ToEffect()
    flame:GetData().MizukiPepperFlame = true
    flame.SpriteScale = Vector(result.Scale, result.Scale)
    flame.CollisionDamage = result.Damage
    flame:SetTimeout(result.Timeout)
    if echoMode then
        local alpha = echoMode == "finite" and Mizuki.CannonEchoReplayAlpha or Mizuki.CannonEchoPersistentAlpha
        if not Mizuki.bindEchoAttackReplay(flame, result.AttackSequence, {
            Alpha = alpha, Tint = true, DamageMultiplier = 1}) then
            flame.Color = Mizuki.getCannonEchoColor(result.Color or flame.Color, alpha)
        end
    else
        result.Color = Color.Lerp(flame.Color, flame.Color, 0)
        if Mizuki.hasCannonEcho(player) then result.AttackSequence = Mizuki.startEchoAttackRecording(flame) end
    end
    if knife then
        flame:GetData().MizukiPepperKnifeFlame = true
        -- Native FollowParent captures Position - parent.Position. Both start
        -- at the knife collision center, so no artwork offset is added.
        flame:FollowParent(knife)
        local record = { Flame = flame, FlameSeed = flame.InitSeed, FlameHash = GetPtrHash(flame),
            Knife = knife, KnifeSeed = knife.InitSeed, KnifeHash = GetPtrHash(knife),
            Player = player, PlayerSeed = player.InitSeed, PlayerHash = GetPtrHash(player),
            Echo = echoMode == "finite", BornFrame = Game():GetFrameCount() }
        attachedFlames[#attachedFlames + 1] = record
        syncAttachedFlame(record)
    end
end

local function opportunity(player, direction, towardCannon, attack, elapsed, knife)
    local result = rollFlame(player, direction, towardCannon)
    spawnFlame(player, result, player.Position, knife)
    if attack then
        local events = attack.PepperEvents
        events[#events + 1] = { Elapsed = elapsed, Result = result }
    end
    return result
end

-- One roll for a real gbt volley. Echoes reuse the result, never reroll it.
function Mizuki.fireFanPepper(player, familiar, direction)
    local result = rollFlame(player, direction, false)
    spawnFlame(player, result, familiar.Position)
    return result
end

function Mizuki.replayFanPepper(player, result, origin)
    spawnFlame(player, result, origin, nil, "finite")
end

-- Melee is a real attack even when no ranged beam is released.
function Mizuki.recordMeleePepperAttack(player, direction)
    if hasPeppers(player) then opportunity(player, direction, false) end
end

local function liveBeam(beam)
    if beam and beam.TrisagionShot then return beam.Tear and beam.Tear:Exists() end
    return beam and beam.Laser and beam.Laser:Exists()
end

-- Called once by the real firing controller, after all of its beams exist.
function Mizuki.recordPepperAttack(player, direction, beams, automatic, periodic, duration, echo)
    if #beams == 0 or echo then return end
    local attack = beams[1].PepperAttack or {
        Direction = Vector(direction.X, direction.Y), Duration = duration, Periodic = periodic,
    }
    attack.PepperEvents = attack.PepperEvents or {}
    attack.PepperStartFrame = attack.PepperStartFrame or Game():GetFrameCount()
    for _, beam in ipairs(beams) do beam.PepperAttack = attack end
    if not hasPeppers(player) then return end
    local data = player:GetData()
    -- These modes own a single delay clock, not an extra firing-event proc.
    if data.MizukiCannonAutoFireState == "deployed"
        or Mizuki.usesLudovicoWeapon(player) then return end
    local state = getState(data)
    local tethered = beams[1] and beams[1].TechXDriven and beams[1].TechXLinked
    if tethered then
        attack.TechXTethered, attack.Periodic = true, true
        state.Shots[#state.Shots + 1] = {
            Beams = beams, Direction = Vector(direction.X, direction.Y),
            Elapsed = 0, Duration = duration, BornFrame = Game():GetFrameCount(), Attack = attack,
        }
    elseif automatic then
        if not state.Continuous.original then
            state.Continuous.original = { Frame = Game():GetFrameCount(), Elapsed = 0 }
        end
    elseif periodic and not player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        state.Shots[#state.Shots + 1] = {
            Beams = beams, Direction = Vector(direction.X, direction.Y),
            Elapsed = 0, Duration = duration, BornFrame = Game():GetFrameCount(),
            Attack = attack,
        }
    else
        local knife, knifeAttack = originalKnife(player, beams)
        if not knifeAttack or knife then opportunity(player, direction, false, attack, 0, knife) end
    end
end

local function pairCenter(data, echo)
    local total, count, first = Vector.Zero, 0, nil
    for side = 1, 2 do
        for _, cannon in ipairs(data.MizukiCannons and data.MizukiCannons[side] or {}) do
            if cannon and cannon:Exists() then
                local cannonData = cannon:GetData()
                if (cannonData.MizukiPersistentEchoMode ~= nil) == echo
                    and not cannonData.MizukiAwaitingInitialLayout then
                    -- Entity.Position is the native familiar collision center.
                    -- Do not add sprite pivot, hover, shadow or ground-aim offsets.
                    total, count = total + cannon.Position, count + 1
                    first = first or cannon
                    break -- the first pair; extra multishot pairs do not add procs
                end
            end
        end
    end
    return count > 0 and total * (1 / count) or nil, first
end

local function updateFiniteReplay(player, replay)
    local ghost = replay.Ghost
    if not sameEntity(ghost, replay.GhostSeed, replay.GhostHash) then return false end
    local live = false
    for _, child in ipairs(replay.Children) do
        if liveBeam(child) then live = true; break end
    end
    if not live then return false end
    if replay.KnifeMode and (not sameEntity(replay.Knife, replay.KnifeSeed, replay.KnifeHash)
        or not ownedKnife(replay.Knife, player, true) or not replay.Knife:IsFlying()) then return false end
    local events = replay.Attack.PepperEvents
    while events[replay.NextEvent] and events[replay.NextEvent].Elapsed <= replay.Elapsed do
        local event = events[replay.NextEvent]
        spawnFlame(player, event.Result, ghost.Position, replay.Knife, "finite")
        replay.NextEvent = replay.NextEvent + 1
    end
    if replay.Attack.TechXTethered then return live end
    return (replay.Attack.Periodic or replay.Attack.Deployed) and replay.Elapsed < 600
end

-- A finite echo shares the original attack's event log. Source attacks may
-- still be recording later periodic events while an earlier echo has begun.
function Mizuki.recordPepperEchoAttack(player, attack, children)
    if not attack.PepperEvents or #children == 0 then return end
    local first, ghost = children[1], children[1].Ghost
    if not ghost or not ghost:Exists() then return end
    local replay = { Attack = attack, Children = children,
        Ghost = ghost, GhostSeed = ghost.InitSeed, GhostHash = GetPtrHash(ghost),
        KnifeMode = first.KnifeMode, NextEvent = 1, Elapsed = 0, BornFrame = Game():GetFrameCount() }
    if first.KnifeMode then
        local original = first.Shot and first.Shot.Children[1]
        local knife = original and original.Knife
        if not ownedKnife(knife, player, true) then return end
        replay.Knife, replay.KnifeSeed, replay.KnifeHash = knife, knife.InitSeed, GetPtrHash(knife)
    end
    if updateFiniteReplay(player, replay) then
        local state = getState(player:GetData())
        state.EchoShots[#state.EchoShots + 1] = replay
    end
end

local function updateDelay(player, state, mode)
    -- MaxFireDelay itself, matching the measured Ludovico 10-frame period at 10.
    local interval = math.max(1, player.MaxFireDelay)
    local clock = state.DelayClocks.original
    if not clock or clock.Mode ~= mode then
        clock = { Elapsed = 0, Interval = interval, Mode = mode }
        state.DelayClocks.original = clock
    elseif clock.Interval ~= interval then
        clock.Elapsed = clock.Elapsed * interval / clock.Interval
    end
    clock.Interval = interval
    clock.Elapsed = clock.Elapsed + 1
    if clock.Elapsed >= interval then
        clock.Elapsed = clock.Elapsed - interval
        return true
    end
end

local function queuePersistentReplay(state, mode, result, sources)
    local delay = mode == "ludovico" and 0 or Mizuki.CannonEchoFollowDelay
    state.ReplayEvents[#state.ReplayEvents + 1] = {
        Frame = Game():GetFrameCount() + delay, Mode = mode, Result = result, Sources = sources,
    }
end

local function updatePersistentReplay(player, state, mode, echoes)
    local frame = Game():GetFrameCount()
    for index = #state.ReplayEvents, 1, -1 do
        local event = state.ReplayEvents[index]
        if event.Mode ~= mode or event.Frame <= frame then
            local cannon
            -- Do not burst stale events after a controls/room-transition pause.
            -- Only the exact delayed source frame is eligible to replay.
            if event.Mode == mode and event.Frame == frame then
                if mode == "automatic" then
                    for _, beam in ipairs(echoes) do
                        for _, source in ipairs(event.Sources) do
                            if beam.PersistentEchoSourceSeed == source.Seed
                                and beam.PersistentEchoSourceHash == source.Hash then
                                cannon = beam.Cannon
                                break
                            end
                        end
                        if cannon then break end
                    end
                else
                    local _, first = pairCenter(player:GetData(), true)
                    cannon = first
                end
                if cannon and cannon:Exists() then
                    spawnFlame(player, event.Result, cannon.Position, nil, "persistent")
                end
            end
            table.remove(state.ReplayEvents, index)
        end
    end
end

local function latestFiniteAttack(data)
    local latest
    for side = 1, 2 do
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            local attack = beam.PepperAttack
            if liveBeam(beam) and not beam.Automatic and not beam.PersistentEchoMode
                and attack and attack.PepperEvents and attack.PepperStartFrame
                and (not latest or attack.PepperStartFrame > latest.PepperStartFrame) then
                latest = attack
            end
        end
    end
    return latest
end

function Mizuki:UpdatePepperAttacks(player)
    if not Mizuki.isMizuki(player) then return end
    local data = player:GetData()
    if Mizuki.usesCSectionWeapon(player) then
        data.MizukiPepperState = nil
        return
    end
    if player:IsDead() then
        data.MizukiPepperState = nil
        return
    end
    if Game():IsPaused() or not player:AreControlsEnabled() then return end
    local canRoll = hasPeppers(player)
    if not canRoll and not data.MizukiPepperState then return end
    local state = getState(data)
    if not canRoll then
        state.Shots, state.Continuous, state.DelayClocks = {}, {}, {}
        if #state.EchoShots == 0 and #state.ReplayEvents == 0 then
            data.MizukiPepperState = nil
            return
        end
    end
    local frame = Game():GetFrameCount()
    if state.LastUpdateFrame == frame then return end
    state.LastUpdateFrame = frame
    for index = #state.EchoShots, 1, -1 do
        local replay = state.EchoShots[index]
        if replay.BornFrame ~= frame then replay.Elapsed = replay.Elapsed + 1 end
        if not updateFiniteReplay(player, replay) then table.remove(state.EchoShots, index) end
    end
    local ring = data.MizukiLudovicoRing
    local mode = Mizuki.usesLudovicoWeapon(player)
        and ring and ring:Exists() and "ludovico"
        or data.MizukiCannonAutoFireState == "deployed" and "deployed"
    if mode then
        state.Shots = {}
        state.Continuous = {}
        local center = pairCenter(data, false)
        -- Original flames retain the requested aim at the collision center.
        local target = mode == "ludovico" and center and ring.Position or center
        if canRoll and target and updateDelay(player, state, mode) then
            local attack = mode == "deployed" and latestFiniteAttack(data) or nil
            local result = opportunity(player, target - player.Position, true,
                attack, attack and frame - attack.PepperStartFrame or 0)
            queuePersistentReplay(state, mode, result)
        elseif not target then
            state.DelayClocks.original = nil
        end
        updatePersistentReplay(player, state, mode)
        return
    end
    state.DelayClocks = {}
    if data.MizukiCannonAutoFireState == "returning" then
        state.Shots = {}
        state.Continuous = {}
        state.EchoShots = {}
        state.ReplayEvents = {}
        return
    end

    for index = #state.Shots, 1, -1 do
        local shot = state.Shots[index]
        local live = false
        for _, beam in ipairs(shot.Beams) do
            if liveBeam(beam) and (not shot.Attack.TechXTethered or not beam.Ending) then
                live = true; break
            end
        end
        if not live then
            table.remove(state.Shots, index)
        elseif shot.BornFrame ~= frame then
            shot.Elapsed = shot.Elapsed + 1
            -- The native shrink tail is still part of the finite attack.
            -- At 19/17 total frames, opportunities occur at 4, 8, 12, 16 only.
            if (shot.Attack.TechXTethered or shot.Elapsed <= shot.Duration) and shot.Elapsed % PERIOD == 0 then
                opportunity(player, shot.Direction, false, shot.Attack, shot.Elapsed)
            end
            if not shot.Attack.TechXTethered and shot.Elapsed >= shot.Duration then table.remove(state.Shots, index) end
        end
    end

    local original, sources, echoes = nil, {}, {}
    for side = 1, 2 do
        local source
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            if liveBeam(beam) and beam.Automatic and not beam.Ending and not beam.SpiritSwordDriven then
                if beam.PersistentEchoMode then echoes[#echoes + 1] = beam
                else
                    original, source = original or beam, source or beam
                end
            end
        end
        if source then sources[#sources + 1] = {Seed = source.Laser.InitSeed, Hash = GetPtrHash(source.Laser)} end
    end
    if original and canRoll then
        local clock = state.Continuous.original or { Elapsed = 0 }
        if clock.Frame ~= frame then
            clock.Elapsed = clock.Elapsed + 1
            if clock.Elapsed >= PERIOD then
                clock.Elapsed = 0
                local result = opportunity(player,
                    original.Direction:Rotated(-(original.DirectionOffset or 0)), false)
                queuePersistentReplay(state, "automatic", result, sources)
            end
        end
        clock.Frame = frame
        state.Continuous.original = clock
    else
        state.Continuous.original = nil
    end
    updatePersistentReplay(player, state, "automatic", echoes)
end

local function reset()
    for _, record in ipairs(attachedFlames) do removeAttachedFlame(record) end
    attachedFlames = {}
    for index = 0, Game():GetNumPlayers() - 1 do
        Isaac.GetPlayer(index):GetData().MizukiPepperState = nil
    end
end

-- Registered after the main weapon callback: layouts and attack state are current.
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdatePepperAttacks)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, reset)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, reset)

-- Validate attachment lifetimes and synchronize the anchor's grid rule.
-- Native FollowParent owns movement; no post-update teleports or timeout refreshes.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, 100, function(_, knife)
    for _, record in ipairs(attachedFlames) do
        if record.KnifeHash == GetPtrHash(knife) then syncAttachedFlame(record) end
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, effect)
    if effect:GetData().MizukiPepperKnifeFlame ~= true then return end
    for _, record in ipairs(attachedFlames) do
        if record.FlameHash == GetPtrHash(effect) then syncAttachedFlame(record); return end
    end
    -- Hot reload loses local attachment records, but entity data survives.
    -- Only explicitly marked attached flames may enter this orphan cleanup.
    effect:Remove()
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    for index = #attachedFlames, 1, -1 do
        if not syncAttachedFlame(attachedFlames[index]) then table.remove(attachedFlames, index) end
    end
end)
