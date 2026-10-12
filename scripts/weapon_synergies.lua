-- Small weapon compatibility rules. Large independent weapons keep their own files.

-- Dr. Fetus: one native bomb at the first enemy/grid hit by each attack entity.
-- Ownership is resolved from the actual source, never from a volley-wide flag.
do
    local function ownerOf(entity)
        if not entity then return nil end
        local player = entity:ToPlayer()
        if player then return player end
        local familiar = entity:ToFamiliar()
        return familiar and familiar.Player or nil
    end

    local pendingGridBombs = {}

    local function spawnFirstHitBomb(attack, player, position)
        local data = attack:GetData()
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

    local function resolveAttack(source, damageFlags)
        local attack = source and source.Entity
        if not attack then return end
        local data = attack:GetData()
        local player = attack:ToPlayer()
        if player then
            -- Native Ludovico ring damage names the player as its source.
            if (damageFlags & DamageFlag.DAMAGE_LASER) == 0
                or (damageFlags & DamageFlag.DAMAGE_EXPLOSION) ~= 0 then return end
            attack = player:GetData().MizukiLudovicoTechXProbe
            if not attack or not attack:Exists()
                or attack:GetData().MizukiLudovicoTechXProbe ~= true then return end
        elseif attack:ToLaser() then
            attack = attack:ToLaser()
            player = data.MizukiBeamOwner or data.MizukiLudovicoOwner
        elseif attack:ToKnife() then
            attack = attack:ToKnife()
            if data.MizukiCannonKnife ~= true and data.MizukiEchoKnife ~= true
                and data.MizukiBerserkSwingHitbox ~= true then return end
            player = data.MizukiCannonKnifeOwner
                or ownerOf(attack.Parent) or ownerOf(attack.SpawnerEntity)
        elseif attack:ToTear() then
            attack = attack:ToTear()
            -- Native fetuses already drop their own Dr. Fetus bomb.
            if attack:HasTearFlags(TearFlags.TEAR_FETUS) then return end
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

    function Mizuki:TriggerFirstHitFetusBomb(entity, amount, damageFlags, source)
        local enemy = entity:ToNPC()
        if amount <= 0 or not enemy or not enemy:IsActiveEnemy(false)
            or enemy:IsDead() or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
        local attributedOwner = ownerOf(source and source.Entity)
        if attributedOwner and attributedOwner:Exists() and Mizuki.isMizuki(attributedOwner)
            and attributedOwner:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS)
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
                    and (data.MizukiBeam == true or data.MizukiLudovicoTechXProbe == true
                        or data.MizukiTech5 == true)
                    and laser.CollisionDamage > 0 and overlapsEnemy(laser, enemy) then
                    spawnFirstHitBomb(laser, attributedOwner, enemy.Position)
                end
            end
            return
        end
        local attack, player = resolveAttack(source, damageFlags)
        if not attack or not player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then return end
        spawnFirstHitBomb(attack, player, enemy.Position)
    end

    Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, Mizuki.TriggerFirstHitFetusBomb)

    function Mizuki:QueueFirstHitFetusGridBomb(attack)
        if Game():IsPaused() or not attack:Exists() then return end
        local data = attack:GetData()
        if data.MizukiFirstHitBombSpawned == true then return end
        local tear = attack:ToTear()
        local player
        if tear and tear:HasTearFlags(TearFlags.TEAR_FETUS) then
            if data.MizukiFanFetus ~= true
                or (tear.WaitFrames or 0) > 0
                or not tear:HasTearFlags(TearFlags.TEAR_FETUS_BOMBER) then return end
            player = ownerOf(tear.Parent) or ownerOf(tear.SpawnerEntity)
        else
            attack, player = resolveAttack({Entity = attack}, 0)
        end
        if not attack or not player or not player:Exists() or not Mizuki.isMizuki(player)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then return end

        local position
        local laser, knife, familiar = attack:ToLaser(), attack:ToKnife(), attack:ToFamiliar()
        if laser then
            if laser.CollisionDamage <= 0 or (data.MizukiBeam ~= true
                and data.MizukiLudovicoTechXProbe ~= true and data.MizukiTech5 ~= true) then return end
            position = laser:IsCircleLaser() and Mizuki.getFetusRingGridTarget(laser)
                or (not laser:IsCircleLaser() and Mizuki.getFetusBeamGridTarget(laser))
        elseif knife then
            if not knife:IsFlying() then return end
            position = Mizuki.getFetusContactGridTarget(knife.Position, knife.Size)
        elseif familiar then
            if data.MizukiAwaitingInitialLayout or data.MizukiIsIdle
                or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
                or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then return end
            if data.MizukiEchoCannon == true then
                local shot = data.MizukiEchoShot
                if data.MizukiEchoAwaitingShot or not shot or not shot.ReplayFrame
                    or shot.Removed or shot.FadeFrame or data.MizukiEchoKnifeMode then return end
            end
            position = Mizuki.getFetusContactGridTarget(familiar.Position, familiar.Size)
        else
            position = Mizuki.getFetusContactGridTarget(attack.Position, attack.Size)
        end
        if not position then return end
        local hash = GetPtrHash(attack)
        -- Defer until native enemy damage has run, just like Epic Fetus's grid
        -- candidate. An enemy proc and a grid proc cannot spend two bombs.
        pendingGridBombs[hash] = {
            Entity = attack, Seed = attack.InitSeed, Hash = hash,
            Player = player, PlayerSeed = player.InitSeed, PlayerHash = GetPtrHash(player),
            Position = Vector(position.X, position.Y), Frame = Game():GetFrameCount(),
        }
    end

    function Mizuki:FinalizeFirstHitFetusGridBombs()
        local candidates = pendingGridBombs
        pendingGridBombs = {}
        local frame = Game():GetFrameCount()
        for _, candidate in pairs(candidates) do
            local attack, player = candidate.Entity, candidate.Player
            if candidate.Frame == frame and attack:Exists() and attack.InitSeed == candidate.Seed
                and GetPtrHash(attack) == candidate.Hash and player:Exists()
                and player.InitSeed == candidate.PlayerSeed and GetPtrHash(player) == candidate.PlayerHash
                and Mizuki.isMizuki(player)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
                spawnFirstHitBomb(attack, player, candidate.Position)
            end
        end
    end

    for _, callback in ipairs({ModCallbacks.MC_POST_LASER_UPDATE, ModCallbacks.MC_POST_KNIFE_UPDATE,
        ModCallbacks.MC_POST_TEAR_UPDATE, ModCallbacks.MC_POST_EFFECT_UPDATE, ModCallbacks.MC_FAMILIAR_UPDATE}) do
        Mizuki:AddCallback(callback, Mizuki.QueueFirstHitFetusGridBomb)
    end
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, Mizuki.FinalizeFirstHitFetusGridBombs)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() pendingGridBombs = {} end)
end

