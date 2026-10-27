-- The visible hilt owns the pose; its blade is an independently drawn attachment.
-- Sword beams retain native motion/collision/lifespan. Melee uses independently
-- owned knife detectors; the echo retains its existing composite replay artwork.
local swordArt = "gfx/entities/mizuki/spirit_sword.anm2"
-- Tail, cannon body and light share one native sprite and one visual scale.
local beamArt = "gfx/entities/mizuki/spirit_sword_tear.anm2"
-- Each appearance uses the native Idle name, without animation redirects.
-- Tear-shaped bodies spin without a tail; cannon/full Mom Knife keep the tail.
local waveTextures = {
    scythe = "gfx/scythe_tears.png", rock = "gfx/rock_tears.png",
    ice = "gfx/ice_tears.png", nail = "gfx/8inchnails_tears.png",
    bone = "gfx/tears_bone.png", coin = "gfx/coin_tears_player.png",
    cupid = "gfx/cupids_arrow_tears.png", pupula = "gfx/pupula_tears.png",
    eye = "gfx/tears_pop.png", needle = "gfx/needle_tears.png",
    booger = "gfx/booger_tears.png", spore = "gfx/spore_tears.png",
    black_tooth = "gfx/tooth_shot_black.png", tooth = "gfx/tooth_shot.png",
    razor = "gfx/razor_shot.png", egg = "gfx/tears_egg.png",
    fist = "gfx/fist_tears.png", diamond = "gfx/diamond_tears.png",
    mom_knife = "gfx/effects/effect_momsknife.png",
}
local hiltArt = "gfx/entities/mizuki/spirit_sword_hilt.anm2"
local bladeArt = "gfx/entities/mizuki/spirit_sword_blade.anm2"
local knifeBladeArt = "gfx/entities/mizuki/spirit_sword_knife_blade.anm2"
local linkArt = "gfx/entities/mizuki/spirit_sword_link_body.anm2"
-- region Sword collision geometry
local swordHitboxes
do
    -- Original Spirit Sword Hit/Hit2 frames, expanded by each keyframe Delay.
    -- Null-layer visibility is not the per-frame collision flag: native code tests
    -- the frame visibility and rejects indices outside the null track.
    local frames = {
        IdleRight = {{{0, 24, 450, 100, 90}, false}},
        AttackRight = {
            {{24, 0, 450, 100, 0}, false},
            {{18, 18, 450, 300, 45}, {21, 11, 450, 300, 22}},
            {{0, 24, 450, 400, 90}, {11, 21, 450, 300, 67}},
            {{-18, 18, 450, 300, 135}, {-10, 24, 450, 400, 112}},
            {{-24, 0, 450, 100, 180}, {-21, 11, 450, 300, 157}},
            {{-24, 0, 450, 100, 180}, false},
            {false, false},
            {false, false},
        },
        AttackLeft = {
            {{-24, 0, 450, 100, 180}, false},
            {{-18, 18, 450, 300, 135}, {-21, 11, 450, 300, 158}},
            {{0, 24, 450, 400, 90}, {-11, 21, 450, 300, 113}},
            {{18, 18, 450, 300, 45}, {10, 24, 450, 400, 68}},
            {{24, 0, 450, 100, 0}, {21, 11, 450, 300, 23}},
            {{24, 0, 450, 100, 0}, false},
            {false, false},
            {false, false},
        },
        SpinRight = {
            {{18, 18, 450, 100, 45}, false},
            {{18, 18, 450, 100, 45}, false},
            {{0, 24, 450, 300, 90}, {9, 22, 450, 100, 67}},
            {{-18, 18, 450, 400, 135}, {-10, 23, 450, 300, 112}},
            {{-24, 0, 450, 400, 180}, {-23, 10, 450, 400, 157}},
            {{-18, -18, 450, 400, 225}, {-24, -10, 450, 400, 202}},
            {{0, -24, 450, 400, 270}, {-10, -21, 450, 400, 247}},
            {{18, -18, 450, 400, -45}, {10, -23, 450, 400, 292}},
            {{24, 0, 450, 400, 0}, {23, -11, 450, 400, -23}},
            {{18, 18, 450, 300, 45}, {23, 9, 450, 400, 22}},
            {{0, 24, 450, 100, 90}, {11, 21, 450, 300, 67}},
            {false, false},
            {false, false},
            {false, false},
        },
    }

    -- Native sword collision expands the major extent after GetNullCapsule when
    -- _isSpinAttack is set. The capsule radius is unchanged (isaac-ng 0x968DF1).
    -- The held-contact branch uses the same major-axis operation with 0.8
    -- (0x968DDA); neither branch moves the null center or scales its radius.
    local M = {Frames = frames, SpinReachMultiplier = 1.8, ChargeReachMultiplier = 0.8}
    local WORLD_TO_SCREEN_SCALE = 0.65

    -- Native Capsule constructor: radius is the smaller half-extent, with the
    -- remaining extent becoming a segment. This also matches Y-major capsules.
    local function capsule(center, x, y, rotation, reachMultiplier)
        x, y = math.abs(x), math.abs(y)
        local angle = math.rad(rotation)
        local axis
        local radius = math.min(x, y)
        local extent = math.max(x, y) * (reachMultiplier or 1)
        if x > y then
            axis = Vector(math.cos(angle), math.sin(angle)) * (extent - radius)
        else
            axis = Vector(math.sin(angle), math.cos(angle)) * (extent - radius)
        end
        local axisAngle = rotation
        if axis.X ~= 0 or axis.Y ~= 0 then axisAngle = math.deg(math.atan(axis.Y, axis.X)) end
        return {A = center - axis, B = center + axis, Center = center, Radius = radius,
            Extent = extent, Rotation = axisAngle}
    end

    function M.forFrame(origin, animation, frame, scale, rotation, reachMultiplier, rangeOffset)
        local result = {}
        -- The reference mod filters knife subtype 4: attacking children only.
        -- IdleRight is the held parent's charge-contact capsule, not that child.
        if animation ~= "IdleRight" and rangeOffset and rangeOffset ~= 0 then
            -- Range Fix for Bones & Sword grows the native knife geometry.
            -- Keep this multiplier local: attack.HitboxScale also drives art.
            scale = scale * Mizuki.getSpiritSwordRangeMultiplier(rangeOffset)
        end
        local pose = frames[animation] and frames[animation][frame + 1]
        for _, null in ipairs(pose or {}) do
            if null then
                -- Native GetNullCapsule: null position / 0.65; null scale * 4 /
                -- 0.65. ANM2 scale values are percentages, hence 0.04 here.
                local offset = Vector(null[1] * scale.X, null[2] * scale.Y) * (1 / WORLD_TO_SCREEN_SCALE)
                local x = null[3] * scale.X * (0.04 / WORLD_TO_SCREEN_SCALE)
                local y = null[4] * scale.Y * (0.04 / WORLD_TO_SCREEN_SCALE)
                local nullRotation = null[5]
                if x < 0 then offset = Vector(-offset.X, offset.Y); nullRotation = 180 - nullRotation end
                if y < 0 then offset = Vector(offset.X, -offset.Y); nullRotation = -nullRotation end
                result[#result + 1] = capsule(origin + offset:Rotated(rotation), x, y,
                    nullRotation + rotation, reachMultiplier)
            end
        end
        return result
    end

    -- Native 0x968FA7..0x969119: each sword has one candidate circle around
    -- Hit/Hit2. Entity processing can accept this bound without a capsule test
    -- in the single-track/degenerate branches below; grids cannot.
    function M.searchCircle(capsules)
        local first, second = capsules[1], capsules[2]
        if not first then return nil end
        if not second then return {Center = first.Center, Radius = first.Extent} end
        local delta = second.Center - first.Center
        local distance = delta:Length()
        local radius = (distance + first.Extent + second.Extent) * 0.5
        local center = first.Center
        if distance > 0 then center = center + delta * ((radius - first.Extent) / distance) end
        return {Center = center, Radius = radius}
    end

    function M.inSearchCircles(circles, position, radius)
        for _, circle in ipairs(circles) do
            if (position - circle.Center):Length() < circle.Radius + radius then return true end
        end
        return false
    end

    function M.isCandidate(circles, entity)
        return M.inSearchCircles(circles, entity.Position, entity.Size)
    end

    local function pointSegmentDistanceSquared(p, a, b)
        local dx, dy = b.X - a.X, b.Y - a.Y
        local lengthSquared = dx * dx + dy * dy
        local t = lengthSquared > 0 and ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / lengthSquared or 0
        t = math.max(0, math.min(1, t))
        local x, y = p.X - a.X - t * dx, p.Y - a.Y - t * dy
        return x * x + y * y
    end

    local function segmentDistanceSquared(a, b, c, d)
        local rx, ry, sx, sy = b.X - a.X, b.Y - a.Y, d.X - c.X, d.Y - c.Y
        local denominator = rx * sy - ry * sx
        if denominator ~= 0 then
            local qx, qy = c.X - a.X, c.Y - a.Y
            local t, u = (qx * sy - qy * sx) / denominator, (qx * ry - qy * rx) / denominator
            if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return 0 end
        end
        return math.min(pointSegmentDistanceSquared(a, c, d), pointSegmentDistanceSquared(b, c, d),
            pointSegmentDistanceSquared(c, a, b), pointSegmentDistanceSquared(d, a, b))
    end

    function M.overlaps(capsules, enemy)
        -- Native GetCollisionCapsule uses Position, Size, SizeMulti and SpriteRotation.
        local multi = enemy.SizeMulti
        local target = capsule(enemy.Position, enemy.Size * multi.X, enemy.Size * multi.Y, enemy.SpriteRotation)
        for _, hit in ipairs(capsules) do
            local radius = hit.Radius + target.Radius
            if segmentDistanceSquared(hit.A, hit.B, target.A, target.B) <= radius * radius then return true end
        end
        return false
    end

    -- Native entity branch 0x969652..0x9696F1, after the radius query.
    -- Preserve its fall-through when Hit2 is absent; do not apply it to grids.
    function M.entityContact(group, entity)
        if not group or not M.isCandidate({group.Circle}, entity) then return nil end
        local first, second = group.Capsules[1], group.Capsules[2]
        if first.Extent - first.Radius <= 0 or M.overlaps({first}, entity) then return first end
        if not second or second.Radius <= 0 then return first end
        if M.overlaps({second}, entity) then return second end
    end

    function M.overlapsBox(capsules, center, halfSize)
        local left, right = center.X - halfSize, center.X + halfSize
        local top, bottom = center.Y - halfSize, center.Y + halfSize
        local corners = {Vector(left, top), Vector(right, top), Vector(right, bottom), Vector(left, bottom)}
        local function inside(point)
            return point.X >= left and point.X <= right and point.Y >= top and point.Y <= bottom
        end
        for _, hit in ipairs(capsules) do
            if inside(hit.A) or inside(hit.B) then return true end
            for index = 1, 4 do
                if segmentDistanceSquared(hit.A, hit.B, corners[index], corners[index % 4 + 1])
                    <= hit.Radius * hit.Radius then return true end
            end
        end
        return false
    end
    swordHitboxes = M
end
-- endregion Sword collision geometry
-- region Sword contact interactions
local swordInteractions
do
    -- Query candidates per sword, then apply the native entity branch.
    -- Grids keep a separate precise capsule test; all hands share hit ledgers.
    local M = {}

    local function reflectFistula(ball, origin)
        -- Native sword collision 0x969814..0x9699D9: this NPC needs its
        -- return state and target vector, not only projectile reflection flags.
        if ball.Velocity.Y <= 0 or origin.Y <= ball.Position.Y then return end
        local parent = ball.Parent
        local target = parent and parent:Exists() and parent.Position or ball.Position
        local outward = target - origin
        local direction = outward:Length() > 0 and outward:Resized(1) or outward
        local distance = ball.TargetPosition:Length()
        ball.State, ball.Velocity = 16, direction * 18
        ball.TargetPosition = direction * (distance + 0.1)
        ball.Mass = ball.Mass + 1
    end

    local function pickupPush(attack, capsule)
        local outward = capsule.Center - (attack.SpinThrow and attack.ThrowKnife.Position or attack.Player.Position)
        if outward:Length() > 0 then outward = outward:Resized(1) end
        local turn = attack.Animation == "AttackLeft" and -90 or 90
        return (outward + Vector.FromAngle(capsule.Rotation + turn)) * 5
    end

    function M.update(attack, geometry)
        local detector = attack.Hitbox
        if attack.Finished or not detector or not detector:Exists()
            or detector:GetData().MizukiSpiritSwordHitbox ~= true
            or detector:GetData().MizukiSpiritSwordAttack ~= attack then return end

        local frame = Game():GetFrameCount()
        attack.PickupHits = attack.PickupHits or {}
        local reflect = attack.Spin or detector:HasTearFlags(TearFlags.TEAR_SHIELDED)
            or attack.Player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY)
            or attack.Player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
        for _, group in ipairs(attack.CollisionGroups) do
            local entry = attack.Hitboxes[group.HitboxIndex]
            local source = entry and entry.Entity
            if source and source:Exists() and source.InitSeed == entry.Seed
                and source:GetData().MizukiSpiritSwordHitbox == true
                and source:GetData().MizukiSpiritSwordAttack == attack then
                for _, entity in ipairs(Isaac.FindInRadius(group.Circle.Center, group.Circle.Radius,
                    EntityPartition.ENEMY | EntityPartition.PICKUP | EntityPartition.BULLET)) do
                    if entity:Exists() and not entity:IsDead() then
                        local contact = geometry.entityContact(group, entity)
                        if contact then
                            if entity.Type == EntityType.ENTITY_FIREPLACE then
                                if not attack.ChargeContact and entity.Variant ~= 4 then entity:Die() end
                            elseif entity.Type == 912 and entity.Variant == 100 and entity:ToNPC() then
                                reflectFistula(entity, group.Origin)
                            elseif entity:ToNPC() and entity:IsVulnerableEnemy()
                                and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                                local previous = attack.Targets[GetPtrHash(entity)]
                                if not previous or previous.Seed ~= entity.InitSeed then
                                    -- The guarded callback owns damage, deduplication
                                    -- and on-hit bookkeeping for this explicit source.
                                    entity:TakeDamage(attack.Damage, 0, EntityRef(source), 30)
                                    if attack.Finished or attack.RetireAfterHit then return end
                                end
                            elseif not attack.ChargeContact then
                                local pickup, projectile = entity:ToPickup(), entity:ToProjectile()
                                if pickup and attack.PickupHits[GetPtrHash(pickup)] ~= pickup.InitSeed
                                    and not pickup:GetData().MizukiMeleePickupTransfer then
                                    attack.PickupHits[GetPtrHash(pickup)] = pickup.InitSeed
                                    local velocity = pickupPush(attack, contact)
                                    if not Mizuki.tryCollectMeleePickup(pickup, attack.Player, velocity)
                                        and pickup:GetSprite():GetAnimation() ~= "Collect" then pickup:AddVelocity(velocity) end
                                elseif projectile and reflect
                                    and not projectile:HasProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER) then
                                    local direction = projectile.Position - (attack.SpinThrow and group.Origin or attack.Player.Position)
                                    if direction:Length() == 0 then direction = attack.Direction end
                                    projectile.Velocity = direction:Resized(math.max(8, projectile.Velocity:Length()))
                                    projectile:AddProjectileFlags(ProjectileFlags.CANT_HIT_PLAYER | ProjectileFlags.HIT_ENEMIES)
                                    projectile.CollisionDamage = projectile.Damage <= 1 and 6 or 7
                                    projectile.SpawnerEntity, projectile.Parent = attack.Player, attack.Player
                                end
                            end
                        end
                    end
                end
            end
        end

        if attack.ChargeContact then return end
        local room = Game():GetRoom()
        attack.GridHits = attack.GridHits or {}
        for index = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(index)
            if grid and geometry.inSearchCircles(attack.SearchCircles, grid.Position, math.sqrt(2) * 20)
                and geometry.overlapsBox(attack.Capsules, grid.Position, 20) then
                local previous = attack.GridHits[index]
                local seed = grid.Desc.SpawnSeed
                if not previous or previous.Seed ~= seed then
                    attack.GridHits[index] = {Seed = seed, Frame = frame}
                    for _, group in ipairs(attack.CollisionGroups) do
                        if geometry.overlapsBox(group.Capsules, grid.Position, 20) then
                            local entry = attack.Hitboxes[group.HitboxIndex]
                            if entry and Mizuki.triggerSpiritSwordGridImpact then
                                Mizuki.triggerSpiritSwordGridImpact(entry.Entity, grid.Position)
                            end
                        end
                    end
                    room:DamageGrid(index, 1, EntityRef(detector))
                end
            end
        end
    end
    swordInteractions = M
