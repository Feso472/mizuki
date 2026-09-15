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
local EPIC_FETUS_COOLDOWN_MULTIPLIER = 2

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

local function updateEpicFetusStrike(player, data)
    local cooldown = data.MizukiEpicFetusCooldown or 0
    if cooldown > 0 then
        data.MizukiEpicFetusCooldown = cooldown - 1
    end

    local strike = data.MizukiEpicFetusStrike
    if not strike then return end

    local target = strike.Target
    if not target or not target:Exists() then
        if strike.Locked then beginEpicFetusCooldown(player, data) end
        data.MizukiEpicFetusStrike = nil
        return
    end

    if not strike.Locked then
        local enemy = strike.Enemy
        if enemy and enemy:Exists() and not enemy:IsDead() then
            target.Position = Vector(enemy.Position.X, enemy.Position.Y)
        end

        strike.TrackFrames = strike.TrackFrames - 1
        if strike.TrackFrames <= 0 then
            spawnEpicFetusRocket(player, strike)
        end
        return
    end

    -- TARGET normally remains player-controlled. Once this strike locks, pin
    -- it every frame so its native update cannot move the confirmed landing
    -- point before the rocket arrives.
    target.Position = strike.LockedPosition
    target.Velocity = Vector.Zero

    if not strike.Rocket or not strike.Rocket:Exists() then
        data.MizukiEpicFetusStrike = nil
        beginEpicFetusCooldown(player, data)
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

    -- Door cells sit on the room boundary and are not always returned by
    -- GetGridEntityFromPos at the hit point. Check closed doors separately so
    -- the missile can still serve as a bomb for opening them.
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door and not door:IsOpen()
            and (door.Position - hitPosition):LengthSquared() <= 30 * 30
        then
            return Vector(door.Position.X, door.Position.Y), hitDistance
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
    if data.MizukiEpicFetusStrike
        or (data.MizukiEpicFetusCooldown or 0) > 0
    then
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
    local target = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.TARGET,
        0,
        position,
        Vector.Zero,
        player
    ):ToEffect()
    target.Timeout = EPIC_FETUS_TRACK_FRAMES + EPIC_FETUS_FALL_FRAMES

    player:GetData().MizukiEpicFetusStrike = {
        Target = target,
        Enemy = enemy,
        TrackFrames = EPIC_FETUS_TRACK_FRAMES,
        Locked = false,
    }
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
Mizuki.startEpicFetusStrike = startEpicFetusStrike
Mizuki.updateEpicFetusStrike = updateEpicFetusStrike
