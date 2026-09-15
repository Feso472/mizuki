Mizuki = RegisterMod("Mizuki", 1)

-- Vanilla Repentance+ only. Mizuki's beam uses a native EntityLaser for
-- collision, damage ticks and tear-effect compatibility. Lua still owns its
-- charge cycle and keeps the laser anchored to the firing cannon position.
Mizuki.PlayerType = Isaac.GetPlayerTypeByName("弥月", false)
Mizuki.PlayerAnm2 = "gfx/characters/mizuki/character_mizuki.anm2"
Mizuki.HairCostume = Isaac.GetCostumeIdByPath(
    "gfx/characters/mizuki/character_mizuki_hair.anm2"
)
Mizuki.CannonVariant = Isaac.GetEntityVariantByName("Mizuki Cannon")
Mizuki.ExperimentalCapsuleCard = Isaac.GetCardIdByName("Mizuki Experimental Capsule")
Mizuki.FanItem = Isaac.GetItemIdByName("Mizuki Fan")
Mizuki.FanVariant = Isaac.GetEntityVariantByName("Mizuki Fan Familiar")
local EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = 9201

-- Present the capsule as an ordinary Experimental Pill. Register after the
-- game starts because EID rebuilds its icon tables during its own startup.
local function registerExperimentalCapsuleEID()
    if not EID or not EID.addCard or not EID.addIcon then
        return
    end

    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ 随机提升1项属性#↓ 随机降低1项属性",
        "实验性胶囊",
        "zh_cn"
    )
    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ Increases 1 random stat#↓ Decreases 1 random stat",
        "Experimental Pill",
        "en_us"
    )

    local capsuleEIDIcon = Sprite()
    capsuleEIDIcon:Load("gfx/items/mizuki/experimental_capsule.anm2", true)
    capsuleEIDIcon:Play("EID", true)
    EID:addIcon(
        "Card" .. Mizuki.ExperimentalCapsuleCard,
        "EID",
        0,
        9,
        8,
        0,
        1,
        capsuleEIDIcon
    )
end

Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerExperimentalCapsuleEID)

local GLOWING_HOUR_GLASS = CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS
local HOUR_GLASS = CollectibleType.COLLECTIBLE_HOURGLASS
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

local MIN_CHARGE_PERCENT = 0.50
local CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER = 2
local CHOCOLATE_MILK_MIN_DAMAGE_MULTIPLIER = 0.25
local CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER = 2.50
local CURSED_EYE_MAX_CHARGE_MULTIPLIER = 3
local CURSED_EYE_EXTRA_SHOT_INTERVAL_PERCENT = 0.50
local TEARS_MULTIPLIER = 1 / 3
local TEARS_MODIFIER = 0
local DAMAGE_MULTIPLIER = 0.9
local MOVE_SPEED_MODIFIER = -0.15
local LUCK_MODIFIER = 1
local BEAM_DISTANCE = 240
local HORIZONTAL_BEAM_HITBOX_Y_OFFSET = 22.5
-- Empirical perpendicular alignment between the rotated cannon sprite centre
-- and the native Technology laser centreline. This is not a laser path sample
-- interval.
local DIAGONAL_LASER_ORIGIN_CORRECTION = 4
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
-- Finite shots use that real cadence and the full panel on every tick; the
-- multiplier below is the whole shot's budget, so lowering it scales the ticks.
local BEAM_TICK_COUNT = 8
local BEAM_DURATION = BEAM_TICK_COUNT * 2 + 1
local BEAM_TOTAL_DAMAGE_MULTIPLIER = 8.00
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
    5 * 246 / 255,
    5 * 171 / 255,
    5 * 180 / 255,
    1
)

local CANNON_ANM2 = "gfx/entities/mizuki/mizuki_cannon.anm2"
local CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon.png"
local CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light.png"
local LEFT_CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_left.png"
local LEFT_CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light_left.png"
local CANNON_SCALES = {
    Vector(0.65, 0.65),
    Vector(0.65, 0.65),
}
local IDLE_CANNON_DEPTH_OFFSET = 70
local CANNON_DEPTH_OFFSET = 30
local FIRING_CANNON_DEPTH_OFFSET = 30
local HORIZONTAL_BACK_DEPTH_OFFSET = -30
local HORIZONTAL_FRONT_DEPTH_OFFSET = 30
local CHARGE_BAR_SCALE = Vector(1, 1)
local CHARGE_BAR_OFFSET = Vector(0, 5)
local CHARGE_BAR_NORMAL_GRAPHICS_OFFSET = Vector(1, 0)
-- Resting formation: two separated rabbit ears above the head.
local CANNON_OFFSETS = { Vector(-12, -60), Vector(12, -60) }
local CANNON_IDLE_OFFSETS = Vector(0, -5)
local CANNON_GROUP_SPACING = 16
local HORIZONTAL_CANNON_X = 10
-- Horizontal pair sits close to Isaac's normal tear-launch height.
local HORIZONTAL_CANNON_CENTER_Y = -22.5
local HORIZONTAL_CANNON_HALF_SPACING = 2.5
local CANNON_FOLLOW_SPEED = 0.22
local CANNON_FLOAT_AMPLITUDE = 2
local LEFT_CANNON_IDLE_ROTATION = -55
local RIGHT_CANNON_IDLE_ROTATION = -5
local CANNON_ROTATION_RETURN_SPEED = 0.18
-- The decorative idle turn pivots around the cannon sprite's bottom centre,
-- while its Familiar entity (and therefore the beam origin) stays fixed.
local CANNON_IDLE_ROTATION_PIVOT = Vector(0, 10)

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
-- While firing, the cannon's own height above the player varies with the facing
-- (60 / 22.5 / 0 px when aiming up / sideways / down), so a geometric mirror
-- would drop the reflection on top of the cannon when aiming down. Firing lays
-- the pair out as a trapezoid around the aim line in every direction, so the
-- sideways height is the distance that reads as a reflection for every facing.
--
-- At rest the cannons genuinely sit above the player's head, and there the
-- reflection is a plain geometric mirror instead, using that head height.
--
-- Both are derived from the layout that defines them, so retuning either layout
-- retunes its reflection distance with it.
local CANNON_FIRING_REFLECTION_SPAN = -2 * HORIZONTAL_CANNON_CENTER_Y
local CANNON_IDLE_REFLECTION_SPAN = -2 * CANNON_OFFSETS[1].Y

-- How fast the reflection distance follows a change between the resting and
-- firing layouts. The cannon's own pose already eases between those layouts
-- (CANNON_FOLLOW_SPEED for the position, CANNON_ROTATION_RETURN_SPEED for the
-- idle tilt), so the reflection eases at a similar rate instead of jumping the
-- whole distance in the frame the player starts or stops firing.
local CANNON_REFLECTION_SPAN_SPEED = 0.22

local function getDiagonalLaserOriginCorrection(direction)
    if math.abs(direction.X) <= 0.001 or math.abs(direction.Y) <= 0.001 then
        return Vector.Zero
    end
    local normalized = direction:Normalized()
    local quadrantSign = normalized.X * normalized.Y > 0 and -1 or 1
    return normalized:Rotated(90):Resized(
        DIAGONAL_LASER_ORIGIN_CORRECTION * quadrantSign
    )
end

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
        if targetDirection:Length() > 0.01 then
            originDirection = targetDirection:Normalized()
        end
    end

    local beamDirection = originDirection:Rotated(directionOffset)
    local isHorizontal = math.abs(originDirection.X)
        > math.abs(originDirection.Y)
    local originCorrection = isHorizontal
        and Vector.Zero
        or getDiagonalLaserOriginCorrection(originDirection)
    return beamDirection, originCorrection
