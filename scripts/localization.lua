-- Native pickup banners and EID descriptions; language strings live in translations/.

-- region Capsule EID
do
    local CAPSULE_ICON_SIZE = { Width = 9, Height = 8 }
    -- Present the capsule as an ordinary Experimental Pill. The card ID is ready
    -- when this file loads; registration waits for game start so EID can load too.
    local function registerExperimentalCapsuleEID()
        if not EID or not EID.addCard or not EID.addIcon then
            return
        end

        for _, translation in pairs(Mizuki.Translations) do
            EID:addCard(Mizuki.ExperimentalCapsuleCard, translation.Capsule.EID,
                translation.Capsule.Name, translation.EIDLanguage)
        end

        -- The capsule is a pocket object, so EID's pill-only modifier never
        -- reaches it. Mirror ordinary Experimental Pill priorities and reuse
        -- EID's own localized text; this object never becomes a horse pill.
        EID:addDescriptionModifier("Mizuki Experimental Capsule Synergies", function(descObj)
            return descObj.ObjType == EntityType.ENTITY_PICKUP
                and descObj.ObjVariant == PickupVariant.PICKUP_TAROTCARD
                and descObj.ObjSubType == Mizuki.ExperimentalCapsuleCard
        end, function(descObj)
            local player = EID:ClosestPlayerTo(descObj.Entity)
            if not player or not Mizuki.isMizuki(player) then return descObj end

            local goodPillItem
            for _, item in ipairs({ CollectibleType.COLLECTIBLE_PHD,
                CollectibleType.COLLECTIBLE_LUCKY_FOOT, CollectibleType.COLLECTIBLE_VIRGO }) do
                if player:HasCollectible(item) then
                    goodPillItem = item
                    break
                end
            end
            local item, text
            if player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD) then
                item = CollectibleType.COLLECTIBLE_FALSE_PHD
                text = EID:getDescriptionEntry("FalsePHDDamage")
                if not goodPillItem then
                    text = EID:getDescriptionEntry("ExperimentalPillFalsePHD")
                        .. "#{{Collectible" .. item .. "}} " .. text
                end
            elseif goodPillItem then
                item = goodPillItem
                text = EID:getDescriptionEntry("ExperimentalPillPHD")
            end
            if item then
                EID:appendToDescription(descObj, "#{{Collectible" .. item .. "}} " .. text)
            end
            return descObj
        end)

        local capsuleEIDIcon = Sprite()
        capsuleEIDIcon:Load("gfx/items/mizuki/experimental_capsule.anm2", true)
        capsuleEIDIcon:Play("EID", true)
        EID:addIcon(
            "Card" .. Mizuki.ExperimentalCapsuleCard,
            "EID",
            0,
            CAPSULE_ICON_SIZE.Width,
            CAPSULE_ICON_SIZE.Height,
            0,
            1,
            capsuleEIDIcon
        )
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerExperimentalCapsuleEID)
end
-- endregion Capsule EID

