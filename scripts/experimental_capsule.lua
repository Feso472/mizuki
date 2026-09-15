-- The experimental capsule pocket item: pill stat capture, hour glass
-- variants and their pickups.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE = Mizuki.EXPERIMENTAL_CAPSULE_PICKUP_SUBTYPE
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
            and entity.Position:DistanceSquared(player.Position) <= 14400 then
            entity:Remove()
        end
    end
end

local function giveExperimentalCapsule(player)
    local state = getCapsuleState(player)
    local existingSlot = findExperimentalCapsuleSlot(player)
    if existingSlot == 0 then
        state.WasHeld = true
        state.LastSlot = 0
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
    state.WasHeld = true
    state.LastSlot = 0
end

local function giveCapsuleHourGlass(player, alreadyUsed)
    -- SetPocketActiveItem is the only stable vanilla API for a character that
    -- did not start with an XML-defined pocket active. Remaining capsule uses
    -- are tracked by the mod, while the native VarData is synchronized below
    -- so the HUD shows the same count.
    player:SetPocketActiveItem(GLOWING_HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)

    local used = alreadyUsed or 0
    if used > 0 then
        -- SetPocketActiveItem first materializes the dynamic pocket-active
        -- slot. Replacing that occupied slot through the vanilla
        -- AddCollectible API then writes Glowing Hour Glass's real VarData,
        -- which is also what the HUD uses for its remaining-use display.
        player:AddCollectible(
            GLOWING_HOUR_GLASS,
            0,
            false,
            ActiveSlot.SLOT_POCKET,
            used
        )
    end
end

function Mizuki:MaintainExperimentalCapsule(player)
    if not isMizuki(player) then
        return
    end

    local state = getCapsuleState(player)
    local slot = findExperimentalCapsuleSlot(player)
    if not state.Initialized then
        state.Initialized = true
        state.LastSlot = slot or 0
        if slot ~= nil then
            state.Consumed = false
            state.WasHeld = true
        elseif player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            ~= CollectibleType.COLLECTIBLE_NULL then
            state.Consumed = true
            state.WasHeld = false
        else
            -- Makes a Lua hot reload recover the character's floor state
            -- instead of leaving both pocket areas blank.
            giveExperimentalCapsule(player)
            slot = findExperimentalCapsuleSlot(player)
        end
    end
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end
    if slot ~= nil then
        -- Glowing Hour Glass restores the pre-use consumable inventory. Mod
        -- state is intentionally kept outside that snapshot, so a consumed
        -- capsule is removed again instead of becoming an infinite hourglass.
        if state.Consumed then
            player:SetCard(slot, Card.CARD_NULL)
            slot = nil
        else
            state.WasHeld = true
            state.LastSlot = slot
            return
        end
    end

    if state.RewindFrames then
        state.RewindFrames = state.RewindFrames - 1
        if state.RewindFrames <= 0 then
            state.RewindFrames = nil
            if state.PendingStatDelta then
                state.RewindStatDelta = addExperimentalPillStats(
                    state.RewindStatDelta,
                    state.PendingStatDelta
                )
                state.PendingStatDelta = nil
                player:AddCacheFlags(CAPSULE_STAT_CACHE_FLAGS)
                player:EvaluateItems()
            end
            giveCapsuleHourGlass(player, 1)
            state.CapsuleHourGlassUsesRemaining = 2
        end
    end

    if state.CapsuleHourGlassRestoreFrames then
        state.CapsuleHourGlassRestoreFrames = state.CapsuleHourGlassRestoreFrames - 1
        if state.CapsuleHourGlassRestoreFrames <= 0 then
            state.CapsuleHourGlassRestoreFrames = nil
            giveCapsuleHourGlass(player, 3 - state.CapsuleHourGlassUsesRemaining)
        end
    end

    if state.CapsuleHourGlassFinishFrames then
        state.CapsuleHourGlassFinishFrames = state.CapsuleHourGlassFinishFrames - 1
        if state.CapsuleHourGlassFinishFrames <= 0 then
            state.CapsuleHourGlassFinishFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            player:SetPocketActiveItem(HOUR_GLASS, ActiveSlot.SLOT_POCKET, true)
        end
    end

    if not state.Consumed and state.WasHeld then
        removeDroppedExperimentalCapsules(player)
        giveExperimentalCapsule(player)
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
    state.WasHeld = false
    state.ImmediateHourGlass = true
    state.UseRoomIndex = Game():GetLevel():GetCurrentRoomIndex()

    state.PillStatsBefore = captureExperimentalPillStats(player)
    state.CapturePillStatsPending = true

    -- Delegate the stat changes, feedback and all edge cases to the vanilla
    -- Experimental Pill implementation instead of reproducing its RNG here.
    player:UsePill(PillEffect.PILLEFFECT_EXPERIMENTAL, PillColor.PILL_NULL, useFlags)
    giveCapsuleHourGlass(player, 0)
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
    -- If the hourglass was activated before the next player update, finish
    -- the post-pill snapshot here. The native pill cache has resolved by now.
    if state.CapturePillStatsPending and state.PillStatsBefore then
        state.PendingStatDelta = subtractExperimentalPillStats(
            captureExperimentalPillStats(player),
            state.PillStatsBefore
        )
        state.PillStatsBefore = nil
        state.CapturePillStatsPending = nil
    end

    local isImmediateCapsuleHourGlass = state.ImmediateHourGlass
        and state.UseRoomIndex == Game():GetLevel():GetCurrentRoomIndex()
    if state.Consumed and isImmediateCapsuleHourGlass then
        -- Resolve after the vanilla rewind has restored the room/player state.
        -- Item restoration must not depend on whether the pill stat cache has
        -- finished resolving; a very fast use can arrive before that snapshot.
        -- Clear the marker before restoring the item so later uses are native.
        state.ImmediateHourGlass = false
        state.RewindRequested = true
    elseif state.CapsuleHourGlassUsesRemaining then
        state.CapsuleHourGlassUsesRemaining = state.CapsuleHourGlassUsesRemaining - 1
        if state.CapsuleHourGlassUsesRemaining > 0 then
            state.CapsuleHourGlassRestoreRequested = true
        else
            state.CapsuleHourGlassFinishRequested = true
        end
    end

    if isImmediateCapsuleHourGlass or state.CapsuleHourGlassUsesRemaining ~= nil then
        return {
            Discharge = false,
            Remove = false,
            ShowAnim = true,
        }
    end
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

            local state = getCapsuleState(player)
            if state.RewindRequested then
                state.RewindRequested = nil
                state.RewindFrames = 1
            elseif state.CapsuleHourGlassRestoreRequested then
                state.CapsuleHourGlassRestoreRequested = nil
                state.CapsuleHourGlassRestoreFrames = 1
            elseif state.CapsuleHourGlassFinishRequested then
                state.CapsuleHourGlassFinishRequested = nil
                state.CapsuleHourGlassFinishFrames = 1
            else
                state.ImmediateHourGlass = false
                state.PendingStatDelta = nil
            end
        end
    end
