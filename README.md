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

Language text stays in `translations/en.lua` and `translations/zh.lua`.
Related rules belong in their feature file; a new mode or short helper does not need a new module.

## Parameter conventions

- Define tuning values once, with a descriptive name and units (frames, degrees, world-space distance, probability or multiplier).
- `main.lua` defines shared `Mizuki.RuntimeParameters` and controller-owned `Mizuki.WeaponParameters` before loading features. Feature-private tuning stays near the top of its existing file or section.
- Cross-file consumers reference the owning parameter directly. For example, real knives and echoes use `Mizuki.KnifeParameters.SpinDegreesPerPixel`; echo geometry uses the controller's exported cannon scale and reflection span. Do not duplicate a fallback literal in another file.
- Parameters are load-time configuration, not a live settings API. Reload the mod after changing them so cached geometry and local aliases update together.
- Keep unrelated meanings separate even when their default numbers happen to match. Native enums, array indices, zero/one, and elementary geometric factors need no artificial aliases.
- Preserve native timing, RNG order, callback order and entity-identity guards when extracting parameters. This cleanup does not rebalance gameplay.
