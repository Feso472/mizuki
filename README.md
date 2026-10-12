# Mizuki / 弥月

《以撒的结合：忏悔 / 忏悔+》角色模组，使用原生 Lua API，无需 REPENTOGON。

弥月以一对浮游炮代替普通泪弹，小博兔负责随行与给予。道具组合会改变攻击方式；获得剖腹产后，由小博兔发射胎儿。

## 从哪里看起

先看 `main.lua` 的攻击控制，再按需要进入下面的功能模块。

- `main.lua`：角色初始化、属性与攻击控制、模块加载。
- `scripts/cannons.lua`：浮游炮部署、跟随和接触伤害。
- `scripts/cannon_appearance.lua`：浮游炮外观选择与绘制。
- `scripts/cannon_echo.lua`：残影生成、跟随和延迟发射。
- `scripts/echo_attack_sequence.lua`：攻击属性变化的记录与回放。
- `scripts/fan.lua`：小博兔跟随、给予、消弹与共用动画。
- `scripts/c_section.lua`：剖腹产发射、胎儿贴图、消弹和硫磺火团。
- `scripts/moms_knife.lua`：妈刀攻击、运动和绘制。
- `scripts/berserk_club.lua`：狂暴骨棒挥动、蓄力投掷和近战交互。
- `scripts/epic_fetus.lua`：史诗胎儿目标、导弹和冷却。
- `scripts/peppers.lua`：辣椒攻击及残影回放。
- `scripts/weapon_synergies.lua`：共用道具兼容，包括胎儿博士、硫磺火诅咒、科技 .5、假发和咳血。
- `scripts/birthright.lua`：长子权、博士选择与挑战奖励。
- `scripts/experimental_capsule.lua`：实验胶囊生成、使用与状态管理。
- `scripts/localization.lua`：拾取提示与 EID 集成。
- `translations/`：中英文文本与语言加载。
- `content/`：角色、道具和实体定义。
- `resources/`：贴图与动画资源。
