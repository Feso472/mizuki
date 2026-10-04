-- region Knife parameters
-- The real knife and its echo share the same distance-to-spin conversion.
Mizuki.KnifeParameters = { SpinDegreesPerPixel = 12 }
-- endregion Knife parameters

local MOMS_KNIFE = CollectibleType.COLLECTIBLE_MOMS_KNIFE
local KNIFE_LASER_ROOT_ANM2 = "gfx/1000.126_Tech Dot.anm2"
local knifeLaserRoots = {}
local KNIFE_STATE_FOLLOW = "follow"
local KNIFE_STATE_OUTBOUND = "outbound"
local KNIFE_STATE_RETURNING = "returning"
local KNIFE_VELOCITY_EPSILON = Mizuki.RuntimeParameters.VectorEpsilon
local KNIFE_DISTANCE_EPSILON = Mizuki.RuntimeParameters.DistanceEpsilon
local KNIFE_SPIN_DEGREES_PER_PIXEL = Mizuki.KnifeParameters.SpinDegreesPerPixel
local LUDOVICO_KNIFE_FOLLOW_OUTWARD_OFFSET = 20

local function sameEntity(entity, initSeed, ptrHash)
    return entity
        and entity:Exists()
        and entity.InitSeed == initSeed
        and GetPtrHash(entity) == ptrHash
end

local function getCannonBodyPosition(cannon)
    local data = cannon:GetData()
    local bobY = data.MizukiLudovicoOrbiting
        and 0
        or (data.MizukiBobOffsetY or 0)
    -- main.lua stores the pivot at the shared player/Ludovico scale before the
    -- cannon artwork applies its own 0.65 multiplier. Mom's Knife is full-size,
    -- so it consumes that shared pivot directly; no inverse scale is needed.
    local pivotRenderOffset = data.MizukiBasePivotRenderOffset
        or data.MizukiPivotRenderOffset
        or Vector.Zero
    return cannon.Position
        + pivotRenderOffset
        + (data.MizukiRenderWorldOffset or Vector.Zero)
        + Vector(0, bobY)
end

local function getCannonKnifeFollowOffset(cannon)
    local player = cannon.Player
    if not player or not player:Exists() then
        return Vector.Zero
    end

    local cannonData = cannon:GetData()
    -- Ordinary attacks carry this offset on the hidden cannon itself, so the
    -- knife and its laser have the same origin. Ludovico has a separate ring
    -- layout and keeps its existing knife-only tangent offset.
    if not cannonData.MizukiLudovicoOrbiting then
        return Vector.Zero
    end

    local aim = cannonData.MizukiCannonAim
    if not aim or aim:Length() <= KNIFE_VELOCITY_EPSILON then
        return Vector.Zero
    end

    local baseScale = cannonData.MizukiCannonBaseScale
        or player.SpriteScale
        or Vector.One
    return aim:Normalized():Resized(
        LUDOVICO_KNIFE_FOLLOW_OUTWARD_OFFSET * math.abs(baseScale.X)
    )
end

local function getCannonKnifeFollowPosition(cannon)
    return getCannonBodyPosition(cannon)
        + getCannonKnifeFollowOffset(cannon)
end

local function getCannonKnifeRotation(cannon)
    local data = cannon:GetData()
    if data.MizukiCannonBodyRotation ~= nil then
        -- The cannon sprite points up at rotation 0; Mom's Knife points right.
        return data.MizukiCannonBodyRotation - 90
    end
    local aim = data.MizukiCannonAim or Vector(0, -1)
    return aim:GetAngleDegrees()
end

local function setKnifeAtVisualPosition(knife, visualPosition)
    -- EntityKnife renders its artwork at Position + PositionOffset. Keep the
    -- requested point as the artwork position and leave the real collision at
    -- the knife's native offset below it, in both follow and attack states.
    knife.Position = visualPosition - knife.PositionOffset
end

local function captureCannonKnifeBaseScale(knife, knifeData)
    if knifeData.MizukiCannonKnifeBaseScale ~= nil then
        return
    end
    knifeData.MizukiCannonKnifeBaseScale = knife.Scale
    knifeData.MizukiCannonKnifeBaseSpriteScale = Vector(
        knife.SpriteScale.X,
        knife.SpriteScale.Y
    )
    knifeData.MizukiCannonKnifeBaseSize = knife.Size
end

