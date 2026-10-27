-- Primary weapon selection and per-player attack dispatch.
local Config = Mizuki.Config

-- Resolve the owning controller independently of native weapon flags. Lower
-- priority items may still provide attacks inside that controller.
function Mizuki.getCannonWeaponMode(player)
    local C = CollectibleType
    if Mizuki.isBerserkClubActive(player) then return "berserk" end
    if player:HasCollectible(C.COLLECTIBLE_C_SECTION) then return "c_section" end
    if player:HasCollectible(C.COLLECTIBLE_SPIRIT_SWORD) then return "spirit_sword" end
    if player:HasCollectible(C.COLLECTIBLE_MOMS_KNIFE) then
        -- Ludovico controls the existing knife/ring combination; it does not
        -- raise Ludovico above C Section, Spirit Sword or active Berserk.
        if player:HasCollectible(C.COLLECTIBLE_LUDOVICO_TECHNIQUE) then return "ludovico" end
        return "knife"
    end
    if player:HasCollectible(C.COLLECTIBLE_TECH_X) then return "tech_x" end
    if player:HasCollectible(C.COLLECTIBLE_LUDOVICO_TECHNIQUE) then return "ludovico" end
    if player:HasCollectible(C.COLLECTIBLE_BRIMSTONE) then return "brimstone" end
    if player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY_ZERO) then return "technology_zero" end
    if player:HasCollectible(C.COLLECTIBLE_TRISAGION) then return "trisagion" end
    return "ordinary"
end

function Mizuki.usesCSectionWeapon(player)
    return Mizuki.getCannonWeaponMode(player) == "c_section"
end

function Mizuki.usesLudovicoWeapon(player)
    return Mizuki.getCannonWeaponMode(player) == "ludovico"
end

function Mizuki.usesCannonSpiritSword(player)
    return player and player:Exists() and not player:IsDead()
        and Mizuki.getCannonWeaponMode(player) == "spirit_sword" or false
end

-- These controllers own a separate damage-bearing weapon. Every other route
-- uses the cannon's beam damage, including the Ludovico + Knife exception.
function Mizuki.usesCannonBeamWeapon(player, mode)
    mode = mode or Mizuki.getCannonWeaponMode(player)
    return mode ~= "berserk" and mode ~= "c_section"
        and mode ~= "spirit_sword" and mode ~= "knife"
end

function Mizuki.canUseTechnologyZeroWeaponEffect(player)
    local mode = Mizuki.getCannonWeaponMode(player)
    return mode == "ordinary" or mode == "trisagion"
        or mode == "technology_zero" or mode == "brimstone"
end

function Mizuki.usesTechnologyZeroBeam(player)
    return Mizuki.getCannonWeaponMode(player) == "technology_zero"
end

-- Tech 0 owns the charge/tick schedule; Trisagion contributes the white
-- native Brimstone shape. Higher weapon controllers retain their own routes.
function Mizuki.usesTechnologyZeroTrisagionBeam(player)
    return Mizuki.usesTechnologyZeroBeam(player)
        and player:HasCollectible(CollectibleType.COLLECTIBLE_TRISAGION)
end

function Mizuki.applyTechnologyZeroTrisagionColor(laser)
    local data = laser:GetData()
    if data.MizukiTechnologyZeroTrisagionBeam ~= true then return end
    local player = data.MizukiBeamOwner
    if not player or not player:Exists() then return end
    laser.Color = Mizuki.getCharacterTearTint(player, 8, laser.Color)
end

-- Sword melee owns its pose and spin charge. This controller only requests
-- the existing cannon shots; it never deploys/freezes either sword.
function Mizuki.getSpiritSwordChargingSide(player, data)
    if Mizuki.hasCannonTech2(player) then return 1 end
    local melee, shooting = data.MizukiSpiritSwordInput, data.MizukiSpiritSwordShooting
    return (melee and melee.Side) or (shooting and shooting.NextSide)
        or Mizuki.getNextCannonFiringSide(player, data)
end

