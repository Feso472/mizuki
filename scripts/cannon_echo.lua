-- Cannon echoes: finite replay, delayed automatic pairs and Ludovico pairs.
-- Shared tuning: damage, automatic delay (frames), and finite-echo opacity (0-1).
Mizuki.CannonEchoDamageMultiplier = 0.5
Mizuki.CannonEchoFollowDelay = 1
Mizuki.CannonEchoReplayAlpha = 0.65
Mizuki.CannonEchoWaitingAlpha = 0.4
Mizuki.CannonEchoVariant = Isaac.GetEntityVariantByName("Mizuki Echo Cannon")
Mizuki.CannonEchoPersistentAlpha = 0.45

local ECHO_TINT = { Red = 0.45, Green = 0.85, Blue = 1, RedOffset = 0.08, GreenOffset = 0.12, BlueOffset = 0.18 }
local ECHO_KNIFE_INITIAL_ALPHA = 0.45
local ECHO_KNIFE_DEPTH_OFFSET = 1
local ECHO_BELOW_SOURCE_DEPTH_OFFSET = 1
local ECHO_KNIFE_MIN_FLIGHT_FRAMES = 1

function Mizuki.getCannonEchoColor(base, alpha)
    local tint = Color.Lerp(base, base, 0)
    tint.R, tint.G, tint.B = tint.R * ECHO_TINT.Red, tint.G * ECHO_TINT.Green, tint.B * ECHO_TINT.Blue
    tint.A = tint.A * alpha
    tint.RO, tint.GO, tint.BO = tint.RO + ECHO_TINT.RedOffset,
        tint.GO + ECHO_TINT.GreenOffset, tint.BO + ECHO_TINT.BlueOffset
    return tint
end