local function applyCannonKnifeScale(knife, cannon)
    local knifeData = knife:GetData()
    captureCannonKnifeBaseScale(knife, knifeData)

    local cannonData = cannon:GetData()
    local multiplier = cannonData.MizukiCannonBaseScale
    if not multiplier then
        local player = cannon.Player
        local playerScale = player and player:Exists()
            and player.SpriteScale
            or Vector.One
        local ludovicoScale = cannonData.MizukiLudovicoOrbiting
            and (cannonData.MizukiLudovicoScaleMultiplier or 1)
            or 1
        multiplier = Vector(
            playerScale.X * ludovicoScale,
            playerScale.Y * ludovicoScale
        )
    end
    -- EntityKnife has a circular collision shape. Use the larger visual axis so
    -- a non-uniform player scale cannot leave visible blade area outside it.
    local collisionMultiplier = math.max(
        math.abs(multiplier.X),
        math.abs(multiplier.Y)
    )
    local baseSpriteScale = knifeData.MizukiCannonKnifeBaseSpriteScale
    knife.Scale = knifeData.MizukiCannonKnifeBaseScale * collisionMultiplier
    knife.SpriteScale = Vector(
        baseSpriteScale.X * multiplier.X,
        baseSpriteScale.Y * multiplier.Y
    )
    knife.Size = knifeData.MizukiCannonKnifeBaseSize * collisionMultiplier
end

local function clearCannonKnifeSpin(knife, knifeData)
    local baseOffset = knifeData.MizukiCannonKnifeSpriteRotationOffset
    if baseOffset ~= nil then
        knife.SpriteRotation = knife.Rotation + baseOffset
    end
    knifeData.MizukiCannonKnifeSpriteRotationOffset = nil
    knifeData.MizukiCannonKnifeSpinAngle = nil
end

local function applyCannonKnifeSpin(knife, knifeData, movedDistance)
    local baseOffset = knifeData.MizukiCannonKnifeSpriteRotationOffset
    if baseOffset == nil then
        -- Preserve the native knife art's current relationship to its attack
        -- direction instead of assuming a particular spritesheet orientation.
        baseOffset = knife.SpriteRotation - knife.Rotation
        knifeData.MizukiCannonKnifeSpriteRotationOffset = baseOffset
    end
    local spinAngle = (knifeData.MizukiCannonKnifeSpinAngle or 0)
        + math.abs(movedDistance) * KNIFE_SPIN_DEGREES_PER_PIXEL
    spinAngle = spinAngle % 360
    knifeData.MizukiCannonKnifeSpinAngle = spinAngle
    knife.SpriteRotation = knife.Rotation + baseOffset + spinAngle
end

local function applyCannonKnifeColor(knife, player)
    local playerData = player:GetData()
    local knifeData = knife:GetData()
    local revision = playerData.MizukiMomKnifeColorRevision or 0
    if knifeData.MizukiCannonKnifeColorRevision == revision then
        return
    end

    -- FireKnife copied Mizuki's already-colorized TearColor. Replace it with the
    -- colour captured immediately before that character-only layer was applied;
    -- this retains vanilla and other-mod item colours instead of forcing white.
    knife.Color = playerData.MizukiMomKnifeBaseColor or Color.Default
    knifeData.MizukiCannonKnifeColorRevision = revision
end

local function useManualCannonKnifeRender(knife)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true then
        return
    end

    -- EntityKnife chooses its own render Z relative to its parent, so the
    -- inherited entity depth fields cannot reliably put this cannon body above
    -- the player. Keep the real knife as the attack entity, but move only its
    -- draw into the owning cannon's manual body draw.
    --
    -- The engine's own draw is hidden with an alpha of 0 instead of Visible: an
    -- invisible entity is skipped by more than rendering - the debug collision
    -- display stops listing it and its contact pass is not reliable - while the
    -- zero alpha keeps the entity in every pass it needs and only removes the
    -- picture. The colour channels are kept so the item tint still shows in the
    -- manual draw.
    knifeData.MizukiCannonKnifeManualRender = true
    knife.Visible = true
    local color = knife.Color
    knifeData.MizukiCannonKnifeDrawColor = Color(
        color.R, color.G, color.B, 1,
        color.RO, color.GO, color.BO
    )
    local hiddenColor = Color(
        color.R, color.G, color.B, 0,
        color.RO, color.GO, color.BO
    )
    knife.Color = hiddenColor
    knife:GetSprite().Color = hiddenColor
