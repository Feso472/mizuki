# Mizuki / 弥月

Early vanilla Repentance+ character prototype. 

## Current prototype

- A separate playable character named `弥月Mizuki`.

## Code layout

`main.lua` owns the weapon controller and connects these feature modules:

- `scripts/cannon_echo.lua`: all cannon echoes; damage and follow-delay settings are at the top.
- `scripts/birthright.lua`: pickup detection, doctorate offers, Boss challenge and rewards.
- `scripts/cannons.lua`: deployment controls and contact damage.
- `scripts/weapon_synergies.lua`: Kidney Stone, Isaac's Tears and Neptunus compatibility.
- `scripts/localization.lua`: pickup banners and EID integration.
- `scripts/experimental_capsule.lua`, `scripts/fan.lua`, `scripts/moms_knife.lua`, `scripts/epic_fetus.lua`: independent gameplay features.
- `scripts/berserk_club.lua`: Berserk bone-club replacement, tap swings, held throw charge, reflection and melee pickup interactions. Throws reuse the knife-driven beam and its native collision offset; both club and beam carry the native Berserk kill-reward flag.

### C Section prototype

While Mizuki holds C Section, each real Xiaobotu familiar fires immediately
and then at `max(1, MaxFireDelay + 1)` logical-frame intervals while shooting.
This is a direct-fire character synergy with no charge bar. Firing plays
`SOUND_PLOP` (once per player per frame, including delayed echo shots).
The fetus starts at Xiaobotu's
position, uses the player's ShotSpeed and native tear damage/effects, and retains
Mizuki's custom fetus graphics (without an extra color tint). While holding
C Section, Xiaobotu uses `gbt.png`: cells 1/2 are forward/right idle/shot,
mirrored for left; cells 3/4 are back idle/shot, and cells 5-8 give gifts.
Idle floating never alternates into the shot artwork. An actual fetus launch
shows the shot artwork for five logical frames before returning to idle;
gifts take animation priority and echoes replay the recorded shot posture.
The gift's Drop event stays at logical frame 6. Losing C Section restores
Xiaobotu without restarting a gift in progress. Copied familiars fire independently.
Geibotu blocks enemy projectiles with a 75% chance and has an extra 1.5x
blocking radius, stacking with BFFS for 2.25x. C Section does not add visual
scaling. Each fetus (including echo shots) gets a 10% block roll per hostile
projectile, once per pair; failed rolls do not reroll on subsequent overlap
frames. Native Lost Contact shielding takes priority. EID shows the C Section
combination on both items and updates the familiar's displayed block chance.
With the existing Birthright + PHD/False PHD echo condition, each fan has a
separate Xiaobotu afterimage which follows the shared echo delay and replays
its fetus shots at the shared echo damage multiplier. The afterimage cannot
block projectiles or produce gifts. Brimstone, Technology, Tech X,
Mom's Knife, Spirit Sword and Dr. Fetus add their native fetus flags.

Only C Section's collectible costume is removed from Mizuki. Other costumes
and the item itself remain active. C Section takes priority over ordinary cannon
attacks, cannon contact damage, cannon knives and the custom Ludovico ring;
losing the item restores the usual weapon controller. Paused or disabled controls
suspend familiar firing. Native homing, lifespan and combined synergy priorities
still need in-game validation on the target Repentance build.

Language text stays in `translations/en.lua` and `translations/zh.lua`.
Related rules belong in their feature file; a new mode or short helper does not need a new module.

## Parameter conventions

- Define tuning values once, with a descriptive name and units (frames, degrees, world-space distance, probability or multiplier).
- `main.lua` defines shared `Mizuki.RuntimeParameters` and controller-owned `Mizuki.WeaponParameters` before loading features. Feature-private tuning stays near the top of its existing file or section.
- Cross-file consumers reference the owning parameter directly. For example, real knives and echoes use `Mizuki.KnifeParameters.SpinDegreesPerPixel`; echo geometry uses the controller's exported cannon scale and reflection span. Do not duplicate a fallback literal in another file.
- Parameters are load-time configuration, not a live settings API. Reload the mod after changing them so cached geometry and local aliases update together.
- Keep unrelated meanings separate even when their default numbers happen to match. Native enums, array indices, zero/one, and elementary geometric factors need no artificial aliases.
- Preserve native timing, RNG order, callback order and entity-identity guards when extracting parameters. This cleanup does not rebalance gameplay.
