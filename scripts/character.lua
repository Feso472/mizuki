-- Character appearance, stat caches and capsule state access.
local Config = Mizuki.Config
local json = require("json")
-- Native constants are independent of the adjustable Mizuki target values.
local NativeStats = {
    TechnologyBrimstoneDamage = 1.5,
    BrimstoneTears = 1 / 3,
    BombTears = 1 / 2.5,
    BoneTears = 0.5,
    LungTears = 1 / 4.3,
    TechXLungTears = 1 / 3.1,
}
local CharacterCacheFlags = {
    CacheFlag.CACHE_DAMAGE, CacheFlag.CACHE_FIREDELAY,
    CacheFlag.CACHE_SPEED, CacheFlag.CACHE_SHOTSPEED, CacheFlag.CACHE_RANGE,
    CacheFlag.CACHE_LUCK, CacheFlag.CACHE_TEARFLAG, CacheFlag.CACHE_TEARCOLOR,
}

-- Shared character layer, independent of item-side tear colors.
function Mizuki.getCharacterTearTint(player, intensityOverride, baseColor)
    local tint = Mizuki.WeaponParameters.TearTint
    local belial = player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL)
    if not intensityOverride and not belial and not baseColor then return Config.MIZUKI_TEAR_COLOR end
    local intensity = (intensityOverride or tint.ColorizeIntensity) / Mizuki.RuntimeParameters.ColorByteMax
    local multiplier = tint.BelialMultiplier
    local source = baseColor or Config.MIZUKI_TEAR_COLOR
    local color = Color.Lerp(source, source, 0)
    color:SetColorize(intensity * tint.Red * (belial and multiplier.Red or 1),
        intensity * tint.Green * (belial and multiplier.Green or 1),
        intensity * tint.Blue * (belial and multiplier.Blue or 1), 1)
    return color
end

function Mizuki.isMizuki(player)
    return player:GetPlayerType() == Mizuki.PlayerType
end

-- Native getters/callbacks may return different Lua wrappers for one entity.
function Mizuki.isSameEntity(first, second)
    return first ~= nil and second ~= nil and first:Exists() and second:Exists()
        and GetPtrHash(first) == GetPtrHash(second) and first.InitSeed == second.InitSeed
end

function Mizuki:LoadPlayerAnm2(player)
    if Mizuki.isMizuki(player) then
        player:GetSprite():Load(Mizuki.PlayerAnm2, true)
    end
end

function Mizuki:EnsureHairCostume(player)
    if not Mizuki.isMizuki(player) then
        return
    end

    local data = player:GetData()
    if Mizuki.HairCostume < 0 then
        return
    end

    local refreshFrame = data.MizukiHairCostumeRefreshFrame
    if refreshFrame then
        if Game():GetFrameCount() > refreshFrame then
            -- D4/D100 can rebuild the player's costumes without clearing our
            -- "applied" marker. Refresh once after the reroll has finished.
            player:TryRemoveNullCostume(Mizuki.HairCostume)
            player:AddNullCostume(Mizuki.HairCostume)
            data.MizukiHairCostumeApplied = true
            data.MizukiHairCostumeRefreshFrame = nil
        end
        return
    end

    if not data.MizukiHairCostumeApplied then
        player:AddNullCostume(Mizuki.HairCostume)
        data.MizukiHairCostumeApplied = true
    end
end

function Mizuki:QueueHairCostumeRerollRefresh(collectible, rng, player)
    if Mizuki.isMizuki(player) then
        player:GetData().MizukiHairCostumeRefreshFrame = Game():GetFrameCount()
    end
end

function Mizuki.getPlayerIndex(player)
    local game = Game()
    local playerHash = GetPtrHash(player)
    for index = 0, game:GetNumPlayers() - 1 do
        if GetPtrHash(Isaac.GetPlayer(index)) == playerHash then
            return index
        end
    end
    return player.ControllerIndex or 0
end

function Mizuki.getCapsuleState(player)
    local index = Mizuki.getPlayerIndex(player)
    Mizuki.capsuleStates[index] = Mizuki.capsuleStates[index] or {}
    return Mizuki.capsuleStates[index]
