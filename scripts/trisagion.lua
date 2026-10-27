-- Native moving Trisagion tears; short technology rings follow their centres.
Mizuki.TrisagionParameters = {
    Interval = Mizuki.DEFAULT_BEAM_DURATION, PulseTimeout = 3, PulseRadius = 50,
    PulseForwardOffset = 45, -- pixels along the tear's current flight direction
}
local pendingEchoes = {}
local spawningWave
local function copy(v) return Vector(v.X, v.Y) end
local function alive(e) return e and e:Exists() and not e:IsDead() end

function Mizuki.usesCannonTrisagion(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_TRISAGION)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
        and not Mizuki.usesLudovicoWeapon(player)
        and not (player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO)
            and Mizuki.canUseTechnologyZeroWeaponEffect(player))
        and not Mizuki.usesCannonTechX(player) and not Mizuki.cannonUsesKnifeWeapon(player)
end

local function pulseOffset(tear, data)
    if tear.Velocity:Length() > 0 then data.Direction = tear.Velocity:Normalized() end
    data.Direction = data.Direction or Vector(1, 0) -- pre-reload stationary pulse
    return data.Direction:Resized(Mizuki.TrisagionParameters.PulseForwardOffset)
end

local function updatePulseGeometry(ring, tear, data)
    ring.ParentOffset = pulseOffset(tear, data)
    ring.Radius = Mizuki.TrisagionParameters.PulseRadius * tear.Scale
end

-- FireTear can create its light laser synchronously, before the tear is returned.
Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_INIT, function(_, laser)
    if spawningWave and laser.Variant == LaserVariant.LIGHT_BEAM then
        spawningWave.NativeLaser = laser
        laser:GetData().MizukiTrisagionNativeLaser = true
        laser:GetData().MizukiBeamOwner = spawningWave.Emitter.Player
    end
end)

local function bindReplay(entity, sequence, emitter)
    if sequence then
        Mizuki.bindEchoAttackReplay(entity, sequence, {
            Alpha = Mizuki.CannonEchoReplayAlpha, Tint = true,
            DamageMultiplier = emitter.ReplayMultiplier, LaserSpawner = emitter.Cannon,
        })
    end
end