end

local CHARGE_BAR_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
CHARGE_BAR_COLOR:SetColorize(
    246 / 255,
    171 / 255,
    180 / 255,
    1
)
local chargeBar = Sprite()
chargeBar:Load("gfx/chargebar_revelation.anm2", true)

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
    if Mizuki.HairCostume >= 0 and not data.MizukiHairCostumeApplied then
        player:AddNullCostume(Mizuki.HairCostume)
        data.MizukiHairCostumeApplied = true
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_PEFFECT_UPDATE,
    Mizuki.EnsureHairCostume
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

local function getChargeProfile(player)
    -- Input advances in whole logical frames, but MaxFireDelay may be
    -- fractional. Keep the unrounded duration for damage interpolation and use
    -- the ceiling only for the first frame on which a charge is considered full.
    local baseChargeFrames = math.max(1, player.MaxFireDelay + 1)
    local baseFrames = math.max(1, math.ceil(baseChargeFrames))
    local minMultiplier = MIN_CHARGE_PERCENT
    local maxMultiplier = 1
    local hasChocolateMilk = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CHOCOLATE_MILK
    ) and not usesAutomaticBeam(player)

    local hasCursedEye = player:HasCollectible(
        CollectibleType.COLLECTIBLE_CURSED_EYE
    ) and not usesAutomaticBeam(player)

    -- Each item owns its charge range. When both are present, keep the longer
    -- range instead of multiplying them: Chocolate Milk reaches maximum damage
    -- at 2x base charge while Cursed Eye reaches five shots at 3x.
    if hasChocolateMilk then
        minMultiplier = 0
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
        MinFrames = math.max(1, math.ceil(baseFrames * minMultiplier)),
        MaxFrames = math.max(1, math.ceil(baseFrames * maxMultiplier)),
        ChocolateMaxFrames = math.max(1, math.ceil(
            baseChargeFrames * CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER
        )),
        ChocolateMaxChargeFrames = math.max(
            1,
            baseChargeFrames * CHOCOLATE_MILK_MAX_CHARGE_MULTIPLIER
        ),
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

    if charge <= profile.BaseFrames then
        -- 0.25 is the theoretical zero-charge Brimstone floor. The earliest
        -- releasable shot has already accumulated one logical frame. Interpolate
        -- against the unrounded native duration: at 18.75 frames the first shot
        -- is exactly 0.29x, so 3.5 panel damage is 1.015 (displayed as 1.02) and
        -- three identical hits total 3.045 (displayed as 3.05).
        local normalizedBaseCharge = math.max(
            0,
            math.min(1, charge / profile.BaseChargeFrames)
        )
        return CHOCOLATE_MILK_MIN_DAMAGE_MULTIPLIER
            + (1 - CHOCOLATE_MILK_MIN_DAMAGE_MULTIPLIER)
                * normalizedBaseCharge
    end

    local extendedRange = math.max(
        1,
        profile.ChocolateMaxChargeFrames - profile.BaseChargeFrames
    )
    local normalizedExtendedCharge = math.max(
        0,
        math.min(1, (charge - profile.BaseChargeFrames) / extendedRange)
    )
    return 1 + (CHOCOLATE_MILK_MAX_DAMAGE_MULTIPLIER - 1)
        * normalizedExtendedCharge
end

local function getCursedEyeShotCount(player, charge, profile)
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        or usesAutomaticBeam(player)
    then
        return 1
    end

    local shotCount = 1
    for extraShot = 1, 4 do
        local threshold = math.ceil(profile.BaseFrames * (
            1 + extraShot * CURSED_EYE_EXTRA_SHOT_INTERVAL_PERCENT
        ))
        if charge >= threshold then
            shotCount = shotCount + 1
        end
    end
    return shotCount
end

local function getDisplayedFireRate(player)
    return 30 / math.max(player.MaxFireDelay + 1, 0.001)
end

usesAutomaticBeam = function(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
        or getDisplayedFireRate(player) >= 15
        or player:GetData().MizukiKidneyStoneBurst ~= nil
end

local SHOOT_ACTIONS = {
    { Action = ButtonAction.ACTION_SHOOTLEFT, Direction = Vector(-1, 0) },
    { Action = ButtonAction.ACTION_SHOOTRIGHT, Direction = Vector(1, 0) },
    { Action = ButtonAction.ACTION_SHOOTUP, Direction = Vector(0, -1) },
    { Action = ButtonAction.ACTION_SHOOTDOWN, Direction = Vector(0, 1) },
}

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
-- to grant it (Analog Stick) are supposed to be the source of.
--
-- Aiming at a target reticle (Marked, Eye of the Occult, Epic Fetus) is left
-- alone: those items aim at a point, so they stay exempt by construction.
local EIGHT_WAY_AIM = {
    Vector(1, 0),
    Vector(0.70710678, 0.70710678),
    Vector(0, 1),
    Vector(-0.70710678, 0.70710678),
    Vector(-1, 0),
    Vector(-0.70710678, -0.70710678),
    Vector(0, -1),
    Vector(0.70710678, -0.70710678),
}

local function hasFreeAim(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_ANALOG_STICK)
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

local function getShootingIntent(player, data)
    local target = getMizukiTargetReticle(player, data)
    if target then
        local targetDirection = target.Position - player.Position
        if targetDirection:Length() > 0.01 then
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
        local mouseDirection = Input.GetMousePosition(true) - player.Position
        if mouseDirection:Length() > 0.01 then
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

    local shootingInput = player:GetShootingInput()
    if shootingInput:Length() > 0.01 then
        local direction = quantizeAim(player, shootingInput)
        data.MizukiLastShootDirection = direction
        return true, direction
    end

    -- A newly pressed opposite direction can cancel the combined vector to
    -- zero. In that case only, let the new key choose the retained direction.
    if triggeredDirection then
        local direction = quantizeAim(player, triggeredDirection)
        data.MizukiLastShootDirection = direction
        return true, direction
    end

    for _, input in ipairs(SHOOT_ACTIONS) do
        if Input.IsActionPressed(input.Action, controller) then
            local retained = data.MizukiLastShootDirection
                or input.Direction
            return true, quantizeAim(player, retained)
        end
    end

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

    return math.max(40, BEAM_DISTANCE * player.TearRange / BASE_TEAR_RANGE)
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
local BRIMSTONE_BEAM_DURATION = BRIMSTONE_BEAM_TICK_COUNT * 2 + 1
local BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER = 9.00
-- EntityLaser appends its own ending after Timeout reaches zero. Keep that
-- ending inside the advertised total lifetime instead of adding it afterwards.
local TECHNOLOGY_BEAM_END_FRAMES = 3
local BRIMSTONE_BEAM_END_FRAMES = 10
-- Measured against vanilla: a native Brimstone beam ticks every 2 frames for
-- 1x the panel per tick (panel 0.7, tear delay 5, hit log at frames 3155/3157/
-- 3159...), so the held beam's per-tick is rate/5 with no extra factor. Each
-- cannon lands its own hit, so the pair is simply twice a single cannon.
local AUTOMATIC_BEAM_TWO_CANNON_MULTIPLIER = 1

-- Finite beams live exactly as long as their tick count needs. ShotSpeed still
-- controls their width, but no longer reduces hit count or proc opportunities.
local function getBeamDamageTiming(player, automatic, brimstone)
    if automatic then
        -- A held beam is not a finite shot, so it has no per-shot budget to
        -- spread across its ticks: while the button is down the cannons keep
        -- refreshing it, and every engine tick deals the panel.
        -- Measured vanilla (non-Mizuki) Brimstone on this build: 1x the panel
        -- per tick, every 2 frames, at both tear delay 5 and tear delay 32 - the
        -- fire rate only changes how often the beam is fired, never its per-tick
        -- damage. Each cannon lands its own hit.
        local duration = brimstone
            and BRIMSTONE_BEAM_DURATION
            or BEAM_DURATION
        return duration, 1
    end

    if brimstone then
        return BRIMSTONE_BEAM_DURATION, BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER
            / BRIMSTONE_BEAM_TICK_COUNT
    end

    local expectedTicks = math.floor((BEAM_DURATION - 1) / 2)
    return BEAM_DURATION, BEAM_TOTAL_DAMAGE_MULTIPLIER / expectedTicks
end

local function getBeamEndFrames(brimstone)
    return brimstone
        and BRIMSTONE_BEAM_END_FRAMES
        or TECHNOLOGY_BEAM_END_FRAMES
end

-- Weapon-specific fire-rate profiles live here.  A profile first removes the
-- relevant native WeaponType Tears multiplier, then applies Mizuki's intended
-- final multiplier.  Keep the default neutral until a real synergy is added.
local function getMizukiFireRateProfile(player)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        -- Brimstone charges at the unmodified rate: the item is meant to drop
        -- Mizuki's own 1/3 fire-rate correction entirely. Nothing native has to
        -- be divided out for the item itself (its items.xml entry carries no
        -- tears value and the character has no native weapon), but Monstro's
        -- Lung's own x4.3 penalty still has to come out when both are held -
        -- Brimstone keeps its charge rate and only adds the radial beams.
        return {
            Id = "brimstone",
            VanillaTearsMultiplier = player:HasCollectible(
                CollectibleType.COLLECTIBLE_MONSTROS_LUNG
            ) and 1 / 4.3 or 1,
            TearsModifier = 0,
            MizukiTearsMultiplier = 1,
        }
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG) then
        -- Brimstone has priority over Monstro's Lung: it keeps Brimstone's
        -- charge rate and only adds the radial beams. Remove the native Lung
        -- weapon's x4.3 tear-delay penalty before applying Mizuki's rate.
        return {
            Id = "monstros_lung",
            VanillaTearsMultiplier = 1 / 4.3,
            TearsModifier = TEARS_MODIFIER,
            MizukiTearsMultiplier = TEARS_MULTIPLIER,
        }
    end
    return {
        Id = "default",
        VanillaTearsMultiplier = 1,
        TearsModifier = TEARS_MODIFIER,
        MizukiTearsMultiplier = TEARS_MULTIPLIER,
    }
