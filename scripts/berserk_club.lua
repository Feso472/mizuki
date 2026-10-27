-- Fixed XML blindfold. The body/throw use the existing knife-driven beam;
-- melee uses a separate, explicitly owned hitbox, as in Samael's weapon.
local C = CollectibleType
local P = {SwingFrames = 10, MeleeMultiplier = 3, ThrowMultiplier = 1.5,
    HitInvincibilityFrames = 8, Recoil = 5, Knockback = 10, MinimumThrowCharge = 3,
    MeleeReach = 32, HitboxRadius = 32, ScytheSizeMultiplier = 1.25,
    RotationPivotPixels = 2,
    HeldIdleRotationOffset = 180, HeldBodyRotationOffset = -90, SwingRotationOffset = -90,
    ActiveBodyRotationOffset = 180,
    GlowRotationOffset = 90,
    HeldGlowAxisOffset = 30,
    ScytheMeleeMultiplier = 1.5, ScytheThrowHitInterval = 1,
    ScytheThrowBaseMultiplier = 0.4, ScytheThrowOutgoingMultiplier = 0.4,
    ScytheThrowChargeSpeedDivisor = 3,
    ThrowHitInterval = 8}
Mizuki.BerserkClubParameters = P
-- Use native tear parameters and record the resolved outcome, like other echoes.
function Mizuki.fireBerserkLungTear(player, position, velocity, multiplier, source, replayMultiplier)
    local tear = player:FireTear(position, velocity, false, false, false, player, multiplier or 1)
    tear:GetData().MizukiBerserkLungTear = true
    tear:ChangeVariant(source and source.Variant or TearVariant.BONE)
    tear:ClearTearFlags(Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS)
    if source then
        tear.Scale, tear.Height = source.Scale, source.Height
        tear.FallingSpeed, tear.FallingAcceleration = source.FallingSpeed, source.FallingAcceleration
        Mizuki.bindEchoAttackReplay(tear, source.Sequence, {
            Alpha = Mizuki.CannonEchoReplayAlpha, Tint = true, DamageMultiplier = replayMultiplier})
        return tear
    end
    tear:AddTearFlags(TearFlags.TEAR_EXTRA_GORE)
    if player:HasCollectible(C.COLLECTIBLE_EYE_OF_THE_OCCULT) then tear:AddTearFlags(TearFlags.TEAR_HOMING) end
    Mizuki.trackDeadEyeProjectile(player, tear)
    return {Position = Vector(tear.Position.X, tear.Position.Y), Velocity = Vector(tear.Velocity.X, tear.Velocity.Y),
        Variant = tear.Variant, Scale = tear.Scale, Height = tear.Height,
        FallingSpeed = tear.FallingSpeed, FallingAcceleration = tear.FallingAcceleration,
        Sequence = Mizuki.startEchoAttackRecording(tear)}
end

function Mizuki.getCannonKnifeArtVariant(knife)
    return knife:GetData().MizukiCannonKnifeArtVariant or knife.Variant
end
local HITBOX_SUBTYPE = 9521
local swingVolleys = {}
local meleeBodies = {}
local MELEE_REPEAT_INTERVAL = 2 -- native 96A783..96A790, 96ADC0..96ADCF

function Mizuki.isBerserkClubActive(player)
    return player and player:Exists() and not player:IsDead()
        and player:GetEffects():HasCollectibleEffect(C.COLLECTIBLE_BERSERK) or false
end

function Mizuki.cannonUsesKnifeWeapon(player)
    return player and player:Exists() and (player:HasCollectible(C.COLLECTIBLE_MOMS_KNIFE)
        or Mizuki.isBerserkClubActive(player)) or false
end

function Mizuki.getCannonKnifeWeaponVariant(player)
    if Mizuki.isBerserkClubActive(player) then
        if player:HasCollectible(C.COLLECTIBLE_MOMS_KNIFE) then return 2 end
        if player:HasCollectible(C.COLLECTIBLE_SPIRIT_SWORD) then return 10 end
        return 3
    end
    return 0
