-- Birthright: pickup transactions, doctorate offers and the three-Boss challenge.
-- Sections keep private state separate without scattering one feature across files.

-- region Doctorate offers
do
    -- Birthright never grants a doctorate directly. All collectible pools can
    -- offer one through a 10%, +10 percentage-point replacement roll. A success
    -- resets the chance. Inventory is sampled only on acquisition; generating
    -- an enabled doctorate closes that offer for the rest of the run.
    -- The pickup-room Boss challenge is independent of doctorate ownership.
    local json = require("json")

    local BIRTHRIGHT = CollectibleType.COLLECTIBLE_BIRTHRIGHT
    local PHD = CollectibleType.COLLECTIBLE_PHD
    local FALSE_PHD = CollectibleType.COLLECTIBLE_FALSE_PHD
    local INITIAL_DOCTORATE_CHANCE = 10
    local DOCTORATE_CHANCE_STEP = 10
    local FALSE_PHD_SHARE = 0.10
    local DOCTORATE_SAVE_VERSION = 3
    local DOCTORATE_FLAGS = { PHD = 1, FalsePHD = 2 }
    local ALL_DOCTORATES = DOCTORATE_FLAGS.PHD | DOCTORATE_FLAGS.FalsePHD

    -- Item-pool rolls belong to the shared run, not an individual co-op player.
    -- Use integer percentage points so the tenth roll reaches exactly 100%.
    local doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
    local birthrightStateReady = false
    local enabledDoctorates = 0
    local resolvedDoctorates = 0
    -- Reserve an unconfirmed result only within its draw frame. The pickup
    -- callbacks commit generation; unused queries must not consume an offer.
    local pendingDoctorates = {}

    local function getDoctorateMask(player)
        return (player:HasCollectible(PHD) and DOCTORATE_FLAGS.PHD or 0)
            + (player:HasCollectible(FALSE_PHD) and DOCTORATE_FLAGS.FalsePHD or 0)
    end

    local function isMizuki(player)
        return player:GetPlayerType() == Mizuki.PlayerType
    end

    local function enableDoctoratesForAcquisition(player)
        local missing = ALL_DOCTORATES & ~getDoctorateMask(player)
        enabledDoctorates = (enabledDoctorates | missing) & ~resolvedDoctorates
    end

    local function seedLegacyEligibility()
        -- Older saves have no generation history. Migrate once from inventory;
        -- never invent a pickup event or replay the Boss portal.
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if isMizuki(player) and player:HasCollectible(BIRTHRIGHT) then
                enableDoctoratesForAcquisition(player)
            end
        end
    end

    local function readSaveRoot()
        if not Mizuki:HasData() then return {} end
        local ok, root = pcall(json.decode, Mizuki:LoadData())
        return ok and type(root) == "table" and root or {}
    end

    local function restoreDoctorateChance()
        doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
        enabledDoctorates, resolvedDoctorates, pendingDoctorates = 0, 0, {}
        local saved = readSaveRoot().Birthright
        if type(saved) == "table" and (saved.version == 2 or saved.version == DOCTORATE_SAVE_VERSION) then
            doctorateChancePercent = math.max(INITIAL_DOCTORATE_CHANCE,
                math.min(Mizuki.RuntimeParameters.PercentScale, tonumber(saved.doctorateChancePercent) or INITIAL_DOCTORATE_CHANCE))
        end
        if type(saved) == "table" and saved.version == DOCTORATE_SAVE_VERSION then
            resolvedDoctorates = math.floor(tonumber(saved.resolvedDoctorates) or 0) & ALL_DOCTORATES
            enabledDoctorates = math.floor(tonumber(saved.enabledDoctorates) or 0)
                & ALL_DOCTORATES & ~resolvedDoctorates
        else
            seedLegacyEligibility()
        end
        birthrightStateReady = true
    end

    local function saveBirthrightState()
        if not birthrightStateReady then restoreDoctorateChance() end
        local root = readSaveRoot()
        root.Birthright = {
            version = DOCTORATE_SAVE_VERSION, doctorateChancePercent = doctorateChancePercent,
            enabledDoctorates = enabledDoctorates, resolvedDoctorates = resolvedDoctorates,
        }
        Mizuki:SaveData(json.encode(root))
    end

    local function doctorateFlag(collectible)
        if collectible == PHD then return DOCTORATE_FLAGS.PHD end
        if collectible == FALSE_PHD then return DOCTORATE_FLAGS.FalsePHD end
        return 0
    end

    local function observeGeneratedDoctorate(_, pickup)
        if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
        local flag = doctorateFlag(pickup.SubType)
        if flag == 0 then return end
        if not birthrightStateReady then restoreDoctorateChance() end
        if (enabledDoctorates & flag) == 0 then return end
        enabledDoctorates = enabledDoctorates & ~flag
        resolvedDoctorates = resolvedDoctorates | flag
        pendingDoctorates[flag] = nil
        doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
        saveBirthrightState()
    end

    function Mizuki.HasCompletedBirthright()
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if isMizuki(player) and player:HasCollectible(BIRTHRIGHT)
                and player:HasCollectible(PHD) and player:HasCollectible(FALSE_PHD) then
                return true
            end
        end
        return false
    end

    function Mizuki.HasBirthright()
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            if isMizuki(player) and player:HasCollectible(BIRTHRIGHT) then return true end
        end
        return false
    end

    local function isBirthrightQueued(player)
        if player:IsItemQueueEmpty() then return false end
        local queued = player.QueuedItem
        local item = queued and queued.Item
        return item ~= nil and item.ID == BIRTHRIGHT and item.Type ~= ItemType.ITEM_TRINKET
    end

    local function seedAcquisitionState(player)
        -- Entity data survives a Lua reload; a fresh observer must only establish
        -- a baseline, never invent an acquisition from existing inventory/queues.
        local state = {
            Count = player:GetCollectibleNum(BIRTHRIGHT),
            Queued = isBirthrightQueued(player),
            Frame = Game():GetFrameCount(),
        }
        player:GetData().MizukiBirthrightAcquisition = state
        return state
    end

    local function updateBirthrightAcquisition(_, player)
        if not birthrightStateReady then restoreDoctorateChance() end
        if player.Variant ~= 0 or not isMizuki(player) then return end
        local frame = Game():GetFrameCount()
        local state = player:GetData().MizukiBirthrightAcquisition
        if not state or frame < state.Frame then
            seedAcquisitionState(player)
            return
        end
        local count = player:GetCollectibleNum(BIRTHRIGHT)
        local queued = isBirthrightQueued(player)
        if queued and not state.Queued then
            state.PickupCountBefore = state.Count
        end
        local completedPickup = not queued and state.PickupCountBefore ~= nil
            and count > state.PickupCountBefore
        if not queued then state.PickupCountBefore = nil end
        state.Count, state.Queued, state.Frame = count, queued, frame
        -- Commit the observation before invoking effects, so reentrant updates
        -- and subsequent frames cannot consume the same queue transaction twice.
        if completedPickup then
            enableDoctoratesForAcquisition(player)
            doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
            saveBirthrightState()
            Mizuki.QueueBirthrightBossChain(player)
        end
    end

    local function injectDoctorate(_, collectible, poolType, decrease, seed)
        if not birthrightStateReady then restoreDoctorateChance() end
        if decrease == false or not Mizuki.HasBirthright() then return end
        local frame = Game():GetFrameCount()
        local needPHD = (enabledDoctorates & DOCTORATE_FLAGS.PHD) ~= 0
            and pendingDoctorates[DOCTORATE_FLAGS.PHD] ~= frame
        local needFalsePHD = (enabledDoctorates & DOCTORATE_FLAGS.FalsePHD) ~= 0
            and pendingDoctorates[DOCTORATE_FLAGS.FalsePHD] ~= frame
        if not needPHD and not needFalsePHD then return end
        -- Leave natural doctorates intact, even if their extra offer is closed.
        -- Reserve the selected kind until its actual pickup confirms generation.
        local selectedFlag = doctorateFlag(collectible)
        if selectedFlag ~= 0 then
            if (enabledDoctorates & selectedFlag) ~= 0 then
                pendingDoctorates[selectedFlag] = frame
            end
            return
        end

        local rng = RNG()
        rng:SetSeed(seed == 0 and 1 or seed, Mizuki.RuntimeParameters.RngShiftIndex)
        if rng:RandomFloat() < doctorateChancePercent / Mizuki.RuntimeParameters.PercentScale then
            local result
            if needPHD and needFalsePHD then
                result = rng:RandomFloat() < FALSE_PHD_SHARE and FALSE_PHD or PHD
            else
                result = needPHD and PHD or FALSE_PHD
            end
            pendingDoctorates[doctorateFlag(result)] = frame
            doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
            saveBirthrightState()
            return result
        end
        doctorateChancePercent = math.min(Mizuki.RuntimeParameters.PercentScale, doctorateChancePercent + DOCTORATE_CHANCE_STEP)
        saveBirthrightState()
    end

    local function initializeBirthright(_, isContinued)
        doctorateChancePercent = INITIAL_DOCTORATE_CHANCE
        enabledDoctorates, resolvedDoctorates, pendingDoctorates = 0, 0, {}
        birthrightStateReady = true
        if isContinued then
            restoreDoctorateChance()
        else
            seedLegacyEligibility() -- Starting items count as the initial acquisition.
        end
        for index = 0, Game():GetNumPlayers() - 1 do
            seedAcquisitionState(Isaac.GetPlayer(index))
        end
        saveBirthrightState()
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, updateBirthrightAcquisition)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, injectDoctorate)
    Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, observeGeneratedDoctorate,
        PickupVariant.PICKUP_COLLECTIBLE)
    -- Morph/reroll and late-initialized subtypes do not always issue a new init.
    -- Closing is idempotent: once closed, updates cannot reset chance or resave.
    Mizuki:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, observeGeneratedDoctorate,
        PickupVariant.PICKUP_COLLECTIBLE)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, initializeBirthright)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, saveBirthrightState)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_END, saveBirthrightState)