end

local function cannonBelongsToPlayer(cannon, player)
    if not cannon then
        return false
    end
    local owner = cannon.Player
    if not owner and cannon.Parent then
        owner = cannon.Parent:ToPlayer()
    end
    if not owner and cannon.SpawnerEntity then
        owner = cannon.SpawnerEntity:ToPlayer()
    end
    return owner and GetPtrHash(owner) == GetPtrHash(player)
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
    local expectedPerSide = 1 + player:GetEffects():GetCollectibleEffectNum(BOX_OF_FRIENDS)
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
                cannon:Remove()
            end
        end
    end

    data.MizukiCannons = retained
end

local tryFireImmaculateHeartTear
local advanceLeadPencil

local function getLeftEyeFlatDamageBonus(player)
    local bonus = 0
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BLOOD_CLOT) then
        bonus = bonus + 1
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_CHEMICAL_PEEL) then
        bonus = bonus + 2
    end
    return bonus
end

local function getEyeDamageMultiplier(player, leftEye)
    if leftEye then
        return player:HasCollectible(CollectibleType.COLLECTIBLE_PEEPER)
            and 1.35 or 1
    end
    return player:HasCollectible(CollectibleType.COLLECTIBLE_STYE)
        and 1.28 or 1
end

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
                if beam.Ending then
                    if not laser or not laser:Exists() then
                        table.remove(beams, index)
                    else
                        Mizuki.RefreshMizukiBeamAttackParams(
                            player,
                            data,
                            beam,
                            laser,
                            shootingDirection
                        )
                    end
                elseif beam.Automatic and automaticMode and shootingHeld then
                    -- Refresh only the full-width portion. The variant's native
                    -- 3 / 10-frame ending is reserved outside this countdown.
                    local activeDuration = beam.ActiveDuration
                        or math.max(
                            1,
                            (beam.TotalDuration or BEAM_DURATION)
                                - (beam.EndFrames
                                    or TECHNOLOGY_BEAM_END_FRAMES)
                        )
                    beam.Timeout = activeDuration
                    if laser and laser:Exists() then
                        laser.Timeout = activeDuration
                        local desiredDirection = shootingDirection
                            and shootingDirection:Rotated(beam.DirectionOffset or 0)
                            or nil
                        if desiredDirection
                            and (desiredDirection - beam.Direction):LengthSquared() > 0.0001
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
                activeSides = activeSides + 1
                cannonFiringSides = cannonFiringSides + 1
            end
        end
    end
    return activeSides, cannonFiringSides
end

local function getCannonSpriteTransform(cannonAim, positionAim, idleRotation)
    local baseRotation = cannonAim:GetAngleDegrees() + 90
    local spriteRotation = baseRotation + idleRotation
    local positionBaseRotation = positionAim:GetAngleDegrees() + 90
    local spriteOffset = CANNON_IDLE_ROTATION_PIVOT:Rotated(positionBaseRotation)
        - CANNON_IDLE_ROTATION_PIVOT:Rotated(spriteRotation)
    return spriteRotation, spriteOffset
end

