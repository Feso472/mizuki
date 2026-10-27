-- Native beam creation, volleys, damage timing and attack updates.
local Config = Mizuki.Config

function Mizuki.resolveBeamGeometry(
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

-- Like Azazel's mini-Brimstone, the beam starts short but Range ups extend it.
-- At Mizuki's starting HUD Range 6.50 (internal TearRange 260), its length is exactly 240 px.
function Mizuki.getBeamDistance(player)
    -- Technology and Brimstone lift the cannon beam's range limit. Zero is
    -- the native "do not trim" MaxDistance sentinel.
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then
        return 0
    end

    return math.max(Mizuki.WeaponParameters.MinBeamDistance, Config.BEAM_DISTANCE * player.TearRange / Config.BASE_TEAR_RANGE)
end

-- Convert the final ShotSpeed stat into real beam thickness. At the normal
-- 1.0 stat the laser keeps its native width; at 2.0 it reaches exactly 3x,
-- then approaches (but never exceeds) 5x for extreme combinations.
function Mizuki.getBeamWidthScale(player)
    local shotSpeedOffset = player.ShotSpeed - 1
    local widthScale = 1
        + (Config.MAX_BEAM_WIDTH_SCALE - 1)
        * (2 / math.pi)
        * math.atan(shotSpeedOffset)
    return math.max(widthScale, Config.MIN_BEAM_WIDTH_SCALE)
end

-- Finite beams live exactly as long as their tick count needs. ShotSpeed still
-- controls their width, but no longer reduces hit count or proc opportunities.
function Mizuki.getBrimstoneBeamDuration(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_TRISAGION)
        and Config.TRISAGION_BRIMSTONE_BEAM_DURATION or Config.BRIMSTONE_BEAM_DURATION
end

function Mizuki.getBeamDamageTiming(
    player,
    automatic,
    brimstone,
    technologyZero,
    brimstoneDuration
)
    brimstoneDuration = brimstoneDuration or Mizuki.getBrimstoneBeamDuration(player)
    if automatic then
        -- FireTechLaser/FireBrimstone create the native laser entity but do not
        -- run vanilla's high-Tears weapon controller for this custom mode, so
        -- pass that controller's final-Tears multiplier into the firing API.
        local duration = brimstone
            and brimstoneDuration
            or Config.DEFAULT_BEAM_DURATION
        return duration,
            Mizuki.getDisplayedFireRate(player)
                / Config.AUTOMATIC_BEAM_FIRE_RATE_DAMAGE_DIVISOR
    end

    if brimstone then
        return brimstoneDuration, Config.BRIMSTONE_BEAM_TOTAL_DAMAGE_MULTIPLIER
            / Config.BRIMSTONE_BEAM_TICK_COUNT
    end

    if technologyZero then
        return Config.TECHNOLOGY_ZERO_BEAM_DURATION,
            Config.TECHNOLOGY_ZERO_BEAM_TOTAL_DAMAGE_MULTIPLIER
                / Config.TECHNOLOGY_ZERO_BEAM_TICK_COUNT
    end

    return Config.DEFAULT_BEAM_DURATION,
        Config.DEFAULT_BEAM_TOTAL_DAMAGE_MULTIPLIER / Config.DEFAULT_BEAM_TICK_COUNT
end

function Mizuki.getBeamEndFrames(brimstone)
    return brimstone
        and Config.BRIMSTONE_BEAM_END_FRAMES
        or Config.TECHNOLOGY_BEAM_END_FRAMES
end

function Mizuki.getCollectibleFamiliarCount(player, collectible)
    return player:GetCollectibleNum(collectible)
        + player:GetEffects():GetCollectibleEffectNum(collectible)
end

-- Resolve the deterministic part of Mizuki's multishot layout once so normal
-- firing and Ludovico cannon pairs cannot drift into separate item formulas.
-- bonusGlassesCount is reserved for per-shot effects such as Book Worm; callers
-- which manage persistent entities pass zero and therefore never consume RNG.
local function getMizukiStandardBeamProfile(player, bonusGlassesCount, techXVolley)
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
    local duplicateShots = 0
    for _, item in ipairs(Config.DUPLICATE_MULTISHOT_ITEMS) do
        duplicateShots = duplicateShots
            + math.max(0, player:GetCollectibleNum(item) - 1)
    end
    local extraLungs = not techXVolley and math.max(0, player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG
    ) - 1) or 0
    standardCount = standardCount + duplicateShots
        + extraLungs * Mizuki.WeaponParameters.LungExtraBaseShotsPerCopy
    if glassesCount > 0 then
        standardCount = standardCount + glassesCount
        if hasEyeSpread then
            standardCount = standardCount - 1
        end
    end

    local totalSpread = 0
    if hasEyeSpread then
        totalSpread = (preGlassesCount - 1)
            * Config.LINE_MULTISHOT_BASE_SPREAD
            * Config.LINE_MULTISHOT_SPREAD_FACTOR
    end
    totalSpread = totalSpread
        + glassesCount * Config.LINE_MULTISHOT_GLASSES_SPREAD
        + duplicateShots * Config.DUPLICATE_WEAPON_SPREAD
        + extraLungs * Config.DUPLICATE_LUNG_SPREAD
        + wizCount * Config.WIZ_GROUP_SPREAD

    local wizGroups = math.min(wizCount + 1, Config.MAX_WIZ_GROUPS)
    if wizCount > 0 then
        -- Native order: add Wiz copies, round up to whole direction groups,
        -- then include Conjoined, cap the total and divide between the groups.
        standardCount = math.ceil((standardCount + wizCount) / wizGroups)
            * wizGroups
    end
    local conjoined = player:HasPlayerForm(PlayerForm.PLAYERFORM_BABY)
    if conjoined then standardCount = standardCount + 2 end
    local beamsPerWizGroup = math.floor(
        math.min(standardCount, Config.MAX_STANDARD_MULTISHOT) / wizGroups
    )
    return {
        WizGroups = wizGroups,
        BeamsPerWizGroup = beamsPerWizGroup,
        TotalSpread = math.min(totalSpread, 90),
        BeamCount = wizGroups * beamsPerWizGroup,
        ConjoinedSideShots = conjoined and wizCount == 0,
    }
