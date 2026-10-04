Mizuki = RegisterMod("Mizuki", 1)

-- region Shared parameters
-- Units and native lifecycle contracts used by more than one feature.
-- Values with different meanings stay separate even when their defaults match.
Mizuki.RuntimeParameters = {
    LogicFramesPerSecond = 30,
    FrameComparisonEpsilon = 0.0001,
    MinimumFireInterval = 0.001,
    VectorEpsilon = 0.001,
    OffsetEpsilon = 0.001,
    ScaleEpsilon = 0.001,
    AimDeadZone = 0.01,
    DistanceEpsilon = 0.01,
    DirectionMatchSquaredEpsilon = 0.0001,
    AngleMatchEpsilon = 0.0001,
    DamageComparisonEpsilon = 0.0001,
    NativeLaserInitFrames = 2,
    RngShiftIndex = 35,
    PercentScale = 100,
    ColorByteMax = 255,
}

-- Weapon-controller tuning stays here, including shared geometry consumed by
-- feature modules. Existing named constants below retain their original role.
Mizuki.WeaponParameters = {
    ChocolateMilkMinChargeFrames = 2,
    CursedEyeFullChargeShots = 5,
    MinBeamDistance = 40,
    MonstrosLungTearsDivisor = 4.3,
    ThickBrimstoneWidthThreshold = 2.5,
    BeamDepthBehindCannon = 5,
    CannonIdleSwingFrames = 150,
    CannonRotationReturnRate = 0.18,
    CannonAngleSnapDegrees = 0.1,
    CannonDepthSnapDistance = 0.5,
    CannonReflectionSnapDistance = 0.5,
    AimComponentThreshold = 0.5,
    DiagonalAimComponent = 0.70710678,
    BookWormBonusChance = 0.25,
    MomsEyeBaseChance = 0.5,
    MomsEyeLuckStep = 0.1,
    LokisHornsBaseChance = 0.25,
    LokisHornsLuckStep = 0.05,
    EyeSoreCountBound = 4,
    LungMinExtraBeams = 3,
    LungMaxExtraBeams = 5,
    LungMinExtraPerCopy = 2,
    LungMaxExtraPerCopy = 3,
    LudovicoDefaultRingRadius = 60,
    LudovicoMoveSpeed = 8,
    LudovicoVelocityResponse = 0.2,
    ReflectionPullSpeedMultiplier = 1,
    ReflectionPullDistanceResponse = 0.05,
    ChargeBarStartFrames = 12,
    ChargeBarLoopFrames = 6,
    ChargeBarProgressFrames = 100,
    TearBaseSpeed = 10,
    ImmaculateHeartChance = 0.25,
    PencilTriggerShots = 15,
    PencilTearCount = 12,
    PencilSpreadDegrees = 60,
    PencilSpeedMin = 0.5,
    PencilSpeedRandomSpan = 0.75,
    PencilScaleMin = 0.75,
    PencilScaleRandomSpan = 0.5,
    PencilBaseHeight = -5,
    PencilHeightRandomSpan = 3,
    PencilBaseFallingSpeed = -10,
    PencilFallingSpeedRandomSpan = 10,
    PencilBloodTearChance = 0.5,
    TearTint = { Red = 246, Green = 171, Blue = 180, ColorizeIntensity = 5 },
}
-- endregion Shared parameters

-- Vanilla Repentance+ only. Mizuki's beam uses a native EntityLaser for
-- collision, damage ticks and tear-effect compatibility. Lua owns its firing
-- cadence and keeps the laser anchored to the firing cannon position.
Mizuki.PlayerType = Isaac.GetPlayerTypeByName("Mizuki", false)
Mizuki.PlayerAnm2 = "gfx/characters/mizuki/character_mizuki.anm2"
Mizuki.HairCostume = Isaac.GetCostumeIdByPath(
    "gfx/characters/mizuki/character_mizuki_hair.anm2"
)
Mizuki.CannonVariant = Isaac.GetEntityVariantByName("Mizuki Cannon")
Mizuki.ExperimentalCapsuleCard = Isaac.GetCardIdByName("Mizuki Experimental Capsule")
Mizuki.FanItem = Isaac.GetItemIdByName("Xiaobotu")
Mizuki.FanVariant = Isaac.GetEntityVariantByName("Mizuki Fan Familiar")
local EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = 9201

include("translations/main")
include("scripts/localization")
include("scripts/birthright")

local GLOWING_HOUR_GLASS = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
local BOX_OF_FRIENDS = CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS
local BFFS = CollectibleType.COLLECTIBLE_BFFS
local LUCKY_FOOT = CollectibleType.COLLECTIBLE_LUCKY_FOOT
local MOMS_BOX = CollectibleType.COLLECTIBLE_MOMS_BOX
local SACK_HEAD = CollectibleType.COLLECTIBLE_SACK_HEAD
local CAPSULE_STAT_CACHE_FLAGS = CacheFlag.CACHE_DAMAGE
    | CacheFlag.CACHE_FIREDELAY
    | CacheFlag.CACHE_SPEED
    | CacheFlag.CACHE_SHOTSPEED
    | CacheFlag.CACHE_RANGE
    | CacheFlag.CACHE_LUCK

local CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER = 2.5
local CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER = 2.50
local CURSED_EYE_MAX_CHARGE_MULTIPLIER = 2
local CURSED_EYE_CHOCOLATE_SHOT_THRESHOLDS = { 1 / 3, 1 / 2, 3 / 4, 1 }
local AUTOMATIC_BEAM_BASE_FIRE_RATE = 7.5
local AUTOMATIC_BEAM_RATE_EXCLUSIONS = {
    CollectibleType.COLLECTIBLE_MOMS_KNIFE,
}
local DEFAULT_TEARS_MULTIPLIER = 0.5
local TECHNOLOGY_ZERO_TEARS_MULTIPLIER = 1 / 3
local TEARS_MODIFIER = 0
local DEFAULT_DAMAGE_MULTIPLIER = 0.75
local TECHNOLOGY_ZERO_DAMAGE_MULTIPLIER = 1
local MOVE_SPEED_MODIFIER = -0.15
local LUCK_MODIFIER = 1
local BEAM_DISTANCE = 240
local BEAM_HITBOX_Y_OFFSET = 22.5
-- Mizuki begins at HUD Range 6.50, which is internal TearRange 260.
-- Its baseline beam length is anchored to that starting stat.
local BASE_TEAR_RANGE = 260
local MIN_BEAM_WIDTH_SCALE = 0.75
local MAX_BEAM_WIDTH_SCALE = 5.00
local LEAD_PENCIL_BLOOD_CLOT_COLOR = Color(0.9, 0, 0, 1, 0, 0, 0)
-- Wiki timing is stated in 60 Hz render frames; gameplay callbacks advance at
-- 30 Hz. A native laser's four-render-frame damage cadence is two logical frames.
local BEAM_DAMAGE_INTERVAL = 2
-- Anti-Gravity's waiting state does not fit either Mizuki beam lifecycle: it
-- can freeze a persistent path and can leave a finite charged shot suspended.
-- It needs a dedicated synergy rather than being copied onto EntityLaser.
local MIZUKI_FORBIDDEN_TEAR_FLAGS = TearFlags.TEAR_WAIT
-- The engine lands a laser's damage every 2 frames, so a beam that owes N ticks
-- lives N * 2 + 1 frames: the frame it spawns on, then two frames per tick.
-- Technology Zero restores Mizuki's original eight-tick finite beam. Charge
-- items can still select the charge/release input path without inheriting this
-- damage schedule.
local TECHNOLOGY_ZERO_BEAM_TICK_COUNT = 8
local TECHNOLOGY_ZERO_BEAM_DURATION =
    TECHNOLOGY_ZERO_BEAM_TICK_COUNT * BEAM_DAMAGE_INTERVAL + 1
local TECHNOLOGY_ZERO_BEAM_TOTAL_DAMAGE_MULTIPLIER = 8.00
local DEFAULT_BEAM_TICK_COUNT = 4
local DEFAULT_BEAM_DURATION = DEFAULT_BEAM_TICK_COUNT * BEAM_DAMAGE_INTERVAL + 1
local DEFAULT_BEAM_TOTAL_DAMAGE_MULTIPLIER = 4.00
-- Repentance's line weapons keep ordinary multishots close together. This is
-- the laser/brimstone correction used by the vanilla-compatible multishot
-- fallback: the basic 2.17-degree spread is widened by 1500 / 1397.
local LINE_MULTISHOT_SPREAD_FACTOR = 1500 / 1397
local LINE_MULTISHOT_BASE_SPREAD = 2.17
local LINE_MULTISHOT_GLASSES_SPREAD = 2
local MAX_STANDARD_MULTISHOT = 16
local WIZ_ARC_HALF_ANGLE = 45
local CONJOINED_SIDE_ANGLE = 45
local IMMACULATE_HEART_FALLING_ACCELERATION = -0.08
local MIN_CHARGE_DAMAGE_MULTIPLIER = 0.45
local MIZUKI_TEAR_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
MIZUKI_TEAR_COLOR:SetColorize(
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Red / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Green / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Blue / Mizuki.RuntimeParameters.ColorByteMax,
    1
)

local CANNON_ANM2 = "gfx/entities/mizuki/mizuki_cannon.anm2"
local CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon.png"
local CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light.png"
local LEFT_CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_left.png"
local LEFT_CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light_left.png"
-- Player size and Ludovico copies form the shared weapon scale. Each visual
-- then applies one explicit art multiplier: cannon art is authored at 0.65,
-- while Mom's Knife uses its native full-size art (1.0).
local CANNON_ART_SCALE_MULTIPLIER = 0.65
local MOMS_KNIFE_ART_SCALE_MULTIPLIER = 1
local IDLE_CANNON_DEPTH_OFFSET = 70
local MOMS_KNIFE_DEPTH_OFFSET = 5
local CANNON_DEPTH_OFFSET = 30
local FIRING_CANNON_DEPTH_OFFSET = 30
local HORIZONTAL_BACK_DEPTH_OFFSET = 20
local HORIZONTAL_FRONT_DEPTH_OFFSET = 30
local CHARGE_BAR_SCALE = Vector(1, 1)
local CHARGE_BAR_OFFSET = Vector(0, 5)
local CHARGE_BAR_NORMAL_GRAPHICS_OFFSET = Vector(1, 0)
-- Resting formation: two separated rabbit ears above the head.
local CANNON_OFFSETS = { Vector(-12, -60), Vector(12, -60) }
local CANNON_IDLE_OFFSETS = Vector(0, -5)
local CANNON_MOMS_KNIFE_IDLE_OFFSET = Vector(0, -8)
local CANNON_GROUP_SPACING = 16
-- Attack-pair half-spacing at the vertical and horizontal points of the orbit.
local VERTICAL_CANNON_X = 5
local HORIZONTAL_CANNON_HALF_SPACING = 3
-- The attack midpoint circles the player's collision position, then the whole
-- formation is lifted by the cannon's visual height. Keep the old horizontal
-- midpoint (10, -22.5) while bringing the upward pose closer to the player.
local CANNON_ATTACK_ORBIT_RADIUS = 20
local CANNON_ATTACK_ORBIT_HEIGHT = 22.5
-- Mom's Knife moves the attack cannon and its laser outward together.
-- Its idle height is independent of this attack-radius bonus.
local CANNON_MOMS_KNIFE_ORBIT_RADIUS_BONUS = 20
-- Side-on projection of the hand-drawn cannon body at vertical aim.
local VERTICAL_CANNON_BODY_X_MULTIPLIER = 0.75
local CANNON_FOLLOW_SPEED = 0.25
-- Keep a little elastic motion without letting normal player movement pull the
-- cannons far enough away from their authored silhouette to cross the body.
local CANNON_MAX_FOLLOW_LAG = 8
local CANNON_FLOAT_AMPLITUDE = 2
local CANNON_FLOAT_PERIOD = 45

function Mizuki.getCannonHoverOffset(frame)
    return math.sin(frame * 2 * math.pi / CANNON_FLOAT_PERIOD)
        * CANNON_FLOAT_AMPLITUDE
end
-- Tap Drop to toggle a stationary cannon pair; hold it to invert that state
-- only until release. The game's own Drop action is left untouched.
local LEFT_CANNON_IDLE_ROTATION = -55
local RIGHT_CANNON_IDLE_ROTATION = -10
local LEFT_CANNON_IDLE_OUTER_ROTATION = -65
local RIGHT_CANNON_IDLE_OUTER_ROTATION = -0.1
-- The configured idle rotations above are the inward end of the motion. Over
-- five seconds at 30 logical frames per second, the pair opens to -65 / 5 and
-- returns. Cosine position produces sinusoidal speed: fastest halfway through
-- each stroke and smoothly slowing to zero at both ends.
-- Orbit distance past the ring's own collision radius.
Mizuki.LUDOVICO_CANNON_ORBIT_PADDING = 0
Mizuki.LUDOVICO_CANNON_ORBIT_DEGREES_PER_FRAME = 3
Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER = 3
Mizuki.LUDOVICO_CANNON_MIN_HIT_RADIUS = 10
local LUDOVICO_TRIGGERED_BEAM_DAMAGE_MULTIPLIER = 0.5
local TRANSIENT_BEAM_SOURCE_BOOK_WORM = "book_worm"
local TRANSIENT_BEAM_SOURCE_MOMS_EYE = "moms_eye"
local TRANSIENT_BEAM_SOURCE_LOKIS_HORNS = "lokis_horns"
local TRANSIENT_BEAM_SOURCE_EYE_SORE = "eye_sore"
local LUDOVICO_INCUBUS_MULTIPLIER = 0.75
local LUDOVICO_TWISTED_BABY_MULTIPLIER = 0.375
-- The decorative idle turn pivots around the cannon sprite's bottom centre,
-- while its Familiar entity (and therefore the beam origin) stays fixed.
local CANNON_IDLE_ROTATION_PIVOT = Vector(0, 22)

-- Water reflections are re-drawn by this mod instead of by the engine; see
-- Mizuki:RenderCannon. The engine keeps "drawing" the cannon in every water
-- pass so those render callbacks keep firing, but the draw itself is made fully
-- transparent here. A fresh Color per call avoids handing several sprites the
-- same mutable object.
local function getCannonHiddenColor()
    return Color(1, 1, 1, 0, 0, 0, 0)
end

-- Distance from a cannon straight down to its water reflection.
--
-- While attacking, the cannon midpoint orbits the player's collision position
-- at a fixed visual height. Keep that height as the reflection separation;
-- individual cannon positions still vary with aim direction around the orbit.
--
-- At rest the cannons genuinely sit above the player's head, and there the
-- reflection is a plain geometric mirror instead, using that head height.
--
-- Both are derived from the layout that defines them, so retuning either layout
-- retunes its reflection distance with it.
local CANNON_FIRING_REFLECTION_SPAN = 2 * CANNON_ATTACK_ORBIT_HEIGHT
local CANNON_IDLE_REFLECTION_SPAN = -2 * CANNON_OFFSETS[1].Y

local function getCannonIdleHeightOffset(player)
    local offset = CANNON_IDLE_OFFSETS
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        offset = offset + CANNON_MOMS_KNIFE_IDLE_OFFSET
    end
    return offset
end

local function getCannonReflectionSpan(player, isIdle)
    if not isIdle then
        return CANNON_FIRING_REFLECTION_SPAN * player.SpriteScale.Y
    end
    -- The base formation follows player size, while the final idle lift is a
    -- fixed world-space adjustment. Reflect both parts about the same plane.
    return CANNON_IDLE_REFLECTION_SPAN * player.SpriteScale.Y
        - 2 * getCannonIdleHeightOffset(player).Y
end

-- Native flooded-room laser reflections use the laser entity's Position and
-- PositionOffset differently from the normal body draw. Split Mizuki's extra
-- scale-based cannon height equally between them: the visible beam stays at the
-- cannon muzzle, while the native reflection gains the full extra separation.
--
-- Moving Position also changes the entity's Y sort key, so return that shift and
-- subtract it from DepthOffset at each call site. That keeps the beam/cannon
-- layering exactly where it was before the reflection correction.
local function applyMizukiBeamReflectionHeight(player, laser)
    if not laser then
        return 0
    end
    local extraGap = CANNON_FIRING_REFLECTION_SPAN
        * (player.SpriteScale.Y - 1)
    local shift = extraGap * 0.5
    if math.abs(shift) <= Mizuki.RuntimeParameters.OffsetEpsilon then
        return 0
    end
    local verticalShift = Vector(0, shift)
    laser.Position = laser.Position + verticalShift
    laser.PositionOffset = laser.PositionOffset - verticalShift
    return shift
end

-- How fast the reflection distance follows a change between the resting and
-- firing layouts. The cannon's own pose already eases between those layouts
-- (CANNON_FOLLOW_SPEED for the position and a separate return speed for the
-- idle tilt), so the reflection eases at a similar rate instead of jumping the
-- whole distance in the frame the player starts or stops firing. The immediate
-- attack's explicit position snap is handled separately below.
local CANNON_REFLECTION_SPAN_SPEED = CANNON_FOLLOW_SPEED

local function resolveBeamGeometry(
    visualOrigin,
    baseDirection,
    directionOffset,
    targetPosition
)
    directionOffset = directionOffset or 0
    local originDirection = baseDirection:Normalized()

    if targetPosition then
        local targetDirection = targetPosition - visualOrigin
        if targetDirection:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            originDirection = targetDirection:Normalized()
        end
    end

    local beamDirection = originDirection:Rotated(directionOffset)
    -- Cannon body and laser origin already share the same world-space pivot
    -- correction. A second diagonal-only offset would move the beam away from
    -- the displayed cannon centre.
    return beamDirection, Vector.Zero
end

local CHARGE_BAR_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
CHARGE_BAR_COLOR:SetColorize(
    Mizuki.WeaponParameters.TearTint.Red / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.Green / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.Blue / Mizuki.RuntimeParameters.ColorByteMax,
    1
)
local chargeBar = Sprite()
chargeBar:Load("gfx/chargebar_revelation.anm2", true)

-- The cannon's shadow is the sprite's own anm2 "shadow" layer (built from
-- gfx/shadow.png, a plain black ellipse, like every vanilla entity shadow), and
-- the engine draws it in its own pass - that pass is what keeps two overlapping
-- shadows from adding up. Size, shape and opacity live in that layer's frames;
-- Mizuki:RenderCannon only leaves the sprite in the pose the shadow needs.

local function isMizuki(player)
    return player:GetPlayerType() == Mizuki.PlayerType
end

function Mizuki:LoadPlayerAnm2(player)
    if isMizuki(player) then
        player:GetSprite():Load(Mizuki.PlayerAnm2, true)
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_PLAYER_INIT,
    Mizuki.LoadPlayerAnm2
)

function Mizuki:EnsureHairCostume(player)
    if not isMizuki(player) then
        return
    end

    local data = player:GetData()
    if Mizuki.HairCostume < 0 then
        return
    end

    local refreshFrame = data.MizukiHairCostumeRefreshFrame
    if refreshFrame then
        if Game():GetFrameCount() > refreshFrame then
            -- D4/D100 can rebuild the player's costumes without clearing our
            -- "applied" marker. Refresh once after the reroll has finished.
            player:TryRemoveNullCostume(Mizuki.HairCostume)
            player:AddNullCostume(Mizuki.HairCostume)
            data.MizukiHairCostumeApplied = true
            data.MizukiHairCostumeRefreshFrame = nil
        end
        return
    end

    if not data.MizukiHairCostumeApplied then
        player:AddNullCostume(Mizuki.HairCostume)
        data.MizukiHairCostumeApplied = true
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_PEFFECT_UPDATE,
    Mizuki.EnsureHairCostume
)

function Mizuki:QueueHairCostumeRerollRefresh(collectible, rng, player)
    if isMizuki(player) then
        player:GetData().MizukiHairCostumeRefreshFrame = Game():GetFrameCount()
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.QueueHairCostumeRerollRefresh,
    CollectibleType.COLLECTIBLE_D4
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.QueueHairCostumeRerollRefresh,
    CollectibleType.COLLECTIBLE_D100
)

local function scalePlayerOffset(player, offset)
    local scale = player.SpriteScale
    return Vector(offset.X * scale.X, offset.Y * scale.Y)
end

-- Glowing Hour Glass rewinds EntityPlayer state, including values associated
-- with that snapshot. Keep the capsule transaction outside player:GetData()
-- so the fact that it was consumed cannot itself be rewound.
local capsuleStates = {}
-- Glowing Hour Glass also rewinds player:GetData(), so cannon-reconcile
-- bookkeeping must live outside EntityPlayer state for the same reason.
local cannonReconcileStates = {}

local function getPlayerIndex(player)
    local game = Game()
    local playerHash = GetPtrHash(player)
    for index = 0, game:GetNumPlayers() - 1 do
        if GetPtrHash(Isaac.GetPlayer(index)) == playerHash then
            return index
        end
    end
    return player.ControllerIndex or 0
end

local function getCapsuleState(player)
    local index = getPlayerIndex(player)
    capsuleStates[index] = capsuleStates[index] or {}
    return capsuleStates[index]
end

local function getCannonReconcileState(player)
    local index = getPlayerIndex(player)
    cannonReconcileStates[index] = cannonReconcileStates[index] or {}
    return cannonReconcileStates[index]
end

-- Match Brimstone's charging principle: effective Tear Delay is the interval
-- between shots, MaxFireDelay + 1. The final visible Tears stat therefore
-- directly determines the number of real frames required to fully charge.
local usesAutomaticBeam

