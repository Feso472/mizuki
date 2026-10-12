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

Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, restoreSneezeMouth,
    EffectVariant.BLOOD_EXPLOSION)
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, restoreSneezeMouth,
    EffectVariant.HAEMO_TRAIL)
