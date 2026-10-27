-- Cannon ownership, layout, movement, deployment and contact damage.
local Config = Mizuki.Config

function Mizuki.getCannonHoverOffset(frame)
    return math.sin(frame * 2 * math.pi / Config.CANNON_FLOAT_PERIOD)
        * Config.CANNON_FLOAT_AMPLITUDE
end

-- Water reflections are re-drawn by this mod instead of by the engine; see
-- Mizuki:RenderCannon. The engine keeps "drawing" the cannon in every water
-- pass so those render callbacks keep firing, but the draw itself is made fully
-- transparent here. A fresh Color per call avoids handing several sprites the
-- same mutable object.
function Mizuki.getCannonHiddenColor()
    return Color(1, 1, 1, 0, 0, 0, 0)
end

local function getCannonIdleHeightOffset(player)
    local offset = Config.CANNON_IDLE_OFFSETS
    if Mizuki.cannonUsesKnifeWeapon(player) then
        offset = offset + Config.CANNON_MOMS_KNIFE_IDLE_OFFSET
    end
    return offset
end

function Mizuki.getCannonReflectionSpan(player, isIdle)
    if not isIdle then
        return Config.CANNON_FIRING_REFLECTION_SPAN * player.SpriteScale.Y
    end
    -- The base formation follows player size, while the final idle lift is a
    -- fixed world-space adjustment. Reflect both parts about the same plane.
    return Config.CANNON_IDLE_REFLECTION_SPAN * player.SpriteScale.Y
        - 2 * getCannonIdleHeightOffset(player).Y
end

-- Native flooded-room laser reflections use the laser entity's Position and
-- PositionOffset differently from the normal body draw. Split Mizuki's extra
-- scale-based cannon height equally between them: the visible beam stays at the
-- cannon muzzle, while the native reflection gains the full extra separation.
--
-- Moving Position also changes the entity's Y sort key, so return that shift and
-- subtract it from DepthOffset at each call site. That keeps the beam/cannon
-- layering exactly where it was before the reflection correction.
function Mizuki.applyBeamReflectionHeight(player, laser)
    if not laser then
        return 0
    end
    local extraGap = Config.CANNON_FIRING_REFLECTION_SPAN
        * (player.SpriteScale.Y - 1)
    local shift = extraGap * 0.5
    if math.abs(shift) <= Mizuki.RuntimeParameters.OffsetEpsilon then
        return 0
    end
    local verticalShift = Vector(0, shift)
    laser.Position = laser.Position + verticalShift
    laser.PositionOffset = laser.PositionOffset - verticalShift
    return shift
end

local function scalePlayerOffset(player, offset)
    local scale = player.SpriteScale
    return Vector(offset.X * scale.X, offset.Y * scale.Y)
end

-- Glowing Hour Glass rewinds EntityPlayer state, including values associated
-- with that snapshot. Keep the capsule transaction outside player:GetData()
-- so the fact that it was consumed cannot itself be rewound.
-- Glowing Hour Glass also rewinds player:GetData(), so cannon-reconcile
-- bookkeeping must live outside EntityPlayer state for the same reason.
Mizuki.cannonReconcileStates = {}

function Mizuki.getCannonReconcileState(player)
    local index = Mizuki.getPlayerIndex(player)
    Mizuki.cannonReconcileStates[index] = Mizuki.cannonReconcileStates[index] or {}
    return Mizuki.cannonReconcileStates[index]
end

local function getFamiliarPlayer(familiar)
    if not familiar then return nil end
    local owner = familiar.Player
    if not owner and familiar.Parent then
        owner = familiar.Parent:ToPlayer()
    end
    if not owner and familiar.SpawnerEntity then
        owner = familiar.SpawnerEntity:ToPlayer()
    end
    return owner
end

function Mizuki.cannonBelongsToPlayer(cannon, player)
    local owner = getFamiliarPlayer(cannon)
    return owner and GetPtrHash(owner) == GetPtrHash(player)
end

function Mizuki.getExpectedCannonPairProfiles(player, stableShotCount)
    local basePairs = 1
    local hasLudovico = Mizuki.usesLudovicoWeapon(player)
    if hasLudovico then
        basePairs = stableShotCount or Mizuki.getStableShotCount(player)
    end
    basePairs = basePairs
        + player:GetEffects():GetCollectibleEffectNum(Config.BOX_OF_FRIENDS)

    local profiles = {}
    for _ = 1, basePairs do
        profiles[#profiles + 1] = {
            DamageMultiplier = 1,
            ScaleMultiplier = 1,
        }
    end

    if hasLudovico then
        local familiarPowerMultiplier = player:HasCollectible(Config.BFFS) and 2 or 1
        local familiarProfiles = {
            {
                Count = Mizuki.getCollectibleFamiliarCount(
                    player,
                    CollectibleType.COLLECTIBLE_INCUBUS
                ),
                Multiplier = Config.LUDOVICO_INCUBUS_MULTIPLIER
                    * familiarPowerMultiplier,
            },
            {
                -- Each Twisted Pair item/effect owns two Twisted Baby entities,
                -- and therefore contributes two independently damaging pairs.
                Count = Mizuki.getCollectibleFamiliarCount(
                    player,
                    CollectibleType.COLLECTIBLE_TWISTED_PAIR
                ) * 2,
                Multiplier = Config.LUDOVICO_TWISTED_BABY_MULTIPLIER
                    * familiarPowerMultiplier,
            },
        }
        for _, familiarProfile in ipairs(familiarProfiles) do
            for _ = 1, familiarProfile.Count do
                profiles[#profiles + 1] = {
                    DamageMultiplier = familiarProfile.Multiplier,
                    -- The extra cannon is the familiar's bone-club analogue;
                    -- its body and contact radius use the same native familiar
                    -- multiplier as its damage. The familiar's own Ludovico
                    -- tear remains entirely engine-owned and is not rescaled.
                    ScaleMultiplier = familiarProfile.Multiplier,
                }
            end
        end
    end
    profiles = Mizuki.appendPersistentCannonEchoProfiles(player, profiles)
    return Mizuki.appendGuillotineCannonProfiles(player, profiles)
end

function Mizuki.getExpectedCannonPairs(player)
    return #Mizuki.getExpectedCannonPairProfiles(player)
end

-- CheckFamiliar owns spawning and despawning. Lua only rebuilds stable side
-- groups from the engine-owned entities; it never creates or removes cannons.
local function claimPlayerCannons(player, data)
    local claimed = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, Mizuki.CannonVariant, -1, false, false)) do
        local cannon = entity:ToFamiliar()
        if Mizuki.cannonBelongsToPlayer(cannon, player) then
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
    if not player or not Mizuki.isMizuki(player) then
        return
    end

    -- Keep the engine-style familiar ownership chain complete. Knives parented
    -- to the cannon (and third-party knife callbacks) resolve their player via
    -- Familiar.SpawnerEntity.
    cannon.SpawnerEntity = player

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

function Mizuki.prunePlayerCannons(data)
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
    local expectedPerSide = Mizuki.getExpectedCannonPairs(player)
    local actual = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR,
        Mizuki.CannonVariant,
        -1,
        false,
        false
    )) do
        local cannon = entity:ToFamiliar()
        if cannon and cannon:Exists() and Mizuki.cannonBelongsToPlayer(cannon, player) then
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
                Mizuki.removeCannonMomKnife(cannon)
                cannon:Remove()
            end
        end
    end

    data.MizukiCannons = retained
end

function Mizuki.getCannonBaseScale(cannon)
    local cannonData = cannon:GetData()
    local ludovicoScale = cannonData.MizukiLudovicoOrbiting
        and (cannonData.MizukiLudovicoScaleMultiplier or 1)
        or 1
    local player = cannon.Player
    local baseScale
    if player and player:Exists() then
        baseScale = Vector(
            player.SpriteScale.X * ludovicoScale,
            player.SpriteScale.Y * ludovicoScale
        )
    else
        baseScale = Vector(ludovicoScale, ludovicoScale)
    end
    cannonData.MizukiCannonBaseScale = baseScale
    return baseScale
end

function Mizuki.applyArtScaleMultiplier(baseScale, artScaleMultiplier)
    return Vector(
        baseScale.X * artScaleMultiplier,
        baseScale.Y * artScaleMultiplier
    )
end

-- Map a screen-X compression onto the lengths of the sprite's rotated axes.
-- This diagonal approximation uses ordinary Sprite.Scale; no extra animation
-- or render sprite is required, and 90 degrees swaps the X/Y factors.
function Mizuki.getCannonScreenCompression(rotation, width)
    width = width or 1
    if width == 1 then return Vector(1, 1) end
    local angle = math.rad(rotation)
    local cos2, sin2 = math.cos(angle) ^ 2, math.sin(angle) ^ 2
    return Vector(math.sqrt(width * width * cos2 + sin2),
        math.sqrt(width * width * sin2 + cos2))
end

-- Reflect the complete world direction about Y, then convert back from the
-- up-facing artwork's 90-degree baseline. Scale channels remain independent.
function Mizuki.getCannonIdleFlipTransform(rotation, progress, angleProgress)
    progress = math.max(0, math.min(1, progress or 0))
    angleProgress = math.max(0, math.min(1, angleProgress or 0))
    local worldAngle = math.rad(rotation - 90)
    local mirroredWorldAngle = math.deg(math.atan(math.sin(worldAngle), -math.cos(worldAngle)))
    local mirroredRotation = mirroredWorldAngle + 90
    local delta = (mirroredRotation - rotation + 180) % 360 - 180
    return rotation + delta * angleProgress, 1 - 2 * progress, 1
end

