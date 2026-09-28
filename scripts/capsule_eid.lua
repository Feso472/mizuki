-- Present the capsule as an ordinary Experimental Pill. The card ID is ready
-- when this file loads; registration waits for game start so EID can load too.
local function registerExperimentalCapsuleEID()
    if not EID or not EID.addCard or not EID.addIcon then
        return
    end

    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ 随机提升1项属性#↓ 随机降低1项属性",
        "实验性胶囊",
        "zh_cn"
    )
    EID:addCard(
        Mizuki.ExperimentalCapsuleCard,
        "↑ Increases 1 random stat#↓ Decreases 1 random stat",
        "Experimental Pill",
        "en_us"
    )

    local capsuleEIDIcon = Sprite()
    capsuleEIDIcon:Load("gfx/items/mizuki/experimental_capsule.anm2", true)
    capsuleEIDIcon:Play("EID", true)
    EID:addIcon(
        "Card" .. Mizuki.ExperimentalCapsuleCard,
        "EID",
        0,
        9,
        8,
        0,
        1,
        capsuleEIDIcon
    )
end

Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerExperimentalCapsuleEID)
