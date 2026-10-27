-- Cannon Tech X: native rings, per-side charge, tethered flight and release.
Mizuki.TechXParameters = { MaxRadius = 70, MinRadius = 5, ConnectorDamageMultiplier = 0.5 }
local rings = {}
local rails = {}
local function copy(v) return Vector(v.X, v.Y) end
local function alive(e) return e and e:Exists() end

-- This is firing capability, not controller ownership: Spirit Sword can
-- still fire Tech X from its blade while owning the melee input controller.
function Mizuki.usesCannonTechX(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X)
        and not Mizuki.usesCSectionWeapon(player)
        and not Mizuki.cannonUsesKnifeWeapon(player)
        and not Mizuki.isBerserkClubActive(player)
end

-- Snapshot at firing, shared by every weapon using the cannon position rules.
function Mizuki.shouldAntiGravityFollow(player)
    return player:GetCollectibleNum(CollectibleType.COLLECTIBLE_ANTI_GRAVITY) % 2 == 1
end

function Mizuki.createCannonTechXRing(player, parameters)
    local velocity = parameters.Direction:Resized(parameters.TechXSpeed)
    local damageMultiplier = parameters.TechXDamageMultiplier
    local brimstoneMultiplier = 1
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        brimstoneMultiplier = Mizuki.getSecondaryBrimstoneDamageMultiplier(player)
    end
    local ring = player:FireTechXLaser(parameters.Origin, velocity,
        parameters.TechXRadius, player, damageMultiplier * brimstoneMultiplier)
    ring.DisableFollowParent = true
    ring.Parent = player
    ring.Position = copy(parameters.Origin)
    ring.Velocity = velocity
    ring.PositionOffset = copy(parameters.PositionOffset)
    ring.DepthOffset = parameters.DepthOffset
    ring.TearFlags = Mizuki.addOccultHoming(player, ring.TearFlags)
        & ~Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS
    local data = ring:GetData()
    data.MizukiCannonTechXRing = true
    data.MizukiBeamOwner = player
    data.MizukiBrimstoneDamageMultiplier = brimstoneMultiplier
    rings[ring] = { Player = player, Seed = ring.InitSeed }
    return ring
end

-- One native connector per cannon and multishot lane, retained until release.
function Mizuki.findCannonTechXRail(data, side, cannon, lane)
    for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
        if beam.TechXRailMaster and not beam.TechXReleased and not beam.Ending
            and alive(beam.Laser) and Mizuki.isSameEntity(beam.Cannon, cannon)
            and beam.TechXChainLane == lane then return beam end
    end
end

function Mizuki.attachCannonTechX(beam, player)
    local parameters = beam.BeamParameters
    if not parameters.TechXRadius then return end
    beam.TechXDriven = true
    beam.TechXLinked = not parameters.TechXPartial
    beam.TechXChain = parameters.TechXChain == true
    beam.TechXChainLane = parameters.TechXChainLane
    beam.TechXRailRingOnly = parameters.TechXRingOnly == true
    beam.TechXRailMaster = beam.TechXChain and not beam.TechXRailRingOnly
    if beam.TechXRailMaster then rails[beam] = true end
    if beam.TechXChain then beam.TechXGuideOrigin = copy(parameters.Origin) end
    local ring = (parameters.TechXPartial or beam.TechXRailRingOnly) and beam.Laser
        or Mizuki.createCannonTechXRing(player, parameters)
    beam.TechXRing = ring
    rings[ring].Beam = beam
    beam.TechXBornFrame = Game():GetFrameCount()
    beam.TechXDistance = 0
    beam.TechXFlightVelocity = parameters.Direction:Resized(parameters.TechXSpeed)
    beam.TechXNativeTimeout = ring.Timeout
    beam.TechXFreeDepthOffset = ring.DepthOffset
    beam.TechXInitialOrigin = copy(parameters.Origin)
    beam.TechXFrames, beam.TechXFrameAges = {}, {}
    beam.TechXReleased = parameters.TechXPartial == true
    ring:GetData().MizukiTechXTether = beam
    if parameters.TechXPartial then
        beam.TechXReleaseAge = 0
    else
        if not beam.TechXRailRingOnly then beam.Laser:SetMaxDistance(1) end
        ring:SetTimeout(-1)
        ring.Position = copy(parameters.Origin)
        ring.Velocity = Vector.Zero
    end
end