local function updateCannonPositions(player, data)
    prunePlayerCannons(data)
    local targetPositions = { {}, {} }
    local aim = data.MizukiCannonAim
    local isHorizontal = aim and math.abs(aim.X) > math.abs(aim.Y)

    local normalizedAim = aim and aim:Normalized() or Vector(0, -1)
    local positionAim
    if isHorizontal then
        positionAim = Vector(normalizedAim.X > 0 and 1 or -1, 0)
    else
        positionAim = Vector(0, normalizedAim.Y > 0 and 1 or -1)
    end
    local sideHorizontalStates = {}
    local sideEyeDirections = {}
    local sideFiringStates = {}
    local sideFollowingStates = {}
    local sideFiniteFollowStates = {}
    local anyCannonFiring = false

    -- Resolve each side's beam state once. Position layout, firing pose and
    -- laser synchronization all consume the same result below.
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams
            and data.MizukiActiveBeams[side]
        local isFiring = beams and #beams > 0 or false
        local isFollowing = false
        local hasFiniteFollower = false
        if beams then
            for _, beam in ipairs(beams) do
                if beam.FollowCannon then
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

    for side = 1, 2 do
        -- A finite Anti-Gravity beam keeps only its own side's positional
        -- firing direction. The other side remains free to move to the layout
        -- requested by a new charge, so the pair need not share one axis.
        local sidePositionAim = positionAim
        if sideFiniteFollowStates[side] then
            local lockedState = data.MizukiLockedCannonAims
                and data.MizukiLockedCannonAims[side]
            if lockedState and lockedState.PositionAim then
                sidePositionAim = lockedState.PositionAim
            end
        end
        local sideIsHorizontal = math.abs(sidePositionAim.X)
            > math.abs(sidePositionAim.Y)
        local sidePositionCharacterLeft = sidePositionAim:Rotated(-90)
        local positionEyeDirection = side == 1
            and sidePositionCharacterLeft
            or -sidePositionCharacterLeft
        sideHorizontalStates[side] = sideIsHorizontal
        sideEyeDirections[side] = positionEyeDirection
        for member = 1, #data.MizukiCannons[side] do
            local groupDistance = (member - 1) * CANNON_GROUP_SPACING
            if sideIsHorizontal then
                local horizontalOffset = sidePositionAim * HORIZONTAL_CANNON_X
                    + Vector(0, HORIZONTAL_CANNON_CENTER_Y)
                    + positionEyeDirection * (HORIZONTAL_CANNON_HALF_SPACING
                        + groupDistance)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, horizontalOffset)
            else
                local verticalCenterY = sidePositionAim.Y > 0
                    and 0
                    or CANNON_OFFSETS[1].Y
                local restingOffset = Vector(0, verticalCenterY)
                    + positionEyeDirection * (math.abs(CANNON_OFFSETS[1].X)
                        + groupDistance)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, restingOffset)
            end
            -- Layout offset for this side and member: where the cannon belongs
            -- for the current aim, with no follow lag in it. A room transition
            -- re-places the cannons from this. Carrying the cannon's actual
            -- position instead would also carry the lag the door pull builds up
            -- (the player is yanked through the doorway far faster than the
            -- cannon follow speed closes the gap), so the cannon would land out
            -- of place and then visibly coast back.
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

    data.MizukiCannonPositions = { {}, {} }
    local frame = Game():GetFrameCount()
    for side = 1, 2 do
        local eyeDirection = sideEyeDirections[side]
        local sideIsHorizontal = sideHorizontalStates[side]
        for member, targetPosition in ipairs(targetPositions[side]) do
            local cannon = data.MizukiCannons[side][member]
            local sideBeams = data.MizukiActiveBeams
                and data.MizukiActiveBeams[side]
            local isFiring = sideFiringStates[side]
            local isFollowingFiring = sideFollowingStates[side]
            local isIdle = not data.MizukiHasShootingInput
                and (data.MizukiCharge or 0) <= 0
                and not anyCannonFiring
            local bobOffset = Vector(0, math.sin(frame * 0.16) * CANNON_FLOAT_AMPLITUDE)
            local idleHeightOffset = isIdle and CANNON_IDLE_OFFSETS or Vector.Zero
            if isFiring and not isFollowingFiring then
                -- targetPosition is the exact world position captured on the
                -- firing frame and already includes that frame's bob offset.
                cannon.Position = targetPosition
            else
                local floatingTarget = targetPosition + bobOffset + idleHeightOffset
                cannon.Position = cannon.Position + (floatingTarget - cannon.Position) * CANNON_FOLLOW_SPEED
            end
            cannon.Velocity = Vector.Zero
            if isIdle then
                cannon.DepthOffset = IDLE_CANNON_DEPTH_OFFSET
            elseif isFiring and not isFollowingFiring then
                -- Keep the firing group decisively above the native laser;
                -- depth zero can alternate around Technology's moving render
                -- position as the beam animates.
                cannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
            elseif sideIsHorizontal then
                cannon.DepthOffset = eyeDirection.Y > 0
                    and HORIZONTAL_FRONT_DEPTH_OFFSET
                    or HORIZONTAL_BACK_DEPTH_OFFSET
            else
                cannon.DepthOffset = CANNON_DEPTH_OFFSET
            end
            local lockedCannonState = data.MizukiLockedCannonAims[side]
            local lockedPositionAim = lockedCannonState
                and lockedCannonState.PositionAim
            local lockedCannonAim = lockedCannonState
                and lockedCannonState.MemberAims[member]
            local cannonAim = lockedCannonAim
                or data.MizukiCannonAim or Vector(0, -1)
            local cannonData = cannon:GetData()
            cannonData.CannonSide = side
            -- Read by Mizuki:RenderCannon to pick the resting or firing
            -- reflection distance and mirroring.
            cannonData.MizukiIsIdle = isIdle
            -- Ease toward the distance the current state asks for, so the
            -- reflection travels with the pose instead of snapping.
            local targetSpan = (isIdle and CANNON_IDLE_REFLECTION_SPAN
                or CANNON_FIRING_REFLECTION_SPAN) * player.SpriteScale.Y
            local smoothSpan = cannonData.MizukiReflectionSpan
            if smoothSpan == nil then
                cannonData.MizukiReflectionSpan = targetSpan
            else
                smoothSpan = smoothSpan
                    + (targetSpan - smoothSpan) * CANNON_REFLECTION_SPAN_SPEED
                if math.abs(smoothSpan - targetSpan) < 0.5 then
                    smoothSpan = targetSpan
                end
                cannonData.MizukiReflectionSpan = smoothSpan
            end
            local sideIdleRotation = side == 1
                and LEFT_CANNON_IDLE_ROTATION
                or RIGHT_CANNON_IDLE_ROTATION
            local idleRotationTarget = isIdle and sideIdleRotation
                or 0
            if cannonData.MizukiIdleRotationOffset == nil then
                cannonData.MizukiIdleRotationOffset = idleRotationTarget
            else
                cannonData.MizukiIdleRotationOffset = cannonData.MizukiIdleRotationOffset
                    + (idleRotationTarget - cannonData.MizukiIdleRotationOffset)
                    * CANNON_ROTATION_RETURN_SPEED
                if math.abs(cannonData.MizukiIdleRotationOffset - idleRotationTarget) < 0.1 then
                    cannonData.MizukiIdleRotationOffset = idleRotationTarget
                end
            end
            -- Use the same (possibly locked) aim for both sprite rotation and
            -- bottom-pivot compensation. During a finite beam the player's
            -- live input may already point elsewhere; mixing that live
            -- cardinal direction with the locked firing rotation shifts the
            -- sprite around the wrong pivot.
            local idleRotation = cannonData.MizukiIdleRotationOffset
            local sprite = cannon:GetSprite()
            local target = getMizukiTargetReticle(player, data)
            local spritePositionAim = lockedPositionAim or positionAim
            if target and not lockedCannonAim then
                for _ = 1, 2 do
                    local _, trialOffset = getCannonSpriteTransform(
                        cannonAim,
                        spritePositionAim,
                        idleRotation
                    )
                    cannonAim = resolveBeamGeometry(
                        cannon.Position + trialOffset,
                        cannonAim,
                        0,
                        target.Position
                    )
                end
            end
            sprite.Rotation, sprite.Offset = getCannonSpriteTransform(
                cannonAim,
                spritePositionAim,
                idleRotation
            )
            -- Hide the engine's own draw; Mizuki:RenderCannon replaces it in
            -- the same render slot, with an explicit mirror in the water
            -- reflection pass. Alpha is used instead of Visible on purpose:
            -- an invisible entity stops being rendered, which would also stop
            -- the render callback that re-draws it.
            sprite.Color = getCannonHiddenColor()
            cannonData.MizukiCannonAim = cannonAim
            data.MizukiCannonPositions[side][member] = Vector(cannon.Position.X, cannon.Position.Y)

            -- The cannon position, rotation and render offset are final here.
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
                        local visualOrigin = cannon.Position + sprite.Offset
                        -- Finite Anti-Gravity shots follow only the cannon's
                        -- position. Keep their fired direction and distance;
                        -- live reticle tracking remains an automatic-beam rule.
                        local target = beam.Automatic
                            and getMizukiTargetReticle(player, data)
                            or nil
                        local directionOffset = beam.DirectionOffset or 0
                        local baseDirection = beam.Direction:Rotated(
                            -directionOffset
                        )
                        local originCorrection
                        beam.Direction, originCorrection = resolveBeamGeometry(
                            visualOrigin,
                            baseDirection,
                            directionOffset,
                            target and target.Position or nil
                        )
                        local horizontal = math.abs(beam.Direction.X)
                            > math.abs(beam.Direction.Y)
                        local hitboxOffset = horizontal
                            and Vector(0, HORIZONTAL_BEAM_HITBOX_Y_OFFSET)
                            or Vector.Zero
                        laser.AngleDegrees = beam.Direction:GetAngleDegrees()
                        laser.Position = cannon.Position
                            + sprite.Offset
                            + hitboxOffset
                            + originCorrection
                        laser.PositionOffset = -hitboxOffset
                        laser.Velocity = Vector.Zero
                        laser.DepthOffset = cannon.DepthOffset - 5
                            - hitboxOffset.Y
                            - originCorrection.Y
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