local function getChargeProfile(player, rawChargeItems)
    -- Input advances in whole logical frames, but MaxFireDelay may be
    -- fractional. Keep the unrounded duration for damage interpolation and use
    -- the ceiling only for the first frame on which a charge is considered full.
    local baseChargeFrames = math.max(1, player.MaxFireDelay + 1)
    local baseFrames = math.max(1, math.ceil(baseChargeFrames))
    local minMultiplier = 0.50
    local maxMultiplier = 1
    local automatic = not rawChargeItems and usesAutomaticBeam(player)
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
            CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER
        )
    end
    if hasCursedEye then
        maxMultiplier = math.max(
            maxMultiplier,
            CURSED_EYE_MAX_CHARGE_MULTIPLIER
        )
    end

    return {
        BaseFrames = baseFrames,
        BaseChargeFrames = baseChargeFrames,
        MaxChargeMultiplier = maxMultiplier,
        MinFrames = hasChocolateMilk and Mizuki.WeaponParameters.ChocolateMilkMinChargeFrames
            or math.max(1, math.ceil(baseFrames * minMultiplier)),
        MaxFrames = math.max(1, math.ceil(baseChargeFrames * maxMultiplier)),
        HasChocolateMilk = hasChocolateMilk,
    }
end

local function getChargeDamageMultiplier(charge, profile)
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
        return MIN_CHARGE_DAMAGE_MULTIPLIER
            + (1 - MIN_CHARGE_DAMAGE_MULTIPLIER) * normalizedCharge
    end

    -- Vanilla Chocolate Milk scales charge linearly to 400%. The beam variant
    -- keeps that timing but caps each native damage tick at 250% instead.
    return math.min(
        charge / profile.BaseChargeFrames,
        CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER
    )
end

local function getCursedEyeShotCount(player, charge, profile)
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        or usesAutomaticBeam(player)
    then
        return 1
    end
    if not profile.HasChocolateMilk then
        return charge >= profile.MaxFrames and Mizuki.WeaponParameters.CursedEyeFullChargeShots or 1
    end

    -- Match the observed shot counts to the visible Chocolate Milk charge bar.
    local shotCount = 1
    for _, fraction in ipairs(CURSED_EYE_CHOCOLATE_SHOT_THRESHOLDS) do
        local threshold = math.ceil(profile.MaxFrames * fraction)
        if charge >= threshold then
            shotCount = shotCount + 1
        end
    end
    return shotCount
end

local function getDisplayedFireRate(player)
    return Mizuki.RuntimeParameters.LogicFramesPerSecond / math.max(player.MaxFireDelay + 1, Mizuki.RuntimeParameters.MinimumFireInterval)
end

usesAutomaticBeam = function(player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
    then
        return true
    end

    -- These weapons have no sustained-beam transition from high fire rate.
    for _, collectible in ipairs(AUTOMATIC_BEAM_RATE_EXCLUSIONS) do
        if player:HasCollectible(collectible) then
            return false
        end
    end
    -- Charge-extending items reach the finite-shot overlap point at
    -- proportionally higher fire rates.
    return getDisplayedFireRate(player)
        >= AUTOMATIC_BEAM_BASE_FIRE_RATE
            * getChargeProfile(player, true).MaxChargeMultiplier
end

-- Technology Zero restores Mizuki's original charged finite beam. Items whose
-- own established compatibility depends on a charge/release cycle stay on that
-- path as well; the new four-tick immediate shot is the unmodified default.
local function usesChargedBeam(player)
    return player:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
    ) or player:HasCollectible(
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

local SHOOT_ACTIONS = {
    { Action = ButtonAction.ACTION_SHOOTLEFT, Direction = Vector(-1, 0) },
    { Action = ButtonAction.ACTION_SHOOTRIGHT, Direction = Vector(1, 0) },
    { Action = ButtonAction.ACTION_SHOOTUP, Direction = Vector(0, -1) },
    { Action = ButtonAction.ACTION_SHOOTDOWN, Direction = Vector(0, 1) },
}

local function getRawShootingInput(player)
    local controller = player.ControllerIndex
    return Vector(
        Input.GetActionValue(ButtonAction.ACTION_SHOOTRIGHT, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTLEFT, controller),
        Input.GetActionValue(ButtonAction.ACTION_SHOOTDOWN, controller)
            - Input.GetActionValue(ButtonAction.ACTION_SHOOTUP, controller)
    )
end

local function hasRawShootingInput(player)
    local input = getRawShootingInput(player)
    if input:Length() > Mizuki.RuntimeParameters.AimDeadZone then
        return true
    end
    return Options.MouseControl
        and player.ControllerIndex == 0
        and player:AreControlsEnabled()
        and Input.IsMouseBtnPressed(0)
end

Mizuki.hasRawShootingInput = hasRawShootingInput
Mizuki.CANNON_ATTACK_ORBIT_HEIGHT = CANNON_ATTACK_ORBIT_HEIGHT

local function getLudovicoFacingAnimation(player)
    local ring = player:GetData().MizukiLudovicoTechXProbe
    if not ring or not ring:Exists() then return nil end
    if not hasRawShootingInput(player) then return nil end

    local offset = ring.Position - player.Position
    if offset:Length() <= Mizuki.RuntimeParameters.DistanceEpsilon then return nil end
    if math.abs(offset.X) > math.abs(offset.Y) then
        return offset.X < 0 and "HeadLeft" or "HeadRight"
    end
    return offset.Y < 0 and "HeadUp" or "HeadDown"
end

local function updateLudovicoPlayerFacing(player)
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

local function getMizukiTargetReticle(player, data)
    local target = data.MizukiTargetReticle
    if not target or not target:Exists() or target.State ~= 0 then
        data.MizukiTargetReticle = nil
        return nil
    end

    local validVariant = target.Variant == EffectVariant.TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MARKED)
        or target.Variant == EffectVariant.OCCULT_TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
    if not validVariant then
        data.MizukiTargetReticle = nil
        return nil
    end
    return target
end

local function addOccultHoming(player, tearFlags)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT) then
        return tearFlags | TearFlags.TEAR_HOMING
    end
    return tearFlags
end

-- Eight-way aim -------------------------------------------------------------
-- Shape the shooting input the way the base game does: eight directions. Mouse
-- aiming and an analog stick both report a continuous angle, and letting the
-- cannons use that directly hands out free 360 degree aiming that items meant
-- to grant it (Analog Stick and Mom's Knife) are supposed to be the source of.
--
-- Aiming at a target reticle (Marked, Eye of the Occult, Epic Fetus) is left
-- alone: those items aim at a point, so they stay exempt by construction.
local EIGHT_WAY_AIM = {
    Vector(1, 0),
    Vector(Mizuki.WeaponParameters.DiagonalAimComponent, Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(0, 1),
    Vector(-Mizuki.WeaponParameters.DiagonalAimComponent, Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(-1, 0),
    Vector(-Mizuki.WeaponParameters.DiagonalAimComponent, -Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(0, -1),
    Vector(Mizuki.WeaponParameters.DiagonalAimComponent, -Mizuki.WeaponParameters.DiagonalAimComponent),
}

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
    local best = EIGHT_WAY_AIM[1]
    local bestDot = -2
    for _, candidate in ipairs(EIGHT_WAY_AIM) do
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

local function getShootingIntent(player, data, allowDiagonalGrace)
    local target = getMizukiTargetReticle(player, data)
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
    for _, input in ipairs(SHOOT_ACTIONS) do
        if Input.IsActionTriggered(input.Action, controller) then
            triggeredDirection = input.Direction
        end
    end

    local shootingJoystick = player:GetShootingJoystick()
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

    for _, input in ipairs(SHOOT_ACTIONS) do
        if Input.IsActionPressed(input.Action, controller) then
            clearDiagonalReleaseGrace(data)
            local retained = data.MizukiLastShootDirection
                or input.Direction
            return true, quantizeAim(player, retained)
        end
    end

    clearDiagonalReleaseGrace(data)
    return false, nil
end

function Mizuki:CaptureTargetReticle(effect)
    if effect.State ~= 0 then return end
    local player = effect.SpawnerEntity and effect.SpawnerEntity:ToPlayer()
    if not player or not isMizuki(player) then return end

    local validVariant = effect.Variant == EffectVariant.TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MARKED)
        or effect.Variant == EffectVariant.OCCULT_TARGET
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
    if validVariant then
        player:GetData().MizukiTargetReticle = effect
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_EFFECT_UPDATE,
    Mizuki.CaptureTargetReticle,
    EffectVariant.TARGET
)
Mizuki:AddCallback(
    ModCallbacks.MC_POST_EFFECT_UPDATE,
    Mizuki.CaptureTargetReticle,
    EffectVariant.OCCULT_TARGET
)

-- Like Azazel's mini-Brimstone, the beam starts short but Range ups extend it.
-- At Mizuki's starting HUD Range 6.50 (internal TearRange 260), its length is exactly 240 px.
local function getBeamDistance(player)
    -- Brimstone's laser has no range limit at all: MaxDistance 0 is the engine's
    -- own "do not trim" value (that is what vanilla's brimstone laser carries),
    -- so the item ignores the Range stat instead of inheriting Mizuki's
    -- Range-scaled beam length.
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        return 0
    end

    return math.max(Mizuki.WeaponParameters.MinBeamDistance, BEAM_DISTANCE * player.TearRange / BASE_TEAR_RANGE)
end

-- Convert the final ShotSpeed stat into real beam thickness. At the normal
-- 1.0 stat the laser keeps its native width; at 2.0 it reaches exactly 3x,
-- then approaches (but never exceeds) 5x for extreme combinations.
local function getBeamWidthScale(player)
    local shotSpeedOffset = player.ShotSpeed - 1
    local widthScale = 1
        + (MAX_BEAM_WIDTH_SCALE - 1)
        * (2 / math.pi)
        * math.atan(shotSpeedOffset)
    return math.max(widthScale, MIN_BEAM_WIDTH_SCALE)
end

-- Brimstone's shot is the item's own shape rather than the Technology one: the
-- item's own nine ticks at the engine's cadence, so 9 * 2 + 1 frames long, with
-- the full panel on every tick.
local BRIMSTONE_BEAM_TICK_COUNT = 9
local BRIMSTONE_BEAM_DURATION = BRIMSTONE_BEAM_TICK_COUNT * BEAM_DAMAGE_INTERVAL + 1
local BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER = 9.00
-- EntityLaser appends its own ending after Timeout reaches zero. Keep that
-- ending inside the advertised total lifetime instead of adding it afterwards.
local TECHNOLOGY_BEAM_END_FRAMES = 3
local BRIMSTONE_BEAM_END_FRAMES = 10
-- Vanilla's sustained Brimstone rule scales every damage tick by Tears / 5.
-- Keep this rule on the generic automatic-beam path rather than on any item:
-- Soy Milk, Almond Milk, a Kidney Stone stat spike which crosses the generic
-- threshold, high-Tears weapon modes and future automatic sources all receive
-- the same final-stat-based multiplier.
-- Both cannons own a real beam, so each beam receives the complete multiplier.
local AUTOMATIC_BEAM_FIRE_RATE_DAMAGE_DIVISOR = 5

-- Finite beams live exactly as long as their tick count needs. ShotSpeed still
-- controls their width, but no longer reduces hit count or proc opportunities.
local function getBeamDamageTiming(
    player,
    automatic,
    brimstone,
    technologyZero
)
    if automatic then
        -- FireTechLaser/FireBrimstone create the native laser entity but do not
        -- run vanilla's high-Tears weapon controller for this custom mode, so
        -- pass that controller's final-Tears multiplier into the firing API.
        local duration = brimstone
            and BRIMSTONE_BEAM_DURATION
            or DEFAULT_BEAM_DURATION
        return duration,
            getDisplayedFireRate(player)
                / AUTOMATIC_BEAM_FIRE_RATE_DAMAGE_DIVISOR
    end

    if brimstone then
        return BRIMSTONE_BEAM_DURATION, BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER
            / BRIMSTONE_BEAM_TICK_COUNT
    end

    if technologyZero then
        return TECHNOLOGY_ZERO_BEAM_DURATION,
            TECHNOLOGY_ZERO_BEAM_TOTAL_DAMAGE_MULTIPLIER
                / TECHNOLOGY_ZERO_BEAM_TICK_COUNT
    end

    return DEFAULT_BEAM_DURATION,
        DEFAULT_BEAM_TOTAL_DAMAGE_MULTIPLIER / DEFAULT_BEAM_TICK_COUNT
end

local function getBeamEndFrames(brimstone)
    return brimstone
        and BRIMSTONE_BEAM_END_FRAMES
        or TECHNOLOGY_BEAM_END_FRAMES
end

-- Weapon-specific fire-rate profiles live here. A profile first removes the
-- relevant native WeaponType Tears multiplier, then applies the multiplier for
-- the selected Mizuki weapon mode.
local function getMizukiFireRateProfile(player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        -- Brimstone charges at the unmodified rate: the item is meant to drop
        -- Mizuki's own fire-rate correction entirely. Nothing native has to
        -- be divided out for the item itself (its items.xml entry carries no
        -- tears value and the character has no native weapon), but Monstro's
        -- Lung's own x4.3 penalty still has to come out when both are held -
        -- Brimstone keeps its charge rate and only adds the radial beams.
        return {
            Id = "brimstone",
            VanillaTearsMultiplier = player:HasCollectible(
                CollectibleType.COLLECTIBLE_MONSTROS_LUNG
            ) and 1 / Mizuki.WeaponParameters.MonstrosLungTearsDivisor or 1,
            TearsModifier = 0,
            MizukiTearsMultiplier = 1,
        }
    end

    local mizukiTearsMultiplier = player:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
    ) and TECHNOLOGY_ZERO_TEARS_MULTIPLIER
        or DEFAULT_TEARS_MULTIPLIER

    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        -- Brimstone has priority over Monstro's Lung: it keeps Brimstone's
        -- charge rate and only adds the radial beams. Remove the native Lung
        -- weapon's x4.3 tear-delay penalty before applying Mizuki's rate.
        return {
            Id = "monstros_lung",
            VanillaTearsMultiplier = 1 / Mizuki.WeaponParameters.MonstrosLungTearsDivisor,
            TearsModifier = TEARS_MODIFIER,
            MizukiTearsMultiplier = mizukiTearsMultiplier,
        }
    end
    return {
        Id = "default",
        VanillaTearsMultiplier = 1,
        TearsModifier = TEARS_MODIFIER,
        MizukiTearsMultiplier = mizukiTearsMultiplier,
    }
end

local function getFamiliarPlayer(familiar)
    if not familiar then return nil end
    local owner = familiar.Player
    if not owner and familiar.Parent then
        owner = familiar.Parent:ToPlayer()
    end
    if not owner and familiar.SpawnerEntity then
        owner = familiar.SpawnerEntity:ToPlayer()
    end
    return owner
end

local function cannonBelongsToPlayer(cannon, player)
    local owner = getFamiliarPlayer(cannon)
    return owner and GetPtrHash(owner) == GetPtrHash(player)
end

local function getCollectibleFamiliarCount(player, collectible)
    return player:GetCollectibleNum(collectible)
        + player:GetEffects():GetCollectibleEffectNum(collectible)
end

-- Resolve the deterministic part of Mizuki's multishot layout once so normal
-- firing and Ludovico cannon pairs cannot drift into separate item formulas.
-- bonusGlassesCount is reserved for per-shot effects such as Book Worm; callers
-- which manage persistent entities pass zero and therefore never consume RNG.
local function getMizukiStandardBeamProfile(player, bonusGlassesCount)
    local innerEyeCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_INNER_EYE
    )
    local mutantSpiderCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MUTANT_SPIDER
    )
    local glassesCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_20_20
    ) + (bonusGlassesCount or 0)
    local wizCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_THE_WIZ
    )

    local hasEyeSpread = innerEyeCount + mutantSpiderCount > 0
    local preGlassesCount = 1
    if hasEyeSpread then
        preGlassesCount = preGlassesCount + 1
            + innerEyeCount
            + mutantSpiderCount * 2
    end

    local standardCount = preGlassesCount
    if glassesCount > 0 then
        standardCount = standardCount + glassesCount
        if hasEyeSpread then
            standardCount = standardCount - 1
        end
    end

    local totalSpread = 0
    if hasEyeSpread then
        totalSpread = (preGlassesCount - 1)
            * LINE_MULTISHOT_BASE_SPREAD
            * LINE_MULTISHOT_SPREAD_FACTOR
    end
    totalSpread = totalSpread
        + glassesCount * LINE_MULTISHOT_GLASSES_SPREAD

    local wizGroups = math.min(wizCount + 1, MAX_STANDARD_MULTISHOT)
    local beamsPerWizGroup = math.max(
        1,
        math.min(
            standardCount,
            math.floor(MAX_STANDARD_MULTISHOT / wizGroups)
        )
    )
    return {
        WizGroups = wizGroups,
        BeamsPerWizGroup = beamsPerWizGroup,
        TotalSpread = totalSpread,
        BeamCount = wizGroups * beamsPerWizGroup,
    }
end

local function getMizukiStableBeamCount(player)
    local profile = getMizukiStandardBeamProfile(player, 0)
    local count = profile.BeamCount
    if player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY) then
        count = count + 2
    end
    return count
end

local function getExpectedCannonPairProfiles(player, stableShotCount)
    local basePairs = 1
    local hasLudovico = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
    )
    if hasLudovico then
        basePairs = stableShotCount or getMizukiStableBeamCount(player)
    end
    basePairs = basePairs
        + player:GetEffects():GetCollectibleEffectNum(BOX_OF_FRIENDS)

    local profiles = {}
    for _ = 1, basePairs do
        profiles[#profiles + 1] = {
            DamageMultiplier = 1,
            ScaleMultiplier = 1,
        }
    end

    if hasLudovico then
        local familiarPowerMultiplier = player:HasCollectible(BFFS) and 2 or 1
        local familiarProfiles = {
            {
                Count = getCollectibleFamiliarCount(
                    player,
                    CollectibleType.COLLECTIBLE_INCUBUS
                ),
                Multiplier = LUDOVICO_INCUBUS_MULTIPLIER
                    * familiarPowerMultiplier,
            },
            {
                -- Each Twisted Pair item/effect owns two Twisted Baby entities,
                -- and therefore contributes two independently damaging pairs.
                Count = getCollectibleFamiliarCount(
                    player,
                    CollectibleType.COLLECTIBLE_TWISTED_PAIR
                ) * 2,
                Multiplier = LUDOVICO_TWISTED_BABY_MULTIPLIER
                    * familiarPowerMultiplier,
            },
        }
        for _, familiarProfile in ipairs(familiarProfiles) do
            for _ = 1, familiarProfile.Count do
                profiles[#profiles + 1] = {
                    DamageMultiplier = familiarProfile.Multiplier,
                    -- The extra cannon is the familiar's bone-club analogue;
                    -- its body and contact radius use the same native familiar
                    -- multiplier as its damage. The familiar's own Ludovico
                    -- tear remains entirely engine-owned and is not rescaled.
                    ScaleMultiplier = familiarProfile.Multiplier,
                }
            end
        end
    end
    return Mizuki.appendPersistentCannonEchoProfiles(player, profiles)
end

local function getExpectedCannonPairs(player)
    return #getExpectedCannonPairProfiles(player)
end

-- CheckFamiliar owns spawning and despawning. Lua only rebuilds stable side
-- groups from the engine-owned entities; it never creates or removes cannons.
local function claimPlayerCannons(player, data)
    local claimed = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, Mizuki.CannonVariant, -1, false, false)) do
        local cannon = entity:ToFamiliar()
        if cannonBelongsToPlayer(cannon, player) then
            cannon.Player = player
            cannon.Parent = player
            local side = cannon.SubType
            if side == 1 or side == 2 then
                table.insert(claimed[side], cannon)
            end
        end
    end

    for side = 1, 2 do
        table.sort(claimed[side], function(left, right)
            return left.InitSeed < right.InitSeed
        end)
    end

    data.MizukiCannons = claimed
end

local function ensureCannonRegistered(cannon)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    -- Keep the engine-style familiar ownership chain complete. Knives parented
    -- to the cannon (and third-party knife callbacks) resolve their player via
    -- Familiar.SpawnerEntity.
    cannon.SpawnerEntity = player

    local side = cannon.SubType
    if side ~= 1 and side ~= 2 then
        return
    end

    local data = player:GetData()
    data.MizukiCannons = data.MizukiCannons or { {}, {} }
    data.MizukiCannons[side] = data.MizukiCannons[side] or {}

    local group = data.MizukiCannons[side]
    local cannonHash = GetPtrHash(cannon)
    for _, existing in ipairs(group) do
        if existing and existing:Exists() and GetPtrHash(existing) == cannonHash then
            return
        end
    end

    table.insert(group, cannon)
    table.sort(group, function(left, right)
        return left.InitSeed < right.InitSeed
    end)
end

local function prunePlayerCannons(data)
    data.MizukiCannons = data.MizukiCannons or { {}, {} }

    for side = 1, 2 do
        data.MizukiCannons[side] = data.MizukiCannons[side] or {}
        local group = data.MizukiCannons[side]
        for index = #group, 1, -1 do
            local cannon = group[index]
            if not cannon or not cannon:Exists() then
                table.remove(group, index)
            end
        end
    end
end

