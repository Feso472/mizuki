-- Preserve floor transactions when Lua is reloaded; run initialization owns resets.
local capsuleStates = Mizuki and Mizuki.capsuleStates or {}
Mizuki = RegisterMod("Mizuki", 1)
Mizuki.capsuleStates = capsuleStates

include("scripts/config")
include("translations/main")
include("scripts/localization")
include("scripts/birthright")

-- Definitions load before callback registration. Cross-module helpers use Mizuki;
-- constants live in Config, while module-private helpers remain local.
include("scripts/character")
include("scripts/weapon_input")
include("scripts/cannons")
include("scripts/cannon_render")
include("scripts/weapon_beams")
include("scripts/ludovico")
include("scripts/weapon_controller")
include("scripts/callbacks")
Mizuki.registerCoreCallbacks()

-- Shared compatibility loads before weapons that consume its helpers.
include("scripts/weapon_synergies")
include("scripts/cannon_appearance")
include("scripts/peppers")
include("scripts/epic_fetus")
include("scripts/experimental_capsule")
include("scripts/c_section")
include("scripts/fan")
Mizuki.registerMeleePickupCallbacks()
include("scripts/berserk_club")
include("scripts/moms_knife")
include("scripts/tech_x")
include("scripts/technology2")
include("scripts/cannon_echo")
include("scripts/echo_attack_sequence")
include("scripts/trisagion")
include("scripts/spirit_sword")

Mizuki.registerSpecialBrimstoneCompatibility()
Mizuki.registerAttackPoseCallbacks()
Mizuki.registerFetalBrimstoneCallbacks()
Mizuki.registerTech5Callbacks()
Mizuki.registerInputAttackEffectCallbacks()
Mizuki.registerHemoptysisCallbacks()
Mizuki.RegisterPickupLocalization()