end

-- Resolve the weapon before applying Lung. Bone Scythe keeps the native
-- small-knife volley; ordinary bone weapons use our recorded bone-tear scatter.
function Mizuki.getBerserkLungScatterKind(weaponVariant)
    if weaponVariant == 2 then return "knife" end
    if weaponVariant == 3 or weaponVariant == 10 then return "bone" end
end

local function valid(entity, seed)
    return entity and entity:Exists() and entity.InitSeed == seed
end

local function removeSwingHitbox(swing)
    local hitbox = swing and swing.Hitbox
    if valid(hitbox, swing and swing.HitboxSeed)
        and hitbox:GetData().MizukiBerserkSwingHitbox == true then hitbox:Remove() end
end

function Mizuki.cancelBerserkClubSwing(knife)
    local data = knife:GetData()
    removeSwingHitbox(data.MizukiBerserkSwing)
    data.MizukiBerserkSwing = nil
end

function Mizuki.clearBerserkClubInput(data)
    data.MizukiBerserkInput = nil
    data.MizukiCharge = 0
    data.MizukiAim = nil
    data.MizukiChargeBarFullFrames = nil
end

function Mizuki.shouldRenderBerserkClubChargeBar(data)
    local state = data.MizukiBerserkInput
    return state and (state.Held or Mizuki.isReleaseProtected(state.ChargeReleaseHoldUntil))
        and state.Phase == 'charging' and state.Side ~= nil
        and (data.MizukiCharge or 0) > 0 or false
end

function Mizuki.getBerserkSwingDirection(data)
    local direction, latestSwingFrame
    for _, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            local knife = cannon:Exists() and cannon:GetData().MizukiMomKnife
            if knife and knife:Exists() then
                local kd = knife:GetData()
                if kd.MizukiCannonKnife == true and kd.MizukiBerserkClub == true then
                    local swing = kd.MizukiBerserkSwing
                    if swing and Game():GetFrameCount() < swing.Frame + swing.Duration
                        and (not latestSwingFrame or swing.Frame > latestSwingFrame) then
                        direction, latestSwingFrame = swing.Direction, swing.Frame
                    end
                end
            end
        end
    end
    for body, seed in pairs(meleeBodies) do
        if not valid(body, seed) then meleeBodies[body] = nil
        else
            local swing = body:GetData().MizukiBerserkSwing
            if swing and not swing.Echo and valid(swing.Player, swing.PlayerSeed) and swing.Player:GetData() == data
                and Game():GetFrameCount() < swing.Frame + swing.Duration
                and (not latestSwingFrame or swing.Frame > latestSwingFrame) then
                direction, latestSwingFrame = swing.Direction, swing.Frame
            end
        end
    end
    return direction
end