local function reconcilePlayerCannons(player, data)
    local expectedPerSide = getExpectedCannonPairs(player)
    local actual = { {}, {} }

    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR,
        Mizuki.CannonVariant,
        -1,
        false,
        false
    )) do
        local cannon = entity:ToFamiliar()
        if cannon and cannon:Exists() and cannonBelongsToPlayer(cannon, player) then
            local side = cannon.SubType
            if side == 1 or side == 2 then
                table.insert(actual[side], cannon)
            end
        end
    end

    local retained = { {}, {} }
    for side = 1, 2 do
        table.sort(actual[side], function(left, right)
            return left.InitSeed < right.InitSeed
        end)

        for index, cannon in ipairs(actual[side]) do
            if index <= expectedPerSide then
                table.insert(retained[side], cannon)
            else
                if Mizuki.removeCannonMomKnife then
                    Mizuki.removeCannonMomKnife(cannon)
                end
                cannon:Remove()
            end
        end
    end

    data.MizukiCannons = retained
end

local tryFireImmaculateHeartTear
local advanceLeadPencil

-- Hand a finished beam back to EntityLaser for its native narrowing animation
-- instead of deleting it on the last full-width frame. Only the visual state
-- changes: damage, flags, color, cadence-based synergies, cannon ownership,
-- positioning, and firing occupancy all continue until the entity disappears.
local function beginNaturalMizukiBeamEnding(beam)
    local laser = beam and beam.Laser
    if not laser or not laser:Exists() then
        return
    end

    local laserData = laser:GetData()
    if laserData.MizukiBeamEnding then
        return
    end
    laserData.MizukiBeamEnding = true
    -- A positive Timeout extends Brimstone's procedural shrink. Zero it first
    -- so only the variant's measured native ending remains (3 / 10 frames).
    laser.Timeout = 0
    laser.Shrink = true
    beam.Ending = true
end

local function removeActiveMizukiBeams(data)
    for side = 1, 2 do
        for _, beam in ipairs(
            data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}
        ) do
            if Mizuki.cancelCannonKnifeBeam then
                Mizuki.cancelCannonKnifeBeam(beam)
            end
            local laser = beam.Laser
            if laser and laser:Exists() then
                laser:Remove()
            end
        end
    end
    data.MizukiActiveBeams = {}
    data.MizukiLockedCannonPositions = {}
    data.MizukiLockedCannonAims = {}
end

function Mizuki.RefreshMizukiBeamAttackParams(
    player,
    data,
    beam,
    laser,
    shootingDirection
)
    -- Delayed followers replay one attack; their shifted ticks/tail must not
    -- advance the player's shared per-attack synergies a second time.
    if beam.PersistentEchoMode == "automatic" then return end
    local damageFrame = laser.FrameCount % BEAM_DAMAGE_INTERVAL == 0
    if not damageFrame then
        return
    end

    local currentFrame = Game():GetFrameCount()
    if data.MizukiExtraAttackFrame ~= currentFrame then
        local attackDirection = shootingDirection
            or beam.Direction:Rotated(-(beam.DirectionOffset or 0))
        tryFireImmaculateHeartTear(player, attackDirection)
        advanceLeadPencil(player, attackDirection)
        data.MizukiExtraAttackFrame = currentFrame
    end
end

local function updateActiveBeams(
    player,
    data,
    shootingHeld,
    shootingDirection,
    automaticMode
)
    data.MizukiActiveBeams = data.MizukiActiveBeams or {}
    local activeSides = 0
    -- Sides whose cannon is genuinely mid-shot.
    local cannonFiringSides = 0
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams[side]
        if beams and #beams == 0 then
            data.MizukiActiveBeams[side] = nil
            data.MizukiLockedCannonPositions[side] = nil
            data.MizukiLockedCannonAims[side] = nil
            beams = nil
        end
        if beams and #beams > 0 then
            for index = #beams, 1, -1 do
                local beam = beams[index]
                local laser = beam.Laser
                local delayedEcho = beam.PersistentEchoMode == "automatic"
                local beamShootingHeld = shootingHeld
                if delayedEcho then
                    beamShootingHeld = Mizuki.shouldHoldAutomaticCannonEchoBeam(data, side, beam)
                end
                if beam.PersistentEchoMode and (not beam.Cannon or not beam.Cannon:Exists()
                    or Mizuki.getPersistentCannonEchoMode(player) ~= beam.PersistentEchoMode
                    or beam.Cannon:GetData().MizukiPersistentEchoMode ~= beam.PersistentEchoMode) then
                    -- Only this explicitly identified extra beam is retired.
                    -- Its real counterpart remains under the ordinary controller.
                    if laser and laser:Exists() then laser:Remove() end
                end
                if beam.Ending then
                    if not laser or not laser:Exists() then
                        if not Mizuki.isCannonKnifeAttackActive
                            or not Mizuki.isCannonKnifeAttackActive(beam)
                        then
                            table.remove(beams, index)
                        end
                    else
                        Mizuki.RefreshMizukiBeamAttackParams(
                            player,
                            data,
                            beam,
                            laser,
                            shootingDirection
                        )
                    end
                elseif beam.MomKnifeDriven then
                    if Mizuki.shouldHoldCannonKnifeBeam
                        and Mizuki.shouldHoldCannonKnifeBeam(beam)
                    then
                        local activeDuration = beam.ActiveDuration
                            or math.max(
                                1,
                                (beam.TotalDuration or DEFAULT_BEAM_DURATION)
                                    - (beam.EndFrames
                                        or TECHNOLOGY_BEAM_END_FRAMES)
                            )
                        beam.Timeout = activeDuration
                        if laser and laser:Exists() then
                            laser.Timeout = activeDuration
                        end
                    else
                        beginNaturalMizukiBeamEnding(beam)
                    end
                elseif beam.Automatic and automaticMode and beamShootingHeld then
                    -- Refresh only the full-width portion. The variant's native
                    -- 3 / 10-frame ending is reserved outside this countdown.
                    local activeDuration = beam.ActiveDuration
                        or math.max(
                            1,
                            (beam.TotalDuration or DEFAULT_BEAM_DURATION)
                                - (beam.EndFrames
                                    or TECHNOLOGY_BEAM_END_FRAMES)
                        )
                    beam.Timeout = activeDuration
                    if laser and laser:Exists() then
                        laser.Timeout = activeDuration
                        local currentAim = (delayedEcho or beam.MizukiAutoFire)
                            and beam.Cannon and beam.Cannon:Exists()
                            and beam.Cannon:GetData().MizukiCannonAim
                            or shootingDirection
                        local desiredDirection = currentAim
                            and currentAim:Rotated(beam.DirectionOffset or 0)
                            or nil
                        if desiredDirection
                            and (desiredDirection - beam.Direction):LengthSquared() > Mizuki.RuntimeParameters.DirectionMatchSquaredEpsilon
                        then
                            beam.Direction = desiredDirection
                        end
                    end
                elseif not beam.Ending then
                    beam.Timeout = beam.Automatic and 0 or beam.Timeout - 1
                end
                if not beam.Ending and (not laser or not laser:Exists()) then
                    table.remove(beams, index)
                elseif not beam.Ending and beam.Timeout <= 0 then
                    beginNaturalMizukiBeamEnding(beam)
                elseif not beam.Ending then
                    Mizuki.RefreshMizukiBeamAttackParams(
                        player,
                        data,
                        beam,
                        laser,
                        shootingDirection
                    )
                end
            end

            if #beams == 0 then
                data.MizukiActiveBeams[side] = nil
                data.MizukiLockedCannonPositions[side] = nil
                data.MizukiLockedCannonAims[side] = nil
            else
                for _, beam in ipairs(beams) do
                    if beam.PersistentEchoMode ~= "automatic" then
                        -- An echo's delayed tail never occupies a real cannon
                        -- or postpones the player's next automatic volley.
                        activeSides = activeSides + 1
                        cannonFiringSides = cannonFiringSides + 1
                        break
                    end
                end
            end
        end
    end
    return activeSides, cannonFiringSides
end

local function getCannonBaseScale(cannon)
    local cannonData = cannon:GetData()
    local ludovicoScale = cannonData.MizukiLudovicoOrbiting
        and (cannonData.MizukiLudovicoScaleMultiplier or 1)
        or 1
    local player = cannon.Player
    local baseScale
    if player and player:Exists() then
        baseScale = Vector(
            player.SpriteScale.X * ludovicoScale,
            player.SpriteScale.Y * ludovicoScale
        )
    else
        baseScale = Vector(ludovicoScale, ludovicoScale)
    end
    cannonData.MizukiCannonBaseScale = baseScale
    return baseScale
end

local function applyArtScaleMultiplier(baseScale, artScaleMultiplier)
    return Vector(
        baseScale.X * artScaleMultiplier,
        baseScale.Y * artScaleMultiplier
    )
end

local function getCannonVisualScale(cannon)
    return applyArtScaleMultiplier(
        getCannonBaseScale(cannon),
        CANNON_ART_SCALE_MULTIPLIER
    )
end

local function getCannonBodyRenderScale(cannonData, visualScale, xFactor)
    return Vector(
        visualScale.X * math.abs(xFactor
            or cannonData.MizukiVerticalBodyXFactor or 1),
        visualScale.Y
    )
end

local function updateCannonBodyGraphics(cannon, cannonData)
    local xFactor = cannonData.MizukiVerticalBodyXFactor
    if xFactor == nil then
        xFactor = (cannonData.CannonSide or cannon.SubType) == 1 and -1 or 1
    end
    -- At zero width the old sheet is invisible; keep its sign until the body
    -- emerges on the other side so a zero crossing changes sheets only once.
    local graphicsMode = xFactor < 0 and "left" or "normal"
    if xFactor == 0 then
        graphicsMode = cannonData.MizukiCannonGraphicsMode or graphicsMode
    end
    if cannonData.MizukiCannonGraphicsMode == graphicsMode then
        return
    end

    local sprite = cannon:GetSprite()
    sprite:ReplaceSpritesheet(0, graphicsMode == "left"
        and LEFT_CANNON_SPRITESHEET or CANNON_SPRITESHEET)
    sprite:ReplaceSpritesheet(1, graphicsMode == "left"
        and LEFT_CANNON_LIGHT_SPRITESHEET or CANNON_LIGHT_SPRITESHEET)
    sprite:LoadGraphics()
    sprite.Color = getCannonHiddenColor()
    cannonData.MizukiCannonGraphicsMode = graphicsMode
end

local function getCannonBodyXFactor(side, direction, isIdle)
    local sideSign = side == 1 and -1 or 1
    if isIdle then
        return sideSign
    end
    -- This signed projection controls the body's positive width and selects
    -- its pre-mirrored sheet. It is +/-1 when aiming horizontally, +/-0.75
    -- vertically, and passes through zero near the old graphics-mode switch.
    local aimX = math.max(-1, math.min(1, direction.X))
    local verticalFactor = sideSign * VERTICAL_CANNON_BODY_X_MULTIPLIER
    return (aimX + verticalFactor) / (1 + aimX * verticalFactor)
end

local function getCannonReflectionBodySprite(cannonData, sourceSprite, xFactor)
    local graphicsMode = xFactor < 0 and "left" or "normal"
    if xFactor == 0 then
        graphicsMode = cannonData.MizukiReflectionGraphicsMode or graphicsMode
    end
    cannonData.MizukiReflectionGraphicsMode = graphicsMode
    local sprites = cannonData.MizukiReflectionBodySprites
    if not sprites then
        sprites = {}
        cannonData.MizukiReflectionBodySprites = sprites
    end
    local reflectionSprite = sprites[graphicsMode]
    if not reflectionSprite then
        reflectionSprite = Sprite()
        reflectionSprite:Load(CANNON_ANM2, true)
        reflectionSprite:ReplaceSpritesheet(0, graphicsMode == "left"
            and LEFT_CANNON_SPRITESHEET or CANNON_SPRITESHEET)
        reflectionSprite:ReplaceSpritesheet(1, graphicsMode == "left"
            and LEFT_CANNON_LIGHT_SPRITESHEET or CANNON_LIGHT_SPRITESHEET)
        reflectionSprite:LoadGraphics()
        reflectionSprite:Play("Idle", true)
        sprites[graphicsMode] = reflectionSprite
    end
    reflectionSprite:SetFrame(sourceSprite:GetAnimation(), sourceSprite:GetFrame())
    return reflectionSprite
end

local function getCannonSpriteTransform(cannon, cannonAim, positionAim, idleRotation)
    local cannonData = cannon:GetData()
    local spriteRotation = cannonAim:GetAngleDegrees() + 90 + idleRotation
    local positionBaseRotation = positionAim:GetAngleDegrees() + 90

    -- Keep the cannon's configured bottom-centre pivot fixed in world/render
    -- space instead of trying to compensate through Sprite.Offset. The pivot is
    -- authored in unscaled sprite pixels, so use the cannon's final visual scale
    -- here as well. This keeps the same point attached to the cannon root when
    -- the player's SpriteScale makes the whole weapon larger or smaller.
    local function getPivotOffset(renderScale)
        local scaledPivot = Vector(
            CANNON_IDLE_ROTATION_PIVOT.X * renderScale.X,
            CANNON_IDLE_ROTATION_PIVOT.Y * renderScale.Y
        )
        return scaledPivot:Rotated(positionBaseRotation)
            - scaledPivot:Rotated(spriteRotation)
    end

    local baseScale = getCannonBaseScale(cannon)
    local basePivotRenderOffset = getPivotOffset(applyArtScaleMultiplier(
        baseScale,
        MOMS_KNIFE_ART_SCALE_MULTIPLIER
    ))
    local cannonPivotRenderOffset = getPivotOffset(getCannonBodyRenderScale(
        cannonData,
        applyArtScaleMultiplier(baseScale, CANNON_ART_SCALE_MULTIPLIER)
    ))
    return spriteRotation, cannonPivotRenderOffset, basePivotRenderOffset
end

local function getCannonBeamPivotRenderOffset(player, cannonData)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return cannonData.MizukiBasePivotRenderOffset or Vector.Zero
    end
    return cannonData.MizukiPivotRenderOffset or Vector.Zero
end

-- SpriteScale moves the cannon farther above/below the player's sorting Y even
-- though that extra distance represents visual height, not a different ground
-- depth. Cancel only the scale-created part of the layout Y in DepthOffset.
-- Bobbing and the small idle lift remain real render motion and are untouched.
local function getCannonScaleDepthCompensation(player, cannon)
    local scaleY = player.SpriteScale.Y
    if math.abs(scaleY) < Mizuki.RuntimeParameters.ScaleEpsilon then
        return 0
    end

    local layoutOffset = cannon:GetData().MizukiLayoutOffset
    if not layoutOffset then
        return 0
    end

    local unscaledLayoutY = layoutOffset.Y / scaleY
    return unscaledLayoutY - layoutOffset.Y
end

local function getCannonTargetDepthOffset(
    player,
    cannon,
    isIdle,
    isFiring,
    isFollowingFiring,
    sideIsHorizontal,
    eyeDirection
)
    local baseDepthOffset
    if isIdle then
        baseDepthOffset = IDLE_CANNON_DEPTH_OFFSET
    elseif isFiring and not isFollowingFiring then
        baseDepthOffset = FIRING_CANNON_DEPTH_OFFSET
    elseif sideIsHorizontal then
        baseDepthOffset = eyeDirection.Y > 0
            and HORIZONTAL_FRONT_DEPTH_OFFSET
            or HORIZONTAL_BACK_DEPTH_OFFSET
    else
        baseDepthOffset = CANNON_DEPTH_OFFSET
    end

    if (isIdle or isFiring)
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
    then
        baseDepthOffset = baseDepthOffset + MOMS_KNIFE_DEPTH_OFFSET
    end

    return baseDepthOffset + getCannonScaleDepthCompensation(player, cannon)
end

local function updateCannonDepthOffset(cannon, targetDepthOffset, snap)
    if snap then
        cannon.DepthOffset = targetDepthOffset
        return
    end

    local depthOffset = cannon.DepthOffset
        + (targetDepthOffset - cannon.DepthOffset) * CANNON_FOLLOW_SPEED
    if math.abs(depthOffset - targetDepthOffset) < Mizuki.WeaponParameters.CannonDepthSnapDistance then
        depthOffset = targetDepthOffset
    end
    cannon.DepthOffset = depthOffset
end

local function getCannonPositionWithElasticLag(player, cannon, targetPosition)
    local cannonData = cannon:GetData()
    local targetPoseOffset = targetPosition - player.Position
    local poseOffset = cannonData.MizukiPoseOffset
        or (cannon.Position - player.Position)
    poseOffset = poseOffset
        + (targetPoseOffset - poseOffset) * CANNON_FOLLOW_SPEED
    cannonData.MizukiPoseOffset = poseOffset

    -- Player translation contributes only a small elastic drag. Aim/layout
    -- changes still use the normal pose interpolation above, so capping this
    -- lag does not make large pose changes snap toward their destination.
    local movementLag = cannonData.MizukiMovementLag or Vector.Zero
    local lastPlayerPosition = cannonData.MizukiLastPlayerPosition
    if lastPlayerPosition then
        local playerDelta = player.Position - lastPlayerPosition
        movementLag = (movementLag - playerDelta) * (1 - CANNON_FOLLOW_SPEED)
    else
        movementLag = Vector.Zero
    end
    local lagLength = movementLag:Length()
    if lagLength > CANNON_MAX_FOLLOW_LAG then
        movementLag = movementLag * (CANNON_MAX_FOLLOW_LAG / lagLength)
    end
    cannonData.MizukiMovementLag = movementLag
    cannonData.MizukiLastPlayerPosition = Vector(
        player.Position.X,
        player.Position.Y
    )

    return player.Position + poseOffset + movementLag
end

-- Horizontal cannons may visibly lag behind the player's movement, but that
-- lag must not decide whether they are drawn in front of or behind the player.
-- Ease their intended sorting position relative to the player, then solve the
-- DepthOffset needed to keep that sorting position independent of world-space
-- follow lag.
local function updateHorizontalCannonDepthOffset(
    player,
    cannon,
    cannonPosition,
    targetSortOffset,
    previousSortOffset,
    snap
)
    local cannonData = cannon:GetData()
    local sortOffset = targetSortOffset
    if not snap then
        sortOffset = cannonData.MizukiHorizontalSortOffset
            or previousSortOffset
            or targetSortOffset
        sortOffset = sortOffset
            + (targetSortOffset - sortOffset) * CANNON_FOLLOW_SPEED
        if math.abs(sortOffset - targetSortOffset) < Mizuki.WeaponParameters.CannonDepthSnapDistance then
            sortOffset = targetSortOffset
        end
    end
    cannonData.MizukiHorizontalSortOffset = sortOffset

    local playerSortY = player.Position.Y + player.DepthOffset
    cannon.DepthOffset = playerSortY + sortOffset - cannonPosition.Y
end

-- The shadow is the sprite's own anm2 "shadow" layer and the engine draws it by
-- itself, with whatever transform the sprite is left in. That transform has to be
-- written during the update: the render callback runs after the engine has
-- already drawn the familiar, so anything set there only reaches the next frame
-- and trails the cannon by a frame - which reads as the shadow wobbling.
--
-- The layer lands at the entity position plus Sprite.Offset, so:
--   * ordinary shadows use half the eased reflection distance, while a
--     deployed cannon keeps the charging-height shadow offset;
--     the entity position contains no visual hover bob;
--   * the shadow shares the cannon's player-scaled entity transform; Ludovico
--     additionally includes the ring's visual height in its midpoint offset;
--   * every shadow uses the same horizontal ellipse, so rotation never makes
--     it jump between authored size tiers.
function Mizuki.refreshCannonMomKnifeShadow(cannon)
    local cannonData = cannon:GetData()
    local baseOffset = cannonData.MizukiShadowBaseOffset
    if not baseOffset then
        return
    end
    local knifeDisplacement = Mizuki.getCannonMomKnifeShadowDisplacement
        and Mizuki.getCannonMomKnifeShadowDisplacement(cannon)
        or Vector.Zero
    local offsetUnit = cannonData.MizukiLudovicoOrbiting
        and 1 or CANNON_ART_SCALE_MULTIPLIER
    local shadowOffset = baseOffset + knifeDisplacement * offsetUnit
    cannonData.MizukiShadowOffset = shadowOffset
    cannon:GetSprite().Offset = shadowOffset
end

