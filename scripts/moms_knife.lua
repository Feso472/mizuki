-- region Knife parameters
-- The real knife and its echo share the same distance-to-spin conversion.
Mizuki.KnifeParameters = { SpinDegreesPerPixel = 12, SpinChargeThreshold = 1 / 3 }
-- endregion Knife parameters

local MOMS_KNIFE = CollectibleType.COLLECTIBLE_MOMS_KNIFE
local KNIFE_LASER_ROOT_ANM2 = "gfx/1000.126_Tech Dot.anm2"
local knifeLaserRoots = {}
local multidimensionalKnifeSources = {}
local getKnifeMotionSource
local restoreMultidimensionalKnife
local KNIFE_STATE_FOLLOW = "follow"
local KNIFE_STATE_OUTBOUND = "outbound"
local KNIFE_STATE_RETURNING = "returning"
local KNIFE_VELOCITY_EPSILON = Mizuki.RuntimeParameters.VectorEpsilon
local KNIFE_DISTANCE_EPSILON = Mizuki.RuntimeParameters.DistanceEpsilon
local KNIFE_SPIN_DEGREES_PER_PIXEL = Mizuki.KnifeParameters.SpinDegreesPerPixel
local LUDOVICO_KNIFE_FOLLOW_OUTWARD_OFFSET = 20
-- Native Isaac.WorldToScreen uses this scale before position-dependent rounding
-- (0x87028A and 0x8702F5). Sprite-local offsets must not inherit that rounding.
local WORLD_TO_SCREEN_SCALE = 0.65
local KNIFE_FLIGHT_ANCHOR_VARIANT = Isaac.GetEntityVariantByName("Mizuki Knife Flight Anchor")
local KNIFE_FLIGHT_ANCHOR_ANM2 = "gfx/entities/mizuki/knife_flight_anchor.anm2"

function Mizuki.cannonKnifeNeedsFlightAnchor(player, variant, berserk)
    if berserk then return variant == 2 or variant == 3 end
    -- Native update checks the weapon cache, not item ownership. Both Epic
    -- Fetus and Spirit Sword can leave our ordinary knife without Knife type.
    return variant == 0 and not player:HasWeaponType(WeaponType.WEAPON_KNIFE)
end

local function clearKnifeFlightAnchorArtwork(anchor)
    local data = anchor:GetData()
    if data.MizukiKnifeFlightAnchor ~= true or data.MizukiFlightAnchorBlankSprite == true then return end
    anchor:GetSprite():Load(KNIFE_FLIGHT_ANCHOR_ANM2, true)
    anchor:GetSprite():Play("Idle", true)
    data.MizukiFlightAnchorBlankSprite = true
end

local function attachKnifeFlightAnchor(knife, cannon)
    local data = knife:GetData()
    if data.MizukiBerserkCollisionProxy ~= true
        and data.MizukiKnifeFlightAnchorRequired ~= true then return end
    local anchor = data.MizukiKnifeFlightAnchor
    if not anchor or not anchor:Exists() then
        anchor = Isaac.Spawn(EntityType.ENTITY_EFFECT, KNIFE_FLIGHT_ANCHOR_VARIANT, 0,
            cannon.Position, Vector.Zero, cannon.Player):ToEffect()
        local anchorData = anchor:GetData()
        anchorData.MizukiKnifeFlightAnchor = true
        anchorData.MizukiFlightAnchorKnife = knife
        anchorData.MizukiFlightAnchorKnifeSeed = knife.InitSeed
        anchorData.MizukiFlightAnchorKnifeHash = GetPtrHash(knife)
        anchorData.MizukiFlightAnchorCannon = cannon
        anchorData.MizukiFlightAnchorCannonSeed = cannon.InitSeed
        anchorData.MizukiFlightAnchorCannonHash = GetPtrHash(cannon)
        -- Keep the parent in the engine's active passes, just like its knife.
        -- Hide only the artwork; the parent is not a disabled entity.
        anchor.Visible = true
        anchor.Color = Color(1, 1, 1, 0)
        anchor.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        anchor.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        anchor:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        data.MizukiKnifeFlightAnchor = anchor
    end
    clearKnifeFlightAnchorArtwork(anchor)
    anchor.Parent = cannon.Player
    anchor.Visible = true
    anchor.Color = Color(1, 1, 1, 0)
    anchor.Position = cannon.Position
    anchor.Velocity = Mizuki.renderCannonSpiritSword(cannon)
        and Vector(cannon.Velocity.X, cannon.Velocity.Y) or Vector.Zero
    knife.Parent = anchor
    knife.SubType = 0
    data.MizukiBerserkFlightClock = nil
end

if KNIFE_FLIGHT_ANCHOR_VARIANT > 0 then
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, anchor)
    local data = anchor:GetData()
    -- The registered variant is reserved for this invisible parent entity.
    if data.MizukiKnifeFlightAnchor ~= true then anchor:Remove(); return end
    clearKnifeFlightAnchorArtwork(anchor)
    local knife, cannon = data.MizukiFlightAnchorKnife, data.MizukiFlightAnchorCannon
    if not knife or not knife:Exists() or knife.InitSeed ~= data.MizukiFlightAnchorKnifeSeed
        or GetPtrHash(knife) ~= data.MizukiFlightAnchorKnifeHash
        or (knife:GetData().MizukiBerserkCollisionProxy ~= true
            and knife:GetData().MizukiKnifeFlightAnchorRequired ~= true)
        or not knife:GetData().MizukiKnifeFlightAnchor
        or GetPtrHash(knife:GetData().MizukiKnifeFlightAnchor) ~= GetPtrHash(anchor)
        or not cannon or not cannon:Exists() or cannon.InitSeed ~= data.MizukiFlightAnchorCannonSeed
        or GetPtrHash(cannon) ~= data.MizukiFlightAnchorCannonHash then
        anchor:Remove()
        return
    end
    local knifeData = knife:GetData()
    if knifeData.MizukiBerserkCollisionProxy ~= true
        and not Mizuki.cannonKnifeNeedsFlightAnchor(cannon.Player, knife.Variant,
            knifeData.MizukiBerserkClub == true) then
        -- Restore the familiar parent before removing this explicitly owned
        -- anchor, so the native knife never sees a deleted parent.
        if Mizuki.isSameEntity(knife.Parent, anchor) then knife.Parent = cannon end
        knifeData.MizukiKnifeFlightAnchorRequired = nil
        anchor:Remove()
        return
    end
    anchor.Position = cannon.Position
    anchor.Velocity = Mizuki.renderCannonSpiritSword(cannon)
        and Vector(cannon.Velocity.X, cannon.Velocity.Y) or Vector.Zero
    anchor.Visible = true
    anchor.Color = Color(1, 1, 1, 0)
end, KNIFE_FLIGHT_ANCHOR_VARIANT)
end

local function hasCannonKnifeTinyPlanet(knife, cannon, motionSource)
    local source = motionSource or knife
    local player = cannon and cannon.Player
    -- Our injected flag must not keep enabling the item after it is removed.
    if player then
        return player:HasCollectible(CollectibleType.COLLECTIBLE_TINY_PLANET)
    end
    return (source.TearFlags & TearFlags.TEAR_ORBIT) ~= TearFlags.TEAR_NORMAL
end

local function sameEntity(entity, initSeed, ptrHash)
    return entity
        and entity:Exists()
        and entity.InitSeed == initSeed
        and GetPtrHash(entity) == ptrHash
end

function Mizuki.getCannonKnifeBodyPivot(cannon)
    local data = cannon:GetData()
    return data.MizukiBasePivotRenderOffset or data.MizukiPivotRenderOffset or Vector.Zero
end

local function getCannonBodyPosition(cannon)
    if Mizuki.renderCannonSpiritSword(cannon) then
        return Mizuki.getSpiritSwordMomKnifePosition(cannon)
            or cannon.Position
    end
    local data = cannon:GetData()
    local bobY = data.MizukiLudovicoOrbiting
        and 0
        or (data.MizukiBobOffsetY or 0)
    -- Layout supplies the weapon's pivot at the shared character scale.
    local pivotRenderOffset = Mizuki.getCannonKnifeBodyPivot(cannon)
    return cannon.Position
        + pivotRenderOffset
        + (data.MizukiRenderWorldOffset or Vector.Zero)
        + Vector(0, bobY)
end

local function getCannonKnifeFollowOffset(cannon)
    local player = cannon.Player
    if not player or not player:Exists() then
        return Vector.Zero
    end

    local cannonData = cannon:GetData()
    -- Ordinary attacks carry this offset on the hidden cannon itself, so the
    -- knife and its laser have the same origin. Ludovico has a separate ring
    -- layout and keeps its existing knife-only tangent offset.
    if not cannonData.MizukiLudovicoOrbiting then
        return Vector.Zero
    end

    local aim = cannonData.MizukiCannonAim
    if not aim or aim:Length() <= KNIFE_VELOCITY_EPSILON then
        return Vector.Zero
    end

    local baseScale = cannonData.MizukiCannonBaseScale
        or player.SpriteScale
        or Vector.One
    return aim:Normalized():Resized(
        LUDOVICO_KNIFE_FOLLOW_OUTWARD_OFFSET * math.abs(baseScale.X)
    )
end

local function getCannonKnifeFollowPosition(cannon)
    return getCannonBodyPosition(cannon)
        + getCannonKnifeFollowOffset(cannon)
end

local function getCannonKnifeRotation(cannon)
    local data = cannon:GetData()
    if data.MizukiCannonBodyRotation ~= nil then
        -- The cannon sprite points up at rotation 0; Mom's Knife points right.
        return data.MizukiCannonBodyRotation - 90
    end
    local aim = data.MizukiCannonAim or Vector(0, -1)
    return aim:GetAngleDegrees()
end

local function getHeldBoneDrawRotation(knife, cannon)
    local bodyRotation = cannon and cannon:Exists() and cannon:GetData().MizukiCannonBodyRotation
    -- The held bone artwork follows the cannon body's pose. Converting that
    -- pose to Mom's Knife direction subtracts 90 degrees and is inappropriate
    -- for this redraw now that its physical carrier is an ordinary knife.
    if bodyRotation == nil then bodyRotation = knife.Rotation + 90 end
    return bodyRotation + Mizuki.BerserkClubParameters.HeldBodyRotationOffset
end

local function syncHeldBoneSpriteRotation(knife)
    local data = knife:GetData()
    if data.MizukiBerserkClub == true and (Mizuki.getCannonKnifeArtVariant(knife) == 2 or Mizuki.getCannonKnifeArtVariant(knife) == 3)
        and not data.MizukiBerserkSwing and not knife:IsFlying() then
        knife.SpriteRotation = getHeldBoneDrawRotation(knife, data.MizukiCannonKnifeCannon)
    end
end

local function getHeldKnifePosition(knife, cannon)
    local position = getCannonKnifeFollowPosition(cannon)
    local data = knife:GetData()
    if data.MizukiBerserkClub == true and (Mizuki.getCannonKnifeArtVariant(knife) == 2 or Mizuki.getCannonKnifeArtVariant(knife) == 3)
        and not data.MizukiBerserkSwing and not knife:IsFlying()
        and cannon:GetData().MizukiIsIdle == true then
        position = position + Vector(0, 20 * math.abs(knife.SpriteScale.Y))
    end
    return position
end

local function setKnifeAtVisualPosition(knife, visualPosition)
    -- EntityKnife renders its artwork at Position + PositionOffset. Keep the
    -- requested point as the artwork position and leave the real collision at
    -- the knife's native offset below it, in both follow and attack states.
    knife.Position = visualPosition - knife.PositionOffset
end

local function captureCannonKnifeBaseScale(knife, knifeData)
    if knifeData.MizukiBerserkCollisionProxy == true then
        knifeData.MizukiCannonKnifeBaseSize = 16
    end
    if knifeData.MizukiCannonKnifeBaseScale ~= nil then
        return
    end
    knifeData.MizukiCannonKnifeBaseScale = knife.Scale
    knifeData.MizukiCannonKnifeBaseSpriteScale = Vector(
        knife.SpriteScale.X,
        knife.SpriteScale.Y
    )
    knifeData.MizukiCannonKnifeBaseSize = knifeData.MizukiBerserkCollisionProxy == true and 16 or knife.Size
    local sizeMulti = knife.SizeMulti or Vector.One
    knifeData.MizukiCannonKnifeBaseSizeMulti = Vector(sizeMulti.X, sizeMulti.Y)
end