end
-- endregion Sword contact interactions
-- region Directional sword copies
local extraSwords
do
    -- Directional sword procs keep a real hilt and a separate moving blade.
    local M = {}
    local function alive(entity) return entity and entity:Exists() end
    local function removeOwned(entity)
        if alive(entity) and entity:GetData().MizukiSpiritSwordExtraVisual == true then entity:Remove() end
    end
    function M.clear(cannon)
        local data = cannon:GetData()
        for _, entry in ipairs(data.MizukiSpiritSwordExtraVisuals or {}) do
            removeOwned(entry.Hilt); removeOwned(entry.Blade); removeOwned(entry.Link)
        end
        data.MizukiSpiritSwordExtraVisuals = nil
    end
    function M.update(cannon, sourceHilt, attack, rootFor, transform)
        if not attack or attack.Finished or attack.ChargeContact or not alive(sourceHilt) then M.clear(cannon); return end
        local entries = cannon:GetData().MizukiSpiritSwordExtraVisuals or {}
        cannon:GetData().MizukiSpiritSwordExtraVisuals = entries
        local index = 0
        for _, angle in ipairs(attack.ExtraAngles or {0}) do
            if angle ~= 0 then
                index = index + 1
                local entry = entries[index] or {}
                entries[index] = entry
                for _, role in ipairs({"Hilt", "Blade"}) do
                    if not alive(entry[role]) then
                        local visual = Isaac.Spawn(EntityType.ENTITY_EFFECT, sourceHilt.Variant, 0,
                            sourceHilt.Position, cannon.Player.Velocity, cannon.Player):ToEffect()
                        visual:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
                        visual.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
                        visual.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
                        local data = visual:GetData()
                        data.MizukiSpiritSwordExtraVisual, data.Cannon, data.CannonSeed = true, cannon, cannon.InitSeed
                        data.Role, data.Entry = role, entry
                        entry[role] = visual
                        local sprite = visual:GetSprite()
                        sprite:Load(role == "Hilt" and "gfx/entities/mizuki/spirit_sword_hilt.anm2"
                            or "gfx/entities/mizuki/spirit_sword_blade.anm2", false)
                        sprite:ReplaceSpritesheet(0, role == "Hilt" and "gfx/entities/mizuki/spirit_sword.png"
                            or "gfx/entities/mizuki/mizuki_cannon.png")
                        if role == "Blade" then sprite:ReplaceSpritesheet(1, "gfx/entities/mizuki/mizuki_cannon_light.png") end
                        sprite:LoadGraphics()
                    end
                end
                entry.Attack, entry.Angle, entry.Cannon = attack, angle, cannon
                local hilt, blade = entry.Hilt, entry.Blade
                local original, sprite = sourceHilt:GetSprite(), hilt:GetSprite()
                sprite:SetFrame(original:GetAnimation(), original:GetFrame())
                sprite.Rotation, sprite.Scale, sprite.Offset = original.Rotation + angle, original.Scale, Vector.Zero
                hilt.Color, sprite.Color = sourceHilt.Color, sourceHilt.Color
                hilt.Position = rootFor(cannon, attack.Direction:Rotated(angle))
                hilt.Velocity, hilt.PositionOffset = cannon.Player.Velocity, Vector.Zero
                local offset, rotation, scale = transform(sprite, nil, nil,
                    Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
                Mizuki.configureSpiritSwordBladeAppearance(cannon, blade, scale, rotation, sourceHilt.Color)
                local knife = Mizuki.getCannonMomKnife(cannon)
                -- Directional melee previews leave with the actual knife body; the
                -- ordinary multi-shot launch path owns the real flying copies.
                if blade:GetData().MizukiSpiritSwordExtraVisual == true then
                    blade.Visible = not knife or not knife:IsFlying()
                end
                blade.Position, blade.Velocity = hilt.Position + offset / 0.65, hilt.Velocity
                if knife then
                    local forward = Mizuki.getSpiritSwordMomKnifePosition(cannon) - cannon.Position
                    local angle = rotation - (cannon:GetData().MizukiCannonBodyRotation or rotation)
                    blade.Position = blade.Position + forward:Rotated(angle)
                end
                Mizuki.alignSpiritSwordBladeEntity(blade,
                    hilt.Position, sprite,
                    Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
                blade.PositionOffset = Vector.Zero
                local behind = attack.Direction:Rotated(angle).Y < -0.00001
                    or math.sin(math.rad(rotation - 90)) <= 0.00001
                local depth = cannon.Player.Position.Y + cannon.Player.DepthOffset + (behind and -1 or 1)
                hilt.DepthOffset, blade.DepthOffset = depth - hilt.Position.Y, depth - blade.Position.Y
                local _, _, _, hiltEnd = transform(sprite)
                entry.Link = Mizuki.updateSpiritSwordLinkEntity(cannon, hilt, blade, entry.Link,
                    hilt.Position + hiltEnd / 0.65, Mizuki.getSpiritSwordLinkEnd(blade), blade.Visible)
                if entry.Link then
                    local ld = entry.Link:GetData()
                    ld.MizukiSpiritSwordExtraVisual = true
                    ld.Role, ld.Entry = "Link", entry
                end
                entry.Arc = entry.Arc or Sprite()
                if entry.Arc:GetFilename() ~= "gfx/entities/mizuki/spirit_sword.anm2" then
                    entry.Arc:Load("gfx/entities/mizuki/spirit_sword.anm2", true)
                end
            end
        end
        for current = #entries, index + 1, -1 do
            removeOwned(entries[current].Hilt); removeOwned(entries[current].Blade); removeOwned(entries[current].Link); table.remove(entries, current)
        end
    end
    function M.updateEntity(entity)
        local data = entity:GetData()
        if data.MizukiSpiritSwordExtraVisual ~= true then return false end
        local entry, cannon = data.Entry, data.Cannon
        if not alive(cannon) or cannon.InitSeed ~= data.CannonSeed or not entry
            or not entry.Attack or entry.Attack.Finished or not alive(entry.Hilt) or not alive(entry.Blade) then
            removeOwned(entity)
        end
        return true
    end
    function M.render(entity, offset, transform)
        local data = entity:GetData()
        if data.MizukiSpiritSwordExtraVisual ~= true then return false end
        if data.Role ~= "Hilt" then return true end
        local entry = data.Entry
        if not entry or not entry.Attack or entry.Attack.Finished or not alive(entry.Blade) then return true end
        local sprite, game = entity:GetSprite(), Game()
        local screen = Isaac.WorldToScreen(entity.Position) + offset
            - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset
        local arc = entry.Arc
        arc:SetFrame(sprite:GetAnimation(), sprite:GetFrame())
        arc.Rotation, arc.Scale, arc.Color = sprite.Rotation, entry.Cannon.Player.SpriteScale, entity.Color
        local arcPosition = screen + Mizuki.getSpiritSwordRangeDisplacement(sprite:GetAnimation(),
            sprite:GetFrame(), sprite.Scale, sprite.Rotation, entry.Attack.RangeOffset,
            Mizuki.getSpiritSwordBladeSpacingScale(entry.Cannon)) * 0.65
        arc:RenderLayer(1, arcPosition, Vector.Zero, Vector.Zero)
        arc:RenderLayer(2, arcPosition, Vector.Zero, Vector.Zero)
        if not entry.Blade.Visible then return true end
        local bodyScreen = Isaac.WorldToScreen(entry.Blade.Position) + offset
            - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset
        Mizuki.renderDeadEyeGlow(entry.Cannon, bodyScreen, entry.Blade:GetSprite().Scale,
            entity.Color.A, nil, entry.Blade:GetSprite().Rotation - 90)
        Mizuki.renderSpiritSwordLink(entry.Cannon, entity, entry.Link, offset)
        Mizuki.renderSpiritSwordBladeBody(entry.Cannon, entry.Blade, offset, entry)
        Mizuki.renderSpecialBrimstoneIcon(entry.Attack.Hitbox, entity.Position, offset, entity.Color.A, screen)
        return true
    end
    extraSwords = M
end
-- endregion Directional sword copies
local ART_REVISION = 16
local swordRendererVariant = Isaac.GetEntityVariantByName("Mizuki Spirit Sword Renderer")
local updateSwordRenderer, updateSwordBlade, swordVisualState
local WORLD_TO_SCREEN_SCALE = 0.65
local beginPairedSpin, finishPairedSpin, pairedSpinPose, beginChargeContact, clearChargeContact, fireWave
local function loadComposite(sprite, path)
    sprite:Load(path, false)
    sprite:ReplaceSpritesheet(0, "gfx/entities/mizuki/spirit_sword.png")
    -- ReplaceSpritesheet takes a LAYER id, not a Spritesheet id. Sword layers
    -- 0/1/2 share the sword sheet; only added layers 3/4 are cannon/light.
    if path == swordArt then
        sprite:ReplaceSpritesheet(1, "gfx/entities/mizuki/spirit_sword.png")
        sprite:ReplaceSpritesheet(2, "gfx/entities/mizuki/spirit_sword.png")
        sprite:ReplaceSpritesheet(3, "gfx/entities/mizuki/mizuki_cannon.png")
        sprite:ReplaceSpritesheet(4, "gfx/entities/mizuki/mizuki_cannon_light.png")
    else
        sprite:ReplaceSpritesheet(1, "gfx/entities/mizuki/mizuki_cannon.png")
        sprite:ReplaceSpritesheet(2, "gfx/entities/mizuki/mizuki_cannon_light.png")
    end
    sprite:LoadGraphics()
end
local swordAnimations = {}
for _, stem in ipairs({"Idle", "Attack", "Charged", "Spin"}) do
    for _, direction in ipairs({"Right", "Left", "Up", "Down"}) do
        swordAnimations[stem .. direction] = true
    end
end

local function owner(entity)
    local spawner = entity.SpawnerEntity
    local player = spawner and spawner:ToPlayer()
    if not player then
        local parent = entity.Parent
        player = parent and parent:ToPlayer()
        local familiar = not player and parent and parent:ToFamiliar()
        player = player or (familiar and familiar.Player)
    end
    if player and player:Exists() and Mizuki.isMizuki(player)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        return player
    end
end

function Mizuki.applySpiritSwordVisual(entity)
    local data = entity:GetData()
    if data.MizukiSpiritSwordHitbox == true then
        -- Unique Spirit Swords must not reskin our owned collision carriers.
        data.UpdatedCustomSword = true
        return
    end
    local knife, tear = entity:ToKnife(), entity:ToTear()
    local player = owner(entity)
    if tear and player and (tear.Variant == TearVariant.SWORD_BEAM
        or tear.Variant == TearVariant.TECH_SWORD_BEAM)
        and data.MizukiSpiritSwordWaveAppearanceResolved ~= true then
        -- Engine-created split waves bypass fireWave and do not copy Lua data.
        -- Prefer the parent's birth snapshot, including an explicitly base wave.
        local inherited = false
        for _, source in pairs({Parent = tear.Parent, Spawner = tear.SpawnerEntity}) do
            local sourceTear = source:ToTear()
            local sourceData = sourceTear and sourceTear:GetData()
            if sourceData and sourceData.MizukiSpiritSwordWaveAppearanceResolved == true then
                data.MizukiSpiritSwordWaveAppearance = sourceData.MizukiSpiritSwordWaveAppearance
                inherited = true
                break
            end
        end
        if not inherited and not data.MizukiSpiritSwordWaveAppearance then
            if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
                data.MizukiSpiritSwordWaveAppearance = "mom_knife"
            else
                -- Some native splits retain only the player as spawner. Read
                -- their existing flags/items; never roll attack parameters again.
                data.MizukiSpiritSwordWaveAppearance = Mizuki.resolveCannonAttackAppearance(player, tear)
            end
        end
        data.MizukiSpiritSwordWaveAppearanceResolved = true
    end
    local appearance = tear and data.MizukiSpiritSwordWaveAppearance
    local waveKey = appearance and waveTextures[appearance] and appearance or "base"
    local path
    if knife and (knife.Variant == 10 or knife.Variant == 11) then path = swordArt
    elseif tear and (tear.Variant == TearVariant.SWORD_BEAM
        or tear.Variant == TearVariant.TECH_SWORD_BEAM) then
        path = waveKey == "base" and beamArt or "gfx/entities/mizuki/sword_waves/" .. waveKey .. ".anm2"
    else return end
    if not owner(entity) then return end
    -- Unique Spirit Swords checks this before looking up a character skin.
    if knife then data.UpdatedCustomSword = true end
    local sprite = entity:GetSprite()
    if sprite:GetFilename() == path and data.MizukiSpiritSwordArtRevision == ART_REVISION
        and (not tear or data.MizukiSpiritSwordWaveVisualKey == waveKey) then
        return
    end
    local animation, frame = sprite:GetAnimation(), sprite:GetFrame()
    -- Keep the source frame; loading the composite must not restart an attack.
    loadComposite(sprite, path)
    if tear and waveKey ~= "base" then
        sprite:ReplaceSpritesheet(1, waveTextures[waveKey])
        sprite:LoadGraphics()
    end
    data.MizukiSpiritSwordArtRevision = ART_REVISION
    if tear then
        data.MizukiSpiritSwordWaveVisualKey = waveKey
        -- This is the real entity sprite; the engine advances it. Start its
        -- looping animation once, never select frames or call Update from Lua.
        sprite:Play("Idle", true)
        return
    end
    local validAnimation = path == beamArt and animation == "Idle"
        or path == swordArt and swordAnimations[animation]
    sprite:SetFrame(validAnimation and animation or (path == beamArt and "Idle" or "IdleRight"),
        validAnimation and frame or 0)
end

Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, CallbackPriority.EARLY, function(_, knife)
    -- Also protect existing entities after Lua reload, before reskin callbacks.
    Mizuki.applySpiritSwordVisual(knife)
end)

local P = { SwingFrames = 8, SpinFrames = 14, SpinAlignFrames = 4, MeleeMultiplier = 3,
    MeleeBonus = 3.5, SpinMultiplier = 8, SpinBonus = 10,
    ChargeIntervalMultiplier = 4, WaveIntervalMultiplier = 2, SpinShotSpeedMultiplier = 2,
    HandForwardOffset = 6, HandHeight = -10, HandHalfSpacing = 6, ChargePoseFrames = 6,
    SpinChargeBarOffset = Vector(18, -30),
    HiltBladeConnection = Vector(16, 0), BladeGapPixels = 5, BladeForwardPixels = 16, RangeGrowthFactor = 5,
    LinkBladeFraction = 0.25, ReturnShadowDistance = 0.5 } -- sheet (28,16) relative to pivot (12,16)
Mizuki.SpiritSwordParameters = P

function Mizuki.getSpiritSwordRangeMultiplier(rangeOffset)
    -- Reference mod default factor=5, divisor=450. Omit its constant 4px
    -- baseline so the existing whiteboard sword stays unchanged.
    return 1 + (rangeOffset or 0) * P.RangeGrowthFactor / 450
end
local attacks = {}
local attackRegistryIdentity = {}
local function registerAttack(attack)
    if attack.RegistryIdentity ~= attackRegistryIdentity then
        attack.RegistryIdentity = attackRegistryIdentity
        attacks[#attacks + 1] = attack
    end
end
local function alive(e, seed) return e and e:Exists() and (not seed or e.InitSeed == seed) end
local function copy(v) return Vector(v.X, v.Y) end

function Mizuki.getSpiritSwordChargeProfile(player)
    return {MaxFrames = math.max(1, math.ceil(math.max(0, player.MaxFireDelay + 1)
        * P.ChargeIntervalMultiplier))}
end

local spinChargeBar
function Mizuki:RenderSpiritSwordSpinCharge(player, renderOffset)
    if not Mizuki.isMizuki(player) or not Mizuki.usesCannonSpiritSword(player)
        or player:IsDead() or not player.Visible then return end
    local game = Game()
    local room = game:GetRoom()
    if room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then return end
    local data = player:GetData()
    local charge = data.MizukiCharge or 0
    if charge <= 0 then return end
    spinChargeBar = spinChargeBar or Sprite()
    if spinChargeBar:GetFilename() ~= "gfx/chargebar.anm2" then spinChargeBar:Load("gfx/chargebar.anm2", true) end
    local full = data.MizukiChargeBarFullFrames
    if full then
        spinChargeBar:SetFrame(full <= 12 and "StartCharged" or "Charged", full <= 12 and full - 1 or (full - 13) % 6)
    else
        spinChargeBar:SetFrame("Charging", math.floor(math.min(1, charge / Mizuki.getSpiritSwordChargeProfile(player).MaxFrames) * 100))
    end
    spinChargeBar.Color, spinChargeBar.Scale, spinChargeBar.Rotation = Color(1, 1, 1, 1), Vector.One, 0
    local position = Isaac.WorldToScreen(player.Position) + (renderOffset or Vector.Zero)
        + P.SpinChargeBarOffset - room:GetRenderScrollOffset() - game.ScreenShakeOffset
    -- Standard native bar only; the surrounding circle belongs to ranged charge.
    spinChargeBar:RenderLayer(0, position)
    spinChargeBar:RenderLayer(1, position)
end
Mizuki:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, Mizuki.RenderSpiritSwordSpinCharge)

local function canFireHealthWave(player)
    return player:GetHearts() + player:GetSoulHearts() >= player:GetMaxHearts()
end

local function bladeSprite(cannon)
    local cd = cannon:GetData()
    if not cd.MizukiSpiritSwordSprite or cd.MizukiSpiritSwordArtRevision ~= ART_REVISION then
        local sprite = cd.MizukiSpiritSwordSprite or Sprite()
        loadComposite(sprite, swordArt)
        cd.MizukiSpiritSwordSprite = sprite
        cd.MizukiSpiritSwordArtRevision = ART_REVISION
    end
    return cd.MizukiSpiritSwordSprite
end

local function swordRangeOffset(player)
    -- Native swing child TargetPosition.X (0x96A844..0x96A954) is
    -- 4 + max(0, TearRange - 260) * .15. Keep our established dual-hand
    -- baseline; apply only the extra reach to the blade/connector, not the hand.
    return math.max(0, player.TearRange - 260) * 0.15
end

local function swordWeaponScale(player, params)
    local data = player:GetData()
    if params then
        -- Use the same native parameter roll as this attack's damage/flags.
        -- Rendering reads the latest real attack size without rolling again.
        data.MizukiSpiritSwordWeaponScale = params.TearScale or 1
    end
    return data.MizukiSpiritSwordWeaponScale or 1
end
Mizuki.getSpiritSwordWeaponScale = swordWeaponScale

function Mizuki.getSpiritSwordBladeAttack(cannon)
    local state = cannon.Player:GetData().MizukiSpiritSwordInput
    local attack = state and (state.ChargeContact or state.PairedSpin and state.PairedSpin.Attack)
        or cannon:GetData().MizukiSpiritSwordAttack
    return attack and not attack.Finished and attack or nil
end

function Mizuki.getSpiritSwordBladeRangeOffset(cannon)
    local attack = Mizuki.getSpiritSwordBladeAttack(cannon)
    return attack and attack.RangeOffset or swordRangeOffset(cannon.Player)
end

function Mizuki.getSpiritSwordBladeSpacingScale(cannon)
    local attack = Mizuki.getSpiritSwordBladeAttack(cannon)
    return attack and attack.HitboxScale and attack.HitboxScale.X
        or swordWeaponScale(cannon.Player)
end

local function shakeSwordAttack(attack, weaponScale)
    -- Native Weapon_SpiritSword A0A306..A0A3E5: the maximum created
    -- sword CollisionDamage must exceed 20 and weapon scale exceed 1.5.
    -- Polyphemus is only one source of that scale; no item check here.
    if attack.Echo or attack.ChargeContact or attack.Damage <= 20 or weaponScale <= 1.5 then return end
    local playerData, frame = attack.Player:GetData(), Game():GetFrameCount()
    local strength = math.floor(weaponScale * 5)
    -- Both opposed hands/directional copies belong to one player action.
    local previous = playerData.MizukiSpiritSwordShakeFrame == frame
        and playerData.MizukiSpiritSwordShakeStrength or 0
    if strength <= previous then return end
    playerData.MizukiSpiritSwordShakeFrame, playerData.MizukiSpiritSwordShakeStrength = frame, strength
    Game():ShakeScreen(strength)
end

local function handPosition(player, direction, side)
    local offset = direction * P.HandForwardOffset + Vector(0, P.HandHeight)
        + direction:Rotated(side == 1 and -90 or 90) * P.HandHalfSpacing
    return player.Position + Vector(offset.X * player.SpriteScale.X, offset.Y * player.SpriteScale.Y)
end

local function chargeHandPosition(player, direction, side, forwardSide)
    -- IdleRight's blade axis is its local Y axis. Use that same scale for
    -- root separation so nonuniform character scaling keeps both blades collinear.
    local distance = P.HandForwardOffset * player.SpriteScale.Y
        * (side == forwardSide and 1 or -1)
    return player.Position + Vector(0, P.HandHeight * player.SpriteScale.Y) + direction * distance
end

local function chargePoseProgress(contact)
    local age = Game():GetFrameCount() - contact.Frame
    return (1 - math.cos(math.pi * math.min(1, math.max(0, age / P.ChargePoseFrames)))) * 0.5
end

local function chargePoseRotation(state, side)
    local target = side == state.Side and 0 or 180
    local contact = state.ChargeContact
    local start = contact and contact.StartPoses and contact.StartPoses[side]
    if not start then return target end
    local offset = start.Angle - state.Direction:GetAngleDegrees()
    local turn = (target - offset + 180) % 360 - 180
    return offset + turn * chargePoseProgress(contact)
end

local function chargeHandAnchor(player, state, side)
    local contact = state.ChargeContact
    local target = chargeHandPosition(player, state.Direction, side, state.Side)
    local start = contact and contact.StartPoses and contact.StartPoses[side]
    if not start then return target end
    local origin = player.Position + start.Offset
    return origin + (target - origin) * chargePoseProgress(contact)
end

local function anchor(cannon, direction)
    local player = cannon.Player
    local state = player:GetData().MizukiSpiritSwordInput
    if state then
        local offsets = state.PairedSpin and state.PairedSpin.HandOffsets
        if offsets and offsets[cannon.SubType] then
            local center = Vector(0, P.HandHeight * player.SpriteScale.Y)
            local turn = direction:GetAngleDegrees() - state.PairedSpin.Direction:GetAngleDegrees()
            return player.Position + center + (offsets[cannon.SubType] - center):Rotated(turn)
        end
        if state.RestHandOffsets and state.RestHandOffsets[cannon.SubType] then
            return player.Position + state.RestHandOffsets[cannon.SubType]
        end
        -- Consuming charge disables damage immediately, but retirement is
        -- deferred until the native hit dispatch ends. Keep its visual pose
        -- until retire() transfers both hands into the retained rest pose.
        if state.ChargeContact then
            return chargeHandAnchor(player, state, cannon.SubType)
        end
    end
    return handPosition(cannon.Player, direction, cannon.SubType)
end

function Mizuki.getSpiritSwordEchoPosition(ghost)
    local source = ghost:GetData().MizukiSpiritSwordEchoSource
    if not source or not alive(source.Player, source.PlayerSeed) then return nil end
    if source.PairedSpin and source.PairedSpin.HandOffsets then
        return source.Player.Position + source.PairedSpin.HandOffsets[source.PairedSpin.PrimarySide]
    end
    return handPosition(source.Player, source.Direction,
        source.PairedSpin and source.PairedSpin.PrimarySide or source.HandSide)
end

local function attackPosition(attack)
    if attack.SpinThrow then return copy(attack.ThrowKnife.Position) end
    if attack.PairedSpin and attack.PairedSpin.HandOffsets then
        return attack.Player.Position + attack.PairedSpin.HandOffsets[attack.PairedSpin.PrimarySide]
    end
    if attack.Echo then
        return handPosition(attack.Player, attack.Direction,
            attack.PairedSpin and attack.PairedSpin.PrimarySide or attack.HandSide)
    end
    return anchor(attack.Cannon, attack.Direction)
end

local function attackDirectionalPosition(attack, direction)
    if attack.PairedSpin then
        local center = attack.Player.Position + Vector(0, P.HandHeight * attack.Player.SpriteScale.Y)
        local turn = direction:GetAngleDegrees() - attack.Direction:GetAngleDegrees()
        return center + (attackPosition(attack) - center):Rotated(turn)
    end
    return handPosition(attack.Player, direction, attack.HandSide)
end

local function echoSwingAnimation(animation)
    if animation == "AttackRight" then return "AttackLeft" end
    if animation == "AttackLeft" then return "AttackRight" end
    return animation
end

local function echoPose(attack, sampleAge)
    local age = sampleAge or (Game():GetFrameCount() - attack.Frame)
    local animation, frame, rotation = attack.Echo and attack.Animation or echoSwingAnimation(attack.Animation),
        math.max(0, math.min((attack.Spin and P.SpinFrames or P.SwingFrames) - 1,
            age - (attack.EchoPhaseFrames or 0))), 0
    if attack.PairedSpin then
        animation, frame, rotation = pairedSpinPose(attack.PairedSpin, attack.PairedSpin.PrimarySide,
            sampleAge and math.max(0, sampleAge - (attack.EchoPhaseFrames or 0)))
    end
    return animation, frame, rotation
end

local function createHitbox(attack, index)
    local hitbox = Isaac.Spawn(EntityType.ENTITY_KNIFE, 0, 9522,
        copy(attackPosition(attack)), copy(attack.Player.Velocity), attack.Player):ToKnife()
    hitbox:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    hitbox.Parent, hitbox.SpawnerEntity = attack.Player, attack.Player
    local data = hitbox:GetData()
    data.MizukiSpiritSwordHitbox = true
    data.UpdatedCustomSword = true
    data.MizukiSpiritSwordAttack = attack
    data.MizukiSpiritSwordHitboxIndex = index
    attack.Hitboxes[index] = {Entity = hitbox, Seed = hitbox.InitSeed}
    if index == 1 then attack.Hitbox, attack.HitboxSeed = hitbox, hitbox.InitSeed end
    return hitbox
end

local function retire(attack)
    if attack.Finished then return end
    attack.Finished = true
    if attack.SpinThrow and alive(attack.ThrowKnife, attack.ThrowKnifeSeed) then
        local knife = attack.ThrowKnife
        local data = knife:GetData()
        if data.MizukiSpiritSwordThrowCarrier == true and data.MizukiSpiritSwordThrowAttack == attack then
            if not data.MizukiMultidimensionalKnifeInactive then
                knife.EntityCollisionClass = data.MizukiSpiritSwordThrowCollisionClass
            end
            data.MizukiSpiritSwordThrowCarrier = nil
            data.MizukiSpiritSwordThrowCollisionClass = nil
            data.MizukiSpiritSwordThrowAttack = nil
        end
    end
    local retainedChargePose = false
    if attack.ChargeContact and alive(attack.Player, attack.PlayerSeed) then
        local state = attack.Player:GetData().MizukiSpiritSwordInput
        if state and state.ChargeContact == attack then
            -- Ending contact retires its collision sources, not the two hand
            -- poses. In particular, a consumed charge has already set
            -- ChargeConsumed, so sample the contact geometry directly.
            state.RestHandOffsets = {}
            for side, group in ipairs(attack.Player:GetData().MizukiCannons or {}) do
                for _, cannon in ipairs(group) do
                    local cd = alive(cannon) and cannon:GetData()
                    if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode
                        and not Mizuki.isTech2Cannon(cannon) then
                        state.RestHandOffsets[side] = chargeHandAnchor(attack.Player, state, side) - attack.Player.Position
                        cd.MizukiSpiritSwordRestPose = {
                            Animation = "IdleRight", Frame = 0, RotationOffset = chargePoseRotation(state, side),
                        }
                    end
                end
            end
            retainedChargePose = true
            state.ChargeContact = nil
        end
    end
    for _, entry in ipairs(attack.Hitboxes or {{Entity = attack.Hitbox, Seed = attack.HitboxSeed}}) do
        local hitbox = entry.Entity
        if alive(hitbox, entry.Seed) and hitbox:GetData().MizukiSpiritSwordHitbox == true
            and hitbox:GetData().MizukiSpiritSwordAttack == attack then hitbox:Remove() end
    end

    if alive(attack.Cannon, attack.CannonSeed)
        and attack.Cannon:GetData().MizukiSpiritSwordAttack == attack then
        local cd = attack.Cannon:GetData()
        -- Keep only the visible endpoint, never the retired attack/hitbox.
        if not retainedChargePose then
            cd.MizukiSpiritSwordRestPose = {
                Animation = attack.Animation,
                Frame = math.max(0, math.min(attack.Duration - 1, Game():GetFrameCount() - attack.Frame)),
            }
            if attack.ChargeContact then
                cd.MizukiSpiritSwordRestPose = {Animation = "IdleRight", Frame = 0}
            end
        end
        if attack.PairedSpin then
            local animation, frame, rotation = pairedSpinPose(attack.PairedSpin,
                attack.Echo and attack.PairedSpin.PrimarySide or attack.Cannon.SubType)
            cd.MizukiSpiritSwordRestPose = {Animation = animation, Frame = frame, RotationOffset = rotation}
        end
        if attack.Echo then
            local animation, frame, rotation = echoPose(attack)
            cd.MizukiSpiritSwordRestPose = {Animation = animation, Frame = frame, RotationOffset = rotation}
        end
        cd.MizukiSpiritSwordAttack = nil
    end
end

local function configureHitbox(attack)
    if attack.SpinThrow and (not alive(attack.ThrowKnife, attack.ThrowKnifeSeed)
        or not attack.ThrowKnife:IsFlying()) then return end
    local age = Game():GetFrameCount() - attack.Frame
    local position = attackPosition(attack)
    attack.HitboxScale = attack.HitboxScale or Vector(attack.Scale, attack.Scale)
    local capsules = {}
    local searchCircles, collisionGroups = {}, {}
    attack.FirstImpactStates = attack.FirstImpactStates or {}
    local function addCapsules(group, key, origin)
        local circle = swordHitboxes.searchCircle(group)
        if not circle then return end
        key = key or tostring(attack.HandSide)
        local impact = attack.FirstImpactStates[key]
        if not impact then
            impact = {}
            local saved = attack.SourceFirstImpactStates and attack.SourceFirstImpactStates[key]
            impact.MizukiHaemolacriaCarrier = saved and saved.MizukiHaemolacriaCarrier
            attack.FirstImpactStates[key] = impact
        end
        collisionGroups[#collisionGroups + 1] = {Capsules = group, Circle = circle,
            HitboxIndex = #capsules + 1, Key = key, Origin = copy(origin or position), FirstImpact = impact}
        searchCircles[#searchCircles + 1] = circle
        for _, capsule in ipairs(group) do
            capsule.GroupIndex = #collisionGroups
            capsules[#capsules + 1] = capsule
        end
    end
    local baseRotation = attack.Direction:GetAngleDegrees() - 90
    local reachMultiplier = attack.Spin and swordHitboxes.SpinReachMultiplier or 1
    if attack.SpinThrow then
        -- The flight body is center-pivoted. Use the active SpinRight Hit/Hit2
        -- tracks around that pivot, phase-locked to its actual blade angle.
        -- No inactive animation tail may turn off a sword still in flight.
        local angle = attack.ThrowKnife.SpriteRotation + 90
        local step = math.floor((angle % 360) / 45)
        local frame = (step + 6) % 8 + 2
        local pose = swordHitboxes.Frames.SpinRight[frame + 1][1]
        local rotation = angle - pose[5]
        local group = swordHitboxes.forFrame(Vector.Zero, "SpinRight", frame,
            attack.HitboxScale, rotation, swordHitboxes.SpinReachMultiplier)
        local center = group[1].Center
        for _, hit in ipairs(group) do
            hit.A, hit.B, hit.Center = hit.A - center + position,
                hit.B - center + position, hit.Center - center + position
        end
        addCapsules(group, "throw", position)
    elseif attack.ChargeContact then
        if not attack.ChargeCancelArmed and age >= P.ChargePoseFrames then
            attack.ChargeCancelArmed = true
            -- Transition damage must not prevent this same enemy from
            -- triggering the newly armed held-contact phase.
            attack.Targets = {}
        end
        local state = attack.Player:GetData().MizukiSpiritSwordInput
        if state and state.ChargeContact == attack and not state.ChargeConsumed then
            for side, group in ipairs(attack.Player:GetData().MizukiCannons or {}) do
                if side == state.Side or not Mizuki.hasCannonTech2(attack.Player) then
                    for _, cannon in ipairs(group) do
                        local cd = alive(cannon) and cannon:GetData()
                        if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode then
                            local rotation = baseRotation + chargePoseRotation(state, side)
                            local root = anchor(cannon, attack.Direction)
                            addCapsules(swordHitboxes.forFrame(root,
                                "IdleRight", 0, attack.HitboxScale, rotation,
                                swordHitboxes.ChargeReachMultiplier, attack.RangeOffset), tostring(side), root)
                        end
                    end
                end
            end
        end
    elseif attack.Echo then
        local animation, frame, rotation = echoPose(attack)
        if age >= (attack.EchoPhaseFrames or 0) + (attack.PairedSpin and attack.PairedSpin.AlignFrames or 0) then
            addCapsules(swordHitboxes.forFrame(position, animation, frame, attack.HitboxScale,
                baseRotation + rotation, reachMultiplier, attack.RangeOffset))
        end
    elseif attack.PairedSpin then
        local pair = attack.PairedSpin
        if not pair.HandOffsets then
            pair.HandOffsets = {}
            for side = 1, 2 do pair.HandOffsets[side] = handPosition(attack.Player, attack.Direction, side) - attack.Player.Position end
        end
        if age >= pair.AlignFrames then
            for side = 1, 2 do
                if not Mizuki.hasCannonTech2(attack.Player) or side == pair.PrimarySide then
                local root = position + pair.HandOffsets[side] - pair.HandOffsets[pair.PrimarySide]
                local animation, frame, rotation = pairedSpinPose(pair, side)
                addCapsules(swordHitboxes.forFrame(root, animation, frame,
                    attack.HitboxScale, baseRotation + rotation, reachMultiplier, attack.RangeOffset), tostring(side), root)
                end
            end
        end
    else
        addCapsules(swordHitboxes.forFrame(position, attack.Animation, age, attack.HitboxScale,
            baseRotation, reachMultiplier, attack.RangeOffset))
    end
    if attack.ExtraAngles and #attack.ExtraAngles > 1 then
        local originalGroups = #collisionGroups
        for _, angle in ipairs(attack.ExtraAngles) do
            if angle ~= 0 then
                local root = attackDirectionalPosition(attack, attack.Direction:Rotated(angle))
                for groupIndex = 1, originalGroups do
                    local clones = {}
                    for _, original in ipairs(collisionGroups[groupIndex].Capsules) do
                        local clone = {}
                        for key, value in pairs(original) do clone[key] = value end
                        for _, key in ipairs({"A", "B", "Center"}) do
                            clone[key] = root + (original[key] - position):Rotated(angle)
                        end
                        clone.Rotation = original.Rotation + angle
                        clones[#clones + 1] = clone
                    end
                    local origin = root + (collisionGroups[groupIndex].Origin - position):Rotated(angle)
                    addCapsules(clones, collisionGroups[groupIndex].Key .. ":" .. tostring(angle), origin)
                end
            end
        end
    end
    attack.Capsules = capsules
    attack.SearchCircles = searchCircles
    attack.CollisionGroups = collisionGroups
    attack.Hitboxes = attack.Hitboxes or {{Entity = attack.Hitbox, Seed = attack.HitboxSeed}}
    for index = 1, math.max(1, #capsules, #attack.Hitboxes) do
        local entry = attack.Hitboxes[index]
        local hitbox = entry and alive(entry.Entity, entry.Seed) and entry.Entity
        if not hitbox then hitbox = createHitbox(attack, index) end
        local data = hitbox:GetData()
        if data.MizukiSpiritSwordHitbox == true and data.MizukiSpiritSwordAttack == attack then
            local capsule = capsules[index]
            data.MizukiSpiritSwordHitboxIndex = index
            data.MizukiSpiritSwordGroupIndex = capsule and capsule.GroupIndex or nil
            data.MizukiSpecialBrimstoneCurse = attack.Curse
            hitbox.Variant = 0
            -- GetCollisionCapsule and the ordinary debug renderer both use
            -- Size, SizeMulti and SpriteRotation. Keep the enclosing radius in
            -- Size and express the shorter capsule axis through SizeMulti.
            hitbox.Position = capsule and capsule.Center or position
            hitbox.PositionOffset = Vector.Zero
            hitbox.Velocity = copy(attack.SpinThrow and attack.ThrowKnife.Velocity or attack.Player.Velocity)
            hitbox:SetSize(capsule and capsule.Extent or 0,
                capsule and capsule.Extent > 0 and Vector(1, capsule.Radius / capsule.Extent) or Vector.One, 0)
            hitbox.SpriteRotation = capsule and capsule.Rotation or 0
            hitbox.Rotation = hitbox.SpriteRotation
            hitbox.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            -- Contacts are queried from each sword's outer circle in PostUpdate.
            -- Native debug rendering skips ENTCOLL_NONE. The owned pre-collision
            -- callback below cancels every native contact, so active queries
            -- still exclusively own damage and the shared hit ledger.
            hitbox.EntityCollisionClass = capsule
                and EntityCollisionClass.ENTCOLL_ENEMIES
                or EntityCollisionClass.ENTCOLL_NONE
            hitbox.TearFlags = attack.Flags
            -- The engine can cache damage before pre-collision reconfiguration.
            -- This field describes our attack; the owned damage callback below
            -- dispatches the final amount instead of trusting that cached value.
            hitbox.CollisionDamage = attack.Damage
            hitbox.Color = Color(1, 1, 1, 0)
            hitbox:GetSprite().Color = hitbox.Color
        end
    end

end

function Mizuki.syncSpiritSwordKnifeThrow(knife, cannon)
    local data = knife:GetData()
    local attack = data.MizukiSpiritSwordThrowAttack
    local created, replaySource, replayMultiplier, forkSource
    if data.MizukiSpiritSwordSpinThrow ~= true or not knife:IsFlying()
        or data.MizukiMultidimensionalKnifeInactive or not alive(cannon)
        or not Mizuki.usesCannonSpiritSword(cannon.Player) then
        if attack and attack.SpinThrow then retire(attack) end
        return
    end
    if not attack or attack.Finished then
        local player = cannon.Player
        local child = data.MizukiEchoChild
        local source = child and child.SpiritSwordThrowSource
        local fork = data.MizukiMultidimensionalKnife == true and data.MizukiCannonKnifeMotionSource
        if alive(fork) then source = fork:GetData().MizukiSpiritSwordThrowAttack end
        local params = not source and player:GetTearHitParams(WeaponType.WEAPON_SPIRIT_SWORD, 1, 1, knife)
        local multiplier = not fork and child and child.Shot.DamageMultiplier
            or (not source and Mizuki.getPersistentEchoKnifeMultiplier
                and Mizuki.getPersistentEchoKnifeMultiplier(knife)) or 1
        local scale = source and copy(source.HitboxScale)
            or Vector.One * swordWeaponScale(player, params)
        attack = {
            SpinThrow = true, ThrowKnife = knife, ThrowKnifeSeed = knife.InitSeed,
            Player = player, PlayerSeed = player.InitSeed, Cannon = cannon, CannonSeed = cannon.InitSeed,
            HandSide = cannon.SubType, Frame = Game():GetFrameCount(), Duration = math.huge,
            Direction = Vector.FromAngle(knife.Rotation), Animation = "SpinRight", Spin = true,
            BaseDamage = source and source.BaseDamage or params.TearDamage,
            Damage = (source and source.Damage or params.TearDamage * P.SpinMultiplier + P.SpinBonus) * multiplier,
            Flags = knife.TearFlags | TearFlags.TEAR_SHIELDED, Color = Color.Lerp(knife.Color, knife.Color, 0),
            Scale = 1, HitboxScale = scale, Anchor = copy(knife.Position),
            Echo = source and source.Echo or child ~= nil or cannon:GetData().MizukiPersistentEchoMode == true,
            EchoDamageMultiplier = source and (source.EchoDamageMultiplier or 1) * multiplier or multiplier,
            SourceFirstImpactStates = source and source.FirstImpactStates,
            Targets = {}, Hitboxes = {}, Waves = {},
            Curse = data.MizukiSpecialBrimstoneCurse,
        }
        data.MizukiSpiritSwordThrowCollisionClass = knife.EntityCollisionClass
        data.MizukiSpiritSwordThrowCarrier = true
        data.MizukiSpiritSwordThrowAttack = attack
        createHitbox(attack, 1)
        created, replaySource, replayMultiplier, forkSource = true, source, multiplier, fork
    end
    -- The visible knife remains the native flight clock, never a damage source.
    knife.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    registerAttack(attack)
    attack.Flags = knife.TearFlags | TearFlags.TEAR_SHIELDED
    local visibleColor = data.MizukiCannonKnifeDrawColor or knife.Color
    attack.Color = Color.Lerp(visibleColor, visibleColor, 0)
    attack.Curse = data.MizukiSpecialBrimstoneCurse
    attack.DeadEyeAttack = data.MizukiDeadEyeAttack
    configureHitbox(attack)
    if created and not forkSource then
        if not attack.Echo then shakeSwordAttack(attack, swordWeaponScale(attack.Player)) end
        if replaySource then
            for _, wave in ipairs(replaySource.Waves or {}) do
                fireWave(attack, wave.Direction, replayMultiplier, wave)
            end
        elseif not attack.Echo then
            local angles = {0}
            Mizuki.appendLungVolleyAngles(attack.Player, angles, {}, false)
            for _, angle in ipairs(angles) do fireWave(attack, attack.Direction:Rotated(angle), 1) end
        end
    end
end

local function startAttack(player, cannon, direction, spin, alternate, source, multiplier, spinPair, isContact)
    local cd = cannon:GetData()
    if cd.MizukiSpiritSwordAttack then retire(cd.MizukiSpiritSwordAttack) end
    local params = not source and player:GetTearHitParams(WeaponType.WEAPON_SPIRIT_SWORD, 1, 1, nil)
    local weaponScale = not source and swordWeaponScale(player, params)
    -- Delay the animation timeline, not the weapon's world rotation. A normal
    -- stroke spans half a turn; a spin spans a full turn.
    local echoPhaseFrames = source and math.floor((spin and P.SpinFrames / 4 or P.SwingFrames / 2) + 0.5) or 0
    if source and source.PairedSpin then
        spinPair = {}
        for key, value in pairs(source.PairedSpin) do spinPair[key] = value end
        spinPair.Frame = Game():GetFrameCount() + echoPhaseFrames
    end
    local attack = {
        Player = player, PlayerSeed = player.InitSeed, Cannon = cannon, CannonSeed = cannon.InitSeed,
        HandSide = source and source.HandSide or cannon.SubType,
        Frame = Game():GetFrameCount(), Direction = copy(direction), Spin = spin, ChargeContact = isContact == true,
        Duration = source and source.Duration + echoPhaseFrames or (spin and (spinPair and spinPair.Duration or P.SpinFrames) or P.SwingFrames),
        EchoPhaseFrames = echoPhaseFrames,
        PairedSpin = spinPair,
        Animation = spin and "SpinRight" or (alternate and "AttackLeft" or "AttackRight"),
        BaseDamage = source and (source.BaseDamage or 0) or params.TearDamage,
        Damage = source and source.Damage * multiplier
            or (isContact and params.TearDamage
                or params.TearDamage * (spin and P.SpinMultiplier or P.MeleeMultiplier)
                    + (spin and P.SpinBonus or P.MeleeBonus)),
        -- Spin and the native Technology/Mom's Knife/Lost Contact synergies
        -- reflect hostile projectiles. Ranged beams keep their own tear flags.
        Flags = source and source.Flags or ((spin or player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_LOST_CONTACT))
            and (params.TearFlags | TearFlags.TEAR_SHIELDED) or params.TearFlags),
        Color = Color.Lerp(source and source.Color or params.TearColor,
            source and source.Color or params.TearColor, 0),
        -- Sword artwork uses the player's body color, independently of tear
        -- effects. Preserve that visual snapshot for the blue echo too.
        VisualColor = Color.Lerp(source and (source.VisualColor or source.Player.Color) or player.Color,
            source and (source.VisualColor or source.Player.Color) or player.Color, 0),
        Scale = source and source.Scale or math.max(math.abs(player.SpriteScale.X), math.abs(player.SpriteScale.Y)),
        HitboxScale = source and copy(source.HitboxScale or Vector(source.Scale, source.Scale))
            or Vector(weaponScale, weaponScale),
        RangeOffset = source and source.RangeOffset or swordRangeOffset(player),
        SourceFirstImpactStates = source and source.FirstImpactStates,
        EchoDamageMultiplier = source and multiplier or nil,
        Anchor = source and copy(source.Anchor) or anchor(cannon, direction), Targets = {},
        Echo = source ~= nil, Waves = {}, Hitboxes = {},
        ExtraAngles = source and source.ExtraAngles or nil,
        BladeVisual = source and source.BladeVisual or Mizuki.snapshotSpiritSwordBladeVisual(cannon),
    }
    if not source and not spin and not isContact and player:HasCollectible(CollectibleType.COLLECTIBLE_PROPTOSIS) then
        -- Proptosis changes the damage term of melee, not the fixed bonus.
        attack.Damage = params.TearDamage * (spin and P.SpinMultiplier or P.MeleeMultiplier) * 3
            + (spin and P.SpinBonus or P.MeleeBonus)
    end
    if source then attack.Animation = echoSwingAnimation(source.Animation) end
    local hitbox = createHitbox(attack, 1)
    cd.MizukiSpiritSwordAttack = attack
    cd.MizukiSpiritSwordRestPose = nil
    local sprite = bladeSprite(cannon)
    sprite:Play(attack.Animation, true)
    if source then
        hitbox:GetData().MizukiSpecialBrimstoneCurse = source.Curse
    else
        if not isContact then attack.DeadEyeAttack = Mizuki.trackDeadEyeSwing(player, hitbox, attack.Duration) end
        Mizuki.rollSpecialBrimstone(hitbox, player)
        attack.Curse = hitbox:GetData().MizukiSpecialBrimstoneCurse
    end
    configureHitbox(attack)
    registerAttack(attack)
    if not source then shakeSwordAttack(attack, weaponScale) end
    return attack
end

local function fireSwordTechRing(attack, source, multiplier)
    if not source and not attack.Player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY) then return end
    -- Native Spirit Sword collision/attack creation, 9688D0 -> 96AB71..96ACBD.
    -- (28 + 30 + Normalize(RotationOffset) * 60/180) * SpriteScale.Y.
    -- Our blade's rotation offset is zero; world aim/animation rotation is
    -- separate and must not change the radius when turning the player.
    local radius = source and source.Radius or 58 * math.abs(attack.HitboxScale.Y)
    if radius <= 0 then return end
    local player = attack.Player
    -- The sword branch directly creates 7.2.3; FireTechXLaser is not involved.
    local ring = Isaac.Spawn(EntityType.ENTITY_LASER, LaserVariant.THIN_RED,
        LaserSubType.LASER_SUBTYPE_RING_FOLLOW_PARENT,
        copy(player.Position), copy(player.Velocity), player):ToLaser()
    ring:GetData().MizukiSpiritSwordTechRing = true
    ring:GetData().MizukiBeamOwner = player
    ring.Radius = radius
    ring.SubType, ring.Parent = LaserSubType.LASER_SUBTYPE_RING_FOLLOW_PARENT, player
    ring.ParentOffset, ring.DisableFollowParent = Vector.Zero, false
    ring.PositionOffset, ring.Velocity, ring.Timeout = Vector(0, P.HandHeight), copy(player.Velocity), 3
    ring:SetOneHit(true) -- native 96AC9B writes 515, exposed by SetOneHit
    ring.TearFlags = attack.Flags & ~Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS
    -- Deliberately retain Mizuki's attack tint, per the requested appearance.
    ring.Color = Color.Lerp(attack.Color, attack.Color, 0)
    ring.CollisionDamage = (source and source.Damage or attack.BaseDamage) * (multiplier or 1)
    ring.SpawnerEntity = attack.Cannon
    -- Native 96ACB9..96ACBD performs one birth update after these settings.
    -- Initialize the laser's native animation/sample state once, not per frame.
    ring:Update()
    ring.Color = Color.Lerp(attack.Color, attack.Color, 0)
    if not source then
        attack.TechRing = {Radius = radius, Damage = ring.CollisionDamage}
    end
end

clearChargeContact = function(state)
    local attack = state and state.ChargeContact
    if attack then retire(attack); state.ChargeContact = nil end
end

beginChargeContact = function(player, data, state)
    if state.ChargeContact or state.ChargeConsumed then return end
    local cannon
    for _, candidate in ipairs(data.MizukiCannons[state.Side] or {}) do
        local cd = alive(candidate) and candidate:GetData()
        if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode then cannon = candidate; break end
    end
    if not cannon then return end
    -- Sample both completed strokes before startAttack replaces the active
    -- hand's animation. Keep offsets relative to the moving player.
    local starts = {}
    for side, group in ipairs(data.MizukiCannons or {}) do
        for _, candidate in ipairs(group) do
            local cd = alive(candidate) and candidate:GetData()
            if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode
                and not Mizuki.isTech2Cannon(candidate) then
                local _, direction, angle = swordVisualState(candidate)
                starts[side] = {Offset = anchor(candidate, direction) - player.Position, Angle = angle}
                break
            end
        end
    end
    -- This entry is reached only with real held input. Carry the old resting
    -- roots into StartPoses, then let the new charge own their movement (also
    -- when a room change retired the previous contact mid-transition).
    state.RestHandOffsets = nil
    local attack = startAttack(player, cannon, state.Direction, false, false, nil, 1, nil, true)
    attack.ChargeContact, attack.Duration = true, math.huge
    attack.StartPoses = starts
    state.ChargeContact = attack
    configureHitbox(attack)
end

fireWave = function(attack, direction, multiplier, source)
    local player = attack.Player

    local position = attack.SpinThrow and copy(attack.ThrowKnife.Position)
        or (attackDirectionalPosition(attack, direction) + direction * (attack.RangeOffset or 0))
    local appearance = source and source.Appearance
    if not source then
        if player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then appearance = "mom_knife"
        else
            local definition = Mizuki.getCannonAttackAppearanceDefinition(attack.Cannon)
            appearance = definition and definition.Id
        end
    end
    local velocity = source and source.Velocity
        or direction:Resized(player.ShotSpeed * Mizuki.WeaponParameters.TearBaseSpeed
            * (attack.Spin and P.SpinShotSpeedMultiplier or 1))

    -- Match fetal creation: omit only Mizuki's cached character colorize at
    -- the native source, preserving this shot's single random item/color roll.
    local untinted = Mizuki.isMizuki(player) and player:GetData().MizukiUntintedTearColor
    local playerColor = player.TearColor
    if untinted then player.TearColor = untinted end
    local ok, tear = pcall(player.FireTear, player,
        copy(position), copy(velocity), false, false, false, player, multiplier or 1)
    if untinted then player.TearColor = playerColor end
    if not ok then error(tear, 0) end

    tear:ChangeVariant(source and source.Variant
        or ((player:HasCollectible(CollectibleType.COLLECTIBLE_TECHNOLOGY)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_TECH_X))
            and TearVariant.TECH_SWORD_BEAM or TearVariant.SWORD_BEAM))

    tear:ClearTearFlags(Mizuki.MIZUKI_FORBIDDEN_TEAR_FLAGS)
    if not source and player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT) then
        tear:AddTearFlags(TearFlags.TEAR_HOMING)
    end
    tear:GetData().MizukiSpiritSwordWaveAppearance = appearance
    tear:GetData().MizukiSpiritSwordWaveAppearanceResolved = true
    if source then
        tear.Scale, tear.Height = source.Scale, source.Height
        tear.FallingSpeed, tear.FallingAcceleration = source.FallingSpeed, source.FallingAcceleration
        Mizuki.bindEchoAttackReplay(tear, source.Sequence, {
            Alpha = Mizuki.CannonEchoReplayAlpha, Tint = true, DamageMultiplier = multiplier })
    else
        tear.CollisionDamage = tear.CollisionDamage * (attack.Spin and 4 or 1)
            + (attack.Spin and 4 or 2) * (multiplier or 1)
        Mizuki.trackDeadEyeProjectile(player, tear)
        attack.Waves[#attack.Waves + 1] = {
            Direction = copy(direction), Velocity = copy(tear.Velocity), Variant = tear.Variant,
            Scale = tear.Scale, Height = tear.Height, FallingSpeed = tear.FallingSpeed,
            FallingAcceleration = tear.FallingAcceleration, Sequence = Mizuki.startEchoAttackRecording(tear),
            Appearance = appearance,
            FireAge = Game():GetFrameCount() - attack.Frame,
        }
    end
    Mizuki.applySpiritSwordVisual(tear)
    return tear
end

function Mizuki.replaySpiritSwordAttack(player, ghost, source, multiplier)
    local attack = startAttack(player, ghost, source.Direction, source.Spin, false, source, multiplier)
    attack.PendingWaves, attack.ReplayMultiplier = {}, multiplier
    for _, wave in ipairs(source.Waves) do
        if (wave.FireAge or 0) == 0 then fireWave(attack, wave.Direction, multiplier, wave)
        else attack.PendingWaves[#attack.PendingWaves + 1] = wave end
    end
    if source.TechRing then fireSwordTechRing(attack, source.TechRing, multiplier) end
    return attack
end

function Mizuki.getSpiritSwordSwingDirection(data, activeOnly)
    local state = data.MizukiSpiritSwordInput
    if state and state.Held and state.ChargeStart and not state.ChargeConsumed then return state.Direction end
    local pair = data.MizukiSpiritSwordInput and data.MizukiSpiritSwordInput.PairedSpin
    if pair and Game():GetFrameCount() < pair.Frame + pair.Duration then return pair.Direction end
    local direction, latest
    for _, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            local attack = alive(cannon) and cannon:GetData().MizukiSpiritSwordAttack
            if attack and not attack.Finished and Game():GetFrameCount() < attack.Frame + attack.Duration
                and (not latest or attack.Frame > latest) then
                direction, latest = attack.Direction, attack.Frame
            end
        end
    end
    if direction then return direction end
    if not activeOnly then return Mizuki.getAttackPoseDirection(data) end
end

function Mizuki.isSpiritSwordPairPrepared(player, data)
    local state = data.MizukiSpiritSwordInput
    if not state or not state.PairPrepared or not Mizuki.usesCannonSpiritSword(player) then return false end
    return Mizuki.isAttackPoseHeld(data)
end

function Mizuki.updateSpiritSwordBodyVisibility(cannon)
    if not alive(cannon) or cannon.Type ~= EntityType.ENTITY_FAMILIAR
        or cannon.Variant ~= Mizuki.CannonVariant then return end
    local cd, player = cannon:GetData(), cannon.Player
    local wasHidden = cd.MizukiSpiritSwordBodyHidden == true
    local sword = player and player:Exists() and Mizuki.isMizuki(player)
        and Mizuki.usesCannonSpiritSword(player)
        and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode
        and not Mizuki.isTech2Cannon(cannon)
    cd.MizukiSpiritSwordBodyHidden = sword
        and Mizuki.isSpiritSwordPairPrepared(player, player:GetData()) or false
    if not sword or cd.MizukiSpiritSwordBodyHidden then
        cd.MizukiSpiritSwordShadowReturning = nil
    elseif wasHidden then
        cd.MizukiSpiritSwordShadowReturning = true
    end
    -- This explicit role/state only hides registered cannon bodies, including
    -- their native shadow. Sword art is owned by the renderer/fallback pass.
    cannon.Visible = not cd.MizukiSpiritSwordBodyHidden and not cd.MizukiSpiritSwordShadowReturning
        and not cd.MizukiAwaitingInitialLayout and not cd.MizukiGuillotineDisplaySuppressed
        and not cd.MizukiTech2EchoSuppressed
end

-- The raw idle target precedes elastic easing. Compare the player's relative
-- formation pose so normal movement lag does not indefinitely hide the shadow.
function Mizuki.updateSpiritSwordReturnShadow(cannon, targetPosition, idle)
    if not alive(cannon) or cannon.Type ~= EntityType.ENTITY_FAMILIAR
        or cannon.Variant ~= Mizuki.CannonVariant then return end
    local cd = cannon:GetData()
    if cd.MizukiSpiritSwordShadowReturning ~= true or not idle then return end
    local pose = cd.MizukiPoseOffset or (cannon.Position - cannon.Player.Position)
    if (pose - (targetPosition - cannon.Player.Position)):Length() <= P.ReturnShadowDistance then
        cd.MizukiSpiritSwordShadowReturning = nil
        Mizuki.updateSpiritSwordBodyVisibility(cannon)
    end
end

function Mizuki.clearSpiritSwordInput(data)
    clearChargeContact(data.MizukiSpiritSwordInput)
    data.MizukiSpiritSwordInput = nil
    data.MizukiSpiritSwordShooting = nil
    data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
    for _, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            local attack = alive(cannon) and cannon:GetData().MizukiSpiritSwordAttack
            if attack then retire(attack) end
            if alive(cannon) then cannon:GetData().MizukiSpiritSwordRestPose = nil end
            Mizuki.updateSpiritSwordBodyVisibility(cannon)
            updateSwordRenderer(cannon)
        end
    end
end

function Mizuki.updateSpiritSwordInput(player, data, held, direction, profile)
    local state = data.MizukiSpiritSwordInput or { Held = false, Cooldown = 0, WaveCooldown = 0 }
    data.MizukiSpiritSwordInput = state
    if state.PairedSpin and Game():GetFrameCount() >= state.PairedSpin.Frame + state.PairedSpin.Duration then
        finishPairedSpin(data)
    end
    -- Each hand reverses its own next stroke. A global toggle plus alternating
    -- hands would leave each hand repeating the same stroke forever.
    state.NextReverse = state.NextReverse or { true, false }
    state.Cooldown = math.max(0, state.Cooldown - 1)
    state.WaveCooldown = math.max(0, state.WaveCooldown - 1)
    local function fire(spin)
        if spin and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
            -- Mom's Knife replaces the local spin with a real throw. Retiring
            -- contact keeps both prepared hand poses; no paired-spin animation,
            -- hand-centered melee spin detector is created here. The actual
            -- throw creates its own spin collision and sword wave at launch.
            clearChargeContact(state)
            -- At very high fire rate, full charge can precede the six-frame
            -- hand transition. A front/back throw still needs opposed axes.
            state.RestHandOffsets = {}
            for hand, group in ipairs(data.MizukiCannons or {}) do
                for _, cannon in ipairs(group) do
                    local cd = alive(cannon) and cannon:GetData()
                    if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode
                        and not Mizuki.isTech2Cannon(cannon) then
                        state.RestHandOffsets[hand] = chargeHandPosition(player, state.Direction, hand, state.Side) - player.Position
                        cd.MizukiSpiritSwordRestPose = {Animation = "IdleRight", Frame = 0,
                            RotationOffset = hand == state.Side and 0 or 180}
                    end
                end
            end
            state.KnifeSpinRelease = true
            state.ChargeStart = nil
            Mizuki.chargeIsaacsTearsFromSword(player, true)
            SFXManager():Play(SoundEffect.SOUND_SWORD_SPIN, 1, 0, false, 1)
            return true
        end
        local nextSide = -(data.MizukiShotSide or -1)
        local side = nextSide == -1 and 1 or 2
        if spin then side = state.Side or side end
        if Mizuki.hasCannonTech2(player) then side = 1 end
        local aim = state.Direction or direction
        local angles, spins = Mizuki.getSpiritSwordVolley(player)
        local pair = spin and beginPairedSpin(player, data, side, aim, spins)
        clearChargeContact(state)
        local volley = Mizuki.beginCannonEchoShot(player, side)
        local canWave = spin or (canFireHealthWave(player) and state.WaveCooldown <= 0)
        local fired = false
        for _, cannon in ipairs(data.MizukiCannons[side] or {}) do
            local cd = cannon:GetData()
            if alive(cannon) and not cd.MizukiAwaitingInitialLayout
                and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode then
                local attack = startAttack(player, cannon, aim,
                    spin, state.NextReverse[side], nil, 1, pair)
                attack.ExtraAngles, attack.SpinCount, attack.NextSpinWave = angles, spins, 2
                if pair then pair.Attack = attack end
                configureHitbox(attack)
                fireSwordTechRing(attack)
                if canWave then
                    local waveAngles = {}
                    for _, angle in ipairs(angles) do waveAngles[#waveAngles + 1] = angle end
                    if spin then Mizuki.appendLungVolleyAngles(player, waveAngles, {}, false) end
                    attack.WaveAngles = waveAngles
                    for _, angle in ipairs(waveAngles) do
                        fireWave(attack, attack.Direction:Rotated(angle), 1)
                    end
                end
                if volley then Mizuki.captureCannonEchoSpiritSword(volley, attack) end
                fired = true
            end
        end
        if fired then
            state.PairedSpin = pair or nil
            state.PairPrepared = true
            if not spin then data.MizukiShotSide = nextSide end
            state.Side, state.Direction = side, copy(aim)
            state.Cooldown = Mizuki.getFireInterval(player)
            if not spin then state.NextReverse[side] = not state.NextReverse[side] end
            if canWave then state.WaveCooldown = math.max(Mizuki.RuntimeParameters.MinimumFireInterval,
                Mizuki.getFireInterval(player) * P.WaveIntervalMultiplier) end
            state.ChargeConsumed = false
            state.ChargeStart = Game():GetFrameCount() + (spin and pair.Duration or P.SwingFrames)
            Mizuki.recordMeleeAttackEffects(player, side, state.Direction)
            Mizuki.chargeIsaacsTearsFromSword(player, spin)
            SFXManager():Play(spin and SoundEffect.SOUND_SWORD_SPIN or SoundEffect.SOUND_SHELLGAME, 1, 0, false, 1)
        end
        return fired
    end
    local pressed = held and not state.Held
    local frame = Game():GetFrameCount()
    local protectedCharge, resumed = Mizuki.protectChargeRelease(state, held, data.MizukiCharge or 0, state.ChargeConsumed)
    local resume = pressed and resumed
    data.MizukiCharge = protectedCharge
    if resume then
        state.ChargeStart = frame - data.MizukiCharge
    elseif pressed then
        clearChargeContact(state)
        if state.PairedSpin then finishPairedSpin(data) end
        state.ChargeStart = nil
        state.ChargeConsumed = false
        state.Direction = copy(direction or state.Direction)
    end
    -- A physical press may choose a new hand layout; passive spin/contact
    -- completion, movement and release grace retain both hand poses.
    if pressed then state.RestHandOffsets = nil end
    if held then
        -- Keep the original direction until release or the held blade hits.
        if not state.Direction then state.Direction = copy(direction) end
        if state.ChargeConsumed then state.Direction = copy(direction or state.Direction) end
        local soy = player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK)
            or player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK)
        -- Manual presses are individual swings, independent of panel fire delay.
        -- Only automatic Soy/Almond repetition uses the fire-rate clock.
        local automatic = soy or data.MizukiKidneyStoneBurst ~= nil or player.MaxFireDelay + 1 <= 1
        if automatic then
            clearChargeContact(state)
            state.ChargeStart = nil
            state.Direction = copy(direction or state.Direction)
        end
        if (pressed and not resume) or (automatic and state.Cooldown == 0) then fire(false) end
        if not automatic and state.ChargeStart and Game():GetFrameCount() >= state.ChargeStart then
            beginChargeContact(player, data, state)
        end
        data.MizukiCharge = not automatic and state.ChargeStart
            and math.min(profile.MaxFrames, math.max(0, Game():GetFrameCount() - state.ChargeStart + 1)) or 0
        data.MizukiAim = state.Direction
        data.MizukiChargeBarFullFrames = data.MizukiCharge >= profile.MaxFrames
            and ((data.MizukiChargeBarFullFrames or 0) + 1) or nil
    elseif state.Held then
        if state.ChargeStart and (data.MizukiCharge or 0) >= profile.MaxFrames then
            fire(true)
            clearChargeContact(state)
            state.ChargeStart = nil
            Mizuki.protectChargeRelease(state, false, 0, true)
            data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
        elseif not state.ChargeConsumed and (data.MizukiCharge or 0) > 0 then
            -- Pause partial charge across a brief release, instead of losing
            -- spin progress whenever a ranged charged shot is released.
            -- The shared release controller already paused this progress.
        else
            clearChargeContact(state)
            state.ChargeStart = nil
            data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
        end
    elseif not held and not resumed and protectedCharge <= 0 and state.ChargeContact then
        clearChargeContact(state)
        state.ChargeStart = nil
        data.MizukiCharge, data.MizukiAim, data.MizukiChargeBarFullFrames = 0, nil, nil
    end
    state.Held = held
    Mizuki.updateAttackPose(data, Game():GetFrameCount(), false, state.Direction)
    for _, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            Mizuki.updateSpiritSwordBodyVisibility(cannon)
            updateSwordRenderer(cannon)
        end
    end
end

function Mizuki.renderCannonSpiritSword(cannon)
    if not Mizuki.usesCannonSpiritSword(cannon.Player) or Mizuki.isTech2Cannon(cannon) then return false end
    local cd = cannon:GetData()
    if cd.MizukiGuillotineNonFiring or cd.MizukiPersistentEchoMode then return false end
    -- Both blades share the same release lease. Suppress both resting bodies
    -- while the sword render pass owns their active/prepared artwork.
    return Mizuki.isSpiritSwordPairPrepared(cannon.Player, cannon.Player:GetData())
end

-- Native body-layer angles, expanded to logical frames (including the
-- interpolated settling frames). Depth follows the blade, not just aim/input.
local bladeAngles = {
    IdleRight = {90},
    AttackRight = {0, 30, 90, 135, 188, 184, 180, 180},
    AttackLeft = {180, 150, 90, 45, -8, -4, 0, 0},
    SpinRight = {45, 45, 90, 135, 180, 225, 270, -45, 0, 45, 100, 92.5, 85, 90},
}
-- Native arcs follow the tip's range displacement without enlarging their art.
function Mizuki.getSpiritSwordRangeDisplacement(animation, frame, scale, rotation, rangeOffset, spacingScale)
    if animation == "IdleRight" or not rangeOffset or rangeOffset == 0 then return Vector.Zero end
    local angles = bladeAngles[animation]
    local angle = angles[math.min(#angles, frame + 1)]
    local connection = P.HiltBladeConnection:Rotated(angle)
    connection = Vector(connection.X * scale.X, connection.Y * scale.Y):Rotated(rotation)
    local tip = Mizuki.getSpiritSwordPoseTip(Vector.Zero, animation, frame,
        spacingScale or scale.Y / Mizuki.CANNON_ART_SCALE_MULTIPLIER, rotation, 0, connection:Resized(1))
    return tip and tip * (Mizuki.getSpiritSwordRangeMultiplier(rangeOffset) - 1) or Vector.Zero
end

pairedSpinPose = function(pair, side, sampleAge)
    local age = math.max(0, sampleAge or (Game():GetFrameCount() - pair.Frame))
    local base = pair.Direction:GetAngleDegrees() - 90
    if age < pair.AlignFrames then
        local progress = (1 - math.cos(math.pi * age / pair.AlignFrames)) * 0.5
        local angle = pair.StartAngles[side]
        if side ~= pair.PrimarySide then angle = angle + pair.AlignTurn * progress end
        return "AttackRight", 0, angle - base
    end
    local elapsed = age - pair.AlignFrames
    local loopEnd = 11 + ((pair.SpinCount or 1) - 1) * 9
    local frame = elapsed < 11 and elapsed
        or elapsed < loopEnd and 2 + (elapsed - 11) % 9
        or math.min(13, 11 + elapsed - loopEnd)
    local phase = side == pair.PrimarySide and 0 or 180
    -- IdleRight and SpinRight's final body angle are both 90 degrees. The
    -- native 45-degree opening is anticipation, not the resting direction.
    return "SpinRight", frame, pair.StartAngles[pair.PrimarySide] - base - 90 + phase
end

finishPairedSpin = function(data)
    local state = data.MizukiSpiritSwordInput
    local pair = state and state.PairedSpin
    if not pair then return end
    -- Retire the spin clock, not its final hand arrangement. These are
    -- player-relative anchors, so movement carries both collinear swords.
    state.RestHandOffsets = {}
    for side, offset in pairs(pair.HandOffsets or {}) do state.RestHandOffsets[side] = copy(offset) end
    for side, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            local cd = alive(cannon) and cannon:GetData()
            if cd and not cd.MizukiGuillotineNonFiring and not cd.MizukiPersistentEchoMode
                and not Mizuki.isTech2Cannon(cannon) then
                local animation, frame, rotation = pairedSpinPose(pair, side)
                cd.MizukiSpiritSwordRestPose = {Animation = animation, Frame = frame, RotationOffset = rotation}
            end
        end
    end
    state.PairedSpin = nil
end

swordVisualState = function(cannon)
    local cd, player = cannon:GetData(), cannon.Player
    local state, attack = player:GetData().MizukiSpiritSwordInput, cd.MizukiSpiritSwordAttack
    if attack and attack.Finished then attack = nil end
    local rest = cd.MizukiSpiritSwordRestPose
    local reverse = state and state.NextReverse and state.NextReverse[cannon.SubType]
    local animation = attack and attack.Animation or (rest and rest.Animation)
        or (reverse and "AttackLeft" or "AttackRight")
    local frame = attack and math.max(0, math.min(attack.Duration - 1, Game():GetFrameCount() - attack.Frame))
        or (rest and rest.Frame) or 0
    local rotationOffset = not attack and rest and rest.RotationOffset or 0
    local direction = attack and attack.Direction or state.Direction or player:GetData().MizukiCannonAim
        or Vector.FromAngle((player:GetHeadDirection() * 90 + 180) % 360)
    local pair = state.PairedSpin or (attack and attack.PairedSpin)
    if pair then
        direction = pair.Direction
        animation, frame, rotationOffset = pairedSpinPose(pair, cannon.SubType)
    elseif state.ChargeContact then
        animation, frame = "IdleRight", 0
        rotationOffset = chargePoseRotation(state, cannon.SubType)
        direction = state.Direction
        attack = nil -- held contact is not a slash arc
    end
    local angle = direction:GetAngleDegrees() - 90 + rotationOffset + bladeAngles[animation][frame + 1]
    return attack, direction, angle, animation, frame, rotationOffset
end

beginPairedSpin = function(player, data, primarySide, direction, count)
    local starts = {}
    for side, group in ipairs(data.MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            local cd = alive(cannon) and cannon:GetData()
            if cd and not cd.MizukiAwaitingInitialLayout and not cd.MizukiGuillotineNonFiring
                and not cd.MizukiPersistentEchoMode and not Mizuki.isTech2Cannon(cannon) then
                local _, _, angle = swordVisualState(cannon)
                starts[side] = angle
                break
            end
        end
    end
    starts[primarySide] = starts[primarySide] or direction:GetAngleDegrees()
    local other = 3 - primarySide
    starts[other] = starts[other] or starts[primarySide] + 180
    local turn = (starts[primarySide] + 180 - starts[other]) % 360
    if turn > 180 then turn = turn - 360 end
    local align = math.abs(turn) > 0.1 and P.SpinAlignFrames or 0
    local handOffsets = {}
    local state = data.MizukiSpiritSwordInput
    for side = 1, 2 do
        local root = handPosition(player, direction, side)
        if state.ChargeContact and not state.ChargeConsumed then
            root = chargeHandAnchor(player, state, side)
        end
        handOffsets[side] = root - player.Position
    end
    return {Frame = Game():GetFrameCount(), Direction = copy(direction), PrimarySide = primarySide, HandOffsets = handOffsets,
        StartAngles = starts, AlignTurn = turn, AlignFrames = align, SpinCount = count or 1,
        Duration = align + P.SpinFrames + ((count or 1) - 1) * 9}
end

updateSwordRenderer = function(cannon)
    if not alive(cannon) then return end
    local cd = cannon:GetData()
    local renderer = cd.MizukiSpiritSwordRenderer
    -- Retire the previous native connector when reloading this implementation.
    local oldLink = cd.MizukiSpiritSwordLinkLaser
    if alive(oldLink) and oldLink:GetData().MizukiSpiritSwordLink == true then oldLink:Remove() end
    cd.MizukiSpiritSwordLinkLaser = nil
    if not Mizuki.renderCannonSpiritSword(cannon) or cd.MizukiAwaitingInitialLayout then
        extraSwords.clear(cannon)
        if alive(renderer) and renderer:GetData().MizukiSpiritSwordRenderer == true then renderer:Remove() end
        local blade = cd.MizukiSpiritSwordBladeEntity
        if alive(blade) and blade:GetData().MizukiSpiritSwordBladeRole == true then blade:Remove() end
        local link = cd.MizukiSpiritSwordLinkEntity
        if alive(link) and link:GetData().MizukiSpiritSwordLinkRole == true
            and Mizuki.isSameEntity(link:GetData().Cannon, cannon) then link:Remove() end
        cd.MizukiSpiritSwordLinkEntity = nil
        cd.MizukiSpiritSwordBladeEntity = nil
        cd.MizukiSpiritSwordRenderer = nil
        return
    end
    -- XML definitions are not reloaded by Lua hot reload. Keep the existing
    -- player render pass until the registered renderer is actually available.
    if swordRendererVariant <= 0 then return end
    if not alive(renderer) then
        renderer = Isaac.Spawn(EntityType.ENTITY_EFFECT, swordRendererVariant, 0,
            copy(cannon.Player.Position), copy(cannon.Player.Velocity), cannon.Player):ToEffect()
        local rd = renderer:GetData()
        rd.MizukiSpiritSwordRenderer = true
        rd.Cannon, rd.CannonSeed = cannon, cannon.InitSeed
        renderer:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        renderer.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        renderer.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        cd.MizukiSpiritSwordRenderer = renderer
    end
    -- This entity is the actual visible hilt. The blade is independently drawn
    -- from its animated attachment point; it is not part of this sprite.
    local hiltSprite = renderer:GetSprite()
    if hiltSprite:GetFilename() ~= hiltArt then
        hiltSprite:Load(hiltArt, false)
        hiltSprite:ReplaceSpritesheet(0, "gfx/entities/mizuki/spirit_sword.png")
        hiltSprite:LoadGraphics()
    end
    renderer.Visible = true
    local player = cannon.Player
    local _, direction, angle, animation, frame, rotationOffset = swordVisualState(cannon)
    hiltSprite:SetFrame(animation, frame)
    hiltSprite.Rotation = direction:GetAngleDegrees() - 90 + rotationOffset
    hiltSprite.Scale = player.SpriteScale * Mizuki.CANNON_ART_SCALE_MULTIPLIER
    hiltSprite.Offset = Vector.Zero
    hiltSprite.FlipX, hiltSprite.FlipY = false, false
    renderer.Color = Color.Lerp(player.Color, player.Color, 0)
    hiltSprite.Color = renderer.Color
    renderer.Position = anchor(cannon, direction)
    renderer.PositionOffset = Vector.Zero
    -- The hand follows the player. Match its velocity as well as its position
    -- so native interpolation does not leave the visible hilt behind.
    renderer.Velocity = copy(player.Velocity)
    -- Include the horizontal boundary of the upper half-plane. Upward attacks
    -- stay behind the player for the entire stroke, regardless of blade angle.
    local behindPlayer = direction.Y < -0.00001 or math.sin(math.rad(angle)) <= 0.00001
    renderer.DepthOffset = player.Position.Y + player.DepthOffset - renderer.Position.Y
        + (behindPlayer and -1 or 1)
    updateSwordBlade(cannon, renderer)
    local state = cannon.Player:GetData().MizukiSpiritSwordInput
    extraSwords.update(cannon, renderer, cd.MizukiSpiritSwordAttack
        or state and state.PairedSpin and state.PairedSpin.Attack, anchor, Mizuki.getSpiritSwordBladeTransform)
end

local function swordBladeSprite(cannon)
    local cd = cannon:GetData()
    local sprite = cd.MizukiSpiritSwordBladeSprite
    if not sprite or cd.MizukiSpiritSwordBladeSpriteRevision ~= ART_REVISION then
        sprite = sprite or Sprite()
        sprite:Load(bladeArt, false)
        sprite:ReplaceSpritesheet(0, "gfx/entities/mizuki/mizuki_cannon.png")
        sprite:ReplaceSpritesheet(1, "gfx/entities/mizuki/mizuki_cannon_light.png")
        sprite:LoadGraphics()
        sprite:SetFrame("Idle", 0)
        cd.MizukiSpiritSwordBladeSprite = sprite
        cd.MizukiSpiritSwordBladeSpriteRevision = ART_REVISION
    end
    return sprite
end

local chargeFlash = {
    {0, 150 / 255, 0, 0}, {2, 1, 220 / 255, 0},
    {4, 1, 1, 150 / 255}, {6, 1, 220 / 255, 0}, {8, 150 / 255, 0, 0},
}
local function bladeColor(cannon)
    local color = Color.Lerp(cannon.Player.Color, cannon.Player.Color, 0)
    local fullFrames = cannon.Player:GetData().MizukiChargeBarFullFrames
    if not fullFrames then return color end
    -- Native ChargedRight's 9-frame tint/offset curve, applied directly to the
    -- visible body instead of relying on a newly loaded animation name.
    local frame = (fullFrames - 1) % 9
    local a, b = chargeFlash[5], chargeFlash[5]
    for i = 1, #chargeFlash - 1 do
        if frame < chargeFlash[i + 1][1] then a, b = chargeFlash[i], chargeFlash[i + 1]; break end
    end
    local t = a == b and 0 or (frame - a[1]) / (b[1] - a[1])
    local tint = a[2] + (b[2] - a[2]) * t
    color.R, color.G, color.B = color.R * tint, color.G * tint, color.B * tint
    color.RO = color.RO + a[3] + (b[3] - a[3]) * t
    color.GO = color.GO + a[4] + (b[4] - a[4]) * t
    return color
end

-- Native API cannot read individual layer transforms. These body-layer angles
-- match hiltArt. Read the HILT's displayed animation/frame and sprite transform,
-- rather than recomputing a second sword pose from player input.
function Mizuki.getSpiritSwordBladeTransform(hiltSprite, localOffset, angleOffset, spacingScale, rangeOffset)
    local angles = bladeAngles[hiltSprite:GetAnimation()]
    local bodyAngle = angles[math.min(#angles, hiltSprite:GetFrame() + 1)]
    local connection = P.HiltBladeConnection:Rotated(bodyAngle)
    local bladeRoot = (P.HiltBladeConnection + Vector(P.BladeGapPixels / Mizuki.CANNON_ART_SCALE_MULTIPLIER, 0)
        + (localOffset or Vector.Zero)):Rotated(bodyAngle)
    local scale = hiltSprite.Scale
    local offset = Vector(bladeRoot.X * scale.X, bladeRoot.Y * scale.Y):Rotated(hiltSprite.Rotation)
    local hiltEnd = Vector(connection.X * scale.X, connection.Y * scale.Y):Rotated(hiltSprite.Rotation)
    -- Nonuniform player scaling changes the hilt's displayed axis. Derive the
    -- blade angle from that transformed connection, not the unscaled track.
    if spacingScale then
        -- Only the gap grows with weapon size; the hilt and fixed cannon art
        -- keep their own scale. Remove the character-scaled gap first.
        local gap = Vector(P.BladeGapPixels / Mizuki.CANNON_ART_SCALE_MULTIPLIER, 0):Rotated(bodyAngle)
        gap = Vector(gap.X * scale.X, gap.Y * scale.Y):Rotated(hiltSprite.Rotation)
        offset = offset - gap + gap:Resized(P.BladeGapPixels * spacingScale)
    end
    offset = offset * Mizuki.getSpiritSwordRangeMultiplier(rangeOffset)
    local bladeRotation = hiltEnd:GetAngleDegrees() + 90 + (angleOffset or 0)
    return offset, bladeRotation, scale, hiltEnd
end

-- Rectangle edges, not opaque-pixel bounds. The native knife-body frame is
-- 32x16, center-pivoted and rotated 90 degrees inside its ANM2; the cannon's
-- 32x32 frame is bottom-pivoted. Replacement art has a centered frame.
function Mizuki.getSpiritSwordFrameTipOffset(scale, rotation, kind, frameSize, spriteOffset, direction)
    kind = kind or "cannon"
    local size = kind == "knife" and Vector(16, 32) or frameSize or Vector(32, 32)
    local center = kind == "cannon" and Vector(0, -size.Y * 0.5) or Vector.Zero
    -- Choose the rectangle's forward edge even when a native knife carries
    -- its own 180-degree art correction. Axis-aligned ties use the edge center.
    local localDirection = direction and direction:Rotated(-rotation) or Vector(0, -1)
    local function sign(value) return math.abs(value) < 0.00001 and 0 or value > 0 and 1 or -1 end
    local edge = center + Vector(size.X * 0.5 * sign(localDirection.X * scale.X),
        size.Y * 0.5 * sign(localDirection.Y * scale.Y))
    return Vector(edge.X * scale.X, edge.Y * scale.Y):Rotated(rotation) + (spriteOffset or Vector.Zero)
end

function Mizuki.getSpiritSwordCapsuleTip(capsules, direction)
    local best, projection
    for _, capsule in ipairs(capsules or {}) do
        for _, endpoint in ipairs({capsule.A, capsule.B}) do
            local point = endpoint + direction * capsule.Radius
            local value = point.X * direction.X + point.Y * direction.Y
            if not projection or value > projection then best, projection = point, value end
        end
    end
    return best
end

-- Use the same native Hit/Hit2 conversion as damage. Animation tails have no
-- active capsules; retain the last valid frame's reach until the pose changes.
function Mizuki.getSpiritSwordPoseTip(root, animation, frame, weaponScale, rotation, rangeOffset, direction)
    local poses = swordHitboxes.Frames[animation]
    if not poses then return nil end
    local reach = animation == "SpinRight" and swordHitboxes.SpinReachMultiplier
        or animation == "IdleRight" and swordHitboxes.ChargeReachMultiplier or 1
    local capsules
    repeat
        capsules = swordHitboxes.forFrame(root, animation, frame, Vector(weaponScale, weaponScale),
            rotation, reach, rangeOffset)
        frame = frame - 1
    until #capsules > 0 or frame < 0
    return Mizuki.getSpiritSwordCapsuleTip(capsules, direction)
end

function Mizuki.getSpiritSwordTipAlignedPosition(root, hiltSprite, weaponScale, rangeOffset, tipOffset)
    local _, rotation = Mizuki.getSpiritSwordBladeTransform(hiltSprite)
    local target = Mizuki.getSpiritSwordPoseTip(root, hiltSprite:GetAnimation(), hiltSprite:GetFrame(),
        weaponScale, hiltSprite.Rotation, rangeOffset, Vector.FromAngle(rotation - 90))
    return target and target - tipOffset / WORLD_TO_SCREEN_SCALE
end

function Mizuki.alignSpiritSwordBladeEntity(blade, root, hiltSprite, weaponScale, rangeOffset)
    local sprite, data = blade:GetSprite(), blade:GetData()
    local _, rotation = Mizuki.getSpiritSwordBladeTransform(hiltSprite)
    local tipOffset = Mizuki.getSpiritSwordFrameTipOffset(sprite.Scale, sprite.Rotation,
        data.MizukiSpiritSwordBladeArtKind, data.MizukiSpiritSwordBladeFrameSize, sprite.Offset,
        Vector.FromAngle(rotation - 90))
    local position = Mizuki.getSpiritSwordTipAlignedPosition(root, hiltSprite, weaponScale, rangeOffset, tipOffset)
    if position then blade.Position = position end
    return blade.Position
end

-- The held native knife and its Knife Piece 2 artwork use the same tip target
-- as the cannon body. Flying knives remain owned by their flight controller.
function Mizuki.getSpiritSwordMomKnifePosition(cannon)
    local rotation = cannon:GetData().MizukiCannonBodyRotation or 0
    local hilt = cannon:GetData().MizukiSpiritSwordRenderer
    if alive(hilt) then
        local knife = Mizuki.getCannonMomKnife(cannon)
        local scale = knife and knife.SpriteScale or Vector.One * Mizuki.getSpiritSwordBladeSpacingScale(cannon)
        -- updateSpiritSwordMomKnife assigns aim-90 to SpriteRotation, while
        -- cannon body rotation is aim+90. Use that desired pose, not last frame.
        local tipOffset = Mizuki.getSpiritSwordFrameTipOffset(scale, rotation - 180, "knife", nil, nil,
            Vector.FromAngle(rotation - 90))
        local position = Mizuki.getSpiritSwordTipAlignedPosition(
            hilt.Position, hilt:GetSprite(),
            Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon), tipOffset)
        if position then return position end
    end
    local offset = Vector(0, -P.BladeForwardPixels * Mizuki.getSpiritSwordBladeSpacingScale(cannon)):Rotated(rotation)
    return cannon.Position + offset * (1 / WORLD_TO_SCREEN_SCALE)
end

-- Attachment point along the blade: 0 is the hilt side, 1 is the tip.
-- Only the laser endpoint moves; entity poses and flight origins stay intact.
function Mizuki.getSpiritSwordLinkEnd(body)
    local offset = body:GetData().MizukiSpiritSwordBladeLinkOffset or Vector.Zero
    if body.Type == EntityType.ENTITY_KNIFE then
        -- The native 32px knife points down at sprite rotation zero.
        offset = Vector(0, 32 * (P.LinkBladeFraction - 0.5) * body.SpriteScale.Y)
            :Rotated(body.SpriteRotation)
    end
    return body.Position + body.PositionOffset + offset / WORLD_TO_SCREEN_SCALE
end

-- The ranged knife beam covers the whole hilt-to-blade span during flight.
-- There must be no second short bridge alongside that real attack beam.
function Mizuki.getSpiritSwordLinkTarget(cannon, body)
    return Mizuki.getSpiritSwordLinkEnd(body), body.Type ~= EntityType.ENTITY_KNIFE or not body:IsFlying()
end

function Mizuki.getSpiritSwordKnifeBeamOrigin(cannon)
    if not alive(cannon) or not Mizuki.renderCannonSpiritSword(cannon) then return nil end
    local hilt = cannon:GetData().MizukiSpiritSwordRenderer
    if not alive(hilt) then return nil end
    local hd = hilt:GetData()
    if hd.MizukiSpiritSwordRenderer ~= true or not alive(hd.Cannon, hd.CannonSeed)
        or not Mizuki.isSameEntity(hd.Cannon, cannon) then return nil end
    local _, _, _, offset = Mizuki.getSpiritSwordBladeTransform(hilt:GetSprite())
    return hilt.Position + offset / WORLD_TO_SCREEN_SCALE
end

function Mizuki.releaseSpiritSwordHeldLink(cannon)
    if not alive(cannon) or cannon.Type ~= EntityType.ENTITY_FAMILIAR
        or cannon.Variant ~= Mizuki.CannonVariant then return end
    local cd = cannon:GetData()
    local link = cd.MizukiSpiritSwordLinkEntity
    if alive(link) and link:GetData().MizukiSpiritSwordLinkRole == true
        and Mizuki.isSameEntity(link:GetData().Cannon, cannon) then
        link:Remove()
        cd.MizukiSpiritSwordLinkEntity = nil
    end
end

local function spiritSwordLinkNativeAdvance(laser)
    -- Native sample setup (0x97405c..0x9740e3) starts at the forward
    -- boundary of layer 0, then applies MaxDistance from that point.
    -- Thin technology's native tip frame has YPosition=0, Height=16.
    -- Keep this scoped to the variant verified by the endpoint trace.
    if laser.Variant == LaserVariant.THIN_RED and laser.Size > 1 then
        return 16 * laser.SpriteScale.Y
    end
    return 0
end

-- Keep the connector as a real player-fired laser, including its native tip.
-- The independent attack rays remain on their existing multi-shot path.
function Mizuki.updateSpiritSwordLinkEntity(cannon, hilt, body, entity, startPosition, endPosition, visible)
    local delta = endPosition - startPosition
    local length = delta:Length()
    if alive(entity) then
        local data = entity:GetData()
        if data.MizukiSpiritSwordLinkRole ~= true or not Mizuki.isSameEntity(data.Cannon, cannon)
            or not Mizuki.isSameEntity(data.Hilt, hilt) then entity = nil end
    end
    if visible == false or length <= 0.001 then
        if alive(entity) and entity:GetData().MizukiSpiritSwordLinkRole == true then entity:Remove() end
        return nil -- SetMaxDistance(0) means unlimited, never a hidden short link.
    end
    -- Lua reload can leave the previous purely visual effect in the slot.
    if alive(entity) and entity.Type ~= EntityType.ENTITY_LASER
        and entity:GetData().MizukiSpiritSwordLinkRole == true then entity:Remove(); entity = nil end
    local hiltDepth = hilt.Position.Y + hilt.DepthOffset
    local bodyDepth = body.Position.Y + body.DepthOffset
    local hitboxOffset = Vector(0, Mizuki.WeaponParameters.BeamHitboxYOffset)
    local depth = math.min(hiltDepth, bodyDepth) - startPosition.Y - hitboxOffset.Y - 0.1
    local direction = delta:Resized(1)
    if not alive(entity) then
        entity = Mizuki.createCannonBeam(cannon.Player, {
            Origin = startPosition + hitboxOffset, Direction = direction, LeftEye = cannon.SubType == 1,
            DamageMultiplier = 1, WidthScale = 1, PositionOffset = -hitboxOffset,
            DepthOffset = depth, ActiveDuration = 2, Distance = length, Automatic = false,
        })
        local data = entity:GetData()
        data.MizukiSpiritSwordLinkRole = true
        data.Cannon, data.CannonSeed = cannon, cannon.InitSeed
        data.Hilt, data.HiltSeed = hilt, hilt.InitSeed
    end
    local data = entity:GetData()
    entity.SubType = 0 -- Ordinary linear laser; also restores surviving links after Lua reload.
    data.Body, data.BodySeed = body, body.InitSeed
    entity.DisableFollowParent = true
    -- Keep the cap at the established hilt endpoint. Retreating it behind
    -- the hilt exposes it above the hilt's native render pass.
    entity.Position = startPosition + hitboxOffset
    entity.PositionOffset = -hitboxOffset
    -- Creation applies this already, but the attached pose above replaces
    -- both coordinates every update. Reapply from that base, never accumulate.
    Mizuki.applyBeamReflectionHeight(cannon.Player, entity)
    entity.Velocity = copy(hilt.Velocity)
    entity.AngleDegrees = direction:GetAngleDegrees()
    entity:SetMaxDistance(math.max(0.001, length - spiritSwordLinkNativeAdvance(entity)))
    entity.DepthOffset = math.min(hiltDepth, bodyDepth) - entity.Position.Y - 0.1
    entity.Timeout = 2
    -- Every owned short connector shares its hilt's depth pass. Flying
    -- attack beams have a separate identity and never enter this path.
    data.MizukiSpiritSwordLinkDepthRender = true
    if data.MizukiSpiritSwordLinkRole == true then entity.Visible = false end
    return entity
end

function Mizuki.renderSpiritSwordLink(cannon, hilt, link, renderOffset)
    if not alive(link) then return end
    local data = link:GetData()
    if data.MizukiSpiritSwordLinkRole ~= true or data.MizukiSpiritSwordLinkDepthRender ~= true
        or data.MizukiSpiritSwordLinkRenderActive == true
        or not alive(data.Cannon, data.CannonSeed) or not Mizuki.isSameEntity(data.Cannon, cannon)
        or not alive(data.Hilt, data.HiltSeed) or not Mizuki.isSameEntity(data.Hilt, hilt)
        or not alive(data.Body, data.BodySeed) then return end
    if data.MizukiSpiritSwordExtraVisual == true then
        local entry = data.Entry
        if not entry or not entry.Attack or entry.Attack.Finished
            or not Mizuki.isSameEntity(entry.Link, link)
            or not Mizuki.isSameEntity(entry.Hilt, hilt)
            or not Mizuki.isSameEntity(entry.Blade, data.Body) then return end
    elseif not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordLinkEntity, link)
        or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordRenderer, hilt) then return end
    local visible = link.Visible
    data.MizukiSpiritSwordLinkRenderActive = true
    link.Visible = true
    -- Render the real laser (native samples, animation and caps), never a
    -- Sprite approximation. No entity Update or damage dispatch occurs here.
    local ok, err = pcall(link.Render, link, renderOffset)
    link.Visible = visible
    data.MizukiSpiritSwordLinkRenderActive = nil
    if not ok then error(err, 0) end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, function(_, laser)
    local data = laser:GetData()
    if data.MizukiSpiritSwordLinkRole ~= true then return end
    local cannon, hilt, body = data.Cannon, data.Hilt, data.Body
    local owned = alive(cannon, data.CannonSeed) and alive(hilt, data.HiltSeed)
        and alive(body, data.BodySeed) and Mizuki.renderCannonSpiritSword(cannon)
    if owned then
        if data.MizukiSpiritSwordExtraVisual == true then
            owned = data.Entry and data.Entry.Attack and not data.Entry.Attack.Finished
                and Mizuki.isSameEntity(data.Entry.Link, laser)
        else
            owned = Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordLinkEntity, laser)
        end
    end
    if not owned then laser:Remove(); return end
    local _, _, _, hiltEnd = Mizuki.getSpiritSwordBladeTransform(hilt:GetSprite())
    local startPosition = hilt.Position + hiltEnd * (1 / WORLD_TO_SCREEN_SCALE)
    local endPosition, visible = Mizuki.getSpiritSwordLinkTarget(cannon, body)
    Mizuki.updateSpiritSwordLinkEntity(cannon, hilt, body, laser, startPosition, endPosition, visible)
end)

-- The final pass only handles the ordinary cannon returning to idle.
-- Active sword bodies are drawn with their own depth-sorted hilts.
function Mizuki.renderSpiritSwordBodies(cannon)
    if not alive(cannon) or cannon.Type ~= EntityType.ENTITY_FAMILIAR
        or cannon.Variant ~= Mizuki.CannonVariant then return end
    local cd = cannon:GetData()
    if cd.MizukiSpiritSwordShadowReturning == true then
        -- Visible=false keeps the native shadow out. Reuse the ordinary cannon
        -- redraw here; compensate its native-pass coordinate conversion once.
        local game = Game()
        Mizuki:RenderCannon(cannon, game:GetRoom():GetRenderScrollOffset() + game.ScreenShakeOffset, false, true)
        return
    end
end

function Mizuki.renderSpiritSwordBladeBody(cannon, body, renderOffset, extraEntry)
    local cd = cannon:GetData()
    if not alive(body) or not body.Visible then return end
    local bd = body:GetData()
    if not alive(bd.Cannon, bd.CannonSeed) or not Mizuki.isSameEntity(bd.Cannon, cannon) then return end
    if bd.MizukiSpiritSwordEchoBladeRole == true then
        if not extraEntry or bd.Entry ~= extraEntry or not Mizuki.isSameEntity(extraEntry.Body, body)
            or not Mizuki.isSameEntity(bd.Ghost, cannon) or not alive(bd.Ghost, bd.GhostSeed) then return end
    elseif extraEntry then
        if bd.MizukiSpiritSwordExtraVisual ~= true or bd.Role ~= "Blade"
            or bd.Entry ~= extraEntry or not extraEntry.Attack or extraEntry.Attack.Finished
            or not alive(extraEntry.Hilt) or not Mizuki.isSameEntity(extraEntry.Blade, body) then return end
    elseif bd.MizukiSpiritSwordBladeRole ~= true or bd.MizukiSpiritSwordBladeUsesKnife == true
        or not alive(bd.Hilt, bd.HiltSeed)
        or not Mizuki.isSameEntity(cd.MizukiSpiritSwordBladeEntity, body) then return end
    if not bd.MizukiSpiritSwordBladeDrawColor then return end
    local sprite = body:GetSprite()
    local hidden = sprite.Color
    sprite.Color = bd.MizukiSpiritSwordBladeDrawColor
    local game = Game()
    local screen = Isaac.WorldToScreen(body.Position + body.PositionOffset) + renderOffset
        - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset
    for layer = 0, sprite:GetLayerCount() - 1 do
        sprite:RenderLayer(layer, screen, Vector.Zero, Vector.Zero)
    end
    sprite.Color = hidden
end

-- Temporary read-only endpoint evidence. The requested range alone does not
-- establish where native sampling or its tip artwork actually renders.

-- Configure the native blade entity from the cannon's shared appearance.
-- Replacement art uses the same 1x scale and selection rules as ordinary fire.
-- Only the sword's visible body changes. The real knife retains its native
-- sprite/animation and collision data, including after returning to idle.
function Mizuki.getSpiritSwordMomKnifeSprite(knife, cannon)
    local data = knife:GetData()
    if knife.Variant ~= 0 or data.MizukiBerserkClub == true
        or (data.MizukiCannonKnife ~= true and data.MizukiEchoKnife ~= true) then return nil end
    local beam = data.MizukiCannonKnifeBeam
    local child = data.MizukiEchoKnife == true and data.MizukiEchoChild
    if data.MizukiMultidimensionalKnife == true then
        local source = data.MizukiCannonKnifeMotionSource
        if alive(source, data.MizukiCannonKnifeMotionSourceInitSeed) then
            local sd = source:GetData()
            beam = sd.MizukiCannonKnifeBeam
            child = sd.MizukiEchoKnife == true and sd.MizukiEchoChild
        end
    end
    if not (data.MizukiCannonKnife == true and cannon and cannon:Exists()
            and Mizuki.renderCannonSpiritSword(cannon))
        and not (beam and beam.SpiritSwordDriven == true and knife:IsFlying())
        and not (child and child.SpiritSwordKnifeFromHilt == true) then return nil end
    local sprite = data.MizukiSpiritSwordKnifeBodySprite
    if not sprite or data.MizukiSpiritSwordKnifeBodyTextureBound ~= true then
        sprite = sprite or Sprite()
        -- This ANM2 lives below gfx/entities/mizuki, unlike the original
        -- Knife Piece 2 ANM2 at gfx/. Bind the native atlas explicitly.
        sprite:Load(knifeBladeArt, false)
        sprite:ReplaceSpritesheet(0, "gfx/familiar/familiar_knifepieces.png")
        sprite:LoadGraphics()
        data.MizukiSpiritSwordKnifeBodySprite = sprite
        data.MizukiSpiritSwordKnifeBodyTextureBound = true
    end
    sprite:SetFrame("Idle", 0)
    return sprite
end

-- Copy only visual parameters; echo bodies never query the current inventory.
function Mizuki.snapshotSpiritSwordBladeVisual(cannon)
    local knife = Mizuki.getCannonMomKnife(cannon)
    local hiltScale = copy(cannon.Player.SpriteScale * Mizuki.CANNON_ART_SCALE_MULTIPLIER)
    local spacingScale = Mizuki.getSpiritSwordBladeSpacingScale(cannon)
    if knife or cannon.Player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
        return {Kind = "knife", HiltScale = hiltScale, SpacingScale = spacingScale,
            ForwardPixels = P.BladeForwardPixels * spacingScale, Scale = copy(knife and knife.SpriteScale
            or cannon.Player.SpriteScale * Mizuki.CANNON_ART_SCALE_MULTIPLIER),
            RotationOffset = knife and (knife.SpriteRotation - (cannon:GetData().MizukiCannonBodyRotation or knife.SpriteRotation)) or 0}
    end
    local definition, frame
    definition, frame = Mizuki.getCannonAttackAppearanceDefinition(cannon)
    if definition then
        return {Kind = "appearance", HiltScale = hiltScale, SpacingScale = spacingScale, Id = definition.Id, Anm2 = definition.Anm2,
            Animation = definition.Animation, Scale = definition.Scale, Frame = frame or 0,
            SwordFrameSize = definition.SwordFrameSize}
    end
    return {Kind = "cannon", HiltScale = hiltScale, SpacingScale = spacingScale}
end

function Mizuki.configureSpiritSwordBladeAppearance(cannon, blade, scale, rotation, color, visual)
    local sprite, data = blade:GetSprite(), blade:GetData()
    local knife = not visual and Mizuki.getCannonMomKnife(cannon)
    local definition, appearanceFrame
    if visual and visual.Kind == "appearance" then definition, appearanceFrame = visual, visual.Frame
    elseif not visual and not knife and Mizuki.getCannonAttackAppearanceDefinition then
        definition, appearanceFrame = Mizuki.getCannonAttackAppearanceDefinition(cannon)
    end
    if visual and visual.Kind == "knife" then
        if sprite:GetFilename() ~= knifeBladeArt then
            sprite:Load(knifeBladeArt, false)
            sprite:ReplaceSpritesheet(0, "gfx/familiar/familiar_knifepieces.png")
            sprite:LoadGraphics()
        end
        sprite:SetFrame("Idle", 0)
        sprite.Scale, sprite.Offset = copy(visual.Scale), Vector.Zero
        rotation = rotation + visual.RotationOffset
    elseif knife then
        local source = Mizuki.getSpiritSwordMomKnifeSprite(knife, cannon) or knife:GetSprite()
        if sprite:GetFilename() ~= source:GetFilename() then sprite:Load(source:GetFilename(), true) end
        sprite:SetFrame(source:GetAnimation(), source:GetFrame())
        sprite.Scale, sprite.Offset = knife.SpriteScale, Vector.Zero
        rotation = knife.SpriteRotation + rotation - (cannon:GetData().MizukiCannonBodyRotation or rotation)
        color = Color.Lerp(knife:GetData().MizukiCannonKnifeDrawColor or knife.Color,
            knife:GetData().MizukiCannonKnifeDrawColor or knife.Color, 0)
    elseif definition then
        if sprite:GetFilename() ~= definition.Anm2 or sprite:GetAnimation() ~= definition.Animation then
            sprite:Load(definition.Anm2, true)
            sprite:Play(definition.Animation, true)
        end
        sprite:SetFrame(definition.Animation, appearanceFrame or 0)
        sprite.Scale = scale * ((definition.Scale or 1) / Mizuki.CANNON_ART_SCALE_MULTIPLIER)
        -- Tear replacement art is center-pivoted; the cannon blade is bottom-pivoted.
        sprite.Offset = Vector(0, -P.BladeForwardPixels * scale.Y):Rotated(rotation)
    else
        if sprite:GetFilename() ~= bladeArt or data.MizukiSpiritSwordBladeArtRevision ~= ART_REVISION then
            sprite:Load(bladeArt, false)
            sprite:ReplaceSpritesheet(0, "gfx/entities/mizuki/mizuki_cannon.png")
            sprite:ReplaceSpritesheet(1, "gfx/entities/mizuki/mizuki_cannon_light.png")
            sprite:LoadGraphics()
            data.MizukiSpiritSwordBladeArtRevision = ART_REVISION
        end
        sprite:SetFrame("Idle", 0)
        sprite.Scale, sprite.Offset = scale, Vector.Zero
    end
    sprite.Rotation, sprite.Color = rotation, color
    sprite.FlipX, sprite.FlipY = false, false
    local knifeArt = knife or visual and visual.Kind == "knife"
    data.MizukiSpiritSwordBladeArtKind = knifeArt and "knife" or definition and "appearance" or "cannon"
    data.MizukiSpiritSwordBladeFrameSize = definition and definition.SwordFrameSize or nil
    local centerOffset = knifeArt and Vector.Zero
        or Vector(0, -P.BladeForwardPixels * scale.Y):Rotated(rotation)
    local backwardShift = 32 * (P.LinkBladeFraction - 0.5)
    local localOffset = knifeArt and Vector(0, backwardShift * sprite.Scale.Y)
        or Vector(0, -backwardShift * scale.Y)
    data.MizukiSpiritSwordBladeLinkOffset = centerOffset + localOffset:Rotated(rotation)
    -- Keep the real moving entity, but draw its sprite once with its hilt.
    -- Duplicate passes compound translucent body/light art.
    if data.MizukiSpiritSwordBladeRole == true
        or data.MizukiSpiritSwordEchoBladeRole == true
        or (data.MizukiSpiritSwordExtraVisual == true and data.Role == "Blade") then
        data.MizukiSpiritSwordBladeDrawColor = Color.Lerp(color, color, 0)
        local hidden = Color.Lerp(color, color, 0)
        hidden.A = 0
        blade.Color, sprite.Color = hidden, hidden
    else
        blade.Color = color
    end
end

updateSwordBlade = function(cannon, hilt)
    local cd = cannon:GetData()
    local offset, rotation, scale = Mizuki.getSpiritSwordBladeTransform(hilt:GetSprite(),
        cd.MizukiSpiritSwordBladeLocalOffset, cd.MizukiSpiritSwordBladeAngleOffset,
        Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
    local position = hilt.Position + offset * (1 / WORLD_TO_SCREEN_SCALE)
    local blade = cd.MizukiSpiritSwordBladeEntity
    if not alive(blade) then
        blade = Isaac.Spawn(EntityType.ENTITY_EFFECT, swordRendererVariant, 0,
            position, copy(hilt.Velocity), cannon.Player):ToEffect()
        local bd = blade:GetData()
        bd.MizukiSpiritSwordBladeRole = true
        bd.Cannon, bd.CannonSeed = cannon, cannon.InitSeed
        bd.Hilt, bd.HiltSeed = hilt, hilt.InitSeed
        blade:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
        blade.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        blade.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        cd.MizukiSpiritSwordBladeEntity = blade
    end
    blade.Position, blade.PositionOffset = position, Vector.Zero
    blade.Velocity = copy(hilt.Velocity)
    blade.Visible = true
    Mizuki.configureSpiritSwordBladeAppearance(cannon, blade, scale, rotation, bladeColor(cannon))
    position = Mizuki.alignSpiritSwordBladeEntity(blade,
        hilt.Position, hilt:GetSprite(),
        Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
    local attack = cd.MizukiSpiritSwordAttack
    blade.DepthOffset = hilt.Position.Y + hilt.DepthOffset - position.Y + 0.1
    local knife
    -- The artwork entity keeps its native pivot. The registered cannon owns
    -- the visible body's CENTER, shared by firing and charge indicators.
    -- Echoes and secondary visual swords are not registered cannon bodies.
    if cannon.Type == EntityType.ENTITY_FAMILIAR and cannon.Variant == Mizuki.CannonVariant
        and Mizuki.renderCannonSpiritSword(cannon) then
        cd.MizukiCannonAim = Vector.FromAngle(rotation - 90)
        cd.MizukiCannonBodyRotation = rotation
        cannon.Velocity = copy(blade.Velocity)
        -- Resolve the real native knife before publishing the center: a newly
        -- created knife can have a different base scale than the fallback art.
        knife = Mizuki.updateSpiritSwordMomKnife(cannon)
        local bodyPosition
        if cannon.Player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE) then
            -- Resolve the held pose, even while an earlier knife is flying.
            bodyPosition = alive(knife) and not knife:IsFlying() and (knife.Position + knife.PositionOffset)
                or Mizuki.getSpiritSwordMomKnifePosition(cannon)
        else
            local sprite = blade:GetSprite()
            local center = blade:GetData().MizukiSpiritSwordBladeArtKind == "cannon"
                and Vector(0, -16 * sprite.Scale.Y):Rotated(sprite.Rotation) or Vector.Zero
            bodyPosition = position + (center + sprite.Offset) / WORLD_TO_SCREEN_SCALE
        end
        cannon.Position, cannon.PositionOffset = copy(bodyPosition), Vector.Zero
        cannon.Velocity = copy(blade.Velocity)
        cannon.DepthOffset = position.Y + blade.DepthOffset - bodyPosition.Y
        if alive(knife) and not knife:IsFlying() then knife.DepthOffset = cannon.DepthOffset end
        cd.MizukiDesiredPosition = copy(bodyPosition)
        cd.MizukiPoseOffset = bodyPosition - cannon.Player.Position
        cd.MizukiPivotRenderOffset = Vector.Zero
        cd.MizukiBasePivotRenderOffset = Vector.Zero
        local data = cannon.Player:GetData()
        local positions = data.MizukiCannonPositions and data.MizukiCannonPositions[cannon.SubType]
        if positions then
            for member, candidate in ipairs(data.MizukiCannons[cannon.SubType] or {}) do
                if Mizuki.isSameEntity(candidate, cannon) then positions[member] = copy(bodyPosition); break end
            end
        end
        for _, beam in ipairs((data.MizukiActiveBeams or {})[cannon.SubType] or {}) do
            if beam.Cannon and Mizuki.isSameEntity(beam.Cannon, cannon) then Mizuki.syncSpiritSwordBeam(beam) end
        end
    end
    knife = knife or Mizuki.updateSpiritSwordMomKnife(cannon)
    if attack and not attack.Echo then attack.BladeVisual = Mizuki.snapshotSpiritSwordBladeVisual(cannon) end
    -- This independently identified effect is only the floating cannon body.
    -- The real knife supplies the sword body AND leaves the hand on launch.
    blade:GetData().MizukiSpiritSwordBladeUsesKnife = knife ~= nil
    if blade:GetData().MizukiSpiritSwordBladeRole == true then blade.Visible = knife == nil end
    local _, _, _, hiltEnd = Mizuki.getSpiritSwordBladeTransform(hilt:GetSprite())
    local startPosition = hilt.Position + hiltEnd * (1 / WORLD_TO_SCREEN_SCALE)
    local endPosition, visible = Mizuki.getSpiritSwordLinkTarget(cannon, knife or blade)
    cd.MizukiSpiritSwordLinkEntity = Mizuki.updateSpiritSwordLinkEntity(cannon, hilt, knife or blade,
        cd.MizukiSpiritSwordLinkEntity, startPosition, endPosition, visible)
    cd.MizukiSpiritSwordLinkSprite = nil -- release the superseded manual-draw cache
end

function Mizuki.updateSpiritSwordCannonPose(cannon)
    if not alive(cannon) or cannon.Type ~= EntityType.ENTITY_FAMILIAR
        or cannon.Variant ~= Mizuki.CannonVariant or not Mizuki.renderCannonSpiritSword(cannon) then return end
    -- Reapply after the familiar's generic follower update as well as the
    -- player/effect updates; those paths must not pull it back to idle layout.
    updateSwordRenderer(cannon)
end

local function renderSwordLink(cannon, startPosition, endPosition, color, widthScale)
    local delta = endPosition - startPosition
    local length = delta:Length()
    if length <= 0 then return end
    local cd = cannon:GetData()
    local sprite = cd.MizukiSpiritSwordLinkSprite
    if not sprite or sprite:GetFilename() ~= linkArt then
        sprite = sprite or Sprite()
        sprite:Load(linkArt, false)
        sprite:ReplaceSpritesheet(0, "gfx/Effects/Effect_018_TechnologyLaser.png")
        sprite:LoadGraphics()
        cd.MizukiSpiritSwordLinkSprite = sprite
    end
    -- The resource contains only an 8px section of the native laser body.
    -- No laser entity, impact entity or tip animation is involved.
    sprite:SetFrame("Idle", Game():GetFrameCount() % 3)
    sprite.Scale = Vector(math.abs(widthScale), length / 8)
    sprite.Rotation = delta:GetAngleDegrees() - 90
    sprite.Color, sprite.Offset = color, Vector.Zero
    sprite:RenderLayer(0, startPosition, Vector.Zero, Vector.Zero)
end

local function renderSwordAttachments(cannon, renderOffset, hilt)
    local player, game = cannon.Player, Game()
    local attack, direction, _, animation, frame, rotationOffset = swordVisualState(cannon)
    local root = hilt and hilt.Position or anchor(cannon, direction)
    local screen = Isaac.WorldToScreen(root) + renderOffset
        - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset
    local scale = player.SpriteScale * Mizuki.CANNON_ART_SCALE_MULTIPLIER
    local color = Color.Lerp(player.Color, player.Color, 0)
    local hiltSprite = hilt and hilt:GetSprite()
    if not hiltSprite then
        -- Lua reload before XML registration: keep the hilt visible without
        -- spawning an invalid effect. This fallback still draws only the hilt.
        local cd = cannon:GetData()
        hiltSprite = cd.MizukiSpiritSwordHiltSprite
        if not hiltSprite then
            hiltSprite = Sprite()
            hiltSprite:Load(hiltArt, true)
            cd.MizukiSpiritSwordHiltSprite = hiltSprite
        end
        hiltSprite:SetFrame(animation, frame)
        hiltSprite.Scale, hiltSprite.Color = scale, color
        hiltSprite.Rotation = direction:GetAngleDegrees() - 90 + rotationOffset
        hiltSprite:RenderLayer(0, screen, Vector.Zero, Vector.Zero)
    end
    -- The slash arc is a separate draw at character scale, never a blade layer.
    local pair = player:GetData().MizukiSpiritSwordInput.PairedSpin
    if attack or (pair and Game():GetFrameCount() >= pair.Frame + pair.AlignFrames) then
        local arc = bladeSprite(cannon)
        arc:SetFrame(hiltSprite:GetAnimation(), hiltSprite:GetFrame())
        arc.Scale, arc.Color, arc.Offset = player.SpriteScale, color, Vector.Zero
        arc.Rotation = hiltSprite.Rotation
        local arcPosition = screen + Mizuki.getSpiritSwordRangeDisplacement(hiltSprite:GetAnimation(),
            hiltSprite:GetFrame(), hiltSprite.Scale, hiltSprite.Rotation,
            Mizuki.getSpiritSwordBladeRangeOffset(cannon), Mizuki.getSpiritSwordBladeSpacingScale(cannon)) * WORLD_TO_SCREEN_SCALE
        arc:RenderLayer(1, arcPosition, Vector.Zero, Vector.Zero)
        arc:RenderLayer(2, arcPosition, Vector.Zero, Vector.Zero)
    end
    local cd = cannon:GetData()
    local offset, rotation, bladeScale, hiltEnd = Mizuki.getSpiritSwordBladeTransform(hiltSprite,
        cd.MizukiSpiritSwordBladeLocalOffset, cd.MizukiSpiritSwordBladeAngleOffset,
        Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
    local body = hilt and cd.MizukiSpiritSwordBladeEntity
    local bodyScreen = alive(body) and (Isaac.WorldToScreen(body.Position) + renderOffset
        - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset) or screen + offset
    local linkColor = Color.Lerp(player.LaserColor, player.LaserColor, 0)
    linkColor.A = linkColor.A * color.A
    local knife = (not body or body:GetData().MizukiSpiritSwordBladeUsesKnife == true)
        and Mizuki.getCannonMomKnife(cannon)
    if knife then
        -- The hilt's native depth already implements the shared upper/lower
        -- half-plane rule. Held real knives must render here, not POST_RENDER.
        -- Flying knives retain their existing final-room draw after the beam.
        if hilt then Mizuki.renderSpiritSwordLink(cannon, hilt, cd.MizukiSpiritSwordLinkEntity, renderOffset) end
        local drawn = Mizuki.renderSpiritSwordHeldKnifeBody
            and Mizuki.renderSpiritSwordHeldKnifeBody(cannon, renderOffset)
        if not drawn then Mizuki.renderCannonMomKnifeBody(cannon, renderOffset) end
        if not hilt and not knife:IsFlying() then
            local knifeScreen = Isaac.WorldToScreen(knife.Position + knife.PositionOffset) + renderOffset
                - game:GetRoom():GetRenderScrollOffset() - game.ScreenShakeOffset
            renderSwordLink(cannon, screen + hiltEnd, knifeScreen, linkColor, player.SpriteScale.X)
        end
        if hilt then Mizuki:RenderChargeBar(cannon, renderOffset, true) end
    else
        if not hilt then renderSwordLink(cannon, screen + hiltEnd, bodyScreen, linkColor, player.SpriteScale.X) end
        Mizuki.renderDeadEyeGlow(cannon, bodyScreen, bladeScale, color.A, nil, rotation - 90)
        if hilt then
            Mizuki.renderSpiritSwordLink(cannon, hilt, cd.MizukiSpiritSwordLinkEntity, renderOffset)
            Mizuki.renderSpiritSwordBladeBody(cannon, body, renderOffset)
        end
    end
    if not hilt and not knife then
        -- The pre-registration fallback also keeps the blade separate.
        local blade = swordBladeSprite(cannon)
        blade.Scale, blade.Color, blade.Offset = bladeScale, bladeColor(cannon), Vector.Zero
        blade.Rotation = rotation
        blade.FlipX, blade.FlipY = false, false
        blade:RenderLayer(0, bodyScreen, Vector.Zero, Vector.Zero)
        blade:RenderLayer(1, bodyScreen, Vector.Zero, Vector.Zero)
    end
    if attack then Mizuki.renderSpecialBrimstoneIcon(attack.Hitbox, root, renderOffset, color.A, screen) end
end

function Mizuki.getSpiritSwordChargeBarAnchor(cannon)
    if not Mizuki.renderCannonSpiritSword(cannon) then return nil end
    local cd = cannon:GetData()
    local blade = cd.MizukiSpiritSwordBladeEntity
    if alive(blade) and blade:GetData().MizukiSpiritSwordBladeRole == true
        and Mizuki.isSameEntity(blade:GetData().Cannon, cannon) then
        return cannon.Position, cd.MizukiCannonBodyRotation or blade:GetSprite().Rotation
    end
    -- Same attachment transform as the pre-registration visual fallback.
    local _, direction, _, animation, frame, rotation = swordVisualState(cannon)
    local hiltSprite = cd.MizukiSpiritSwordHiltSprite
    if not hiltSprite then return nil end
    hiltSprite:SetFrame(animation, frame)
    hiltSprite.Scale = cannon.Player.SpriteScale * Mizuki.CANNON_ART_SCALE_MULTIPLIER
    hiltSprite.Rotation = direction:GetAngleDegrees() - 90 + rotation
    local offset, angle, scale = Mizuki.getSpiritSwordBladeTransform(hiltSprite,
        cd.MizukiSpiritSwordBladeLocalOffset, cd.MizukiSpiritSwordBladeAngleOffset,
        Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon))
    local center = Vector(0, -16 * scale.Y):Rotated(angle)
    local tipOffset = Mizuki.getSpiritSwordFrameTipOffset(scale, angle, "cannon", nil, nil,
        Vector.FromAngle(angle - 90))
    local position = Mizuki.getSpiritSwordTipAlignedPosition(anchor(cannon, direction), hiltSprite,
        Mizuki.getSpiritSwordBladeSpacingScale(cannon), Mizuki.getSpiritSwordBladeRangeOffset(cannon), tipOffset)
    return (position or anchor(cannon, direction) + offset / WORLD_TO_SCREEN_SCALE)
        + center / WORLD_TO_SCREEN_SCALE, angle
end

if swordRendererVariant > 0 then
Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, function(_, renderer)
    if extraSwords.updateEntity(renderer) then return end
    local rd = renderer:GetData()
    if rd.MizukiSpiritSwordEchoBladeRole == true then
        if not alive(rd.Ghost, rd.GhostSeed) or not rd.Entry
            or not Mizuki.isSameEntity(rd.Entry.Body, renderer)
            or not rd.Ghost:GetData().MizukiSpiritSwordEchoSource then renderer:Remove() end
        return
    end
    if rd.MizukiSpiritSwordWaveBodyRole == true then
        -- Retire only the old explicit visual role after a Lua reload. The
        -- actual projectile now renders the entire composite itself.
        local wave = rd.Wave
        if alive(wave, rd.WaveSeed) and Mizuki.isSameEntity(wave:GetData().MizukiSpiritSwordWaveBodyEntity, renderer) then
            wave:GetData().MizukiSpiritSwordWaveBodyEntity, wave:GetData().MizukiSpiritSwordWaveBodySeed = nil, nil
        end
        renderer:Remove()
        return
    end
    if rd.MizukiSpiritSwordLinkRole == true then
        local cannon, hilt = rd.Cannon, rd.Hilt
        if not alive(cannon, rd.CannonSeed) or not alive(hilt, rd.HiltSeed)
            or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordLinkEntity, renderer)
            or not Mizuki.renderCannonSpiritSword(cannon) then
            renderer:Remove()
        else
            updateSwordRenderer(cannon)
        end
        return
    end
    if rd.MizukiSpiritSwordBladeRole == true then
        local cannon, hilt = rd.Cannon, rd.Hilt
        if not alive(cannon, rd.CannonSeed) or not alive(hilt, rd.HiltSeed)
            or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordBladeEntity, renderer)
            or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordRenderer, hilt)
            or not Mizuki.renderCannonSpiritSword(cannon) then
            renderer:Remove()
            return
        end
        updateSwordBlade(cannon, hilt)
        return
    end
    if rd.MizukiSpiritSwordRenderer ~= true then return end
    local cannon = rd.Cannon
    if not alive(cannon, rd.CannonSeed) or not alive(cannon.Player)
        or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordRenderer, renderer) then
        renderer:Remove()
        return
    end
    updateSwordRenderer(cannon)
