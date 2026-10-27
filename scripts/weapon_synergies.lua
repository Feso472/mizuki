-- Small weapon compatibility rules. Large independent weapons keep their own files.

-- Parallel first-impact effects: Dr. Fetus bombs and Haemolacria bursts.
-- Each effect has its own per-entity opportunity; neither overrides the other.
-- Ownership is resolved from the actual source, never from a volley-wide flag.
-- Do not mark native children as MizukiBeam: that would opt them into cannon
-- positioning. Only inherit ownership and the originating attack's hit record.
function Mizuki.inheritNativeLaserBranch(laser)
    local parent = laser.Parent and laser.Parent:ToLaser()
    if not parent or not parent:Exists() then return end
    local source = parent:GetData()
    if not Mizuki.isParallelAttackLaser(parent) then return end
    local player = source.MizukiBeamOwner
    if not player or not player:Exists() or not Mizuki.isMizuki(player) then return end
    local data = laser:GetData()
    data.MizukiNativeLaserBranch = true
    data.MizukiNativeLaserBranchSource = parent
    data.MizukiBeamOwner = player
    data.MizukiNativeLaserBranchEcho = source.MizukiEchoBeam == true
        or source.MizukiNativeLaserBranchEcho == true
        or source.MizukiAttackSequenceReplay ~= nil
    data.MizukiNativeLaserBranchEchoAlpha = source.MizukiAttackSequenceReplay
        and source.MizukiAttackSequenceReplay.Alpha or source.MizukiNativeLaserBranchEchoAlpha
    Mizuki.attachDeadEyeBranch(parent, laser)
    return parent
end
function Mizuki.getNativeLaserBranchColor(laser)
    return Color.Lerp(laser.Color, laser.Color, 0)
end
local function tintNativeEchoBranch(_, laser)
    local data = laser:GetData()
    if data.MizukiNativeLaserBranch ~= true or data.MizukiNativeLaserBranchEcho ~= true then return end
    -- Native child setup already copies the parent's RGB/colorize. Applying
    -- the blue multiplier again squares it (observed R .45 -> .2025).
    local color = Mizuki.getNativeLaserBranchColor(laser)
    color.A = data.MizukiNativeLaserBranchEchoAlpha or Mizuki.CannonEchoReplayAlpha
    laser.Color = color
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.EARLY, function(_, laser)
    if Mizuki.inheritNativeLaserBranch(laser) then Mizuki:QueueFirstHitFetusGridBomb(laser) end
