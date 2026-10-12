-- Real attack notifications are grouped by side, not by projectile count.
local PERIOD = Mizuki.BEAM_DAMAGE_INTERVAL * 2
local getState
local function canRoll(player)
    return Mizuki.isMizuki(player) and not Game():IsPaused() and not player:IsDead()
        and player:AreControlsEnabled() and player:IsExtraAnimationFinished()
        and player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG)
end
local function roll(player, channel)
    if not canRoll(player) then return end
    local state, frame = getState(player), Game():GetFrameCount()
    local previous = state.Attempts[channel]
    if previous and frame >= previous and frame - previous < PERIOD then return end
    -- Failed rolls consume the same minimum interval. Rewinds discard a future
    -- attempt rather than locking the player to the abandoned timeline.
    state.Attempts[channel] = frame
    local twiceLuck = player.Luck * 2
    local steps = twiceLuck < 0 and math.ceil(twiceLuck) or math.floor(twiceLuck)
    local rng = player:GetCollectibleRNG(CollectibleType.COLLECTIBLE_MOMS_WIG)
    if rng:RandomInt(math.max(1, 20 - steps)) ~= 0 then return end
    local hive = CollectibleType.COLLECTIBLE_HIVE_MIND
    local cap = (player:HasCollectible(hive)
        or player:GetEffects():HasCollectibleEffect(hive)) and 10 or 5
    if player:GetNumBlueSpiders() >= cap then return end
    -- Vanilla Wig passes a zero target: native code chooses a free landing
    -- position and adds scatter. An explicit target bypasses that selection.
    player:ThrowBlueSpider(player.Position, Vector.Zero)
end
getState = function(player)
    local data = player:GetData()
    if not data.MizukiMomsWigState or not data.MizukiMomsWigState.Attempts then
        data.MizukiMomsWigState = { Shots = {}, Clocks = {}, Attempts = {} }
    end
    return data.MizukiMomsWigState
end
local function controlledMode(player, data)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then return end
    local ring = data.MizukiLudovicoTechXProbe
    if ring and ring:Exists()
        and player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
        return "controlled"
    end
    if Mizuki.getTargetReticle(player, data) then return "controlled" end
end
local function originalBeam(data, side, beam)
    local cannon = data.MizukiCannons and data.MizukiCannons[side]
        and data.MizukiCannons[side][1]
    return cannon and cannon:Exists() and beam.Cannon == cannon
        and not beam.PersistentEchoMode
        and not cannon:GetData().MizukiGuillotineNonFiring
end
local function liveBeam(beam)
    return beam.Laser and beam.Laser:Exists()
end
-- The controller calls once after the whole volley exists. Only the primary
-- pair counts; Box of Friends, extra familiars and echoes do not add procs.
function Mizuki.recordMomsWigAttack(player, beams, automatic, periodic, duration, echo)
    if echo or not canRoll(player) then return end
    local data = player:GetData()
    if controlledMode(player, data) or data.MizukiCannonAutoFireState == "deployed"
        or automatic then return end
    local sides = {}
    for _, beam in ipairs(beams) do
        local side = beam.LeftEye and 1 or 2
        if originalBeam(data, side, beam) and liveBeam(beam) then
            sides[side] = sides[side] or {}
            sides[side][#sides[side] + 1] = beam
        end
    end
    for side = 1, 2 do
        if sides[side] then
            if periodic then
                local state = getState(player)
                state.Shots[#state.Shots + 1] = {
                    Beams = sides[side], Side = side, Elapsed = 0, Duration = duration,
                    BornFrame = Game():GetFrameCount(),
                }
            else roll(player, side) end
        end
    end
end
-- Real gbt volleys report here. Echo replay calls fireFanFetus directly;
-- simultaneous familiar copies share one player opportunity.
function Mizuki.recordMomsWigFanVolley(player)
    if not canRoll(player) then return end
    roll(player, "fan")
end
local function advanceClock(player, state, side, mode, interval)
    local clock = state.Clocks[side]
    if not clock or clock.Mode ~= mode then
        clock = { Mode = mode, Elapsed = 0, Interval = interval }
        state.Clocks[side] = clock
    elseif clock.Interval ~= interval then
        clock.Elapsed = clock.Elapsed * interval / clock.Interval
    end
    clock.Interval = interval
    clock.Elapsed = clock.Elapsed + 1
    if clock.Elapsed >= interval then
        clock.Elapsed = clock.Elapsed - interval
        roll(player, side)
    end
end
function Mizuki:UpdateMomsWig(player)
    if not Mizuki.isMizuki(player) then return end
    local data = player:GetData()
    if player:IsDead() or not player:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_WIG) then
        data.MizukiMomsWigState = nil
        return
    end
    if not canRoll(player) then return end
    local state, frame = getState(player), Game():GetFrameCount()
    if state.LastFrame == frame then return end
    state.LastFrame = frame
    if player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION) then
        state.Shots, state.Clocks = {}, {}
        return
    end
    local deployed = data.MizukiCannonAutoFireState == "deployed"
    local mode = controlledMode(player, data) or deployed and "deployed"
    if mode then state.Shots = {} end
    for index = #state.Shots, 1, -1 do
        local shot, live = state.Shots[index], false
        for _, beam in ipairs(shot.Beams) do
            if liveBeam(beam) then live = true; break end
        end
        if not live then table.remove(state.Shots, index)
        elseif shot.BornFrame ~= frame then
            shot.Elapsed = shot.Elapsed + 1
            -- Preserve the finite window, including the native shrink tail.
            -- Another effect holding a laser cannot extend this quota.
            if shot.Elapsed <= shot.Duration and shot.Elapsed % PERIOD == 0 then roll(player, shot.Side) end
            if shot.Elapsed >= shot.Duration then table.remove(state.Shots, index) end
        end
    end
    for side = 1, 2 do
        local source
        for _, beam in ipairs(data.MizukiActiveBeams and data.MizukiActiveBeams[side] or {}) do
            if originalBeam(data, side, beam) and liveBeam(beam) and not beam.Ending then
                source = source or beam
                if beam.Automatic then source = beam; break end
            end
        end
        local cannon = data.MizukiCannons and data.MizukiCannons[side]
            and data.MizukiCannons[side][1]
        local interval, clockMode
        if mode and cannon and cannon:Exists() then
            clockMode = mode
            interval = (Mizuki.usesAutomaticBeam(player) or Mizuki.hasPeriodicBeam(player))
                and PERIOD or math.max(PERIOD, player.MaxFireDelay + 1)
        elseif source and source.Automatic then
            clockMode, interval = "continuous", PERIOD
        end
        if interval then advanceClock(player, state, side, clockMode, interval)
        else state.Clocks[side] = nil end
    end
end
local function reset()
    for index = 0, Game():GetNumPlayers() - 1 do
        local data = Isaac.GetPlayer(index):GetData()
        data.MizukiMomsWigState = nil
    end
end
Mizuki:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, Mizuki.UpdateMomsWig)
Mizuki:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, reset)
Mizuki:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, reset)
