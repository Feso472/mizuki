-- Epic Fetus target handling plus the radial beam helper the multishot code
-- uses.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local IMMACULATE_HEART_FALLING_ACCELERATION = Mizuki.IMMACULATE_HEART_FALLING_ACCELERATION
local LEAD_PENCIL_BLOOD_CLOT_COLOR = Mizuki.LEAD_PENCIL_BLOOD_CLOT_COLOR
local isMizuki = Mizuki.isMizuki
local tryFireImmaculateHeartTear = Mizuki.tryFireImmaculateHeartTear
local advanceLeadPencil = Mizuki.advanceLeadPencil

-- FireTechLaser creates the same native Technology laser used by the player
-- weapon system, including its tear-size initialization and firing sound.
local EPIC_FETUS_TRACK_FRAMES = 35
local EPIC_FETUS_FALL_FRAMES = 10
local EPIC_FETUS_COOLDOWN_MULTIPLIER = 3
local EPIC_FETUS_MAX_ACTIVE_STRIKES = 16
local EPIC_FETUS_GRID_HALF_SIZE = 20
local EPIC_FETUS_RING_MIN_THICKNESS = 10

local function getEpicFetusStrikes(data)
    local strikes = data.MizukiEpicFetusStrikes
    if not strikes then
        strikes = {}
        data.MizukiEpicFetusStrikes = strikes
    end

    -- Preserve an in-flight strike across a Lua hot reload from the old
    -- single-strike implementation, then retire the ambiguous legacy field.
    local legacyStrike = data.MizukiEpicFetusStrike
    if legacyStrike then
        strikes[#strikes + 1] = legacyStrike
        data.MizukiEpicFetusStrike = nil
    end
    return strikes
end

local function spawnEpicFetusRocket(player, strike)
    local target = strike.Target
    if not target or not target:Exists() then return end

    strike.Locked = true
    strike.Enemy = nil
    strike.LockedPosition = Vector(target.Position.X, target.Position.Y)
    target.Position = strike.LockedPosition
    target.Velocity = Vector.Zero

    local rocket = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.ROCKET,
        0,
        target.Position,
        Vector.Zero,
        player
    ):ToEffect()
    rocket.Parent = target
    rocket.Timeout = EPIC_FETUS_FALL_FRAMES
    strike.Rocket = rocket
end

local function beginEpicFetusCooldown(player, data)
    data.MizukiEpicFetusCooldown = math.max(
        0,
        math.ceil(
            (player.MaxFireDelay + 1)
                * EPIC_FETUS_COOLDOWN_MULTIPLIER
        )
    )
end

local function canStartEpicFetusStrike(data)
    return (data.MizukiEpicFetusCooldown or 0) <= 0
        and #getEpicFetusStrikes(data) < EPIC_FETUS_MAX_ACTIVE_STRIKES
end

local function updateEpicFetusStrikes(player, data)
    local cooldown = data.MizukiEpicFetusCooldown or 0
    if cooldown > 0 then
        data.MizukiEpicFetusCooldown = math.max(0, cooldown - 1)
    end

    local strikes = getEpicFetusStrikes(data)
    for index = #strikes, 1, -1 do
        local strike = strikes[index]
        local target = strike.Target
        if not target or not target:Exists() then
            table.remove(strikes, index)
        elseif not strike.Locked then
            local enemy = strike.Enemy
            if enemy and enemy:Exists() and not enemy:IsDead() then
                target.Position = Vector(enemy.Position.X, enemy.Position.Y)
            end

            strike.TrackFrames = strike.TrackFrames - 1
            if strike.TrackFrames <= 0 then
                spawnEpicFetusRocket(player, strike)
            end
        else
            -- TARGET normally remains player-controlled. Once this strike
            -- locks, pin it every frame so its native update cannot move the
            -- confirmed landing point before the rocket arrives.
            target.Position = strike.LockedPosition
            target.Velocity = Vector.Zero

            if not strike.Rocket or not strike.Rocket:Exists() then
                table.remove(strikes, index)
            end
        end
    end
end

local function getMizukiBeamOwnerFromDamageSource(source)
    local entity = source and source.Entity
    if not entity then return nil end

    local player = entity:ToPlayer()
    if player and isMizuki(player) then return player end

    local laser = entity:ToLaser()
    if laser then
        local owner = laser:GetData().MizukiBeamOwner
        if owner and owner:Exists() and isMizuki(owner) then return owner end
    end

    local familiar = entity:ToFamiliar()
    if familiar and familiar.Variant == Mizuki.CannonVariant then
        local owner = familiar.Player
        if owner and owner:Exists() and isMizuki(owner) then return owner end
    end

    return nil
end

