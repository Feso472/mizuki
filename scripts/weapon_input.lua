-- Shooting intent, aim and shared charging rules.
local Config = Mizuki.Config

function Mizuki.getFireInterval(player)
    return math.max(Mizuki.RuntimeParameters.MinimumFireInterval, player.MaxFireDelay + 1)
end

function Mizuki.getChargeProfile(player, rawChargeItems, automaticOverride)
    -- Input advances in whole logical frames, but MaxFireDelay may be
    -- fractional. Keep the unrounded duration for damage interpolation and use
    -- the ceiling only for the first frame on which a charge is considered full.
    local baseChargeFrames = Mizuki.getFireInterval(player)
    local baseFrames = math.max(1, math.ceil(baseChargeFrames))
    local minMultiplier = 0.50
    local maxMultiplier = 1
    local automatic = automaticOverride == true or (automaticOverride == nil
        and not rawChargeItems and Mizuki.usesAutomaticBeam(player))
    local hasChocolateMilk = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CHOCOLATE_MILK
    ) and not automatic

    local hasCursedEye = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CURSED_EYE
    ) and not automatic

    -- Each item owns its charge range. When both are present, keep the longer
    -- range instead of multiplying them: Chocolate Milk reaches maximum damage
    -- at 2.5x base charge while Cursed Eye reaches five shots at 2x.
    if hasChocolateMilk then
        maxMultiplier = math.max(
            maxMultiplier,
            Config.CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER
        )
    end
    if hasCursedEye then
        maxMultiplier = math.max(
            maxMultiplier,
            Config.CURSED_EYE_MAX_CHARGE_MULTIPLIER
        )
    end

    return {
        BaseFrames = baseFrames,
        BaseChargeFrames = baseChargeFrames,
        MaxChargeMultiplier = maxMultiplier,
        -- Every Mizuki Mom's Knife route may release after the first held
        -- input frame. Keep the full-charge duration and native charge ratio.
        MinFrames = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) and 1
            or (hasChocolateMilk and Mizuki.WeaponParameters.ChocolateMilkMinChargeFrames
                or math.max(1, math.ceil(baseFrames * minMultiplier))),
        MaxFrames = math.max(1, math.ceil(baseChargeFrames * maxMultiplier)),
        HasChocolateMilk = hasChocolateMilk,
    }
end

function Mizuki.getChargeDamageMultiplier(charge, profile)
    if not profile.HasChocolateMilk then
        local chargeRange = math.max(
            1,
            profile.BaseFrames - profile.MinFrames
        )
        local normalizedCharge = math.max(
            0,
            math.min(
                1,
                (math.min(charge, profile.BaseFrames) - profile.MinFrames)
                    / chargeRange
            )
        )
        return Config.MIN_CHARGE_DAMAGE_MULTIPLIER
            + (1 - Config.MIN_CHARGE_DAMAGE_MULTIPLIER) * normalizedCharge
    end

    -- Vanilla Chocolate Milk scales charge linearly to 400%. The beam variant
    -- keeps that timing but caps each native damage tick at 250% instead.
    return math.min(
        charge / profile.BaseChargeFrames,
        Config.CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER
    )
end

function Mizuki.getCursedEyeShotCount(player, charge, profile)
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        or Mizuki.usesAutomaticBeam(player)
    then
        return 1
    end
    if not profile.HasChocolateMilk then
        return charge >= profile.MaxFrames and Mizuki.WeaponParameters.CursedEyeFullChargeShots or 1
    end

    -- Match the observed shot counts to the visible Chocolate Milk charge bar.
    local shotCount = 1
    for _, fraction in ipairs(Config.CURSED_EYE_CHOCOLATE_SHOT_THRESHOLDS) do
        local threshold = math.ceil(profile.MaxFrames * fraction)
        if charge >= threshold then
            shotCount = shotCount + 1
        end
    end
    return shotCount
end