local function getMizukiBeamAngleOffsets(player)
    local innerEyeCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_INNER_EYE
    )
    local mutantSpiderCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MUTANT_SPIDER
    )
    local glassesCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_20_20
    )
    local wizCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_THE_WIZ
    )

    if player:HasPlayerForm(PlayerForm.PLAYERFORM_BOOK_WORM)
        and player:GetDropRNG():RandomFloat() < 0.25
    then
        glassesCount = glassesCount + 1
    end

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

    local angles = {}
    local wizGroups = math.min(wizCount + 1, MAX_STANDARD_MULTISHOT)
    local beamsPerWizGroup = standardCount
    beamsPerWizGroup = math.max(
        1,
        math.min(
            beamsPerWizGroup,
            math.floor(MAX_STANDARD_MULTISHOT / wizGroups)
        )
    )
    for group = 1, wizGroups do
        local center = 0
        if wizGroups > 1 then
            center = -WIZ_ARC_HALF_ANGLE
                + (group - 1) * (WIZ_ARC_HALF_ANGLE * 2) / (wizGroups - 1)
        end
        Mizuki.appendCenteredBeamAngles(angles, center, beamsPerWizGroup, totalSpread)
    end

    if player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY) then
        table.insert(angles, -CONJOINED_SIDE_ANGLE)
        table.insert(angles, CONJOINED_SIDE_ANGLE)
    end

    local momsEye = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYE)
    local lokisHorns = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LOKIS_HORNS
    )
    local shootBackwards = false
    local shootSideways = false
    if momsEye then
        local chance = math.max(0, math.min(1, 0.5 + player.Luck * 0.1))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MOMS_EYE
        ):RandomFloat() < chance then
            shootBackwards = true
            shootSideways = lokisHorns
        end
    end
    if lokisHorns then
        local chance = math.max(0, math.min(1, 0.25 + player.Luck * 0.05))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_LOKIS_HORNS
        ):RandomFloat() < chance then
            shootBackwards = true
            shootSideways = true
        end
    end
    if shootBackwards then
        table.insert(angles, 180)
    end
    if shootSideways then
        table.insert(angles, -90)
        table.insert(angles, 90)
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_SORE) then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_EYE_SORE
        )
        for _ = 1, rng:RandomInt(4) do
            table.insert(angles, rng:RandomFloat() * 360)
        end
    end

    local lungCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG
    )
    if lungCount > 0 then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MONSTROS_LUNG
        )
        local minExtra = 3 + 2 * (lungCount - 1)
        local maxExtra = 5 + 3 * (lungCount - 1)
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

        if widthScale < 2.5
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
        thickerData.MizukiRecoverChargeMultiplier = damageMultiplier
        -- ShootAngle does not enroll this replacement in the player weapon's
        -- native water-reflection draw. Its owning cannon supplies that one
        -- missing render pass; this marker must not be set on ordinary lasers,
        -- whose reflections are already drawn by the engine.
        thickerData.MizukiManualWaterReflection = true

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
    damageMultiplierOverride
)
    local data = player:GetData()
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
    if automatic then
        firingSides = { 1, 2 }
    elseif forcedSide then
        firingSides = { forcedSide }
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
    local beamDuration, damagePerTickMultiplier =
        getBeamDamageTiming(
            player,
            automatic,
            isBrimstoneBeam
        )
    local beamEndFrames = getBeamEndFrames(isBrimstoneBeam)
    local beamActiveDuration = math.max(1, beamDuration - beamEndFrames)
    -- Ordinary shots reach 1x damage at BaseFrames. Chocolate Milk can extend
    -- the same charge beyond that point instead of merely storing extra time.
    local chargeDamageMultiplier = getChargeDamageMultiplier(
        charge,
        chargeProfile
    )
    -- Calculate the complete charged-shot damage first. The per-tick factor
    -- is applied only when assigning CollisionDamage, so native tear params,
    -- laser size and firing sound all see the same charged attack.
    local damageMultiplier = damageMultiplierOverride
        or chargeDamageMultiplier
    local beamAngleOffsets = getMizukiBeamAngleOffsets(player)
    tryFireImmaculateHeartTear(player, direction)
    advanceLeadPencil(player, direction)
    data.MizukiExtraAttackFrame = Game():GetFrameCount()
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
                local lockedPositionAim
                if math.abs(direction.X) > math.abs(direction.Y) then
                    lockedPositionAim = Vector(direction.X > 0 and 1 or -1, 0)
                else
                    lockedPositionAim = Vector(0, direction.Y > 0 and 1 or -1)
                end
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

                if isFiniteShot then
                    if not followCannon then
                        data.MizukiLockedCannonPositions[side][member] = Vector(
                            origin.X,
                            origin.Y
                        )
                    end
                    local firingAim = firingCannon
                        and firingCannon:GetData().MizukiCannonAim
                        or direction
                    data.MizukiLockedCannonAims[side].MemberAims[member] = Vector(
                        firingAim.X,
                        firingAim.Y
                    )
                end

                local visualOrigin = origin
                if hasFiringCannon then
                    visualOrigin = firingCannon.Position
                        + firingCannon:GetSprite().Offset
                    if isFiniteShot then
                        firingCannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
                    end
                end

                for _, angleOffset in ipairs(beamAngleOffsets) do
                    local target = getMizukiTargetReticle(player, data)
                    local beamDirection, originCorrection = resolveBeamGeometry(
                        visualOrigin,
                        direction,
                        angleOffset,
                        target and target.Position or nil
                    )
                    local isHorizontalShot = math.abs(beamDirection.X)
                        > math.abs(beamDirection.Y)
                    local hitboxOffset = isHorizontalShot
                        and Vector(0, HORIZONTAL_BEAM_HITBOX_Y_OFFSET)
                        or Vector.Zero
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
                        damageMultiplier,
                        beamWidthScale
                    )
                    local leftEyeBonus = getLeftEyeFlatDamageBonus(player)
                    -- Keep the player as SpawnerEntity so native per-tick laser
                    -- effects (Fruit Cake, Playdough Cookie and future item
                    -- synergies) continue refreshing. Cannon ownership is kept
                    -- exclusively in the managed beam record below.
                    laser.DisableFollowParent = true
                    if followCannon and firingCannon then
                        laser.Parent = firingCannon
                    end
                    laser.Position = hitboxOrigin
                    laser.PositionOffset = -hitboxOffset
                    laser.Velocity = Vector.Zero
                    laser.DepthOffset = (firingCannon
                        and firingCannon.DepthOffset
                        or CANNON_DEPTH_OFFSET) - 5
                        - hitboxOffset.Y
                        - originCorrection.Y
                    laser.Timeout = beamActiveDuration
                    laser:SetOneHit(false)
                    laser:SetMaxDistance(currentBeamDistance)
                    local laserData = laser:GetData()
                    -- The thick replacement copied an already-scaled first-frame
                    -- value from FireBrimstone, so use it directly. Only after
                    -- the engine supplies a different native value do we begin
                    -- restoring the multiplier saved on the replacement entity.
                    local nativeDamage = laser.CollisionDamage
                    local eyeDamage = nativeDamage
                        + (side == 1 and leftEyeBonus or 0)
                    eyeDamage = eyeDamage
                        * getEyeDamageMultiplier(player, side == 1)
                    local collisionDamage = eyeDamage
                        * damagePerTickMultiplier
                    laser.CollisionDamage = collisionDamage
                    laser.TearFlags = addOccultHoming(player, laser.TearFlags)
                        & ~MIZUKI_FORBIDDEN_TEAR_FLAGS

                    laserData.MizukiBeam = true
                    laserData.MizukiBeamOwner = player
                    laserData.MizukiBeamWidthScale = beamWidthScale
                    laserData.MizukiBeamAutomatic = automatic
                    laserData.MizukiBeamLeftEye = side == 1
                    laserData.MizukiBeamDamagePerTickMultiplier =
                        damagePerTickMultiplier
                    if laserData.MizukiRecoverChargeMultiplier then
                        laserData.MizukiAwaitingNativeDamageRefresh = true
                    else
                        laserData.MizukiLastNativeCollisionDamage = nativeDamage
                    end
                    laserData.MizukiLastAdjustedCollisionDamage = collisionDamage

                    table.insert(data.MizukiActiveBeams[side], {
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
                        FiniteVolleyId = finiteVolleyId,
                    })
                end
            end
        end
    end
    return finiteVolleyId
