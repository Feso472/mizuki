local Mizuki = RegisterMod("Mizuki", 1)

-- Vanilla Repentance+ only. Mizuki's beam uses a native EntityLaser for
-- collision, damage ticks and tear-effect compatibility. Lua still owns its
-- charge cycle and keeps the laser anchored to the firing cannon position.
Mizuki.PlayerType = Isaac.GetPlayerTypeByName("弥月", false)
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
local CURSED_EYE_MAX_CHARGE_MULTIPLIER = 3
local CURSED_EYE_EXTRA_SHOT_INTERVAL_PERCENT = 0.50
local KIDNEY_STONE_TRIGGER_FIRE_RATE_RATIO = 4
local KIDNEY_STONE_MIN_BURST_FRAMES = 150
local KIDNEY_STONE_MAX_BURST_FRAMES = 190
local KIDNEY_STONE_STABLE_FRAMES = 2
local KIDNEY_STONE_FIRE_DELAY_EPSILON = 0.001
local TEARS_MULTIPLIER = 1 / 3
local TEARS_MODIFIER = 0
local DAMAGE_MULTIPLIER = 0.9
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
local BEAM_DAMAGE_INTERVAL = 5
local ALMOND_BEAM_SHAPE_INTERVAL = 1
local MIZUKI_HIT_PARAMS_WEAPON = WeaponType.WEAPON_LASER
-- Anti-Gravity's waiting state can freeze a persistent laser path after the
-- random effect has changed. It needs a dedicated synergy rather than being
-- copied directly onto the continuously reused EntityLaser.
local MIZUKI_CONTINUOUS_FORBIDDEN_TEAR_FLAGS = TearFlags.TEAR_WAIT
-- Effects which create a discrete result rather than a persistent laser
-- property. Each damaging beam may use a rolled effect for one laser update
-- per five-frame cadence; the left and right beams consume their copies
-- independently. The visual-only beam must never receive any of these flags.
local MIZUKI_SINGLE_TICK_TEAR_FLAG_LIST = {
    { Flag = TearFlags.TEAR_SPLIT, Name = "分裂" },
    { Flag = TearFlags.TEAR_QUADSPLIT, Name = "四分裂" },
    { Flag = TearFlags.TEAR_EXPLOSIVE, Name = "爆炸" },
    { Flag = TearFlags.TEAR_MULLIGAN, Name = "生成苍蝇" },
    { Flag = TearFlags.TEAR_LIGHT_FROM_HEAVEN, Name = "神圣光柱" },
    { Flag = TearFlags.TEAR_COIN_DROP, Name = "命中掉硬币" },
    { Flag = TearFlags.TEAR_GREED_COIN, Name = "贪婪硬币" },
    { Flag = TearFlags.TEAR_STICKY, Name = "黏性炸弹" },
    { Flag = TearFlags.TEAR_BOOGER, Name = "鼻屎" },
    { Flag = TearFlags.TEAR_EGG, Name = "虫卵" },
    { Flag = TearFlags.TEAR_BONE, Name = "骨头分裂" },
    { Flag = TearFlags.TEAR_JACOBS, Name = "雅各天梯" },
    { Flag = TearFlags.TEAR_HORN, Name = "小号角" },
    { Flag = TearFlags.TEAR_LASER, Name = "科技零电弧" },
    { Flag = TearFlags.TEAR_POP, Name = "噗！" },
    { Flag = TearFlags.TEAR_LASERSHOT, Name = "三圣颂光束" },
    { Flag = TearFlags.TEAR_BURSTSPLIT, Name = "爆裂分裂" },
    { Flag = TearFlags.TEAR_RIFT, Name = "邪眼裂口" },
    { Flag = TearFlags.TEAR_SPORE, Name = "毛霉菌孢子" },
}

local MIZUKI_SINGLE_TICK_TEAR_FLAGS = TearFlags.TEAR_NORMAL
for _, effect in ipairs(MIZUKI_SINGLE_TICK_TEAR_FLAG_LIST) do
    MIZUKI_SINGLE_TICK_TEAR_FLAGS =
        MIZUKI_SINGLE_TICK_TEAR_FLAGS | effect.Flag
end

-- The display layer must never receive flags that create gameplay entities.
-- It only mirrors path geometry; its color is copied from the native damage
-- layer after that layer processes the complete flag set.
local MIZUKI_VISUAL_TEAR_FLAGS = TearFlags.TEAR_WIGGLE
    | TearFlags.TEAR_ORBIT
    | TearFlags.TEAR_PULSE
    | TearFlags.TEAR_SPIRAL
    | TearFlags.TEAR_SQUARE
    | TearFlags.TEAR_BIG_SPIRAL
    | TearFlags.TEAR_HOMING
    | TearFlags.TEAR_TURN_HORIZONTAL
-- A 41-frame native Technology beam lands 20 damage ticks in current tests.
-- Finite shots therefore deal 0.4x damage per tick for an 8x total budget.
local BEAM_DURATION = 41
local BEAM_TOTAL_DAMAGE_MULTIPLIER = 8.00
-- Repentance's line weapons keep ordinary multishots close together. This is
-- the laser/brimstone correction used by the vanilla-compatible multishot
-- fallback: the basic 2.17-degree spread is widened by 1500 / 1397.
local LINE_MULTISHOT_SPREAD_FACTOR = 1500 / 1397
local LINE_MULTISHOT_BASE_SPREAD = 2.17
local LINE_MULTISHOT_GLASSES_SPREAD = 2
local WIZ_ARC_HALF_ANGLE = 45
local CONJOINED_SIDE_ANGLE = 45
local MAX_STANDARD_MULTISHOT = 16
local IMMACULATE_HEART_FALLING_ACCELERATION = -0.08
-- FireTechLaser creates the same native Technology laser used by the player
-- weapon system, including its tear-size initialization and firing sound.
local MIZUKI_LASER_VARIANT = LaserVariant.THIN_RED
local EPIC_FETUS_TRACK_FRAMES = 35
local EPIC_FETUS_FALL_FRAMES = 10
local EPIC_FETUS_COOLDOWN_MULTIPLIER = 2
local MIN_CHARGE_DAMAGE_MULTIPLIER = 0.45
local MIZUKI_LASER_COLOR = Color(1, 1, 1, 1, 0, 0, 0)
-- Colorize first converts the source to grayscale. The Technology texture is
-- primarily pure red, whose grayscale luminance is roughly one third, so the
-- requested capsule RGB needs extra brightness compensation.
MIZUKI_LASER_COLOR:SetColorize(
    5 * 246 / 255,
    5 * 171 / 255,
    5 * 180 / 255,
    1
)

local function isNeutralTearColor(color)
    return color
        and color.R == 1 and color.G == 1 and color.B == 1 and color.A == 1
        and color.RO == 0 and color.GO == 0 and color.BO == 0
end

local function hasNativeSpecialBeamColor(player, tearParams)
    local tearColor = tearParams and tearParams.TearColor
    -- Some native effects store additional color state inside Color userdata,
    -- even when its exposed RGBA fields still look neutral. Occult is one of
    -- the effects whose native color must take priority over Mizuki's base tint.
    return tearColor and (
        not isNeutralTearColor(tearColor)
        or player:HasCollectible(
            CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT
        )
    )
end

local CANNON_ANM2 = "gfx/entities/mizuki/mizuki_cannon.anm2"
local CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon.png"
local CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light.png"
local LEFT_CANNON_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_left.png"
local LEFT_CANNON_LIGHT_SPRITESHEET = "gfx/entities/mizuki/mizuki_cannon_light_left.png"
local CANNON_SCALES = {
    Vector(0.65, 0.65),
    Vector(0.65, 0.65),
}
local IDLE_CANNON_DEPTH_OFFSET = 60
local CANNON_DEPTH_OFFSET = 30
local FIRING_CANNON_DEPTH_OFFSET = 30
local HORIZONTAL_BACK_DEPTH_OFFSET = -30
local HORIZONTAL_FRONT_DEPTH_OFFSET = 30
local CHARGE_BAR_SCALE = Vector(0.5, 0.5)
local CHARGE_BAR_OFFSET = Vector(0, 5)
-- Resting formation: two separated rabbit ears above the head.
local CANNON_OFFSETS = { Vector(-12, -60), Vector(12, -60) }
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
    local beamDirection = baseDirection:Normalized():Rotated(directionOffset)

    if targetPosition then
        local targetDirection = targetPosition - visualOrigin
        if targetDirection:Length() > 0.01 then
            beamDirection = targetDirection:Normalized():Rotated(directionOffset)
        end
    end

    local targetIsHorizontal = targetPosition
        and math.abs(beamDirection.X) > math.abs(beamDirection.Y)
    local originCorrection = targetIsHorizontal
        and Vector.Zero
        or getDiagonalLaserOriginCorrection(beamDirection)
    return beamDirection, originCorrection
