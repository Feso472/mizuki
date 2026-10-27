-- Chinese pickup text and EID descriptions; keep player-facing text here.
return {
    EIDLanguage = "zh_cn",
    Player = {
        Name = "弥月",
        Birthright = "深渊三连打+家里蹲博士",
        BirthrightEID = "拾取后开启深渊三连打"
            .. "#{{Collectible75}}药学博士证和{{Collectible654}}伪造药学博士证添加至所有道具池，且生成概率会逐渐上升"
            .. "{MIZUKI_BIRTHRIGHT_ECHO}",
        BirthrightEchoEID = "再现过去的浮游炮#造成50%角色伤害",
        EID = "有两门交替发射的兔耳浮游炮"
            .. "#双击发射键将浮游炮部署在原地"
            .. "#再次按下发射键收回浮游炮"
            .. "#{MIZUKI_CAPSULE_ICON} 每层获得一枚实验性胶囊",
        CapsuleDropLockEID = "获得的胶囊无法丢弃",
        CapsuleDropLockReverseEID = "弥月每层获得的{MIZUKI_CAPSULE_ICON}实验性胶囊无法丢弃",
    },
    BirthrightName = "长子名分",
    BossPortal = {
        Name = "深渊三连打",
        EIDByStage = {
            "进入第一场Boss挑战",
            "进入第二场Boss挑战",
            "进入第三场Boss挑战",
        },
        ContinueEID = "继续挑战可获得更多道具#{{Warning}} 拾取道具将结束三连打",
    },
    Fan = {
        Description = "可靠的小帮手",
        NativeInfo = {
            "50%概率抵挡敌方泪弹",
            "每层给予一个角色需要的掉落物",
            "清理房间后有概率给予额外掉落物",
        },
        Name = "小博兔",
        EID = "{MIZUKI_FAN_BLOCK_CHANCE}%概率抵挡敌方泪弹{MIZUKI_FAN_BFFS_BLOCK}{MIZUKI_FAN_C_SECTION}"
            .. "#每层掉落1个角色最需要的掉落物"
            .. "#清理房间后，有概率额外掉落1个角色最需要的掉落物"
            .. "{MIZUKI_FAN_BFFS_CHANCE}{MIZUKI_FAN_LUCKY_FOOT}"
            .. "#{{Luck}} {{NoLB}}{MIZUKI_FAN_LUCK_LINE}"
            .. "#资源充足时更容易生成高级掉落物{MIZUKI_FAN_MOMS_BOX}{MIZUKI_FAN_SACK_HEAD}",
        Synergies = {
            C_SECTION = "弥月持有时变为给博兔，从给博兔发射胎儿；本体消弹概率变为75%，阻挡半径额外扩大50%，可与大宝叠加；每个胎儿有10%概率抵挡敌方泪弹",
            BFFS_BLOCK = "阻挡半径扩大50%",
            BFFS_CHANCE = "清房掉落概率额外增加20%",
            LUCKY_FOOT = "幸运提供的清房掉落概率翻倍",
            MOMS_BOX = "掉落的饰品有10%概率变为金饰品",
            SACK_HEAD = "普通掉落物有20%概率替换为福袋",
        },
        ReverseSynergies = {
            C_SECTION = "弥月的小博兔变为给博兔并发射胎儿；本体消弹概率变为75%，阻挡半径额外扩大50%，可与大宝叠加；每个胎儿有10%概率抵挡敌方泪弹",
            BFFS_BLOCK = "阻挡半径扩大50%，清房掉落概率额外增加20%",
            LUCKY_FOOT = "幸运提供的清房掉落概率翻倍",
            MOMS_BOX = "小博兔掉落的饰品有10%概率变为金饰品",
            SACK_HEAD = "小博兔的普通掉落物有20%概率替换为福袋",
        },
    },
    Capsule = {
        Name = "实验性胶囊",
        Description = "实验性胶囊？",
        EID = "↑ 随机提升1项属性#↓ 随机降低1项属性",
    },
}