end

local function startCursedEyeBurst(player, data, direction, charge, profile)
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
        nil,
        nil,
        burstDamageMultiplier
    )
    if shotCount > 1 then
        local firingSide = data.MizukiShotSide == -1 and 1 or 2
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
    Mizuki.updateEpicFetusStrike(player, data)

    if data.MizukiRefreshCannonCache then
        data.MizukiRefreshCannonCache = nil
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    local kidneyStoneBurst = Mizuki.updateKidneyStoneBurst(player, data)
    local automatic = usesAutomaticBeam(player)
    local chargeProfile = getChargeProfile(player)
    local shootingInput = player:GetShootingInput()
    local shootingDirection = shootingInput:Length() > 0.01
        and shootingInput:Normalized()
        or nil
    data.MizukiHasShootingInput, shootingDirection =
        getShootingIntent(player, data)
    local targetAiming = getMizukiTargetReticle(player, data) ~= nil
    if kidneyStoneBurst and kidneyStoneBurst.Direction then
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
    Mizuki.updateIsaacsTearsCharge(player, data)
    if data.MizukiCursedEyeBurst then
        data.MizukiCannonAim = data.MizukiCursedEyeBurst.Direction
    elseif data.MizukiHasShootingInput then
        data.MizukiCannonAim = shootingDirection
    end
    updateCannonPositions(player, data)
    -- Cursed Eye releases one independently rolled attack per frame. Ignore
    -- input until the stored burst has completely left the cannons.
    if updateCursedEyeBurst(player, data) then
        data.MizukiCharge = 0
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if automatic and activeSides >= 2 then
        data.MizukiCharge = 0
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if data.MizukiHasShootingInput then
        data.MizukiAim = shootingDirection
        data.MizukiCannonAim = data.MizukiAim
        data.MizukiCharge = math.min(
            (data.MizukiCharge or 0) + 1,
            chargeProfile.MaxFrames
        )
        -- A finite beam still occupies its cannon until that attack ends.
        -- Anti-Gravity changes only whether its position follows the player.
        if cannonFiringSides == 0
            and (automatic or targetAiming)
            and data.MizukiCharge >= chargeProfile.MaxFrames
        then
            fireMizukiBeam(
                player,
                data.MizukiAim,
                data.MizukiCharge,
                automatic
            )
            data.MizukiCharge = 0
            data.MizukiChargeBarFullFrames = nil
            return
        end

        if not automatic and data.MizukiCharge >= chargeProfile.MaxFrames then
            data.MizukiChargeBarFullFrames = (data.MizukiChargeBarFullFrames or 0) + 1
        else
            data.MizukiChargeBarFullFrames = nil
        end
        -- The shot is loosed on release, so holding the button stops here.
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
    end

    data.MizukiCharge = 0
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
    if data.MizukiEpicFetusStrike
        or (data.MizukiEpicFetusCooldown or 0) > 0
        or not hasActiveMizukiBeam(data) then
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

    -- The engine has now refreshed the player-owned laser for this logical
    -- frame. Keep its native random flags/color and damage roll intact, then
    -- layer only Mizuki's eye-specific rules on top. If a laser variant does
    -- not rewrite CollisionDamage on a particular frame, reuse the cached raw
    -- value so the eye multipliers cannot compound.
    local player = laserData.MizukiBeamOwner
    if player and player:Exists() then
        laser.TearFlags = addOccultHoming(player, laser.TearFlags)
            & ~MIZUKI_FORBIDDEN_TEAR_FLAGS

        local nativeDamage = laser.CollisionDamage
        local lastAdjusted = laserData.MizukiLastAdjustedCollisionDamage
        local shouldAdjustDamage = true
        if laserData.MizukiAwaitingNativeDamageRefresh then
            if lastAdjusted
                and math.abs(nativeDamage - lastAdjusted) < 0.0001
            then
                -- Still the copied, already-scaled creation value. Leave it
                -- alone until ShootAngle's entity receives its first native
                -- runtime damage refresh.
                shouldAdjustDamage = false
            else
                laserData.MizukiAwaitingNativeDamageRefresh = nil
            end
        elseif lastAdjusted
            and math.abs(nativeDamage - lastAdjusted) < 0.0001
            and laserData.MizukiLastNativeCollisionDamage
        then
            nativeDamage = laserData.MizukiLastNativeCollisionDamage
        end
        if shouldAdjustDamage then
            local chargeRecovery =
                laserData.MizukiRecoverChargeMultiplier or 1
            local chargedDamage = nativeDamage * chargeRecovery
            local eyeDamage = chargedDamage
                + (laserData.MizukiBeamLeftEye
                    and getLeftEyeFlatDamageBonus(player) or 0)
            eyeDamage = eyeDamage * getEyeDamageMultiplier(
                player,
                laserData.MizukiBeamLeftEye and true or false
            )
            local adjustedDamage = eyeDamage
                * (laserData.MizukiBeamDamagePerTickMultiplier or 1)
            laserData.MizukiLastNativeCollisionDamage = nativeDamage
            laserData.MizukiLastAdjustedCollisionDamage = adjustedDamage
            laser.CollisionDamage = adjustedDamage
        end
    end

    -- Let EntityLaser own the native narrowing animation after the weapon has
    -- released it. Damage and native item refresh continue, but do not restore
    -- the maintained width over the native fade/shrink.
    if laserData.MizukiBeamEnding then
        return
    end

    if laser.FrameCount < 2 then
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