function Mizuki.getCannonSpriteTransform(cannon, cannonAim, positionAim, idleRotation)
    local cannonData = cannon:GetData()
    local spriteRotation = cannonAim:GetAngleDegrees() + 90 + idleRotation
    local pivotRotation = spriteRotation
    cannonData.MizukiIdleFlipBaseRotation = pivotRotation
    local flipX, flipY
    spriteRotation, flipX, flipY = Mizuki.getCannonIdleFlipTransform(
        spriteRotation, cannonData.MizukiIdleFlipProgress,
        cannonData.MizukiIdleAngleMirrorProgress)
    local compressionRotation = pivotRotation
    local positionBaseRotation = positionAim:GetAngleDegrees() + 90
    local screenWidth = cannonData.MizukiIdleScreenXScale or 1
    local compression = Mizuki.getCannonScreenCompression(compressionRotation, screenWidth)

    -- Keep the cannon's configured bottom-centre pivot fixed in world/render
    -- space instead of trying to compensate through Sprite.Offset. The pivot is
    -- authored in unscaled sprite pixels, so use the cannon's final visual scale
    -- here as well. This keeps the same point attached to the cannon root when
    -- the player's SpriteScale makes the whole weapon larger or smaller.
    local function getPivotOffset(renderScale, pivot, projectedBody)
        pivot = pivot or Config.CANNON_IDLE_ROTATION_PIVOT
        local scaledPivot = Vector(
            pivot.X * renderScale.X,
            pivot.Y * renderScale.Y
        )
        if projectedBody then
            local anchor = scaledPivot:Rotated(positionBaseRotation)
            local renderedPivot = Vector(scaledPivot.X * compression.X * flipX,
                scaledPivot.Y * compression.Y * flipY):Rotated(spriteRotation)
            -- Offset the centre so the fully rendered bottom pivot stays at
            -- its formation anchor throughout scaling, rotation and mirroring.
            return Vector(anchor.X * screenWidth, anchor.Y) - renderedPivot
        end
        local offset = scaledPivot:Rotated(positionBaseRotation)
            - scaledPivot:Rotated(pivotRotation)
        -- Idle mirroring keeps the established body centre. Mirroring this
        -- bottom-pivot displacement as well would pull the large-tilt cannon
        -- inward and change the pair's spacing just by changing facing.
        -- Layout already compresses each root toward the shared formation
        -- centre. Apply the same screen-X transform to this visual displacement;
        -- the approximate local-axis art scaling must not move that centre.
        return Vector(offset.X * screenWidth, offset.Y)
    end

    local baseScale = Mizuki.getCannonBaseScale(cannon)
    local weaponPivot = Mizuki.isBerserkClubActive(cannon.Player)
        and Vector(0, Mizuki.BerserkClubParameters.RotationPivotPixels)
        or Config.CANNON_IDLE_ROTATION_PIVOT
    local basePivotRenderOffset = getPivotOffset(Mizuki.applyArtScaleMultiplier(
        baseScale,
        Config.MOMS_KNIFE_ART_SCALE_MULTIPLIER
    ), weaponPivot)
    local cannonPivotRenderOffset = getPivotOffset(Mizuki.getCannonBodyRenderScale(
        cannonData,
        Mizuki.applyArtScaleMultiplier(baseScale, Config.CANNON_ART_SCALE_MULTIPLIER)
    ), nil, true)
    return spriteRotation, cannonPivotRenderOffset, basePivotRenderOffset
end

function Mizuki.getCannonBeamPivotRenderOffset(player, cannonData)
    if Mizuki.cannonUsesKnifeWeapon(player) then
        return cannonData.MizukiBasePivotRenderOffset or Vector.Zero
    end
    return cannonData.MizukiPivotRenderOffset or Vector.Zero
end

-- SpriteScale moves the cannon farther above/below the player's sorting Y even
-- though that extra distance represents visual height, not a different ground
-- depth. Cancel only the scale-created part of the layout Y in DepthOffset.
-- Bobbing and the small idle lift remain real render motion and are untouched.
local function getCannonScaleDepthCompensation(player, cannon)
    local scaleY = player.SpriteScale.Y
    if math.abs(scaleY) < Mizuki.RuntimeParameters.ScaleEpsilon then
        return 0
    end

    local layoutOffset = cannon:GetData().MizukiLayoutOffset
    if not layoutOffset then
        return 0
    end

    local unscaledLayoutY = layoutOffset.Y / scaleY
    return unscaledLayoutY - layoutOffset.Y
end

local function getCannonTargetDepthOffset(
    player,
    cannon,
    isIdle,
    isFiring,
    isFollowingFiring,
    sideIsHorizontal,
    eyeDirection
)
    local baseDepthOffset
    if isIdle then
        local near = cannon:GetData().MizukiIdleDepthOrder or 0
        baseDepthOffset = Config.IDLE_CANNON_DEPTH_OFFSET
            + near * (Config.HORIZONTAL_FRONT_DEPTH_OFFSET - Config.HORIZONTAL_BACK_DEPTH_OFFSET) * 0.5
    elseif isFiring and not isFollowingFiring then
        baseDepthOffset = Config.FIRING_CANNON_DEPTH_OFFSET
    elseif sideIsHorizontal then
        baseDepthOffset = eyeDirection.Y > 0
            and Config.HORIZONTAL_FRONT_DEPTH_OFFSET
            or Config.HORIZONTAL_BACK_DEPTH_OFFSET
    else
        baseDepthOffset = Config.CANNON_DEPTH_OFFSET
    end

    if (isIdle or isFiring)
        and Mizuki.cannonUsesKnifeWeapon(player)
    then
        baseDepthOffset = baseDepthOffset + Config.MOMS_KNIFE_DEPTH_OFFSET
    end

    return baseDepthOffset + getCannonScaleDepthCompensation(player, cannon)
end

local function updateCannonDepthOffset(cannon, targetDepthOffset, snap)
    if snap then
        cannon.DepthOffset = targetDepthOffset
        return
    end

    local depthOffset = cannon.DepthOffset
        + (targetDepthOffset - cannon.DepthOffset) * Config.CANNON_FOLLOW_SPEED
    if math.abs(depthOffset - targetDepthOffset) < Mizuki.WeaponParameters.CannonDepthSnapDistance then
        depthOffset = targetDepthOffset
    end
    cannon.DepthOffset = depthOffset
end

local function getCannonPositionWithElasticLag(player, cannon, targetPosition)
    local cannonData = cannon:GetData()
    local targetPoseOffset = targetPosition - player.Position
    local poseOffset = cannonData.MizukiPoseOffset
        or (cannon.Position - player.Position)
    poseOffset = poseOffset
        + (targetPoseOffset - poseOffset) * Config.CANNON_FOLLOW_SPEED
    cannonData.MizukiPoseOffset = poseOffset

    -- Player translation contributes only a small elastic drag. Aim/layout
    -- changes still use the normal pose interpolation above, so capping this
    -- lag does not make large pose changes snap toward their destination.
    local movementLag = cannonData.MizukiMovementLag or Vector.Zero
    local lastPlayerPosition = cannonData.MizukiLastPlayerPosition
    if lastPlayerPosition then
        local playerDelta = player.Position - lastPlayerPosition
        movementLag = (movementLag - playerDelta) * (1 - Config.CANNON_FOLLOW_SPEED)
    else
        movementLag = Vector.Zero
    end
    local lagLength = movementLag:Length()
    if lagLength > Config.CANNON_MAX_FOLLOW_LAG then
        movementLag = movementLag * (Config.CANNON_MAX_FOLLOW_LAG / lagLength)
    end
    cannonData.MizukiMovementLag = movementLag
    cannonData.MizukiLastPlayerPosition = Vector(
        player.Position.X,
        player.Position.Y
    )

    return player.Position + poseOffset + movementLag
end

-- Horizontal cannons may visibly lag behind the player's movement, but that
-- lag must not decide whether they are drawn in front of or behind the player.
-- Ease their intended sorting position relative to the player, then solve the
-- DepthOffset needed to keep that sorting position independent of world-space
-- follow lag.
local function updateHorizontalCannonDepthOffset(
    player,
    cannon,
    cannonPosition,
    targetSortOffset,
    previousSortOffset,
    snap
)
    local cannonData = cannon:GetData()
    local sortOffset = targetSortOffset
    if not snap then
        sortOffset = cannonData.MizukiHorizontalSortOffset
            or previousSortOffset
            or targetSortOffset
        sortOffset = sortOffset
            + (targetSortOffset - sortOffset) * Config.CANNON_FOLLOW_SPEED
        if math.abs(sortOffset - targetSortOffset) < Mizuki.WeaponParameters.CannonDepthSnapDistance then
            sortOffset = targetSortOffset
        end
    end
    cannonData.MizukiHorizontalSortOffset = sortOffset

    local playerSortY = player.Position.Y + player.DepthOffset
    cannon.DepthOffset = playerSortY + sortOffset - cannonPosition.Y
end

-- The shadow is the sprite's own anm2 "shadow" layer and the engine draws it by
-- itself, with whatever transform the sprite is left in. That transform has to be
-- written during the update: the render callback runs after the engine has
-- already drawn the familiar, so anything set there only reaches the next frame
-- and trails the cannon by a frame - which reads as the shadow wobbling.
--
-- The layer lands at the entity position plus Sprite.Offset, so:
--   * ordinary shadows use half the eased reflection distance, while a
--     deployed cannon keeps the charging-height shadow offset;
--     the entity position contains no visual hover bob;
--   * the shadow shares the cannon's player-scaled entity transform; Ludovico
--     additionally includes the ring's visual height in its midpoint offset;
--   * every shadow uses the same horizontal ellipse, so rotation never makes
--     it jump between authored size tiers.
function Mizuki.refreshCannonMomKnifeShadow(cannon)
    local cannonData = cannon:GetData()
    local baseOffset = cannonData.MizukiShadowBaseOffset
    if not baseOffset then
        return
    end
    local knifeDisplacement = Mizuki.getCannonMomKnifeShadowDisplacement
        and Mizuki.getCannonMomKnifeShadowDisplacement(cannon)
        or Vector.Zero
    local offsetUnit = cannonData.MizukiLudovicoOrbiting
        and 1 or Config.CANNON_ART_SCALE_MULTIPLIER
    local shadowOffset = baseOffset + knifeDisplacement * offsetUnit
    cannonData.MizukiShadowOffset = shadowOffset
    cannon:GetSprite().Offset = shadowOffset
end