local function applyCannonShadowPose(player, cannon, isDeployed)
    local cannonData = cannon:GetData()
    -- The entity's own position carries no hover bob (the bob rides the
    -- hand-drawn body instead). The span's target comes from the authored
    -- layout, not a difference between live positions; that would move the
    -- native shadow's offset out of phase with the entity position.
    --
    -- Sprite.Offset is measured in the cannon's authored scale, which is a
    -- constant: it does not follow the player's size. Converting with the
    -- entity's render scale instead only matches at normal size and drifts as
    -- soon as the player grows.
    local offsetUnit = CANNON_ART_SCALE_MULTIPLIER
    local isIdle = cannonData.MizukiIsIdle
    -- A deployed cannon keeps its shadow at charging height even when its
    -- body enters the idle pose. Reflection spacing remains unchanged.
    local span = isDeployed
        and getCannonReflectionSpan(player, false)
        or cannonData.MizukiReflectionSpan
        or getCannonReflectionSpan(player, isIdle)
    local shadowWorldOffsetY = span * 0.5
    if cannonData.MizukiLudovicoOrbiting then
        -- The orbiting body's render plane is raised by the ring offset, and its
        -- reflected copy receives the same offset. Their midpoint therefore
        -- includes that offset as well; only the hitboxes remain at Position.
        local renderWorldOffset = cannonData.MizukiRenderWorldOffset
        shadowWorldOffsetY = shadowWorldOffsetY
            + (renderWorldOffset and renderWorldOffset.Y or 0)
    end
    -- Ludovico's midpoint above is already expressed in world/render pixels.
    -- Applying the cannon's authored 0.65 scale again pulls the shadow back
    -- toward the entity and makes the body/reflection distances asymmetric.
    -- Ordinary cannons retain their established authored-space conversion.
    local offsetY = cannonData.MizukiLudovicoOrbiting
        and shadowWorldOffsetY
        or shadowWorldOffsetY * offsetUnit
    local knifeFollowOffset = not isIdle
        and Mizuki.getCannonMomKnifeFollowOffset
        and Mizuki.getCannonMomKnifeFollowOffset(cannon)
        or Vector.Zero
    local shadowFollowOffset = cannonData.MizukiLudovicoOrbiting
        and knifeFollowOffset
        or knifeFollowOffset * offsetUnit
    local shadowOffset = Vector(
        shadowFollowOffset.X,
        offsetY + shadowFollowOffset.Y
    )
    cannonData.MizukiShadowBaseOffset = shadowOffset
    cannonData.MizukiShadowOffset = shadowOffset
    cannonData.MizukiShadowOffsetY = offsetY

    local sprite = cannon:GetSprite()
    if not sprite:IsPlaying("Idle") then
        sprite:Play("Idle", true)
    end
    sprite.Rotation = 0
    sprite.Offset = shadowOffset
    Mizuki.refreshCannonMomKnifeShadow(cannon)
end

local function updateCannonPositions(player, data, returnAim, snapSide)
    local idleSwingPeriod = Mizuki.WeaponParameters.CannonIdleSwingFrames
    local rotationReturnSpeed = Mizuki.WeaponParameters.CannonRotationReturnRate
    prunePlayerCannons(data)
    local targetPositions = { {}, {} }
    local targetReticle = getMizukiTargetReticle(player, data)
    local aim = returnAim or data.MizukiCannonAim
    local normalizedAim = aim and aim:Normalized() or Vector(0, -1)
    local sideHorizontalStates = {}
    local sideEyeDirections = {}
    local sideFiringStates = {}
    local sideFollowingStates = {}
    local sideFiniteFollowStates = {}
    local sideOrbitDirections = {}
    local anyCannonFiring = false

    -- Resolve each side's beam state once. Position layout, firing pose and
    -- laser synchronization all consume the same result below.
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams
            and data.MizukiActiveBeams[side]
        local isFiring = false
        local isFollowing = false
        local hasFiniteFollower = false
        if beams then
            for _, beam in ipairs(beams) do
                if beam.PersistentEchoMode ~= "automatic" then
                    isFiring = true
                end
                if beam.PersistentEchoMode ~= "automatic" and beam.FollowCannon then
                    isFollowing = true
                    if not beam.Automatic then
                        hasFiniteFollower = true
                    end
                end
            end
        end
        sideFiringStates[side] = isFiring
        sideFollowingStates[side] = isFollowing
        sideFiniteFollowStates[side] = hasFiniteFollower
        anyCannonFiring = anyCannonFiring or isFiring
    end

    local isIdle = not returnAim
        and not data.MizukiHasShootingInput
        and (data.MizukiCharge or 0) <= 0
        and not anyCannonFiring
    local orbitRadius = CANNON_ATTACK_ORBIT_RADIUS
        + (player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            and CANNON_MOMS_KNIFE_ORBIT_RADIUS_BONUS or 0)
    data.MizukiCannonOrbitAngles = data.MizukiCannonOrbitAngles or {}
    for side = 1, 2 do
        -- A finite Anti-Gravity beam keeps only its own side's positional
        -- firing direction. The other side remains free to move to the layout
        -- requested by a new charge, so the pair need not share one axis.
        local sidePositionAim = normalizedAim
        if sideFiniteFollowStates[side] then
            local lockedState = data.MizukiLockedCannonAims
                and data.MizukiLockedCannonAims[side]
            if lockedState and lockedState.PositionAim then
                sidePositionAim = lockedState.PositionAim
            end
        end
        local targetAngle = isIdle and -90
            or sidePositionAim:GetAngleDegrees()
        local orbitAngle = data.MizukiCannonOrbitAngles[side] or -90
        if ((data.MizukiSnapCannonsToDirectAim or snapSide == side)
                and not sideFiringStates[side])
            or (sideFiringStates[side]
                and not sideFollowingStates[side])
        then
            orbitAngle = targetAngle
        else
            local angleDelta = (targetAngle - orbitAngle + 180) % 360 - 180
            orbitAngle = orbitAngle + angleDelta * CANNON_FOLLOW_SPEED
            if math.abs(angleDelta) < Mizuki.WeaponParameters.CannonAngleSnapDegrees then
                orbitAngle = targetAngle
            end
        end
        data.MizukiCannonOrbitAngles[side] = orbitAngle
        local orbitDirection = isIdle
            and Vector(0, -1) or Vector.FromAngle(orbitAngle)
        sideOrbitDirections[side] = orbitDirection
        local sideIsHorizontal = math.abs(orbitDirection.X)
            > math.abs(orbitDirection.Y)
        local sidePositionCharacterLeft = orbitDirection:Rotated(-90)
        local positionEyeDirection = side == 1
            and sidePositionCharacterLeft
            or -sidePositionCharacterLeft
        sideHorizontalStates[side] = sideIsHorizontal
        sideEyeDirections[side] = positionEyeDirection
        for member = 1, #data.MizukiCannons[side] do
            local groupDistance = (member - 1) * CANNON_GROUP_SPACING
            if isIdle then
                local outward = side == 1 and -groupDistance
                    or groupDistance
                local restingOffset = CANNON_OFFSETS[side]
                    + Vector(outward, 0)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, restingOffset)
            else
                -- The pair's midpoint lies on the orbit. Its members sit on
                -- the tangent, with the half-spacing easing from 3 to 5.
                local halfSpacing = HORIZONTAL_CANNON_HALF_SPACING
                    + (VERTICAL_CANNON_X - HORIZONTAL_CANNON_HALF_SPACING)
                        * math.abs(orbitDirection.Y)
                    + groupDistance
                local attackOffset = orbitDirection * orbitRadius
                    + Vector(0, -CANNON_ATTACK_ORBIT_HEIGHT)
                    + positionEyeDirection * halfSpacing
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, attackOffset)
            end
            -- Layout offset for this side and member: where the cannon belongs
            -- for the current aim, with no follow lag in it. A room transition
            -- re-places the cannons from this. Carrying the cannon's actual
            -- position instead would also carry its deliberate follow lag
            -- through the doorway, so the cannon would land slightly out of
            -- place and then visibly coast back.
            local layoutCannon = data.MizukiCannons[side][member]
            if layoutCannon and layoutCannon:Exists() then
                layoutCannon:GetData().MizukiLayoutOffset =
                    Vector(
                        targetPositions[side][member].X,
                        targetPositions[side][member].Y
                    ) - player.Position
            end
        end
    end

    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    for side = 1, 2 do
        local lockedPositions = data.MizukiLockedCannonPositions[side]
        local activeSideBeams = data.MizukiActiveBeams
            and data.MizukiActiveBeams[side]
        if activeSideBeams and #activeSideBeams > 0 and lockedPositions then
            for member = 1, #targetPositions[side] do
                targetPositions[side][member] = lockedPositions[member]
                    or targetPositions[side][member]
            end
        end
    end

    local autoFireState = data.MizukiCannonAutoFireState
    local isDeployed = autoFireState == "deployed"
    local deployedPositions = data.MizukiCannonAutoFirePositions
    if isDeployed then
        for side = 1, 2 do
            for member, cannon in ipairs(data.MizukiCannons[side]) do
                if cannon and cannon:Exists()
                    and not cannon:GetData().MizukiAwaitingInitialLayout
                then
                    local fixedPosition = deployedPositions[side][member]
                    if not fixedPosition then
                        fixedPosition = Vector(cannon.Position.X, cannon.Position.Y)
                        deployedPositions[side][member] = fixedPosition
                    end
                    targetPositions[side][member] = fixedPosition
                end
            end
        end
    end

    data.MizukiCannonPositions = { {}, {} }
    local frame = Game():GetFrameCount()
    for side = 1, 2 do
        local eyeDirection = sideEyeDirections[side]
        local sideIsHorizontal = sideHorizontalStates[side]
        for member, targetPosition in ipairs(targetPositions[side]) do
            local cannon = data.MizukiCannons[side][member]
            local cannonData = cannon:GetData()
            local pairProfile = data.MizukiExpectedCannonPairProfiles
                and data.MizukiExpectedCannonPairProfiles[member]
            Mizuki.applyPersistentCannonEchoProfile(cannon, pairProfile)
            cannonData.MizukiContactDamageMultiplier = pairProfile
                and pairProfile.DamageMultiplier or 1
            Mizuki.updateCannonCollisionSize(
                cannon,
                pairProfile and pairProfile.ScaleMultiplier or 1,
                autoFireState == "returning"
            )
            local sideBeams = data.MizukiActiveBeams
                and data.MizukiActiveBeams[side]
            local isFiring = sideFiringStates[side]
            local isFollowingFiring = sideFollowingStates[side]
            local bobOffset = Vector(
                0,
                Mizuki.getCannonHoverOffset(frame)
            )
            local idleHeightOffset = isIdle
                and getCannonIdleHeightOffset(player)
                or Vector.Zero
            local snapToFiringPosition = isFiring and not isFollowingFiring
            -- The hover bob stays out of the entity's own position. The engine
            -- draws the shadow layer itself, at that position, and it rounds the
            -- position and the sprite offset separately - so any per-frame wobble
            -- in the position shows up as the shadow flipping between two
            -- neighbouring pixels. Only the hand-drawn body carries the bob (see
            -- Mizuki:RenderCannon), which leaves the shadow dead still.
            -- Firing does not suppress that visual motion: the beam and every
            -- locked position still use the resolved logical position, while
            -- only the body, charge circle and reflection consume
            -- MizukiBobOffsetY.
            cannonData.MizukiBobOffsetY = bobOffset.Y
            local fixedPosition = isDeployed
                and deployedPositions[side][member]
            local desiredPosition = (fixedPosition or snapToFiringPosition)
                and targetPosition
                or (targetPosition + idleHeightOffset)
            if autoFireState == "returning" then
                cannonData.MizukiAutoFireReturnTarget = desiredPosition
            else
                cannonData.MizukiAutoFireReturnTarget = nil
            end
            local snapToDirectAimPosition =
                (data.MizukiSnapCannonsToDirectAim or snapSide == side)
                and not isFiring
            local previousSortOffset = cannon.Position.Y + cannon.DepthOffset
                - (player.Position.Y + player.DepthOffset)

            local resolvedCannonPosition
            if cannonData.MizukiPersistentEchoMode == "automatic" then
                -- The delayed source pose below owns this cannon's target.
                -- Do not snap it to today's deployment/direct-aim layout or
                -- add another elastic lag before replaying the recorded pose.
                resolvedCannonPosition = desiredPosition
            elseif cannonData.MizukiAwaitingInitialLayout then
                -- The spawn coordinate and its interpolation history are both
                -- temporary. Hold the Familiar at the first complete layout for
                -- one full game frame before exposing it; showing it in the same
                -- frame as this snap can still render the old interpolated point.
                resolvedCannonPosition = desiredPosition
                cannon.Position = resolvedCannonPosition
                cannon.Velocity = Vector.Zero
                cannonData.MizukiPoseOffset = desiredPosition - player.Position
                cannonData.MizukiMovementLag = Vector.Zero
                cannonData.MizukiLastPlayerPosition = Vector(
                    player.Position.X,
                    player.Position.Y
                )
                local settledFrame = cannonData.MizukiInitialLayoutFrame
                if settledFrame and frame > settledFrame then
                    cannonData.MizukiAwaitingInitialLayout = nil
                    cannonData.MizukiInitialLayoutFrame = nil
                elseif not settledFrame then
                    cannonData.MizukiInitialLayoutFrame = frame
                end
            elseif fixedPosition or snapToFiringPosition
                or snapToDirectAimPosition then
                -- A stationary cannon keeps its captured world position. Firing
                -- and the first direct-aim frame also resolve without follow lag.
                resolvedCannonPosition = desiredPosition
                cannon.Position = resolvedCannonPosition
                cannon.Velocity = Vector.Zero
                cannonData.MizukiPoseOffset = desiredPosition - player.Position
                cannonData.MizukiMovementLag = Vector.Zero
                cannonData.MizukiLastPlayerPosition = Vector(
                    player.Position.X,
                    player.Position.Y
                )
            else
                resolvedCannonPosition = getCannonPositionWithElasticLag(
                    player,
                    cannon,
                    desiredPosition
                )
            end
            cannonData.MizukiDesiredPosition = resolvedCannonPosition

            local targetDepthOffset = getCannonTargetDepthOffset(
                player,
                cannon,
                isIdle,
                isFiring,
                isFollowingFiring,
                sideIsHorizontal,
                eyeDirection
            )
            if snapToFiringPosition
                and cannonData.MizukiLockedFiringDepthOffset ~= nil
            then
                -- A finite shot locks position and depth as one pose. Preserve
                -- the offset each cannon had when firing began instead of
                -- moving every cannon onto one shared firing layer.
                targetDepthOffset = cannonData.MizukiLockedFiringDepthOffset
            elseif not snapToFiringPosition then
                cannonData.MizukiLockedFiringDepthOffset = nil
            end
            if sideIsHorizontal and not snapToFiringPosition then
                -- Use the authored target pose to choose the intended sorting
                -- layer, but solve DepthOffset from the position the Familiar
                -- reaches after its velocity is applied this frame. Player
                -- movement can therefore create a small visible lag without
                -- ever dragging a horizontal cannon through the body.
                local targetSortOffset = desiredPosition.Y + targetDepthOffset
                    - (player.Position.Y + player.DepthOffset)
                updateHorizontalCannonDepthOffset(
                    player,
                    cannon,
                    resolvedCannonPosition,
                    targetSortOffset,
                    previousSortOffset,
                    snapToDirectAimPosition
                )
            else
                cannonData.MizukiHorizontalSortOffset = nil
                -- Snap depth whenever the position snaps, including the first
                -- direct-aim frame before its immediate beam is created.
                updateCannonDepthOffset(
                    cannon,
                    targetDepthOffset,
                    snapToFiringPosition or snapToDirectAimPosition
                )
            end
            local lockedCannonState = data.MizukiLockedCannonAims[side]
            local lockedPositionAim = lockedCannonState
                and lockedCannonState.PositionAim
            local lockedCannonAim = lockedCannonState
                and lockedCannonState.MemberAims[member]
            local cannonAim = lockedCannonAim
                or aim or Vector(0, -1)
            if autoFireState == "deployed" and not lockedCannonAim then
                cannonAim = Mizuki.getCannonAutoFireAim(player, data, member)
            end
            cannon.Visible = not cannonData.MizukiAwaitingInitialLayout
            cannonData.CannonSide = side
            cannonData.MizukiRenderWorldOffset = nil
            cannonData.MizukiLudovicoOrbiting = nil
            cannonData.MizukiLudovicoDamageMultiplier = nil
            cannonData.MizukiLudovicoScaleMultiplier = nil
            -- Read by Mizuki:RenderCannon to pick the resting or firing
            -- reflection distance and mirroring.
            cannonData.MizukiIsIdle = isIdle
            -- Keep the native shadow on the snapped pose; its position uses
            -- half this span, so easing it after a direct-aim snap would make
            -- the shadow visibly slide in from the old idle location.
            local targetSpan = getCannonReflectionSpan(player, isIdle)
            local smoothSpan = cannonData.MizukiReflectionSpan
            if smoothSpan == nil or snapToFiringPosition
                or snapToDirectAimPosition
            then
                cannonData.MizukiReflectionSpan = targetSpan
            else
                smoothSpan = smoothSpan
                    + (targetSpan - smoothSpan) * CANNON_REFLECTION_SPAN_SPEED
                if math.abs(smoothSpan - targetSpan) < Mizuki.WeaponParameters.CannonReflectionSnapDistance then
                    smoothSpan = targetSpan
                end
                cannonData.MizukiReflectionSpan = smoothSpan
            end
            local sideIdleRotation = side == 1
                and LEFT_CANNON_IDLE_ROTATION
                or RIGHT_CANNON_IDLE_ROTATION
            local idleRotationTarget = isIdle and sideIdleRotation
                or 0
            if snapToDirectAimPosition then
                -- Position and pose resolve together before the immediate beam
                -- samples its origin.
                cannonData.MizukiIdleRotationOffset = idleRotationTarget
            elseif cannonData.MizukiIdleRotationOffset == nil then
                cannonData.MizukiIdleRotationOffset = idleRotationTarget
            else
                cannonData.MizukiIdleRotationOffset = cannonData.MizukiIdleRotationOffset
                    + (idleRotationTarget - cannonData.MizukiIdleRotationOffset)
                    * rotationReturnSpeed
                if math.abs(cannonData.MizukiIdleRotationOffset - idleRotationTarget) < Mizuki.WeaponParameters.CannonAngleSnapDegrees then
                    cannonData.MizukiIdleRotationOffset = idleRotationTarget
                end
            end
            -- The body points toward the attack aim, while its pivot starts
            -- from the current orbit heading. A finite beam keeps its locked
            -- orbit heading even if the player's live input changes.
            local idleRotation = cannonData.MizukiIdleRotationOffset
            if isIdle then
                local swingFrame = cannonData.MizukiIdleSwingFrame or 0
                local swingProgress = (1 - math.cos(
                    swingFrame * 2 * math.pi / idleSwingPeriod
                )) * 0.5
                local outerRotation = side == 1
                    and LEFT_CANNON_IDLE_OUTER_ROTATION
                    or RIGHT_CANNON_IDLE_OUTER_ROTATION
                local inwardRotation = side == 1
                    and LEFT_CANNON_IDLE_ROTATION
                    or RIGHT_CANNON_IDLE_ROTATION
                idleRotation = idleRotation
                    + (outerRotation - inwardRotation) * swingProgress
                cannonData.MizukiIdleSwingFrame =
                    (swingFrame + 1) % idleSwingPeriod
            else
                -- Every new idle interval starts at the existing inward pose.
                cannonData.MizukiIdleSwingFrame = nil
            end
            local sprite = cannon:GetSprite()
            local target = autoFireState ~= "deployed"
                and targetReticle or nil
            local spritePositionAim = lockedPositionAim
                or sideOrbitDirections[side]
            if autoFireState == "deployed" then
                spritePositionAim = cannonAim
            end
            cannonData.MizukiVerticalBodyXFactor = getCannonBodyXFactor(
                side, spritePositionAim, isIdle
            )
            if isIdle then
                cannonData.MizukiReflectionBodyXFactor = nil
            else
                -- Each cannon keeps its own reflection. Mirroring the horizontal
                -- aim makes the other cannon reach the edge-on flip on a sideways
                -- turn, while both match their bodies at vertical aim.
                local reflectionAim = Vector(
                    -spritePositionAim.X, spritePositionAim.Y
                )
                cannonData.MizukiReflectionBodyXFactor = getCannonBodyXFactor(
                    side, reflectionAim, false
                )
            end
            updateCannonBodyGraphics(cannon, cannonData)
            if target and not lockedCannonAim then
                for _ = 1, 2 do
                    local _, cannonTrialOffset, knifeTrialOffset = getCannonSpriteTransform(
                        cannon,
                        cannonAim,
                        spritePositionAim,
                        idleRotation
                    )
                    local trialOffset = player:HasCollectible(
                        CollectibleType.COLLECTIBLE_MOMS_KNIFE
                    ) and knifeTrialOffset or cannonTrialOffset
                    cannonAim = resolveBeamGeometry(
                        resolvedCannonPosition + trialOffset,
                        cannonAim,
                        0,
                        target.Position
                    )
                end
            end
            local spriteRotation, pivotRenderOffset, basePivotRenderOffset = getCannonSpriteTransform(
                cannon,
                cannonAim,
                spritePositionAim,
                idleRotation
            )
            cannonData.MizukiPivotRenderOffset = pivotRenderOffset
            -- The pose lives in the data, not on the sprite, so the engine's own
            -- draw of the sprite stays straightened for the shadow layer.
            cannonData.MizukiCannonBodyRotation = spriteRotation
            cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
            sprite.Rotation = 0
            applyCannonShadowPose(player, cannon, isDeployed)
            -- Hide the engine's own draw; Mizuki:RenderCannon replaces it in
            -- the same render slot and draws the water reflection separately.
            -- Alpha is used instead of Visible on purpose:
            -- an invisible entity stops being rendered, which would also stop
            -- the render callback that re-draws it.
            sprite.Color = getCannonHiddenColor()
            cannonData.MizukiCannonAim = cannonAim
            resolvedCannonPosition = Mizuki.updateAutomaticCannonEchoPose(
                player, data, cannon, resolvedCannonPosition, member, side, frame
            )
            if cannonData.MizukiPersistentEchoMode == "automatic" then
                updateCannonBodyGraphics(cannon, cannonData)
                applyCannonShadowPose(player, cannon, isDeployed)
            end
            data.MizukiCannonPositions[side][member] = Vector(
                resolvedCannonPosition.X,
                resolvedCannonPosition.Y
            )

            -- The resolved position, rotation and render offset are final here.
            -- Keep every cannon-following beam transform in this single update
            -- path so later callbacks cannot overwrite one another. Automatic
            -- beams and finite Anti-Gravity beams share only this positioning;
            -- their firing cadence and lifetime remain separate.
            local sideBeams = data.MizukiActiveBeams
                and data.MizukiActiveBeams[side]
            if sideBeams then
                for _, beam in ipairs(sideBeams) do
                    local laser = beam.Laser
                    if beam.FollowCannon
                        and beam.Cannon
                        and GetPtrHash(beam.Cannon) == GetPtrHash(cannon)
                        and laser
                        and laser:Exists()
                    then
                        local pivotRenderOffset = getCannonBeamPivotRenderOffset(
                            player, cannonData
                        )
                        -- Reticle geometry follows the logical firing origin.
                        -- Visual bob belongs only to the hand-drawn cannon body.
                        local visualOrigin = resolvedCannonPosition
                            + pivotRenderOffset
                        -- Finite Anti-Gravity shots follow only the cannon's
                        -- position. Keep their fired direction and distance;
                        -- live reticle tracking remains an automatic-beam rule.
                        local target = beam.Automatic
                            and not beam.PersistentEchoMode
                            and not beam.MizukiAutoFire and targetReticle or nil
                        local directionOffset = beam.DirectionOffset or 0
                        local baseDirection = beam.Direction:Rotated(
                            -directionOffset
                        )
                        if beam.PersistentEchoMode == "automatic" then
                            baseDirection = cannonData.MizukiCannonAim or baseDirection
                        end
                        local originCorrection
                        beam.Direction, originCorrection = resolveBeamGeometry(
                            visualOrigin,
                            baseDirection,
                            directionOffset,
                            target and target.Position or nil
                        )
                        local hitboxOffset = Vector(0, BEAM_HITBOX_Y_OFFSET)
                        laser.AngleDegrees = beam.Direction:GetAngleDegrees()
                        laser.Position = resolvedCannonPosition
                            + pivotRenderOffset
                            + hitboxOffset
                            + originCorrection
                        laser.PositionOffset = -hitboxOffset
                        local reflectionDepthShift =
                            applyMizukiBeamReflectionHeight(player, laser)
                        laser.Velocity = Vector.Zero
                        laser.DepthOffset = cannon.DepthOffset - Mizuki.WeaponParameters.BeamDepthBehindCannon
                            - hitboxOffset.Y
                            - originCorrection.Y
                            - reflectionDepthShift
                        if target then
                            local targetDistance = (
                                target.Position
                                - (visualOrigin + originCorrection)
                            ):Length()
                            laser:SetMaxDistance(math.max(1, targetDistance))
                        end
                    end
                end
            end
        end
    end