end

local CHARGE_BAR_COLOR = Color(1, 1, 1, 1, 1, 1, 1)
local chargeBar = Sprite()
chargeBar:Load("gfx/chargebar_revelation.anm2", true)

local function isMizuki(player)
    return player:GetPlayerType() == Mizuki.PlayerType
end

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
-- Temporary vanilla Technology sound-threshold test override. Set through the
-- built-in Lua console command and never serialized.
local debugDamageOverride = nil

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
    local baseFrames = math.max(1, math.ceil(player.MaxFireDelay + 1))
    local minMultiplier = MIN_CHARGE_PERCENT
    local maxMultiplier = 1

    -- Items which change the charge range modify its two ends independently.
    -- Chocolate Milk can later lower minMultiplier and change maxMultiplier
    -- without coupling either value to Cursed Eye's enlarged upper limit.
    if player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        and not usesAutomaticBeam(player)
    then
        maxMultiplier = maxMultiplier * CURSED_EYE_MAX_CHARGE_MULTIPLIER
    end

    return {
        BaseFrames = baseFrames,
        MinFrames = math.max(1, math.ceil(baseFrames * minMultiplier)),
        MaxFrames = math.max(1, math.ceil(baseFrames * maxMultiplier)),
    }
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
    local triggeredDirection = nil
    for _, input in ipairs(SHOOT_ACTIONS) do
        if Input.IsActionTriggered(input.Action, controller) then
            triggeredDirection = input.Direction
        end
    end

    local shootingInput = player:GetShootingInput()
    if shootingInput:Length() > 0.01 then
        local direction = shootingInput:Normalized()
        data.MizukiLastShootDirection = direction
        return true, direction
    end

    -- A newly pressed opposite direction can cancel the combined vector to
    -- zero. In that case only, let the new key choose the retained direction.
    if triggeredDirection then
        data.MizukiLastShootDirection = triggeredDirection
        return true, triggeredDirection
    end

    for _, input in ipairs(SHOOT_ACTIONS) do
        if Input.IsActionPressed(input.Action, controller) then
            return true, data.MizukiLastShootDirection or input.Direction
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

-- Keep finite beams at the native 41-frame lifetime. ShotSpeed still controls
-- their width, but no longer reduces hit count or proc opportunities.
local function getBeamDamageTiming(automatic)
    if automatic then
        -- A held automatic beam has no finite per-shot damage budget.
        return BEAM_DURATION, 1
    end

    local expectedTicks = math.floor((BEAM_DURATION - 1) / 2)
    return BEAM_DURATION, BEAM_TOTAL_DAMAGE_MULTIPLIER / expectedTicks
end

-- Weapon-specific fire-rate profiles live here.  A profile first removes the
-- relevant native WeaponType Tears multiplier, then applies Mizuki's intended
-- final multiplier.  Keep the default neutral until a real synergy is added.
local function getMizukiFireRateProfile(player)
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

