-- C Section firing, fetus effects and character costume handling.
local isMizuki = Mizuki.isMizuki
local FAN_FETUS_BLOCK_CHANCE = 0.10
local BALL_SCALE = 0.50

-- C Section belongs to the real fan familiar, not the cannon/echo controller.
-- Preserve native tear physics and graphics; the player API supplies item
-- effects and damage while Source and SpawnerEntity identify the emitting fan.
local FAN_FETUS_SPEED = Mizuki.WeaponParameters.TearBaseSpeed
local FAN_FETUS_SOUND_VOLUME = 1
local spawningFetusParticles
local FAN_FETUS_SYNERGIES = {
    { CollectibleType.COLLECTIBLE_SPIRIT_SWORD, TearFlags.TEAR_FETUS_SWORD },
    { CollectibleType.COLLECTIBLE_MOMS_KNIFE, TearFlags.TEAR_FETUS_KNIFE },
    { CollectibleType.COLLECTIBLE_TECH_X, TearFlags.TEAR_FETUS_TECHX },
    { CollectibleType.COLLECTIBLE_TECHNOLOGY, TearFlags.TEAR_FETUS_TECH },
    { CollectibleType.COLLECTIBLE_BRIMSTONE, TearFlags.TEAR_FETUS_BRIMSTONE },
    { CollectibleType.COLLECTIBLE_DR_FETUS, TearFlags.TEAR_FETUS_BOMBER },
}

function Mizuki.getFanFetusDirection(player)
    local data = player:GetData()
    if not data.MizukiHasShootingInput then return nil end
    local direction = data.MizukiCannonAim or data.MizukiLastShootDirection
    if direction and direction:Length() > Mizuki.RuntimeParameters.AimDeadZone then
        return direction:Normalized()
    end
end

function Mizuki.fireFanFetus(player, familiar, direction, origin, damageMultiplier)
    local firingPosition = origin or familiar.Position
    local playerData = player:GetData()
    local untinted = isMizuki(player) and playerData.MizukiUntintedTearColor
    local playerColor = player.TearColor
    if untinted then player.TearColor = untinted end
    -- Use the untinted cache for this one native creation, retaining the same
    -- random flags/damage/color roll. Never query tear params a second time.
    local ok, tear = pcall(player.FireTear, player,
        firingPosition,
        direction:Resized(player.ShotSpeed * FAN_FETUS_SPEED),
        false, false, true, familiar, damageMultiplier or 1
    )
    -- Restore even if the API or another mod's init callback raises an error.
    if untinted then player.TearColor = playerColor end
    if not ok then error(tear, 0) end
    tear:ChangeVariant(TearVariant.FETUS)
    tear:AddTearFlags(TearFlags.TEAR_FETUS | TearFlags.TEAR_SPECTRAL)
    for _, synergy in ipairs(FAN_FETUS_SYNERGIES) do
        if player:HasCollectible(synergy[1]) then
            tear:AddTearFlags(synergy[2])
        end
    end
    -- FireTear + ChangeVariant bypasses native fetal weapon setup. Berserk
    -- grants a temporary bone weapon; owning the active item is insufficient.
    if player:HasWeaponType(WeaponType.WEAPON_BONE)
        or player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BERSERK) then
        tear:AddTearFlags(TearFlags.TEAR_FETUS_BONE)
    end
    tear.Parent = player
    tear.SpawnerEntity = familiar
    tear:GetData().MizukiFanFetus = true
    if isMizuki(player) then
        local sprite = tear:GetSprite()
        sprite:ReplaceSpritesheet(0, "gfx/characters/costumes/mizuki_fetus_tears.png")
        sprite:LoadGraphics()
    end
    local frame = Game():GetFrameCount()
    -- Copies can fire together. One plop per player's volley avoids layering
    -- identical sounds; delayed echo shots still get their own firing feedback.
    if playerData.MizukiFanFetusSoundFrame ~= frame then
        SFXManager():Play(SoundEffect.SOUND_PLOP, FAN_FETUS_SOUND_VOLUME, 0, false, 1)
        playerData.MizukiFanFetusSoundFrame = frame
    end
    return tear
end