end

local function updateCannonReconcile(player, data)
    local reconcileState = getCannonReconcileState(player)
    if not reconcileState.Frames then
        return
    end

    reconcileState.Frames = reconcileState.Frames - 1
    if reconcileState.Frames <= 0 then
        reconcileState.Frames = nil
        reconcilePlayerCannons(player, data)
    end
end

local function hasActiveMizukiBeam(data)
    local activeBeams = data.MizukiActiveBeams or {}

    for side = 1, 2 do
        local beams = activeBeams[side]
        if beams then
            for _, beam in ipairs(beams) do
                if beam.Laser and beam.Laser:Exists() and beam.Timeout > 0 then
                    return true
                end
            end
        end
    end
    return false
end


-- Roll only the temporary, per-attack direction effects. Ordinary firing and
-- Ludovico both consume this one result for the whole volley, so adding cannon
-- copies never grants extra independent proc chances.
local function getMizukiTransientBeamEffects(player, blockedSources)
    local effects = {
        BookWormBonus = 0,
        Sources = {},
    }
    blockedSources = blockedSources or {}

    if not blockedSources[TRANSIENT_BEAM_SOURCE_BOOK_WORM]
        and player:HasPlayerForm(PlayerForm.PLAYERFORM_BOOK_WORM)
        and player:GetDropRNG():RandomFloat() < Mizuki.WeaponParameters.BookWormBonusChance
    then
        effects.BookWormBonus = 1
        effects.Sources[TRANSIENT_BEAM_SOURCE_BOOK_WORM] = { 0 }
    end

    local momsEye = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYE)
    local lokisHorns = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LOKIS_HORNS
    )
    if momsEye and not blockedSources[TRANSIENT_BEAM_SOURCE_MOMS_EYE] then
        local chance = math.max(0, math.min(1, Mizuki.WeaponParameters.MomsEyeBaseChance + player.Luck * Mizuki.WeaponParameters.MomsEyeLuckStep))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MOMS_EYE
        ):RandomFloat() < chance then
            local angles = { 180 }
            if lokisHorns then
                table.insert(angles, -90)
                table.insert(angles, 90)
            end
            effects.Sources[TRANSIENT_BEAM_SOURCE_MOMS_EYE] = angles
        end
    end
    if lokisHorns
        and not blockedSources[TRANSIENT_BEAM_SOURCE_LOKIS_HORNS]
    then
        local chance = math.max(0, math.min(1, Mizuki.WeaponParameters.LokisHornsBaseChance + player.Luck * Mizuki.WeaponParameters.LokisHornsLuckStep))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_LOKIS_HORNS
        ):RandomFloat() < chance then
            -- Ordinary fire already owns its forward beam. Ludovico has no
            -- equivalent transient shot, so retain 0 degrees in the source and
            -- let the ordinary layout skip it below.
            effects.Sources[TRANSIENT_BEAM_SOURCE_LOKIS_HORNS] = {
                0,
                180,
                -90,
                90,
            }
        end
    end

    if not blockedSources[TRANSIENT_BEAM_SOURCE_EYE_SORE]
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_SORE)
    then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_EYE_SORE
        )
        local angles = {}
        for _ = 1, rng:RandomInt(Mizuki.WeaponParameters.EyeSoreCountBound) do
            table.insert(angles, rng:RandomFloat() * 360)
        end
        if #angles > 0 then
            effects.Sources[TRANSIENT_BEAM_SOURCE_EYE_SORE] = angles
        end
    end

    return effects
end


local function appendUniqueBeamAngle(angles, angleOffset)
    for _, existingAngle in ipairs(angles) do
        local difference = (existingAngle - angleOffset + 180) % 360 - 180
        if math.abs(difference) < Mizuki.RuntimeParameters.AngleMatchEpsilon then
            return
        end
    end
    table.insert(angles, angleOffset)
end


local function getMizukiBeamAngleOffsets(player)
    local transientEffects = getMizukiTransientBeamEffects(player)
    local profile = getMizukiStandardBeamProfile(
        player,
        transientEffects.BookWormBonus
    )

    local angles = {}
    for group = 1, profile.WizGroups do
        local center = 0
        if profile.WizGroups > 1 then
            center = -WIZ_ARC_HALF_ANGLE
                + (group - 1) * (WIZ_ARC_HALF_ANGLE * 2)
                    / (profile.WizGroups - 1)
        end
        Mizuki.appendCenteredBeamAngles(
            angles,
            center,
            profile.BeamsPerWizGroup,
            profile.TotalSpread
        )
    end

    if player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY) then
        table.insert(angles, -CONJOINED_SIDE_ANGLE)
        table.insert(angles, CONJOINED_SIDE_ANGLE)
    end

    for _, source in ipairs({
        TRANSIENT_BEAM_SOURCE_MOMS_EYE,
        TRANSIENT_BEAM_SOURCE_LOKIS_HORNS,
        TRANSIENT_BEAM_SOURCE_EYE_SORE,
    }) do
        for index, angleOffset in ipairs(
            transientEffects.Sources[source] or {}
        ) do
            -- Loki's Horns owns a forward direction in Ludovico. Ordinary fire
            -- already contains that shot in its stable layout.
            if source ~= TRANSIENT_BEAM_SOURCE_LOKIS_HORNS or index > 1 then
                appendUniqueBeamAngle(angles, angleOffset)
            end
        end
    end

    local lungCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG
    )
    if lungCount > 0 then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MONSTROS_LUNG
        )
        local minExtra = Mizuki.WeaponParameters.LungMinExtraBeams + Mizuki.WeaponParameters.LungMinExtraPerCopy * (lungCount - 1)
        local maxExtra = Mizuki.WeaponParameters.LungMaxExtraBeams + Mizuki.WeaponParameters.LungMaxExtraPerCopy * (lungCount - 1)
        local extraCount = minExtra + rng:RandomInt(maxExtra - minExtra + 1)
        for _ = 1, extraCount do
            table.insert(angles, rng:RandomFloat() * 360)
        end
    end

    return angles
end

local function removeBeamsOutsideFiniteVolley(data, side, finiteVolleyId)
    data.MizukiActiveBeams = data.MizukiActiveBeams or {}
    local beams = data.MizukiActiveBeams[side]
    if beams then
        for index = #beams, 1, -1 do
            local beam = beams[index]
            if finiteVolleyId == nil
                or beam.FiniteVolleyId ~= finiteVolleyId
            then
                if Mizuki.cancelCannonKnifeBeam then
                    Mizuki.cancelCannonKnifeBeam(beam)
                end
                local laser = beam.Laser
                if laser and laser:Exists() then
                    laser:Remove()
                end
                table.remove(beams, index)
            end
        end
        if #beams == 0 then
            data.MizukiActiveBeams[side] = nil
            data.MizukiLockedCannonPositions[side] = nil
            data.MizukiLockedCannonAims[side] = nil
        end
    end
end

-- The weapon's beam comes from one of two native sources, and everything else
-- about the shot is identical either way: Technology's laser is the default,
-- and with Brimstone the engine's own charged blood laser takes its place. Only
-- the creation call differs, so the beam keeps the same origin, damage, flags
-- and lifetime below and Brimstone synergies see a real brimstone laser.
local function fireMizukiWeaponBeam(
    player,
    origin,
    direction,
    leftEye,
    damageMultiplier,
    widthScale
)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        local nativeLaser = player:FireBrimstone(
            direction,
            player,
            damageMultiplier
        )

        if widthScale < Mizuki.WeaponParameters.ThickBrimstoneWidthThreshold
            or nativeLaser.Variant ~= LaserVariant.THICK_RED
        then
            return nativeLaser
        end

        -- The thick variant is a separate laser entity: the player API only ever
        -- produces the ordinary one and a laser has no ChangeVariant method, so
        -- the thick shot is spawned through ShootAngle and the ordinary entity
        -- is dropped. The firing sound and player-side initialization already
        -- happened in the FireBrimstone call above; color and flags are carried
        -- over, and the new laser keeps the engine's own thick sizing (measured
        -- Size 32 against the ordinary 16 at the same player state), so it stays
        -- twice as thick instead of being normalised back to the thin beam.
        local thickerLaser = EntityLaser.ShootAngle(
            LaserVariant.THICKER_RED,
            origin,
            direction:GetAngleDegrees(),
            1,
            Vector.Zero,
            player
        )
        thickerLaser.Color = nativeLaser.Color
        thickerLaser.TearFlags = nativeLaser.TearFlags
        thickerLaser.CollisionDamage = nativeLaser.CollisionDamage
        local thickerData = thickerLaser:GetData()
        thickerData.MizukiBeamReferenceSize = nativeLaser.Size
        -- ShootAngle creates a fresh entity and therefore does not retain the
        -- damage multiplier passed to FireBrimstone. Preserve it only on this
        -- replacement variant; ordinary player-API lasers already own theirs.
        thickerData.MizukiRecoverBeamDamageMultiplier = damageMultiplier
        nativeLaser:Remove()
        return thickerLaser
    end

    return player:FireTechLaser(
        origin,
        LaserOffset.LASER_TECH1_OFFSET,
        direction,
        leftEye,
        false,
        player,
        damageMultiplier
    )
end

local function fireMizukiBeam(
    player,
    direction,
    charge,
    automatic,
    forcedSide,
    finiteVolleyId,
    damageMultiplierOverride,
    echoOnlyAngles,
    echoAttack
)
    local data = player:GetData()
    local deployedAutoFire = data.MizukiCannonAutoFireState == "deployed"
    local chargeProfile = getChargeProfile(player)
    local isFiniteShot = not automatic
    local followCannon = automatic
        or (isFiniteShot
            and player:HasCollectible(
                CollectibleType.COLLECTIBLE_ANTI_GRAVITY
            ))
    local usesFiniteVolleyId = false
    if isFiniteShot then
        usesFiniteVolleyId = finiteVolleyId ~= nil
            or player:HasCollectible(
                CollectibleType.COLLECTIBLE_CURSED_EYE
            )
        if usesFiniteVolleyId then
            if not finiteVolleyId then
                data.MizukiFiniteVolleyId =
                    (data.MizukiFiniteVolleyId or 0) + 1
                finiteVolleyId = data.MizukiFiniteVolleyId
            end
        end
    end
    local firingSides
    if forcedSide then
        firingSides = { forcedSide }
    elseif automatic then
        firingSides = { 1, 2 }
    else
        data.MizukiShotSide = -(data.MizukiShotSide or -1)
        firingSides = { data.MizukiShotSide == -1 and 1 or 2 }
    end

    if isFiniteShot then
        -- Every cannon side owns its own finite attack. Ordinary shots clear
        -- all older beams on that side; Cursed Eye retains only beams carrying
        -- the current volley id. Neither path touches the opposite cannon.
        for _, side in ipairs(firingSides) do
            removeBeamsOutsideFiniteVolley(
                data,
                side,
                usesFiniteVolleyId and finiteVolleyId or nil
            )
        end
    end

    local beamDistance = getBeamDistance(player)
    local beamWidthScale = getBeamWidthScale(player)
    local isBrimstoneBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    )
    local isTechnologyZeroBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
    )
    local beamDuration, damagePerTickMultiplier =
        getBeamDamageTiming(
            player,
            automatic,
            isBrimstoneBeam,
            isTechnologyZeroBeam
        )
    local beamEndFrames = getBeamEndFrames(isBrimstoneBeam)
    local beamActiveDuration = math.max(1, beamDuration - beamEndFrames)
    -- Ordinary shots reach 1x damage at BaseFrames. Chocolate Milk can extend
    -- the same charge beyond that point instead of merely storing extra time.
    local chargeDamageMultiplier = getChargeDamageMultiplier(
        charge,
        chargeProfile
    )
    -- The charge is shared by every beam in this shot; each cannon's eye and
    -- per-tick factors are combined with it at the native firing call.
    local damageMultiplier = damageMultiplierOverride
        or chargeDamageMultiplier
    local beamAngleOffsets = echoOnlyAngles or getMizukiBeamAngleOffsets(player)
    -- Record resolved attacks, never re-enter this firing controller to replay
    -- them. Echoes must not change real cannon sides, occupancy or charge.
    local echoShot = isFiniteShot and Mizuki.beginCannonEchoShot
        and Mizuki.beginCannonEchoShot(player, firingSides[1], finiteVolleyId)
        or nil
    local targetReticle = not deployedAutoFire
        and getMizukiTargetReticle(player, data) or nil
    if not echoOnlyAngles then
        tryFireImmaculateHeartTear(player, direction)
        advanceLeadPencil(player, direction)
        data.MizukiExtraAttackFrame = Game():GetFrameCount()
    end
    for _, side in ipairs(firingSides) do
        local origins = data.MizukiCannonPositions[side]
        if origins and #origins > 0 then
            -- Automatic beams and finite Anti-Gravity shots follow their
            -- cannon instead of freezing it at the firing position. This does
            -- not change the finite shot's charge, duration or firing cadence.
            if automatic then
                data.MizukiLockedCannonPositions[side] = nil
                data.MizukiLockedCannonAims[side] = nil
            else
                data.MizukiLockedCannonPositions[side] =
                    followCannon and nil or {}
                local orbitAngles = data.MizukiCannonOrbitAngles
                local orbitAngle = orbitAngles and orbitAngles[side]
                local lockedPositionAim = orbitAngle
                    and Vector.FromAngle(orbitAngle)
                    or direction:Normalized()
                data.MizukiLockedCannonAims[side] = {
                    PositionAim = lockedPositionAim,
                    MemberAims = {},
                }
            end
            data.MizukiActiveBeams[side] =
                data.MizukiActiveBeams[side] or {}
            for member, origin in ipairs(origins) do
                local firingCannon = data.MizukiCannons[side]
                    and data.MizukiCannons[side][member]
                local hasFiringCannon = firingCannon
                    and firingCannon:Exists()
                local persistentEchoMode = hasFiringCannon
                    and firingCannon:GetData().MizukiPersistentEchoMode or nil
                if (echoOnlyAngles and persistentEchoMode == "automatic")
                    or (not echoOnlyAngles and persistentEchoMode ~= "automatic") then
                    local memberDirection = deployedAutoFire
                        and hasFiringCannon
                        and Mizuki.getCannonAutoFireAim(player, data, member)
                        or direction
                    if persistentEchoMode == "automatic" then
                        memberDirection = firingCannon:GetData().MizukiCannonAim or memberDirection
                    end

                    if isFiniteShot then
                        if not followCannon then
                            data.MizukiLockedCannonPositions[side][member] = Vector(
                                origin.X,
                                origin.Y
                            )
                        end
                        local firingAim = deployedAutoFire and memberDirection
                            or firingCannon
                            and firingCannon:GetData().MizukiCannonAim
                            or direction
                        data.MizukiLockedCannonAims[side].MemberAims[member] = Vector(
                            firingAim.X,
                            firingAim.Y
                        )
                    end

                    local visualOrigin = origin
                    if hasFiringCannon then
                        local firingCannonData = firingCannon:GetData()
                        visualOrigin = origin
                            + getCannonBeamPivotRenderOffset(
                                player, firingCannonData
                            )
                        if isFiniteShot then
                            firingCannonData.MizukiLockedFiringDepthOffset =
                                firingCannon.DepthOffset
                        end
                    end

                    -- Eye-specific item bonuses remain native. Player-sourced
                    -- Technology and Brimstone lasers apply them per damage tick;
                    -- pre-applying them here would duplicate the native bonus.
                    local apiDamageMultiplier = damageMultiplier
                        * damagePerTickMultiplier
                        * (persistentEchoMode and Mizuki.CannonEchoDamageMultiplier or 1)
                    for _, angleOffset in ipairs(beamAngleOffsets) do
                        local target = not persistentEchoMode and targetReticle or nil
                        local beamDirection, originCorrection = resolveBeamGeometry(
                            visualOrigin,
                            memberDirection,
                            angleOffset,
                            target and target.Position or nil
                        )
                        local hitboxOffset = Vector(0, BEAM_HITBOX_Y_OFFSET)
                        local hitboxOrigin = visualOrigin
                            + hitboxOffset
                            + originCorrection
                        local currentBeamDistance = beamDistance
                        if target then
                            currentBeamDistance = math.max(
                                1,
                                (
                                    target.Position
                                    - (visualOrigin + originCorrection)
                                ):Length()
                            )
                        end
                        local laser = fireMizukiWeaponBeam(
                            player,
                            hitboxOrigin,
                            beamDirection,
                            side == 1,
                            apiDamageMultiplier,
                            beamWidthScale
                        )
                        laser.DisableFollowParent = true
                        if followCannon and firingCannon then
                            laser.Parent = firingCannon
                        end
                        laser.Position = hitboxOrigin
                        laser.PositionOffset = -hitboxOffset
                        local reflectionDepthShift =
                            applyMizukiBeamReflectionHeight(player, laser)
                        laser.Velocity = Vector.Zero
                        laser.DepthOffset = (firingCannon
                            and firingCannon.DepthOffset
                            or CANNON_DEPTH_OFFSET) - Mizuki.WeaponParameters.BeamDepthBehindCannon
                            - hitboxOffset.Y
                            - originCorrection.Y
                            - reflectionDepthShift
                        laser.Timeout = beamActiveDuration
                        laser:SetOneHit(false)
                        laser:SetMaxDistance(currentBeamDistance)
                        local laserData = laser:GetData()
                        laser.TearFlags = addOccultHoming(player, laser.TearFlags)
                            & ~MIZUKI_FORBIDDEN_TEAR_FLAGS

                        laserData.MizukiBeam = true
                        laserData.MizukiBeamOwner = player
                        laserData.MizukiBeamWidthScale = beamWidthScale
                        laserData.MizukiBeamAutomatic = automatic
                        if persistentEchoMode then
                            laser.Color = Mizuki.getPersistentEchoColor(laser.Color)
                        end
                        if laserData.MizukiRecoverBeamDamageMultiplier then
                            laserData.MizukiAwaitingNativeDamageRefresh = true
                            laserData.MizukiLastAdjustedCollisionDamage =
                                laser.CollisionDamage
                        end

                        local beam = {
                            Laser = laser,
                            Origin = Vector(origin.X, origin.Y),
                            Direction = Vector(beamDirection.X, beamDirection.Y),
                            DirectionOffset = angleOffset,
                            Distance = currentBeamDistance,
                            Timeout = beamActiveDuration,
                            ActiveDuration = beamActiveDuration,
                            TotalDuration = beamDuration + beamEndFrames,
                            EndFrames = beamEndFrames,
                            DamageMultiplier = damageMultiplier,
                            DamagePerTickMultiplier = damagePerTickMultiplier,
                            LeftEye = side == 1,
                            Automatic = automatic,
                            FollowCannon = followCannon,
                            Cannon = firingCannon,
                            PersistentEchoMode = persistentEchoMode,
                            PersistentEchoSourceSeed = echoAttack and echoAttack.SourceSeed,
                            PersistentEchoSourceHash = echoAttack and echoAttack.SourceHash,
                            MizukiAutoFire = deployedAutoFire,
                            FiniteVolleyId = finiteVolleyId,
                        }
                        table.insert(data.MizukiActiveBeams[side], beam)
                        if isFiniteShot
                            and hasFiringCannon
                            and Mizuki.fireCannonMomKnife
                        then
                            Mizuki.fireCannonMomKnife(
                                firingCannon,
                                beam,
                                charge,
                                chargeProfile.BaseChargeFrames
                            )
                        end
                        if echoShot and Mizuki.captureCannonEchoBeam then
                            Mizuki.captureCannonEchoBeam(
                                echoShot, beam, charge, chargeProfile.BaseChargeFrames
                            )
                        end
                    end
                end -- Originals fire now; automatic echoes use the delayed sample.
            end
        end
    end
    if automatic and not echoOnlyAngles then
        -- Position layout was sampled earlier this frame. Add this newly fired
        -- attack to that SAME frame rather than introducing a seventh frame.
        Mizuki.captureAutomaticCannonEchoAttacks(player, data)
    end
    return finiteVolleyId
