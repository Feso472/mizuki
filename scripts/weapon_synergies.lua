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
