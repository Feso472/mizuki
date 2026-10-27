-- Ludovico ring control, attached cannons and room transitions.
local Config = Mizuki.Config

local function getLudovicoFacingAnimation(player)
    local ring = player:GetData().MizukiLudovicoRing
    if not ring or not ring:Exists() then return nil end
    if not Mizuki.hasRawShootingInput(player) then return nil end

    local offset = ring.Position - player.Position
    if offset:Length() <= Mizuki.RuntimeParameters.DistanceEpsilon then return nil end
    if math.abs(offset.X) > math.abs(offset.Y) then
        return offset.X < 0 and "HeadLeft" or "HeadRight"
    end
    return offset.Y < 0 and "HeadUp" or "HeadDown"
end

function Mizuki.updateLudovicoPlayerFacing(player)
    local headAnimation = getLudovicoFacingAnimation(player)
    if not headAnimation then return end

    local sprite = player:GetSprite()
    local animation = sprite:GetAnimation()
    if not animation:match("^Head") and not animation:match("^Walk") then
        -- Do not interrupt pickup, hit, death, teleport or item-use animations.
        return
    end

    -- Keep Ludovico's visual rule independent from the pressed direction:
    -- while any shooting input is held, Mizuki looks toward her controlled ring.
    -- The input itself remains untouched so native familiars can control their
    -- own Ludovico tears normally.
    sprite:SetFrame(headAnimation, 0)
end

function Mizuki.removeLudovicoTriggeredBeams(data)
    for _, beam in ipairs(data.MizukiLudovicoTriggeredBeams or {}) do
        local laser = beam.Laser
        if laser and laser:Exists() and laser:GetData().MizukiLudovicoTriggeredBeam == true then
            laser:Remove()
        end
    end
    data.MizukiLudovicoTriggeredBeams = nil
    data.MizukiLudovicoTriggerNextFrame = nil
    data.MizukiLudovicoTriggerInterval = nil
end

local function updateLudovicoTriggeredBeamLifetimes(data)
    local beams = data.MizukiLudovicoTriggeredBeams
    if not beams then return end

    for index = #beams, 1, -1 do
        local beam = beams[index]
        local laser = beam.Laser
        if not laser or not laser:Exists() then
            table.remove(beams, index)
        elseif not beam.Ending then
            beam.Timeout = beam.Timeout - 1
            if beam.Timeout <= 0 then
                Mizuki.beginNaturalMizukiBeamEnding(beam)
            end
        end
    end

    if #beams == 0 then
        data.MizukiLudovicoTriggeredBeams = nil
    end
end

local function getActiveLudovicoTriggeredSources(data)
    local activeSources = {}
    for _, beam in ipairs(data.MizukiLudovicoTriggeredBeams or {}) do
        for source in pairs(beam.Sources or {}) do
            activeSources[source] = true
        end
    end
    return activeSources
end

local function appendLudovicoTriggeredAngle(entries, angleOffset, source)
    for _, entry in ipairs(entries) do
        local difference = (entry.Angle - angleOffset + 180) % 360 - 180
        if math.abs(difference) < Mizuki.RuntimeParameters.AngleMatchEpsilon then
            -- One rendered laser can satisfy several simultaneous sources. Keep
            -- every owner on the record so angle de-duplication cannot release
            -- one source's per-shot lock early.
            entry.Sources[source] = true
            return
        end
    end
    table.insert(entries, {
        Angle = angleOffset,
        Sources = { [source] = true },
    })
end