-- region Kidney Stone
do
    -- Kidney Stone: detect the native Tears spike, preserve its automatic shooting
    -- intent, and make charge-based Mizuki weapons release at full charge. The
    -- final Tears stat independently decides whether sustained-beam mode activates.
    --
    -- Extracted from main.lua. main publishes the helpers this file needs on the
    -- Mizuki table; the functions below are published there in turn for the code
    -- that stayed behind.

    local KIDNEY_STONE_TRIGGER_FIRE_RATE_RATIO = 4
    local KIDNEY_STONE_MIN_BURST_FRAMES = 150
    local KIDNEY_STONE_MAX_BURST_FRAMES = 190
    local KIDNEY_STONE_STABLE_FRAMES = 2
    local KIDNEY_STONE_FIRE_DELAY_EPSILON = 0.001

    local function updateKidneyStoneBurst(player, data)
        local currentMaxFireDelay = player.MaxFireDelay
        local previousMaxFireDelay = data.MizukiKidneyStoneLastMaxFireDelay
        data.MizukiKidneyStoneLastMaxFireDelay = currentMaxFireDelay

        if not player:HasCollectible(CollectibleType.COLLECTIBLE_KIDNEY_STONE) then
            data.MizukiKidneyStoneBurst = nil
            return nil
        end

        local burst = data.MizukiKidneyStoneBurst
        if not burst and previousMaxFireDelay ~= nil then
            local previousInterval = previousMaxFireDelay + 1
            local currentInterval = currentMaxFireDelay + 1
            if previousInterval / math.max(currentInterval, Mizuki.RuntimeParameters.MinimumFireInterval)
                >= KIDNEY_STONE_TRIGGER_FIRE_RATE_RATIO
            then
                burst = {
                    Elapsed = 0,
                    StableFrames = 0,
                    LastMaxFireDelay = currentMaxFireDelay,
                    Direction = data.MizukiLastShootDirection,
                }
                data.MizukiKidneyStoneBurst = burst
            end
        end

        if not burst then
            return nil
        end

        local aim = player:GetAimDirection()
        if aim:Length() > Mizuki.RuntimeParameters.AimDeadZone then
            burst.Direction = aim:Normalized()
            data.MizukiLastShootDirection = burst.Direction
        end

        if burst.Elapsed > 0 then
            if math.abs(currentMaxFireDelay - burst.LastMaxFireDelay)
                <= KIDNEY_STONE_FIRE_DELAY_EPSILON
            then
                burst.StableFrames = burst.StableFrames + 1
            else
                burst.StableFrames = 0
            end
        end
        burst.LastMaxFireDelay = currentMaxFireDelay
        burst.Elapsed = burst.Elapsed + 1

        local naturallyFinished = burst.Elapsed >= KIDNEY_STONE_MIN_BURST_FRAMES
            and burst.StableFrames >= KIDNEY_STONE_STABLE_FRAMES
        local timedOut = burst.Elapsed >= KIDNEY_STONE_MAX_BURST_FRAMES
        if naturallyFinished or timedOut then
            data.MizukiKidneyStoneBurst = nil
            return nil
        end

        return burst
    end

    Mizuki.updateKidneyStoneBurst = updateKidneyStoneBurst