end

function Mizuki.getStableShotCount(player)
    local profile = getMizukiStandardBeamProfile(player, 0)
    return profile.BeamCount
end

-- Hand a finished beam back to EntityLaser for its native narrowing animation
-- instead of deleting it on the last full-width frame. Only the visual state
-- changes: damage, flags, color, cadence-based synergies and firing occupancy
-- continue until the entity disappears. A returned knife releases its cannon
-- during this tail, while the laser itself stays at its firing origin.
function Mizuki.beginNaturalMizukiBeamEnding(beam)
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

function Mizuki.removeActiveMizukiBeams(data)
    for side = 1, 2 do
        for _, beam in ipairs(
            data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}
        ) do
            Mizuki.cancelCannonTechX(beam)
            Mizuki.cancelCannonKnifeBeam(beam)
            local laser = beam.Laser
            if laser and laser:Exists() and laser:GetData().MizukiBeam == true then
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
    if beam.PersistentEchoMode == "automatic" or beam.Technology2Proc or beam.SpiritSwordDriven then return end
    local damageFrame = laser.FrameCount % Config.BEAM_DAMAGE_INTERVAL == 0
    if not damageFrame then
        return
    end

    local currentFrame = Game():GetFrameCount()
    if data.MizukiExtraAttackFrame ~= currentFrame then
        local attackDirection = shootingDirection
            or beam.Direction:Rotated(-(beam.DirectionOffset or 0))
        Mizuki.tryFireImmaculateHeartTear(player, attackDirection)
        Mizuki.recordExtraAttack(player, attackDirection)
        data.MizukiExtraAttackFrame = currentFrame
    end
end

function Mizuki.updateActiveBeams(
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
                if beam.Technology2 and not beam.Ending then
                    -- The independent right-eye controller owns its lifetime.
                    -- Resolve aim before the common following-pose pass below.
                    if shootingDirection then
                        beam.Direction = shootingDirection:Rotated(beam.DirectionOffset or 0)
                    end
                elseif beam.Ending then
                    if not laser or not laser:Exists() then
                        if not Mizuki.isCannonKnifeAttackActive(beam) then
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
                elseif beam.TechXDriven then
                    Mizuki.updateCannonTechXBeam(beam, beamShootingHeld)
                    if beam.TechXReleased and not beam.TechXLinked then
                        table.remove(beams, index)
                    end
                elseif beam.MomKnifeDriven then
                    if Mizuki.shouldHoldCannonKnifeBeam
                        and Mizuki.shouldHoldCannonKnifeBeam(beam)
                    then
                        local activeDuration = beam.ActiveDuration
                            or math.max(
                                1,
                                (beam.TotalDuration or Config.DEFAULT_BEAM_DURATION)
                                    - (beam.EndFrames
                                        or Config.TECHNOLOGY_BEAM_END_FRAMES)
                            )
                        beam.Timeout = activeDuration
                        if laser and laser:Exists() then
                            laser.Timeout = activeDuration
                        end
                    else
                        -- Keep the native shrinking tail at its firing origin.
                        -- The knife has finished, so only the beam remains.
                        Mizuki.beginNaturalMizukiBeamEnding(beam)
                    end
                elseif beam.Automatic and automaticMode and beamShootingHeld then
                    -- Refresh only the full-width portion. The variant's native
                    -- 3 / 10-frame ending is reserved outside this countdown.
                    local activeDuration = beam.ActiveDuration
                        or math.max(
                            1,
                            (beam.TotalDuration or Config.DEFAULT_BEAM_DURATION)
                                - (beam.EndFrames
                                    or Config.TECHNOLOGY_BEAM_END_FRAMES)
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
                if beam.TechXDriven and beam.TechXReleased and not beam.TechXLinked then
                    -- Native free-flight ring no longer occupies this cannon.
                elseif not beam.Ending and (not laser or not laser:Exists()) then
                    table.remove(beams, index)
                elseif not beam.Ending and beam.Timeout <= 0 then
                    Mizuki.beginNaturalMizukiBeamEnding(beam)
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
                local occupiesSide = false
                local holdsCannonPosition = false
                for _, beam in ipairs(beams) do
                    if beam.PersistentEchoMode ~= "automatic" and not beam.Technology2 then
                        -- An echo's delayed tail never occupies a real cannon
                        -- or postpones the player's next automatic volley.
                        occupiesSide = true
                        if not (beam.MomKnifeDriven and beam.Ending) then
                            holdsCannonPosition = true
                        end
                    end
                end
                if occupiesSide then
                    activeSides = activeSides + 1
                    cannonFiringSides = cannonFiringSides + 1
                end
                if not holdsCannonPosition then
                    -- The laser tail stays at the old firing point, while the
                    -- returned knife and cannon can follow the player again.
                    data.MizukiLockedCannonPositions[side] = nil
                    data.MizukiLockedCannonAims[side] = nil
                end
            end
        end
    end
    return activeSides, cannonFiringSides
end

function Mizuki.hasActiveMizukiBeam(data)
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
function Mizuki.getMizukiTransientBeamEffects(player, blockedSources, fetusVolley)
    local effects = {
        BookWormBonus = 0,
        Sources = {},
    }
    blockedSources = blockedSources or {}

    if not blockedSources[Config.TRANSIENT_BEAM_SOURCE_BOOK_WORM]
        and player:HasPlayerForm(PlayerForm.PLAYERFORM_BOOK_WORM)
        and player:GetDropRNG():RandomFloat() < Mizuki.WeaponParameters.BookWormBonusChance
    then
        effects.BookWormBonus = 1
        effects.Sources[Config.TRANSIENT_BEAM_SOURCE_BOOK_WORM] = { 0 }
    end

    local momsEye = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_EYE)
    local lokisHorns = player:HasCollectible(
        CollectibleType.COLLECTIBLE_LOKIS_HORNS
    )
    if momsEye and not blockedSources[Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE] then
        local chance = math.max(0, math.min(1, Mizuki.WeaponParameters.MomsEyeBaseChance + player.Luck * Mizuki.WeaponParameters.MomsEyeLuckStep))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MOMS_EYE
        ):RandomFloat() < chance then
            local angles = { 180 }
            if lokisHorns then
                table.insert(angles, -90)
                table.insert(angles, 90)
            end
            effects.Sources[Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE] = angles
        end
    end
    if lokisHorns
        and not blockedSources[Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS]
    then
        local chance = math.max(0, math.min(1, Mizuki.WeaponParameters.LokisHornsBaseChance + player.Luck * Mizuki.WeaponParameters.LokisHornsLuckStep))
        if player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_LOKIS_HORNS
        ):RandomFloat() < chance then
            -- Ordinary fire already owns its forward beam. Ludovico has no
            -- equivalent transient shot, so retain 0 degrees in the source and
            -- let the ordinary layout skip it below.
            effects.Sources[Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS] = {
                0,
                180,
                -90,
                90,
            }
        end
    end

    if not blockedSources[Config.TRANSIENT_BEAM_SOURCE_EYE_SORE]
        and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_SORE)
    then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_EYE_SORE
        )
        local angles = {}
        local countBound = Mizuki.WeaponParameters.EyeSoreCountBound
        local extraCount = rng:RandomInt(countBound)
        if fetusVolley then
            -- Native C Section: two independent 0..3 draws, minus three.
            extraCount = math.max(0, extraCount + rng:RandomInt(countBound) - (countBound - 1))
        end
        for _ = 1, extraCount do
            local angle = rng:RandomFloat()
            if fetusVolley then
                angle = (angle * 2 - 1) * Mizuki.WeaponParameters.EyeSoreFetusHalfAngle
            else
                angle = angle * 360
            end
            table.insert(angles, angle)
        end
        if #angles > 0 then
            effects.Sources[Config.TRANSIENT_BEAM_SOURCE_EYE_SORE] = angles
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