function Mizuki.getDisplayedFireRate(player)
    return Mizuki.RuntimeParameters.LogicFramesPerSecond / Mizuki.getFireInterval(player)
end

function Mizuki.usesAutomaticBeam(player, swordShooting)
    if not swordShooting and Mizuki.usesCannonSpiritSword(player) then return false end
    if Mizuki.isBerserkClubActive(player) then return false end
    if Mizuki.usesCannonTechX(player) then return false end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
    then
        return true
    end

    -- These weapons have no sustained-beam transition from high fire rate.
    for _, collectible in ipairs(Config.AUTOMATIC_BEAM_RATE_EXCLUSIONS) do
        if player:HasCollectible(collectible) then
            return false
        end
    end
    -- Charge-extending items reach the finite-shot overlap point at
    -- proportionally higher fire rates.
    return Mizuki.getDisplayedFireRate(player)
        >= Config.AUTOMATIC_BEAM_BASE_FIRE_RATE
            * Mizuki.getChargeProfile(player, true).MaxChargeMultiplier
end

-- Technology Zero restores Mizuki's original charged finite beam. Items whose
-- own established compatibility depends on a charge/release cycle stay on that
-- path as well; the new four-tick immediate shot is the unmodified default.
function Mizuki.usesChargedBeam(player)
    return Mizuki.isBerserkClubActive(player) or Mizuki.usesTechnologyZeroBeam(player)
    or player:HasCollectible(
        CollectibleType.COLLECTIBLE_CHOCOLATE_MILK
    ) or player:HasCollectible(
        CollectibleType.COLLECTIBLE_CURSED_EYE
    ) or player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    ) or player:HasCollectible(
        CollectibleType.COLLECTIBLE_MOMS_KNIFE
    ) or player:HasCollectible(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG
    )
end

function Mizuki.hasPeriodicBeam(player)
    return not Mizuki.cannonUsesKnifeWeapon(player)
        and (player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
            or Mizuki.usesTechnologyZeroBeam(player))
end

function Mizuki.getRawShootingInput(player)
    local controller = player.ControllerIndex
    return Vector(
        Input.GetActionValue(ButtonAction.ACTION_SHOOTRIGHT, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTLEFT, controller),
        Input.GetActionValue(ButtonAction.ACTION_SHOOTDOWN, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTUP, controller)
    )
end

function Mizuki.hasRawShootingInput(player)
    local input = Mizuki.getRawShootingInput(player)
    if input:Length() > Mizuki.RuntimeParameters.AimDeadZone then
        return true
    end
    return Options.MouseControl
        and player.ControllerIndex == 0
        and player:AreControlsEnabled()
        and Input.IsMouseBtnPressed(0)
end

function Mizuki.getTechnologyZeroReleaseDirection(player)
    local data = player:GetData()
    -- Player input/head updates can precede our PEFFECT release handler. Keep
    -- the ready shot's aim across that gap, without inventing a held fire input.
    if not Mizuki.usesAutomaticBeam(player) and data.MizukiCannonAutoFireState ~= "deployed"
        and data.MizukiAim and (data.MizukiCharge or 0) >= Mizuki.getChargeProfile(player).MinFrames
        and not Mizuki.hasRawShootingInput(player) then
        return data.MizukiAim
    end
end

function Mizuki.getTargetReticle(player, data)
    local target = data.MizukiTargetReticle
    if not target or not target:Exists() or target.State ~= 0 then
        data.MizukiTargetReticle = nil
        return nil
    end

    local validVariant = target.Variant == EffectVariant.TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MARKED)
        or target.Variant == EffectVariant.OCCULT_TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
        and not Mizuki.usesCannonTechX(player)
    if not validVariant then
        data.MizukiTargetReticle = nil
        return nil
    end
    return target
end