function Mizuki:FinalizeEpicFetusGridTargets()
    local frame = Game():GetFrameCount()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local data = player:GetData()
            local candidate = data.MizukiEpicFetusGridCandidate
            if candidate and candidate.Frame <= frame then
                data.MizukiEpicFetusGridCandidate = nil
                if not data.MizukiEpicFetusStrike
                    and (data.MizukiEpicFetusCooldown or 0) <= 0
                    and player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
                    and hasActiveMizukiBeam(data)
                then
                    Mizuki.startEpicFetusStrike(player, nil, candidate.Position)
                end
            end
        end
    end
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_UPDATE,
    Mizuki.FinalizeEpicFetusGridTargets
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
        player.TearColor = player.TearColor * MIZUKI_TEAR_COLOR
        player.LaserColor = player.LaserColor * MIZUKI_TEAR_COLOR
    end

    if isMizuki(player) then
        local capsuleDelta = getCapsuleState(player).RewindStatDelta
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            player.Damage = player.Damage * DAMAGE_MULTIPLIER
            if capsuleDelta then
                player.Damage = player.Damage + capsuleDelta.Damage
            end
        elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
            local profile = getMizukiFireRateProfile(player)
            local currentTears = 30 / (player.MaxFireDelay + 1)
            local preWeaponTears = currentTears / profile.VanillaTearsMultiplier
            local finalTears = (preWeaponTears + profile.TearsModifier) * profile.MizukiTearsMultiplier
            if capsuleDelta then
                finalTears = finalTears + capsuleDelta.Tears
            end
            player.MaxFireDelay = math.max(0, 30 / finalTears - 1)
        elseif cacheFlag == CacheFlag.CACHE_SPEED then
            player.MoveSpeed = player.MoveSpeed + MOVE_SPEED_MODIFIER
            if capsuleDelta then
                player.MoveSpeed = player.MoveSpeed + capsuleDelta.MoveSpeed
            end
        elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED and capsuleDelta then
            player.ShotSpeed = player.ShotSpeed + capsuleDelta.ShotSpeed
        elseif cacheFlag == CacheFlag.CACHE_RANGE and capsuleDelta then
            player.TearRange = player.TearRange + capsuleDelta.TearRange
        elseif cacheFlag == CacheFlag.CACHE_LUCK then
            player.Luck = player.Luck + LUCK_MODIFIER
            if capsuleDelta then
                player.Luck = player.Luck + capsuleDelta.Luck
            end
        elseif cacheFlag == CacheFlag.CACHE_FAMILIARS then
            local copies = player:GetEffects():GetCollectibleEffectNum(BOX_OF_FRIENDS)
            local cannonsPerSide = 1 + copies
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
    cannon.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    cannon.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    cannon.DepthOffset = CANNON_DEPTH_OFFSET
    cannon:GetSprite().Color = getCannonHiddenColor()
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitCannonFamiliar, Mizuki.CannonVariant)

-- Keep cannon body scaling in one Familiar-owned update path so no other
-- callback can accidentally overwrite the final render scale.
function Mizuki:UpdateCannonScale(cannon)
    ensureCannonRegistered(cannon)
    -- The cannons are never meant to hide. A Lua reload does not reset entity
    -- state, so a stale `Visible = false` (e.g. left behind by a reflection
    -- experiment) would otherwise keep the cannon invisible until the entity
    -- itself is recreated. Clear it here every update.
    cannon.Visible = true
    local cannonData = cannon:GetData()
    local aim = cannonData.MizukiCannonAim or Vector(0, -1)
    local isHorizontal = math.abs(aim.X) > math.abs(aim.Y)
    local useLeftGraphics
    if isHorizontal then
        useLeftGraphics = aim.X < 0
    else
        useLeftGraphics = cannon.SubType == 1
    end
    local graphicsMode = useLeftGraphics and "left" or "normal"
    if cannonData.MizukiCannonGraphicsMode ~= graphicsMode then
        local sprite = cannon:GetSprite()
        sprite:ReplaceSpritesheet(
            0,
            useLeftGraphics and LEFT_CANNON_SPRITESHEET or CANNON_SPRITESHEET
        )
        sprite:ReplaceSpritesheet(
            1,
            useLeftGraphics
                and LEFT_CANNON_LIGHT_SPRITESHEET
                or CANNON_LIGHT_SPRITESHEET
        )
        sprite:LoadGraphics()
        cannonData.MizukiCannonGraphicsMode = graphicsMode
    end
    cannon.SpriteScale = CANNON_SCALES[cannon.SubType] or Vector(1, 1)

end

Mizuki:AddCallback(
    ModCallbacks.MC_FAMILIAR_UPDATE,
    Mizuki.UpdateCannonScale,
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
            data.MizukiCursedEyeBurst = nil

            claimPlayerCannons(player, data)

            for side = 1, 2 do
                for member, cannon in ipairs(data.MizukiCannons[side]) do
                    if cannon:Exists() then
                        local cannonData = cannon:GetData()
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
                        cannon.Position = player.Position
                            + (carriedOffset
                                or scalePlayerOffset(player, restingOffset))
                        cannon.Velocity = Vector.Zero
                        local aim = data.MizukiCannonAim or Vector(0, -1)
                        cannonData.MizukiCannonAim = aim
                        -- The idle tilt is a smoothed value: leave it as it is so
                        -- it keeps easing, instead of snapping to the resting
                        -- angle on arrival.
                        local idleRotation = cannonData.MizukiIdleRotationOffset
                            or (side == 1 and LEFT_CANNON_IDLE_ROTATION
                                or RIGHT_CANNON_IDLE_ROTATION)
                        local baseRotation = aim:GetAngleDegrees() + 90
                        local sprite = cannon:GetSprite()
                        sprite.Rotation = baseRotation + idleRotation
                        local pivotCorrection = CANNON_IDLE_ROTATION_PIVOT
                            - CANNON_IDLE_ROTATION_PIVOT:Rotated(idleRotation)
                        sprite.Offset = pivotCorrection:Rotated(baseRotation)
                    end
                end
            end
        end
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ResetCannonsForNewRoom)

-- Re-draw the cannon that the engine was told to draw fully transparent (see
-- updateCannonPositions). Every pass except the water reflection pass draws the
-- body exactly where the entity is; the reflection pass draws a vertically
-- mirrored copy instead, mirrored about the same line the engine mirrors the
-- player about, so the cannons reflect under the player rather than on top of
-- themselves.
--
-- A true vertical mirror of a rotated sprite is that sprite flipped in screen
-- space about its anchor, which is what Sprite.FlipY does after rotation, with
-- the screen-space offset mirrored to match. Negating the rotation as well
-- would add a 2 * angle error: invisible when the cannon points straight up or
-- down (rotation 0 / 180), but turning the reflection into a point-symmetric
-- copy when it points sideways.
local function getCannonRenderPosition(renderOffset, worldPosition)
    local room = Game():GetRoom()
    return Isaac.WorldToScreen(worldPosition) + renderOffset
        - room:GetRenderScrollOffset() - Game().ScreenShakeOffset
end