function Mizuki.fireLudovicoTriggeredBeams(player, data)
    updateLudovicoTriggeredBeamLifetimes(data)

    local cannons = data.MizukiCannons
    local hasCannon = false
    for side = 1, 2 do
        for _, cannon in ipairs(cannons and cannons[side] or {}) do
            if cannon and cannon:Exists()
                and cannon:GetData().MizukiLudovicoOrbiting
            then
                hasCannon = true
                break
            end
        end
        if hasCannon then break end
    end
    if not hasCannon then return end

    local frame = Game():GetFrameCount()
    local interval = Mizuki.getFireInterval(player)
    local nextFrame = data.MizukiLudovicoTriggerNextFrame
    local previousInterval = data.MizukiLudovicoTriggerInterval
    if nextFrame and previousInterval
        and math.abs(previousInterval - interval) > Mizuki.RuntimeParameters.FrameComparisonEpsilon
    then
        local remaining = math.max(0, nextFrame - frame)
        nextFrame = frame + remaining * interval / previousInterval
    end
    data.MizukiLudovicoTriggerInterval = interval
    if not nextFrame then
        nextFrame = frame
    end
    if frame + Mizuki.RuntimeParameters.FrameComparisonEpsilon < nextFrame then
        data.MizukiLudovicoTriggerNextFrame = nextFrame
        return
    end
    repeat
        nextFrame = nextFrame + interval
    until nextFrame > frame
    data.MizukiLudovicoTriggerNextFrame = nextFrame

    local activeSources = getActiveLudovicoTriggeredSources(data)
    local transientEffects = Mizuki.getMizukiTransientBeamEffects(
        player,
        activeSources
    )
    local angleEntries = {}
    for _, source in ipairs({
        Config.TRANSIENT_BEAM_SOURCE_BOOK_WORM,
        Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE,
        Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS,
        Config.TRANSIENT_BEAM_SOURCE_EYE_SORE,
    }) do
        for _, angleOffset in ipairs(
            transientEffects.Sources[source] or {}
        ) do
            appendLudovicoTriggeredAngle(angleEntries, angleOffset, source)
        end
    end
    if #angleEntries == 0 then return end

    local beamDistance = Mizuki.getBeamDistance(player)
    local beamWidthScale = Mizuki.getBeamWidthScale(player)
    local isBrimstoneBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    )
    local isTechnologyZeroBeam = Mizuki.usesTechnologyZeroBeam(player)
    local beamDuration, damagePerTickMultiplier = Mizuki.getBeamDamageTiming(
        player,
        false,
        isBrimstoneBeam,
        isTechnologyZeroBeam,
        Mizuki.getBrimstoneBeamDuration(player)
    )
    local beamEndFrames = Mizuki.getBeamEndFrames(isBrimstoneBeam)
    local beamActiveDuration = math.max(1, beamDuration - beamEndFrames)
    data.MizukiLudovicoTriggeredBeams =
        data.MizukiLudovicoTriggeredBeams or {}

    for side = 1, 2 do
        for _, cannon in ipairs(cannons[side] or {}) do
            if cannon and cannon:Exists() then
                local cannonData = cannon:GetData()
                if cannonData.MizukiLudovicoOrbiting
                    and not Mizuki.isTech2Cannon(cannon) then
                    local tangentDirection = cannonData.MizukiCannonAim
                        or Vector(0, -1)
                    local visualOrigin = cannon.Position
                        + (cannonData.MizukiPivotRenderOffset or Vector.Zero)
                    local damageMultiplier =
                        (cannonData.MizukiLudovicoDamageMultiplier or 1)
                        * Config.LUDOVICO_TRIGGERED_BEAM_DAMAGE_MULTIPLIER
                    local apiDamageMultiplier = damageMultiplier
                        * damagePerTickMultiplier

                    for _, angleEntry in ipairs(angleEntries) do
                        local angleOffset = angleEntry.Angle
                        local beamDirection = tangentDirection:Rotated(angleOffset)
                        local hitboxOffset = Vector(0, Config.BEAM_HITBOX_Y_OFFSET)
                        local hitboxOrigin = visualOrigin + hitboxOffset
                        local laser = Mizuki.createCannonBeam(player, {
                            Origin = hitboxOrigin, Direction = beamDirection,
                            LeftEye = side == 1, DamageMultiplier = apiDamageMultiplier,
                            WidthScale = beamWidthScale, PositionOffset = -hitboxOffset,
                            DepthOffset = cannon.DepthOffset - Mizuki.WeaponParameters.BeamDepthBehindCannon
                                - hitboxOffset.Y,
                            ActiveDuration = beamActiveDuration, Distance = beamDistance,
                            Automatic = false,
                        })
                        local laserData = laser:GetData()
                        Mizuki.bindCannonAttackAppearance(cannon, laser, apiDamageMultiplier)
                        Mizuki.connectPersistentEchoAttack(player, cannon, laser, angleOffset, "triggered-beam")
                        laserData.MizukiLudovicoTriggeredBeam = true
                        laserData.MizukiLudovicoTriggeredSources =
                            angleEntry.Sources
                        if cannonData.MizukiPersistentEchoMode and not Mizuki.isEchoAttackReplayActive(laser) then
                            laser.Color = Mizuki.getPersistentEchoColor(laser.Color)
                        end

                        table.insert(data.MizukiLudovicoTriggeredBeams, {
                            Laser = laser,
                            Timeout = beamActiveDuration,
                            Sources = angleEntry.Sources,
                        })
                    end
                end
            end
        end
    end
