-- Fixed XML blindfold. The body/throw use the existing knife-driven beam;
-- melee uses a separate, explicitly owned hitbox, as in Samael's weapon.
local C = CollectibleType
local P = {SwingFrames = 10, MeleeMultiplier = 3, ThrowMultiplier = 1.5,
    HitInvincibilityFrames = 8, Recoil = 5, Knockback = 10, MinimumThrowCharge = 3,
    MeleeReach = 32, HitboxRadius = 32, ScytheSizeMultiplier = 1.25,
    RotationPivotPixels = 2,
    HeldIdleRotationOffset = 180, SwingRotationOffset = -90}
Mizuki.BerserkClubParameters = P
local HITBOX_SUBTYPE = 9521

function Mizuki.isBerserkClubActive(player)
    return player and player:Exists() and not player:IsDead()
        and player:GetEffects():HasCollectibleEffect(C.COLLECTIBLE_BERSERK)
        and not player:HasCollectible(C.COLLECTIBLE_C_SECTION) or false
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
    return state and state.Held and state.Phase == 'charging' and state.Side ~= nil
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
    return direction
end

local facingActions = {
    [ButtonAction.ACTION_SHOOTLEFT] = Vector(-1, 0),
    [ButtonAction.ACTION_SHOOTRIGHT] = Vector(1, 0),
    [ButtonAction.ACTION_SHOOTUP] = Vector(0, -1),
    [ButtonAction.ACTION_SHOOTDOWN] = Vector(0, 1),
}

local function holdSwingHeadDirection(_, entity, hook, action)
    if not facingActions[action] or not entity then return end
    local player = entity:ToPlayer()
    if not player or not Mizuki.isMizuki(player) or not player:AreControlsEnabled()
        or not Mizuki.isBerserkClubActive(player) then return end
    local direction = Mizuki.getBerserkSwingDirection(player:GetData())
    if not direction then return end
    local chosenAction
    if math.abs(direction.X) > math.abs(direction.Y) then
        chosenAction = direction.X < 0 and ButtonAction.ACTION_SHOOTLEFT or ButtonAction.ACTION_SHOOTRIGHT
    else
        chosenAction = direction.Y < 0 and ButtonAction.ACTION_SHOOTUP or ButtonAction.ACTION_SHOOTDOWN
    end
    if hook == InputHook.IS_ACTION_PRESSED then return action == chosenAction end
    if hook == InputHook.GET_ACTION_VALUE then return action == chosenAction and 0.01 or 0 end
end
Mizuki:AddCallback(ModCallbacks.MC_INPUT_ACTION, holdSwingHeadDirection, InputHook.IS_ACTION_PRESSED)
Mizuki:AddCallback(ModCallbacks.MC_INPUT_ACTION, holdSwingHeadDirection, InputHook.GET_ACTION_VALUE)

local function beginSwing(cannon, direction, alternate)
    local knife = Mizuki.ensureCannonKnife(cannon)
    if not knife or knife:IsFlying() then return false end
    local player, data = cannon.Player, knife:GetData()
    removeSwingHitbox(data.MizukiBerserkSwing)
    -- Native BONE parameters include the Berserk EXTRA_GORE flag. This marks
    -- enemies for the engine's kill reward (duration/speed/invincibility).
    local params = player:GetTearHitParams(WeaponType.WEAPON_BONE, 1, 1, knife)
    knife.TearFlags = params.TearFlags | TearFlags.TEAR_EXTRA_GORE
    data.MizukiCannonKnifeDrawColor = Color.Lerp(params.TearColor, params.TearColor, 0)
    local hidden = Color.Lerp(params.TearColor, params.TearColor, 0)
    hidden.A = 0
    knife.Color = hidden
    local sword = knife.Variant == 10
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
        Damage = params.TearDamage * P.MeleeMultiplier,
        MaxHits = knife.Variant == 2 and 2 or 1, Player = player,
        PlayerSeed = player.InitSeed, Sword = sword, VisualSprite = swingSprite,
        Duration = sword and 8 or P.SwingFrames}
    if sword then swing.Damage = params.TearDamage * 1.5 + 1.75 end
    data.MizukiBerserkSwing = swing
    if Mizuki.rollSpecialBrimstone then Mizuki.rollSpecialBrimstone(knife, player) end
    SFXManager():Play(SoundEffect.SOUND_SHELLGAME, 1, 0, false, 1)
    return swing
end