function Mizuki.spawnFanFetusBlood(player, familiar, tear, echo)
    if not isMizuki(player) or tear:GetData().MizukiFanFetus ~= true then return end
    local tint = Color(1, 1, 1, 1, 0, 0, 0)
    if echo then
        tint.A = Mizuki.CannonEchoReplayAlpha
    end
    -- Captured vanilla shots use 1000.2.2 / Poof, no parent, constant
    -- launch velocity and a -15 visual offset rather than the fetus's height.
    local blood = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BLOOD_EXPLOSION,
        2, tear.Position, tear.Velocity, familiar):ToEffect()
    blood:GetData().MizukiFanFetusBlood = true
    blood.Color = tint
    blood.PositionOffset = Vector(0, -15)
    blood:GetSprite():Play("Poof", true)

    local rng = blood:GetDropRNG()
    local speed = tear.Velocity:Length()
    local sideways = Vector(-tear.Velocity.Y, tear.Velocity.X)
    -- Native particle physics supplies falling, droplets and landing. The
    -- trace shows one main gib and 3-4 subtype-99 gibs per launch; their
    -- random vertical launch distribution has not yet been captured.
    local context = { Effects = {}, Color = tint }
    spawningFetusParticles = context
    Game():SpawnParticles(tear.Position, EffectVariant.BLOOD_PARTICLE,
        1, speed, tint, tear.Height, 0)
    Game():SpawnParticles(tear.Position, EffectVariant.BLOOD_PARTICLE,
        3 + rng:RandomInt(2), speed, tint, tear.Height, 99)
    spawningFetusParticles = nil
    for _, particle in ipairs(context.Effects) do
        if particle:Exists() then
            local spread = particle.SubType == 99 and (rng:RandomFloat() * 0.3 - 0.15) or 0
            particle.Velocity = tear.Velocity * rng:RandomFloat() + sideways * spread
            particle.Color = tint
        end
    end
end