-- Shared scatter only; callers retain their own base/directional volley rolls.
function Mizuki.appendLungVolleyAngles(player, angles, damageMultipliers, techXVolley)
    local lungCount = player:GetCollectibleNum(
        CollectibleType.COLLECTIBLE_MONSTROS_LUNG
    )
    if lungCount > 0 then
        local rng = player:GetCollectibleRNG(
            CollectibleType.COLLECTIBLE_MONSTROS_LUNG
        )
        local minExtra = Mizuki.WeaponParameters.LungMinExtraBeams
        local maxExtra = Mizuki.WeaponParameters.LungMaxExtraBeams
        if techXVolley then
            -- Tech X rolls 3–5 extra rings per Lung copy. Copy bonuses are
            -- excluded from the base layout above to avoid adding them twice.
            for _ = 1, lungCount do
                local extraCount = minExtra + rng:RandomInt(maxExtra - minExtra + 1)
                for _ = 1, extraCount do
                    table.insert(angles, (rng:RandomFloat() - 0.5) * 30)
                    damageMultipliers[#angles] = 0.5 + rng:RandomFloat() * 0.5
                end
            end
        else
            -- Other weapons retain the established first-Lung scatter; their
            -- additional copies already enter the shared base profile.
            local extraCount = minExtra + rng:RandomInt(maxExtra - minExtra + 1)
            for _ = 1, extraCount do
                table.insert(angles, rng:RandomFloat() * 360)
            end
        end
    end

end

local function getMizukiBeamAngleOffsets(player, fetusVolley, techXVolley, nativeLungVolley)
    local transientEffects = Mizuki.getMizukiTransientBeamEffects(player, nil, fetusVolley)
    local profile = getMizukiStandardBeamProfile(
        player,
        transientEffects.BookWormBonus,
        techXVolley
    )

    local angles, damageMultipliers = {}, {}
    for group = 1, profile.WizGroups do
        local center = 0
        if profile.WizGroups > 1 then
            center = -Config.WIZ_ARC_HALF_ANGLE
                + (group - 1) * (Config.WIZ_ARC_HALF_ANGLE * 2)
                    / (profile.WizGroups - 1)
        end
        Mizuki.appendCenteredBeamAngles(
            angles,
            center,
            profile.BeamsPerWizGroup - (profile.ConjoinedSideShots and 2 or 0),
            profile.TotalSpread
        )
    end

    if profile.ConjoinedSideShots then
        table.insert(angles, -Config.CONJOINED_SIDE_ANGLE)
        table.insert(angles, Config.CONJOINED_SIDE_ANGLE)
    end

    for _, source in ipairs({
        Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE,
        Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS,
        Config.TRANSIENT_BEAM_SOURCE_EYE_SORE,
    }) do
        for index, angleOffset in ipairs(
            transientEffects.Sources[source] or {}
        ) do
            -- Loki's Horns owns a forward direction in Ludovico. Ordinary fire
            -- already contains that shot in its stable layout.
            if source ~= Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS or index > 1 then
                if fetusVolley and source == Config.TRANSIENT_BEAM_SOURCE_EYE_SORE then
                    -- Each rolled fetus survives even if its angle coincides
                    -- with another shot. The Wiz only rotates the stable groups.
                    table.insert(angles, angleOffset)
                else
                    appendUniqueBeamAngle(angles, angleOffset)
                end
            end
        end
    end

    if not nativeLungVolley then
        Mizuki.appendLungVolleyAngles(player, angles, damageMultipliers, techXVolley)
    end

    return angles, damageMultipliers
end

-- The fan uses the same volley layout and rolls transient multishot once.
Mizuki.getMizukiBeamAngleOffsets = getMizukiBeamAngleOffsets

-- Sword multishot adds revolutions, whereas transient direction procs add
-- actual swords. Roll those procs once for the entire swing, not per hand.
function Mizuki.getSpiritSwordVolley(player)
    local effects = Mizuki.getMizukiTransientBeamEffects(player)
    local profile = getMizukiStandardBeamProfile(player, effects.BookWormBonus)
    local angles = {0}
    for _, source in ipairs({Config.TRANSIENT_BEAM_SOURCE_MOMS_EYE,
        Config.TRANSIENT_BEAM_SOURCE_LOKIS_HORNS, Config.TRANSIENT_BEAM_SOURCE_EYE_SORE}) do
        for _, angle in ipairs(effects.Sources[source] or {}) do
            appendUniqueBeamAngle(angles, angle)
        end
    end
    return angles, math.max(1, profile.BeamCount)
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
                Mizuki.cancelCannonTechX(beam)
                Mizuki.cancelCannonKnifeBeam(beam)
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
    widthScale,
    technologyZeroTrisagion
)
    if technologyZeroTrisagion or player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        local brimstoneMultiplier = Mizuki.getSecondaryBrimstoneDamageMultiplier(player)
        damageMultiplier = (damageMultiplier or 1) * brimstoneMultiplier
        local nativeLaser = player:FireBrimstone(
            direction,
            player,
            damageMultiplier
        )
        nativeLaser:GetData().MizukiBrimstoneDamageMultiplier = brimstoneMultiplier

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
        thickerData.MizukiBrimstoneDamageMultiplier = brimstoneMultiplier
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

