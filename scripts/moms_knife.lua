-- region Knife parameters
-- The real knife and its echo share the same distance-to-spin conversion.
Mizuki.KnifeParameters = { SpinDegreesPerPixel = 12 }
-- endregion Knife parameters

local MOMS_KNIFE = CollectibleType.COLLECTIBLE_MOMS_KNIFE
local KNIFE_LASER_ROOT_ANM2 = "gfx/1000.126_Tech Dot.anm2"
local knifeLaserRoots = {}
local getKnifeMotionSource
local KNIFE_STATE_FOLLOW = "follow"
local KNIFE_STATE_OUTBOUND = "outbound"
local KNIFE_STATE_RETURNING = "returning"
local KNIFE_VELOCITY_EPSILON = Mizuki.RuntimeParameters.VectorEpsilon
local KNIFE_DISTANCE_EPSILON = Mizuki.RuntimeParameters.DistanceEpsilon
local KNIFE_SPIN_DEGREES_PER_PIXEL = Mizuki.KnifeParameters.SpinDegreesPerPixel
local LUDOVICO_KNIFE_FOLLOW_OUTWARD_OFFSET = 20

local function hasCannonKnifeTinyPlanet(knife, cannon, motionSource)
    local source = motionSource or knife
    local player = cannon and cannon.Player
    -- Our injected flag must not keep enabling the item after it is removed.
    if player then
        return player:HasCollectible(CollectibleType.COLLECTIBLE_TINY_PLANET)
    end
    return (source.TearFlags & TearFlags.TEAR_ORBIT) ~= TearFlags.TEAR_NORMAL
end

local function sameEntity(entity, initSeed, ptrHash)
    return entity
        and entity:Exists()
        and entity.InitSeed == initSeed
        and GetPtrHash(entity) == ptrHash
end

function Mizuki.getCannonKnifeBodyPivot(cannon)
    local data = cannon:GetData()
    return data.MizukiBasePivotRenderOffset or data.MizukiPivotRenderOffset or Vector.Zero
end

local function getCannonBodyPosition(cannon)
    local data = cannon:GetData()
    local bobY = data.MizukiLudovicoOrbiting
        and 0
        or (data.MizukiBobOffsetY or 0)
    -- Layout supplies the weapon's pivot at the shared character scale.
    local pivotRenderOffset = Mizuki.getCannonKnifeBodyPivot(cannon)
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
    local sizeMulti = knife.SizeMulti or Vector.One
    knifeData.MizukiCannonKnifeBaseSizeMulti = Vector(sizeMulti.X, sizeMulti.Y)
end

local function applyCannonKnifeScale(knife, cannon, motionSource)
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
    -- Use the larger character axis for the knife's collision scale. Tiny
    -- Planet then supplies native capsule axes independently of its artwork.
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
    local orbitCollisionMultiplier = 1
    local collisionAxes
    if hasCannonKnifeTinyPlanet(knife, cannon, motionSource) then
        local source = motionSource or getKnifeMotionSource(knife, knifeData)
        if source then
            -- Native Tiny Planet capsule (0x9629ED-0x962A80): both normalized
            -- axes are required; enlarging Size alone does not define it.
            local motion = math.max(0, source:GetKnifeDistance())
                * math.abs(source:GetKnifeVelocity())
            local shortAxis, longAxis = 1 + 0.0002 * motion, 1 + 0.0014 * motion
            orbitCollisionMultiplier = math.max(shortAxis, longAxis)
            collisionAxes = Vector(shortAxis / orbitCollisionMultiplier,
                longAxis / orbitCollisionMultiplier)
            knifeData.MizukiCannonKnifeOrbitCollision = true
        end
    elseif knifeData.MizukiCannonKnifeOrbitCollision then
        local baseMulti = knifeData.MizukiCannonKnifeBaseSizeMulti or Vector.One
        collisionAxes = Vector(baseMulti.X, baseMulti.Y)
        knifeData.MizukiCannonKnifeOrbitCollision = nil
    end
    knife.Size = knifeData.MizukiCannonKnifeBaseSize * collisionMultiplier
        * orbitCollisionMultiplier
    -- The native Size setter resets SizeMulti. Set the capsule axes last;
    -- the actual update trace showed our previous order restoring (1, 1).
    if collisionAxes then knife.SizeMulti = collisionAxes end
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
    knifeData.MizukiCannonKnifeDrawColor = Color.Lerp(color, color, 0)
    knifeData.MizukiCannonKnifeDrawColor.A = 1
    local hiddenColor = Color.Lerp(color, color, 0)
    hiddenColor.A = 0
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
            if knifeData.MizukiBerserkClub and Mizuki.cancelBerserkClubSwing then
                Mizuki.cancelBerserkClubSwing(knife)
            end
            clearKnifeBeamLink(knifeData)
            knife:Remove()
        end
    end
    local cannonData = cannon:GetData()
    for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
        if auxiliaryKnife and auxiliaryKnife:Exists() then
            clearKnifeBeamLink(auxiliaryKnife:GetData())
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil
    cannonData.MizukiMomKnife = nil
    cannonData.MizukiMomKnifeInitSeed = nil
