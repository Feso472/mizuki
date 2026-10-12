-- Held shooting remains independent of the primary weapon's releases.
-- Native timing: one 1/3 roll per eight logic frames, including failed rolls.
-- Tech .5 is the player's forehead weapon and never enters cannon/fan echoes.
function Mizuki:UpdateTech5(player)
    if not Mizuki.isMizuki(player) or Game():IsPaused() or player:IsDead()
        or not player:AreControlsEnabled() or not player:IsExtraAnimationFinished()
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_5) then return end
    local data, frame = player:GetData(), Game():GetFrameCount()
    local parameters = Mizuki.WeaponParameters.Tech5
    if data.MizukiTech5NextRollFrame and frame < data.MizukiTech5NextRollFrame then return end
    local shooting, direction, target = Mizuki.getTech5Input(player)
    if not shooting then return end
    data.MizukiTech5NextRollFrame = frame + parameters.RollIntervalFrames
    if player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_TECH_5):RandomInt(parameters.RollRandomBound) ~= 0 then return end
    -- Offset 2 owns the native forehead origin and Repentance+ 5% random-effect
    -- branch. Do not reroll, replace flags/colors, or turn this into a cannon beam.
    local head = Mizuki.getGuillotineHeads(player)[1]
    -- FireTechLaser itself adds TearsOffset, including native Guillotine
    -- displacement. Cancel it in the requested origin instead of adding twice.
    local origin = head and (head.Position - player.TearsOffset) or player.Position
    local laser = player:FireTechLaser(origin, LaserOffset.LASER_TECH5_OFFSET,
        direction, false, true, player, 1)
    -- Native samples enter their fade around age 2 and disappear at age 4-5.
    -- Set only the active timeout; the engine owns the fade and removal.
    laser.Timeout = parameters.ActiveFrames
    -- Raise Tech .5's native forehead beam by two screen pixels.
    laser.PositionOffset = laser.PositionOffset + Vector(0, -2)
    if target then
        -- Point from the actual native forehead origin, not the ground center.
        local offset = target - laser.Position
        if offset:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            laser.AngleDegrees = offset:GetAngleDegrees()
        end
    end
    local laserData = laser:GetData()
    laserData.MizukiTech5, laserData.MizukiBeamOwner = true, player
    if head then
        -- The player remains the native attack source. Only the moving origin
        -- follows the head; disable the engine's body-parent repositioning.
        laser.DisableFollowParent = true
        laserData.MizukiTech5OriginHead = head
        laserData.MizukiTech5OriginHeadSeed = head.InitSeed
        laserData.MizukiTech5HeadOffset = laser.Position - head.Position
        laser.Velocity = Vector(head.Velocity.X, head.Velocity.Y)
    end
end

function Mizuki:UpdateTech5HeadOrigin(laser)
    local data = laser:GetData()
    if not data.MizukiTech5 then return end
    local head = data.MizukiTech5OriginHead
    if not head or not head:Exists() or head.InitSeed ~= data.MizukiTech5OriginHeadSeed then return end
    laser.Position = head.Position + data.MizukiTech5HeadOffset
    laser.Velocity = Vector(head.Velocity.X, head.Velocity.Y)
end

-- Registered after UpdateWeapon; this remains independent of all early exits.
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateTech5)
Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, Mizuki.UpdateTech5HeadOrigin)