local function applyCannonKnifeScale(knife, cannon, motionSource)
    local knifeData = knife:GetData()
    captureCannonKnifeBaseScale(knife, knifeData)

    local cannonData = cannon:GetData()
    local multiplier = cannonData.MizukiCannonBaseScale
    if not multiplier then
        local player = cannon.Player
        local playerScale = player and player:Exists()
            and player.SpriteScale
            or Vector.One
        local ludovicoScale = cannonData.MizukiLudovicoOrbiting
            and (cannonData.MizukiLudovicoScaleMultiplier or 1)
            or 1
        multiplier = Vector(
            playerScale.X * ludovicoScale,
            playerScale.Y * ludovicoScale
        )
    end
    -- Independent sword hitboxes use the attack's native tear parameter scale.
    -- Apply that same absolute scale to the actual blade, never multiply an
    -- already character-scaled knife by it a second time. Ordinary idle and
    -- non-sword knives retain the cannon scale above.
    local beam = knifeData.MizukiCannonKnifeBeam
    local child = knifeData.MizukiEchoKnife == true and knifeData.MizukiEchoChild
    local swordBlade = knifeData.MizukiBerserkClub ~= true
        and (knifeData.MizukiCannonKnife == true or knifeData.MizukiEchoKnife == true)
        and ((Mizuki.renderCannonSpiritSword(cannon))
            or (beam and beam.SpiritSwordDriven == true and knife:IsFlying())
            or (child and child.SpiritSwordKnifeFromHilt == true))
    if swordBlade and Mizuki.getSpiritSwordWeaponScale then
        local attack = knifeData.MizukiSpiritSwordThrowAttack
            or (child and child.SpiritSwordThrowSource)
            or cannonData.MizukiSpiritSwordAttack
        local scale = attack and attack.HitboxScale and attack.HitboxScale.X
            or Mizuki.getSpiritSwordWeaponScale(cannon.Player)
        multiplier = Vector(scale, scale)
    end
    -- Use the larger character axis for the knife's collision scale. Tiny
    -- Planet then supplies native capsule axes independently of its artwork.
    local collisionMultiplier = math.max(
        math.abs(multiplier.X),
        math.abs(multiplier.Y)
    )
    local baseSpriteScale = knifeData.MizukiCannonKnifeBaseSpriteScale
    knife.Scale = knifeData.MizukiCannonKnifeBaseScale * collisionMultiplier
    knife.SpriteScale = Vector(
        baseSpriteScale.X * multiplier.X,
        baseSpriteScale.Y * multiplier.Y
    )
    local orbitCollisionMultiplier = 1
    local collisionAxes
    if hasCannonKnifeTinyPlanet(knife, cannon, motionSource) then
        local source = motionSource or getKnifeMotionSource(knife, knifeData)
        if source then
            -- Native Tiny Planet capsule (0x9629ED-0x962A80): both normalized
            -- axes are required; enlarging Size alone does not define it.
            local motion = math.max(0, source:GetKnifeDistance())
                * math.abs(source:GetKnifeVelocity())
            local shortAxis, longAxis = 1 + 0.0002 * motion, 1 + 0.0014 * motion
            orbitCollisionMultiplier = math.max(shortAxis, longAxis)
            collisionAxes = Vector(shortAxis / orbitCollisionMultiplier,
                longAxis / orbitCollisionMultiplier)
            knifeData.MizukiCannonKnifeOrbitCollision = true
        end
    elseif knifeData.MizukiCannonKnifeOrbitCollision then
        local baseMulti = knifeData.MizukiCannonKnifeBaseSizeMulti or Vector.One
        collisionAxes = Vector(baseMulti.X, baseMulti.Y)
        knifeData.MizukiCannonKnifeOrbitCollision = nil
    end
    knife.Size = (knifeData.MizukiCannonKnifeBaseSize * collisionMultiplier)
        * orbitCollisionMultiplier
    -- The native Size setter resets SizeMulti. Set the capsule axes last;
    -- the actual update trace showed our previous order restoring (1, 1).
    if collisionAxes then knife.SizeMulti = collisionAxes end
end

local function clearCannonKnifeSpin(knife, knifeData)
    local baseOffset = knifeData.MizukiCannonKnifeSpriteRotationOffset
    if baseOffset ~= nil then
        knife.SpriteRotation = knife.Rotation + baseOffset
    end
    knifeData.MizukiCannonKnifeSpriteRotationOffset = nil
    knifeData.MizukiCannonKnifeSpinAngle = nil
end

local function applyCannonKnifeSpin(knife, knifeData, movedDistance)
    -- Use the launch charge, not the native Charge field that changes in
    -- flight. Ordinary Mom Knife rotation marks the maximum-damage charge.
    -- Bone throws retain their separate existing spin behavior.
    if knifeData.MizukiBerserkClub ~= true
        and (knifeData.MizukiCannonKnifeShotCharge or 0) <= Mizuki.KnifeParameters.SpinChargeThreshold then
        clearCannonKnifeSpin(knife, knifeData)
        return
    end
    local baseOffset = knifeData.MizukiCannonKnifeSpriteRotationOffset
    if baseOffset == nil then
        -- Preserve the native knife art's current relationship to its attack
        -- direction instead of assuming a particular spritesheet orientation.
        if knifeData.MizukiBerserkCollisionProxy == true then
            baseOffset = Mizuki.BerserkClubParameters.HeldIdleRotationOffset
        else
            baseOffset = knife.SpriteRotation - knife.Rotation
        end
        knifeData.MizukiCannonKnifeSpriteRotationOffset = baseOffset
    end
    local spinAngle = (knifeData.MizukiCannonKnifeSpinAngle or 0)
        + math.abs(movedDistance) * KNIFE_SPIN_DEGREES_PER_PIXEL
    spinAngle = spinAngle % 360
    knifeData.MizukiCannonKnifeSpinAngle = spinAngle
    knife.SpriteRotation = knife.Rotation + baseOffset + spinAngle
end

local function applyCannonKnifeColor(knife, player)
    local playerData = player:GetData()
    local knifeData = knife:GetData()
    local revision = playerData.MizukiMomKnifeColorRevision or 0
    if knifeData.MizukiCannonKnifeColorRevision == revision then
        return
    end

    -- FireKnife copied Mizuki's already-colorized TearColor. Replace it with the
    -- colour captured immediately before that character-only layer was applied;
    -- this retains vanilla and other-mod item colours instead of forcing white.
    knife.Color = playerData.MizukiMomKnifeBaseColor or Color.Default
    knifeData.MizukiCannonKnifeColorRevision = revision
end

local function useManualCannonKnifeRender(knife)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true then
        return
    end
    local cannon = knifeData.MizukiCannonKnifeCannon
    if cannon and cannon:Exists() and knifeData.MizukiBerserkClub ~= true
        and Mizuki.cannonKnifeNeedsFlightAnchor(cannon.Player, knife.Variant, false) then
        knifeData.MizukiKnifeFlightAnchorRequired = true
    end
    if knifeData.MizukiBerserkCollisionProxy == true
        or knifeData.MizukiKnifeFlightAnchorRequired == true then
        if cannon and cannon:Exists() then attachKnifeFlightAnchor(knife, cannon) end
    end

    if knifeData.MizukiBerserkClub == true and knifeData.MizukiBerserkCollisionProxy ~= true then
        -- Experimental native body draw: restore alpha without changing the
        -- real weapon's collision, animation, or flight state.
        local nativeColor = Color.Lerp(knifeData.MizukiCannonKnifeDrawColor or knife.Color,
            knifeData.MizukiCannonKnifeDrawColor or knife.Color, 0)
        if nativeColor.A == 0 then nativeColor.A = 1 end
        knifeData.MizukiCannonKnifeNativeRender = true
        knifeData.MizukiCannonKnifeManualRender = nil
        knifeData.MizukiCannonKnifeDrawColor = nil
        knife.Visible = true
        knife.Color = nativeColor
        knife:GetSprite().Color = nativeColor
        return
    end
    knifeData.MizukiCannonKnifeNativeRender = nil

    -- EntityKnife chooses its own render Z relative to its parent, so the
    -- inherited entity depth fields cannot reliably put this cannon body above
    -- the player. Keep the real knife as the attack entity, but move only its
    -- draw into the owning cannon's manual body draw.
    --
    -- The engine's own draw is hidden with an alpha of 0 instead of Visible: an
    -- invisible entity is skipped by more than rendering - the debug collision
    -- display stops listing it and its contact pass is not reliable - while the
    -- zero alpha keeps the entity in every pass it needs and only removes the
    -- picture. The colour channels are kept so the item tint still shows in the
    -- manual draw.
    knifeData.MizukiCannonKnifeManualRender = true
    knife.Visible = true
    local color = knife.Color
    knifeData.MizukiCannonKnifeDrawColor = Color.Lerp(color, color, 0)
    knifeData.MizukiCannonKnifeDrawColor.A = 1
    local hiddenColor = Color.Lerp(color, color, 0)
    hiddenColor.A = 0
    knife.Color = hiddenColor
    knife:GetSprite().Color = hiddenColor
end

local function getCannonKnife(cannon)
    local cannonData = cannon:GetData()
    local knife = cannonData.MizukiMomKnife
    if not knife or not knife:Exists() then
        cannonData.MizukiMomKnife = nil
        cannonData.MizukiMomKnifeInitSeed = nil
        return nil
    end

    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true
        or knife.InitSeed ~= cannonData.MizukiMomKnifeInitSeed
        or not sameEntity(
            knifeData.MizukiCannonKnifeCannon,
            knifeData.MizukiCannonKnifeCannonInitSeed,
            knifeData.MizukiCannonKnifeCannonPtrHash
        )
        or GetPtrHash(knifeData.MizukiCannonKnifeCannon)
            ~= GetPtrHash(cannon)
    then
        cannonData.MizukiMomKnife = nil
        cannonData.MizukiMomKnifeInitSeed = nil
        return nil
    end
    return knife
end

function Mizuki.getCannonMomKnifeShadowDisplacement(cannon)
    local knife = getCannonKnife(cannon)
    if not knife or not knife:IsFlying()
        or knife:GetData().MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
    then
        return Vector.Zero
    end
    -- Move only the native Familiar shadow. The cannon and its beam origin
    -- remain at their locked attack position while the knife travels.
    return knife.Position + knife.PositionOffset
        - getCannonKnifeFollowPosition(cannon)
end

local function getAuxiliaryCannonKnives(cannon)
    local cannonData = cannon:GetData()
    local knives = cannonData.MizukiAuxiliaryMomKnives
    if not knives then
        return {}
    end

    for index = #knives, 1, -1 do
        local knife = knives[index]
        local knifeData = knife and knife:Exists() and knife:GetData() or nil
        if not knifeData
            or knifeData.MizukiCannonKnife ~= true
            or knifeData.MizukiCannonKnifeAuxiliary ~= true
            or not sameEntity(
                knifeData.MizukiCannonKnifeCannon,
                knifeData.MizukiCannonKnifeCannonInitSeed,
                knifeData.MizukiCannonKnifeCannonPtrHash
            )
            or GetPtrHash(knifeData.MizukiCannonKnifeCannon)
                ~= GetPtrHash(cannon)
        then
            table.remove(knives, index)
        end
    end
    if #knives == 0 then
        cannonData.MizukiAuxiliaryMomKnives = nil
    end
    return knives
end

local function clearKnifeBeamLink(knifeData, beam)
    if not beam or knifeData.MizukiCannonKnifeBeam == beam then
        local linked = knifeData.MizukiCannonKnifeBeam
        if restoreMultidimensionalKnife and linked and linked.MomKnife then
            restoreMultidimensionalKnife(linked.MomKnife)
        end
        knifeData.MizukiCannonKnifeBeam = nil
    end
end

local function removeCannonKnife(cannon)
    local knife = getCannonKnife(cannon)
    if knife then
        local knifeData = knife:GetData()
        if knifeData.MizukiCannonKnife == true then
            if knifeData.MizukiBerserkClub and Mizuki.cancelBerserkClubSwing then
                Mizuki.cancelBerserkClubSwing(knife)
            end
            clearKnifeBeamLink(knifeData)
            knife:Remove()
        end
    end
    local cannonData = cannon:GetData()
    for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
        if auxiliaryKnife and auxiliaryKnife:Exists() then
            clearKnifeBeamLink(auxiliaryKnife:GetData())
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil
    cannonData.MizukiMomKnife = nil
    cannonData.MizukiMomKnifeInitSeed = nil
end

-- The native body/scale/color setup is shared; callers assign their own explicit
-- identities and ownership. Creating an echo must never register a real knife.
function Mizuki.createCannonKnifeBody(cannon, position, rotation, weaponVariant, berserk)
    local player = cannon.Player
    if not player or not player:Exists() then return nil end
    local variant = weaponVariant or Mizuki.getCannonKnifeWeaponVariant(player)
    if berserk == nil then berserk = Mizuki.isBerserkClubActive(player) end
    local collisionProxy = berserk == true and (variant == 2 or variant == 3)
    -- Native knife update 961ECB-961F3C deletes familiar-parented knives when
    -- the owner's weapon-type cache no longer includes Knife.
    -- The existing effect parent bypasses that weapon check, as for bone throws.
    local needsFlightAnchor = Mizuki.cannonKnifeNeedsFlightAnchor(player, variant, berserk)
    if needsFlightAnchor and KNIFE_FLIGHT_ANCHOR_VARIANT <= 0 then
        Isaac.DebugString("[Mizuki Bone Lifecycle] Flight anchor definition not loaded; restart the game.")
        return nil
    end
    -- FireKnife uses the player's item-aware spawn path (0x7ADED0 ->
    -- 0x6FE410). A plain collision knife must bypass weapon substitution.
    local knife
    if collisionProxy then
        knife = Isaac.Spawn(EntityType.ENTITY_KNIFE, 0, 0,
            position, Vector.Zero, player)
        knife:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        knife:AddEntityFlags(EntityFlag.FLAG_DONT_OVERWRITE)
    else
        knife = player:FireKnife(cannon, 0, true, 0, variant)
    end
    if not knife then return nil end
    knife = knife:ToKnife()
    if not knife then return nil end
    knife.Parent = cannon
    knife.SpawnerEntity = player
    knife:GetData().MizukiBerserkClub = berserk == true
    knife:GetData().MizukiKnifeFlightAnchorRequired = needsFlightAnchor or nil
    if collisionProxy then
        knife:GetData().MizukiBerserkCollisionProxy = true
        knife:GetData().MizukiCannonKnifeArtVariant = variant
        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
        -- Both native bone variants have radius 16; the Mom's Knife carrier
        -- otherwise contributes its smaller radius 8 to the shared scale cache.
        knife.Size = 16
        knife:GetSprite():Load(variant == 2 and "gfx/008.002_bone scythe.anm2"
            or "gfx/008.003_donkey jawbone.anm2", true)
        knife:GetSprite():Play("Idle", true)
    end
    if needsFlightAnchor then attachKnifeFlightAnchor(knife, cannon) end
    knife:GetData().MizukiKnifeBaseEntityCollisionClass = knife.EntityCollisionClass
    knife:GetData().MizukiCannonKnifeBaseGridCollisionClass = knife.GridCollisionClass
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, player)
    knife.Rotation = rotation
    setKnifeAtVisualPosition(knife, position)
    knife.Velocity = Vector.Zero
    Mizuki.applySpiritSwordVisual(knife)
    return knife