function Mizuki.applyCannonShadowPose(player, cannon, isDeployed)
    local cannonData = cannon:GetData()
    -- The entity's own position carries no hover bob (the bob rides the
    -- hand-drawn body instead). The span's target comes from the authored
    -- layout, not a difference between live positions; that would move the
    -- native shadow's offset out of phase with the entity position.
    --
    -- Sprite.Offset is measured in the cannon's authored scale, which is a
    -- constant: it does not follow the player's size. Converting with the
    -- entity's render scale instead only matches at normal size and drifts as
    -- soon as the player grows.
    local offsetUnit = Config.CANNON_ART_SCALE_MULTIPLIER
    local isIdle = cannonData.MizukiIsIdle
    -- A deployed cannon keeps its shadow at charging height even when its
    -- body enters the idle pose. Reflection spacing remains unchanged.
    local span = isDeployed
        and Mizuki.getCannonReflectionSpan(player, false)
        or cannonData.MizukiReflectionSpan
        or Mizuki.getCannonReflectionSpan(player, isIdle)
    local shadowWorldOffsetY = span * 0.5
    if cannonData.MizukiLudovicoOrbiting then
        -- The orbiting body's render plane is raised by the ring offset, and its
        -- reflected copy receives the same offset. Their midpoint therefore
        -- includes that offset as well; only the hitboxes remain at Position.
        local renderWorldOffset = cannonData.MizukiRenderWorldOffset
        shadowWorldOffsetY = shadowWorldOffsetY
            + (renderWorldOffset and renderWorldOffset.Y or 0)
    end
    -- Ludovico's midpoint above is already expressed in world/render pixels.
    -- Applying the cannon's authored 0.65 scale again pulls the shadow back
    -- toward the entity and makes the body/reflection distances asymmetric.
    -- Ordinary cannons retain their established authored-space conversion.
    local offsetY = cannonData.MizukiLudovicoOrbiting
        and shadowWorldOffsetY
        or shadowWorldOffsetY * offsetUnit
    local knifeFollowOffset = not isIdle
        and Mizuki.getCannonMomKnifeFollowOffset
        and Mizuki.getCannonMomKnifeFollowOffset(cannon)
        or Vector.Zero
    local shadowFollowOffset = cannonData.MizukiLudovicoOrbiting
        and knifeFollowOffset
        or knifeFollowOffset * offsetUnit
    local shadowOffset = Vector(
        shadowFollowOffset.X,
        offsetY + shadowFollowOffset.Y
    )
    cannonData.MizukiShadowBaseOffset = shadowOffset
    cannonData.MizukiShadowOffset = shadowOffset
    cannonData.MizukiShadowOffsetY = offsetY

    local sprite = cannon:GetSprite()
    if not sprite:IsPlaying("Idle") then
        sprite:Play("Idle", true)
    end
    sprite.Rotation = 0
    sprite.Offset = shadowOffset
    Mizuki.refreshCannonMomKnifeShadow(cannon)
end

-- Slots select the reference artwork/tilt, independent of familiar identity.
-- Right is the complete mirror of left; front/back retain their original poses.
function Mizuki.getCannonIdleLayout(player, side, groupDistance)
    local data = player:GetData()
    local target = (player:GetHeadDirection() * 90 + 180) % 360
    local frame = Game():GetFrameCount()
    local angle = data.MizukiIdleFacingAngle
    local previousTarget = data.MizukiIdleFacingTarget
    if previousTarget ~= target then
        data.MizukiIdleFacingTurnDirection = nil
        if (target == 0 or target == 180)
            and previousTarget == (target + 180) % 360 then
            data.MizukiIdleFacingTurnDirection = target == 180 and 1 or -1
        end
        data.MizukiIdleFacingTarget = target
    end
    if angle == nil then
        angle = target
    elseif data.MizukiIdleFacingFrame ~= frame and not Game():IsPaused() then
        local delta = (target - angle + 180) % 360 - 180
        -- Keep a horizontal reversal on the lower arc even when the previous
        -- turn left the interpolated angle slightly above its horizontal target.
        local turnDirection = data.MizukiIdleFacingTurnDirection
        if math.abs(delta) >= Mizuki.WeaponParameters.CannonAngleSnapDegrees then
            if turnDirection == 1 then delta = (target - angle) % 360
            elseif turnDirection == -1 then delta = -((angle - target) % 360)
            elseif delta == -180 and angle < 180 then delta = 180 end
        end
        angle = math.abs(delta) < Mizuki.WeaponParameters.CannonAngleSnapDegrees
            and target or (angle + delta * Mizuki.WeaponParameters.CannonRotationReturnRate) % 360
        if angle == target then data.MizukiIdleFacingTurnDirection = nil end
    end
    data.MizukiIdleFacingAngle, data.MizukiIdleFacingFrame = angle, frame
    local sector = math.floor(angle / 90)
    local blend = (angle % 90) / 90
    local function pose(index)
        index = index % 4 -- right, down, left, up
        local slot = index == 3 and side or (3 - side)
        local width = index % 2 == 0 and 0.5 or 1
        local base = Config.CANNON_OFFSETS[3 - slot]
        local outward = slot == 1 and -(groupDistance or 0) or (groupDistance or 0)
        local x = (base.X + outward) * width
        local forward = index == 0 and 1 or index == 2 and -1 or 0
        local mirror = ((index == 2 and side == 1) or (index == 0 and side == 2)) and 1 or 0
        local eyeSign = side == 1 and -1 or 1
        local near = index == 0 and eyeSign or index == 2 and -eyeSign or 0
        return x + forward * Mizuki.WeaponParameters.CannonIdleFacingOffset,
            base.Y, slot, width, mirror, near, index == 0 and 1 or 0
    end
    local x, y, slot, width, mirror, near, angleMirror = pose(sector)
    local nextX, _, nextSlot, nextWidth, nextMirror, nextNear, nextAngleMirror = pose(sector + 1)
    return Vector(x + (nextX - x) * blend, y),
        slot + (nextSlot - slot) * blend, width + (nextWidth - width) * blend,
        mirror + (nextMirror - mirror) * blend, near + (nextNear - near) * blend,
        angleMirror + (nextAngleMirror - angleMirror) * blend
end

function Mizuki.getCannonAttackPosition(player, cannon, direction, member)
    local cd = cannon:GetData()
    local center = cd.MizukiGuillotineHead and cd.MizukiGuillotineHead.Position or player.Position
    local radius = Mizuki.isTech2Cannon(cannon)
        and Config.CANNON_ATTACK_ORBIT_RADIUS or (Config.CANNON_ATTACK_ORBIT_RADIUS
            + (player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
                and Config.CANNON_MOMS_KNIFE_ORBIT_RADIUS_BONUS or 0))
    local halfSpacing = Config.HORIZONTAL_CANNON_HALF_SPACING
        + (Config.VERTICAL_CANNON_X - Config.HORIZONTAL_CANNON_HALF_SPACING) * math.abs(direction.Y)
        + (member - 1) * Config.CANNON_GROUP_SPACING
    local eyeDirection = direction:Rotated(cannon.SubType == 1 and -90 or 90)
    local offset = direction * radius + Vector(0, -Config.CANNON_ATTACK_ORBIT_HEIGHT)
        + eyeDirection * halfSpacing
    return center + scalePlayerOffset(player, offset)
end

function Mizuki.getTech5CannonPose(cannon)
    local cd = cannon:GetData()
    local pose = cd.MizukiTech5AttackPose
    if pose and (Game():GetFrameCount() >= pose.EndFrame
        or not Mizuki.usesCSectionWeapon(cannon.Player)
        or cd.MizukiPersistentEchoMode or cd.MizukiGuillotineNonFiring) then
        cd.MizukiTech5AttackPose = nil
        return nil
    end
    return pose
end

-- Used by ordinary immediate attacks and independent cannon shots alike.
function Mizuki.snapCannonPosition(player, cannon, position)
    local cd = cannon:GetData()
    cannon.Position = position
    cannon.Velocity = Vector.Zero
    cd.MizukiDesiredPosition = position
    cd.MizukiPoseOffset = position - player.Position
    cd.MizukiMovementLag = Vector.Zero
    cd.MizukiLastPlayerPosition = Vector(player.Position.X, player.Position.Y)
end