end

function Mizuki.removeLudovicoRing(data)
    Mizuki.removeLudovicoTriggeredBeams(data)
    local ring = data.MizukiLudovicoRing
    if ring and ring:Exists() and ring:GetData().MizukiIsLudovicoRing == true then
        ring:Remove()
    end
    data.MizukiLudovicoRing = nil
    data.MizukiLudovicoWeaponActive = nil
    data.MizukiLudovicoRingSynergyBrimstone = nil
    data.MizukiLudovicoCannonOrbitAngle = nil
    data.MizukiLudovicoCannonLayoutCenter = nil
    data.MizukiLudovicoKnifeResyncPending = nil
    data.MizukiLudovicoKnifeResyncReady = nil
end

function Mizuki.updateLudovicoCannons(player, data, ring)
    Mizuki.prunePlayerCannons(data)
    data.MizukiCannonPositions = { {}, {} }
    data.MizukiAutomaticEchoHistory = nil
    local frame = Game():GetFrameCount()

    local angle = data.MizukiLudovicoCannonOrbitAngle or -90
    angle = (angle
        + player.ShotSpeed
            * Mizuki.LUDOVICO_CANNON_ORBIT_DEGREES_PER_FRAME) % 360
    data.MizukiLudovicoCannonOrbitAngle = angle

    local ringRadius = ring.Radius
    if not ringRadius or ringRadius <= 0 then
        ringRadius = Mizuki.WeaponParameters.LudovicoDefaultRingRadius
    end
    -- Gameplay geometry follows the laser entity's collision centre. Render
    -- offsets stay visual-only, matching the ring whose hitbox sits slightly
    -- below its artwork.
    local orbitCenter = ring.Position
    -- Every member is one copied cannon pair. Spread pair origins evenly over
    -- one semicircle, then place side 2 exactly 180 degrees from side 1. The
    -- complete set remains evenly distributed, but both cannons belonging to
    -- the same source now stay opposite each other instead of occupying two
    -- adjacent slots. Each Familiar owns its contact cooldown independently.
    local cannonGroups = data.MizukiCannons
    local cannonPairProfiles = data.MizukiExpectedCannonPairProfiles
        or Mizuki.getExpectedCannonPairProfiles(player)
    local maxMembers = math.max(
        #(cannonGroups[1] or {}),
        #(cannonGroups[2] or {})
    )
    local knifeResyncPending = data.MizukiLudovicoKnifeResyncPending
    data.MizukiLudovicoCannonLayoutCenter = Vector(
        orbitCenter.X,
        orbitCenter.Y
    )
    local pairStep = 180 / math.max(maxMembers, 1)
    local orbitRadius = ringRadius + Mizuki.LUDOVICO_CANNON_ORBIT_PADDING
    local cannonHitboxes = {}
    for member = 1, maxMembers do
        local pairProfile = cannonPairProfiles[member] or {
            DamageMultiplier = 1,
            ScaleMultiplier = 1,
        }
        for side = 1, 2 do
            local cannon = cannonGroups[side] and cannonGroups[side][member]
            if cannon and cannon:Exists() then
                local orbitDirection = Vector.FromAngle(
                    angle
                        + (pairProfile.OrbitSlot or (member - 1)) * pairStep
                        + (side - 1) * 180
                )
                local tangentDirection = orbitDirection:Rotated(90)
                cannon.Position = orbitCenter
                    + orbitDirection * orbitRadius
                cannon.Velocity = Vector.Zero
                local cannonData = cannon:GetData()
                Mizuki.applyPersistentCannonEchoProfile(cannon, pairProfile)
                Mizuki.applyGuillotineCannonProfile(cannon, pairProfile, {})
                local collisionRadius = Mizuki.updateCannonCollisionSize(
                    cannon,
                    pairProfile.ScaleMultiplier,
                    false
                )
                local settledFrame = cannonData.MizukiInitialLayoutFrame
                if cannonData.MizukiAwaitingInitialLayout then
                    if settledFrame and frame > settledFrame then
                        cannonData.MizukiAwaitingInitialLayout = nil
                        cannonData.MizukiInitialLayoutFrame = nil
                    elseif not settledFrame then
                        cannonData.MizukiInitialLayoutFrame = frame
                    end
                end
                -- Keep the Familiar in the native render pipeline so its anm2
                -- shadow layer reaches the engine's dedicated shadow pass. The
                -- transparent sprite colour suppresses the native body; the
                -- visible body is still redrawn explicitly after the ring.
                cannon.Visible = not cannonData.MizukiAwaitingInitialLayout
                cannon.DepthOffset = orbitDirection.Y > 0
                    and Config.HORIZONTAL_FRONT_DEPTH_OFFSET
                    or Config.HORIZONTAL_BACK_DEPTH_OFFSET
                cannonData.CannonSide = side
                cannonData.MizukiIsIdle = false
                cannonData.MizukiIdleScreenXScale = 1
                cannonData.MizukiIdleFlipProgress = 0
                cannonData.MizukiIdleDepthOrder = 0
                cannonData.MizukiIdleAngleMirrorProgress = 0
                cannonData.MizukiLudovicoOrbiting = true
                cannonData.MizukiCannonFiringPositionLocked = false
                Mizuki.bindCannonAttackAppearance(cannon, ring, 1)
                Mizuki.updateCannonBrimstoneCurse(cannon)
                -- Ludovico previously kept the left sheet throughout its orbit.
                cannonData.MizukiVerticalBodyXFactor = -1
                cannonData.MizukiReflectionBodyXFactor = -1
                Mizuki.updateCannonBodyGraphics(cannon, cannonData)
                cannonData.MizukiLudovicoDamageMultiplier =
                    pairProfile.DamageMultiplier
                cannonData.MizukiContactDamageMultiplier =
                    pairProfile.DamageMultiplier
                cannonData.MizukiLudovicoScaleMultiplier =
                    pairProfile.ScaleMultiplier
                cannonData.MizukiDesiredPosition = nil
                -- Orbiting cannons have their own explicit visual position and
                -- must not inherit the ordinary familiar's previous hover pose.
                cannonData.MizukiBobOffsetY = 0
                cannonData.MizukiIdleSwingFrame = nil
                cannonData.MizukiIdleRotationOffset = 0
                cannonData.MizukiReflectionSpan =
                    Config.CANNON_FIRING_REFLECTION_SPAN * player.SpriteScale.Y
                cannonData.MizukiCannonAim = tangentDirection
                cannonData.MizukiRenderWorldOffset = Vector(
                    ring.PositionOffset.X,
                    ring.PositionOffset.Y
                )
                cannonData.MizukiLayoutOffset = cannon.Position - player.Position

                if knifeResyncPending then
                    -- Cannons created by CheckFamiliar after MC_POST_NEW_ROOM
                    -- must join the same hidden transition as surviving ones.
                    cannonData.MizukiDeferMomKnifeUntilLudovicoReady = true
                end

                local sprite = cannon:GetSprite()
                -- One angle for both: the sprite keeps pointing along the
                -- tangent and spins about its own centre, so the pair simply
                -- rotates around the ring.
                local spriteRotation, pivotRenderOffset, basePivotRenderOffset = Mizuki.getCannonSpriteTransform(
                    cannon,
                    tangentDirection,
                    tangentDirection,
                    0
                )
                cannonData.MizukiPivotRenderOffset = pivotRenderOffset
                cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
                cannonData.MizukiCannonBodyRotation = spriteRotation
                sprite.Rotation = 0
                Mizuki.applyCannonShadowPose(player, cannon)
                sprite.Color = Mizuki.getCannonHiddenColor()
                data.MizukiCannonPositions[side][member] = Vector(
                    cannon.Position.X,
                    cannon.Position.Y
                )
                cannonHitboxes[#cannonHitboxes + 1] = {
                    Cannon = cannon,
                    Group = member,
                    Position = cannon.Position,
                    Radius = collisionRadius,
                    DamageMultiplier = pairProfile.DamageMultiplier,
                }
            end
        end
    end

    Mizuki.captureLudovicoEpicFetusGeometry(
        player,
        ring,
        cannonHitboxes
    )