end)
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE, tintNativeEchoBranch)
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_RENDER, CallbackPriority.LATE, tintNativeEchoBranch)
do
    local function ownerOf(entity)
        if not entity then return nil end
        local player = entity:ToPlayer()
        if player then return player end
        local familiar = entity:ToFamiliar()
        return familiar and familiar.Player or nil
    end

    local pendingGridImpacts = {}
    local spawningHaemolacria
    local HAEMOLACRIA_IMPACT_CLEARANCE = 10 -- Samael scythe impact offset.
    local GRID_HALF_SIZE = 20 -- Same 40px grid geometry as the shared impact resolver.

    -- Native secondary entities can be born during FireTear/Die, or identify
    -- their carrier as spawner later. Never turn those products into new procs.
    local function markHaemolacriaSecondary(_, entity)
        local spawner = entity.SpawnerEntity
        if spawningHaemolacria or (spawner and
            (spawner:GetData().MizukiHaemolacriaCarrier == true
                or spawner:GetData().MizukiHaemolacriaSecondary == true)) then
            entity:GetData().MizukiHaemolacriaSecondary = true
        end
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, markHaemolacriaSecondary)
    Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_INIT, markHaemolacriaSecondary)

    local function firstImpactData(attack)
        local data = attack:GetData()
        if data.MizukiSpiritSwordHitbox == true then
            local sword = data.MizukiSpiritSwordAttack
            local group = sword and sword.CollisionGroups
                and sword.CollisionGroups[data.MizukiSpiritSwordGroupIndex or 0]
            return group and group.FirstImpact or data
        end
        return data
    end

    local function wantsBomb(attack, player)
        -- Keep the previously working bomb/knife route. Registering native
        -- child lasers adds Haemolacria, not another manual Dr. Fetus bomb.
        if attack:GetData().MizukiNativeLaserBranch == true then return false end
        return player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
            and firstImpactData(attack).MizukiFirstHitBombSpawned ~= true
    end

    local function wantsHaemolacria(attack, player)
        -- Real tears/fetuses already own native BURSTSPLIT and landing/death
        -- handling. This adds the missing non-tear attack route only.
        return not attack:ToTear()
            and player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA)
            and firstImpactData(attack).MizukiFirstHitHaemolacriaSpawned ~= true
    end

    local function spawnFirstHitHaemolacria(attack, player, position)
        if not wantsHaemolacria(attack, player) then return end
        local data = attack:GetData()
        local impact = firstImpactData(attack)
        impact.MizukiFirstHitHaemolacriaSpawned = true -- Before reentrant native callbacks.
        local previous = spawningHaemolacria
        spawningHaemolacria = true
        local ok, err = pcall(function()
            local sequenceData = data
            local source = data.MizukiNativeLaserBranch == true and data.MizukiNativeLaserBranchSource
                or (data.MizukiMultidimensionalKnife == true and data.MizukiCannonKnifeMotionSource)
            if source and source:Exists() then sequenceData = source:GetData() end
            local replay = sequenceData.MizukiAttackSequenceReplay
            local sourceSequence = sequenceData.MizukiAttackSequenceSource
            local sword = data.MizukiSpiritSwordHitbox == true and data.MizukiSpiritSwordAttack
            local saved = (sword and sword.Echo and impact.MizukiHaemolacriaCarrier)
                or (replay and replay.Sequence and replay.Sequence.MizukiHaemolacriaCarrier)
            local damageMultiplier = sword and sword.EchoDamageMultiplier or (replay and replay.DamageMultiplier) or 1
            -- FireTear calls the tear's first Update before returning. This
            -- internal death carrier must never run that live-shot stage:
            -- native split/movement flags can already emit products there.
            -- Roll native parameters once, spawn an unupdated tear and die.
            -- Preserve ALL native flags; never modify the player's cache.
            local params = not saved and player:GetTearHitParams(WeaponType.WEAPON_TEARS, 1, 1, player)
            local variant = saved and (saved.Variant or TearVariant.BALLOON) or params.TearVariant
            local tear = Isaac.Spawn(EntityType.ENTITY_TEAR, variant, 0,
                Vector(position.X, position.Y), Vector.Zero, player):ToTear()
            local td = tear:GetData()
            td.MizukiHaemolacriaCarrier, td.MizukiHaemolacriaSecondary = true, true
            tear.Parent = player
            tear.TearFlags = (saved and saved.Flags or params.TearFlags) | TearFlags.TEAR_BURSTSPLIT
            tear.CollisionDamage = saved and saved.Damage or params.TearDamage
            tear.Color = Color.Lerp(saved and saved.Color or params.TearColor,
                saved and saved.Color or params.TearColor, 0)
            tear.Scale = saved and (saved.Scale or 1) or params.TearScale
            if not saved then
                local record = {Flags = tear.TearFlags, Damage = tear.CollisionDamage,
                    Color = Color.Lerp(tear.Color, tear.Color, 0), Variant = tear.Variant, Scale = tear.Scale}
                if sourceSequence then sourceSequence.MizukiHaemolacriaCarrier = record end
                if sword and not sword.Echo then impact.MizukiHaemolacriaCarrier = record end
            end
            tear.CollisionDamage = tear.CollisionDamage * damageMultiplier
            if replay then
                tear.Color = Mizuki.getCannonEchoColor(tear.Color, replay.Alpha)
            elseif sword and sword.Echo then
                tear.Color = Mizuki.getCannonEchoColor(tear.Color, sword.Color.A)
            end
            tear.Height = 0
            tear:Die()
        end)
        spawningHaemolacria = previous
        if not ok then error(err, 0) end
    end

    local function spawnFirstHitBomb(attack, player, position)
        local data = firstImpactData(attack)
        if data.MizukiFirstHitBombSpawned == true then return end
        local tear = attack:ToTear()
        if tear and tear:HasTearFlags(TearFlags.TEAR_FETUS) then
            -- Native enemy contact consumes this flag. A grid bomb must consume
            -- the SAME opportunity, including on a replay fetus.
            if not tear:HasTearFlags(TearFlags.TEAR_FETUS_BOMBER) then return end
            tear:ClearTearFlags(TearFlags.TEAR_FETUS_BOMBER)
        end
        data.MizukiFirstHitBombSpawned = true
        local bomb = player:FireBomb(Vector(position.X, position.Y), Vector.Zero, player)
        if bomb and Mizuki.rollSpecialBrimstone then Mizuki.rollSpecialBrimstone(bomb, player) end
    end

    local function getHaemolacriaGridPosition(attack, player, position)
        local room = Game():GetRoom()
        local grid = room:GetGridEntityFromPos(position)
        local solidGrid = grid and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
        local center = solidGrid and grid.Position or position
        local outward = player.Position - center
        if outward:LengthSquared() == 0 then outward = attack.Position - center end
        if outward:LengthSquared() == 0 then outward = Vector(0, 1) end
        local direction = outward:Resized(1)
        -- Grid candidates are cell centres, not contact points. Exit the square
        -- along the ray first, then add clearance (including diagonal impacts).
        -- Door/wall-slot candidates without a solid cell already lie on a surface.
        local distance = HAEMOLACRIA_IMPACT_CLEARANCE
        if solidGrid then
            distance = distance + GRID_HALF_SIZE / math.max(math.abs(direction.X), math.abs(direction.Y))
        end
        return room:GetClampedPosition(center + direction * distance, 0)
    end

    local function spawnFirstHitEffects(attack, player, position, enemy, gridBurstPosition)
        -- Independent checks and positions: Dr. Fetus stays at the hit point.
        if position and wantsBomb(attack, player) then spawnFirstHitBomb(attack, player, position) end
        local burstPosition = gridBurstPosition or position
        if not burstPosition then return end
        if enemy and wantsHaemolacria(attack, player) then
            -- Samael places the carrier outside the enemy, toward the player.
            -- Spawning at the centre lets every split tear overlap immediately.
            local outward = player.Position - enemy.Position
            if outward:LengthSquared() == 0 then outward = attack.Position - enemy.Position end
            if outward:LengthSquared() == 0 then outward = Vector(0, 1) end
            burstPosition = enemy.Position + outward:Resized(enemy.Size + HAEMOLACRIA_IMPACT_CLEARANCE)
        end
        spawnFirstHitHaemolacria(attack, player, burstPosition)
    end

    local function segmentDistanceSquared(point, first, last)
        local dx, dy = last.X - first.X, last.Y - first.Y
        local lengthSquared = dx * dx + dy * dy
        local t = lengthSquared > 0 and ((point.X - first.X) * dx
            + (point.Y - first.Y) * dy) / lengthSquared or 0
        t = math.max(0, math.min(1, t))
        local x, y = point.X - first.X - dx * t, point.Y - first.Y - dy * t
        return x * x + y * y
    end

    local function overlapsEnemy(laser, enemy)
        local reach = laser.Size + enemy.Size
        if laser:IsCircleLaser() then
            local dx, dy = enemy.Position.X - laser.Position.X, enemy.Position.Y - laser.Position.Y
            return math.abs(math.sqrt(dx * dx + dy * dy) - laser.Radius) <= reach
        end
        -- Native world-space samples retain homing curves and clipped endpoints.
        local samples = laser:GetSamples()
        if #samples < 2 then
            return segmentDistanceSquared(enemy.Position, laser.Position, laser:GetEndPoint()) <= reach * reach
        end
        for index = 1, #samples - 1 do
            if segmentDistanceSquared(enemy.Position, samples:Get(index - 1),
                samples:Get(index)) <= reach * reach then return true end
        end
        return false
    end

    local function resolveAttack(source, damageFlags, swordGridImpact, includeFetus)
        local attack = source and source.Entity
        if not attack then return end
        local data = attack:GetData()
        if data.MizukiHaemolacriaCarrier == true or data.MizukiHaemolacriaSecondary == true then return end
        local player = attack:ToPlayer()
        if player then
            -- Native Ludovico ring damage names the player as its source.
            if (damageFlags & DamageFlag.DAMAGE_LASER) == 0
                or (damageFlags & DamageFlag.DAMAGE_EXPLOSION) ~= 0 then return end
            attack = player:GetData().MizukiLudovicoRing
            if not attack or not attack:Exists()
                or attack:GetData().MizukiIsLudovicoRing ~= true then return end
        elseif attack:ToLaser() then
            attack = attack:ToLaser()
            player = data.MizukiBeamOwner or data.MizukiLudovicoOwner
        elseif attack:ToKnife() then
            attack = attack:ToKnife()
            if data.MizukiCannonKnife ~= true and data.MizukiEchoKnife ~= true
                and data.MizukiBerserkSwingHitbox ~= true
                and data.MizukiSpiritSwordHitbox ~= true then return end
            if data.MizukiSpiritSwordHitbox == true then
                local sword = data.MizukiSpiritSwordAttack
                if not sword or sword.Finished
                    or not sword.CollisionGroups
                    or not sword.CollisionGroups[data.MizukiSpiritSwordGroupIndex or 0] then return end
                if swordGridImpact and sword.ChargeContact then return end
                -- Only the sword's validated, final damage dispatch may spend
                -- a proc; the preliminary native callback can still be cancelled.
                if not swordGridImpact and data.MizukiSpiritSwordDamageDispatch ~= true then return end
            end
            if data.MizukiBerserkSwingHitbox == true then
                local swing = data.MizukiBerserkSwingState
                if not swing or not swing.Hitbox or not swing.Hitbox:Exists()
                    or swing.Hitbox.InitSeed ~= attack.InitSeed
                    or GetPtrHash(swing.Hitbox) ~= GetPtrHash(attack) then return end
                if not swordGridImpact and data.MizukiBerserkDamageDispatch ~= true then return end
            end
            if data.MizukiBerserkCollisionProxy == true and not swordGridImpact
                and data.MizukiBerserkDamageDispatch ~= true then return end
            player = data.MizukiCannonKnifeOwner
                or ownerOf(attack.Parent) or ownerOf(attack.SpawnerEntity)
        elseif attack:ToTear() then
            attack = attack:ToTear()
            -- Native fetuses already drop their own Dr. Fetus bomb.
            if not includeFetus and attack:HasTearFlags(TearFlags.TEAR_FETUS) then return end
            player = ownerOf(attack.Parent) or ownerOf(attack.SpawnerEntity)
        elseif attack:ToFamiliar() then
            attack = attack:ToFamiliar()
            if attack.Variant ~= Mizuki.CannonVariant
                and attack.Variant ~= Mizuki.CannonEchoVariant then return end
            player = attack.Player
        elseif attack:ToEffect() and data.MizukiPepperFlame == true then
            player = ownerOf(attack.SpawnerEntity)
        else
            -- Bombs, explosions and their secondary effects cannot spawn more bombs.
            return
        end
        if player and player:Exists() and Mizuki.isMizuki(player) then
            return attack, player
        end
    end

    -- These are actual attack lasers, not positioning/visual carriers.
    function Mizuki.isParallelAttackLaser(laser)
        local d = laser:GetData()
        return d.MizukiHaemolacriaSecondary ~= true
            and (d.MizukiBeam == true or d.MizukiCannonTechXRing == true
                or d.MizukiIsLudovicoRing == true or d.MizukiTech5 == true
                or d.MizukiNativeLaserBranch == true or d.MizukiTrisagionPulse ~= nil
                or d.MizukiTrisagionNativeLaser == true or d.MizukiSpiritSwordTechRing == true)
    end

    function Mizuki.resolveEpicFetusAttack(source, flags, gridImpact, enemy)
        local entity = source and source.Entity
        if not entity or (flags & DamageFlag.DAMAGE_EXPLOSION) ~= 0 then return end
        local attributed = ownerOf(entity)
        if attributed and attributed:Exists() and Mizuki.isMizuki(attributed)
            and (entity:ToPlayer() or entity:ToFamiliar())
            and (flags & DamageFlag.DAMAGE_LASER) ~= 0 and enemy then
            -- Native laser damage may name its player/familiar instead of the
            -- laser. Require actual path contact, never merely an active weapon.
            for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
                local laser = e:ToLaser()
                local d = laser:GetData()
                local owner = d.MizukiBeamOwner or d.MizukiLudovicoOwner
                if owner and owner:Exists() and GetPtrHash(owner) == GetPtrHash(attributed)
                    and laser.CollisionDamage > 0 and Mizuki.isParallelAttackLaser(laser)
                    and overlapsEnemy(laser, enemy) then return laser, owner end
            end
            return
        end
        local attack, player = resolveAttack(source, flags, gridImpact, true)
        if not attack then return end
        local tear = attack:ToTear()
        local d = attack:GetData()
        if tear then
            if (tear.WaitFrames or 0) > 0 then return end
            if not tear:HasTearFlags(TearFlags.TEAR_FETUS)
                and not Mizuki.getSpiritSwordWaveOwner(tear)
                and not d.MizukiCannonTrisagionShot and d.MizukiBerserkLungTear ~= true then return end
        elseif attack:ToLaser() then
            if attack.CollisionDamage <= 0 or not Mizuki.isParallelAttackLaser(attack) then return end
        elseif attack:ToFamiliar() then
            if d.MizukiAwaitingInitialLayout or d.MizukiIsIdle
                or Mizuki.usesCSectionWeapon(player)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then return end
            if d.MizukiEchoCannon == true then
                local shot = d.MizukiEchoShot
                if d.MizukiEchoAwaitingShot or not shot or not shot.ReplayFrame
                    or shot.Removed or shot.FadeFrame or d.MizukiEchoKnifeMode then return end
            end
        elseif not attack:ToKnife() then return end
        return attack, player
    end

    function Mizuki:TriggerFirstHitFetusBomb(entity, amount, damageFlags, source)
        local enemy = entity:ToNPC()
        if amount <= 0 or not enemy or not enemy:IsActiveEnemy(false)
            or enemy:IsDead() or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
        local attributedOwner = ownerOf(source and source.Entity)
        if attributedOwner and attributedOwner:Exists() and Mizuki.isMizuki(attributedOwner)
            and (attributedOwner:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
                or attributedOwner:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA))
            and (damageFlags & DamageFlag.DAMAGE_LASER) ~= 0
            and (damageFlags & DamageFlag.DAMAGE_EXPLOSION) == 0 then
            -- FireTechLaser can name its player/familiar as the damage source.
            -- Do not reduce overlapping multishot to one player-owned proc:
            -- infer contact separately from each owned laser's native path.
            for _, entityLaser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
                local laser = entityLaser:ToLaser()
                local data = laser:GetData()
                local owner = data.MizukiBeamOwner or data.MizukiLudovicoOwner
                if laser:Exists() and owner and GetPtrHash(owner) == GetPtrHash(attributedOwner)
                    and Mizuki.isParallelAttackLaser(laser)
                    and data.MizukiHaemolacriaSecondary ~= true
                    and laser.CollisionDamage > 0 and overlapsEnemy(laser, enemy) then
                    spawnFirstHitEffects(laser, attributedOwner, enemy.Position, enemy)
                end
            end
            return
        end
        local attack, player = resolveAttack(source, damageFlags)
        if not attack then return end
        spawnFirstHitEffects(attack, player, enemy.Position, enemy)
    end

    Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, Mizuki.TriggerFirstHitFetusBomb)

    function Mizuki.triggerSpiritSwordGridImpact(source, position)
        if source:GetData().MizukiSpiritSwordHitbox ~= true then return end
        local attack, player = resolveAttack({Entity = source}, 0, true)
        if attack and player then Mizuki.queueEpicFetusGridTarget(attack, position) end
        if not attack or not player or (not wantsBomb(attack, player)
            and not wantsHaemolacria(attack, player)) then return end
        -- Sword interactions already finish every enemy query before grids,
        -- inside MC_POST_UPDATE. Deferring to the earlier shared post-update
        -- callback would discard this candidate as belonging to the last frame.
        local burstPosition = wantsHaemolacria(attack, player)
            and getHaemolacriaGridPosition(attack, player, position) or nil
        spawnFirstHitEffects(attack, player, position, nil, burstPosition)
    end

    local function getFirstImpactGridTarget(attack, includeWalls)
        local laser = attack:ToLaser()
        if laser then
            if laser:IsCircleLaser() then return Mizuki.getFetusRingGridTarget(laser, includeWalls) end
            return Mizuki.getFetusBeamGridTarget(laser, includeWalls)
        end
        return Mizuki.getFetusContactGridTarget(attack.Position, attack.Size, includeWalls)
    end

    function Mizuki:QueueFirstHitFetusGridBomb(attack)
        if Game():IsPaused() or not attack:Exists() then return end
        local data = attack:GetData()
        if data.MizukiHaemolacriaCarrier == true or data.MizukiHaemolacriaSecondary == true then return end
        local tear = attack:ToTear()
        local player
        if tear and tear:HasTearFlags(TearFlags.TEAR_FETUS) then
            if data.MizukiFanFetus ~= true
                or (tear.WaitFrames or 0) > 0
                or not tear:HasTearFlags(TearFlags.TEAR_FETUS_BOMBER) then return end
            player = ownerOf(tear.Parent) or ownerOf(tear.SpawnerEntity)
        else
            attack, player = resolveAttack({Entity = attack}, 0, data.MizukiBerserkSwingHitbox == true)
        end
        if not attack or not player or not player:Exists() or not Mizuki.isMizuki(player)
            or (not wantsBomb(attack, player) and not wantsHaemolacria(attack, player)) then return end

        local laser, knife, familiar = attack:ToLaser(), attack:ToKnife(), attack:ToFamiliar()
        if laser then
            if laser.CollisionDamage <= 0 or not Mizuki.isParallelAttackLaser(laser) then return end
        elseif knife then
            if not knife:IsFlying() and data.MizukiBerserkSwingHitbox ~= true then return end
        elseif familiar then
            if data.MizukiAwaitingInitialLayout or data.MizukiIsIdle
                or Mizuki.usesCSectionWeapon(player)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then return end
            if data.MizukiEchoCannon == true then
                local shot = data.MizukiEchoShot
                if data.MizukiEchoAwaitingShot or not shot or not shot.ReplayFrame
                    or shot.Removed or shot.FadeFrame or data.MizukiEchoKnifeMode then return end
            end
        end
        local position = getFirstImpactGridTarget(attack)
        local haemolacriaPosition = wantsHaemolacria(attack, player)
            and (position or getFirstImpactGridTarget(attack, true)) or nil
        if not position and not haemolacriaPosition then return end
        local hash = GetPtrHash(attack)
        -- Defer grid candidates until enemy damage has run. Enemy/grid callbacks
        -- share each effect's spent marker without spending the other effect.
        pendingGridImpacts[hash] = {
            Entity = attack, Seed = attack.InitSeed, Hash = hash,
            Player = player, PlayerSeed = player.InitSeed, PlayerHash = GetPtrHash(player),
            Position = position and Vector(position.X, position.Y) or nil,
            Frame = Game():GetFrameCount(),
            HaemolacriaPosition = haemolacriaPosition
                and getHaemolacriaGridPosition(attack, player, haemolacriaPosition) or nil,
        }
    end

    function Mizuki:FinalizeFirstHitFetusGridBombs()
        local candidates = pendingGridImpacts
        pendingGridImpacts = {}
        local frame = Game():GetFrameCount()
        for _, candidate in pairs(candidates) do
            local attack, player = candidate.Entity, candidate.Player
            if candidate.Frame == frame and attack:Exists() and attack.InitSeed == candidate.Seed
                and GetPtrHash(attack) == candidate.Hash and player:Exists()
                and player.InitSeed == candidate.PlayerSeed and GetPtrHash(player) == candidate.PlayerHash
                and Mizuki.isMizuki(player) then
                spawnFirstHitEffects(attack, player, candidate.Position, nil, candidate.HaemolacriaPosition)
            end
        end
    end

    for _, callback in ipairs({ModCallbacks.MC_POST_LASER_UPDATE, ModCallbacks.MC_POST_KNIFE_UPDATE,
        ModCallbacks.MC_POST_TEAR_UPDATE, ModCallbacks.MC_POST_EFFECT_UPDATE, ModCallbacks.MC_FAMILIAR_UPDATE}) do
        Mizuki:AddCallback(callback, Mizuki.QueueFirstHitFetusGridBomb)
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, Mizuki.FinalizeFirstHitFetusGridBombs)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() pendingGridImpacts = {} end)
end