end

Mizuki.updateCannonKnifeScale = applyCannonKnifeScale

local function createCannonKnife(cannon, auxiliary, sourceKnife)
    local player = cannon.Player
    if not player or not player:Exists()
        or (not sourceKnife and not Mizuki.cannonUsesKnifeWeapon(player))
        or Mizuki.usesCSectionWeapon(player) then
        return nil
    end
    local knife = Mizuki.createCannonKnifeBody(cannon,
        getCannonKnifeFollowPosition(cannon), getCannonKnifeRotation(cannon),
        sourceKnife and Mizuki.getCannonKnifeArtVariant(sourceKnife),
        sourceKnife and sourceKnife:GetData().MizukiBerserkClub)
    if not knife then return nil end
    local cannonData = cannon:GetData()
    local knifeData = knife:GetData()
    knifeData.MizukiCannonKnife = true
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
    knifeData.MizukiCannonKnifeCannon = cannon
    knifeData.MizukiCannonKnifeCannonInitSeed = cannon.InitSeed
    knifeData.MizukiCannonKnifeCannonPtrHash = GetPtrHash(cannon)
    knifeData.MizukiCannonKnifeOwner = player
    knifeData.MizukiCannonKnifeOwnerInitSeed = player.InitSeed
    knifeData.MizukiCannonKnifeOwnerPtrHash = GetPtrHash(player)
    knifeData.MizukiCannonKnifeAuxiliary = auxiliary and true or nil
    if auxiliary then
        cannonData.MizukiAuxiliaryMomKnives =
            cannonData.MizukiAuxiliaryMomKnives or {}
        table.insert(cannonData.MizukiAuxiliaryMomKnives, knife)
    else
        cannonData.MizukiMomKnife = knife
        cannonData.MizukiMomKnifeInitSeed = knife.InitSeed
    end

    useManualCannonKnifeRender(knife)
    -- A native split follows its already resolved source parameters. Binding a
    -- fresh replay here would give its flags/damage a second, unrelated clock.
    if not sourceKnife then Mizuki.connectPersistentEchoAttack(player, cannon, knife, 0, "knife") end
    return knife
end

local function ensureCannonKnife(cannon)
    local player = cannon.Player
    if not player or not player:Exists() or not Mizuki.cannonUsesKnifeWeapon(player)
        or Mizuki.usesCSectionWeapon(player)
        or Mizuki.isTech2Cannon(cannon) then
        removeCannonKnife(cannon)
        return nil
    end
    local knife = getCannonKnife(cannon)
    if knife and (Mizuki.getCannonKnifeArtVariant(knife) ~= Mizuki.getCannonKnifeWeaponVariant(player)
        or (knife:GetData().MizukiBerserkClub == true) ~= Mizuki.isBerserkClubActive(player)) then
        removeCannonKnife(cannon)
        knife = nil
    end
    return knife or createCannonKnife(cannon)
end

Mizuki.ensureCannonKnife = ensureCannonKnife
Mizuki.getCannonMomKnife = getCannonKnife

-- Use the persistent attack knife itself as the attached sword body. Once its
-- native flight starts, the hand must never move that knife back onto the hilt.
function Mizuki.updateSpiritSwordMomKnife(cannon)
    if not Mizuki.renderCannonSpiritSword or not Mizuki.renderCannonSpiritSword(cannon)
        or not cannon.Player:HasCollectible(MOMS_KNIFE) then return nil end
    local knife = ensureCannonKnife(cannon)
    if not knife then return nil end
    local data = knife:GetData()
    if not knife:IsFlying() and not data.MizukiCannonKnifeBeam then
        knife.Rotation = getCannonKnifeRotation(cannon)
        clearCannonKnifeSpin(knife, data)
        -- Native ordinary knife branch 0x963B0F: sprite angle = aim - 90.
        knife.SpriteRotation = knife.Rotation - 90
        setKnifeAtVisualPosition(knife, getCannonBodyPosition(cannon))
        knife.Velocity = Vector(cannon.Velocity.X, cannon.Velocity.Y)
        knife.DepthOffset = cannon.DepthOffset
    end
    return knife
end
Mizuki.getCannonKnifeAnchor = getCannonKnifeFollowPosition

local function validateKnifeOwnership(knife, knifeData)
    if knifeData.MizukiCannonKnife ~= true then
        return nil, nil
    end
    local cannon = knifeData.MizukiCannonKnifeCannon
    local player = knifeData.MizukiCannonKnifeOwner
    if not sameEntity(
        cannon,
        knifeData.MizukiCannonKnifeCannonInitSeed,
        knifeData.MizukiCannonKnifeCannonPtrHash
    ) or not sameEntity(
        player,
        knifeData.MizukiCannonKnifeOwnerInitSeed,
        knifeData.MizukiCannonKnifeOwnerPtrHash
    ) or not cannon.Player
        or GetPtrHash(cannon.Player) ~= GetPtrHash(player)
        or (not Mizuki.cannonUsesKnifeWeapon(player)
            and not (knifeData.MizukiMultidimensionalKnife == true and knifeData.MizukiEchoKnife == true))
    then
        return nil, nil
    end
    return cannon, player
end