end

local function removeLudovicoTriggeredBeams(data)
    for _, beam in ipairs(data.MizukiLudovicoTriggeredBeams or {}) do
        local laser = beam.Laser
        if laser and laser:Exists() then
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
                beginNaturalMizukiBeamEnding(beam)
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


local function fireLudovicoTriggeredBeams(player, data)
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
    local interval = math.max(player.MaxFireDelay, 1) + 1
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
    local transientEffects = getMizukiTransientBeamEffects(
        player,
        activeSources
    )
    local angleEntries = {}
    for _, source in ipairs({
        TRANSIENT_BEAM_SOURCE_BOOK_WORM,
        TRANSIENT_BEAM_SOURCE_MOMS_EYE,
        TRANSIENT_BEAM_SOURCE_LOKIS_HORNS,
        TRANSIENT_BEAM_SOURCE_EYE_SORE,
    }) do
        for _, angleOffset in ipairs(
            transientEffects.Sources[source] or {}
        ) do
            appendLudovicoTriggeredAngle(angleEntries, angleOffset, source)
        end
    end
    if #angleEntries == 0 then return end

    local beamDistance = getBeamDistance(player)
    local beamWidthScale = getBeamWidthScale(player)
    local isBrimstoneBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    )
    local isTechnologyZeroBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
    )
    local beamDuration, damagePerTickMultiplier = getBeamDamageTiming(
        player,
        false,
        isBrimstoneBeam,
        isTechnologyZeroBeam
    )
    local beamEndFrames = getBeamEndFrames(isBrimstoneBeam)
    local beamActiveDuration = math.max(1, beamDuration - beamEndFrames)
    data.MizukiLudovicoTriggeredBeams =
        data.MizukiLudovicoTriggeredBeams or {}

    for side = 1, 2 do
        for _, cannon in ipairs(cannons[side] or {}) do
            if cannon and cannon:Exists() then
                local cannonData = cannon:GetData()
                if cannonData.MizukiLudovicoOrbiting then
                    local tangentDirection = cannonData.MizukiCannonAim
                        or Vector(0, -1)
                    local visualOrigin = cannon.Position
                        + (cannonData.MizukiPivotRenderOffset or Vector.Zero)
                    local damageMultiplier =
                        (cannonData.MizukiLudovicoDamageMultiplier or 1)
                        * LUDOVICO_TRIGGERED_BEAM_DAMAGE_MULTIPLIER
                    local apiDamageMultiplier = damageMultiplier
                        * damagePerTickMultiplier

                    for _, angleEntry in ipairs(angleEntries) do
                        local angleOffset = angleEntry.Angle
                        local beamDirection = tangentDirection:Rotated(angleOffset)
                        local hitboxOffset = Vector(0, BEAM_HITBOX_Y_OFFSET)
                        local hitboxOrigin = visualOrigin + hitboxOffset
                        local laser = fireMizukiWeaponBeam(
                            player,
                            hitboxOrigin,
                            beamDirection,
                            side == 1,
                            apiDamageMultiplier,
                            beamWidthScale
                        )
                        laser.DisableFollowParent = true
                        laser.Position = hitboxOrigin
                        laser.PositionOffset = -hitboxOffset
                        local reflectionDepthShift =
                            applyMizukiBeamReflectionHeight(player, laser)
                        laser.Velocity = Vector.Zero
                        laser.DepthOffset = cannon.DepthOffset - Mizuki.WeaponParameters.BeamDepthBehindCannon
                            - hitboxOffset.Y
                            - reflectionDepthShift
                        laser.Timeout = beamActiveDuration
                        laser:SetOneHit(false)
                        laser:SetMaxDistance(beamDistance)

                        local laserData = laser:GetData()
                        laser.TearFlags = addOccultHoming(
                            player,
                            laser.TearFlags
                        ) & ~MIZUKI_FORBIDDEN_TEAR_FLAGS

                        laserData.MizukiBeam = true
                        laserData.MizukiBeamOwner = player
                        laserData.MizukiBeamWidthScale = beamWidthScale
                        laserData.MizukiBeamAutomatic = false
                        laserData.MizukiLudovicoTriggeredBeam = true
                        laserData.MizukiLudovicoTriggeredSources =
                            angleEntry.Sources
                        if cannonData.MizukiPersistentEchoMode then
                            laser.Color = Mizuki.getPersistentEchoColor(laser.Color)
                        end
                        if laserData.MizukiRecoverBeamDamageMultiplier then
                            laserData.MizukiAwaitingNativeDamageRefresh = true
                            laserData.MizukiLastAdjustedCollisionDamage =
                                laser.CollisionDamage
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


local function startCursedEyeBurst(
    player, data, direction, charge, profile, forcedSide
)
    local shotCount = getCursedEyeShotCount(player, charge, profile)
    -- Cursed Eye's complete burst belongs to one released Chocolate Milk
    -- charge. Snapshot that multiplier once; later shots must not recalculate it
    -- from their BaseFrames placeholder and silently fall back to 1x damage.
    local burstDamageMultiplier = getChargeDamageMultiplier(charge, profile)
    local finiteVolleyId = fireMizukiBeam(
        player,
        direction,
        charge,
        false,
        forcedSide,
        nil,
        burstDamageMultiplier
    )
    if forcedSide then
        Mizuki.recordNeptunusFiringSide(data, forcedSide)
    end
    if shotCount > 1 then
        local firingSide = forcedSide
            or (data.MizukiShotSide == -1 and 1 or 2)
        data.MizukiCursedEyeBurst = {
            Remaining = shotCount - 1,
            Direction = Vector(direction.X, direction.Y),
            Charge = profile.BaseFrames,
            DamageMultiplier = burstDamageMultiplier,
            Side = firingSide,
            FiniteVolleyId = finiteVolleyId,
        }
    end
end

local function updateCursedEyeBurst(player, data)
    local burst = data.MizukiCursedEyeBurst
    if not burst then
        return false
    end

    fireMizukiBeam(
        player,
        burst.Direction,
        burst.Charge,
        false,
        burst.Side,
        burst.FiniteVolleyId,
        burst.DamageMultiplier
    )
    burst.Remaining = burst.Remaining - 1
    if burst.Remaining <= 0 then
        data.MizukiCursedEyeBurst = nil
    end
    return true
end

local function removeLudovicoTechXProbe(data)
    removeLudovicoTriggeredBeams(data)
    local ring = data.MizukiLudovicoTechXProbe
    if ring and ring:Exists() then
        ring:Remove()
    end
    local legacyCarrier = data.MizukiLudovicoCarrier
    if legacyCarrier and legacyCarrier:Exists() then
        legacyCarrier:Remove()
    end
    data.MizukiLudovicoTechXProbe = nil
    data.MizukiLudovicoCarrier = nil
    data.MizukiLudovicoProbeActive = nil
    data.MizukiLudovicoCannonOrbitAngle = nil
    data.MizukiLudovicoCannonLayoutCenter = nil
    data.MizukiLudovicoKnifeResyncPending = nil
    data.MizukiLudovicoKnifeResyncReady = nil
end

include("scripts/cannons")

function Mizuki.updateLudovicoCannons(player, data, ring)
    prunePlayerCannons(data)
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
        or getExpectedCannonPairProfiles(player)
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
                    and HORIZONTAL_FRONT_DEPTH_OFFSET
                    or HORIZONTAL_BACK_DEPTH_OFFSET
                cannonData.CannonSide = side
                cannonData.MizukiIsIdle = false
                cannonData.MizukiLudovicoOrbiting = true
                -- Ludovico previously kept the left sheet throughout its orbit.
                cannonData.MizukiVerticalBodyXFactor = -1
                cannonData.MizukiReflectionBodyXFactor = -1
                updateCannonBodyGraphics(cannon, cannonData)
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
                    CANNON_FIRING_REFLECTION_SPAN * player.SpriteScale.Y
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
                local spriteRotation, pivotRenderOffset, basePivotRenderOffset = getCannonSpriteTransform(
                    cannon,
                    tangentDirection,
                    tangentDirection,
                    0
                )
                cannonData.MizukiPivotRenderOffset = pivotRenderOffset
                cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
                cannonData.MizukiCannonBodyRotation = spriteRotation
                sprite.Rotation = 0
                applyCannonShadowPose(player, cannon)
                sprite.Color = getCannonHiddenColor()
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
    if not laserData.MizukiLudovicoTechXProbe then return end

    local player = laserData.MizukiLudovicoOwner
    if not player or not player:Exists() then return end
    local data = player:GetData()
    if not data.MizukiLudovicoKnifeResyncPending then return end

    local cannonGroups = data.MizukiCannons
    local layoutCenter = data.MizukiLudovicoCannonLayoutCenter
    if not cannonGroups or not layoutCenter then return end

    local profiles = data.MizukiExpectedCannonPairProfiles
        or getExpectedCannonPairProfiles(player)
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

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_UPDATE,
    Mizuki.FinalizeLudovicoKnifeRoomEntry
)

function Mizuki:CompleteLudovicoKnifeRoomEntry()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
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
                            if Mizuki.updateCannonMomKnife then
                                Mizuki.updateCannonMomKnife(cannon)
                            end
                        end
                    end
                end
                data.MizukiLudovicoKnifeResyncPending = nil
                data.MizukiLudovicoKnifeResyncReady = nil
            end
        end
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_UPDATE,
    Mizuki.CompleteLudovicoKnifeRoomEntry
)

-- A normal player has a weapon controller which moves RING_LUDOVICO from the
-- shooting input. Mizuki is blindfolded, so move the native Tech X ring directly
-- without an intermediate tear carrier.
local function updateLudovicoTechXProbe(player, data)
    local myReflectionPullSpeedMultiplier = Mizuki.WeaponParameters.ReflectionPullSpeedMultiplier
    local myReflectionPullDistanceResponse = Mizuki.WeaponParameters.ReflectionPullDistanceResponse
    local hasLudovico = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
    )
    if not hasLudovico then
        removeLudovicoTechXProbe(data)
        data.MizukiLudovicoRingSynergyBrimstone = nil
        return false
    end

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
        local staleRing = data.MizukiLudovicoTechXProbe
        if staleRing and staleRing:Exists() then
            staleRing:Remove()
        end
        data.MizukiLudovicoTechXProbe = nil
    end

    -- Clean up a carrier left alive by reloading the previous probe version.
    local legacyCarrier = data.MizukiLudovicoCarrier
    if legacyCarrier and legacyCarrier:Exists() then
        legacyCarrier:Remove()
    end
    data.MizukiLudovicoCarrier = nil

    if not data.MizukiLudovicoProbeActive then
        removeActiveMizukiBeams(data)
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        data.MizukiCursedEyeBurst = nil
        data.MizukiLudovicoProbeActive = true
    end

    local ring = data.MizukiLudovicoTechXProbe
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
        ringData.MizukiLudovicoTechXProbe = true
        ringData.MizukiLudovicoOwner = player
        ringData.MizukiLudovicoBasePositionOffset = Vector(
            ring.PositionOffset.X,
            ring.PositionOffset.Y
        )
        data.MizukiLudovicoTechXProbe = ring
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

    local control = getRawShootingInput(player)
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





function Mizuki:UpdateWeapon(player)
    if not isMizuki(player) then
        return
    end

    local data = player:GetData()
    -- Door transitions temporarily clear shooting input. Treat that as a
    -- pause for the weapon state, not a release, so a held charge and its cannon facing survive
    -- until control returns in the destination room.
    --
    -- The cannons keep following through that pause, though. Freezing their
    -- positions as well leaves them sitting still while the player is pulled
    -- through the doorway, and they only catch up once the new room loads.
    if Game():IsPaused() then
        updateCannonPositions(player, data)
        return
    end

    updateCannonReconcile(player, data)
    Mizuki.updateEpicFetusStrikes(player, data)

    -- Ludovico converts the stable multishot count into persistent cannon
    -- pairs. Track the actual desired count so pickups, removals and rerolls
    -- refresh the familiar cache even when the item itself has no familiar flag.
    data.MizukiStableShotCount = getMizukiStableBeamCount(player)
    local expectedCannonPairProfiles = getExpectedCannonPairProfiles(
        player,
        data.MizukiStableShotCount
    )
    data.MizukiExpectedCannonPairProfiles = expectedCannonPairProfiles
    local expectedCannonPairs = #expectedCannonPairProfiles
    if data.MizukiExpectedCannonPairs ~= expectedCannonPairs then
        data.MizukiExpectedCannonPairs = expectedCannonPairs
        data.MizukiRefreshCannonCache = true
    end
    if data.MizukiRefreshCannonCache then
        data.MizukiRefreshCannonCache = nil
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
    if updateLudovicoTechXProbe(player, data) then
        Mizuki.resetNeptunusState(data)
        -- The ring remains the main projectile. The two cannon groups become a
        -- shared, rotating extension of its collision area while Ludovico is
        -- active; ordinary cannon positioning resumes as soon as it ends.
        data.MizukiSnapCannonsToDirectAim = nil
        data.MizukiDirectAimActive = nil
        data.MizukiHasShootingInput = false
        data.MizukiCannonAim = Vector(0, -1)
        data.MizukiCannonOrbitAngles = nil
        data.MizukiCannonAutoFireState = nil
        data.MizukiCannonAutoFirePositions = nil
        data.MizukiCannonAutoFireInputHeld = nil
        data.MizukiCannonAutoFireLastTapFrame = nil
        Mizuki.updateLudovicoCannons(
            player,
            data,
            data.MizukiLudovicoTechXProbe
        )
        fireLudovicoTriggeredBeams(player, data)
        updateLudovicoPlayerFacing(player)
        return
    end
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    Mizuki.updateCannonAutoFireInput(player, data)
    local kidneyStoneBurst = Mizuki.updateKidneyStoneBurst(player, data)
    local automatic = usesAutomaticBeam(player)
    local chargedBeam = not automatic and usesChargedBeam(player)
    local chargeProfile = getChargeProfile(player)
    local shootingDirection
    data.MizukiHasShootingInput, shootingDirection =
        getShootingIntent(
            player,
            data,
            not automatic
                and (not chargedBeam or (data.MizukiCharge or 0) > 0)
        )
    local returnAim
    if data.MizukiCannonAutoFireState == "deployed" then
        data.MizukiHasShootingInput = true
        shootingDirection = Mizuki.getCannonAutoFireAim(player, data, 1)
    elseif data.MizukiCannonAutoFireState == "returning" then
        if data.MizukiHasShootingInput then
            returnAim = shootingDirection
        end
        data.MizukiHasShootingInput = false
        shootingDirection = nil
    end
    local targetAiming = getMizukiTargetReticle(player, data) ~= nil
    if kidneyStoneBurst and kidneyStoneBurst.Direction
        and not data.MizukiCannonAutoFireState
    then
        data.MizukiHasShootingInput = true
        shootingDirection = kidneyStoneBurst.Direction
    end
    local activeSides, cannonFiringSides = updateActiveBeams(
        player,
        data,
        data.MizukiHasShootingInput,
        shootingDirection,
        automatic
    )
    local neptunusEnabled = Mizuki.updateNeptunusStorage(
        player, data, data.MizukiHasShootingInput, automatic
    )
    Mizuki.updateIsaacsTearsCharge(player, data)
    if data.MizukiCursedEyeBurst then
        data.MizukiCannonAim = data.MizukiCursedEyeBurst.Direction
    elseif data.MizukiHasShootingInput then
        data.MizukiCannonAim = shootingDirection
    end
    local directAimActive = not automatic
        and not chargedBeam
        and data.MizukiHasShootingInput
    data.MizukiSnapCannonsToDirectAim = directAimActive
        and not data.MizukiDirectAimActive
    data.MizukiDirectAimActive = directAimActive
    updateCannonPositions(player, data, returnAim)
    Mizuki.completeAutomaticEchoBeams(player, data)
    Mizuki.finishCannonAutoFireReturn(player, data)
    -- Cursed Eye releases one independently rolled attack per frame. Ignore
    -- input until the stored burst has completely left the cannons.
    if updateCursedEyeBurst(player, data) then
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if not automatic and not chargedBeam then
        -- Count remaining logical updates, not a global-frame deadline: rewind
        -- must never leave firing locked to a discarded future. The pause guard
        -- above freezes this timer. Beam lifetime is not added to the interval.
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil

        local interval = math.max(player.MaxFireDelay + 1, 1)
        local cooldown = math.max(0, (data.MizukiDirectBeamCooldown or 0) - 1)
        local previousInterval = data.MizukiDirectBeamInterval
        if previousInterval
            and math.abs(previousInterval - interval) > Mizuki.RuntimeParameters.FrameComparisonEpsilon
        then
            cooldown = cooldown * interval / previousInterval
        end

        local storedDirectShot = neptunusEnabled
            and (data.MizukiNeptunusStoredFrames or 0) > 0
        local freeDirectSide = storedDirectShot
            and Mizuki.getNeptunusFreeSide(data)
        if data.MizukiHasShootingInput
            and (not storedDirectShot or freeDirectSide)
            and Mizuki.canFireNeptunusDirect(data, cooldown)
        then
            fireMizukiBeam(
                player,
                shootingDirection,
                chargeProfile.BaseFrames,
                false,
                freeDirectSide,
                nil,
                1
            )
            if freeDirectSide then
                Mizuki.recordNeptunusFiringSide(data, freeDirectSide)
            end
            cooldown = interval
        end
        data.MizukiDirectBeamCooldown = cooldown
        data.MizukiDirectBeamInterval = interval

        if not data.MizukiHasShootingInput
            and not hasActiveMizukiBeam(data)
        then
            data.MizukiCannonAim = Vector(0, -1)
        end
        return
    end

    data.MizukiDirectBeamCooldown = nil
    data.MizukiDirectBeamInterval = nil

    if automatic and activeSides >= 2 then
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if data.MizukiHasShootingInput then
        data.MizukiAim = shootingDirection
        data.MizukiCannonAim = data.MizukiAim
        if neptunusEnabled then
            data.MizukiCharge = Mizuki.advanceNeptunusCharge(
                data, chargeProfile
            )
        else
            data.MizukiCharge = math.min(
                (data.MizukiCharge or 0) + 1,
                chargeProfile.MaxFrames
            )
        end
        local storedAutoFireSide = neptunusEnabled
            and (data.MizukiNeptunusStoredFrames or 0) > 0
            and data.MizukiCharge >= chargeProfile.MaxFrames
            and Mizuki.getNeptunusFreeSide(data)
        -- A finite beam still occupies its cannon until that attack ends.
        -- Anti-Gravity changes only whether its position follows the player.
        if (storedAutoFireSide
            or (cannonFiringSides == 0
                and (automatic or kidneyStoneBurst or targetAiming
                    or data.MizukiCannonAutoFireState == "deployed")
                and data.MizukiCharge >= chargeProfile.MaxFrames))
        then
            if storedAutoFireSide then
                -- Stored charge can finish on the first held frame. Resolve
                -- the firing side's immediate pose before sampling its beam
                -- origin; ordinary charging and the other side still ease.
                updateCannonPositions(
                    player, data, nil, storedAutoFireSide
                )
            end
            if (storedAutoFireSide
                or kidneyStoneBurst
                or data.MizukiCannonAutoFireState == "deployed")
                and player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
                and not automatic
            then
                startCursedEyeBurst(
                    player, data, data.MizukiAim,
                    data.MizukiCharge, chargeProfile, storedAutoFireSide
                )
            else
                fireMizukiBeam(
                    player,
                    data.MizukiAim,
                    data.MizukiCharge,
                    automatic,
                    storedAutoFireSide
                )
                if storedAutoFireSide then
                    Mizuki.recordNeptunusFiringSide(
                        data, storedAutoFireSide
                    )
                end
            end
            if neptunusEnabled then
                Mizuki.spendNeptunusCharge(data, data.MizukiCharge)
            end
            data.MizukiCharge = 0
            data.MizukiChargeBarFullFrames = nil
            return
        end

        if not automatic and data.MizukiCharge >= chargeProfile.MaxFrames then
            data.MizukiChargeBarFullFrames = (data.MizukiChargeBarFullFrames or 0) + 1
        else
            data.MizukiChargeBarFullFrames = nil
        end
        -- Unstored charged shots wait for release. The deployed pair and
        -- stored Neptunus shots were handled above without changing input.
        return
    end

    local charge = data.MizukiCharge or 0
    if charge >= chargeProfile.MinFrames and data.MizukiAim then
        if player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
            and not automatic
        then
            startCursedEyeBurst(
                player,
                data,
                data.MizukiAim,
                charge,
                chargeProfile
            )
        else
            fireMizukiBeam(player, data.MizukiAim, charge)
        end
        if neptunusEnabled then
            Mizuki.spendNeptunusCharge(data, charge)
        end
    end

    data.MizukiCharge = 0
    data.MizukiNeptunusHeldFrames = nil
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
    if data.MizukiCursedEyeBurst then
        data.MizukiCannonAim = Vector(
            data.MizukiCursedEyeBurst.Direction.X,
            data.MizukiCursedEyeBurst.Direction.Y
        )
    elseif not hasActiveMizukiBeam(data) then
        -- Releasing the input does not make a cannon idle while its finite
        -- attack is still on screen. Preserve the fired aim until the last
        -- active beam ends; only then return the pair to its idle direction.
        -- Automatic beams remain distinct: their aim continues to be updated
        -- from live shooting input in updateActiveBeams.
        data.MizukiCannonAim = Vector(0, -1)
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateWeapon)

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
            or not isMizuki(player)
            or (damageFlags & DamageFlag.DAMAGE_LASER) == 0
        then
            return
        end
        laser = player:GetData().MizukiLudovicoTechXProbe
        if not laser or not laser:Exists() then return end
        laserData = laser:GetData()
        if not laserData.MizukiLudovicoTechXProbe then return end
    elseif not laserData.MizukiLudovicoTechXProbe then
        return
    end

    if not player or not player:Exists() or not isMizuki(player) then
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
    local interval = math.max(player.MaxFireDelay, 1) + 1
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