-- region Kidney Stone
do
    -- The native stone starts the burst; unrelated stat spikes cannot start it.
    -- Native remaining time declines every logic frame and refreshes fire delay.
    -- Tears declining means MaxFireDelay increasing. Two unchanged observations
    -- finish the burst without guessing a duration or a minimum spike ratio.
    local KIDNEY_STONE_STABLE_FRAMES = 2

    local function updateKidneyStoneBurst(player, data)
        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KIDNEY_STONE) then
            data.MizukiKidneyStoneBurst = nil
            return nil
        end
        local burst = data.MizukiKidneyStoneBurst
        if not burst then return nil end
        local frame = Game():GetFrameCount()
        if Game():IsPaused() or burst.LastUpdateFrame == frame then return burst end
        burst.LastUpdateFrame = frame

        local currentMaxFireDelay = player.MaxFireDelay
        -- Compare the native float directly: an absolute epsilon prematurely
        -- ends high-rate bursts whose per-frame delay change is very small.
        if currentMaxFireDelay == burst.LastMaxFireDelay then
            burst.StableFrames = burst.StableFrames + 1
        else
            burst.StableFrames = 0
        end
        burst.LastMaxFireDelay = currentMaxFireDelay
        if burst.StableFrames >= KIDNEY_STONE_STABLE_FRAMES then
            data.MizukiKidneyStoneBurst = nil
            return nil
        end

        local aim = player:GetAimDirection()
        if aim:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            burst.Direction = aim:Normalized()
            data.MizukiLastShootDirection = burst.Direction
        end
        return burst
    end
    Mizuki.updateKidneyStoneBurst = updateKidneyStoneBurst

    Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
        if tear.Variant ~= TearVariant.STONE then return end
        local tearData = tear:GetData()
        if tearData.MizukiKidneyStoneObserved then return end
        tearData.MizukiKidneyStoneObserved = true
        if tearData.MizukiAttackSequenceReplay then return end
        -- A native kidney stone is spawned by the player, not a familiar or a
        -- split/replayed tear. Terra uses ROCK, a different tear variant.
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if not player or not Mizuki.isMizuki(player)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_KIDNEY_STONE) then return end
        local data = player:GetData()
        if data.MizukiKidneyStoneBurst then return end
        local aim = player:GetAimDirection()
        data.MizukiKidneyStoneBurst = {
            StableFrames = 0,
            LastMaxFireDelay = player.MaxFireDelay,
            LastUpdateFrame = Game():GetFrameCount(),
            Direction = aim:Length() > Mizuki.RuntimeParameters.AimDeadZone
                and aim:Normalized() or data.MizukiLastShootDirection,
        }
    end)
end
-- endregion Kidney Stone