local function removeActiveMizukiBeams(data)
    for side = 1, 2 do
        for _, beam in ipairs(
            data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}
        ) do
            if beam.Laser and beam.Laser:Exists() then
                beam.Laser:Remove()
            end
            if beam.VisualLaser and beam.VisualLaser:Exists() then
                beam.VisualLaser:Remove()
            end
        end
    end
    data.MizukiActiveBeams = {}
    data.MizukiLockedCannonPositions = {}
    data.MizukiLockedCannonAims = {}
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
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams[side]
        if beams and #beams == 0 then
            data.MizukiActiveBeams[side] = nil
            data.MizukiLockedCannonPositions[side] = nil
            data.MizukiLockedCannonAims[side] = nil
            beams = nil
        end
        if beams and #beams > 0 then
            local expired = false
            for _, beam in ipairs(beams) do
                local laser = beam.Laser
                local visualLaser = beam.VisualLaser
                if beam.Automatic and automaticMode and shootingHeld then
                    beam.Timeout = BEAM_DURATION
                    if laser and laser:Exists() then
                        laser.Timeout = BEAM_DURATION
                        if visualLaser and visualLaser:Exists() then
                            visualLaser.Timeout = BEAM_DURATION
                        end
                        local desiredDirection = shootingDirection
                            and shootingDirection:Rotated(beam.DirectionOffset or 0)
                            or nil
                        if desiredDirection
                            and (desiredDirection - beam.Direction):LengthSquared() > 0.0001
                        then
                            beam.Direction = desiredDirection
                            if visualLaser and visualLaser:Exists() then
                                visualLaser.AngleDegrees = desiredDirection:GetAngleDegrees()
                            end
                        end
                    end
                else
                    beam.Timeout = beam.Automatic and 0 or beam.Timeout - 1
                end
                if beam.Timeout <= 0 or not laser or not laser:Exists() then
                    if laser and laser:Exists() then
                        laser:Remove()
                    end
                    if visualLaser and visualLaser:Exists() then
                        visualLaser:Remove()
                    end
                    expired = true
                else
                    local laserData = laser:GetData()
                    if laserData.MizukiLungProbeFrames
                        and laserData.MizukiLungProbeFrames > 0 then
                        local sprite = laser:GetSprite()
                        Isaac.DebugString(string.format(
                            "[Mizuki Lung Probe] update entityFrame=%d anim=%s animFrame=%d tearScale=%s size=%s radius=%s",
                            laser.FrameCount,
                            tostring(sprite:GetAnimation()),
                            sprite:GetFrame(),
                            tostring(laser.TearScale),
                            tostring(laser.Size),
                            tostring(laser.Radius)
                        ))
                        laserData.MizukiLungProbeFrames =
                            laserData.MizukiLungProbeFrames - 1
                    end

                    local damageFrame =
                        laser.FrameCount % BEAM_DAMAGE_INTERVAL == 0
                    local hasAlmondMilk = player:HasCollectible(
                        CollectibleType.COLLECTIBLE_ALMOND_MILK
                    )
                    local refreshDynamicShape = beam.Automatic
                        and hasAlmondMilk
                        and laser.FrameCount % ALMOND_BEAM_SHAPE_INTERVAL == 0
                    -- Reroll the complete attack parameters once per damage
                    -- cadence for every effect. Almond Milk additionally
                    -- refreshes its path each frame without rerolling all
                    -- chance effects on those intermediate frames.
                    if damageFrame or refreshDynamicShape then
                        local params
                        local currentFrame = Game():GetFrameCount()
                        if damageFrame
                            and data.MizukiExtraAttackFrame ~= currentFrame
                        then
                            local attackDirection = shootingDirection
                                or beam.Direction:Rotated(-(beam.DirectionOffset or 0))
                            tryFireImmaculateHeartTear(player, attackDirection)
                            advanceLeadPencil(player, attackDirection)
                            data.MizukiExtraAttackFrame = currentFrame
                        end
                        if beam.Automatic
                            and data.MizukiSharedBeamParamsFrame == currentFrame
                        then
                            params = data.MizukiSharedBeamParams
                        else
                            local hitParamsSource = laser
                            if damageFrame then
                                hitParamsSource = nil
                            end
                            params = player:GetTearHitParams(
                                MIZUKI_HIT_PARAMS_WEAPON,
                                beam.DamageMultiplier,
                                1,
                                -- A nil source makes this damage cadence a
                                -- fresh attack roll. Intermediate Almond Milk
                                -- updates rebuild the existing path.
                                hitParamsSource
                            )
                            if beam.Automatic then
                                data.MizukiSharedBeamParamsFrame = currentFrame
                                data.MizukiSharedBeamParams = {
                                    TearFlags = params.TearFlags,
                                    TearDamage = params.TearDamage,
                                    TearColor = params.TearColor,
                                }
                                params = data.MizukiSharedBeamParams
                            end
                        end
                        local tearFlags = addOccultHoming(
                            player,
                            params.TearFlags
                        )
                        if beam.Automatic then
                            tearFlags = tearFlags
                                & ~MIZUKI_CONTINUOUS_FORBIDDEN_TEAR_FLAGS
                        end
                        laser.TearFlags = tearFlags
                        if not hasNativeSpecialBeamColor(player, params) then
                            laser.Color = MIZUKI_LASER_COLOR
                        end
                        laserData.MizukiPendingTearFlags = tearFlags
                        if visualLaser and visualLaser:Exists() then
                            local visualTearFlags = tearFlags
                                & MIZUKI_VISUAL_TEAR_FLAGS
                                & ~MIZUKI_SINGLE_TICK_TEAR_FLAGS
                            visualLaser.TearFlags = visualTearFlags
                            visualLaser:GetData().MizukiPendingTearFlags =
                                visualTearFlags
                        end
                        if damageFrame then
                            -- TearParams does not include the flat left-eye
                            -- bonuses. Add the bonus for the actual eye first;
                            -- DamagePerTickMultiplier distributes the complete
                            -- shot damage across its repeated damage ticks.
                            local leftEyeBonus = getLeftEyeFlatDamageBonus(player)
                            local eyeDamage = params.TearDamage
                                + (beam.LeftEye and leftEyeBonus or 0)
                            eyeDamage = eyeDamage
                                * getEyeDamageMultiplier(player, beam.LeftEye)
                            local collisionDamage = eyeDamage
                                * beam.DamagePerTickMultiplier
                            laser.CollisionDamage = collisionDamage
                            laserData.MizukiAssignedCollisionDamage =
                                collisionDamage
                        end
                    end
                end
            end

            if expired then
                data.MizukiActiveBeams[side] = nil
                data.MizukiLockedCannonPositions[side] = nil
                data.MizukiLockedCannonAims[side] = nil
            else
                activeSides = activeSides + 1
            end
        end
    end
    return activeSides
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
    -- In Isaac's screen coordinates, rotating the firing direction by -90
    -- degrees points to the character's anatomical left. Side 1 always uses
    -- that direction and side 2 always uses its opposite.
    local characterLeft = normalizedAim:Rotated(-90)
    local positionAim
    if isHorizontal then
        positionAim = Vector(normalizedAim.X > 0 and 1 or -1, 0)
    else
        positionAim = Vector(0, normalizedAim.Y > 0 and 1 or -1)
    end
    local positionCharacterLeft = positionAim:Rotated(-90)

    for side = 1, 2 do
        local eyeDirection = side == 1 and characterLeft or -characterLeft
        local positionEyeDirection = side == 1
            and positionCharacterLeft
            or -positionCharacterLeft
        for member = 1, #data.MizukiCannons[side] do
            local groupDistance = (member - 1) * CANNON_GROUP_SPACING
            if isHorizontal then
                local horizontalOffset = positionAim * HORIZONTAL_CANNON_X
                    + Vector(0, HORIZONTAL_CANNON_CENTER_Y)
                    + positionEyeDirection * (HORIZONTAL_CANNON_HALF_SPACING
                        + groupDistance)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, horizontalOffset)
            else
                local verticalCenterY = normalizedAim.Y > 0
                    and 0
                    or CANNON_OFFSETS[1].Y
                local restingOffset = Vector(0, verticalCenterY)
                    + positionEyeDirection * (math.abs(CANNON_OFFSETS[1].X)
                        + groupDistance)
                targetPositions[side][member] = player.Position
                    + scalePlayerOffset(player, restingOffset)
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
        local eyeDirection = side == 1 and characterLeft or -characterLeft
        for member, targetPosition in ipairs(targetPositions[side]) do
            local cannon = data.MizukiCannons[side][member]
            local sideBeams = data.MizukiActiveBeams
                and data.MizukiActiveBeams[side]
            local isFiring = sideBeams and #sideBeams > 0
            local isAutomaticFiring = sideBeams
                and sideBeams[1]
                and sideBeams[1].Automatic
            local isIdle = not data.MizukiHasShootingInput
                and (data.MizukiCharge or 0) <= 0
                and not isFiring
            local bobOffset = Vector(0, math.sin(frame * 0.16) * CANNON_FLOAT_AMPLITUDE)
            if isFiring and not isAutomaticFiring then
                -- targetPosition is the exact world position captured on the
                -- firing frame and already includes that frame's bob offset.
                cannon.Position = targetPosition
            else
                local floatingTarget = targetPosition + bobOffset
                cannon.Position = cannon.Position + (floatingTarget - cannon.Position) * CANNON_FOLLOW_SPEED
            end
            cannon.Velocity = Vector.Zero
            if isIdle then
                cannon.DepthOffset = IDLE_CANNON_DEPTH_OFFSET
            elseif isFiring and not isAutomaticFiring then
                -- Keep the firing group decisively above the native laser;
                -- depth zero can alternate around Technology's moving render
                -- position as the beam animates.
                cannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
            elseif isHorizontal then
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
            cannonData.MizukiCannonAim = cannonAim
            data.MizukiCannonPositions[side][member] = Vector(cannon.Position.X, cannon.Position.Y)

            -- The cannon position, rotation and render offset are final here.
            -- Keep every automatic beam transform in this single update path
            -- so later callbacks cannot overwrite one another.
            local sideBeams = data.MizukiActiveBeams
                and data.MizukiActiveBeams[side]
            if sideBeams then
                for _, beam in ipairs(sideBeams) do
                    local laser = beam.Laser
                    if beam.Automatic
                        and beam.Cannon
                        and GetPtrHash(beam.Cannon) == GetPtrHash(cannon)
                        and laser
                        and laser:Exists()
                    then
                        local visualOrigin = cannon.Position + sprite.Offset
                        local target = getMizukiTargetReticle(player, data)
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
    local activeBeams = data.MizukiActiveBeams
    if not activeBeams then return false end

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
    standardCount = math.min(standardCount, MAX_STANDARD_MULTISHOT)

    local totalSpread = 0
    if hasEyeSpread then
        totalSpread = (preGlassesCount - 1)
            * LINE_MULTISHOT_BASE_SPREAD
            * LINE_MULTISHOT_SPREAD_FACTOR
    end
    totalSpread = totalSpread
        + glassesCount * LINE_MULTISHOT_GLASSES_SPREAD

    local angles = {}
    local wizGroups = wizCount + 1
    for group = 1, wizGroups do
        local center = 0
        if wizGroups > 1 then
            center = -WIZ_ARC_HALF_ANGLE
                + (group - 1) * (WIZ_ARC_HALF_ANGLE * 2) / (wizGroups - 1)
        end
        appendCenteredBeamAngles(angles, center, standardCount, totalSpread)
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

