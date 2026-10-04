-- English fallback for native pickup text and EID descriptions.
return {
    EIDLanguage = "en_us",
    Player = {
        Name = "Mizuki",
        Birthright = "Doctorates, the abyss, and echoes",
        BirthrightEID = "Opens Three Rounds in the Abyss on pickup"
            .. "#Adds {{Collectible75}}PHD and {{Collectible654}}False PHD to all item pools, with a gradually increasing chance to appear"
            .. "{MIZUKI_BIRTHRIGHT_ECHO}",
        BirthrightEchoEID = "Recreates cannons from the past#Deals 50% of the character's damage",
        EID = "Two rabbit-ear cannons take turns firing"
            .. "#Double-tap a fire button to deploy the cannons in place"
            .. "#Press a fire button again to recall the cannons"
            .. "#{MIZUKI_CAPSULE_ICON} Receives an Experimental Capsule each floor",
        CapsuleDropLockEID = "Received capsules cannot be dropped",
        CapsuleDropLockReverseEID = "{MIZUKI_CAPSULE_ICON} Experimental Capsules received by Mizuki each floor cannot be dropped",
    },
    BirthrightName = "Birthright",
    BossPortal = {
        Name = "Three Rounds in the Abyss",
        EIDByStage = {
            "Enter the first boss challenge",
            "Enter the second boss challenge",
            "Enter the third boss challenge",
        },
        ContinueEID = "Continue the challenge for more items#{{Warning}} Picking up an item ends the challenge chain",
    },
    Fan = {
        Name = "Xiaobotu",
        EID = "50% chance to block enemy projectiles{MIZUKI_FAN_BFFS_BLOCK}"
            .. "#Drops 1 pickup the character needs most each floor"
            .. "#Chance to drop 1 extra pickup the character needs most after clearing a room"
            .. "{MIZUKI_FAN_BFFS_CHANCE}{MIZUKI_FAN_LUCKY_FOOT}"
            .. "#{{Luck}} {{NoLB}}{MIZUKI_FAN_LUCK_LINE}"
            .. "#More likely to generate higher-tier pickups when well supplied{MIZUKI_FAN_MOMS_BOX}{MIZUKI_FAN_SACK_HEAD}",
        Synergies = {
            BFFS_BLOCK = "50% larger blocking radius",
            BFFS_CHANCE = "An extra +20% room-clear drop chance",
            LUCKY_FOOT = "Doubles the luck-based portion of the room-clear drop chance",
            MOMS_BOX = "Dropped trinkets have a 10% chance to become golden",
            SACK_HEAD = "Basic pickups have a 20% chance to be replaced with a sack",
        },
        ReverseSynergies = {
            BFFS_BLOCK = "50% larger blocking radius and an extra +20% room-clear drop chance",
            LUCKY_FOOT = "Doubles the luck-based portion of the room-clear drop chance",
            MOMS_BOX = "Trinkets dropped by Xiaobotu have a 10% chance to become golden",
            SACK_HEAD = "Xiaobotu's basic pickup drops have a 20% chance to be replaced with a sack",
        },
    },
    Capsule = {
        Name = "Experimental Pill",
        Description = "Experimental Pill?",
        EID = "↑ Increases 1 random stat#↓ Decreases 1 random stat",
    },
}