end

-- Desired bonuses describe Mizuki's attacks. The native side below separately
-- reads weapon tags; possession alone cannot tell which bonus vanilla applied.
function Mizuki.getTechnologySynergyMultiplier(player)
    local C = CollectibleType
    if not player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY)
        or not player:HasCollectible(C.COLLECTIBLE_BRIMSTONE) then return 1 end
    return Config.TECHNOLOGY_BRIMSTONE_DAMAGE_MULTIPLIER
end

-- Technology Zero has no native damage synergy or corresponding weapon tag.
-- Its custom bonus is one factor, even when both partner items are present.
function Mizuki.getTechnologyZeroSynergyMultiplier(player)
    local C = CollectibleType
    if player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY_ZERO)
        and (player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY)
            or player:HasCollectible(C.COLLECTIBLE_BRIMSTONE)) then
        return Config.TECHNOLOGY_ZERO_SYNERGY_DAMAGE_MULTIPLIER
    end
    return 1
end

-- Beam controllers already receive these factors through the character cache.
-- Separate weapons receive them only on their additional Brimstone entities.
function Mizuki.getSecondaryBrimstoneDamageMultiplier(player)
    if not Mizuki.isMizuki(player) or Mizuki.usesCannonBeamWeapon(player) then return 1 end
    return Mizuki.getTechnologySynergyMultiplier(player)
        * Mizuki.getTechnologyZeroSynergyMultiplier(player)
end

function Mizuki.getCharacterDamageMultiplier(player)
    local C = CollectibleType
    if not (player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY)
        or player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY_ZERO)
        or player:HasCollectible(C.COLLECTIBLE_BRIMSTONE)) then
        return Config.DEFAULT_DAMAGE_MULTIPLIER
    end
    return Config.TECHNOLOGY_ZERO_DAMAGE_MULTIPLIER
end

-- Optional, read-only compatibility. These are the only extension getters used
-- here; vanilla Repentance does not expose the corresponding hidden values.
local function getExtendedStat(player, method, fallback)
    if REPENTOGON and player[method] then return player[method](player) end
    return fallback
end

local function getStatFloorKey()
    local game = Game()
    local level, seeds = game:GetLevel(), game:GetSeeds()
    return table.concat({seeds:GetStartSeed(), level:GetStage(), level:GetStageType(),
        seeds:GetStageSeed(level:GetStage())}, ":")
end

local function getStatState(player)
    local data = player:GetData()
    local floor = getStatFloorKey()
    if not data.MizukiWeaponStats or data.MizukiWeaponStats.Floor ~= floor then
        data.MizukiWeaponStats = {Floor = floor, DamageTaken = 0}
    end
    return data.MizukiWeaponStats
end

local function getMultishotTears(player, fetus)
    local C, effects = CollectibleType, player:GetEffects()
    if player:HasCollectible(C.COLLECTIBLE_20_20) then return 1 end
    if player:HasCollectible(C.COLLECTIBLE_MUTANT_SPIDER)
        or (player:HasCollectible(C.COLLECTIBLE_POLYPHEMUS) and not fetus) then return 0.42 end
    if player:HasCollectible(C.COLLECTIBLE_INNER_EYE)
        or effects:HasCollectibleEffect(C.COLLECTIBLE_INNER_EYE)
        or effects:HasNullEffect(NullItemID.ID_REVERSE_HANGED_MAN) then return 0.51 end
    return 1
end