local function fireMizukiBeam(player, direction, charge, automatic, forcedSide)
    local data = player:GetData()
    local chargeProfile = getChargeProfile(player)
    local firingSides
    if automatic then
        firingSides = { 1, 2 }
    elseif forcedSide then
        firingSides = { forcedSide }
    else
        data.MizukiShotSide = -(data.MizukiShotSide or -1)
        firingSides = { data.MizukiShotSide == -1 and 1 or 2 }
    end

    local beamDistance = getBeamDistance(player)
    local beamWidthScale = getBeamWidthScale(player)
    local beamDuration, damagePerTickMultiplier =
        getBeamDamageTiming(automatic)
    -- Damage reaches its ordinary full-charge value at BaseFrames. An item may
    -- extend MaxFrames to store additional attacks without diluting each one.
    local cappedCharge = math.min(charge, chargeProfile.BaseFrames)
    local chargeRange = math.max(
        1,
        chargeProfile.BaseFrames - chargeProfile.MinFrames
    )
    local normalizedCharge = math.max(
        0,
        math.min(1, (cappedCharge - chargeProfile.MinFrames) / chargeRange)
    )
    local chargeDamageMultiplier = MIN_CHARGE_DAMAGE_MULTIPLIER
        + (1 - MIN_CHARGE_DAMAGE_MULTIPLIER) * normalizedCharge
    -- Calculate the complete charged-shot damage first. The per-tick factor
    -- is applied only when assigning CollisionDamage, so native tear params,
    -- laser size and firing sound all see the same charged attack.
    local damageMultiplier = chargeDamageMultiplier
    local sharedAutomaticTearParams = automatic
        and player:GetTearHitParams(
            MIZUKI_HIT_PARAMS_WEAPON,
            damageMultiplier,
            1,
            nil
        )
        or nil
    local beamAngleOffsets = getMizukiBeamAngleOffsets(player)
    tryFireImmaculateHeartTear(player, direction)
    advanceLeadPencil(player, direction)
    data.MizukiExtraAttackFrame = Game():GetFrameCount()
    for _, side in ipairs(firingSides) do
        local origins = data.MizukiCannonPositions[side]
        if origins and #origins > 0 then
            if automatic then
                data.MizukiLockedCannonPositions[side] = nil
                data.MizukiLockedCannonAims[side] = nil
            else
                data.MizukiLockedCannonPositions[side] = {}
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
            data.MizukiActiveBeams[side] = {}
            for member, origin in ipairs(origins) do
                if not automatic then
                    data.MizukiLockedCannonPositions[side][member] = Vector(origin.X, origin.Y)
                end
                local firingCannon = data.MizukiCannons[side]
                    and data.MizukiCannons[side][member]
                if not automatic then
                    local firingAim = firingCannon
                        and firingCannon:GetData().MizukiCannonAim
                        or direction
                    data.MizukiLockedCannonAims[side].MemberAims[member] = Vector(
                        firingAim.X,
                        firingAim.Y
                    )
                end
                local visualOrigin = origin
                if firingCannon and firingCannon:Exists() then
                    visualOrigin = firingCannon.Position
                        + firingCannon:GetSprite().Offset
                end
                if firingCannon and firingCannon:Exists() and not automatic then
                    firingCannon.DepthOffset = FIRING_CANNON_DEPTH_OFFSET
                end
                for _, angleOffset in ipairs(beamAngleOffsets) do
                    local target = getMizukiTargetReticle(player, data)
                    local beamDirection, originCorrection = resolveBeamGeometry(
                        visualOrigin,
                        direction,
                        angleOffset,
                        target and target.Position or nil
                    )
                    local tearParams = sharedAutomaticTearParams
                        or player:GetTearHitParams(
                            MIZUKI_HIT_PARAMS_WEAPON,
                            damageMultiplier,
                            1,
                            nil
                        )
                    local initialTearFlags = addOccultHoming(
                        player,
                        tearParams.TearFlags
                    )
                    if automatic then
                        initialTearFlags = initialTearFlags
                            & ~MIZUKI_CONTINUOUS_FORBIDDEN_TEAR_FLAGS
                    end
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
                    local laser = player:FireTechLaser(
                        hitboxOrigin,
                        LaserOffset.LASER_TECH1_OFFSET,
                        beamDirection,
                        side == 1,
                        false,
                        player,
                        damageMultiplier
                    )
                local leftEyeBonus = getLeftEyeFlatDamageBonus(player)
                -- Preserve player-based creation (native size and sound), then
                -- detach subsequent parameter inheritance from the player.
                if firingCannon then
                    laser.SpawnerEntity = firingCannon
                end
                laser.DisableFollowParent = true
                if automatic and firingCannon then
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
                laser.Timeout = beamDuration
                laser:SetOneHit(false)
                laser:SetMaxDistance(currentBeamDistance)
                local eyeDamage = tearParams.TearDamage
                    + (side == 1 and leftEyeBonus or 0)
                eyeDamage = eyeDamage
                    * getEyeDamageMultiplier(player, side == 1)
                local collisionDamage = eyeDamage
                    * damagePerTickMultiplier
                laser.CollisionDamage = collisionDamage
                laser.TearFlags = initialTearFlags
                if not hasNativeSpecialBeamColor(player, tearParams) then
                    laser.Color = MIZUKI_LASER_COLOR
                end
                laser:GetData().MizukiBeam = true
                laser:GetData().MizukiBeamOwner = player
                laser:GetData().MizukiBeamWidthScale = beamWidthScale
                laser:GetData().MizukiBeamAutomatic = automatic
                laser:GetData().MizukiBeamCollisionOnly = automatic
                laser:GetData().MizukiBeamSide = side
                laser:GetData().MizukiBeamMember = member
                laser:GetData().MizukiDamageProbeFrames = automatic and 30 or 0

                    table.insert(data.MizukiActiveBeams[side], {
                        Laser = laser,
                        Origin = Vector(origin.X, origin.Y),
                        Direction = Vector(beamDirection.X, beamDirection.Y),
                        DirectionOffset = angleOffset,
                        Distance = currentBeamDistance,
                        Timeout = beamDuration,
                        Duration = beamDuration,
                        DamageMultiplier = damageMultiplier,
                        DamagePerTickMultiplier = damagePerTickMultiplier,
                        LeftEye = side == 1,
                        Automatic = automatic,
                        Cannon = firingCannon,
                    })
                end
            end
        end
    end
end

local function startCursedEyeBurst(player, data, direction, charge, profile)
    local shotCount = getCursedEyeShotCount(player, charge, profile)
    fireMizukiBeam(player, direction, charge, false)
    if shotCount > 1 then
        local firingSide = data.MizukiShotSide == -1 and 1 or 2
        data.MizukiCursedEyeBurst = {
            Remaining = shotCount - 1,
            Direction = Vector(direction.X, direction.Y),
            Charge = profile.BaseFrames,
            Side = firingSide,
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
        burst.Side
    )
    burst.Remaining = burst.Remaining - 1
    if burst.Remaining <= 0 then
        data.MizukiCursedEyeBurst = nil
    end
    return true
end

local function updateKidneyStoneBurst(player, data)
    local currentMaxFireDelay = player.MaxFireDelay
    local previousMaxFireDelay = data.MizukiKidneyStoneLastMaxFireDelay
    data.MizukiKidneyStoneLastMaxFireDelay = currentMaxFireDelay

    if not player:HasCollectible(CollectibleType.COLLECTIBLE_KIDNEY_STONE) then
        data.MizukiKidneyStoneBurst = nil
        return nil
    end

    local burst = data.MizukiKidneyStoneBurst
    if not burst and previousMaxFireDelay ~= nil then
        local previousInterval = previousMaxFireDelay + 1
        local currentInterval = currentMaxFireDelay + 1
        if previousInterval / math.max(currentInterval, 0.001)
            >= KIDNEY_STONE_TRIGGER_FIRE_RATE_RATIO
        then
            burst = {
                Elapsed = 0,
                StableFrames = 0,
                LastMaxFireDelay = currentMaxFireDelay,
                Direction = data.MizukiLastShootDirection,
            }
            data.MizukiKidneyStoneBurst = burst
            removeActiveMizukiBeams(data)
            data.MizukiCharge = 0
            data.MizukiAim = nil
            data.MizukiChargeBarFullFrames = nil
        end
    end

    if not burst then
        return nil
    end

    local aim = player:GetAimDirection()
    if aim:Length() > 0.01 then
        burst.Direction = aim:Normalized()
        data.MizukiLastShootDirection = burst.Direction
    end

    if burst.Elapsed > 0 then
        if math.abs(currentMaxFireDelay - burst.LastMaxFireDelay)
            <= KIDNEY_STONE_FIRE_DELAY_EPSILON
        then
            burst.StableFrames = burst.StableFrames + 1
        else
            burst.StableFrames = 0
        end
    end
    burst.LastMaxFireDelay = currentMaxFireDelay
    burst.Elapsed = burst.Elapsed + 1

    local rockBottom = player:HasCollectible(
        CollectibleType.COLLECTIBLE_ROCK_BOTTOM
    )
    local naturallyFinished = burst.Elapsed >= KIDNEY_STONE_MIN_BURST_FRAMES
        and burst.StableFrames >= KIDNEY_STONE_STABLE_FRAMES
    local timedOut = not rockBottom
        and burst.Elapsed >= KIDNEY_STONE_MAX_BURST_FRAMES
    if not rockBottom and (naturallyFinished or timedOut) then
        data.MizukiKidneyStoneBurst = nil
        return nil
    end

    return burst
end

function Mizuki:UpdateWeapon(player)
    if not isMizuki(player) then
        return
    end

    -- Door transitions temporarily clear shooting input. Treat that as a
    -- pause, not a release, so a held charge and its cannon facing survive
    -- until control returns in the destination room.
    if Game():IsPaused() then
        return
    end

    local data = player:GetData()
    updateCannonReconcile(player, data)
    updateEpicFetusStrike(player, data)

    if data.MizukiRefreshCannonCache then
        data.MizukiRefreshCannonCache = nil
        player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
        player:EvaluateItems()
    end
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    local kidneyStoneBurst = updateKidneyStoneBurst(player, data)
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
    local activeSides = updateActiveBeams(
        player,
        data,
        data.MizukiHasShootingInput,
        shootingDirection,
        automatic
    )
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
        if activeSides == 0
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
    data.MizukiCannonAim = data.MizukiCursedEyeBurst
        and Vector(
            data.MizukiCursedEyeBurst.Direction.X,
            data.MizukiCursedEyeBurst.Direction.Y
        )
        or Vector(0, -1)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateWeapon)

