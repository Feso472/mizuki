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
local FAN_BLOCK_RADIUS = 13
local FAN_BFFS_BLOCK_RADIUS_MULTIPLIER = 1.5
local FAN_GIFT_OFFSET = Vector(0, 8)
local FAN_NEED_THRESHOLDS = { Coin = 15, Bomb = 5, Key = 5, Heart = 12 }
local FAN_BONE_HEART_HEALTH = 2
local FAN_WEALTHY_CONSUMABLE_CHANCE = 0.50
local FAN_WEALTHY_TRINKET_CHANCE = 0.25
local FAN_CONSUMABLE_CATEGORY_COUNT = 4
local FAN_ADVANCED_REWARD_CHANCE = 0.50
local FAN_POCKET_CARD_CHANCE = 0.75
local FAN_ADVANCED_CARD_REROLLS = 12
local FAN_FLIP_DISTANCE = 4
local FAN_LUCK_SOFT_CAP = 5
local FAN_LUCKY_FOOT_MULTIPLIER = 2
local FAN_ADVANCED_PICKUP_POOLS = {
    Coin = { CoinSubType.COIN_NICKEL, CoinSubType.COIN_DIME,
        CoinSubType.COIN_DOUBLEPACK, CoinSubType.COIN_LUCKYPENNY, CoinSubType.COIN_GOLDEN },
    Bomb = { BombSubType.BOMB_DOUBLEPACK, BombSubType.BOMB_GOLDEN },
    Key = { KeySubType.KEY_GOLDEN, KeySubType.KEY_DOUBLEPACK, KeySubType.KEY_CHARGED },
    Heart = { HeartSubType.HEART_SOUL, HeartSubType.HEART_ETERNAL,
        HeartSubType.HEART_DOUBLEPACK, HeartSubType.HEART_BLACK, HeartSubType.HEART_GOLDEN,
        HeartSubType.HEART_HALF_SOUL, HeartSubType.HEART_BLENDED, HeartSubType.HEART_BONE },
}
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
        + player:GetBoneHearts() * FAN_BONE_HEART_HEALTH
    local function need(current, threshold)
        return math.max(0, math.min(1, 1 - current / threshold))
    end
    return {
        { Kind = "Coin", Need = need(player:GetNumCoins(), FAN_NEED_THRESHOLDS.Coin) },
        { Kind = "Bomb", Need = need(player:GetNumBombs(), FAN_NEED_THRESHOLDS.Bomb) },
        { Kind = "Key", Need = need(player:GetNumKeys(), FAN_NEED_THRESHOLDS.Key) },
        { Kind = "Heart", Need = need(health, FAN_NEED_THRESHOLDS.Heart) },
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
        if roll < FAN_WEALTHY_CONSUMABLE_CHANCE then return needs[rng:RandomInt(FAN_CONSUMABLE_CATEGORY_COUNT) + 1].Kind, true end
        return roll < FAN_WEALTHY_CONSUMABLE_CHANCE + FAN_WEALTHY_TRINKET_CHANCE and "Trinket" or "Pocket", true
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
    local advanced = wealthy and rng:RandomFloat() < FAN_ADVANCED_REWARD_CHANCE
    local reward
    local basic = true
    if kind == "Coin" then
        reward = { PickupVariant.PICKUP_COIN, advanced and randomFrom(rng, FAN_ADVANCED_PICKUP_POOLS.Coin) or 0 }
        basic = not advanced
    elseif kind == "Bomb" then
        reward = { PickupVariant.PICKUP_BOMB, advanced and randomFrom(rng, FAN_ADVANCED_PICKUP_POOLS.Bomb) or 0 }
        basic = not advanced
    elseif kind == "Key" then
        reward = { PickupVariant.PICKUP_KEY, advanced and randomFrom(rng, FAN_ADVANCED_PICKUP_POOLS.Key) or 0 }
        basic = not advanced
    elseif kind == "Heart" then
        reward = { PickupVariant.PICKUP_HEART, advanced and randomFrom(rng, FAN_ADVANCED_PICKUP_POOLS.Heart) or 0 }
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
        if rng:RandomFloat() < FAN_POCKET_CARD_CHANCE then
            local subtype = pool:GetCard(rng:Next(), true, true, false)
            if advanced then
                for _ = 1, FAN_ADVANCED_CARD_REROLLS do
                    if subtype < Card.CARD_FOOL or subtype > Card.CARD_WORLD then break end
                    subtype = pool:GetCard(rng:Next(), true, true, false)
                end
            end
            reward = { PickupVariant.PICKUP_TAROTCARD, subtype }
            -- Only the 22 ordinary upright tarot cards are outside the
            -- advanced card pool. Judge the final draw, not the quality roll.
            basic = subtype >= Card.CARD_FOOL and subtype <= Card.CARD_WORLD
        else
            local subtype = pool:GetPill(rng:Next())
            if advanced then subtype = subtype | PillColor.PILL_GIANT_FLAG end
            reward = { PickupVariant.PICKUP_PILL, subtype }
            -- Ordinary colors 1-13 are basic. A regular golden pill and every
            -- giant pill belong to the advanced pool, even on a basic roll.
            local isGiant = (subtype & PillColor.PILL_GIANT_FLAG) ~= 0
            local baseColor = subtype & ~PillColor.PILL_GIANT_FLAG
            basic = not isGiant and baseColor >= PillColor.PILL_BLUE_BLUE and baseColor <= PillColor.PILL_WHITE_YELLOW
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
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    familiar.CollisionDamage = 0
    familiar.Size = FAN_BLOCK_RADIUS
    familiar:GetSprite():Play("Float", true)
end

function Mizuki:UpdateFanFamiliar(familiar)
    local player = getFanOwner(familiar)
    if not player then return end
    -- Native entity collision (the red hitbox), not a distance scan or grid
    -- collision. Assign the base radius each update so BFFS never compounds.
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_ALL
    familiar.CollisionDamage = 0
    familiar.Size = FAN_BLOCK_RADIUS
        * (player:HasCollectible(BFFS) and FAN_BFFS_BLOCK_RADIUS_MULTIPLIER or 1)
    familiar:FollowParent()

    local sprite = familiar:GetSprite()
    local data = familiar:GetData()
    -- The painted frame faces slightly right. Mirror only after the familiar
    -- moves clearly across the player, keeping the previous direction near
    -- the centre line so follower bobbing cannot make it flicker.
    local horizontalOffset = familiar.Position.X - player.Position.X
    if horizontalOffset < -FAN_FLIP_DISTANCE then
        sprite.FlipX = false
    elseif horizontalOffset > FAN_FLIP_DISTANCE then
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
end

function Mizuki:BlockProjectileOnFanCollision(familiar, collider)
    if not getFanOwner(familiar) then return true end
    local projectile = collider:ToProjectile()
    if projectile and projectile:Exists()
        and not projectile:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER) then
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
    -- Only the successful roll destroys a hostile projectile. Skip native
    -- collision response so missed rolls pass through, with no contact damage
    -- or pushing against players, friendly tears, enemies or other familiars.
    return true