end, swordRendererVariant)

Mizuki:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, function(_, renderer, renderOffset)
    if extraSwords.render(renderer, renderOffset, Mizuki.getSpiritSwordBladeTransform) then return end
    local rd = renderer:GetData()
    if rd.MizukiSpiritSwordLinkRole == true or rd.MizukiSpiritSwordEchoBladeRole == true then return end
    if rd.MizukiSpiritSwordBladeRole == true then
        local cannon, hilt = rd.Cannon, rd.Hilt
        if alive(cannon, rd.CannonSeed) and alive(hilt, rd.HiltSeed)
            and Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordBladeEntity, renderer)
            and Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordRenderer, hilt)
            and Mizuki.renderCannonSpiritSword(cannon) then
            Mizuki:RenderChargeBar(cannon, renderOffset, true)
        end
        return
    end
    if rd.MizukiSpiritSwordRenderer ~= true then return end
    local cannon = rd.Cannon
    if not alive(cannon, rd.CannonSeed) or not alive(cannon.Player)
        or not Mizuki.isSameEntity(cannon:GetData().MizukiSpiritSwordRenderer, renderer)
        or not Mizuki.renderCannonSpiritSword(cannon) then return end
    renderSwordAttachments(cannon, renderOffset, renderer)
end, swordRendererVariant)