function Mizuki.updateBerserkClubInput(player, data, held, direction, profile, fire)
    local state = data.MizukiBerserkInput or {Held = false, Cooldown = 0}
    data.MizukiBerserkInput = state
    state.Cooldown = math.max(0, state.Cooldown - 1)
    if held and not state.Held then
        state.Direction, state.Side, state.ChargeStartFrame = direction, nil, nil
        state.Phase = 'waiting'
        data.MizukiCharge, data.MizukiChargeBarFullFrames = 0, nil
    end
    -- Cooldown gates starting the whole melee-then-charge sequence.
    -- A held press waits here until it can perform a real initial swing.
    if held and state.Phase == 'waiting' and state.Cooldown == 0 then
        local nextShotSide = -(data.MizukiShotSide or -1)
        local side = nextShotSide == -1 and 1 or 2
        local alternate = not state.Alternate
        local swung = false
        for _, cannon in ipairs(data.MizukiCannons[side] or {}) do
            local cd = cannon:GetData()
            if cannon:Exists() and not cd.MizukiAwaitingInitialLayout
                and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode then
                local swing = beginSwing(cannon, direction, alternate)
                if swing then
                    swung = true
                    state.ChargeStartFrame = math.max(state.ChargeStartFrame or 0,
                        swing.Frame + swing.Duration)
                end
            end
        end
        if swung then
            data.MizukiShotSide, state.Side, state.Alternate = nextShotSide, side, alternate
            state.Cooldown = math.max(1, player.MaxFireDelay + 1)
            state.Phase = 'swinging'
        end
    end
    if held then
        state.Direction = direction or state.Direction
        -- Charging continues the same sequence as soon as its melee animation
        -- ends; it does not require a second cooldown check.
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
        if state.Side and data.MizukiCharge >= math.max(P.MinimumThrowCharge, profile.MinFrames)
            and state.Direction then
            fire(player, state.Direction, data.MizukiCharge, false, state.Side)
        end
        data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
        state.Phase, state.ChargeStartFrame, state.Side = 'idle', nil, nil
    end
    state.Held = held
end

local pickupBlacklist = {
    [PickupVariant.PICKUP_COLLECTIBLE] = true, [PickupVariant.PICKUP_SHOPITEM] = true,
    [PickupVariant.PICKUP_TROPHY] = true, [PickupVariant.PICKUP_BIGCHEST] = true,
    [PickupVariant.PICKUP_BED] = true, [PickupVariant.PICKUP_MEGACHEST] = true,
    [PickupVariant.PICKUP_THROWABLEBOMB] = true,
}
local pickupTransfers = {}

local function interact(swing, knife, position, radius)
    local player = swing.Player
    for _, entity in ipairs(Isaac.FindInRadius(position, radius)) do
        local hash = GetPtrHash(entity)
        if not swing.Interactions[hash] then
            local projectile = entity:ToProjectile()
            local bomb = entity:ToBomb()
            local pickup = entity:ToPickup()
            if projectile and knife.Variant ~= 2
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
            elseif pickup and not pickupBlacklist[pickup.Variant] and pickup.Price == 0
                and pickup.Wait <= 0 and pickup:GetSprite():GetAnimation() ~= 'Collect'
                and not pickup:GetData().MizukiBerserkPickupTransfer then
                swing.Interactions[hash] = true
                if pickup.Variant == PickupVariant.PICKUP_MIMICCHEST then
                    pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_SPIKEDCHEST,
                        pickup.SubType, false, true, false)
                end
                -- Samael's native-collection transfer preserves pickup effects,
                -- affordability and chest/room triggers; never manually grant items.
                local pd = pickup:GetData()
                pd.MizukiBerserkPickupTransfer = {Position = Vector(pickup.Position.X, pickup.Position.Y),
                    Player = player, PlayerSeed = player.InitSeed, Frame = Game():GetFrameCount(),
                    PlayerPosition = Vector(player.Position.X, player.Position.Y),
                    PickupSeed = pickup.InitSeed, Variant = pickup.Variant,
                    Color = Color.Lerp(pickup:GetSprite().Color, pickup:GetSprite().Color, 0)}
                pickupTransfers[GetPtrHash(pickup)] = pd.MizukiBerserkPickupTransfer
                pickup.Position = player.Position
                pickup.Velocity = Vector.Zero
                local hidden = Color.Lerp(pd.MizukiBerserkPickupTransfer.Color,
                    pd.MizukiBerserkPickupTransfer.Color, 0)
                hidden.A = 0
                pickup:GetSprite().Color = hidden
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
    if age >= swing.Duration or knife:IsFlying() or not Mizuki.isBerserkClubActive(cannon.Player) then
        removeSwingHitbox(swing)
        data.MizukiBerserkSwing = nil
        knife:GetSprite():Play(swing.Sword and 'IdleRight' or 'Idle', true)
        return false
    end
    local anchor = Mizuki.getCannonKnifeAnchor(cannon)
    knife.Position = anchor - knife.PositionOffset
    knife.Velocity = Vector.Zero
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
            interact(swing, knife, position, radius)
        end
    else removeSwingHitbox(swing) end
    return true
end