function Mizuki:InitFanFetusBloodParticle(effect)
    local data = effect:GetData()
    if spawningFetusParticles then
        data.MizukiFanFetusBlood = true
        effect.Color = spawningFetusParticles.Color
        spawningFetusParticles.Effects[#spawningFetusParticles.Effects + 1] = effect
    else
        -- Native secondary droplets keep a spawner reference to the main gib.
        -- Only propagate from explicitly identified Mizuki blood effects.
        local source = effect.SpawnerEntity
        if source and source:Exists() and source:GetData().MizukiFanFetusBlood == true then
            data.MizukiFanFetusBlood = true
            effect.Color = Color.Lerp(source.Color, source.Color, 0)
        end
    end
end

function Mizuki.updateFanFetus(familiar, player)
    local data = familiar:GetData()
    if not Mizuki.usesCSectionWeapon(player) then
        data.MizukiFanFetusCooldown = nil
        data.MizukiFanFetusInterval = nil
        data.MizukiFanFetusCharge = nil
        data.MizukiFanFetusChargeFrames = nil
        return
    end
    if Game():IsPaused() or player:IsDead() or not player:AreControlsEnabled() then
        return
    end

    -- Direct fire: the first shot is immediate; subsequent shots use the
    -- ordinary fire interval. Keep the remaining fraction when Tears changes.
    local interval = Mizuki.getFireInterval(player)
    local cooldown = data.MizukiFanFetusCooldown or 0
    local previousInterval = data.MizukiFanFetusInterval
    if previousInterval and math.abs(previousInterval - interval)
        > Mizuki.RuntimeParameters.FrameComparisonEpsilon then
        cooldown = cooldown * interval / previousInterval
    end
    cooldown = math.max(0, cooldown - 1)
    data.MizukiFanFetusInterval = interval
    data.MizukiFanFetusCooldown = cooldown
    -- Retire the previous charge state on a Lua reload.
    data.MizukiFanFetusCharge = nil
    data.MizukiFanFetusChargeFrames = nil
    local direction = Mizuki.getFanFetusDirection(player)
    if not direction or cooldown > 0 then return end

    local fetuses = {}
    for _, angle in ipairs(Mizuki.getMizukiBeamAngleOffsets(player, true)) do
        local tear = Mizuki.fireFanFetus(player, familiar, direction:Rotated(angle))
        Mizuki.prepareFetalBrimstone(tear, player)
        Mizuki.spawnFanFetusBlood(player, familiar, tear, false)
        fetuses[#fetuses + 1] = tear
        -- Count actual original fetuses, including multishot. Echo replay
        -- calls fireFanFetus directly and must not roll/count these again.
        -- Both additions stay ordinary tears and originate from gbt.
        Mizuki.tryFireImmaculateHeartTear(player, direction:Rotated(angle),
            familiar.Position, familiar)
        Mizuki.recordExtraAttack(player, direction:Rotated(angle),
            familiar.Position, familiar)
    end
    data.MizukiFanFetusCooldown = interval
    if #fetuses > 0 then
        Mizuki.recordFanInputAttackEffects(player, direction)
        Mizuki.chargeIsaacsTearsFromAttack(player, 1)
    end
    return fetuses
end

function Mizuki:RemoveFanCSectionCostume(player)
    local data = player:GetData()
    if not isMizuki(player)
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        data.MizukiFanCSectionCostumeRemoved = nil
        data.MizukiFanCSectionCostumeRefreshPending = nil
        data.MizukiFanCSectionCostumeItemCount = nil
        data.MizukiFanCSectionCostumeCount = nil
        return
    end
    local itemCount = player:GetCollectibleCount()
    local cSectionCount = player:GetCollectibleNum(CollectibleType.COLLECTIBLE_C_SECTION)
    if data.MizukiFanCSectionCostumeRemoved
        and not data.MizukiFanCSectionCostumeRefreshPending
        and data.MizukiFanCSectionCostumeItemCount == itemCount
        and data.MizukiFanCSectionCostumeCount == cSectionCount then return end
    -- Removing a costume is an appearance mutation, not a per-frame keepalive.
    -- Stat/familiar cache evaluation is NOT an inventory change. Do not queue
    -- this from MC_EVALUATE_CACHE: it can fire repeatedly without a new costume.
    data.MizukiFanCSectionCostumeRemoved = true
    data.MizukiFanCSectionCostumeRefreshPending = nil
    data.MizukiFanCSectionCostumeItemCount = itemCount
    data.MizukiFanCSectionCostumeCount = cSectionCount
    player:RemoveCostume(Isaac.GetItemConfig():GetCollectible(
        CollectibleType.COLLECTIBLE_C_SECTION
    ))
end

function Mizuki:QueueFanCSectionCostumeRefresh(collectible, rng, player)
    if isMizuki(player)
        and player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        player:GetData().MizukiFanCSectionCostumeRefreshPending = true
    end
end

function Mizuki:BlockProjectilesWithFanFetus(tear)
    if tear:GetData().MizukiFanFetus ~= true or tear:IsDead() then return end
    local player = tear.Parent and tear.Parent:ToPlayer()
    if not player or not player:Exists() or not isMizuki(player) then return end
    -- Lost Contact keeps its native guaranteed shielding. Do not add SHIELDED
    -- to every fetus: that would turn this 10% bonus into a guaranteed block.
    if tear:HasTearFlags(TearFlags.TEAR_SHIELDED) then return end
    local key = tostring(tear.InitSeed) .. ":" .. tostring(GetPtrHash(tear))
    -- Test actual entity radii without enabling native guaranteed shielding.
    -- No fixed search radius: large projectiles and enlarged fetuses still count.
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PROJECTILE,
        -1, -1, true, true)) do
        local projectile = entity:ToProjectile()
        if projectile and projectile:Exists() and not projectile:IsDead()
            and not projectile:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER)
            and projectile.Position:DistanceSquared(tear.Position)
                <= (tear.Size + projectile.Size) ^ 2 then
            local data = projectile:GetData()
            data.MizukiFanFetusBlockAttempts = data.MizukiFanFetusBlockAttempts or {}
            if not data.MizukiFanFetusBlockAttempts[key] then
                data.MizukiFanFetusBlockAttempts[key] = true
                if tear:GetDropRNG():RandomFloat() < FAN_FETUS_BLOCK_CHANCE then
                    projectile:Die()
                end
            end
        end
    end
end

function Mizuki.registerCSectionCallbacks()
    Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.RemoveFanCSectionCostume)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, Mizuki.QueueFanCSectionCostumeRefresh,
        CollectibleType.COLLECTIBLE_D4)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, Mizuki.QueueFanCSectionCostumeRefresh,
        CollectibleType.COLLECTIBLE_D100)
    Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, Mizuki.InitFanFetusBloodParticle,
        EffectVariant.BLOOD_PARTICLE)
    Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, Mizuki.BlockProjectilesWithFanFetus,
        TearVariant.FETUS)