else
Mizuki:AddCallback(ModCallbacks.MC_POST_PLAYER_RENDER, function(_, player, renderOffset)
    if not Mizuki.isMizuki(player) or not Mizuki.usesCannonSpiritSword(player) then return end
    for _, group in ipairs(player:GetData().MizukiCannons or {}) do
        for _, cannon in ipairs(group) do
            if alive(cannon) and not cannon:GetData().MizukiAwaitingInitialLayout
                and Mizuki.renderCannonSpiritSword(cannon) then
                renderSwordAttachments(cannon, renderOffset)
                Mizuki:RenderChargeBar(cannon, renderOffset, true)
            end
        end
    end
end)
end

function Mizuki.clearSpiritSwordEchoVisuals(ghost)
    local data = ghost:GetData()
    for _, entry in ipairs(data.MizukiSpiritSwordEchoVisuals or {}) do
        local body = entry.Body
        if alive(body) and body:GetData().MizukiSpiritSwordEchoBladeRole == true
            and Mizuki.isSameEntity(body:GetData().Ghost, ghost) then body:Remove() end
    end
    data.MizukiSpiritSwordEchoVisuals = nil
end

function Mizuki.updateSpiritSwordEchoVisuals(ghost)
    local cd = ghost:GetData()
    local source, shot = cd.MizukiSpiritSwordEchoSource, cd.MizukiEchoShot
    if not source or not shot or shot.Removed or not alive(source.Player, source.PlayerSeed) then
        Mizuki.clearSpiritSwordEchoVisuals(ghost)
        return
    end
    local attack = cd.MizukiSpiritSwordAttack
    local pose, arc
    if attack and not attack.Finished then
        local animation, frame, rotation = echoPose(attack)
        pose = {Animation = animation, Frame = frame, RotationOffset = rotation}
        arc = Game():GetFrameCount() - attack.Frame >= (attack.EchoPhaseFrames or 0)
            + (attack.PairedSpin and attack.PairedSpin.AlignFrames or 0)
    else
        pose = cd.MizukiSpiritSwordRestPose
        if not pose then
            local animation, frame, rotation = echoPose(source, 0)
            pose = {Animation = animation, Frame = frame, RotationOffset = rotation}
        end
        attack = nil
    end
    local alpha = shot.FadeFrame and math.max(0, 1 - (Game():GetFrameCount() - shot.FadeFrame) / 6) or 1
    local color = Mizuki.getCannonEchoColor(source.VisualColor or source.Player.Color,
        Mizuki.CannonEchoReplayAlpha * alpha)
    local visual = source.BladeVisual or {Kind = "cannon"}
    local scale = visual.HiltScale or Vector(source.Scale, source.Scale) * Mizuki.CANNON_ART_SCALE_MULTIPLIER
    local entries = cd.MizukiSpiritSwordEchoVisuals or {}
    cd.MizukiSpiritSwordEchoVisuals = entries
    local angles = source.ExtraAngles or {0}
    for index, angle in ipairs(angles) do
        local entry = entries[index] or {Hilt = Sprite()}
        entries[index] = entry
        local hilt = entry.Hilt
        if hilt:GetFilename() ~= hiltArt then
            hilt:Load(hiltArt, false)
            hilt:ReplaceSpritesheet(0, "gfx/entities/mizuki/spirit_sword.png")
            hilt:LoadGraphics()
        end
        hilt:SetFrame(pose.Animation, pose.Frame)
        hilt.Scale, hilt.Color, hilt.Offset = scale, color, Vector.Zero
        hilt.Rotation = source.Direction:GetAngleDegrees() - 90 + (pose.RotationOffset or 0) + angle
        local root = angle == 0 and Mizuki.getSpiritSwordEchoPosition(ghost)
            or attackDirectionalPosition(attack or source, source.Direction:Rotated(angle))
        local offset, rotation, bodyScale, hiltEnd = Mizuki.getSpiritSwordBladeTransform(hilt, nil, nil,
            visual.SpacingScale or source.HitboxScale and source.HitboxScale.X, source.RangeOffset)
        if visual.Kind == "knife" then
            offset = offset + Vector(0, -(visual.ForwardPixels or 0)):Rotated(rotation)
        end
        local body = entry.Body
        if not alive(body) then
            body = Isaac.Spawn(EntityType.ENTITY_EFFECT, swordRendererVariant, 0,
                root + offset / WORLD_TO_SCREEN_SCALE, copy(source.Player.Velocity), source.Player):ToEffect()
            body:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
            body.EntityCollisionClass, body.GridCollisionClass = EntityCollisionClass.ENTCOLL_NONE, EntityGridCollisionClass.GRIDCOLL_NONE
            local data = body:GetData()
            data.MizukiSpiritSwordEchoBladeRole = true
            data.Ghost, data.GhostSeed, data.Entry = ghost, ghost.InitSeed, entry
            data.Cannon, data.CannonSeed = ghost, ghost.InitSeed
            entry.Body = body
        end
        body.Position, body.PositionOffset, body.Velocity = root + offset / WORLD_TO_SCREEN_SCALE,
            Vector.Zero, copy(source.Player.Velocity)
        body.DepthOffset = ghost.Position.Y + ghost.DepthOffset - body.Position.Y
        body.Visible = true -- Sprite alpha is hidden; the ghost's depth pass draws it once.
        Mizuki.configureSpiritSwordBladeAppearance(ghost, body, bodyScale, rotation, color,
            visual)
        Mizuki.alignSpiritSwordBladeEntity(body, root, hilt,
            visual.SpacingScale or source.HitboxScale and source.HitboxScale.X or 1, source.RangeOffset)
        body.DepthOffset = ghost.Position.Y + ghost.DepthOffset - body.Position.Y
        entry.Root, entry.HiltEnd, entry.Arc, entry.Color = root, hiltEnd, arc, color
    end
    for index = #entries, #angles + 1, -1 do
        local body = entries[index].Body
        if alive(body) and body:GetData().MizukiSpiritSwordEchoBladeRole == true then body:Remove() end
        table.remove(entries, index)
    end