-- region Finite echoes
do
    local states = {}
    -- Entity:GetData survives Lua reloads; these registrations intentionally do
    -- not. An old shot table alone is never proof of current ownership.
    local liveShots = {}
    local FADE_FRAMES = 6
    local MAX_REPLAY_FRAMES = 600
    local ART_ROOT = "gfx/entities/mizuki/"

    local function vector(v)
        return Vector(v.X, v.Y)
    end

    local function color(c)
        -- The seven exposed channels omit native Colorize (Mizuki's pink laser
        -- coloration). A native color interpolation copies the complete value.
        return Color.Lerp(c, c, 0)
    end

    local function ghostColor(alpha)
        return Color(ECHO_TINT.Red, ECHO_TINT.Green, ECHO_TINT.Blue, alpha,
            ECHO_TINT.RedOffset, ECHO_TINT.GreenOffset, ECHO_TINT.BlueOffset)
    end

    local function ghostAlpha(shot)
        local alpha = shot.ReplayFrame and Mizuki.CannonEchoReplayAlpha or Mizuki.CannonEchoWaitingAlpha
        if shot.FadeFrame then
            alpha = alpha * math.max(0,
                1 - (Game():GetFrameCount() - shot.FadeFrame) / FADE_FRAMES)
        end
        return alpha
    end

    local function valid(entity, seed)
        return entity and entity:Exists() and entity.InitSeed == seed
    end

    local function isEchoKnife(knife)
        return knife and knife:GetData().MizukiEchoKnife == true
    end

    local function getKnifeSpriteRotationOffset(knife)
        return knife:GetData().MizukiCannonKnifeSpriteRotationOffset
            or (knife.SpriteRotation - knife.Rotation)
    end

    local function removeEchoKnife(knife)
        if knife and knife:Exists() and isEchoKnife(knife) then
            knife:Remove()
        end
    end

    local function removeShot(shot)
        if shot.Removed then return end
        shot.Removed = true
        liveShots[shot] = nil
        for _, child in ipairs(shot.Children) do
            local laser = child.Laser
            if laser and laser:Exists() and laser:GetData().MizukiEchoBeam == true then
                laser:Remove()
            end
            removeEchoKnife(child.Knife)
        end
        for _, ghost in ipairs(shot.Ghosts) do
            if ghost:Exists() and ghost:GetData().MizukiEchoCannon == true then
                removeEchoKnife(ghost:GetData().MizukiEchoWaitingKnife)
                if Mizuki.removeCannonKnifeLaserRoots then Mizuki.removeCannonKnifeLaserRoots(ghost) end
                ghost:GetData().MizukiEchoBodySprite = nil
                ghost:Remove()
            end
        end
    end

    local function clearState(state)
        for _, shot in pairs(state.Pending) do removeShot(shot) end
        for _, shot in ipairs(state.Playing) do removeShot(shot) end
        state.Pending, state.Playing = {}, {}
    end

    local function clearAll()
        for _, state in pairs(states) do clearState(state) end
        states = {}
        liveShots = {}
    end

    function Mizuki.hasCannonEcho(player)
        return player and player:Exists()
            and not player:IsDead() and Mizuki.isMizuki(player)
            and player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT)
            and (player:HasCollectible(CollectibleType.COLLECTIBLE_PHD)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD))
    end

    local function eligible(player)
        return Mizuki.hasCannonEcho(player)
            and not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
            and not Mizuki.usesAutomaticBeam(player)
            and not player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE)
    end

    local knifeDamageReplay
    local function scaleKnifeHit(_, target, amount, flags, source, countdown)
        local knife = source and source.Entity and source.Entity:ToKnife()
        if not knife or not target:IsVulnerableEnemy() then return end
        local multiplier
        if isEchoKnife(knife) then
            local child = knife:GetData().MizukiEchoChild
            if not child or child.Shot.Removed then return end
            multiplier = child.Shot.DamageMultiplier
        elseif Mizuki.getPersistentEchoKnifeMultiplier then
            multiplier = Mizuki.getPersistentEchoKnifeMultiplier(knife)
        end
        if not multiplier then return end
        local knifeKey, targetKey = GetPtrHash(knife), GetPtrHash(target)
        if knifeDamageReplay and knifeDamageReplay.Knife == knifeKey
            and knifeDamageReplay.Target == targetKey then return end
        if multiplier == 1 or amount <= 0 then return end
        -- Vanilla TAKE_DMG cannot return a replacement amount. Reapply with the
        -- same source/flags/countdown and cancel only the original echo hit.
        -- Scope the recursion guard to this knife/target pair; other knives and
        -- targets (including co-op/secondary hits) must still be scaled normally.
        local previous = knifeDamageReplay
        knifeDamageReplay = {Knife = knifeKey, Target = targetKey}
        local ok, err = pcall(function()
            target:TakeDamage(amount * multiplier, flags, source, countdown)
        end)
        knifeDamageReplay = previous
        if not ok then error(err) end
        return false
    end

    local function createKnife(child)
        local ghost = child.Ghost
        local knife = Mizuki.createCannonKnifeBody(ghost,
            child.KnifeOrigin, child.Direction:GetAngleDegrees(), child.KnifeVariant, child.BerserkClub)
        if not knife then return nil end
        local data = knife:GetData()
        data.MizukiEchoKnife = true
        data.MizukiEchoChild = child
        data.MizukiEchoFired = false
        data.MizukiEchoKnifeAge = 0
        data.MizukiEchoKnifeState = "outbound"
        data.MizukiEchoKnifePreviousDistance = 0
        data.MizukiEchoKnifeBaseColor = color(knife.Color)
        local ghostData = ghost:GetData()
        local primary = ghostData.MizukiEchoPrimaryKnife
        local auxiliary = valid(primary, ghostData.MizukiEchoPrimaryKnifeSeed)
            and GetPtrHash(primary) == ghostData.MizukiEchoPrimaryKnifeHash
            and isEchoKnife(primary) and primary:GetData().MizukiEchoFired == true
            and primary:IsFlying()
        data.MizukiEchoKnifeAuxiliary = auxiliary == true
        if auxiliary then
            data.MizukiEchoKnifeMotionSource = primary
            data.MizukiEchoKnifeMotionSourceSeed = primary.InitSeed
            data.MizukiEchoKnifeMotionSourceHash = GetPtrHash(primary)
        else
            ghostData.MizukiEchoPrimaryKnife = knife
            ghostData.MizukiEchoPrimaryKnifeSeed = knife.InitSeed
            ghostData.MizukiEchoPrimaryKnifeHash = GetPtrHash(knife)
        end
        knife.Visible = true
        knife.SpriteRotation = knife.Rotation + child.KnifeSpriteRotationOffset
        knife.Color = Mizuki.getCannonEchoColor(data.MizukiEchoKnifeBaseColor, ECHO_KNIFE_INITIAL_ALPHA)
        knife.DepthOffset = ghost.DepthOffset + ECHO_KNIFE_DEPTH_OFFSET
        return knife
    end

    local function getEchoMotionSource(knife)
        if not knife or not knife:Exists() or not isEchoKnife(knife) then return nil end
        local data = knife:GetData()
        if data.MizukiEchoKnifeAuxiliary ~= true then return knife end
        local source = data.MizukiEchoKnifeMotionSource
        if valid(source, data.MizukiEchoKnifeMotionSourceSeed)
            and GetPtrHash(source) == data.MizukiEchoKnifeMotionSourceHash
            and isEchoKnife(source) then
            local sourceChild, child = source:GetData().MizukiEchoChild, data.MizukiEchoChild
            if sourceChild and child and sourceChild.Shot == child.Shot
                and sourceChild.Ghost == child.Ghost then return source end
        end
    end

    local function updateGhostShadow(ghost)
        local data = ghost:GetData()
        local shot = data.MizukiEchoShot
        if data.MizukiEchoCannon ~= true or data.MizukiEchoAwaitingShot
            or not shot or shot.Removed then return end
        -- The engine's shadow pass ignores the body's Sprite.Color alpha. Drive
        -- the shadow layer's authored alpha with the same six-frame fade instead.
        local age = shot.FadeFrame and Game():GetFrameCount() - shot.FadeFrame or 0
        local sprite = ghost:GetSprite()
        sprite:SetFrame("Idle", math.max(0, math.min(FADE_FRAMES, age)))
        -- Real cannons reassert this every familiar update too. Keep the frozen
        -- source scale, never a player-size refresh or the body's turning squash.
        ghost.SpriteScale = vector(data.MizukiEchoShadowScale)
        sprite.Scale = vector(data.MizukiEchoShadowScale)
        sprite.Offset = vector(data.MizukiEchoShadowOffset)
        sprite.Rotation = 0
        sprite.FlipX, sprite.FlipY = false, false
        sprite.Color = ghostColor(0)
    end

    local function makeGhost(shot, beam)
        local cannon = beam.Cannon
        local source = cannon:GetData()
        local firingPosition = beam.Origin
        local ghost = Isaac.Spawn(EntityType.ENTITY_FAMILIAR,
            Mizuki.CannonEchoVariant, 0, vector(firingPosition), Vector.Zero,
            shot.Player):ToFamiliar()
        ghost.Player = shot.Player
        ghost.EntityCollisionClass = beam.MomKnifeDriven
            and EntityCollisionClass.ENTCOLL_NONE or EntityCollisionClass.ENTCOLL_ENEMIES
        ghost.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        ghost.CollisionDamage = 0
        ghost.Size = cannon.Size
        ghost.DepthOffset = cannon.DepthOffset
        ghost:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        local data = ghost:GetData()
        data.MizukiEchoCannon = true
        data.MizukiEchoShot = shot
        data.MizukiEchoAnchor = vector(firingPosition)
        data.MizukiEchoKnifeMode = beam.MomKnifeDriven == true
        data.MizukiEchoContactDamage = shot.Player.Damage
            * Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER
            * (source.MizukiContactDamageMultiplier or 1) * shot.DamageMultiplier
        data.MizukiEchoContactInterval = math.max(shot.Player.MaxFireDelay, 1) + 1
        data.MizukiEchoContactClocks = {}
        data.MizukiSpecialBrimstoneCurse = source.MizukiSpecialBrimstoneCurse
        data.MizukiCannonAttackAppearanceKey = beam.Laser:GetData().MizukiCannonAttackAppearanceKey
        -- Body and laser share the resolved firing snapshot. Reading the live
        -- familiar here can mix its previous pose with the new laser origin.
        -- This base draw position excludes the animated hover displacement.
        data.MizukiEchoDrawPosition = vector(beam.FiringCannonDrawPosition)
        data.MizukiEchoReflectionSpan = source.MizukiReflectionSpan or Mizuki.CANNON_FIRING_REFLECTION_SPAN
        data.MizukiEchoRotation = source.MizukiCannonBodyRotation or 0
        local scale = source.MizukiCannonBaseScale or shot.Player.SpriteScale
        -- The shared knife scaler consumes the same cannon-scale input.
        data.MizukiCannonBaseScale = vector(scale)
        data.MizukiEchoScale = Vector(scale.X * Mizuki.CANNON_ART_SCALE_MULTIPLIER
            * math.abs(source.MizukiVerticalBodyXFactor or 1), scale.Y * Mizuki.CANNON_ART_SCALE_MULTIPLIER)
        -- Only the echo uses this shadow-only animation. It retains the existing
        -- ellipse and native ground pass, with per-frame layer alpha for fading.
        data.MizukiEchoShadowScale = vector(cannon.SpriteScale)
        data.MizukiEchoShadowOffset = vector(source.MizukiShadowOffset
            or Vector(0, source.MizukiShadowOffsetY or 0))
        local nativeSprite = ghost:GetSprite()
        nativeSprite:Load(ART_ROOT .. "mizuki_echo_shadow.anm2", true)
        local sprite = Sprite()
        sprite:Load(ART_ROOT .. "mizuki_cannon.anm2", true)
        local left = source.MizukiCannonGraphicsMode == "left"
        sprite:ReplaceSpritesheet(0, ART_ROOT .. (left and "mizuki_cannon_left.png"
            or "mizuki_cannon.png"))
        sprite:ReplaceSpritesheet(1, ART_ROOT .. (left and "mizuki_cannon_light_left.png"
            or "mizuki_cannon_light.png"))
        sprite:LoadGraphics()
        local sourceSprite = cannon:GetSprite()
        sprite:SetFrame(sourceSprite:GetAnimation(), sourceSprite:GetFrame())
        data.MizukiEchoBodyFlipX = sourceSprite.FlipX
        data.MizukiEchoBodySprite = sprite
        table.insert(shot.Ghosts, ghost)
        -- Only a fully bound attack record may expose this familiar's shadow.
        data.MizukiEchoAwaitingShot = false
        updateGhostShadow(ghost)
        ghost.Visible = true
        return ghost
    end

    function Mizuki.beginCannonEchoShot(player, side, volleyId)
        if not eligible(player) then return nil end
        local key = GetPtrHash(player)
        local state = states[key]
        if state and not valid(state.Player, state.PlayerSeed) then
            clearState(state)
            state = nil
        end
        if not state then
            state = {Player = player, PlayerSeed = player.InitSeed,
                Pending = {}, Playing = {}}
            states[key] = state
        end
        local previous = state.Pending[side]
        if volleyId and previous and previous.VolleyId == volleyId then
            return previous -- Another child of the SAME Cursed Eye release.
        end
        local other = state.Pending[3 - side]
        if other then
            other.ReplayFrame = Game():GetFrameCount()
            state.Pending[3 - side] = nil
            table.insert(state.Playing, other)
        end
        -- A forced same-side release supersedes an older waiting record; it does
        -- not fabricate an opposite-side event or build an unbounded queue.
        if previous then removeShot(previous) end
        local shot = {Player = player, Side = side, VolleyId = volleyId,
            Frame = Game():GetFrameCount(), Children = {}, Ghosts = {},
            GhostByCannon = {}, DamageMultiplier = Mizuki.CannonEchoDamageMultiplier}
        liveShots[shot] = true
        state.Pending[side] = shot
        return shot
    end

    function Mizuki.captureCannonEchoBeam(shot, beam, charge, baseChargeFrames)
        if shot.Removed or not beam.Cannon or not beam.Cannon:Exists()
            or not beam.BeamParameters or not beam.Origin
            or not beam.FiringCannonDrawPosition then return end
        local key = GetPtrHash(beam.Cannon)
        local ghost = shot.GhostByCannon[key]
        if not ghost then
            ghost = makeGhost(shot, beam)
            shot.GhostByCannon[key] = ghost
        end
        Mizuki.snapshotCannonAttackAppearance(ghost, beam.Laser)
        local parameters = {}
        for name, value in pairs(beam.BeamParameters) do parameters[name] = value end
        parameters.Origin = vector(parameters.Origin)
        parameters.Direction = vector(parameters.Direction)
        parameters.PositionOffset = vector(parameters.PositionOffset)
        -- This is a player-fired attack. The ghost is only its visual origin;
        -- native item/status-effect ownership must remain on the player.
        -- createCannonBeam disables parent following and sets the recorded origin.
        parameters.Parent = shot.Player
        parameters.DamageMultiplier = parameters.DamageMultiplier * shot.DamageMultiplier
        local child = {Shot = shot, Ghost = ghost, Cannon = ghost,
            BeamParameters = parameters,
            PepperAttack = beam.PepperAttack,
            Offset = Game():GetFrameCount() - shot.Frame,
            Direction = vector(beam.Direction),
            -- A knife-driven laser is already shortened to 1 at release. Its
            -- launch range remains in the beam record, not current laser length.
            Distance = parameters.Distance, ActiveDuration = beam.ActiveDuration,
            EndFrames = beam.EndFrames,
            KnifeMode = beam.MomKnifeDriven == true,
            KnifeCharge = math.max(0, math.min(charge / math.max(1, baseChargeFrames), 1))}
        if child.KnifeMode then
            local knife = beam.MomKnife
            if not knife or not knife:Exists() then return end
            child.KnifeOrigin = vector(knife.Position + knife.PositionOffset)
            child.KnifeVariant = knife.Variant
            child.BerserkClub = knife:GetData().MizukiBerserkClub == true
            child.KnifeSpriteRotationOffset = getKnifeSpriteRotationOffset(knife)
        end
        table.insert(shot.Children, child)
        child.AttackSequence = Mizuki.startEchoAttackRecording(beam.Laser)
        if child.KnifeMode then child.KnifeSequence = Mizuki.startEchoAttackRecording(beam.MomKnife, false, true) end
        if child.KnifeMode and not ghost:GetData().MizukiEchoWaitingKnife then
            ghost:GetData().MizukiEchoWaitingKnife = createKnife(child)
        end
    end

    local function applyLaserAppearance(laser, child)
        if Mizuki.applyEchoAttackSequence(laser) then return end
        if laser:HasTearFlags(TearFlags.TEAR_RAINBOW) then
            -- Preserve the native rainbow phase and native per-hit effects.
            -- Only alpha is fixed; copying the birth RGB would freeze cycling.
            local rainbowColor = color(laser.Color)
            rainbowColor.A = child.BaseColor.A * Mizuki.CannonEchoReplayAlpha
            laser.Color = rainbowColor
            return
        end
        -- Always rebuild from the captured native color, never the tinted result.
        laser.Color = Mizuki.getCannonEchoColor(child.BaseColor, Mizuki.CannonEchoReplayAlpha)
    end

    local function beginEnding(child)
        if child.Ending then return end
        child.EndFrame = Game():GetFrameCount()
        Mizuki.beginNaturalMizukiBeamEnding(child)
        child.Ending = true
    end

    local function replayChild(child)
        child.Started = true
        child.StartFrame = Game():GetFrameCount()
        local laser = Mizuki.createCannonBeam(child.Shot.Player, child.BeamParameters)
        child.Laser = laser
        laser:GetData().MizukiEchoBeam = true
        laser:GetData().MizukiEchoChild = child
        child.BaseColor = color(laser.Color)
        Mizuki.bindEchoAttackReplay(laser, child.AttackSequence, {
            Alpha = Mizuki.CannonEchoReplayAlpha, Tint = true, LaserSpawner = child.Ghost})
        Mizuki.bindCannonAttackAppearance(child.Ghost, laser, 1)
        applyLaserAppearance(laser, child)
        if child.KnifeMode then
            local ghostData = child.Ghost:GetData()
            local knife = ghostData.MizukiEchoWaitingKnife
            if knife and knife:Exists() and not knife:GetData().MizukiEchoFired then
                ghostData.MizukiEchoWaitingKnife = nil
            else
                knife = createKnife(child)
            end
            child.Knife = knife
            if knife then
                local data = knife:GetData()
                data.MizukiEchoChild = child
                data.MizukiEchoFired = true
                Mizuki.bindEchoAttackReplay(knife, child.KnifeSequence, {
                    Alpha = Mizuki.CannonEchoReplayAlpha, Tint = true})
                data.MizukiEchoKnifeAge = 0
                data.MizukiEchoKnifeState = "outbound"
                data.MizukiEchoKnifePreviousDistance = 0
                Mizuki.launchCannonKnife(knife, child.Ghost, child, child.KnifeCharge, child.KnifeOrigin)
            end
        end
    end

    local function updateShot(shot, frame)
        if not shot.ReplayFrame then return end
        local age = frame - shot.ReplayFrame
        local allDone = true
        local pepperAttacks = {}
        for _, child in ipairs(shot.Children) do
            if not child.Started and age >= child.Offset then
                replayChild(child)
                if child.PepperAttack then
                    local group = pepperAttacks[child.PepperAttack] or {}
                    pepperAttacks[child.PepperAttack] = group
                    group[#group + 1] = child
                end
            end
            if child.Started and not child.Ending then
                local knife = child.Knife
                if child.KnifeMode and knife and knife:Exists() then
                    local motionSource = getEchoMotionSource(knife)
                    if frame > child.StartFrame and (not motionSource or not motionSource:IsFlying()) then
                        beginEnding(child)
                    elseif child.Laser and child.Laser:Exists() then
                        child.Laser.Timeout = child.ActiveDuration
                    end
                elseif frame - child.StartFrame >= child.ActiveDuration then
                    beginEnding(child)
                end
            end
            local laserAlive = child.Laser and child.Laser:Exists()
            local motionSource = getEchoMotionSource(child.Knife)
            local knifeAlive = motionSource and motionSource:IsFlying()
            if not child.Started or laserAlive or knifeAlive then allDone = false end
        end
        if Mizuki.recordPepperEchoAttack then
            for attack, children in pairs(pepperAttacks) do
                Mizuki.recordPepperEchoAttack(shot.Player, attack, children)
            end
        end
        if allDone or age >= MAX_REPLAY_FRAMES then
            shot.FadeFrame = shot.FadeFrame or frame
            for _, ghost in ipairs(shot.Ghosts) do
                if ghost:Exists() and ghost:GetData().MizukiEchoCannon == true then
                    ghost.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                    updateGhostShadow(ghost)
                end
            end
            if frame - shot.FadeFrame >= FADE_FRAMES then removeShot(shot) end
        end
    end

    local function updateEchoes()
        local frame = Game():GetFrameCount()
        for key, state in pairs(states) do
            if not valid(state.Player, state.PlayerSeed) or not eligible(state.Player)
                or (state.LastFrame and frame < state.LastFrame) then
                clearState(state)
                states[key] = nil
            else
                state.LastFrame = frame
                for _, shot in pairs(state.Pending) do updateShot(shot, frame) end
                for index = #state.Playing, 1, -1 do
                    local shot = state.Playing[index]
                    updateShot(shot, frame)
                    if shot.Removed then table.remove(state.Playing, index) end
                end
            end
        end
    end

    local function updateLaser(_, laser)
        local data = laser:GetData()
        if data.MizukiEchoCapture then
            -- Old-version records can survive a Lua reload on original lasers.
            data.MizukiEchoCapture = nil -- A source laser is NOT an echo.
        end
        if data.MizukiEchoBeam == true then
            local child = data.MizukiEchoChild
            if not child or not liveShots[child.Shot] or child.Shot.Removed then
                laser:Remove()
                return
            end
            applyLaserAppearance(laser, child)
            local knife = child.Knife
            if child.KnifeMode and knife and knife:Exists() and knife:GetData().MizukiEchoFired then
                Mizuki.syncCannonKnifeFlightEndpoint(knife, getEchoMotionSource(knife), child)
            end
        end
    end

    local function syncInterpolatedKnife(_, laser)
        local data = laser:GetData()
        if data.MizukiEchoBeam ~= true then return end
        local child = data.MizukiEchoChild
        if not child or not liveShots[child.Shot] or child.Shot.Removed then return end
        local knife = child.Knife
        if child.KnifeMode and knife and knife:Exists() and knife:GetData().MizukiEchoFired then
            local source = getEchoMotionSource(knife)
            local player = child.Cannon and child.Cannon.Player
            if source and ((player and player:HasCollectible(CollectibleType.COLLECTIBLE_TINY_PLANET))
                or (not player and (source.TearFlags & TearFlags.TEAR_ORBIT) ~= TearFlags.TEAR_NORMAL)) then
                Mizuki.syncCannonKnifeFlightEndpoint(knife, source, child)
            end
        end
    end

    local function updateKnife(_, knife)
        if not isEchoKnife(knife) then return end
        local data = knife:GetData()
        local child = data.MizukiEchoChild
        if not child or not liveShots[child.Shot] or child.Shot.Removed or not child.Ghost:Exists() then
            removeEchoKnife(knife)
            return
        end
        Mizuki.updateCannonKnifeScale(knife, child.Ghost)
        if not Mizuki.applyEchoAttackSequence(knife) then
            knife.Color = Mizuki.getCannonEchoColor(data.MizukiEchoKnifeBaseColor,
                data.MizukiEchoFired and Mizuki.CannonEchoReplayAlpha or Mizuki.CannonEchoWaitingAlpha)
        end
        if data.MizukiEchoFired then
            data.MizukiEchoKnifeAge = data.MizukiEchoKnifeAge + 1
            local motionSource = getEchoMotionSource(knife)
            if not motionSource or (data.MizukiEchoKnifeAge > ECHO_KNIFE_MIN_FLIGHT_FRAMES
                and not motionSource:IsFlying()) then
                beginEnding(child)
                removeEchoKnife(knife)
                return
            end
            if data.MizukiEchoKnifeAuxiliary == true then
                Mizuki.refreshAuxiliaryCannonKnifeFlight(knife, child.Ghost, child,
                    motionSource, child.KnifeCharge)
            end
            data.MizukiEchoKnifeState, data.MizukiEchoKnifePreviousDistance =
                Mizuki.updateCannonKnifeFlight(knife, motionSource, child, child.KnifeOrigin,
                    data.MizukiEchoKnifeState, data.MizukiEchoKnifePreviousDistance)
        else
            knife.Position = child.KnifeOrigin - knife.PositionOffset
            knife.Velocity = Vector.Zero
            knife.Rotation = child.Direction:GetAngleDegrees()
            -- Frozen aim plus the source art's native offset, without flight spin.
            knife.SpriteRotation = knife.Rotation + child.KnifeSpriteRotationOffset
        end
    end

    local function initGhost(_, ghost)
        -- This variant is exclusively an echo, including engine-restored familiars
        -- that were not created by makeGhost. Hiding the body alpha alone does not
        -- hide its native shadow; keep unbound entities out of rendering entirely.
        local data = ghost:GetData()
        data.MizukiEchoCannon = true
        data.MizukiEchoAwaitingShot = true
        ghost.Visible = false
        ghost.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        ghost.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        ghost.CollisionDamage = 0
        ghost:GetSprite().Color = ghostColor(0)
    end

    local function updateGhost(_, ghost)
        local data = ghost:GetData()
        if data.MizukiEchoCannon ~= true then return end
        local shot = data.MizukiEchoShot
        if data.MizukiEchoAwaitingShot or not shot or not liveShots[shot] or shot.Removed then
            if shot and not shot.Removed then removeShot(shot) end
            ghost:Remove()
            return
        end
        ghost.Position = vector(data.MizukiEchoAnchor)
        ghost.Velocity = Vector.Zero
        updateGhostShadow(ghost)
    end

    local function collideGhost(_, ghost, enemy)
        local data = ghost:GetData()
        if data.MizukiEchoCannon ~= true then return end
        local shot = data.MizukiEchoShot
        if data.MizukiEchoAwaitingShot or not shot or not liveShots[shot] or shot.Removed
            or not eligible(shot.Player) or shot.FadeFrame or data.MizukiEchoKnifeMode
            or not enemy:IsVulnerableEnemy()
            or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return true end
        local frame, key = Game():GetFrameCount(), GetPtrHash(enemy)
        local previous = data.MizukiEchoContactClocks[key]
        if previous and previous.Seed == enemy.InitSeed and frame < previous.Next then return true end
        data.MizukiEchoContactClocks[key] = {Seed = enemy.InitSeed,
            Next = frame + data.MizukiEchoContactInterval}
        enemy:TakeDamage(data.MizukiEchoContactDamage, 0, EntityRef(ghost), 0)
        return true -- Never also apply a second native familiar collision hit.
    end

    local function renderGhost(_, ghost, renderOffset)
        local data = ghost:GetData()
        if data.MizukiEchoCannon ~= true then return end
        local shot = data.MizukiEchoShot
        if data.MizukiEchoAwaitingShot or not shot or not liveShots[shot] or shot.Removed then return end
        if data.MizukiEchoKnifeMode then
            if Mizuki.renderCannonKnifeLaserRoots then Mizuki.renderCannonKnifeLaserRoots(ghost, renderOffset) end
            return
        end
        local game, sprite = Game(), data.MizukiEchoBodySprite
        local room = game:GetRoom()
        local reflection = room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
        local position = vector(data.MizukiEchoDrawPosition)
        local hoverY = Mizuki.getCannonHoverOffset(game:GetFrameCount())
        position.Y = position.Y + (reflection
            and (data.MizukiEchoReflectionSpan - hoverY) or hoverY)
        sprite.Color = ghostColor(ghostAlpha(shot))
        sprite.Scale = vector(data.MizukiEchoScale)
        sprite.Rotation = data.MizukiEchoRotation * (reflection and -1 or 1)
        sprite.FlipX = data.MizukiEchoBodyFlipX
        sprite.FlipY = reflection
        sprite.Offset = Vector.Zero
        local screen = Isaac.WorldToScreen(position) + renderOffset
            - room:GetRenderScrollOffset() - game.ScreenShakeOffset
        if not Mizuki.renderCannonAttackAppearance(ghost, sprite, screen) then
            sprite:RenderLayer(0, screen, Vector.Zero, Vector.Zero)
            sprite:RenderLayer(1, screen, Vector.Zero, Vector.Zero)
        end
        Mizuki.renderSpecialBrimstoneIcon(ghost, position, renderOffset, sprite.Color.A)
    end

    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, initGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, updateGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_COLLISION, collideGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, renderGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE, updateLaser)
    Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER, CallbackPriority.LATE, syncInterpolatedKnife)
    Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, updateKnife)
    -- Run before ordinary on-hit handlers, so they see the replacement hit once.
    Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG,
        CallbackPriority.EARLY, scaleKnifeHit)
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, updateEchoes)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, clearAll, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
end
-- endregion Finite echoes

