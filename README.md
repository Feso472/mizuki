# Mizuki

A character mod for The Binding of Isaac: Repentance / Repentance+. Uses native Lua APIs; REPENTOGON is not required.

Mizuki fights with a pair of floating cannons, accompanied by Xiaobotu, a familiar that offers supplies.

## Code layout

Start with `main.lua` for the attack controller, then explore the relevant feature module.

- `main.lua`: character setup, stats, attack control and module loading.
- `scripts/cannons.lua`: cannon deployment, following and contact damage.
- `scripts/cannon_appearance.lua`: cannon appearance selection and rendering.
- `scripts/cannon_echo.lua`: echo creation, following and delayed attacks.
- `scripts/echo_attack_sequence.lua`: recording and replaying attack property changes.
- `scripts/fan.lua`: Xiaobotu's following, gifts, projectile blocking and shared animations.
- `scripts/c_section.lua`: C Section firing, fetus graphics, blocking and Brimstone fireballs.
- `scripts/moms_knife.lua`: knife attacks, movement and rendering.
- `scripts/berserk_club.lua`: Berserk swings, charged throws and melee interactions.
- `scripts/epic_fetus.lua`: Epic Fetus targeting, rockets and cooldowns.
- `scripts/peppers.lua`: pepper attacks and echo replay.
- `scripts/weapon_synergies.lua`: shared item compatibility, including Dr. Fetus, Brimstone curses, Tech .5, Mom's Wig and Hemoptysis.
- `scripts/birthright.lua`: Birthright, doctorate choices and challenge rewards.
- `scripts/experimental_capsule.lua`: Experimental Capsule creation, use and state management.
- `scripts/localization.lua`: pickup banners and EID integration.
- `translations/`: English and Chinese text and language loading.
- `content/`: character, item and entity definitions.
- `resources/`: graphics and animations.
