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
- `scripts/berserk_club.lua`: Berserk bone-club swings, charged throws, reflection and kill-time extension.

### C Section compatibility

- Geibotu replaces the floating cannons and fires fetuses directly.
- Mizuki-only fetus graphics and Geibotu idle, shot and gift animations.
- Geibotu blocks projectiles at 75%; fetuses block at 10%.
- Delayed echoes replay fetus attacks and changing attack effects.
- Supports multishot and native fetus weapon combinations.
- Brimstone adds a damaging fireball and a chance to apply its curse.
- Epic Fetus strikes share the player's cooldown.
- Removes C Section's character costume from Mizuki.