end

-- Shared by the reward roll and EID so the displayed chance stays exact.
function Mizuki.GetFanRoomClearChance(player)
    local luck = math.max(player.Luck, 0)
    local luckChance = FAN_LUCK_CLEAR_CAP * luck / (luck + FAN_LUCK_SOFT_CAP)
    if player:HasCollectible(LUCKY_FOOT) then luckChance = luckChance * FAN_LUCKY_FOOT_MULTIPLIER end
    return luckChance
        + (player:HasCollectible(BFFS) and FAN_BFFS_CLEAR_CHANCE or 0)
end

function Mizuki:RollFanRoomClearGifts()
    for _, entity in ipairs(Isaac.FindByType(
        EntityType.ENTITY_FAMILIAR, Mizuki.FanVariant, -1, false, false
    )) do
        local familiar = entity:ToFamiliar()
        local player = getFanOwner(familiar)
        if player then
            local chance = Mizuki.GetFanRoomClearChance(player)
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

function Mizuki:InitializeFanFloorGift(isContinued)
    if isContinued == true then return end

    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isMizuki(player) then
            if isContinued == false and not player:HasCollectible(Mizuki.FanItem) then
                -- Resolve the custom item by ID instead of a localized players.xml name.
                player:AddCollectible(Mizuki.FanItem, 0, false)
            end
            queueFloorGiftForPlayer(player)
        end
    end
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
Mizuki:AddCallback(ModCallbacks.MC_PRE_FAMILIAR_COLLISION, Mizuki.BlockProjectileOnFanCollision, Mizuki.FanVariant)
Mizuki:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, Mizuki.RollFanRoomClearGifts)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeFanFloorGift)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.InitializeFanFloorGift)
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.DispatchFanFloorGift)