end

local function getCannonKnife(cannon)
    local cannonData = cannon:GetData()
    local knife = cannonData.MizukiMomKnife
    if not knife or not knife:Exists() then
        cannonData.MizukiMomKnife = nil
        cannonData.MizukiMomKnifeInitSeed = nil
        return nil
    end

    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true
        or knife.InitSeed ~= cannonData.MizukiMomKnifeInitSeed
        or not sameEntity(
            knifeData.MizukiCannonKnifeCannon,
            knifeData.MizukiCannonKnifeCannonInitSeed,
            knifeData.MizukiCannonKnifeCannonPtrHash
        )
        or GetPtrHash(knifeData.MizukiCannonKnifeCannon)
            ~= GetPtrHash(cannon)
    then
        cannonData.MizukiMomKnife = nil
        cannonData.MizukiMomKnifeInitSeed = nil
        return nil
    end
    return knife
end

function Mizuki.getCannonMomKnifeShadowDisplacement(cannon)
    local knife = getCannonKnife(cannon)
    if not knife or not knife:IsFlying()
        or knife:GetData().MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
    then
        return Vector.Zero
    end
    -- Move only the native Familiar shadow. The cannon and its beam origin
    -- remain at their locked attack position while the knife travels.
    return knife.Position + knife.PositionOffset
        - getCannonKnifeFollowPosition(cannon)
end

local function getAuxiliaryCannonKnives(cannon)
    local cannonData = cannon:GetData()
    local knives = cannonData.MizukiAuxiliaryMomKnives
    if not knives then
        return {}
    end

    for index = #knives, 1, -1 do
        local knife = knives[index]
        local knifeData = knife and knife:Exists() and knife:GetData() or nil
        if not knifeData
            or knifeData.MizukiCannonKnife ~= true
            or knifeData.MizukiCannonKnifeAuxiliary ~= true
            or not sameEntity(
                knifeData.MizukiCannonKnifeCannon,
                knifeData.MizukiCannonKnifeCannonInitSeed,
                knifeData.MizukiCannonKnifeCannonPtrHash
            )
            or GetPtrHash(knifeData.MizukiCannonKnifeCannon)
                ~= GetPtrHash(cannon)
        then
            table.remove(knives, index)
        end
    end
    if #knives == 0 then
        cannonData.MizukiAuxiliaryMomKnives = nil
    end
    return knives
end

local function clearKnifeBeamLink(knifeData, beam)
    if not beam or knifeData.MizukiCannonKnifeBeam == beam then
        knifeData.MizukiCannonKnifeBeam = nil
    end
end

local function removeCannonKnife(cannon)
    local knife = getCannonKnife(cannon)
    if knife then
        local knifeData = knife:GetData()
        if knifeData.MizukiCannonKnife == true then
            knife:Remove()
        end
    end
    local cannonData = cannon:GetData()
    for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
        if auxiliaryKnife and auxiliaryKnife:Exists() then
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil
    cannonData.MizukiMomKnife = nil
    cannonData.MizukiMomKnifeInitSeed = nil
end

local function createCannonKnife(cannon, auxiliary)
    local player = cannon.Player
    if not player or not player:Exists() or not player:HasCollectible(MOMS_KNIFE) then
        return nil
    end

    local knife = player:FireKnife(cannon, 0, true, 0, 0)
    if not knife then
        return nil
    end
    knife = knife:ToKnife()
    if not knife then
        return nil
    end

    local cannonData = cannon:GetData()
    local knifeData = knife:GetData()
    knifeData.MizukiCannonKnife = true
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
    knifeData.MizukiCannonKnifeCannon = cannon
    knifeData.MizukiCannonKnifeCannonInitSeed = cannon.InitSeed
    knifeData.MizukiCannonKnifeCannonPtrHash = GetPtrHash(cannon)
    knifeData.MizukiCannonKnifeOwner = player
    knifeData.MizukiCannonKnifeOwnerInitSeed = player.InitSeed
    knifeData.MizukiCannonKnifeOwnerPtrHash = GetPtrHash(player)
    knifeData.MizukiCannonKnifeAuxiliary = auxiliary and true or nil
    if auxiliary then
        cannonData.MizukiAuxiliaryMomKnives =
            cannonData.MizukiAuxiliaryMomKnives or {}
        table.insert(cannonData.MizukiAuxiliaryMomKnives, knife)
    else
        cannonData.MizukiMomKnife = knife
        cannonData.MizukiMomKnifeInitSeed = knife.InitSeed
    end

    knife.Parent = cannon
    knife.SpawnerEntity = player
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, player)
    useManualCannonKnifeRender(knife)
    knife.Rotation = getCannonKnifeRotation(cannon)
    setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
    knife.Velocity = Vector.Zero
    return knife