-- region Isaacs Tears
do
    -- Isaac's Tears charging from the beam's own damage ticks.
    --
    -- Reuse the beam lifecycle's tick interval and active-attack query.

    local BEAM_DAMAGE_INTERVAL = Mizuki.BEAM_DAMAGE_INTERVAL
    local isMizuki = Mizuki.isMizuki
    local hasActiveMizukiBeam = Mizuki.hasActiveMizukiBeam

    -- Isaac's Tears charges once per two damage ticks of the beam, not once per
    -- fire-rate interval: vanilla's Brimstone ticks 9 times over a shot and hands
    -- out about 4 charges, which is what a two-ticks-per-charge rule produces. (The
    -- "charges at the same rate as the fire rate" wording on the item's page
    -- describes an older behaviour.) Multiple cannons/multishot beams are still one
    -- attack, so a logical damage moment counts once rather than once per entity.
    local CHARGE_ROLLS_PER_TICK = 2
    local BATTERY_CAPACITY_MULTIPLIER = 2

    local function countBeamDamageRolls(data)
        for side = 1, 2 do
            local beams = data.MizukiActiveBeams and data.MizukiActiveBeams[side]
            if beams then
                for _, beam in ipairs(beams) do
                    local laser = beam.Laser
                    if laser and laser:Exists()
                        and laser.FrameCount % BEAM_DAMAGE_INTERVAL == 0
                    then
                        return 1
                    end
                end
            end
        end
        local ring = data.MizukiLudovicoRing
        if ring and ring:Exists() and ring.FrameCount % BEAM_DAMAGE_INTERVAL == 0 then return 1 end
        return 0
    end

    -- Isaac's Tears charges by being shot: one charge per tear fired. Mizuki never
    -- fires a tear - the cannons are lasers created through FireTechLaser - so the
    -- weapon system the engine watches never runs and the item sits at zero
    -- forever.
    --
    -- The rule reproduced here is the one the item follows with a tear-replacing
    -- weapon (Brimstone, Mom's Knife, Technology): nothing accrues while the shot
    -- is still charging, then it charges for as long as the beam is actually being
    -- fired - one charge per damage tick pair, not per fire-rate interval.
    local function addIsaacsTearsCharge(player, charges, slot)
        slot = slot or ActiveSlot.SLOT_PRIMARY
        if player:GetActiveItem(slot) ~= CollectibleType.COLLECTIBLE_ISAACS_TEARS then return end
        if charges < 1 then return end

        -- Modelled on the two community fixes for this exact problem: Samael's
        -- IsaacsTearsFix (another custom character whose weapon replaces tears) and
        -- CuerLib's Actives:ChargeSlot. Both read the *total* charge - the slot's
        -- active charge plus its battery charge - and write the sum back, capped at
        -- MaxCharges (doubled by The Battery). GetActiveCharge() alone does not
        -- include the battery bar, so reading only that would discard whatever the
        -- player has banked there.
        local itemConfig = Isaac.GetItemConfig():GetCollectible(
            CollectibleType.COLLECTIBLE_ISAACS_TEARS
        )
        local maxCharges = itemConfig and itemConfig.MaxCharges or 1
        if maxCharges < 1 then
            maxCharges = 1
        end
        if player:HasCollectible(CollectibleType.COLLECTIBLE_BATTERY) then
            maxCharges = maxCharges * BATTERY_CAPACITY_MULTIPLIER
        end

        local total = player:GetActiveCharge(slot) + player:GetBatteryCharge(slot)
        if total >= maxCharges then
            return
        end

        local nextCharge = math.min(maxCharges, total + charges)
        player:SetActiveCharge(nextCharge, slot)
        -- Feedback for a charge tick: the bar flashes and the tick beeps
        -- (sfx/feedback/beep.wav), with the item-recharge jingle on the tick that
        -- finishes the charge. SOUND_BATTERYCHARGE is the sound of picking a battery
        -- up, not of a charge tick.
        local sfx = SFXManager()
        sfx:Play(SoundEffect.SOUND_BEEP)
        Game():GetHUD():FlashChargeBar(player, slot)
        if nextCharge >= maxCharges then
            sfx:Play(SoundEffect.SOUND_ITEMRECHARGE)
        end
    end

    function Mizuki.chargeIsaacsTearsFromAttack(player, charges)
        for slot = ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET2 do
            addIsaacsTearsCharge(player, charges, slot)
        end
    end

    local function updateIsaacsTearsCharge(player, data, shotFired)
        local equipped = false
        for slot = ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET2 do
            if player:GetActiveItem(slot) == CollectibleType.COLLECTIBLE_ISAACS_TEARS then equipped = true; break end
        end
        if not equipped then data.MizukiTearsChargeRolls = nil; return end
        local charges
        if shotFired then
            charges = 1
        elseif Mizuki.usesCannonTechX(player) then
            -- Flying/maintained rings grant nothing: only the explicit shot does.
            data.MizukiTearsChargeRolls = nil
            return
        else
            local ring = data.MizukiLudovicoRing
            if not hasActiveMizukiBeam(data) and not (ring and ring:Exists()) then
                data.MizukiTearsChargeRolls = nil
                return
            end
            local banked = (data.MizukiTearsChargeRolls or 0) + countBeamDamageRolls(data)
            charges = math.floor(banked / CHARGE_ROLLS_PER_TICK)
            data.MizukiTearsChargeRolls = banked % CHARGE_ROLLS_PER_TICK
        end
        Mizuki.chargeIsaacsTearsFromAttack(player, charges)
    end

    function Mizuki.chargeIsaacsTearsFromSword(player, spin)
        -- Native sword: a slash adds one, a spin adds one complete base bar.
        local config = spin and Isaac.GetItemConfig():GetCollectible(CollectibleType.COLLECTIBLE_ISAACS_TEARS)
        Mizuki.chargeIsaacsTearsFromAttack(player, spin and math.max(1, config and config.MaxCharges or 6) or 1)
    end

    Mizuki.updateIsaacsTearsCharge = updateIsaacsTearsCharge
end
-- endregion Isaacs Tears

-- region Neptunus
do
    -- Neptunus stores idle firing time separately from the current cannon charge.
    -- The bank changes when an attack actually fires, not when a key is pressed.
    local STORED_FRAME_CAP = 90
    local CHARGE_BAR_PROGRESS_FRAMES = 100
    local BAR_HORIZONTAL_OFFSET = 20
    local BAR_HEIGHT_SCALE = 48
    local BAR_HEIGHT_BASE = 10

    function Mizuki.isNeptunusEnabled(player, automatic)
        return not automatic
            and player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS)
            and not player:HasCollectible(
                CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
            )
    end

    function Mizuki.resetNeptunusState(data)
        data.MizukiNeptunusStoredFrames = nil
        data.MizukiNeptunusHeldFrames = nil
    end

    function Mizuki.updateNeptunusStorage(player, data, shooting, automatic)
        if not Mizuki.isNeptunusEnabled(player, automatic) then
            Mizuki.resetNeptunusState(data)
            return false
        end

        -- A released Cursed Eye volley may still be firing. Like an ordinary
        -- airborne tear, it does not count as held shooting input here.
        if not shooting and (data.MizukiCharge or 0) <= 0 then
            data.MizukiNeptunusStoredFrames = math.min(
                STORED_FRAME_CAP,
                (data.MizukiNeptunusStoredFrames or 0) + 1
            )
        end
        return true
    end

    function Mizuki.advanceNeptunusCharge(data, profile)
        local held = math.min(
            (data.MizukiNeptunusHeldFrames or 0) + 1,
            profile.MaxFrames
        )
        data.MizukiNeptunusHeldFrames = held
        return math.min(
            profile.MaxFrames,
            held + (data.MizukiNeptunusStoredFrames or 0)
        )
    end

    function Mizuki.spendNeptunusCharge(data, charge)
        local stored = data.MizukiNeptunusStoredFrames or 0
        local held = data.MizukiNeptunusHeldFrames or 0
        data.MizukiNeptunusStoredFrames = math.max(
            0,
            stored - math.min(stored, math.max(0, charge - held))
        )
        data.MizukiNeptunusHeldFrames = nil
    end

    function Mizuki.canFireNeptunusDirect(data, cooldown)
        if cooldown <= Mizuki.RuntimeParameters.FrameComparisonEpsilon then
            return true
        end

        local stored = data.MizukiNeptunusStoredFrames or 0
        if stored + Mizuki.RuntimeParameters.FrameComparisonEpsilon < cooldown then
            return false
        end
        data.MizukiNeptunusStoredFrames = math.max(0, stored - cooldown)
        return true
    end

    function Mizuki.getNeptunusFreeSide(data)
        local nextShotSide = -(data.MizukiShotSide or -1)
        local preferred = nextShotSide == -1 and 1 or 2
        local other = preferred == 1 and 2 or 1
        local beams = data.MizukiActiveBeams or {}
        local positions = data.MizukiCannonPositions or {}
        local cannons = data.MizukiCannons or {}
        local function isFree(side)
            if side == 2 and data.MizukiCannons and data.MizukiCannons[2]
                and Mizuki.isTech2Cannon(data.MizukiCannons[2][1]) then return false end
            return positions[side] and #positions[side] > 0
                and cannons[side] and #cannons[side] > 0
                and (not beams[side] or #beams[side] == 0)
        end
        if isFree(preferred) then
            return preferred
        end
        if isFree(other) then
            return other
        end
        return nil
    end

    function Mizuki.recordNeptunusFiringSide(data, side)
        data.MizukiShotSide = side == 1 and -1 or 1
    end

    function Mizuki:RenderNeptunusBar()
        local game = Game()
        if game:IsPaused() or Options.ChargeBars == false then
            return
        end
        local room = game:GetRoom()
        local renderMode = room:GetRenderMode()
        if renderMode == RenderMode.RENDER_WATER_REFLECT
            or renderMode == RenderMode.RENDER_WATER_REFRACT
        then
            return
        end

        for index = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if Mizuki.isMizuki(player)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS)
                and Mizuki.isNeptunusEnabled(
                    player,
                    Mizuki.usesAutomaticBeam(player)
                )
            then
                local data = player:GetData()
                local stored = data.MizukiNeptunusStoredFrames or 0
                local bar = data.MizukiNeptunusBarSprite
                if stored > 0 or bar then
                    if not bar then
                        bar = Sprite()
                        bar:Load("gfx/chargebar.anm2", true)
                        data.MizukiNeptunusBarSprite = bar
                    end

                    local frameCount = game:GetFrameCount()
                    if data.MizukiNeptunusBarFrame ~= frameCount then
                        data.MizukiNeptunusBarFrame = frameCount
                        if bar:IsPlaying("StartCharged")
                            or bar:IsPlaying("Charged")
                            or bar:IsPlaying("Disappear")
                        then
                            bar:Update()
                        end

                        if stored >= STORED_FRAME_CAP then
                            if bar:IsFinished("StartCharged") then
                                bar:Play("Charged", true)
                            elseif not bar:IsPlaying("StartCharged")
                                and not bar:IsPlaying("Charged")
                            then
                                bar:Play("StartCharged", true)
                            end
                        elseif stored > 0 then
                            bar:SetFrame(
                                "Charging",
                                math.floor(stored / STORED_FRAME_CAP * CHARGE_BAR_PROGRESS_FRAMES)
                            )
                        elseif not bar:IsPlaying("Disappear")
                            and not bar:IsFinished("Disappear")
                        then
                            bar:Play("Disappear", true)
                        end
                    end

                    if stored > 0 or not bar:IsFinished("Disappear") then
                        local height = player.SpriteScale.Y * BAR_HEIGHT_SCALE
                            + BAR_HEIGHT_BASE
                        local worldPosition = player.Position
                            + Vector(BAR_HORIZONTAL_OFFSET, -height)
                        local renderPosition = Isaac.WorldToScreen(worldPosition)
                        bar:Render(renderPosition, Vector.Zero, Vector.Zero)
                    end
                end
            end
        end
    end

    -- Render after player and familiar callbacks, so this player-owned meter sits
    -- in front of both cannon bodies and their separate per-shot charge circles.
    Mizuki:AddCallback(ModCallbacks.MC_POST_RENDER, Mizuki.RenderNeptunusBar)
end
-- endregion Neptunus

-- Shared Brimstone curse. Register at the original controller load point.
function Mizuki.registerSpecialBrimstoneCompatibility()
    -- Native Repentance only. The attack marker is separate from the enemy status.
    local MARK = EntityFlag.FLAG_BRIMSTONE_MARKED
    local MARK_FRAMES = 150

    function Mizuki.getSpecialBrimstoneChance(luck)
        -- Holy Light: 10% at zero luck, discrete luck growth, capped at 50%.
        return 1 / math.max(2, 10 - math.floor(luck * 0.9))
    end

    function Mizuki.rollSpecialBrimstone(entity, player)
        local data = entity:GetData()
        data.MizukiSpecialBrimstoneAttack = true
        data.MizukiSpecialBrimstoneOwner = player
        data.MizukiSpecialBrimstoneCurse = player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
            and player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_BRIMSTONE):RandomFloat()
                < Mizuki.getSpecialBrimstoneChance(player.Luck)
    end

    function Mizuki.updateCannonBrimstoneCurse(cannon)
        local player, data = cannon.Player, cannon:GetData()
        if data.MizukiPersistentEchoMode then
            -- Persistent contact echoes copy the original cannon's proc. Automatic
            -- mode receives its delayed state in the pose history immediately after this.
            if data.MizukiPersistentEchoMode == "ludovico" then
                local cannons = player:GetData().MizukiCannons
                local side = cannons and cannons[data.CannonSide]
                if side then
                    for index, candidate in ipairs(side) do
                        if GetPtrHash(candidate) == GetPtrHash(cannon) then
                            local original = side[index - #side / 2]
                            data.MizukiSpecialBrimstoneCurse = original and original:GetData().MizukiSpecialBrimstoneCurse or false
                            break
                        end
                    end
                end
            end
            return
        end
        if data.MizukiIsIdle or Mizuki.usesCSectionWeapon(player)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
            data.MizukiSpecialBrimstoneCurse = false
            data.MizukiSpecialBrimstoneContactNext = nil
            return
        end
        local frame = Game():GetFrameCount()
        if not data.MizukiSpecialBrimstoneContactNext or frame >= data.MizukiSpecialBrimstoneContactNext then
            Mizuki.rollSpecialBrimstone(cannon, player)
            data.MizukiSpecialBrimstoneContactNext = frame + Mizuki.getFireInterval(player)
        end
    end

    local function markEnemy(enemy)
        if enemy:HasEntityFlags(EntityFlag.FLAG_NO_STATUS_EFFECTS) then return end
        local data = enemy:GetData()
        if data.MizukiBrimstoneMarkExpires == nil then
            -- Leave a status already owned by the native game or another mod alone.
            if enemy:HasEntityFlags(MARK) then return end
        end
        -- Ownership and expiry travel with this enemy, rather than a local
        -- lookup that disappears on Lua reload or room-controller reset.
        data.MizukiBrimstoneMarkExpires = Game():GetFrameCount() + MARK_FRAMES
        enemy:AddEntityFlags(MARK)
    end

    Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, _, source)
        local enemy, attack = entity:ToNPC(), source and source.Entity
        if not enemy or not attack or amount <= 0 or not enemy:IsActiveEnemy(false)
            or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
        local data = attack:GetData()
        if data.MizukiSpecialBrimstoneCurse == true then markEnemy(enemy) end
    end)

    -- Native Lua exposes the status flag but not AddBrimstoneMark's timer. Maintain
    -- only our own five-second status; the native engine handles its damage synergy.
    Mizuki:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, enemy)
        local data = enemy:GetData()
        local expires = data.MizukiBrimstoneMarkExpires
        if expires == nil then return end
        if enemy:IsDead() then data.MizukiBrimstoneMarkExpires = nil; return end
        if Game():GetFrameCount() >= expires then
            enemy:ClearEntityFlags(MARK)
            data.MizukiBrimstoneMarkExpires = nil
        else enemy:AddEntityFlags(MARK) end
    end)

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

    Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_UPDATE, function(_, bomb)
        if bomb:GetData().MizukiSpecialBrimstoneAttack or not bomb.IsFetus then return end
        local player = ownerOf(bomb)
        if player and Mizuki.isMizuki(player) then Mizuki.rollSpecialBrimstone(bomb, player) end
    end)

    -- Knife callback filters are SUBTYPES, not variants. Native axe swings are
    -- 8.9.4; the held 8.9.0 also animates but must not roll a second proc.
    local function prepareNotchedAxe(knife)
        if knife.Variant ~= 9 then return false end
        local data = knife:GetData()
        if not data.MizukiSpecialBrimstoneAttack then
            local player = ownerOf(knife)
            if player and Mizuki.isMizuki(player) then
                Mizuki.rollSpecialBrimstone(knife, player)
            end
        end
        return data.MizukiSpecialBrimstoneCurse == true
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, knife)
        prepareNotchedAxe(knife)
    end, 4)
    -- The axe's wide melee hit reports player-sourced DAMAGE_CRUSH. Knife
    -- collision only covers its small entity collider, not the full swing.
    Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
        local enemy = entity:ToNPC()
        local player = source and source.Entity and source.Entity:ToPlayer()
        if not enemy or amount <= 0 or not player or not Mizuki.isMizuki(player)
            or flags & DamageFlag.DAMAGE_CRUSH == 0 or not enemy:IsActiveEnemy(false)
            or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
        local swing
        for _, axe in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE, 9, 4, false, false)) do
            local owner = ownerOf(axe)
            if axe:Exists() and not axe:IsDead() and owner and GetPtrHash(owner) == GetPtrHash(player)
                and (not swing or axe.FrameCount < swing.FrameCount) then
                swing = axe
            end
        end
        -- Select the current swing before reading its proc; an older marked
        -- swing must never turn a newer unmarked swing into a marked attack.
        if swing and prepareNotchedAxe(swing) then markEnemy(enemy) end
    end)

    function Mizuki.renderSpecialBrimstoneIcon(entity, worldPosition, renderOffset, alpha, bodyScreenPosition)
        local data = entity:GetData()
        if data.MizukiSpecialBrimstoneCurse ~= true then return end
        local room = Game():GetRoom()
        if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then return end
        local sprite = data.MizukiSpecialBrimstoneIcon
        if not sprite then
            sprite = Sprite()
            sprite:Load("gfx/statuseffects.anm2", true)
            data.MizukiSpecialBrimstoneIcon = sprite
        end
        sprite:SetFrame("BrimstoneCurse", Game():GetFrameCount() % 30)
        sprite.Color = Color(1, 1, 1, alpha or entity.Color.A, 0, 0, 0)
        -- Manual weapon draws already resolved their callback's screen space.
        -- In particular MC_POST_RENDER must not subtract room scrolling again.
        local position = bodyScreenPosition or (Isaac.WorldToScreen(worldPosition)
            + (renderOffset or Vector.Zero) - room:GetRenderScrollOffset() - Game().ScreenShakeOffset)
        sprite:Render(position + Vector(0, -16), Vector.Zero, Vector.Zero)
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_RENDER, function(_, tear, offset)
        if tear:GetData().MizukiFanFetus == true then
            Mizuki.renderSpecialBrimstoneIcon(tear, tear.Position + tear.PositionOffset, offset)
        end
    end)
    Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_RENDER, function(_, bomb, offset)
        Mizuki.renderSpecialBrimstoneIcon(bomb, bomb.Position + bomb.PositionOffset, offset)
    end)
    Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_RENDER, function(_, knife, offset)
        if knife.Variant == 9 and knife:GetData().MizukiSpecialBrimstoneAttack then
            Mizuki.renderSpecialBrimstoneIcon(knife, knife.Position + knife.PositionOffset, offset)
        end
    end, 4)
    Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, function(_, rocket, offset)
        if rocket:GetData().MizukiSpecialBrimstoneAttack then
            Mizuki.renderSpecialBrimstoneIcon(rocket, rocket.Position + rocket.PositionOffset, offset)
        end
    end, EffectVariant.ROCKET)

