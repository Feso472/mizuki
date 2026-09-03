local Mizuki = RegisterMod("Mizuki", 1)

-- Vanilla Repentance+ only. Mizuki's beam uses a native EntityLaser for
-- collision, damage ticks and tear-effect compatibility. Lua still owns its
-- charge cycle and keeps the laser anchored to the firing cannon position.
Mizuki.PlayerType = Isaac.GetPlayerTypeByName("弥月", false)
Mizuki.CannonVariant = Isaac.GetEntityVariantByName("Mizuki Cannon")
Mizuki.ExperimentalCapsuleCard = Isaac.GetCardIdByName("Mizuki Experimental Capsule")
local EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = 9201

-- Present the capsule as an ordinary Experimental Pill. Register after the
-- game starts because EID rebuilds its icon tables during its own startup.
local function registerExperimentalCapsuleEID()
    if not EID or not EID.addCard or not EID.addIcon then
        return
    end

    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ 随机提升1项属性#↓ 随机降低1项属性",
        "实验性胶囊",
        "zh_cn"
    )
    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ Increases 1 random stat#↓ Decreases 1 random stat",
        "Experimental Pill",
        "en_us"
    )

    local capsuleEIDIcon = Sprite()
    capsuleEIDIcon:Load("gfx/items/mizuki/experimental_capsule.anm2", true)
    capsuleEIDIcon:Play("EID", true)
    EID:addIcon(
        "Card" .. Mizuki.ExperimentalCapsuleCard,
        "EID",
        0,
        9,
        8,
        0,
        1,
        capsuleEIDIcon
    )
end

Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerExperimentalCapsuleEID)

local GLOWING_HOUR_GLASS = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
local HOUR_GLASS = CollectibleType.COLLECTIBLE_HOURGLASS
local BOX_OF_FRIENDS = CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS
local CAPSULE_STAT_CACHE_FLAGS = CacheFlag.CACHE_DAMAGE
    | CacheFlag.CACHE_FIREDELAY
    | CacheFlag.CACHE_SPEED
    | CacheFlag.CACHE_SHOTSPEED
    | CacheFlag.CACHE_RANGE
    | CacheFlag.CACHE_LUCK

local MIN_CHARGE_PERCENT = 0.50
local TEARS_MULTIPLIER = 0.30
local TEARS_MODIFIER = 0.5
local DAMAGE_MODIFIER = -0.5
local BEAM_DISTANCE = 240
-- Mizuki begins at HUD Range 6.50, which is internal TearRange 260.
-- Its baseline beam length is anchored to that starting stat.
local BASE_TEAR_RANGE = 260
local MIN_BEAM_WIDTH_SCALE = 0.75
local MAX_BEAM_WIDTH_SCALE = 5.00
local BEAM_DAMAGE_INTERVAL = 5
-- A 42-frame native Technology beam lands 20 damage ticks in current tests.
-- Each full-charge tick deals 0.4x damage, capping one complete beam at 8x.
local BEAM_DURATION = 42
local BEAM_DAMAGE_PER_TICK_MULTIPLIER = 0.40
-- Mizuki charges manually, then releases a sustained native Technology laser.
-- Variant 2 supplies real curved-laser collision and native tear interactions.
local MIZUKI_LASER_VARIANT = 2
local MIN_CHARGE_DAMAGE_MULTIPLIER = 0.45
local MIZUKI_LASER_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
-- Colorize first converts the source to grayscale. The Technology texture is
-- primarily pure red, whose grayscale luminance is roughly one third, so the
-- requested capsule RGB needs extra brightness compensation.
MIZUKI_LASER_COLOR:SetColorize(
    5 * 246 / 255,
    5 * 171 / 255,
    5 * 180 / 255,
    1
)

local CANNON_ANM2 = "gfx/entities/mizuki/mizuki_cannon.anm2"
local LEFT_CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_left.png"
local LEFT_CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light_left.png"
local CANNON_SCALES = {
    Vector(0.65, 0.65),
    Vector(0.65, 0.65),
}
local CANNON_DEPTH_OFFSET = 70
local FIRING_CANNON_DEPTH_OFFSET = 70
local HORIZONTAL_BACK_DEPTH_OFFSET = -70
local HORIZONTAL_FRONT_DEPTH_OFFSET = 70
local CHARGE_BAR_SCALE = Vector(0.5, 0.5)
local CHARGE_BAR_OFFSET = Vector(0, 5)
-- Resting formation: two separated rabbit ears above the head.
local CANNON_OFFSETS = { Vector(-12, -60), Vector(12, -60) }
local CANNON_GROUP_SPACING = 16
local HORIZONTAL_CANNON_X = 10
-- Horizontal pair sits close to Isaac's normal tear-launch height.
-- Side 2 is the front cannon and is 5 px lower than side 1.
local HORIZONTAL_CANNON_Y = { -25, -20 }
local CANNON_FOLLOW_SPEED = 0.22
local CANNON_FLOAT_AMPLITUDE = 2
local LEFT_CANNON_IDLE_ROTATION = -55
local RIGHT_CANNON_IDLE_ROTATION = -5
local CANNON_ROTATION_RETURN_SPEED = 0.18
-- The decorative idle turn pivots around the cannon sprite's bottom centre,
-- while its Familiar entity (and therefore the beam origin) stays fixed.
local CANNON_IDLE_ROTATION_PIVOT = Vector(0, 10)

local CHARGE_BAR_COLOR = Color(1, 1, 1, 1, 1, 1, 1)
local chargeBar = Sprite()
chargeBar:Load("gfx/chargebar_revelation.anm2", true)

local function isMizuki(player)
    return player:GetPlayerType() == Mizuki.PlayerType
end

