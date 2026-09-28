-- Neptunus stores idle firing time separately from the current cannon charge.
-- The bank changes when an attack actually fires, not when a key is pressed.
local STORED_FRAME_CAP = 90
local BAR_HORIZONTAL_OFFSET = 20
local BAR_HEIGHT_SCALE = 48
local BAR_HEIGHT_BASE = 10

function Mizuki.isNeptunusEnabled(player, automatic)
    return not automatic
        and player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS)
        and not player:HasCollectible(
            CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE
        )
end

function Mizuki.resetNeptunusState(data)
    data.MizukiNeptunusStoredFrames = nil
    data.MizukiNeptunusHeldFrames = nil
end

function Mizuki.updateNeptunusStorage(player, data, shooting, automatic)
    if not Mizuki.isNeptunusEnabled(player, automatic) then
        Mizuki.resetNeptunusState(data)
        return false
    end

    -- A released Cursed Eye volley may still be firing. Like an ordinary
    -- airborne tear, it does not count as held shooting input here.
    if not shooting and (data.MizukiCharge or 0) <= 0 then
        data.MizukiNeptunusStoredFrames = math.min(
            STORED_FRAME_CAP,
            (data.MizukiNeptunusStoredFrames or 0) + 1
        )
    end
    return true
end

function Mizuki.advanceNeptunusCharge(data, profile)
    local held = math.min(
        (data.MizukiNeptunusHeldFrames or 0) + 1,
        profile.MaxFrames
    )
    data.MizukiNeptunusHeldFrames = held
    return math.min(
        profile.MaxFrames,
        held + (data.MizukiNeptunusStoredFrames or 0)
    )
end

function Mizuki.spendNeptunusCharge(data, charge)
    local stored = data.MizukiNeptunusStoredFrames or 0
    local held = data.MizukiNeptunusHeldFrames or 0
    data.MizukiNeptunusStoredFrames = math.max(
        0,
        stored - math.min(stored, math.max(0, charge - held))
    )
    data.MizukiNeptunusHeldFrames = nil
end

function Mizuki.canFireNeptunusDirect(data, frame, nextFrame)
    if not nextFrame or frame + 0.0001 >= nextFrame then
        return true
    end

    local required = nextFrame - frame
    local stored = data.MizukiNeptunusStoredFrames or 0
    if stored + 0.0001 < required then
        return false
    end
    data.MizukiNeptunusStoredFrames = math.max(0, stored - required)
    return true
end

function Mizuki.getNeptunusFreeSide(data)
    local nextShotSide = -(data.MizukiShotSide or -1)
    local preferred = nextShotSide == -1 and 1 or 2
    local other = preferred == 1 and 2 or 1
    local beams = data.MizukiActiveBeams or {}
    local positions = data.MizukiCannonPositions or {}
    local cannons = data.MizukiCannons or {}
    local function isFree(side)
        return positions[side] and #positions[side] > 0
            and cannons[side] and #cannons[side] > 0
            and (not beams[side] or #beams[side] == 0)
    end
    if isFree(preferred) then
        return preferred
    end
    if isFree(other) then
        return other
    end
    return nil
end

function Mizuki.recordNeptunusFiringSide(data, side)
    data.MizukiShotSide = side == 1 and -1 or 1
end

function Mizuki:RenderNeptunusBar()
    local game = Game()
    if game:IsPaused() or Options.ChargeBars == false then
        return
    end
    local room = game:GetRoom()
    local renderMode = room:GetRenderMode()
    if renderMode == RenderMode.RENDER_WATER_REFLECT
        or renderMode == RenderMode.RENDER_WATER_REFRACT
    then
        return
    end

    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Mizuki.isMizuki(player)
            and player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS)
            and Mizuki.isNeptunusEnabled(
                player,
                Mizuki.usesAutomaticBeam(player)
            )
        then
            local data = player:GetData()
            local stored = data.MizukiNeptunusStoredFrames or 0
            local bar = data.MizukiNeptunusBarSprite
            if stored > 0 or bar then
                if not bar then
                    bar = Sprite()
                    bar:Load("gfx/chargebar.anm2", true)
                    data.MizukiNeptunusBarSprite = bar
                end

                local frameCount = game:GetFrameCount()
                if data.MizukiNeptunusBarFrame ~= frameCount then
                    data.MizukiNeptunusBarFrame = frameCount
                    if bar:IsPlaying("StartCharged")
                        or bar:IsPlaying("Charged")
                        or bar:IsPlaying("Disappear")
                    then
                        bar:Update()
                    end

                    if stored >= STORED_FRAME_CAP then
                        if bar:IsFinished("StartCharged") then
                            bar:Play("Charged", true)
                        elseif not bar:IsPlaying("StartCharged")
                            and not bar:IsPlaying("Charged")
                        then
                            bar:Play("StartCharged", true)
                        end
                    elseif stored > 0 then
                        bar:SetFrame(
                            "Charging",
                            math.floor(stored / STORED_FRAME_CAP * 100)
                        )
                    elseif not bar:IsPlaying("Disappear")
                        and not bar:IsFinished("Disappear")
                    then
                        bar:Play("Disappear", true)
                    end
                end

                if stored > 0 or not bar:IsFinished("Disappear") then
                    local height = player.SpriteScale.Y * BAR_HEIGHT_SCALE
                        + BAR_HEIGHT_BASE
                    local worldPosition = player.Position
                        + Vector(BAR_HORIZONTAL_OFFSET, -height)
                    local renderPosition = Isaac.WorldToScreen(worldPosition)
                    bar:Render(renderPosition, Vector.Zero, Vector.Zero)
                end
            end
        end
    end
end

-- Render after player and familiar callbacks, so this player-owned meter sits
-- in front of both cannon bodies and their separate per-shot charge circles.
Mizuki:AddCallback(ModCallbacks.MC_POST_RENDER, Mizuki.RenderNeptunusBar)