local function getLaserPath(laser)
    local positionOffset = laser.PositionOffset or Vector.Zero
    local path = { laser.Position + positionOffset }
    local totalLength = 0
    local samples = laser:GetSamples()
    for index = 0, #samples - 1 do
        local sample = samples:Get(index)
        local position = Vector(sample.X, sample.Y) + positionOffset
        local previous = path[#path]
        local segmentLength = (position - previous):Length()
        if segmentLength > KNIFE_VELOCITY_EPSILON then
            totalLength = totalLength + segmentLength
            path[#path + 1] = position
        end
    end
    return path, totalLength
end
Mizuki.getCannonKnifeLaserPath = getLaserPath

local function getKnifeOrbitOffset(source)
    local offset = (source.RotationOffset or 0) % 360
    return offset > 180 and offset - 360 or offset
end

-- Native ordinary knife (variant/subtype 0): 0x961C09-0x961C2F,
-- 0x962952-0x96298A. Flight distance is the clock, not the orbit radius.
local function getKnifeOrbitRadius(source, distance)
    return 30 + math.max(0, distance) * 0.25 * (1 - getKnifeOrbitOffset(source) * 0.02)
end

-- During a sword swing, a short native knife flight still belongs to the
-- moving blade axis. Preserve its art correction/charge spin while following
-- that axis; full spin throws have their own independent flight direction.
function Mizuki.syncSpiritSwordKnifeAim(knife, beam)
    if not knife or not knife:Exists() or not beam
        or (beam.SpiritSwordDriven ~= true and beam.SpiritSwordKnifeFromHilt ~= true)
        or beam.SpiritSwordSpinThrow == true or not beam.Direction then return end
    local data = knife:GetData()
    if data.MizukiSpiritSwordSpinThrow == true or data.MizukiBerserkClub == true
        or (data.MizukiCannonKnife ~= true and data.MizukiEchoKnife ~= true)
        or (data.MizukiCannonKnifeBeam ~= beam and data.MizukiEchoChild ~= beam) then return end
    local artOffset = knife.SpriteRotation - knife.Rotation
    knife.Rotation = beam.Direction:GetAngleDegrees()
    knife.SpriteRotation = knife.Rotation + artOffset
end

function Mizuki.getCannonKnifeBeamAngle(beam, motionSource, distanceOverride)
    local angle = beam.Direction:GetAngleDegrees()
    local knife = beam.MomKnife
    if not knife or not knife:Exists() or knife.InitSeed ~= beam.MomKnifeInitSeed then
        return angle
    end
    local source = motionSource or getKnifeMotionSource(knife, knife:GetData())
    if not source or not source:IsFlying()
        or not hasCannonKnifeTinyPlanet(knife, beam.Cannon, source) then
        return angle
    end
    -- Native Tiny Planet knife position uses this distance-based orbit angle
    -- (isaac-ng.exe 0x9628F2-0x96293A). Apply it to the whole laser instead;
    -- the knife still advances along that laser's native, shortened path.
    local rotationOffset = getKnifeOrbitOffset(source)
    return angle + math.max(0, distanceOverride or source:GetKnifeDistance()) * 2 * math.pi
        * (1 + rotationOffset * 0.002)
end

local function getLaserEndpointTransform(laser, distance, fallbackDirection, continuePastEndpoint)
    local path, pathLength = getLaserPath(laser)
    if #path == 1 or pathLength <= KNIFE_VELOCITY_EPSILON then
        local direction = fallbackDirection or Vector(1, 0)
        if continuePastEndpoint and laser.AngleDegrees then
            direction = Vector.FromAngle(laser.AngleDegrees)
        end
        return path[1] + direction:Resized(math.max(0, distance)), direction
    end

    local finalSegment = path[#path] - path[#path - 1]
    local finalDirection = finalSegment:Normalized()
    local position = path[#path]
    if continuePastEndpoint then
        -- EndPoint is the native ray endpoint before the homing/curved path.
        -- Keep all native samples, then continue the knife along the final
        -- tangent by the ray distance lost to clipping. Do not rewrite the
        -- laser's samples, graphics, flags, or damage path.
        local endpoint = laser.EndPoint or (position - laser.PositionOffset)
        local clippedDistance = (endpoint - laser.Position):Length()
        position = position + finalDirection * math.max(0, distance - clippedDistance)
    end
    return position, finalDirection
end

-- Only Spirit Sword throws add the held hilt-to-launch span. Ordinary knives
-- and echoes retain their existing native path/distance mapping.
local function getSwordKnifeEndpointOffset(beam)
    local knife = beam and beam.MomKnife
    if not beam or beam.SpiritSwordKnifeFromHilt ~= true or not knife or not knife:Exists()
        or knife.InitSeed ~= beam.MomKnifeInitSeed then return Vector.Zero end
    return Mizuki.getSpiritSwordLinkEnd(knife) - (knife.Position + knife.PositionOffset)
end

local function getKnifeLaserDistance(beam, distance)
    if beam and beam.SpiritSwordKnifeFromHilt == true then
        return math.max(0.001, (beam.SpiritSwordKnifeLaunchDistance or 0) + distance
            - getSwordKnifeEndpointOffset(beam):Length())
    end
    return distance
end

local function getKnifeBeamEndpointTransform(knife, laser, distance, direction, continuePastEndpoint, beam)
    local position, tangent = getLaserEndpointTransform(laser, getKnifeLaserDistance(beam, distance),
        direction, continuePastEndpoint)
    -- The native tip ends at the selected quarter-blade attachment. Derive
    -- the knife center from that attachment without altering its flight clock.
    return position - getSwordKnifeEndpointOffset(beam), tangent
end

local function getKnifeOrbitRotation(beam, source, position, pathDirection)
    local origin = beam.Laser.Position + beam.Laser.PositionOffset
    local distance = math.max(0, source:GetKnifeDistance())
    local angularRate = math.rad(Mizuki.getCannonKnifeBeamAngle(beam, source, distance + 1)
        - Mizuki.getCannonKnifeBeamAngle(beam, source, distance))
    -- dP/dd = radial rate * path tangent + angular rate * perpendicular radius.
    -- A line between last/current positions is a chord, and repeated endpoint
    -- corrections can give it a completely different direction from the orbit.
    local radialRate = 0.25 * (1 - getKnifeOrbitOffset(source) * 0.02)
    local tangent = pathDirection * radialRate + (position - origin):Rotated(90) * angularRate
    if source:GetKnifeVelocity() < 0 then tangent = tangent * -1 end
    return tangent:GetAngleDegrees() - 90
end

-- The knife callback prepares the laser's angle/range before native sampling.
-- Finish its placement again after that sampling, without advancing flight,
-- changing the state machine, or accumulating another spin increment.
function Mizuki.syncCannonKnifeFlightEndpoint(knife, motionSource, beam)
    local laser = beam and beam.Laser
    if not knife or not knife:Exists() or not motionSource or not motionSource:Exists()
        or not motionSource:IsFlying() or not laser or not laser:Exists() then return end
    Mizuki.syncSpiritSwordKnifeAim(knife, beam)
    local tinyPlanet = hasCannonKnifeTinyPlanet(knife, beam.Cannon, motionSource)
    local distance = math.max(0, motionSource:GetKnifeDistance())
    if tinyPlanet then distance = getKnifeOrbitRadius(motionSource, distance) end
    local position, direction = getKnifeBeamEndpointTransform(knife, laser,
        distance, beam.Direction, tinyPlanet, beam)
    setKnifeAtVisualPosition(knife, position)
    knife.Velocity = Vector.Zero
    if tinyPlanet then
        knife.SpriteRotation = getKnifeOrbitRotation(beam, motionSource, position, direction)
        if beam.Cannon then applyCannonKnifeScale(knife, beam.Cannon, motionSource) end
    end
end

local function setKnifeDrivenLaserDistance(beam, distance)
    local laser = beam and beam.Laser
    if not laser or not laser:Exists() then
        return
    end
    laser:SetMaxDistance(beam.SpiritSwordKnifeFromHilt == true
        and math.max(0.001, getKnifeLaserDistance(beam, distance)) or math.max(1, distance))
end

local function createCannonKnifeLaserRoot(beam)
    local cannon = beam and beam.Cannon
    local player = cannon and cannon.Player
    -- The sword hilt covers its beam origin; it needs no separate Tech Dot.
    if beam and beam.SpiritSwordDriven then return end
    if cannon and Mizuki.renderCannonSpiritSword(cannon) then return end
    -- Match fireMizukiWeaponBeam's source choice. Brimstone already supplies
    -- its own firing effect; this extra Tech Dot belongs only to the tech beam.
    if not player or not player:Exists()
        or player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        return
    end
    local laser = beam.Laser
    local sprite = Sprite()
    sprite:Load(KNIFE_LASER_ROOT_ANM2, true)
    sprite:Play("Idle", true)
    table.insert(knifeLaserRoots, {
        CannonInitSeed = beam.Cannon.InitSeed,
        CannonPtrHash = GetPtrHash(beam.Cannon),
        Laser = laser,
        LaserInitSeed = laser.InitSeed,
        LaserPtrHash = GetPtrHash(laser),
        Sprite = sprite,
        Position = laser.Position + laser.PositionOffset,
        LastFrame = Game():GetFrameCount(),
    })
end
Mizuki.createCannonKnifeLaserRoot = createCannonKnifeLaserRoot

function Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
    knife:GetData().MizukiCannonKnifeShotCharge = shotCharge
    if hasCannonKnifeTinyPlanet(knife, cannon) then
        knife.TearFlags = knife.TearFlags | TearFlags.TEAR_ORBIT
    elseif cannon and cannon.Player then
        knife.TearFlags = knife.TearFlags & ~TearFlags.TEAR_ORBIT
    end
    local range = beam and beam.Distance or 1
    -- Zero is a laser-only "unlimited" sentinel, not a knife launch range.
    -- Pass the owner's existing native stat unchanged: no beam-range formula,
    -- extra multiplier, minimum, or maximum is applied to the knife.
    if range == 0 then range = cannon.Player.TearRange end
    knife.Charge = shotCharge
    knife:Shoot(shotCharge, range)
end

function Mizuki.launchCannonKnife(knife, cannon, beam, shotCharge, position)
    knife:GetData().MizukiSpiritSwordSpinThrow = beam.SpiritSwordSpinThrow == true
    if knife:GetData().MizukiBerserkClub then
        knife.EntityCollisionClass = knife:GetData().MizukiKnifeBaseEntityCollisionClass
            or EntityCollisionClass.ENTCOLL_ENEMIES
        knife:AddTearFlags(TearFlags.TEAR_EXTRA_GORE)
    end
    clearCannonKnifeSpin(knife, knife:GetData())
    knife.Rotation = beam.Direction:GetAngleDegrees()
    setKnifeAtVisualPosition(knife, position)
    applyCannonKnifeScale(knife, cannon)
    Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
    if knife:GetData().MizukiBerserkCollisionProxy == true then
        local playerData, frame = cannon.Player:GetData(), Game():GetFrameCount()
        if playerData.MizukiBerserkThrowSoundFrame ~= frame then
            SFXManager():Play(SoundEffect.SOUND_FETUS_JUMP, 1.75, 0, false, 1)
            playerData.MizukiBerserkThrowSoundFrame = frame
        end
    end
    if hasCannonKnifeTinyPlanet(knife, cannon) then
        knife.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        beam.Laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    else
        local baseGrid = knife:GetData().MizukiCannonKnifeBaseGridCollisionClass
        if baseGrid ~= nil then knife.GridCollisionClass = baseGrid end
    end
    applyCannonKnifeScale(knife, cannon)
    beam.MomKnifeDriven = true
    beam.MomKnife = knife
    beam.MomKnifeInitSeed = knife.InitSeed
    beam.MomKnifeReturnStarted = false
    setKnifeDrivenLaserDistance(beam, 1)
    beam.Laser:GetData().MizukiKnifeSourceBeam = beam
    createCannonKnifeLaserRoot(beam)
    knife.Velocity = Vector.Zero
    Mizuki.syncSpiritSwordKnifeThrow(knife, cannon)
end

function Mizuki.refreshAuxiliaryCannonKnifeFlight(knife, cannon, beam, motionSource, shotCharge)
    if motionSource and motionSource:IsFlying() and not knife:IsFlying() then
        Mizuki.shootCannonKnife(knife, cannon, beam, shotCharge)
        applyCannonKnifeScale(knife, cannon)
    end
end

-- Native knife distance/velocity are the flight clock. Laser length uses the
-- native orbit radius for Tiny Planet; its path maps the knife onto curves.
-- knives continue past a clipped endpoint while the laser keeps its wall stop.
-- Both real and echo controllers use this same outbound/return/spin algorithm.
function Mizuki.updateCannonKnifeFlight(knife, motionSource, beam, targetPosition, state, previousDistance)
    Mizuki.syncSpiritSwordKnifeAim(knife, beam)
    if knife:GetData().MizukiBerserkCollisionProxy == true then
        knife.Visible = true
        knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
    end
    local laser = beam and beam.Laser
    local distance = math.max(0, motionSource:GetKnifeDistance())
    local knifeVelocity = motionSource:GetKnifeVelocity()
    local tinyPlanet = hasCannonKnifeTinyPlanet(knife, beam and beam.Cannon, motionSource)
    local mappedDistance = tinyPlanet and getKnifeOrbitRadius(motionSource, distance) or distance
    if tinyPlanet then
        knife.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        if laser and laser:Exists() then
            laser.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        end
    end
    if laser and laser:Exists() then
        laser.AngleDegrees = Mizuki.getCannonKnifeBeamAngle(beam, motionSource)
    end
    if state == KNIFE_STATE_OUTBOUND then
        local returning = knifeVelocity < -KNIFE_VELOCITY_EPSILON
            or (previousDistance ~= nil and distance < previousDistance - KNIFE_DISTANCE_EPSILON)
        local mappedPosition
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, mappedDistance)
            mappedPosition = getKnifeBeamEndpointTransform(knife, laser, mappedDistance, beam.Direction, tinyPlanet, beam)
        else
            local direction = beam and beam.Direction or Vector.FromAngle(knife.Rotation)
            mappedPosition = targetPosition + direction:Resized(mappedDistance)
        end
        if returning then
            state = KNIFE_STATE_RETURNING
            if beam then beam.MomKnifeReturnStarted = true end
        else
            setKnifeAtVisualPosition(knife, mappedPosition)
            knife.Velocity = Vector.Zero
            applyCannonKnifeSpin(knife, knife:GetData(), distance - (previousDistance or distance))
        end
    end
    if state == KNIFE_STATE_RETURNING then
        local returnPosition
        if laser and laser:Exists() then
            setKnifeDrivenLaserDistance(beam, mappedDistance)
            returnPosition = getKnifeBeamEndpointTransform(knife, laser, mappedDistance, beam.Direction, tinyPlanet, beam)
        else
            local returnDirection = beam and beam.Direction or Vector.FromAngle(knife.Rotation)
            returnPosition = targetPosition + returnDirection:Resized(mappedDistance)
        end
        setKnifeAtVisualPosition(knife, returnPosition)
        knife.Velocity = Vector.Zero
        applyCannonKnifeSpin(knife, knife:GetData(), distance - (previousDistance or distance))
    end
    local mappedPosition = knife.Position + knife.PositionOffset
    if tinyPlanet then
        if laser and laser:Exists() then
            local _, direction = getLaserEndpointTransform(laser, getKnifeLaserDistance(beam, mappedDistance), beam.Direction, true)
            -- SpriteRotation is also the native capsule's local Y axis.
            knife.SpriteRotation = getKnifeOrbitRotation(beam, motionSource, mappedPosition, direction)
        end
        if beam and beam.Cannon then
            applyCannonKnifeScale(knife, beam.Cannon, motionSource)
        end
    end
    return state, distance
end

local function beamOwnsKnife(beam)
    local knife = beam and beam.MomKnife
    if not knife or not knife:Exists()
        or knife.InitSeed ~= beam.MomKnifeInitSeed
    then
        return nil
    end
    local knifeData = knife:GetData()
    if knifeData.MizukiEchoKnife == true and knifeData.MizukiEchoChild == beam
        and beam.Knife == knife and beam.Shot and not beam.Shot.Removed then
        return knife, knifeData
    end
    if knifeData.MizukiCannonKnife ~= true
        or knifeData.MizukiCannonKnifeBeam ~= beam
    then
        return nil
    end
    return knife, knifeData
end

getKnifeMotionSource = function(knife, knifeData)
    if knifeData.MizukiMultidimensionalKnife == true then
        local source = knifeData.MizukiCannonKnifeMotionSource
        if sameEntity(source, knifeData.MizukiCannonKnifeMotionSourceInitSeed,
            knifeData.MizukiCannonKnifeMotionSourcePtrHash) then
            return getKnifeMotionSource(source, source:GetData())
        end
        return nil
    end
    if knifeData.MizukiEchoKnife == true then
        if knifeData.MizukiEchoKnifeAuxiliary ~= true then return knife end
        local source = knifeData.MizukiEchoKnifeMotionSource
        if sameEntity(source, knifeData.MizukiEchoKnifeMotionSourceSeed,
            knifeData.MizukiEchoKnifeMotionSourceHash) then return source end
        return nil
    end
    if knifeData.MizukiCannonKnifeAuxiliary ~= true then
        return knife
    end
    local source = knifeData.MizukiCannonKnifeMotionSource
    if sameEntity(
        source,
        knifeData.MizukiCannonKnifeMotionSourceInitSeed,
        knifeData.MizukiCannonKnifeMotionSourcePtrHash
    ) then
        return source
    end
    return nil
end

function Mizuki.getCannonKnifeMotionVelocity(knife)
    local data = knife:GetData()
    local source = getKnifeMotionSource(knife, data)
    return source and source:Exists() and source:GetKnifeVelocity() or knife:GetKnifeVelocity()
end

-- Native multidimensional laser creation (974BDE-974C7C) sets each new
-- laser's Parent to the incident laser. Parent is exposed at offset 3BC.
-- Use that exact relationship, not proximity or a shared player spawner.
local function getMultidimensionalKnifeSource(laser)
    local parent = laser.Parent and laser.Parent:ToLaser()
    if not parent or not parent:Exists() then return end
    local beam = parent:GetData().MizukiKnifeSourceBeam
    if not beam or not Mizuki.isSameEntity(beam.Laser, parent)
        or beam.MultidimensionalKnifeBranch == true then return end
    local source, data = beamOwnsKnife(beam)
    if not source then return end
    if data.MizukiBerserkClub == true and data.MizukiBerserkCollisionProxy ~= true then return end
    local motion = getKnifeMotionSource(source, data)
    if not motion or not motion:Exists() or not motion:IsFlying() then return end
    local cannon, player
    if data.MizukiEchoKnife == true then
        cannon, player = beam.Ghost, beam.Shot.Player
        if not cannon or not cannon:Exists() or not player or not player:Exists()
            or not Mizuki.isSameEntity(cannon.Player, player) then return end
    else cannon, player = validateKnifeOwnership(source, data) end
    -- The live child can lose TEAR_LASER during native parameter refresh.
    -- The sampled children retain Parent and the validated source knife.
    -- The familiar may come from Monster Manual without owning the item.
    if not cannon then return end
    return beam, source, cannon
end

restoreMultidimensionalKnife = function(knife)
    if not knife or not knife:Exists() then return end
    local data = knife:GetData()
    if data.MizukiMultidimensionalKnifeSuppressed ~= true then return end
    knife.EntityCollisionClass = data.MizukiMultidimensionalKnifeCollisionClass
    if data.MizukiMultidimensionalKnifeNativeAlpha ~= nil then
        local color = Color.Lerp(knife.Color, knife.Color, 0)
        color.A = data.MizukiMultidimensionalKnifeNativeAlpha
        knife.Color = color
        data.MizukiMultidimensionalKnifeNativeAlpha = nil
    end
    data.MizukiMultidimensionalKnifeSuppressed = nil
    data.MizukiMultidimensionalKnifeCollisionClass = nil
end

function Mizuki.keepSplitKnifeSourceHidden(knife)
    local data = knife:GetData()
    if data.MizukiEchoKnife ~= true or data.MizukiMultidimensionalKnifeSuppressed ~= true
        or data.MizukiCannonKnifeManualRender == true then return end
    -- Replay/fallback color updates run after the split controller too. Keep
    -- their newest alpha for restoration, but never expose the flight clock.
    local color = Color.Lerp(knife.Color, knife.Color, 0)
    data.MizukiMultidimensionalKnifeNativeAlpha = color.A
    color.A = 0
    knife.Color = color
    knife:GetSprite().Color = color
end

local function getMultidimensionalKnifeDistance(beam, source, childLaser)
    local path = getLaserPath(beam.Laser)
    local split = childLaser.Position + childLaser.PositionOffset
    local incidentLength, travelled, nearest = 0, 0, math.huge
    -- The incident laser can keep samples beyond the baby. Its whole length
    -- is not the distance to the split. Project the child's native origin onto
    -- that path; parallel children differ laterally, not in flight progress.
    for index = 2, #path do
        local first, last = path[index - 1], path[index]
        local delta = last - first
        local squared = delta.X * delta.X + delta.Y * delta.Y
        if squared > KNIFE_VELOCITY_EPSILON * KNIFE_VELOCITY_EPSILON then
            local offset = split - first
            local fraction = math.max(0, math.min(1,
                (offset.X * delta.X + offset.Y * delta.Y) / squared))
            local error = split - (first + delta * fraction)
            local errorSquared = error.X * error.X + error.Y * error.Y
            local length = math.sqrt(squared)
            if errorSquared < nearest then
                nearest = errorSquared
                incidentLength = travelled + length * fraction
            end
            travelled = travelled + length
        end
    end
    if #path == 1 then
        local offset = split - path[1]
        local direction = Vector.FromAngle(beam.Laser.AngleDegrees)
        incidentLength = math.max(0, offset.X * direction.X + offset.Y * direction.Y)
    end
    local motion = getKnifeMotionSource(source, source:GetData())
    local distance = math.max(0, motion:GetKnifeDistance())
    if hasCannonKnifeTinyPlanet(source, beam.Cannon, motion) then
        distance = getKnifeOrbitRadius(motion, distance)
    end
    return math.max(0, distance - incidentLength)
end

-- Native multidimensional synchronization owns the child range (96F1EB-1F1
-- copies MaxDistance/4D0 from the incident laser). Do not compete with it.
-- The final sampled endpoint already includes native start advance/clipping.
local function getMultidimensionalKnifePose(laser)
    local path = getLaserPath(laser)
    -- A native split with no samples already includes PositionOffset in
    -- GetEndPoint (runtime: Y 216.65 - 22.5 = 194.15). Applying it again
    -- lifts native-rendered echo knives above their child laser.
    if #path == 1 then return laser:GetEndPoint() end
    return path[#path]
end

local function getMultidimensionalKnifeColor(laser, echo)
    -- Vanilla 002.021_multidimensional tear.anm2 blends a negative layer
    -- over its grayscale body: 11 frames to full negative, then back by 22.
    -- Reproduce that blend without duplicating/replacing the weapon artwork:
    -- (1-t)*gray + t*(1-gray) = (1-2*t)*gray + t.
    local frame = laser.FrameCount % 22
    local negative = frame <= 11 and frame / 11 or (22 - frame) / 11
    local multiplier = 1 - 2 * negative
    local color = Color(multiplier, multiplier, multiplier, 1, negative, negative, negative)
    color:SetColorize(1, 1, 1, 1)
    if echo then
        -- Apply the echo palette once, after inversion. Offset participates in
        -- the same RGB transform, otherwise the negative half flashes white.
        local tint = Mizuki.getCannonEchoColor(Color(1, 1, 1, 1), Mizuki.CannonEchoReplayAlpha)
        color.RO, color.GO, color.BO = negative * tint.R + tint.RO,
            negative * tint.G + tint.GO, negative * tint.B + tint.BO
        color.A = tint.A
        -- Grayscale must be computed before the blue tint, not afterwards.
        color:SetColorize(tint.R, tint.G, tint.B, 1)
    end
    return color
end

local function syncMultidimensionalKnife(knife)
    local data = knife:GetData()
    if data.MizukiMultidimensionalKnife ~= true then return end
    local branch = data.MizukiCannonKnifeBeam
    local laser = branch and branch.Laser
    local beam, source
    if laser and laser:Exists() then beam, source = getMultidimensionalKnifeSource(laser) end
    if not beam or not Mizuki.isSameEntity(source, data.MizukiCannonKnifeMotionSource) then
        knife:Remove()
        return
    end
    local distance = getMultidimensionalKnifeDistance(beam, source, laser)
    local active = data.MizukiNativeMultidimensionalKnife == true or distance > KNIFE_DISTANCE_EPSILON
    data.MizukiMultidimensionalKnifeInactive = not active
    knife.EntityCollisionClass = active and data.MizukiKnifeBaseEntityCollisionClass
        or EntityCollisionClass.ENTCOLL_NONE
    if not knife:IsFlying() then
        Mizuki.shootCannonKnife(knife, branch.Cannon, branch,
            data.MizukiCannonKnifeShotCharge or 1)
    end
    branch.Direction = Vector.FromAngle(laser.AngleDegrees)
    setKnifeAtVisualPosition(knife, getMultidimensionalKnifePose(laser))
    knife.Velocity = Vector.Zero
    knife.SpriteRotation = source.SpriteRotation + laser.AngleDegrees - beam.Laser.AngleDegrees
    knife.Rotation = source.Rotation + laser.AngleDegrees - beam.Laser.AngleDegrees
    knife.Charge = source.Charge
    local sourceData = source:GetData()
    knife.TearFlags, knife.CollisionDamage = source.TearFlags, source.CollisionDamage
    data.MizukiCannonKnifeSpinAngle = sourceData.MizukiCannonKnifeSpinAngle
    data.MizukiSpiritSwordSpinThrow = sourceData.MizukiSpiritSwordSpinThrow == true
    data.MizukiSpecialBrimstoneCurse = sourceData.MizukiSpecialBrimstoneCurse
    local motion = getKnifeMotionSource(source, source:GetData())
    data.MizukiCannonKnifeState = motion:GetKnifeVelocity() < 0
        and KNIFE_STATE_RETURNING or KNIFE_STATE_OUTBOUND
    applyCannonKnifeScale(knife, branch.Cannon, source)
    Mizuki.syncSpiritSwordKnifeThrow(knife, branch.Cannon)
    knife.Color = getMultidimensionalKnifeColor(laser, data.MizukiEchoKnife == true)
    if data.MizukiNativeMultidimensionalKnife == true then
        -- Keep the native draw; share the same negative palette as manual forks.
        Mizuki.attachDeadEyeBranch(source, knife)
        return
    end
    useManualCannonKnifeRender(knife)
    if data.MizukiEchoKnife == true then
        data.MizukiCannonKnifeDrawColor.A = Mizuki.CannonEchoReplayAlpha
    end
    Mizuki.attachDeadEyeBranch(source, knife)
end

local function updateMultidimensionalKnives(_, laser)
    local beam, source, cannon = getMultidimensionalKnifeSource(laser)
    if not beam then return end
    local laserData = laser:GetData()
    local knife = laserData.MizukiMultidimensionalKnifeEntity
    if not knife or not knife:Exists() then
        knife = createCannonKnife(cannon, true, source)
        if not knife then return end
        local data, sourceData = knife:GetData(), source:GetData()
        local branch = { Laser = laser, Cannon = cannon, Distance = beam.Distance,
            Direction = Vector.FromAngle(laser.AngleDegrees),
            MultidimensionalKnifeBranch = true, MomKnife = knife, MomKnifeInitSeed = knife.InitSeed }
        data.MizukiMultidimensionalKnife = true
        data.MizukiCannonKnifeBeam = branch
        data.MizukiCannonKnifeMotionSource = source
        data.MizukiCannonKnifeMotionSourceInitSeed = source.InitSeed
        data.MizukiCannonKnifeMotionSourcePtrHash = GetPtrHash(source)
        data.MizukiCannonKnifeShotCharge = sourceData.MizukiCannonKnifeShotCharge or beam.KnifeCharge
        data.MizukiCannonKnifeState = KNIFE_STATE_OUTBOUND
        data.MizukiSpecialBrimstoneCurse = sourceData.MizukiSpecialBrimstoneCurse
        data.MizukiDeadEyeIntensity = sourceData.MizukiDeadEyeIntensity
        if sourceData.MizukiEchoKnife == true then
            data.MizukiEchoKnife = true
            data.MizukiEchoChild = sourceData.MizukiEchoChild
            data.MizukiEchoKnifeMotionSource = source
        end
        Mizuki.shootCannonKnife(knife, cannon, branch, data.MizukiCannonKnifeShotCharge or 1)
        knife.TearFlags, knife.CollisionDamage = source.TearFlags, source.CollisionDamage
        knife.Color = Color.Lerp(source.Color, source.Color, 0)
        laserData.MizukiMultidimensionalKnifeEntity = knife
        multidimensionalKnifeSources[source] = beam
    end
    syncMultidimensionalKnife(knife)
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE,
    CallbackPriority.LATE, updateMultidimensionalKnives)

local function syncMultidimensionalKnifeSource(knife, beam)
    restoreMultidimensionalKnife(knife)
    local motion = getKnifeMotionSource(knife, knife:GetData())
    if not beam or not motion or not motion:Exists() or not motion:IsFlying() then return end
    for _, auxiliary in ipairs(getAuxiliaryCannonKnives(beam.Cannon)) do
        local data = auxiliary:GetData()
        if data.MizukiMultidimensionalKnife == true
            and Mizuki.isSameEntity(data.MizukiCannonKnifeMotionSource, knife) then
            syncMultidimensionalKnife(auxiliary)
            if auxiliary:Exists() and data.MizukiMultidimensionalKnifeInactive == false then
                local kd = knife:GetData()
                if kd.MizukiMultidimensionalKnifeSuppressed ~= true then
                    kd.MizukiMultidimensionalKnifeCollisionClass = knife.EntityCollisionClass
                    kd.MizukiMultidimensionalKnifeSuppressed = true
                    knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                    if kd.MizukiCannonKnifeManualRender ~= true then
                        local color = Color.Lerp(knife.Color, knife.Color, 0)
                        kd.MizukiMultidimensionalKnifeNativeAlpha = color.A
                        color.A = 0
                        knife.Color = color
                    end
                end
            end
        end
    end
end

-- Observed native copies: subtype 0, both Parent and Spawner are the original
-- finite echo knife. Brimstone's subtype-1 knife projectiles are not this role.
local function adoptNativeMultidimensionalKnife(knife)
    local data = knife:GetData()
    if data.MizukiMultidimensionalKnife == true or data.MizukiCannonKnife == true
        or data.MizukiEchoKnife == true or knife.SubType ~= 0 then return end
    local source = knife.Parent and knife.Parent:ToKnife()
    if not source or not source:Exists() or not Mizuki.isSameEntity(knife.SpawnerEntity, source) then return end
    local sourceData = source:GetData()
    if sourceData.MizukiEchoKnife ~= true or sourceData.MizukiMultidimensionalKnife == true
        or sourceData.MizukiBerserkClub == true then return end
    local beam = sourceData.MizukiEchoChild
    if not beam or not beamOwnsKnife(beam) or not beam.Cannon or not beam.Cannon:Exists() then return end
    local replacement, nearest
    local position = knife.Position + knife.PositionOffset
    for _, candidate in ipairs(getAuxiliaryCannonKnives(beam.Cannon)) do
        local cd = candidate:GetData()
        if cd.MizukiMultidimensionalKnife == true and cd.MizukiNativeMultidimensionalKnife ~= true
            and cd.MizukiBerserkClub ~= true
            and Mizuki.isSameEntity(cd.MizukiCannonKnifeMotionSource, source) then
            local delta = candidate.Position + candidate.PositionOffset - position
            local distance = delta.X * delta.X + delta.Y * delta.Y
            if not nearest or distance < nearest then replacement, nearest = candidate, distance end
        end
    end
    if not replacement then return end
    local old = replacement:GetData()
    -- Explicit ownership/state/cache transfer, not a blanket copy of engine
    -- identity, alpha-hiding state, replay bindings or unrelated item data.
    for _, name in ipairs({"MizukiCannonKnife", "MizukiCannonKnifeState", "MizukiCannonKnifeCannon",
        "MizukiCannonKnifeCannonInitSeed", "MizukiCannonKnifeCannonPtrHash", "MizukiCannonKnifeOwner",
        "MizukiCannonKnifeOwnerInitSeed", "MizukiCannonKnifeOwnerPtrHash", "MizukiCannonKnifeAuxiliary",
        "MizukiCannonKnifeBeam", "MizukiCannonKnifeMotionSource", "MizukiCannonKnifeMotionSourceInitSeed",
        "MizukiCannonKnifeMotionSourcePtrHash", "MizukiCannonKnifeShotCharge", "MizukiMultidimensionalKnife",
        "MizukiEchoKnife", "MizukiEchoChild", "MizukiEchoKnifeMotionSource", "MizukiBerserkClub",
        "MizukiSpecialBrimstoneCurse", "MizukiDeadEyeIntensity", "MizukiFirstHitBombSpawned",
        "MizukiFirstHitHaemolacriaSpawned", "MizukiKnifeBaseEntityCollisionClass",
        "MizukiCannonKnifeBaseScale", "MizukiCannonKnifeBaseSpriteScale", "MizukiCannonKnifeBaseSize",
        "MizukiCannonKnifeBaseSizeMulti"}) do data[name] = old[name] end
    data.MizukiNativeMultidimensionalKnife = true
    local branch = data.MizukiCannonKnifeBeam
    branch.MomKnife, branch.MomKnifeInitSeed = knife, knife.InitSeed
    branch.Laser:GetData().MizukiMultidimensionalKnifeEntity = knife
    table.insert(beam.Cannon:GetData().MizukiAuxiliaryMomKnives, knife)
    replacement:Remove() -- Only the explicitly identified manual branch body.
    syncMultidimensionalKnife(knife)
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, CallbackPriority.LATE, function(_, knife)
    adoptNativeMultidimensionalKnife(knife)
end)

-- Native child sampling and knife updates can run in either entity order.
-- Finish the shared clock/branch visibility after all entity positioning.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.LATE, function()
    if next(multidimensionalKnifeSources) then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE)) do
            adoptNativeMultidimensionalKnife(entity:ToKnife())
        end
    end
    for knife, beam in pairs(multidimensionalKnifeSources) do
        if not knife:Exists() or not beamOwnsKnife(beam)
            or not beam.Cannon or not beam.Cannon:Exists() then
            restoreMultidimensionalKnife(knife)
            multidimensionalKnifeSources[knife] = nil
        else
            syncMultidimensionalKnifeSource(knife, beam)
            local motion = getKnifeMotionSource(knife, knife:GetData())
            if not motion or not motion:Exists() or not motion:IsFlying() then
                multidimensionalKnifeSources[knife] = nil
            end
        end
    end