local function scalePlayerOffset(player, offset)
    local scale = player.SpriteScale
    return Vector(offset.X * scale.X, offset.Y * scale.Y)
end

-- Glowing Hour Glass rewinds EntityPlayer state, including values associated
-- with that snapshot. Keep the capsule transaction outside player:GetData()
-- so the fact that it was consumed cannot itself be rewound.
local capsuleStates = {}
-- Glowing Hour Glass also rewinds player:GetData(), so cannon-reconcile
-- bookkeeping must live outside EntityPlayer state for the same reason.
local cannonReconcileStates = {}

local function getPlayerIndex(player)
    local game = Game()
    local playerHash = GetPtrHash(player)
    for index = 0, game:GetNumPlayers() - 1 do
        if GetPtrHash(Isaac.GetPlayer(index)) == playerHash then
            return index
        end
    end
    return player.ControllerIndex or 0
end

local function getCapsuleState(player)
    local index = getPlayerIndex(player)
    capsuleStates[index] = capsuleStates[index] or {}
    return capsuleStates[index]
end

local function getCannonReconcileState(player)
    local index = getPlayerIndex(player)
    cannonReconcileStates[index] = cannonReconcileStates[index] or {}
    return cannonReconcileStates[index]
end

-- Match Brimstone's charging principle: effective Tear Delay is the interval
-- between shots, MaxFireDelay + 1. The final visible Tears stat therefore
-- directly determines the number of real frames required to fully charge.
local function getMaxChargeFrames(player)
    return math.max(1, math.ceil(player.MaxFireDelay + 1))
end

local function getMinChargeFrames(player)
    return math.ceil(getMaxChargeFrames(player) * MIN_CHARGE_PERCENT)
end

-- Like Azazel's mini-Brimstone, the beam starts short but Range ups extend it.
-- At Mizuki's starting HUD Range 6.50 (internal TearRange 260), its length is exactly 240 px.
local function getBeamDistance(player)
    return math.max(40, BEAM_DISTANCE * player.TearRange / BASE_TEAR_RANGE)
end

-- Convert the final ShotSpeed stat into real beam thickness. At the normal
-- 1.0 stat the laser keeps its native width; at 2.0 it reaches exactly 3x,
-- then approaches (but never exceeds) 5x for extreme combinations.
local function getBeamWidthScale(player)
    local shotSpeedOffset = player.ShotSpeed - 1
    local widthScale = 1
        + (MAX_BEAM_WIDTH_SCALE - 1)
        * (2 / math.pi)
        * math.atan(shotSpeedOffset)
    return math.max(widthScale, MIN_BEAM_WIDTH_SCALE)
end

-- Weapon-specific fire-rate profiles live here.  A profile first removes the
-- relevant native WeaponType Tears multiplier, then applies Mizuki's intended
-- final multiplier.  Keep the default neutral until a real synergy is added.
local function getMizukiFireRateProfile(player)
    return {
        Id = "default",
        VanillaTearsMultiplier = 1,
        TearsModifier = TEARS_MODIFIER,
        MizukiTearsMultiplier = TEARS_MULTIPLIER,
    }
end

local function cannonBelongsToPlayer(cannon, player)
    if not cannon then
        return false
    end
    local owner = cannon.Player
    if not owner and cannon.Parent then
        owner = cannon.Parent:ToPlayer()
    end
    if not owner and cannon.SpawnerEntity then
        owner = cannon.SpawnerEntity:ToPlayer()
    end
    return owner and GetPtrHash(owner) == GetPtrHash(player)
end

-- CheckFamiliar owns spawning and despawning. Lua only rebuilds stable side
-- groups from the engine-owned entities; it never creates or removes cannons.
local function claimPlayerCannons(player, data)
    local claimed = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, Mizuki.CannonVariant, -1, false, false)) do
        local cannon = entity:ToFamiliar()
        if cannonBelongsToPlayer(cannon, player) then
            cannon.Player = player
            cannon.Parent = player
            local side = cannon.SubType
            if side == 1 or side == 2 then
                table.insert(claimed[side], cannon)
            end
        end
    end

    for side = 1, 2 do
        table.sort(claimed[side], function(left, right)
            return left.InitSeed < right.InitSeed
        end)
    end

    data.MizukiCannons = claimed
end

local function ensureCannonRegistered(cannon)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local side = cannon.SubType
    if side ~= 1 and side ~= 2 then
        return
    end

    local data = player:GetData()
    data.MizukiCannons = data.MizukiCannons or { {}, {} }
    data.MizukiCannons[side] = data.MizukiCannons[side] or {}

    local group = data.MizukiCannons[side]
    local cannonHash = GetPtrHash(cannon)
    for _, existing in ipairs(group) do
        if existing and existing:Exists() and GetPtrHash(existing) == cannonHash then
            return
        end
    end

    table.insert(group, cannon)
    table.sort(group, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
end

local function prunePlayerCannons(data)
    data.MizukiCannons = data.MizukiCannons or { {}, {} }

    for side = 1, 2 do
        data.MizukiCannons[side] = data.MizukiCannons[side] or {}
        local group = data.MizukiCannons[side]
        for index = #group, 1, -1 do
            local cannon = group[index]
            if not cannon or not cannon:Exists() then
                table.remove(group, index)
            end
        end
    end
end

local function reconcilePlayerCannons(player, data)
    local expectedPerSide = 1 + player:GetEffects():GetCollectibleEffectNum(BOX_OF_FRIENDS)
    local actual = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR,
        Mizuki.CannonVariant,
        -1,
        false,
        false
    )) do
        local cannon = entity:ToFamiliar()
        if cannon and cannon:Exists() and cannonBelongsToPlayer(cannon, player) then
            local side = cannon.SubType
            if side == 1 or side == 2 then
                table.insert(actual[side], cannon)
            end
        end
    end

    local retained = { {}, {} }
    for side = 1, 2 do
        table.sort(actual[side], function(left, right)
            return left.InitSeed < right.InitSeed
        end)

        for index, cannon in ipairs(actual[side]) do
            if index <= expectedPerSide then
                table.insert(retained[side], cannon)
            else
                cannon:Remove()
            end
        end
    end

    data.MizukiCannons = retained