end

-- The native body/scale/color setup is shared; callers assign their own explicit
-- identities and ownership. Creating an echo must never register a real knife.
function Mizuki.createCannonKnifeBody(cannon, position, rotation, weaponVariant, berserk)
    local player = cannon.Player
    if not player or not player:Exists() then return nil end
    local variant = weaponVariant or Mizuki.getCannonKnifeWeaponVariant(player)
    local knife = player:FireKnife(cannon, 0, true, 0, variant)
    if not knife then return nil end
    knife = knife:ToKnife()
    if not knife then return nil end
    knife.Parent = cannon
    knife.SpawnerEntity = player
    if berserk == nil then berserk = Mizuki.isBerserkClubActive(player) end
    knife:GetData().MizukiBerserkClub = berserk == true
    knife:GetData().MizukiKnifeBaseEntityCollisionClass = knife.EntityCollisionClass
    knife:GetData().MizukiCannonKnifeBaseGridCollisionClass = knife.GridCollisionClass
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, player)
    knife.Rotation = rotation
    setKnifeAtVisualPosition(knife, position)
    knife.Velocity = Vector.Zero
    return knife
end

Mizuki.updateCannonKnifeScale = applyCannonKnifeScale

local function createCannonKnife(cannon, auxiliary)
    local player = cannon.Player
    if not player or not player:Exists() or not Mizuki.cannonUsesKnifeWeapon(player)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        return nil
    end
    local knife = Mizuki.createCannonKnifeBody(cannon,
        getCannonKnifeFollowPosition(cannon), getCannonKnifeRotation(cannon))
    if not knife then return nil end
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

    useManualCannonKnifeRender(knife)
    Mizuki.connectPersistentEchoAttack(player, cannon, knife, 0, "knife")
    return knife
end

local function ensureCannonKnife(cannon)
    local player = cannon.Player
    if not player or not player:Exists() or not Mizuki.cannonUsesKnifeWeapon(player)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        removeCannonKnife(cannon)
        return nil
    end
    local knife = getCannonKnife(cannon)
    if knife and (knife.Variant ~= Mizuki.getCannonKnifeWeaponVariant(player)
        or (knife:GetData().MizukiBerserkClub == true) ~= Mizuki.isBerserkClubActive(player)) then
        removeCannonKnife(cannon)
        knife = nil
    end
    return knife or createCannonKnife(cannon)
end

Mizuki.ensureCannonKnife = ensureCannonKnife
Mizuki.getCannonKnifeAnchor = getCannonKnifeFollowPosition

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
        or not Mizuki.cannonUsesKnifeWeapon(player)
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
Mizuki.getCannonKnifeLaserPath = getLaserPath