-- Tech X keeps finite native shots even when input is sustained. This policy
-- does not switch other weapons into their persistent-laser controller.
function Mizuki.getCannonTechXContinuousMode(player, data)
    local milk = player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
    local fast = Mizuki.getDisplayedFireRate(player) >= Config.AUTOMATIC_BEAM_BASE_FIRE_RATE
        * Mizuki.getChargeProfile(player, true).MaxChargeMultiplier
    local target = Mizuki.getTargetReticle(player, data)
    return milk or fast or target ~= nil, milk or fast
end

function Mizuki.addOccultHoming(player, tearFlags)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT) then
        return tearFlags | TearFlags.TEAR_HOMING
    end
    return tearFlags
end

local function hasFreeAim(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_ANALOG_STICK)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
end

-- Snap a direction to the nearest of the eight base directions. Keyboard input
-- already lands exactly on one of them, so this only changes mouse and stick
-- input.
local function quantizeAim(player, direction)
    if hasFreeAim(player) then
        return direction
    end

    local normalized = direction:Normalized()
    local best = Config.EIGHT_WAY_AIM[1]
    local bestDot = -2
    for _, candidate in ipairs(Config.EIGHT_WAY_AIM) do
        local dot = normalized.X * candidate.X + normalized.Y * candidate.Y
        if dot > bestDot then
            bestDot = dot
            best = candidate
        end
    end
    return best
end

local function clearDiagonalReleaseGrace(data)
    data.MizukiPendingCardinalAim = nil
    data.MizukiPendingCardinalAimFrames = nil
end

local function applyDiagonalReleaseGrace(data, direction, enabled)
    local diagonalReleaseGraceFrames = 2
    if not enabled then
        clearDiagonalReleaseGrace(data)
        return direction
    end

    local previous = data.MizukiAim
    local previousIsDiagonal = previous
        and math.abs(previous.X) > Mizuki.WeaponParameters.AimComponentThreshold
        and math.abs(previous.Y) > Mizuki.WeaponParameters.AimComponentThreshold
    local currentIsHorizontal = math.abs(direction.X) > 0.5
        and math.abs(direction.Y) < Mizuki.WeaponParameters.AimComponentThreshold
    local currentIsVertical = math.abs(direction.Y) > 0.5
        and math.abs(direction.X) < Mizuki.WeaponParameters.AimComponentThreshold
    local compatible = previousIsDiagonal and (
        currentIsHorizontal and previous.X * direction.X > 0
        or currentIsVertical and previous.Y * direction.Y > 0
    )

    if not compatible then
        clearDiagonalReleaseGrace(data)
        return direction
    end

    local pending = data.MizukiPendingCardinalAim
    if pending
        and (pending - direction):LengthSquared() < Mizuki.RuntimeParameters.DirectionMatchSquaredEpsilon
    then
        local frames = (data.MizukiPendingCardinalAimFrames or 1) + 1
        if frames > diagonalReleaseGraceFrames then
            clearDiagonalReleaseGrace(data)
            return direction
        end
        data.MizukiPendingCardinalAimFrames = frames
        return previous
    end

    -- Forgive a short gap between releasing the two keys of a diagonal.
    -- Continuing to hold the surviving cardinal direction confirms the turn on
    -- the update after the grace window; releasing it during the window fires
    -- with the retained diagonal instead.
    data.MizukiPendingCardinalAim = Vector(direction.X, direction.Y)
    data.MizukiPendingCardinalAimFrames = 1
    return previous
end

