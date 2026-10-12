-- Native-only attack state replay. Verify FULL Color equality in the running
-- API before selecting change-frame storage; public RGB alone is insufficient.
local epoch, sources, replays = {}, {}, {}
local function key(entity) return GetPtrHash(entity) end
local function copyColor(value) return Color.Lerp(value, value, 0) end
local comparisonBase = Color(1, 1, 1, 1, 0, 0, 0)
comparisonBase:SetColorize(0.2, 0.4, 0.6, 0.8)
local comparisonEqual = copyColor(comparisonBase)
local comparisonDifferent = copyColor(comparisonBase)
comparisonDifferent:SetColorize(0.7, 0.1, 0.3, 0.8)
local comparisonAmount = copyColor(comparisonBase)
comparisonAmount:SetColorize(0.2, 0.4, 0.6, 0.3)
local comparisonAlpha = copyColor(comparisonBase)
comparisonAlpha.A = 0.5
local comparisonTint = copyColor(comparisonBase)
comparisonTint.R = 0.5
local comparisonOffset = copyColor(comparisonBase)
comparisonOffset.RO = 0.5
local sameCopy = comparisonBase == comparisonEqual
local detectsColorize = comparisonBase ~= comparisonDifferent
local detectsAmount = comparisonBase ~= comparisonAmount
local useChangeFrames = sameCopy and detectsColorize and detectsAmount
    and comparisonBase ~= comparisonAlpha and comparisonBase ~= comparisonTint
    and comparisonBase ~= comparisonOffset
Mizuki.canCompareEchoColors = useChangeFrames

local function stateAt(sequence, age)
    local ages = sequence.Ages
    local low, high, chosen = 1, #ages, nil
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if ages[middle] <= age then chosen, low = ages[middle], middle + 1
        else high = middle - 1 end
    end
    return chosen and sequence.Samples[chosen], chosen
end
local function valid(record)
    local entity = record.Entity
    return entity and entity:Exists() and entity.InitSeed == record.Seed
        and key(entity) == record.Hash
end
local function readState(entity)
    local data = entity:GetData()
    local flags = entity.Type ~= EntityType.ENTITY_EFFECT and entity.TearFlags or nil
    local cannon = data.MizukiCannonAppearanceCannon
    local cannonAppearance = data.MizukiCannonAttackAppearanceKey
    if cannon and cannon:Exists() then
        -- Record the body actually shown, including the hold through the native
        -- shrinking tail; native laser params alone may already have lost a proc.
        cannonAppearance = Mizuki.getCannonAttackAppearance(cannon)
    end
    return {
        Flags = flags and (flags | TearFlags.TEAR_NORMAL),
        FlagsKey = tostring(flags),
        Color = copyColor(data.MizukiCannonKnifeDrawColor or entity.Color),
        Damage = entity.CollisionDamage,
        BrimstoneCurse = data.MizukiSpecialBrimstoneCurse,
        FetalBrimstone = data.MizukiFetalBrimstoneEnabled,
        CannonAppearance = cannonAppearance,
    }
end
local function restoreReplayColor(binding)
    if not valid(binding) then return end
    local entity = binding.Entity
    if binding.NativeLaserSpawner then
        entity.SpawnerEntity = binding.NativeLaserSpawner.Entity
        entity.SpawnerType = binding.NativeLaserSpawner.Type
        entity.SpawnerVariant = binding.NativeLaserSpawner.Variant
    end
    local state = binding.LastState
    if not state then return end
    local color = copyColor(state.Color)
    local data = entity:GetData()
    if data.MizukiCannonKnifeManualRender == true then
        data.MizukiCannonKnifeDrawColor = copyColor(color)
        color.A = 0
        entity:GetSprite().Color = color
    end
    entity.Color = color