end)
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER, CallbackPriority.LATE, function(_, laser)
    local knife = laser:GetData().MizukiMultidimensionalKnifeEntity
    if knife and knife:Exists() then syncMultidimensionalKnife(knife) end
end)

local function syncKnifeAfterLaserUpdate(_, laser, interpolated)
    if laser:GetData().MizukiBeam ~= true then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE)) do
        local knife = entity:ToKnife()
        local data = knife:GetData()
        if data.MizukiCannonKnife == true and validateKnifeOwnership(knife, data) then
            local beam = data.MizukiCannonKnifeBeam
            local ownedKnife = beamOwnsKnife(beam)
            if beam and beam.Laser and beam.Laser:Exists()
                and GetPtrHash(beam.Laser) == GetPtrHash(laser)
                and ownedKnife and GetPtrHash(ownedKnife) == GetPtrHash(knife)
                and data.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW then
                local source = getKnifeMotionSource(knife, data)
                if not interpolated or (source and hasCannonKnifeTinyPlanet(knife, beam.Cannon, source)) then
                    if data.MizukiMultidimensionalKnife == true then
                        syncMultidimensionalKnife(knife)
                    else
                        Mizuki.syncCannonKnifeFlightEndpoint(knife, source, beam)
                        syncMultidimensionalKnifeSource(knife, beam)
                    end
                    if data.MizukiCannonKnifeAuxiliary ~= true then
                        Mizuki.refreshCannonMomKnifeShadow(data.MizukiCannonKnifeCannon)
                    end
                end
            end
        end
    end
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE,
    CallbackPriority.LATE, syncKnifeAfterLaserUpdate)