-- region Character EID
do
    local CHARACTER_ICON_LAYOUT = { Width = 16, Height = 16, LeftOffset = 0, TopOffset = 1 }
    -- EID draws a title icon at Y-4, its title text at Y-3; reminder icons
    -- and text share one baseline. Compensate only the portal's title icon.
    local EID_TITLE_BASELINES = { Icon = -4, Text = -3 }
    local BOSS_PORTAL_ICON_NAME = "MizukiBossPortal"

    local function registerCapsuleDropLockEID()
        -- Native character info bypasses collectible description modifiers.
        -- Append to this player's generated reminder entry, not the shared
        -- CharacterInfo translation (two Mizuki players can have different PHDs).
        if type(EID.ItemReminderHandleCharacterInfo) == "function"
            and not EID.MizukiCapsuleCharacterInfoRegistered then
            local original = EID.ItemReminderHandleCharacterInfo
            EID.ItemReminderHandleCharacterInfo = function(self, player)
                local before = #self.ItemReminderTempDescriptions
                local result = original(self, player)
                if Mizuki.isMizuki(player)
                    and player:HasCollectible(CollectibleType.COLLECTIBLE_FALSE_PHD)
                    and not player:HasCollectible(CollectibleType.COLLECTIBLE_PHD) then
                    local icon = self:GetPlayerIcon(player:GetPlayerType())
                    for index = before + 1, #self.ItemReminderTempDescriptions do
                        local entry = self.ItemReminderTempDescriptions[index]
                        if entry[1] == icon then
                            entry[3] = entry[3] .. "#{{Collectible"
                                .. CollectibleType.COLLECTIBLE_FALSE_PHD .. "}} "
                                .. Mizuki.GetTranslation(self:getLanguage()).Player.CapsuleDropLockEID
                            break
                        end
                    end
                end
                return result
            end
            EID.MizukiCapsuleCharacterInfoRegistered = true
        end

        EID:addDescriptionModifier("Mizuki Capsule Drop Lock", function(descObj)
            return descObj.ObjType == EntityType.ENTITY_PICKUP
                and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE
                and descObj.ObjSubType == CollectibleType.COLLECTIBLE_FALSE_PHD
        end, function(descObj)
            local player = EID:ClosestPlayerTo(descObj.Entity)
            -- On a False PHD pedestal this is prospective: the player need not
            -- own False PHD yet. PHD overrides the lock in both descriptions.
            if player and Mizuki.isMizuki(player)
                and not player:HasCollectible(CollectibleType.COLLECTIBLE_PHD) then
                local text = Mizuki.GetTranslation(EID:getLanguage()).Player.CapsuleDropLockReverseEID
                    :gsub("{MIZUKI_CAPSULE_ICON}", "{{Card" .. Mizuki.ExperimentalCapsuleCard .. "}}")
                EID:appendToDescription(descObj, "#{{Player" .. Mizuki.PlayerType .. "}} "
                    .. text)
            end
            return descObj
        end)
    end

    local function registerBirthrightEchoEID()
        -- Birthright's native modifier replaces the entire description after
        -- conditionals. Insert into Mizuki's section only after it has run.
        EID:addDescriptionModifier("Mizuki Birthright Echo", function(descObj)
            local item = descObj.ObjSubType
            return descObj.ObjType == EntityType.ENTITY_PICKUP
                and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE
                and (item == CollectibleType.COLLECTIBLE_BIRTHRIGHT
                    or item == CollectibleType.COLLECTIBLE_PHD
                    or item == CollectibleType.COLLECTIBLE_FALSE_PHD)
        end, function(descObj)
            local birthright = CollectibleType.COLLECTIBLE_BIRTHRIGHT
            local phd = CollectibleType.COLLECTIBLE_PHD
            local falsePhd = CollectibleType.COLLECTIBLE_FALSE_PHD
            local player = EID:ClosestPlayerTo(descObj.Entity)
            local isBirthright = descObj.ObjSubType == birthright
            if isBirthright and not EID.InsideItemReminder then
                -- Native Birthright lists each character type once, using its
                -- first eligible co-op player rather than the nearest player.
                player = nil
                for _, candidate in ipairs(EID.coopAllPlayers) do
                    if Mizuki.isMizuki(candidate) and not candidate:IsSubPlayer()
                        and candidate:GetMainTwin():GetPlayerType() == candidate:GetPlayerType() then
                        player = candidate
                        break
                    end
                end
            end

            local icon
            if player and Mizuki.isMizuki(player) then
                if isBirthright then
                    -- Only one icon/description even when both are held.
                    if player:HasCollectible(phd) then
                        icon = phd
                    elseif player:HasCollectible(falsePhd) then
                        icon = falsePhd
                    end
                elseif player:HasCollectible(birthright) then
                    icon = birthright
                end
            end
            local extra = ""
            if icon then
                -- Embed the icon only on the first line; the second uses EID's
                -- normal bullet rather than repeating the collectible icon.
                extra = "#{{Collectible" .. icon .. "}} "
                    .. Mizuki.GetTranslation(EID:getLanguage()).Player.BirthrightEchoEID
            end
            if isBirthright then
                descObj.Description = descObj.Description:gsub("{MIZUKI_BIRTHRIGHT_ECHO}", function()
                    return extra
                end)
            elseif extra ~= "" then
                EID:appendToDescription(descObj, extra)
            end
            return descObj
        end)
    end

    -- Register once per game start, after EID has loaded, including continued runs.
    local function registerCharacterEID()
        if not EID then return end

        for _, translation in pairs(Mizuki.Translations) do
            local description = translation.Player.EID:gsub("{MIZUKI_CAPSULE_ICON}",
                "{{Card" .. Mizuki.ExperimentalCapsuleCard .. "}}")
            EID:addCharacterInfo(Mizuki.PlayerType, description,
                translation.Player.Name, translation.EIDLanguage)
            EID:addBirthright(Mizuki.PlayerType, translation.Player.BirthrightEID,
                translation.Player.Name, translation.EIDLanguage)
        end
        registerBirthrightEchoEID()
        registerCapsuleDropLockEID()

        -- EID controls Sprite.Scale; the icon's own reduction lives in its anm2.
        local icon = Sprite()
        icon:Load("gfx/eid/player_icons.anm2", true)
        EID:addIcon("Player" .. Mizuki.PlayerType, "Mizuki", 0,
            CHARACTER_ICON_LAYOUT.Width, CHARACTER_ICON_LAYOUT.Height,
            CHARACTER_ICON_LAYOUT.LeftOffset, CHARACTER_ICON_LAYOUT.TopOffset, icon)
        EID:addIcon(BOSS_PORTAL_ICON_NAME, "Mizuki", 0,
            CHARACTER_ICON_LAYOUT.Width, CHARACTER_ICON_LAYOUT.Height,
            CHARACTER_ICON_LAYOUT.LeftOffset,
            CHARACTER_ICON_LAYOUT.TopOffset + EID_TITLE_BASELINES.Text - EID_TITLE_BASELINES.Icon,
            icon)
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerCharacterEID)

    -- Entity descriptions take precedence over EID's built-in Card Reading branch,
    -- which would overwrite a description modifier's name after it runs.
    local function updateBossPortalEID(_, effect)
        if not EID then return end
        local data = effect:GetData()
        if data.MizukiBossChainPortal ~= true then return end

        local translation = Mizuki.GetTranslation(EID:getLanguage()).BossPortal
        local targetStage = data.MizukiBossChainTargetStage
        local description = translation.EIDByStage[targetStage]
        if not description then return end
        if targetStage > 1 then
            description = description .. "#" .. translation.ContinueEID
        end
        data.EID_Description = data.EID_Description or {}
        data.EID_Description.Name = translation.Name
        data.EID_Description.Description = description
        data.EID_Description.Icon = EID:getIcon(BOSS_PORTAL_ICON_NAME)
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, updateBossPortalEID,
        EffectVariant.PORTAL_TELEPORT)

    -- EID can still enumerate a removed effect through FindByType's cache.
    -- Its native portal fallback does not require GetData or Exists(), so keep
    -- a short-lived identity outside the entity while that cache expires.
    local RETIRED_PORTAL_EID_FRAMES = 2
    function Mizuki.RetireBossPortalEID(portal)
        if portal:GetData().MizukiBossChainPortal ~= true
            or not EID or type(EID.hasDescription) ~= "function" then return end

        -- Keep one filter per EID instance, including across Lua reloads.
        local state = EID.MizukiRetiredPortalDescriptions
        if not state then
            state = { Original = EID.hasDescription, Identities = {} }
            EID.MizukiRetiredPortalDescriptions = state
            EID.hasDescription = function(self, entity)
                local frame = Game():GetFrameCount()
                local blocked = false
                for hash, identity in pairs(state.Identities) do
                    if frame < identity.Frame or frame > identity.ExpiresAt then
                        state.Identities[hash] = nil
                    elseif entity and entity.Type == EntityType.ENTITY_EFFECT
                        and entity.Variant == EffectVariant.PORTAL_TELEPORT
                        and GetPtrHash(entity) == hash and entity.InitSeed == identity.InitSeed then
                        blocked = true
                    end
                end
                if blocked then return false end
                return state.Original(self, entity)
            end
        end
        local frame = Game():GetFrameCount()
        state.Identities[GetPtrHash(portal)] = {
            InitSeed = portal.InitSeed, Frame = frame,
            ExpiresAt = frame + RETIRED_PORTAL_EID_FRAMES,
        }
        EID.ForceRefreshCache = true
    end
