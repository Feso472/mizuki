-- The experimental capsule pocket item: pill stat capture, hour glass
-- variants and their pickups.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local GLOWING_HOUR_GLASS = Mizuki.GLOWING_HOUR_GLASS
local HOUR_GLASS = Mizuki.HOUR_GLASS
local CAPSULE_STAT_CACHE_FLAGS = Mizuki.CAPSULE_STAT_CACHE_FLAGS
local isMizuki = Mizuki.isMizuki
local capsuleStates = Mizuki.capsuleStates
local cannonReconcileStates = Mizuki.cannonReconcileStates
local getCannonReconcileState = Mizuki.getCannonReconcileState
local getCapsuleState = Mizuki.getCapsuleState

-- Experimental Capsule -----------------------------------------------------
-- This is a real pocket object, so it occupies the normal card/pill slot.
-- The small state machine distinguishes deliberately consuming it from trying
-- to drop it: only the latter causes the capsule to be restored.
local function findExperimentalCapsuleSlot(player)
    for slot = 0, 1 do
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

    return math.max(1, math.min(2, slotCount))
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

local function captureExperimentalPillStats(player)
    return {
        Damage = player.Damage,
        Tears = 30 / (player.MaxFireDelay + 1),
        MoveSpeed = player.MoveSpeed,
        ShotSpeed = player.ShotSpeed,
        TearRange = player.TearRange,
        Luck = player.Luck,
    }
end

local function subtractExperimentalPillStats(after, before)
    return {
        Damage = after.Damage - before.Damage,
        Tears = after.Tears - before.Tears,
        MoveSpeed = after.MoveSpeed - before.MoveSpeed,
        ShotSpeed = after.ShotSpeed - before.ShotSpeed,
        TearRange = after.TearRange - before.TearRange,
        Luck = after.Luck - before.Luck,
    }
end

local function addExperimentalPillStats(total, addition)
    total = total or {
        Damage = 0,
        Tears = 0,
        MoveSpeed = 0,
        ShotSpeed = 0,
        TearRange = 0,
        Luck = 0,
    }

    for stat, value in pairs(addition) do
        total[stat] = (total[stat] or 0) + value
    end

    return total
end

local function giveExperimentalCapsule(player)
    local state = getCapsuleState(player)
    local existingSlot = findExperimentalCapsuleSlot(player)
    if existingSlot == 0 then
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
            -- With no spare slot, preserve the selected object as a pickup
            -- before reserving slot 0 for the floor-refreshed capsule.
            player:DropPocketItem(0, player.Position)
        end
    end

    player:SetCard(0, Mizuki.ExperimentalCapsuleCard)
    state.Consumed = false
end

local function giveCapsuleHourGlass(player)
    -- SetPocketActiveItem is the only stable vanilla API for a character that
    -- did not start with an XML-defined pocket active. Native use-count
    -- handling stays with the game.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
end