end

local function updateActiveBeams(player, data)
    data.MizukiActiveBeams = data.MizukiActiveBeams or {}
    local activeSides = 0
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams[side]
        if beams and #beams > 0 then
            local expired = false
            for _, beam in ipairs(beams) do
                local laser = beam.Laser
                beam.Timeout = beam.Timeout - 1
                if beam.Timeout <= 0 or not laser or not laser:Exists() then
                    if laser and laser:Exists() then
                        laser:Remove()
                    end
                    expired = true
                else
                    -- ShootAngle initially receives the player as its damage
                    -- owner, but the beam itself must stay at the captured
                    -- cannon position for its entire lifetime.
                    laser.Position = beam.Origin
                    laser.Velocity = Vector.Zero
                    laser:SetMaxDistance(beam.Distance)

                    -- Refresh at the beam's damage cadence. This lets native
                    -- laser-context random effects (notably Fruit Cake)
                    -- change during a sustained shot without rerolling every
                    -- render frame.
                    if beam.Timeout % BEAM_DAMAGE_INTERVAL == 0 then
                        local params = player:GetTearHitParams(
                            WeaponType.WEAPON_LASER,
                            beam.DamageMultiplier,
                            1,
                            laser
                        )
                        laser.TearFlags = params.TearFlags
                        laser.CollisionDamage = params.TearDamage
                    end
                end
            end

            if expired then
                data.MizukiActiveBeams[side] = nil
                data.MizukiLockedCannonPositions[side] = nil
                data.MizukiLockedCannonAims[side] = nil
            else
                activeSides = activeSides + 1
            end
        end
    end
    return activeSides
end

local function updateCannonPositions(player, data)
    prunePlayerCannons(data)
    local targetPositions = { {}, {} }
    local aim = data.MizukiCannonAim
    local isHorizontal = aim and math.abs(aim.X) > math.abs(aim.Y)
    for side = 1, 2 do
        for member = 1, #data.MizukiCannons[side] do
            if isHorizontal then
                local horizontalSide = aim.X >= 0 and 1 or -1
                local outward = side == 1 and -(member - 1) or (member - 1)
                local horizontalOffset = Vector(
                    horizontalSide * HORIZONTAL_CANNON_X,
                    HORIZONTAL_CANNON_Y[side] + outward * CANNON_GROUP_SPACING
                )
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, horizontalOffset)
            else
                local outward = side == 1 and -(member - 1) or (member - 1)
                local restingOffset = CANNON_OFFSETS[side]
                    + Vector(outward * CANNON_GROUP_SPACING, 0)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, restingOffset)
            end
        end
    end

    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    for side = 1, 2 do
        if data.MizukiActiveBeams and data.MizukiActiveBeams[side] then
            for member = 1, #targetPositions[side] do
                targetPositions[side][member] = data.MizukiLockedCannonPositions[side][member]
                    or targetPositions[side][member]
            end
        end
    end

    data.MizukiCannonPositions = { {}, {} }
    local frame = Game():GetFrameCount()
    for side = 1, 2 do
        for member, targetPosition in ipairs(targetPositions[side]) do
            local cannon = data.MizukiCannons[side][member]
            local isFiring = data.MizukiActiveBeams and data.MizukiActiveBeams[side]
            local bobOffset = Vector(0, math.sin(frame * 0.16) * CANNON_FLOAT_AMPLITUDE)
            if isFiring then
                cannon.Position = targetPosition + bobOffset
            else
                local floatingTarget = targetPosition + bobOffset
                cannon.Position = cannon.Position + (floatingTarget - cannon.Position) * CANNON_FOLLOW_SPEED
            end
            cannon.Velocity = Vector.Zero
            if isFiring then
                -- Keep the firing group decisively above the native laser;
                -- depth zero can alternate around Technology's moving render
                -- position as the beam animates.
                cannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
            elseif isHorizontal then
                cannon.DepthOffset = side == 2
                    and HORIZONTAL_FRONT_DEPTH_OFFSET
                    or HORIZONTAL_BACK_DEPTH_OFFSET
            else
                cannon.DepthOffset = CANNON_DEPTH_OFFSET
            end
            local cannonAim = data.MizukiLockedCannonAims[side]
                or data.MizukiCannonAim or Vector(0, -1)
            local cannonData = cannon:GetData()
            cannonData.MizukiCannonAim = cannonAim
            cannonData.CannonSide = side
            local sideIdleRotation = side == 1
                and LEFT_CANNON_IDLE_ROTATION
                or RIGHT_CANNON_IDLE_ROTATION
            local idleRotationTarget = not data.MizukiHasShootingInput
                and (data.MizukiCharge or 0) <= 0
                and not isFiring
                and sideIdleRotation
                or 0
            if cannonData.MizukiIdleRotationOffset == nil then
                cannonData.MizukiIdleRotationOffset = idleRotationTarget
            else
                cannonData.MizukiIdleRotationOffset = cannonData.MizukiIdleRotationOffset
                    + (idleRotationTarget - cannonData.MizukiIdleRotationOffset)
                    * CANNON_ROTATION_RETURN_SPEED
                if math.abs(cannonData.MizukiIdleRotationOffset - idleRotationTarget) < 0.1 then
                    cannonData.MizukiIdleRotationOffset = idleRotationTarget
                end
            end
            local baseRotation = cannonAim:GetAngleDegrees() + 90
            local idleRotation = cannonData.MizukiIdleRotationOffset
            local sprite = cannon:GetSprite()
            sprite.Rotation = baseRotation + idleRotation
            local pivotCorrection = CANNON_IDLE_ROTATION_PIVOT
                - CANNON_IDLE_ROTATION_PIVOT:Rotated(idleRotation)
            sprite.Offset = pivotCorrection:Rotated(baseRotation)
            data.MizukiCannonPositions[side][member] = Vector(cannon.Position.X, cannon.Position.Y)
        end
    end