function Mizuki.updateCannonPositions(player, data, returnAim, snapSide, onlyCannon)
    local idleSwingPeriod = Mizuki.WeaponParameters.CannonIdleSwingFrames
    local rotationReturnSpeed = Mizuki.WeaponParameters.CannonRotationReturnRate
    Mizuki.prunePlayerCannons(data)
    local targetPositions = { {}, {} }
    local targetReticle = Mizuki.getTargetReticle(player, data)
    local aim = returnAim or data.MizukiCannonAim
    local normalizedAim = aim and aim:Normalized() or Vector(0, -1)
    local sideHorizontalStates = {}
    local sideEyeDirections = {}
    local sideFiringStates = {}
    local sideFollowingStates = {}
    local sideFiniteFollowStates = {}
    local sideOrbitDirections = {}
    local sideIdleStates = {}
    local anyCannonFiring = false

    -- Resolve each side's beam state once. Position layout, firing pose and
    -- laser synchronization all consume the same result below.
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams
            and data.MizukiActiveBeams[side]
        local isFiring = false
        local isFollowing = false
        local hasFiniteFollower = false
        if beams then
            for _, beam in ipairs(beams) do
                if beam.PersistentEchoMode ~= "automatic"
                    and not (beam.MomKnifeDriven and beam.Ending)
                then
                    isFiring = true
                end
                if beam.PersistentEchoMode ~= "automatic" and beam.FollowCannon
                    and not (beam.MomKnifeDriven and beam.Ending)
                then
                    isFollowing = true
                    if not beam.Automatic then
                        hasFiniteFollower = true
                    end
                end
            end
        end
        sideFiringStates[side] = isFiring
        sideFollowingStates[side] = isFollowing
        sideFiniteFollowStates[side] = hasFiniteFollower
        anyCannonFiring = anyCannonFiring or isFiring
    end

    local holdAttackPose = Mizuki.updateAttackPose(
        data, Game():GetFrameCount(), anyCannonFiring
    )
    local isIdle = not returnAim
        and not data.MizukiHasShootingInput
        and (data.MizukiCharge or 0) <= 0
        and not anyCannonFiring
        and not holdAttackPose
        and data.MizukiCannonAutoFireState ~= "deployed"
    if isIdle then
        -- Every weapon releases its facing with the same positional pose lease.
        data.MizukiCannonAim = Vector(0, -1)
        aim = data.MizukiCannonAim
        normalizedAim = aim
    end
    local guillotineHeads = Mizuki.getGuillotineHeads(player)
    data.MizukiCannonOrbitAngles = data.MizukiCannonOrbitAngles or {}
    for side = 1, 2 do
        -- A finite Anti-Gravity beam keeps only its own side's positional
        -- firing direction. The other side remains free to move to the layout
        -- requested by a new charge, so the pair need not share one axis.
        local sideIdle = isIdle
        if Mizuki.usesCSectionWeapon(player)
            or Mizuki.usesCannonSpiritSword(player) then
            -- Fetus and sword input keep the familiars in their resting layout.
            -- Sword art moves separately to the hand. Only this side's beam
            -- (or an individual .5 pose below) deploys the actual familiar.
            sideIdle = not sideFiringStates[side]
        end
        sideIdleStates[side] = sideIdle
        local sidePositionAim = normalizedAim
        if sideFiniteFollowStates[side] then
            local lockedState = data.MizukiLockedCannonAims
                and data.MizukiLockedCannonAims[side]
            if lockedState and lockedState.PositionAim then
                sidePositionAim = lockedState.PositionAim
            end
        end
        local targetAngle = sideIdle and -90
            or sidePositionAim:GetAngleDegrees()
        local orbitAngle = data.MizukiCannonOrbitAngles[side] or -90
        if ((data.MizukiSnapCannonsToDirectAim or snapSide == side)
                and not sideFiringStates[side])
            or (sideFiringStates[side]
                and not sideFollowingStates[side])
        then
            orbitAngle = targetAngle
        else
            local angleDelta = (targetAngle - orbitAngle + 180) % 360 - 180
            orbitAngle = orbitAngle + angleDelta * Config.CANNON_FOLLOW_SPEED
            if math.abs(angleDelta) < Mizuki.WeaponParameters.CannonAngleSnapDegrees then
                orbitAngle = targetAngle
            end
        end
        if not onlyCannon or onlyCannon.SubType == side then
            data.MizukiCannonOrbitAngles[side] = orbitAngle
        end
        local orbitDirection = sideIdle
            and Vector(0, -1) or Vector.FromAngle(orbitAngle)
        sideOrbitDirections[side] = orbitDirection
        local sideIsHorizontal = math.abs(orbitDirection.X)
            > math.abs(orbitDirection.Y)
        local sidePositionCharacterLeft = orbitDirection:Rotated(-90)
        local positionEyeDirection = side == 1
            and sidePositionCharacterLeft
            or -sidePositionCharacterLeft
        sideHorizontalStates[side] = sideIsHorizontal
        sideEyeDirections[side] = positionEyeDirection
        for member = 1, #data.MizukiCannons[side] do
            local layoutCannon = data.MizukiCannons[side][member]
            local pairProfile = data.MizukiExpectedCannonPairProfiles
                and data.MizukiExpectedCannonPairProfiles[member]
            if not onlyCannon or Mizuki.isSameEntity(layoutCannon, onlyCannon) then
                Mizuki.applyGuillotineCannonProfile(
                    layoutCannon, pairProfile, guillotineHeads
                )
            end
            local head = layoutCannon:GetData().MizukiGuillotineHead
            local layoutCenter = head and head.Position or player.Position
            local groupDistance = (pairProfile and pairProfile.GuillotineNonFiring)
                and 0 or (member - 1) * Config.CANNON_GROUP_SPACING
            if sideIdle or layoutCannon:GetData().MizukiGuillotineNonFiring then
                local restingOffset = Mizuki.getCannonIdleLayout(player, side, groupDistance)
                targetPositions[side][member] = layoutCenter
                    + scalePlayerOffset(player, restingOffset)
            else
                -- The pair's midpoint lies on the orbit. Its members sit on
                -- the tangent, with the half-spacing easing from 3 to 5.
                targetPositions[side][member] = Mizuki.getCannonAttackPosition(
                    player, layoutCannon, orbitDirection, member)
            end
            -- Layout offset for this side and member: where the cannon belongs
            -- for the current aim, with no follow lag in it. A room transition
            -- re-places the cannons from this. Carrying the cannon's actual
            -- position instead would also carry its deliberate follow lag
            -- through the doorway, so the cannon would land slightly out of
            -- place and then visibly coast back.
            if layoutCannon and layoutCannon:Exists()
                and (not onlyCannon or Mizuki.isSameEntity(layoutCannon, onlyCannon)) then
                layoutCannon:GetData().MizukiLayoutOffset =
                    Vector(
                        targetPositions[side][member].X,
                        targetPositions[side][member].Y
                    ) - player.Position
            end
        end
    end

    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    for side = 1, 2 do
        local lockedPositions = data.MizukiLockedCannonPositions[side]
        local activeSideBeams = data.MizukiActiveBeams
            and data.MizukiActiveBeams[side]
        if activeSideBeams and #activeSideBeams > 0 and lockedPositions then
            for member = 1, #targetPositions[side] do
                if not data.MizukiCannons[side][member]:GetData().MizukiGuillotineNonFiring then
                    targetPositions[side][member] = lockedPositions[member]
                        or targetPositions[side][member]
                end
            end
        end
    end

    local autoFireState = data.MizukiCannonAutoFireState
    local isDeployed = autoFireState == "deployed"
    local deployedPositions = data.MizukiCannonAutoFirePositions
    if isDeployed then
        for side = 1, 2 do
            for member, cannon in ipairs(data.MizukiCannons[side]) do
                if cannon and cannon:Exists()
                    and not cannon:GetData().MizukiAwaitingInitialLayout
                    and not cannon:GetData().MizukiGuillotineNonFiring
                    and not Mizuki.isTech2Cannon(cannon)
                then
                    local fixedPosition = deployedPositions[side][member]
                    if not fixedPosition then
                        fixedPosition = Vector(cannon.Position.X, cannon.Position.Y)
                        deployedPositions[side][member] = fixedPosition
                    end
                    targetPositions[side][member] = fixedPosition
                end
            end
        end
    end

    if not onlyCannon then
        data.MizukiCannonPositions = { {}, {} }
    else
        data.MizukiCannonPositions = data.MizukiCannonPositions or { {}, {} }
    end
    local frame = Game():GetFrameCount()
    for side = 1, 2 do
        local eyeDirection = sideEyeDirections[side]
        local sideIsHorizontal = sideHorizontalStates[side]
        for member, targetPosition in ipairs(targetPositions[side]) do
            if not onlyCannon or Mizuki.isSameEntity(data.MizukiCannons[side][member], onlyCannon) then
                local cannon = data.MizukiCannons[side][member]
                local cannonData = cannon:GetData()
                local tech5Pose = Mizuki.getTech5CannonPose(cannon)
                if tech5Pose then
                    targetPosition = Mizuki.getCannonAttackPosition(
                        player, cannon, tech5Pose.PositionAim, member)
                    cannonData.MizukiLayoutOffset = targetPosition - player.Position
                end
                -- Extra heads keep the complete resting pose during the player's
                -- attack, including height, swing, reflection and shadow.
                local nonFiring = cannonData.MizukiGuillotineNonFiring
                local memberIsIdle = (sideIdleStates[side] and not tech5Pose) or nonFiring
                local _, idleSlot, idleWidth, idleMirror, idleNear, idleAngleMirror = Mizuki.getCannonIdleLayout(player, side)
                -- Eye slots keep their original identities. Only the right-facing
                -- artwork borrows the opposite slot's tilt before mirroring it.
                local idleTiltSlot = idleSlot + (3 - 2 * idleSlot) * idleAngleMirror
                cannonData.MizukiIdleScreenXScale = memberIsIdle and idleWidth or 1
                cannonData.MizukiIdleFlipProgress = memberIsIdle and idleMirror or 0
                cannonData.MizukiIdleDepthOrder = memberIsIdle and idleNear or 0
                cannonData.MizukiIdleAngleMirrorProgress = memberIsIdle and idleAngleMirror or 0
                local tech2Cannon = Mizuki.isTech2Cannon(cannon)
                local memberIsDeployed = isDeployed and not nonFiring and not tech2Cannon
                local sideIsHorizontal = sideIsHorizontal and not nonFiring
                local memberEyeDirection = eyeDirection
                if tech5Pose then
                    sideIsHorizontal = math.abs(tech5Pose.PositionAim.X) > math.abs(tech5Pose.PositionAim.Y)
                    memberEyeDirection = tech5Pose.PositionAim:Rotated(side == 1 and -90 or 90)
                end
                local pairProfile = data.MizukiExpectedCannonPairProfiles
                    and data.MizukiExpectedCannonPairProfiles[member]
                Mizuki.applyPersistentCannonEchoProfile(cannon, pairProfile)
                cannonData.MizukiTech2EchoSuppressed = tech2Cannon
                    and cannonData.MizukiPersistentEchoMode ~= nil
                cannonData.MizukiContactDamageMultiplier = pairProfile
                    and pairProfile.DamageMultiplier or 1
                Mizuki.updateCannonCollisionSize(
                    cannon,
                    pairProfile and pairProfile.ScaleMultiplier or 1,
                    autoFireState == "returning"
                )
                local sideBeams = data.MizukiActiveBeams
                    and data.MizukiActiveBeams[side]
                local isFiring = (sideFiringStates[side] or tech5Pose ~= nil) and not nonFiring
                local isFollowingFiring = (sideFollowingStates[side] or tech5Pose ~= nil
                    or tech2Cannon) and not nonFiring
                local bobOffset = Vector(
                    0,
                    Mizuki.getCannonHoverOffset(frame)
                )
                local idleHeightOffset = memberIsIdle
                    and getCannonIdleHeightOffset(player)
                    or Vector.Zero
                local snapToFiringPosition = isFiring and not isFollowingFiring
                -- Appearance release shares the exact state that selects the frozen
                -- firing position, including the native laser's shrinking tail.
                cannonData.MizukiCannonFiringPositionLocked = snapToFiringPosition
                    or (isFiring and cannonData.MizukiGuillotineHead ~= nil
                        and not memberIsDeployed and not tech2Cannon and not tech5Pose)
                -- The hover bob stays out of the entity's own position. The engine
                -- draws the shadow layer itself, at that position, and it rounds the
                -- position and the sprite offset separately - so any per-frame wobble
                -- in the position shows up as the shadow flipping between two
                -- neighbouring pixels. Only the hand-drawn body carries the bob (see
                -- Mizuki:RenderCannon), which leaves the shadow dead still.
                -- Firing does not suppress that visual motion: the beam and every
                -- locked position still use the resolved logical position, while
                -- only the body, charge circle and reflection consume
                -- MizukiBobOffsetY.
                cannonData.MizukiBobOffsetY = bobOffset.Y
                local fixedPosition = memberIsDeployed
                    and deployedPositions[side][member]
                local desiredPosition = (fixedPosition or snapToFiringPosition)
                    and targetPosition
                    or (targetPosition + idleHeightOffset)
                if autoFireState == "returning" and not nonFiring and not tech2Cannon then
                    cannonData.MizukiAutoFireReturnTarget = desiredPosition
                else
                    cannonData.MizukiAutoFireReturnTarget = nil
                end
                local snapToDirectAimPosition =
                    (data.MizukiSnapCannonsToDirectAim or snapSide == side)
                    and (not isFiring or tech5Pose ~= nil) and not nonFiring
                local previousSortOffset = cannon.Position.Y + cannon.DepthOffset
                    - (player.Position.Y + player.DepthOffset)

                local resolvedCannonPosition
                if cannonData.MizukiPersistentEchoMode == "automatic" then
                    -- The delayed source pose below owns this cannon's target.
                    -- Do not snap it to today's deployment/direct-aim layout or
                    -- add another elastic lag before replaying the recorded pose.
                    resolvedCannonPosition = desiredPosition
                elseif cannonData.MizukiAwaitingInitialLayout then
                    -- The spawn coordinate and its interpolation history are both
                    -- temporary. Hold the Familiar at the first complete layout for
                    -- one full game frame before exposing it; showing it in the same
                    -- frame as this snap can still render the old interpolated point.
                    resolvedCannonPosition = desiredPosition
                    Mizuki.snapCannonPosition(player, cannon, resolvedCannonPosition)
                    local settledFrame = cannonData.MizukiInitialLayoutFrame
                    if settledFrame and frame > settledFrame then
                        cannonData.MizukiAwaitingInitialLayout = nil
                        cannonData.MizukiInitialLayoutFrame = nil
                    elseif not settledFrame then
                        cannonData.MizukiInitialLayoutFrame = frame
                    end
                elseif fixedPosition or snapToFiringPosition
                    or snapToDirectAimPosition then
                    -- A stationary cannon keeps its captured world position. Firing
                    -- and the first direct-aim frame also resolve without follow lag.
                    resolvedCannonPosition = desiredPosition
                    Mizuki.snapCannonPosition(player, cannon, resolvedCannonPosition)
                else
                    resolvedCannonPosition = getCannonPositionWithElasticLag(
                        player,
                        cannon,
                        desiredPosition
                    )
                end
                cannonData.MizukiDesiredPosition = resolvedCannonPosition

                local targetDepthOffset = getCannonTargetDepthOffset(
                    player,
                    cannon,
                    memberIsIdle,
                    isFiring,
                    isFollowingFiring,
                    sideIsHorizontal,
                    memberEyeDirection
                    )
                if not tech5Pose and snapToFiringPosition
                    and cannonData.MizukiLockedFiringDepthOffset ~= nil
                then
                    -- A finite shot locks position and depth as one pose. Preserve
                    -- the offset each cannon had when firing began instead of
                    -- moving every cannon onto one shared firing layer.
                    targetDepthOffset = cannonData.MizukiLockedFiringDepthOffset
                elseif not tech5Pose and not snapToFiringPosition then
                    cannonData.MizukiLockedFiringDepthOffset = nil
                end
                if memberIsIdle and player:GetHeadDirection() == Direction.UP then
                    -- Resting cannons behind the head must sort below the
                    -- player, independent of their hover position/follow lag.
                    cannonData.MizukiHorizontalSortOffset = nil
                    cannon.DepthOffset = player.Position.Y + player.DepthOffset
                        - resolvedCannonPosition.Y - 1
                elseif sideIsHorizontal and not snapToFiringPosition then
                    -- Use the authored target pose to choose the intended sorting
                    -- layer, but solve DepthOffset from the position the Familiar
                    -- reaches after its velocity is applied this frame. Player
                    -- movement can therefore create a small visible lag without
                    -- ever dragging a horizontal cannon through the body.
                    local targetSortOffset = desiredPosition.Y + targetDepthOffset
                        - (player.Position.Y + player.DepthOffset)
                    updateHorizontalCannonDepthOffset(
                        player,
                        cannon,
                        resolvedCannonPosition,
                        targetSortOffset,
                        previousSortOffset,
                        snapToDirectAimPosition
                    )
                else
                    cannonData.MizukiHorizontalSortOffset = nil
                    -- Snap depth whenever the position snaps, including the first
                    -- direct-aim frame before its immediate beam is created.
                    updateCannonDepthOffset(
                        cannon,
                        targetDepthOffset,
                        snapToFiringPosition or snapToDirectAimPosition
                    )
                end
                local lockedCannonState = not nonFiring and data.MizukiLockedCannonAims[side]
                local lockedPositionAim = lockedCannonState
                    and lockedCannonState.PositionAim
                local lockedCannonAim = lockedCannonState
                    and lockedCannonState.MemberAims[member]
                local cannonAim = tech5Pose and tech5Pose.Direction or lockedCannonAim
                    or aim or Vector(0, -1)
                if Mizuki.hasLinkedCannonTechX(data, side, cannon) then
                    -- The guide ray and body use the same resolved orbit pose.
                    -- A following cannon eases toward input before dragging its ring.
                    cannonAim = sideOrbitDirections[side]
                    lockedPositionAim = sideOrbitDirections[side]
                end
                if nonFiring or (memberIsIdle
                    and Mizuki.usesCSectionWeapon(player))
                    or (memberIsIdle and Mizuki.usesCannonSpiritSword(player))
                    or (memberIsIdle and Mizuki.isBerserkClubActive(player)
                    and (Mizuki.getCannonKnifeWeaponVariant(player) == 2
                        or Mizuki.getCannonKnifeWeaponVariant(player) == 3)) then
                    -- Restore the actual idle aim before deriving both rotation and
                    -- pivot displacement; correcting only the final draw leaves
                    -- the pivot anchored to the previous firing direction.
                    cannonAim = Vector(0, -1)
                elseif autoFireState == "deployed" and not lockedCannonAim then
                    cannonAim = Mizuki.getCannonAutoFireAim(player, data, member)
                end
                cannon.Visible = not cannonData.MizukiAwaitingInitialLayout
                    and not cannonData.MizukiGuillotineDisplaySuppressed
                    and not cannonData.MizukiTech2EchoSuppressed
                Mizuki.updateSpiritSwordBodyVisibility(cannon)
                cannonData.CannonSide = side
                cannonData.MizukiRenderWorldOffset = nil
                cannonData.MizukiLudovicoOrbiting = nil
                cannonData.MizukiLudovicoDamageMultiplier = nil
                cannonData.MizukiLudovicoScaleMultiplier = nil
                -- Read by Mizuki:RenderCannon to pick the resting or firing
                -- reflection distance and mirroring.
                cannonData.MizukiIsIdle = memberIsIdle
                Mizuki.updateCannonBrimstoneCurse(cannon)
                -- Keep the native shadow on the snapped pose; its position uses
                -- half this span, so easing it after a direct-aim snap would make
                -- the shadow visibly slide in from the old idle location.
                local targetSpan = Mizuki.getCannonReflectionSpan(player, memberIsIdle)
                local smoothSpan = cannonData.MizukiReflectionSpan
                if smoothSpan == nil or snapToFiringPosition
                    or snapToDirectAimPosition
                then
                    cannonData.MizukiReflectionSpan = targetSpan
                else
                    smoothSpan = smoothSpan
                        + (targetSpan - smoothSpan) * Config.CANNON_REFLECTION_SPAN_SPEED
                    if math.abs(smoothSpan - targetSpan) < Mizuki.WeaponParameters.CannonReflectionSnapDistance then
                        smoothSpan = targetSpan
                    end
                    cannonData.MizukiReflectionSpan = smoothSpan
                end
                local sideIdleRotation = Config.LEFT_CANNON_IDLE_ROTATION
                    + (Config.RIGHT_CANNON_IDLE_ROTATION - Config.LEFT_CANNON_IDLE_ROTATION) * (idleTiltSlot - 1)
                local idleRotationTarget = memberIsIdle and sideIdleRotation
                    or 0
                if tech5Pose or snapToDirectAimPosition then
                    -- Position and pose resolve together before the immediate beam
                    -- samples its origin.
                    cannonData.MizukiIdleRotationOffset = idleRotationTarget
                elseif cannonData.MizukiIdleRotationOffset == nil then
                    cannonData.MizukiIdleRotationOffset = idleRotationTarget
                else
                    cannonData.MizukiIdleRotationOffset = cannonData.MizukiIdleRotationOffset
                        + (idleRotationTarget - cannonData.MizukiIdleRotationOffset)
                        * rotationReturnSpeed
                    if math.abs(cannonData.MizukiIdleRotationOffset - idleRotationTarget) < Mizuki.WeaponParameters.CannonAngleSnapDegrees then
                        cannonData.MizukiIdleRotationOffset = idleRotationTarget
                    end
                end
                -- The body points toward the attack aim, while its pivot starts
                -- from the current orbit heading. A finite beam keeps its locked
                -- orbit heading even if the player's live input changes.
                local idleRotation = cannonData.MizukiIdleRotationOffset
                if memberIsIdle then
                    local swingFrame = cannonData.MizukiIdleSwingFrame or 0
                    local swingProgress = (1 - math.cos(
                        swingFrame * 2 * math.pi / idleSwingPeriod
                    )) * 0.5
                    cannonData.MizukiIdleSwingProgress = swingProgress
                    local outerRotation = Config.LEFT_CANNON_IDLE_OUTER_ROTATION
                        + (Config.RIGHT_CANNON_IDLE_OUTER_ROTATION - Config.LEFT_CANNON_IDLE_OUTER_ROTATION) * (idleTiltSlot - 1)
                    local inwardRotation = sideIdleRotation
                    idleRotation = idleRotation
                        + (outerRotation - inwardRotation) * swingProgress
                    cannonData.MizukiIdleSwingFrame = (swingFrame + 1) % idleSwingPeriod
                else
                    cannonData.MizukiIdleSwingFrame = nil
                    cannonData.MizukiIdleSwingProgress = nil
                end
                local sprite = cannon:GetSprite()
                local target = autoFireState ~= "deployed"
                    and not nonFiring and not memberIsIdle and targetReticle or nil
                if tech5Pose and tech5Pose.TargetPosition then
                    target = {Position = tech5Pose.TargetPosition}
                end
                local spritePositionAim = tech5Pose and tech5Pose.PositionAim or nonFiring and Vector(0, -1)
                    or lockedPositionAim or sideOrbitDirections[side]
                if autoFireState == "deployed" and not nonFiring then
                    spritePositionAim = cannonAim
                end
                cannonData.MizukiVerticalBodyXFactor = Mizuki.getCannonBodyXFactor(
                    side, spritePositionAim, memberIsIdle, idleSlot
                )
                if memberIsIdle then
                    cannonData.MizukiReflectionBodyXFactor = nil
                else
                    -- Each cannon keeps its own reflection. Mirroring the horizontal
                    -- aim makes the other cannon reach the edge-on flip on a sideways
                    -- turn, while both match their bodies at vertical aim.
                    local reflectionAim = Vector(
                        -spritePositionAim.X, spritePositionAim.Y
                    )
                    cannonData.MizukiReflectionBodyXFactor = Mizuki.getCannonBodyXFactor(
                        side, reflectionAim, false
                    )
                end
                Mizuki.updateCannonBodyGraphics(cannon, cannonData)
                if target and not lockedCannonAim then
                    for _ = 1, 2 do
                        local _, cannonTrialOffset, knifeTrialOffset = Mizuki.getCannonSpriteTransform(
                            cannon,
                            cannonAim,
                            spritePositionAim,
                            idleRotation
                        )
                        local trialOffset = Mizuki.cannonUsesKnifeWeapon(player) and knifeTrialOffset or cannonTrialOffset
                        cannonAim = Mizuki.resolveBeamGeometry(
                            resolvedCannonPosition + trialOffset,
                            cannonAim,
                            0,
                            target.Position
                        )
                    end
                end
                local spriteRotation, pivotRenderOffset, basePivotRenderOffset = Mizuki.getCannonSpriteTransform(
                    cannon,
                    cannonAim,
                    spritePositionAim,
                    idleRotation
                )
                cannonData.MizukiPivotRenderOffset = pivotRenderOffset
                -- The pose lives in the data, not on the sprite, so the engine's own
                -- draw of the sprite stays straightened for the shadow layer.
                cannonData.MizukiCannonBodyRotation = spriteRotation
                cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
                sprite.Rotation = 0
                Mizuki.updateSpiritSwordReturnShadow(cannon, desiredPosition, memberIsIdle)
                Mizuki.applyCannonShadowPose(player, cannon, memberIsDeployed)
                -- Hide the engine's own draw; Mizuki:RenderCannon replaces it in
                -- the same render slot and draws the water reflection separately.
                -- Alpha is used instead of Visible on purpose:
                -- an invisible entity stops being rendered, which would also stop
                -- the render callback that re-draws it.
                sprite.Color = Mizuki.getCannonHiddenColor()
                cannonData.MizukiCannonAim = cannonAim
                resolvedCannonPosition = Mizuki.updateAutomaticCannonEchoPose(
                    player, data, cannon, resolvedCannonPosition, member, side, frame
                )
                if cannonData.MizukiPersistentEchoMode == "automatic" then
                    Mizuki.updateCannonBodyGraphics(cannon, cannonData)
                    Mizuki.applyCannonShadowPose(player, cannon, memberIsDeployed)
                end
                data.MizukiCannonPositions[side][member] = Vector(
                    resolvedCannonPosition.X,
                    resolvedCannonPosition.Y
                )

                -- The resolved position, rotation and render offset are final here.
                -- Keep every cannon-following beam transform in this single update
                -- path so later callbacks cannot overwrite one another. Automatic
                -- beams and finite Anti-Gravity beams share only this positioning;
                -- their firing cadence and lifetime remain separate.
                local sideBeams = data.MizukiActiveBeams
                    and data.MizukiActiveBeams[side]
                if sideBeams then
                    for _, beam in ipairs(sideBeams) do
                        local laser = beam.Laser
                        if beam.FollowCannon
                            and not (beam.MomKnifeDriven and beam.Ending)
                            and beam.Cannon
                            and GetPtrHash(beam.Cannon) == GetPtrHash(cannon)
                            and laser
                            and laser:Exists()
                        then
                            local pivotRenderOffset = Mizuki.getCannonBeamPivotRenderOffset(
                                player, cannonData
                            )
                            -- Reticle geometry follows the logical firing origin.
                            -- Visual bob belongs only to the hand-drawn cannon body.
                            local visualOrigin = resolvedCannonPosition
                                + pivotRenderOffset
                            -- Finite Anti-Gravity shots follow only the cannon's
                            -- position. Keep their fired direction and distance;
                            -- live reticle tracking remains an automatic-beam rule.
                            local target = (beam.Automatic or beam.TechXChain)
                                and not beam.PersistentEchoMode
                                and not beam.MizukiAutoFire and targetReticle or nil
                            local directionOffset = beam.DirectionOffset or 0
                            local baseDirection = beam.Direction:Rotated(
                                -directionOffset
                            )
                            if beam.PersistentEchoMode == "automatic" then
                                baseDirection = cannonData.MizukiCannonAim or baseDirection
                            end
                            local originCorrection
                            beam.Direction, originCorrection = Mizuki.resolveBeamGeometry(
                                visualOrigin,
                                baseDirection,
                                directionOffset,
                                target and target.Position or nil
                            )
                            local hitboxOffset = Vector(0, Config.BEAM_HITBOX_Y_OFFSET)
                            if not beam.TechXDriven then
                                laser.AngleDegrees = beam.MomKnifeDriven
                                    and Mizuki.getCannonKnifeBeamAngle(beam)
                                    or beam.Direction:GetAngleDegrees()
                            end
                            laser.Position = resolvedCannonPosition
                                + pivotRenderOffset
                                + hitboxOffset
                                + originCorrection
                            if beam.TechXChain and not beam.Ending then
                                beam.TechXGuideOrigin = Vector(laser.Position.X, laser.Position.Y)
                            end
                            laser.PositionOffset = -hitboxOffset
                            local reflectionDepthShift =
                                Mizuki.applyBeamReflectionHeight(player, laser)
                            laser.Velocity = Vector.Zero
                            laser.DepthOffset = cannon.DepthOffset - Mizuki.WeaponParameters.BeamDepthBehindCannon
                                - hitboxOffset.Y
                                - originCorrection.Y
                                - reflectionDepthShift
                            if target then
                                local targetDistance = (
                                    target.Position
                                    - (visualOrigin + originCorrection)
                                ):Length()
                                if beam.TechXChain and not beam.Ending then
                                    beam.Distance = math.max(1, targetDistance)
                                end
                                laser:SetMaxDistance(math.max(1, targetDistance))
                            end
                        end
                    end
                end
            end
        end
    end