end

local function ensureCannonKnife(cannon)
    local player = cannon.Player
    if not player or not player:Exists() or not player:HasCollectible(MOMS_KNIFE) then
        removeCannonKnife(cannon)
        return nil
    end
    return getCannonKnife(cannon) or createCannonKnife(cannon)
end

local function validateKnifeOwnership(knife, knifeData)
    if knifeData.MizukiCannonKnife ~= true then
        return nil, nil
    end
    local cannon = knifeData.MizukiCannonKnifeCannon
    local player = knifeData.MizukiCannonKnifeOwner
    if not sameEntity(
        cannon,
        knifeData.MizukiCannonKnifeCannonInitSeed,
        knifeData.MizukiCannonKnifeCannonPtrHash
    ) or not sameEntity(
        player,
        knifeData.MizukiCannonKnifeOwnerInitSeed,
        knifeData.MizukiCannonKnifeOwnerPtrHash
    ) or not cannon.Player
        or GetPtrHash(cannon.Player) ~= GetPtrHash(player)
        or not player:HasCollectible(MOMS_KNIFE)
    then
        return nil, nil
    end
    return cannon, player
end

local function getLaserPath(laser)
    local positionOffset = laser.PositionOffset or Vector.Zero
    local path = { laser.Position + positionOffset }
    local totalLength = 0
    local samples = laser:GetSamples()
    for index = 0, #samples - 1 do
        local sample = samples:Get(index)
        local position = Vector(sample.X, sample.Y) + positionOffset
        local previous = path[#path]
        local segmentLength = (position - previous):Length()
        if segmentLength > KNIFE_VELOCITY_EPSILON then
            totalLength = totalLength + segmentLength
            path[#path + 1] = position
        end
    end
    return path, totalLength
end

local function getLaserEndpointTransform(laser, distance, fallbackDirection)
    local path, pathLength = getLaserPath(laser)
    if #path == 1 or pathLength <= KNIFE_VELOCITY_EPSILON then
        local direction = fallbackDirection or Vector(1, 0)
        return path[1] + direction:Resized(math.max(0, distance)), direction
    end

    local finalSegment = path[#path] - path[#path - 1]
    local finalDirection = finalSegment:Normalized()
    return path[#path], finalDirection
end

local function setKnifeDrivenLaserDistance(beam, distance)
    local laser = beam and beam.Laser
    if not laser or not laser:Exists() then
        return
    end
    laser:SetMaxDistance(math.max(1, distance))
end

local function createCannonKnifeLaserRoot(beam)
    local laser = beam.Laser
    local sprite = Sprite()
    sprite:Load(KNIFE_LASER_ROOT_ANM2, true)
    sprite:Play("Idle", true)
    table.insert(knifeLaserRoots, {
        CannonInitSeed = beam.Cannon.InitSeed,
        CannonPtrHash = GetPtrHash(beam.Cannon),
        Laser = laser,
        LaserInitSeed = laser.InitSeed,
        LaserPtrHash = GetPtrHash(laser),
        Sprite = sprite,
        Position = laser.Position + laser.PositionOffset,
        LastFrame = Game():GetFrameCount(),
    })
end

local function beamOwnsKnife(beam)
    local knife = beam and beam.MomKnife
    if not knife or not knife:Exists()
        or knife.InitSeed ~= beam.MomKnifeInitSeed
    then
        return nil
    end
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true
        or knifeData.MizukiCannonKnifeBeam ~= beam
    then
        return nil
    end
    return knife, knifeData
end

local function getKnifeMotionSource(knife, knifeData)
    if knifeData.MizukiCannonKnifeAuxiliary ~= true then
        return knife
    end
    local source = knifeData.MizukiCannonKnifeMotionSource
    if sameEntity(
        source,
        knifeData.MizukiCannonKnifeMotionSourceInitSeed,
        knifeData.MizukiCannonKnifeMotionSourcePtrHash
    ) then
        return source
    end
    return nil
end

function Mizuki.updateCannonMomKnife(cannon)
    local knife = ensureCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, cannon.Player)
    useManualCannonKnifeRender(knife)
    if knifeData.MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
        or not knife:IsFlying()
    then
        knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
        clearKnifeBeamLink(knifeData)
        knife.Rotation = getCannonKnifeRotation(cannon)
        setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
        -- Position is fully owned by Lua. A non-zero world Velocity would make
        -- the engine advance the knife once more between these hard placements.
        knife.Velocity = Vector.Zero
    end
end

function Mizuki.fireCannonMomKnife(cannon, beam, charge, baseChargeFrames)
    local laser = beam.Laser
    if not laser or not laser:Exists() then
        return false
    end

    local motionSource = ensureCannonKnife(cannon)
    local knife = motionSource
    local auxiliary = knife and (knife:IsFlying()
        or knife:GetData().MizukiCannonKnifeBeam ~= nil)
    if auxiliary then
        -- The first laser uses the cannon's persistent body. Every additional
        -- laser gets a temporary knife of its own so native multi-shot layouts
        -- and their already-resolved angles remain the single source of truth.
        knife = createCannonKnife(cannon, true)
    end
    if not knife then
        return false
    end

    local knifeData = knife:GetData()
    if auxiliary then
        knifeData.MizukiCannonKnifeMotionSource = motionSource
        knifeData.MizukiCannonKnifeMotionSourceInitSeed = motionSource.InitSeed
        knifeData.MizukiCannonKnifeMotionSourcePtrHash = GetPtrHash(motionSource)
    end
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_OUTBOUND
    knifeData.MizukiCannonKnifeBeam = beam
    knifeData.MizukiCannonKnifePreviousDistance = 0
    clearCannonKnifeSpin(knife, knifeData)
    knife.Rotation = beam.Direction:GetAngleDegrees()
    setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
    applyCannonKnifeScale(knife, cannon)
    -- The persistent body has existed throughout charging, while auxiliary
    -- knives are born only on release. Give every native entity the same charge
    -- parameters; auxiliary visual timing is synchronized to the persistent
    -- knife separately in UpdateCannonMomKnifeEntity.
    local shotCharge = math.max(
        0,
        math.min(charge / math.max(1, baseChargeFrames), 1)
    )
    knife.Charge = shotCharge
    knifeData.MizukiCannonKnifeShotCharge = shotCharge
    knife:Shoot(shotCharge, beam.Distance)
    applyCannonKnifeScale(knife, cannon)
    knife.Velocity = Vector.Zero
    setKnifeDrivenLaserDistance(beam, 1)

    beam.MomKnifeDriven = true
    beam.MomKnife = knife
    beam.MomKnifeInitSeed = knife.InitSeed
    beam.MomKnifeReturnStarted = false
    createCannonKnifeLaserRoot(beam)
    return true
end

function Mizuki.shouldHoldCannonKnifeBeam(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    local motionSource = knife and getKnifeMotionSource(knife, knifeData)
    return knife ~= nil
        and motionSource ~= nil
        and knifeData.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW
        and motionSource:IsFlying()
end

function Mizuki.isCannonKnifeAttackActive(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    local motionSource = knife and getKnifeMotionSource(knife, knifeData)
    return knife ~= nil
        and motionSource ~= nil
        and knifeData.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW
        and motionSource:IsFlying()
end

function Mizuki.cancelCannonKnifeBeam(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    if not knife then
        return
    end
    beam.MomKnifeReturnStarted = true
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_RETURNING
    clearKnifeBeamLink(knifeData, beam)
    knife:Reset()
    local cannon = knifeData.MizukiCannonKnifeCannon
    if cannon and cannon:Exists() then
        applyCannonKnifeScale(knife, cannon)
    end
end

function Mizuki.removeCannonMomKnife(cannon)
    removeCannonKnife(cannon)
end

function Mizuki.resetCannonMomKnife(cannon)
    local cannonData = cannon:GetData()
    for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
        if auxiliaryKnife and auxiliaryKnife:Exists() then
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil

    local knife = getCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    clearKnifeBeamLink(knifeData)
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
    knife:Reset()
    applyCannonKnifeScale(knife, cannon)
    knife.Rotation = getCannonKnifeRotation(cannon)
    setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
    clearCannonKnifeSpin(knife, knifeData)
    knife.Velocity = Vector.Zero
end

function Mizuki.cannonUsesMomKnifeBody(cannon)
    return getCannonKnife(cannon) ~= nil
end

function Mizuki.getCannonMomKnifeBodyPosition(cannon)
    if not getCannonKnife(cannon) then
        return nil
    end
    return getCannonKnifeFollowPosition(cannon)
end

function Mizuki.getCannonMomKnifeFollowOffset(cannon)
    if not getCannonKnife(cannon) then
        return Vector.Zero
    end
    return getCannonKnifeFollowOffset(cannon)
end

function Mizuki:UpdateCannonMomKnifeEntity(knife)
    local knifeData = knife:GetData()
    local cannon = validateKnifeOwnership(knife, knifeData)
    if not cannon then
        if knifeData.MizukiCannonKnife == true then
            knife:Remove()
        end
        return
    end
    useManualCannonKnifeRender(knife)
    applyCannonKnifeScale(knife, cannon)

    local state = knifeData.MizukiCannonKnifeState or KNIFE_STATE_FOLLOW
    local motionSource = getKnifeMotionSource(knife, knifeData)
    local motionSourceFlying = motionSource and motionSource:IsFlying()
    if knifeData.MizukiCannonKnifeAuxiliary == true
        and motionSourceFlying
        and not knife:IsFlying()
    then
        -- A freshly-created auxiliary knife may finish its own native cycle
        -- sooner than the persistent knife. Keep its native collision active;
        -- its visible distance and return state are driven by the persistent
        -- knife below.
        local beam = knifeData.MizukiCannonKnifeBeam
        local shotCharge = knifeData.MizukiCannonKnifeShotCharge or 1
        knife.Charge = shotCharge
        knife:Shoot(shotCharge, beam and beam.Distance or 1)
        applyCannonKnifeScale(knife, cannon)
    end
    if state == KNIFE_STATE_FOLLOW or not motionSourceFlying then
        local beam = knifeData.MizukiCannonKnifeBeam
        if beam then
            beam.MomKnifeReturnStarted = true
        end
        clearKnifeBeamLink(knifeData)
        if knifeData.MizukiCannonKnifeAuxiliary == true then
            knife:Remove()
            return
        end
        knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
        knifeData.MizukiCannonKnifePreviousDistance = nil
        knife.Rotation = getCannonKnifeRotation(cannon)
        setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
        clearCannonKnifeSpin(knife, knifeData)
        knife.Velocity = Vector.Zero
        Mizuki.refreshCannonMomKnifeShadow(cannon)
        return
    end

    local beam = knifeData.MizukiCannonKnifeBeam
    local laser = beam and beam.Laser
    local distance = math.max(0, motionSource:GetKnifeDistance())
    local previousDistance = knifeData.MizukiCannonKnifePreviousDistance
    local knifeVelocity = motionSource:GetKnifeVelocity()

    if state == KNIFE_STATE_OUTBOUND then
        local returning = knifeVelocity < -KNIFE_VELOCITY_EPSILON
            or (previousDistance ~= nil
                and distance < previousDistance - KNIFE_DISTANCE_EPSILON)
        local mappedPosition
        local mappedDirection
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, distance)
            mappedPosition, mappedDirection = getLaserEndpointTransform(
                laser,
                distance,
                beam.Direction
            )
        else
            mappedDirection = beam and beam.Direction or Vector.FromAngle(knife.Rotation)
            mappedPosition = getCannonBodyPosition(cannon)
                + mappedDirection:Resized(distance)
        end

        if returning then
            state = KNIFE_STATE_RETURNING
            knifeData.MizukiCannonKnifeState = state
            if beam then
                beam.MomKnifeReturnStarted = true
            end
        else
            knife.Rotation = mappedDirection:GetAngleDegrees()
            setKnifeAtVisualPosition(knife, mappedPosition)
            knife.Velocity = Vector.Zero
            applyCannonKnifeSpin(
                knife,
                knifeData,
                distance - (previousDistance or distance)
            )
        end
    end

    if state == KNIFE_STATE_RETURNING then
        local targetPosition = getCannonBodyPosition(cannon)
        local returnPosition
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, distance)
            returnPosition = getLaserEndpointTransform(
                laser,
                distance,
                beam.Direction
            )
        else
            local returnDirection = beam and beam.Direction
                or Vector.FromAngle(knife.Rotation)
            returnPosition = targetPosition + returnDirection:Resized(distance)
        end
        local returnDirection = targetPosition - returnPosition
        if returnDirection:Length() > KNIFE_VELOCITY_EPSILON then
            knife.Rotation = returnDirection:GetAngleDegrees()
        end
        setKnifeAtVisualPosition(knife, returnPosition)
        knife.Velocity = Vector.Zero
        applyCannonKnifeSpin(
            knife,
            knifeData,
            distance - (previousDistance or distance)
        )
    end

    knifeData.MizukiCannonKnifePreviousDistance = distance
    if knifeData.MizukiCannonKnifeAuxiliary ~= true then
        Mizuki.refreshCannonMomKnifeShadow(cannon)
    end
end

local function renderCannonKnifeLaserRoots(cannon, renderOffset)
    local game = Game()
    local room = game:GetRoom()
    local renderMode = room:GetRenderMode()
    if renderMode == RenderMode.RENDER_WATER_REFLECT
        or renderMode == RenderMode.RENDER_WATER_REFRACT
    then
        return
    end

    local frame = game:GetFrameCount()
    local cannonPtrHash = GetPtrHash(cannon)
    for index = #knifeLaserRoots, 1, -1 do
        local root = knifeLaserRoots[index]
        if root.CannonInitSeed == cannon.InitSeed
            and root.CannonPtrHash == cannonPtrHash
        then
            local sprite = root.Sprite
            if not game:IsPaused() and root.LastFrame ~= frame then
                sprite:Update()
                root.LastFrame = frame
            end
            local laser = root.Laser
            if sameEntity(laser, root.LaserInitSeed, root.LaserPtrHash) then
                root.Position = laser.Position + laser.PositionOffset
                -- Preserve the laser's complete colour, including colorize.
                sprite.Color = laser.Color
            elseif not root.Ending then
                root.Ending = true
                root.Laser = nil
                sprite:Play("Disappear", true)
            end

            if root.Ending and sprite:IsFinished("Disappear") then
                table.remove(knifeLaserRoots, index)
            else
                local screenPosition = Isaac.WorldToScreen(root.Position)
                    + (renderOffset or Vector.Zero)
                    - room:GetRenderScrollOffset()
                    - game.ScreenShakeOffset
                -- Layer 1 is the Tech Dot's downward pointer. Draw only the
                -- glow, in this Familiar slot before either knife draw path.
                sprite:RenderLayer(0, screenPosition)
            end
        end
    end
end

-- Draw the knife through its sprite rather than through Entity:Render. The entity
-- path applies the engine's parent-relative Z rules - the same rules that let a
-- beam sort above a following child - while the cannon body is a plain sprite draw
-- inside the Familiar's own slot. Going through the sprite puts both bodies on one
-- path, so their layering matches by construction. The entity itself is untouched:
-- it stays alive, keeps its collision and its updates, and stays hidden behind the
-- alpha-0 colour.
local function drawKnifeSprite(
    knife,
    renderOffset,
    worldPosition,
    cancelWaterMirror,
    finalRoomDraw
)
    local knifeData = knife:GetData()
    local sprite = knife:GetSprite()
    local originalRotation = sprite.Rotation
    local originalScale = Vector(sprite.Scale.X, sprite.Scale.Y)
    local originalOffset = Vector(sprite.Offset.X, sprite.Offset.Y)
    local originalFlipX = sprite.FlipX
    local originalFlipY = sprite.FlipY

    sprite.Rotation = knife.SpriteRotation
    sprite.Scale = Vector(knife.SpriteScale.X, knife.SpriteScale.Y)
    sprite.Offset = Vector.Zero
    sprite.Color = knifeData.MizukiCannonKnifeDrawColor or Color.Default
    local cannon = knifeData.MizukiCannonKnifeCannon
    if cannon and cannon:Exists() and cannon:GetData().MizukiPersistentEchoMode then
        sprite.Color = Mizuki.getPersistentEchoColor(sprite.Color)
    end
    if cancelWaterMirror then
        sprite.FlipY = not sprite.FlipY
    end
    local screenPosition = Isaac.WorldToScreen(worldPosition)
    if not finalRoomDraw then
        local game = Game()
        screenPosition = screenPosition
            + (renderOffset or Vector.Zero)
            - game:GetRoom():GetRenderScrollOffset()
            - game.ScreenShakeOffset
    end
    sprite:Render(screenPosition, Vector.Zero, Vector.Zero)

    sprite.Rotation = originalRotation
    sprite.Scale = originalScale
    sprite.Offset = originalOffset
    local drawColor = knifeData.MizukiCannonKnifeDrawColor or Color.Default
    sprite.Color = Color(
        drawColor.R, drawColor.G, drawColor.B, 0,
        drawColor.RO, drawColor.GO, drawColor.BO
    )
    sprite.FlipX = originalFlipX
    sprite.FlipY = originalFlipY
end

local function renderCannonKnifeEntity(
    knife,
    cannon,
    renderOffset,
    reflectedBodyPosition,
    cancelWaterMirror,
    finalRoomDraw
)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true
        or knifeData.MizukiCannonKnifeManualRender ~= true
    then
        return false
    end

    local worldPosition = knife.Position + knife.PositionOffset
    if reflectedBodyPosition then
        -- main.lua supplies the final full-size knife anchor on the reflected
        -- plane. Translate the live knife by the difference between that anchor
        -- and its normal cannon anchor; collision stays at the real position.
        worldPosition = worldPosition
            + (reflectedBodyPosition - getCannonBodyPosition(cannon))
    end

    drawKnifeSprite(
        knife,
        renderOffset,
        worldPosition,
        cancelWaterMirror,
        finalRoomDraw
    )
    return true
end

-- Both render callbacks use the same eligibility check. Losing the live beam
-- immediately restores the familiar draw; water keeps its existing anchor path.
local function getKnifeRenderLaser(knife)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnifeManualRender ~= true
        or knifeData.MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
    then
        return nil
    end
    local beam = knifeData.MizukiCannonKnifeBeam
    local ownedKnife = beamOwnsKnife(beam)
    if not ownedKnife or GetPtrHash(ownedKnife) ~= GetPtrHash(knife) then
        return nil
    end
    local laser = beam.Laser
    if not laser or not laser:Exists() then
        return nil
    end
    if not validateKnifeOwnership(knife, knifeData) then return nil end
    return laser
end

function Mizuki.renderCannonMomKnifeBody(
    cannon,
    renderOffset,
    reflectedBodyPosition,
    cancelWaterMirror
)
    local knife = getCannonKnife(cannon)
    if not knife then
        return false
    end
    renderCannonKnifeLaserRoots(cannon, renderOffset)
    if not reflectedBodyPosition and getKnifeRenderLaser(knife) then
        -- The body is supplied by the laser callback. Returning true also keeps
        -- main.lua from drawing the ordinary cannon artwork in this slot.
        return true
    end
    renderCannonKnifeEntity(
        knife,
        cannon,
        renderOffset,
        reflectedBodyPosition,
        cancelWaterMirror,
        false
    )
    if reflectedBodyPosition then
        for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
            renderCannonKnifeEntity(
                auxiliaryKnife,
                cannon,
                renderOffset,
                reflectedBodyPosition,
                cancelWaterMirror,
                false
            )
        end
    end
    return true
end

function Mizuki:RenderFlyingMomKnives()
    local game = Game()
    if game:GetFrameCount() <= 0 then return end

    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(playerIndex)
        local cannons = player:GetData().MizukiCannons
        if cannons then
            for side = 1, 2 do
                for _, cannon in ipairs(cannons[side] or {}) do
                    if cannon and cannon:Exists() then
                        local knife = getCannonKnife(cannon)
                        if knife and getKnifeRenderLaser(knife) then
                            renderCannonKnifeEntity(
                                knife,
                                cannon,
                                Vector.Zero,
                                nil,
                                false,
                                true
                            )
                        end
                        for _, auxiliaryKnife in ipairs(
                            getAuxiliaryCannonKnives(cannon)
                        ) do
                            if getKnifeRenderLaser(auxiliaryKnife) then
                                renderCannonKnifeEntity(
                                    auxiliaryKnife,
                                    cannon,
                                    Vector.Zero,
                                    nil,
                                    false,
                                    true
                                )
                            end
                        end
                    end
                end
            end
        end
    end
end

function Mizuki:ClearCannonKnifeLaserRoots()
    knifeLaserRoots = {}
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_NEW_ROOM,
    Mizuki.ClearCannonKnifeLaserRoots
)

Mizuki:AddCallback(
    ModCallbacks.MC_POST_RENDER,
    Mizuki.RenderFlyingMomKnives
)

Mizuki:AddCallback(
    ModCallbacks.MC_POST_KNIFE_UPDATE,
    Mizuki.UpdateCannonMomKnifeEntity
)
