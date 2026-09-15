-- The fan familiar: its needs, rewards and floor gifts.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local BFFS = Mizuki.BFFS
local LUCKY_FOOT = Mizuki.LUCKY_FOOT
local MOMS_BOX = Mizuki.MOMS_BOX
local SACK_HEAD = Mizuki.SACK_HEAD
local isMizuki = Mizuki.isMizuki
local getConsumableSlotCount = Mizuki.getConsumableSlotCount
local pocketConsumableSlotIsEmpty = Mizuki.pocketConsumableSlotIsEmpty

-- Mizuki Fan ---------------------------------------------------------------
-- Values which the design document leaves open are centralized for testing.
local FAN_BLOCK_CHANCE = 0.50
local FAN_NEED_WINDOW = 0.10
local FAN_BFFS_CLEAR_CHANCE = 0.20
local FAN_LUCK_CLEAR_CAP = 0.05
local FAN_MOMS_BOX_GOLDEN_CHANCE = 0.10
local FAN_SACK_HEAD_REPLACE_CHANCE = 0.20
local FAN_BFFS_BLOCK_RADIUS_MULTIPLIER = 1.5
local FAN_GIFT_OFFSET = Vector(0, 8)
local GOLDEN_TRINKET_FLAG = 1 << 15
local FAN_ADVANCED_TRINKET_POOL = {
    TrinketType.TRINKET_SAFETY_SCISSORS,
    TrinketType.TRINKET_COUNTERFEIT_PENNY,
    TrinketType.TRINKET_SWALLOWED_PENNY,
    TrinketType.TRINKET_CRYSTAL_KEY,
    TrinketType.TRINKET_ADOPTION_PAPERS,
    TrinketType.TRINKET_NOSE_GOBLIN,
    TrinketType.TRINKET_BLESSED_PENNY,
    TrinketType.TRINKET_LIL_CLOT,
    TrinketType.TRINKET_FILIGREE_FEATHERS,
    TrinketType.TRINKET_CRACKED_CROWN,
    TrinketType.TRINKET_CANCER,
    TrinketType.TRINKET_CURVED_HORN,
    TrinketType.TRINKET_BRAIN_WORM,
    TrinketType.TRINKET_M,
    TrinketType.TRINKET_JAW_BREAKER,
    TrinketType.TRINKET_DEVILS_CROWN,
    TrinketType.TRINKET_PAY_TO_WIN,
    TrinketType.TRINKET_SIGIL_OF_BAPHOMET,
    TrinketType.TRINKET_DICE_BAG,
    TrinketType.TRINKET_CRACKED_DICE,
}
local FAN_ADVANCED_TRINKETS = {}
for _, subtype in ipairs(FAN_ADVANCED_TRINKET_POOL) do
    FAN_ADVANCED_TRINKETS[subtype] = true
end

local function getFanOwner(familiar)
    local player = familiar.Player
    return player and isMizuki(player) and player or nil
end

local function getFanNeeds(player)
    local trinketSlots = math.max(1, player:GetMaxTrinkets())
    local trinketsFilled = 0
    for slot = 0, trinketSlots - 1 do
        if player:GetTrinket(slot) ~= TrinketType.TRINKET_NULL then
            trinketsFilled = trinketsFilled + 1
        end
    end

    local pocketSlots = getConsumableSlotCount(player)
    local pocketsFilled = 0
    for slot = 0, pocketSlots - 1 do
        if not pocketConsumableSlotIsEmpty(player, slot) then
            pocketsFilled = pocketsFilled + 1
        end
    end

    local health = player:GetHearts() + player:GetSoulHearts()
        + player:GetBoneHearts() * 2
    local function need(current, threshold)
        return math.max(0, math.min(1, 1 - current / threshold))
    end
    return {
        { Kind = "Coin", Need = need(player:GetNumCoins(), 15) },
        { Kind = "Bomb", Need = need(player:GetNumBombs(), 5) },
        { Kind = "Key", Need = need(player:GetNumKeys(), 5) },
        { Kind = "Heart", Need = need(health, 12) },
        { Kind = "Trinket", Need = need(trinketsFilled, trinketSlots) },
        { Kind = "Pocket", Need = need(pocketsFilled, pocketSlots) },
    }
end

