# Mizuki

A character mod for The Binding of Isaac: Repentance / Repentance+. Uses native Lua APIs; REPENTOGON is not required.

## Character features

- A pair of floating cannons replaces ordinary tear attacks.
- Xiaobotu follows Mizuki and offers supplies.
- Experimental Capsules provide stat changes.
- Birthright unlocks delayed attack echoes through the doctorate system.

## Code layout

Start with `main.lua` for the load order, then open the module for the feature you need.

- `main.lua`: initialization and module loading.
- `scripts/config.lua`: shared parameters, native IDs and layout constants.
- `scripts/character.lua`: character appearance, stats and cache refresh.
- `scripts/weapon_input.lua`: aiming and shared charge rules.
- `scripts/weapon_controller.lua`: weapon priority and attack dispatch.
- `scripts/weapon_beams.lua`: native beam creation, volleys and damage timing.
- `scripts/callbacks.lua`: core callback registration order.
- `scripts/cannons.lua`, `cannon_render.lua`, `cannon_appearance.lua`: cannon movement, drawing and appearance selection.
- `scripts/cannon_echo.lua`, `echo_attack_sequence.lua`: delayed attacks and recorded attack properties.
- `scripts/c_section.lua`, `moms_knife.lua`, `berserk_club.lua`, `spirit_sword.lua`: fetus, knife and melee weapons.
- `scripts/tech_x.lua`, `ludovico.lua`, `technology2.lua`, `trisagion.lua`: ring, controlled projectile and laser weapons.
- `scripts/weapon_synergies.lua`, `epic_fetus.lua`, `peppers.lua`: shared item interactions and additional attacks.
- `scripts/fan.lua`, `birthright.lua`, `experimental_capsule.lua`: Xiaobotu, Birthright and capsules.
- `scripts/localization.lua`: pickup text and EID integration.
- `translations/`: English and Chinese text and language loading.
- `content/`: character, item and entity definitions.
- `resources/`: graphics and animations.