local function getKnifeOrbitOffset(source)
    local offset = (source.RotationOffset or 0) % 360
    return offset > 180 and offset - 360 or offset
end

-- Native ordinary knife (variant/subtype 0): 0x961C09-0x961C2F,
-- 0x962952-0x96298A. Flight distance is the clock, not the orbit radius.
local function getKnifeOrbitRadius(source, distance)
    return 30 + math.max(0, distance) * 0.25 * (1 - getKnifeOrbitOffset(source) * 0.02)
end

function Mizuki.getCannonKnifeBeamAngle(beam, motionSource, distanceOverride)
    local angle = beam.Direction:GetAngleDegrees()
    local knife = beam.MomKnife
    if not knife or not knife:Exists() or knife.InitSeed ~= beam.MomKnifeInitSeed then
        return angle
    end
    local source = motionSource or getKnifeMotionSource(knife, knife:GetData())
    if not source or not source:IsFlying()
        or not hasCannonKnifeTinyPlanet(knife, beam.Cannon, source) then
        return angle
    end
    -- Native Tiny Planet knife position uses this distance-based orbit angle
    -- (isaac-ng.exe 0x9628F2-0x96293A). Apply it to the whole laser instead;
    -- the knife still advances along that laser's native, shortened path.
    local rotationOffset = getKnifeOrbitOffset(source)
    return angle + math.max(0, distanceOverride or source:GetKnifeDistance()) * 2 * math.pi
        * (1 + rotationOffset * 0.002)
end