-- Native stages 8..10 for damage, and 3/4/6/8 for tears. Do not replace the
-- source of these modifiers with the custom attack-selection chain.
local function getNativeWeaponStats(player)
    local C = CollectibleType
    local brimstone = player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
    local techX = player:HasWeaponType(WeaponType.WEAPON_TECH_X)
    local lung = player:HasWeaponType(WeaponType.WEAPON_MONSTROS_LUNGS)
    local tears = player:HasWeaponType(WeaponType.WEAPON_TEARS)
    local fetus = player:HasWeaponType(WeaponType.WEAPON_FETUS)
    local ipecac = player:HasCollectible(C.COLLECTIBLE_IPECAC)
    local multipleBrimstone = brimstone and player:GetCollectibleNum(C.COLLECTIBLE_BRIMSTONE) > 1
    local technologyBonus = player:HasCollectible(C.COLLECTIBLE_TECHNOLOGY)
        and ((brimstone and not multipleBrimstone)
            or (not brimstone and techX and player:HasCollectible(C.COLLECTIBLE_BRIMSTONE)))
    return {
        -- Multiple Brimstones' native x1.2 stays in the input damage. It skips
        -- vanilla's Technology x1.5, so the two effects must not be conflated.
        BrimstoneDamage = technologyBonus and NativeStats.TechnologyBrimstoneDamage or 1,
        HaemolacriaDamage = player:HasCollectible(C.COLLECTIBLE_HAEMOLACRIA) and 1.5 or 1,
        IpecacDamage = ipecac and ((tears or lung or fetus) and 40 or 2) or 0,
        MultishotTears = getMultishotTears(player, fetus),
        IpecacTears = ipecac and (tears or lung or player:HasWeaponType(WeaponType.WEAPON_LASER))
            and 1 / 3 or 1,
        WeaponTears = brimstone and NativeStats.BrimstoneTears
            or player:HasWeaponType(WeaponType.WEAPON_BOMBS) and NativeStats.BombTears
            or player:HasWeaponType(WeaponType.WEAPON_BONE) and NativeStats.BoneTears or 1,
        LungTears = lung and NativeStats.LungTears
            or (techX and player:HasCollectible(C.COLLECTIBLE_MONSTROS_LUNG)
                and NativeStats.TechXLungTears or 1),
    }
end

-- Effects that survive as parallel attacks keep their own cost; an extra
-- Brimstone fireball on a fetus/knife is not a charged Brimstone primary.
local function getDesiredWeaponStats(player, native)
    local C = CollectibleType
    local mode = Mizuki.getCannonWeaponMode(player)
    local beam = Mizuki.usesCannonBeamWeapon(player, mode)
    local brimstone = beam and player:HasCollectible(C.COLLECTIBLE_BRIMSTONE)
    local technologyZero = mode == "technology_zero"
    local haemolacria = player:HasCollectible(C.COLLECTIBLE_HAEMOLACRIA)
    local lung = player:HasCollectible(C.COLLECTIBLE_MONSTROS_LUNG)
    local bombs = player:HasCollectible(C.COLLECTIBLE_DR_FETUS)
        and not player:HasCollectible(C.COLLECTIBLE_EPIC_FETUS)
    local characterTears = (haemolacria or mode == "berserk" or brimstone
        or technologyZero or mode == "trisagion") and 1 or Config.DEFAULT_TEARS_MULTIPLIER
    local weaponTears = 1
    if mode == "berserk" then
        weaponTears = NativeStats.BoneTears
    elseif brimstone then
        weaponTears = Config.BRIMSTONE_TEARS_MULTIPLIER
    elseif technologyZero then
        weaponTears = Config.TECHNOLOGY_ZERO_TEARS_MULTIPLIER
    elseif bombs then
        weaponTears = Config.DR_FETUS_TEARS_MULTIPLIER
    end
    local lungTears = 1
    if lung then
        if mode == "c_section" then
            lungTears = 1 / Mizuki.WeaponParameters.MonstrosLungTearsDivisor
        elseif mode == "tech_x" then
            lungTears = NativeStats.TechXLungTears
        end
    end
    local laserOrTearPrimary = mode == "ordinary" or mode == "trisagion"
        or (mode == "ludovico" and not player:HasCollectible(C.COLLECTIBLE_MOMS_KNIFE))
    local ipecacTears = player:HasCollectible(C.COLLECTIBLE_IPECAC)
        and laserOrTearPrimary and not brimstone and 1 / 3 or 1
    local multishotTears = getMultishotTears(player, mode == "c_section")
    -- Haemolacria's shared nonlinear entry is intentionally preserved, including
    -- its Ipecac input. No ratio may be moved across that nonlinear conversion.
    if haemolacria then
        ipecacTears, multishotTears = native.IpecacTears, native.MultishotTears
    end
    return {
        BrimstoneDamage = beam and (Mizuki.getTechnologySynergyMultiplier(player)
            * Mizuki.getTechnologyZeroSynergyMultiplier(player)) or 1,
        HaemolacriaDamage = native.HaemolacriaDamage,
        IpecacDamage = player:HasCollectible(C.COLLECTIBLE_IPECAC)
            and (mode == "c_section" and 40 or 2) or 0,
        MultishotTears = multishotTears,
        IpecacTears = ipecacTears,
        WeaponTears = weaponTears,
        LungTears = lungTears,
        CharacterDamage = Mizuki.getCharacterDamageMultiplier(player),
        CharacterTears = characterTears,
    }