end

local function updateCannonReconcile(player, data)
    local reconcileState = getCannonReconcileState(player)
    if not reconcileState.Frames then
        return
    end

    reconcileState.Frames = reconcileState.Frames - 1
    if reconcileState.Frames <= 0 then
        reconcileState.Frames = nil
        reconcilePlayerCannons(player, data)
    end
end

local function fireMizukiBeam(player, direction, charge)
    local data = player:GetData()
    data.MizukiShotSide = -(data.MizukiShotSide or -1)
    local side = data.MizukiShotSide == -1 and 1 or 2
    local origins = data.MizukiCannonPositions[side]
    if not origins or #origins == 0 then
        return
    end
    local beamDistance = getBeamDistance(player)
    local beamWidthScale = getBeamWidthScale(player)
    local beamDuration = BEAM_DURATION
    local chargePercent = math.min(charge / getMaxChargeFrames(player), 1)
    local normalizedCharge = math.max(0, (chargePercent - MIN_CHARGE_PERCENT) / (1 - MIN_CHARGE_PERCENT))
    local chargeDamageMultiplier = MIN_CHARGE_DAMAGE_MULTIPLIER
        + (1 - MIN_CHARGE_DAMAGE_MULTIPLIER) * normalizedCharge
    local damageMultiplier = BEAM_DAMAGE_PER_TICK_MULTIPLIER
        * chargeDamageMultiplier
    data.MizukiLockedCannonPositions[side] = {}
    data.MizukiLockedCannonAims[side] = Vector(direction.X, direction.Y)
    data.MizukiActiveBeams[side] = {}
    for member, origin in ipairs(origins) do
        data.MizukiLockedCannonPositions[side][member] = Vector(origin.X, origin.Y)
        local firingCannon = data.MizukiCannons[side]
            and data.MizukiCannons[side][member]
        if firingCannon and firingCannon:Exists() then
            -- Apply the firing depth before this frame is rendered; waiting
            -- for the next Familiar update would leave a one-frame layer pop.
            firingCannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
        end
        local tearParams = player:GetTearHitParams(
            WeaponType.WEAPON_LASER,
            damageMultiplier,
            1,
            nil
        )
        local laser = EntityLaser.ShootAngle(
            MIZUKI_LASER_VARIANT,
            origin,
            direction:GetAngleDegrees(),
            beamDuration,
            Vector.Zero,
            player
        )
        laser.DisableFollowParent = true
        laser:SetOneHit(false)
        laser:SetMaxDistance(beamDistance)
        laser.CollisionDamage = tearParams.TearDamage
        laser.TearFlags = tearParams.TearFlags
        laser.Color = MIZUKI_LASER_COLOR
        -- The native laser initializes Size during its first updates. Store
        -- the desired width here and apply only Size from the update callback,
        -- so we can verify whether this variant synchronizes its own visuals.
        laser:GetData().MizukiBeam = true
        laser:GetData().MizukiBeamOwner = player
        laser:GetData().MizukiBeamWidthScale = beamWidthScale

        local beam = {
            Laser = laser,
            Origin = Vector(origin.X, origin.Y),
            Direction = Vector(direction.X, direction.Y),
            Distance = beamDistance,
            Timeout = beamDuration,
            Duration = beamDuration,
            DamageMultiplier = damageMultiplier,
        }
        table.insert(data.MizukiActiveBeams[side], beam)
    end

end

function Mizuki:UpdateWeapon(player)
    if not isMizuki(player) then
        return
    end

    -- Door transitions temporarily clear shooting input. Treat that as a
    -- pause, not a release, so a held charge and its cannon facing survive
    -- until control returns in the destination room.
    if Game():IsPaused() then
        return
    end

    local data = player:GetData()
    updateCannonReconcile(player, data)

    if data.MizukiBoxFallbackDemonBabyEffects ~= nil then
        local effects = player:GetEffects()
        local targetCount = data.MizukiBoxFallbackDemonBabyEffects
        data.MizukiBoxFallbackDemonBabyEffects = nil
        while effects:GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_DEMON_BABY) > targetCount do
            effects:RemoveCollectibleEffect(CollectibleType.COLLECTIBLE_DEMON_BABY)
        end
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end

    if data.MizukiRefreshCannonCache then
        data.MizukiRefreshCannonCache = nil
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    local activeSides = updateActiveBeams(player, data)
    local shootingInput = player:GetShootingInput()
    data.MizukiHasShootingInput = shootingInput:Length() > 0.01
    if data.MizukiHasShootingInput then
        data.MizukiCannonAim = shootingInput:Normalized()
    end
    updateCannonPositions(player, data)

    if activeSides >= 2 then
        data.MizukiCharge = 0
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if data.MizukiHasShootingInput then
        data.MizukiCharge = math.min((data.MizukiCharge or 0) + 1, getMaxChargeFrames(player))
        if data.MizukiCharge >= getMaxChargeFrames(player) then
            data.MizukiChargeBarFullFrames = (data.MizukiChargeBarFullFrames or 0) + 1
        else
            data.MizukiChargeBarFullFrames = nil
        end
        data.MizukiAim = shootingInput:Normalized()
        data.MizukiCannonAim = data.MizukiAim
        return
    end

    local charge = data.MizukiCharge or 0
    if charge >= getMinChargeFrames(player) and data.MizukiAim then
        fireMizukiBeam(player, data.MizukiAim, charge)
    end

    data.MizukiCharge = 0
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
    data.MizukiCannonAim = Vector(0, -1)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateWeapon)