local mizukiDamageProbeHits = 0
local MIZUKI_DAMAGE_PROBE_HIT_LIMIT = 80

function Mizuki:TriggerEpicFetusStrike(entity, amount, damageFlags, source)
    local enemy = entity:ToNPC()
    if not enemy
        or not enemy:IsActiveEnemy(false)
        or enemy:IsDead()
        or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return
    end

    local player = getMizukiBeamOwnerFromDamageSource(source)
    if player and mizukiDamageProbeHits < MIZUKI_DAMAGE_PROBE_HIT_LIMIT then
        local sourceEntity = source and source.Entity
        local sourceData = sourceEntity and sourceEntity:GetData() or nil
        Isaac.DebugString(string.format(
            "[Mizuki Hit Damage Probe] amount=%s damageFlags=%s sourceType=%s sourceVariant=%s sourceSubType=%s sourceSeed=%s",
            tostring(amount),
            tostring(damageFlags),
            tostring(sourceEntity and sourceEntity.Type),
            tostring(sourceEntity and sourceEntity.Variant),
            tostring(sourceEntity and sourceEntity.SubType),
            tostring(sourceEntity and sourceEntity.InitSeed)
        ))
        mizukiDamageProbeHits = mizukiDamageProbeHits + 1
    end
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
    startEpicFetusStrike(
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

    -- Player-fired lasers can restore creation-time flags during their native
    -- update. Reapply the current Almond Milk roll at the final laser-update
    -- callback so it survives into the next path calculation.
    if laserData.MizukiPendingTearFlags then
        laser.TearFlags = laserData.MizukiPendingTearFlags
    end

    -- Both finite and automatic damaging beams reroll discrete effects on the
    -- five-frame damage cadence. Let the current roll survive one native laser
    -- update, then remove it until the next cadence. The visual-only automatic
    -- beam never receives these flags in the first place.
    if not laserData.MizukiBeamVisualOnly then
        laser:ClearTearFlags(MIZUKI_SINGLE_TICK_TEAR_FLAGS)
    end

    if laserData.MizukiBeamCollisionOnly then
        queueEpicFetusGridTarget(laser)
    elseif not laserData.MizukiBeamVisualOnly then
        queueEpicFetusGridTarget(laser)
    end

    if laserData.MizukiBeamVisualOnly then
        local collisionLaser = laserData.MizukiBeamCollisionLaser
        if collisionLaser and collisionLaser:Exists() then
            laser.Color = collisionLaser.Color
        end
    end

    if laserData.MizukiBeamCollisionOnly
        and (laserData.MizukiDamageProbeFrames or 0) > 0
        and laser.FrameCount % BEAM_DAMAGE_INTERVAL == 0
    then
        Isaac.DebugString(string.format(
            "[Mizuki Dual Damage Probe] side=%s member=%s frame=%d assigned=%s actual=%s flags=%s",
            tostring(laserData.MizukiBeamSide),
            tostring(laserData.MizukiBeamMember),
            laser.FrameCount,
            tostring(laserData.MizukiAssignedCollisionDamage),
            tostring(laser.CollisionDamage),
            tostring(laser.TearFlags)
        ))
        laserData.MizukiDamageProbeFrames =
            laserData.MizukiDamageProbeFrames - 1
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
        laser.Size = laser.Size * widthScale
        laserData.MizukiBeamWidthApplied = true
    end

    local baseScale = laserData.MizukiBeamBaseSpriteScale or Vector.One
    -- Size may synchronize back into SpriteScale during native updates. Undo
    -- its longitudinal scaling after every update: widen around the shared
    -- centered X pivot, while leaving body length and tip placement native.
    laser.SpriteScale = Vector(
        baseScale.X * widthScale,
        baseScale.Y
    )
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_UPDATE,
    Mizuki.ApplyLaserWidth,
    MIZUKI_LASER_VARIANT
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
                    startEpicFetusStrike(player, nil, candidate.Position)
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
        elseif cacheFlag == CacheFlag.CACHE_SPEED and capsuleDelta then
            player.MoveSpeed = player.MoveSpeed + capsuleDelta.MoveSpeed
        elseif cacheFlag == CacheFlag.CACHE_SHOTSPEED and capsuleDelta then
            player.ShotSpeed = player.ShotSpeed + capsuleDelta.ShotSpeed
        elseif cacheFlag == CacheFlag.CACHE_RANGE and capsuleDelta then
            player.TearRange = player.TearRange + capsuleDelta.TearRange
        elseif cacheFlag == CacheFlag.CACHE_LUCK and capsuleDelta then
            player.Luck = player.Luck + capsuleDelta.Luck
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

    if cacheFlag == CacheFlag.CACHE_DAMAGE and debugDamageOverride then
        player.Damage = debugDamageOverride
    end
end

Mizuki:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, Mizuki.ApplyTearsMultiplier)

local function refreshDebugDamageAndPrint()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
        local laserParams = player:GetTearHitParams(
            WeaponType.WEAPON_TEARS,
            1,
            1,
            nil
        )
        Isaac.ConsoleOutput(string.format(
            "[Mizuki Tech Sound Test] player=%d damage=%.8f tearScale=%.8f\n",
            index,
            player.Damage,
            laserParams.TearScale
        ))
    end
end

function Mizuki.SetDebugDamageOverride(requestedDamage)
    if requestedDamage == nil or requestedDamage == false then
        debugDamageOverride = nil
        Isaac.ConsoleOutput("[Mizuki Tech Sound Test] damage override disabled\n")
        refreshDebugDamageAndPrint()
        return
    end

    requestedDamage = tonumber(requestedDamage)
    if not requestedDamage or requestedDamage < 0 then
        Isaac.ConsoleOutput(
            "[Mizuki Tech Sound Test] usage: lua MizukiTestDamage(number|nil)\n"
        )
        return
    end

    debugDamageOverride = requestedDamage
    refreshDebugDamageAndPrint()
end

-- Intentionally exposed only as a temporary debug-console entry point.
MizukiTestDamage = Mizuki.SetDebugDamageOverride
MizukiPrintTechSize = refreshDebugDamageAndPrint

function Mizuki:InitCannonFamiliar(cannon)
    cannon.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    cannon.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    cannon.DepthOffset = CANNON_DEPTH_OFFSET
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitCannonFamiliar, Mizuki.CannonVariant)

-- Keep cannon body scaling in one Familiar-owned update path so no other
-- callback can accidentally overwrite the final render scale.
function Mizuki:UpdateCannonScale(cannon)
    ensureCannonRegistered(cannon)
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
                        local outward = side == 1 and -(member - 1) or (member - 1)
                        local restingOffset = CANNON_OFFSETS[side]
                            + Vector(outward * CANNON_GROUP_SPACING, 0)
                        cannon.Position = player.Position
                            + scalePlayerOffset(player, restingOffset)
                        cannon.Velocity = Vector.Zero
                        local aim = data.MizukiCannonAim or Vector(0, -1)
                        local cannonData = cannon:GetData()
                        cannonData.MizukiCannonAim = aim
                        cannonData.MizukiIdleRotationOffset = side == 1
                            and LEFT_CANNON_IDLE_ROTATION
                            or RIGHT_CANNON_IDLE_ROTATION
                        local baseRotation = aim:GetAngleDegrees() + 90
                        local idleRotation = cannonData.MizukiIdleRotationOffset
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

-- Draw immediately after the selected Familiar. The Familiar survives room
-- changes and this callback receives the same camera offset used for its body.
function Mizuki:RenderChargeBar(cannon, renderOffset)
    local player = cannon.Player
    if not player or not isMizuki(player) then
        return
    end

    local data = player:GetData()
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

    local renderPosition = Isaac.WorldToScreen(cannon.Position) + renderOffset
        + cannonSprite.Offset
        + CHARGE_BAR_OFFSET:Rotated(cannonSprite.Rotation)
        - room:GetRenderScrollOffset() - Game().ScreenShakeOffset
        
    -- The Revelation charge bar separates its art into bg (0), bar (1), and
    -- the inward-contracting outer circle (2). Mizuki only uses the circle.
    chargeBar:RenderLayer(2, renderPosition)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, Mizuki.RenderChargeBar, Mizuki.CannonVariant)