function Mizuki.updateSpiritSwordShooting(player, data, held)
    local state = data.MizukiSpiritSwordShooting or {Charge = 0, Cooldown = 0, Held = false}
    data.MizukiSpiritSwordShooting = state
    local automatic = Mizuki.usesAutomaticBeam(player, true)
    local profile = Mizuki.getChargeProfile(player, false, automatic)
    local charged = not automatic and (Mizuki.usesChargedBeam(player) or Mizuki.usesCannonTechX(player))
    local interval = Mizuki.getFireInterval(player)
    if state.Interval then state.Cooldown = state.Cooldown * interval / state.Interval end
    state.Interval, state.Cooldown = interval, math.max(0, state.Cooldown - 1)
    state.Profile, state.Automatic = profile, automatic
    state.Charge = Mizuki.protectChargeRelease(state, held, state.Charge, not charged)
    local function fire(charge, continuous, volley, forcedSide, spinThrow)
        local melee = data.MizukiSpiritSwordInput
        -- Charged fire belongs to the hand the last slash prepared in front.
        -- A separate ranged alternator selects the opposite/back hand and
        -- drifts again after every release. Only a new slash changes this hand.
        local side = forcedSide or (charged and Mizuki.getSpiritSwordChargingSide(player, data))
            or state.NextSide or Mizuki.getNextCannonFiringSide(player, data)
        if Mizuki.hasCannonTech2(player) then side = 1 end
        local direction = melee and melee.Direction or data.MizukiCannonAim
        local id = Mizuki.fireMizukiBeam(player, direction, charge, continuous, not continuous and side or nil,
            volley, not charged and 1 or nil, nil, nil, nil, true, spinThrow)
        if not charged then state.NextSide = 3 - side end
        state.Charge, state.FullFrames = 0, nil
        Mizuki.protectChargeRelease(state, held, 0, true)
        return id
    end
    local function fireSpinPair(charge, volley)
        local front = Mizuki.getSpiritSwordChargingSide(player, data)
        volley = fire(charge, false, volley, front, true)
        if not Mizuki.hasCannonTech2(player) then
            volley = fire(charge, false, volley, 3 - front, true)
        end
        return volley
    end
    local melee = data.MizukiSpiritSwordInput
    local spinRelease = melee and melee.KnifeSpinRelease
    if spinRelease and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        melee.KnifeSpinRelease = nil
        local charge = profile.MaxFrames
        local count = Mizuki.getCursedEyeShotCount(player, charge, profile)
        state.BurstVolley = fireSpinPair(charge)
        state.BurstCharge, state.BurstRemaining, state.BurstSpinThrow = charge, count - 1, true
    elseif state.BurstRemaining and state.BurstRemaining > 0 then
        if state.BurstSpinThrow then
            state.BurstVolley = fireSpinPair(state.BurstCharge, state.BurstVolley)
        else
            state.BurstVolley = fire(state.BurstCharge, false, state.BurstVolley)
        end
        state.BurstRemaining = state.BurstRemaining - 1
    elseif automatic then
        if held then
            local active = false
            for _, beams in pairs(data.MizukiActiveBeams or {}) do
                for _, beam in ipairs(beams) do
                    if beam.SpiritSwordDriven and beam.Automatic and not beam.Ending
                        and beam.Laser and beam.Laser:Exists() then active = true end
                end
            end
            if not active then fire(profile.MaxFrames, true) end
        end
        state.Charge, state.FullFrames = 0, nil
    elseif not charged then
        if held and state.Cooldown <= 0 then
            fire(profile.BaseFrames, false)
            state.Cooldown = interval
        end
        state.Charge, state.FullFrames = 0, nil
    elseif held then
        state.Charge = math.min(profile.MaxFrames, state.Charge + 1)
        state.FullFrames = state.Charge >= profile.MaxFrames and ((state.FullFrames or 0) + 1) or nil
        if data.MizukiKidneyStoneBurst and state.Charge >= profile.MaxFrames then
            local charge = state.Charge
            local count = Mizuki.getCursedEyeShotCount(player, charge, profile)
            state.BurstVolley = fire(charge, false)
            state.BurstCharge, state.BurstRemaining, state.BurstSpinThrow = charge, count - 1, nil
        end
    elseif state.Held then
        if state.Charge >= profile.MinFrames then
            local charge = state.Charge
            local count = Mizuki.getCursedEyeShotCount(player, charge, profile)
            state.BurstVolley = fire(charge, false)
            state.BurstCharge, state.BurstRemaining, state.BurstSpinThrow = charge, count - 1, nil
        end
    end
    if state.Charge <= 0 then state.FullFrames = nil end
    state.Held = held
end