local EPIC_FETUS_GRID_TARGET_TYPES = {
    [GridEntityType.GRID_ROCK] = true,
    [GridEntityType.GRID_ROCKB] = true,
    [GridEntityType.GRID_ROCKT] = true,
    [GridEntityType.GRID_ROCK_BOMB] = true,
    [GridEntityType.GRID_ROCK_ALT] = true,
    [GridEntityType.GRID_ROCK_SS] = true,
    [GridEntityType.GRID_LOCK] = true,
    [GridEntityType.GRID_TNT] = true,
    [GridEntityType.GRID_POOP] = true,
    [GridEntityType.GRID_STATUE] = true,
}

local function getEpicFetusDoorSlotTarget(room, slot)
    local door = room:GetDoor(slot)
    local isClosedDoor = door
        and (not door:IsOpen() or door:CanBlowOpen())
    if not room:IsDoorSlotAllowed(slot)
        or (door and not isClosedDoor)
    then
        return nil
    end

    -- Empty valid slots deliberately remain targets. Treating them differently
    -- from an undiscovered secret-room door would reveal the hidden connection.
    local slotPosition = door and door.Position
        or room:GetDoorSlotPosition(slot)
    return room:GetClampedPosition(slotPosition, 0)
end

local function getEpicFetusGridTarget(laser)
    local room = Game():GetRoom()
    local endpoint = laser:GetEndPoint()
    local direction = Vector.FromAngle(laser.AngleDegrees)
    local endpointDistance = (endpoint - laser.Position):Length()
    -- Vanilla uses this query for Technology and Robo-Baby. It returns the
    -- first poop, TNT, rock or wall reached by the straight laser ray.
    local hitPosition = room:GetLaserTarget(laser.Position, direction)
    local hitDistance = (hitPosition - laser.Position):Length()
    if hitDistance > endpointDistance + 30 then return nil end

    -- The returned hit point can sit on either side of the grid boundary.
    -- Probe a small distance into the obstruction to resolve its actual cell.
    local probeOffsets = { 0, 5, 10, 20, 30, -5 }
    for _, offset in ipairs(probeOffsets) do
        local position = hitPosition + direction * offset
        local grid = room:GetGridEntityFromPos(position)
        if grid and EPIC_FETUS_GRID_TARGET_TYPES[grid:GetType()] then
            return Vector(grid.Position.X, grid.Position.Y), hitDistance
        end
    end

    -- Door slots sit on the room boundary and are not returned by the grid
    -- probe. Empty valid slots intentionally behave like hidden doors.
    for slot = 0, 7 do
        local position = getEpicFetusDoorSlotTarget(room, slot)
        if position
            and (position - hitPosition):LengthSquared() <= 30 * 30
        then
            return position, hitDistance
        end
    end

    -- Walls and all non-physical floor grids intentionally fall through.
    return nil
end

local function queueEpicFetusGridTarget(laser)
    local laserData = laser:GetData()
    local player = laserData.MizukiBeamOwner
    if not player
        or not player:Exists()
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
    then
        return
    end

    local data = player:GetData()
    if not canStartEpicFetusStrike(data) then
        data.MizukiEpicFetusGridCandidate = nil
        return
    end

    local position, distance = getEpicFetusGridTarget(laser)
    if not position then return end

    local candidate = data.MizukiEpicFetusGridCandidate
    if not candidate or distance < candidate.Distance then
        data.MizukiEpicFetusGridCandidate = {
            Position = position,
            Distance = distance,
            Frame = Game():GetFrameCount(),
        }
    end
end

local function startEpicFetusStrike(player, enemy, position)
    local data = player:GetData()
    if not canStartEpicFetusStrike(data) then return false end

    local target = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.TARGET,
        0,
        position,
        Vector.Zero,
        player
    ):ToEffect()
    target.Timeout = EPIC_FETUS_TRACK_FRAMES + EPIC_FETUS_FALL_FRAMES

    local strikes = getEpicFetusStrikes(data)
    strikes[#strikes + 1] = {
        Target = target,
        Enemy = enemy,
        TrackFrames = EPIC_FETUS_TRACK_FRAMES,
        Locked = false,
    }
    -- Fire rate controls the interval between strike starts. The previous
    -- missile may still be tracking or falling when this cooldown expires.
    beginEpicFetusCooldown(player, data)
    return true
end

local function queueLudovicoEpicFetusEnemy(player, enemy, fromCannon)
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then
        return
    end

    local data = player:GetData()
    if not canStartEpicFetusStrike(data) then
        data.MizukiEpicFetusLudovicoCandidate = nil
        return
    end

    local frame = Game():GetFrameCount()
    local priority = fromCannon and 4 or 3
    local candidate = data.MizukiEpicFetusLudovicoCandidate
    if not candidate
        or candidate.Frame ~= frame
        or priority > candidate.Priority
    then
        data.MizukiEpicFetusLudovicoCandidate = {
            Enemy = enemy,
            EnemyInitSeed = enemy.InitSeed,
            EnemyPtrHash = GetPtrHash(enemy),
            Priority = priority,
            Frame = frame,
        }
    end
end