end

function Mizuki.updateCannonReconcile(player, data)
    local reconcileState = Mizuki.getCannonReconcileState(player)
    if not reconcileState.Frames then
        return
    end

    reconcileState.Frames = reconcileState.Frames - 1
    if reconcileState.Frames <= 0 then
        reconcileState.Frames = nil
        reconcilePlayerCannons(player, data)
    end
end

function Mizuki:QueueBoxOfFriendsCannonRefresh(collectible, rng, player)
    if Mizuki.isMizuki(player) then
        -- Resolve on the next player update, after the vanilla active effect
        -- has incremented its temporary Box of Friends effect count.
        player:GetData().MizukiRefreshCannonCache = true
    end
end

function Mizuki:InitCannonFamiliar(cannon)
    cannon.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
    cannon.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    cannon.CollisionDamage = 0
    local cannonData = cannon:GetData()
    -- CheckFamiliar creates the entity before the player and render interpolation
    -- have settled. Keep every layer out of the pipeline until the first real
    -- weapon layout can place it once at the resolved player-relative position.
    cannonData.MizukiAwaitingInitialLayout = true
    cannon.DepthOffset = Config.CANNON_DEPTH_OFFSET
    cannon.Visible = false
    cannon:GetSprite().Color = Mizuki.getCannonHiddenColor()