function Mizuki:ApplyLaserWidth(laser)
    local laserData = laser:GetData()
    if not laserData.MizukiBeam or laser.FrameCount < 2 then
        return
    end

    local widthScale = laserData.MizukiBeamWidthScale or 1
    if not laserData.MizukiBeamWidthApplied then
        -- Wait until the native laser has initialized both its collision size
        -- and render scale, then preserve that unmodified render baseline.
        laserData.MizukiBeamBaseSpriteScale = Vector(
            laser.SpriteScale.X,
            laser.SpriteScale.Y
        )
        laser.Size = laser.Size * widthScale
        laserData.MizukiBeamWidthApplied = true
    end

    local baseScale = laserData.MizukiBeamBaseSpriteScale or Vector.One
    -- Size may synchronize back into SpriteScale during native updates. Undo
    -- its longitudinal scaling after every update: widen around the shared
    -- centered X pivot, while leaving body length and tip placement native.
    laser.SpriteScale = Vector(
        baseScale.X * widthScale,
        baseScale.Y
    )
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_UPDATE,
    Mizuki.ApplyLaserWidth,
    MIZUKI_LASER_VARIANT
)

function Mizuki:RememberBoxOfFriendsDemonBabyEffects(collectible, rng, player)
    if isMizuki(player) and player:GetCollectibleNum(CollectibleType.COLLECTIBLE_DEMON_BABY) == 0 then
        player:GetData().MizukiBoxFallbackDemonBabyEffects =
            player:GetEffects():GetCollectibleEffectNum(CollectibleType.COLLECTIBLE_DEMON_BABY)
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_PRE_USE_ITEM,
    Mizuki.RememberBoxOfFriendsDemonBabyEffects,
    BOX_OF_FRIENDS
)

function Mizuki:QueueBoxOfFriendsCannonRefresh(collectible, rng, player)
    if isMizuki(player) then
        -- Resolve on the next player update, after the vanilla active effect
        -- has incremented its temporary Box of Friends effect count.
        player:GetData().MizukiRefreshCannonCache = true
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.QueueBoxOfFriendsCannonRefresh,
    BOX_OF_FRIENDS
)

function Mizuki:ApplyTearsMultiplier(player, cacheFlag)
    if isMizuki(player) then
        local capsuleDelta = getCapsuleState(player).RewindStatDelta
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            player.Damage = player.Damage + DAMAGE_MODIFIER
            if capsuleDelta then
                player.Damage = player.Damage + capsuleDelta.Damage
            end
        elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
            local profile = getMizukiFireRateProfile(player)
            local currentTears = 30 / (player.MaxFireDelay + 1)
            local preWeaponTears = currentTears / profile.VanillaTearsMultiplier
            local finalTears = (preWeaponTears + profile.TearsModifier) * profile.MizukiTearsMultiplier
            if capsuleDelta then
                finalTears = finalTears + capsuleDelta.Tears
            end
            player.MaxFireDelay = math.max(0, 30 / finalTears - 1)
        elseif cacheFlag == CacheFlag.CACHE_SPEED and capsuleDelta then
            player.MoveSpeed = player.MoveSpeed + capsuleDelta.MoveSpeed
        elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED and capsuleDelta then
            player.ShotSpeed = player.ShotSpeed + capsuleDelta.ShotSpeed
        elseif cacheFlag == CacheFlag.CACHE_RANGE and capsuleDelta then
            player.TearRange = player.TearRange + capsuleDelta.TearRange
        elseif cacheFlag == CacheFlag.CACHE_LUCK and capsuleDelta then
            player.Luck = player.Luck + capsuleDelta.Luck
        elseif cacheFlag == CacheFlag.CACHE_FAMILIARS then
            local copies = player:GetEffects():GetCollectibleEffectNum(BOX_OF_FRIENDS)
            local cannonsPerSide = 1 + copies
            local rng = player:GetCollectibleRNG(BOX_OF_FRIENDS)
            player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 1)
            player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 2)
        end
    end
end

Mizuki:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, Mizuki.ApplyTearsMultiplier)

function Mizuki:InitCannonFamiliar(cannon)
    cannon.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    cannon.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    cannon.DepthOffset = CANNON_DEPTH_OFFSET
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitCannonFamiliar, Mizuki.CannonVariant)

-- Keep cannon body scaling in one Familiar-owned update path so no other
-- callback can accidentally overwrite the final render scale.
function Mizuki:UpdateCannonScale(cannon)
    ensureCannonRegistered(cannon)
    local cannonData = cannon:GetData()
    if cannon.SubType == 1 and not cannonData.MizukiLeftGraphicsLoaded then
        local sprite = cannon:GetSprite()
        sprite:ReplaceSpritesheet(0, LEFT_CANNON_SPRITESHEET)
        sprite:ReplaceSpritesheet(1, LEFT_CANNON_LIGHT_SPRITESHEET)
        sprite:LoadGraphics()
        cannonData.MizukiLeftGraphicsLoaded = true
    end
    cannon.SpriteScale = CANNON_SCALES[cannon.SubType] or Vector(1, 1)
end

Mizuki:AddCallback(
    ModCallbacks.MC_FAMILIAR_UPDATE,
    Mizuki.UpdateCannonScale,
    Mizuki.CannonVariant
)

