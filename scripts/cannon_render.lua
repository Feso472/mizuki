-- Cannon bodies, reflections and charge feedback.
local Config = Mizuki.Config

local chargeBar = Sprite()

chargeBar:Load("gfx/chargebar_revelation.anm2", true)

function Mizuki.getCannonVisualScale(cannon)
    return Mizuki.applyArtScaleMultiplier(
        Mizuki.getCannonBaseScale(cannon),
        Config.CANNON_ART_SCALE_MULTIPLIER
    )
end

function Mizuki.getCannonBodyRenderScale(cannonData, visualScale, xFactor)
    return Vector(
        visualScale.X * math.abs(xFactor
            or cannonData.MizukiVerticalBodyXFactor or 1),
        visualScale.Y
    )
end

function Mizuki.updateCannonBodyGraphics(cannon, cannonData)
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
        and Config.LEFT_CANNON_SPRITESHEET or Config.CANNON_SPRITESHEET)
    sprite:ReplaceSpritesheet(1, graphicsMode == "left"
        and Config.LEFT_CANNON_LIGHT_SPRITESHEET or Config.CANNON_LIGHT_SPRITESHEET)
    sprite:LoadGraphics()
    sprite.Color = Mizuki.getCannonHiddenColor()
    cannonData.MizukiCannonGraphicsMode = graphicsMode
end

function Mizuki.getCannonBodyXFactor(side, direction, isIdle, idleSlot)
    local sideSign = side == 1 and -1 or 1
    if isIdle then
        return 2 * (idleSlot or (3 - side)) - 3
    end
    -- This signed projection controls the body's positive width and selects
    -- its pre-mirrored sheet. It is +/-1 when aiming horizontally, +/-0.75
    -- vertically, and passes through zero near the old graphics-mode switch.
    local aimX = math.max(-1, math.min(1, direction.X))
    local verticalFactor = sideSign * Config.VERTICAL_CANNON_BODY_X_MULTIPLIER
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
        reflectionSprite:Load(Config.CANNON_ANM2, true)
        reflectionSprite:ReplaceSpritesheet(0, graphicsMode == "left"
            and Config.LEFT_CANNON_SPRITESHEET or Config.CANNON_SPRITESHEET)
        reflectionSprite:ReplaceSpritesheet(1, graphicsMode == "left"
            and Config.LEFT_CANNON_LIGHT_SPRITESHEET or Config.CANNON_LIGHT_SPRITESHEET)
        reflectionSprite:LoadGraphics()
        reflectionSprite:Play("Idle", true)
        sprites[graphicsMode] = reflectionSprite
    end
    reflectionSprite:SetFrame(sourceSprite:GetAnimation(), sourceSprite:GetFrame())
    return reflectionSprite
end

-- Re-draw the cannon that the engine was told to draw fully transparent (see
-- updateCannonPositions). Every pass except the water reflection pass draws the
-- body exactly where the entity is. Idle reflections keep the engine's native
-- mirror; active reflections cancel it and draw a separate body projection.
--
-- The reflected bob still moves opposite the body about the water plane.