local function chooseFanCategory(player, rng)
    local needs = getFanNeeds(player)
    local maxNeed = 0
    for _, entry in ipairs(needs) do maxNeed = math.max(maxNeed, entry.Need) end
    if maxNeed <= 0 then
        local roll = rng:RandomFloat()
        if roll < 0.50 then return needs[rng:RandomInt(4) + 1].Kind, true end
        return roll < 0.75 and "Trinket" or "Pocket", true
    end

    local candidates = {}
    for _, entry in ipairs(needs) do
        if entry.Need >= maxNeed - FAN_NEED_WINDOW then
            candidates[#candidates + 1] = entry.Kind
        end
    end
    return candidates[rng:RandomInt(#candidates) + 1], false
end

local function randomFrom(rng, values)
    return values[rng:RandomInt(#values) + 1]
end

local function rollFanReward(player, rng)
    local kind, wealthy = chooseFanCategory(player, rng)
    local advanced = wealthy and rng:RandomFloat() < 0.50
    local reward
    local basic = true
    if kind == "Coin" then
        reward = { PickupVariant.PICKUP_COIN, advanced and randomFrom(rng, { 2, 3, 4, 5, 7 }) or 0 }
        basic = not advanced
    elseif kind == "Bomb" then
        reward = { PickupVariant.PICKUP_BOMB, advanced and randomFrom(rng, { 2, 4 }) or 0 }
        basic = not advanced
    elseif kind == "Key" then
        reward = { PickupVariant.PICKUP_KEY, advanced and randomFrom(rng, { 2, 3, 4 }) or 0 }
        basic = not advanced
    elseif kind == "Heart" then
        reward = { PickupVariant.PICKUP_HEART, advanced and randomFrom(rng, { 3, 4, 5, 6, 7, 8, 10, 11 }) or 0 }
        basic = not advanced
    elseif kind == "Trinket" then
        local subtype = advanced
            and randomFrom(rng, FAN_ADVANCED_TRINKET_POOL)
            or Game():GetItemPool():GetTrinket()
        if player:HasCollectible(MOMS_BOX)
            and rng:RandomFloat() < FAN_MOMS_BOX_GOLDEN_CHANCE then
            subtype = subtype | GOLDEN_TRINKET_FLAG
        end
        reward = { PickupVariant.PICKUP_TRINKET, subtype }
        -- Golden status does not change whether the trinket itself belongs to
        -- the advanced pool. Judge the final trinket by its base subtype.
        basic = not FAN_ADVANCED_TRINKETS[subtype & ~GOLDEN_TRINKET_FLAG]
    else
        local pool = Game():GetItemPool()
        if rng:RandomFloat() < 0.75 then
            local subtype = pool:GetCard(rng:Next(), true, true, false)
            if advanced then
                for _ = 1, 12 do
                    if subtype < 1 or subtype > 22 then break end
                    subtype = pool:GetCard(rng:Next(), true, true, false)
                end
            end
            reward = { PickupVariant.PICKUP_TAROTCARD, subtype }
            -- Only the 22 ordinary upright tarot cards are outside the
            -- advanced card pool. Judge the final draw, not the quality roll.
            basic = subtype >= 1 and subtype <= 22
        else
            local subtype = pool:GetPill(rng:Next())
            if advanced then subtype = subtype | PillColor.PILL_GIANT_FLAG end
            reward = { PickupVariant.PICKUP_PILL, subtype }
            -- Ordinary colors 1-13 are basic. A regular golden pill and every
            -- giant pill belong to the advanced pool, even on a basic roll.
            local isGiant = (subtype & PillColor.PILL_GIANT_FLAG) ~= 0
            local baseColor = subtype & ~PillColor.PILL_GIANT_FLAG
            basic = not isGiant and baseColor >= 1 and baseColor <= 13
        end
    end

    if basic and player:HasCollectible(SACK_HEAD)
        and rng:RandomFloat() < FAN_SACK_HEAD_REPLACE_CHANCE then
        reward = { PickupVariant.PICKUP_GRAB_BAG, 0 }
    end
    return reward
end

local function queueFanGift(familiar)
    local player = getFanOwner(familiar)
    if not player then return end
    local data = familiar:GetData()
    data.MizukiFanGiftQueue = data.MizukiFanGiftQueue or {}
    data.MizukiFanGiftQueue[#data.MizukiFanGiftQueue + 1] =
        rollFanReward(player, familiar:GetDropRNG())
end

function Mizuki:InitFanFamiliar(familiar)
    familiar:AddToFollowers()
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    familiar:GetSprite():Play("Float", true)
end

function Mizuki:UpdateFanFamiliar(familiar)
    local player = getFanOwner(familiar)
    if not player then return end
    familiar:FollowParent()

    local sprite = familiar:GetSprite()
    local data = familiar:GetData()
    -- The painted frame faces slightly right. Mirror only after the familiar
    -- moves clearly across the player, keeping the previous direction near
    -- the centre line so follower bobbing cannot make it flicker.
    local horizontalOffset = familiar.Position.X - player.Position.X
    if horizontalOffset < -4 then
        sprite.FlipX = false
    elseif horizontalOffset > 4 then
        sprite.FlipX = true
    end
    local queue = data.MizukiFanGiftQueue
    if queue and #queue > 0 and not sprite:IsPlaying("Gift") then
        data.MizukiFanCurrentGift = table.remove(queue, 1)
        sprite:Play("Gift", true)
    end
    if sprite:IsEventTriggered("Drop") and data.MizukiFanCurrentGift then
        local reward = data.MizukiFanCurrentGift
        Isaac.Spawn(EntityType.ENTITY_PICKUP, reward[1], reward[2],
            familiar.Position + FAN_GIFT_OFFSET, Vector.Zero, familiar)
        SFXManager():Play(SoundEffect.SOUND_THUMBSUP, 1.0, 0, false, 1.0)
        data.MizukiFanCurrentGift = nil
    end
    if sprite:IsFinished("Gift") then sprite:Play("Float", true) end

    local radius = familiar.Size
    if player:HasCollectible(BFFS) then
        radius = radius * FAN_BFFS_BLOCK_RADIUS_MULTIPLIER
    end
    for _, entity in ipairs(Isaac.FindInRadius(
        familiar.Position, radius + 8, EntityPartition.BULLET
    )) do
        local projectile = entity:ToProjectile()
        if projectile and projectile:Exists()
            and projectile.Position:Distance(familiar.Position) <= radius + projectile.Size then
            local projectileData = projectile:GetData()
            projectileData.MizukiFanBlockAttempts = projectileData.MizukiFanBlockAttempts or {}
            local fanKey = tostring(familiar.InitSeed)
            if not projectileData.MizukiFanBlockAttempts[fanKey] then
                projectileData.MizukiFanBlockAttempts[fanKey] = true
                if familiar:GetDropRNG():RandomFloat() < FAN_BLOCK_CHANCE then
                    projectile:Die()
                end
            end
        end
    end
end

function Mizuki:RollFanRoomClearGifts()
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR, Mizuki.FanVariant, -1, false, false
    )) do
        local familiar = entity:ToFamiliar()
        local player = getFanOwner(familiar)
        if player then
            local luck = math.max(player.Luck, 0)
            local luckChance = FAN_LUCK_CLEAR_CAP * luck / (luck + 5)
            if player:HasCollectible(LUCKY_FOOT) then luckChance = luckChance * 2 end
            local chance = luckChance
                + (player:HasCollectible(BFFS) and FAN_BFFS_CLEAR_CHANCE or 0)
            if familiar:GetDropRNG():RandomFloat() < chance then
                queueFanGift(familiar)
            end
        end
    end
end

local function queueFloorGiftForPlayer(player)
    player:GetData().MizukiFanFloorGiftPending = true
    player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
    player:EvaluateItems()
end

function Mizuki:QueueFanFloorGifts()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then queueFloorGiftForPlayer(player) end
    end
end

function Mizuki:InitializeFanFloorGift(isContinued)
    if not isContinued then Mizuki:QueueFanFloorGifts() end
end

function Mizuki:DispatchFanFloorGift(player)
    if not isMizuki(player) or not player:GetData().MizukiFanFloorGiftPending then return end
    local fans = {}
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR, Mizuki.FanVariant, -1, false, false
    )) do
        local familiar = entity:ToFamiliar()
        if familiar and familiar.Player
            and GetPtrHash(familiar.Player) == GetPtrHash(player) then
            fans[#fans + 1] = familiar
        end
    end
    table.sort(fans, function(a, b) return a.InitSeed < b.InitSeed end)
    if fans[1] then
        player:GetData().MizukiFanFloorGiftPending = nil
        queueFanGift(fans[1])
    end
end

Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitFanFamiliar, Mizuki.FanVariant)
Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, Mizuki.UpdateFanFamiliar, Mizuki.FanVariant)
Mizuki:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, Mizuki.RollFanRoomClearGifts)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeFanFloorGift)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.QueueFanFloorGifts)
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.DispatchFanFloorGift)