local function pulse(tear, shot, index)
    local emitter = shot.Emitter
    local original = shot.Source and shot.Source.Pulses[index]
    if shot.Source and not original then return end
    local player = emitter.Player
    if not alive(player) then return end
    local p = Mizuki.TrisagionParameters
    local pulseData = { Tear = tear, Seed = tear.InitSeed,
        Direction = shot.Direction and copy(shot.Direction) or nil }
    local offset = pulseOffset(tear, pulseData)
    local ring = player:FireTechXLaser(tear.Position + offset, copy(tear.Velocity),
        p.PulseRadius * tear.Scale, player, 1)
    -- Native technology/melee rings use subtype 3, not the travelling Tech X
    -- subtype 2. Keep the engine's short tick/fade cycle, without forced Update.
    ring.SubType = LaserSubType.LASER_SUBTYPE_RING_FOLLOW_PARENT
    ring.Parent = tear
    updatePulseGeometry(ring, tear, pulseData)
    ring.DisableFollowParent = false
    -- Set the actual birth velocity as well as the factory's velocity input;
    -- parent-following has not run yet when this pulse is first created.
    ring.Velocity = copy(tear.Velocity)
    ring.Timeout = p.PulseTimeout
    ring.PositionOffset = copy(tear.PositionOffset)
    ring.TearFlags = tear.TearFlags & ~TearFlags.TEAR_LASERSHOT
        & ~Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS
    -- Preserve the resolved shot's RGB/offset/alpha, but set the pulse's
    -- character colorize directly. It never divides by the tear intensity.
    ring.Color = Mizuki.getCharacterTearTint(player, nil, tear.Color)
    ring.CollisionDamage = alive(shot.NativeLaser) and shot.NativeLaser.CollisionDamage
        or tear.CollisionDamage
    local cannon = emitter.Cannon
    if alive(cannon) then
        -- As with echo lasers, a custom familiar spawner prevents the native
        -- player refresh from replacing the wave's already resolved proc.
        ring.SpawnerEntity = cannon
        ring.SpawnerType = cannon.Type
        ring.SpawnerVariant = cannon.Variant
    end
    ring:GetData().MizukiTrisagionPulse = pulseData
    ring:GetData().MizukiBeamOwner = player
    Mizuki.attachDeadEyeBranch(tear, ring)
    shot.LivePulses = shot.LivePulses or {}
    shot.LivePulses[#shot.LivePulses + 1] = { Entity = ring, Seed = ring.InitSeed }
    if original then
        bindReplay(ring, original, emitter)
    else
        shot.Pulses[index] = Mizuki.startEchoAttackRecording(ring)
    end
end

function Mizuki.fireCannonTrisagion(player, cannon, parameters, damageMultiplier, source, replayMultiplier)
    local emitter = { Player = player, Cannon = cannon,
        ReplayMultiplier = replayMultiplier or Mizuki.CannonEchoDamageMultiplier }
    local shot = { Emitter = emitter, Source = source, Pulses = {}, LivePulses = {},
        Origin = copy(parameters.Origin), Direction = copy(parameters.Direction),
        DamageMultiplier = damageMultiplier, BirthFrame = Game():GetFrameCount() }
    spawningWave = shot
    local velocity = source and source.BirthVelocity or parameters.Direction:Resized(
        player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed)
    local ok, tear = pcall(player.FireTear, player, copy(shot.Origin), copy(velocity),
        false, false, false, player, damageMultiplier)
    spawningWave = nil
    if not ok then error(tear) end
    tear:AddTearFlags(TearFlags.TEAR_LASERSHOT)
    tear:ClearTearFlags(Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS)
    shot.Tear, shot.BirthVelocity = tear, copy(tear.Velocity)
    shot.BirthScale, shot.BirthHeight = tear.Scale, tear.Height
    shot.BirthFallingSpeed, shot.BirthFallingAcceleration = tear.FallingSpeed, tear.FallingAcceleration
    tear:GetData().MizukiCannonTrisagionShot = shot
    if alive(shot.NativeLaser) then
        shot.NativeLaser.Color = Color.Lerp(tear.Color, tear.Color, 0)
    end
    if source then
        tear.Scale, tear.Height = source.BirthScale, source.BirthHeight
        tear.FallingSpeed, tear.FallingAcceleration = source.BirthFallingSpeed, source.BirthFallingAcceleration
        bindReplay(tear, source.TearSequence, emitter)
        if alive(shot.NativeLaser) then bindReplay(shot.NativeLaser, source.LaserSequence, emitter) end
    else
        Mizuki.trackDeadEyeProjectile(player, tear)
        Mizuki.attachDeadEyeBranch(tear, shot.NativeLaser)
        shot.TearSequence = Mizuki.startEchoAttackRecording(tear)
        if alive(shot.NativeLaser) then shot.LaserSequence = Mizuki.startEchoAttackRecording(shot.NativeLaser) end
    end
    pulse(tear, shot, 1)
    shot.NextPulse = 2
    return shot
end

function Mizuki.queueAutomaticTrisagionEcho(player, cannon, shot)
    if not Mizuki.hasCannonEcho(player) or Mizuki.getPersistentCannonEchoMode(player) ~= "automatic" then return end
    local side = cannon:GetData().CannonSide
    local cannons = player:GetData().MizukiCannons
    local original = cannons and cannons[side] and cannons[side][1]
    if not Mizuki.isSameEntity(cannon, original) then return end
    pendingEchoes[#pendingEchoes + 1] = { Player = player, Source = shot,
        Side = side,
        Frame = Game():GetFrameCount() + Mizuki.CannonEchoFollowDelay }
end

Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
    local shot = tear:GetData().MizukiCannonTrisagionShot
    if not shot then return end
    shot.LivePulses = shot.LivePulses or {}
    -- Prepare parent offset/radius from the current tear before the ring's
    -- native follow/path pass. Keep its birth-only visual height unchanged.
    for i = #shot.LivePulses, 1, -1 do
        local record = shot.LivePulses[i]
        local ring = record.Entity
        if alive(ring) and ring.InitSeed == record.Seed then
            updatePulseGeometry(ring, tear, ring:GetData().MizukiTrisagionPulse)
        else table.remove(shot.LivePulses, i) end
    end
    local age = Game():GetFrameCount() - shot.BirthFrame
    if age >= (shot.NextPulse - 1) * Mizuki.TrisagionParameters.Interval then
        pulse(tear, shot, shot.NextPulse)
        shot.NextPulse = shot.NextPulse + 1
    end
end)

Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
    local data = laser:GetData()
    local pulseData = data.MizukiTrisagionPulse
    if pulseData then
        local tear = pulseData.Tear
        if alive(tear) and tear.InitSeed == pulseData.Seed then
            -- Subtype 3 copies its parent's position AND velocity before native
            -- path generation (0x97C3C3..0x97C424). A post-update teleport only
            -- moves Entity.Position, leaving the rendered path one step behind.
            -- Also repair pulses already alive when this code is hot-reloaded.
            if laser.DisableFollowParent then
                updatePulseGeometry(laser, tear, pulseData)
                laser.DisableFollowParent = false
            end
        else
            laser.Timeout = 0
            laser.Shrink = true
        end
    end
    local parent = laser.Parent
    local shot = parent and parent:ToTear() and parent:GetData().MizukiCannonTrisagionShot
    if shot and laser.Variant == LaserVariant.LIGHT_BEAM and not pulseData then
        laser:GetData().MizukiTrisagionNativeLaser = true
        laser:GetData().MizukiBeamOwner = shot.Emitter.Player
        -- LIGHT_BEAM is the tear's native visible body, not its pulse ring.
        if alive(parent) then laser.Color = Color.Lerp(parent.Color, parent.Color, 0) end
        if not Mizuki.isSameEntity(shot.NativeLaser, laser) then
            shot.NativeLaser = laser
            if shot.Source then bindReplay(laser, shot.Source.LaserSequence, shot.Emitter)
            else
                Mizuki.attachDeadEyeBranch(parent, laser)
                shot.LaserSequence = Mizuki.startEchoAttackRecording(laser)
            end
        end
    end
end)

Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    local frame = Game():GetFrameCount()
    for i = #pendingEchoes, 1, -1 do
        local entry = pendingEchoes[i]
        if not alive(entry.Player) or not Mizuki.hasCannonEcho(entry.Player)
            or Mizuki.getPersistentCannonEchoMode(entry.Player) ~= "automatic" then
            table.remove(pendingEchoes, i)
        elseif frame >= entry.Frame then
            local cannons = entry.Player:GetData().MizukiCannons
            local side = cannons and cannons[entry.Side]
            local ghost = side and side[#side]
            if alive(ghost) and ghost:GetData().MizukiPersistentEchoMode == "automatic" then
                local source = entry.Source
                local geometry = Mizuki.getCannonLaserGeometry(entry.Player, ghost, source.Direction, 0)
                Mizuki.fireCannonTrisagion(entry.Player, ghost, geometry,
                    source.DamageMultiplier, source, Mizuki.CannonEchoDamageMultiplier)
                table.remove(pendingEchoes, i)
            end
        end
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() pendingEchoes = {} end)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() pendingEchoes = {} end)