local function captureLudovicoEpicFetusGeometry(
    player,
    ring,
    cannonHitboxes
)
    local data = player:GetData()
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
        or not canStartEpicFetusStrike(data)
    then
        data.MizukiEpicFetusLudovicoGeometry = nil
        return
    end

    local cannons = {}
    for _, hitbox in ipairs(cannonHitboxes) do
        cannons[#cannons + 1] = {
            Position = Vector(hitbox.Position.X, hitbox.Position.Y),
            Radius = hitbox.Radius,
        }
    end
    data.MizukiEpicFetusLudovicoGeometry = {
        Frame = Game():GetFrameCount(),
        RingPosition = Vector(ring.Position.X, ring.Position.Y),
        RingRadius = ring.Radius and ring.Radius > 0
            and ring.Radius
            or 60,
        RingThickness = math.max(
            ring.Size or 0,
            EPIC_FETUS_RING_MIN_THICKNESS
        ),
        Cannons = cannons,
    }
end

local function considerLudovicoGridPosition(
    candidate,
    contactPosition,
    geometry
)
    for _, cannon in ipairs(geometry.Cannons) do
        local overlap = contactPosition:Distance(cannon.Position)
            - cannon.Radius
            - EPIC_FETUS_GRID_HALF_SIZE
        if overlap <= 0
            and (not candidate
                or candidate.Priority < 2
                or candidate.Priority == 2 and overlap < candidate.Distance)
        then
            candidate = {
                Position = Vector(contactPosition.X, contactPosition.Y),
                Priority = 2,
                Distance = overlap,
            }
        end
    end

    local ringDistance = contactPosition:Distance(geometry.RingPosition)
    local ringOverlap = math.abs(ringDistance - geometry.RingRadius)
        - geometry.RingThickness
        - EPIC_FETUS_GRID_HALF_SIZE
    if ringOverlap <= 0
        and (not candidate
            or candidate.Priority < 1
            or candidate.Priority == 1 and ringOverlap < candidate.Distance)
    then
        candidate = {
            Position = Vector(contactPosition.X, contactPosition.Y),
            Priority = 1,
            Distance = ringOverlap,
        }
    end
    return candidate
end

local function getLudovicoEpicFetusGridCandidate(geometry)
    local room = Game():GetRoom()
    local candidate = nil
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid
            and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
            and EPIC_FETUS_GRID_TARGET_TYPES[grid:GetType()]
        then
            candidate = considerLudovicoGridPosition(
                candidate,
                grid.Position,
                geometry
            )
        end
    end

    for slot = 0, 7 do
        local contactPosition = getEpicFetusDoorSlotTarget(room, slot)
        if contactPosition then
            candidate = considerLudovicoGridPosition(
                candidate,
                contactPosition,
                geometry
            )
        end
    end
    return candidate
end

local function getLudovicoEpicFetusCandidate(player, frame)
    local data = player:GetData()
    local enemyCandidate = data.MizukiEpicFetusLudovicoCandidate
    local geometry = data.MizukiEpicFetusLudovicoGeometry
    data.MizukiEpicFetusLudovicoCandidate = nil
    data.MizukiEpicFetusLudovicoGeometry = nil

    if enemyCandidate and enemyCandidate.Frame == frame then
        local enemy = enemyCandidate.Enemy
        if enemy
            and enemy:Exists()
            and enemy.InitSeed == enemyCandidate.EnemyInitSeed
            and GetPtrHash(enemy) == enemyCandidate.EnemyPtrHash
        then
            return enemy, Vector(enemy.Position.X, enemy.Position.Y)
        end
    end

    if geometry and geometry.Frame == frame then
        local gridCandidate = getLudovicoEpicFetusGridCandidate(geometry)
        if gridCandidate then
            return nil, gridCandidate.Position
        end
    end
    return nil, nil
end

local function appendCenteredBeamAngles(angles, center, count, totalSpread)
    if count <= 1 then
        table.insert(angles, center)
        return
    end

    local step = totalSpread / (count - 1)
    for index = 1, count do
        -- This single expression centers odd and even counts alike: odd counts
        -- include zero, while even counts straddle zero by half a step.
        local centeredIndex = index - (count + 1) / 2
        table.insert(angles, center + centeredIndex * step)
    end
end



Mizuki.appendCenteredBeamAngles = appendCenteredBeamAngles
Mizuki.getMizukiBeamOwnerFromDamageSource = getMizukiBeamOwnerFromDamageSource
Mizuki.queueEpicFetusGridTarget = queueEpicFetusGridTarget
Mizuki.canStartEpicFetusStrike = canStartEpicFetusStrike
Mizuki.queueLudovicoEpicFetusEnemy = queueLudovicoEpicFetusEnemy
Mizuki.captureLudovicoEpicFetusGeometry =
    captureLudovicoEpicFetusGeometry
Mizuki.getLudovicoEpicFetusCandidate = getLudovicoEpicFetusCandidate
Mizuki.startEpicFetusStrike = startEpicFetusStrike
Mizuki.updateEpicFetusStrikes = updateEpicFetusStrikes
