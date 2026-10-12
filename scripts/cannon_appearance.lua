-- Attack art changes only the manually drawn cannon body. Its familiar sprite,
-- shadow, collision, beam and knife remain independent of this visual state.
local appearances, variants, ordered = {}, {}, {}
local itemConfig = Isaac.GetItemConfig()
local json = require("json")

function Mizuki.registerCannonAttackAppearance(id, definition)
    assert(type(id) == "string" and id ~= "", "Cannon appearance needs an id")
    assert(not appearances[id], "Duplicate cannon appearance: " .. id)
    assert(type(definition.Anm2) == "string" and type(definition.Animation) == "string",
        "Cannon appearance needs an animation file and animation")
    assert(type(definition.Variants) == "table", "Cannon appearance needs tear variants")
    appearances[id] = definition
    definition.Id = id
    ordered[#ordered + 1] = definition
    for _, variant in ipairs(definition.Variants) do
        local old = variants[variant]
        if not old or (definition.Priority or 0) > (appearances[old].Priority or 0) then
            variants[variant] = id
        end
    end
end

function Mizuki.canUseCannonAttackAppearance(player, data)
    return player and player:Exists() and Mizuki.isMizuki(player)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
        and not Mizuki.cannonUsesKnifeWeapon(player)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
        and not data.MizukiAwaitingInitialLayout
end

-- Only the small set of appearance-granting items is observed. True inventory
-- counts distinguish acquisitions/removals from temporary collectible effects.
-- Entity data retains order through hot reload; the save retains it on continue.
local function inventory(player)
    local data = player:GetData()
    local state = data.MizukiCannonAppearanceInventory
    if not state then
        state = {Counts = {}, Order = {}, Serial = 0}
        data.MizukiCannonAppearanceInventory = state
    end
    local frame = Game():GetFrameCount()
    if state.Frame == frame then return state end
    state.Frame = frame
    local queued = not player:IsItemQueueEmpty() and player.QueuedItem.Item
    local queueId = queued and queued.Type ~= ItemType.ITEM_TRINKET and queued.ID
    local seen, acquired = {}, {}
    for _, definition in ipairs(ordered) do
        for _, source in ipairs(definition.Sources or {}) do
            local id = source.Id
            if not seen[id] then
                seen[id] = true
                local count = player:GetCollectibleNum(id, true)
                local previous = state.Counts[tostring(id)] or 0
                if count > previous then acquired[#acquired + 1] = id end
                if count == 0 then state.Order[tostring(id)] = nil end
                state.Counts[tostring(id)] = count
            end
        end
    end
    -- A queued pickup has a known position in a simultaneous inventory change.
    -- Grants without an observable order share one rank rather than inventing it.
    if #acquired > 0 then
        state.Serial = state.Serial + 1
        for _, id in ipairs(acquired) do state.Order[tostring(id)] = state.Serial end
        if queueId and seen[queueId] then
            for _, id in ipairs(acquired) do
                if id == queueId then
                    state.Serial = state.Serial + 1
                    state.Order[tostring(id)] = state.Serial
                    break
                end
            end
        end
    end
    return state
end

local function permanentAppearance(player)
    local state = inventory(player)
    local best, quality, acquired = nil, -1, -1
    for _, definition in ipairs(ordered) do
        if definition.Category == "permanent" then
            for _, source in ipairs(definition.Sources or {}) do
                local active = source.Active and source.Active(player)
                    or (not source.Active and player:HasCollectible(source.Id))
                if active then
                    local config = itemConfig:GetCollectible(source.Id)
                    local q = config and config.Quality or 0
                    local order = state.Order[tostring(source.Id)] or 0
                    if q > quality or (q == quality and order > acquired) then
                        best, quality, acquired = definition.Id, q, order
                    end
                end
            end
        end
    end
    return best
end

local function hasFlag(attack, flag)
    return flag and (attack.TearFlags & flag) ~= TearFlags.TEAR_NORMAL
end

-- Lasers have no TearVariant. Use their real flags and native damage, never a
-- second GetTearHitParams roll. Equivalent damage combinations intentionally
-- share art when the corresponding item is owned (the agreed heuristic).
function Mizuki.resolveCannonAttackAppearance(player, attack, baseDamage)
    if player:GetEffects():HasCollectibleEffect(CollectibleType.COLLECTIBLE_CROWN_OF_LIGHT) then
        return "diamond"
    end
    local tear = attack and attack:ToTear()
    local actual = tear and variants[tear.Variant]
    if actual and (appearances[actual].Category == "random"
        or appearances[actual].Category == "conditional") then return actual end
    local selected, priority = nil, -1
    if attack then
        for _, definition in ipairs(ordered) do
            if definition.Category == "random" and definition.Flag
                and hasFlag(attack, definition.Flag) and definition.Priority > priority then
                selected, priority = definition.Id, definition.Priority
            end
        end
        local ratio = baseDamage and baseDamage > 0 and attack.CollisionDamage / baseDamage
        local function matches(multiplier)
            if not ratio then return false end
            local epsilon = 0.0001 * math.max(1, math.abs(ratio))
            return math.abs(ratio - multiplier) < epsilon
                or (hasFlag(attack, TearFlags.TEAR_RAINBOW)
                    and math.abs(ratio - multiplier * 2) < epsilon)
        end
        for _, candidate in ipairs({
            {"black_tooth", 2, player:HasTrinket(TrinketType.TRINKET_BLACK_TOOTH)},
            {"tooth", 3.2, player:HasCollectible(CollectibleType.COLLECTIBLE_TOUGH_LOVE)
                or player:HasTrinket(TrinketType.TRINKET_JAW_BREAKER)},
            {"razor", 4, player:HasCollectible(CollectibleType.COLLECTIBLE_APPLE)},
        }) do
            local definition = appearances[candidate[1]]
            if candidate[3] and matches(candidate[2]) and definition.Priority > priority then
                selected, priority = definition.Id, definition.Priority
            end
        end
    end
    return selected or permanentAppearance(player)
end

-- A cannon can have several live beams. Pick the highest appearance category
-- across them; a later ordinary beam must not erase another beam's proc.
function Mizuki.bindCannonAttackAppearance(cannon, attack, multiplier)
    if not cannon or not cannon:Exists() then return end
    local data, attackData = cannon:GetData(), attack:GetData()
    local entries = data.MizukiCannonAppearanceAttacks or {}
    data.MizukiCannonAppearanceAttacks = entries
    for index = #entries, 1, -1 do
        local entry = entries[index]
        if not entry.Attack:Exists() then table.remove(entries, index)
        elseif entry.Attack.InitSeed == attack.InitSeed and GetPtrHash(entry.Attack) == GetPtrHash(attack) then
            return
        end
    end
    local entry = {Attack = attack, Seed = attack.InitSeed}
    entries[#entries + 1] = entry
    attackData.MizukiCannonAppearancePlayer = cannon.Player
    attackData.MizukiCannonAppearanceDamageMultiplier = multiplier or 1
    if not attackData.MizukiAttackSequenceReplay then
        if not data.MizukiEchoCannon and not data.MizukiPersistentEchoMode then
            attackData.MizukiCannonAppearanceCannon = cannon
        end
        attackData.MizukiCannonAttackAppearanceKey = Mizuki.resolveCannonAttackAppearance(
            cannon.Player, attack, cannon.Player.Damage * (multiplier or 1))
    end
    local id = attackData.MizukiCannonAttackAppearanceKey
    if id and appearances[id] and appearances[id].Category == "random" then
        entry.RandomAppearance = id
    end
end

function Mizuki.snapshotCannonAttackAppearance(cannon, attack)
    local data = cannon:GetData()
    local id = attack:GetData().MizukiCannonAttackAppearanceKey
    local old = data.MizukiCannonAttackAppearanceKey
    local incoming, current = id and appearances[id], old and appearances[old]
    if incoming and (not current or incoming.Priority > current.Priority) then
        data.MizukiCannonAttackAppearanceKey = id
    end
end

local function resolvedCannonAppearance(cannon)
    local data = cannon:GetData()
    if data.MizukiCannonAttackAppearanceManual then
        if not data.MizukiCannonAttackAppearanceEndFrame
            or Game():GetFrameCount() < data.MizukiCannonAttackAppearanceEndFrame then
            return data.MizukiCannonAttackAppearanceKey
        end
        Mizuki.clearCannonAttackAppearance(cannon)
    end
    -- Idle originals show their permanent/crown art even while an old beam
    -- finishes fading. Delayed echoes retain the recorded source appearance.
    if data.MizukiIsIdle and not data.MizukiEchoCannon and not data.MizukiPersistentEchoMode then
        return Mizuki.resolveCannonAttackAppearance(cannon.Player)
    end
    local best, priority = nil, -1
    local positionLocked = data.MizukiCannonFiringPositionLocked
        and not data.MizukiEchoCannon and not data.MizukiPersistentEchoMode
    local entries = data.MizukiCannonAppearanceAttacks or {}
    for index = #entries, 1, -1 do
        local entry, attack = entries[index], entries[index].Attack
        local alive = attack:Exists() and attack.InitSeed == entry.Seed
        if not alive and not positionLocked then
            table.remove(entries, index)
        else
            local id = alive and attack:GetData().MizukiCannonAttackAppearanceKey or nil
            local definition = id and appearances[id]
            if definition and definition.Category == "random" then
                entry.RandomAppearance = id
            end
            -- EntityLaser can disappear after the player's layout update. Keep
            -- its proc art through that frame and through native flag refreshes;
            -- only the layout's firing-position release ends this visual hold.
            local held = positionLocked and entry.RandomAppearance
            if held and (not definition or appearances[held].Priority > definition.Priority) then
                id, definition = held, appearances[held]
            end
            if definition and definition.Priority > priority then best, priority = id, definition.Priority end
        end
    end
    if positionLocked then
        local baseline = Mizuki.resolveCannonAttackAppearance(cannon.Player)
        if baseline and appearances[baseline].Priority > priority then best = baseline end
    end
    if best then return best end
    -- Echoes use their recorded key even while waiting/fading, never current items.
    if data.MizukiEchoCannon or data.MizukiPersistentEchoMode then
        return data.MizukiCannonAttackAppearanceKey
    end
    return Mizuki.resolveCannonAttackAppearance(cannon.Player)
end

Mizuki.getCannonAttackAppearance = resolvedCannonAppearance

function Mizuki.clearCannonAttackAppearance(cannon)
    local data = cannon:GetData()
    data.MizukiCannonAttackAppearanceKey = nil
    data.MizukiCannonAttackAppearanceEndFrame = nil
    data.MizukiCannonAttackAppearanceManual = nil
end

-- Call with the resolved parameters of the actual attack, never with a second
-- appearance-only random roll. Unregistered variants restore base art.
function Mizuki.setCannonAttackAppearance(cannon, tearVariant, duration)
    local data = cannon:GetData()
    local id = variants[tearVariant]
    if not id or not Mizuki.canUseCannonAttackAppearance(cannon.Player, data) then
        Mizuki.clearCannonAttackAppearance(cannon)
        return
    end
    data.MizukiCannonAttackAppearanceKey = id
    data.MizukiCannonAttackAppearanceManual = true
    data.MizukiCannonAttackAppearanceEndFrame = duration
        and Game():GetFrameCount() + math.max(1, duration) or nil
end

-- Source poses and finite echoes carry the key, not a shared mutable Sprite.
function Mizuki.renderCannonAttackAppearance(cannon, poseSprite, position)
    local data = cannon:GetData()
    if not Mizuki.canUseCannonAttackAppearance(cannon.Player, data) then
        Mizuki.clearCannonAttackAppearance(cannon)
        return false
    end
    local id = resolvedCannonAppearance(cannon)
    data.MizukiCannonAttackAppearanceKey = id
    if not id then return false end
    local definition = appearances[id]
    if not definition then return false end
    local sprites = data.MizukiCannonAttackAppearanceSprites
    if not sprites then sprites = {}; data.MizukiCannonAttackAppearanceSprites = sprites end
    local sprite = sprites[id]
    if not sprite then
        sprite = Sprite()
        sprite:Load(definition.Anm2, true)
        sprite:Play(definition.Animation, true)
        sprites[id] = sprite
    end
    sprite.Rotation = poseSprite.Rotation
    -- The source pose includes the cannon art's 0.65 shrink. Replacement tear
    -- art uses its own 1x baseline while retaining player/Ludovico/turn scaling.
    sprite.Scale = poseSprite.Scale
        * ((definition.Scale or 1) / Mizuki.CANNON_ART_SCALE_MULTIPLIER)
    sprite.Offset = poseSprite.Offset
    sprite.FlipX = poseSprite.FlipX
    sprite.FlipY = poseSprite.FlipY
    sprite.Color = Color.Lerp(poseSprite.Color, poseSprite.Color, 0)
    for _, layer in ipairs(definition.Layers or {0}) do
        sprite:RenderLayer(layer, position, Vector.Zero, Vector.Zero)
    end
    return true
end

local C, T, F = CollectibleType, TearVariant, TearFlags
local function register(id, variant, file, animation, category, priority, sources, flag, layers)
    Mizuki.registerCannonAttackAppearance(id, {Variants = {variant},
        Anm2 = "gfx/" .. file .. ".anm2", Animation = animation,
        Category = category, Priority = priority, Sources = sources, Flag = flag,
        Layers = layers or {0}, Scale = 1})
end
local function source(id) return {{Id = id}} end
register("scythe", T.SCHYTHE, "002.008_scythe tear", "Rotate3", "permanent", 10, source(C.COLLECTIBLE_DEATHS_TOUCH))
register("rock", T.ROCK, "002.042_rock tear", "Rotate3", "permanent", 10, source(C.COLLECTIBLE_TERRA))
register("ice", T.ICE, "002.041_ice tear", "RegularTear8", "permanent", 10, source(C.COLLECTIBLE_URANUS))
register("nail", T.NAIL, "002.013_nail tear", "RegularTear8", "permanent", 10, source(C.COLLECTIBLE_8_INCH_NAILS))
register("bone", T.BONE, "002.029_bone tear", "Stone3Idle", "permanent", 10, source(C.COLLECTIBLE_COMPOUND_FRACTURE))
register("coin", T.COIN, "002.020_coin tear", "Rotate3", "permanent", 10, source(C.COLLECTIBLE_HEAD_OF_THE_KEEPER))
register("cupid", T.CUPID_BLUE, "002.011_cupid tear", "RegularTear8", "permanent", 10, {
    {Id = C.COLLECTIBLE_CUPIDS_ARROW}, {Id = C.COLLECTIBLE_SAGITTARIUS},
    {Id = C.COLLECTIBLE_ZODIAC, Active = function(player) return player:GetZodiacEffect() == C.COLLECTIBLE_SAGITTARIUS end},
})
register("pupula", T.PUPULA, "002.014_pupula tear", "RegularTear8", "permanent", 10, source(C.COLLECTIBLE_PUPULA_DUPLEX))
register("eye", T.EYE, "002.033_pop tear", "RegularTear8", "permanent", 10, source(C.COLLECTIBLE_POP))
-- Within random procs retain the native parameter-write order. These ranks do
-- not override the user's permanent-item quality/acquisition policy.
register("needle", T.NEEDLE, "002.031_needle tear", "RegularTear8", "random", 110, nil, F.TEAR_NEEDLE)
register("booger", T.BOOGER, "002.026_booger tear", "Stone3Idle", "random", 120, nil, F.TEAR_BOOGER)
register("spore", T.SPORE, "002.048_spore tear", "Stone3Idle", "random", 130, nil, F.TEAR_SPORE)
register("black_tooth", T.BLACK_TOOTH, "002.030_black tooth tear", "Tooth3Idle", "random", 160)
register("tooth", T.TOOTH, "002.002_tooth tear", "Tooth3Idle", "random", 170)
register("razor", T.RAZOR, "002.028_razor tear", "Stone3Idle", "random", 180)
register("egg", T.EGG, "002.027_egg tear", "Stone3Idle", "random", 190, nil, F.TEAR_EGG)
register("fist", T.FIST, "002.039_fist tear", "RegularTear8", "random", 200, nil, F.TEAR_PUNCH)
register("diamond", T.DIAMOND, "002.018_diamond tear", "RegularTear8", "crown", 1000)
for _, pair in ipairs({{T.CUPID_BLOOD, T.CUPID_BLUE}, {T.NAIL_BLOOD, T.NAIL},
    {T.PUPULA_BLOOD, T.PUPULA},
    {T.EYE_BLOOD, T.EYE}}) do
    variants[pair[1]] = variants[pair[2]]
end

Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, CallbackPriority.EARLY, function(_, player)
    if Mizuki.isMizuki(player) then inventory(player) end
end)
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE, function(_, laser)
    local data = laser:GetData()
    local player = data.MizukiCannonAppearancePlayer
    if player and player:Exists() and not data.MizukiAttackSequenceReplay then
        data.MizukiCannonAttackAppearanceKey = Mizuki.resolveCannonAttackAppearance(
            player, laser, player.Damage * data.MizukiCannonAppearanceDamageMultiplier)
    end
end)

local function readRoot()
    if not Mizuki:HasData() then return {} end
    local ok, root = pcall(json.decode, Mizuki:LoadData())
    return ok and type(root) == "table" and root or {}
end
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    local game = Game()
    local saved = continued and readRoot().CannonAppearance
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local state = saved and saved.RunSeed == game:GetSeeds():GetStartSeed()
            and saved.Players and saved.Players[tostring(index)]
        player:GetData().MizukiCannonAppearanceInventory = state and {
            Counts = state.Counts or {}, Order = state.Order or {}, Serial = state.Serial or 0,
        } or nil
    end
end)
local function saveOrder()
    local game, players = Game(), {}
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player) then
            local state = inventory(player)
            players[tostring(index)] = {Counts = state.Counts, Order = state.Order, Serial = state.Serial}
        end
    end
    local root = readRoot()
    root.CannonAppearance = {RunSeed = game:GetSeeds():GetStartSeed(), Players = players}
    Mizuki:SaveData(json.encode(root))
end
Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave) if shouldSave then saveOrder() end end)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, saveOrder)