local function beginSwing(cannon, direction, alternate, body, source, echo)
    local knife = body or Mizuki.ensureCannonKnife(cannon)
    if not knife or knife:IsFlying() then return false end
    local player, data = cannon.Player, knife:GetData()
    removeSwingHitbox(data.MizukiBerserkSwing)
    -- Native BONE parameters include the Berserk EXTRA_GORE flag. This marks
    -- enemies for the engine's kill reward (duration/speed/invincibility).
    local params = source and {TearFlags = source.Flags, TearDamage = 0}
        or player:GetTearHitParams(WeaponType.WEAPON_BONE, 1, 1, knife)
    knife.TearFlags = params.TearFlags | TearFlags.TEAR_EXTRA_GORE
    local weaponColor = source and source.Color
        or player:GetData().MizukiMomKnifeBaseColor or Color.Default
    if echo then weaponColor = Mizuki.getCannonEchoColor(weaponColor, Mizuki.CannonEchoReplayAlpha) end
    local bodyColor = Color.Lerp(weaponColor, weaponColor, 0)
    if data.MizukiCannonKnifeNativeRender ~= true then
        data.MizukiCannonKnifeDrawColor = Color.Lerp(weaponColor, weaponColor, 0)
        bodyColor.A = 0
    end
    knife.Color = bodyColor
    knife:GetSprite().Color = bodyColor
    local sword = Mizuki.getCannonKnifeArtVariant(knife) == 10
    local anim = sword and (alternate and 'AttackLeft' or 'AttackRight')
        or (alternate and 'Swing2' or 'Swing')
    local sprite = knife:GetSprite()
    sprite:Play(anim, true)
    -- Native knife initialization hides the whoosh layers on held subtype 0
    -- (0x961157); only native melee subtype 4 enables them. A standalone
    -- Sprite retains the complete animation without changing the real weapon.
    local swingSprite = data.MizukiBerserkSwingSprite
    if not swingSprite or swingSprite:GetFilename() ~= sprite:GetFilename() then
        swingSprite = Sprite()
        swingSprite:Load(sprite:GetFilename(), true)
        data.MizukiBerserkSwingSprite = swingSprite
    end
    swingSprite:Play(anim, true)
    swingSprite:SetFrame(anim, 0)
    knife.Rotation = direction:GetAngleDegrees()
    -- The bone Swing artwork faces down at rotation 0; align it with aim.
    -- The resting jawbone's flip belongs only to the idle renderer.
    knife.SpriteRotation = sword and knife.Rotation or knife.Rotation + P.SwingRotationOffset
    local swing = {Frame = Game():GetFrameCount(), Animation = anim,
        Direction = Vector(direction.X, direction.Y), Targets = {}, Interactions = {},
        Damage = params.TearDamage * (Mizuki.getCannonKnifeArtVariant(knife) == 2
            and P.ScytheMeleeMultiplier or P.MeleeMultiplier),
        MaxHits = Mizuki.getCannonKnifeArtVariant(knife) == 2 and 2 or 1, Player = player,
        PlayerSeed = player.InitSeed, Sword = sword, VisualSprite = swingSprite,
        Duration = sword and 8 or P.SwingFrames, Alternate = alternate,
        Cannon = cannon, CannonSeed = cannon.InitSeed, Body = knife,
        Flags = knife.TearFlags, Color = Color.Lerp(weaponColor, weaponColor, 0),
        WeaponVariant = Mizuki.getCannonKnifeArtVariant(knife),
        Scale = Vector(knife.SpriteScale.X, knife.SpriteScale.Y), Echo = echo == true,
        Source = source,
        AnchorOffset = source and source.AnchorOffset
            or (Mizuki.getCannonKnifeAnchor(cannon) - cannon.Position)}
    if source then
        swing.Damage, swing.MaxHits, swing.Duration = source.Damage, source.MaxHits, source.Duration
    elseif sword then swing.Damage = params.TearDamage * 1.5 + 1.75 end
    data.MizukiBerserkSwing = swing
    if not echo then
        swing.DeadEyeAttack = Mizuki.trackDeadEyeSwing(player, knife, swing.Duration)
        Mizuki.rollSpecialBrimstone(knife, player)
    else data.MizukiSpecialBrimstoneCurse = source.Curse end
    swing.Curse = data.MizukiSpecialBrimstoneCurse
    local playerData, frame = player:GetData(), Game():GetFrameCount()
    if not echo and playerData.MizukiBerserkSwingSoundFrame ~= frame then
        -- Native bone swing: 0x96A9F5..0x96AA40, sound 252, pitch 0.9..1.1.
        local pitch = 0.9 + Random() * (0.2 / 4294967296)
        SFXManager():Play(SoundEffect.SOUND_SHELLGAME, 1, 1, false, pitch)
        playerData.MizukiBerserkSwingSoundFrame = frame
    end
    return swing
end