end

local function ownerOf(entity, visited)
    if not entity then return nil end
    visited = visited or {}
    local hash = GetPtrHash(entity)
    if visited[hash] then return nil end
    visited[hash] = true
    local player = entity:ToPlayer()
    if player then return player end
    local familiar = entity:ToFamiliar()
    if familiar then return familiar.Player end
    return ownerOf(entity.SpawnerEntity, visited) or ownerOf(entity.Parent, visited)
end

function Mizuki.prepareFetalBrimstone(tear, player)
    Mizuki.rollSpecialBrimstone(tear, player)
    local data = tear:GetData()
    data.MizukiFetalBrimstoneEnabled = player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
    -- This factor belongs to the fireball, not the fetus's damage. Record it
    -- at birth so echoes retain it even after the player's weapon changes.
    data.MizukiFetalBrimstoneDamageMultiplier = Mizuki.getSecondaryBrimstoneDamageMultiplier(player)
end

local function applyBallAppearance(ball, fetus)
    -- Native tears already write their converted Height into PositionOffset.Y
    -- (height setter 0x675FC0 / conversion 0x676020). Do not add Height again.
    ball.PositionOffset = Vector(fetus.PositionOffset.X, fetus.PositionOffset.Y)
    ball.DepthOffset = fetus.DepthOffset - 10
    ball.CollisionDamage = fetus.CollisionDamage * 0.5
        * (fetus:GetData().MizukiFetalBrimstoneDamageMultiplier or 1)
    ball.SpriteScale = Vector.One * (BALL_SCALE * fetus.Scale)
    -- Supply the native effect scale as well as its drawing scale.
    ball.Scale = BALL_SCALE * fetus.Scale
    ball:SetTimeout(30)
    local color = Color(1, 1, 1, fetus.Color.A, 0, 0, 0)
    ball.Color = color
end

local function updateBall(ball)
    local data = ball:GetData()
    if data.MizukiFetalBrimstoneBall ~= true then return end
    local fetus = data.MizukiFetalBrimstoneFetus
    if not fetus or not fetus:Exists() or fetus:IsDead() or fetus.InitSeed ~= data.MizukiFetalBrimstoneSeed
        or fetus:GetData().MizukiFetalBrimstoneEnabled ~= true then ball:Remove(); return end
    -- An attachment shares its anchor's position AND interpolation velocity.
    -- A chase velocity leaves it behind; zero velocity makes the render phases
    -- differ. Keep the player Parent required by the native damaging fireball.
    ball.Position = Vector(fetus.Position.X, fetus.Position.Y)
    ball.Velocity = Vector(fetus.Velocity.X, fetus.Velocity.Y)
    applyBallAppearance(ball, fetus)
end

local function updateFetus(_, tear)
    local data = tear:GetData()
    if data.MizukiFanFetus ~= true then return end
    if data.MizukiFetalBrimstoneEnabled ~= true or tear:IsDead() then return end
    local ball = data.MizukiFetalBrimstoneBallEntity
    if not ball or not ball:Exists() then
        local player = ownerOf(tear)
        if not player then return end
        -- Reverie's wheelchair and Blood Bony use this same native damaging
        -- entity: player parent, CollisionDamage and SetTimeout, no hidden laser.
        ball = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BRIMSTONE_BALL,
            0, tear.Position, tear.Velocity, player):ToEffect()
        ball.Parent = player
        ball:GetSprite().PlaybackSpeed = 0.5
        local ballData = ball:GetData()
        ballData.MizukiFetalBrimstoneBall = true
        ballData.MizukiFetalBrimstoneFetus = tear
        ballData.MizukiFetalBrimstoneSeed = tear.InitSeed
        data.MizukiFetalBrimstoneBallEntity = ball
        -- Initialize size and damage before the first native collision/render.
        applyBallAppearance(ball, tear)
    end
end
function Mizuki.registerFetalBrimstoneCallbacks()
    Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_TEAR_UPDATE, CallbackPriority.LATE, updateFetus)
    Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, ball) updateBall(ball) end, EffectVariant.BRIMSTONE_BALL)
end