end

-- region Input Attack Effects
do
    -- Real attack notifications are grouped by side, not by projectile count.
    local PERIOD = Mizuki.BEAM_DAMAGE_INTERVAL * 2
    local getState
    local function hasEffect(player)
        return player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_EVIL_EYE)
    end
    local function attackDirection(player, channel, direction)
        if direction and direction:Length() > 0 then return direction:Normalized() end
        local data = player:GetData()
        local target = Mizuki.getTargetReticle(player, data)
        local ring = data.MizukiLudovicoRing
        if not target and ring and ring:Exists() then target = ring end
        if target then
            local offset = target.Position - player.Position
            if offset:Length() > 0 then return offset:Normalized() end
        end
        local pair = data.MizukiCannons and data.MizukiCannons[channel]
        local cannon = pair and pair[1]
        direction = cannon and cannon:Exists() and cannon:GetData().MizukiCannonAim
            or data.MizukiCannonAim or data.MizukiLastShootDirection
        if direction and direction:Length() > 0 then return direction:Normalized() end
    end
    local function rollWig(player)
        if not player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG) then return end
        local twiceLuck = player.Luck * 2
        local steps = twiceLuck < 0 and math.ceil(twiceLuck) or math.floor(twiceLuck)
        local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_MOMS_WIG)
        if rng:RandomInt(math.max(1, 20 - steps)) ~= 0 then return end
        local hive = CollectibleType.COLLECTIBLE_HIVE_MIND
        local cap = (player:HasCollectible(hive)
            or player:GetEffects():HasCollectibleEffect(hive)) and 10 or 5
        if player:GetNumBlueSpiders() >= cap then return end
        -- Zero target retains vanilla's free landing position and scatter.
        player:ThrowBlueSpider(player.Position, Vector.Zero)
    end
    local function rollEvilEye(player, direction)
        if not direction or not player:HasCollectible(CollectibleType.COLLECTIBLE_EVIL_EYE) then return end
        local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_EVIL_EYE)
        if rng:RandomInt(math.max(10, 30 - math.floor(player.Luck))) ~= 0 then return end
        -- Vanilla effect creation, as used by Samael. The engine manages its
        -- lifetime and subsequent tears; this is not another cannon or echo.
        local eye = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.EVIL_EYE, 0,
            player.Position, direction:Resized(player.ShotSpeed * 3), player)
        eye.Parent = player
    end
    local function canRoll(player)
        return Mizuki.isMizuki(player) and not Game():IsPaused() and not player:IsDead()
            and player:AreControlsEnabled() and player:IsExtraAnimationFinished()
            and hasEffect(player)
    end
    local function roll(player, channel, direction)
        if not canRoll(player) then return end
        local state, frame = getState(player), Game():GetFrameCount()
        local previous = state.Attempts[channel]
        if previous and frame >= previous and frame - previous < PERIOD then return end
        -- Failed rolls consume the same minimum interval. Rewinds discard a future
        -- attempt rather than locking the player to the abandoned timeline.
        state.Attempts[channel] = frame
        rollWig(player)
        if player:HasCollectible(CollectibleType.COLLECTIBLE_EVIL_EYE) then
            rollEvilEye(player, attackDirection(player, channel, direction))
        end
    end
    getState = function(player)
        local data = player:GetData()
        if not data.MizukiInputAttackEffectsState or not data.MizukiInputAttackEffectsState.Attempts then
            data.MizukiInputAttackEffectsState = { Shots = {}, Clocks = {}, Attempts = {} }
        end
        return data.MizukiInputAttackEffectsState
    end
    local function controlledMode(player, data)
        if Mizuki.usesCSectionWeapon(player) then return end
        local ring = data.MizukiLudovicoRing
        if ring and ring:Exists()
            and Mizuki.usesLudovicoWeapon(player) then
            return "controlled"
        end
        if Mizuki.getTargetReticle(player, data) then return "controlled" end
    end
    local function originalBeam(data, side, beam)
        local cannon = data.MizukiCannons and data.MizukiCannons[side]
            and data.MizukiCannons[side][1]
        return cannon and cannon:Exists() and Mizuki.isSameEntity(beam.Cannon, cannon)
            and not beam.PersistentEchoMode
            and not cannon:GetData().MizukiGuillotineNonFiring
    end
    local function liveBeam(beam)
        if beam.TrisagionShot then return beam.Tear and beam.Tear:Exists() end
        return beam.Laser and beam.Laser:Exists()
    end
    -- The controller calls once after the whole volley exists. Only the primary
    -- pair counts; Box of Friends, extra familiars and echoes do not add procs.
    function Mizuki.recordInputAttackEffects(player, beams, automatic, periodic, duration, echo)
        if echo or not canRoll(player) then return end
        local data = player:GetData()
        if controlledMode(player, data) or data.MizukiCannonAutoFireState == "deployed"
            or automatic then return end
        local sides = {}
        for _, beam in ipairs(beams) do
            local side = beam.LeftEye and 1 or 2
            if originalBeam(data, side, beam) and liveBeam(beam) then
                sides[side] = sides[side] or {}
                sides[side][#sides[side] + 1] = beam
            end
        end
        for side = 1, 2 do
            if sides[side] then
                if periodic then
                    local state = getState(player)
                    state.Shots[#state.Shots + 1] = {
                        Beams = sides[side], Side = side, Elapsed = 0, Duration = duration,
                        BornFrame = Game():GetFrameCount(),
                    }
                else roll(player, side, sides[side][1].Direction) end
            end
        end
    end
    -- Real gbt volleys report here. Echo replay calls fireFanFetus directly;
    -- simultaneous familiar copies share one player opportunity.
    function Mizuki.recordFanInputAttackEffects(player, direction)
        if not canRoll(player) then return end
        roll(player, "fan", direction)
    end
    local function advanceClock(player, state, side, mode, interval, direction)
        local clock = state.Clocks[side]
        if not clock or clock.Mode ~= mode then
            clock = { Mode = mode, Elapsed = 0, Interval = interval }
            state.Clocks[side] = clock
        elseif clock.Interval ~= interval then
            clock.Elapsed = clock.Elapsed * interval / clock.Interval
        end
        clock.Interval = interval
        clock.Elapsed = clock.Elapsed + 1
        if clock.Elapsed >= interval then
            clock.Elapsed = clock.Elapsed - interval
            roll(player, side, direction)
        end
    end
    function Mizuki.recordSwordInputAttackEffects(player, side, direction)
        if canRoll(player) then roll(player, side, direction) end
    end
    function Mizuki.recordMeleeAttackEffects(player, side, direction)
        local data, frame = player:GetData(), Game():GetFrameCount()
        if data.MizukiMeleeExtraAttackFrame ~= frame then
            data.MizukiMeleeExtraAttackFrame = frame
            data.MizukiExtraAttackFrame = frame
            Mizuki.tryFireImmaculateHeartTear(player, direction)
            Mizuki.recordExtraAttack(player, direction)
            Mizuki.recordMeleePepperAttack(player, direction)
        end
        Mizuki.recordSwordInputAttackEffects(player, side, direction)
    end

    -- The persistent ring has no firing events. One fire-rate interval is one
    -- counted attack, aimed from the player towards the current ring position.
    function Mizuki:UpdateLudovicoExtraAttacks(player)
        if not Mizuki.isMizuki(player) then return end
        local data = player:GetData()
        local ring = data.MizukiLudovicoRing
        if player:IsDead() or not Mizuki.usesLudovicoWeapon(player)
            or Mizuki.usesCSectionWeapon(player)
            or Mizuki.isBerserkClubActive(player)
            or not ring or not ring:Exists() or not ring:GetData().MizukiIsLudovicoRing then
            data.MizukiLudovicoExtraAttackClock = nil
            return
        end
        if Game():IsPaused() or not player:AreControlsEnabled()
            or not player:IsExtraAnimationFinished() then return end
        local clock = data.MizukiLudovicoExtraAttackClock or {Progress = 0}
        data.MizukiLudovicoExtraAttackClock = clock
        local frame = Game():GetFrameCount()
        if clock.LastFrame == frame then return end
        clock.LastFrame = frame
        clock.Progress = clock.Progress + 1 / Mizuki.getFireInterval(player)
        if clock.Progress + 0.000001 < 1 then return end
        clock.Progress = math.max(0, clock.Progress - 1)
        local offset = ring.Position - player.Position
        if offset:Length() <= Mizuki.RuntimeParameters.AimDeadZone then return end
        local direction = offset:Normalized()
        Mizuki.tryFireImmaculateHeartTear(player, direction)
        Mizuki.recordExtraAttack(player, direction)
        data.MizukiExtraAttackFrame = frame
    end
    function Mizuki:UpdateInputAttackEffects(player)
        if not Mizuki.isMizuki(player) then return end
        local data = player:GetData()
        if player:IsDead() or not hasEffect(player) then
            data.MizukiInputAttackEffectsState = nil
            return
        end
        if not canRoll(player) then return end
        local state, frame = getState(player), Game():GetFrameCount()
        if state.LastFrame == frame then return end
        state.LastFrame = frame
        if Mizuki.usesCSectionWeapon(player)
            or Mizuki.usesCannonSpiritSword(player) then
            state.Shots, state.Clocks = {}, {}
            return
        end
        local deployed = data.MizukiCannonAutoFireState == "deployed"
        local mode = controlledMode(player, data) or deployed and "deployed"
        if mode then state.Shots = {} end
        for index = #state.Shots, 1, -1 do
            local shot, live = state.Shots[index], false
            for _, beam in ipairs(shot.Beams) do
                if liveBeam(beam) then live = true; break end
            end
            if not live then table.remove(state.Shots, index)
            elseif shot.BornFrame ~= frame then
                shot.Elapsed = shot.Elapsed + 1
                -- Preserve the finite window, including the native shrink tail.
                -- Another effect holding a laser cannot extend this quota.
                if shot.Elapsed <= shot.Duration and shot.Elapsed % PERIOD == 0 then roll(player, shot.Side, shot.Beams[1].Direction) end
                if shot.Elapsed >= shot.Duration then table.remove(state.Shots, index) end
            end
        end
        for side = 1, 2 do
            local source
            for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
                if originalBeam(data, side, beam) and liveBeam(beam) and not beam.Ending then
                    source = source or beam
                    if beam.Automatic then source = beam; break end
                end
            end
            local cannon = data.MizukiCannons and data.MizukiCannons[side]
                and data.MizukiCannons[side][1]
            local interval, clockMode
            if mode and cannon and cannon:Exists() then
                clockMode = mode
                interval = (Mizuki.usesAutomaticBeam(player) or Mizuki.hasPeriodicBeam(player))
                    and PERIOD or math.max(PERIOD, player.MaxFireDelay + 1)
            elseif source and (source.Automatic or source.TechXDriven) then
                clockMode, interval = "continuous", PERIOD
            end
            if interval then advanceClock(player, state, side, clockMode, interval,
                not mode and source and source.Direction or nil)
            else state.Clocks[side] = nil end
        end
    end
    local function reset()
        for index = 0, Game():GetNumPlayers() - 1 do
            local data = Isaac.GetPlayer(index):GetData()
            data.MizukiInputAttackEffectsState = nil
            data.MizukiLudovicoExtraAttackClock = nil
        end
    end
    function Mizuki.registerInputAttackEffectCallbacks()
        Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateInputAttackEffects)
        Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateLudovicoExtraAttacks)
        Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, reset)
        Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, reset)
    end
