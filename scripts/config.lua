-- Shared parameters, native IDs and geometry constants.
local Config = {}
Mizuki.Config = Config

-- Units and native lifecycle contracts used by more than one feature.
-- Values with different meanings stay separate even when their defaults match.
Mizuki.RuntimeParameters = {
    LogicFramesPerSecond = 30,
    FrameComparisonEpsilon = 0.0001,
    MinimumFireInterval = 0.25,
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
    BeamHitboxYOffset = 22.5,
    CannonIdleSwingFrames = 150,
    CannonIdleFacingOffset = 10,
    CannonRotationReturnRate = 0.18,
    CannonReleaseGraceFrames = 6,
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
    EyeSoreFetusHalfAngle = 25,
    LungMinExtraBeams = 3,
    LungMaxExtraBeams = 5,
    LungExtraBaseShotsPerCopy = 5,
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
    Tech5 = {
        RollIntervalFrames = 8,
        RollRandomBound = 3,
        ActiveFrames = 2,
    },
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
    TearTint = {
        Red = 246, Green = 171, Blue = 180, ColorizeIntensity = 5,
        TrisagionColorizeIntensity = 1.5,
        BelialMultiplier = { Red = 1, Green = 0.4, Blue = 0.4 },
    },
}

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

if Mizuki.FanItem <= 0 then
    Mizuki.FanItem = Isaac.GetItemIdByName("小博兔")
end

Mizuki.FanVariant = Isaac.GetEntityVariantByName("Mizuki Fan Familiar")

Config.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = 9201
Config.GLOWING_HOUR_GLASS = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
Config.BOX_OF_FRIENDS = CollectibleType.COLLECTIBLE_BOX_OF_FRIENDS
Config.BFFS = CollectibleType.COLLECTIBLE_BFFS
Config.LUCKY_FOOT = CollectibleType.COLLECTIBLE_LUCKY_FOOT
Config.MOMS_BOX = CollectibleType.COLLECTIBLE_MOMS_BOX
Config.SACK_HEAD = CollectibleType.COLLECTIBLE_SACK_HEAD
Config.CAPSULE_STAT_CACHE_FLAGS = CacheFlag.CACHE_DAMAGE
    | CacheFlag.CACHE_FIREDELAY
    | CacheFlag.CACHE_SPEED
    | CacheFlag.CACHE_SHOTSPEED
    | CacheFlag.CACHE_RANGE
    | CacheFlag.CACHE_LUCK

Config.CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER = 2.5
Config.CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER = 2.50
Config.CURSED_EYE_MAX_CHARGE_MULTIPLIER = 2
Config.CURSED_EYE_CHOCOLATE_SHOT_THRESHOLDS = { 1 / 3, 1 / 2, 3 / 4, 1 }
Config.AUTOMATIC_BEAM_BASE_FIRE_RATE = 7.5
Config.AUTOMATIC_BEAM_RATE_EXCLUSIONS = {
    CollectibleType.COLLECTIBLE_MOMS_KNIFE,
}

Config.DEFAULT_TEARS_MULTIPLIER = 0.5
Config.TECHNOLOGY_ZERO_TEARS_MULTIPLIER = 1 / 3
Config.BRIMSTONE_TEARS_MULTIPLIER = 1 / 3
Config.DR_FETUS_TEARS_MULTIPLIER = 0.4
Config.TEARS_MODIFIER = 0
Config.WEAPON_STAT_CACHE_PRIORITY = CallbackPriority.LATE + 1
Config.DEFAULT_DAMAGE_MULTIPLIER = 0.75
Config.TECHNOLOGY_ZERO_DAMAGE_MULTIPLIER = 1
Config.TECHNOLOGY_BRIMSTONE_DAMAGE_MULTIPLIER = 1.5
Config.TECHNOLOGY_ZERO_SYNERGY_DAMAGE_MULTIPLIER = 1.5
Config.MOVE_SPEED_MODIFIER = -0.15
Config.LUCK_MODIFIER = 1
Config.BEAM_DISTANCE = 240
Config.BEAM_HITBOX_Y_OFFSET = Mizuki.WeaponParameters.BeamHitboxYOffset

-- Mizuki begins at HUD Range 6.50, which is internal TearRange 260.
-- Its baseline beam length is anchored to that starting stat.
Config.BASE_TEAR_RANGE = 260
Config.MIN_BEAM_WIDTH_SCALE = 0.75
Config.MAX_BEAM_WIDTH_SCALE = 5.00
Config.LEAD_PENCIL_BLOOD_CLOT_COLOR = Color(0.9, 0, 0, 1, 0, 0, 0)

-- Wiki timing is stated in 60 Hz render frames; gameplay callbacks advance at
-- 30 Hz. A native laser's four-render-frame damage cadence is two logical frames.
Config.BEAM_DAMAGE_INTERVAL = 2