local function createSwingBody(cannon, direction, alternate, source, echo)
    local variant = source and source.WeaponVariant or Mizuki.getCannonKnifeWeaponVariant(cannon.Player)
    local body = Mizuki.createCannonKnifeBody(cannon, Mizuki.getCannonKnifeAnchor(cannon),
        direction:GetAngleDegrees(), variant, true)
    if not body then return end
    local bd = body:GetData()
    -- Independent melee body, never a registered held/throwing knife.
    bd.MizukiBerserkMeleeBody, bd.MizukiBerserkMeleeCannon = true, cannon
    bd.MizukiBerserkMeleeCannonSeed = cannon.InitSeed
    body.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    if source then body.SpriteScale = Vector(source.Scale.X, source.Scale.Y) end
    local swing = beginSwing(cannon, direction, alternate, body, source, echo)
    if not swing then body:Remove(); return end
    meleeBodies[body] = body.InitSeed
    return swing
end

function Mizuki.replayBerserkClubSwing(player, ghost, source, multiplier)
    local swing = createSwingBody(ghost, source.Direction, not source.Alternate, source, true)
    if swing then swing.Damage = source.Damage * multiplier end
    return swing
end

function Mizuki.getBerserkSwingEchoPosition(source)
    if valid(source.Cannon, source.CannonSeed) then return source.Cannon.Position end
end