end

function Mizuki:FinalizeLudovicoKnifeRoomEntry(laser)
    local laserData = laser:GetData()
    if not laserData.MizukiIsLudovicoRing then return end

    local player = laserData.MizukiLudovicoOwner
    if not player or not player:Exists() then return end
    local data = player:GetData()
    if not data.MizukiLudovicoKnifeResyncPending then return end

    local cannonGroups = data.MizukiCannons
    local layoutCenter = data.MizukiLudovicoCannonLayoutCenter
    if not cannonGroups or not layoutCenter then return end

    local profiles = data.MizukiExpectedCannonPairProfiles
        or Mizuki.getExpectedCannonPairProfiles(player)
    local expectedPairCount = #profiles
    if #(cannonGroups[1] or {}) < expectedPairCount
        or #(cannonGroups[2] or {}) < expectedPairCount
    then
        return
    end

    -- Player update runs before the native Ludovico laser update. During a room
    -- transition that first layout therefore uses the temporary player-centred
    -- ring position. Translate the completed layout by the ring's final native
    -- displacement here; keep its already-resolved orbit angle unchanged.
    local centerCorrection = laser.Position - layoutCenter
    data.MizukiCannonPositions = { {}, {} }
    for side = 1, 2 do
        for member, cannon in ipairs(cannonGroups[side] or {}) do
            if cannon and cannon:Exists() then
                local cannonData = cannon:GetData()
                cannon.Position = cannon.Position + centerCorrection
                cannon.Velocity = Vector.Zero
                cannonData.MizukiLayoutOffset = cannon.Position - player.Position
                cannonData.MizukiRenderWorldOffset = Vector(
                    laser.PositionOffset.X,
                    laser.PositionOffset.Y
                )
                data.MizukiCannonPositions[side][member] = Vector(
                    cannon.Position.X,
                    cannon.Position.Y
                )
            end
        end
    end
    data.MizukiLudovicoCannonLayoutCenter = Vector(
        laser.Position.X,
        laser.Position.Y
    )
    -- Keep the existing knife entity hidden through the transition. Its native
    -- update preserves the established sprite/rotation relationship; after all
    -- entities finish updating, only its position is synchronized to this final
    -- cannon layout.
    data.MizukiLudovicoKnifeResyncReady = true