end


function Mizuki:InitializeExperimentalCapsule(isContinued)
    capsuleStates = {}
    cannonReconcileStates = {}
    local game = Game()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            -- Add by resolved custom ID instead of relying on players.xml to
            -- parse a localized/custom item name. The quest tag protects it
            -- from ordinary rerolls after this one-time initialization.
            if not player:HasCollectible(Mizuki.FanItem) then
                player:AddCollectible(Mizuki.FanItem, 0, false)
            end
            player:AddCacheFlags(
                CacheFlag.CACHE_FAMILIARS
                    | CacheFlag.CACHE_TEARCOLOR
                    | CacheFlag.CACHE_SPEED
                    | CacheFlag.CACHE_LUCK
            )
            player:EvaluateItems()
            local state = getCapsuleState(player)
            local slot = findExperimentalCapsuleSlot(player)
            local pocketActive = player:GetActiveItem(ActiveSlot.SLOT_POCKET)
            local hasCapsuleHourGlass = pocketActive == GLOWING_HOUR_GLASS
                or pocketActive == HOUR_GLASS

            state.WasHeld = slot ~= nil
            state.Initialized = true
            state.LastSlot = slot or 0
            state.Consumed = hasCapsuleHourGlass and slot == nil
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil

            if slot == nil and pocketActive == CollectibleType.COLLECTIBLE_NULL then
                giveExperimentalCapsule(player)
            end

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
            state.WasHeld = false
            state.Initialized = true
            state.ImmediateHourGlass = false
            state.PendingStatDelta = nil
            state.PillStatsBefore = nil
            state.CapturePillStatsPending = nil
            state.RewindRequested = nil
            state.RewindFrames = nil
            state.CapsuleHourGlassUsesRemaining = nil
            state.CapsuleHourGlassRestoreRequested = nil
            state.CapsuleHourGlassRestoreFrames = nil
            state.CapsuleHourGlassFinishRequested = nil
            state.CapsuleHourGlassFinishFrames = nil
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