-- Anti-Gravity's waiting state does not fit either Mizuki beam lifecycle: it
-- can freeze a persistent path and can leave a finite charged shot suspended.
-- It needs a dedicated synergy rather than being copied onto EntityLaser.
Config.MIZUKI_FORBIDDEN_TEAR_FLAGS = TearFlags.TEAR_WAIT

-- The engine lands a laser's damage every 2 frames, so a beam that owes N ticks
-- lives N * 2 + 1 frames: the frame it spawns on, then two frames per tick.
-- Technology Zero restores Mizuki's original eight-tick finite beam. Charge
-- items can still select the charge/release input path without inheriting this
-- damage schedule.
Config.TECHNOLOGY_ZERO_BEAM_TICK_COUNT = 8

Config.TECHNOLOGY_ZERO_BEAM_DURATION =
    Config.TECHNOLOGY_ZERO_BEAM_TICK_COUNT * Config.BEAM_DAMAGE_INTERVAL + 1

Config.TECHNOLOGY_ZERO_BEAM_TOTAL_DAMAGE_MULTIPLIER = 8.00
Config.DEFAULT_BEAM_TICK_COUNT = 4
Config.DEFAULT_BEAM_DURATION = Config.DEFAULT_BEAM_TICK_COUNT * Config.BEAM_DAMAGE_INTERVAL + 1
Config.DEFAULT_BEAM_TOTAL_DAMAGE_MULTIPLIER = 4.00

-- Repentance's line weapons keep ordinary multishots close together. This is
-- the laser/brimstone correction used by the vanilla-compatible multishot
-- fallback: the basic 2.17-degree spread is widened by 1500 / 1397.
Config.LINE_MULTISHOT_SPREAD_FACTOR = 1500 / 1397
Config.LINE_MULTISHOT_BASE_SPREAD = 2.17
Config.LINE_MULTISHOT_GLASSES_SPREAD = 2
Config.MAX_STANDARD_MULTISHOT = 16
Config.MAX_WIZ_GROUPS = 8
Config.DUPLICATE_WEAPON_SPREAD = 2.333
Config.DUPLICATE_LUNG_SPREAD = 2.7
Config.WIZ_GROUP_SPREAD = 3
Config.DUPLICATE_MULTISHOT_ITEMS = {
    CollectibleType.COLLECTIBLE_TECHNOLOGY,
    CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO,
    CollectibleType.COLLECTIBLE_MOMS_KNIFE,
    CollectibleType.COLLECTIBLE_DR_FETUS,
    CollectibleType.COLLECTIBLE_EPIC_FETUS,
    CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE,
    CollectibleType.COLLECTIBLE_TECH_X,
}

Config.WIZ_ARC_HALF_ANGLE = 45
Config.CONJOINED_SIDE_ANGLE = 45
Config.IMMACULATE_HEART_FALLING_ACCELERATION = -0.08
Config.MIN_CHARGE_DAMAGE_MULTIPLIER = 0.45
Config.MIZUKI_TEAR_COLOR = Color(1, 1, 1, 1, 0, 0, 0)

Config.MIZUKI_TEAR_COLOR:SetColorize(
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Red / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Green / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.ColorizeIntensity * Mizuki.WeaponParameters.TearTint.Blue / Mizuki.RuntimeParameters.ColorByteMax,
    1
)

Config.CANNON_ANM2 = "gfx/entities/mizuki/mizuki_cannon.anm2"
Config.CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon.png"
Config.CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light.png"
Config.LEFT_CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_left.png"
Config.LEFT_CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light_left.png"

-- Player size and Ludovico copies form the shared weapon scale. Each visual
-- then applies one explicit art multiplier: cannon art is authored at 0.65,
-- while Mom's Knife uses its native full-size art (1.0).
Config.CANNON_ART_SCALE_MULTIPLIER = 0.65
Config.MOMS_KNIFE_ART_SCALE_MULTIPLIER = 1
Config.IDLE_CANNON_DEPTH_OFFSET = 70
Config.MOMS_KNIFE_DEPTH_OFFSET = 5
Config.CANNON_DEPTH_OFFSET = 30
Config.FIRING_CANNON_DEPTH_OFFSET = 30
Config.HORIZONTAL_BACK_DEPTH_OFFSET = 20
Config.HORIZONTAL_FRONT_DEPTH_OFFSET = 30
Config.CHARGE_BAR_SCALE = Vector(1, 1)
Config.CHARGE_BAR_OFFSET = Vector(0, 5)
Config.CHARGE_BAR_NORMAL_GRAPHICS_OFFSET = Vector(1, 0)