local function getLaserEndpointTransform(laser, distance, fallbackDirection, continuePastEndpoint)
    local path, pathLength = getLaserPath(laser)
    if #path == 1 or pathLength <= KNIFE_VELOCITY_EPSILON then
        local direction = fallbackDirection or Vector(1, 0)
        if continuePastEndpoint and laser.AngleDegrees then
            direction = Vector.FromAngle(laser.AngleDegrees)
        end
        return path[1] + direction:Resized(math.max(0, distance)), direction
    end

    local finalSegment = path[#path] - path[#path - 1]
    local finalDirection = finalSegment:Normalized()
    local position = path[#path]
    if continuePastEndpoint then
        -- EndPoint is the native ray endpoint before the homing/curved path.
        -- Keep all native samples, then continue the knife along the final
        -- tangent by the ray distance lost to clipping. Do not rewrite the
        -- laser's samples, graphics, flags, or damage path.
        local endpoint = laser.EndPoint or (position - laser.PositionOffset)
        local clippedDistance = (endpoint - laser.Position):Length()
        position = position + finalDirection * math.max(0, distance - clippedDistance)
    end
    return position, finalDirection
end

local function getKnifeOrbitRotation(beam, source, position, pathDirection)
    local origin = beam.Laser.Position + beam.Laser.PositionOffset
    local distance = math.max(0, source:GetKnifeDistance())
    local angularRate = math.rad(Mizuki.getCannonKnifeBeamAngle(beam, source, distance + 1)
        - Mizuki.getCannonKnifeBeamAngle(beam, source, distance))
    -- dP/dd = radial rate * path tangent + angular rate * perpendicular radius.
    -- A line between last/current positions is a chord, and repeated endpoint
    -- corrections can give it a completely different direction from the orbit.
    local radialRate = 0.25 * (1 - getKnifeOrbitOffset(source) * 0.02)
    local tangent = pathDirection * radialRate + (position - origin):Rotated(90) * angularRate
    if source:GetKnifeVelocity() < 0 then tangent = tangent * -1 end
    return tangent:GetAngleDegrees() - 90
end

-- The knife callback prepares the laser's angle/range before native sampling.
-- Finish its placement again after that sampling, without advancing flight,
-- changing the state machine, or accumulating another spin increment.
function Mizuki.syncCannonKnifeFlightEndpoint(knife, motionSource, beam)
    local laser = beam and beam.Laser
    if not knife or not knife:Exists() or not motionSource or not motionSource:Exists()
        or not motionSource:IsFlying() or not laser or not laser:Exists() then return end
    local tinyPlanet = hasCannonKnifeTinyPlanet(knife, beam.Cannon, motionSource)
    local distance = math.max(0, motionSource:GetKnifeDistance())
    if tinyPlanet then distance = getKnifeOrbitRadius(motionSource, distance) end
    local position, direction = getLaserEndpointTransform(laser,
        distance, beam.Direction, tinyPlanet)
    setKnifeAtVisualPosition(knife, position)
    knife.Velocity = Vector.Zero
    if tinyPlanet then
        knife.SpriteRotation = getKnifeOrbitRotation(beam, motionSource, position, direction)
        if beam.Cannon then applyCannonKnifeScale(knife, beam.Cannon, motionSource) end
    end
end

local function setKnifeDrivenLaserDistance(beam, distance)
    local laser = beam and beam.Laser
    if not laser or not laser:Exists() then
        return
    end
    laser:SetMaxDistance(math.max(1, distance))
end

local function createCannonKnifeLaserRoot(beam)
    local cannon = beam and beam.Cannon
    local player = cannon and cannon.Player
    -- Match fireMizukiWeaponBeam's source choice. Brimstone already supplies
    -- its own firing effect; this extra Tech Dot belongs only to the tech beam.
    if not player or not player:Exists()
        or player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        return
    end
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
Mizuki.createCannonKnifeLaserRoot = createCannonKnifeLaserRoot

function Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
    if hasCannonKnifeTinyPlanet(knife, cannon) then
        knife.TearFlags = knife.TearFlags | TearFlags.TEAR_ORBIT
    elseif cannon and cannon.Player then
        knife.TearFlags = knife.TearFlags & ~TearFlags.TEAR_ORBIT
    end
    local range = beam and beam.Distance or 1
    -- Zero is a laser-only "unlimited" sentinel, not a knife launch range.
    -- Pass the owner's existing native stat unchanged: no beam-range formula,
    -- extra multiplier, minimum, or maximum is applied to the knife.
    if range == 0 then range = cannon.Player.TearRange end
    knife.Charge = shotCharge
    knife:Shoot(shotCharge, range)
end

function Mizuki.launchCannonKnife(knife, cannon, beam, shotCharge, position)
    if knife:GetData().MizukiBerserkClub then
        knife.EntityCollisionClass = knife:GetData().MizukiKnifeBaseEntityCollisionClass
            or EntityCollisionClass.ENTCOLL_ENEMIES
        knife:AddTearFlags(TearFlags.TEAR_EXTRA_GORE)
    end
    clearCannonKnifeSpin(knife, knife:GetData())
    knife.Rotation = beam.Direction:GetAngleDegrees()
    setKnifeAtVisualPosition(knife, position)
    applyCannonKnifeScale(knife, cannon)
    Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
    if hasCannonKnifeTinyPlanet(knife, cannon) then
        knife.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        beam.Laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    else
        local baseGrid = knife:GetData().MizukiCannonKnifeBaseGridCollisionClass
        if baseGrid ~= nil then knife.GridCollisionClass = baseGrid end
    end
    applyCannonKnifeScale(knife, cannon)
    setKnifeDrivenLaserDistance(beam, 1)
    beam.MomKnifeDriven = true
    beam.MomKnife = knife
    beam.MomKnifeInitSeed = knife.InitSeed
    beam.MomKnifeReturnStarted = false
    createCannonKnifeLaserRoot(beam)
    knife.Velocity = Vector.Zero
end

function Mizuki.refreshAuxiliaryCannonKnifeFlight(knife, cannon, beam, motionSource, shotCharge)
    if motionSource and motionSource:IsFlying() and not knife:IsFlying() then
        Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
        applyCannonKnifeScale(knife, cannon)
    end
end

-- Knife distance/velocity remain the sole flight clock. Laser length uses the
-- native orbit radius for Tiny Planet; its path maps the knife onto curves.
-- knives continue past a clipped endpoint while the laser keeps its wall stop.
-- Both real and echo controllers use this same outbound/return/spin algorithm.
function Mizuki.updateCannonKnifeFlight(knife, motionSource, beam, targetPosition, state, previousDistance)
    local laser = beam and beam.Laser
    local distance = math.max(0, motionSource:GetKnifeDistance())
    local knifeVelocity = motionSource:GetKnifeVelocity()
    local tinyPlanet = hasCannonKnifeTinyPlanet(knife, beam and beam.Cannon, motionSource)
    local mappedDistance = tinyPlanet and getKnifeOrbitRadius(motionSource, distance) or distance
    if tinyPlanet then
        knife.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        if laser and laser:Exists() then
            laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        end
    end
    if laser and laser:Exists() then
        laser.AngleDegrees = Mizuki.getCannonKnifeBeamAngle(beam, motionSource)
    end
    if state == KNIFE_STATE_OUTBOUND then
        local returning = knifeVelocity < -KNIFE_VELOCITY_EPSILON
            or (previousDistance ~= nil and distance < previousDistance - KNIFE_DISTANCE_EPSILON)
        local mappedPosition
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, mappedDistance)
            mappedPosition = getLaserEndpointTransform(laser, mappedDistance, beam.Direction, tinyPlanet)
        else
            local direction = beam and beam.Direction or Vector.FromAngle(knife.Rotation)
            mappedPosition = targetPosition + direction:Resized(mappedDistance)
        end
        if returning then
            state = KNIFE_STATE_RETURNING
            if beam then beam.MomKnifeReturnStarted = true end
        else
            setKnifeAtVisualPosition(knife, mappedPosition)
            knife.Velocity = Vector.Zero
            applyCannonKnifeSpin(knife, knife:GetData(), distance - (previousDistance or distance))
        end
    end
    if state == KNIFE_STATE_RETURNING then
        local returnPosition
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, mappedDistance)
            returnPosition = getLaserEndpointTransform(laser, mappedDistance, beam.Direction, tinyPlanet)
        else
            local returnDirection = beam and beam.Direction or Vector.FromAngle(knife.Rotation)
            returnPosition = targetPosition + returnDirection:Resized(mappedDistance)
        end
        setKnifeAtVisualPosition(knife, returnPosition)
        knife.Velocity = Vector.Zero
        applyCannonKnifeSpin(knife, knife:GetData(), distance - (previousDistance or distance))
    end
    local mappedPosition = knife.Position + knife.PositionOffset
    if tinyPlanet then
        if laser and laser:Exists() then
            local _, direction = getLaserEndpointTransform(laser, mappedDistance, beam.Direction, true)
            -- SpriteRotation is also the native capsule's local Y axis.
            knife.SpriteRotation = getKnifeOrbitRotation(beam, motionSource, mappedPosition, direction)
        end
        if beam and beam.Cannon then
            applyCannonKnifeScale(knife, beam.Cannon, motionSource)
        end
    end
    return state, distance
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