end
-- endregion Input Attack Effects

-- region Eye of Greed
function Mizuki.advanceEyeOfGreed(player, direction, origin, source)
    if not player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_GREED) then return end
    local data = player:GetData()
    data.MizukiEyeOfGreedShots = (data.MizukiEyeOfGreedShots or 0) + 1
    if data.MizukiEyeOfGreedShots < 20 then return end
    data.MizukiEyeOfGreedShots = data.MizukiEyeOfGreedShots - 20

    local paid = player:GetNumCoins() > 0
    if paid then player:AddCoins(-1) end
    local aim = direction and direction:Normalized() or Vector(0, -1)
    -- FireTear supplies native item effects/physics. Do not notify the counted
    -- attack entry for this extra shot, or it would advance its own counter.
    local tear = player:FireTear(origin or player.Position,
        aim:Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed),
        true, true, false, source or player, 1)
    tear:ChangeVariant(TearVariant.COIN)
    tear:AddTearFlags(TearFlags.TEAR_MIDAS | TearFlags.TEAR_COIN_DROP)
    if paid then tear.CollisionDamage = player.Damage * 1.5 + 10 end
end
-- endregion Eye of Greed

-- region Dead Tooth
do
    -- Same native FART_RING setup as Samael's blindfolded character.
    -- Raw input keeps this independent of weapon charge/release behavior.
    Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
        if not Mizuki.isMizuki(player) or player:IsDead()
            or not player:AreControlsEnabled() or not player:IsExtraAnimationFinished()
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_DEAD_TOOTH)
            or not Mizuki.hasRawShootingInput(player) then return end
        local data = player:GetData()
        local ring = data.MizukiDeadToothRing
        if not ring or not ring:Exists() then
            ring = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.FART_RING, 0,
                player.Position, Vector.Zero, player):ToEffect()
            ring:FollowParent(player)
            ring.ParentOffset = Vector(0, -20)
            ring.Scale = 0.4
            data.MizukiDeadToothRing = ring
        end
        ring.Timeout = 10
    end)
end
-- endregion Dead Tooth

-- region Large Zit
do
    -- Native held-fire check 7827EC-782850: global frame % 30 == 0,
    -- Random() % 3 == 0. Thirty logic updates are sixty rendered frames.
    function Mizuki:UpdateLargeZit(player)
        if not Mizuki.isMizuki(player) or Game():IsPaused() or player:IsDead()
            or not player:AreControlsEnabled() or not player:IsExtraAnimationFinished()
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_LARGE_ZIT)
            or not Mizuki.hasRawShootingInput(player) then return end
        local frame = Game():GetFrameCount()
        local data = player:GetData()
        if frame % 30 ~= 0 or data.MizukiLargeZitRollFrame == frame then return end
        local shooting, direction = Mizuki.getTech5Input(player)
        if not shooting then return end
        data.MizukiLargeZitRollFrame = frame
        if Random() % 3 ~= 0 then return end
        -- Native DoZitEffect (7C9590) creates the fixed-size, double-damage
        -- slow/white-creep tear with player ownership. Our existing Dr. Fetus
        -- enemy/grid impact callbacks already accept these ordinary tears.
        -- It must not enter Pencil/Greed counters or echo recording.
        player:DoZitEffect(direction)
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateLargeZit)
end
-- endregion Large Zit

-- region Hemoptysis
do
    -- Native sneeze visuals are BLOOD_EXPLOSION (subtype 2/3) and HAEMO_TRAIL
    -- (subtype 1), not EntityLaser. Their first native update occurs inside the
    -- firing function, before ID_HEMOPTYSIS is added to the player.
    local function restoreSneezeMouth(_, effect)
        if effect:GetData().MizukiHemoptysisMouthOffsetApplied then return end
        if effect.Variant == EffectVariant.BLOOD_EXPLOSION then
            if effect.SubType ~= 2 and effect.SubType ~= 3 then return end
        elseif effect.Variant == EffectVariant.HAEMO_TRAIL then
            if effect.SubType ~= 1 then return end
        else
            return
        end
        local player = effect.SpawnerEntity and effect.SpawnerEntity:ToPlayer()
        if not player or not Mizuki.isMizuki(player)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_HEMOPTYSIS) then return end
        -- Only replace the native C Section belly offset. Fetal launch effects
        -- come from a familiar and ordinary blood effects do not use this offset.
        local offset = effect.PositionOffset
        if math.abs(offset.X) > Mizuki.RuntimeParameters.OffsetEpsilon
            or math.abs(offset.Y + 6 * player.SpriteScale.Y)
                > Mizuki.RuntimeParameters.OffsetEpsilon then return end
        -- Native offset 3 resolves Mouth without the C Section override. Offset
        -- 4 resolves the same Mouth but substitutes the belly when C Section is held.
        effect.PositionOffset = player:GetLaserOffset(
            LaserOffset.LASER_SHOOP_OFFSET, Vector.Zero
        )
        effect:GetData().MizukiHemoptysisMouthOffsetApplied = true
    end

    function Mizuki.registerHemoptysisCallbacks()
        Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, restoreSneezeMouth,
            EffectVariant.BLOOD_EXPLOSION)
        Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, restoreSneezeMouth,
            EffectVariant.HAEMO_TRAIL)
    end
end
-- endregion Hemoptysis