function Mizuki:ResetCannonsForNewRoom()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local data = player:GetData()
            data.MizukiActiveBeams = {}
            data.MizukiLockedCannonPositions = {}
            data.MizukiLockedCannonAims = {}

            claimPlayerCannons(player, data)

            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side]) do
                    if cannon:Exists() then
                        local outward = side == 1 and -(member - 1) or (member - 1)
                        local restingOffset = CANNON_OFFSETS[side]
                            + Vector(outward * CANNON_GROUP_SPACING, 0)
                        cannon.Position = player.Position
                            + scalePlayerOffset(player, restingOffset)
                        cannon.Velocity = Vector.Zero
                        local aim = data.MizukiCannonAim or Vector(0, -1)
                        local cannonData = cannon:GetData()
                        cannonData.MizukiCannonAim = aim
                        cannonData.MizukiIdleRotationOffset = side == 1
                            and LEFT_CANNON_IDLE_ROTATION
                            or RIGHT_CANNON_IDLE_ROTATION
                        local baseRotation = aim:GetAngleDegrees() + 90
                        local idleRotation = cannonData.MizukiIdleRotationOffset
                        local sprite = cannon:GetSprite()
                        sprite.Rotation = baseRotation + idleRotation
                        local pivotCorrection = CANNON_IDLE_ROTATION_PIVOT
                            - CANNON_IDLE_ROTATION_PIVOT:Rotated(idleRotation)
                        sprite.Offset = pivotCorrection:Rotated(baseRotation)
                    end
                end
            end
        end
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ResetCannonsForNewRoom)

-- Draw immediately after the selected Familiar. The Familiar survives room
-- changes and this callback receives the same camera offset used for its body.
function Mizuki:RenderChargeBar(cannon, renderOffset)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local data = player:GetData()
    local charge = data.MizukiCharge or 0
    if charge <= 0 then
        return
    end

    -- The next firing side decides which registered cannon group may own the bar.
    local nextShotSide = -(data.MizukiShotSide or -1)
    local side = nextShotSide == -1 and 1 or 2
    if cannon.SubType ~= side then
        return
    end

    -- Registration keeps each side sorted by InitSeed, so the first live cannon
    -- is the stable representative even when Box of Friends creates extra copies.
    local frameCount = Game():GetFrameCount()
    if data.MizukiChargeBarOwnerFrame ~= frameCount
        or data.MizukiChargeBarOwnerSide ~= side then
        data.MizukiChargeBarOwnerFrame = frameCount
        data.MizukiChargeBarOwnerSide = side
        data.MizukiChargeBarOwnerHash = nil

        prunePlayerCannons(data)
        local ownerCannon = data.MizukiCannons[side][1]
        if ownerCannon then
            data.MizukiChargeBarOwnerHash = GetPtrHash(ownerCannon)
        end
    end

    if data.MizukiChargeBarOwnerHash ~= GetPtrHash(cannon) then
        return
    end

    local fullFrames = data.MizukiChargeBarFullFrames
    if fullFrames then
        if fullFrames <= 12 then
            chargeBar:Play("StartCharged", true)
            chargeBar:SetFrame("StartCharged", fullFrames - 1)
        else
            chargeBar:Play("Charged", true)
            chargeBar:SetFrame("Charged", (fullFrames - 13) % 6)
        end
    else
        local frame = math.floor(math.min(charge / getMaxChargeFrames(player), 1) * 100)
        chargeBar:Play("Charging", true)
        chargeBar:SetFrame("Charging", frame)
    end

    chargeBar.Color = CHARGE_BAR_COLOR
    chargeBar.Scale = CHARGE_BAR_SCALE
    local room = Game():GetRoom()
    local cannonSprite = cannon:GetSprite()

    local renderPosition = Isaac.WorldToScreen(cannon.Position) + renderOffset
        + cannonSprite.Offset
        + CHARGE_BAR_OFFSET:Rotated(cannonSprite.Rotation)
        - room:GetRenderScrollOffset() - Game().ScreenShakeOffset
        
    -- The Revelation charge bar separates its art into bg (0), bar (1), and
    -- the inward-contracting outer circle (2). Mizuki only uses the circle.
    chargeBar:RenderLayer(2, renderPosition)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, Mizuki.RenderChargeBar, Mizuki.CannonVariant)

-- Experimental Capsule -----------------------------------------------------
-- This is a real pocket object, so it occupies the normal card/pill slot.
-- The small state machine distinguishes deliberately consuming it from trying
-- to drop it: only the latter causes the capsule to be restored.
local function findExperimentalCapsuleSlot(player)
    for slot = 0, 1 do
        if player:GetCard(slot) == Mizuki.ExperimentalCapsuleCard then
            return slot
        end
    end

    return nil
end

local function getConsumableSlotCount(player)
    local slotCount = player:GetMaxPocketItems()
    if player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= CollectibleType.COLLECTIBLE_NULL then
        slotCount = slotCount - 1
    end

    return math.max(1, math.min(2, slotCount))
end

local function pocketConsumableSlotIsEmpty(player, slot)
    return player:GetCard(slot) == Card.CARD_NULL and player:GetPill(slot) == PillColor.PILL_NULL
end

local function captureExperimentalPillStats(player)
    return {
        Damage = player.Damage,
        Tears = 30 / (player.MaxFireDelay + 1),
        MoveSpeed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed,
        TearRange = player.TearRange,
        Luck = player.Luck,
    }
end

local function subtractExperimentalPillStats(after, before)
    return {
        Damage = after.Damage - before.Damage,
        Tears = after.Tears - before.Tears,
        MoveSpeed = after.MoveSpeed - before.MoveSpeed,
        ShotSpeed = after.ShotSpeed - before.ShotSpeed,
        TearRange = after.TearRange - before.TearRange,
        Luck = after.Luck - before.Luck,
    }
