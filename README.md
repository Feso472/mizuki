# Mizuki / 弥月

A playable character mod for vanilla Repentance / Repentance+, using native Lua APIs without REPENTOGON.

## Character

- A separate playable character named `弥月Mizuki`.
- Paired floating cannons provide Mizuki's ordinary attacks, with weapon replacements and item synergies.
- Xiaobotu handles gifts and becomes Geibotu while Mizuki holds C Section, firing Mizuki's custom fetuses.
- Birthright with PHD or False PHD enables delayed attack echoes.

## Code layout

`main.lua` owns the weapon controller and connects these feature modules:

- `scripts/cannon_echo.lua`, `scripts/echo_attack_sequence.lua`: delayed attack replay, including recorded changes to attack flags, damage and color.
- `scripts/birthright.lua`: pickup detection, doctorate offers, Boss challenge and rewards.
- `scripts/cannons.lua`: deployment controls and contact damage.
- `scripts/weapon_synergies.lua`: shared item interactions, including Dr. Fetus bombs on the first enemy or obstacle contact.
- `scripts/cannon_appearance.lua`: floating-cannon appearance selection for permanent and randomly triggered tear graphics.
- `scripts/tech5.lua`, `scripts/moms_wig.lua`, `scripts/peppers.lua`, `scripts/hemoptysis.lua`: auxiliary item attacks and their trigger rules.
- `scripts/brimstone_special.lua`: Brimstone curses on special attacks and damaging fireballs attached to fetuses.
- `scripts/localization.lua`: pickup banners and EID integration.
- `scripts/experimental_capsule.lua`, `scripts/fan.lua`, `scripts/moms_knife.lua`, `scripts/epic_fetus.lua`: independent gameplay features.
- `scripts/berserk_club.lua`: Berserk bone-club replacement, tap swings, held throw charge, reflection and melee pickup interactions. Throws reuse the knife-driven beam and its native collision offset; both club and beam carry the native Berserk kill-reward flag.

### C Section compatibility

- **Attack replacement:** C Section disables ordinary cannon attacks, contact damage, cannon knives and the custom Ludovico ring. Losing it restores the usual weapon controller.
- **Firing origin:** Each real Xiaobotu fires fetuses from its own position; copied familiars fire independently.
- **Fire rate:** Direct fire without charging. The first shot is immediate; subsequent volleys use `max(1, MaxFireDelay + 1)` logical-frame intervals.
- **Attack properties:** Fetuses use the player's ShotSpeed and native tear damage/effects, including supported multishot combinations.
- **Fetus graphics:** Mizuki's custom fetus graphics apply only to her fetuses, without extra pink tinting.
- **Character costume:** Only C Section's collectible costume is removed from Mizuki.
- **Geibotu graphics:** C Section switches Xiaobotu to `gbt.png`; losing it restores Xiaobotu without interrupting an ongoing gift animation.
- **Animation cells:** Cells 1/2 are forward/right idle/shot, mirrored for left; cells 3/4 are back idle/shot; cells 5-8 give gifts.
- **Shot animation:** A launch shows the shot artwork for five logical frames, then returns to idle. Idle bobbing does not alternate into shot artwork.
- **Gift animation:** Gifts take priority over shots; the Drop event remains at logical frame 6.
- **Sound:** Launches play `SOUND_PLOP`, at most once per player per frame, including delayed echo shots.
- **Geibotu blocking:** 75% chance with an extra 1.5x blocking radius; BFFS stacks this to 2.25x. C Section itself does not enlarge the displayed familiar.
- **Fetus blocking:** Each fetus, including echo fetuses, has a 10% block chance per hostile projectile. Failed rolls do not repeat during continued overlap; native Lost Contact shielding takes priority.
- **Echo familiar:** Birthright with PHD or False PHD creates a delayed afterimage for each fan. The afterimage cannot block projectiles or give gifts.
- **Echo attacks:** Replay the recorded volley, shot posture and subsequent flag, damage and color changes, with the shared echo damage multiplier and echo transparency.
- **Native fetus weapons:** Technology, Tech X, Mom's Knife, Spirit Sword and Dr. Fetus use native fetus flags; Berserk supplies the bone-club flag.
- **Brimstone fireball:** A native damaging fireball follows beneath each fetus, at 0.5 times its scale and 50% of its damage.
- **Brimstone curse:** Fetuses can roll the custom curse using the player's luck.
- **Epic Fetus:** Fetus-triggered strikes share the player's cooldown.
- **Controls:** Pausing, death or disabled controls suspend familiar firing.
- **EID:** Both items show the combination; the familiar's description updates its block chance.

Language text stays in `translations/en.lua` and `translations/zh.lua`.
Related rules belong in their feature file; a new mode or short helper does not need a new module.

## Parameter conventions

- Define tuning values once, with a descriptive name and units (frames, degrees, world-space distance, probability or multiplier).
- `main.lua` defines shared `Mizuki.RuntimeParameters` and controller-owned `Mizuki.WeaponParameters` before loading features. Feature-private tuning stays near the top of its existing file or section.
- Cross-file consumers reference the owning parameter directly. For example, real knives and echoes use `Mizuki.KnifeParameters.SpinDegreesPerPixel`; echo geometry uses the controller's exported cannon scale and reflection span. Do not duplicate a fallback literal in another file.
- Parameters are load-time configuration, not a live settings API. Reload the mod after changing them so cached geometry and local aliases update together.
- Keep unrelated meanings separate even when their default numbers happen to match. Native enums, array indices, zero/one, and elementary geometric factors need no artificial aliases.
- Preserve native timing, RNG order, callback order and entity-identity guards when extracting parameters. This cleanup does not rebalance gameplay.
