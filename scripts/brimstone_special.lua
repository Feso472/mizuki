-- Native Repentance only. The attack marker is separate from the enemy status.
local MARK = EntityFlag.FLAG_BRIMSTONE_MARKED
local MARK_FRAMES = 150
local BALL_SCALE = 0.50
local markedEnemies = {}

function Mizuki.getSpecialBrimstoneChance(luck)
    -- Holy Light: 10% at zero luck, discrete luck growth, capped at 50%.
    return 1 / math.max(2, 10 - math.floor(luck * 0.9))
end

function Mizuki.rollSpecialBrimstone(entity, player)
    local data = entity:GetData()
    data.MizukiSpecialBrimstoneAttack = true
    data.MizukiSpecialBrimstoneOwner = player
    data.MizukiSpecialBrimstoneCurse = player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
        and player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_BRIMSTONE):RandomFloat()
            < Mizuki.getSpecialBrimstoneChance(player.Luck)
end

function Mizuki.updateCannonBrimstoneCurse(cannon)
    local player, data = cannon.Player, cannon:GetData()
    if data.MizukiPersistentEchoMode then
        -- Persistent contact echoes copy the original cannon's proc. Automatic
        -- mode receives its delayed state in the pose history immediately after this.
        if data.MizukiPersistentEchoMode == "ludovico" then
            local cannons = player:GetData().MizukiCannons
            local side = cannons and cannons[data.CannonSide]
            if side then
                for index, candidate in ipairs(side) do
                    if GetPtrHash(candidate) == GetPtrHash(cannon) then
                        local original = side[index - #side / 2]
                        data.MizukiSpecialBrimstoneCurse = original and original:GetData().MizukiSpecialBrimstoneCurse or false
                        break
                    end
                end
            end
        end
        return
    end
    if data.MizukiIsIdle or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        or not player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        data.MizukiSpecialBrimstoneCurse = false
        data.MizukiSpecialBrimstoneContactNext = nil
        return
    end
    local frame = Game():GetFrameCount()
    if not data.MizukiSpecialBrimstoneContactNext or frame >= data.MizukiSpecialBrimstoneContactNext then
        Mizuki.rollSpecialBrimstone(cannon, player)
        data.MizukiSpecialBrimstoneContactNext = frame + math.max(1, player.MaxFireDelay + 1)
    end
end

local function markEnemy(enemy)
    if enemy:HasEntityFlags(EntityFlag.FLAG_NO_STATUS_EFFECTS) then return end
    local hash = GetPtrHash(enemy)
    local record = markedEnemies[hash]
    if record and record.Seed ~= enemy.InitSeed then record = nil end
    if not record then
        -- Leave a status already owned by the native game or another mod alone.
        if enemy:HasEntityFlags(MARK) then return end
        record = {Entity = enemy, Seed = enemy.InitSeed}
        markedEnemies[hash] = record
    end
    record.Expires = Game():GetFrameCount() + MARK_FRAMES
    enemy:AddEntityFlags(MARK)
end

Mizuki:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, _, source)
    local enemy, attack = entity:ToNPC(), source and source.Entity
    if not enemy or not attack or amount <= 0 or not enemy:IsActiveEnemy(false)
        or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
    local data = attack:GetData()
    if data.MizukiSpecialBrimstoneCurse == true then markEnemy(enemy) end
end)

-- Native Lua exposes the status flag but not AddBrimstoneMark's timer. Maintain
-- only our own five-second status; the native engine handles its damage synergy.
Mizuki:AddCallback(ModCallbacks.MC_NPC_UPDATE, function(_, enemy)
    local hash = GetPtrHash(enemy)
    local record = markedEnemies[hash]
    if not record then return end
    if record.Seed ~= enemy.InitSeed or enemy:IsDead() then markedEnemies[hash] = nil; return end
    if Game():GetFrameCount() >= record.Expires then
        enemy:ClearEntityFlags(MARK)
        markedEnemies[hash] = nil
    else enemy:AddEntityFlags(MARK) end
end)

local function ownerOf(entity, visited)
    if not entity then return nil end
    visited = visited or {}
    local hash = GetPtrHash(entity)
    if visited[hash] then return nil end
    visited[hash] = true
    local player = entity:ToPlayer()
    if player then return player end
    local familiar = entity:ToFamiliar()
    if familiar then return familiar.Player end
    return ownerOf(entity.SpawnerEntity, visited) or ownerOf(entity.Parent, visited)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_UPDATE, function(_, bomb)
    if bomb:GetData().MizukiSpecialBrimstoneAttack or not bomb.IsFetus then return end
    local player = ownerOf(bomb)
    if player and Mizuki.isMizuki(player) then Mizuki.rollSpecialBrimstone(bomb, player) end
end)