local function startCursedEyeBurst(
    player, data, direction, charge, profile, forcedSide, finiteVolleyId
)
    local techX = Mizuki.usesCannonTechX(player)
    local shotCount = Mizuki.getCursedEyeShotCount(player, charge, profile)
    -- All shots in the burst retain the original charge's damage. Tech X also
    -- retains its radius; only the primary shot can have a tether.
    local burstDamageMultiplier = Mizuki.getChargeDamageMultiplier(charge, profile)
    finiteVolleyId = Mizuki.fireMizukiBeam(
        player, direction, charge, false, forcedSide, finiteVolleyId, burstDamageMultiplier
    )
    if forcedSide and not techX then
        Mizuki.recordNeptunusFiringSide(data, forcedSide)
    end
    if shotCount > 1 then
        local burst = {
            Remaining = shotCount - 1,
            Direction = Vector(direction.X, direction.Y),
            Charge = (techX or Mizuki.isBerserkClubActive(player)) and charge or profile.BaseFrames,
            DamageMultiplier = burstDamageMultiplier,
            Side = forcedSide or (data.MizukiShotSide == -1 and 1 or 2),
            FiniteVolleyId = finiteVolleyId,
            TechXFreeShots = techX,
        }
        if techX then
            -- Opposite sides may finish charging before an earlier burst ends.
            data.MizukiTechXCursedEyeBursts = data.MizukiTechXCursedEyeBursts or {}
            table.insert(data.MizukiTechXCursedEyeBursts, burst)
        else
            data.MizukiCursedEyeBurst = burst
        end
    end
end

local function updateCursedEyeBurst(player, data)
    local function advance(burst)
        Mizuki.fireMizukiBeam(
            player, burst.Direction, burst.Charge, false, burst.Side,
            burst.FiniteVolleyId, burst.DamageMultiplier, nil, nil, burst.TechXFreeShots
        )
        burst.Remaining = burst.Remaining - 1
    end
    if Mizuki.usesCannonTechX(player) then
        local bursts = data.MizukiTechXCursedEyeBursts
        if not bursts then return false end
        for index = #bursts, 1, -1 do
            advance(bursts[index])
            if bursts[index].Remaining <= 0 then table.remove(bursts, index) end
        end
        if #bursts == 0 then data.MizukiTechXCursedEyeBursts = nil end
        return true
    end
    local burst = data.MizukiCursedEyeBurst
    if not burst then return false end
    advance(burst)
    if burst.Remaining <= 0 then data.MizukiCursedEyeBurst = nil end
    return true
end

-- Each path owns its update flow. Shared shot input below is also used by Knife.
function Mizuki.prepareCannonWeaponUpdate(player, data, mode)
    -- Ludovico converts the stable multishot count into persistent cannon
    -- pairs. Track the actual desired count so pickups, removals and rerolls
    -- refresh the familiar cache even when the item itself has no familiar flag.
    data.MizukiStableShotCount = Mizuki.getStableShotCount(player)
    local expectedCannonPairProfiles = Mizuki.getExpectedCannonPairProfiles(
        player,
        data.MizukiStableShotCount
    )
    data.MizukiExpectedCannonPairProfiles = expectedCannonPairProfiles
    local expectedCannonPairs = #expectedCannonPairProfiles
    if data.MizukiExpectedCannonPairs ~= expectedCannonPairs then
        data.MizukiExpectedCannonPairs = expectedCannonPairs
        data.MizukiRefreshCannonCache = true
    end
    local cacheFlags = data.MizukiRefreshCannonCache and CacheFlag.CACHE_FAMILIARS or 0
    data.MizukiRefreshCannonCache = nil
    local cSectionActive = mode == "c_section"
    if data.MizukiStatCSectionActive ~= cSectionActive then
        cacheFlags = cacheFlags | CacheFlag.CACHE_FAMILIARS
    end
    Mizuki.refreshCharacterStats(player, cacheFlags)
    data.MizukiStatCSectionActive = cSectionActive
    local kidneyStoneBurst = Mizuki.updateKidneyStoneBurst(player, data)
    if data.MizukiSpiritSwordWeaponActive and mode ~= "spirit_sword" then
        Mizuki.clearSpiritSwordInput(data)
        data.MizukiSpiritSwordWeaponActive = nil
    end
    if data.MizukiCSectionWeaponActive and not cSectionActive then
        data.MizukiCSectionWeaponActive = nil
        data.MizukiHasShootingInput = false
    end

    Mizuki.updateCannonReconcile(player, data)
    Mizuki.updateEpicFetusStrikes(player, data)

    if data.MizukiBerserkWeaponActive and mode ~= "berserk" then
        data.MizukiBerserkWeaponActive = nil
        Mizuki.removeActiveMizukiBeams(data)
        Mizuki.clearBerserkClubInput(data)
        data.MizukiHasShootingInput = false
        data.MizukiCannonAim = Vector(0, -1)
    end

    return kidneyStoneBurst