end
-- endregion Doctorate offers

-- region Boss rewards
do
    -- Mizuki Birthright's carried Boss rewards.
    --
    -- A Boss clear arms one pending reward event. The first collectible pedestal
    -- spawned by that native award confirms that this room really has an item
    -- reward; one complete logic frame later Damocles has finished duplicating it,
    -- so the previous offers can be restored beside the new native reward. The
    -- sequence is A -> A+B -> A+B+C; this effect never draws from an item pool.

    local pendingBossReward

    local AWARD_CONFIRM_TIMEOUT_FRAMES = 2
    local PEDESTAL_SPACING = 80
    local SIDE_GAP = 80
    local MAX_OUTWARD_STEPS = 8
    local PEDESTAL_EDGE_MARGIN = 20
    local PEDESTAL_OBSTACLE_PADDING = 20

    local function birthrightIsHeld()
        return Mizuki.HasBirthright()
    end

    local function hasTheresOptions()
        local game = Game()
        for index = 0, game:GetNumPlayers() - 1 do
            if Isaac.GetPlayer(index):HasCollectible(
                CollectibleType.COLLECTIBLE_THERES_OPTIONS
            ) then
                return true
            end
        end
        return false
    end

    local function getCollectiblePedestals()
        local pedestals = {}
        for _, entity in ipairs(Isaac.FindByType(
            EntityType.ENTITY_PICKUP,
            PickupVariant.PICKUP_COLLECTIBLE
        )) do
            local pickup = entity:ToPickup()
            if pickup and pickup.SubType > 0 then
                table.insert(pedestals, pickup)
            end
        end
        return pedestals
    end

    local function getUniqueOptionsIndex()
        local usedIndices = {}
        for _, pickup in ipairs(getCollectiblePedestals()) do
            if pickup.OptionsPickupIndex > 0 then
                usedIndices[pickup.OptionsPickupIndex] = true
            end
        end

        local optionsIndex = 1
        while usedIndices[optionsIndex] do
            optionsIndex = optionsIndex + 1
        end
        return optionsIndex
    end

    local function positionIsSeparated(position)
        for _, pickup in ipairs(getCollectiblePedestals()) do
            local delta = position - pickup.Position
            if math.abs(delta.X) < PEDESTAL_SPACING
                and math.abs(delta.Y) < PEDESTAL_SPACING
            then
                return false
            end
        end
        return true
    end

    local function isRemovableRewardGrid(gridType)
        return gridType == GridEntityType.GRID_ROCK
            or gridType == GridEntityType.GRID_ROCKB
            or gridType == GridEntityType.GRID_ROCKT
            or gridType == GridEntityType.GRID_ROCK_BOMB
            or gridType == GridEntityType.GRID_ROCK_ALT
            or gridType == GridEntityType.GRID_ROCK_SS
            or gridType == GridEntityType.GRID_ROCK_SPIKED
            or gridType == GridEntityType.GRID_ROCK_ALT2
            or gridType == GridEntityType.GRID_ROCK_GOLD
            or gridType == GridEntityType.GRID_SPIKES
            or gridType == GridEntityType.GRID_SPIKES_ONOFF
            or gridType == GridEntityType.GRID_SPIDERWEB
            or gridType == GridEntityType.GRID_TNT
            or gridType == GridEntityType.GRID_POOP
            or gridType == GridEntityType.GRID_FIREPLACE
    end

    local function clearRewardPosition(room, position)
        -- Reward anchors are grid-aligned. Pits use the engine's normal bridge
        -- state and default bridge texture; other removable grids use the native
        -- non-immediate destruction path so their breaking animation is visible.
        local gridIndex = room:GetGridIndex(position)
        local gridEntity = room:GetGridEntity(gridIndex)
        if gridEntity then
            local pit = gridEntity:ToPit()
            if pit then
                -- Repentance+ requires the rock type as a second argument so it
                -- can distinguish ordinary and spiked bridges. With no source
                -- grid, the engine still uses its default bridge texture.
                pit:MakeBridge(nil, GridEntityType.GRID_ROCK)
            elseif isRemovableRewardGrid(gridEntity:GetType()) then
                room:DestroyGrid(gridIndex, false)
            end
        end

        -- These blockers are entities rather than grid entities. Restrict removal
        -- to the explicit obstacle types occupying the pedestal itself; players,
        -- familiars, pickups and scripted room entities are never touched here.
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local removable = entity.Type == EntityType.ENTITY_FIREPLACE
                or entity.Type == EntityType.ENTITY_MOVABLE_TNT
                or entity.Type == EntityType.ENTITY_SLOT
            if removable
                and entity.Position:Distance(position) < entity.Size + PEDESTAL_OBSTACLE_PADDING
            then
                entity:Die()
            end
        end
    end

    local function getCarriedRewardSlots(nativeSpawnPosition, carriedRewards)
        local slots = {}
        for index, reward in ipairs(carriedRewards) do
            local direction = index % 2 == 1 and -1 or 1
            table.insert(slots, {
                position = Vector(nativeSpawnPosition.X
                    + direction * (SIDE_GAP + (math.ceil(index / 2) - 1) * PEDESTAL_SPACING),
                    nativeSpawnPosition.Y),
                direction = direction,
                reward = reward,
            })
        end
        return slots
    end

    local function prepareBossRewardArea(room, nativeSpawnPosition, carriedRewards)
        -- Reserve the native anchor and all extra anchors before the engine spawns
        -- its reward. This lets grid destruction/bridging begin before either the
        -- pedestals or the later Boss portal are created.
        clearRewardPosition(room, nativeSpawnPosition)
        if hasTheresOptions() then
            clearRewardPosition(
                room,
                nativeSpawnPosition + Vector(-PEDESTAL_SPACING * 0.5, 0)
            )
            clearRewardPosition(
                room,
                nativeSpawnPosition + Vector(PEDESTAL_SPACING * 0.5, 0)
            )
        end
        local slots = getCarriedRewardSlots(nativeSpawnPosition, carriedRewards)
        for _, slot in ipairs(slots) do
            if room:IsPositionInRoom(slot.position, PEDESTAL_EDGE_MARGIN) then
                clearRewardPosition(room, slot.position)
            end
        end
    end

    local function findSeparatedSidePosition(
        room,
        target,
        sideDirection
    )
        -- Environment obstacles no longer push rewards onto another row. Only an
        -- existing collectible or the room boundary may move a new pedestal, and
        -- that movement stays horizontal like the original reward row.
        for outwardStep = 0, MAX_OUTWARD_STEPS do
            local candidate = target + Vector(
                sideDirection * outwardStep * PEDESTAL_SPACING,
                0
            )
            if room:IsPositionInRoom(candidate, PEDESTAL_EDGE_MARGIN)
                and positionIsSeparated(candidate)
            then
                if outwardStep > 0 then
                    clearRewardPosition(room, candidate)
                end
                return candidate
            end
        end

        -- This should only be reachable in an unusually narrow room packed with
        -- collectible pedestals. Keep the exceptional fallback on the same row.
        Isaac.DebugString(
            "[Mizuki] Boss reward side position used clamped fallback"
        )
        local fallback = room:GetClampedPosition(target, PEDESTAL_EDGE_MARGIN)
        clearRewardPosition(room, fallback)
        return fallback
    end

    local function restoreCarriedBossRewards(room, nativeSpawnPosition, carriedRewards)
        local slots = getCarriedRewardSlots(nativeSpawnPosition, carriedRewards)
        local optionGroups = {}
        for _, slot in ipairs(slots) do
            local reward = slot.reward
            local optionsIndex = 0
            if reward.optionsIndex > 0 then
                -- An old choice group must not merge with the new native award,
                -- which often reuses the same OptionsPickupIndex on each boss.
                optionsIndex = optionGroups[reward.optionsIndex]
                if not optionsIndex then
                    optionsIndex = getUniqueOptionsIndex()
                    optionGroups[reward.optionsIndex] = optionsIndex
                end
            end
            local spawnPosition = findSeparatedSidePosition(
                room,
                slot.position,
                slot.direction
            )
            local pickup = Isaac.Spawn(
                EntityType.ENTITY_PICKUP,
                PickupVariant.PICKUP_COLLECTIBLE,
                reward.collectible,
                spawnPosition,
                Vector.Zero,
                nil
            ):ToPickup()
            -- This is a transfer, not another new award. Already-seen Damocles
            -- copies are included in the snapshot and must not duplicate again.
            pickup:ClearEntityFlags(EntityFlag.FLAG_ITEM_SHOULD_DUPLICATE)
            pickup.OptionsPickupIndex = optionsIndex
            pickup.Charge = reward.charge
            pickup.Touched = reward.touched
            pickup.ShopItemId = reward.shopItemId
            pickup.Price = reward.price
            pickup.AutoUpdatePrice = reward.autoUpdatePrice
        end
    end

    local function beginBossRewardEvent(_, rng, spawnPosition)
        local game = Game()
        local room = game:GetRoom()
        if room:GetType() ~= RoomType.ROOM_BOSS
            or not birthrightIsHeld()
        then
            return
        end

        -- Each boss supplies one new native award. Restore the exact offers that
        -- were left behind in the previous round, without rerolling any of them.
        local chainStage = Mizuki.GetBirthrightBossChainStage()
        local carriedRewards = Mizuki.GetBirthrightCarriedRewards()
        if not chainStage or not carriedRewards or #carriedRewards == 0 then return end

        prepareBossRewardArea(room, spawnPosition, carriedRewards)

        pendingBossReward = {
            awardFrame = game:GetFrameCount(),
            spawnPosition = Vector(spawnPosition.X, spawnPosition.Y),
            observedPickups = {},
            chainStage = chainStage,
            carriedRewards = carriedRewards,
        }
    end

    local function observeBossRewardPickup(_, pickup)
        if not pendingBossReward then
            return
        end

        -- MC_POST_PICKUP_INIT is used only as an existence signal. Several pickup
        -- fields are not final during this callback, and no placement work is done
        -- until a later update.
        local event = pendingBossReward
        table.insert(event.observedPickups, {
            entity = pickup,
            ptrHash = GetPtrHash(pickup),
            initSeed = pickup.InitSeed,
        })
        event.confirmedFrame = event.confirmedFrame
            or Game():GetFrameCount()
    end

    function Mizuki.RestoreBirthrightRoomRewardsAfterContinue()
        local room = Game():GetRoom()
        if room:GetType() ~= RoomType.ROOM_BOSS or not room:IsClear() then return end
        local snapshot = Mizuki.GetBirthrightRoomRewardSnapshot()
        if not snapshot then return end

        local existing = getCollectiblePedestals()
        local matched, used = {}, {}
        -- Match all native identities first, then allow an identical saved offer at
        -- its saved position if the engine recreated it with a different seed.
        -- Each live entity can satisfy only one record (including duplicate IDs).
        for pass = 1, 2 do
            for index, reward in ipairs(snapshot) do
                if not matched[index] then
                    for _, pickup in ipairs(existing) do
                        local sameIdentity = pickup.InitSeed == reward.initSeed
                        local sameOffer = pickup.OptionsPickupIndex == reward.optionsIndex
                            and pickup.Position:DistanceSquared(Vector(reward.x, reward.y)) < 1
                        if not used[pickup] and pickup:Exists()
                            and pickup.SubType == reward.collectible
                            and ((pass == 1 and sameIdentity) or (pass == 2 and sameOffer)) then
                            matched[index], used[pickup] = true, true
                            break
                        end
                    end
                end
            end
        end
        for index, reward in ipairs(snapshot) do
            if not matched[index] then
                local pickup = Isaac.Spawn(
                    EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
                    reward.collectible, Vector(reward.x, reward.y), Vector.Zero, nil
                ):ToPickup()
                -- Recreate a saved offer, not a fresh award or a new choice group.
                pickup:ClearEntityFlags(EntityFlag.FLAG_ITEM_SHOULD_DUPLICATE)
                pickup.OptionsPickupIndex = reward.optionsIndex
                pickup.Charge = reward.charge
                pickup.Touched = reward.touched
                pickup.ShopItemId = reward.shopItemId
                pickup.Price = reward.price
                pickup.AutoUpdatePrice = reward.autoUpdatePrice
            end
        end
    end

    function Mizuki.RestoreBirthrightRewardsAfterContinue()
        -- A save may have happened after the native pedestal appeared but before
        -- the deferred transfer, or may contain legacy offers with repaired round
        -- keys. Resume only in a cleared challenge with an existing native award;
        -- never spawn another native award or invent/reroll carried items.
        if not Game():GetRoom():IsClear() then return end
        local pickups = Isaac.FindByType(
            EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE)
        local anchor
        for _, pickup in ipairs(pickups) do
            if pickup:Exists() and pickup.SubType > 0 then
                anchor = pickup.Position
                break
            end
        end
        if not anchor then return end
        beginBossRewardEvent(nil, nil, anchor)
        if pendingBossReward then
            for _, pickup in ipairs(pickups) do
                if pickup:Exists() then observeBossRewardPickup(nil, pickup) end
            end
        end
    end

    local function getRewardRowAnchor(event)
        local closestPosition
        local closestDistance
        for _, identity in ipairs(event.observedPickups) do
            local pickup = identity.entity
            if pickup
                and pickup:Exists()
                and GetPtrHash(pickup) == identity.ptrHash
                and pickup.InitSeed == identity.initSeed
            then
                local distance = pickup.Position:DistanceSquared(
                    event.spawnPosition
                )
                if closestDistance == nil or distance < closestDistance then
                    closestDistance = distance
                    closestPosition = pickup.Position
                end
            end
        end

        if not closestPosition then
            return event.spawnPosition
        end

        -- The callback position is the centre of the native choice group, while
        -- the actual initialized pedestal provides its final row after the engine's
        -- own free-position adjustment. Preserve the former X and the latter Y.
        return Vector(event.spawnPosition.X, closestPosition.Y)
    end

    local function processPendingBossReward()
        local event = pendingBossReward
        if not event then
            return
        end

        local game = Game()
        local currentFrame = game:GetFrameCount()
        if event.confirmedFrame == nil then
            if currentFrame > event.awardFrame + AWARD_CONFIRM_TIMEOUT_FRAMES then
                pendingBossReward = nil
            end
            return
        end

        -- Damocles marks the original pedestal during its spawn and creates the
        -- duplicate at the end of that logic frame. Waiting for a strictly later
        -- frame makes both native pedestals visible to the one-shot position search.
        if currentFrame <= event.confirmedFrame then
            return
        end

        -- Clear first: our own pickup-init callbacks and their later Damocles copies
        -- must never be mistaken for another native Boss reward.
        pendingBossReward = nil
        restoreCarriedBossRewards(
            game:GetRoom(),
            getRewardRowAnchor(event),
            event.carriedRewards
        )
        Mizuki.MarkBirthrightCarriedRewardsRestored(event.chainStage)
    end

    local function cancelPendingBossReward()
        pendingBossReward = nil
    end

    Mizuki:AddCallback(
        ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD,
        beginBossRewardEvent
    )
    Mizuki:AddCallback(
        ModCallbacks.MC_POST_PICKUP_INIT,
        observeBossRewardPickup,
        PickupVariant.PICKUP_COLLECTIBLE
    )
    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, processPendingBossReward)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, cancelPendingBossReward)