end

local function getWeaponStats(player)
    local native = getNativeWeaponStats(player)
    return native, getDesiredWeaponStats(player, native)
end

-- Native damage stage 11, after Ipecac. Only needed when crossing its flat
-- addition; ordinary multiplicative changes do not require guessing this tail.
local function getDamageTailMultiplier(player)
    local C, effects = CollectibleType, player:GetEffects()
    local multiplier = 1
    if player:HasCollectible(C.COLLECTIBLE_CRICKETS_HEAD)
        or player:HasCollectible(C.COLLECTIBLE_MAGIC_MUSHROOM)
        or effects:HasCollectibleEffect(C.COLLECTIBLE_MAGIC_MUSHROOM)
        or (player:HasCollectible(C.COLLECTIBLE_BLOOD_MARTYR)
            and effects:HasCollectibleEffect(C.COLLECTIBLE_BOOK_OF_BELIAL)) then
        multiplier = multiplier * 1.5
    end
    if player:HasCollectible(C.COLLECTIBLE_EVES_MASCARA) then multiplier = multiplier * 2 end
    if player:HasCollectible(C.COLLECTIBLE_ALMOND_MILK) then multiplier = multiplier * 0.3
    elseif player:HasCollectible(C.COLLECTIBLE_SOY_MILK) then multiplier = multiplier * 0.2 end
    if player:HasCollectible(C.COLLECTIBLE_20_20) then multiplier = multiplier * 0.8 end
    if player:HasCollectible(C.COLLECTIBLE_DEAD_EYE) then
        -- The getter returns raw charges. Native 0x767016 uses 0.125, not
        -- CuerLib's 0.25; copying that coefficient doubles the correction.
        multiplier = multiplier * (1 + 0.125 * getExtendedStat(player, "GetDeadEyeCharge", 0))
    end
    local succubi = 0
    for _, familiar in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.SUCCUBUS)) do
        if familiar.Position:DistanceSquared(player.Position) < 10000 then succubi = succubi + 1 end
    end
    return multiplier * 1.5 ^ succubi * getExtendedStat(player, "GetD8DamageModifier", 1)
end

local function getDamageCorrection(player, native, desired)
    if not native then native, desired = getWeaponStats(player) end
    local changed = native.BrimstoneDamage ~= desired.BrimstoneDamage
        or native.IpecacDamage ~= desired.IpecacDamage
    local tail = changed and (native.IpecacDamage ~= 0 or desired.IpecacDamage ~= 0)
        and getDamageTailMultiplier(player) or 1
    return {Native = native, Desired = desired, TailMultiplier = tail,
        CrownMultiplier = 1 + 0.2 * player:GetTrinketMultiplier(TrinketType.TRINKET_CRACKED_CROWN)}
end