function Mizuki.updateBerserkClubInput(player, data, held, direction, profile, fire)
    local state = data.MizukiBerserkInput or {Held = false, Cooldown = 0}
    data.MizukiBerserkInput = state
    state.Cooldown = math.max(0, state.Cooldown - 1)
    local milk = player:HasCollectible(C.COLLECTIBLE_SOY_MILK)
        or player:HasCollectible(C.COLLECTIBLE_ALMOND_MILK)
    local continuousMelee = milk or data.MizukiKidneyStoneBurst ~= nil
    local charge, resumed, protected = Mizuki.protectChargeRelease(state, held,
        continuousMelee and 0 or (data.MizukiCharge or 0), continuousMelee)
    data.MizukiCharge = charge
    if resumed and state.ChargeStartFrame then
        state.ChargeStartFrame = Game():GetFrameCount() - charge
    elseif held and not state.Held then
        state.Direction, state.Side, state.ChargeStartFrame = direction, nil, nil
        state.Phase = 'waiting'
        data.MizukiCharge, data.MizukiChargeBarFullFrames = 0, nil
    end
    -- Cooldown gates starting the whole melee-then-charge sequence.
    -- A held press waits here until it can perform a real initial swing.
    if held and continuousMelee and state.Cooldown == 0 then state.Phase = 'waiting' end
    if held and state.Phase == 'waiting' and state.Cooldown == 0 then
        local nextShotSide = -(data.MizukiShotSide or -1)
        local side = nextShotSide == -1 and 1 or 2
        if Mizuki.hasCannonTech2(player) then side = 1 end
        local alternate = not state.Alternate
        local swung = false
        for _, cannon in ipairs(data.MizukiCannons[side] or {}) do
            local cd = cannon:GetData()
            if cannon:Exists() and not cd.MizukiAwaitingInitialLayout
                and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode then
                local swing = beginSwing(cannon, direction, alternate)
                if swing then
                    swung = true
                    if not state.Volley then
                        local angles, count = Mizuki.getSpiritSwordVolley(player)
                        data.MizukiFiniteVolleyId = (data.MizukiFiniteVolleyId or 0) + 1
                        state.EchoVolleyId = data.MizukiFiniteVolleyId
                        state.Volley = {Player = player, PlayerSeed = player.InitSeed,
                            Side = side, Direction = Vector(direction.X, direction.Y),
                            Alternate = alternate, Angles = angles, Count = count,
                            Next = 2, Frame = swing.Frame, Duration = swing.Duration,
                            Cannons = {}, Echo = Mizuki.beginCannonEchoShot(player, side, state.EchoVolleyId)}
                        swingVolleys[#swingVolleys + 1] = state.Volley
                    end
                    local volley = state.Volley
                    volley.Cannons[#volley.Cannons + 1] = {Entity = cannon, Seed = cannon.InitSeed}
                    if volley.Echo then Mizuki.captureCannonEchoBerserkSwing(volley.Echo, swing) end
                    for index = 2, #volley.Angles do
                        local extra = createSwingBody(cannon, direction:Rotated(volley.Angles[index]), alternate)
                        if extra and volley.Echo then Mizuki.captureCannonEchoBerserkSwing(volley.Echo, extra) end
                    end
                    state.ChargeStartFrame = math.max(state.ChargeStartFrame or 0,
                        swing.Frame + swing.Duration + (volley.Count - 1) * MELEE_REPEAT_INTERVAL)
                end
            end
        end
        if swung then
            data.MizukiShotSide, state.Side, state.Alternate = nextShotSide, side, alternate
            state.Cooldown = math.max(Mizuki.getFireInterval(player),
                (state.Volley.Count - 1) * MELEE_REPEAT_INTERVAL)
            state.Phase = 'swinging'
            Mizuki.recordMeleeAttackEffects(player, side, direction)
            Mizuki.chargeIsaacsTearsFromAttack(player, 1)
            state.Volley = nil
        end
    end
    if held then
        state.Direction = direction or state.Direction
        -- Charging continues the same sequence as soon as its melee animation
        -- ends; it does not require a second cooldown check.
        if continuousMelee then state.ChargeStartFrame = nil end
        if state.Side and state.ChargeStartFrame
            and Game():GetFrameCount() >= state.ChargeStartFrame then
            state.Phase = 'charging'
        end
        data.MizukiCharge = state.Side and state.ChargeStartFrame and math.min(profile.MaxFrames,
            math.max(0, Game():GetFrameCount() - state.ChargeStartFrame + 1)) or 0
        data.MizukiAim = state.Direction
        data.MizukiChargeBarFullFrames = data.MizukiCharge >= profile.MaxFrames
            and ((data.MizukiChargeBarFullFrames or 0) + 1) or nil
    elseif state.Held then
        local minimumThrowCharge = player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            and profile.MinFrames or math.max(P.MinimumThrowCharge, profile.MinFrames)
        local throwCharge = milk and profile.MaxFrames or data.MizukiCharge
        if state.Side and throwCharge >= minimumThrowCharge and state.Direction then
            fire(player, state.Direction, throwCharge, false, state.Side, state.EchoVolleyId)
            Mizuki.protectChargeRelease(state, false, 0, true)
            protected = false
        end
        if not protected then
            data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
            state.Phase, state.ChargeStartFrame, state.Side = 'idle', nil, nil
        end
    elseif not held and not protected then
        data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
        state.Phase, state.ChargeStartFrame, state.Side = 'idle', nil, nil
    end
    state.Held = held
end

local function interact(swing, knife, position, radius)
    local player = swing.Player
    for _, entity in ipairs(Isaac.FindInRadius(position, radius)) do
        local hash = GetPtrHash(entity)
        if not swing.Interactions[hash] then
            local projectile = entity:ToProjectile()
            local bomb = entity:ToBomb()
            local pickup = entity:ToPickup()
            if projectile and Mizuki.getCannonKnifeArtVariant(knife) ~= 2
                and not projectile:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER) then
                swing.Interactions[hash] = true
                projectile.Velocity = swing.Direction:Resized(math.max(8, projectile.Velocity:Length()))
                projectile:AddProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER | ProjectileFlags.HIT_ENEMIES)
                projectile.CollisionDamage = projectile.Damage <= 1 and 6 or 7
                projectile.SpawnerEntity = player
                projectile.Parent = player
            elseif bomb then
                swing.Interactions[hash] = true
                bomb:AddVelocity(swing.Direction * P.Knockback)
            elseif pickup and Mizuki.tryCollectMeleePickup(pickup, player) then
                swing.Interactions[hash] = true
            elseif entity.Type == EntityType.ENTITY_FIREPLACE then
                swing.Interactions[hash] = true
                entity:TakeDamage(100, 0, EntityRef(knife), 0)
            end
        end
    end
    local room = Game():GetRoom()
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid and grid:GetType() == GridEntityType.GRID_POOP
            and grid.Position:DistanceSquared(position) <= (radius + 12) ^ 2 then
            room:DestroyGrid(index, false)
        end
    end
end