-- One native creation/initialization path for originals and delayed echoes.
-- Parameters describe the firing request, not a hand-built copy of native item
-- properties. FireTechLaser/FireBrimstone own curvature, homing and collision.
function Mizuki.createCannonBeam(player, parameters)
    if parameters.TechXPartial or parameters.TechXRingOnly then
        return Mizuki.createCannonTechXRing(player, parameters)
    end
    local laser
    if parameters.Technology2Proc then
        -- Native Tech 2's Mom's Eye/Loki shots use the Mom's Eye offset and
        -- one-hit laser, independently of the primary weapon (even Brimstone).
        laser = player:FireTechLaser(parameters.Origin, LaserOffset.LASER_MOMS_EYE_OFFSET,
            parameters.Direction, false, true, player, parameters.DamageMultiplier)
    elseif parameters.Technology2 then
        laser = player:FireTechLaser(parameters.Origin, LaserOffset.LASER_TECH2_OFFSET,
            parameters.Direction, false, false, player, 1)
        -- TECH2_OFFSET ignores the API damage multiplier. Its native damage
        -- already contains Tech 2's reduction; apply only familiar/echo scaling.
        local nativeDamage = laser.CollisionDamage
        local factor = parameters.DamageMultiplier or 1
        laser.CollisionDamage = nativeDamage * factor
        local ld = laser:GetData()
        ld.MizukiRecoverBeamDamageMultiplier = factor
        ld.MizukiTechnology2Beam = true
    else
        laser = fireMizukiWeaponBeam(
            player, parameters.Origin, parameters.Direction, parameters.LeftEye,
            parameters.DamageMultiplier, parameters.WidthScale, parameters.TechnologyZeroTrisagion
        )
    end
    if parameters.Technology2Eye then
        -- FireTechLaser explicitly disables following at native creation.
        -- Re-enable it with the player parent; preserve the API's eye offset.
        laser.Parent = player
        laser.DisableFollowParent = false
    else
        laser.DisableFollowParent = true
        if parameters.Parent then laser.Parent = parameters.Parent end
        laser.Position = parameters.Origin
        laser.PositionOffset = parameters.PositionOffset
        local reflectionDepthShift = Mizuki.applyBeamReflectionHeight(player, laser)
        laser.Velocity = Vector.Zero
        laser.DepthOffset = parameters.DepthOffset - reflectionDepthShift
    end
    laser.Timeout = parameters.ActiveDuration
    laser:SetOneHit(parameters.Technology2Proc == true)
    laser:SetMaxDistance(parameters.Distance)
    laser.TearFlags = Mizuki.addOccultHoming(player, laser.TearFlags)
        & ~Config.MIZUKI_FORBIDDEN_TEAR_FLAGS
    local laserData = laser:GetData()
    laserData.MizukiBeam = true
    laserData.MizukiBeamOwner = player
    laserData.MizukiBeamWidthScale = parameters.WidthScale
    laserData.MizukiBeamAutomatic = parameters.Automatic
    laserData.MizukiTechnologyZeroTrisagionBeam = parameters.TechnologyZeroTrisagion == true
    Mizuki.applyTechnologyZeroTrisagionColor(laser)
    if laserData.MizukiRecoverBeamDamageMultiplier then
        laserData.MizukiAwaitingNativeDamageRefresh = true
        laserData.MizukiLastAdjustedCollisionDamage = laser.CollisionDamage
    end
    return laser
end

-- Shared muzzle geometry for independent native laser factories (Tech 2/.5).
function Mizuki.getCannonLaserGeometry(player, cannon, direction, directionOffset, targetPosition, exactAim)
    local cd = cannon:GetData()
    local origin = cd.MizukiDesiredPosition or cannon.Position
    local visual = origin + Mizuki.getCannonBeamPivotRenderOffset(player, cd)
    local target = not exactAim and Mizuki.getTargetReticle(player, player:GetData())
    local aim, correction = Mizuki.resolveBeamGeometry(visual, direction, directionOffset or 0,
        targetPosition or (target and target.Position or nil))
    local hitboxOffset = Vector(0, Config.BEAM_HITBOX_Y_OFFSET)
    return {
        Origin = visual + hitboxOffset + correction, Direction = aim,
        PositionOffset = -hitboxOffset,
        DepthOffset = cannon.DepthOffset - Mizuki.WeaponParameters.BeamDepthBehindCannon
            - hitboxOffset.Y - correction.Y,
    }
end

