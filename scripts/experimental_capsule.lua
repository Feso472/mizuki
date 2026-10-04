-- The experimental capsule pocket item: native pill replay, hour glass
-- variants and their pickups.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local GLOWING_HOUR_GLASS = Mizuki.GLOWING_HOUR_GLASS
local EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = Mizuki.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE
local CAPSULE_STAT_CACHE_FLAGS = Mizuki.CAPSULE_STAT_CACHE_FLAGS
local isMizuki = Mizuki.isMizuki
local capsuleStates = Mizuki.capsuleStates
local cannonReconcileStates = Mizuki.cannonReconcileStates
local getCannonReconcileState = Mizuki.getCannonReconcileState
local getCapsuleState = Mizuki.getCapsuleState
local json = require("json")
local EXPERIMENTAL_PILL = PillEffect.PILLEFFECT_EXPERIMENTAL
local CAPSULE_SAVE_VERSION = 3
local REPLAY_USE_FLAGS = UseFlag.USE_NOANIM | UseFlag.USE_NOANNOUNCER | UseFlag.USE_NOHUD
local CAPSULE_CHECKPOINT_SEED_MAX = 0xffffffff
local CAPSULE_CHECKPOINT_SHIFT = 35

-- Capsule lifecycle tuning: frames, world-space pixels and per-floor uses.
local CAPSULE_DROP_RECOVERY_RADIUS = 120
local CAPSULE_DROP_RECOVERY_MAX_AGE = 2
local CAPSULE_REWIND_TIMEOUT_FRAMES = 90
local CAPSULE_HOURGLASS_USES_PER_FLOOR = 3
local CAPSULE_BASE_HOURGLASS_USES_PER_FLOOR = 1
local CAPSULE_PICKUP_BLOCK_FRAMES = 2
local CANNON_RECONCILE_DELAY_FRAMES = 2
local MAX_CONSUMABLE_SLOTS = 2

-- Experimental Capsule -----------------------------------------------------
-- This is a real pocket object, so it occupies the normal card/pill slot.
-- Only False PHD without PHD locks the capsule. Otherwise native dropping and
-- replacement are allowed, without granting another capsule on the same floor.
local function isCapsuleDropLocked(player)
    return player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_PHD)
end

local function findExperimentalCapsuleSlot(player)
    for slot = 0, MAX_CONSUMABLE_SLOTS - 1 do
        if player:GetCard(slot) == Mizuki.ExperimentalCapsuleCard then
            return slot
        end
    end

    return nil
end

local function getConsumableSlotCount(player)
    local slotCount = player:GetMaxPocketItems()
    if player:GetActiveItem(ActiveSlot.SLOT_POCKET) ~= CollectibleType.COLLECTIBLE_NULL then
        slotCount = slotCount - 1
    end

    return math.max(1, math.min(MAX_CONSUMABLE_SLOTS, slotCount))
end

local function pocketConsumableSlotIsEmpty(player, slot)
    return player:GetCard(slot) == Card.CARD_NULL and player:GetPill(slot) == PillColor.PILL_NULL
end

local function movePocketConsumable(player, fromSlot, toSlot)
    local card = player:GetCard(fromSlot)
    local pill = player:GetPill(fromSlot)

    player:SetCard(fromSlot, Card.CARD_NULL)
    player:SetPill(fromSlot, PillColor.PILL_NULL)
    if card ~= Card.CARD_NULL then
        player:SetCard(toSlot, card)
    elseif pill ~= PillColor.PILL_NULL then
        player:SetPill(toSlot, pill)
    end
end

local function refreshCapsuleStats(player)
    player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
    player:EvaluateItems()
end