-- Native interpolation advances/samples the laser again between update and
-- render (including a paused half-step). Sync the actual capsule as well as
-- its visible pose, without advancing the knife clock or changing the laser.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER,
    CallbackPriority.LATE, function(_, laser)
        syncKnifeAfterLaserUpdate(nil, laser, true)
    end)

function Mizuki.updateCannonMomKnife(cannon)
    if cannon:GetData().MizukiGuillotineNonFiring
        or (cannon.Player and Mizuki.usesCSectionWeapon(cannon.Player)) then
        removeCannonKnife(cannon)
        return
    end
    local knife = ensureCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    applyCannonKnifeScale(knife, cannon)
    applyCannonKnifeColor(knife, cannon.Player)
    useManualCannonKnifeRender(knife)
    if knifeData.MizukiBerserkClub and Mizuki.updateBerserkClubSwing(knife, cannon) then return end
    Mizuki.connectPersistentEchoAttack(cannon.Player, cannon, knife, 0, "knife")
    if knifeData.MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
        or not knife:IsFlying()
    then
        if knifeData.MizukiBerserkClub == true then
            knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        end
        knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
        knifeData.MizukiBerserkFlightClock = nil
        knifeData.MizukiSpecialBrimstoneCurse = false
        clearKnifeBeamLink(knifeData)
        knife.Rotation = getCannonKnifeRotation(cannon)
        syncHeldBoneSpriteRotation(knife)
        setKnifeAtVisualPosition(knife, getHeldKnifePosition(knife, cannon))
        -- Position is fully owned by Lua. A non-zero world Velocity would make
        -- the engine advance the knife once more between these hard placements.
        knife.Velocity = Vector.Zero
    end
end

function Mizuki.fireCannonMomKnife(cannon, beam, charge, baseChargeFrames)
    local laser = beam.Laser
    if not laser or not laser:Exists() then
        return false
    end

    local motionSource = ensureCannonKnife(cannon)
    local knife = motionSource
    local auxiliary = knife and (knife:IsFlying()
        or knife:GetData().MizukiCannonKnifeBeam ~= nil)
    if auxiliary then
        -- The first laser uses the cannon's persistent body. Every additional
        -- laser gets a temporary knife of its own so native multi-shot layouts
        -- and their already-resolved angles remain the single source of truth.
        knife = createCannonKnife(cannon, true)
    end
    if not knife then
        return false
    end

    local knifeData = knife:GetData()
    if auxiliary then
        knifeData.MizukiCannonKnifeMotionSource = motionSource
        knifeData.MizukiCannonKnifeMotionSourceInitSeed = motionSource.InitSeed
        knifeData.MizukiCannonKnifeMotionSourcePtrHash = GetPtrHash(motionSource)
    end
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_OUTBOUND
    -- The primary knife body is reused for successive firing requests.
    knifeData.MizukiFirstHitBombSpawned = nil
    knifeData.MizukiFirstHitHaemolacriaSpawned = nil
    if not cannon:GetData().MizukiPersistentEchoMode then
        Mizuki.rollSpecialBrimstone(knife, cannon.Player)
    end
    knifeData.MizukiCannonKnifeBeam = beam
    knifeData.MizukiCannonKnifePreviousDistance = 0
    -- The persistent body has existed throughout charging, while auxiliary
    -- knives are born only on release. Give every native entity the same charge
    -- parameters; auxiliary visual timing is synchronized to the persistent
    -- knife separately in UpdateCannonMomKnifeEntity.
    local shotCharge = math.max(
        0,
        math.min(charge / math.max(1, baseChargeFrames), 1)
    )
    if knifeData.MizukiBerserkClub then
        Mizuki.cancelBerserkClubSwing(knife)
        knifeData.MizukiBerserkSwing = nil
        local params = cannon.Player:GetTearHitParams(WeaponType.WEAPON_BONE, 1, 1, knife)
        knife.TearFlags = params.TearFlags | TearFlags.TEAR_EXTRA_GORE
        if cannon.Player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT) then
            knife:AddTearFlags(TearFlags.TEAR_HOMING)
        end
        knife.CollisionDamage = params.TearDamage * (beam.BerserkChargeDamageMultiplier or 1)
            * (knifeData.MizukiBerserkCollisionProxy and Mizuki.getCannonKnifeArtVariant(knife) ~= 2
                and Mizuki.BerserkClubParameters.ThrowMultiplier or 1)
        if knifeData.MizukiBerserkCollisionProxy then knifeData.MizukiBerserkThrowTargets = {} end
        local weaponColor = cannon.Player:GetData().MizukiMomKnifeBaseColor or Color.Default
        knife.Color = Color.Lerp(weaponColor, weaponColor, 0)
        useManualCannonKnifeRender(knife)
        laser.TearFlags = laser.TearFlags | TearFlags.TEAR_EXTRA_GORE
    end
    Mizuki.launchCannonKnife(knife, cannon, beam, shotCharge, getCannonKnifeFollowPosition(cannon))
    if beam.SpiritSwordKnifeFromHilt == true then Mizuki.releaseSpiritSwordHeldLink(cannon) end
    return true
end

