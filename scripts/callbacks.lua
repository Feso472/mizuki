-- Core callback order is explicit; feature modules register after this.
local Config = Mizuki.Config

function Mizuki.registerCoreCallbacks()
    Mizuki:AddCallback(
        ModCallbacks.MC_POST_PLAYER_INIT,
        Mizuki.LoadPlayerAnm2
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_PEFFECT_UPDATE,
        Mizuki.EnsureHairCostume
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_USE_ITEM,
        Mizuki.QueueHairCostumeRerollRefresh,
        CollectibleType.COLLECTIBLE_D4
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_USE_ITEM,
        Mizuki.QueueHairCostumeRerollRefresh,
        CollectibleType.COLLECTIBLE_D100
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_EFFECT_UPDATE,
        Mizuki.CaptureTargetReticle,
        EffectVariant.TARGET
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_EFFECT_UPDATE,
        Mizuki.CaptureTargetReticle,
        EffectVariant.OCCULT_TARGET
    )

    Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
        local beam = laser:GetData().MizukiSpiritSwordBeam
        if beam and beam.Laser and GetPtrHash(beam.Laser) == GetPtrHash(laser) then
            Mizuki.syncSpiritSwordBeam(beam)
        end
    end)

    Mizuki.registerCannonControlCallbacks()

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_LASER_UPDATE,
        Mizuki.FinalizeLudovicoKnifeRoomEntry
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_UPDATE,
        Mizuki.CompleteLudovicoKnifeRoomEntry
    )

    Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateWeapon)

    Mizuki:AddPriorityCallback(
        ModCallbacks.MC_ENTITY_TAKE_DMG,
        CallbackPriority.EARLY,
        Mizuki.ThrottleLudovicoTechXDamage
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_ENTITY_TAKE_DMG,
        Mizuki.TriggerEpicFetusStrike
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_ENTITY_TAKE_DMG,
        Mizuki.TriggerCursedEyeTeleport,
        EntityType.ENTITY_PLAYER
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_UPDATE,
        Mizuki.StartPendingCursedEyeTeleport
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_LASER_UPDATE,
        Mizuki.UpdateCannonLaser
    )

    Mizuki:AddPriorityCallback(
        ModCallbacks.MC_POST_UPDATE, CallbackPriority.LATE,
        Mizuki.FinalizeEpicFetusTargets
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_USE_ITEM,
        Mizuki.QueueBoxOfFriendsCannonRefresh,
        Config.BOX_OF_FRIENDS
    )

    Mizuki:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, Mizuki.EvaluateCharacterCache)
    -- Final weapon conversion follows LATE passes that reconstruct vanilla
    -- stats. Colors, familiars and the other caches retain their order.
    Mizuki:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, Config.WEAPON_STAT_CACHE_PRIORITY,
        Mizuki.EvaluateCharacterWeaponStats, CacheFlag.CACHE_DAMAGE)
    Mizuki:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, Config.WEAPON_STAT_CACHE_PRIORITY,
        Mizuki.EvaluateCharacterWeaponStats, CacheFlag.CACHE_FIREDELAY)

    Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE,
        Mizuki.CountCharacterStatDamage, EntityType.ENTITY_PLAYER)
    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Mizuki.InitializeCharacterStats)
    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, Mizuki.ResetCharacterStatsForFloor)
    Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, Mizuki.SaveCharacterStats)

    Mizuki:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, Mizuki.InitCannonFamiliar, Mizuki.CannonVariant)

    Mizuki:AddCallback(
        ModCallbacks.MC_FAMILIAR_UPDATE,
        Mizuki.UpdateCannonFamiliar,
        Mizuki.CannonVariant
    )

    Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Mizuki.ResetCannonsForNewRoom)

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_FAMILIAR_RENDER,
        Mizuki.RenderCannon,
        Mizuki.CannonVariant
    )

    Mizuki:AddCallback(
        ModCallbacks.MC_POST_LASER_RENDER,
        Mizuki.RenderLudovicoCannonsAboveRing
    )

    Mizuki:AddCallback(ModCallbacks.MC_POST_FAMILIAR_RENDER, Mizuki.RenderChargeBar, Mizuki.CannonVariant)

    Mizuki:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, Mizuki.RenderLowFireRateBar)
end