end

local function addExperimentalPillStats(total, addition)
    total = total or {
        Damage = 0,
        Tears = 0,
        MoveSpeed = 0,
        ShotSpeed = 0,
        TearRange = 0,
        Luck = 0,
    }

    for stat, value in pairs(addition) do
        total[stat] = (total[stat] or 0) + value
    end

    return total
end

local function removeDroppedExperimentalCapsules(player)
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TAROTCARD,
        -1,
        false,
        false
    )) do
        if (entity.SubType == Mizuki.ExperimentalCapsuleCard
                or entity.SubType == EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE)
            and entity.Position:DistanceSquared(player.Position) <= 14400 then
            entity:Remove()
        end
    end
end

local function giveExperimentalCapsule(player, preferredSlot)
    local state = getCapsuleState(player)
    local existingSlot = findExperimentalCapsuleSlot(player)
    if existingSlot ~= nil then
        state.WasHeld = true
        state.LastSlot = existingSlot
        return
    end

    local slotCount = getConsumableSlotCount(player)
    local targetSlot = nil
    if preferredSlot and preferredSlot < slotCount
        and pocketConsumableSlotIsEmpty(player, preferredSlot) then
        targetSlot = preferredSlot
    end

    if targetSlot == nil then
        for slot = 0, slotCount - 1 do
            if pocketConsumableSlotIsEmpty(player, slot) then
                targetSlot = slot
                break
            end
        end
    end

    -- Never silently delete a card or pill that the player picked up. If all
    -- usable slots are full, place the selected one on the floor first.
    if targetSlot == nil then
        targetSlot = math.min(preferredSlot or 0, slotCount - 1)
        player:DropPocketItem(targetSlot, player.Position)
    end

    player:SetCard(targetSlot, Mizuki.ExperimentalCapsuleCard)
    state.Consumed = false
    state.WasHeld = true
    state.LastSlot = targetSlot
end

local function giveCapsuleHourGlass(player, alreadyUsed)
    -- SetPocketActiveItem is the only stable vanilla API for a character that
    -- did not start with an XML-defined pocket active. Remaining capsule uses
    -- are tracked by the mod, while the native VarData is synchronized below
    -- so the HUD shows the same count.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)

    local used = alreadyUsed or 0
    if used > 0 then
        -- SetPocketActiveItem first materializes the dynamic pocket-active
        -- slot. Replacing that occupied slot through the vanilla
        -- AddCollectible API then writes Glowing Hour Glass's real VarData,
        -- which is also what the HUD uses for its remaining-use display.
        player:AddCollectible(
            GLOWING_HOUR_GLASS,
            0,
            false,
            ActiveSlot.SLOT_POCKET,
            used
        )
    end
end