function Mizuki.shouldHoldCannonKnifeBeam(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    local motionSource = knife and getKnifeMotionSource(knife, knifeData)
    return knife ~= nil
        and motionSource ~= nil
        and knifeData.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW
        and motionSource:IsFlying()
end

function Mizuki.isCannonKnifeAttackActive(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    local motionSource = knife and getKnifeMotionSource(knife, knifeData)
    return knife ~= nil
        and motionSource ~= nil
        and knifeData.MizukiCannonKnifeState ~= KNIFE_STATE_FOLLOW
        and motionSource:IsFlying()
end

function Mizuki.cancelCannonKnifeBeam(beam)
    local knife, knifeData = beamOwnsKnife(beam)
    if not knife then
        return
    end
    beam.MomKnifeReturnStarted = true
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_RETURNING
    clearKnifeBeamLink(knifeData, beam)
    knife:Reset()
    knifeData.MizukiBerserkFlightClock = nil
    local cannon = knifeData.MizukiCannonKnifeCannon
    if cannon and cannon:Exists() then
        applyCannonKnifeScale(knife, cannon)
    end
end

function Mizuki.removeCannonMomKnife(cannon)
    removeCannonKnife(cannon)
end

function Mizuki.resetCannonMomKnife(cannon)
    local cannonData = cannon:GetData()
    for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
        if auxiliaryKnife and auxiliaryKnife:Exists() then
            clearKnifeBeamLink(auxiliaryKnife:GetData())
            auxiliaryKnife:Remove()
        end
    end
    cannonData.MizukiAuxiliaryMomKnives = nil

    local knife = getCannonKnife(cannon)
    if not knife then
        return
    end
    local knifeData = knife:GetData()
    if knifeData.MizukiBerserkClub == true then Mizuki.cancelBerserkClubSwing(knife) end
    clearKnifeBeamLink(knifeData)
    knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
    knife:Reset()
    knifeData.MizukiBerserkFlightClock = nil
    knifeData.MizukiSpecialBrimstoneCurse = false
    applyCannonKnifeScale(knife, cannon)
    knife.Rotation = getCannonKnifeRotation(cannon)
    setKnifeAtVisualPosition(knife, getCannonKnifeFollowPosition(cannon))
    clearCannonKnifeSpin(knife, knifeData)
    knife.Velocity = Vector.Zero
end

function Mizuki.getCannonMomKnifeBodyPosition(cannon)
    if not getCannonKnife(cannon) then
        return nil
    end
    return getCannonKnifeFollowPosition(cannon)
end

function Mizuki.getCannonMomKnifeFollowOffset(cannon)
    if not getCannonKnife(cannon) then
        return Vector.Zero
    end
    return getCannonKnifeFollowOffset(cannon)
end

function Mizuki:UpdateCannonMomKnifeEntity(knife)
    local knifeData = knife:GetData()
    local cannon = validateKnifeOwnership(knife, knifeData)
    if not cannon then
        if knifeData.MizukiCannonKnife == true then
            knife:Remove()
        end
        return
    end
    if knifeData.MizukiMultidimensionalKnife == true then
        syncMultidimensionalKnife(knife)
        return
    end
    if cannon.Player and Mizuki.usesCSectionWeapon(cannon.Player) then
        removeCannonKnife(cannon)
        return
    end
    if not Mizuki.cannonUsesKnifeWeapon(cannon.Player)
        or Mizuki.getCannonKnifeArtVariant(knife) ~= Mizuki.getCannonKnifeWeaponVariant(cannon.Player)
        or (knifeData.MizukiBerserkClub == true) ~= Mizuki.isBerserkClubActive(cannon.Player) then
        removeCannonKnife(cannon)
        return
    end
    useManualCannonKnifeRender(knife)
    applyCannonKnifeScale(knife, cannon)

    if knifeData.MizukiBerserkClub and Mizuki.updateBerserkClubSwing(knife, cannon) then
        Mizuki.refreshCannonMomKnifeShadow(cannon)
        return
    end

    local state = knifeData.MizukiCannonKnifeState or KNIFE_STATE_FOLLOW
    local motionSource = getKnifeMotionSource(knife, knifeData)
    local motionSourceFlying = motionSource and motionSource:IsFlying()
    if knifeData.MizukiCannonKnifeAuxiliary == true
        and motionSourceFlying
        and not knife:IsFlying()
    then
        -- A freshly-created auxiliary knife may finish its own native cycle
        -- sooner than the persistent knife. Keep its native collision active;
        -- its visible distance and return state are driven by the persistent
        -- knife below.
        Mizuki.refreshAuxiliaryCannonKnifeFlight(knife, cannon,
            knifeData.MizukiCannonKnifeBeam, motionSource,
            knifeData.MizukiCannonKnifeShotCharge or 1)
    end
    if state == KNIFE_STATE_FOLLOW or not motionSourceFlying then
        if knifeData.MizukiBerserkClub == true then
            knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        end
        local beam = knifeData.MizukiCannonKnifeBeam
        if beam then
            beam.MomKnifeReturnStarted = true
        end
        clearKnifeBeamLink(knifeData)
        if knifeData.MizukiCannonKnifeAuxiliary == true then
            knife:Remove()
            return
        end
        knifeData.MizukiCannonKnifeState = KNIFE_STATE_FOLLOW
        knifeData.MizukiCannonKnifePreviousDistance = nil
        knifeData.MizukiBerserkFlightClock = nil
        knifeData.MizukiSpecialBrimstoneCurse = false
        knife.Rotation = getCannonKnifeRotation(cannon)
        setKnifeAtVisualPosition(knife, getHeldKnifePosition(knife, cannon))
        clearCannonKnifeSpin(knife, knifeData)
        syncHeldBoneSpriteRotation(knife)
        knife.Velocity = Vector.Zero
        Mizuki.updateSpiritSwordMomKnife(cannon)
        Mizuki.refreshCannonMomKnifeShadow(cannon)
        return
    end

    knifeData.MizukiCannonKnifeState, knifeData.MizukiCannonKnifePreviousDistance =
        Mizuki.updateCannonKnifeFlight(knife, motionSource, knifeData.MizukiCannonKnifeBeam,
            getCannonBodyPosition(cannon), state, knifeData.MizukiCannonKnifePreviousDistance)
    if knifeData.MizukiCannonKnifeAuxiliary ~= true then
        Mizuki.refreshCannonMomKnifeShadow(cannon)
    end
end

-- Lifetime belongs to updates, including while the cannon's familiar draw is
-- hidden by a sword. Otherwise old roots accumulate and all reappear on release.
local function updateCannonKnifeLaserRoots()
    local game, frame = Game(), Game():GetFrameCount()
    for index = #knifeLaserRoots, 1, -1 do
        local root = knifeLaserRoots[index]
        local sprite = root.Sprite
        if not game:IsPaused() and root.LastFrame ~= frame then
            sprite:Update()
            root.LastFrame = frame
        end
        local laser = root.Laser
        if sameEntity(laser, root.LaserInitSeed, root.LaserPtrHash) then
            root.Position = laser.Position + laser.PositionOffset
            sprite.Color = laser.Color
        elseif not root.Ending then
            root.Ending, root.Laser = true, nil
            sprite:Play("Disappear", true)
        end
        if root.Ending and sprite:IsFinished("Disappear") then table.remove(knifeLaserRoots, index) end
    end
end
Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, updateCannonKnifeLaserRoots)

local function renderCannonKnifeLaserRoots(cannon, renderOffset)
    if Mizuki.renderCannonSpiritSword(cannon) then return end
    local game = Game()
    local room = game:GetRoom()
    local renderMode = room:GetRenderMode()
    if renderMode == RenderMode.RENDER_WATER_REFLECT
        or renderMode == RenderMode.RENDER_WATER_REFRACT then return end
    updateCannonKnifeLaserRoots()
    local cannonPtrHash = GetPtrHash(cannon)
    for _, root in ipairs(knifeLaserRoots) do
        if root.CannonInitSeed == cannon.InitSeed and root.CannonPtrHash == cannonPtrHash then
            local screenPosition = Isaac.WorldToScreen(root.Position) + (renderOffset or Vector.Zero)
                - room:GetRenderScrollOffset() - game.ScreenShakeOffset
            root.Sprite:RenderLayer(0, screenPosition)
        end
    end
end
Mizuki.renderCannonKnifeLaserRoots = renderCannonKnifeLaserRoots

function Mizuki.removeCannonKnifeLaserRoots(cannon)
    local hash = GetPtrHash(cannon)
    for index = #knifeLaserRoots, 1, -1 do
        local root = knifeLaserRoots[index]
        if root.CannonInitSeed == cannon.InitSeed and root.CannonPtrHash == hash then
            table.remove(knifeLaserRoots, index)
        end
    end
end

-- Draw the knife through its sprite rather than through Entity:Render. The entity
-- path applies the engine's parent-relative Z rules - the same rules that let a
-- beam sort above a following child - while the cannon body is a plain sprite draw
-- inside the Familiar's own slot. Going through the sprite puts both bodies on one
-- path, so their layering matches by construction. The entity itself is untouched:
-- it stays alive, keeps its collision and its updates, and stays hidden behind the
-- alpha-0 colour.
local function getBoneGlowTip(animation, frame, variant)
    -- Native ANM2 tip-null frames. Vanilla Lua cannot query null frames.
    -- The final pose in each swing lasts five frames, hence the last entry hold.
    local radius, diagonal = variant == 2 and 24 or 20, variant == 2 and 17 or 14
    if animation == "Spin" then return Vector.Zero end
    if animation == "Swing" or animation == "SwingDown2" then
        local tips = {Vector(-radius, 0), Vector(-diagonal, diagonal), Vector(0, radius),
            Vector(diagonal, diagonal), Vector(radius, 0)}
        return tips[math.min(frame + 1, #tips)]
    elseif animation == "Swing2" or animation == "SwingDown" then
        local tips = {Vector(radius, 0), Vector(diagonal, diagonal), Vector(0, radius),
            Vector(-diagonal, diagonal), Vector(-radius, 0)}
        return tips[math.min(frame + 1, #tips)]
    end
    return Vector(-radius, 0)
end

local function drawKnifeSprite(
    knife,
    renderOffset,
    worldPosition,
    cancelWaterMirror,
    finalRoomDraw
)
    local knifeData = knife:GetData()
    if knifeData.MizukiMultidimensionalKnifeSuppressed == true
        or knifeData.MizukiMultidimensionalKnifeInactive == true then return end
    local swing = knifeData.MizukiBerserkSwing
    local echoChild = knifeData.MizukiEchoKnife == true and knifeData.MizukiEchoChild
    local cannon = knifeData.MizukiCannonKnifeCannon or (echoChild and echoChild.Ghost)
    local sprite = swing and swing.VisualSprite or knife:GetSprite()
    if not swing and Mizuki.getSpiritSwordMomKnifeSprite then
        sprite = Mizuki.getSpiritSwordMomKnifeSprite(knife, cannon) or sprite
    end
    if knifeData.MizukiBerserkCollisionProxy == true and not swing then
        -- Only the collision carrier is a native Mom's Knife. Its mutable
        -- layer/animation state must not control the held bone artwork.
        sprite = knifeData.MizukiBerserkHeldSprite
        if not sprite then
            sprite = Sprite()
            sprite:Load(Mizuki.getCannonKnifeArtVariant(knife) == 2
                and "gfx/008.002_bone scythe.anm2" or "gfx/008.003_donkey jawbone.anm2", true)
            knifeData.MizukiBerserkHeldSprite = sprite
        end
        sprite:SetFrame("Idle", 0)
        sprite.FlipX = false
        sprite.FlipY = false
    end
    local swingFrame = swing and math.min(math.max(Game():GetFrameCount() - swing.Frame, 0), swing.Duration - 1)
    if swing then sprite:SetFrame(swing.Animation, swingFrame) end
    local originalRotation = sprite.Rotation
    local originalScale = Vector(sprite.Scale.X, sprite.Scale.Y)
    local originalOffset = Vector(sprite.Offset.X, sprite.Offset.Y)
    local originalFlipX = sprite.FlipX
    local originalFlipY = sprite.FlipY

    sprite.Rotation = knife.SpriteRotation
    if knifeData.MizukiBerserkClub == true and (Mizuki.getCannonKnifeArtVariant(knife) == 2 or Mizuki.getCannonKnifeArtVariant(knife) == 3) then
        -- Both bone weapons keep their fixed held-art correction, independent of
        -- native Mom's Knife sprite updates, which also run between our updates
        -- and this redraw. A swing owns its aim; a throw owns its spin history.
        if swing then
            sprite.Rotation = swing.Direction:GetAngleDegrees() + Mizuki.BerserkClubParameters.SwingRotationOffset
        elseif knife:IsFlying() then
            local beam = knifeData.MizukiCannonKnifeBeam or echoChild
            local source = beam and (echoChild and (knifeData.MizukiEchoKnifeMotionSource or knife)
                or getKnifeMotionSource(knife, knifeData))
            if source and hasCannonKnifeTinyPlanet(knife, cannon, source) then
                if knifeData.MizukiMultidimensionalKnife == true then
                    -- The child angle already contains the source's orbit.
                    sprite.Rotation = knife.SpriteRotation
                else
                    local direction = Vector.FromAngle(Mizuki.getCannonKnifeBeamAngle(beam, source))
                    sprite.Rotation = getKnifeOrbitRotation(beam, source,
                        knife.Position + knife.PositionOffset, direction)
                end
            else
                sprite.Rotation = knife.Rotation + Mizuki.BerserkClubParameters.HeldIdleRotationOffset
                    + (knifeData.MizukiCannonKnifeSpinAngle or 0)
            end
        else
            sprite.Rotation = echoChild and knife.Rotation + echoChild.KnifeSpriteRotationOffset
                or getHeldBoneDrawRotation(knife, cannon)
            if knifeData.MizukiBerserkCollisionProxy == true then
                sprite:SetFrame("Idle", 0)
                sprite.FlipX = false
                sprite.FlipY = false
            end
        end
        if not swing and not knife:IsFlying() and not echoChild
            and cannon and cannon:Exists() then
            sprite.Rotation = sprite.Rotation + Mizuki.BerserkClubParameters.ActiveBodyRotationOffset
        end
    end
    sprite.Scale = Vector(knife.SpriteScale.X, knife.SpriteScale.Y)
    sprite.Offset = Vector.Zero
    sprite.Color = knifeData.MizukiCannonKnifeDrawColor or Color.Default
    if cannon and cannon:Exists() and cannon:GetData().MizukiPersistentEchoMode
        and not Mizuki.isEchoAttackReplayActive(knife) then
        sprite.Color = Mizuki.getPersistentEchoColor(sprite.Color)
    end
    if cancelWaterMirror then
        sprite.FlipY = not sprite.FlipY
    end
    local screenPosition = Isaac.WorldToScreen(worldPosition)
    if not finalRoomDraw then
        local game = Game()
        screenPosition = screenPosition
            + (renderOffset or Vector.Zero)
            - game:GetRoom():GetRenderScrollOffset()
            - game.ScreenShakeOffset
    end
    local deadEyeIntensity = knifeData.MizukiDeadEyeIntensity
    if knifeData.MizukiCannonKnife == true and not echoChild
        and not (cannon and cannon:Exists() and cannon:GetData().MizukiPersistentEchoMode)
        and not swing and not knife:IsFlying() then
        deadEyeIntensity = Mizuki.getDeadEyeIntensity(knifeData.MizukiCannonKnifeOwner)
    end
    local boneGlowPose = knifeData.MizukiBerserkCollisionProxy == true
    if not boneGlowPose then
        Mizuki.renderDeadEyeGlow(knife, screenPosition, sprite.Scale, sprite.Color.A,
            deadEyeIntensity, sprite.Rotation)
    end
    if boneGlowPose then
        -- Bone Scythe and Donkey Jawbone point horizontally in their source
        -- artwork; the stretched glow's long axis is vertical at rotation 0.
        local glowPosition = screenPosition
        local glowRotation = sprite.Rotation + Mizuki.BerserkClubParameters.GlowRotationOffset
        do
            local tip = getBoneGlowTip(swing and swing.Animation or sprite:GetAnimation(),
                swingFrame or sprite:GetFrame(), Mizuki.getCannonKnifeArtVariant(knife))
            if sprite.FlipX then tip.X = -tip.X end
            if sprite.FlipY then tip.Y = -tip.Y end
            -- Native bone Render places the glow halfway towards the tip null.
            -- Both the swing's frame pose and our final redraw rotation matter.
            local localOffset = tip * 0.5
            if tip:LengthSquared() > 0 then
                if not swing and not knife:IsFlying() and not echoChild and cannon and cannon:Exists()
                    and cannon:GetData().MizukiIsIdle == true then
                    -- Held glow correction follows the weapon's own lower axis,
                    -- opposite the animated tip, rather than world/screen Y.
                    localOffset = (localOffset + (tip * -1):Resized(
                        Mizuki.BerserkClubParameters.HeldGlowAxisOffset * WORLD_TO_SCREEN_SCALE)) * -1
                end
                glowRotation = sprite.Rotation + tip:GetAngleDegrees()
                    + Mizuki.BerserkClubParameters.GlowRotationOffset
            end
            local offset = localOffset:Rotated(sprite.Rotation)
            glowPosition = glowPosition + Vector(offset.X * sprite.Scale.X, offset.Y * sprite.Scale.Y)
        end
        Mizuki.renderDeadEyeGlow(knife, glowPosition, sprite.Scale, sprite.Color.A,
            deadEyeIntensity, glowRotation)
    end
    -- Sprite.Color is mutable native state. Keep an owned copy so changing
    -- the sprite for one trail cannot change the body or the next trail's alpha.
    local bodyColor = Color.Lerp(sprite.Color, sprite.Color, 0)
    local beam = knifeData.MizukiCannonKnifeBeam or echoChild
    local source = beam and (echoChild and (knifeData.MizukiEchoKnifeMotionSource or knife)
        or getKnifeMotionSource(knife, knifeData))
    if source and source:Exists() and source:IsFlying() and beam.Laser and beam.Laser:Exists()
        and hasCannonKnifeTinyPlanet(knife, cannon, source) then
        local distance = math.max(0, source:GetKnifeDistance())
        if distance > KNIFE_DISTANCE_EPSILON then
            local origin = beam.Laser.Position + beam.Laser.PositionOffset
            local endpoint = knife.Position + knife.PositionOffset
            local bodyRotation = sprite.Rotation
            local radialPosition = endpoint - origin
            local radius = getKnifeOrbitRadius(source, distance)
            local currentAngle = Mizuki.getCannonKnifeBeamAngle(beam, source)
            -- Native orbit-knife Render (0x965E60-0x966202): two in-between
            -- poses, distance - velocity*0.2*(index+1), alpha 0.6-index*0.3.
            -- Map those poses through our current curved ray, rather than
            -- drawing the engine's original parent-centred orbit underneath.
            for index = 1, 0, -1 do
                local trailDistance = math.max(0,
                    distance - source:GetKnifeVelocity() * 0.2 * (index + 1))
                local angleDelta = Mizuki.getCannonKnifeBeamAngle(beam, source, trailDistance)
                    - currentAngle
                local trailRadius = getKnifeOrbitRadius(source, trailDistance)
                local trailPosition = origin + (radialPosition * (radius ~= 0 and trailRadius / radius or 1))
                    :Rotated(angleDelta) + (worldPosition - endpoint)
                local trailScreen = screenPosition
                    + Isaac.WorldToScreen(trailPosition) - Isaac.WorldToScreen(worldPosition)
                local trailColor = Color.Lerp(bodyColor, bodyColor, 0)
                trailColor.A = bodyColor.A * (0.6 - index * 0.3)
                sprite.Color = trailColor
                sprite.Rotation = bodyRotation + angleDelta
                sprite:Render(trailScreen, Vector.Zero, Vector.Zero)
            end
            sprite.Rotation = bodyRotation
            sprite.Color = bodyColor
        end
    end
    sprite:Render(screenPosition, Vector.Zero, Vector.Zero)
    Mizuki.renderSpecialBrimstoneIcon(knife, worldPosition,
        finalRoomDraw and Vector.Zero or renderOffset, sprite.Color.A, screenPosition)

    sprite.Rotation = originalRotation
    sprite.Scale = originalScale
    sprite.Offset = originalOffset
    local drawColor = knifeData.MizukiCannonKnifeDrawColor or Color.Default
    sprite.Color = Color(
        drawColor.R, drawColor.G, drawColor.B, 0,
        drawColor.RO, drawColor.GO, drawColor.BO
    )
    sprite.FlipX = originalFlipX
    sprite.FlipY = originalFlipY
end

function Mizuki.renderBerserkEchoKnife(knife, renderOffset)
    local data = knife:GetData()
    if data.MizukiEchoKnife ~= true or data.MizukiBerserkCollisionProxy ~= true then return false end
    drawKnifeSprite(knife, renderOffset, knife.Position + knife.PositionOffset, false, false)
    return true
end

function Mizuki.renderBerserkMeleeKnife(knife, renderOffset)
    local data = knife:GetData()
    if data.MizukiBerserkMeleeBody ~= true then return end
    local swing = data.MizukiBerserkSwing
    local source = swing and swing.Source
    if swing and swing.Echo and source and source.Cannon and source.Cannon:Exists()
        and source.Cannon:GetData().MizukiIsIdle == true then return end
    drawKnifeSprite(knife, renderOffset, knife.Position + knife.PositionOffset, false, false)
end

local function renderCannonKnifeEntity(
    knife,
    cannon,
    renderOffset,
    reflectedBodyPosition,
    cancelWaterMirror,
    finalRoomDraw
)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnife ~= true
        or knifeData.MizukiCannonKnifeManualRender ~= true
    then
        return false
    end

    local worldPosition = knife.Position + knife.PositionOffset
    -- Draw the collision entity's authoritative pose. Reading newer laser
    -- samples here makes the art advance while its capsule remains behind.
    if reflectedBodyPosition then
        -- The cannon renderer supplies the final full-size knife anchor on the reflected
        -- plane. Translate the live knife by the difference between that anchor
        -- and its normal cannon anchor; collision stays at the real position.
        worldPosition = worldPosition
            + (reflectedBodyPosition - getCannonBodyPosition(cannon))
    end

    drawKnifeSprite(
        knife,
        renderOffset,
        worldPosition,
        cancelWaterMirror,
        finalRoomDraw
    )
    return true
end

local function usesFamiliarBoneBodyDraw(knife)
    local data = knife:GetData()
    if data.MizukiMultidimensionalKnife == true then return false end
    return data.MizukiCannonKnife == true and data.MizukiCannonKnifeManualRender == true
        and data.MizukiBerserkClub == true and (Mizuki.getCannonKnifeArtVariant(knife) == 2 or Mizuki.getCannonKnifeArtVariant(knife) == 3)
end

-- Ordinary knives return to the familiar slot once their beam ends. Bone
-- bodies stay in the familiar slot so the native weapon pass can add the glow
-- afterwards, without drawing another body over it at the end of the room.
local function getKnifeRenderLaser(knife)
    local knifeData = knife:GetData()
    if knifeData.MizukiCannonKnifeManualRender ~= true
        or knifeData.MizukiCannonKnifeState == KNIFE_STATE_FOLLOW
    then
        return nil
    end
    local beam = knifeData.MizukiCannonKnifeBeam
    local ownedKnife = beamOwnsKnife(beam)
    if not ownedKnife or GetPtrHash(ownedKnife) ~= GetPtrHash(knife) then
        return nil
    end
    local laser = beam.Laser
    if not laser or not laser:Exists() then
        return nil
    end
    if not validateKnifeOwnership(knife, knifeData) then return nil end
    return laser
end

local function usesSpiritSwordHeldKnifeDepthDraw(knife, cannon)
    local data = knife:GetData()
    return data.MizukiCannonKnife == true and data.MizukiCannonKnifeManualRender == true
        and not knife:IsFlying() and cannon and cannon:Exists()
        and Mizuki.renderCannonSpiritSword(cannon)
        and Mizuki.isSameEntity(getCannonKnife(cannon), knife)
end

-- Held sword knives render in their hilt's depth pass. Only airborne knives
-- need the final room pass after the extended attack laser.
local function usesFinalCannonKnifeDraw(knife, cannon)
    if usesSpiritSwordHeldKnifeDepthDraw(knife, cannon) then return false end
    if usesFamiliarBoneBodyDraw(knife) then return false end
    if getKnifeRenderLaser(knife) then return true end
    local data = knife:GetData()
    return data.MizukiCannonKnife == true and data.MizukiCannonKnifeManualRender == true
        and cannon and cannon:Exists() and Mizuki.renderCannonSpiritSword(cannon)
        and Mizuki.isSameEntity(getCannonKnife(cannon), knife)
end

function Mizuki.renderSpiritSwordHeldKnifeBody(cannon, renderOffset)
    local knife = getCannonKnife(cannon)
    if not knife or not usesSpiritSwordHeldKnifeDepthDraw(knife, cannon) then return false end
    return renderCannonKnifeEntity(knife, cannon, renderOffset, nil, false, false)
end

function Mizuki.renderCannonMomKnifeBody(
    cannon,
    renderOffset,
    reflectedBodyPosition,
    cancelWaterMirror
)
    local knife = getCannonKnife(cannon)
    if not knife then
        return false
    end
    renderCannonKnifeLaserRoots(cannon, renderOffset)
    if knife:GetData().MizukiCannonKnifeNativeRender == true then return true end
    if not reflectedBodyPosition and usesSpiritSwordHeldKnifeDepthDraw(knife, cannon) then
        return true -- the depth-controlled hilt pass owns the visible body
    end
    if not reflectedBodyPosition and usesFinalCannonKnifeDraw(knife, cannon) then
        -- The body is supplied by the final room draw. Returning true also keeps
        -- the cannon renderer from drawing ordinary cannon artwork in this slot.
        return true
    end
    renderCannonKnifeEntity(
        knife,
        cannon,
        renderOffset,
        reflectedBodyPosition,
        cancelWaterMirror,
        false
    )
    if reflectedBodyPosition or usesFamiliarBoneBodyDraw(knife) then
        for _, auxiliaryKnife in ipairs(getAuxiliaryCannonKnives(cannon)) do
            if reflectedBodyPosition or usesFamiliarBoneBodyDraw(auxiliaryKnife) then
                renderCannonKnifeEntity(
                    auxiliaryKnife,
                    cannon,
                    renderOffset,
                    reflectedBodyPosition,
                    cancelWaterMirror,
                    false
                )
            end
        end
    end
    return true
end

function Mizuki:RenderFlyingMomKnives()
    local game = Game()
    if game:GetFrameCount() <= 0 then return end

    -- Echo ghosts are not in the player's real cannon lists. Their explicitly
    -- registered split knives use the same final draw as the real split knives.
    for source, beam in pairs(multidimensionalKnifeSources) do
        if source:Exists() and source:GetData().MizukiEchoKnife == true
            and beam.Cannon and beam.Cannon:Exists() then
            for _, knife in ipairs(getAuxiliaryCannonKnives(beam.Cannon)) do
                if knife:GetData().MizukiMultidimensionalKnife == true
                    and Mizuki.isSameEntity(knife:GetData().MizukiCannonKnifeMotionSource, source)
                    and getKnifeRenderLaser(knife) then
                    renderCannonKnifeEntity(knife, beam.Cannon, Vector.Zero, nil, false, true)
                end
            end
        end
    end
    for playerIndex = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(playerIndex)
        local cannons = player:GetData().MizukiCannons
        if cannons then
            for side = 1, 2 do
                for _, cannon in ipairs(cannons[side] or {}) do
                    if cannon and cannon:Exists() then
                        local knife = getCannonKnife(cannon)
                        if knife and usesFinalCannonKnifeDraw(knife, cannon) then
                            renderCannonKnifeEntity(
                                knife,
                                cannon,
                                Vector.Zero,
                                nil,
                                false,
                                true
                            )
                        end
                        for _, auxiliaryKnife in ipairs(
                            getAuxiliaryCannonKnives(cannon)
                        ) do
                            if not usesFamiliarBoneBodyDraw(auxiliaryKnife) and getKnifeRenderLaser(auxiliaryKnife) then
                                renderCannonKnifeEntity(
                                    auxiliaryKnife,
                                    cannon,
                                    Vector.Zero,
                                    nil,
                                    false,
                                    true
                                )
                            end
                        end
                        -- Sword bodies share this final pass with real knives;
                        -- no per-laser callback can leave a later tip above them.
                        Mizuki.renderSpiritSwordBodies(cannon)
                    end
                end
            end
        end
    end
end

function Mizuki:ClearCannonKnifeLaserRoots()
    knifeLaserRoots = {}
    for knife in pairs(multidimensionalKnifeSources) do restoreMultidimensionalKnife(knife) end
    multidimensionalKnifeSources = {}
end

Mizuki:AddCallback(
    ModCallbacks.MC_POST_NEW_ROOM,
    Mizuki.ClearCannonKnifeLaserRoots
)

Mizuki:AddCallback(
    ModCallbacks.MC_POST_RENDER,
    Mizuki.RenderFlyingMomKnives
)

Mizuki:AddCallback(
    ModCallbacks.MC_POST_KNIFE_UPDATE,
    Mizuki.UpdateCannonMomKnifeEntity
)

-- Native knife launch 0x9671ED..0x96744D excludes bone/sword variants
-- from Lung's subtype-1 knife volley. Our bone flight carrier is variant 0,
-- so suppress only its explicitly identified native children; the custom bone
-- scatter is already emitted and recorded by the weapon controller.
local function identifyBerserkCarrierProjectile(knife)
    local data = knife:GetData()
    if data.MizukiBerserkCarrierProjectile == true then return true end
    if knife.Variant ~= 0 or knife.SubType ~= 1 then return false end
    local parent = knife.Parent and knife.Parent:ToKnife()
    if not parent or not parent:Exists() or parent.SubType ~= 0 then return false end
    local source = parent:GetData()
    if source.MizukiBerserkCollisionProxy ~= true or source.MizukiBerserkClub ~= true
        or (source.MizukiCannonKnife ~= true and source.MizukiEchoKnife ~= true) then return false end
    -- Bone Scythe + Lung intentionally emits ordinary knife projectiles.
    -- Read the source weapon's resolved identity, not the owner's later items.
    if Mizuki.getBerserkLungScatterKind(source.MizukiCannonKnifeArtVariant) ~= "bone" then return false end
    data.MizukiBerserkCarrierProjectile = true
    return true
end

-- Parent is assigned after INIT in the native launch path, but before the
-- child's first Update. Cancel contact too, in case collision precedes POST.
Mizuki:AddCallback(ModCallbacks.MC_PRE_KNIFE_COLLISION, function(_, knife)
    if identifyBerserkCarrierProjectile(knife) then return true end
end)

-- The engine can emit subtype-1 knives from a fired Mom's Knife. They inherit
-- the alpha-0 native body colour, although that body is drawn manually here.
-- Restore only those projectiles' inherited transparency, preserving their
-- native tint, motion, damage and any later nonzero fade.
local function restoreCannonKnifeProjectileAlpha(_, knife)
    if identifyBerserkCarrierProjectile(knife) then
        knife:Remove()
        return
    end
    if knife.SubType ~= 1 then return end
    local parent = knife.Parent and knife.Parent:ToKnife()
    if not parent or not parent:Exists() or parent.SubType ~= 0 then return end
    local parentData = parent:GetData()
    if parentData.MizukiCannonKnife ~= true
        or parentData.MizukiCannonKnifeManualRender ~= true
        or not validateKnifeOwnership(parent, parentData) then return end
    local drawColor = parentData.MizukiCannonKnifeDrawColor
    if not drawColor or drawColor.A <= 0 then return end
    if knife.Color.A <= 0 then
        local color = Color.Lerp(knife.Color, knife.Color, 0)
        color.A = drawColor.A
        knife.Color = color
    end
    local sprite = knife:GetSprite()
    if sprite.Color.A <= 0 then
        local spriteColor = Color.Lerp(sprite.Color, sprite.Color, 0)
        spriteColor.A = drawColor.A
        sprite.Color = spriteColor
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_INIT, restoreCannonKnifeProjectileAlpha)
Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, restoreCannonKnifeProjectileAlpha)
