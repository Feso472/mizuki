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
local ECHO_SHOT_SOUND_VOLUME = 0.45
local ECHO_SHOT_SOUND_PITCH = 1.15
local ECHO_KNIFE_MIN_FLIGHT_FRAMES = 1

-- region Finite echoes
do
    local states = {}
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
        if knife and knife:Exists() and isEchoKnife(knife) then knife:Remove() end
    end

    local function removeShot(shot)
        if shot.Removed then return end
        shot.Removed = true
        for _, child in ipairs(shot.Children) do
            if valid(child.SourceLaser, child.SourceLaserSeed) then
                child.SourceLaser:GetData().MizukiEchoCapture = nil
            end
            child.SourceLaser, child.SourceKnife = nil, nil
            local laser = child.Laser
            if laser and laser:Exists() and laser:GetData().MizukiEchoBeam == true then
                laser:Remove()
            end
            removeEchoKnife(child.Knife)
        end
        for _, ghost in ipairs(shot.Ghosts) do
            removeEchoKnife(ghost:GetData().MizukiEchoWaitingKnife)
            if ghost:Exists() and ghost:GetData().MizukiEchoCannon == true then
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
            and not Mizuki.usesAutomaticBeam(player)
            and not player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE)
    end

    local function captureInitializedParameters(child)
        local laser = child.SourceLaser
        if valid(laser, child.SourceLaserSeed) then
            -- The real laser's width callback has run before this module's update.
            -- Freeze only its initialization, never later changes in player stats.
            child.Damage = laser.CollisionDamage
            child.Flags = laser.TearFlags
            child.GridCollisionClass = laser.GridCollisionClass
            child.Color = color(laser.Color)
            child.Size = laser.Size
            child.SpriteScale = vector(laser.SpriteScale)
            if laser.FrameCount >= Mizuki.RuntimeParameters.NativeLaserInitFrames then
                laser:GetData().MizukiEchoCapture = nil
                child.SourceLaser = nil
            end
        else
            child.SourceLaser = nil
        end
        local knife = child.SourceKnife
        if valid(knife, child.SourceKnifeSeed) then
            if knife.CollisionDamage > 0 then child.KnifeDamage = knife.CollisionDamage end
            child.KnifeFlags = knife.TearFlags
            child.KnifeSpriteRotationOffset = getKnifeSpriteRotationOffset(knife)
            if not child.SourceLaser then child.SourceKnife = nil end
        else
            child.SourceKnife = nil
        end
    end

    local function applyKnifeDamage(knife)
        if not isEchoKnife(knife) then return end
        local data = knife:GetData()
        local child = data.MizukiEchoChild
        if child then
            -- Native Mom's Knife hits can ignore CollisionDamage (verified in the
            -- game: 1.3125 here still produced the source's full 15.75 damage).
            -- Keep this unscaled; scale the actual hit exactly once below, so a
            -- native phase that DOES use this field cannot be halved twice.
            knife.CollisionDamage = child.KnifeDamage
            knife.TearFlags = child.KnifeFlags
        end
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
        local knife = child.Shot.Player:FireKnife(ghost, 0, true, 0, 0)
        if not knife then return nil end
        local data = knife:GetData()
        data.MizukiEchoKnife = true
        data.MizukiEchoChild = child
        data.MizukiEchoFired = false
        data.MizukiEchoKnifeAge = 0
        knife.Parent = ghost
        knife.SpawnerEntity = child.Shot.Player
        knife.Visible = true
        knife.Scale = child.KnifeScale
        knife.Size = child.KnifeSize
        knife.SpriteScale = vector(child.KnifeSpriteScale)
        knife.Rotation = child.Direction:GetAngleDegrees()
        knife.SpriteRotation = knife.Rotation + child.KnifeSpriteRotationOffset
        knife.Color = ghostColor(ECHO_KNIFE_INITIAL_ALPHA)
        knife.DepthOffset = ghost.DepthOffset + ECHO_KNIFE_DEPTH_OFFSET
        knife.Position = child.KnifeOrigin - knife.PositionOffset
        knife.Velocity = Vector.Zero
        applyKnifeDamage(knife)
        return knife
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
        local ghost = Isaac.Spawn(EntityType.ENTITY_FAMILIAR,
            Mizuki.CannonEchoVariant, 0, vector(cannon.Position), Vector.Zero,
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
        data.MizukiEchoAnchor = vector(cannon.Position)
        data.MizukiEchoKnifeMode = beam.MomKnifeDriven == true
        data.MizukiEchoContactDamage = shot.Player.Damage
            * Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER
            * (source.MizukiContactDamageMultiplier or 1) * shot.DamageMultiplier
        data.MizukiEchoContactInterval = math.max(shot.Player.MaxFireDelay, 1) + 1
        data.MizukiEchoContactClocks = {}
        local poseOffset = source.MizukiPivotRenderOffset or Vector.Zero
        -- Freeze the base pose, not its animated hover displacement.
        data.MizukiEchoDrawPosition = cannon.Position + poseOffset
            + (source.MizukiRenderWorldOffset or Vector.Zero)
        data.MizukiEchoReflectionSpan = source.MizukiReflectionSpan or Mizuki.CANNON_FIRING_REFLECTION_SPAN
        data.MizukiEchoRotation = source.MizukiCannonBodyRotation or 0
        local scale = source.MizukiCannonBaseScale or shot.Player.SpriteScale
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
        state.Pending[side] = shot
        return shot
    end

    function Mizuki.captureCannonEchoBeam(shot, beam, charge, baseChargeFrames)
        if shot.Removed or not beam.Cannon or not beam.Cannon:Exists() then return end
        local laser = beam.Laser
        local key = GetPtrHash(beam.Cannon)
        local ghost = shot.GhostByCannon[key]
        if not ghost then
            ghost = makeGhost(shot, beam)
            shot.GhostByCannon[key] = ghost
        end
        local child = {Shot = shot, Ghost = ghost,
            Offset = Game():GetFrameCount() - shot.Frame,
            Origin = vector(laser.Position), PositionOffset = vector(laser.PositionOffset),
            Direction = vector(beam.Direction),
            -- A knife-driven laser is already shortened to 1 at release. Its
            -- launch range remains in the beam record, not current laser length.
            Distance = beam.MomKnifeDriven and beam.Distance or laser.MaxDistance,
            Variant = laser.Variant, ActiveDuration = beam.ActiveDuration,
            EndFrames = beam.EndFrames, Width = laser.Size,
            Damage = laser.CollisionDamage, Flags = laser.TearFlags,
            GridCollisionClass = laser.GridCollisionClass,
            Color = color(laser.Color), Size = laser.Size,
            SpriteScale = vector(laser.SpriteScale), DepthOffset = laser.DepthOffset,
            SourceLaser = laser, SourceLaserSeed = laser.InitSeed,
            KnifeMode = beam.MomKnifeDriven == true,
            KnifeCharge = math.max(0, math.min(charge / math.max(1, baseChargeFrames), 1))}
        if child.KnifeMode then
            local knife = beam.MomKnife
            if not knife or not knife:Exists() then return end
            child.SourceKnife, child.SourceKnifeSeed = knife, knife.InitSeed
            child.KnifeDamage = knife.CollisionDamage > 0 and knife.CollisionDamage
                or shot.Player.Damage
            child.KnifeFlags = knife.TearFlags
            child.KnifeScale, child.KnifeSize = knife.Scale, knife.Size
            child.KnifeSpriteScale = vector(knife.SpriteScale)
            child.KnifeOrigin = vector(knife.Position + knife.PositionOffset)
            child.KnifeSpriteRotationOffset = getKnifeSpriteRotationOffset(knife)
        end
        table.insert(shot.Children, child)
        laser:GetData().MizukiEchoCapture = child
        if child.KnifeMode and not ghost:GetData().MizukiEchoWaitingKnife then
            ghost:GetData().MizukiEchoWaitingKnife = createKnife(child)
        end
    end

    local function applyLaserSnapshot(laser, child)
        laser.CollisionDamage = child.Damage * child.Shot.DamageMultiplier
        laser.TearFlags = child.Flags
        -- ShootAngle defaults to walls-only even when the recorded player laser
        -- collides with rocks. Replay its collision class as well as its tear flags.
        laser.GridCollisionClass = child.GridCollisionClass
        -- Apply the body's ghost layer over the frozen native color, preserving
        -- Colorize. Always start from the snapshot, never last frame's overlay.
        local beamColor = color(child.Color)
        local overlay = ghostColor(ghostAlpha(child.Shot))
        beamColor.R = beamColor.R * overlay.R
        beamColor.G = beamColor.G * overlay.G
        beamColor.B = beamColor.B * overlay.B
        beamColor.A = beamColor.A * overlay.A
        beamColor.RO = beamColor.RO + overlay.RO
        beamColor.GO = beamColor.GO + overlay.GO
        beamColor.BO = beamColor.BO + overlay.BO
        laser.Color = beamColor
        if laser.FrameCount >= Mizuki.RuntimeParameters.NativeLaserInitFrames then
            laser.Size = child.Size
            if not child.Ending then laser.SpriteScale = vector(child.SpriteScale) end
        end
    end

    local function beginEnding(child)
        if child.Ending then return end
        child.Ending = true
        child.EndFrame = Game():GetFrameCount()
        if child.Laser and child.Laser:Exists() then
            child.Laser.Timeout = 0
            child.Laser.Shrink = true
        end
    end

    local function replayChild(child)
        captureInitializedParameters(child)
        child.Started = true
        child.StartFrame = Game():GetFrameCount()
        local laser = EntityLaser.ShootAngle(child.Variant, vector(child.Origin),
            child.Direction:GetAngleDegrees(), child.ActiveDuration,
            vector(child.PositionOffset), child.Ghost)
        child.Laser = laser
        laser:GetData().MizukiEchoBeam = true
        laser:GetData().MizukiEchoChild = child
        laser.DisableFollowParent = true
        laser.Position = vector(child.Origin)
        laser.PositionOffset = vector(child.PositionOffset)
        laser.Velocity = Vector.Zero
        laser.DepthOffset = child.DepthOffset
        laser:SetOneHit(false)
        laser:SetMaxDistance(child.Distance)
        applyLaserSnapshot(laser, child)
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
                data.MizukiEchoKnifeAge = 0
                knife.Charge = child.KnifeCharge
                knife:Shoot(child.KnifeCharge, child.Distance)
                knife.Velocity = Vector.Zero
                applyKnifeDamage(knife)
                laser:SetMaxDistance(1)
            end
        end
    end

    local function updateShot(shot, frame)
        for _, child in ipairs(shot.Children) do
            if child.SourceLaser or child.SourceKnife then captureInitializedParameters(child) end
        end
        if not shot.ReplayFrame then return end
        local age = frame - shot.ReplayFrame
        local allDone, playedSound = true, false
        for _, child in ipairs(shot.Children) do
            if not child.Started and age >= child.Offset then
                replayChild(child)
                if not playedSound then
                    local sound = child.Variant == LaserVariant.THICK_RED
                        or child.Variant == LaserVariant.THICKER_RED
                    SFXManager():Play(sound and SoundEffect.SOUND_BLOOD_LASER
                        or SoundEffect.SOUND_LASERRING_WEAK, ECHO_SHOT_SOUND_VOLUME, 0, false, ECHO_SHOT_SOUND_PITCH)
                    playedSound = true
                end
            end
            if child.Started and not child.Ending then
                local knife = child.Knife
                if child.KnifeMode and knife and knife:Exists() then
                    if frame > child.StartFrame and not knife:IsFlying() then
                        beginEnding(child)
                    elseif child.Laser and child.Laser:Exists() then
                        child.Laser.Timeout = child.ActiveDuration
                    end
                elseif frame - child.StartFrame >= child.ActiveDuration then
                    beginEnding(child)
                end
            end
            local laserAlive = child.Laser and child.Laser:Exists()
            local knifeAlive = child.Knife and child.Knife:Exists() and child.Knife:IsFlying()
            if not child.Started or laserAlive or knifeAlive then allDone = false end
        end
        if allDone or age >= MAX_REPLAY_FRAMES then
            shot.FadeFrame = shot.FadeFrame or frame
            for _, ghost in ipairs(shot.Ghosts) do
                if ghost:Exists() then
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
        if data.MizukiEchoCapture then captureInitializedParameters(data.MizukiEchoCapture) end
        if data.MizukiEchoBeam == true and data.MizukiEchoChild then
            applyLaserSnapshot(laser, data.MizukiEchoChild)
        end
    end

    local function updateKnife(_, knife)
        if not isEchoKnife(knife) then return end
        local data = knife:GetData()
        local child = data.MizukiEchoChild
        if not child or child.Shot.Removed or not child.Ghost:Exists() then
            removeEchoKnife(knife)
            return
        end
        applyKnifeDamage(knife)
        knife.Scale, knife.Size = child.KnifeScale, child.KnifeSize
        knife.SpriteScale = vector(child.KnifeSpriteScale)
        knife.Color = ghostColor(data.MizukiEchoFired and Mizuki.CannonEchoReplayAlpha or Mizuki.CannonEchoWaitingAlpha)
        local distance = data.MizukiEchoFired and math.max(0, knife:GetKnifeDistance()) or 0
        if data.MizukiEchoFired then
            data.MizukiEchoKnifeAge = data.MizukiEchoKnifeAge + 1
            if data.MizukiEchoKnifeAge > ECHO_KNIFE_MIN_FLIGHT_FRAMES and not knife:IsFlying() then
                beginEnding(child)
                removeEchoKnife(knife)
                return
            end
            if child.Laser and child.Laser:Exists() and not child.Ending then
                child.Laser:SetMaxDistance(math.max(1, distance))
            end
        end
        -- An echo knife has its own stationary parent and native flight clock.
        -- It never references the real cannon's persistent knife/motion source.
        local position = child.KnifeOrigin + child.Direction:Resized(distance)
        knife.Position = position - knife.PositionOffset
        knife.Velocity = Vector.Zero
        knife.Rotation = child.Direction:GetAngleDegrees()
        if data.MizukiEchoFired then
            knife.SpriteRotation = knife.Rotation + distance * Mizuki.KnifeParameters.SpinDegreesPerPixel
        else
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
        if data.MizukiEchoAwaitingShot or not shot or shot.Removed then
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
        if data.MizukiEchoAwaitingShot or not shot or shot.Removed
            or shot.FadeFrame or data.MizukiEchoKnifeMode
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
        if data.MizukiEchoCannon ~= true or data.MizukiEchoKnifeMode then return end
        local shot = data.MizukiEchoShot
        if data.MizukiEchoAwaitingShot or not shot or shot.Removed then return end
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
        sprite:RenderLayer(0, screen, Vector.Zero, Vector.Zero)
        sprite:RenderLayer(1, screen, Vector.Zero, Vector.Zero)
    end

    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, initGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, updateGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_COLLISION, collideGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, renderGhost, Mizuki.CannonEchoVariant)
    Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, updateLaser)
    Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, updateKnife)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_KNIFE_COLLISION, function(_, knife)
        applyKnifeDamage(knife) -- No return: native knife collision still executes.
    end)
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
        local tint = Color.Lerp(base, base, 0)
        tint.R, tint.G, tint.B = tint.R * ECHO_TINT.Red, tint.G * ECHO_TINT.Green, tint.B
        tint.A = tint.A * Mizuki.CannonEchoPersistentAlpha
        tint.RO, tint.GO, tint.BO = tint.RO + ECHO_TINT.RedOffset, tint.GO + ECHO_TINT.GreenOffset, tint.BO + ECHO_TINT.BlueOffset
        return tint
    end

    local poseFields = {
        "MizukiCannonAim", "MizukiPivotRenderOffset", "MizukiBasePivotRenderOffset",
        "MizukiCannonBodyRotation", "MizukiVerticalBodyXFactor",
        "MizukiReflectionBodyXFactor", "MizukiReflectionSpan", "MizukiRenderWorldOffset",
        "MizukiBobOffsetY", "MizukiIsIdle", "MizukiIdleRotationOffset",
        "MizukiAutoFireReturnTarget",
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
        return sample and sample.Attack
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
                        attack = attack or {Angles = {}, DamageMultiplier = beam.DamageMultiplier,
                            SourceSeed = beam.Laser.InitSeed, SourceHash = GetPtrHash(beam.Laser)}
                        attack.Angles[#attack.Angles + 1] = beam.DirectionOffset or 0
                    end
                end
                sample.Attack = attack
            end
        end
    end

    function Mizuki.shouldHoldAutomaticCannonEchoBeam(data, side, beam)
        local attack = Mizuki.getAutomaticCannonEchoAttack(data, side)
        return attack ~= nil and beam.PersistentEchoSourceSeed == attack.SourceSeed
            and beam.PersistentEchoSourceHash == attack.SourceHash
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
                local exists = false
                for _, beam in ipairs((data.MizukiActiveBeams or {})[side] or {}) do
                    if beam.Cannon == ghost and beam.PersistentEchoMode == "automatic"
                        and not beam.Ending and beam.Laser and beam.Laser:Exists()
                        and Mizuki.shouldHoldAutomaticCannonEchoBeam(data, side, beam) then
                        exists = true
                    end
                end
                if not exists then
                    -- Replay resolved angles without rerolling volley synergies.
                    -- The source can already have stopped: short taps still replay
                    -- for their original length, shifted by the pose delay.
                    Mizuki.fireMizukiBeam(player, ghost:GetData().MizukiCannonAim,
                        0, true, side, nil, attack.DamageMultiplier, attack.Angles, attack)
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