-- region Persistent echoes
do
    -- Persistent echoes are ordinary cannon entities owned by CheckFamiliar.
    -- Their explicit profile role is separate from their delayed pose history.
    -- No manual cannon spawning/removal, no secondary proc rolls, no new item API.

    function Mizuki.getPersistentCannonEchoMode(player)
        if not Mizuki.hasCannonEcho(player) then return nil end
        if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then return nil end
        if player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
            return "ludovico"
        end
        if Mizuki.usesAutomaticBeam(player) then return "automatic" end
    end

    function Mizuki.appendPersistentCannonEchoProfiles(player, profiles)
        local mode = Mizuki.getPersistentCannonEchoMode(player)
        local count = #profiles
        if mode == "ludovico" then
            -- Keep original members in their old order. With the doubled count,
            -- even slots preserve their old angles and odd slots fill the gaps.
            for member = 1, count do
                local original = profiles[member]
                original.OrbitSlot = (member - 1) * 2
                profiles[count + member] = {
                    EchoMode = mode,
                    OrbitSlot = (member - 1) * 2 + 1,
                    DamageMultiplier = original.DamageMultiplier
                        * Mizuki.CannonEchoDamageMultiplier,
                    ScaleMultiplier = original.ScaleMultiplier,
                }
            end
        elseif mode == "automatic" and count > 0 then
            -- Exactly one extra pair, trailing the first real pair. Box of Friends
            -- continues to own its original extra pairs, without exponential copies.
            profiles[count + 1] = {
                EchoMode = mode,
                DamageMultiplier = profiles[1].DamageMultiplier
                    * Mizuki.CannonEchoDamageMultiplier,
                ScaleMultiplier = profiles[1].ScaleMultiplier,
            }
        end
        return profiles
    end

    function Mizuki.applyPersistentCannonEchoProfile(cannon, profile)
        local data = cannon:GetData()
        local mode = profile and profile.EchoMode or nil
        if data.MizukiPersistentEchoMode ~= mode then
            -- A retained entity may change role after a reroll/reconciliation.
            data.MizukiContactDamageSchedules = nil
        end
        data.MizukiPersistentEchoMode = mode
    end

    function Mizuki.getPersistentEchoColor(base)
        return Mizuki.getCannonEchoColor(base, Mizuki.CannonEchoPersistentAlpha)
    end

    local poseFields = {
        "MizukiCannonAim", "MizukiPivotRenderOffset", "MizukiBasePivotRenderOffset",
        "MizukiCannonBodyRotation", "MizukiVerticalBodyXFactor",
        "MizukiReflectionBodyXFactor", "MizukiReflectionSpan", "MizukiRenderWorldOffset",
        "MizukiBobOffsetY", "MizukiIsIdle", "MizukiIdleRotationOffset",
        "MizukiAutoFireReturnTarget",
        "MizukiSpecialBrimstoneCurse",
        "MizukiCannonAttackAppearanceKey",
    }
    local function copyPoseValue(value)
        if type(value) == "userdata" or type(value) == "table" then
            return Vector(value.X, value.Y)
        end
        return value
    end

    function Mizuki.updateAutomaticCannonEchoPose(player, data, cannon, position, member, side, frame)
        if Mizuki.getPersistentCannonEchoMode(player) ~= "automatic" then
            data.MizukiAutomaticEchoHistory = nil
            return position
        end
        local cannonData = cannon:GetData()
        local histories = data.MizukiAutomaticEchoHistory or {}
        data.MizukiAutomaticEchoHistory = histories
        if member == 1 and not cannonData.MizukiPersistentEchoMode then
            local history = histories[side]
            if not history or history.Seed ~= cannon.InitSeed
                or history.Hash ~= GetPtrHash(cannon) or frame < history.Frame then
                history = {Seed = cannon.InitSeed, Hash = GetPtrHash(cannon), Samples = {}}
                histories[side] = history
            end
            history.Frame = frame
            local previous = history.Samples[frame]
            local sample = {Position = Vector(position.X, position.Y), Pose = {},
                Attack = previous and previous.Attack or nil}
            for _, field in ipairs(poseFields) do
                sample.Pose[field] = copyPoseValue(cannonData[field])
            end
            history.Samples[frame] = sample -- Repeated layout calls do not advance time.
            for age in pairs(history.Samples) do
                if age < frame - Mizuki.CannonEchoFollowDelay then history.Samples[age] = nil end
            end
        elseif cannonData.MizukiPersistentEchoMode == "automatic" then
            local history = histories[side]
            if not history then return position end
            local sample = history.Samples[frame - Mizuki.CannonEchoFollowDelay]
            if not sample then
                local oldest
                for age in pairs(history.Samples) do
                    if not oldest or age < oldest then oldest = age end
                end
                sample = oldest and history.Samples[oldest]
            end
            if not sample then return position end
            position = Vector(sample.Position.X, sample.Position.Y)
            for _, field in ipairs(poseFields) do
                cannonData[field] = copyPoseValue(sample.Pose[field])
            end
            -- Ordinary cannons publish a target and let UpdateCannonFamiliar
            -- move through Velocity, preserving native render interpolation.
            -- Only the hidden initial layout may snap; never teleport an
            -- already-following echo or erase its velocity every player update.
            if cannonData.MizukiAwaitingInitialLayout then
                cannon.Position, cannon.Velocity = position, Vector.Zero
                local settledFrame = cannonData.MizukiInitialLayoutFrame
                if settledFrame and frame > settledFrame then
                    cannonData.MizukiAwaitingInitialLayout = nil
                    cannonData.MizukiInitialLayoutFrame = nil
                elseif not settledFrame then
                    cannonData.MizukiInitialLayoutFrame = frame
                end
            end
            cannonData.MizukiDesiredPosition = position
            cannonData.MizukiPoseOffset = position - player.Position
            cannonData.MizukiMovementLag = Vector.Zero
            cannonData.MizukiLastPlayerPosition = Vector(player.Position.X, player.Position.Y)
            local original = data.MizukiCannons[side][1]
            local sourceData = original:GetData()
            -- A doorway carries the real layout, never the ghost's old-room lag.
            cannonData.MizukiLayoutOffset = copyPoseValue(sourceData.MizukiLayoutOffset)
                or (position - player.Position)
            cannonData.MizukiPendingRoomEntryOffset =
                copyPoseValue(sourceData.MizukiPendingRoomEntryOffset)
            -- Native entity sorting is Position.Y + DepthOffset: compensate for
            -- the lagged Y so the ghost stays just beneath the CURRENT real cannon.
            local current = history.Samples[frame]
            cannon.DepthOffset = (current and current.Position.Y or original.Position.Y)
                + original.DepthOffset - position.Y - ECHO_BELOW_SOURCE_DEPTH_OFFSET
        end
        return position
    end

    function Mizuki.getPersistentEchoKnifeMultiplier(knife)
        local data = knife:GetData()
        if data.MizukiCannonKnife ~= true then return nil end
        local cannon, player = data.MizukiCannonKnifeCannon, data.MizukiCannonKnifeOwner
        if not cannon or not cannon:Exists()
            or cannon.InitSeed ~= data.MizukiCannonKnifeCannonInitSeed
            or GetPtrHash(cannon) ~= data.MizukiCannonKnifeCannonPtrHash
            or not player or not player:Exists()
            or player.InitSeed ~= data.MizukiCannonKnifeOwnerInitSeed
            or GetPtrHash(player) ~= data.MizukiCannonKnifeOwnerPtrHash
            or not cannon.Player or GetPtrHash(cannon.Player) ~= GetPtrHash(player) then return nil end
        local mode = cannon:GetData().MizukiPersistentEchoMode
        if mode and mode == Mizuki.getPersistentCannonEchoMode(player) then
            -- Scale the actual native hit, never CollisionDamage: some knife
            -- phases ignore that field and others would otherwise be halved twice.
            return Mizuki.CannonEchoDamageMultiplier
        end
    end

    -- Attack state shares the pose clock. Unlike the visual warm-up fallback,
    -- firing requires an EXACT delayed sample: an old idle pose must never shoot.
    function Mizuki.getAutomaticCannonEchoAttack(data, side)
        local history = data.MizukiAutomaticEchoHistory
            and data.MizukiAutomaticEchoHistory[side]
        local sample = history and history.Samples[
            Game():GetFrameCount() - Mizuki.CannonEchoFollowDelay]
        local attack = sample and sample.Attack
        -- A pre-reload group lacks per-laser records; the next captured frame
        -- supplies them without guessing which original each echo belongs to.
        return attack and attack.Shots and attack or nil
    end

    function Mizuki.captureAutomaticCannonEchoAttacks(player, data)
        if Mizuki.getPersistentCannonEchoMode(player) ~= "automatic" then return end
        local frame = Game():GetFrameCount()
        for side = 1, 2 do
            local history = data.MizukiAutomaticEchoHistory
                and data.MizukiAutomaticEchoHistory[side]
            local sample = history and history.Samples[frame]
            if sample then
                local source = data.MizukiCannons[side] and data.MizukiCannons[side][1]
                local attack
                for _, beam in ipairs((data.MizukiActiveBeams or {})[side] or {}) do
                    if beam.Cannon == source and not beam.PersistentEchoMode
                        and beam.Automatic and not beam.Ending
                        and beam.Laser and beam.Laser:Exists() then
                        attack = attack or {Angles = {}, Shots = {}, DamageMultiplier = beam.DamageMultiplier}
                        attack.Angles[#attack.Angles + 1] = beam.DirectionOffset or 0
                        attack.Shots[#attack.Shots + 1] = {
                            Sequence = Mizuki.startEchoAttackRecording(beam.Laser, true),
                            SourceSeed = beam.Laser.InitSeed, SourceHash = GetPtrHash(beam.Laser),
                        }
                    end
                end
                sample.Attack = attack
            end
        end
    end

    function Mizuki.shouldHoldAutomaticCannonEchoBeam(data, side, beam)
        local attack = Mizuki.getAutomaticCannonEchoAttack(data, side)
        for _, shot in ipairs(attack and attack.Shots or {}) do
            if beam.PersistentEchoSourceSeed == shot.SourceSeed
                and beam.PersistentEchoSourceHash == shot.SourceHash then return true end
        end
        return false
    end

    function Mizuki.completeAutomaticEchoBeams(player, data)
        if Mizuki.getPersistentCannonEchoMode(player) ~= "automatic" then return end
        Mizuki.captureAutomaticCannonEchoAttacks(player, data)
        for side = 1, 2 do
            local attack = Mizuki.getAutomaticCannonEchoAttack(data, side)
            local cannons = data.MizukiCannons[side] or {}
            local ghost = cannons[#cannons]
            if attack and ghost and ghost:Exists()
                and ghost:GetData().MizukiPersistentEchoMode == "automatic" then
                local missingAngles, missingShots = {}, {}
                for index, shot in ipairs(attack.Shots) do
                    local exists = false
                    for _, beam in ipairs((data.MizukiActiveBeams or {})[side] or {}) do
                        if beam.Cannon == ghost and beam.PersistentEchoMode == "automatic"
                            and not beam.Ending and beam.Laser and beam.Laser:Exists()
                            and beam.PersistentEchoSourceSeed == shot.SourceSeed
                            and beam.PersistentEchoSourceHash == shot.SourceHash then
                            exists = true
                            break
                        end
                    end
                    if not exists then
                        missingAngles[#missingAngles + 1] = attack.Angles[index]
                        missingShots[#missingShots + 1] = shot
                    end
                end
                if #missingShots > 0 then
                    -- Replay resolved angles without rerolling volley synergies.
                    -- The source can already have stopped: short taps still replay
                    -- for their original length, shifted by the pose delay.
                    Mizuki.fireMizukiBeam(player, ghost:GetData().MizukiCannonAim,
                        0, true, side, nil, attack.DamageMultiplier, missingAngles, {Shots = missingShots})
                end
            end
        end
    end

    local function clearHistories()
        for index = 0, Game():GetNumPlayers() - 1 do
            Isaac.GetPlayer(index):GetData().MizukiAutomaticEchoHistory = nil
        end
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearHistories)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clearHistories)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearHistories)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, clearHistories, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
end
-- endregion Persistent echoes

-- region Xiaobotu C Section echoes
do
    Mizuki.FanEchoVariant = Isaac.GetEntityVariantByName("Mizuki Echo Fan")
    local shots, registered = {}, {}
    local FADE_FRAMES = 6
    local SHOOT_ANIMATION_FRAMES = 7 -- Same shot pose duration as the real fan.
    -- TEMPORARY: size/animation overrides remain disabled; only alpha is applied.
    -- Compare all source/replay pairs at matching native tear ages.

    local function vector(value) return Vector(value.X, value.Y) end
    local function applyEchoFetusColor(tear)
        if Mizuki.applyEchoAttackSequence(tear) then return end
        local data = tear:GetData()
        if data.MizukiFanFetus ~= true or data.MizukiFanEchoFetus ~= true then return end
        if tear:IsDead() then return end
        local alpha = Mizuki.CannonEchoReplayAlpha
        local baseColor = data.MizukiFanEchoFetusBaseColor
        if not baseColor then return end
        -- Restore the complete birth color, including colorize data. Only alpha
        -- changes for this echo; there is no additional fetus tint or color mask.
        local color = Color.Lerp(baseColor, baseColor, 0)
        color.A = alpha
        tear.Color = color
    end
    local function playAnimation(sprite, animation, frame)
        -- All four gbt float animations share the same 16-frame cadence.
        -- Changing the artwork must not restart that motion at frame zero.
        local phase = frame or sprite:GetFrame()
        sprite:Play(animation, true)
        sprite:SetFrame(phase)
    end
    local function sameEntity(a, b)
        -- API getters/callbacks may wrap the same native entity differently.
        return a and b and a:Exists() and b:Exists()
            and GetPtrHash(a) == GetPtrHash(b) and a.InitSeed == b.InitSeed
    end
    local function eligible(player)
        return Mizuki.hasCannonEcho(player)
            and player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
    end
    local function removeShot(shot)
        local ghost = shot.Ghost
        if ghost and ghost:Exists() and ghost:GetData().MizukiFanEcho == true then
            registered[GetPtrHash(ghost)] = nil
            ghost:Remove()
        end
        -- The fired fetus is a real attack and outlives its visual source.
        shots[shot] = nil
    end
    local function clearAll()
        for shot in pairs(shots) do removeShot(shot) end
        shots, registered = {}, {}
    end

    function Mizuki.queueFanEchoPhaseSync(familiar)
        for shot in pairs(shots) do
            if sameEntity(shot.Source, familiar) and shot.SourceSeed == familiar.InitSeed then
                shot.PhaseSyncPending = true
            end
        end
    end

    function Mizuki.recordFanEchoSample(familiar, fetuses, auxiliary)
        local player = familiar.Player
        if not fetuses or #fetuses == 0 or not player or not eligible(player) or Game():IsPaused() then return end
        local sprite = familiar:GetSprite()
        local frame = Game():GetFrameCount()
        -- A new firing round releases the previous waiting round. Familiars
        -- firing in the same game frame belong to one round, so they cannot
        -- trigger echoes that have only just been created by their siblings.
        for previous in pairs(shots) do
            if not previous.ReplayFrame and previous.Frame < frame
                and sameEntity(previous.Player, player) then
                previous.ReplayFrame = frame
            end
        end
        local position = vector(familiar.Position)
        local ghost = Isaac.Spawn(EntityType.ENTITY_FAMILIAR,
            Mizuki.FanEchoVariant, 0, position, Vector.Zero, player):ToFamiliar()
        ghost.Player = player
        registered[GetPtrHash(ghost)] = ghost
        Mizuki.setFanCSectionAppearance(ghost,
            familiar:GetData().MizukiFanCSectionAppearance == true)
        local ghostSprite = ghost:GetSprite()
        local direction = familiar:GetData().MizukiFanShotDirection
            or fetuses[1].Velocity
        local facingUp = direction.Y < -Mizuki.RuntimeParameters.AimDeadZone
            and math.abs(direction.Y) > math.abs(direction.X)
        local shootAnimation = facingUp and "FloatShootUp" or "FloatShoot"
        ghostSprite.PlaybackSpeed = sprite.PlaybackSpeed
        playAnimation(ghostSprite, facingUp and "FloatUp" or "Float", sprite:GetFrame())
        ghostSprite.FlipX = sprite.FlipX
        ghostSprite.Offset = vector(sprite.Offset)
        ghost.SpriteScale = vector(familiar.SpriteScale)
        ghost.DepthOffset = familiar.DepthOffset - ECHO_BELOW_SOURCE_DEPTH_OFFSET
        local color = Color.Lerp(familiar.Color, familiar.Color, 0)
        ghost.Color = Mizuki.getCannonEchoColor(color, Mizuki.CannonEchoWaitingAlpha)
        local shot = {
            Ghost = ghost, Player = player, PlayerSeed = player.InitSeed,
            Source = familiar, SourceSeed = familiar.InitSeed, PhaseSyncPending = true,
            Frame = frame, Position = position, Color = color, ShootAnimation = shootAnimation,
            Fetuses = {}, Auxiliary = auxiliary,
        }
        shots[shot] = true
        for _, fetus in ipairs(fetuses) do
            local recorded = {
                Velocity = vector(fetus.Velocity), Flags = fetus.TearFlags,
                ContinueVelocity = vector(fetus.ContinueVelocity), WaitFrames = fetus.WaitFrames,
                FetusColor = Color.Lerp(fetus.Color, fetus.Color, 0),
                Damage = fetus.CollisionDamage,
                AttackSequence = Mizuki.startEchoAttackRecording(fetus),
                Height = fetus.Height, FallingSpeed = fetus.FallingSpeed,
                FallingAcceleration = fetus.FallingAcceleration,
            }
            shot.Fetuses[#shot.Fetuses + 1] = recorded
        end
    end

    local function initGhost(_, ghost)
        ghost:GetData().MizukiFanEcho = true
        ghost.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        ghost.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        ghost.CollisionDamage = 0
        ghost:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        ghost:GetSprite():Play("Float", true)
    end

    local function updateEchoes()
        if Game():IsPaused() then return end
        local frame = Game():GetFrameCount()
        for shot in pairs(shots) do
            local ghost, player = shot.Ghost, shot.Player
            if not sameEntity(registered[GetPtrHash(ghost)], ghost)
                or not player:Exists() or player.InitSeed ~= shot.PlayerSeed
                or not eligible(player) or frame < shot.Frame then
                removeShot(shot)
            else
                -- Freeze each visual at its own firing origin, never follow xbt.
                ghost.Position = vector(shot.Position)
                ghost.Velocity = Vector.Zero
                if shot.ReplayFrame and not shot.StartedFrame and frame >= shot.ReplayFrame then
                    playAnimation(ghost:GetSprite(), shot.ShootAnimation)
                    if shot.Auxiliary then
                        Mizuki.replayFanPepper(player, shot.Auxiliary.Pepper, shot.Position)
                    end
                    for _, recorded in ipairs(shot.Fetuses) do
                        -- Anti-Gravity stores its launch speed separately while
                        -- Velocity is zero. Reusing zero as the firing request
                        -- produces a tear with no speed to resume on release.
                        local launchVelocity = recorded.WaitFrames > 0
                            and recorded.ContinueVelocity or recorded.Velocity
                        local tear = Mizuki.fireFanFetus(player, ghost,
                            launchVelocity:Normalized(), shot.Position, Mizuki.CannonEchoDamageMultiplier)
                        tear.Velocity = vector(recorded.Velocity)
                        tear.ContinueVelocity = vector(recorded.ContinueVelocity)
                        tear:SetWaitFrames(recorded.WaitFrames)
                        tear.TearFlags = recorded.Flags
                        tear.CollisionDamage = recorded.Damage * Mizuki.CannonEchoDamageMultiplier
                        tear.Height = recorded.Height
                        tear.FallingSpeed = recorded.FallingSpeed
                        tear.FallingAcceleration = recorded.FallingAcceleration
                        local tearData = tear:GetData()
                        tearData.MizukiFanEchoFetus = true
                        tearData.MizukiFanEchoFetusBaseColor = Color.Lerp(recorded.FetusColor, recorded.FetusColor, 0)
                        Mizuki.bindEchoAttackReplay(tear, recorded.AttackSequence, {
                            Alpha = Mizuki.CannonEchoReplayAlpha, Tint = false,
                            NativeConsumedFlags = TearFlags.TEAR_FETUS_BOMBER})
                        applyEchoFetusColor(tear)
                        Mizuki.spawnFanFetusBlood(player, ghost, tear, true)
                    end
                    shot.StartedFrame = frame
                end
                if shot.StartedFrame and not shot.FadeFrame
                    and frame - shot.StartedFrame >= SHOOT_ANIMATION_FRAMES then
                    -- Return to front idle after the shot, just like the fan.
                    playAnimation(ghost:GetSprite(), "Float")
                    shot.FadeFrame = frame
                end
                if shot.StartedFrame and not shot.FadeFrame then
                    ghost.Color = Mizuki.getCannonEchoColor(shot.Color, Mizuki.CannonEchoReplayAlpha)
                end
                if shot.FadeFrame then
                    local age = frame - shot.FadeFrame
                    if age >= FADE_FRAMES then
                        removeShot(shot)
                    else
                        ghost.Color = Mizuki.getCannonEchoColor(shot.Color,
                            Mizuki.CannonEchoReplayAlpha * (1 - age / FADE_FRAMES))
                    end
                end
                -- A creation or source-animation-change event requests one
                -- phase copy after all familiar updates. No source sprite is
                -- read between events; the echo advances independently then.
                if shot.PhaseSyncPending then
                    local source = shot.Source
                    if shots[shot] and source:Exists() and source.InitSeed == shot.SourceSeed then
                        local sourceSprite = source:GetSprite()
                        local animation = sourceSprite:GetAnimation()
                        if animation == "Float" or animation == "FloatUp"
                            or animation == "FloatShoot" or animation == "FloatShootUp" then
                            local ghostSprite = ghost:GetSprite()
                            ghostSprite.PlaybackSpeed = sourceSprite.PlaybackSpeed
                            ghostSprite:SetFrame(sourceSprite:GetFrame())
                        end
                    end
                    shot.PhaseSyncPending = nil
                end
            end
        end
    end

    local function updateEchoFetus(_, tear)
        if tear:GetData().MizukiFanFetus ~= true then return end
        applyEchoFetusColor(tear)
    end
    Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_TEAR_UPDATE, CallbackPriority.LATE, updateEchoFetus)
    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, initGhost, Mizuki.FanEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, function(_, ghost)
        if ghost:GetData().MizukiFanEcho == true
            and not sameEntity(registered[GetPtrHash(ghost)], ghost) then ghost:Remove() end
    end, Mizuki.FanEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, updateEchoes)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearAll)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, clearAll, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
end
-- endregion Xiaobotu C Section echoes