-- Resting formation: two separated rabbit ears above the head.
-- Eye identity is character-relative: 1 = left, 2 = right. At rest Mizuki
-- faces down, so her right cannon occupies the screen-left resting slot.
Config.CANNON_OFFSETS = { Vector(12, -60), Vector(-12, -60) }
Config.CANNON_IDLE_OFFSETS = Vector(0, -5)
Config.CANNON_MOMS_KNIFE_IDLE_OFFSET = Vector(0, -8)
Config.CANNON_GROUP_SPACING = 16

-- Attack-pair half-spacing at the vertical and horizontal points of the orbit.
Config.VERTICAL_CANNON_X = 5
Config.HORIZONTAL_CANNON_HALF_SPACING = 3

-- The attack midpoint circles the player's collision position, then the whole
-- formation is lifted by the cannon's visual height. Keep the old horizontal
-- midpoint (10, -22.5) while bringing the upward pose closer to the player.
Config.CANNON_ATTACK_ORBIT_RADIUS = 20
Config.CANNON_ATTACK_ORBIT_HEIGHT = 22.5

-- Mom's Knife moves the attack cannon and its laser outward together.
-- Its idle height is independent of this attack-radius bonus.
Config.CANNON_MOMS_KNIFE_ORBIT_RADIUS_BONUS = 20

-- Side-on projection of the hand-drawn cannon body at vertical aim.
Config.VERTICAL_CANNON_BODY_X_MULTIPLIER = 0.75
Config.CANNON_FOLLOW_SPEED = 0.25

-- Keep a little elastic motion without letting normal player movement pull the
-- cannons far enough away from their authored silhouette to cross the body.
Config.CANNON_MAX_FOLLOW_LAG = 8
Config.CANNON_FLOAT_AMPLITUDE = 2
Config.CANNON_FLOAT_PERIOD = 45

-- Tap Drop to toggle a stationary cannon pair; hold it to invert that state
-- only until release. The game's own Drop action is left untouched.
Config.LEFT_CANNON_IDLE_ROTATION = -55
Config.RIGHT_CANNON_IDLE_ROTATION = -10
Config.LEFT_CANNON_IDLE_OUTER_ROTATION = -65
Config.RIGHT_CANNON_IDLE_OUTER_ROTATION = -0.1

-- The configured idle rotations above are the inward end of the motion. Over
-- five seconds at 30 logical frames per second, the pair opens to -65 / -0.1 and
-- returns. Cosine position produces sinusoidal speed: fastest halfway through
-- each stroke and smoothly slowing to zero at both ends.
-- Orbit distance past the ring's own collision radius.
Mizuki.LUDOVICO_CANNON_ORBIT_PADDING = 0
Mizuki.LUDOVICO_CANNON_ORBIT_DEGREES_PER_FRAME = 3
Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER = 3
Mizuki.LUDOVICO_CANNON_MIN_HIT_RADIUS = 10

Config.LUDOVICO_TRIGGERED_BEAM_DAMAGE_MULTIPLIER = 0.5
Config.TRANSIENT_BEAM_SOURCE_BOOK_WORM = "book_worm"
Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE = "moms_eye"
Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS = "lokis_horns"
Config.TRANSIENT_BEAM_SOURCE_EYE_SORE = "eye_sore"
Config.LUDOVICO_INCUBUS_MULTIPLIER = 0.75
Config.LUDOVICO_TWISTED_BABY_MULTIPLIER = 0.375

-- The decorative idle turn pivots around the cannon sprite's bottom centre,
-- while its Familiar entity (and therefore the beam origin) stays fixed.
Config.CANNON_IDLE_ROTATION_PIVOT = Vector(0, 22)

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
Config.CANNON_FIRING_REFLECTION_SPAN = 2 * Config.CANNON_ATTACK_ORBIT_HEIGHT
Config.CANNON_IDLE_REFLECTION_SPAN = -2 * Config.CANNON_OFFSETS[1].Y

-- How fast the reflection distance follows a change between the resting and
-- firing layouts. The cannon's own pose already eases between those layouts
-- (CANNON_FOLLOW_SPEED for the position and a separate return speed for the
-- idle tilt), so the reflection eases at a similar rate instead of jumping the
-- whole distance in the frame the player starts or stops firing. The immediate
-- attack's explicit position snap is handled separately below.
Config.CANNON_REFLECTION_SPAN_SPEED = Config.CANNON_FOLLOW_SPEED
Config.CHARGE_BAR_COLOR = Color(1, 1, 1, 1, 0, 0, 0)

Config.CHARGE_BAR_COLOR:SetColorize(
    Mizuki.WeaponParameters.TearTint.Red / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.Green / Mizuki.RuntimeParameters.ColorByteMax,
    Mizuki.WeaponParameters.TearTint.Blue / Mizuki.RuntimeParameters.ColorByteMax,
    1
)