end

function Mizuki.updateCannonBerserkWeapon(player, data)
    if not data.MizukiBerserkWeaponActive then
        Mizuki.removeActiveMizukiBeams(data)
        Mizuki.removeLudovicoRing(data)
        Mizuki.clearBerserkClubInput(data)
        data.MizukiTechXInput = nil
        data.MizukiTechXCursedEyeBursts = nil
        data.MizukiBerserkWeaponActive = true
        data.MizukiCannonAutoFireState = nil
        data.MizukiCannonAutoFirePositions = nil
        data.MizukiCursedEyeBurst = nil
        data.MizukiAutomaticEchoHistory = nil
        Mizuki.resetNeptunusState(data)
    end
    if not player:AreControlsEnabled() then
        Mizuki.updateCannonPositions(player, data)
        return
    end
    local held, aim = Mizuki.getShootingIntent(player, data, true)
    data.MizukiHasShootingInput = held
    if aim then data.MizukiCannonAim, data.MizukiAim = aim, aim end
    Mizuki.updateActiveBeams(player, data, held, aim, Mizuki.usesAutomaticBeam(player, true))
    Mizuki.updateIsaacsTearsCharge(player, data)
    Mizuki.updateCannonPositions(player, data)
    local profile = Mizuki.getChargeProfile(player)
    updateCursedEyeBurst(player, data)
    Mizuki.updateBerserkClubInput(player, data, held, aim, profile,
        function(owner, direction, charge, automatic, side, volley)
            if owner:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE) then
                startCursedEyeBurst(owner, data, direction, charge, profile, side, volley)
            else
                Mizuki.fireMizukiBeam(owner, direction, charge, automatic, side, volley)
            end
        end)
end

function Mizuki.updateCannonCSectionWeapon(player, data)
    -- C Section is a separate weapon owned by Xiaobotu. Retire controller
    -- attacks on entry, then maintain only the independent Tech 2 eye.
    -- Do not advance ordinary cannon charging, deployment or replay.
    local tech2 = Mizuki.hasCannonTech2(player)
    local shooting, direction = Mizuki.getShootingIntent(player, data, false)
    if not data.MizukiCSectionWeaponActive or not tech2 then
        Mizuki.removeActiveMizukiBeams(data)
    else
        Mizuki.updateActiveBeams(player, data, shooting, direction, false)
    end
    data.MizukiTechXInput = nil
    data.MizukiTechXCursedEyeBursts = nil
    Mizuki.removeLudovicoRing(data)
    data.MizukiCSectionWeaponActive = true
    data.MizukiCharge = 0
    data.MizukiChargeBarFullFrames = nil
    data.MizukiCursedEyeBurst = nil
    data.MizukiEpicFetusLudovicoCandidate = nil
    data.MizukiEpicFetusLudovicoGeometry = nil
    data.MizukiDirectBeamCooldown = nil
    data.MizukiDirectBeamInterval = nil
    data.MizukiCannonAutoFireState = nil
    data.MizukiCannonAutoFirePositions = nil
    data.MizukiAutomaticEchoHistory = nil
    data.MizukiHasShootingInput = tech2 and shooting or false
    data.MizukiAim = nil
    data.MizukiCannonAim = tech2 and direction or Vector(0, -1)
    Mizuki.updateAttackPose(data, Game():GetFrameCount(), shooting, direction)
    Mizuki.resetNeptunusState(data)
    Mizuki.updateCannonPositions(player, data)
    data.MizukiHasShootingInput = shooting
    data.MizukiCannonAim = direction or Vector(0, -1)
end