end

function Mizuki:CompleteLudovicoKnifeRoomEntry()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then
            local data = player:GetData()
            if data.MizukiLudovicoKnifeResyncPending
                and data.MizukiLudovicoKnifeResyncReady
            then
                for side = 1, 2 do
                    for _, cannon in ipairs(
                        (data.MizukiCannons and data.MizukiCannons[side]) or {}
                    ) do
                        if cannon and cannon:Exists() then
                            local cannonData = cannon:GetData()
                            cannonData.MizukiDeferMomKnifeUntilLudovicoReady = nil
                            Mizuki.updateCannonMomKnife(cannon)
                        end
                    end
                end
                data.MizukiLudovicoKnifeResyncPending = nil
                data.MizukiLudovicoKnifeResyncReady = nil
            end
        end
    end
end

-- A normal player has a weapon controller which moves RING_LUDOVICO from the
-- shooting input. Mizuki is blindfolded, so move the native Tech X ring directly
-- without an intermediate tear carrier.
function Mizuki.updateLudovicoRing(player, data)
    local myReflectionPullSpeedMultiplier = Mizuki.WeaponParameters.ReflectionPullSpeedMultiplier
    local myReflectionPullDistanceResponse = Mizuki.WeaponParameters.ReflectionPullDistanceResponse
    local hasBrimstone = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    )
    local previousHasBrimstone = data.MizukiLudovicoRingSynergyBrimstone
    data.MizukiLudovicoRingSynergyBrimstone = hasBrimstone
    if previousHasBrimstone ~= nil
        and previousHasBrimstone ~= hasBrimstone
    then
        -- FireTechXLaser chooses Brimstone visuals when the entity is created.
        -- Track that actual creation input instead of total collectible count,
        -- so both gaining and losing it through a reroll rebuild the ring.
        local staleRing = data.MizukiLudovicoRing
        if staleRing and staleRing:Exists() then
            staleRing:Remove()
        end
        data.MizukiLudovicoRing = nil
    end

    if not data.MizukiLudovicoWeaponActive then
        Mizuki.removeActiveMizukiBeams(data)
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        data.MizukiCursedEyeBurst = nil
        data.MizukiLudovicoWeaponActive = true
    end

    local ring = data.MizukiLudovicoRing
    if not ring or not ring:Exists() then
        ring = player:FireTechXLaser(
            player.Position,
            Vector.Zero,
            Mizuki.WeaponParameters.LudovicoDefaultRingRadius,
            player,
            1
        ):ToLaser()
        -- Parent and RING_FOLLOW_PARENT are independent concerns. Subtype 1 is
        -- the engine's Tech/Brim + Ludovico ring; subtype 3 is the kind used by
        -- effects such as Maw of the Void and can discard the fire-ring visuals.
        ring.SubType = LaserSubType.LASER_SUBTYPE_RING_LUDOVICO
        ring:SetTimeout(-1)
        local ringData = ring:GetData()
        ringData.MizukiIsLudovicoRing = true
        ringData.MizukiLudovicoOwner = player
        ringData.MizukiLudovicoBasePositionOffset = Vector(
            ring.PositionOffset.X,
            ring.PositionOffset.Y
        )
        data.MizukiLudovicoRing = ring
    end
    -- Also repairs ownership after a Lua hot reload without requiring the ring
    -- to be recreated or the room to be changed.
    local ringData = ring:GetData()
    ringData.MizukiLudovicoOwner = player
    local basePositionOffset = ringData.MizukiLudovicoBasePositionOffset
    if not basePositionOffset then
        basePositionOffset = Vector(
            ring.PositionOffset.X,
            ring.PositionOffset.Y
        )
        ringData.MizukiLudovicoBasePositionOffset = basePositionOffset
    end
    if data.MizukiLudovicoNeedsRoomEntryReset then
        -- A surviving laser can retain an engine transition coordinate, while
        -- a rebuilt one already starts at the player. Normalize both cases
        -- before the orbiting cannons consume ring.Position this frame.
        ring.Position = Vector(player.Position.X, player.Position.Y)
        ring.Velocity = Vector.Zero
        ringData.MizukiLudovicoSmoothedVelocity = Vector.Zero
        data.MizukiLudovicoNeedsRoomEntryReset = nil
    end
    -- Native Ludovico keeps a fixed render height when player size changes.
    -- Scale only that visual Y offset; ring.Position remains the collision plane.
    ring.PositionOffset = Vector(
        basePositionOffset.X,
        basePositionOffset.Y * player.SpriteScale.Y
    )

    local control = Mizuki.getRawShootingInput(player)
    if Options.MouseControl
        and player.ControllerIndex == 0
        and player:AreControlsEnabled()
        and Input.IsMouseBtnPressed(0)
    then
        control = Input.GetMousePosition(true) - ring.Position
    end
    local targetVelocity = Vector.Zero
    if control:Length() > Mizuki.RuntimeParameters.AimDeadZone then
        targetVelocity = control:Normalized() * player.ShotSpeed * Mizuki.WeaponParameters.LudovicoMoveSpeed
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MY_REFLECTION) then
        -- Vanilla Ludovico + My Reflection continuously draws the controlled
        -- tear back toward Isaac. Add that weak pull to manual movement rather
        -- than replacing it; taper it near the player to prevent oscillation.
        local toPlayer = player.Position - ring.Position
        local distance = toPlayer:Length()
        if distance > Mizuki.RuntimeParameters.DistanceEpsilon then
            local pullSpeed = math.min(
                player.ShotSpeed
                    * myReflectionPullSpeedMultiplier,
                distance * myReflectionPullDistanceResponse
            )
            targetVelocity = targetVelocity
                + toPlayer:Resized(pullSpeed)
        end
    end
    -- Match Samael's controlled-Ludovico movement: approach the requested
    -- velocity by 20% per frame. Store our own previous velocity because the
    -- native Ludovico laser controller may rewrite EntityLaser.Velocity between
    -- callbacks, which would erase the turn history and make direction snap.
    local smoothedVelocity = ringData.MizukiLudovicoSmoothedVelocity
        or ring.Velocity
    smoothedVelocity = smoothedVelocity * (1 - Mizuki.WeaponParameters.LudovicoVelocityResponse)
        + targetVelocity * Mizuki.WeaponParameters.LudovicoVelocityResponse
    ringData.MizukiLudovicoSmoothedVelocity = smoothedVelocity
    ring.Velocity = smoothedVelocity

    return true
