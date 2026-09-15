-- Isaac's Tears charging from the beam's own damage ticks.
--
-- Extracted from main.lua. main publishes the helpers this file needs on the
-- Mizuki table; the functions below are published there in turn for the code
-- that stayed behind.

local BEAM_DAMAGE_INTERVAL = Mizuki.BEAM_DAMAGE_INTERVAL
local isMizuki = Mizuki.isMizuki
local hasActiveMizukiBeam = Mizuki.hasActiveMizukiBeam

-- Isaac's Tears charges once per two damage ticks of the beam, not once per
-- fire-rate interval: vanilla's Brimstone ticks 9 times over a shot and hands
-- out about 4 charges, which is what a two-ticks-per-charge rule produces. (The
-- "charges at the same rate as the fire rate" wording on the item's page
-- describes an older behaviour.) Multiple cannons/multishot beams are still one
-- attack, so a logical damage moment counts once rather than once per entity.
local CHARGE_ROLLS_PER_TICK = 2

local function countBeamDamageRolls(data)
    for side = 1, 2 do
        local beams = data.MizukiActiveBeams and data.MizukiActiveBeams[side]
        if beams then
            for _, beam in ipairs(beams) do
                local laser = beam.Laser
                if laser and laser:Exists()
                    and laser.FrameCount % BEAM_DAMAGE_INTERVAL == 0
                then
                    return 1
                end
            end
        end
    end
    return 0
end

-- Isaac's Tears charges by being shot: one charge per tear fired. Mizuki never
-- fires a tear - the cannons are lasers created through FireTechLaser - so the
-- weapon system the engine watches never runs and the item sits at zero
-- forever.
--
-- The rule reproduced here is the one the item follows with a tear-replacing
-- weapon (Brimstone, Mom's Knife, Technology): nothing accrues while the shot
-- is still charging, then it charges for as long as the beam is actually being
-- fired - one charge per damage tick pair, not per fire-rate interval.
local function updateIsaacsTearsCharge(player, data)
    local slot = nil
    -- Primary only: an off-hand active never charges, so charging one here
    -- would be inventing behaviour the game does not have.
    if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
        == CollectibleType.COLLECTIBLE_ISAACS_TEARS
    then
        slot = ActiveSlot.SLOT_PRIMARY
    end

    if not slot or not hasActiveMizukiBeam(data) then
        data.MizukiTearsChargeRolls = nil
        return
    end

    local banked = (data.MizukiTearsChargeRolls or 0)
        + countBeamDamageRolls(data)
    local charges = math.floor(banked / CHARGE_ROLLS_PER_TICK)
    data.MizukiTearsChargeRolls = banked % CHARGE_ROLLS_PER_TICK
    if charges < 1 then
        return
    end

    -- Modelled on the two community fixes for this exact problem: Samael's
    -- IsaacsTearsFix (another custom character whose weapon replaces tears) and
    -- CuerLib's Actives:ChargeSlot. Both read the *total* charge - the slot's
    -- active charge plus its battery charge - and write the sum back, capped at
    -- MaxCharges (doubled by The Battery). GetActiveCharge() alone does not
    -- include the battery bar, so reading only that would discard whatever the
    -- player has banked there.
    local itemConfig = Isaac.GetItemConfig():GetCollectible(
        CollectibleType.COLLECTIBLE_ISAACS_TEARS
    )
    local maxCharges = itemConfig and itemConfig.MaxCharges or 1
    if maxCharges < 1 then
        maxCharges = 1
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_BATTERY) then
        maxCharges = maxCharges * 2
    end

    local total = player:GetActiveCharge(slot) + player:GetBatteryCharge(slot)
    if total >= maxCharges then
        return
    end

    local nextCharge = math.min(maxCharges, total + charges)
    player:SetActiveCharge(nextCharge, slot)
    -- Feedback for a charge tick: the bar flashes and the tick beeps
    -- (sfx/feedback/beep.wav), with the item-recharge jingle on the tick that
    -- finishes the charge. SOUND_BATTERYCHARGE is the sound of picking a battery
    -- up, not of a charge tick.
    local sfx = SFXManager()
    sfx:Play(SoundEffect.SOUND_BEEP)
    Game():GetHUD():FlashChargeBar(player, slot)
    if nextCharge >= maxCharges then
        sfx:Play(SoundEffect.SOUND_ITEMRECHARGE)
    end
end

Mizuki.updateIsaacsTearsCharge = updateIsaacsTearsCharge