end

-- Apply the resolved movement and keep the Familiar's player-scaled body/shadow
-- transform in its own update path, so native interpolation sees both together.
function Mizuki:UpdateCannonFamiliar(cannon)
    ensureCannonRegistered(cannon)
    local cannonData = cannon:GetData()
    local roomEntryOffset = cannonData.MizukiPendingRoomEntryOffset
    local player = cannon.Player
    if player and player:Exists()
        and player:GetData().MizukiLudovicoKnifeResyncPending
    then
        cannonData.MizukiDeferMomKnifeUntilLudovicoReady = true
    end
    if cannonData.MizukiDeferMomKnifeUntilLudovicoReady
        and player
        and player:Exists()
        and not Mizuki.usesLudovicoWeapon(player)
    then
        -- A reroll during the transition can remove Ludovico before its setup
        -- consumes the deferred spawn. Fall back to the ordinary cannon path.
        cannonData.MizukiDeferMomKnifeUntilLudovicoReady = nil
    end
    if roomEntryOffset and player and player:Exists() then
        -- MC_POST_NEW_ROOM can run before the engine has finalized the player's
        -- destination-floor position. Resolve the saved relative layout here,
        -- in the Familiar's first real update, so neither body nor knife spends
        -- a frame at the engine's temporary room coordinate.
        cannon.Position = player.Position + roomEntryOffset
        cannon.Velocity = Vector.Zero
        cannonData.MizukiDesiredPosition = Vector(
            cannon.Position.X,
            cannon.Position.Y
        )
        cannonData.MizukiPoseOffset = Vector(
            roomEntryOffset.X,
            roomEntryOffset.Y
        )
        cannonData.MizukiLastPlayerPosition = Vector(
            player.Position.X,
            player.Position.Y
        )
        cannonData.MizukiPendingRoomEntryOffset = nil
    end
    local desiredPosition = cannonData.MizukiDesiredPosition
    if desiredPosition and not cannonData.MizukiLudovicoOrbiting then
        -- Move through the Familiar's own update path, like native/custom
        -- followers normally do, instead of teleporting Position from the
        -- player's callback. Velocity supplies the engine with the motion it
        -- needs to interpolate both the Familiar and its native shadow.
        cannon.Velocity = desiredPosition - cannon.Position
    end
    -- A freshly spawned Familiar still carries the engine's temporary spawn
    -- coordinate and interpolation history. Do not expose either its native
    -- shadow or the manually redrawn body until a weapon layout has resolved
    -- the first real position. Afterwards it stays in the native pipeline so
    -- layer 2 can continue to supply the shadow.
    cannon.Visible = not cannonData.MizukiAwaitingInitialLayout
        and not cannonData.MizukiGuillotineDisplaySuppressed
        and not cannonData.MizukiTech2EchoSuppressed
    Mizuki.updateSpiritSwordBodyVisibility(cannon)
    Mizuki.updateCannonBodyGraphics(cannon, cannonData)
    -- LoadGraphics and callback ordering can restore the sprite's visible
    -- colour after the player-owned positioning update. Reassert the hidden
    -- native body here, in the Familiar's own update, for both ordinary and
    -- Ludovico cannons. Visible stays true so layer 2 still reaches the engine's
    -- native shadow pass; RenderCannon temporarily restores body alpha only for
    -- the explicit layer 0/1 draw.
    cannon:GetSprite().Color = Mizuki.getCannonHiddenColor()
    cannon.SpriteScale = Mizuki.getCannonVisualScale(cannon)
    if not cannonData.MizukiAwaitingInitialLayout
        and not cannonData.MizukiDeferMomKnifeUntilLudovicoReady
        and Mizuki.updateCannonMomKnife
    then
        Mizuki.updateCannonMomKnife(cannon)
    end
    Mizuki.updateSpiritSwordCannonPose(cannon)
end