end
-- endregion Boss rewards

-- region Boss challenge
do
    -- Mizuki Birthright's pickup-triggered three-Boss-Room challenge.
    --
    -- Boss layouts are loaded from the vanilla special-room file with `goto` and
    -- fought in its native off-grid debug room. All three encounters
    -- reuse that room sequentially, keeping the engine-initialized descriptor,
    -- boss, terrain, room shape, and scripted room entities together.

    local bossChain = nil
    local lastChainStage = nil
    local pendingGeneration = nil
    local queuedCollectibles = {}
    local pendingBirthrightEntries = {}
    local json = require("json")
    local gameStarted = false
    local initializeBossChain
    local ROUND_MAP_KEYS = {"encounters", "temporaryDoorSlot", "clearFrameByStage",
        "rewardClaimed", "carriedRewards", "portalActive", "portalIdentities",
        "roomRewardSnapshots"}

    local function serializeBossChain()
        if not bossChain then return nil end
        local saved = {}
        for key, value in pairs(bossChain) do saved[key] = value end
        -- The game's JSON decoder drops null array entries. Explicit object keys
        -- keep sparse round numbers intact, even when another feature resaves root.
        -- Work on a snapshot; live room logic continues to use numeric round keys.
        for _, key in ipairs(ROUND_MAP_KEYS) do
            local rounds = {}
            for round, value in pairs(bossChain[key] or {}) do
                rounds[tostring(round)] = value
            end
            saved[key] = rounds
        end
        return saved
    end

    local function readSaveRoot()
        if not Mizuki:HasData() then return {} end
        local ok, root = pcall(json.decode, Mizuki:LoadData())
        return ok and type(root) == "table" and root or {}
    end

    local function saveBossChain()
        if not gameStarted then return end
        local level = Game():GetLevel()
        local root = readSaveRoot()
        root.BirthrightBossChain = {
            version = 2,
            stage = level:GetStage(), stageType = level:GetStageType(),
            stageSeed = Game():GetSeeds():GetStageSeed(level:GetStage()),
            chain = serializeBossChain(), entries = pendingBirthrightEntries, pending = pendingGeneration,
        }
        Mizuki:SaveData(json.encode(root))
    end

    local BOSS_ROOM_COUNT = 3
    local BOSS_ENCOUNTER_ROOM_SEED_FACTOR = 31
    local BOSS_ENCOUNTER_SEED_SALT = 9173
    local PORTAL_MIN_TOUCH_AGE_FRAMES = 5
    local DEBUG_ROOM_INDEX = GridRooms.ROOM_DEBUG_IDX
    local BOSS_PORTAL_SUBTYPE = 1
    local PORTAL_TRIGGER_RADIUS = 22
    local PORTAL_EDGE_MARGIN = 24
    local PORTAL_AFTER_CLEAR_DELAY_FRAMES = 15

    -- Vanilla special-room variants grouped by the same boss pools used in
    -- bosspools.xml. Double Trouble layouts and Difficulty-0 test layouts are
    -- deliberately omitted: one portal represents one natural Boss Room.
    local BRANCH_BOSS_POOLS = {
        downpour = {
            { bossId = 75, variants = { 5170, 5171, 5172, 5173, 5174, 5175 } },
            { bossId = 76, variants = { 5180, 5181, 5182, 5183, 5184, 5185 } },
            { bossId = 77, variants = { 5230, 5231, 5232, 5233, 5234 } },
            { bossId = 91, variants = { 5280, 5281, 5282, 5283 } },
        },
        dross = {
            { bossId = 75, variants = { 5170, 5171, 5172, 5173, 5174, 5175 } },
            { bossId = 76, variants = { 5180, 5181, 5182, 5183, 5184, 5185 } },
            { bossId = 92, variants = { 5190, 5191, 5192, 5193, 5194 } },
            { bossId = 95, variants = { 5330 } },
            { bossId = 97, variants = { 5320, 5321, 5322 } },
        },
        mines = {
            { bossId = 74, variants = { 5250, 5251, 5252, 5253, 5254, 5255, 5256 } },
            { bossId = 80, variants = { 5200, 5201, 5202, 5203, 5204, 5205, 5206, 5207 } },
            { bossId = 82, variants = { 5220, 5221, 5222, 5223, 5224, 5225, 5226, 5227, 5228, 5229 } },
            { bossId = 83, variants = { 5210, 5211, 5212, 5213, 5214 } },
        },
        ashpit = {
            { bossId = 73, variants = { 5240, 5241, 5242, 5243, 5244 } },
            { bossId = 83, variants = { 5210, 5211, 5212, 5213, 5214 } },
            { bossId = 93, variants = { 5260, 5261, 5262, 5263, 5264 } },
            { bossId = 96, variants = { 5310, 5311, 5312, 5313 } },
            { bossId = 102, variants = { 6020, 6021, 6022 } },
        },
        mausoleum = {
            { bossId = 79, variants = { 5370, 5371, 5372 } },
            { bossId = 81, variants = { 5290, 5291, 5292, 5293 } },
        },
        gehenna = {
            { bossId = 78, variants = { 5300, 5301 } },
            { bossId = 101, variants = { 6010, 6011, 6012 } },
        },
        corpse = {
            { bossId = 85, variants = { 5360, 5361, 5362 } },
            { bossId = 86, variants = { 5350, 5351, 5352 } },
            { bossId = 87, variants = { 5340 } },
        },
    }

    -- Main-path pools for the chapter immediately after the original Boss Room.
    -- Only naturally selectable single-Boss layouts are listed; vanilla Double
    -- Trouble variants (3700-3850) and Difficulty-0 test layouts are excluded.
    local NORMAL_BOSS_POOLS = {
        basement = {
            { bossId = 1, variants = { 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018, 1122, 1123, 1037, 1038, 1039, 1045 } },
            { bossId = 17, variants = { 2050, 2051, 2052, 2053 } },
            { bossId = 2, variants = { 1020, 1124, 1125, 1021, 1022, 1023, 1024, 1025, 1026, 1027, 1028, 1046, 1047 } },
            { bossId = 44, variants = { 5020, 5021, 5022, 5023, 5024, 5025 } },
            { bossId = 64, variants = { 1117, 1118, 1119, 1120, 1121 } },
            { bossId = 56, variants = { 5140, 5141, 5142, 5143, 5144 } },
            { bossId = 65, variants = { 5146, 5147, 5148, 5149, 5150, 5151 } },
            { bossId = 20, variants = { 2070, 2071, 2072, 2073 } },
            { bossId = 13, variants = { 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018 } },
            { bossId = 60, variants = { 1088, 1089, 1095, 1096, 5373, 5374 } },
            { bossId = 84, variants = { 5160, 5161, 5162, 5163, 5164, 5165 } },
        },
        caves = {
            { bossId = 3, variants = { 1030, 1126, 1127, 1031, 1032, 1033, 1034, 1055, 1056 } },
            { bossId = 4, variants = { 1040, 1130, 1131, 1041, 1042, 1043, 1044, 1058, 1059, 1065, 1066 } },
            { bossId = 18, variants = { 2060, 2061, 2062, 2063, 2064 } },
            { bossId = 45, variants = { 5030, 5031, 5032, 5033, 5034 } },
            { bossId = 47, variants = { 5050, 5051, 5052, 5054 } },
            { bossId = 21, variants = { 1100, 1101, 1102, 1103, 1104 } },
            { bossId = 14, variants = { 2020, 2021, 2022, 2023, 2024, 2025 } },
            { bossId = 28, variants = { 3280, 3281, 3282, 3283 } },
            { bossId = 57, variants = { 1106, 1107, 1108, 1109, 1115 } },
            { bossId = 67, variants = { 3398, 3399, 3404, 3405 } },
            { bossId = 69, variants = { 3394, 3395, 3396, 3397 } },
            { bossId = 94, variants = { 5270, 5271, 5272, 5273, 5274 } },
        },
        depths = {
            { bossId = 48, variants = { 5060, 5061, 5062, 5063, 5064 } },
            { bossId = 5, variants = { 1050, 1051, 1052, 1053, 1054, 1067, 1068, 1069, 1076 } },
            { bossId = 46, variants = { 5040, 5041, 5042, 5044, 5045 } },
            { bossId = 19, variants = { 1110, 1111, 1112, 1113, 1114 } },
            { bossId = 15, variants = { 2030, 2031, 2032, 2033, 5195, 5196 } },
            { bossId = 58, variants = { 1097, 1098, 1099, 1105, 1116 } },
            { bossId = 68, variants = { 3406, 3407, 3408, 3409 } },
            { bossId = 74, variants = { 5250, 5251, 5252, 5253, 5254, 5255, 5256 } },
        },
        womb = {
            { bossId = 7, variants = { 1070, 1071, 1072, 1073, 1074, 1075 } },
            { bossId = 49, variants = { 5070, 5071, 5072 } },
            { bossId = 31, variants = { 3310, 3311, 3312, 3313 } },
            { bossId = 53, variants = { 5110, 5111, 5113 } },
            { bossId = 16, variants = { 2040, 2041, 2042, 2043 } },
            { bossId = 72, variants = { 5152, 5153, 5154, 5155 } },
        },
    }

    local function birthrightIsHeld()
        return Mizuki.HasBirthright()
    end

    local function getCurrentRoomIndex(level)
        return level:GetCurrentRoomDesc().SafeGridIndex
    end

    local function getChainStage(roomIndex)
        if not bossChain then
            return nil
        end
        if roomIndex == DEBUG_ROOM_INDEX then
            return bossChain.currentTemporaryStage
        end
        return nil
    end

    function Mizuki.GetBirthrightBossChainStage()
        return getChainStage(getCurrentRoomIndex(Game():GetLevel()))
    end

    function Mizuki.GetBirthrightCarriedRewards()
        local chainStage = Mizuki.GetBirthrightBossChainStage()
        return bossChain and chainStage and bossChain.carriedRewards[chainStage]
    end

    function Mizuki.GetBirthrightRoomRewardSnapshot()
        local chainStage = Mizuki.GetBirthrightBossChainStage()
        if bossChain and not bossChain.finished and not pendingGeneration and chainStage then
            return bossChain.roomRewardSnapshots[chainStage]
        end
    end

    local function captureRoomRewards()
        local room = Game():GetRoom()
        local chainStage = Mizuki.GetBirthrightBossChainStage()
        if not gameStarted or not bossChain or bossChain.finished or pendingGeneration
            or not chainStage or room:GetType() ~= RoomType.ROOM_BOSS
            or not room:IsClear() then return false end

        -- A consumed carry list only says the transfer finished. The off-grid room
        -- can still lose those physical pedestals on continue, so save the actual
        -- remaining offers separately, including rerolls and an empty picked room.
        local snapshot = {}
        for _, entity in ipairs(Isaac.FindByType(
            EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE
        )) do
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists() and pickup.SubType > 0 then
                snapshot[#snapshot + 1] = {
                    collectible = pickup.SubType, initSeed = pickup.InitSeed,
                    x = pickup.Position.X, y = pickup.Position.Y,
                    optionsIndex = pickup.OptionsPickupIndex,
                    charge = pickup.Charge, touched = pickup.Touched,
                    price = pickup.Price, shopItemId = pickup.ShopItemId,
                    autoUpdatePrice = pickup.AutoUpdatePrice,
                }
            end
        end
        table.sort(snapshot, function(a, b) return a.initSeed < b.initSeed end)
        local previous = bossChain.roomRewardSnapshots[chainStage]
        local changed = not previous or #previous ~= #snapshot
        if not changed then
            for index, reward in ipairs(snapshot) do
                for key, value in pairs(reward) do
                    if previous[index][key] ~= value then changed = true; break end
                end
                if changed then break end
            end
        end
        if changed then bossChain.roomRewardSnapshots[chainStage] = snapshot end
        return changed
    end

    function Mizuki.MarkBirthrightCarriedRewardsRestored(chainStage)
        if bossChain and Mizuki.GetBirthrightBossChainStage() == chainStage then
            bossChain.carriedRewards[chainStage] = nil
            captureRoomRewards()
            saveBossChain()
        end
    end

    local function bindBossPortal(portal, chainStage)
        local data = portal:GetData()
        data.MizukiBossChainPortal = true
        data.MizukiBossChainSourceStage = chainStage
        data.MizukiBossChainTargetStage = chainStage + 1

        -- Only bound chain portals: render above floor debris, including on
        -- continue, without moving the portal or changing its touch radius.
        portal.SortingLayer = SortingLayer.SORTING_NORMAL

        local roomIndex = getCurrentRoomIndex(Game():GetLevel())
        local identity = bossChain.portalIdentities[chainStage]
        if not identity or identity.initSeed ~= portal.InitSeed
            or identity.roomIndex ~= roomIndex then
            bossChain.portalIdentities[chainStage] = {
                initSeed = portal.InitSeed, roomIndex = roomIndex,
            }
            saveBossChain()
        end
    end

    local function getPortalForStage(chainStage)
        if not bossChain then return nil end
        local identity = bossChain.portalIdentities[chainStage]
        local roomIndex = getCurrentRoomIndex(Game():GetLevel())
        for _, entity in ipairs(Isaac.FindByType(
            EntityType.ENTITY_EFFECT,
            EffectVariant.PORTAL_TELEPORT,
            BOSS_PORTAL_SUBTYPE
        )) do
            local data = entity:GetData()
            local marked = data.MizukiBossChainPortal == true
                and data.MizukiBossChainSourceStage == chainStage
            -- GetData is erased on continue, while the native portal may survive.
            -- Match its saved identity, never its color, position or generic subtype:
            -- those are shared with genuine Card Reading/other-mod portals.
            local restored = identity and identity.roomIndex == roomIndex
                and identity.initSeed == entity.InitSeed
            if marked or restored then
                local portal = entity:ToEffect()
                bindBossPortal(portal, chainStage)
                return portal
            end
        end
        return nil
    end

    local function removePortalForStage(chainStage)
        local portal = getPortalForStage(chainStage)
        if portal then
            Mizuki.RetireBossPortalEID(portal)
            portal:Remove()
        end
    end

    local function getQueuedCollectible(player)
        if player:IsItemQueueEmpty() then return nil end
        local queued = player.QueuedItem
        local item = queued and queued.Item
        if item then return { ID = item.ID, Type = item.Type } end
    end

    local function rememberCurrentQueues()
        queuedCollectibles = {}
        for index = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            queuedCollectibles[GetPtrHash(player)] = getQueuedCollectible(player)
        end
    end

    local function checkBossRewardClaim(player)
        if player.Variant ~= 0 then return end
        local playerHash = GetPtrHash(player)
        local queued = getQueuedCollectible(player)
        local previous = queuedCollectibles[playerHash]
        queuedCollectibles[playerHash] = queued
        if not queued or queued.ID <= 0 or queued.Type == ItemType.ITEM_TRINKET then return end
        if previous and previous.ID == queued.ID and previous.Type == queued.Type then return end

        local game = Game()
        if game:GetRoom():GetType() ~= RoomType.ROOM_BOSS then return end
        local roomIndex = getCurrentRoomIndex(game:GetLevel())
        local chainStage = getChainStage(roomIndex)
        if chainStage then
            bossChain.rewardClaimed[chainStage] = true
            bossChain.portalActive[chainStage] = false
            removePortalForStage(chainStage)
            if pendingGeneration and pendingGeneration.sourceStage == chainStage then
                pendingGeneration = nil
            end
            saveBossChain()
        end
    end

    local function spawnBossPortal(room, chainStage)
        local target = room:GetClampedPosition(
            room:GetCenterPos(),
            PORTAL_EDGE_MARGIN
        )
        local position = room:FindFreePickupSpawnPosition(target, 0, true)
        local portal = Isaac.Spawn(
            EntityType.ENTITY_EFFECT,
            EffectVariant.PORTAL_TELEPORT,
            BOSS_PORTAL_SUBTYPE,
            position,
            Vector.Zero,
            nil
        ):ToEffect()
        bindBossPortal(portal, chainStage)
        portal:GetSprite():Play("Appear", true)
        return portal
    end

    local function getBossChainPoolNames(level)
        local stage = level:GetStage()
        local useSecondVariant = level:GetStageType()
            == StageType.STAGETYPE_REPENTANCE_B

        -- The first additional fight uses the branch belonging to the current
        -- chapter; the second advances to the following main-path chapter. Floor I
        -- versus II does not change either pool.
        if stage == LevelStage.STAGE1_1
            or stage == LevelStage.STAGE1_2
        then
            return "caves", useSecondVariant and "dross" or "downpour"
        end
        if stage == LevelStage.STAGE2_1
            or stage == LevelStage.STAGE2_2
        then
            return "depths", useSecondVariant and "ashpit" or "mines"
        end
        if stage == LevelStage.STAGE3_1
            or stage == LevelStage.STAGE3_2
        then
            return "womb", useSecondVariant and "gehenna" or "mausoleum"
        end
        if stage == LevelStage.STAGE4_1 then
            -- The next chapter only has fixed end bosses. Fall back to this
            -- floor's random Boss pool.
            local stageType = level:GetStageType()
            local poolName = (stageType == StageType.STAGETYPE_REPENTANCE
                or stageType == StageType.STAGETYPE_REPENTANCE_B) and "corpse" or "womb"
            return poolName, poolName
        end
        -- Pickup-triggered challenges also work after chapter IV-I. Avoid fixed
        -- story bosses and their exits; use the existing random Womb boss pool.
        return "womb", "womb"
    end

    local function chooseBossEncounters(level, roomIndex)
        local normalPoolName, branchPoolName = getBossChainPoolNames(level)
        local normalPool = normalPoolName
            and (NORMAL_BOSS_POOLS[normalPoolName] or BRANCH_BOSS_POOLS[normalPoolName])
        local branchPool = branchPoolName
            and (BRANCH_BOSS_POOLS[branchPoolName] or NORMAL_BOSS_POOLS[branchPoolName])
        if not normalPool or not branchPool then
            return nil, nil
        end

        local rng = RNG()
        local stageSeed = Game():GetSeeds():GetStageSeed(level:GetStage())
        rng:SetSeed(stageSeed + roomIndex * BOSS_ENCOUNTER_ROOM_SEED_FACTOR + BOSS_ENCOUNTER_SEED_SALT,
            Mizuki.RuntimeParameters.RngShiftIndex)

        local function makeEncounter(entry)
            return {
                bossId = entry.bossId,
                roomVariant = entry.variants[
                    rng:RandomInt(#entry.variants) + 1
                ],
            }
        end

        local stage = level:GetStage()
        local firstPoolName = stage <= LevelStage.STAGE1_2 and "basement"
            or stage <= LevelStage.STAGE2_2 and "caves"
            or stage <= LevelStage.STAGE3_2 and "depths" or "womb"
        local firstPool = NORMAL_BOSS_POOLS[firstPoolName]
        local firstEntry = firstPool[rng:RandomInt(#firstPool) + 1]
        local function chooseDifferentBoss(pool, otherBossId)
            local candidates = {}
            for _, entry in ipairs(pool) do
                if entry.bossId ~= firstEntry.bossId and entry.bossId ~= otherBossId then
                    table.insert(candidates, entry)
                end
            end
            if #candidates == 0 then candidates = pool end
            return candidates[rng:RandomInt(#candidates) + 1]
        end
        local branchEntry = chooseDifferentBoss(branchPool)
        local normalEntry = chooseDifferentBoss(normalPool, branchEntry.bossId)

        return firstPoolName .. "+" .. branchPoolName .. "+" .. normalPoolName, {
            [1] = makeEncounter(firstEntry),
            [2] = makeEncounter(branchEntry),
            [3] = makeEncounter(normalEntry),
        }
    end

    local function createBossChain(room, level, roomIndex, entry)
        local poolName, encounters = chooseBossEncounters(level, roomIndex)
        if not encounters then
            return nil
        end

        bossChain = {
            originRoomIndex = roomIndex,
            entryPosition = { X = entry.X, Y = entry.Y },
            entryActive = true,
            finished = false,
            encounters = encounters,
            currentTemporaryStage = nil,
            temporaryDoorSlot = {},
            clearFrameByStage = {},
            rewardClaimed = {},
            carriedRewards = {},
            roomRewardSnapshots = {},
            portalIdentities = {},
            portalActive = {
                [1] = true,
                [2] = true,
            },
        }
        Isaac.DebugString(table.concat({
            "[Mizuki] Boss chain pool=",
            poolName,
            " stage1 boss=",
            tostring(encounters[1].bossId),
            " room=",
            tostring(encounters[1].roomVariant),
            " stage2 boss=",
            tostring(encounters[2].bossId),
            " room=",
            tostring(encounters[2].roomVariant),
            " stage3 boss=",
            tostring(encounters[3].bossId),
            " room=",
            tostring(encounters[3].roomVariant),
        }))
        lastChainStage = nil
        saveBossChain()
        return bossChain
    end

    function Mizuki.QueueBirthrightBossChain(player)
        -- Lua reloads do not emit GAME_STARTED. Recover existing progress before
        -- appending a genuine pickup; this never derives an entry from inventory.
        if not gameStarted then initializeBossChain(nil, true, true) end
        local roomIndex = getCurrentRoomIndex(Game():GetLevel())
        local position = player.Position
        -- A co-op acquisition during a challenge must not overwrite the current
        -- debug room or strand its rewards. Queue its entrance at the return room.
        if roomIndex == DEBUG_ROOM_INDEX and bossChain then
            roomIndex, position = bossChain.originRoomIndex, bossChain.entryPosition
        end
        pendingBirthrightEntries[#pendingBirthrightEntries + 1] = {
            roomIndex = roomIndex, X = position.X, Y = position.Y,
        }
        saveBossChain()
    end

    local function findNativeTemporaryEntranceDoor(room)
        for doorSlot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
            local door = room:GetDoor(doorSlot)
            if door
                and door.TargetRoomType ~= RoomType.ROOM_DEVIL
                and door.TargetRoomType ~= RoomType.ROOM_ANGEL
            then
                return door, doorSlot
            end
        end
        return nil, nil
    end

    local function synchronizeTemporaryBossDoor(room, level, chainStage)
        local doorSlot = bossChain.temporaryDoorSlot[chainStage]
        local door = doorSlot and room:GetDoor(doorSlot) or nil
        if not door then
            door, doorSlot = findNativeTemporaryEntranceDoor(room)
            if not door then
                return false
            end
            bossChain.temporaryDoorSlot[chainStage] = doorSlot
        end

        door.TargetRoomIndex = bossChain.originRoomIndex
        local outsideDesc = level:GetRoomByIdx(bossChain.originRoomIndex)
        if outsideDesc.Data then
            door.TargetRoomType = outsideDesc.Data.Type
        end
        return true
    end

    local function ensureBossRoomFunctions()
        local game = Game()
        local level = game:GetLevel()
        local room = game:GetRoom()
        local roomIndex = getCurrentRoomIndex(level)
        local chainStage = getChainStage(roomIndex)
        -- These extra encounters return to the original map, not the next
        -- floor. Retire exits left by the previous implementation or native
        -- clear logic, only inside this chain's identified temporary Boss room.
        if bossChain and roomIndex == DEBUG_ROOM_INDEX
            and chainStage and chainStage >= 1 and chainStage <= BOSS_ROOM_COUNT
            and room:GetType() == RoomType.ROOM_BOSS then
            for gridIndex = 0, room:GetGridSize() - 1 do
                local gridEntity = room:GetGridEntity(gridIndex)
                if gridEntity and gridEntity:GetType() == GridEntityType.GRID_TRAPDOOR then
                    room:RemoveGridEntity(gridIndex, 0, false)
                end
            end
        end
        if (not bossChain or bossChain.finished) and birthrightIsHeld() then
            for index, entry in ipairs(pendingBirthrightEntries) do
                if entry.roomIndex == roomIndex then
                    if createBossChain(room, level, roomIndex, entry) then
                        table.remove(pendingBirthrightEntries, index)
                        saveBossChain()
                    end
                    break
                end
            end
        end
        if not bossChain or bossChain.finished then return end
        if roomIndex == bossChain.originRoomIndex then
            if bossChain.entryActive and birthrightIsHeld() and not getPortalForStage(0) then
                spawnBossPortal(room, 0)
            end
            return
        end
        if not chainStage then return end
        synchronizeTemporaryBossDoor(room, level, chainStage)
        if not room:IsClear() then
            return
        end

        local currentFrame = game:GetFrameCount()
        local clearFrame = bossChain.clearFrameByStage[chainStage]
        if not clearFrame then
            clearFrame = currentFrame
            bossChain.clearFrameByStage[chainStage] = clearFrame
            saveBossChain()
        end
        if currentFrame < clearFrame + PORTAL_AFTER_CLEAR_DELAY_FRAMES then
            return
        end

        if chainStage >= BOSS_ROOM_COUNT
            or not bossChain.portalActive[chainStage]
            or not birthrightIsHeld()
            or pendingGeneration
        then
            return
        end

        if not getPortalForStage(chainStage) then
            spawnBossPortal(room, chainStage)
        end
    end

    local function resetReusedTemporaryRoom(descriptor)
        -- `goto` replaces the RoomConfig and refreshes the engine-owned RNG data,
        -- but the debug descriptor can retain completion state from the previous
        -- encounter. Only reset the public lifecycle fields so the next Boss can
        -- award its clear reward normally.
        descriptor.Clear = false
        descriptor.ClearCount = 0
        descriptor.VisitedCount = 0
        descriptor.Flags = 0
        descriptor.DisplayFlags = 0
        descriptor.NoReward = false
        descriptor.ChallengeDone = false
    end

    local function discardPreviousBossItems(sourceStage, sourceRoomIndex)
        local game = Game()
        -- Destruction is restricted to an explicitly committed, cleared round
        -- in the current chain. Never touch inventory or another room's entities.
        if not bossChain or bossChain.rewardClaimed[sourceStage]
            or getCurrentRoomIndex(game:GetLevel()) ~= sourceRoomIndex
            or getChainStage(sourceRoomIndex) ~= sourceStage
            or game:GetRoom():GetType() ~= RoomType.ROOM_BOSS
            or not game:GetRoom():IsClear() then
            return false
        end
        local carriedRewards = {}
        for _, entity in ipairs(Isaac.FindByType(
            EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE
        )) do
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists()
                and pickup.Type == EntityType.ENTITY_PICKUP
                and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                if pickup.SubType > 0 then
                    carriedRewards[#carriedRewards + 1] = {
                        collectible = pickup.SubType,
                        optionsIndex = pickup.OptionsPickupIndex,
                        charge = pickup.Charge,
                        touched = pickup.Touched,
                        price = pickup.Price,
                        shopItemId = pickup.ShopItemId,
                        autoUpdatePrice = pickup.AutoUpdatePrice,
                    }
                end
                pickup:Remove()
            end
        end
        -- Carry the actual visible offers, including rerolls and native option /
        -- Damocles variants. No pool roll is needed to transfer an existing item.
        bossChain.carriedRewards[sourceStage + 1] = carriedRewards
        bossChain.roomRewardSnapshots[sourceStage] = nil
        saveBossChain()
        return true
    end

    local function loadPendingBossLayout()
        local game = Game()
        local level = game:GetLevel()
        -- A different co-op player may have picked up a reward later in the same
        -- frame as portal contact. Check everyone before forfeiting any items.
        for index = 0, game:GetNumPlayers() - 1 do
            checkBossRewardClaim(Isaac.GetPlayer(index))
        end
        local pending = pendingGeneration
        if not pending then return end
        local entryTransition = pending.sourceStage == 0
        local atEntry = entryTransition and bossChain
            and pending.sourceRoomIndex == bossChain.originRoomIndex
            and getCurrentRoomIndex(level) == bossChain.originRoomIndex
        if not birthrightIsHeld()
            or (entryTransition and not atEntry)
            or (not entryTransition
                and not discardPreviousBossItems(pending.sourceStage, pending.sourceRoomIndex)) then
            if entryTransition and bossChain then bossChain.entryActive = true end
            pendingGeneration = nil
            saveBossChain()
            return
        end
        local encounter = bossChain.encounters[pending.targetStage]
        local result = Isaac.ExecuteCommand(
            "goto s.boss." .. tostring(encounter.roomVariant)
        )
        if result == "Error changing room." then
            Isaac.DebugString(
                "[Mizuki] Failed to load vanilla Boss Room variant "
                    .. tostring(encounter.roomVariant)
            )
            pendingGeneration = nil
            if entryTransition then bossChain.entryActive = true end
            saveBossChain()
            return
        end

        local debugDescriptor = level:GetRoomByIdx(DEBUG_ROOM_INDEX)
        local loadedRoom = debugDescriptor.Data
        if not loadedRoom
            or loadedRoom.Type ~= RoomType.ROOM_BOSS
            or loadedRoom.Variant ~= encounter.roomVariant
            or loadedRoom.Subtype ~= encounter.bossId
            or loadedRoom.Difficulty <= 0
        then
            Isaac.DebugString(
                "[Mizuki] Invalid Boss Room mapping: expected boss="
                    .. tostring(encounter.bossId)
                    .. " room=" .. tostring(encounter.roomVariant)
                    .. " actual boss="
                    .. tostring(loadedRoom and loadedRoom.Subtype)
                    .. " difficulty="
                    .. tostring(loadedRoom and loadedRoom.Difficulty)
            )
            pendingGeneration = nil
            game:ChangeRoom(pending.sourceRoomIndex)
            return
        end

        -- Use the debug room created by `goto` directly. Besides RoomConfig data,
        -- the engine initializes hidden descriptor fields such as the Boss death
        -- effect RNG seed; copying only Data to another off-grid descriptor leaves
        -- those fields at zero and can crash when a Boss dies.
        resetReusedTemporaryRoom(debugDescriptor)
        bossChain.temporaryDoorSlot[pending.targetStage] = nil
        pending.targetRoomIndex = DEBUG_ROOM_INDEX
        pending.phase = "waiting_for_target"
    end

    local function beginTemporaryBossGeneration(targetStage)
        pendingGeneration = {
            targetStage = targetStage,
            sourceRoomIndex = getCurrentRoomIndex(Game():GetLevel()),
            sourceStage = targetStage - 1,
            phase = "load_layout",
        }
    end

    local function useBossChainPortal(portal)
        if pendingGeneration then
            return
        end

        local targetStage = portal:GetData().MizukiBossChainTargetStage
        if not targetStage or not bossChain.encounters[targetStage] then
            return
        end

        Mizuki.RetireBossPortalEID(portal)
        portal:Remove()
        if targetStage == 1 then
            bossChain.entryActive = false
        else
            bossChain.portalActive[targetStage - 1] = false
        end
        beginTemporaryBossGeneration(targetStage)
        saveBossChain()
    end

    local function checkBossPortalTouch(_, player)
        if not gameStarted then initializeBossChain(nil, true, true) end
        checkBossRewardClaim(player)
        if not bossChain
            or pendingGeneration
            or not birthrightIsHeld()
        then
            return
        end

        local roomIndex = getCurrentRoomIndex(Game():GetLevel())
        if roomIndex == bossChain.originRoomIndex and bossChain.entryActive then
            local entry = getPortalForStage(0)
            if entry and entry.FrameCount > PORTAL_MIN_TOUCH_AGE_FRAMES
                and player.Position:DistanceSquared(entry.Position)
                    <= PORTAL_TRIGGER_RADIUS * PORTAL_TRIGGER_RADIUS then
                useBossChainPortal(entry)
            end
            return
        end
        local chainStage = getChainStage(roomIndex)
        if not chainStage or chainStage >= BOSS_ROOM_COUNT
            or not bossChain.portalActive[chainStage]
            or bossChain.rewardClaimed[chainStage] then
            return
        end

        local portal = getPortalForStage(chainStage)
        if portal
            and portal.FrameCount > PORTAL_MIN_TOUCH_AGE_FRAMES
            and player.Position:DistanceSquared(portal.Position)
                <= PORTAL_TRIGGER_RADIUS * PORTAL_TRIGGER_RADIUS
        then
            useBossChainPortal(portal)
        end
    end

    local function placePlayersAtOrigin(room)
        local entry = bossChain.entryPosition
        local playerPosition = room:FindFreePickupSpawnPosition(
            room:GetClampedPosition(Vector(entry.X, entry.Y), PORTAL_EDGE_MARGIN), 0, true)
        local game = Game()
        for playerIndex = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(playerIndex)
            player.Position = playerPosition
            player.Velocity = Vector.Zero
        end
    end

    local function onPostUpdate()
        if not gameStarted then initializeBossChain(nil, true, true) end
        if pendingGeneration then
            if pendingGeneration.phase == "load_layout" then
                loadPendingBossLayout()
            end
            return
        end

        ensureBossRoomFunctions()
        if captureRoomRewards() then saveBossChain() end
    end

    local function onNewRoom()
        local game = Game()
        local level = game:GetLevel()
        local room = game:GetRoom()
        local currentRoomIndex = getCurrentRoomIndex(level)
        rememberCurrentQueues()

        if pendingGeneration then
            if pendingGeneration.phase == "waiting_for_target"
                and currentRoomIndex == pendingGeneration.targetRoomIndex
            then
                local targetStage = pendingGeneration.targetStage
                pendingGeneration = nil
                bossChain.currentTemporaryStage = targetStage
                lastChainStage = targetStage
                synchronizeTemporaryBossDoor(room, level, targetStage)
                saveBossChain()
                return
            end
        end

        if bossChain and lastChainStage
            and currentRoomIndex == bossChain.originRoomIndex
        then
            bossChain.entryActive = false
            bossChain.portalActive[1] = false
            bossChain.portalActive[2] = false
            bossChain.finished = true
            placePlayersAtOrigin(room)
            saveBossChain()
        end

        local chainStage = getChainStage(currentRoomIndex)
        if chainStage
            and bossChain.portalActive[chainStage] == false
        then
            removePortalForStage(chainStage)
        end
        if chainStage then
            synchronizeTemporaryBossDoor(room, level, chainStage)
        end
        lastChainStage = chainStage
    end

    local function resetBossChainForFloor()
        bossChain = nil
        lastChainStage = nil
        pendingGeneration = nil
        pendingBirthrightEntries = {}
        rememberCurrentQueues()
        saveBossChain()
    end

    initializeBossChain = function(_, isContinued, isLuaReload)
        bossChain, lastChainStage, pendingGeneration = nil, nil, nil
        pendingBirthrightEntries = {}
        if isContinued then
            local saved = readSaveRoot().BirthrightBossChain
            local level = Game():GetLevel()
            if type(saved) == "table" and saved.stage == level:GetStage()
                and saved.stageType == level:GetStageType()
                and saved.stageSeed == Game():GetSeeds():GetStageSeed(level:GetStage()) then
                bossChain = saved.chain
                pendingBirthrightEntries = saved.entries or {}
                pendingGeneration = saved.pending
                if bossChain then
                    for _, key in ipairs(ROUND_MAP_KEYS) do
                        local restored = {}
                        for round, value in pairs(bossChain[key] or {}) do
                            local index = tonumber(round)
                            if index then restored[index] = value end
                        end
                        bossChain[key] = restored
                    end
                    -- Legacy arrays may already have collapsed [2]/[3] into [1].
                    -- Only one transfer can be pending: the current fight (or the
                    -- queued destination). Recover only that unambiguous case and
                    -- never reopen a finished/claimed challenge.
                    if (saved.version == nil or saved.version == 1) and not bossChain.finished
                        and next(bossChain.rewardClaimed) == nil then
                        local target = pendingGeneration and pendingGeneration.targetStage
                            or bossChain.currentTemporaryStage
                        local onlyRound, count = nil, 0
                        for round, rewards in pairs(bossChain.carriedRewards) do
                            if type(rewards) == "table" and #rewards > 0 then
                                onlyRound, count = round, count + 1
                            end
                        end
                        if (target == 2 or target == 3) and count == 1
                            and onlyRound < target and not bossChain.carriedRewards[target] then
                            bossChain.carriedRewards[target] = bossChain.carriedRewards[onlyRound]
                            bossChain.carriedRewards[onlyRound] = nil
                        end
                    end
                    lastChainStage = getChainStage(getCurrentRoomIndex(level))
                end
            end
        else
            resetBossChainForFloor()
        end
        gameStarted = true
        rememberCurrentQueues()
        if pendingGeneration and pendingGeneration.phase == "waiting_for_target" then
            onNewRoom()
        end
        saveBossChain()
        -- A reload keeps live room entities. Only an actual save/continue may
        -- restore missing ground rewards from the saved room snapshot.
        if isContinued and not isLuaReload and bossChain and not bossChain.finished and not pendingGeneration then
            Mizuki.RestoreBirthrightRoomRewardsAfterContinue()
            if captureRoomRewards() then saveBossChain() end
            if next(bossChain.rewardClaimed) == nil then
                Mizuki.RestoreBirthrightRewardsAfterContinue()
            end
        end
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, onPostUpdate)
    Mizuki:AddCallback(
        ModCallbacks.MC_POST_PLAYER_UPDATE,
        checkBossPortalTouch
    )
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, onNewRoom)
    Mizuki:AddCallback(
        ModCallbacks.MC_POST_NEW_LEVEL,
        resetBossChainForFloor
    )
    Mizuki:AddCallback(
        ModCallbacks.MC_POST_GAME_STARTED,
        initializeBossChain
    )
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        captureRoomRewards()
        saveBossChain()
        gameStarted = false
    end)
end
-- endregion Boss challenge