Mizuki:AddPriorityCallback(
    ModCallbacks.MC_ENTITY_TAKE_DMG,
    CallbackPriority.EARLY,
    Mizuki.ThrottleLudovicoTechXDamage
)

local function getLudovicoEpicFetusSource(player, damageFlags, source)
    local ring = player:GetData().MizukiLudovicoTechXProbe
    if not ring or not ring:Exists() then return nil end

    local sourceEntity = source and source.Entity
    if not sourceEntity then return nil end

    local familiar = sourceEntity:ToFamiliar()
    if familiar
        and familiar.Variant == Mizuki.CannonVariant
        and familiar:GetData().MizukiLudovicoOrbiting
        and cannonBelongsToPlayer(familiar, player)
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

function Mizuki:TriggerEpicFetusStrike(entity, amount, damageFlags, source)
    local enemy = entity:ToNPC()
    if not enemy
        or not enemy:IsActiveEnemy(false)
        or enemy:IsDead()
        or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return
    end

    local player = Mizuki.getMizukiBeamOwnerFromDamageSource(source)
    if not player
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then
        return
    end

    local data = player:GetData()
    local ludovicoFromCannon = getLudovicoEpicFetusSource(
        player,
        damageFlags,
        source
    )
    if ludovicoFromCannon ~= nil then
        Mizuki.queueLudovicoEpicFetusEnemy(
            player,
            enemy,
            ludovicoFromCannon
        )
        return
    end

    if not hasActiveMizukiBeam(data)
        or not Mizuki.canStartEpicFetusStrike(data)
    then
        return
    end

    -- Enemy damage wins over any grid candidate collected during this frame.
    data.MizukiEpicFetusGridCandidate = nil
    Mizuki.startEpicFetusStrike(
        player,
        enemy,
        Vector(enemy.Position.X, enemy.Position.Y)
    )
end

Mizuki:AddCallback(
    ModCallbacks.MC_ENTITY_TAKE_DMG,
    Mizuki.TriggerEpicFetusStrike
)

function Mizuki:TriggerCursedEyeTeleport(entity)
    local player = entity:ToPlayer()
    if not player
        or not isMizuki(player)
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_BLACK_CANDLE)
        or usesAutomaticBeam(player)
    then
        return
    end

    local data = player:GetData()
    local charge = data.MizukiCharge or 0
    local profile = getChargeProfile(player)
    if charge <= 0 or charge >= profile.MaxFrames then
        return
    end

    data.MizukiCharge = 0
    data.MizukiNeptunusHeldFrames = nil
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
    data.MizukiCursedEyeBurst = nil

    local rng = player:GetCollectibleRNG(
        CollectibleType.COLLECTIBLE_CURSED_EYE
    )
    -- MC_ENTITY_TAKE_DMG runs before the native hurt state is completely
    -- applied. Starting the transition here lets the remainder of that state
    -- delay it until the hurt animation ends. Defer only to this frame's final
    -- update, after damage processing, to match Cursed Eye's immediate timing.
    data.MizukiPendingCursedEyeTeleportSeed = rng:Next()
end

Mizuki:AddCallback(
    ModCallbacks.MC_ENTITY_TAKE_DMG,
    Mizuki.TriggerCursedEyeTeleport,
    EntityType.ENTITY_PLAYER
)

function Mizuki:StartPendingCursedEyeTeleport()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local data = player:GetData()
        local teleportSeed = data.MizukiPendingCursedEyeTeleportSeed
        if teleportSeed then
            data.MizukiPendingCursedEyeTeleportSeed = nil
            game:MoveToRandomRoom(false, teleportSeed, player)
            return
        end
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_UPDATE,
    Mizuki.StartPendingCursedEyeTeleport
)

function Mizuki:ApplyLaserWidth(laser)
    local laserData = laser:GetData()
    if not laserData.MizukiBeam then
        return
    end

    Mizuki.queueEpicFetusGridTarget(laser)

    -- Player-fired lasers already received their complete damage multiplier
    -- through FireTechLaser or FireBrimstone. Only the ShootAngle replacement
    -- for thick Brimstone loses that parameter on native damage refresh.
    local player = laserData.MizukiBeamOwner
    if player and player:Exists() then
        laser.TearFlags = addOccultHoming(player, laser.TearFlags)
            & ~MIZUKI_FORBIDDEN_TEAR_FLAGS

        local recovery = laserData.MizukiRecoverBeamDamageMultiplier
        if recovery then
            local nativeDamage = laser.CollisionDamage
            local lastAdjusted = laserData.MizukiLastAdjustedCollisionDamage
            local shouldAdjustDamage = true
            if laserData.MizukiAwaitingNativeDamageRefresh then
                if lastAdjusted
                    and math.abs(nativeDamage - lastAdjusted) < Mizuki.RuntimeParameters.DamageComparisonEpsilon
                then
                    -- The copied first-frame value is already scaled.
                    shouldAdjustDamage = false
                else
                    laserData.MizukiAwaitingNativeDamageRefresh = nil
                end
            elseif lastAdjusted
                and math.abs(nativeDamage - lastAdjusted) < Mizuki.RuntimeParameters.DamageComparisonEpsilon
                and laserData.MizukiLastNativeCollisionDamage
            then
                nativeDamage = laserData.MizukiLastNativeCollisionDamage
            end
            if shouldAdjustDamage then
                local adjustedDamage = nativeDamage * recovery
                laserData.MizukiLastNativeCollisionDamage = nativeDamage
                laserData.MizukiLastAdjustedCollisionDamage = adjustedDamage
                laser.CollisionDamage = adjustedDamage
            end
        end
    end

    -- Let EntityLaser own the native narrowing animation after the weapon has
    -- released it. Damage and native item refresh continue, but do not restore
    -- the maintained width over the native fade/shrink.
    if laserData.MizukiBeamEnding then
        return
    end

    if laser.FrameCount < Mizuki.RuntimeParameters.NativeLaserInitFrames then
        return
    end

    local widthScale = laserData.MizukiBeamWidthScale or 1
    if not laserData.MizukiBeamWidthApplied then
        -- Wait until the native laser has initialized both its collision size
        -- and render scale, then preserve those unmodified native baselines.
        laserData.MizukiBeamBaseSpriteScale = Vector(
            laser.SpriteScale.X,
            laser.SpriteScale.Y
        )
        -- The engine hands the thick variant out at twice the ordinary size
        -- (Size 16 -> 32), so the same ratio has to bring both the collision and
        -- the render scale back to the ordinary beam's width; applying it to the
        -- hitbox alone leaves the sprite twice as wide. The ratio is measured
        -- once here, before Size is modified, and cached for the frames after.
        local referenceRatio = 1
        local referenceSize = laserData.MizukiBeamReferenceSize
        if referenceSize and laser.Size > 0 then
            referenceRatio = referenceSize / laser.Size
        end
        laserData.MizukiBeamWidthRatio = referenceRatio
        laser.Size = laser.Size * widthScale * referenceRatio
        laserData.MizukiBeamWidthApplied = true
    end

    local baseScale = laserData.MizukiBeamBaseSpriteScale or Vector.One
    local appliedSpriteScale = widthScale
        * (laserData.MizukiBeamWidthRatio or 1)
    -- Size may synchronize back into SpriteScale during native updates. Undo
    -- its longitudinal scaling after every update: widen around the shared
    -- centered X pivot, while leaving body length and tip placement native.
    laser.SpriteScale = Vector(
        baseScale.X * appliedSpriteScale,
        baseScale.Y
    )
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_UPDATE,
    Mizuki.ApplyLaserWidth
)

function Mizuki:FinalizeEpicFetusTargets()
    local frame = Game():GetFrameCount()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local data = player:GetData()
            local canStart = player:HasCollectible(
                CollectibleType.COLLECTIBLE_EPIC_FETUS
            ) and Mizuki.canStartEpicFetusStrike(data)
            local ring = data.MizukiLudovicoTechXProbe
            local hasLudovicoRing = ring and ring:Exists()

            if canStart and hasLudovicoRing then
                local enemy, position =
                    Mizuki.getLudovicoEpicFetusCandidate(player, frame)
                data.MizukiEpicFetusGridCandidate = nil
                if position then
                    Mizuki.startEpicFetusStrike(player, enemy, position)
                end
            elseif canStart then
                data.MizukiEpicFetusLudovicoCandidate = nil
                data.MizukiEpicFetusLudovicoGeometry = nil
                local candidate = data.MizukiEpicFetusGridCandidate
                if candidate
                    and candidate.Frame <= frame
                    and hasActiveMizukiBeam(data)
                then
                    Mizuki.startEpicFetusStrike(
                        player,
                        nil,
                        candidate.Position
                    )
                end
                data.MizukiEpicFetusGridCandidate = nil
            else
                data.MizukiEpicFetusGridCandidate = nil
                data.MizukiEpicFetusLudovicoCandidate = nil
                data.MizukiEpicFetusLudovicoGeometry = nil
            end
        end
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_UPDATE,
    Mizuki.FinalizeEpicFetusTargets
)

function Mizuki:QueueBoxOfFriendsCannonRefresh(collectible, rng, player)
    if isMizuki(player) then
        -- Resolve on the next player update, after the vanilla active effect
        -- has incremented its temporary Box of Friends effect count.
        player:GetData().MizukiRefreshCannonCache = true
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.QueueBoxOfFriendsCannonRefresh,
    BOX_OF_FRIENDS
)

function Mizuki:ApplyTearsMultiplier(player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_TEARCOLOR and isMizuki(player) then
        local data = player:GetData()
        -- FireKnife inherits the player's final TearColor. Preserve the colour
        -- produced by vanilla and other items before Mizuki adds her character
        -- pink colorize, so the cannon knives can discard only Mizuki's layer.
        data.MizukiMomKnifeBaseColor = player.TearColor
        data.MizukiMomKnifeColorRevision =
            (data.MizukiMomKnifeColorRevision or 0) + 1
        player.TearColor = player.TearColor * MIZUKI_TEAR_COLOR
        player.LaserColor = player.LaserColor * MIZUKI_TEAR_COLOR
    end

    if isMizuki(player) then
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            -- Technology Zero's damage restoration is an independent passive:
            -- higher-priority weapon modes such as Brimstone may replace its
            -- eight-tick attack, but cannot remove this held-item benefit.
            local damageMultiplier = player:HasCollectible(
                CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO
            ) and TECHNOLOGY_ZERO_DAMAGE_MULTIPLIER
                or DEFAULT_DAMAGE_MULTIPLIER
            player.Damage = player.Damage * damageMultiplier
        elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
            local profile = getMizukiFireRateProfile(player)
            local currentTears = 30 / (player.MaxFireDelay + 1)
            local preWeaponTears = currentTears / profile.VanillaTearsMultiplier
            local finalTears = (preWeaponTears + profile.TearsModifier) * profile.MizukiTearsMultiplier
            player.MaxFireDelay = math.max(0, Mizuki.RuntimeParameters.LogicFramesPerSecond / finalTears - 1)
        elseif cacheFlag == CacheFlag.CACHE_SPEED then
            player.MoveSpeed = player.MoveSpeed + MOVE_SPEED_MODIFIER
        elseif cacheFlag == CacheFlag.CACHE_TEARFLAG
            and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        then
            player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
        elseif cacheFlag == CacheFlag.CACHE_LUCK then
            player.Luck = player.Luck + LUCK_MODIFIER
        elseif cacheFlag == CacheFlag.CACHE_FAMILIARS then
            local cannonsPerSide = getExpectedCannonPairs(player)
            player:GetData().MizukiExpectedCannonPairs = cannonsPerSide
            local rng = player:GetCollectibleRNG(BOX_OF_FRIENDS)
            player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 1)
            player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 2)
            player:CheckFamiliar(
                Mizuki.FanVariant,
                player:GetCollectibleNum(Mizuki.FanItem)
                    + player:GetEffects():GetCollectibleEffectNum(Mizuki.FanItem),
                player:GetCollectibleRNG(Mizuki.FanItem),
                Isaac.GetItemConfig():GetCollectible(Mizuki.FanItem)
            )
        end
    end

end

Mizuki:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, Mizuki.ApplyTearsMultiplier)

function Mizuki:InitCannonFamiliar(cannon)
    cannon.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
    cannon.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    cannon.CollisionDamage = 0
    local cannonData = cannon:GetData()
    -- CheckFamiliar creates the entity before the player and render interpolation
    -- have settled. Keep every layer out of the pipeline until the first real
    -- weapon layout can place it once at the resolved player-relative position.
    cannonData.MizukiAwaitingInitialLayout = true
    cannon.DepthOffset = CANNON_DEPTH_OFFSET
    cannon.Visible = false
    cannon:GetSprite().Color = getCannonHiddenColor()
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitCannonFamiliar, Mizuki.CannonVariant)

-- Apply the resolved movement and keep the Familiar's player-scaled body/shadow
-- transform in its own update path, so native interpolation sees both together.
function Mizuki:UpdateCannonFamiliar(cannon)
    ensureCannonRegistered(cannon)
    local cannonData = cannon:GetData()
    local roomEntryOffset = cannonData.MizukiPendingRoomEntryOffset
    local player = cannon.Player
    if player and player:Exists()
        and player:GetData().MizukiLudovicoKnifeResyncPending
    then
        cannonData.MizukiDeferMomKnifeUntilLudovicoReady = true
    end
    if cannonData.MizukiDeferMomKnifeUntilLudovicoReady
        and player
        and player:Exists()
        and not player:HasCollectible(
            CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
        )
    then
        -- A reroll during the transition can remove Ludovico before its setup
        -- consumes the deferred spawn. Fall back to the ordinary cannon path.
        cannonData.MizukiDeferMomKnifeUntilLudovicoReady = nil
    end
    if roomEntryOffset and player and player:Exists() then
        -- MC_POST_NEW_ROOM can run before the engine has finalized the player's
        -- destination-floor position. Resolve the saved relative layout here,
        -- in the Familiar's first real update, so neither body nor knife spends
        -- a frame at the engine's temporary room coordinate.
        cannon.Position = player.Position + roomEntryOffset
        cannon.Velocity = Vector.Zero
        cannonData.MizukiDesiredPosition = Vector(
            cannon.Position.X,
            cannon.Position.Y
        )
        cannonData.MizukiPoseOffset = Vector(
            roomEntryOffset.X,
            roomEntryOffset.Y
        )
        cannonData.MizukiLastPlayerPosition = Vector(
            player.Position.X,
            player.Position.Y
        )
        cannonData.MizukiPendingRoomEntryOffset = nil
    end
    local desiredPosition = cannonData.MizukiDesiredPosition
    if desiredPosition and not cannonData.MizukiLudovicoOrbiting then
        -- Move through the Familiar's own update path, like native/custom
        -- followers normally do, instead of teleporting Position from the
        -- player's callback. Velocity supplies the engine with the motion it
        -- needs to interpolate both the Familiar and its native shadow.
        cannon.Velocity = desiredPosition - cannon.Position
    end
    -- A freshly spawned Familiar still carries the engine's temporary spawn
    -- coordinate and interpolation history. Do not expose either its native
    -- shadow or the manually redrawn body until a weapon layout has resolved
    -- the first real position. Afterwards it stays in the native pipeline so
    -- layer 2 can continue to supply the shadow.
    cannon.Visible = not cannonData.MizukiAwaitingInitialLayout
    updateCannonBodyGraphics(cannon, cannonData)
    -- LoadGraphics and callback ordering can restore the sprite's visible
    -- colour after the player-owned positioning update. Reassert the hidden
    -- native body here, in the Familiar's own update, for both ordinary and
    -- Ludovico cannons. Visible stays true so layer 2 still reaches the engine's
    -- native shadow pass; RenderCannon temporarily restores body alpha only for
    -- the explicit layer 0/1 draw.
    cannon:GetSprite().Color = getCannonHiddenColor()
    cannon.SpriteScale = getCannonVisualScale(cannon)
    if not cannonData.MizukiAwaitingInitialLayout
        and not cannonData.MizukiDeferMomKnifeUntilLudovicoReady
        and Mizuki.updateCannonMomKnife
    then
        Mizuki.updateCannonMomKnife(cannon)
    end

end

Mizuki:AddCallback(
    ModCallbacks.MC_FAMILIAR_UPDATE,
    Mizuki.UpdateCannonFamiliar,
    Mizuki.CannonVariant
)

function Mizuki:ResetCannonsForNewRoom()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local data = player:GetData()
            data.MizukiActiveBeams = {}
            data.MizukiLockedCannonPositions = {}
            data.MizukiLockedCannonAims = {}
            data.MizukiCannonAutoFireState = nil
            data.MizukiCannonAutoFirePositions = nil
            data.MizukiCannonAutoFireInputHeld = nil
            data.MizukiCannonAutoFireLastTapFrame = nil
            data.MizukiCursedEyeBurst = nil
            data.MizukiSnapCannonsToDirectAim = nil
            data.MizukiDirectAimActive = nil
            data.MizukiEpicFetusGridCandidate = nil
            data.MizukiEpicFetusLudovicoCandidate = nil
            data.MizukiEpicFetusLudovicoGeometry = nil
            data.MizukiLudovicoNeedsRoomEntryReset = true
            removeLudovicoTriggeredBeams(data)

            local ludovicoRing = data.MizukiLudovicoTechXProbe
            if ludovicoRing and ludovicoRing:Exists() then
                local ringData = ludovicoRing:GetData()
                ringData.MizukiLudovicoDamageSchedules = nil
            end

            claimPlayerCannons(player, data)
            local hasLudovico = player:HasCollectible(
                CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
            )
            local deferLudovicoMomKnife = hasLudovico
                and player:HasCollectible(
                    CollectibleType.COLLECTIBLE_MOMS_KNIFE
                )
            data.MizukiLudovicoKnifeResyncPending =
                deferLudovicoMomKnife and true or nil
            data.MizukiLudovicoKnifeResyncReady = nil

            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side]) do
                    if cannon:Exists() then
                        local cannonData = cannon:GetData()
                        cannonData.MizukiContactDamageSchedules = nil
                        local outward = side == 1 and -(member - 1) or (member - 1)
                        local restingOffset = CANNON_OFFSETS[side]
                            + Vector(outward * CANNON_GROUP_SPACING, 0)
                        -- Carry the layout the cannons were in when the player
                        -- walked through the door, rather than their exact
                        -- position: the door pull leaves the cannons lagging by
                        -- the time the room changes, and carrying that lag makes
                        -- them land out of place and coast back. Snapping to the
                        -- resting position over the head instead is what this
                        -- replaces - a held charge or a live beam can have the
                        -- cannons in a different layout on the way out.
                        local carriedOffset = cannonData.MizukiLayoutOffset
                        local roomEntryOffset
                        if hasLudovico then
                            -- The new room's ring starts over the player. The
                            -- previous controlled ring displacement belongs to
                            -- the old room and must not be carried across.
                            roomEntryOffset = Vector.Zero
                        else
                            roomEntryOffset = carriedOffset
                                or scalePlayerOffset(player, restingOffset)
                        end
                        cannonData.MizukiDeferMomKnifeUntilLudovicoReady =
                            deferLudovicoMomKnife and true or nil
                        cannon.Position = player.Position + roomEntryOffset
                        cannon.Velocity = Vector.Zero
                        cannonData.MizukiDesiredPosition = Vector(
                            cannon.Position.X,
                            cannon.Position.Y
                        )
                        cannonData.MizukiPoseOffset = cannon.Position - player.Position
                        cannonData.MizukiPendingRoomEntryOffset = Vector(
                            roomEntryOffset.X,
                            roomEntryOffset.Y
                        )
                        cannonData.MizukiMovementLag = Vector.Zero
                        -- The position was just snapped to the layout, so the
                        -- drawn body carries no hover bob either.
                        cannonData.MizukiBobOffsetY = 0
                        cannonData.MizukiLastPlayerPosition = Vector(
                            player.Position.X,
                            player.Position.Y
                        )
                        cannonData.MizukiHorizontalSortOffset = nil
                        local aim = data.MizukiCannonAim or Vector(0, -1)
                        cannonData.MizukiCannonAim = aim
                        -- The idle tilt is a smoothed value: leave it as it is so
                        -- it keeps easing, instead of snapping to the resting
                        -- angle on arrival.
                        local idleRotation = cannonData.MizukiIdleRotationOffset
                            or (side == 1 and LEFT_CANNON_IDLE_ROTATION
                                or RIGHT_CANNON_IDLE_ROTATION)
                        local sprite = cannon:GetSprite()
                        local spriteRotation, pivotRenderOffset, basePivotRenderOffset = getCannonSpriteTransform(
                            cannon,
                            aim,
                            aim,
                            idleRotation
                        )
                        cannonData.MizukiPivotRenderOffset = pivotRenderOffset
                        cannonData.MizukiBasePivotRenderOffset = basePivotRenderOffset
                        cannonData.MizukiCannonBodyRotation = spriteRotation
                        sprite.Rotation = 0
                        if not deferLudovicoMomKnife
                            and Mizuki.resetCannonMomKnife
                        then
                            -- Ordinary weapons reset only after their owning
                            -- cannon has been placed. Ludovico deliberately
                            -- keeps its existing knife hidden until the ring's
                            -- final room-entry position is known.
                            Mizuki.resetCannonMomKnife(cannon)
                        end
                    end
                end
            end
        end
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ResetCannonsForNewRoom)