getKnifeMotionSource = function(knife, knifeData)
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

local function syncKnifeAfterLaserUpdate(_, laser, interpolated)
    if laser:GetData().MizukiBeam ~= true then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE)) do
        local knife = entity:ToKnife()
        local data = knife:GetData()
        if data.MizukiCannonKnife == true and validateKnifeOwnership(knife, data) then
            local beam = data.MizukiCannonKnifeBeam
            local ownedKnife = beamOwnsKnife(beam)
            if beam and beam.Laser and beam.Laser:Exists()
                and GetPtrHash(beam.Laser) == GetPtrHash(laser)
                and ownedKnife and GetPtrHash(ownedKnife) == GetPtrHash(knife)
                and data.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW then
                local source = getKnifeMotionSource(knife, data)
                if not interpolated or (source and hasCannonKnifeTinyPlanet(knife, beam.Cannon, source)) then
                    Mizuki.syncCannonKnifeFlightEndpoint(knife, source, beam)
                    if data.MizukiCannonKnifeAuxiliary ~= true then
                        Mizuki.refreshCannonMomKnifeShadow(data.MizukiCannonKnifeCannon)
                    end
                end
            end
        end
    end
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE,
    CallbackPriority.LATE, syncKnifeAfterLaserUpdate)
-- Native interpolation advances/samples the laser again between update and
-- render (including a paused half-step). Sync the actual capsule as well as
-- its visible pose, without advancing the knife clock or changing the laser.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER,
    CallbackPriority.LATE, function(_, laser)
        syncKnifeAfterLaserUpdate(nil, laser, true)
    end)