function Mizuki.updateBerserkClubSwing(knife, cannon)
    local data = knife:GetData()
    local swing = data.MizukiBerserkSwing
    if not swing then return false end
    local age = Game():GetFrameCount() - swing.Frame
    if age >= swing.Duration or knife:IsFlying()
        or (not swing.Echo and not Mizuki.isBerserkClubActive(cannon.Player)) then
        removeSwingHitbox(swing)
        data.MizukiBerserkSwing = nil
        knife:GetSprite():Play(swing.Sword and 'IdleRight' or 'Idle', true)
        return false
    end
    local anchor = swing.Echo and cannon.Position + swing.AnchorOffset or Mizuki.getCannonKnifeAnchor(cannon)
    knife.Position = anchor - knife.PositionOffset
    knife.Velocity = cannon.Velocity
    if data.MizukiBerserkMeleeBody == true then
        knife.DepthOffset = cannon.Position.Y + cannon.DepthOffset - knife.Position.Y + (swing.Echo and 0 or 1)
        knife.Color = Color(1, 1, 1, 0)
        knife:GetSprite().Color = knife.Color
    end
    knife.Rotation = swing.Direction:GetAngleDegrees()
    knife.SpriteRotation = swing.Sword and knife.Rotation or knife.Rotation + P.SwingRotationOffset
    -- The body has no idle/contact damage. Only the explicit swing hitbox
    -- attacks until Shoot starts the native thrown body's flight.
    knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    knife:GetSprite():SetFrame(swing.Animation, age)
    swing.VisualSprite:SetFrame(swing.Animation, age)
    local scale = math.max(math.abs(knife.SpriteScale.X), math.abs(knife.SpriteScale.Y))
    local weaponScale = scale * (swing.MaxHits == 2 and P.ScytheSizeMultiplier or 1)
    local radius = P.HitboxRadius * weaponScale
    local position = knife.Position + swing.Direction * (P.MeleeReach * weaponScale)
    if age >= 2 and age <= 7 then
        if not valid(swing.Hitbox, swing.HitboxSeed) then
            local hitbox = Isaac.Spawn(EntityType.ENTITY_KNIFE, 0, HITBOX_SUBTYPE,
                position, Vector.Zero, cannon.Player):ToKnife()
            local hd = hitbox:GetData()
            hd.MizukiBerserkSwingHitbox = true
            hd.MizukiBerserkSwingState = swing
            hd.MizukiBerserkBody = knife
            hd.MizukiBerserkBodySeed = knife.InitSeed
            hd.MizukiBerserkCannon = cannon
            hd.MizukiBerserkCannonSeed = cannon.InitSeed
            hd.MizukiSpecialBrimstoneCurse = data.MizukiSpecialBrimstoneCurse
            hitbox.Parent, hitbox.SpawnerEntity = cannon.Player, cannon.Player
            hitbox.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
            hitbox.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            hitbox.TearFlags = knife.TearFlags
            hitbox.CollisionDamage = swing.Damage / 2 -- held native Mom's Knife multiplier
            hitbox.Color = Color(1, 1, 1, 0)
            hitbox:GetSprite().Color = hitbox.Color
            swing.Hitbox, swing.HitboxSeed = hitbox, hitbox.InitSeed
        end
        swing.Hitbox.Position, swing.Hitbox.Velocity = position, cannon.Velocity
        swing.Hitbox.Size, swing.Hitbox.SizeMulti = radius, Vector.One
        swing.Hitbox.SpriteRotation = knife.SpriteRotation
        if swing.LastInteractionFrame ~= Game():GetFrameCount() then
            swing.LastInteractionFrame = Game():GetFrameCount()
            Mizuki:QueueFirstHitFetusGridBomb(swing.Hitbox)
            Mizuki.queueEpicFetusGridTarget(swing.Hitbox)
            interact(swing, knife, position, radius)
        end
    else removeSwingHitbox(swing) end
    return true