local function giveCapsuleHourGlassWithUsesSpent(player, usesSpent)
    if usesSpent >= 3 then
        player:SetPocketActiveItem(HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
        return
    end

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
            state.CapsuleFloorRewindCount =
                (state.CapsuleFloorRewindCount or 0) + 1
            local usesSpent = state.CapsuleFloorRewindCount

            -- The rewind restores the capsule from its snapshot. Recreate the
            -- native hourglass with the number of uses already spent this floor.
            player:SetCard(restoredCapsuleSlot, Card.CARD_NULL)
            state.Consumed = true
            giveCapsuleHourGlassWithUsesSpent(player, usesSpent)
            state.CapsuleHourGlassOrigin = usesSpent < 3
            state.CapsuleNativeRewindPending = nil
            state.CapsuleNativeRewindUseFrame = nil

            if state.CapsulePillStatDelta
                and not state.CapsuleFloorPillDeltaApplied
            then
                state.RewindStatDelta = addExperimentalPillStats(
                    state.RewindStatDelta,
                    state.CapsulePillStatDelta
                )
                state.CapsuleFloorPillDeltaApplied = true
            end
            if state.CapsulePillStatDelta then
                player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
                player:EvaluateItems()
            end
        elseif state.CapsuleNativeRewindUseFrame
            and Game():GetFrameCount() - state.CapsuleNativeRewindUseFrame > 90
        then
            -- A blocked/failed native rewind may not restore the capsule.
            -- Expire its pending probe so it cannot affect a later room state.
            state.CapsuleNativeRewindPending = nil
            state.CapsuleNativeRewindUseFrame = nil
        end
    end

    local slot = findExperimentalCapsuleSlot(player)
    if not state.Initialized then
        state.Initialized = true
        local pocketActive = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
        if slot ~= nil then
            state.Consumed = false
            state.CapsuleHourGlassOrigin = false
            state.CapsuleFloorRewindCount = 0
        elseif pocketActive ~= CollectibleType.COLLECTIBLE_NULL then
            state.Consumed = true
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
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.CapsulePillStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end
    if slot ~= nil then
        state.Consumed = false
        state.CapsuleHourGlassOrigin = false
        state.CapsuleNativeRewindPending = nil
        state.CapsuleNativeRewindUseFrame = nil
        return
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
    if player:GetCard(0) == Mizuki.ExperimentalCapsuleCard then
        local slotCount = getConsumableSlotCount(player)
        if slotCount >= 2 and pocketConsumableSlotIsEmpty(player, 1) then
            return
        end

        pickup.Wait = math.max(pickup.Wait or 0, 2)
        return
    end
end


function Mizuki:UseExperimentalCapsule(card, player, useFlags)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    state.Consumed = true
    state.CapsuleHourGlassOrigin = true
    state.CapsuleFloorPillDeltaApplied = false
    state.CapsulePillStatDelta = nil
    state.PillStatsBefore = captureExperimentalPillStats(player)
    state.CapturePillStatsPending = true

    -- Delegate the stat changes, feedback and all edge cases to the vanilla
    -- Experimental Pill implementation instead of reproducing its RNG here.
    player:UsePill(PillEffect.PILLEFFECT_EXPERIMENTAL, PillColor.PILL_NULL, useFlags)
    giveCapsuleHourGlass(player)
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

    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.CapsulePillStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end

    state.CapsuleNativeRewindPending = true
    state.CapsuleNativeRewindUseFrame = Game():GetFrameCount()
end


function Mizuki:ExpireImmediateCapsuleHourGlass()
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            local reconcileState = getCannonReconcileState(player)
            if reconcileState.Pending then
                reconcileState.Pending = nil
                reconcileState.Frames = 2
            end

        end
    end
end


function Mizuki:InitializeExperimentalCapsule(isContinued)
    if isContinued then return end

    for index in pairs(capsuleStates) do
        capsuleStates[index] = nil
    end
    for index in pairs(cannonReconcileStates) do
        cannonReconcileStates[index] = nil
    end
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            -- A quick restart can evaluate the new player before this callback
            -- clears the previous run's capsule stat delta. Recalculate every
            -- stat that delta can affect after clearing it.
            player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
            player:EvaluateItems()
        end
    end
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
            state.Initialized = true
            state.CapsuleHourGlassOrigin = false
            state.CapsuleFloorRewindCount = 0
            state.CapsuleFloorPillDeltaApplied = false
            state.CapsulePillStatDelta = nil
            state.CapsuleNativeRewindPending = nil
            state.CapsuleNativeRewindUseFrame = nil
            state.PillStatsBefore = nil
            state.CapturePillStatsPending = nil
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
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.RefreshExperimentalCapsule)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ExpireImmediateCapsuleHourGlass)

Mizuki.captureExperimentalPillStats = captureExperimentalPillStats
Mizuki.findExperimentalCapsuleSlot = findExperimentalCapsuleSlot
Mizuki.getConsumableSlotCount = getConsumableSlotCount
Mizuki.giveCapsuleHourGlass = giveCapsuleHourGlass
Mizuki.giveExperimentalCapsule = giveExperimentalCapsule
Mizuki.pocketConsumableSlotIsEmpty = pocketConsumableSlotIsEmpty
Mizuki.subtractExperimentalPillStats = subtractExperimentalPillStats