function Mizuki.updateCannonMomKnife(cannon)
    if cannon:GetData().MizukiGuillotineNonFiring
        or (cannon.Player and cannon.Player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)) then
        removeCannonKnife(cannon)
        return
    end
    local knife = ensureCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, cannon.Player)
    useManualCannonKnifeRender(knife)
    if knifeData.MizukiBerserkClub and Mizuki.updateBerserkClubSwing(knife, cannon) then return end
    Mizuki.connectPersistentEchoAttack(cannon.Player, cannon, knife, 0, "knife")
    if knifeData.MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
        or not knife:IsFlying()
    then
        if knifeData.MizukiBerserkClub == true then
            knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        end
        knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
        knifeData.MizukiSpecialBrimstoneCurse = false
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
    -- The primary knife body is reused for successive firing requests.
    knifeData.MizukiFirstHitBombSpawned = nil
    if not cannon:GetData().MizukiPersistentEchoMode then
        Mizuki.rollSpecialBrimstone(knife, cannon.Player)
    end
    knifeData.MizukiCannonKnifeBeam = beam
    knifeData.MizukiCannonKnifePreviousDistance = 0
    -- The persistent body has existed throughout charging, while auxiliary
    -- knives are born only on release. Give every native entity the same charge
    -- parameters; auxiliary visual timing is synchronized to the persistent
    -- knife separately in UpdateCannonMomKnifeEntity.
    local shotCharge = math.max(
        0,
        math.min(charge / math.max(1, baseChargeFrames), 1)
    )
    knifeData.MizukiCannonKnifeShotCharge = shotCharge
    if knifeData.MizukiBerserkClub then
        if Mizuki.cancelBerserkClubSwing then Mizuki.cancelBerserkClubSwing(knife) end
        knifeData.MizukiBerserkSwing = nil
        local params = cannon.Player:GetTearHitParams(WeaponType.WEAPON_BONE, 1, 1, knife)
        knife.TearFlags = params.TearFlags | TearFlags.TEAR_EXTRA_GORE
        knife.CollisionDamage = params.TearDamage
        knife.Color = Color.Lerp(params.TearColor, params.TearColor, 0)
        useManualCannonKnifeRender(knife)
        laser.TearFlags = laser.TearFlags | TearFlags.TEAR_EXTRA_GORE
    end
    Mizuki.launchCannonKnife(knife, cannon, beam, shotCharge, getCannonKnifeFollowPosition(cannon))
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
            clearKnifeBeamLink(auxiliaryKnife:GetData())
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil

    local knife = getCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    if knifeData.MizukiBerserkClub == true then Mizuki.cancelBerserkClubSwing(knife) end
    clearKnifeBeamLink(knifeData)
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
    knife:Reset()
    knifeData.MizukiSpecialBrimstoneCurse = false
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
    if cannon.Player and cannon.Player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        removeCannonKnife(cannon)
        return
    end
    if not Mizuki.cannonUsesKnifeWeapon(cannon.Player)
        or knife.Variant ~= Mizuki.getCannonKnifeWeaponVariant(cannon.Player)
        or (knifeData.MizukiBerserkClub == true) ~= Mizuki.isBerserkClubActive(cannon.Player) then
        removeCannonKnife(cannon)
        return
    end
    useManualCannonKnifeRender(knife)
    applyCannonKnifeScale(knife, cannon)

    if knifeData.MizukiBerserkClub and Mizuki.updateBerserkClubSwing(knife, cannon) then
        Mizuki.refreshCannonMomKnifeShadow(cannon)
        return
    end

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
        Mizuki.refreshAuxiliaryCannonKnifeFlight(knife, cannon,
            knifeData.MizukiCannonKnifeBeam, motionSource,
            knifeData.MizukiCannonKnifeShotCharge or 1)
    end
    if state == KNIFE_STATE_FOLLOW or not motionSourceFlying then
        if knifeData.MizukiBerserkClub == true then
            knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        end
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
        knifeData.MizukiSpecialBrimstoneCurse = false
        knife.Rotation = getCannonKnifeRotation(cannon)
        setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
        clearCannonKnifeSpin(knife, knifeData)
        knife.Velocity = Vector.Zero
        Mizuki.refreshCannonMomKnifeShadow(cannon)
        return
    end

    knifeData.MizukiCannonKnifeState, knifeData.MizukiCannonKnifePreviousDistance =
        Mizuki.updateCannonKnifeFlight(knife, motionSource, knifeData.MizukiCannonKnifeBeam,
            getCannonBodyPosition(cannon), state, knifeData.MizukiCannonKnifePreviousDistance)
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
Mizuki.renderCannonKnifeLaserRoots = renderCannonKnifeLaserRoots