end

function Mizuki.renderSpiritSwordEcho(ghost, renderOffset)
    local cd = ghost:GetData()
    local source = cd.MizukiSpiritSwordEchoSource
    if not source or not alive(source.Player, source.PlayerSeed)
        or not Mizuki.isSpiritSwordPairPrepared(source.Player, source.Player:GetData()) then return end
    -- The same function also covers the birth frame before the first familiar update.
    Mizuki.updateSpiritSwordEchoVisuals(ghost)
    local game = Game()
    local scroll = game:GetRoom():GetRenderScrollOffset() + game.ScreenShakeOffset
    for _, entry in ipairs(cd.MizukiSpiritSwordEchoVisuals or {}) do
        local screen = Isaac.WorldToScreen(entry.Root) + renderOffset - scroll
        entry.Hilt:RenderLayer(0, screen, Vector.Zero, Vector.Zero)
        if entry.Arc then
            local arc = bladeSprite(ghost)
            arc:SetFrame(entry.Hilt:GetAnimation(), entry.Hilt:GetFrame())
            arc.Rotation, arc.Scale, arc.Color = entry.Hilt.Rotation,
                entry.Hilt.Scale * (1 / Mizuki.CANNON_ART_SCALE_MULTIPLIER), entry.Color
            local arcPosition = screen + Mizuki.getSpiritSwordRangeDisplacement(entry.Hilt:GetAnimation(),
                entry.Hilt:GetFrame(), entry.Hilt.Scale, entry.Hilt.Rotation, source.RangeOffset,
                source.BladeVisual and source.BladeVisual.SpacingScale) * WORLD_TO_SCREEN_SCALE
            arc:RenderLayer(1, arcPosition, Vector.Zero, Vector.Zero)
            arc:RenderLayer(2, arcPosition, Vector.Zero, Vector.Zero)
        end
        -- Existing visual-only short connector; no extra damaging replay shot.
        local target = Isaac.WorldToScreen(Mizuki.getSpiritSwordLinkEnd(entry.Body)) + renderOffset - scroll
        renderSwordLink(ghost, screen + entry.HiltEnd, target, entry.Color, source.Scale)
        Mizuki.renderSpiritSwordBladeBody(ghost, entry.Body, renderOffset, entry)
    end