local damageReplay
Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.EARLY,
    function(_, enemy, amount, flags, source, countdown)
        local attack = source and source.Entity
        if not attack or not enemy:IsVulnerableEnemy() then return end
        local data = attack:GetData()
        if damageReplay and damageReplay.Attack == GetPtrHash(attack)
            and damageReplay.Target == GetPtrHash(enemy) then return end
        if data.MizukiBerserkSwingHitbox == true then
            local swing = data.MizukiBerserkSwingState
            if not valid(data.MizukiBerserkBody, data.MizukiBerserkBodySeed)
                or not valid(swing.Player, swing.PlayerSeed) then return false end
            local hash, frame = GetPtrHash(enemy), Game():GetFrameCount()
            local previous = swing.Targets[hash]
            if previous and previous.Seed == enemy.InitSeed
                and (previous.Count >= swing.MaxHits or frame - previous.Frame < 3) then return false end
            enemy:AddEntityFlags(EntityFlag.FLAG_EXTRA_GORE)
            -- Re-enter once to fix this custom hitbox's damage without changing
            -- native flag/on-hit handling or applying the held-knife multiplier twice.
            damageReplay = {Attack = GetPtrHash(attack), Target = hash}
            local ok, result = pcall(function()
                return enemy:TakeDamage(swing.Damage, flags, source, countdown)
            end)
            damageReplay = nil
            if not ok then error(result) end
            if result then
                swing.Targets[hash] = {Seed = enemy.InitSeed, Frame = frame,
                    Count = (previous and previous.Count or 0) + 1}
                swing.Player:SetMinDamageCooldown(P.HitInvincibilityFrames)
                enemy:AddVelocity(swing.Direction * P.Knockback)
                swing.Player:AddVelocity(-swing.Direction * P.Recoil)
                SFXManager():Play(SoundEffect.SOUND_MEATY_DEATHS, 1, 0, false, 1.5)
            end
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
        or not Mizuki.isBerserkClubActive(cannon.Player)
        or Game():GetFrameCount() - swing.Frame > 7 then hitbox:Remove(); return end
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

-- Native collection is performed at the player for two updates. As in
-- Samael, contents of opened chests/sacks must return to the original site.
local function restorePickupContents(_, entity)
    local transfer = pickupTransfers[GetPtrHash(entity)]
    if transfer and entity.InitSeed ~= transfer.PickupSeed then transfer = nil end
    if not transfer then
        local spawner = entity.SpawnerEntity
        transfer = spawner and spawner:GetData().MizukiBerserkPickupTransfer
    end
    if not transfer then
        local closest
        for _, candidate in pairs(pickupTransfers) do
            if Game():GetFrameCount() - candidate.Frame < 2 then
                local distance = entity.Position:DistanceSquared(candidate.PlayerPosition)
                if distance <= 25 and (not closest or distance < closest) then
                    closest, transfer = distance, candidate
                end
            end
        end
    end
    if transfer then
        entity.Position = Vector(transfer.Position.X, transfer.Position.Y)
        local pickup = entity:ToPickup()
        if pickup then pickup.TargetPosition = entity.Position end
    end
end
Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, restorePickupContents)
Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, restorePickupContents)
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, restorePickupContents)
Mizuki:AddCallback(ModCallbacks.MC_POST_NPC_INIT, restorePickupContents)
for _, variant in ipairs({BombVariant.BOMB_TROLL, BombVariant.BOMB_SUPERTROLL,
    BombVariant.BOMB_GOLDENTROLL}) do
    Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, restorePickupContents, variant)
end
Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    for hash, transfer in pairs(pickupTransfers) do
        if Game():GetFrameCount() - transfer.Frame >= 2 then pickupTransfers[hash] = nil end
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() pickupTransfers = {} end)

Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    local data = pickup:GetData()
    local transfer = data.MizukiBerserkPickupTransfer
    if not transfer or Game():GetFrameCount() - transfer.Frame < 2 then return end
    pickup:GetSprite().Color = transfer.Color
    if pickup:GetSprite():GetAnimation() ~= 'Collect' then
        pickup.Position = transfer.Position
        pickup.Velocity = valid(transfer.Player, transfer.PlayerSeed)
            and (transfer.Position - transfer.Player.Position):Resized(5) or Vector.Zero
    end
    data.MizukiBerserkPickupTransfer = nil
end)

Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_RENDER, function(_, pickup)
    local transfer = pickup:GetData().MizukiBerserkPickupTransfer
    if not transfer then return end
    local sprite = pickup:GetSprite()
    local hidden = sprite.Color
    sprite.Color = transfer.Color
    sprite:Render(Isaac.WorldToScreen(transfer.Position), Vector.Zero, Vector.Zero)
    sprite.Color = hidden
end)

Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, _, _, source)
    local pickup = source and source.Entity and source.Entity:ToPickup()
    if not entity:ToPlayer() then return end
    local attacker = source and source.Entity
    if attacker and attacker.Type == EntityType.ENTITY_POLTY then
        for _, transfer in pairs(pickupTransfers) do
            if transfer.Variant == PickupVariant.PICKUP_HAUNTEDCHEST
                and valid(transfer.Player, transfer.PlayerSeed)
                and GetPtrHash(transfer.Player) == GetPtrHash(entity)
                and Game():GetFrameCount() - transfer.Frame < 2 then return false end
        end
    end
    if not pickup then return end
    local transfer = pickup:GetData().MizukiBerserkPickupTransfer
    if transfer and valid(transfer.Player, transfer.PlayerSeed)
        and GetPtrHash(transfer.Player) == GetPtrHash(entity)
        and (pickup.Variant == PickupVariant.PICKUP_SPIKEDCHEST
            or pickup.Variant == PickupVariant.PICKUP_MIMICCHEST) then return false end
end)