function Mizuki:RenderCannon(cannon, renderOffset, renderAfterLudovicoRing, renderSwordReturn)
    local player = cannon.Player
    if not player or not Mizuki.isMizuki(player) then
        return
    end
    local game = Game()
    local room = game:GetRoom()
    local cannonData = cannon:GetData()
    -- Returning sword bodies are supplied once by the existing final pass,
    -- even if a native familiar callback still arrives while Visible=false.
    if cannonData.MizukiSpiritSwordShadowReturning and renderSwordReturn ~= true then return end
    if cannonData.MizukiAwaitingInitialLayout or cannonData.MizukiGuillotineDisplaySuppressed
        or cannonData.MizukiTech2EchoSuppressed or cannonData.MizukiSpiritSwordBodyHidden then
        -- Visible is normally already false, but keep the explicit redraw path
        -- closed as well in case render/update callback order changes.
        cannon:GetSprite().Color = Mizuki.getCannonHiddenColor()
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
        sprite.Color = Mizuki.getCannonHiddenColor()
        sprite.FlipY = false
        cannon.SpriteScale = Mizuki.getCannonVisualScale(cannon)
        return
    end

    local sprite = cannon:GetSprite()
    local originalColor = sprite.Color

    -- Reassert the complete player-scaled transform before the explicit body
    -- draw; the native shadow intentionally uses this same scale.
    local bodyScale = Mizuki.getCannonVisualScale(cannon)
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
            span = Mizuki.getCannonReflectionSpan(player, isIdle)
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
    local basePivotRenderOffset = Mizuki.getCannonKnifeBodyPivot(cannon)
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
    local bodyRotation = cannonData.MizukiCannonBodyRotation or 0
    bodySprite.Rotation = bodyRotation
    bodySprite.Scale = Mizuki.getCannonBodyRenderScale(
        cannonData, bodyScale, bodyXFactor
    )
    local flipBase = cannonData.MizukiIdleFlipBaseRotation or bodySprite.Rotation
    local _, flipX, flipY = Mizuki.getCannonIdleFlipTransform(flipBase, cannonData.MizukiIdleFlipProgress,
        cannonData.MizukiIdleAngleMirrorProgress)
    local compression = Mizuki.getCannonScreenCompression(flipBase, cannonData.MizukiIdleScreenXScale)
    bodySprite.Scale = Vector(bodySprite.Scale.X * compression.X * flipX,
        bodySprite.Scale.Y * compression.Y * flipY)
    -- Native RenderLayer (0x409E03..0x409E3F) negates Rotation when X scale is
    -- negative. Compensate the API input so the displayed angle remains the
    -- already-mirrored world pose, rather than reflecting it a second time.
    if bodySprite.Scale.X < 0 then bodySprite.Rotation = -bodyRotation end
    bodySprite.Offset = Vector.Zero
    -- Force the sprite visible for this draw while keeping whatever colour it
    -- arrived with, so a tint applied elsewhere is not thrown away.
    local bodyColor = Color(
        originalColor.R, originalColor.G, originalColor.B,
        1, originalColor.RO, originalColor.GO, originalColor.BO
    )
    -- Sample the player's live colour only for the manual body draw. Native
    -- getter references cannot be multiplied directly. Lerp makes an owned
    -- Color value, retaining Colorize; replacements copy this pose colour.
    local playerColor = Color.Lerp(player.Color, player.Color, 0)
    bodySprite.Color = bodyColor * playerColor
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
    local renderedSpiritSword = not renderedMomKnife and Mizuki.renderCannonSpiritSword
        and Mizuki.renderCannonSpiritSword(cannon, bodySprite, bodyRenderPosition, cancelWaterMirror)
    if not renderedMomKnife and not renderedSpiritSword then
        local deadEyeIntensity = cannonData.MizukiDeadEyeIntensity
        if not cannonData.MizukiPersistentEchoMode
            and (cannonData.MizukiIsIdle or not cannonData.MizukiDeadEyeAttack) then
            deadEyeIntensity = Mizuki.getDeadEyeIntensity(player)
        end
        Mizuki.renderDeadEyeGlow(cannon, bodyRenderPosition, bodySprite.Scale,
            bodySprite.Color.A, deadEyeIntensity, bodyRotation)
        if not Mizuki.renderCannonAttackAppearance(cannon, bodySprite, bodyRenderPosition) then
            bodySprite:RenderLayer(0, bodyRenderPosition, Vector.Zero, Vector.Zero)
            bodySprite:RenderLayer(1, bodyRenderPosition, Vector.Zero, Vector.Zero)
        end
        Mizuki.renderSpecialBrimstoneIcon(cannon, worldPosition + Vector(0, bodyBobY),
            renderOffset, bodySprite.Color.A, bodyRenderPosition)
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
        sprite.Color = Mizuki.getCannonHiddenColor()
        sprite.FlipY = false
        cannon.SpriteScale = bodyScale
    else
        sprite.Color = originalColor
    end
end

function Mizuki:RenderLudovicoCannonsAboveRing(laser, renderOffset)
    local laserData = laser:GetData()
    if not laserData.MizukiIsLudovicoRing then return end

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