function Mizuki:RenderCannon(cannon, renderOffset)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local sprite = cannon:GetSprite()
    local originalColor = sprite.Color
    local originalFlipY = sprite.FlipY
    local originalScale = Vector(sprite.Scale.X, sprite.Scale.Y)

    local worldPosition = cannon.Position
    local isWaterReflection = Game():GetRoom():GetRenderMode()
        == RenderMode.RENDER_WATER_REFLECT
    if isWaterReflection then
        -- The span is anchored to the cannon itself rather than to the live
        -- player position, so the reflection stays rigidly attached to the
        -- cannon: a locked finite shot freezes body and reflection together,
        -- and the follow lag of a continuous beam applies to both instead of
        -- being recomputed (and doubled) on the reflection.
        local cannonData = cannon:GetData()
        local isIdle = cannonData.MizukiIsIdle
        -- updateCannonPositions eases this toward the distance the current
        -- state asks for; the direct value is only a first-frame fallback.
        local span = cannonData.MizukiReflectionSpan
        if span == nil then
            span = (isIdle and CANNON_IDLE_REFLECTION_SPAN
                or CANNON_FIRING_REFLECTION_SPAN) * player.SpriteScale.Y
        end
        worldPosition = Vector(
            cannon.Position.X,
            cannon.Position.Y + span
        )
        -- At rest the cannons sit above the player's head and mirror like a true
        -- reflection, so the engine's flip is kept as is.
        --
        -- While firing the pair is laid out as a trapezoid around the aim line,
        -- and sideways aims keep that same mirror. Aiming up or down is a
        -- deliberate exception there: the reflection should read as a plain
        -- translation of the cannon, so the flip is cancelled for those aims.
        --
        -- The engine mirrors the entity internally for this pass instead of
        -- through the sprite's FlipY, which arrives false in both passes.
        -- Setting FlipY therefore adds a second flip that cancels the engine's
        -- mirror, so negating it is what turns the reflection into a plain
        -- translation; leaving it alone keeps the mirror.
        if not isIdle then
            local aim = cannonData.MizukiCannonAim or Vector(0, -1)
            if math.abs(aim.X) <= math.abs(aim.Y) then
                sprite.FlipY = not sprite.FlipY
            end
        end
        -- Nothing else is mirrored: the reflection is the body's whole draw
        -- mirrored, so the sprite keeps its rotation, scale and offset and only
        -- the position moves. That offset is applied inside the sprite's own
        -- rotated frame, so mirroring it here - which is a screen-space
        -- operation - would shift the reflection sideways by twice its Y
        -- component, most visibly on the strongly tilted resting cannon.
    end

    -- Sprite:Render is a Sprite method, so it cannot know about the entity's
    -- SpriteScale. The cannon's render scale lives on the entity, so apply it
    -- here or the cannon is drawn 1 / 0.65 too large.
    sprite.Scale = Vector(cannon.SpriteScale.X, cannon.SpriteScale.Y)
    -- Force the sprite visible for this draw while keeping whatever colour it
    -- arrived with, so a tint applied elsewhere is not thrown away.
    sprite.Color = Color(
        originalColor.R, originalColor.G, originalColor.B,
        1, originalColor.RO, originalColor.GO, originalColor.BO
    )
    if isWaterReflection then
        -- Render the marked replacement through EntityLaser itself so all of
        -- its body, impact and ending layers use the current animation frame.
        -- The callback runs once for the owning cannon, so this adds one visual
        -- pass without creating another entity or another damage source.
        local side = cannon:GetData().CannonSide
        local beams = side
            and player:GetData().MizukiActiveBeams
            and player:GetData().MizukiActiveBeams[side]
        if beams then
            for _, beam in ipairs(beams) do
                local laser = beam.Laser
                if beam.Cannon
                    and GetPtrHash(beam.Cannon) == GetPtrHash(cannon)
                    and laser
                    and laser:Exists()
                    and laser:GetData().MizukiManualWaterReflection
                then
                    laser:Render(renderOffset)
                end
            end
        end
    end
    -- The 2nd and 3rd arguments are clamps, not offset and scale.
    sprite:Render(
        getCannonRenderPosition(renderOffset, worldPosition),
        Vector.Zero,
        Vector.Zero
    )

    sprite.Color = originalColor
    sprite.FlipY = originalFlipY
    sprite.Scale = originalScale
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_FAMILIAR_RENDER,
    Mizuki.RenderCannon,
    Mizuki.CannonVariant
)

-- Draw immediately after the selected Familiar. The Familiar survives room
-- changes and this callback receives the same camera offset used for its body.
function Mizuki:RenderChargeBar(cannon, renderOffset)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local data = player:GetData()
    -- The charge bar belongs to the body only. Without this guard the
    -- reflection pass would draw a second, unmirrored bar over the real one.
    if Game():GetRoom():GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then
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
    local frameCount = Game():GetFrameCount()
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
        if fullFrames <= 12 then
            chargeBar:Play("StartCharged", true)
            chargeBar:SetFrame("StartCharged", fullFrames - 1)
        else
            chargeBar:Play("Charged", true)
            chargeBar:SetFrame("Charged", (fullFrames - 13) % 6)
        end
    else
        local frame = math.floor(
            math.min(charge / getChargeProfile(player).MaxFrames, 1) * 100
        )
        chargeBar:Play("Charging", true)
        chargeBar:SetFrame("Charging", frame)
    end

    chargeBar.Color = CHARGE_BAR_COLOR
    chargeBar.Scale = CHARGE_BAR_SCALE
    local room = Game():GetRoom()
    local cannonSprite = cannon:GetSprite()
    local cannonData = cannon:GetData()
    local graphicsOffset = cannonData.MizukiCannonGraphicsMode == "normal"
        and CHARGE_BAR_NORMAL_GRAPHICS_OFFSET:Rotated(cannonSprite.Rotation)
        or Vector.Zero

    local renderPosition = Isaac.WorldToScreen(cannon.Position) + renderOffset
        + cannonSprite.Offset
        + CHARGE_BAR_OFFSET:Rotated(cannonSprite.Rotation)
        + graphicsOffset
        - room:GetRenderScrollOffset() - Game().ScreenShakeOffset
        
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
    ):RandomFloat() >= 0.25 then
        return
    end

    local shotDirection = direction and direction:Normalized() or Vector(0, -1)
    local tear = player:FireTear(
        player.Position,
        shotDirection:Resized(player.ShotSpeed * 10),
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
    if data.MizukiLeadPencilShots < 15 then
        return
    end
    data.MizukiLeadPencilShots = data.MizukiLeadPencilShots - 15

    local shotDirection = direction and direction:Normalized() or Vector(0, -1)
    local rng = player:GetCollectibleRNG(
        CollectibleType.COLLECTIBLE_LEAD_PENCIL
    )
    local hasBloodClot = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BLOOD_CLOT
    )
    for _ = 1, 12 do
        local velocity = shotDirection
            :Rotated(rng:RandomFloat() * 60 - 30)
            :Resized(player.ShotSpeed * 10 * (0.5 + rng:RandomFloat() * 0.75))
        local tear = player:FireTear(
            player.Position,
            velocity,
            true,
            false,
            true,
            player,
            1
        )
        tear.Scale = tear.Scale * (0.75 + rng:RandomFloat() * 0.5)
        tear.Height = -5 - rng:RandomFloat() * 3
        tear.FallingSpeed = -10 - rng:RandomFloat() * 10
        tear.FallingAcceleration = 1 + rng:RandomFloat()
        -- Lead Pencil normally turns half of its ordinary tears into the
        -- highlighted blood-tear sprite. Blood Clot is a separate exception:
        -- tint the complete barrage deep red without replacing special tear
        -- variants (or mixing BLUE and BLOOD base sprites).
        if hasBloodClot then
            tear.Color = LEAD_PENCIL_BLOOD_CLOT_COLOR
        elseif tear.Variant == TearVariant.BLUE and rng:RandomFloat() < 0.5 then
            tear:ChangeVariant(TearVariant.BLOOD)
        end
        tear:GetData().MizukiLeadPencilTear = true
    end
end

-- The feature files in scripts/ are separate chunks (each with its own 200-local
-- budget), so everything they share travels through the Mizuki table; each file
-- aliases what it needs at its own top.
Mizuki.isMizuki = isMizuki
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
Mizuki.HOUR_GLASS = HOUR_GLASS
Mizuki.CAPSULE_STAT_CACHE_FLAGS = CAPSULE_STAT_CACHE_FLAGS
Mizuki.LEAD_PENCIL_BLOOD_CLOT_COLOR = LEAD_PENCIL_BLOOD_CLOT_COLOR
Mizuki.capsuleStates = capsuleStates
Mizuki.cannonReconcileStates = cannonReconcileStates
Mizuki.getCannonReconcileState = getCannonReconcileState
Mizuki.BFFS = BFFS
Mizuki.LUCKY_FOOT = LUCKY_FOOT
Mizuki.MOMS_BOX = MOMS_BOX
Mizuki.SACK_HEAD = SACK_HEAD

-- Order matters only in that the capsule file publishes the pocket helpers the
-- fan file aliases.
include("scripts/kidney_stone")
include("scripts/epic_fetus")
include("scripts/isaacs_tears")
include("scripts/experimental_capsule")
include("scripts/fan")
