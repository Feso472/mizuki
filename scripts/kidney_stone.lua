-- Kidney Stone: the fire-rate-drop burst the cannons fire when the Tears
-- stat spikes mid-shot.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local removeActiveMizukiBeams = Mizuki.removeActiveMizukiBeams

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
        if previousInterval / math.max(currentInterval, 0.001)
            >= KIDNEY_STONE_TRIGGER_FIRE_RATE_RATIO
        then
            burst = {
                Elapsed = 0,
                StableFrames = 0,
                LastMaxFireDelay = currentMaxFireDelay,
                Direction = data.MizukiLastShootDirection,
            }
            data.MizukiKidneyStoneBurst = burst
            removeActiveMizukiBeams(data)
            data.MizukiCharge = 0
            data.MizukiAim = nil
            data.MizukiChargeBarFullFrames = nil
        end
    end

    if not burst then
        return nil
    end

    local aim = player:GetAimDirection()
    if aim:Length() > 0.01 then
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

    local rockBottom = player:HasCollectible(
        CollectibleType.COLLECTIBLE_ROCK_BOTTOM
    )
    local naturallyFinished = burst.Elapsed >= KIDNEY_STONE_MIN_BURST_FRAMES
        and burst.StableFrames >= KIDNEY_STONE_STABLE_FRAMES
    local timedOut = not rockBottom
        and burst.Elapsed >= KIDNEY_STONE_MAX_BURST_FRAMES
    if not rockBottom and (naturallyFinished or timedOut) then
        data.MizukiKidneyStoneBurst = nil
        return nil
    end

    return burst
end

Mizuki.updateKidneyStoneBurst = updateKidneyStoneBurst