function Mizuki.syncSpiritSwordBeam(beam)
    local cannon, laser = beam.Cannon, beam.Laser
    if not beam.SpiritSwordDriven or not cannon or not cannon:Exists()
        or not laser or not laser:Exists() or not Mizuki.renderCannonSpiritSword(cannon) then return end
    local cd, player = cannon:GetData(), cannon.Player
    local direction = cd.MizukiCannonAim
    if not direction then return end
    local geometry = Mizuki.getCannonLaserGeometry(player, cannon, direction, beam.DirectionOffset, nil, true)
    beam.Direction, beam.Origin = geometry.Direction, Vector(cannon.Position.X, cannon.Position.Y)
    Mizuki.syncSpiritSwordKnifeAim(beam.MomKnife, beam)
    if not beam.TechXDriven then laser.AngleDegrees = geometry.Direction:GetAngleDegrees() end
    local hiltOrigin = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        and Mizuki.getSpiritSwordKnifeBeamOrigin(cannon)
    if hiltOrigin then
        -- Keep the native knife's launch-distance clock; the added span belongs
        -- to this SAME laser, between the hilt and the former firing origin.
        beam.SpiritSwordKnifeFromHilt = true
        beam.SpiritSwordKnifeLaunchDistance = (geometry.Origin + geometry.PositionOffset - hiltOrigin):Length()
        local hitboxOrigin = hiltOrigin - geometry.PositionOffset
        geometry.DepthOffset = geometry.DepthOffset + geometry.Origin.Y - hitboxOrigin.Y
        geometry.Origin = hitboxOrigin
    else
        beam.SpiritSwordKnifeFromHilt, beam.SpiritSwordKnifeLaunchDistance = nil, nil
    end
    laser.Position, laser.PositionOffset = geometry.Origin, geometry.PositionOffset
    laser.Velocity = Vector(cannon.Velocity.X, cannon.Velocity.Y)
    laser.DepthOffset = geometry.DepthOffset - Mizuki.applyBeamReflectionHeight(player, laser)
end

function Mizuki.prepareTech5CannonShot(player, cannon, direction, target)
    if Mizuki.usesCSectionWeapon(player) then
        cannon:GetData().MizukiTech5AttackPose = {
            Direction = direction, PositionAim = direction, TargetPosition = target,
            EndFrame = Game():GetFrameCount() + Mizuki.WeaponParameters.Tech5.ActiveFrames + Config.TECHNOLOGY_BEAM_END_FRAMES,
        }
        -- The regular layout owns position, pose and depth. Update only this
        -- cannon immediately, then let it follow the player during the pose.
        Mizuki.updateCannonPositions(player, player:GetData(), nil, cannon.SubType, cannon)
    end
    return Mizuki.getCannonLaserGeometry(player, cannon, direction, 0, target)
end

function Mizuki.getCannonTech2Parameters(player, cannon, direction, multiplier, directionOffset)
    local parameters
    if cannon then
        parameters = Mizuki.getCannonLaserGeometry(player, cannon, direction, directionOffset)
        parameters.Parent = cannon
    else
        parameters = {Origin = player.Position, Direction = direction:Rotated(directionOffset or 0),
            Technology2Eye = true}
    end
    parameters.LeftEye, parameters.DamageMultiplier, parameters.WidthScale = false, multiplier, 1
    parameters.ActiveDuration, parameters.Distance, parameters.Automatic = 2, 0, true
    parameters.Technology2 = true
    return parameters
end

-- Shared by the charge display and independent attacks selecting a free cannon.
function Mizuki.getNextCannonFiringSide(player, data)
    local nextShotSide = Mizuki.hasCannonTech2(player)
        and -1 or -(data.MizukiShotSide or -1)
    local side = nextShotSide == -1 and 1 or 2
    if Mizuki.isBerserkClubActive(player) and data.MizukiBerserkInput then
        side = data.MizukiBerserkInput.Side or side
    elseif data.MizukiTechXInput then
        side = data.MizukiTechXInput.Side or side
    end
    return side
end