local function releaseRing(beam)
    if beam.TechXRingReleased then return end
    beam.TechXRingReleased = true
    beam.TechXRingReleaseAge = Game():GetFrameCount() - beam.TechXBornFrame
    local ring = beam.TechXRing
    if alive(ring) and ring:GetData().MizukiCannonTechXRing == true then
        ring:GetData().MizukiTechXTether = nil
        ring.Velocity = copy(beam.TechXFlightVelocity)
        ring:SetTimeout(beam.TechXNativeTimeout)
        ring.DepthOffset = beam.TechXFreeDepthOffset or ring.DepthOffset
    end
end

function Mizuki.releaseCannonTechX(beam)
    if not beam.TechXDriven or beam.TechXReleased then return end
    beam.TechXReleased = true
    beam.TechXReleaseAge = Game():GetFrameCount() - beam.TechXBornFrame
    releaseRing(beam)
    -- Ring-only followers have no separate connector to shrink or damage.
    if beam.TechXRailRingOnly then beam.TechXLinked = false end
    if beam.TechXLinked then Mizuki.beginNaturalMizukiBeamEnding(beam) end
end

function Mizuki.cancelCannonTechX(beam, includeReleased)
    if not beam.TechXDriven or (beam.TechXReleased and not includeReleased) then return end
    local ring = beam.TechXRing
    if alive(ring) and ring:GetData().MizukiCannonTechXRing == true
        and (includeReleased or not beam.TechXRingReleased) then ring:Remove() end
end

function Mizuki.updateCannonTechXBeam(beam, held)
    if beam.TechXReleased or not held
        or (not alive(beam.TechXRing) and not beam.TechXRailMaster)
        or not alive(beam.Cannon) then
        if not alive(beam.TechXRing) and not beam.TechXRailMaster then
            beam.TechXEndAge = Game():GetFrameCount() - beam.TechXBornFrame
        end
        Mizuki.releaseCannonTechX(beam)
        return
    end
    beam.Timeout = beam.ActiveDuration
    beam.Laser.Timeout = beam.ActiveDuration
    if not beam.TechXRingReleased then beam.TechXRing:SetTimeout(-1) end
end

local function setGeometry(beam, origin, center, velocity)
    local ring, laser = beam.TechXRing, beam.Laser
    if not alive(ring) or not alive(laser) then return end
    beam.TechXDesiredCenter = copy(center)
    ring.Position = copy(center)
    ring.PositionOffset = copy(laser.PositionOffset)
    ring.Velocity = copy(velocity)
    -- Preparation only. The native ring update can still constrain its center.
    -- Resolve the actual connector after every entity has finished positioning.
    if not beam.TechXRailRingOnly then laser.Position = copy(origin) end
end

function Mizuki.hasLinkedCannonTechX(data, side, cannon)
    for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
        if beam.TechXDriven and beam.TechXLinked and not beam.TechXReleased
            and not beam.Ending and not beam.PersistentEchoMode
            and Mizuki.isSameEntity(beam.Cannon, cannon)
            and (beam.TechXRailMaster or alive(beam.TechXRing)) then return true end
    end
    return false
end