-- Experimental Capsule -----------------------------------------------------
-- This is a real pocket object, so it occupies the normal card/pill slot.
-- The small state machine distinguishes deliberately consuming it from trying
-- to drop it: only the latter causes the capsule to be restored.
local function findExperimentalCapsuleSlot(player)
    for slot = 0, 1 do
        if player:GetCard(slot) == Mizuki.ExperimentalCapsuleCard then
            return slot
        end
    end

    return nil
end

local function getConsumableSlotCount(player)
    local slotCount = player:GetMaxPocketItems()
    if player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= CollectibleType.COLLECTIBLE_NULL then
        slotCount = slotCount - 1
    end

    return math.max(1, math.min(2, slotCount))
end

local function pocketConsumableSlotIsEmpty(player, slot)
    return player:GetCard(slot) == Card.CARD_NULL and player:GetPill(slot) == PillColor.PILL_NULL
end

local function movePocketConsumable(player, fromSlot, toSlot)
    local card = player:GetCard(fromSlot)
    local pill = player:GetPill(fromSlot)

    player:SetCard(fromSlot, Card.CARD_NULL)
    player:SetPill(fromSlot, PillColor.PILL_NULL)
    if card ~= Card.CARD_NULL then
        player:SetCard(toSlot, card)
    elseif pill ~= PillColor.PILL_NULL then
        player:SetPill(toSlot, pill)
    end
end

local function captureExperimentalPillStats(player)
    return {
        Damage = player.Damage,
        Tears = 30 / (player.MaxFireDelay + 1),
        MoveSpeed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed,
        TearRange = player.TearRange,
        Luck = player.Luck,
    }
end

local function subtractExperimentalPillStats(after, before)
    return {
        Damage = after.Damage - before.Damage,
        Tears = after.Tears - before.Tears,
        MoveSpeed = after.MoveSpeed - before.MoveSpeed,
        ShotSpeed = after.ShotSpeed - before.ShotSpeed,
        TearRange = after.TearRange - before.TearRange,
        Luck = after.Luck - before.Luck,
    }
end

local function addExperimentalPillStats(total, addition)
    total = total or {
        Damage = 0,
        Tears = 0,
        MoveSpeed = 0,
        ShotSpeed = 0,
        TearRange = 0,
        Luck = 0,
    }

    for stat, value in pairs(addition) do
        total[stat] = (total[stat] or 0) + value
    end

    return total
end

local function removeDroppedExperimentalCapsules(player)
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TAROTCARD,
        -1,
        false,
        false
    )) do
        if (entity.SubType == Mizuki.ExperimentalCapsuleCard
                or entity.SubType == EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE)
            and entity.Position:DistanceSquared(player.Position) <= 14400 then
            entity:Remove()
        end
    end
end

local function giveExperimentalCapsule(player)
    local state = getCapsuleState(player)
    local existingSlot = findExperimentalCapsuleSlot(player)
    if existingSlot == 0 then
        state.WasHeld = true
        state.LastSlot = 0
        return
    end

    local slotCount = getConsumableSlotCount(player)
    if existingSlot == 1 then
        -- The capsule must always be the selected/front consumable. Move the
        -- former slot-0 object behind it without dropping either object.
        player:SetCard(1, Card.CARD_NULL)
        if not pocketConsumableSlotIsEmpty(player, 0) then
            movePocketConsumable(player, 0, 1)
        end
    elseif not pocketConsumableSlotIsEmpty(player, 0) then
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            movePocketConsumable(player, 0, 1)
        else
            -- With no spare slot, preserve the selected object as a pickup
            -- before reserving slot 0 for the floor-refreshed capsule.
            player:DropPocketItem(0, player.Position)
        end
    end

    player:SetCard(0, Mizuki.ExperimentalCapsuleCard)
    state.Consumed = false
    state.WasHeld = true
    state.LastSlot = 0
end

local function giveCapsuleHourGlass(player, alreadyUsed)
    -- SetPocketActiveItem is the only stable vanilla API for a character that
    -- did not start with an XML-defined pocket active. Remaining capsule uses
    -- are tracked by the mod, while the native VarData is synchronized below
    -- so the HUD shows the same count.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)

    local used = alreadyUsed or 0
    if used > 0 then
        -- SetPocketActiveItem first materializes the dynamic pocket-active
        -- slot. Replacing that occupied slot through the vanilla
        -- AddCollectible API then writes Glowing Hour Glass's real VarData,
        -- which is also what the HUD uses for its remaining-use display.
        player:AddCollectible(
            GLOWING_HOUR_GLASS,
            0,
            false,
            ActiveSlot.SLOT_POCKET,
            used
        )
    end
end