Config.SHOOT_ACTIONS = {
    { Action = ButtonAction.ACTION_SHOOTLEFT, Direction = Vector(-1, 0) },
    { Action = ButtonAction.ACTION_SHOOTRIGHT, Direction = Vector(1, 0) },
    { Action = ButtonAction.ACTION_SHOOTUP, Direction = Vector(0, -1) },
    { Action = ButtonAction.ACTION_SHOOTDOWN, Direction = Vector(0, 1) },
}

Mizuki.CANNON_ATTACK_ORBIT_HEIGHT = Config.CANNON_ATTACK_ORBIT_HEIGHT

-- Eight-way aim -------------------------------------------------------------
-- Shape the shooting input the way the base game does: eight directions. Mouse
-- aiming and an analog stick both report a continuous angle, and letting the
-- cannons use that directly hands out free 360 degree aiming that items meant
-- to grant it (Analog Stick and Mom's Knife) are supposed to be the source of.
--
-- Aiming at a target reticle (Marked, Eye of the Occult, Epic Fetus) is left
-- alone: those items aim at a point, so they stay exempt by construction.
Config.EIGHT_WAY_AIM = {
    Vector(1, 0),
    Vector(Mizuki.WeaponParameters.DiagonalAimComponent, Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(0, 1),
    Vector(-Mizuki.WeaponParameters.DiagonalAimComponent, Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(-1, 0),
    Vector(-Mizuki.WeaponParameters.DiagonalAimComponent, -Mizuki.WeaponParameters.DiagonalAimComponent),
    Vector(0, -1),
    Vector(Mizuki.WeaponParameters.DiagonalAimComponent, -Mizuki.WeaponParameters.DiagonalAimComponent),
}

-- Brimstone's shot is the item's own shape rather than the Technology one: the
-- item's own nine ticks at the engine's cadence, so 9 * 2 + 1 frames long, with
-- the full panel on every tick.
Config.BRIMSTONE_BEAM_TICK_COUNT = 9
Config.TRISAGION_BRIMSTONE_BEAM_TICK_COUNT = 13
Config.BRIMSTONE_BEAM_DURATION = Config.BRIMSTONE_BEAM_TICK_COUNT * Config.BEAM_DAMAGE_INTERVAL + 1
Config.TRISAGION_BRIMSTONE_BEAM_DURATION =
    Config.TRISAGION_BRIMSTONE_BEAM_TICK_COUNT * Config.BEAM_DAMAGE_INTERVAL + 1
Config.BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER = 9.00

-- EntityLaser appends its own ending after Timeout reaches zero. Keep that
-- ending inside the advertised total lifetime instead of adding it afterwards.
Config.TECHNOLOGY_BEAM_END_FRAMES = 3
Config.BRIMSTONE_BEAM_END_FRAMES = 10

-- Vanilla's sustained Brimstone rule scales every damage tick by Tears / 5.
-- Keep this rule on the generic automatic-beam path rather than on any item:
-- Soy Milk, Almond Milk, a Kidney Stone stat spike which crosses the generic
-- threshold, high-Tears weapon modes and future automatic sources all receive
-- the same final-stat-based multiplier.
-- Both cannons own a real beam, so each beam receives the complete multiplier.
Config.AUTOMATIC_BEAM_FIRE_RATE_DAMAGE_DIVISOR = 5

Mizuki.CANNON_ART_SCALE_MULTIPLIER = Config.CANNON_ART_SCALE_MULTIPLIER
Mizuki.CANNON_FIRING_REFLECTION_SPAN = Config.CANNON_FIRING_REFLECTION_SPAN
Mizuki.BEAM_DAMAGE_INTERVAL = Config.BEAM_DAMAGE_INTERVAL
Mizuki.DEFAULT_BEAM_DURATION = Config.DEFAULT_BEAM_DURATION
Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS = Config.MIZUKI_FORBIDDEN_TEAR_FLAGS
Mizuki.IMMACULATE_HEART_FALLING_ACCELERATION = Config.IMMACULATE_HEART_FALLING_ACCELERATION
Mizuki.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = Config.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE
Mizuki.GLOWING_HOUR_GLASS = Config.GLOWING_HOUR_GLASS
Mizuki.CAPSULE_STAT_CACHE_FLAGS = Config.CAPSULE_STAT_CACHE_FLAGS
Mizuki.LEAD_PENCIL_BLOOD_CLOT_COLOR = Config.LEAD_PENCIL_BLOOD_CLOT_COLOR
Mizuki.BFFS = Config.BFFS
Mizuki.LUCKY_FOOT = Config.LUCKY_FOOT
Mizuki.MOMS_BOX = Config.MOMS_BOX
Mizuki.SACK_HEAD = Config.SACK_HEAD