end

Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, body)
    local bd = body:GetData()
    if bd.MizukiBerserkMeleeBody ~= true then return end
    local cannon = bd.MizukiBerserkMeleeCannon
    if not valid(cannon, bd.MizukiBerserkMeleeCannonSeed)
        or not Mizuki.updateBerserkClubSwing(body, cannon) then
        removeSwingHitbox(bd.MizukiBerserkSwing)
        meleeBodies[body] = nil
        body:Remove()
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_RENDER, function(_, body, offset)
    if body:GetData().MizukiBerserkMeleeBody == true then
        Mizuki.renderBerserkMeleeKnife(body, offset)
    end
end)

local dispatchBerserkKnifeHit
Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.EARLY,
    function(_, enemy, _, flags, source, countdown)
        local attack = source and source.Entity
        if not attack or not enemy:IsVulnerableEnemy() then return end
        local data = attack:GetData()
        if data.MizukiBerserkDamageDispatch == true then return end
        if data.MizukiBerserkCollisionProxy == true or data.MizukiBerserkSwingHitbox == true then
            -- Existing independent hitboxes reach this native damage path even
            -- when PRE_KNIFE_COLLISION does not fire. Dispatch before cancelling
            -- the native amount; both entries share the same target clock.
            dispatchBerserkKnifeHit(attack, enemy, flags, countdown, "damage")
            return false
        end
    end)

Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, hitbox)
    local data = hitbox:GetData()
    if data.MizukiBerserkSwingHitbox ~= true then return end
    local body, cannon, swing = data.MizukiBerserkBody, data.MizukiBerserkCannon,
        data.MizukiBerserkSwingState
    if not valid(body, data.MizukiBerserkBodySeed) or not valid(cannon, data.MizukiBerserkCannonSeed)
        or body:GetData().MizukiBerserkSwing ~= swing
        or (not swing.Echo and not Mizuki.isBerserkClubActive(cannon.Player))
        or Game():GetFrameCount() - swing.Frame >= 8
    then hitbox:Remove(); return end
    hitbox.Color = Color(1, 1, 1, 0)
    hitbox:GetSprite().Color = hitbox.Color
    local scale = math.max(math.abs(body.SpriteScale.X), math.abs(body.SpriteScale.Y))
        * (swing.MaxHits == 2 and P.ScytheSizeMultiplier or 1)
    hitbox.Position = body.Position + swing.Direction * (P.MeleeReach * scale)
    hitbox.Velocity = cannon.Velocity
    hitbox.Size, hitbox.SizeMulti = P.HitboxRadius * scale, Vector.One
    hitbox.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ENEMIES
    hitbox.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
end)