-- Re-draw the cannon that the engine was told to draw fully transparent (see
-- updateCannonPositions). Every pass except the water reflection pass draws the
-- body exactly where the entity is. Idle reflections keep the engine's native
-- mirror; active reflections cancel it and draw a separate body projection.
--
-- The reflected bob still moves opposite the body about the water plane.

function Mizuki:RenderCannon(cannon, renderOffset, renderAfterLudovicoRing)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end
    local game = Game()
    local room = game:GetRoom()
    local cannonData = cannon:GetData()
    if cannonData.MizukiAwaitingInitialLayout then
        -- Visible is normally already false, but keep the explicit redraw path
        -- closed as well in case render/update callback order changes.
        cannon:GetSprite().Color = getCannonHiddenColor()
        return
    end
    if cannonData.MizukiLudovicoOrbiting
        and not renderAfterLudovicoRing
    then
        -- Unlike an ordinary cannon, the orbiting body is redrawn later from
        -- MC_POST_LASER_RENDER. Still finish this native Familiar pass with the
        -- exact state its shadow needs; returning without this cleanup lets the
        -- engine's normal/water passes leak a visible body colour into the next
        -- pass before the delayed draw gets a chance to restore it.
        local sprite = cannon:GetSprite()
        sprite.Rotation = 0
        sprite.Offset = cannonData.MizukiShadowOffset
            or Vector(0, cannonData.MizukiShadowOffsetY or 0)
        sprite.Color = getCannonHiddenColor()
        sprite.FlipY = false
        cannon.SpriteScale = getCannonVisualScale(cannon)
        return
    end

    local sprite = cannon:GetSprite()
    local originalColor = sprite.Color

    -- Reassert the complete player-scaled transform before the explicit body
    -- draw; the native shadow intentionally uses this same scale.
    local bodyScale = getCannonVisualScale(cannon)
    cannon.SpriteScale = bodyScale

    local worldPosition = cannon.Position
    local isWaterReflection = room:GetRenderMode()
        == RenderMode.RENDER_WATER_REFLECT
    local isIdle = cannonData.MizukiIsIdle
    local cancelWaterMirror = isWaterReflection and not isIdle
    -- The hover bob is drawn, not simulated: the entity itself stays put so the
    -- engine's shadow draw cannot wobble. The reflected body receives the
    -- opposite visual offset, mirroring the bob about the reflection plane.
    local hoverY = cannonData.MizukiBobOffsetY or 0
    local bodyBobY = hoverY
    if isWaterReflection then
        -- The span is anchored to the cannon itself rather than to the live
        -- player position, so the reflection stays rigidly attached to the
        -- cannon: a locked finite shot freezes body and reflection together,
        -- and the follow lag of a continuous beam applies to both instead of
        -- being recomputed (and doubled) on the reflection.
        -- updateCannonPositions eases this toward the distance the current
        -- state asks for; the direct value is only a first-frame fallback.
        local span = cannonData.MizukiReflectionSpan
        if span == nil then
            span = getCannonReflectionSpan(player, isIdle)
        end
        worldPosition = Vector(
            cannon.Position.X,
            cannon.Position.Y + span
        )
        bodyBobY = -hoverY
    end

    -- Apply the idle-rotation pivot correction in world/render space. Only the
    -- idle water pass keeps the engine mirror, so only it mirrors this offset.
    local pivotRenderOffset = cannonData.MizukiPivotRenderOffset
        or Vector.Zero
    local basePivotRenderOffset = cannonData.MizukiBasePivotRenderOffset
        or pivotRenderOffset
    if isWaterReflection and isIdle then
        pivotRenderOffset = Vector(
            pivotRenderOffset.X,
            -pivotRenderOffset.Y
        )
        basePivotRenderOffset = Vector(
            basePivotRenderOffset.X,
            -basePivotRenderOffset.Y
        )
    end

    -- Ludovico contact damage uses cannon.Position, matching the laser ring's
    -- collision plane. Apply the ring's own PositionOffset only to the manually
    -- drawn cannon body so both visuals share the same render plane without
    -- moving either hitbox.
    local renderWorldOffset = cannonData.MizukiRenderWorldOffset
    renderWorldOffset = renderWorldOffset or Vector.Zero

    -- Both visuals share this root, but each applies its own explicit art-scale
    -- pivot. Build the knife reflection directly from the full-size pivot instead
    -- of routing it through the cannon's 0.65 pivot and undoing that afterwards.
    local knifeReflectionBodyPosition = isWaterReflection
        and (worldPosition
            + basePivotRenderOffset
            + renderWorldOffset
            + Vector(0, bodyBobY))
        or nil
    worldPosition = worldPosition + pivotRenderOffset + renderWorldOffset

    -- An active reflection keeps this cannon's position and identity; only its
    -- horizontal projection is mirrored, so the other cannon is the one that
    -- reaches the edge-on flip on a sideways turn. Idle keeps its old native
    -- mirror and ordinary body sheet. Separate cached sprites avoid reloading
    -- the Familiar's graphics during the water pass.
    local bodySprite = sprite
    local bodyXFactor = cannonData.MizukiVerticalBodyXFactor or 1
    if cancelWaterMirror then
        bodyXFactor = cannonData.MizukiReflectionBodyXFactor
            or bodyXFactor
        bodySprite = getCannonReflectionBodySprite(
            cannonData, sprite, bodyXFactor
        )
        bodySprite.FlipX = sprite.FlipX
        bodySprite.FlipY = not sprite.FlipY
    end
    -- The pose lives in cannon data so the Familiar sprite can stay straight
    -- for its native shadow pass. Only body/light layers are drawn here.
    bodySprite.Rotation = cannonData.MizukiCannonBodyRotation or 0
    bodySprite.Scale = getCannonBodyRenderScale(
        cannonData, bodyScale, bodyXFactor
    )
    bodySprite.Offset = Vector.Zero
    -- Force the sprite visible for this draw while keeping whatever colour it
    -- arrived with, so a tint applied elsewhere is not thrown away.
    bodySprite.Color = Color(
        originalColor.R, originalColor.G, originalColor.B,
        1, originalColor.RO, originalColor.GO, originalColor.BO
    )
    if cannonData.MizukiPersistentEchoMode then
        bodySprite.Color = Mizuki.getPersistentEchoColor(bodySprite.Color)
    end
    -- The 2nd and 3rd arguments are clamps, not offset and scale.
    local bodyRenderPosition = Isaac.WorldToScreen(
        worldPosition + Vector(0, bodyBobY)
    ) + renderOffset - room:GetRenderScrollOffset()
        - game.ScreenShakeOffset
    -- The knife follows the same idle/native versus active/cancelled mirror.
    local renderedMomKnife = cannonData.MizukiDeferMomKnifeUntilLudovicoReady
        or (Mizuki.renderCannonMomKnifeBody
            and Mizuki.renderCannonMomKnifeBody(
                cannon,
                renderOffset,
                knifeReflectionBodyPosition,
                cancelWaterMirror
            ))
    if not renderedMomKnife then
        bodySprite:RenderLayer(0, bodyRenderPosition, Vector.Zero, Vector.Zero)
        bodySprite:RenderLayer(1, bodyRenderPosition, Vector.Zero, Vector.Zero)
    end

    -- Put the sprite back into the pose the engine's own shadow draw needs (see
    -- applyCannonShadowPose, which writes it every update; the body draw above
    -- had to borrow the transform for a moment).
    sprite.Rotation = 0
    sprite.Scale = Vector(bodyScale.X, bodyScale.Y)
    sprite.Offset = cannonData.MizukiShadowOffset
        or Vector(0, cannonData.MizukiShadowOffsetY or 0)

    if cannonData.MizukiLudovicoOrbiting then
        -- The delayed Ludovico draw must not trust the colour/flip inherited
        -- from an earlier native render pass. Leave the sprite explicitly ready
        -- for its next native shadow pass, matching the ordinary cannon cleanup.
        sprite.Color = getCannonHiddenColor()
        sprite.FlipY = false
        cannon.SpriteScale = bodyScale
    else
        sprite.Color = originalColor
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_FAMILIAR_RENDER,
    Mizuki.RenderCannon,
    Mizuki.CannonVariant
)

function Mizuki:RenderLudovicoCannonsAboveRing(laser, renderOffset)
    local laserData = laser:GetData()
    if not laserData.MizukiLudovicoTechXProbe then return end

    local player = laserData.MizukiLudovicoOwner
    if not player or not player:Exists() then return end

    local cannons = player:GetData().MizukiCannons
    if not cannons then return end
    for side = 1, 2 do
        for _, cannon in ipairs(cannons[side] or {}) do
            if cannon and cannon:Exists() then
                Mizuki:RenderCannon(
                    cannon,
                    renderOffset or Vector.Zero,
                    true
                )
            end
        end
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_RENDER,
    Mizuki.RenderLudovicoCannonsAboveRing
)


-- Draw immediately after the selected Familiar. The Familiar survives room
-- changes and this callback receives the same camera offset used for its body.
function Mizuki:RenderChargeBar(cannon, renderOffset)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local game = Game()
    local room = game:GetRoom()
    local cannonData = cannon:GetData()
    if cannonData.MizukiAwaitingInitialLayout then
        return
    end
    local data = player:GetData()
    -- The charge bar belongs to the body only. Without this guard the
    -- reflection pass would draw a second, unmirrored bar over the real one.
    if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then
        return
    end
    if usesAutomaticBeam(player) then
        return
    end
    local charge = data.MizukiCharge or 0
    if charge <= 0 then
        return
    end

    -- The next firing side decides which registered cannon group may own the bar.
    local nextShotSide = -(data.MizukiShotSide or -1)
    local side = nextShotSide == -1 and 1 or 2
    if cannon.SubType ~= side then
        return
    end

    -- Registration keeps each side sorted by InitSeed, so the first live cannon
    -- is the stable representative even when Box of Friends creates extra copies.
    local frameCount = game:GetFrameCount()
    if data.MizukiChargeBarOwnerFrame ~= frameCount
        or data.MizukiChargeBarOwnerSide ~= side then
        data.MizukiChargeBarOwnerFrame = frameCount
        data.MizukiChargeBarOwnerSide = side
        data.MizukiChargeBarOwnerHash = nil

        prunePlayerCannons(data)
        local ownerCannon = data.MizukiCannons[side][1]
        if ownerCannon then
            data.MizukiChargeBarOwnerHash = GetPtrHash(ownerCannon)
        end
    end

    if data.MizukiChargeBarOwnerHash ~= GetPtrHash(cannon) then
        return
    end

    local fullFrames = data.MizukiChargeBarFullFrames
    if fullFrames then
        if fullFrames <= Mizuki.WeaponParameters.ChargeBarStartFrames then
            chargeBar:Play("StartCharged", true)
            chargeBar:SetFrame("StartCharged", fullFrames - 1)
        else
            chargeBar:Play("Charged", true)
            chargeBar:SetFrame("Charged", (fullFrames - (Mizuki.WeaponParameters.ChargeBarStartFrames + 1)) % Mizuki.WeaponParameters.ChargeBarLoopFrames)
        end
    else
        local frame = math.floor(
            math.min(charge / getChargeProfile(player).MaxFrames, 1) * Mizuki.WeaponParameters.ChargeBarProgressFrames
        )
        chargeBar:Play("Charging", true)
        chargeBar:SetFrame("Charging", frame)
    end

    chargeBar.Color = CHARGE_BAR_COLOR
    chargeBar.Scale = CHARGE_BAR_SCALE
    local cannonSprite = cannon:GetSprite()
    -- The body's pose is kept in the data (the sprite itself stays straightened
    -- for the engine's shadow draw). Compose the same visual-only pivot, render
    -- plane and hover offsets used by the hand-drawn body without moving the
    -- cannon entity or its attack geometry.
    local bodyRotation = cannonData.MizukiCannonBodyRotation
        or cannonSprite.Rotation
    local graphicsWeight = (1 + (cannonData.MizukiVerticalBodyXFactor or 1))
        * 0.5
    local graphicsOffset = CHARGE_BAR_NORMAL_GRAPHICS_OFFSET:Rotated(
        bodyRotation
    ) * graphicsWeight

    local bodyWorldPosition = Mizuki.getCannonMomKnifeBodyPosition
        and Mizuki.getCannonMomKnifeBodyPosition(cannon)
    bodyWorldPosition = bodyWorldPosition or (cannon.Position
        + (cannonData.MizukiPivotRenderOffset or Vector.Zero)
        + (cannonData.MizukiRenderWorldOffset or Vector.Zero)
        + Vector(0, cannonData.MizukiBobOffsetY or 0))
    local renderPosition = Isaac.WorldToScreen(bodyWorldPosition) + renderOffset
        + CHARGE_BAR_OFFSET:Rotated(bodyRotation)
        + graphicsOffset
        - room:GetRenderScrollOffset() - game.ScreenShakeOffset
        
    -- The Revelation charge bar separates its art into bg (0), bar (1), and
    -- the inward-contracting outer circle (2). Mizuki only uses the circle.
    chargeBar:RenderLayer(2, renderPosition)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, Mizuki.RenderChargeBar, Mizuki.CannonVariant)

-- Implementations of the two forward-declared helpers above. They stay here
-- because main declares and calls them as locals; scripts/epic_fetus.lua
-- aliases them from the Mizuki table instead.

tryFireImmaculateHeartTear = function(player, direction)
    if not player:HasCollectible(
        CollectibleType.COLLECTIBLE_IMMACULATE_HEART
    ) then
        return
    end
    if player:GetCollectibleRNG(
        CollectibleType.COLLECTIBLE_IMMACULATE_HEART
    ):RandomFloat() >= Mizuki.WeaponParameters.ImmaculateHeartChance then
        return
    end

    local shotDirection = direction and direction:Normalized() or Vector(0, -1)
    local tear = player:FireTear(
        player.Position,
        shotDirection:Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed),
        false,
        true,
        false,
        player,
        1
    )
    tear.Parent = player
    tear.SpawnerEntity = player
    tear:AddTearFlags(
        TearFlags.TEAR_ORBIT_ADVANCED | TearFlags.TEAR_SPECTRAL
    )
    -- Test the native advanced orbit with the negative falling acceleration
    -- used by Reverie's orbiting projectile implementation. Keep FireTear's
    -- original FallingSpeed so this changes only the downward acceleration.
    tear.FallingAcceleration = IMMACULATE_HEART_FALLING_ACCELERATION
end

advanceLeadPencil = function(player, direction)
    if not player:HasCollectible(
        CollectibleType.COLLECTIBLE_LEAD_PENCIL
    ) then
        return
    end

    local data = player:GetData()
    data.MizukiLeadPencilShots = (data.MizukiLeadPencilShots or 0) + 1
    if data.MizukiLeadPencilShots < Mizuki.WeaponParameters.PencilTriggerShots then
        return
    end
    data.MizukiLeadPencilShots = data.MizukiLeadPencilShots - Mizuki.WeaponParameters.PencilTriggerShots

    local shotDirection = direction and direction:Normalized() or Vector(0, -1)
    local rng = player:GetCollectibleRNG(
        CollectibleType.COLLECTIBLE_LEAD_PENCIL
    )
    local hasBloodClot = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BLOOD_CLOT
    )
    for _ = 1, Mizuki.WeaponParameters.PencilTearCount do
        local velocity = shotDirection
            :Rotated(rng:RandomFloat() * Mizuki.WeaponParameters.PencilSpreadDegrees - Mizuki.WeaponParameters.PencilSpreadDegrees * 0.5)
            :Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed * (Mizuki.WeaponParameters.PencilSpeedMin + rng:RandomFloat() * Mizuki.WeaponParameters.PencilSpeedRandomSpan))
        local tear = player:FireTear(
            player.Position,
            velocity,
            true,
            false,
            true,
            player,
            1
        )
        tear.Scale = tear.Scale * (Mizuki.WeaponParameters.PencilScaleMin + rng:RandomFloat() * Mizuki.WeaponParameters.PencilScaleRandomSpan)
        tear.Height = Mizuki.WeaponParameters.PencilBaseHeight - rng:RandomFloat() * Mizuki.WeaponParameters.PencilHeightRandomSpan
        tear.FallingSpeed = Mizuki.WeaponParameters.PencilBaseFallingSpeed - rng:RandomFloat() * Mizuki.WeaponParameters.PencilFallingSpeedRandomSpan
        tear.FallingAcceleration = 1 + rng:RandomFloat()
        -- Lead Pencil normally turns half of its ordinary tears into the
        -- highlighted blood-tear sprite. Blood Clot is a separate exception:
        -- tint the complete barrage deep red without replacing special tear
        -- variants (or mixing BLUE and BLOOD base sprites).
        if hasBloodClot then
            tear.Color = LEAD_PENCIL_BLOOD_CLOT_COLOR
        elseif tear.Variant == TearVariant.BLUE and rng:RandomFloat() < Mizuki.WeaponParameters.PencilBloodTearChance then
            tear:ChangeVariant(TearVariant.BLOOD)
        end
        tear:GetData().MizukiLeadPencilTear = true
    end
end

-- The feature files in scripts/ are separate chunks (each with its own 200-local
-- budget), so everything they share travels through the Mizuki table; each file
-- aliases what it needs at its own top.
Mizuki.isMizuki = isMizuki
Mizuki.CANNON_ART_SCALE_MULTIPLIER = CANNON_ART_SCALE_MULTIPLIER
Mizuki.CANNON_FIRING_REFLECTION_SPAN = CANNON_FIRING_REFLECTION_SPAN
Mizuki.BEAM_DAMAGE_INTERVAL = BEAM_DAMAGE_INTERVAL
Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS = MIZUKI_FORBIDDEN_TEAR_FLAGS
Mizuki.usesAutomaticBeam = usesAutomaticBeam
Mizuki.getChargeDamageMultiplier = getChargeDamageMultiplier
Mizuki.getBeamDamageTiming = getBeamDamageTiming
Mizuki.addOccultHoming = addOccultHoming
Mizuki.fireMizukiBeam = fireMizukiBeam
Mizuki.removeActiveMizukiBeams = removeActiveMizukiBeams
Mizuki.hasActiveMizukiBeam = hasActiveMizukiBeam
Mizuki.tryFireImmaculateHeartTear = tryFireImmaculateHeartTear
Mizuki.advanceLeadPencil = advanceLeadPencil
Mizuki.IMMACULATE_HEART_FALLING_ACCELERATION = IMMACULATE_HEART_FALLING_ACCELERATION
Mizuki.getCapsuleState = getCapsuleState
Mizuki.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE
Mizuki.GLOWING_HOUR_GLASS = GLOWING_HOUR_GLASS
Mizuki.CAPSULE_STAT_CACHE_FLAGS = CAPSULE_STAT_CACHE_FLAGS
Mizuki.LEAD_PENCIL_BLOOD_CLOT_COLOR = LEAD_PENCIL_BLOOD_CLOT_COLOR
Mizuki.capsuleStates = capsuleStates
Mizuki.cannonReconcileStates = cannonReconcileStates
Mizuki.getCannonReconcileState = getCannonReconcileState
Mizuki.getStableShotCount = getMizukiStableBeamCount
Mizuki.BFFS = BFFS
Mizuki.LUCKY_FOOT = LUCKY_FOOT
Mizuki.MOMS_BOX = MOMS_BOX
Mizuki.SACK_HEAD = SACK_HEAD

-- Order matters only in that the capsule file publishes the pocket helpers the
-- fan file aliases.
include("scripts/weapon_synergies")
include("scripts/epic_fetus")
include("scripts/experimental_capsule")
include("scripts/fan")
include("scripts/moms_knife")
include("scripts/cannon_echo")
Mizuki.RegisterPickupLocalization()