function Mizuki:ResetCannonsForNewRoom()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then
            local data = player:GetData()
            data.MizukiActiveBeams = {}
            data.MizukiLockedCannonPositions = {}
            data.MizukiLockedCannonAims = {}
            data.MizukiCannonAutoFireState = nil
            data.MizukiCannonAutoFirePositions = nil
            data.MizukiCannonAutoFireInputHeld = nil
            data.MizukiCannonAutoFireLastTapFrame = nil
            data.MizukiCursedEyeBurst = nil
            data.MizukiSnapCannonsToDirectAim = nil
            data.MizukiDirectAimActive = nil
            data.MizukiEpicFetusGridCandidate = nil
            data.MizukiEpicFetusLudovicoCandidate = nil
            data.MizukiEpicFetusLudovicoGeometry = nil
            data.MizukiLudovicoNeedsRoomEntryReset = true
            Mizuki.removeLudovicoTriggeredBeams(data)

            local ludovicoRing = data.MizukiLudovicoRing
            if ludovicoRing and ludovicoRing:Exists() then
                local ringData = ludovicoRing:GetData()
                ringData.MizukiLudovicoDamageSchedules = nil
            end

            claimPlayerCannons(player, data)
            local hasLudovico = Mizuki.usesLudovicoWeapon(player)
            local deferLudovicoMomKnife = hasLudovico
                and player:HasCollectible(
                    CollectibleType.COLLECTIBLE_MOMS_KNIFE
                )
            data.MizukiLudovicoKnifeResyncPending =
                deferLudovicoMomKnife and true or nil
            data.MizukiLudovicoKnifeResyncReady = nil

            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side]) do
                    if cannon:Exists() then
                        local cannonData = cannon:GetData()
                        cannonData.MizukiContactDamageSchedules = nil
                        local restingOffset, idleSlot, idleWidth, idleMirror, idleNear, idleAngleMirror = Mizuki.getCannonIdleLayout(
                            player, side, (member - 1) * Config.CANNON_GROUP_SPACING)
                        local idleTiltSlot = idleSlot + (3 - 2 * idleSlot) * idleAngleMirror
                        -- Carry the layout the cannons were in when the player
                        -- walked through the door, rather than their exact
                        -- position: the door pull leaves the cannons lagging by
                        -- the time the room changes, and carrying that lag makes
                        -- them land out of place and coast back. Snapping to the
                        -- resting position over the head instead is what this
                        -- replaces - a held charge or a live beam can have the
                        -- cannons in a different layout on the way out.
                        local carriedOffset = cannonData.MizukiLayoutOffset
                        local roomEntryOffset
                        if hasLudovico then
                            -- The new room's ring starts over the player. The
                            -- previous controlled ring displacement belongs to
                            -- the old room and must not be carried across.
                            roomEntryOffset = Vector.Zero
                        else
                            roomEntryOffset = carriedOffset
                                or scalePlayerOffset(player, restingOffset)
                        end
                        cannonData.MizukiDeferMomKnifeUntilLudovicoReady =
                            deferLudovicoMomKnife and true or nil
                        cannon.Position = player.Position + roomEntryOffset
                        cannon.Velocity = Vector.Zero
                        cannonData.MizukiDesiredPosition = Vector(
                            cannon.Position.X,
                            cannon.Position.Y
                        )
                        cannonData.MizukiPoseOffset = cannon.Position - player.Position
                        cannonData.MizukiPendingRoomEntryOffset = Vector(
                            roomEntryOffset.X,
                            roomEntryOffset.Y
                        )
                        cannonData.MizukiMovementLag = Vector.Zero
                        -- The position was just snapped to the layout, so the
                        -- drawn body carries no hover bob either.
                        cannonData.MizukiBobOffsetY = 0
                        cannonData.MizukiLastPlayerPosition = Vector(
                            player.Position.X,
                            player.Position.Y
                        )
                        cannonData.MizukiHorizontalSortOffset = nil
                        local aim = data.MizukiCannonAim or Vector(0, -1)
                        cannonData.MizukiCannonAim = aim
                        -- The idle tilt is a smoothed value: leave it as it is so
                        -- it keeps easing, instead of snapping to the resting
                        -- angle on arrival.
                        local idleRotation = cannonData.MizukiIdleRotationOffset
                            or (Config.LEFT_CANNON_IDLE_ROTATION
                                + (Config.RIGHT_CANNON_IDLE_ROTATION - Config.LEFT_CANNON_IDLE_ROTATION) * (idleTiltSlot - 1))
                        local sprite = cannon:GetSprite()
                        local spriteRotation, pivotRenderOffset, basePivotRenderOffset = Mizuki.getCannonSpriteTransform(
                            cannon,
                            aim,
                            aim,
                            idleRotation
                        )
                        cannonData.MizukiPivotRenderOffset = pivotRenderOffset
                        cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
                        cannonData.MizukiCannonBodyRotation = spriteRotation
                        sprite.Rotation = 0
                        if not deferLudovicoMomKnife
                            and Mizuki.resetCannonMomKnife
                        then
                            -- Ordinary weapons reset only after their owning
                            -- cannon has been placed. Ludovico deliberately
                            -- keeps its existing knife hidden until the ring's
                            -- final room-entry position is known.
                            Mizuki.resetCannonMomKnife(cannon)
                        end
                    end
                end
            end
        end
    end
end

-- Shared cannon controls and native contact damage.

-- Guillotine heads remain engine-owned. Their extra cannon pairs keep an idle
-- pose and contact damage, without firing; item/echo copies retain their roles.
do
    function Mizuki.getGuillotineHeads(player)
        local heads = {}
        local ownerHash = GetPtrHash(player)
        for _, entity in ipairs(Isaac.FindByType(
            EntityType.ENTITY_FAMILIAR, FamiliarVariant.GUILLOTINE, -1, false, false
        )) do
            local head = entity:ToFamiliar()
            if head and head.Player and GetPtrHash(head.Player) == ownerHash then
                heads[#heads + 1] = head
            end
        end
        -- Native Guillotine updates publish the firing origin as TearsOffset.
        -- Index/InitSeed order does not identify that head. Match the native
        -- origin; retain the previous identity only when distances are tied.
        table.sort(heads, function(a, b) return a.Index < b.Index end)
        local data = player:GetData()
        local primary = data.MizukiGuillotinePrimaryHead
        if primary and not primary:Exists() then primary = nil end
        local nearestDistance = math.huge
        local nativeOrigin = player.Position + player.TearsOffset
        for _, head in ipairs(heads) do
            local distance = head.Position:DistanceSquared(nativeOrigin)
            if distance < nearestDistance
                or (distance == nearestDistance and primary
                    and GetPtrHash(head) == GetPtrHash(primary))
            then
                nearestDistance = distance
                data.MizukiGuillotinePrimaryHead = head
            end
        end
        primary = #heads > 0 and data.MizukiGuillotinePrimaryHead or nil
        for index, head in ipairs(heads) do
            if primary and GetPtrHash(head) == GetPtrHash(primary)
            then
                table.remove(heads, index)
                table.insert(heads, 1, head)
                break
            end
        end
        data.MizukiGuillotinePrimaryHead = heads[1]
        return heads
    end

    function Mizuki.appendGuillotineCannonProfiles(player, profiles)
        -- Ludovico already owns the cannon pairs as projectile geometry.
        if Mizuki.usesLudovicoWeapon(player)
        then return profiles end
        local heads = Mizuki.getGuillotineHeads(player)
        local count = math.max(#heads,
            player:GetCollectibleNum(CollectibleType.COLLECTIBLE_GUILLOTINE))
        for index = 2, count do
            profiles[#profiles + 1] = {
                GuillotineNonFiring = true, GuillotineHeadIndex = index,
                DamageMultiplier = 1, ScaleMultiplier = 1,
            }
        end
        return profiles
    end

    function Mizuki.applyGuillotineCannonProfile(cannon, profile, heads)
        local data = cannon:GetData()
        data.MizukiGuillotineNonFiring = profile
            and profile.GuillotineNonFiring == true or false
        data.MizukiGuillotineHead = heads[profile and profile.GuillotineHeadIndex or 1]
        data.MizukiGuillotineDisplaySuppressed = data.MizukiGuillotineNonFiring
            and not data.MizukiGuillotineHead
    end
end

do
    -- Double-tap deployment and recall share the same cannon state as layout.

    local DOUBLE_TAP_WINDOW_FRAMES = 15
    local RETURN_SETTLE_DISTANCE = 10

    local function getCannonGroundAim(player, cannonPosition)
        -- The body is raised above its ground projection by the attack height.
        -- Visual bob and sprite pivot do not affect this aiming geometry.
        local groundPosition = cannonPosition + Vector(
            0,
            Mizuki.CANNON_ATTACK_ORBIT_HEIGHT * player.SpriteScale.Y
        )
        local direction = groundPosition - player.Position
        return direction:Length() > Mizuki.RuntimeParameters.AimDeadZone
            and direction:Normalized() or Vector(0, -1)
    end

    function Mizuki.getCannonAutoFireAim(player, data, member)
        local positions = data.MizukiCannonAutoFirePositions
        if not positions then return Vector(0, -1) end
        local left = positions[1] and positions[1][member]
        local right = positions[2] and positions[2][member]
        if not left and not right then return Vector(0, -1) end
        local midpoint = left and right and (left + right) * 0.5
            or left or right
        return getCannonGroundAim(player, midpoint)
    end

    function Mizuki.updateCannonAutoFireInput(player, data)
        local pressed = player:AreControlsEnabled()
            and Mizuki.hasRawShootingInput(player)
        local triggered = pressed and not data.MizukiCannonAutoFireInputHeld
        data.MizukiCannonAutoFireInputHeld = pressed
        if not triggered then return end

        local frame = Game():GetFrameCount()
        local previousTap = data.MizukiCannonAutoFireLastTapFrame
        local consecutiveTap = previousTap and frame >= previousTap
            and frame - previousTap <= DOUBLE_TAP_WINDOW_FRAMES
        local tapCount = consecutiveTap
            and (data.MizukiCannonAutoFireTapCount or 1) + 1 or 1
        data.MizukiCannonAutoFireLastTapFrame = frame
        data.MizukiCannonAutoFireTapCount = tapCount
        local state = data.MizukiCannonAutoFireState
        if state == "deployed" then
            -- Rapid tapping resumes manual fire immediately; a deliberate
            -- recall still travels home until the next shooting press.
            if tapCount > 2 then
                data.MizukiCannonAutoFireState = nil
            else
                data.MizukiCannonAutoFireState = "returning"
            end
            data.MizukiCannonAutoFirePositions = nil
            data.MizukiCharge = 0
            data.MizukiNeptunusHeldFrames = nil
            data.MizukiAim = nil
            data.MizukiChargeBarFullFrames = nil
            data.MizukiCursedEyeBurst = nil
            return
        end
        if state == "returning" then
            data.MizukiCannonAutoFireState = nil
            return
        end
        -- Recall on the third tap, then suppress deployment for this tap chain.
        if tapCount > 2 then return end

        if tapCount == 2 then
            local positions = { {}, {} }
            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side] or {}) do
                    if cannon and cannon:Exists()
                        and not cannon:GetData().MizukiAwaitingInitialLayout
                        and not cannon:GetData().MizukiGuillotineNonFiring
                    then
                        positions[side][member] = Vector(
                            cannon.Position.X, cannon.Position.Y
                        )
                    end
                end
            end
            data.MizukiCannonAutoFireState = "deployed"
            data.MizukiCannonAutoFirePositions = positions
        end
    end

    function Mizuki.finishCannonAutoFireReturn(player, data)
        if data.MizukiCannonAutoFireState ~= "returning" then return end
        for side = 1, 2 do
            local beams = data.MizukiActiveBeams and data.MizukiActiveBeams[side]
            for _, beam in ipairs(beams or {}) do
                if not beam.Technology2 then return end
            end
        end
        for side = 1, 2 do
            for _, cannon in ipairs(data.MizukiCannons[side] or {}) do
                if cannon and cannon:Exists() then
                    local target = cannon:GetData().MizukiAutoFireReturnTarget
                    local relativePosition = cannon:GetData().MizukiPoseOffset
                        or (cannon.Position - player.Position)
                    if target and relativePosition:Distance(
                        target - player.Position
                    ) > RETURN_SETTLE_DISTANCE then
                        return
                    end
                end
            end
        end
        data.MizukiCannonAutoFireState = nil
    end