function Mizuki:MaintainExperimentalCapsule(player)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    local slot = findExperimentalCapsuleSlot(player)
    if not state.Initialized then
        state.Initialized = true
        state.LastSlot = slot or 0
        if slot ~= nil then
            state.Consumed = false
            state.WasHeld = true
        elseif player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            ~= CollectibleType.COLLECTIBLE_NULL then
            state.Consumed = true
            state.WasHeld = false
        else
            -- Makes a Lua hot reload recover the character's floor state
            -- instead of leaving both pocket areas blank.
            giveExperimentalCapsule(player)
            slot = findExperimentalCapsuleSlot(player)
        end
    end
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end
    if slot ~= nil then
        -- Glowing Hour Glass restores the pre-use consumable inventory. Mod
        -- state is intentionally kept outside that snapshot, so a consumed
        -- capsule is removed again instead of becoming an infinite hourglass.
        if state.Consumed then
            player:SetCard(slot, Card.CARD_NULL)
            slot = nil
        else
            state.WasHeld = true
            state.LastSlot = slot
            return
        end
    end

    if state.RewindFrames then
        state.RewindFrames = state.RewindFrames - 1
        if state.RewindFrames <= 0 then
            state.RewindFrames = nil
            if state.PendingStatDelta then
                state.RewindStatDelta = addExperimentalPillStats(
                    state.RewindStatDelta,
                    state.PendingStatDelta
                )
                state.PendingStatDelta = nil
                player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
                player:EvaluateItems()
            end
            giveCapsuleHourGlass(player, 1)
            state.CapsuleHourGlassUsesRemaining = 2
        end
    end

    if state.CapsuleHourGlassRestoreFrames then
        state.CapsuleHourGlassRestoreFrames = state.CapsuleHourGlassRestoreFrames - 1
        if state.CapsuleHourGlassRestoreFrames <= 0 then
            state.CapsuleHourGlassRestoreFrames = nil
            giveCapsuleHourGlass(player, 3 - state.CapsuleHourGlassUsesRemaining)
        end
    end

    if state.CapsuleHourGlassFinishFrames then
        state.CapsuleHourGlassFinishFrames = state.CapsuleHourGlassFinishFrames - 1
        if state.CapsuleHourGlassFinishFrames <= 0 then
            state.CapsuleHourGlassFinishFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            player:SetPocketActiveItem(HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
        end
    end

    if not state.Consumed and state.WasHeld then
        removeDroppedExperimentalCapsules(player)
        giveExperimentalCapsule(player)
    end
end


function Mizuki:BlockPocketPickupWhileCapsuleSelected(pickup, collider)
    local player = collider:ToPlayer()
    if not player or not isMizuki(player) then
        return
    end

    -- Slot 0 is the selected consumable. If a real secondary consumable slot
    -- is unlocked and empty, vanilla can safely place the pickup there.
    --
    -- Otherwise keep this pickup briefly in vanilla's "not yet collectible"
    -- state instead of cancelling the collision with `return true`.
    -- The normal pickup collision logic can then still run.
    if player:GetCard(0) == Mizuki.ExperimentalCapsuleCard then
        local slotCount = getConsumableSlotCount(player)
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            return
        end

        pickup.Wait = math.max(pickup.Wait or 0, 2)
        return
    end
end


function Mizuki:UseExperimentalCapsule(card, player, useFlags)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    state.Consumed = true
    state.WasHeld = false
    state.ImmediateHourGlass = true
    state.UseRoomIndex = Game():GetLevel():GetCurrentRoomIndex()

    state.PillStatsBefore = captureExperimentalPillStats(player)
    state.CapturePillStatsPending = true

    -- Delegate the stat changes, feedback and all edge cases to the vanilla
    -- Experimental Pill implementation instead of reproducing its RNG here.
    player:UsePill(PillEffect.PILLEFFECT_EXPERIMENTAL, PillColor.PILL_NULL, useFlags)
    giveCapsuleHourGlass(player, 0)
end


function Mizuki:UseCapsuleHourGlass(collectible, rng, player, useFlags, activeSlot)
    if not isMizuki(player) then
        return
    end

    -- Glowing Hour Glass can transiently duplicate custom familiars while its
    -- rewind snapshot is being restored. player:GetData() is itself rewound, so
    -- keep this marker in external Lua state or the rewind erases the request.
    local reconcileState = getCannonReconcileState(player)
    reconcileState.Pending = true

    local state = getCapsuleState(player)
    -- If the hourglass was activated before the next player update, finish
    -- the post-pill snapshot here. The native pill cache has resolved by now.
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end

    local isImmediateCapsuleHourGlass = state.ImmediateHourGlass
        and state.UseRoomIndex == Game():GetLevel():GetCurrentRoomIndex()
    if state.Consumed and isImmediateCapsuleHourGlass then
        -- Resolve after the vanilla rewind has restored the room/player state.
        -- Item restoration must not depend on whether the pill stat cache has
        -- finished resolving; a very fast use can arrive before that snapshot.
        -- Clear the marker before restoring the item so later uses are native.
        state.ImmediateHourGlass = false
        state.RewindRequested = true
    elseif state.CapsuleHourGlassUsesRemaining then
        state.CapsuleHourGlassUsesRemaining = state.CapsuleHourGlassUsesRemaining - 1
        if state.CapsuleHourGlassUsesRemaining > 0 then
            state.CapsuleHourGlassRestoreRequested = true
        else
            state.CapsuleHourGlassFinishRequested = true
        end
    end

    if isImmediateCapsuleHourGlass or state.CapsuleHourGlassUsesRemaining ~= nil then
        return {
            Discharge = false,
            Remove = false,
            ShowAnim = true,
        }
    end
end


function Mizuki:ExpireImmediateCapsuleHourGlass()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local reconcileState = getCannonReconcileState(player)
            if reconcileState.Pending then
                reconcileState.Pending = nil
                reconcileState.Frames = 2
            end

            local state = getCapsuleState(player)
            if state.RewindRequested then
                state.RewindRequested = nil
                state.RewindFrames = 1
            elseif state.CapsuleHourGlassRestoreRequested then
                state.CapsuleHourGlassRestoreRequested = nil
                state.CapsuleHourGlassRestoreFrames = 1
            elseif state.CapsuleHourGlassFinishRequested then
                state.CapsuleHourGlassFinishRequested = nil
                state.CapsuleHourGlassFinishFrames = 1
            else
                state.ImmediateHourGlass = false
                state.PendingStatDelta = nil
            end
        end
    end
end


function Mizuki:InitializeExperimentalCapsule(isContinued)
    capsuleStates = {}
    cannonReconcileStates = {}
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            -- Add by resolved custom ID instead of relying on players.xml to
            -- parse a localized/custom item name. The quest tag protects it
            -- from ordinary rerolls after this one-time initialization.
            if not player:HasCollectible(Mizuki.FanItem) then
                player:AddCollectible(Mizuki.FanItem, 0, false)
            end
            player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
            player:EvaluateItems()
            local state = getCapsuleState(player)
            local slot = findExperimentalCapsuleSlot(player)
            local pocketActive = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            local hasCapsuleHourGlass = pocketActive == GLOWING_HOUR_GLASS
                or pocketActive == HOUR_GLASS

            state.WasHeld = slot ~= nil
            state.Initialized = true
            state.LastSlot = slot or 0
            state.Consumed = hasCapsuleHourGlass and slot == nil
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil

            if slot == nil and pocketActive == CollectibleType.COLLECTIBLE_NULL then
                giveExperimentalCapsule(player)
            end

        end
    end
end


function Mizuki:RefreshExperimentalCapsule()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            if player:GetActiveItem(ActiveSlot.SLOT_POCKET) == GLOWING_HOUR_GLASS then
                player:SetPocketActiveItem(
                    CollectibleType.COLLECTIBLE_NULL,
                    ActiveSlot.SLOT_POCKET,
                    true
                )
            end

            local state = getCapsuleState(player)
            state.Consumed = false
            state.WasHeld = false
            state.Initialized = true
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil
            state.PillStatsBefore = nil
            state.CapturePillStatsPending = nil
            state.RewindRequested = nil
            state.RewindFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            state.CapsuleHourGlassRestoreRequested = nil
            state.CapsuleHourGlassRestoreFrames = nil
            state.CapsuleHourGlassFinishRequested = nil
            state.CapsuleHourGlassFinishFrames = nil
            giveExperimentalCapsule(player)
        end
    end
end


Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.MaintainExperimentalCapsule)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_TAROTCARD
)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_PILL
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_CARD,
    Mizuki.UseExperimentalCapsule,
    Mizuki.ExperimentalCapsuleCard
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.UseCapsuleHourGlass,
    GLOWING_HOUR_GLASS
)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.RefreshExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ExpireImmediateCapsuleHourGlass)

-- Mizuki Fan ---------------------------------------------------------------
-- Values which the design document leaves open are centralized for testing.
local FAN_BLOCK_CHANCE = 1.00
local FAN_NEED_WINDOW = 0.10
local FAN_BFFS_CLEAR_CHANCE = 0.20
local FAN_LUCK_CLEAR_CAP = 0.05
local FAN_MOMS_BOX_GOLDEN_CHANCE = 0.10
local FAN_SACK_HEAD_REPLACE_CHANCE = 0.20
local FAN_BFFS_BLOCK_RADIUS_MULTIPLIER = 1.5
local FAN_GIFT_OFFSET = Vector(0, 8)
local GOLDEN_TRINKET_FLAG = 1 << 15

local function getFanOwner(familiar)
    local player = familiar.Player
    return player and isMizuki(player) and player or nil
end

local function getFanNeeds(player)
    local trinketSlots = math.max(1, player:GetMaxTrinkets())
    local trinketsFilled = 0
    for slot = 0, trinketSlots - 1 do
        if player:GetTrinket(slot) ~= TrinketType.TRINKET_NULL then
            trinketsFilled = trinketsFilled + 1
        end
    end

    local pocketSlots = getConsumableSlotCount(player)
    local pocketsFilled = 0
    for slot = 0, pocketSlots - 1 do
        if not pocketConsumableSlotIsEmpty(player, slot) then
            pocketsFilled = pocketsFilled + 1
        end
    end

    local health = player:GetHearts() + player:GetSoulHearts()
        + player:GetBoneHearts() * 2
    local function need(current, threshold)
        return math.max(0, math.min(1, 1 - current / threshold))
    end
    return {
        { Kind = "Coin", Need = need(player:GetNumCoins(), 15) },
        { Kind = "Bomb", Need = need(player:GetNumBombs(), 5) },
        { Kind = "Key", Need = need(player:GetNumKeys(), 5) },
        { Kind = "Heart", Need = need(health, 12) },
        { Kind = "Trinket", Need = need(trinketsFilled, trinketSlots) },
        { Kind = "Pocket", Need = need(pocketsFilled, pocketSlots) },
    }
end