end

-- Mizuki's Ludovico-only attack uses a Tech-flavoured ring even without the
-- Technology item. Rate-limit only that custom branch by her current fire
-- delay. Real Technology or Brimstone Ludovico rings keep their native damage
-- cadence; the schedule is otherwise stored per target so touching several
-- enemies never makes them consume one another's damage ticks.
function Mizuki:ThrottleLudovicoTechXDamage(entity, amount, damageFlags, source)
    local sourceEntity = source and source.Entity
    local laser = sourceEntity and sourceEntity:ToLaser()
    local laserData = laser and laser:GetData()
    local player = laserData and laserData.MizukiLudovicoOwner

    if not player then
        -- RING_LUDOVICO attributes its native collision damage directly to the
        -- firing player (DAMAGE_LASER), not to the EntityLaser returned by
        -- FireTechXLaser. Resolve that source back to this player's live ring.
        player = sourceEntity and sourceEntity:ToPlayer()
        if not player
            or not Mizuki.isMizuki(player)
            or (damageFlags & DamageFlag.DAMAGE_LASER) == 0
        then
            return
        end
        laser = player:GetData().MizukiLudovicoRing
        if not laser or not laser:Exists() then return end
        laserData = laser:GetData()
        if not laserData.MizukiIsLudovicoRing then return end
    elseif not laserData.MizukiIsLudovicoRing then
        return
    end

    if not player or not player:Exists() or not Mizuki.isMizuki(player) then
        return
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
    then
        -- These synergies already own their native ring timing. Also discard a
        -- Ludo-only schedule so losing either item through a reroll starts a
        -- fresh manual interval instead of inheriting an obsolete cooldown.
        laserData.MizukiLudovicoDamageSchedules = nil
        return
    end

    local targetHash = GetPtrHash(entity)
    local schedules = laserData.MizukiLudovicoDamageSchedules
    if not schedules then
        schedules = {}
        laserData.MizukiLudovicoDamageSchedules = schedules
    end

    local frame = Game():GetFrameCount()
    local interval = Mizuki.getFireInterval(player)
    local schedule = schedules[targetHash]
    local targetSeed = entity.InitSeed
    if schedule and schedule.TargetInitSeed ~= targetSeed then
        schedule = nil
        schedules[targetHash] = nil
    end
    if not schedule then
        -- Contact should feel immediate; only repeated damage is rate-limited.
        schedules[targetHash] = {
            TargetInitSeed = targetSeed,
            NextFrame = frame + interval,
            Interval = interval,
        }
        return
    end

    if math.abs(schedule.Interval - interval) > Mizuki.RuntimeParameters.FrameComparisonEpsilon then
        -- Preserve the completed fraction of the current cooldown when Tears
        -- changes instead of granting or deleting a whole hit.
        local remaining = math.max(0, schedule.NextFrame - frame)
        schedule.NextFrame = frame
            + remaining * interval / schedule.Interval
        schedule.Interval = interval
    end

    if frame + Mizuki.RuntimeParameters.FrameComparisonEpsilon < schedule.NextFrame then
        return false
    end

    repeat
        schedule.NextFrame = schedule.NextFrame + interval
    until schedule.NextFrame > frame
end

function Mizuki.getLudovicoEpicFetusSource(player, damageFlags, source)
    local ring = player:GetData().MizukiLudovicoRing
    if not ring or not ring:Exists() then return nil end

    local sourceEntity = source and source.Entity
    if not sourceEntity then return nil end

    local familiar = sourceEntity:ToFamiliar()
    if familiar
        and familiar.Variant == Mizuki.CannonVariant
        and familiar:GetData().MizukiLudovicoOrbiting
        and Mizuki.cannonBelongsToPlayer(familiar, player)
    then
        return true
    end

    local sourceLaser = sourceEntity:ToLaser()
    if sourceLaser
        and sourceLaser:Exists()
        and sourceLaser.InitSeed == ring.InitSeed
        and GetPtrHash(sourceLaser) == GetPtrHash(ring)
    then
        return false
    end

    local sourcePlayer = sourceEntity:ToPlayer()
    if sourcePlayer
        and sourcePlayer.InitSeed == player.InitSeed
        and GetPtrHash(sourcePlayer) == GetPtrHash(player)
        and (damageFlags & DamageFlag.DAMAGE_LASER) ~= 0
    then
        -- RING_LUDOVICO normally attributes its damage to the firing player.
        return false
    end
    return nil
end