end

do
    -- The Familiar's native collision circle detects contact. Each cannon owns
    -- its damage clock; copied cannons no longer share a per-pair schedule.

    local RETURN_COLLISION_RADIUS_MULTIPLIER = 1.5

    function Mizuki.updateCannonCollisionSize(cannon, scaleMultiplier, returning)
        local radius = Mizuki.LUDOVICO_CANNON_MIN_HIT_RADIUS
            * (scaleMultiplier or 1)
            * (returning and RETURN_COLLISION_RADIUS_MULTIPLIER or 1)
        cannon.Size = radius
        return radius
    end

    function Mizuki:DamageOnCannonCollision(cannon, collider)
        local cannonData = cannon:GetData()
        local player = cannon.Player
        if cannonData.MizukiAwaitingInitialLayout
            or cannonData.MizukiGuillotineDisplaySuppressed
            or (cannonData.MizukiIsIdle and not cannonData.MizukiGuillotineNonFiring)
            or not player or not player:Exists()
            or (not cannonData.MizukiGuillotineNonFiring
                and (Mizuki.usesCSectionWeapon(player)
                    or (Mizuki.usesCannonSpiritSword(player)
                        and not Mizuki.isTech2Cannon(cannon))
                    or (Mizuki.cannonUsesKnifeWeapon(player)
                        and not Mizuki.isTech2Cannon(cannon))))
            or not collider:IsVulnerableEnemy()
            or collider:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        then
            return true
        end

        if cannonData.MizukiLudovicoOrbiting then
            -- Contact takes priority for Epic Fetus targeting even when this
            -- cannon's damage clock has not elapsed yet.
            Mizuki.queueLudovicoEpicFetusEnemy(player, collider, true)
        end

        local frame = Game():GetFrameCount()
        local interval = Mizuki.getFireInterval(player)
        local schedules = cannonData.MizukiContactDamageSchedules or {}
        cannonData.MizukiContactDamageSchedules = schedules
        local targetHash = GetPtrHash(collider)
        local targetSeed = collider.InitSeed
        local schedule = schedules[targetHash]
        if schedule and schedule.TargetInitSeed ~= targetSeed then
            schedule = nil
            schedules[targetHash] = nil
        end
        if schedule then
            if math.abs(schedule.Interval - interval) > Mizuki.RuntimeParameters.FrameComparisonEpsilon then
                local remaining = math.max(0, schedule.NextFrame - frame)
                schedule.NextFrame = frame
                    + remaining * interval / schedule.Interval
                schedule.Interval = interval
            end
            if frame + Mizuki.RuntimeParameters.FrameComparisonEpsilon < schedule.NextFrame then
                return true
            end
            repeat
                schedule.NextFrame = schedule.NextFrame + interval
            until schedule.NextFrame > frame
        else
            schedules[targetHash] = {
                TargetInitSeed = targetSeed,
                NextFrame = frame + interval,
                Interval = interval,
            }
        end

        collider:TakeDamage(
            player.Damage
                * Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER
                * (cannonData.MizukiContactDamageMultiplier or 1),
            0,
            EntityRef(cannon),
            0
        )
        -- The callback supplies the damage. Do not also run native damage or
        -- physical collision response.
        return true
    end

    function Mizuki.registerCannonControlCallbacks()
        Mizuki:AddCallback(
            ModCallbacks.MC_PRE_FAMILIAR_COLLISION,
            Mizuki.DamageOnCannonCollision,
            Mizuki.CannonVariant
        )
    end
end

-- Shared by every weapon: one pose deadline, one saved direction and one
-- engine-facing input hook. Weapon modules report real attacks; this controller
-- never creates shooting intent from its own virtual head-direction input.
function Mizuki.getReleaseProtectionDeadline(frame)
    return (frame or Game():GetFrameCount()) + Mizuki.WeaponParameters.CannonReleaseGraceFrames
end

function Mizuki.isReleaseProtected(deadline, frame)
    return deadline ~= nil and (frame or Game():GetFrameCount()) < deadline
end

-- One release window for pose and all charge controllers. Consumed attacks
-- clear immediately; an unspent charge pauses until resumed or timed out.
-- Each charge channel owns its timestamp, so simultaneous charges stay separate.
function Mizuki.protectChargeRelease(state, held, charge, consumed)
    local frame = Game():GetFrameCount()
    local deadline = state.ChargeReleaseHoldUntil
    if consumed or charge <= 0 then
        state.ChargeReleaseHoldUntil, state.ChargeReleaseFrame = nil, nil
        return 0, false, false
    end
    if deadline and (frame < state.ChargeReleaseFrame or not Mizuki.isReleaseProtected(deadline, frame)) then
        state.ChargeReleaseHoldUntil, state.ChargeReleaseFrame = nil, nil
        return 0, false, false
    end
    if held then
        state.ChargeReleaseHoldUntil, state.ChargeReleaseFrame = nil, nil
        return charge, deadline ~= nil, false
    end
    if not deadline then
        state.ChargeReleaseHoldUntil = Mizuki.getReleaseProtectionDeadline(frame)
        state.ChargeReleaseFrame = frame
    end
    return charge, false, true
end

function Mizuki.isAttackPoseHeld(data, frame)
    return data.MizukiCannonPoseHoldUntil ~= nil
        and (data.MizukiCannonPoseFrame == nil or (frame or Game():GetFrameCount()) >= data.MizukiCannonPoseFrame)
        and Mizuki.isReleaseProtected(data.MizukiCannonPoseHoldUntil, frame)
end

function Mizuki.getAttackPoseDirection(data, frame)
    if Mizuki.isAttackPoseHeld(data, frame) then return data.MizukiCannonPoseDirection end
end

function Mizuki.updateAttackPose(data, frame, anyCannonFiring, direction)
    if data.MizukiCannonPoseFrame and frame < data.MizukiCannonPoseFrame then
        data.MizukiCannonPoseHoldUntil, data.MizukiCannonPoseDirection = nil, nil
    end
    data.MizukiCannonPoseFrame = frame
    local bone = Mizuki.getBerserkSwingDirection(data)
    local sword = Mizuki.getSpiritSwordSwingDirection(data, true)
    local chargeWindow = data.ChargeReleaseHoldUntil
        or (data.MizukiBerserkInput and data.MizukiBerserkInput.ChargeReleaseHoldUntil)
        or (data.MizukiSpiritSwordInput and data.MizukiSpiritSwordInput.ChargeReleaseHoldUntil)
    -- Retained progress is not a fresh attack: otherwise the charge window
    -- would keep renewing the pose window, adding a second grace period.
    local active = data.MizukiHasShootingInput or anyCannonFiring
        or (not chargeWindow and ((data.MizukiCharge or 0) > 0 or bone ~= nil or sword ~= nil))
    if active then
        local aim = direction or sword or bone or data.MizukiCannonAim or data.MizukiAim
        if aim then data.MizukiCannonPoseDirection = Vector(aim.X, aim.Y) end
        data.MizukiCannonPoseHoldUntil = Mizuki.getReleaseProtectionDeadline(frame)
    elseif not Mizuki.isAttackPoseHeld(data, frame) then
        data.MizukiCannonPoseHoldUntil, data.MizukiCannonPoseDirection = nil, nil
    end
    return Mizuki.isAttackPoseHeld(data, frame)
end

function Mizuki.getAttackPoseHeadDirection(player)
    if not player or not Mizuki.isMizuki(player) or player:IsDead() then return end
    -- Tech 0 reports its actual release direction before the ordinary weapon
    -- update, avoiding the native head update's release-frame gap.
    local technologyZero = Mizuki.getTechnologyZeroHeadDirection
        and Mizuki.getTechnologyZeroHeadDirection(player)
    if technologyZero then return technologyZero end
    local data = player:GetData()
    local bone = Mizuki.getBerserkSwingDirection(data)
    local sword = Mizuki.getSpiritSwordSwingDirection(data, true)
    return sword or bone or Mizuki.getAttackPoseDirection(data)
end

function Mizuki.registerAttackPoseCallbacks()
    local actions = {
        [ButtonAction.ACTION_SHOOTLEFT] = true, [ButtonAction.ACTION_SHOOTRIGHT] = true,
        [ButtonAction.ACTION_SHOOTUP] = true, [ButtonAction.ACTION_SHOOTDOWN] = true,
    }
    local function holdHead(_, entity, hook, action)
        if not entity or not actions[action] then return end
        local player = entity:ToPlayer()
        if not player or not player:AreControlsEnabled() then return end
        local direction = Mizuki.getAttackPoseHeadDirection(player)
        if not direction then return end
        local chosen
        if math.abs(direction.X) > math.abs(direction.Y) then
            chosen = direction.X < 0 and ButtonAction.ACTION_SHOOTLEFT or ButtonAction.ACTION_SHOOTRIGHT
        else chosen = direction.Y < 0 and ButtonAction.ACTION_SHOOTUP or ButtonAction.ACTION_SHOOTDOWN end
        if hook == InputHook.IS_ACTION_PRESSED then return action == chosen end
        if hook == InputHook.GET_ACTION_VALUE then return action == chosen and 0.01 or 0 end
    end
    Mizuki:AddCallback(ModCallbacks.MC_INPUT_ACTION, holdHead, InputHook.IS_ACTION_PRESSED)
    Mizuki:AddCallback(ModCallbacks.MC_INPUT_ACTION, holdHead, InputHook.GET_ACTION_VALUE)
    local function clear()
        for index = 0, Game():GetNumPlayers() - 1 do
            local data = Isaac.GetPlayer(index):GetData()
            data.MizukiCannonPoseHoldUntil, data.MizukiCannonPoseDirection = nil, nil
            data.MizukiCannonPoseFrame = nil
            data.MizukiTechnologyZeroHeadLock = nil
        end
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clear)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clear)
end