-- Draw after the selected familiar, or after each visible sword blade. Both
-- paths use the body's standard charge-bar offsets and camera transform.
function Mizuki:RenderChargeBar(cannon, renderOffset, swordRenderPass)
    local player = cannon.Player
    if not player or not Mizuki.isMizuki(player) then
        return
    end

    local game = Game()
    local room = game:GetRoom()
    local cannonData = cannon:GetData()
    if cannonData.MizukiAwaitingInitialLayout or cannonData.MizukiGuillotineDisplaySuppressed then
        return
    end
    local data = player:GetData()
    local sword = data.MizukiSpiritSwordWeaponActive and Mizuki.usesCannonSpiritSword(player)
    -- Hidden familiar bodies do not own the sword's visible render pass.
    if (sword and not swordRenderPass) or (swordRenderPass and not sword) then return end
    -- The charge bar belongs to the body only. Without this guard the
    -- reflection pass would draw a second, unmirrored bar over the real one.
    if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then
        return
    end
    if Mizuki.usesAutomaticBeam(player)
        or (data.MizukiTechXInput and data.MizukiTechXInput.HideChargeBar) then
        return
    end
    local shooting = sword and data.MizukiSpiritSwordShooting
    local charge = sword and (shooting and shooting.Charge or 0) or (data.MizukiCharge or 0)
    if charge <= 0 then
        return
    end
    if Mizuki.isBerserkClubActive(player)
        and not Mizuki.shouldRenderBerserkClubChargeBar(data) then
        return
    end

    -- Spin charge has its independent head bar. This circle belongs only to
    -- the hand that will actually release the ranged charged attack.
    local side = sword and Mizuki.getSpiritSwordChargingSide(player, data)
        or Mizuki.getNextCannonFiringSide(player, data)
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

        Mizuki.prunePlayerCannons(data)
        local ownerCannon = data.MizukiCannons[side][1]
        if ownerCannon then
            data.MizukiChargeBarOwnerHash = GetPtrHash(ownerCannon)
        end
    end

    if data.MizukiChargeBarOwnerHash ~= GetPtrHash(cannon) then
        return
    end

    local fullFrames = sword and shooting and shooting.FullFrames or (not sword and data.MizukiChargeBarFullFrames)
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
            math.min(charge / (sword and shooting.Profile
                or Mizuki.getChargeProfile(player)).MaxFrames, 1) * Mizuki.WeaponParameters.ChargeBarProgressFrames
        )
        chargeBar:Play("Charging", true)
        chargeBar:SetFrame("Charging", frame)
    end

    chargeBar.Color = Config.CHARGE_BAR_COLOR
    chargeBar.Scale = Config.CHARGE_BAR_SCALE
    local cannonSprite = cannon:GetSprite()
    -- The body's pose is kept in the data (the sprite itself stays straightened
    -- for the engine's shadow draw). Compose the same visual-only pivot, render
    -- plane and hover offsets used by the hand-drawn body without moving the
    -- cannon entity or its attack geometry.
    local swordPosition, swordRotation
    if sword then swordPosition, swordRotation = Mizuki.getSpiritSwordChargeBarAnchor(cannon) end
    if sword and not swordPosition then return end
    local bodyRotation = swordRotation or cannonData.MizukiCannonBodyRotation
        or cannonSprite.Rotation
    local graphicsWeight = sword and 0 or (1 + (cannonData.MizukiVerticalBodyXFactor or 1)) * 0.5
    local graphicsOffset = Config.CHARGE_BAR_NORMAL_GRAPHICS_OFFSET:Rotated(
        bodyRotation
    ) * graphicsWeight

    local bodyWorldPosition = swordPosition or (Mizuki.getCannonMomKnifeBodyPosition
        and Mizuki.getCannonMomKnifeBodyPosition(cannon))
    bodyWorldPosition = bodyWorldPosition or (cannon.Position
        + (cannonData.MizukiPivotRenderOffset or Vector.Zero)
        + (cannonData.MizukiRenderWorldOffset or Vector.Zero)
        + Vector(0, cannonData.MizukiBobOffsetY or 0))
    local renderPosition = Isaac.WorldToScreen(bodyWorldPosition) + renderOffset
        + Config.CHARGE_BAR_OFFSET:Rotated(bodyRotation)
        + graphicsOffset
        - room:GetRenderScrollOffset() - game.ScreenShakeOffset

    -- The Revelation charge bar separates its art into bg (0), bar (1), and
    -- the inward-contracting outer circle (2). Mizuki only uses the circle.
    chargeBar:RenderLayer(2, renderPosition)