end

Mizuki:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, function(_, hitbox)
    local data = hitbox:GetData()
    if data.MizukiSpiritSwordHitbox ~= true then return end
    local attack = data.MizukiSpiritSwordAttack
    if attack and not attack.Finished then
        registerAttack(attack) -- surviving owned knives reconnect after Lua reload
        configureHitbox(attack)
    end
end, 9522)
Mizuki:AddPriorityCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, CallbackPriority.LATE, function(_, knife)
    local data = knife:GetData()
    if (data.MizukiCannonKnife == true or data.MizukiEchoKnife == true)
        and (data.MizukiSpiritSwordSpinThrow == true or data.MizukiSpiritSwordThrowCarrier == true) then
        local cannon = data.MizukiCannonKnifeCannon or (data.MizukiEchoChild and data.MizukiEchoChild.Ghost)
        Mizuki.syncSpiritSwordKnifeThrow(knife, cannon)
    end
end)
Mizuki:AddCallback(ModCallbacks.MC_PRE_KNIFE_COLLISION, function(_, knife, enemy)
    local data = knife:GetData()
    if data.MizukiSpiritSwordHitbox ~= true then return end
    return true -- the active radius-query path exclusively owns these knives
end, 9522)

Mizuki:AddCallback(ModCallbacks.MC_PRE_KNIFE_COLLISION, function(_, knife)
    if knife:GetData().MizukiSpiritSwordThrowCarrier == true then return true end
end)
Mizuki:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.EARLY,
    function(_, enemy, amount, flags, source, countdown)
        local knife = source and source.Entity and source.Entity:ToKnife()
        if knife and knife:GetData().MizukiSpiritSwordThrowCarrier == true then return false end
        if not knife or knife:GetData().MizukiSpiritSwordHitbox ~= true then return end
        local data = knife:GetData()
        -- The replacement TakeDamage call keeps the same native source/flags.
        -- Let it pass exactly once without repeating the contact ledger/effects.
        if data.MizukiSpiritSwordDamageDispatch == true then return end
        local attack = data.MizukiSpiritSwordAttack
        if not attack or attack.Finished then return false end
        if attack.SpinThrow and (not alive(attack.ThrowKnife, attack.ThrowKnifeSeed)
            or not attack.ThrowKnife:IsFlying()) then return false end
        configureHitbox(attack)
        local group = attack.CollisionGroups[data.MizukiSpiritSwordGroupIndex or 0]
        if not enemy:IsVulnerableEnemy() or enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            or not swordHitboxes.entityContact(group, enemy) then return false end
        local previous = attack.Targets[GetPtrHash(enemy)]
        -- Native 0x96974F..0x969793 checks and inserts the target's identifier
        -- in the attack hit set (0x431640/0x431570), without a frame timeout.
        if previous and previous.Seed == enemy.InitSeed then return false end
        attack.Targets[GetPtrHash(enemy)] = { Seed = enemy.InitSeed, Frame = Game():GetFrameCount() }

        if attack.ChargeContact and attack.ChargeCancelArmed then
            local state = attack.Player:GetData().MizukiSpiritSwordInput
            if state and state.ChargeContact == attack then
                state.ChargeConsumed, state.ChargeStart = true, nil
                local pd = attack.Player:GetData()
                pd.MizukiCharge, pd.MizukiChargeBarFullFrames = 0, nil
                -- Leave the source alive until this native damage dispatch
                -- finishes; no second contact may consume the same charge.
                attack.RetireAfterHit = true
                attack.DeadEyeAttack = Mizuki.trackDeadEyeSwing(attack.Player, knife, 1)
            end
        end
        if attack.DeadEyeAttack then attack.DeadEyeAttack.Hit = true end
        -- Native sword collision 9689C8..968A0C / 969A9C..969B36:
        -- source mass * 18/3, attenuated by 50/(target mass+50).
        -- AddVelocity performs the same time-scale/friction scaling
        -- (4314B0) as that native branch. Deliberately omit player recoil.
        if not enemy:HasEntityFlags(EntityFlag.FLAG_NO_KNOCKBACK) then
            local outward = enemy.Position - (attack.SpinThrow and attack.ThrowKnife.Position or attack.Player.Position)
            local distance = outward:Length()
            if distance > 0 then
                local force = knife.Mass * 6 * 50 / (enemy.Mass + 50)
                enemy:AddVelocity(outward * (force / distance))
            end
        end
        local npc = enemy:ToNPC()
        if npc then npc:PlaySound(SoundEffect.SOUND_MEATY_DEATHS, 0.75, 0, false, 1.8) end
        -- Samael's native hit-interaction bridge; reset to collision variant 0
        -- at the next owned knife update, never alter another knife.
        knife.Variant = 10
        data.MizukiSpiritSwordDamageDispatch = true
        local ok, result = pcall(function()
            return enemy:TakeDamage(attack.Damage, flags or 0, EntityRef(knife), countdown or 0)
        end)
        data.MizukiSpiritSwordDamageDispatch = nil
        if not ok then error(result) end

        return false -- cancel the cached native knife hit, not the replacement
    end)