end
local function capture(record)
    if not valid(record) or record.Sequence.Epoch ~= epoch then return end
    local sequence = record.Sequence
    if sequence.Rolling and sequence.Owner and (not Mizuki.hasCannonEcho(sequence.Owner)
        or Mizuki.getPersistentCannonEchoMode(sequence.Owner) ~= sequence.Mode) then
        sources[record.Hash] = nil
        record.Entity:GetData().MizukiAttackSequenceSource = nil
        return
    end
    local age = Game():GetFrameCount() - sequence.Origin
    if age < 0 then return end
    local state = readState(record.Entity)
    local previous = sequence.Ages[#sequence.Ages]
    local old = previous and sequence.Samples[previous]
    if previous == age then
        sequence.Samples[age] = state
    elseif not useChangeFrames or not old or state.FlagsKey ~= old.FlagsKey
        or state.Damage ~= old.Damage or state.Color ~= old.Color
        or state.BrimstoneCurse ~= old.BrimstoneCurse or state.FetalBrimstone ~= old.FetalBrimstone
        or state.CannonAppearance ~= old.CannonAppearance then
        sequence.Ages[#sequence.Ages + 1] = age
        sequence.Samples[age] = state
    end
    sequence.LastAge = age
    -- Only rolling attacks discard consumed frames. Finite attacks can wait
    -- indefinitely for their release and need their complete original history.
    if sequence.Rolling and sequence.ConsumedAge then
        while #sequence.Ages > 1 and sequence.Ages[2] <= sequence.ConsumedAge do
            sequence.Samples[table.remove(sequence.Ages, 1)] = nil
        end
    end
end

function Mizuki.startEchoAttackRecording(entity, rolling, restart)
    local previousReplay = entity:GetData().MizukiAttackSequenceReplay
    if previousReplay then
        restoreReplayColor(previousReplay)
        entity:GetData().MizukiAttackSequenceReplay = nil
        replays[key(entity)] = nil
        restart = true
    end
    local old = entity:GetData().MizukiAttackSequenceSource
    if not restart and old and old.Epoch == epoch then return old end
    local sequence = {Epoch = epoch, Origin = Game():GetFrameCount(), Samples = {}, Ages = {}, Rolling = rolling}
    local record = {Entity = entity, Seed = entity.InitSeed, Hash = key(entity), Sequence = sequence}
    sources[record.Hash] = record
    entity:GetData().MizukiAttackSequenceSource = sequence
    capture(record)
    return sequence
end

function Mizuki.applyEchoAttackSequence(entity)
    local binding = entity:GetData().MizukiAttackSequenceReplay
    if not binding or binding.Sequence.Epoch ~= epoch or not valid(binding) then return false end
    if binding.WorldClock and (not Mizuki.hasCannonEcho(binding.Owner)
        or Mizuki.getPersistentCannonEchoMode(binding.Owner) ~= binding.Mode) then
        restoreReplayColor(binding)
        entity:GetData().MizukiAttackSequenceReplay = nil
        replays[binding.Hash] = nil
        return false
    end
    local sequence = binding.Sequence
    local age = Game():GetFrameCount() - (binding.WorldClock and sequence.Origin or binding.Origin)
        - binding.Delay
    local state, savedAge = stateAt(sequence, age)
    if not state then state = binding.LastState end
    if not state then return false end
    binding.LastState = state
    if sequence.Rolling then sequence.ConsumedAge = age end
    -- Laser rainbow cycling is visual only; replay already supplies its color.
    -- Keep the source history intact and retain every gameplay effect flag.
    local replayFlags = state.Flags and (state.Flags | TearFlags.TEAR_NORMAL)
    if replayFlags and entity.Type == EntityType.ENTITY_LASER then
        replayFlags = replayFlags & ~TearFlags.TEAR_RAINBOW
    end
    if replayFlags and binding.NativeConsumedFlags then
        -- Contact-consumed flags belong to this entity's collision history.
        -- Copying the source's spent bomber bit disarms an unspent echo;
        -- copying it back later would instead give a spent echo another bomb.
        replayFlags = (replayFlags & ~binding.NativeConsumedFlags)
            | (entity.TearFlags & binding.NativeConsumedFlags)
    end
    if replayFlags then entity.TearFlags = replayFlags end
    local color = copyColor(state.Color)
    if binding.Tint then color = Mizuki.getCannonEchoColor(color, binding.Alpha)
    else color.A = color.A * binding.Alpha end
    local data = entity:GetData()
    if data.MizukiCannonKnifeManualRender == true then
        data.MizukiCannonKnifeDrawColor = color
        local hidden = copyColor(color)
        hidden.A = 0 -- Preserve the existing manual-render collision body.
        entity.Color = hidden
    else entity.Color = color end
    data.MizukiSpecialBrimstoneCurse = state.BrimstoneCurse
    data.MizukiFetalBrimstoneEnabled = state.FetalBrimstone
    data.MizukiCannonAttackAppearanceKey = state.CannonAppearance
    -- Knife native hit scaling already runs in scaleKnifeHit; never halve it twice.
    if not entity:ToKnife() then entity.CollisionDamage = state.Damage * binding.DamageMultiplier end
    data.MizukiAttackSequenceReplayAge = age
    data.MizukiAttackSequenceSampleAge = savedAge
    data.MizukiAttackSequenceRecordedFlags = state.Flags
    data.MizukiAttackSequenceExpectedFlags = replayFlags
    data.MizukiAttackSequenceExpectedColor = copyColor(entity.Color)
    return true
end

function Mizuki.bindEchoAttackReplay(entity, sequence, options)
    if not sequence or sequence.Epoch ~= epoch then return false end
    local previous = entity:GetData().MizukiAttackSequenceReplay
    local binding = {Entity = entity, Seed = entity.InitSeed, Hash = key(entity), Sequence = sequence,
        Origin = Game():GetFrameCount(), WorldClock = options.WorldClock,
        Delay = options.Delay or 0, Alpha = options.Alpha, Tint = options.Tint,
        Owner = options.Owner, Mode = options.Mode,
        NativeConsumedFlags = options.NativeConsumedFlags,
        DamageMultiplier = options.DamageMultiplier or Mizuki.CannonEchoDamageMultiplier}
    local spawner = options.LaserSpawner
    if entity.Type == EntityType.ENTITY_LASER and spawner and spawner:Exists()
        and spawner.Type == EntityType.ENTITY_FAMILIAR
        and (spawner.Variant == Mizuki.CannonVariant or spawner.Variant == Mizuki.CannonEchoVariant) then
        -- Native laser refresh recalculates player tear params before collision
        -- for player spawners and selected vanilla familiars. Our custom cannon
        -- is excluded, so recorded gameplay flags and damage survive that phase.
        binding.NativeLaserSpawner = previous and previous.NativeLaserSpawner
            or {Entity = entity.SpawnerEntity, Type = entity.SpawnerType, Variant = entity.SpawnerVariant}
        entity.SpawnerEntity = spawner
        entity.SpawnerType = spawner.Type
        entity.SpawnerVariant = spawner.Variant
    end
    replays[binding.Hash] = binding
    entity:GetData().MizukiAttackSequenceReplay = binding
    Mizuki.applyEchoAttackSequence(entity)
    return true
end

function Mizuki.isEchoAttackReplayActive(entity)
    local binding = entity:GetData().MizukiAttackSequenceReplay
    return binding and binding.Sequence.Epoch == epoch and valid(binding)
end

-- Persistent profiles retain their existing cannon ordering. Each echo reads
-- the corresponding real cannon, angle and entity kind, not an arbitrary beam.
function Mizuki.connectPersistentEchoAttack(player, cannon, entity, angle, kind, explicitSequence, shotIndex)
    if not Mizuki.hasCannonEcho(player) or not cannon or not cannon:Exists() then return end
    local data, cannonData = player:GetData(), cannon:GetData()
    local side = cannonData.CannonSide
    local cannons = data.MizukiCannons and data.MizukiCannons[side]
    if not cannons then return end
    local mode = cannonData.MizukiPersistentEchoMode
    if not mode and not Mizuki.getPersistentCannonEchoMode(player) then return end
    local channel = kind .. ":" .. tostring(shotIndex or 1) .. ":" .. tostring(angle or 0)
    if not mode then
        local sequence = Mizuki.startEchoAttackRecording(entity, true)
        sequence.Owner, sequence.Mode = player, Mizuki.getPersistentCannonEchoMode(player)
        cannonData.MizukiAttackSequenceChannels = cannonData.MizukiAttackSequenceChannels or {}
        cannonData.MizukiAttackSequenceChannels[channel] = sequence
        return sequence
    end
    local source
    if mode == "automatic" then source = cannons[1]
    elseif mode == "ludovico" then
        for member, current in ipairs(cannons) do
            if key(current) == key(cannon) then source = cannons[member - #cannons / 2]; break end
        end
    end
    local channels = source and source:Exists() and source:GetData().MizukiAttackSequenceChannels
    local sequence = explicitSequence or channels and channels[channel]
    if sequence then
        local previous = entity:GetData().MizukiAttackSequenceReplay
        if previous and previous.Sequence == sequence and previous.Sequence.Epoch == epoch then return sequence end
        Mizuki.bindEchoAttackReplay(entity, sequence, {WorldClock = true,
            Delay = mode == "automatic" and Mizuki.CannonEchoFollowDelay or 0,
            Alpha = Mizuki.CannonEchoPersistentAlpha, Tint = true, Owner = player, Mode = mode,
            LaserSpawner = cannon})
    end
    return sequence
end

local function updateEarly(_, entity)
    if entity:GetData().MizukiAttackSequenceReplay then Mizuki.applyEchoAttackSequence(entity) end
end
local function updateLate(_, entity)
    local record = sources[key(entity)]
    if record and valid(record) then capture(record) end
    updateEarly(nil, entity)
end
for _, callback in ipairs({ModCallbacks.MC_POST_LASER_UPDATE,
    ModCallbacks.MC_POST_TEAR_UPDATE, ModCallbacks.MC_POST_KNIFE_UPDATE,
    ModCallbacks.MC_POST_EFFECT_UPDATE}) do
    Mizuki:AddPriorityCallback(callback, CallbackPriority.EARLY, updateEarly)
    Mizuki:AddPriorityCallback(callback, CallbackPriority.LATE, updateLate)
end
-- All originals have updated before this two-pass capture/apply. In particular,
-- a same-frame Ludovico echo must not depend on native entity traversal order.
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.LATE, function()
    if Game():IsPaused() then return end
    for hash, record in pairs(sources) do
        if valid(record) then capture(record) else sources[hash] = nil end
    end
    for hash, binding in pairs(replays) do
        if valid(binding) then Mizuki.applyEchoAttackSequence(binding.Entity) else replays[hash] = nil end
    end
end)
local function clear() epoch, sources, replays = {}, {}, {} end
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clear)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clear)
Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clear)
Mizuki:AddCallback(ModCallbacks.MC_USE_ITEM, clear, CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS)