end
-- endregion Kidney Stone

-- region Isaacs Tears
do
    -- Isaac's Tears charging from the beam's own damage ticks.
    --
    -- Extracted from main.lua. main publishes the helpers this file needs on the
    -- Mizuki table; the functions below are published there in turn for the code
    -- that stayed behind.

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
    local function updateIsaacsTearsCharge(player, data)
        local slot = nil
        -- Primary only: an off-hand active never charges, so charging one here
        -- would be inventing behaviour the game does not have.
        if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
            == CollectibleType.COLLECTIBLE_ISAACS_TEARS
        then
            slot = ActiveSlot.SLOT_PRIMARY
        end

        if not slot or not hasActiveMizukiBeam(data) then
            data.MizukiTearsChargeRolls = nil
            return
        end

        local banked = (data.MizukiTearsChargeRolls or 0)
            + countBeamDamageRolls(data)
        local charges = math.floor(banked / CHARGE_ROLLS_PER_TICK)
        data.MizukiTearsChargeRolls = banked % CHARGE_ROLLS_PER_TICK
        if charges < 1 then
            return
        end

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
    local markedEnemies = {}

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
        if data.MizukiIsIdle or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            or not player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
            data.MizukiSpecialBrimstoneCurse = false
            data.MizukiSpecialBrimstoneContactNext = nil
            return
        end
        local frame = Game():GetFrameCount()
        if not data.MizukiSpecialBrimstoneContactNext or frame >= data.MizukiSpecialBrimstoneContactNext then
            Mizuki.rollSpecialBrimstone(cannon, player)
            data.MizukiSpecialBrimstoneContactNext = frame + math.max(1, player.MaxFireDelay + 1)
        end
    end

    local function markEnemy(enemy)
        if enemy:HasEntityFlags(EntityFlag.FLAG_NO_STATUS_EFFECTS) then return end
        local hash = GetPtrHash(enemy)
        local record = markedEnemies[hash]
        if record and record.Seed ~= enemy.InitSeed then record = nil end
        if not record then
            -- Leave a status already owned by the native game or another mod alone.
            if enemy:HasEntityFlags(MARK) then return end
            record = {Entity = enemy, Seed = enemy.InitSeed}
            markedEnemies[hash] = record
        end
        record.Expires = Game():GetFrameCount() + MARK_FRAMES
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
        local hash = GetPtrHash(enemy)
        local record = markedEnemies[hash]
        if not record then return end
        if record.Seed ~= enemy.InitSeed or enemy:IsDead() then markedEnemies[hash] = nil; return end
        if Game():GetFrameCount() >= record.Expires then
            enemy:ClearEntityFlags(MARK)
            markedEnemies[hash] = nil
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

    function Mizuki.renderSpecialBrimstoneIcon(entity, worldPosition, renderOffset, alpha)
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
        local position = Isaac.WorldToScreen(worldPosition) + (renderOffset or Vector.Zero)
            - room:GetRenderScrollOffset() - Game().ScreenShakeOffset + Vector(0, -16)
        sprite:Render(position, Vector.Zero, Vector.Zero)
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_RENDER, function(_, tear, offset)
        if tear:GetData().MizukiFanFetus == true then
            Mizuki.renderSpecialBrimstoneIcon(tear, tear.Position + tear.PositionOffset, offset)
        end
    end)
    Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_RENDER, function(_, bomb, offset)
        Mizuki.renderSpecialBrimstoneIcon(bomb, bomb.Position + bomb.PositionOffset, offset)
    end)
    Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, function(_, rocket, offset)
        if rocket:GetData().MizukiSpecialBrimstoneAttack then
            Mizuki.renderSpecialBrimstoneIcon(rocket, rocket.Position + rocket.PositionOffset, offset)
        end
    end, EffectVariant.ROCKET)

    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() markedEnemies = {} end)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() markedEnemies = {} end)