-- Called after the shared cannon pose resolver. Advance only once per logical
-- frame; parent translation changes the entire tether, not relative range.
function Mizuki.syncCannonTechXAttacks(data)
    local frame = Game():GetFrameCount()
    for side = 1, 2 do
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            if beam.TechXDriven and beam.TechXLinked and not beam.TechXReleased
                and alive(beam.Laser) and (alive(beam.TechXRing) or beam.TechXRailMaster) then
                if alive(beam.TechXRing) and not rings[beam.TechXRing] then
                    rings[beam.TechXRing] = { Player = beam.Laser:GetData().MizukiBeamOwner,
                        Seed = beam.TechXRing.InitSeed, Beam = beam }
                end
                -- First resolve the guide ray from the cannon's completed pose.
                -- Input requests that pose; it does not place the circle directly.
                local cannonData = alive(beam.Cannon) and beam.Cannon:GetData()
                -- RenderCannon draws BodyRotation, including the idle-return
                -- tilt. Its artwork points upward, hence the +90 art baseline.
                local cannonAim = cannonData and cannonData.MizukiCannonBodyRotation ~= nil
                    and Vector.FromAngle(cannonData.MizukiCannonBodyRotation - 90)
                    or cannonData and cannonData.MizukiCannonAim
                beam.Direction = cannonAim and cannonAim:Rotated(beam.DirectionOffset or 0)
                    or beam.TechXTargetDirection or beam.Direction
                beam.TechXFlightVelocity = beam.Direction:Resized(beam.BeamParameters.TechXSpeed)
                local origin = beam.TechXChain and beam.TechXGuideOrigin or beam.Laser.Position
                if beam.TechXGeometryFrame ~= frame then
                    local step = frame == beam.TechXBornFrame and 0 or beam.BeamParameters.TechXSpeed
                    beam.TechXDistance = beam.TechXChain and (beam.TechXDistance + step)
                        or math.min(beam.Distance, beam.TechXDistance + step)
                    beam.TechXGeometryFrame = frame
                end
                local center = origin + beam.Direction:Resized(math.min(beam.Distance, beam.TechXDistance))
                if beam.TechXChain then
                    if beam.TechXRailMaster then
                        beam.TechXRailLength = math.min(beam.Distance, beam.TechXDistance)
                        beam.TechXRailEndpoint = center
                        Mizuki.syncCannonTechXConnection(beam)
                    end
                    if not beam.TechXRingReleased and alive(beam.TechXRing) then
                        setGeometry(beam, origin, center, Vector.Zero)
                        if beam.TechXDistance > beam.Distance then beam.TechXRangeDetachRequested = true end
                    end
                else
                    -- Keep the stable ordinary tether positioning unchanged.
                    setGeometry(beam, origin, center, Vector.Zero)
                end

            end
        end
    end
end

-- Followers share a rail, never another ring's connector. The root remains
-- valid after its own ring has left range, so later shots cannot shorten it.
function Mizuki.syncCannonTechXRails(data)
    for side = 1, 2 do
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            if beam.TechXRailRingOnly and not beam.TechXReleased then
                beam.TechXRailRoot = Mizuki.findCannonTechXRail(data, side, beam.Cannon, beam.TechXChainLane)
                if not beam.TechXRailRoot then Mizuki.releaseCannonTechX(beam) end
            end
        end
    end
end