local function capturePillReplay(player, useFlags)
    local rng = player:GetPillRNG(EXPERIMENTAL_PILL)
    local seed = rng:GetSeed()
    assert(seed > 0, "Experimental Capsule: invalid native pill RNG seed")

    -- Vanilla has no shift-index getter. Match the native sequence, then
    -- restore it BEFORE the real pill use so recording consumes no randomness.
    -- Eighteen samples distinguish all supported shift indices (IsaacDocs/RNG).
    local samples = {}
    for index = 1, 18 do samples[index] = rng:Next() end
    for shift = 0, 80 do
        local candidate = RNG()
        candidate:SetSeed(seed, shift)
        local matches = true
        for _, sample in ipairs(samples) do
            if candidate:Next() ~= sample then
                matches = false
                break
            end
        end
        if matches then
            rng:SetSeed(seed, shift)
            return { Seed = seed, Shift = shift, UseFlags = useFlags or 0 }
        end
    end
    error("Experimental Capsule: native pill RNG shift not found")
end

local function suspendCapsuleReplay(state)
    if not state.CapsuleReplayUntracked then
        Isaac.DebugString("[Mizuki Capsule] Untracked snapshot/legacy records; "
            .. "automatic replay suspended until the next floor.")
    end
    state.CapsuleReplayUntracked = true
end

local function initializeCapsuleCheckpoint(player, state)
    if state.CapsuleReplayUntracked then return false end
    if not state.CapsuleCheckpointBaseSeed then
        -- A pre-marker record cannot tell us how much an old snapshot contains.
        -- Preserve it, but never guess that its prefix is either zero or full.
        if #(state.CapsulePillReplays or {}) > 0 then
            suspendCapsuleReplay(state)
            return false
        end
        local seed = player:GetCardRNG(Mizuki.ExperimentalCapsuleCard):GetSeed()
        assert(seed > 0, "Experimental Capsule: invalid native card RNG seed")
        state.CapsuleCheckpointBaseSeed = seed
    end
    return true
end

local function readCapsuleCheckpoint(player, state)
    if not initializeCapsuleCheckpoint(player, state) then return nil end
    -- The engine stores/restores this custom card's seed with player state.
    -- Pill RNG is separate. Keep the original seed as prefix zero, so snapshots
    -- taken before Lua initialization also work without rewriting that snapshot.
    local seed = player:GetCardRNG(Mizuki.ExperimentalCapsuleCard):GetSeed()
    local count = (seed - state.CapsuleCheckpointBaseSeed) % CAPSULE_CHECKPOINT_SEED_MAX
    if seed <= 0 or count > #(state.CapsulePillReplays or {}) then
        suspendCapsuleReplay(state)
        return nil
    end
    return count
end

local function stampCapsuleCheckpoint(player, state)
    if state.CapsuleReplayUntracked then return end
    local count = #(state.CapsulePillReplays or {})
    assert(count < CAPSULE_CHECKPOINT_SEED_MAX, "Experimental Capsule: checkpoint overflow")
    local seed = (state.CapsuleCheckpointBaseSeed - 1 + count) % CAPSULE_CHECKPOINT_SEED_MAX + 1
    player:GetCardRNG(Mizuki.ExperimentalCapsuleCard):SetSeed(seed, CAPSULE_CHECKPOINT_SHIFT)
end

