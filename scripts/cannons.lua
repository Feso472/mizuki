-- Shared cannon controls and native contact damage.

-- region Deployment controls
do
    -- Double-tap auto-fire deployment and recall. This is a separate Lua
    -- chunk so these helpers do not consume main.lua's top-level local budget.

    local DOUBLE_TAP_WINDOW_FRAMES = 9
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

        local state = data.MizukiCannonAutoFireState
        if state == "deployed" then
            data.MizukiCannonAutoFireState = "returning"
            data.MizukiCannonAutoFirePositions = nil
            data.MizukiCannonAutoFireLastTapFrame = nil
            data.MizukiCharge = 0
            data.MizukiNeptunusHeldFrames = nil
            data.MizukiAim = nil
            data.MizukiChargeBarFullFrames = nil
            data.MizukiCursedEyeBurst = nil
            data.MizukiCannonAim = Vector(0, -1)
            return
        end
        if state == "returning" then return end

        local frame = Game():GetFrameCount()
        local previousTap = data.MizukiCannonAutoFireLastTapFrame
        if previousTap and frame - previousTap <= DOUBLE_TAP_WINDOW_FRAMES then
            local positions = { {}, {} }
            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side] or {}) do
                    if cannon and cannon:Exists()
                        and not cannon:GetData().MizukiAwaitingInitialLayout
                    then
                        positions[side][member] = Vector(
                            cannon.Position.X, cannon.Position.Y
                        )
                    end
                end
            end
            data.MizukiCannonAutoFireState = "deployed"
            data.MizukiCannonAutoFirePositions = positions
            data.MizukiCannonAutoFireLastTapFrame = nil
        else
            data.MizukiCannonAutoFireLastTapFrame = frame
        end
    end

    function Mizuki.finishCannonAutoFireReturn(player, data)
        if data.MizukiCannonAutoFireState ~= "returning" then return end
        for side = 1, 2 do
            local beams = data.MizukiActiveBeams and data.MizukiActiveBeams[side]
            if beams and #beams > 0 then return end
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
-- endregion Deployment controls

-- region Contact damage
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
            or cannonData.MizukiIsIdle
            or not player or not player:Exists()
            or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
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
        local interval = math.max(player.MaxFireDelay, 1) + 1
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

    Mizuki:AddCallback(
        ModCallbacks.MC_PRE_FAMILIAR_COLLISION,
        Mizuki.DamageOnCannonCollision,
        Mizuki.CannonVariant
    )
end
-- endregion Contact damage