-- Walk the native sampled polyline by arc length, including homing/curvature.
-- PositionOffset is separate from the native collision-plane samples.
function Mizuki.getCannonTechXRailPoint(root, fraction)
    local laser = root.Laser
    local samples = laser:GetSamples()
    local lengths, total = {}, 0
    for index = 1, #samples - 1 do
        local length = (samples:Get(index) - samples:Get(index - 1)):Length()
        lengths[index], total = length, total + length
    end
    if total <= 0 then
        local origin = root.TechXGuideOrigin or laser.Position
        return origin + root.Direction:Resized((root.TechXRailLength or 0) * fraction), root.Direction
    end
    local remaining = math.max(0, math.min(1, fraction)) * total
    for index = 1, #samples - 1 do
        local length = lengths[index]
        if length > 0 and (remaining <= length or index == #samples - 1) then
            local direction = (samples:Get(index) - samples:Get(index - 1)):Resized(1)
            return samples:Get(index - 1) + direction * remaining, direction
        end
        remaining = remaining - length
    end
    return samples:Get(#samples - 1), root.Direction
end

local function placeRailRings(root)
    local length = root.TechXRailLength or 0
    for ring, record in pairs(rings) do
        local beam = record.Beam
        if beam and (beam == root or beam.TechXRailRoot == root)
            and not beam.TechXRingReleased and not beam.TechXSource and alive(ring) then
            local fraction = length > 0 and math.min(1, beam.TechXDistance / length) or 0
            local point, tangent = Mizuki.getCannonTechXRailPoint(root, fraction)
            ring.Position = copy(point)
            ring.PositionOffset = copy(root.Laser.PositionOffset)
            ring.Velocity = Vector.Zero
            beam.TechXFlightVelocity = tangent:Resized(beam.BeamParameters.TechXSpeed)
        end
    end
end

-- A held tether locks position/occupancy, not its aim. Only live original
-- volleys read player input; echoes continue replaying the captured movement.
function Mizuki.steerCannonTechX(data, aim)
    if not aim or aim:Length() == 0 then return end
    aim = aim:Normalized()
    for side = 1, 2 do
        local steering = false
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            if beam.TechXDriven and beam.TechXLinked and not beam.TechXReleased
                and not beam.Ending and not beam.PersistentEchoMode
                and (beam.TechXRailMaster or alive(beam.TechXRing)) then
                beam.TechXTargetDirection = aim:Rotated(beam.DirectionOffset or 0)
                steering = true
            end
        end
        local locked = steering and data.MizukiLockedCannonAims and data.MizukiLockedCannonAims[side]
        if locked then
            locked.PositionAim = copy(aim)
            for member in pairs(locked.MemberAims) do locked.MemberAims[member] = copy(aim) end
        end
    end
end

local function sideBusy(data, side)
    for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
        if beam.PersistentEchoMode ~= "automatic" and not beam.Ending
            and alive(beam.Laser) and (not beam.TechXDriven or not beam.TechXReleased) then return true end
    end
    return false
end

function Mizuki.updateCannonTechXInput(player, data, held, aim, profile, updateBeams, updatePose, fire, startBurst, updateBurst, continuous, hideChargeBar)
    local state = data.MizukiTechXInput
    if not state then state = {}; data.MizukiTechXInput = state end
    state.Continuous, state.HideChargeBar = continuous == true, hideChargeBar == true
    data.MizukiCharge = Mizuki.protectChargeRelease(state, held, data.MizukiCharge or 0)
    data.MizukiHasShootingInput = held
    if aim then data.MizukiCannonAim, data.MizukiAim = aim, aim end
    if held then Mizuki.steerCannonTechX(data, aim) end
    updateBeams(player, data, held, aim, false)
    updatePose(player, data)
    Mizuki.syncCannonTechXAttacks(data)
    Mizuki.syncCannonTechXRails(data)
    if updateBurst then updateBurst(player, data) end
    if held then
        local nextSide = -(data.MizukiShotSide or -1) == -1 and 1 or 2
        local tech2 = Mizuki.hasCannonTech2(player)
        local side = tech2 and 1 or state.Side or nextSide
        if not tech2 and not state.Continuous and sideBusy(data, side) then side = 3 - side end
        if not state.Continuous and sideBusy(data, side) then
            state.Side = nil
            data.MizukiCharge, data.MizukiChargeBarFullFrames = 0, nil
            Mizuki.protectChargeRelease(state, held, 0, true)
            return
        end
        state.Side = side
        data.MizukiCharge = math.min((data.MizukiCharge or 0) + 1, profile.MaxFrames)
        if data.MizukiCharge >= profile.MaxFrames and data.MizukiAim then
            if startBurst then
                startBurst(player, data, data.MizukiAim, data.MizukiCharge, profile, side)
            else
                fire(player, data.MizukiAim, data.MizukiCharge, false, side)
            end
            data.MizukiShotSide = side == 1 and -1 or 1
            state.Side = nil
            data.MizukiCharge, data.MizukiChargeBarFullFrames = 0, nil
            Mizuki.syncCannonTechXAttacks(data)
            Mizuki.syncCannonTechXRails(data)
        end
    else
        if state.Side and (data.MizukiCharge or 0) > 0 and data.MizukiAim then
            if startBurst then
                startBurst(player, data, data.MizukiAim, data.MizukiCharge, profile, state.Side)
            else
                fire(player, data.MizukiAim, data.MizukiCharge, false, state.Side)
            end
            data.MizukiShotSide = state.Side == 1 and -1 or 1
        end
        state.Side = nil
        data.MizukiCharge, data.MizukiChargeBarFullFrames, data.MizukiAim = 0, nil, nil
        Mizuki.protectChargeRelease(state, false, 0, true)
    end
end

-- Finite echoes read the source's complete relative geometry and release age.
-- They have no input, real-side occupancy, or independent release decision.
function Mizuki.updateCannonTechXReplay(child, frame)
    local source, ring = child.TechXSource, child.TechXRing
    local age = frame - child.StartFrame
    if source.TechXEndAge and age >= source.TechXEndAge then
        Mizuki.cancelCannonTechX(child)
        Mizuki.releaseCannonTechX(child)
        return
    end
    local ringReleaseDue = source.TechXRingReleaseAge and age >= source.TechXRingReleaseAge
    local releaseDue = source.TechXReleaseAge and age >= source.TechXReleaseAge
    if releaseDue and not source.TechXChain then
        child.TechXFlightVelocity = copy(source.TechXFlightVelocity)
        Mizuki.releaseCannonTechX(child)
        return
    end
    if child.TechXLinked and not child.TechXReleased and (alive(ring) or child.TechXRailMaster) then
        local ages = source.TechXFrameAges
        local low, high, chosen = 1, #ages, nil
        while low <= high do
            local middle = math.floor((low + high) / 2)
            if ages[middle] <= age then chosen, low = middle, middle + 1
            else high = middle - 1 end
        end
        local sample = chosen and source.TechXFrames[ages[chosen]]
        if sample then
            local origin = child.BeamParameters.Origin
            if child.TechXRailMaster and sample.RailEndpoint then
                child.TechXGuideOrigin = origin + sample.Origin
                child.TechXRailEndpoint = origin + sample.RailEndpoint
                Mizuki.syncCannonTechXConnection(child)
            end
            if not child.TechXRingReleased then
                setGeometry(child, origin + sample.Origin, origin + sample.Center, sample.Velocity)
            end
            if sample.RingOffset and alive(ring) and not child.TechXRingReleased then
                ring.PositionOffset = copy(sample.RingOffset)
            end
            if sample.FlightVelocity then child.TechXFlightVelocity = copy(sample.FlightVelocity) end
        end
        child.Laser.Timeout = child.ActiveDuration
        if not child.TechXRingReleased and alive(ring) then ring:SetTimeout(-1) end
    end
    if ringReleaseDue then releaseRing(child) end
    if releaseDue then
        child.TechXFlightVelocity = copy(source.TechXFlightVelocity)
        Mizuki.releaseCannonTechX(child)
    end
end

-- Native laser rendering consumes the path in GetSamples, not a newly read
-- Entity.Position (isaac-ng.exe 0x978981..0x978AD5). PositionOffset is applied
-- separately (0x978971..0x9789D2). Read the center of that actual circular path.
function Mizuki.getCannonTechXDrawCenter(ring)
    local samples = ring:GetSamples()
    if #samples < 4 then return ring.Position + ring.PositionOffset end
    local first = samples:Get(0)
    local minX, maxX, minY, maxY = first.X, first.X, first.Y, first.Y
    for index = 1, #samples - 1 do
        local point = samples:Get(index)
        minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
        minY, maxY = math.min(minY, point.Y), math.max(maxY, point.Y)
    end
    return Vector((minX + maxX) * 0.5, (minY + maxY) * 0.5) + ring.PositionOffset
end

-- This pass reads final native positions; it never moves the ring. Include
-- each entity's visual offset so collision-plane and render-plane differences
-- cannot leave the connector beside the visible ring center.
function Mizuki.syncCannonTechXConnection(beam)
    if not beam.TechXLinked or beam.TechXReleased or beam.TechXRailRingOnly
        or not alive(beam.Laser) or (not beam.TechXRailMaster and not alive(beam.TechXRing)) then return end
    local ring, laser = beam.TechXRing, beam.Laser
    local center
    if beam.TechXRailMaster then
        if not beam.TechXRailEndpoint then return end
        laser.Position = copy(beam.TechXGuideOrigin)
        center = beam.TechXRailEndpoint + laser.PositionOffset
    else
        center = Mizuki.getCannonTechXDrawCenter(ring)
    end
    local origin = laser.Position + laser.PositionOffset
    local delta = center - origin
    if delta:Length() > 0 then
        local angle = delta:GetAngleDegrees()
        laser.AngleDegrees, laser.LastAngleDegrees = angle, angle
    end
    -- FireTechLaser advances its native path start beyond Entity.Position.
    -- LaserLength/MaxDistance describe the span from that advanced start, not
    -- the distance from Entity.Position. Measure the offset after native update.
    local distance = math.max(1, delta:Length() - (beam.TechXNativeStartOffset or 0))
    laser:SetMaxDistance(distance)
    -- The native update already cached these before this final positioning pass.
    -- Refresh the public endpoint/length too, instead of leaving a frame-old ray.
    laser.EndPoint = copy(center - laser.PositionOffset)
    laser.LaserLength = distance
end

Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE, function(_, laser)
    local beam = laser:GetData().MizukiTechXConnection
    if not beam or beam.TechXReleased then return end
    if beam.TechXRailMaster and not beam.TechXSource then placeRailRings(beam) end
    local samples = laser:GetSamples()
    if #samples > 0 then
        beam.TechXNativeStartOffset = (samples:Get(0) - laser.Position):Length()
    end
end)

-- Preserve ordinary tether draw order, and the leading circle while it is
-- still attached. Followers do not own a separate connector.
function Mizuki.prepareCannonTechXDrawOrder(beam)
    if beam.TechXLinked and not beam.TechXReleased and not beam.TechXRailRingOnly
        and not beam.TechXRingReleased and alive(beam.TechXRing) and alive(beam.Laser) then
        local laser, ring = beam.Laser, beam.TechXRing
        if beam.TechXFreeDepthOffset == nil then beam.TechXFreeDepthOffset = ring.DepthOffset end
        ring.DepthOffset = laser.Position.Y + laser.DepthOffset - ring.Position.Y - 1
    end
end

local function recordFinalGeometry(beam, frame)
    if beam.TechXSource then return end -- Echoes consume the original history.
    local origin, ring = beam.Laser.Position, beam.TechXRing
    local age = frame - beam.TechXBornFrame
    local sample = { Origin = copy(origin - beam.TechXInitialOrigin),
        Center = copy((alive(ring) and ring.Position or beam.TechXInitialOrigin) - beam.TechXInitialOrigin),
        Velocity = copy(alive(ring) and ring.Velocity or Vector.Zero),
        RailEndpoint = beam.TechXRailEndpoint and copy(beam.TechXRailEndpoint - beam.TechXInitialOrigin),
        RingOffset = copy(alive(ring) and ring.PositionOffset or beam.Laser.PositionOffset), FlightVelocity = copy(beam.TechXFlightVelocity) }
    local ages = beam.TechXFrameAges
    local previous = beam.TechXFrames[ages[#ages]]
    local changed = not previous
    for _, name in ipairs({"Origin", "Center", "Velocity", "RingOffset", "FlightVelocity", "RailEndpoint"}) do
        if sample[name] then
            changed = changed or not previous or not previous[name]
                or previous[name].X ~= sample[name].X or previous[name].Y ~= sample[name].Y
        end
    end
    if changed then
        if ages[#ages] ~= age then ages[#ages + 1] = age end
        beam.TechXFrames[age] = sample
    end
end

-- After player/familiar/native laser positioning AND the echo replay pass.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.LATE, function()
    if Game():IsPaused() then return end
    local frame = Game():GetFrameCount()
    for root in pairs(rails) do
        if not alive(root.Laser) then
            rails[root] = nil
        elseif not root.TechXReleased then
            Mizuki.syncCannonTechXConnection(root)
            if not root.TechXSource then placeRailRings(root) end
            recordFinalGeometry(root, frame)
        end
    end
    for ring, record in pairs(rings) do
        if not alive(ring) or ring.InitSeed ~= record.Seed then
            if record.Beam and not record.Beam.TechXRailMaster then
                record.Beam.TechXEndAge = frame - record.Beam.TechXBornFrame
            end
            rings[ring] = nil
        elseif not alive(record.Player) or record.Player:IsDead() then
            if ring:GetData().MizukiCannonTechXRing == true then ring:Remove() end
            rings[ring] = nil
        else
            local beam = record.Beam
            if beam and beam.TechXLinked and not beam.TechXReleased and alive(beam.Laser) then
                Mizuki.prepareCannonTechXDrawOrder(beam)
                Mizuki.syncCannonTechXConnection(beam)
                recordFinalGeometry(beam, frame)
                if beam.TechXRangeDetachRequested then
                    beam.TechXRangeDetachRequested = nil
                    if beam.TechXRailMaster then releaseRing(beam)
                    else Mizuki.releaseCannonTechX(beam) end
                end
            end
        end
    end
end)

-- Ordinary tethers still connect to the completed circle pass. Continuous
-- rails instead use their independent endpoint; no circle can shorten them.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER, CallbackPriority.LATE, function(_, laser)
    local data = laser:GetData()
    local beam = data.MizukiCannonTechXRing == true and data.MizukiTechXTether
    if beam then Mizuki.syncCannonTechXConnection(beam) end
end)

local function reset()
    for ring, record in pairs(rings) do
        if alive(ring) and ring:GetData().MizukiCannonTechXRing == true then ring:Remove() end
    end
    rings, rails = {}, {}
    for index = 0, Game():GetNumPlayers() - 1 do
        local data = Isaac.GetPlayer(index):GetData()
        data.MizukiTechXInput = nil
        data.MizukiTechXCursedEyeBursts = nil
    end
end
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, reset)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, reset)
