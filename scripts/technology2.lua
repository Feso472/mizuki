-- Ordinary fire gives Technology 2 the right cannon. Sustained fire and
-- Spirit Sword use both cannons, so Technology 2 fires from the player eye.
function Mizuki.tech2UsesPlayerEye(player)
    return Mizuki.isMizuki(player)
        and player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
        and not Mizuki.usesCSectionWeapon(player)
        and (Mizuki.usesAutomaticBeam(player) or Mizuki.usesCannonSpiritSword(player))
end

-- SubType is the stable eye identity, never the cannon's screen coordinate.
function Mizuki.hasCannonTech2(player)
    return Mizuki.isMizuki(player)
        and player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
        and not Mizuki.tech2UsesPlayerEye(player)
end

function Mizuki.isTech2Cannon(cannon)
    return cannon and cannon:Exists() and cannon.SubType == 2 and cannon.Player
        and Mizuki.hasCannonTech2(cannon.Player)
end

local function retire(beam)
    if beam.Technology2 and not beam.Ending then Mizuki.beginNaturalMizukiBeamEnding(beam) end
end

-- Native Tech 2 rolls these on laser damage ticks, not on the left weapon's
-- shots. One shared roll serves all right-cannon copies; they do not add odds.
function Mizuki.rollTech2ExtraDirections(player)
    local function roll(id, base, luckStep)
        if not player:HasCollectible(id) then return false end
        local value = player.Luck * luckStep
        local steps = value < 0 and math.ceil(value) or math.floor(value)
        return player:GetCollectibleRNG(id):RandomInt(math.max(1, base - steps)) == 0
    end
    local momsEye = roll(CollectibleType.COLLECTIBLE_MOMS_EYE, 20, 1.5)
    local loki = player:HasCollectible(CollectibleType.COLLECTIBLE_LOKIS_HORNS)
    if momsEye or roll(CollectibleType.COLLECTIBLE_LOKIS_HORNS, 80, 5) then
        return loki and {180, -90, 90} or {180}
    end
end

