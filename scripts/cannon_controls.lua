-- Stationary hover and double-tap auto-fire input. This is a separate Lua
-- chunk so these helpers do not consume main.lua's top-level local budget.

local function getCannonGroundAim(player, cannonPosition)
    -- The body is raised above its ground projection by the attack height.
    -- Visual bob and sprite pivot do not affect this aiming geometry.
    local groundPosition = cannonPosition + Vector(
        0,
        Mizuki.CANNON_ATTACK_ORBIT_HEIGHT * player.SpriteScale.Y
    )
    local direction = groundPosition - player.Position
    return direction:Length() > 0.01
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

function Mizuki.updateCannonHoverInput(player, data)
    if not player:AreControlsEnabled() then return end
    local pressed = Input.IsActionPressed(
        ButtonAction.ACTION_DROP,
        player.ControllerIndex
    )
    local heldFrames = data.MizukiCannonHoverHeldFrames
    if pressed then
        heldFrames = (heldFrames or 0) + 1
        data.MizukiCannonHoverHeldFrames = heldFrames
        if heldFrames == 10 then
            data.MizukiCannonHoverTemporary = true
            data.MizukiCannonHoverPositions = nil
        end
    elseif heldFrames then
        if heldFrames < 10 then
            data.MizukiCannonHoverToggled =
                not data.MizukiCannonHoverToggled
        end
        data.MizukiCannonHoverHeldFrames = nil
        data.MizukiCannonHoverTemporary = nil
        data.MizukiCannonHoverPositions = nil
    end
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
    if previousTap and frame - previousTap <= 9 then
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
        data.MizukiCannonHoverToggled = nil
        data.MizukiCannonHoverTemporary = nil
        data.MizukiCannonHoverPositions = nil
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
                ) > 10 then
                    return
                end
            end
        end
    end
    data.MizukiCannonAutoFireState = nil
end