local function replayCapsulePills(player, state)
    local replays = state.CapsulePillReplays or {}
    -- Read the RESTORED marker before writing anything. Neither room entry nor
    -- room clear proves which of the two native snapshots will be restored.
    local includedCount = readCapsuleCheckpoint(player, state)
    if includedCount == nil then
        refreshCapsuleStats(player)
        return
    end
    local firstMissing = includedCount + 1
    local replaySfx = firstMissing <= #replays and SFXManager() or nil
    for index = firstMissing, #replays do
        local replay = replays[index]
        player:GetPillRNG(EXPERIMENTAL_PILL):SetSeed(replay.Seed, replay.Shift)
        player:UsePill(EXPERIMENTAL_PILL, PillColor.PILL_NULL,
            replay.UseFlags | REPLAY_USE_FLAGS)
        -- Experimental Pill calls AnimateHappy/AnimateSad even with NOANIM,
        -- and PHD also plays POWERUP_SPEWER. NOANNOUNCER only mutes the voice.
        -- Stop these native effect sounds immediately after EACH replay, not
        -- on a later update and never in the real capsule-use callback.
        replaySfx:Stop(SoundEffect.SOUND_THUMBSUP)
        replaySfx:Stop(SoundEffect.SOUND_THUMBS_DOWN)
        replaySfx:Stop(SoundEffect.SOUND_POWERUP_SPEWER)
    end
    -- The native effect can be present while the displayed stats remain stale
    -- after a rewind. Recalculate it; never add the old final-panel delta too.
    refreshCapsuleStats(player)
    stampCapsuleCheckpoint(player, state)
end

local function readCapsuleSaveRoot()
    if not Mizuki:HasData() then return {} end
    local ok, root = pcall(json.decode, Mizuki:LoadData())
    return ok and type(root) == "table" and root or {}
end

local function validPillReplay(replay)
    return type(replay) == "table"
        and type(replay.Seed) == "number" and replay.Seed == math.floor(replay.Seed)
        and replay.Seed > 0
        and replay.Seed <= 0xffffffff
        and type(replay.Shift) == "number" and replay.Shift == math.floor(replay.Shift)
        and replay.Shift >= 0 and replay.Shift <= 80
        and type(replay.UseFlags) == "number" and replay.UseFlags == math.floor(replay.UseFlags)
        and replay.UseFlags >= 0 and replay.UseFlags <= 0x7fffffff
end

local function removeDroppedExperimentalCapsules(player)
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_TAROTCARD,
        -1,
        false,
        false
    )) do
        if (entity.SubType == Mizuki.ExperimentalCapsuleCard
                or entity.SubType == EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE)
            and entity.Position:DistanceSquared(player.Position) <= CAPSULE_DROP_RECOVERY_RADIUS * CAPSULE_DROP_RECOVERY_RADIUS
            and entity.FrameCount <= CAPSULE_DROP_RECOVERY_MAX_AGE
        then
            entity:Remove()
        end
    end
end

local function giveExperimentalCapsule(player)
    local state = getCapsuleState(player)
    local existingSlot = findExperimentalCapsuleSlot(player)
    if existingSlot == 0 then
        state.CapsuleWasHeld = true
        return
    end

    local slotCount = getConsumableSlotCount(player)
    if existingSlot == 1 then
        -- The capsule must always be the selected/front consumable. Move the
        -- former slot-0 object behind it without dropping either object.
        player:SetCard(1, Card.CARD_NULL)
        if not pocketConsumableSlotIsEmpty(player, 0) then
            movePocketConsumable(player, 0, 1)
        end
    elseif not pocketConsumableSlotIsEmpty(player, 0) then
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            movePocketConsumable(player, 0, 1)
        else
            -- Dropping slot 0 may promote slot 1 into its place. Save and clear
            -- slot 1 first, then put it back after dropping slot 0 so the
            -- capsule cannot overwrite the promoted item.
            local secondCard = player:GetCard(1)
            local secondPill = player:GetPill(1)
            if slotCount >= 2 then
                player:SetCard(1, Card.CARD_NULL)
                player:SetPill(1, PillColor.PILL_NULL)
            end
            player:DropPocketItem(0, player.Position)
            if slotCount >= 2 then
                if secondCard ~= Card.CARD_NULL then
                    player:SetCard(1, secondCard)
                elseif secondPill ~= PillColor.PILL_NULL then
                    player:SetPill(1, secondPill)
                end
            end
        end
    end

    player:SetCard(0, Mizuki.ExperimentalCapsuleCard)
    state.Consumed = false
    state.CapsuleWasHeld = true
end