end
-- endregion Character EID

-- region Fan EID
do
    local FAN_EID_SYNERGIES = {
        { Key = "BFFS_BLOCK", Item = CollectibleType.COLLECTIBLE_BFFS },
        { Key = "BFFS_CHANCE", Item = CollectibleType.COLLECTIBLE_BFFS },
        { Key = "LUCKY_FOOT", Item = CollectibleType.COLLECTIBLE_LUCKY_FOOT },
        { Key = "MOMS_BOX", Item = CollectibleType.COLLECTIBLE_MOMS_BOX },
        { Key = "SACK_HEAD", Item = CollectibleType.COLLECTIBLE_SACK_HEAD },
    }

    local function registerFanConditions()
        if not EID.AddConditional or not EID.CreateDescriptionTableIfMissing then return end
        -- Named localization entries can be refreshed without registering new
        -- conditions on every game start or Lua reload.
        for _, translation in pairs(Mizuki.Translations) do
            local language = translation.EIDLanguage
            EID:CreateDescriptionTableIfMissing("MizukiFanConditions", language)
            EID:CreateDescriptionTableIfMissing("MizukiFanReverseConditions", language)
            for _, synergy in ipairs(FAN_EID_SYNERGIES) do
                EID.descriptions[language].MizukiFanConditions[synergy.Key] = {
                    "{MIZUKI_FAN_" .. synergy.Key .. "}",
                    "#{{Collectible" .. synergy.Item .. "}} " .. translation.Fan.Synergies[synergy.Key],
                }
                -- Missing entries also clear obsolete text after Lua reloads:
                -- BFFS now combines both effects under its first condition.
                EID.descriptions[language].MizukiFanReverseConditions[synergy.Key] =
                    translation.Fan.ReverseSynergies[synergy.Key]
            end
        end
        -- Reverse descriptions belong to the four partner items, and are only
        -- relevant when this same player owns Xiaobotu. Missing reverse text
        -- is skipped by EID without changing the partner's own description.
        EID.MizukiFanReverseConditionsRegistered = EID.MizukiFanReverseConditionsRegistered or {}
        if not EID.MizukiFanReverseConditionsRegistered[Mizuki.FanItem] then
            for index, synergy in ipairs(FAN_EID_SYNERGIES) do
                EID:AddConditional(synergy.Item, function(eid, descObj)
                    local player = eid:ClosestPlayerTo(descObj.Entity)
                    return player and player:HasCollectible(Mizuki.FanItem)
                end, synergy.Key, {
                    locTable = "MizukiFanReverseConditions", noFallback = false,
                    bulletpoint = "Collectible" .. Mizuki.FanItem, layer = -index,
                    uniqueID = "MizukiFanReverse_" .. synergy.Key,
                })
            end
            EID.MizukiFanReverseConditionsRegistered[Mizuki.FanItem] = true
        end
        EID.MizukiFanConditionsRegistered = EID.MizukiFanConditionsRegistered or {}
        if EID.MizukiFanConditionsRegistered[Mizuki.FanItem] then return end
        for _, synergy in ipairs(FAN_EID_SYNERGIES) do
            EID:AddConditional(Mizuki.FanItem, function(eid, descObj)
                -- Match the probability line's owner, including item reminders;
                -- another co-op player's inventory must not add a false bonus.
                local player = eid:ClosestPlayerTo(descObj.Entity)
                return player and player:HasCollectible(synergy.Item)
            end, synergy.Key, {
                locTable = "MizukiFanConditions", noFallback = false,
                uniqueID = "MizukiFan_" .. synergy.Key,
            })
        end
        EID.MizukiFanConditionsRegistered[Mizuki.FanItem] = true
    end

    -- Register on new and continued runs, after EID has loaded.
    local function registerFanEID()
        if not EID then return end

        for _, translation in pairs(Mizuki.Translations) do
            EID:addCollectible(Mizuki.FanItem, translation.Fan.EID,
                translation.Fan.Name, translation.EIDLanguage)
        end
        registerFanConditions()

        -- The built-in LuckFormulas callback receives luck only and skips zero
        -- luck. This modifier also accounts for held items and the reminder owner.
        EID:addDescriptionModifier(
            "Mizuki Fan Clear Chance",
            function(descObj)
                return descObj.ObjType == EntityType.ENTITY_PICKUP
                    and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE
                    and descObj.ObjSubType == Mizuki.FanItem
            end,
            function(descObj)
                local player = EID:ClosestPlayerTo(descObj.Entity)
                local chance = Mizuki.GetFanRoomClearChance(player) * Mizuki.RuntimeParameters.PercentScale
                -- Match EID's native luck line, highlighting the current luck.
                local luckLine = EID:getDescriptionEntry("LuckModifier")
                luckLine = EID:ReplaceVariableStr(luckLine, 1, string.format("%.3g", chance))
                luckLine = EID:ReplaceVariableStr(luckLine, 2,
                    "{{BlinkGreen}}" .. string.format("%.3g", player.Luck) .. "{{CR}}")
                descObj.Description = descObj.Description:gsub("{MIZUKI_FAN_LUCK_LINE}", function()
                    return luckLine
                end)
                -- Native conditions run before description modifiers. Remove
                -- unused insertion points without leaving blank bullet lines.
                descObj.Description = descObj.Description:gsub("{MIZUKI_FAN_[A-Z_]+}", "")
                return descObj
            end
        )
    end

    Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, registerFanEID)