function Mizuki.getShootingIntent(player, data, allowDiagonalGrace)
    local target = Mizuki.getTargetReticle(player, data)
    if target then
        clearDiagonalReleaseGrace(data)
        local targetDirection = target.Position - player.Position
        if targetDirection:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            targetDirection = targetDirection:Normalized()
            data.MizukiLastShootDirection = targetDirection
            return true, targetDirection
        end
    end

    local controller = player.ControllerIndex
    if Options.MouseControl
        and controller == 0
        and player:AreControlsEnabled()
        and Input.IsMouseBtnPressed(0)
    then
        clearDiagonalReleaseGrace(data)
        local mouseDirection = Input.GetMousePosition(true) - player.Position
        if mouseDirection:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            mouseDirection = quantizeAim(player, mouseDirection)
            data.MizukiLastShootDirection = mouseDirection
            return true, mouseDirection
        end
    end

    local triggeredDirection = nil
    for _, input in ipairs(Config.SHOOT_ACTIONS) do
        if Input.IsActionTriggered(input.Action, controller) then
            triggeredDirection = input.Direction
        end
    end

    -- Native head locks inject a tiny virtual shooting input. Read hardware
    -- during those windows so release and the next shot's aim remain real.
    local shootingJoystick = Mizuki.getAttackPoseHeadDirection(player)
        and Mizuki.getRawShootingInput(player) or player:GetShootingJoystick()
    if shootingJoystick:Length() > Mizuki.RuntimeParameters.AimDeadZone then
        -- Use one direction source for keyboard and controller, matching the
        -- CuerLib input pattern. Analog Stick and Mom's Knife keep the
        -- continuous angle; ordinary aim snaps to eight directions. Both paths
        -- retain the same diagonal release grace.
        local direction = quantizeAim(
            player,
            shootingJoystick:Normalized()
        )
        direction = applyDiagonalReleaseGrace(
            data,
            direction,
            allowDiagonalGrace
        )
        data.MizukiLastShootDirection = direction
        return true, direction
    end

    -- A newly pressed opposite direction can cancel the combined vector to
    -- zero. In that case only, let the new key choose the retained direction.
    if triggeredDirection then
        clearDiagonalReleaseGrace(data)
        local direction = quantizeAim(player, triggeredDirection)
        data.MizukiLastShootDirection = direction
        return true, direction
    end

    for _, input in ipairs(Config.SHOOT_ACTIONS) do
        if Input.IsActionPressed(input.Action, controller) then
            clearDiagonalReleaseGrace(data)
            local retained = data.MizukiLastShootDirection
                or input.Direction
            return true, quantizeAim(player, retained)
        end
    end

    clearDiagonalReleaseGrace(data)
    local kidney = data.MizukiKidneyStoneBurst
    if kidney and player:AreControlsEnabled() then
        local direction = data.MizukiLastShootDirection or kidney.Direction
        if direction then return true, direction end
    end
    return false, nil
end

function Mizuki:CaptureTargetReticle(effect)
    if effect.State ~= 0 then return end
    local player = effect.SpawnerEntity and effect.SpawnerEntity:ToPlayer()
    if not player or not Mizuki.isMizuki(player) then return end

    local validVariant = effect.Variant == EffectVariant.TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MARKED)
        or effect.Variant == EffectVariant.OCCULT_TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
        and not Mizuki.usesCannonTechX(player)
    if validVariant then
        player:GetData().MizukiTargetReticle = effect
    end
end

-- Independent auxiliary weapons read input without advancing the main weapon
-- or changing its stored charge/release direction.
function Mizuki.getTech5Input(player)
    local data = player:GetData()
    local target = Mizuki.getTargetReticle(player, data)
    if target then
        local offset = target.Position - player.Position
        return offset:Length() > Mizuki.RuntimeParameters.AimDeadZone,
            offset:Normalized(), target.Position
    end
    if not Mizuki.hasRawShootingInput(player) then return false end
    local ring = data.MizukiLudovicoRing
    if ring and ring:Exists() then
        local offset = ring.Position - player.Position
        return offset:Length() > Mizuki.RuntimeParameters.AimDeadZone,
            offset:Normalized(), ring.Position
    end
    local direction
    if Options.MouseControl and player.ControllerIndex == 0 and Input.IsMouseBtnPressed(0) then
        direction = Input.GetMousePosition(true) - player.Position
    else direction = Mizuki.getAttackPoseHeadDirection(player)
        and Mizuki.getRawShootingInput(player) or player:GetShootingJoystick() end
    if direction:Length() <= Mizuki.RuntimeParameters.AimDeadZone then return false end
    return true, quantizeAim(player, direction)
end