local function giveCapsuleHourGlass(player)
    -- SetPocketActiveItem is the only stable vanilla API for a character that
    -- did not start with an XML-defined pocket active. Native use-count
    -- handling stays with the game.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
end

local function giveCapsuleHourGlassWithUsesSpent(player, usesSpent)
    usesSpent = math.max(0, math.min(CAPSULE_HOURGLASS_USES_PER_FLOOR, usesSpent))
    -- Even when exhausted, keep the blue item with native VarData = 3.
    -- Its slowdown behavior is NOT a reason to replace it with item 66.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
    if usesSpent > 0 then
        player:AddCollectible(
            GLOWING_HOUR_GLASS,
            0,
            false,
            ActiveSlot.SLOT_POCKET,
            usesSpent
        )
    end
end

function Mizuki:MaintainExperimentalCapsule(player)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)

    if state.CapsuleNativeRewindPending then
        local restoredCapsuleSlot = findExperimentalCapsuleSlot(player)
        if restoredCapsuleSlot ~= nil and state.CapsuleHourGlassOrigin then
            state.CapsuleNativeRewindPending = nil
            state.CapsuleNativeRewindFramesLeft = nil

            if player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD) then
                -- False PHD takes priority over PHD. Leave the restored card
                -- untouched; the next REAL capsule use supplies a fresh glass.
                state.Consumed = false
                state.CapsuleWasHeld = true
                state.CapsuleHourGlassOrigin = false
                state.CapsuleFloorRewindCount = 0
            else
                state.CapsuleFloorRewindCount = math.min(CAPSULE_HOURGLASS_USES_PER_FLOOR,
                    (state.CapsuleFloorRewindCount or 0) + 1)
                local usesSpent = state.CapsuleFloorRewindCount
                player:SetCard(restoredCapsuleSlot, Card.CARD_NULL)
                state.Consumed = true
                state.CapsuleWasHeld = false
                giveCapsuleHourGlassWithUsesSpent(player, usesSpent)
                state.CapsuleHourGlassOrigin = usesSpent < CAPSULE_HOURGLASS_USES_PER_FLOOR
            end
            replayCapsulePills(player, state)
        else
            -- Relative time still expires if the native rewind moves the
            -- global frame counter backwards or if the rewind was blocked.
            state.CapsuleNativeRewindFramesLeft =
                (state.CapsuleNativeRewindFramesLeft or CAPSULE_REWIND_TIMEOUT_FRAMES) - 1
            if state.CapsuleNativeRewindFramesLeft <= 0 then
                state.CapsuleNativeRewindPending = nil
                state.CapsuleNativeRewindFramesLeft = nil
            end
        end
    end

    local slot = findExperimentalCapsuleSlot(player)
    if not state.Initialized then
        state.Initialized = true
        local pocketActive = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
        if slot ~= nil then
            state.Consumed = false
            state.CapsuleWasHeld = true
            state.CapsuleHourGlassOrigin = false
            state.CapsuleFloorRewindCount = 0
        elseif pocketActive ~= CollectibleType.COLLECTIBLE_NULL then
            state.Consumed = true
            state.CapsuleWasHeld = false
            state.CapsuleHourGlassOrigin = pocketActive == GLOWING_HOUR_GLASS
            local activeItemDesc = player.GetActiveItemDesc
                and player:GetActiveItemDesc(ActiveSlot.SLOT_POCKET)
            state.CapsuleFloorRewindCount = state.CapsuleHourGlassOrigin
                and activeItemDesc
                and (activeItemDesc.VarData or 0)
                or 0
        else
            -- Makes a Lua hot reload recover the character's floor state
            -- instead of leaving both pocket areas blank.
            giveExperimentalCapsule(player)
            state.CapsuleHourGlassOrigin = false
            state.CapsuleFloorRewindCount = 0
            slot = findExperimentalCapsuleSlot(player)
        end
    end
    if slot ~= nil then
        state.Consumed = false
        state.CapsuleWasHeld = true
        state.CapsuleHourGlassOrigin = false
        state.CapsuleNativeRewindPending = nil
        state.CapsuleNativeRewindFramesLeft = nil
        return
    end
    if state.CapsuleWasHeld and not state.Consumed then
        if isCapsuleDropLocked(player) then
            removeDroppedExperimentalCapsules(player)
            giveExperimentalCapsule(player)
        else
            -- Losing the held card is a permitted drop/replacement, not a
            -- reason to grant a replacement now or after gaining False PHD.
            state.CapsuleWasHeld = false
        end
    end