local function applyDamageCorrection(damage, correction)
    local native, desired = correction.Native, correction.Desired
    local tail, crown = correction.TailMultiplier, correction.CrownMultiplier
    if native.BrimstoneDamage == desired.BrimstoneDamage
        and native.HaemolacriaDamage == desired.HaemolacriaDamage
        and native.IpecacDamage == desired.IpecacDamage then
        return damage * desired.CharacterDamage
    end
    -- Reverse native stages, then apply desired stages in forward order.
    if damage > 3.5 then damage = (damage - 3.5) / crown + 3.5 end
    damage = damage / tail
    damage = damage - native.IpecacDamage
    damage = damage / native.HaemolacriaDamage / native.BrimstoneDamage
    damage = damage * desired.BrimstoneDamage * desired.HaemolacriaDamage
    damage = (damage + desired.IpecacDamage) * tail
    if damage > 3.5 then damage = (damage - 3.5) * crown + 3.5 end
    return damage * desired.CharacterDamage
end

local function getLateTearsAddition(player)
    local C, effects = CollectibleType, player:GetEffects()
    local addition = effects:HasCollectibleEffect(C.COLLECTIBLE_BERSERK) and 2 or 0
    local gust = player:HasCollectible(C.COLLECTIBLE_BLOODY_GUST)
    local bloodRights = effects:HasCollectibleEffect(C.COLLECTIBLE_BLOOD_RIGHTS)
    if not gust and not bloodRights then return addition end
    local hits = getStatState(player).DamageTaken
    if gust then
        local gustHits = math.min(hits, 6)
        addition = addition + 0.05 * gustHits ^ 2 + 0.2 * gustHits
    end
    if bloodRights then
        addition = addition + 0.33 + 0.15 * math.min(hits, 999)
    end
    return addition
end

local function getFireRateCorrection(player, native, desired)
    if not native then native, desired = getWeaponStats(player) end
    return {Native = native, Desired = desired, Addition = getLateTearsAddition(player),
        D8Multiplier = getExtendedStat(player, "GetD8FireDelayModifier", 1),
        FlatModifier = Config.TEARS_MODIFIER}
end

local function applyFireRateCorrection(delay, correction)
    local native, desired = correction.Native, correction.Desired
    local addition, d8 = correction.Addition, correction.D8Multiplier
    local tears = Mizuki.RuntimeParameters.LogicFramesPerSecond / (delay + 1)
    -- Stages 1/2/5/7/9/10 stay native. Their unchanged multipliers commute
    -- with these corrections; stage 5 also keeps its original nonlinear input.
    tears = tears / d8 - addition
    tears = tears / native.LungTears / native.WeaponTears / native.IpecacTears / native.MultishotTears
    tears = (tears + correction.FlatModifier) * desired.MultishotTears * desired.IpecacTears
        * desired.WeaponTears * desired.LungTears * desired.CharacterTears
    tears = (tears + addition) * d8
    return math.max(Mizuki.RuntimeParameters.MinimumFireInterval - 1,
        Mizuki.RuntimeParameters.LogicFramesPerSecond / tears - 1)
end

-- Only compare our correction inputs, never the already-corrected HUD values.
-- Refresh checks share one weapon snapshot. Cache callbacks build a fresh one
-- after earlier callbacks, then record the exact inputs they actually applied.
function Mizuki.getCharacterCacheInputs(player, flag, native, desired)
    if flag == CacheFlag.CACHE_DAMAGE then
        local profile = getDamageCorrection(player, native, desired)
        local native, desired = profile.Native, profile.Desired
        -- A phase change also invalidates corrections retained across a Lua reload.
        return {Config.WEAPON_STAT_CACHE_PRIORITY,
            native.BrimstoneDamage, native.HaemolacriaDamage, native.IpecacDamage,
            desired.BrimstoneDamage, desired.HaemolacriaDamage, desired.IpecacDamage,
            profile.TailMultiplier, profile.CrownMultiplier, desired.CharacterDamage}, profile
    elseif flag == CacheFlag.CACHE_FIREDELAY then
        local profile = getFireRateCorrection(player, native, desired)
        local native, desired = profile.Native, profile.Desired
        return {Config.WEAPON_STAT_CACHE_PRIORITY,
            native.MultishotTears, native.IpecacTears, native.WeaponTears, native.LungTears,
            desired.MultishotTears, desired.IpecacTears, desired.WeaponTears, desired.LungTears, desired.CharacterTears,
            profile.Addition, profile.D8Multiplier, profile.FlatModifier}, profile
    elseif flag == CacheFlag.CACHE_SPEED then
        return {Config.MOVE_SPEED_MODIFIER}
    elseif flag == CacheFlag.CACHE_LUCK then
        return {Config.LUCK_MODIFIER}
    elseif flag == CacheFlag.CACHE_SHOTSPEED or flag == CacheFlag.CACHE_RANGE then
        return {}
    elseif flag == CacheFlag.CACHE_TEARFLAG then
        return {player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE),
            Mizuki.usesCannonTechX(player)
                and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)}
    elseif flag == CacheFlag.CACHE_TEARCOLOR then
        local tint = Mizuki.WeaponParameters.TearTint
        local multiplier = tint.BelialMultiplier
        return {player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_BOOK_OF_BELIAL),
            Mizuki.usesCSectionWeapon(player),
            Mizuki.usesCannonTrisagion(player),
            tint.Red, tint.Green, tint.Blue, tint.ColorizeIntensity, tint.TrisagionColorizeIntensity,
            multiplier.Red, multiplier.Green, multiplier.Blue}
    end