end

-- Low-rate cooldown feedback for blindfolded Mizuki. Tear Bar's native
-- CanShoot/FireDelay checks cannot observe either of these custom timers.
function Mizuki.getLowFireRateCooldown(player)
    local data = player:GetData()
    local cSection = Mizuki.usesCSectionWeapon(player)
    if not cSection and (Mizuki.isBerserkClubActive(player) or Mizuki.usesCannonTechX(player)
        or Mizuki.usesLudovicoWeapon(player)) then return end
    local remaining, interval, animation
    if cSection then
        -- Read real gbt timers, never echoes or another player's familiar.
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
            Mizuki.FanVariant, -1, false, false)) do
            local familiar = entity:ToFamiliar()
            if familiar and familiar:Exists() and Mizuki.isSameEntity(familiar.Player, player) then
                local fan = familiar:GetData()
                if fan.MizukiFanFetusInterval and fan.MizukiFanFetusCooldown
                    and (not remaining or fan.MizukiFanFetusCooldown < remaining) then
                    remaining, interval = fan.MizukiFanFetusCooldown, fan.MizukiFanFetusInterval
                end
            end
        end
        animation = "ChargingTear"
    elseif not Mizuki.usesAutomaticBeam(player) and not Mizuki.usesChargedBeam(player) then
        remaining, interval = data.MizukiDirectBeamCooldown, data.MizukiDirectBeamInterval
        animation = "ChargingLaser"
    end
    -- Match Tear Bar's <= 1.00 shots/sec threshold. Already charged weapons
    -- retain their existing cannon charge display rather than a second bar.
    if not interval or not remaining or interval < Mizuki.RuntimeParameters.LogicFramesPerSecond then return end
    return math.max(0, math.min(remaining, interval)), interval, animation
end

local lowFireRateBar

local lowFireRateBarUsesTearBar

function Mizuki:RenderLowFireRateBar(player, renderOffset)
    if not Mizuki.isMizuki(player) then return end
    local game = Game()
    local room = game:GetRoom()
    if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then return end
    local data = player:GetData()
    if player:IsDead() or not player.Visible then
        data.MizukiLowFireRateBar = nil
        return
    end
    local remaining, interval, animation = Mizuki.getLowFireRateCooldown(player)
    local state = data.MizukiLowFireRateBar or {Alpha = 0, Progress = 1}
    data.MizukiLowFireRateBar = state
    local frame = game:GetFrameCount()
    if not game:IsPaused() and state.Frame ~= frame then
        state.Frame = frame
        state.Alpha = math.max(0, math.min(1, state.Alpha + (interval and 0.1 or -0.1)))
        if interval then
            state.Progress = 1 - remaining / interval
            state.Animation = animation
        end
    end
    if state.Alpha <= 0 then return end
    if not lowFireRateBar then
        lowFireRateBar = Sprite()
        -- Optional reuse of the installed Tear Bar art, not its native timers.
        -- Without that mod, the vanilla Revelation bar is self-contained.
        lowFireRateBarUsesTearBar = LowFirerateChargeBar ~= nil
        lowFireRateBar:Load(lowFireRateBarUsesTearBar and "gfx/lfrc_chargebar.anm2"
            or "gfx/chargebar_revelation.anm2", true)
    end
    lowFireRateBar:SetFrame(lowFireRateBarUsesTearBar and state.Animation or "Charging",
        math.floor(state.Progress * Mizuki.WeaponParameters.ChargeBarProgressFrames))
    lowFireRateBar.Color = Color(1, 1, 1, state.Alpha)
    local position = Isaac.WorldToScreen(player.Position) + (renderOffset or Vector.Zero)
        - room:GetRenderScrollOffset() - game.ScreenShakeOffset + Vector(0, 14)
    if lowFireRateBarUsesTearBar then
        lowFireRateBar:Render(position, Vector.Zero, Vector.Zero)
    else
        lowFireRateBar:RenderLayer(0, position)
        lowFireRateBar:RenderLayer(1, position)
    end
end