end


function Mizuki:BlockPocketPickupWhileCapsuleSelected(pickup, collider)
    local player = collider:ToPlayer()
    if not player or not isMizuki(player) then
        return
    end

    -- Slot 0 is the selected consumable. If a real secondary consumable slot
    -- is unlocked and empty, vanilla can safely place the pickup there.
    --
    -- Otherwise keep this pickup briefly in vanilla's "not yet collectible"
    -- state instead of cancelling the collision with `return true`.
    -- The normal pickup collision logic can then still run.
    if isCapsuleDropLocked(player) and player:GetCard(0) == Mizuki.ExperimentalCapsuleCard then
        local slotCount = getConsumableSlotCount(player)
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            return
        end

        pickup.Wait = math.max(pickup.Wait or 0, CAPSULE_PICKUP_BLOCK_FRAMES)
        return
    end
end


function Mizuki:UseExperimentalCapsule(card, player, useFlags)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    -- Validate/init the marker before adding this real use to the external log.
    -- Unknown native state must not be silently relabelled as a complete prefix.
    local includedCount = readCapsuleCheckpoint(player, state)
    if includedCount ~= nil and includedCount ~= #(state.CapsulePillReplays or {}) then
        suspendCapsuleReplay(state)
    end
    state.Consumed = true
    state.CapsuleWasHeld = false
    local hasDoctorate = player:HasCollectible(CollectibleType.COLLECTIBLE_PHD)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD)
    -- Both variants are capsule-created hourglasses. Without a doctorate,
    -- start with two native uses spent so exactly one rewind remains.
    state.CapsuleHourGlassOrigin = true
    state.CapsuleFloorRewindCount = hasDoctorate and 0
        or CAPSULE_HOURGLASS_USES_PER_FLOOR - CAPSULE_BASE_HOURGLASS_USES_PER_FLOOR
    -- This filtered custom-card callback is the ONLY recording entry point.
    -- Ordinary Experimental Pills (and other players' pills) are not retained.
    state.CapsulePillReplays = state.CapsulePillReplays or {}
    table.insert(state.CapsulePillReplays, capturePillReplay(player, useFlags))
    state.CapsuleNativeRewindPending = nil
    state.CapsuleNativeRewindFramesLeft = nil

    -- Delegate the stat changes, feedback and all edge cases to the vanilla
    -- Experimental Pill implementation instead of reproducing its RNG here.
    player:UsePill(EXPERIMENTAL_PILL, PillColor.PILL_NULL, useFlags)
    refreshCapsuleStats(player)
    if hasDoctorate then
        giveCapsuleHourGlass(player)
    else
        -- Lucky Foot / Virgo affect the pill, not the three-rewind upgrade.
        -- The non-False-PHD restore path consumes the returned capsule and
        -- advances the native spent count to three after this one rewind.
        giveCapsuleHourGlassWithUsesSpent(player, state.CapsuleFloorRewindCount)
    end
    -- MC_USE_CARD is at the end of the native custom-card use path. Stamp only
    -- after the real pill effect; never advance or replace the pill RNG here.
    stampCapsuleCheckpoint(player, state)
end


function Mizuki:UseCapsuleHourGlass(collectible, rng, player, useFlags, activeSlot)
    if not isMizuki(player) then
        return
    end

    -- Glowing Hour Glass can transiently duplicate custom familiars while its
    -- rewind snapshot is being restored. player:GetData() is itself rewound, so
    -- keep this marker in external Lua state or the rewind erases the request.
    local reconcileState = getCannonReconcileState(player)
    reconcileState.Pending = true

    local state = getCapsuleState(player)
    if activeSlot ~= ActiveSlot.SLOT_POCKET then
        return
    end

    -- Primary and Schoolbag hourglasses remain native and do not participate
    -- in capsule rewind handling. For a capsule-created pocket hourglass, only
    -- mark the native rewind; the next player update checks whether its
    -- restored inventory actually contains the capsule.
    if not state.CapsuleHourGlassOrigin or not state.Consumed then
        return
    end

    state.CapsuleNativeRewindPending = true
    state.CapsuleNativeRewindFramesLeft = CAPSULE_REWIND_TIMEOUT_FRAMES
end


function Mizuki:ExpireImmediateCapsuleHourGlass()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local reconcileState = getCannonReconcileState(player)
            if reconcileState.Pending then
                reconcileState.Pending = nil
                reconcileState.Frames = CANNON_RECONCILE_DELAY_FRAMES
            end
        end
    end
end


function Mizuki:InitializeExperimentalCapsule(isContinued)
    for index in pairs(capsuleStates) do
        capsuleStates[index] = nil
    end
    for index in pairs(cannonReconcileStates) do
        cannonReconcileStates[index] = nil
    end
    local game = Game()
    local root = readCapsuleSaveRoot()
    local saved = root.ExperimentalCapsule
    local level = game:GetLevel()
    local canRestore = isContinued and type(saved) == "table"
        and (saved.Version == 1 or saved.Version == 2 or saved.Version == CAPSULE_SAVE_VERSION)
        and saved.RunSeed == game:GetSeeds():GetStartSeed()
        and saved.Stage == level:GetStage() and saved.StageType == level:GetStageType()
        and saved.StageSeed == game:GetSeeds():GetStageSeed(level:GetStage())
        and type(saved.Players) == "table"
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local entry = canRestore and saved.Players[tostring(index)]
            if type(entry) == "table" then
                local state = getCapsuleState(player)
                state.Initialized = entry.Initialized == true
                state.Consumed = entry.Consumed == true
                state.CapsuleWasHeld = entry.CapsuleWasHeld == true
                state.CapsuleHourGlassOrigin = entry.CapsuleHourGlassOrigin == true
                state.CapsuleFloorRewindCount = math.max(0, math.min(
                    CAPSULE_HOURGLASS_USES_PER_FLOOR,
                    math.floor(tonumber(entry.CapsuleFloorRewindCount) or 0)))
                state.CapsulePillReplays = {}
                if saved.Version == 1 and validPillReplay(entry.CapsulePillReplay) then
                    state.CapsulePillReplays[1] = entry.CapsulePillReplay
                elseif type(entry.CapsulePillReplays) == "table" then
                    for _, replay in ipairs(entry.CapsulePillReplays) do
                        if not validPillReplay(replay) then break end
                        table.insert(state.CapsulePillReplays, replay)
                    end
                end
                local baseSeed = entry.CapsuleCheckpointBaseSeed
                if saved.Version == CAPSULE_SAVE_VERSION and type(baseSeed) == "number"
                    and baseSeed == math.floor(baseSeed) and baseSeed > 0
                    and baseSeed <= CAPSULE_CHECKPOINT_SEED_MAX then
                    state.CapsuleCheckpointBaseSeed = baseSeed
                end
                if entry.CapsuleReplayUntracked == true then
                    state.CapsuleReplayUntracked = true
                end
                if entry.CapsuleNativeRewindPending == true then
                    state.CapsuleNativeRewindPending = true
                    state.CapsuleNativeRewindFramesLeft = CAPSULE_REWIND_TIMEOUT_FRAMES
                end
            end
            -- Native pill effects are already in a continued game's save.
            -- Restore only the replay record, NEVER consume it on Continue.
            initializeCapsuleCheckpoint(player, getCapsuleState(player))
            refreshCapsuleStats(player)
        end
    end
    if not isContinued then
        root.ExperimentalCapsule = nil
        Mizuki:SaveData(json.encode(root))
    end
end

function Mizuki:SaveExperimentalCapsule(shouldSave)
    if not shouldSave then return end
    local game = Game()
    local level = game:GetLevel()
    local players = {}
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local state = getCapsuleState(player)
            players[tostring(index)] = {
                Initialized = state.Initialized,
                Consumed = state.Consumed,
                CapsuleWasHeld = state.CapsuleWasHeld,
                CapsuleHourGlassOrigin = state.CapsuleHourGlassOrigin,
                CapsuleFloorRewindCount = state.CapsuleFloorRewindCount,
                CapsulePillReplays = state.CapsulePillReplays,
                CapsuleCheckpointBaseSeed = state.CapsuleCheckpointBaseSeed,
                CapsuleReplayUntracked = state.CapsuleReplayUntracked,
                CapsuleNativeRewindPending = state.CapsuleNativeRewindPending,
            }
        end
    end
    -- Merge with the latest save root; Birthright owns the other keys.
    local root = readCapsuleSaveRoot()
    root.ExperimentalCapsule = {
        Version = CAPSULE_SAVE_VERSION, RunSeed = game:GetSeeds():GetStartSeed(),
        Stage = level:GetStage(), StageType = level:GetStageType(),
        StageSeed = game:GetSeeds():GetStageSeed(level:GetStage()), Players = players,
    }
    Mizuki:SaveData(json.encode(root))
end


function Mizuki:RefreshExperimentalCapsule()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            if player:GetActiveItem(ActiveSlot.SLOT_POCKET) == GLOWING_HOUR_GLASS then
                player:SetPocketActiveItem(
                    CollectibleType.COLLECTIBLE_NULL,
                    ActiveSlot.SLOT_POCKET,
                    true
                )
            end

            local state = getCapsuleState(player)
            state.Consumed = false
            state.CapsuleWasHeld = false
            state.Initialized = true
            state.CapsuleHourGlassOrigin = false
            state.CapsuleFloorRewindCount = 0
            state.CapsulePillReplays = nil
            state.CapsuleCheckpointBaseSeed = nil
            state.CapsuleReplayUntracked = nil
            state.CapsuleNativeRewindPending = nil
            state.CapsuleNativeRewindFramesLeft = nil
            initializeCapsuleCheckpoint(player, state)
            giveExperimentalCapsule(player)
        end
    end
end


Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.MaintainExperimentalCapsule)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_TAROTCARD
)
Mizuki:AddCallback(
    ModCallbacks.MC_PRE_PICKUP_COLLISION,
    Mizuki.BlockPocketPickupWhileCapsuleSelected,
    PickupVariant.PICKUP_PILL
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_CARD,
    Mizuki.UseExperimentalCapsule,
    Mizuki.ExperimentalCapsuleCard
)
Mizuki:AddCallback(
    ModCallbacks.MC_USE_ITEM,
    Mizuki.UseCapsuleHourGlass,
    GLOWING_HOUR_GLASS
)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, Mizuki.SaveExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.RefreshExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ExpireImmediateCapsuleHourGlass)

Mizuki.findExperimentalCapsuleSlot = findExperimentalCapsuleSlot
Mizuki.getConsumableSlotCount = getConsumableSlotCount
Mizuki.giveCapsuleHourGlass = giveCapsuleHourGlass
Mizuki.giveExperimentalCapsule = giveExperimentalCapsule
Mizuki.pocketConsumableSlotIsEmpty = pocketConsumableSlotIsEmpty