-- region Tech 5
do
    -- Held shooting remains independent of the primary weapon's releases.
    -- Native timing: one 1/3 roll per eight logic frames, including failed rolls.
    -- Tech .5 borrows a free original cannon without taking primary occupancy.
    -- Its independent input clock and native factory never create echo shots.
    function Mizuki.getTech5IdleCannon(player)
        local data = player:GetData()
        local preferred = Mizuki.getNextCannonFiringSide(player, data)
        local available = {}
        for _, side in ipairs({preferred, 3 - preferred}) do
            for _, cannon in ipairs(data.MizukiCannons and data.MizukiCannons[side] or {}) do
                local cd = cannon:Exists() and cannon:GetData()
                if cd and not cd.MizukiAwaitingInitialLayout and not cd.MizukiPersistentEchoMode
                    and not cd.MizukiGuillotineNonFiring and not cd.MizukiGuillotineDisplaySuppressed
                    and not Mizuki.isTech2Cannon(cannon) then
                    local busy = false
                    local knife = cd.MizukiMomKnife
                    if knife and knife:Exists() and knife.InitSeed == cd.MizukiMomKnifeInitSeed then
                        local swing = knife:GetData().MizukiBerserkSwing
                        busy = knife:IsFlying() or (swing and Game():GetFrameCount() < swing.Frame + swing.Duration)
                    end
                    for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
                        if Mizuki.isSameEntity(beam.Cannon, cannon) and not beam.PersistentEchoMode
                            and not (beam.MomKnifeDriven and beam.Ending)
                            and not (beam.TechXReleased and not beam.TechXLinked)
                            and ((beam.Laser and beam.Laser:Exists())
                                or Mizuki.isCannonKnifeAttackActive(beam)) then
                            busy = true
                            break
                        end
                    end
                    if not busy then available[side] = cannon; break end
                end
            end
        end
        if available[1] and available[2] then
            return available[data.MizukiTech5NextIdleSide or preferred], true
        end
        return available[preferred] or available[3 - preferred], false
    end

    function Mizuki:UpdateTech5(player)
        if not Mizuki.isMizuki(player) or Game():IsPaused() or player:IsDead()
            or not player:AreControlsEnabled() or not player:IsExtraAnimationFinished()
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_5) then return end
        local data, frame = player:GetData(), Game():GetFrameCount()
        local parameters = Mizuki.WeaponParameters.Tech5
        if data.MizukiTech5NextRollFrame and frame < data.MizukiTech5NextRollFrame then return end
        local shooting, direction, target = Mizuki.getTech5Input(player)
        if not shooting then return end
        data.MizukiTech5NextRollFrame = frame + parameters.RollIntervalFrames
        if player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_TECH_5):RandomInt(parameters.RollRandomBound) ~= 0 then return end
        -- Keep offset 2 for its native parameters and Repentance+ 5% random
        -- effect even when replacing only the initial muzzle geometry.
        local cannon, bothIdle
        if not Mizuki.usesCannonSpiritSword(player) then
            cannon, bothIdle = Mizuki.getTech5IdleCannon(player)
        end
        local geometry = cannon and Mizuki.prepareTech5CannonShot(player, cannon, direction, target)
        local head = not cannon and Mizuki.getGuillotineHeads(player)[1]
        -- FireTechLaser itself adds TearsOffset, including native Guillotine
        -- displacement. Cancel it in the requested origin instead of adding twice.
        local origin = geometry and geometry.Origin
            or (head and (head.Position - player.TearsOffset) or player.Position)
        local laser = player:FireTechLaser(origin, LaserOffset.LASER_TECH5_OFFSET,
            direction, false, true, player, 1)
        data.MizukiTech5NextIdleSide = cannon and bothIdle and (3 - cannon.SubType) or nil
        -- Native samples enter their fade around age 2 and disappear at age 4-5.
        -- Set only the active timeout; the engine owns the fade and removal.
        laser.Timeout = parameters.ActiveFrames
        if geometry then
            -- Static shot: copy the final cannon origin once, never register
            -- this laser in its primary attack list or bind cannon following.
            laser.Position, laser.PositionOffset = geometry.Origin, geometry.PositionOffset
            local reflectionDepthShift = Mizuki.applyBeamReflectionHeight(player, laser)
            laser.AngleDegrees = geometry.Direction:GetAngleDegrees()
            laser.DepthOffset = geometry.DepthOffset - reflectionDepthShift
            laser.DisableFollowParent, laser.Velocity = true, Vector.Zero
        else
            -- Retain the forehead fallback's existing upward correction.
            laser.PositionOffset = laser.PositionOffset + Vector(0, -2)
        end
        if target and not geometry then
            -- Point from the actual native forehead origin, not the ground center.
            local offset = target - laser.Position
            if offset:Length() > Mizuki.RuntimeParameters.AimDeadZone then
                laser.AngleDegrees = offset:GetAngleDegrees()
            end
        end
        local laserData = laser:GetData()
        laserData.MizukiTech5, laserData.MizukiBeamOwner = true, player
        if head then
            -- The player remains the native attack source. Only the moving origin
            -- follows the head; disable the engine's body-parent repositioning.
            laser.DisableFollowParent = true
            laserData.MizukiTech5OriginHead = head
            laserData.MizukiTech5OriginHeadSeed = head.InitSeed
            laserData.MizukiTech5HeadOffset = laser.Position - head.Position
            laser.Velocity = Vector(head.Velocity.X, head.Velocity.Y)
        end
        Mizuki.trackDeadEyeLaser(player, laser)
    end

    function Mizuki:UpdateTech5HeadOrigin(laser)
        local data = laser:GetData()
        if not data.MizukiTech5 then return end
        local head = data.MizukiTech5OriginHead
        if not head or not head:Exists() or head.InitSeed ~= data.MizukiTech5OriginHeadSeed then return end
        laser.Position = head.Position + data.MizukiTech5HeadOffset
        laser.Velocity = Vector(head.Velocity.X, head.Velocity.Y)
    end

    function Mizuki.registerTech5Callbacks()
        -- Registered after UpdateWeapon; this remains independent of all early exits.
        Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateTech5)
        Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, Mizuki.UpdateTech5HeadOrigin)
    end
end
-- endregion Tech 5

-- region Dead Eye
-- Native ClearDeadEyeCharge owns the 20/33/50% miss RNG. Native charge units
-- add 12.5% damage each (0x767016), so a wiki-sized hit adds two units.
do
    local attacks = {}
    local P = {ChargeUnitsPerHit = 2, IntensityPerHit = 0.25,
        MinimumWindowFrames = 4, GlowScale = 0.5, GlowVerticalStretch = 2, GlowAlpha = 0.5}
    Mizuki.DeadEyeParameters = P

    local function eligible(player)
        return player and player:Exists() and Mizuki.isMizuki(player)
            and not player:IsDead()
            and player:HasCollectible(CollectibleType.COLLECTIBLE_DEAD_EYE)
            and not player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
            and not player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
    end
    local function isOriginal(entity)
        local data = entity:GetData()
        return not data.MizukiEchoCannon and not data.MizukiPersistentEchoMode
            and not data.MizukiEchoKnife and not data.MizukiFanEchoFetus
            and not data.MizukiAttackSequenceReplay and not data.MizukiNativeLaserBranchEcho
    end
    local function alive(entity, seed)
        return entity and entity:Exists() and entity.InitSeed == seed
    end
    function Mizuki.getDeadEyeIntensity(player)
        if not eligible(player) then return 0 end
        return player:GetData().MizukiDeadEyeIntensity or 0
    end
    local function attach(record, entity)
        if not entity or not entity:Exists() then return end
        local data = entity:GetData()
        data.MizukiDeadEyeAttack = record
        data.MizukiDeadEyeIntensity = record.Intensity
        record.Entities[#record.Entities + 1] = {Entity = entity, Seed = entity.InitSeed}
    end
    function Mizuki.attachDeadEyeBranch(source, entity)
        if not source or not source:Exists() or not entity or not entity:Exists()
            or not isOriginal(source) or not isOriginal(entity) then return end
        local record = source:GetData().MizukiDeadEyeAttack
        if record and entity:GetData().MizukiDeadEyeAttack ~= record then attach(record, entity) end
    end
    local function begin(player, duration, rolling)
        if not eligible(player) then return end
        local frame = Game():GetFrameCount()
        local record = {Player = player, PlayerSeed = player.InitSeed, Entities = {},
            Deadline = frame + duration, Rolling = rolling,
            Intensity = Mizuki.getDeadEyeIntensity(player)}
        attacks[#attacks + 1] = record
        return record
    end
    local function window(player)
        return math.max(P.MinimumWindowFrames, player.MaxFireDelay + 1)
    end
    function Mizuki.trackDeadEyeBeam(player, beam, echo)
        if echo or beam.PersistentEchoMode or not beam.Laser or not isOriginal(beam.Laser) then return end
        -- Native bone/sword throws already own their Dead Eye collision handling.
        if Mizuki.isBerserkClubActive(player)
            and not (beam.MomKnife and beam.MomKnife:GetData().MizukiBerserkCollisionProxy) then return end
        local record = begin(player, beam.Automatic and window(player) or beam.TotalDuration, beam.Automatic)
        if not record then return end
        record.Beam = beam
        attach(record, beam.Laser)
        attach(record, beam.MomKnife)
        attach(record, beam.Cannon)
    end
    function Mizuki.trackDeadEyeTechXRing(player, ring, beam)
        if Mizuki.isSameEntity(ring, beam.Laser) or not isOriginal(ring) then return end
        local record = beam.Laser:GetData().MizukiDeadEyeAttack
        if record then attach(record, ring)
        else Mizuki.trackDeadEyeLaser(player, ring) end
    end
    function Mizuki.trackDeadEyeLaser(player, laser)
        if not isOriginal(laser) then return end
        local record = begin(player, laser.Timeout + 2, false)
        if record then attach(record, laser) end
    end
    function Mizuki.trackDeadEyeProjectile(player, tear)
        if not isOriginal(tear) then return end
        local record = begin(player, window(player), false)
        if record then record.Projectile = true; attach(record, tear) end
    end
    function Mizuki.trackDeadEyeSwing(player, body, duration)
        local record = begin(player, duration, false)
        if record then record.Swing = true; attach(record, body) end
        return record
    end
    local function finish(record)
        if record.Awarded or not eligible(record.Player) then return end
        local player = record.Player
        if record.Hit then
            for _ = 1, P.ChargeUnitsPerHit do player:AddDeadEyeCharge() end
            player:GetData().MizukiDeadEyeIntensity = math.min(1,
                Mizuki.getDeadEyeIntensity(player) + P.IntensityPerHit)
        elseif not record.CancelMiss then
            local before = player.Damage
            player:ClearDeadEyeCharge()
            -- Clear calls native cache evaluation only on a successful reset.
            if player.Damage < before - Mizuki.RuntimeParameters.DamageComparisonEpsilon then
                player:GetData().MizukiDeadEyeIntensity = 0
            end
        end
        record.Awarded = true
    end
    local function owner(entity)
        if not entity then return end
        local player = entity:ToPlayer()
        if player then return player end
        local familiar = entity:ToFamiliar()
        if familiar then return familiar.Player end
        return entity:GetData().MizukiBeamOwner
    end
    local function overlap(laser, enemy)
        local reach = laser.Size + enemy.Size
        if laser:IsCircleLaser() then
            return math.abs(laser.Position:Distance(enemy.Position) - laser.Radius) <= reach
        end
        local samples = laser:GetSamples()
        local function near(first, last)
            local segment = last - first
            local length = segment:LengthSquared()
            local t = length > 0 and (enemy.Position - first):Dot(segment) / length or 0
            local point = first + segment * math.max(0, math.min(1, t))
            return point:DistanceSquared(enemy.Position) <= reach * reach
        end
        if #samples < 2 then return near(laser.Position, laser:GetEndPoint()) end
        for index = 1, #samples - 1 do
            if near(samples:Get(index - 1), samples:Get(index)) then return true end
        end
        return false
    end
    Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE,
        function(_, enemy, amount, flags, source)
            if amount <= 0 or not enemy:ToNPC() or not enemy:IsVulnerableEnemy()
                or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
            local entity = source and source.Entity
            if not entity then return end
            local data = entity:GetData()
            local record = data.MizukiBerserkSwingState and data.MizukiBerserkSwingState.DeadEyeAttack
                or data.MizukiDeadEyeAttack
            if record and not record.Awarded and isOriginal(entity)
                and (entity:ToLaser() or entity:ToKnife()
                    or (flags & DamageFlag.DAMAGE_LASER) == 0) then record.Hit = true; return end
            -- Player/familiar-sourced native lasers require actual path attribution.
            if (flags & DamageFlag.DAMAGE_LASER) == 0 then return end
            local player = owner(entity)
            if not eligible(player) then return end
            for _, candidate in ipairs(attacks) do
                if not candidate.Awarded and GetPtrHash(candidate.Player) == GetPtrHash(player) then
                    for _, entry in ipairs(candidate.Entities) do
                        local laser = alive(entry.Entity, entry.Seed) and entry.Entity:ToLaser()
                        if laser and laser.CollisionDamage > 0 and overlap(laser, enemy) then
                            candidate.Hit = true
                            break
                        end
                    end
                end
            end
        end)
    local function active(record)
        if record.Swing then return Game():GetFrameCount() < record.Deadline end
        if record.Contact then
            for _, entry in ipairs(record.Entities) do
                if alive(entry.Entity, entry.Seed) and entry.Entity:GetData().MizukiDeadEyeAttack == record
                    and not entry.Entity:GetData().MizukiIsIdle then return true end
            end
            return false
        end
        if record.Beam and record.Beam.MomKnifeDriven then
            return Mizuki.isCannonKnifeAttackActive(record.Beam)
        end
        for _, entry in ipairs(record.Entities) do
            local entity = entry.Entity
            if alive(entity, entry.Seed) and entity:GetData().MizukiDeadEyeAttack == record
                and (entity:ToLaser() or (record.Projectile and entity:ToTear())) then return true end
        end
        return false
    end
    local function renew(record)
        local nextRecord = begin(record.Player, window(record.Player), true)
        if not nextRecord then return end
        nextRecord.Beam = record.Beam
        nextRecord.Contact = record.Contact
        for _, entry in ipairs(record.Entities) do
            if alive(entry.Entity, entry.Seed) then attach(nextRecord, entry.Entity) end
        end
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
        if Game():IsPaused() then return end
        local frame = Game():GetFrameCount()
        for index = #attacks, 1, -1 do
            local record = attacks[index]
            local valid = alive(record.Player, record.PlayerSeed) and eligible(record.Player)
            local live = valid and active(record)
            if valid and record.Hit and not record.Awarded then finish(record) end
            if record.Rolling and record.Beam and record.Beam.Ending
                and not record.EndingObserved then
                record.EndingObserved = true
                -- Releasing midway through a window is not another missed
                -- attack. Keep attribution alive for hits in the native tail.
                record.CancelMiss = frame < record.Deadline
            end
            -- Finite shots retain their result for the actual entity lifetime.
            -- Once a sustained beam starts its native ending, its last window
            -- also stays attached until removal; the tail is not a new shot.
            local canRenew = record.Rolling and not (record.Beam and record.Beam.Ending)
            local expired = (record.Swing or canRenew) and frame >= record.Deadline
            if record.Beam and record.Beam.MomKnifeDriven then expired = not live end
            if not valid or not live or expired then
                if valid then finish(record) end
                table.remove(attacks, index)
                for _, entry in ipairs(record.Entities) do
                    if alive(entry.Entity, entry.Seed) and entry.Entity:GetData().MizukiDeadEyeAttack == record then
                        entry.Entity:GetData().MizukiDeadEyeAttack = nil
                        if entry.Entity:ToFamiliar() then
                            entry.Entity:GetData().MizukiDeadEyeIntensity = Mizuki.getDeadEyeIntensity(record.Player)
                        end
                    end
                end
                if live and canRenew then renew(record) end
            end
        end
    end)
    Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE,
        function(_, laser)
            local data = laser:GetData()
            if data.MizukiIsLudovicoRing ~= true or data.MizukiDeadEyeAttack
                or not isOriginal(laser) then return end
            local player = data.MizukiLudovicoOwner
            local record = eligible(player) and begin(player, window(player), true)
            if record then attach(record, laser) end
        end)
    Mizuki:AddPriorityCallback(ModCallbacks.MC_FAMILIAR_UPDATE, CallbackPriority.LATE,
        function(_, cannon)
            local data, player = cannon:GetData(), cannon.Player
            if not eligible(player) or not isOriginal(cannon) or data.MizukiIsIdle
                or data.MizukiDeadEyeAttack or Mizuki.cannonUsesKnifeWeapon(player)
                or Mizuki.usesCSectionWeapon(player) then return end
            -- Ordinary firing cannons belong to their beam's shot. Their
            -- delayed return pose must not create a second, empty attack.
            -- Only independent contact weapons need their own rolling clock.
            if not data.MizukiLudovicoOrbiting and not data.MizukiGuillotineNonFiring then return end
            local record = begin(player, window(player), true)
            if record then record.Contact = true; attach(record, cannon) end
        end, Mizuki.CannonVariant)
    function Mizuki.renderDeadEyeGlow(entity, screen, scale, alpha, explicitIntensity, rotation)
        local data = entity:GetData()
        -- Native bone-knife Render (0x966380..0x966584) draws its own Dead Eye
        -- sprite from the animation's tip null, independently of body alpha.
        -- A second manual sprite duplicates that glow and cannot follow Swing.
        if data.MizukiBerserkClub == true and (entity.Variant == 2 or entity.Variant == 3) then return end
        local intensity = explicitIntensity or data.MizukiDeadEyeIntensity or 0
        if intensity <= 0 then return end
        local sprite = data.MizukiDeadEyeGlowSprite
        if not sprite then
            sprite = Sprite()
            sprite:Load("gfx/DeadEyeTearEffect.anm2", true)
            data.MizukiDeadEyeGlowSprite = sprite
        end
        sprite:SetFrame("Idle", 0)
        sprite.Rotation = rotation or 0
        sprite.Scale = Vector(math.abs(scale.X), math.abs(scale.Y) * P.GlowVerticalStretch) * P.GlowScale
        -- Native bone glow (0x9663C1-0x966444) uses white RGB/alpha with a
        -- red additive channel of min(charge, 8) * 0.125. Keep that colour
        -- parameterization and apply our requested opacity separately.
        sprite.Color = Color(1, 1, 1, (alpha or 1) * P.GlowAlpha, intensity, 0, 0)
        sprite:Render(screen, Vector.Zero, Vector.Zero)
    end
    local function clear()
        for _, record in ipairs(attacks) do
            for _, entry in ipairs(record.Entities) do
                if alive(entry.Entity, entry.Seed) and entry.Entity:GetData().MizukiDeadEyeAttack == record then
                    entry.Entity:GetData().MizukiDeadEyeAttack = nil
                end
            end
        end
        attacks = {}
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clear)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clear)
    Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, clear, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