end

-- region Moms Wig
do
    -- Real attack notifications are grouped by side, not by projectile count.
    local PERIOD = Mizuki.BEAM_DAMAGE_INTERVAL * 2
    local getState
    local function canRoll(player)
        return Mizuki.isMizuki(player) and not Game():IsPaused() and not player:IsDead()
            and player:AreControlsEnabled() and player:IsExtraAnimationFinished()
            and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG)
    end
    local function roll(player, channel)
        if not canRoll(player) then return end
        local state, frame = getState(player), Game():GetFrameCount()
        local previous = state.Attempts[channel]
        if previous and frame >= previous and frame - previous < PERIOD then return end
        -- Failed rolls consume the same minimum interval. Rewinds discard a future
        -- attempt rather than locking the player to the abandoned timeline.
        state.Attempts[channel] = frame
        local twiceLuck = player.Luck * 2
        local steps = twiceLuck < 0 and math.ceil(twiceLuck) or math.floor(twiceLuck)
        local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_MOMS_WIG)
        if rng:RandomInt(math.max(1, 20 - steps)) ~= 0 then return end
        local hive = CollectibleType.COLLECTIBLE_HIVE_MIND
        local cap = (player:HasCollectible(hive)
            or player:GetEffects():HasCollectibleEffect(hive)) and 10 or 5
        if player:GetNumBlueSpiders() >= cap then return end
        -- Vanilla Wig passes a zero target: native code chooses a free landing
        -- position and adds scatter. An explicit target bypasses that selection.
        player:ThrowBlueSpider(player.Position, Vector.Zero)
    end
    getState = function(player)
        local data = player:GetData()
        if not data.MizukiMomsWigState or not data.MizukiMomsWigState.Attempts then
            data.MizukiMomsWigState = { Shots = {}, Clocks = {}, Attempts = {} }
        end
        return data.MizukiMomsWigState
    end
    local function controlledMode(player, data)
        if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then return end
        local ring = data.MizukiLudovicoTechXProbe
        if ring and ring:Exists()
            and player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
            return "controlled"
        end
        if Mizuki.getTargetReticle(player, data) then return "controlled" end
    end
    local function originalBeam(data, side, beam)
        local cannon = data.MizukiCannons and data.MizukiCannons[side]
            and data.MizukiCannons[side][1]
        return cannon and cannon:Exists() and beam.Cannon == cannon
            and not beam.PersistentEchoMode
            and not cannon:GetData().MizukiGuillotineNonFiring
    end
    local function liveBeam(beam)
        return beam.Laser and beam.Laser:Exists()
    end
    -- The controller calls once after the whole volley exists. Only the primary
    -- pair counts; Box of Friends, extra familiars and echoes do not add procs.
    function Mizuki.recordMomsWigAttack(player, beams, automatic, periodic, duration, echo)
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
                else roll(player, side) end
            end
        end
    end
    -- Real gbt volleys report here. Echo replay calls fireFanFetus directly;
    -- simultaneous familiar copies share one player opportunity.
    function Mizuki.recordMomsWigFanVolley(player)
        if not canRoll(player) then return end
        roll(player, "fan")
    end
    local function advanceClock(player, state, side, mode, interval)
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
            roll(player, side)
        end
    end
    function Mizuki:UpdateMomsWig(player)
        if not Mizuki.isMizuki(player) then return end
        local data = player:GetData()
        if player:IsDead() or not player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG) then
            data.MizukiMomsWigState = nil
            return
        end
        if not canRoll(player) then return end
        local state, frame = getState(player), Game():GetFrameCount()
        if state.LastFrame == frame then return end
        state.LastFrame = frame
        if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
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
                if shot.Elapsed <= shot.Duration and shot.Elapsed % PERIOD == 0 then roll(player, shot.Side) end
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
            elseif source and source.Automatic then
                clockMode, interval = "continuous", PERIOD
            end
            if interval then advanceClock(player, state, side, clockMode, interval)
            else state.Clocks[side] = nil end
        end
    end
    local function reset()
        for index = 0, Game():GetNumPlayers() - 1 do
            local data = Isaac.GetPlayer(index):GetData()
            data.MizukiMomsWigState = nil
        end
    end
    function Mizuki.registerMomsWigCallbacks()
        Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateMomsWig)
        Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, reset)
        Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, reset)
    end
end
-- endregion Moms Wig

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
    -- Tech .5 is the player's forehead weapon and never enters cannon/fan echoes.
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
        -- Offset 2 owns the native forehead origin and Repentance+ 5% random-effect
        -- branch. Do not reroll, replace flags/colors, or turn this into a cannon beam.
        local head = Mizuki.getGuillotineHeads(player)[1]
        -- FireTechLaser itself adds TearsOffset, including native Guillotine
        -- displacement. Cancel it in the requested origin instead of adding twice.
        local origin = head and (head.Position - player.TearsOffset) or player.Position
        local laser = player:FireTechLaser(origin, LaserOffset.LASER_TECH5_OFFSET,
            direction, false, true, player, 1)
        -- Native samples enter their fade around age 2 and disappear at age 4-5.
        -- Set only the active timeout; the engine owns the fade and removal.
        laser.Timeout = parameters.ActiveFrames
        -- Raise Tech .5's native forehead beam by two screen pixels.
        laser.PositionOffset = laser.PositionOffset + Vector(0, -2)
        if target then
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