end

function Mizuki.refreshCharacterStats(player, extraFlags)
    local data = player:GetData()
    local flags = extraFlags or 0
    local applied = data.MizukiAppliedStatInputs or {}
    local native, desired = getWeaponStats(player)
    for _, flag in ipairs(CharacterCacheFlags) do
        local inputs = Mizuki.getCharacterCacheInputs(player, flag, native, desired)
        local previous = applied[flag]
        local changed = not previous or #previous ~= #inputs
        if not changed then
            for index, value in ipairs(inputs) do
                if previous[index] ~= value then changed = true; break end
            end
        end
        if changed then flags = flags | flag end
    end
    if flags ~= 0 then
        player:AddCacheFlags(flags)
        player:EvaluateItems()
    end
end

local function rememberCharacterStatInputs(player, cacheFlag, inputs)
    inputs = inputs or Mizuki.getCharacterCacheInputs(player, cacheFlag)
    if inputs then
        local data = player:GetData()
        data.MizukiAppliedStatInputs = data.MizukiAppliedStatInputs or {}
        data.MizukiAppliedStatInputs[cacheFlag] = inputs
    end
end

-- Weapon conversion consumes the completed common stats. Libraries that
-- reverse vanilla damage formulas must run before this changes their meaning.
function Mizuki:EvaluateCharacterWeaponStats(player, cacheFlag)
    if not Mizuki.isMizuki(player) then return end
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE and cacheFlag ~= CacheFlag.CACHE_FIREDELAY then return end
    local inputs, correction = Mizuki.getCharacterCacheInputs(player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        player.Damage = applyDamageCorrection(player.Damage, correction)
    else
        player.MaxFireDelay = applyFireRateCorrection(player.MaxFireDelay, correction)
    end
    rememberCharacterStatInputs(player, cacheFlag, inputs)
end

function Mizuki:EvaluateCharacterCache(player, cacheFlag)
    if not Mizuki.isMizuki(player) then return end
    if cacheFlag == CacheFlag.CACHE_DAMAGE or cacheFlag == CacheFlag.CACHE_FIREDELAY then return end
    if cacheFlag == CacheFlag.CACHE_TEARCOLOR then
        local data = player:GetData()
        -- FireKnife inherits the player's final TearColor. Preserve the colour
        -- produced by vanilla and other items before Mizuki adds her character
        -- pink colorize, so the cannon knives can discard only Mizuki's layer.
        data.MizukiMomKnifeBaseColor = player.TearColor
        -- Fetuses and sword waves omit only Mizuki's tint; other attacks inherit it.
        data.MizukiUntintedTearColor = Color.Lerp(player.TearColor, player.TearColor, 0)
        data.MizukiMomKnifeColorRevision =
            (data.MizukiMomKnifeColorRevision or 0) + 1
        local characterTint = Mizuki.getCharacterTearTint(player)
        local tearTint = Mizuki.usesCannonTrisagion(player)
            and Mizuki.getCharacterTearTint(player, Mizuki.WeaponParameters.TearTint.TrisagionColorizeIntensity)
            or characterTint
        player.TearColor = player.TearColor * tearTint
        player.LaserColor = player.LaserColor * characterTint
    elseif cacheFlag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = player.MoveSpeed + Config.MOVE_SPEED_MODIFIER
    elseif cacheFlag == CacheFlag.CACHE_TEARFLAG then
        if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
            player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
        end
        local occultTechXHoming = Mizuki.usesCannonTechX(player)
            and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
        if occultTechXHoming then
            player.TearFlags = player.TearFlags | TearFlags.TEAR_HOMING
        end
    elseif cacheFlag == CacheFlag.CACHE_LUCK then
        player.Luck = player.Luck + Config.LUCK_MODIFIER
    elseif cacheFlag == CacheFlag.CACHE_FAMILIARS then
        local cannonsPerSide = Mizuki.getExpectedCannonPairs(player)
        player:GetData().MizukiExpectedCannonPairs = cannonsPerSide
        local rng = player:GetCollectibleRNG(Config.BOX_OF_FRIENDS)
        player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 1)
        player:CheckFamiliar(Mizuki.CannonVariant, cannonsPerSide, rng, nil, 2)
        player:CheckFamiliar(
            Mizuki.FanVariant,
            player:GetCollectibleNum(Mizuki.FanItem)
                + player:GetEffects():GetCollectibleEffectNum(Mizuki.FanItem),
            player:GetCollectibleRNG(Mizuki.FanItem),
            Isaac.GetItemConfig():GetCollectible(Mizuki.FanItem)
        )
    end
    rememberCharacterStatInputs(player, cacheFlag)