function Mizuki.prepareFetalBrimstone(tear, player)
    Mizuki.rollSpecialBrimstone(tear, player)
    tear:GetData().MizukiFetalBrimstoneEnabled = player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
end

local function applyBallAppearance(ball, fetus)
    -- Native tears already write their converted Height into PositionOffset.Y
    -- (height setter 0x675FC0 / conversion 0x676020). Do not add Height again.
    ball.PositionOffset = Vector(fetus.PositionOffset.X, fetus.PositionOffset.Y)
    ball.DepthOffset = fetus.DepthOffset - 10
    ball.CollisionDamage = fetus.CollisionDamage * 0.5
    ball.SpriteScale = Vector.One * (BALL_SCALE * fetus.Scale)
    -- Supply the native effect scale as well as its drawing scale.
    ball.Scale = BALL_SCALE * fetus.Scale
    ball:SetTimeout(30)
    local color = Color(1, 1, 1, fetus.Color.A, 0, 0, 0)
    ball.Color = color
end

local function updateBall(ball)
    local data = ball:GetData()
    if data.MizukiFetalBrimstoneBall ~= true then return end
    local fetus = data.MizukiFetalBrimstoneFetus
    if not fetus or not fetus:Exists() or fetus:IsDead() or fetus.InitSeed ~= data.MizukiFetalBrimstoneSeed
        or fetus:GetData().MizukiFetalBrimstoneEnabled ~= true then ball:Remove(); return end
    -- An attachment shares its anchor's position AND interpolation velocity.
    -- A chase velocity leaves it behind; zero velocity makes the render phases
    -- differ. Keep the player Parent required by the native damaging fireball.
    ball.Position = Vector(fetus.Position.X, fetus.Position.Y)
    ball.Velocity = Vector(fetus.Velocity.X, fetus.Velocity.Y)
    applyBallAppearance(ball, fetus)
end

local function updateFetus(_, tear)
    local data = tear:GetData()
    if data.MizukiFanFetus ~= true then return end
    if data.MizukiFetalBrimstoneEnabled ~= true or tear:IsDead() then return end
    local ball = data.MizukiFetalBrimstoneBallEntity
    if not ball or not ball:Exists() then
        local player = ownerOf(tear)
        if not player then return end
        -- Reverie's wheelchair and Blood Bony use this same native damaging
        -- entity: player parent, CollisionDamage and SetTimeout, no hidden laser.
        ball = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BRIMSTONE_BALL,
            0, tear.Position, tear.Velocity, player):ToEffect()
        ball.Parent = player
        ball:GetSprite().PlaybackSpeed = 0.5
        local ballData = ball:GetData()
        ballData.MizukiFetalBrimstoneBall = true
        ballData.MizukiFetalBrimstoneFetus = tear
        ballData.MizukiFetalBrimstoneSeed = tear.InitSeed
        data.MizukiFetalBrimstoneBallEntity = ball
        -- Initialize size and damage before the first native collision/render.
        applyBallAppearance(ball, tear)
    end
end
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_TEAR_UPDATE, CallbackPriority.LATE, updateFetus)
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, ball) updateBall(ball) end, EffectVariant.BRIMSTONE_BALL)

function Mizuki.renderSpecialBrimstoneIcon(entity, worldPosition, renderOffset, alpha)
    local data = entity:GetData()
    if data.MizukiSpecialBrimstoneCurse ~= true then return end
    local room = Game():GetRoom()
    if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then return end
    local sprite = data.MizukiSpecialBrimstoneIcon
    if not sprite then
        sprite = Sprite()
        sprite:Load("gfx/statuseffects.anm2", true)
        data.MizukiSpecialBrimstoneIcon = sprite
    end
    sprite:SetFrame("BrimstoneCurse", Game():GetFrameCount() % 30)
    sprite.Color = Color(1, 1, 1, alpha or entity.Color.A, 0, 0, 0)
    local position = Isaac.WorldToScreen(worldPosition) + (renderOffset or Vector.Zero)
        - room:GetRenderScrollOffset() - Game().ScreenShakeOffset + Vector(0, -16)
    sprite:Render(position, Vector.Zero, Vector.Zero)
end

Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_RENDER, function(_, tear, offset)
    if tear:GetData().MizukiFanFetus == true then
        Mizuki.renderSpecialBrimstoneIcon(tear, tear.Position + tear.PositionOffset, offset)
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_BOMB_RENDER, function(_, bomb, offset)
    Mizuki.renderSpecialBrimstoneIcon(bomb, bomb.Position + bomb.PositionOffset, offset)
end)
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, function(_, rocket, offset)
    if rocket:GetData().MizukiSpecialBrimstoneAttack then
        Mizuki.renderSpecialBrimstoneIcon(rocket, rocket.Position + rocket.PositionOffset, offset)
    end
end, EffectVariant.ROCKET)

Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() markedEnemies = {} end)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() markedEnemies = {} end)