function Mizuki.removeCannonKnifeLaserRoots(cannon)
    local hash = GetPtrHash(cannon)
    for index = #knifeLaserRoots, 1, -1 do
        local root = knifeLaserRoots[index]
        if root.CannonInitSeed == cannon.InitSeed and root.CannonPtrHash == hash then
            table.remove(knifeLaserRoots, index)
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
    local swing = knifeData.MizukiBerserkSwing
    local sprite = swing and swing.VisualSprite or knife:GetSprite()
    local cannon = knifeData.MizukiCannonKnifeCannon
    local originalRotation = sprite.Rotation
    local originalScale = Vector(sprite.Scale.X, sprite.Scale.Y)
    local originalOffset = Vector(sprite.Offset.X, sprite.Offset.Y)
    local originalFlipX = sprite.FlipX
    local originalFlipY = sprite.FlipY

    sprite.Rotation = knife.SpriteRotation
    if knifeData.MizukiBerserkClub == true and knife.Variant == 3
        and not knifeData.MizukiBerserkSwing and not knife:IsFlying() then
        -- Each held body keeps its own fixed art correction, independent of
        -- the player's input or the other side's attack. Swing draws separately.
        sprite.Rotation = knife.Rotation + Mizuki.BerserkClubParameters.HeldIdleRotationOffset
        if cannon and cannon:Exists() then
            local idle = cannon:GetData().MizukiIsIdle == true
            if idle then
                -- Resting artwork has one downward offset at the character's scale.
                worldPosition = worldPosition + Vector(0, 20 * math.abs(knife.SpriteScale.Y))
            end
        end
    end
    sprite.Scale = Vector(knife.SpriteScale.X, knife.SpriteScale.Y)
    sprite.Offset = Vector.Zero
    sprite.Color = knifeData.MizukiCannonKnifeDrawColor or Color.Default
    if cannon and cannon:Exists() and cannon:GetData().MizukiPersistentEchoMode
        and not Mizuki.isEchoAttackReplayActive(knife) then
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
    -- Sprite.Color is mutable native state. Keep an owned copy so changing
    -- the sprite for one trail cannot change the body or the next trail's alpha.
    local bodyColor = Color.Lerp(sprite.Color, sprite.Color, 0)
    local beam = knifeData.MizukiCannonKnifeBeam
    local source = beam and getKnifeMotionSource(knife, knifeData)
    if source and source:Exists() and source:IsFlying() and beam.Laser and beam.Laser:Exists()
        and hasCannonKnifeTinyPlanet(knife, cannon, source) then
        local distance = math.max(0, source:GetKnifeDistance())
        if distance > KNIFE_DISTANCE_EPSILON then
            local origin = beam.Laser.Position + beam.Laser.PositionOffset
            local endpoint = knife.Position + knife.PositionOffset
            local bodyRotation = knife.SpriteRotation
            local radialPosition = endpoint - origin
            local radius = getKnifeOrbitRadius(source, distance)
            local currentAngle = Mizuki.getCannonKnifeBeamAngle(beam, source)
            -- Native orbit-knife Render (0x965E60-0x966202): two in-between
            -- poses, distance - velocity*0.2*(index+1), alpha 0.6-index*0.3.
            -- Map those poses through our current curved ray, rather than
            -- drawing the engine's original parent-centred orbit underneath.
            for index = 1, 0, -1 do
                local trailDistance = math.max(0,
                    distance - source:GetKnifeVelocity() * 0.2 * (index + 1))
                local angleDelta = Mizuki.getCannonKnifeBeamAngle(beam, source, trailDistance)
                    - currentAngle
                local trailRadius = getKnifeOrbitRadius(source, trailDistance)
                local trailPosition = origin + (radialPosition * (radius ~= 0 and trailRadius / radius or 1))
                    :Rotated(angleDelta) + (worldPosition - endpoint)
                local trailScreen = screenPosition
                    + Isaac.WorldToScreen(trailPosition) - Isaac.WorldToScreen(worldPosition)
                local trailColor = Color.Lerp(bodyColor, bodyColor, 0)
                trailColor.A = bodyColor.A * (0.6 - index * 0.3)
                sprite.Color = trailColor
                sprite.Rotation = bodyRotation + angleDelta
                sprite:Render(trailScreen, Vector.Zero, Vector.Zero)
            end
            sprite.Rotation = bodyRotation
            sprite.Color = bodyColor
        end
    end
    sprite:Render(screenPosition, Vector.Zero, Vector.Zero)
    Mizuki.renderSpecialBrimstoneIcon(knife, worldPosition,
        finalRoomDraw and Vector.Zero or renderOffset, sprite.Color.A)

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
    -- Draw the collision entity's authoritative pose. Reading newer laser
    -- samples here makes the art advance while its capsule remains behind.
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