function Mizuki.updateCannonSpiritSwordWeapon(player, data)
    if not data.MizukiSpiritSwordWeaponActive then
        Mizuki.removeActiveMizukiBeams(data)
        Mizuki.removeLudovicoRing(data)
        Mizuki.clearSpiritSwordInput(data)
        data.MizukiSpiritSwordWeaponActive = true
        data.MizukiTechXInput, data.MizukiTechXCursedEyeBursts = nil, nil
        data.MizukiCannonAutoFireState, data.MizukiCannonAutoFirePositions = nil, nil
        data.MizukiCursedEyeBurst = nil
        Mizuki.resetNeptunusState(data)
    end
    if not player:AreControlsEnabled() then
        Mizuki.updateCannonPositions(player, data)
        return
    end
    local held, aim = Mizuki.getShootingIntent(player, data, false)
    data.MizukiHasShootingInput = held
    if aim then data.MizukiCannonAim = aim end
    Mizuki.updateActiveBeams(player, data, held, aim, Mizuki.usesAutomaticBeam(player, true))
    Mizuki.updateCannonPositions(player, data)
    Mizuki.updateSpiritSwordInput(player, data, held, aim, Mizuki.getSpiritSwordChargeProfile(player))
    Mizuki.updateSpiritSwordShooting(player, data, held)
end

function Mizuki.updateCannonTechXWeapon(player, data)
    Mizuki.removeLudovicoRing(data)
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    if not data.MizukiTechXInput then
        data.MizukiCursedEyeBurst = nil
        Mizuki.removeActiveMizukiBeams(data)
        data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
        data.MizukiCannonAutoFireState, data.MizukiCannonAutoFirePositions = nil, nil
        Mizuki.resetNeptunusState(data)
    end
    local held, aim = Mizuki.getShootingIntent(player, data, true)
    local continuous, hideChargeBar = Mizuki.getCannonTechXContinuousMode(player, data)
    Mizuki.updateCannonTechXInput(player, data, held, aim, Mizuki.getChargeProfile(player, true),
        Mizuki.updateActiveBeams, Mizuki.updateCannonPositions, Mizuki.fireMizukiBeam,
        startCursedEyeBurst, updateCursedEyeBurst, continuous, hideChargeBar)
end

function Mizuki.updateCannonLudovicoWeapon(player, data)
    Mizuki.updateLudovicoRing(player, data)
    Mizuki.updateIsaacsTearsCharge(player, data)
    local poseHeld, poseDirection = Mizuki.getShootingIntent(player, data, false)
    Mizuki.updateAttackPose(data, Game():GetFrameCount(), poseHeld, poseDirection)
    data.MizukiTechXInput = nil
    data.MizukiTechXCursedEyeBursts = nil
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
        data.MizukiLudovicoRing
    )
    Mizuki.fireLudovicoTriggeredBeams(player, data)
    Mizuki.updateLudovicoPlayerFacing(player)
end