local function fireBeam(player, beams, cannon, direction, multiplier, offset, proc)
    local parameters = Mizuki.getCannonTech2Parameters(player, cannon, direction, multiplier, offset)
    parameters.Technology2Proc = proc
    if proc then
        -- Repentance+ fixed the old full-damage extra lasers to 13%. Keep
        -- Repentance's original value when running that version instead.
        parameters.DamageMultiplier = multiplier * ((REPENTANCE_PLUS or FontRenderSettings ~= nil) and 0.13 or 1)
    end
    local laser = Mizuki.createCannonBeam(player, parameters)
    local beam = {
        Technology2 = true, Technology2Proc = proc,
        Technology2Eye = parameters.Technology2Eye == true,
        Laser = laser, Cannon = cannon, BeamParameters = parameters,
        Origin = parameters.Origin, Direction = parameters.Direction, DirectionOffset = offset or 0,
        LeftEye = false, Automatic = true, FollowCannon = not parameters.Technology2Eye, Distance = 0,
        Timeout = 2, ActiveDuration = 2, TotalDuration = 5, EndFrames = 3,
        DamageMultiplier = multiplier, DamagePerTickMultiplier = 1,
        Tech2ProcEndFrame = proc and Game():GetFrameCount() + 2 or nil,
    }
    beams[#beams + 1] = beam
    if not proc then
        if cannon then Mizuki.bindCannonAttackAppearance(cannon, laser, multiplier) end
        Mizuki.trackDeadEyeBeam(player, beam, false)
    end
    return beam
end

function Mizuki:UpdateCannonTech2(player)
    if not Mizuki.isMizuki(player) or Game():IsPaused() then return end
    local data = player:GetData()
    local enabled = player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY_2)
    local eyeMode = Mizuki.tech2UsesPlayerEye(player)
    local cannonMode = enabled and not eyeMode
    for _, cannon in ipairs(data.MizukiCannons and data.MizukiCannons[2] or {}) do
        if cannon:Exists() then
            local cd = cannon:GetData()
            local previous = cd.MizukiTech2EchoSuppressed
            cd.MizukiTech2EchoSuppressed = cannonMode and cd.MizukiPersistentEchoMode ~= nil
            if cd.MizukiTech2EchoSuppressed then cannon.Visible = false
            elseif previous then
                cannon.Visible = not cd.MizukiAwaitingInitialLayout and not cd.MizukiGuillotineDisplaySuppressed
            end
        end
    end
    local held, direction = false, nil
    if enabled and not player:IsDead() and player:AreControlsEnabled()
        and player:IsExtraAnimationFinished() then
        held, direction = Mizuki.getTech5Input(player)
        if data.MizukiCannonAutoFireState == "deployed" then
            held, direction = true, data.MizukiCannonAim
        end
    end
    data.MizukiActiveBeams = data.MizukiActiveBeams or {}
    data.MizukiActiveBeams[2] = data.MizukiActiveBeams[2] or {}
    data.MizukiTech2EyeBeams = data.MizukiTech2EyeBeams or {}
    local live, liveEye = {}, false
    local function updateBeams(beams, fromEye)
        for index = #beams, 1, -1 do
            local beam = beams[index]
            if beam.Technology2 then
                local cannon = beam.Cannon
                local cd = cannon and cannon:Exists() and cannon:GetData()
                if not beam.Laser or not beam.Laser:Exists() then
                    table.remove(beams, index)
                elseif not enabled or not held or not direction or fromEye ~= eyeMode
                    or (not fromEye and (not cd or cd.MizukiPersistentEchoMode
                        or cd.MizukiGuillotineNonFiring)) then
                    retire(beam)
                elseif not beam.Ending then
                    beam.Direction = direction:Rotated(beam.DirectionOffset or 0)
                    if beam.Technology2Proc then
                        -- A proc is one short, one-hit shot. Never renew it into
                        -- another continuous laser or let it replace the main one.
                        beam.Timeout = math.max(0, beam.Tech2ProcEndFrame - Game():GetFrameCount())
                        if beam.Timeout <= 0 then retire(beam) end
                    else
                        beam.Timeout, beam.Laser.Timeout = 2, 2
                        if fromEye then liveEye = true
                        else live[GetPtrHash(cannon)] = true end
                    end
                    if fromEye then
                    -- Also repairs already-live eye beams after hot reload:
                    -- native FireTechLaser was created with following disabled.
                    beam.Laser.Parent = player
                    beam.Laser.DisableFollowParent = false
                        beam.Laser.AngleDegrees = beam.Direction:GetAngleDegrees()
                    end
                    -- Ludovico owns a separate layout and bypasses normal following.
                    if not fromEye and data.MizukiLudovicoRing then
                        local p = Mizuki.getCannonTech2Parameters(player, cannon, direction,
                            beam.DamageMultiplier, beam.DirectionOffset)
                        beam.Laser.Position, beam.Laser.PositionOffset = p.Origin, p.PositionOffset
                        beam.Laser.AngleDegrees = p.Direction:GetAngleDegrees()
                        beam.Origin, beam.Direction = p.Origin, p.Direction
                    end
                    -- Share the ordinary sustained-attack notification (including
                    -- its per-frame deduplication) with Pencil / Eye of Greed.
                    if not beam.Technology2Proc and Mizuki.RefreshMizukiBeamAttackParams then
                        Mizuki.RefreshMizukiBeamAttackParams(player, data, beam, beam.Laser, direction)
                    end
                end
            elseif not fromEye and cannonMode and beam.Laser and beam.Laser:Exists()
                and beam.Laser:GetData().MizukiBeam == true then
                -- Only our explicitly owned old right-side attacks are replaced.
                Mizuki.cancelCannonTechX(beam)
                Mizuki.cancelCannonKnifeBeam(beam)
                beam.Laser:Remove()
                table.remove(beams, index)
            end
        end
    end
    updateBeams(data.MizukiActiveBeams[2], false)
    updateBeams(data.MizukiTech2EyeBeams, true)
    if not enabled or not held or not direction then return end
    local beams = eyeMode and data.MizukiTech2EyeBeams or data.MizukiActiveBeams[2]
    if eyeMode then
        if not liveEye then fireBeam(player, beams, nil, direction, 1) end
    else
        data.MizukiLockedCannonPositions = data.MizukiLockedCannonPositions or {}
        data.MizukiLockedCannonAims = data.MizukiLockedCannonAims or {}
        data.MizukiLockedCannonPositions[2], data.MizukiLockedCannonAims[2] = nil, nil
        for member, cannon in ipairs(data.MizukiCannons and data.MizukiCannons[2] or {}) do
            local cd = cannon:Exists() and cannon:GetData()
            if cd and not cd.MizukiAwaitingInitialLayout and not cd.MizukiGuillotineNonFiring
                and not cd.MizukiPersistentEchoMode and not live[GetPtrHash(cannon)] then
                local profile = data.MizukiExpectedCannonPairProfiles and data.MizukiExpectedCannonPairProfiles[member]
                local multiplier = profile and profile.DamageMultiplier or 1
                fireBeam(player, beams, cannon, direction, multiplier)
            end
        end
    end
    local frame = Game():GetFrameCount()
    if data.MizukiTech2ProcRollFrame == frame then return end
    local originals = {}
    for _, beam in ipairs(beams) do
        if beam.Technology2 and not beam.Technology2Proc and not beam.Ending
            and beam.Laser and beam.Laser:Exists()
            and beam.Laser.FrameCount % Mizuki.BEAM_DAMAGE_INTERVAL == 0 then
            originals[#originals + 1] = beam
        end
    end
    if #originals == 0 then return end
    data.MizukiTech2ProcRollFrame = frame
    local angles = Mizuki.rollTech2ExtraDirections(player)
    if not angles then return end
    for _, beam in ipairs(originals) do
        for _, offset in ipairs(angles) do
            fireBeam(player, beams, beam.Cannon, direction, beam.DamageMultiplier, offset, true)
        end
    end
end

-- Normal player input/layout has resolved before creating/renewing the beam.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, CallbackPriority.LATE,
    Mizuki.UpdateCannonTech2)