end
-- endregion Dead Eye

-- region Technology Zero head direction
function Mizuki.getTechnologyZeroHeadDirection(player)
    local data = player:GetData()
    local lock = data.MizukiTechnologyZeroHeadLock
    if not Mizuki.isMizuki(player) or not Mizuki.usesTechnologyZeroBeam(player) or player:IsDead() then
        data.MizukiTechnologyZeroHeadLock = nil
        return
    end
    local release = Mizuki.getTechnologyZeroReleaseDirection(player)
    if release then return release end
    if not lock then return end
    for i = #lock.Lasers, 1, -1 do
        local record = lock.Lasers[i]
        local laser = record.Entity
        if not laser:Exists() or laser:IsDead() or laser.InitSeed ~= record.Seed
            or GetPtrHash(laser) ~= record.Hash then
            table.remove(lock.Lasers, i)
        end
    end
    if #lock.Lasers == 0 then
        data.MizukiTechnologyZeroHeadLock = nil
        return
    end
    return lock.Direction
end

function Mizuki.lockTechnologyZeroHead(player, direction, beams)
    if not Mizuki.usesTechnologyZeroBeam(player) then return end
    local lasers = {}
    for _, beam in ipairs(beams) do
        local laser = beam.Laser
        if not beam.PersistentEchoMode and not beam.Technology2 and not beam.TechXDriven
            and not beam.MomKnifeDriven and laser and laser:Exists() then
            lasers[#lasers + 1] = { Entity = laser, Seed = laser.InitSeed, Hash = GetPtrHash(laser) }
        end
    end
    if #lasers == 0 then return end
    Mizuki.getTechnologyZeroHeadDirection(player)
    local data = player:GetData()
    local lock = data.MizukiTechnologyZeroHeadLock or { Lasers = {} }
    -- Keep outstanding beams only for lifetime; the newest real shot owns
    -- facing, so an older overlapping shot can never restore an old direction.
    lock.Direction = Vector(direction.X, direction.Y)
    for _, record in ipairs(lasers) do lock.Lasers[#lock.Lasers + 1] = record end
    data.MizukiTechnologyZeroHeadLock = lock
end

-- endregion Technology Zero head direction

-- region Melee pickups
do
    -- Shared native pickup collection for held melee weapons.
    local function valid(entity, seed)
        return entity and entity:Exists() and (not seed or entity.InitSeed == seed)
    end

    local pickupBlacklist = {
        [PickupVariant.PICKUP_COLLECTIBLE] = true, [PickupVariant.PICKUP_SHOPITEM] = true,
        [PickupVariant.PICKUP_TROPHY] = true, [PickupVariant.PICKUP_BIGCHEST] = true,
        [PickupVariant.PICKUP_BED] = true, [PickupVariant.PICKUP_MEGACHEST] = true,
        [PickupVariant.PICKUP_THROWABLEBOMB] = true,
    }
    local pickupTransfers = {}

    function Mizuki.tryCollectMeleePickup(pickup, player, pushVelocity)
        if not valid(pickup) or not valid(player) or pickupBlacklist[pickup.Variant]
            or pickup.Price ~= 0 or pickup.Wait > 0 or pickup:GetSprite():GetAnimation() == 'Collect'
            or pickup:GetData().MizukiMeleePickupTransfer then return false end
        if pickup.Variant == PickupVariant.PICKUP_MIMICCHEST then
            pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_SPIKEDCHEST,
                pickup.SubType, false, true, false)
        end
        -- Samael's native-collection transfer preserves pickup effects,
        -- affordability and chest/room triggers; never manually grant items.
        local pd = pickup:GetData()
        pd.MizukiMeleePickupTransfer = {Position = Vector(pickup.Position.X, pickup.Position.Y),
            Player = player, PlayerSeed = player.InitSeed, Frame = Game():GetFrameCount(),
            PlayerPosition = Vector(player.Position.X, player.Position.Y),
            PickupSeed = pickup.InitSeed, Variant = pickup.Variant, PushVelocity = pushVelocity,
            Color = Color.Lerp(pickup:GetSprite().Color, pickup:GetSprite().Color, 0)}
        pickupTransfers[GetPtrHash(pickup)] = pd.MizukiMeleePickupTransfer
        pickup.Position = player.Position
        pickup.Velocity = Vector.Zero
        local hidden = Color.Lerp(pd.MizukiMeleePickupTransfer.Color,
            pd.MizukiMeleePickupTransfer.Color, 0)
        hidden.A = 0
        pickup:GetSprite().Color = hidden
        return true
    end

    -- Native collection is performed at the player for two updates. As in
    -- Samael, contents of opened chests/sacks must return to the original site.
    local function restorePickupContents(_, entity)
        local transfer = pickupTransfers[GetPtrHash(entity)]
        if transfer and entity.InitSeed ~= transfer.PickupSeed then transfer = nil end
        if not transfer then
            local spawner = entity.SpawnerEntity
            transfer = spawner and spawner:GetData().MizukiMeleePickupTransfer
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
    function Mizuki.registerMeleePickupCallbacks()
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
            local transfer = data.MizukiMeleePickupTransfer
            if not transfer or Game():GetFrameCount() - transfer.Frame < 2 then return end
            pickup:GetSprite().Color = transfer.Color
            if pickup:GetSprite():GetAnimation() ~= 'Collect' then
                pickup.Position = transfer.Position
                pickup.Velocity = transfer.PushVelocity or (valid(transfer.Player, transfer.PlayerSeed)
                    and (transfer.Position - transfer.Player.Position):Resized(5) or Vector.Zero)
            end
            data.MizukiMeleePickupTransfer = nil
        end)

        Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_RENDER, function(_, pickup)
            local transfer = pickup:GetData().MizukiMeleePickupTransfer
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
            local transfer = pickup:GetData().MizukiMeleePickupTransfer
            if transfer and valid(transfer.Player, transfer.PlayerSeed)
                and GetPtrHash(transfer.Player) == GetPtrHash(entity)
                and (pickup.Variant == PickupVariant.PICKUP_SPIKEDCHEST
                    or pickup.Variant == PickupVariant.PICKUP_MIMICCHEST) then return false end
        end)
    end
end
-- endregion Melee pickups