function Mizuki.updateCannonShotWeapon(player, data, kidneyStoneBurst)
    Mizuki.removeLudovicoRing(data)
    data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
    data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
    if data.MizukiTechXInput then
        Mizuki.removeActiveMizukiBeams(data)
        data.MizukiTechXInput = nil
        data.MizukiTechXCursedEyeBursts = nil
        data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
    end
    Mizuki.updateCannonAutoFireInput(player, data)
    local automatic = Mizuki.usesAutomaticBeam(player)
    local chargedBeam = not automatic and Mizuki.usesChargedBeam(player)
    local chargeProfile = Mizuki.getChargeProfile(player)
    local shootingDirection
    data.MizukiHasShootingInput, shootingDirection =
        Mizuki.getShootingIntent(
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
    local targetAiming = Mizuki.getTargetReticle(player, data) ~= nil
    local activeSides, cannonFiringSides = Mizuki.updateActiveBeams(
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
    local continuingHeldPose = Mizuki.isAttackPoseHeld(data)
        and shootingDirection ~= nil and data.MizukiCannonAim ~= nil
        and (shootingDirection:Normalized() - data.MizukiCannonAim:Normalized()):LengthSquared()
            < Mizuki.RuntimeParameters.DirectionMatchSquaredEpsilon
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
        and not continuingHeldPose
    data.MizukiDirectAimActive = directAimActive
    Mizuki.updateCannonPositions(player, data, returnAim)
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
        Mizuki.protectChargeRelease(data, false, 0, true)

        local interval = Mizuki.getFireInterval(player)
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
            Mizuki.fireMizukiBeam(
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

        return
    end

    data.MizukiDirectBeamCooldown = nil
    data.MizukiDirectBeamInterval = nil

    if automatic and activeSides >= (Mizuki.hasCannonTech2(player) and 1 or 2) then
        data.MizukiCharge = 0
        data.MizukiNeptunusHeldFrames = nil
        data.MizukiAim = nil
        data.MizukiChargeBarFullFrames = nil
        return
    end

    if data.MizukiHasShootingInput then
        data.MizukiCharge = Mizuki.protectChargeRelease(data, true, data.MizukiCharge or 0)
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
                Mizuki.updateCannonPositions(
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
                Mizuki.fireMizukiBeam(
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
    local releasedCharge = false
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
            Mizuki.fireMizukiBeam(player, data.MizukiAim, charge)
        end
        if neptunusEnabled then
            Mizuki.spendNeptunusCharge(data, charge)
        end
        releasedCharge = true
    end

    data.MizukiCharge = Mizuki.protectChargeRelease(data, false, charge, releasedCharge)
    if data.MizukiCharge > 0 then return end
    data.MizukiNeptunusHeldFrames = nil
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
    if data.MizukiCursedEyeBurst then
        data.MizukiCannonAim = Vector(
            data.MizukiCursedEyeBurst.Direction.X,
            data.MizukiCursedEyeBurst.Direction.Y
        )

    end
end

-- Knife, Brimstone, Tech 0, Trisagion and ordinary beams share shot input.
-- Only controllers with a distinct update flow need an entry here.
local WeaponUpdaters = {
    berserk = Mizuki.updateCannonBerserkWeapon,
    c_section = Mizuki.updateCannonCSectionWeapon,
    spirit_sword = Mizuki.updateCannonSpiritSwordWeapon,
    tech_x = Mizuki.updateCannonTechXWeapon,
    ludovico = Mizuki.updateCannonLudovicoWeapon,
}

function Mizuki:UpdateWeapon(player)
    if not Mizuki.isMizuki(player) then
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
        Mizuki.updateCannonPositions(player, data)
        return
    end

    local mode = Mizuki.getCannonWeaponMode(player)
    local kidneyStoneBurst = Mizuki.prepareCannonWeaponUpdate(player, data, mode)

    local update = WeaponUpdaters[mode] or Mizuki.updateCannonShotWeapon
    return update(player, data, kidneyStoneBurst)
end

function Mizuki:TriggerEpicFetusStrike(entity, amount, damageFlags, source)
    local enemy = entity:ToNPC()
    if amount <= 0 or not enemy
        or not enemy:IsActiveEnemy(false)
        or enemy:IsDead()
        or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return
    end

    local attack, player = Mizuki.resolveEpicFetusAttack(source, damageFlags, false, enemy)
    if not player or not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS) then return end

    local data = player:GetData()
    local ludovicoFromCannon = Mizuki.getLudovicoEpicFetusSource(
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

    if not Mizuki.canStartEpicFetusStrike(data) then return end

    -- Enemy damage wins over any grid candidate collected during this frame.
    data.MizukiEpicFetusGridCandidate = nil
    Mizuki.startEpicFetusStrike(
        player,
        enemy,
        Vector(enemy.Position.X, enemy.Position.Y)
    )
end

function Mizuki:TriggerCursedEyeTeleport(entity)
    local player = entity:ToPlayer()
    if not player
        or not Mizuki.isMizuki(player)
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_CURSED_EYE)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_BLACK_CANDLE)
        or Mizuki.usesAutomaticBeam(player)
    then
        return
    end

    local data = player:GetData()
    local sword = Mizuki.usesCannonSpiritSword(player)
    local ranged = sword and data.MizukiSpiritSwordShooting
    if sword and (not ranged or ranged.Automatic) then return end
    local charge = sword and ranged.Charge or (data.MizukiCharge or 0)
    local profile = sword and ranged.Profile or Mizuki.getChargeProfile(player)
    if charge <= 0 or charge >= profile.MaxFrames then
        return
    end

    data.MizukiCharge = 0
    data.MizukiNeptunusHeldFrames = nil
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
    data.MizukiCursedEyeBurst = nil
    data.MizukiTechXCursedEyeBursts = nil
    if ranged then
        ranged.Charge, ranged.FullFrames = 0, nil
        ranged.BurstRemaining, ranged.BurstVolley, ranged.BurstSpinThrow = nil, nil, nil
        Mizuki.protectChargeRelease(ranged, false, 0, true)
    end

    local rng = player:GetCollectibleRNG(
        CollectibleType.COLLECTIBLE_CURSED_EYE
    )
    -- MC_ENTITY_TAKE_DMG runs before the native hurt state is completely
    -- applied. Starting the transition here lets the remainder of that state
    -- delay it until the hurt animation ends. Defer only to this frame's final
    -- update, after damage processing, to match Cursed Eye's immediate timing.
    data.MizukiPendingCursedEyeTeleportSeed = rng:Next()
end

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