end
-- endregion Fan EID

-- region Pickup banners
do
    -- Install after gameplay modules, preserving the original callback order.
    function Mizuki.RegisterPickupLocalization()
        -- Localize Mizuki's Birthright pickup banner through the native HUD API.
        -- Never mutate item configs, player types or pickup behavior.
        local function getQueuedItem(player)
            if player:IsItemQueueEmpty() then return nil end
            local queued = player.QueuedItem
            local item = queued and queued.Item
            if item then return { ID = item.ID, Type = item.Type } end
        end

        local function localizeCollectiblePickup(_, player)
            if player.Variant ~= 0 or Game():GetFrameCount() <= 0 then return end
            local data = player:GetData()
            local queued = getQueuedItem(player)
            local observation = data.MizukiPickupBannerObservation
            data.MizukiPickupBannerObservation = { Queued = queued }
            if not observation then return end -- A reload/new observer only seeds its baseline.
            local previous = observation.Queued
            if not queued or queued.Type == ItemType.ITEM_TRINKET then return end
            if previous and previous.ID == queued.ID and previous.Type == queued.Type then return end

            local translation = Mizuki.GetTranslation()
            if queued.ID == CollectibleType.COLLECTIBLE_BIRTHRIGHT
                and player:GetPlayerType() == Mizuki.PlayerType then
                Game():GetHUD():ShowItemText(translation.BirthrightName, translation.Player.Birthright)
            end
        end

        local function initializePickupTranslations()
            -- Seed already-held queue entries on new/continued runs. Loading a save
            -- or granting the starting familiar must not replay pickup banners.
            for index = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(index)
                player:GetData().MizukiPickupBannerObservation = { Queued = getQueuedItem(player) }
            end
        end

        Mizuki:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, localizeCollectiblePickup)
        Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, initializePickupTranslations)
    end
end
-- endregion Pickup banners
