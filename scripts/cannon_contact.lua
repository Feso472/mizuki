-- The Familiar's native collision circle detects contact. Each cannon owns
-- its damage clock; copied cannons no longer share a per-pair schedule.

function Mizuki.updateCannonCollisionSize(cannon, scaleMultiplier, returning)
    local radius = Mizuki.LUDOVICO_CANNON_MIN_HIT_RADIUS
        * (scaleMultiplier or 1)
        * (returning and 1.5 or 1)
    cannon.Size = radius
    return radius
end

function Mizuki:DamageOnCannonCollision(cannon, collider)
    local cannonData = cannon:GetData()
    local player = cannon.Player
    if cannonData.MizukiAwaitingInitialLayout
        or cannonData.MizukiIsIdle
        or not player or not player:Exists()
        or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        or not collider:IsVulnerableEnemy()
        or collider:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
    then
        return true
    end

    if cannonData.MizukiLudovicoOrbiting then
        -- Contact takes priority for Epic Fetus targeting even when this
        -- cannon's damage clock has not elapsed yet.
        Mizuki.queueLudovicoEpicFetusEnemy(player, collider, true)
    end

    local frame = Game():GetFrameCount()
    local interval = math.max(player.MaxFireDelay, 1) + 1
    local schedules = cannonData.MizukiContactDamageSchedules or {}
    cannonData.MizukiContactDamageSchedules = schedules
    local targetHash = GetPtrHash(collider)
    local targetSeed = collider.InitSeed
    local schedule = schedules[targetHash]
    if schedule and schedule.TargetInitSeed ~= targetSeed then
        schedule = nil
        schedules[targetHash] = nil
    end
    if schedule then
        if math.abs(schedule.Interval - interval) > 0.0001 then
            local remaining = math.max(0, schedule.NextFrame - frame)
            schedule.NextFrame = frame
                + remaining * interval / schedule.Interval
            schedule.Interval = interval
        end
        if frame + 0.0001 < schedule.NextFrame then
            return true
        end
        repeat
            schedule.NextFrame = schedule.NextFrame + interval
        until schedule.NextFrame > frame
    else
        schedules[targetHash] = {
            TargetInitSeed = targetSeed,
            NextFrame = frame + interval,
            Interval = interval,
        }
    end

    collider:TakeDamage(
        player.Damage
            * Mizuki.LUDOVICO_CANNON_DAMAGE_MULTIPLIER
            * (cannonData.MizukiContactDamageMultiplier or 1),
        0,
        EntityRef(cannon),
        0
    )
    -- The callback supplies the damage. Do not also run native damage or
    -- physical collision response.
    return true
end

Mizuki:AddCallback(
    ModCallbacks.MC_PRE_FAMILIAR_COLLISION,
    Mizuki.DamageOnCannonCollision,
    Mizuki.CannonVariant
)