end

-- This is the native shared floor counter used by Bloody Lust, Bloody Gust
-- and Blood Rights, not the number of currently visible Gust effects. Keeping
-- it on the player also lets native Hour Glass rewind restore the same state.
function Mizuki:CountCharacterStatDamage(entity)
    local player = entity:ToPlayer()
    if not player or not Mizuki.isMizuki(player) then return end
    local C = CollectibleType
    if not (player:HasCollectible(C.COLLECTIBLE_BLOODY_LUST)
        or player:HasCollectible(C.COLLECTIBLE_BLOODY_GUST)
        or player:HasCollectible(C.COLLECTIBLE_BLOOD_RIGHTS)) then return end
    -- Ordinary immunity is checked before MC_ENTITY_TAKE_DMG. Astral Projection
    -- is the vanilla Mizuki-relevant cancellation after it (0x7742B5): its
    -- armed effect has count 1. Merely owning the item does not cancel all hits.
    if player:GetEffects():GetCollectibleEffectNum(C.COLLECTIBLE_ASTRAL_PROJECTION) == 1 then return end
    local state = getStatState(player)
    state.DamageTaken = state.DamageTaken + 1
end

local function readStatSaveRoot()
    if not Mizuki:HasData() then return {} end
    local ok, root = pcall(json.decode, Mizuki:LoadData())
    return ok and type(root) == "table" and root or {}
end

function Mizuki:InitializeCharacterStats(continued)
    local game = Game()
    local saved = continued and readStatSaveRoot().CharacterStats
    if type(saved) ~= "table" then saved = nil end
    local floor = getStatFloorKey()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then
            local entry = saved and saved.Floor == floor and saved.Players
                and saved.Players[tostring(index)]
            player:GetData().MizukiWeaponStats = {Floor = floor,
                DamageTaken = type(entry) == "number" and math.max(0, math.floor(entry)) or 0}
            player:GetData().MizukiAppliedStatInputs = nil
        end
    end
end

function Mizuki:ResetCharacterStatsForFloor()
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then getStatState(player).DamageTaken = 0 end
    end
end

function Mizuki:SaveCharacterStats(shouldSave)
    if not shouldSave then return end
    local players = {}
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then players[tostring(index)] = getStatState(player).DamageTaken end
    end
    local root = readStatSaveRoot()
    root.CharacterStats = {Floor = getStatFloorKey(), Players = players}
    Mizuki:SaveData(json.encode(root))
end