Mizuki:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    for index = #attacks, 1, -1 do
        local attack = attacks[index]
        local invalidThrow = attack.SpinThrow and (not alive(attack.ThrowKnife, attack.ThrowKnifeSeed)
            or not attack.ThrowKnife:IsFlying()
            or attack.ThrowKnife:GetData().MizukiSpiritSwordThrowAttack ~= attack
            or attack.ThrowKnife:GetData().MizukiMultidimensionalKnifeInactive)
        if attack.Finished or attack.RetireAfterHit or not alive(attack.Player, attack.PlayerSeed)
            or not alive(attack.Cannon, attack.CannonSeed)
            or not Mizuki.usesCannonSpiritSword(attack.Player)
            or invalidThrow or Game():GetFrameCount() >= attack.Frame + attack.Duration then
            retire(attack)
            table.remove(attacks, index)
        elseif alive(attack.Hitbox, attack.HitboxSeed) then
            if attack.SpinThrow then Mizuki.syncSpiritSwordKnifeThrow(attack.ThrowKnife, attack.Cannon)
            else configureHitbox(attack) end
            for index = #(attack.PendingWaves or {}), 1, -1 do
                local wave = attack.PendingWaves[index]
                if Game():GetFrameCount() - attack.Frame >= wave.FireAge + (attack.EchoPhaseFrames or 0) then
                    fireWave(attack, wave.Direction, attack.ReplayMultiplier, wave)
                    table.remove(attack.PendingWaves, index)
                end
            end
            swordInteractions.update(attack, swordHitboxes)
            if attack.Spin and not attack.SpinThrow and not attack.Echo and (attack.NextSpinWave or 2) <= (attack.SpinCount or 1) then
                local age = Game():GetFrameCount() - attack.Frame - (attack.PairedSpin and attack.PairedSpin.AlignFrames or 0)
                if age >= 11 + (attack.NextSpinWave - 2) * 9 then
                    for _, angle in ipairs(attack.WaveAngles or attack.ExtraAngles or {0}) do fireWave(attack, attack.Direction:Rotated(angle), 1) end
                    attack.NextSpinWave = attack.NextSpinWave + 1
                end
            end
        end
    end
end)
local function clearAttacks()
    for _, attack in ipairs(attacks) do retire(attack) end
    attacks = {}
end
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, clearAttacks)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, clearAttacks)
Mizuki:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, clearAttacks)
Mizuki:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, function(_, tear)
    Mizuki.applySpiritSwordVisual(tear)
end)