-- The engine can emit subtype-1 knives from a fired Mom's Knife. They inherit
-- the alpha-0 native body colour, although that body is drawn manually here.
-- Restore only those projectiles' inherited transparency, preserving their
-- native tint, motion, damage and any later nonzero fade.
local function restoreCannonKnifeProjectileAlpha(_, knife)
    if knife.SubType ~= 1 then return end
    local parent = knife.Parent and knife.Parent:ToKnife()
    if not parent or not parent:Exists() or parent.SubType ~= 0 then return end
    local parentData = parent:GetData()
    if parentData.MizukiCannonKnife ~= true
        or parentData.MizukiCannonKnifeManualRender ~= true
        or not validateKnifeOwnership(parent, parentData) then return end
    local drawColor = parentData.MizukiCannonKnifeDrawColor
    if not drawColor or drawColor.A <= 0 then return end
    if knife.Color.A <= 0 then
        local color = Color.Lerp(knife.Color, knife.Color, 0)
        color.A = drawColor.A
        knife.Color = color
    end
    local sprite = knife:GetSprite()
    if sprite.Color.A <= 0 then
        local spriteColor = Color.Lerp(sprite.Color, sprite.Color, 0)
        spriteColor.A = drawColor.A
        sprite.Color = spriteColor
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_INIT, restoreCannonKnifeProjectileAlpha)
Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, restoreCannonKnifeProjectileAlpha)