dispatchBerserkKnifeHit = function(knife, enemy, damageFlags, countdown, entry)
    local data = knife:GetData()
    if data.MizukiBerserkCollisionProxy ~= true and data.MizukiBerserkSwingHitbox ~= true then return end
    if not enemy:IsVulnerableEnemy() or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return true end
    local swing = data.MizukiBerserkSwingHitbox and data.MizukiBerserkSwingState
    local player = swing and swing.Player or (knife.SpawnerEntity and knife.SpawnerEntity:ToPlayer())
    if not player or not player:Exists() then return true end
    local frame = Game():GetFrameCount()
    if swing then
        if not valid(data.MizukiBerserkBody, data.MizukiBerserkBodySeed)
            or data.MizukiBerserkBody:GetData().MizukiBerserkSwing ~= swing
            or frame - swing.Frame < 2 or frame - swing.Frame > 7 then return true end
    elseif data.MizukiBerserkSwing or not knife:IsFlying() then return true end
    local targets = swing and swing.Targets or data.MizukiBerserkThrowTargets or {}
    if not swing then data.MizukiBerserkThrowTargets = targets end
    local key, previous = GetPtrHash(enemy), targets[GetPtrHash(enemy)]
    local scytheThrow = not swing and data.MizukiBerserkCollisionProxy == true
        and Mizuki.getCannonKnifeArtVariant(knife) == 2
    -- Game:GetFrameCount advances at the 30 Hz logic rate: one update is the
    -- wiki's two rendered frames. Both collision entries still share a clock.
    local interval = swing and 3 or (scytheThrow and P.ScytheThrowHitInterval or P.ThrowHitInterval)
    if previous and previous.Seed == enemy.InitSeed
        and ((swing and previous.Count >= swing.MaxHits) or frame - previous.Frame < interval) then return true end
    local damage = swing and swing.Damage or knife.CollisionDamage
    if scytheThrow then
        -- Native Bone Scythe hit (0x966A77-0x966AB5). Negative/zero velocity
        -- gives the fixed return multiplier; charge/speed reduce outward damage.
        local speed = Mizuki.getCannonKnifeMotionVelocity(knife)
        local outgoing = math.max(0, math.min(1, knife.Charge * speed / P.ScytheThrowChargeSpeedDivisor))
        damage = damage * (P.ScytheThrowBaseMultiplier + P.ScytheThrowOutgoingMultiplier * outgoing)
    end
    if data.MizukiBerserkCollisionProxy == true then
        local child = data.MizukiEchoKnife == true and data.MizukiEchoChild
        local multiplier = child and child.Shot.DamageMultiplier
            or (Mizuki.getPersistentEchoKnifeMultiplier(knife))
        damage = damage * (multiplier or 1)
    end
    enemy:AddEntityFlags(EntityFlag.FLAG_EXTRA_GORE)
    data.MizukiBerserkDamageDispatch = true
    local ok, accepted = pcall(function()
        return enemy:TakeDamage(damage, damageFlags or 0, EntityRef(knife), countdown or 0)
    end)
    data.MizukiBerserkDamageDispatch = nil
    if not ok then error(accepted) end
    if accepted then
        targets[key] = {Seed = enemy.InitSeed, Frame = frame, Count = (previous and previous.Count or 0) + 1}
        local deadEyeAttack = swing and swing.DeadEyeAttack or data.MizukiDeadEyeAttack
        if deadEyeAttack then deadEyeAttack.Hit = true end
        if swing then
            if not swing.HitFeedbackPlayed then
                swing.HitFeedbackPlayed = true
                SFXManager():Play(SoundEffect.SOUND_MEATY_DEATHS, 1, 0, false, 1.5)
                player:AddVelocity(-swing.Direction * P.Recoil)
            end
            player:SetMinDamageCooldown(P.HitInvincibilityFrames)
            enemy:AddVelocity(swing.Direction * P.Knockback)
        end
    end
    return true -- Cancel native knife damage and its collision response.
end
Mizuki:AddCallback(ModCallbacks.MC_PRE_KNIFE_COLLISION, function(_, knife, enemy)
    return dispatchBerserkKnifeHit(knife, enemy)
end)

-- Complete the native-style short volley even after the original tap ends.
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    if Game():IsPaused() then return end
    local frame = Game():GetFrameCount()
    for index = #swingVolleys, 1, -1 do
        local volley = swingVolleys[index]
        if not valid(volley.Player, volley.PlayerSeed) or not Mizuki.isBerserkClubActive(volley.Player)
            or frame < volley.Frame or volley.Next > volley.Count then
            table.remove(swingVolleys, index)
        elseif volley.Player == player then
            if frame >= volley.Frame + (volley.Next - 1) * MELEE_REPEAT_INTERVAL then
                local alternate = (volley.Next % 2 == 1) == volley.Alternate
                local fired = false
                for _, member in ipairs(volley.Cannons) do
                    if valid(member.Entity, member.Seed) then
                        for _, angle in ipairs(volley.Angles) do
                            local swing = createSwingBody(member.Entity, volley.Direction:Rotated(angle), alternate)
                            if swing then
                                fired = true
                                if volley.Echo then Mizuki.captureCannonEchoBerserkSwing(volley.Echo, swing) end
                            end
                        end
                    end
                end
                if fired then
                    Mizuki.recordMeleeAttackEffects(player, volley.Side, volley.Direction)
                    Mizuki.chargeIsaacsTearsFromAttack(player, 1)
                end
                volley.Next = volley.Next + 1
            end
        end
    end
end)