function Mizuki:MaintainExperimentalCapsule(player)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    local slot = findExperimentalCapsuleSlot(player)
    if not state.Initialized then
        state.Initialized = true
        state.LastSlot = slot or 0
        if slot ~= nil then
            state.Consumed = false
            state.WasHeld = true
        elseif player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            ~= CollectibleType.COLLECTIBLE_NULL then
            state.Consumed = true
            state.WasHeld = false
        else
            -- Makes a Lua hot reload recover the character's floor state
            -- instead of leaving both pocket areas blank.
            giveExperimentalCapsule(player, 0)
            slot = findExperimentalCapsuleSlot(player)
        end
    end
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end
    if slot ~= nil then
        -- Glowing Hour Glass restores the pre-use consumable inventory. Mod
        -- state is intentionally kept outside that snapshot, so a consumed
        -- capsule is removed again instead of becoming an infinite hourglass.
        if state.Consumed then
            player:SetCard(slot, Card.CARD_NULL)
            slot = nil
        else
            state.WasHeld = true
            state.LastSlot = slot
            return
        end
    end

    if state.RewindFrames then
        state.RewindFrames = state.RewindFrames - 1
        if state.RewindFrames <= 0 then
            state.RewindFrames = nil
            if state.PendingStatDelta then
                state.RewindStatDelta = addExperimentalPillStats(
                    state.RewindStatDelta,
                    state.PendingStatDelta
                )
                state.PendingStatDelta = nil
                player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
                player:EvaluateItems()
            end
            giveCapsuleHourGlass(player, 1)
            state.CapsuleHourGlassUsesRemaining = 2
        end
    end

    if state.CapsuleHourGlassRestoreFrames then
        state.CapsuleHourGlassRestoreFrames = state.CapsuleHourGlassRestoreFrames - 1
        if state.CapsuleHourGlassRestoreFrames <= 0 then
            state.CapsuleHourGlassRestoreFrames = nil
            giveCapsuleHourGlass(player, 3 - state.CapsuleHourGlassUsesRemaining)
        end
    end

    if state.CapsuleHourGlassFinishFrames then
        state.CapsuleHourGlassFinishFrames = state.CapsuleHourGlassFinishFrames - 1
        if state.CapsuleHourGlassFinishFrames <= 0 then
            state.CapsuleHourGlassFinishFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            player:SetPocketActiveItem(HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
        end
    end

    if not state.Consumed and state.WasHeld then
        removeDroppedExperimentalCapsules(player)
        giveExperimentalCapsule(player, state.LastSlot)
    end
end


function Mizuki:BlockPocketPickupWhileCapsuleSelected(pickup, collider)
    local player = collider:ToPlayer()
    if not player or not isMizuki(player) then
        return
    end

    -- Slot 0 is the selected consumable. If a real secondary consumable slot
    -- is unlocked and empty, vanilla can safely place the pickup there.
    --
    -- Otherwise keep this pickup briefly in vanilla's "not yet collectible"
    -- state instead of cancelling the collision with `return true`.
    -- The normal pickup collision logic can then still run.
    if player:GetCard(0) == Mizuki.ExperimentalCapsuleCard then
        local slotCount = getConsumableSlotCount(player)
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            return
        end

        pickup.Wait = math.max(pickup.Wait or 0, 2)
        return
    end
end


function Mizuki:UseExperimentalCapsule(card, player, useFlags)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    state.Consumed = true
    state.WasHeld = false
    state.ImmediateHourGlass = true
    state.UseRoomIndex = Game():GetLevel():GetCurrentRoomIndex()

    state.PillStatsBefore = captureExperimentalPillStats(player)
    state.CapturePillStatsPending = true

    -- Delegate the stat changes, feedback and all edge cases to the vanilla
    -- Experimental Pill implementation instead of reproducing its RNG here.
    player:UsePill(PillEffect.PILLEFFECT_EXPERIMENTAL, PillColor.PILL_NULL, useFlags)
    giveCapsuleHourGlass(player, 0)
end


function Mizuki:UseCapsuleHourGlass(collectible, rng, player, useFlags, activeSlot)
    if not isMizuki(player) then
        return
    end

    -- Glowing Hour Glass can transiently duplicate custom familiars while its
    -- rewind snapshot is being restored. player:GetData() is itself rewound, so
    -- keep this marker in external Lua state or the rewind erases the request.
    local reconcileState = getCannonReconcileState(player)
    reconcileState.Pending = true

    local state = getCapsuleState(player)
    -- If the hourglass was activated before the next player update, finish
    -- the post-pill snapshot here. The native pill cache has resolved by now.
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end

    local isImmediateCapsuleHourGlass = state.ImmediateHourGlass
        and state.UseRoomIndex == Game():GetLevel():GetCurrentRoomIndex()
    if state.Consumed and isImmediateCapsuleHourGlass then
        -- Resolve after the vanilla rewind has restored the room/player state.
        -- Item restoration must not depend on whether the pill stat cache has
        -- finished resolving; a very fast use can arrive before that snapshot.
        -- Clear the marker before restoring the item so later uses are native.
        state.ImmediateHourGlass = false
        state.RewindRequested = true
    elseif state.CapsuleHourGlassUsesRemaining then
        state.CapsuleHourGlassUsesRemaining = state.CapsuleHourGlassUsesRemaining - 1
        if state.CapsuleHourGlassUsesRemaining > 0 then
            state.CapsuleHourGlassRestoreRequested = true
        else
            state.CapsuleHourGlassFinishRequested = true
        end
    end

    if isImmediateCapsuleHourGlass or state.CapsuleHourGlassUsesRemaining ~= nil then
        return {
            Discharge = false,
            Remove = false,
            ShowAnim = true,
        }
    end
end


function Mizuki:ExpireImmediateCapsuleHourGlass()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local reconcileState = getCannonReconcileState(player)
            if reconcileState.Pending then
                reconcileState.Pending = nil
                reconcileState.Frames = 2
            end

            local state = getCapsuleState(player)
            if state.RewindRequested then
                state.RewindRequested = nil
                state.RewindFrames = 1
            elseif state.CapsuleHourGlassRestoreRequested then
                state.CapsuleHourGlassRestoreRequested = nil
                state.CapsuleHourGlassRestoreFrames = 1
            elseif state.CapsuleHourGlassFinishRequested then
                state.CapsuleHourGlassFinishRequested = nil
                state.CapsuleHourGlassFinishFrames = 1
            else
                state.ImmediateHourGlass = false
                state.PendingStatDelta = nil
            end
        end
    end
end


function Mizuki:InitializeExperimentalCapsule(isContinued)
    capsuleStates = {}
    cannonReconcileStates = {}
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
            player:EvaluateItems()
            local state = getCapsuleState(player)
            local slot = findExperimentalCapsuleSlot(player)
            local pocketActive = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            local hasCapsuleHourGlass = pocketActive == GLOWING_HOUR_GLASS
                or pocketActive == HOUR_GLASS

            state.WasHeld = slot ~= nil
            state.Initialized = true
            state.LastSlot = slot or 0
            state.Consumed = hasCapsuleHourGlass and slot == nil
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil

            if slot == nil and pocketActive == CollectibleType.COLLECTIBLE_NULL then
                giveExperimentalCapsule(player, 0)
            end

        end
    end
end


function Mizuki:RefreshExperimentalCapsule()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            if player:GetActiveItem(ActiveSlot.SLOT_POCKET) == GLOWING_HOUR_GLASS then
                player:SetPocketActiveItem(
                    CollectibleType.COLLECTIBLE_NULL,
                    ActiveSlot.SLOT_POCKET,
                    true
                )
            end

            local state = getCapsuleState(player)
            state.Consumed = false
            state.WasHeld = false
            state.Initialized = true
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil
            state.PillStatsBefore = nil
            state.CapturePillStatsPending = nil
            state.RewindRequested = nil
            state.RewindFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            state.CapsuleHourGlassRestoreRequested = nil
            state.CapsuleHourGlassRestoreFrames = nil
            state.CapsuleHourGlassFinishRequested = nil
            state.CapsuleHourGlassFinishFrames = nil
            giveExperimentalCapsule(player, state.LastSlot or 0)
        end
    end
end


Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.MaintainExperimentalCapsule)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_TAROTCARD
)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_PILL
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_CARD,
    Mizuki.UseExperimentalCapsule,
    Mizuki.ExperimentalCapsuleCard
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.UseCapsuleHourGlass,
    GLOWING_HOUR_GLASS
)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.RefreshExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ExpireImmediateCapsuleHourGlass)