local function chooseFanCategory(player, rng)
    local needs = getFanNeeds(player)
    local maxNeed = 0
    for _, entry in ipairs(needs) do maxNeed = math.max(maxNeed, entry.Need) end
    if maxNeed <= 0 then
        local roll = rng:RandomFloat()
        if roll < 0.50 then return needs[rng:RandomInt(4) + 1].Kind, true end
        return roll < 0.75 and "Trinket" or "Pocket", true
    end

    local candidates = {}
    for _, entry in ipairs(needs) do
        if entry.Need >= maxNeed - FAN_NEED_WINDOW then
            candidates[#candidates + 1] = entry.Kind
        end
    end
    return candidates[rng:RandomInt(#candidates) + 1], false
end

local function randomFrom(rng, values)
    return values[rng:RandomInt(#values) + 1]
end

local function rollFanReward(player, rng)
    local kind, wealthy = chooseFanCategory(player, rng)
    local advanced = wealthy and rng:RandomFloat() < 0.50
    local reward
    local basic = not advanced
    if kind == "Coin" then
        reward = { PickupVariant.PICKUP_COIN, advanced and randomFrom(rng, { 2, 3, 4, 5, 6, 7 }) or 0 }
    elseif kind == "Bomb" then
        reward = { PickupVariant.PICKUP_BOMB, advanced and randomFrom(rng, { 2, 4 }) or 0 }
    elseif kind == "Key" then
        reward = { PickupVariant.PICKUP_KEY, advanced and randomFrom(rng, { 2, 3, 4 }) or 0 }
    elseif kind == "Heart" then
        reward = { PickupVariant.PICKUP_HEART, advanced and randomFrom(rng, { 2, 3, 5, 6, 7, 9, 10 }) or 0 }
    elseif kind == "Trinket" then
        local subtype = Game():GetItemPool():GetTrinket()
        if player:HasCollectible(MOMS_BOX)
            and rng:RandomFloat() < FAN_MOMS_BOX_GOLDEN_CHANCE then
            subtype = subtype | GOLDEN_TRINKET_FLAG
        end
        reward = { PickupVariant.PICKUP_TRINKET, subtype }
        basic = false
    else
        local pool = Game():GetItemPool()
        if rng:RandomInt(2) == 0 then
            local subtype = pool:GetCard(rng:Next(), false, true, false)
            if advanced then
                for _ = 1, 12 do
                    if subtype < 1 or subtype > 22 then break end
                    subtype = pool:GetCard(rng:Next(), false, true, false)
                end
            end
            reward = { PickupVariant.PICKUP_TAROTCARD, subtype }
        else
            local subtype = pool:GetPill(rng:Next())
            if advanced then subtype = subtype | PillColor.PILL_GIANT_FLAG end
            reward = { PickupVariant.PICKUP_PILL, subtype }
        end
    end

    if basic and kind ~= "Trinket" and player:HasCollectible(SACK_HEAD)
        and rng:RandomFloat() < FAN_SACK_HEAD_REPLACE_CHANCE then
        reward = { PickupVariant.PICKUP_GRAB_BAG, 0 }
    end
    return reward
end

local function queueFanGift(familiar)
    local player = getFanOwner(familiar)
    if not player then return end
    local data = familiar:GetData()
    data.MizukiFanGiftQueue = data.MizukiFanGiftQueue or {}
    data.MizukiFanGiftQueue[#data.MizukiFanGiftQueue + 1] =
        rollFanReward(player, familiar:GetDropRNG())
end

function Mizuki:InitFanFamiliar(familiar)
    familiar:AddToFollowers()
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    familiar:GetSprite():Play("Float", true)
end

function Mizuki:UpdateFanFamiliar(familiar)
    local player = getFanOwner(familiar)
    if not player then return end
    familiar:FollowParent()

    local sprite = familiar:GetSprite()
    local data = familiar:GetData()
    -- The painted frame faces slightly right. Mirror only after the familiar
    -- moves clearly across the player, keeping the previous direction near
    -- the centre line so follower bobbing cannot make it flicker.
    local horizontalOffset = familiar.Position.X - player.Position.X
    if horizontalOffset < -4 then
        sprite.FlipX = false
    elseif horizontalOffset > 4 then
        sprite.FlipX = true
    end
    local queue = data.MizukiFanGiftQueue
    if queue and #queue > 0 and not sprite:IsPlaying("Gift") then
        data.MizukiFanCurrentGift = table.remove(queue, 1)
        sprite:Play("Gift", true)
    end
    if sprite:IsEventTriggered("Drop") and data.MizukiFanCurrentGift then
        local reward = data.MizukiFanCurrentGift
        Isaac.Spawn(EntityType.ENTITY_PICKUP, reward[1], reward[2],
            familiar.Position + FAN_GIFT_OFFSET, Vector.Zero, familiar)
        SFXManager():Play(SoundEffect.SOUND_THUMBSUP, 1.0, 0, false, 1.0)
        data.MizukiFanCurrentGift = nil
    end
    if sprite:IsFinished("Gift") then sprite:Play("Float", true) end

    local radius = familiar.Size
    if player:HasCollectible(BFFS) then
        radius = radius * FAN_BFFS_BLOCK_RADIUS_MULTIPLIER
    end
    for _, entity in ipairs(Isaac.FindInRadius(
        familiar.Position, radius + 8, EntityPartition.BULLET
    )) do
        local projectile = entity:ToProjectile()
        if projectile and projectile:Exists()
            and projectile.Position:Distance(familiar.Position) <= radius + projectile.Size then
            local projectileData = projectile:GetData()
            projectileData.MizukiFanBlockAttempts = projectileData.MizukiFanBlockAttempts or {}
            local fanKey = tostring(familiar.InitSeed)
            if not projectileData.MizukiFanBlockAttempts[fanKey] then
                projectileData.MizukiFanBlockAttempts[fanKey] = true
                if familiar:GetDropRNG():RandomFloat() < FAN_BLOCK_CHANCE then
                    projectile:Die()
                end
            end
        end
    end
end

function Mizuki:RollFanRoomClearGifts()
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR, Mizuki.FanVariant, -1, false, false
    )) do
        local familiar = entity:ToFamiliar()
        local player = getFanOwner(familiar)
        if player then
            local luck = math.max(player.Luck, 0)
            local luckChance = FAN_LUCK_CLEAR_CAP * luck / (luck + 5)
            if player:HasCollectible(LUCKY_FOOT) then luckChance = luckChance * 2 end
            local chance = luckChance
                + (player:HasCollectible(BFFS) and FAN_BFFS_CLEAR_CHANCE or 0)
            if familiar:GetDropRNG():RandomFloat() < chance then
                queueFanGift(familiar)
            end
        end
    end
end

local function queueFloorGiftForPlayer(player)
    player:GetData().MizukiFanFloorGiftPending = true
    player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    player:EvaluateItems()
end

function Mizuki:QueueFanFloorGifts()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then queueFloorGiftForPlayer(player) end
    end
end

function Mizuki:InitializeFanFloorGift(isContinued)
    if not isContinued then Mizuki:QueueFanFloorGifts() end
end

function Mizuki:DispatchFanFloorGift(player)
    if not isMizuki(player) or not player:GetData().MizukiFanFloorGiftPending then return end
    local fans = {}
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR, Mizuki.FanVariant, -1, false, false
    )) do
        local familiar = entity:ToFamiliar()
        if familiar and familiar.Player
            and GetPtrHash(familiar.Player) == GetPtrHash(player) then
            fans[#fans + 1] = familiar
        end
    end
    table.sort(fans, function(a, b) return a.InitSeed < b.InitSeed end)
    if fans[1] then
        player:GetData().MizukiFanFloorGiftPending = nil
        queueFanGift(fans[1])
    end
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitFanFamiliar, Mizuki.FanVariant)
Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, Mizuki.UpdateFanFamiliar, Mizuki.FanVariant)
Mizuki:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, Mizuki.RollFanRoomClearGifts)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeFanFloorGift)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.QueueFanFloorGifts)
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.DispatchFanFloorGift)

-- Temporary native Technology 2 + Almond Milk probe. Reload the mod, hold a
-- firing direction for a few seconds, then inspect log.txt for this prefix.
local tech2AlmondProbeFrames = 0
local TECH2_ALMOND_PROBE_LIMIT = 120

function Mizuki:ProbeNativeTech2AlmondLaser(laser)
    if tech2AlmondProbeFrames >= TECH2_ALMOND_PROBE_LIMIT
        or laser:GetData().MizukiBeam
    then
        return
    end

    local owner = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
    if not owner and laser.Parent then
        owner = laser.Parent:ToPlayer()
    end
    if not owner then
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
            then
                owner = player
                break
            end
        end
    end
    if not owner
        or not owner:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
        or not owner:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
    then
        return
    end

    local samples = laser:GetNonOptimizedSamples()
    local sampleCount = #samples
    local first = sampleCount > 0 and samples:Get(0) or laser.Position
    local middle = sampleCount > 0
        and samples:Get(math.floor((sampleCount - 1) / 2))
        or laser.Position
    local last = sampleCount > 0
        and samples:Get(sampleCount - 1)
        or laser:GetEndPoint()

    tech2AlmondProbeFrames = tech2AlmondProbeFrames + 1
    Isaac.ConsoleOutput(string.format(
        "[Mizuki Tech2 Almond Probe] global=%d entity=%d seed=%d age=%d flags=%s curve=%.6f angle=%.4f samples=%d first=(%.2f,%.2f) mid=(%.2f,%.2f) last=(%.2f,%.2f)\n",
        Game():GetFrameCount(),
        GetPtrHash(laser),
        laser.InitSeed,
        laser.FrameCount,
        tostring(laser.TearFlags),
        laser.CurveStrength,
        laser.AngleDegrees,
        sampleCount,
        first.X,
        first.Y,
        middle.X,
        middle.Y,
        last.X,
        last.Y
    ))
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_LASER_UPDATE,
    Mizuki.ProbeNativeTech2AlmondLaser
)