function Mizuki.fireMizukiBeam(
    player,
    direction,
    charge,
    automatic,
    forcedSide,
    finiteVolleyId,
    damageMultiplierOverride,
    echoOnlyAngles,
    echoAttack,
    techXFreeShot,
    swordDriven,
    swordSpinThrow
)
    if Mizuki.usesCSectionWeapon(player) then return end
    local data = player:GetData()
    if echoOnlyAngles and forcedSide == 2 and Mizuki.hasCannonTech2
        and Mizuki.hasCannonTech2(player) then return end
    local deployedAutoFire = data.MizukiCannonAutoFireState == "deployed"
    local chargeProfile = Mizuki.getChargeProfile(player, false, swordDriven and automatic or nil)
    local isFiniteShot = not automatic
    local techX = Mizuki.usesCannonTechX(player)
    local trisagion = not techX and Mizuki.usesCannonTrisagion(player)
    if trisagion and echoOnlyAngles then return end
    if trisagion and automatic and Game():GetFrameCount() < (data.MizukiTrisagionNextShot or 0) then return end
    local techXShotFired = false
    local trisagionShotFired = false
    local boneWeaponVariant = Mizuki.isBerserkClubActive(player)
        and Mizuki.getCannonKnifeWeaponVariant(player)
    local lungScatterKind = boneWeaponVariant
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
        and Mizuki.getBerserkLungScatterKind(boneWeaponVariant)
    local boneLung = lungScatterKind == "bone"
    local techXContinuous = techX and data.MizukiTechXInput and data.MizukiTechXInput.Continuous
    local techXLinked = techX and not techXFreeShot and charge >= chargeProfile.MaxFrames
    local followCannon = swordDriven or automatic or techXContinuous
        -- The firing head keeps orbiting. Keep finite beams attached as well,
        -- while their recorded firing direction/appearance stays locked.
        or (not deployedAutoFire and data.MizukiGuillotinePrimaryHead ~= nil)
        or (isFiniteShot and Mizuki.shouldAntiGravityFollow(player))
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
    if Mizuki.hasCannonTech2(player) then
        firingSides = { 1 }
    elseif forcedSide then
        firingSides = { forcedSide }
    elseif automatic then
        firingSides = { 1, 2 }
    else
        data.MizukiShotSide = -(data.MizukiShotSide or -1)
        firingSides = { data.MizukiShotSide == -1 and 1 or 2 }
    end

    if isFiniteShot and not trisagion and not techXFreeShot and not techXContinuous then
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

    local beamDistance = techX and math.max(Mizuki.WeaponParameters.MinBeamDistance,
        Config.BEAM_DISTANCE * player.TearRange / Config.BASE_TEAR_RANGE) or Mizuki.getBeamDistance(player)
    local beamWidthScale = Mizuki.getBeamWidthScale(player)
    local isBrimstoneBeam = player:HasCollectible(
        CollectibleType.COLLECTIBLE_BRIMSTONE
    )
    local isTechnologyZeroBeam = Mizuki.usesTechnologyZeroBeam(player)
    local technologyZeroTrisagion = Mizuki.usesTechnologyZeroTrisagionBeam(player)
    local beamDuration, damagePerTickMultiplier =
        Mizuki.getBeamDamageTiming(
            player,
            automatic,
            isBrimstoneBeam,
            isTechnologyZeroBeam,
            Mizuki.getBrimstoneBeamDuration(player)
        )
    if technologyZeroTrisagion and automatic then beamDuration = Config.TECHNOLOGY_ZERO_BEAM_DURATION end
    local beamEndFrames = Mizuki.getBeamEndFrames(isBrimstoneBeam or technologyZeroTrisagion)
    local beamActiveDuration = math.max(1, beamDuration - beamEndFrames)
    -- Ordinary shots reach 1x damage at BaseFrames. Chocolate Milk can extend
    -- the same charge beyond that point instead of merely storing extra time.
    local chargeDamageMultiplier = Mizuki.getChargeDamageMultiplier(
        charge,
        chargeProfile
    )
    -- The charge is shared by every beam in this shot; each cannon's eye and
    -- per-tick factors are combined with it at the native firing call.
    local damageMultiplier = damageMultiplierOverride
        or chargeDamageMultiplier
    local beamAngleOffsets, beamDamageMultipliers
    if echoOnlyAngles then
        beamAngleOffsets = echoOnlyAngles
    else
        beamAngleOffsets, beamDamageMultipliers = getMizukiBeamAngleOffsets(
            player, nil, techX, lungScatterKind == "knife")
    end
    if lungScatterKind == "knife" then
        -- One Bone Scythe launch owns its native Lung volley. Do not also roll
        -- custom scatter or create one complete scythe for each scatter angle.
        beamAngleOffsets = {beamAngleOffsets[1] or 0}
    end
    local pepperBeams = {}
    -- Shared identity for this attack, not for each of its multishot lasers.
    -- Finite echoes retain this group and replay its recorded pepper outcomes.
    local pepperAttack = {
        Direction = Vector(direction.X, direction.Y), Duration = beamDuration,
        Periodic = Mizuki.hasPeriodicBeam(player),
        Deployed = deployedAutoFire,
    }
    -- Record resolved attacks, never re-enter this firing controller to replay
    -- them. Echoes must not change real cannon sides, occupancy or charge.
    local echoShot = isFiniteShot and Mizuki.beginCannonEchoShot
        and Mizuki.beginCannonEchoShot(player, firingSides[1], finiteVolleyId)
        or nil
    local targetReticle = not deployedAutoFire
        and Mizuki.getTargetReticle(player, data) or nil
    if not echoOnlyAngles and not swordDriven then
        Mizuki.tryFireImmaculateHeartTear(player, direction)
        Mizuki.recordExtraAttack(player, direction)
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
            elseif not swordDriven and not trisagion and not techXFreeShot then
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
            if not trisagion then
                data.MizukiActiveBeams[side] = data.MizukiActiveBeams[side] or {}
            end
            for member, origin in ipairs(origins) do
                local firingCannon = data.MizukiCannons[side]
                    and data.MizukiCannons[side][member]
                local hasFiringCannon = firingCannon
                    and firingCannon:Exists()
                local persistentEchoMode = hasFiringCannon
                    and firingCannon:GetData().MizukiPersistentEchoMode or nil
                if not (hasFiringCannon and firingCannon:GetData().MizukiGuillotineNonFiring)
                    and ((echoOnlyAngles and persistentEchoMode == "automatic")
                    or (not echoOnlyAngles and persistentEchoMode ~= "automatic")) then
                    local memberDirection = deployedAutoFire
                        and hasFiringCannon
                        and Mizuki.getCannonAutoFireAim(player, data, member)
                        or direction
                    if persistentEchoMode == "automatic" then
                        memberDirection = firingCannon:GetData().MizukiCannonAim or memberDirection
                    end
                    if swordDriven and hasFiringCannon then
                        memberDirection = firingCannon:GetData().MizukiCannonAim or memberDirection
                    end

                    if not swordDriven and isFiniteShot and not trisagion and not techXFreeShot then
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
                            + Mizuki.getCannonBeamPivotRenderOffset(
                                player, firingCannonData
                            )
                        if isFiniteShot and not trisagion then
                            firingCannonData.MizukiLockedFiringDepthOffset =
                                firingCannon.DepthOffset
                        end
                    end

                    -- Capture the body root from the same resolved firing pose
                    -- used below for the laser, before native creation callbacks.
                    local firingCannonDrawPosition = visualOrigin
                        + (hasFiringCannon
                            and firingCannon:GetData().MizukiRenderWorldOffset or Vector.Zero)

                    -- Eye-specific item bonuses remain native. Player-sourced
                    -- Technology and Brimstone lasers apply them per damage tick;
                    -- pre-applying them here would duplicate the native bonus.
                    local apiDamageMultiplier = damageMultiplier
                        * damagePerTickMultiplier
                        * (persistentEchoMode and Mizuki.CannonEchoDamageMultiplier or 1)
                    local boneLungShots = boneLung and {} or nil
                    for beamIndex, angleOffset in ipairs(beamAngleOffsets) do
                        local shotDamageMultiplier = beamDamageMultipliers
                            and beamDamageMultipliers[beamIndex] or 1
                        local echoSource = echoAttack and echoAttack.Shots[beamIndex]
                        local target = not swordDriven and not persistentEchoMode and targetReticle or nil
                        local beamDirection, originCorrection = Mizuki.resolveBeamGeometry(
                            visualOrigin,
                            memberDirection,
                            angleOffset,
                            target and target.Position or nil
                        )
                        local hitboxOffset = Vector(0, Config.BEAM_HITBOX_Y_OFFSET)
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
                        local beamParameters = {
                            Origin = hitboxOrigin, Direction = beamDirection,
                            LeftEye = side == 1, DamageMultiplier = apiDamageMultiplier * shotDamageMultiplier,
                            WidthScale = beamWidthScale, PositionOffset = -hitboxOffset,
                            DepthOffset = (firingCannon and firingCannon.DepthOffset
                                or Config.CANNON_DEPTH_OFFSET) - Mizuki.WeaponParameters.BeamDepthBehindCannon
                                - hitboxOffset.Y - originCorrection.Y,
                            ActiveDuration = beamActiveDuration, Distance = currentBeamDistance,
                            Automatic = automatic,
                            TechnologyZeroTrisagion = technologyZeroTrisagion,
                            Parent = followCannon and firingCannon or nil,
                        }
                        if swordDriven and hasFiringCannon
                            and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
                            local hiltOrigin = Mizuki.getSpiritSwordKnifeBeamOrigin(firingCannon)
                            if hiltOrigin then
                                local hitboxOrigin = hiltOrigin - beamParameters.PositionOffset
                                beamParameters.DepthOffset = beamParameters.DepthOffset
                                    + beamParameters.Origin.Y - hitboxOrigin.Y
                                beamParameters.Origin = hitboxOrigin
                            end
                        end
                        if techX then
                            local level = math.max(0, math.min(1, charge / chargeProfile.MaxFrames))
                            beamParameters.TechXPartial = not techXLinked
                            beamParameters.TechXChain = techXContinuous and techXLinked or false
                            beamParameters.TechXChainLane = beamIndex
                            beamParameters.TechXRingOnly = techXContinuous and techXLinked
                                and Mizuki.findCannonTechXRail(data, side, firingCannon, beamIndex) ~= nil
                            if techXLinked and not beamParameters.TechXRingOnly then
                                beamParameters.DamageMultiplier = beamParameters.DamageMultiplier
                                    * Mizuki.TechXParameters.ConnectorDamageMultiplier
                            end
                            beamParameters.TechXRadius = math.max(Mizuki.TechXParameters.MinRadius,
                                Mizuki.TechXParameters.MaxRadius * level * shotDamageMultiplier)
                            beamParameters.TechXSpeed = player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed
                            beamParameters.TechXDamageMultiplier = (0.25 + 0.75 * level) * shotDamageMultiplier
                                * (chargeProfile.HasChocolateMilk and damageMultiplier or 1)
                                * (persistentEchoMode and Mizuki.CannonEchoDamageMultiplier or 1)
                        end
                        if boneLung and beamIndex > 1 then
                            boneLungShots[#boneLungShots + 1] = Mizuki.fireBerserkLungTear(player,
                                beamParameters.Origin, beamDirection:Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed),
                                damageMultiplier * shotDamageMultiplier)
                        elseif trisagion then
                            local shot = Mizuki.fireCannonTrisagion(player, firingCannon,
                                beamParameters, damageMultiplier * shotDamageMultiplier)
                            if not persistentEchoMode and not echoOnlyAngles and not echoAttack then trisagionShotFired = true end
                            local attack = { TrisagionShot = shot, Tear = shot.Tear, Cannon = firingCannon,
                                Origin = Vector(origin.X, origin.Y),
                                FiringCannonDrawPosition = firingCannonDrawPosition,
                                Direction = beamDirection, LeftEye = side == 1, PepperAttack = pepperAttack }
                            pepperBeams[#pepperBeams + 1] = attack
                            Mizuki.bindCannonAttackAppearance(firingCannon, shot.Tear,
                                damageMultiplier * shotDamageMultiplier)
                            if echoShot then Mizuki.captureCannonEchoTrisagion(echoShot, attack) end
                            if automatic then Mizuki.queueAutomaticTrisagionEcho(player, firingCannon, shot) end
                        else
                            local laser = Mizuki.createCannonBeam(player, beamParameters)
                            Mizuki.bindCannonAttackAppearance(firingCannon, laser,
                                techX and not techXLinked and beamParameters.TechXDamageMultiplier or beamParameters.DamageMultiplier)
                            Mizuki.connectPersistentEchoAttack(player, firingCannon, laser,
                                angleOffset, "beam", echoSource and echoSource.Sequence, beamIndex)
                            if persistentEchoMode and not Mizuki.isEchoAttackReplayActive(laser) then
                                laser.Color = Mizuki.getPersistentEchoColor(laser.Color)
                            end

                            local beam = {
                                Laser = laser,
                                BeamParameters = beamParameters,
                                Origin = Vector(origin.X, origin.Y),
                                FiringCannonDrawPosition = Vector(
                                    firingCannonDrawPosition.X, firingCannonDrawPosition.Y),
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
                                BerserkLungShots = boneLungShots,
                                BerserkChargeDamageMultiplier = chargeProfile.HasChocolateMilk and damageMultiplier or 1,
                                SpiritSwordDriven = swordDriven == true,
                                SpiritSwordSpinThrow = swordDriven == true and swordSpinThrow == true,
                                Cannon = firingCannon,
                                PersistentEchoMode = persistentEchoMode,
                                PersistentEchoSourceSeed = echoSource and echoSource.SourceSeed,
                                PersistentEchoSourceHash = echoSource and echoSource.SourceHash,
                                MizukiAutoFire = deployedAutoFire,
                                FiniteVolleyId = finiteVolleyId,
                                PepperAttack = pepperAttack,
                            }
                            if techX then
                                Mizuki.attachCannonTechX(beam, player)
                                if not persistentEchoMode and not echoOnlyAngles and not echoAttack then
                                    techXShotFired = true
                                end
                                if techXLinked and not beam.TechXRailRingOnly then
                                    laser:GetData().MizukiTechXConnection = beam
                                end
                            end
                            if not techX or techXLinked then
                                table.insert(data.MizukiActiveBeams[side], beam)
                            end
                            if swordDriven then
                                laser:GetData().MizukiSpiritSwordBeam = beam
                                Mizuki.syncSpiritSwordBeam(beam)
                            end
                            pepperBeams[#pepperBeams + 1] = beam
                            if isFiniteShot
                                and not techX
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
                            Mizuki.trackDeadEyeBeam(player, beam, echoOnlyAngles ~= nil or echoAttack ~= nil)
                            if techX and not persistentEchoMode then
                                Mizuki.trackDeadEyeTechXRing(player, beam.TechXRing, beam)
                            end
                            if echoShot and Mizuki.captureCannonEchoBeam then
                                Mizuki.captureCannonEchoBeam(
                                    echoShot, beam, charge, chargeProfile.BaseChargeFrames
                                )
                            end
                        end -- native beam / independent Trisagion projectile
                    end
                end -- Originals fire now; automatic echoes use the delayed sample.
            end
        end
    end
    if not swordDriven and (techXShotFired or trisagionShotFired) then
        Mizuki.updateIsaacsTearsCharge(player, data, true)
    end
    if techX and not techXLinked and not techXFreeShot then
        for _, side in ipairs(firingSides) do
            data.MizukiActiveBeams[side] = nil
            data.MizukiLockedCannonPositions[side] = nil
            data.MizukiLockedCannonAims[side] = nil
        end
    end
    if trisagion and automatic and #pepperBeams > 0 then
        data.MizukiTrisagionNextShot = Game():GetFrameCount() + Mizuki.TrisagionParameters.Interval
    end
    if not swordDriven and not trisagion and isTechnologyZeroBeam and not automatic and not deployedAutoFire
        and not echoOnlyAngles and not echoAttack then
        Mizuki.lockTechnologyZeroHead(player, direction, pepperBeams)
    end
    -- Sword attack opportunities belong to melee, never its ranged follow-up.
    if not swordDriven then
        Mizuki.recordInputAttackEffects(player, pepperBeams, automatic,
            not techX and pepperAttack.Periodic, beamDuration,
            echoOnlyAngles ~= nil or echoAttack ~= nil)
    end
    if not swordDriven and Mizuki.recordPepperAttack then
        Mizuki.recordPepperAttack(player, direction, pepperBeams, automatic,
            isBrimstoneBeam or isTechnologyZeroBeam, beamDuration,
            echoOnlyAngles ~= nil or echoAttack ~= nil)
    end
    if automatic and not trisagion and not echoOnlyAngles then
        -- Position layout was sampled earlier this frame. Add this newly fired
        -- attack to that SAME frame rather than introducing a seventh frame.
        Mizuki.captureAutomaticCannonEchoAttacks(player, data)
    end
    return finiteVolleyId
end

function Mizuki:UpdateCannonLaser(laser)
    local laserData = laser:GetData()
    if laserData.MizukiCannonTechXRing == true then
        return
    end
    if not laserData.MizukiBeam then
        return
    end

    -- Player-fired lasers already received their complete damage multiplier
    -- through FireTechLaser or FireBrimstone. Only the ShootAngle replacement
    -- for thick Brimstone loses that parameter on native damage refresh.
    local player = laserData.MizukiBeamOwner
    if player and player:Exists() then
        laser.TearFlags = Mizuki.addOccultHoming(player, laser.TearFlags)
            & ~Config.MIZUKI_FORBIDDEN_TEAR_FLAGS

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

    Mizuki.applyTechnologyZeroTrisagionColor(laser)

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

function Mizuki:FinalizeEpicFetusTargets()
    local frame = Game():GetFrameCount()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then
            local data = player:GetData()
            local canStart = player:HasCollectible(
                CollectibleType.COLLECTIBLE_EPIC_FETUS
            ) and Mizuki.canStartEpicFetusStrike(data)
            local ring = data.MizukiLudovicoRing
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
                    and candidate.Frame == frame
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

-- Additional native tears share the counted-attack entry below.
function Mizuki.tryFireImmaculateHeartTear(player, direction, origin, source)
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
        origin or player.Position,
        shotDirection:Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed),
        false,
        true,
        false,
        source or player,
        1
    )
    tear.Parent = player
    tear.SpawnerEntity = source or player
    tear:AddTearFlags(
        TearFlags.TEAR_ORBIT_ADVANCED | TearFlags.TEAR_SPECTRAL
    )
    -- Keep FireTear's native falling speed; the advanced orbit changes only
    -- its falling acceleration.
    tear.FallingAcceleration = Config.IMMACULATE_HEART_FALLING_ACCELERATION
end

local function advanceLeadPencil(player, direction, origin, source)
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
            origin or player.Position,
            velocity,
            true,
            false,
            true,
            source or player,
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
            tear.Color = Config.LEAD_PENCIL_BLOOD_CLOT_COLOR
        elseif tear.Variant == TearVariant.BLUE and rng:RandomFloat() < Mizuki.WeaponParameters.PencilBloodTearChance then
            tear:ChangeVariant(TearVariant.BLOOD)
        end
        tear:GetData().MizukiLeadPencilTear = true
    end
end

-- One notification for counted original attacks. Generated barrages/coins and
-- delayed echoes never call this entry again; item counters stay independent.
function Mizuki.recordExtraAttack(player, direction, origin, source)
    advanceLeadPencil(player, direction, origin, source)
    Mizuki.advanceEyeOfGreed(player, direction, origin, source)
end
