# Manual Acceptance Checklist

本清单专门用于需要实际启动 CS2 才能确认的行为。

Coding agent **不应自行启动 CS2 完成本清单**。Agent 只负责对应代码路径、单元测试、构建、静态检查和打包检查，并把无法从代码证明的行为留给用户手动验证。

每次 CS2 / CounterStrikeSharp / MetaMod 大更新后，也可以复用本清单做回归。

## A. 普通 Steam 启动隔离

- [ ] 完整退出 Panel 和 CS2。
- [ ] 直接从 Steam 启动 CS2。
- [ ] 游戏可以正常进入普通环境，没有因为残留 `-insecure` 或 Mod SearchPath 造成模式异常。
- [ ] 本项目 PlayerCosmetics 不应加载或改变真人玩家饰品。
- [ ] 上一次曾经使用本地饰品模式，也不会改变上述结果。
- [ ] 曾经强退 Panel / CS2 后，再直接 Steam 启动仍是普通状态。

如需技术确认，可在退出游戏后把日志 / 当前 `gameinfo.gi` 状态交给 Agent 复审，但不要仅凭 Panel 文案认定隔离成功。

## B. 本地饰品模式启动

- [ ] 打开 Panel，通过本项目入口启动本地饰品模式。
- [ ] Panel 不要求永久修改 Steam Launch Options。
- [ ] 该次启动使用 `-insecure`。
- [ ] CounterStrikeSharp 配置协调生效：`addons/counterstrikesharp/configs/core.json` 中的 `FollowCS2ServerGuidelines` 自动确保为 `false`。若原文件不存在，根据 `core.example.json` 模板安全生成；若原文件损坏，启动被安全阻止并给出明确提示。
- [ ] MetaMod、CounterStrikeSharp 和 PlayerCosmetics 正常加载，控制台与日志中无 `FollowCS2ServerGuidelines` 阻断 CEconItemView 属性写入报错。
- [ ] 购买轮盘说明：CS2 客户端购买菜单（Panorama UI）基于本地 Steam 库存缓存展示图标，属于客户端原生行为；购买发放后实际武器和手持视图正确套用本项目饰品预设。
- [ ] 使用的是 CS2 官方普通 Bot，而不是 Enhanced Bot AI。
- [ ] Bot 瞄准、投掷物、购买和行为没有出现旧 Bot Improver 的增强逻辑。

## C. 刀具

准备至少：Karambit、Butterfly、M9 Bayonet、Bayonet、Skeleton、Falchion。

- [ ] 刀型选择后模型、动画和 HUD 表现正常。
- [ ] 常用刀在 UI 中排序靠前。
- [ ] 每把刀能够保存自己的独立 PaintKit。
- [ ] 示例：Karambit = Vanilla、Butterfly = Black Laminate、M9 = Blue Steel；来回切换后各自恢复正确皮肤。
- [ ] Blue Steel / Black Laminate / Vanilla 等深色或中性条目容易找到。
- [ ] Doppler 各 Phase / Ruby / Sapphire / Black Pearl 没有被错误合并。
- [ ] Wear 不会被写到 catalog 范围之外。
- [ ] 游戏运行中在 Panel 改刀型 / 刀皮时能在安全时机应用；如果不能当前生命立即刷新，也会在下一安全事件正确生效，不崩溃。

## D. 快捷刀

若启用了快捷刀：

- [ ] 默认或自定义快捷列表按预期轮换。
- [ ] 受控实体替换生效：按下 `\` 快捷键切刀时，新刀以完整独立实体加载，骨骼动画、动作、手持视角模型（viewmodel）与音效完全匹配，绝无骨骼错位、模型穿模或动作混乱（如在蝴蝶刀模型上播放爪子刀动作）。
- [ ] 实体安全替换：旧刀从背包解绑并直接销毁，绝不掉落到地面，地上不产生残留刀具实体。
- [ ] 预设与原皮表现正确：该刀若配置了皮肤则应用对应预设；若未配置或为原皮（Paint = 0 / Vanilla），则加载正确的默认原皮外观。
- [ ] 若切刀步骤异常，回滚保留原刀，不导致玩家空手或手持损坏实体。
- [ ] 快捷功能关闭时不修改 `\` 或其他按键。
- [ ] 除用户明确选择的快捷键外，WASD、1/2/3、Q、E、F、鼠标、购买键等均未改变。

## E. 手套

- [ ] 手套型号和 PaintKit 可以正常选择。
- [ ] 中文名称正常显示；没有整体退化为英文 ID 列表。
- [ ] Wear / Seed 正常。
- [ ] 运行中改手套时模型 / bodygroup 表现正常，没有裸手、重叠模型或持续闪烁。
- [ ] 切刀不会无故改变已经选择的手套。

## F. 枪械 provenance / pickup

这是必须重点验证的行为。

准备一把自己购买的枪和一把 Bot / 地面来源的同型号枪。

- [ ] 自己购买 / 游戏发放的 AK、M4、AWP 等应用自己的预设。
- [ ] 自己买的枪扔到地上再捡回来，仍保持该实体已有外观。
- [ ] 捡 Bot 或其他已有实体的同型号枪，不会因为 `item_pickup` 突然套成自己的预设。
- [ ] 持有捡来的枪时，在 Panel 修改自己的该型号枪皮，不应错误覆盖这把外来实体。
- [ ] 新购买的下一把同型号枪仍使用新的玩家预设。
- [ ] 回合切换 / 死亡重生后上述规则仍一致。

## G. 枪械 UI 与中文

- [ ] 枪械入口没有因为本项目偏重刀具而被隐藏或大幅降级。
- [ ] CT / T 专属武器分别保存正确。
- [ ] 双方共用武器联动 / 分离语义符合 UI 提示。
- [ ] 中文名称可以搜索。
- [ ] 常见英文名（如 Blue Steel）在中文界面也能按设计命中；PaintKit / ID 搜索可用。

## H. Panel 生命周期

- [ ] 配置保存后重开 Panel，预设仍在。
- [ ] CS2 运行期间修改配置不会要求重启整个游戏才能永久保存。
- [ ] 如果实现允许 Panel 关闭后继续使用饰品，关闭 Panel 后本局饰品不消失。
- [ ] Panel 重开后能重新连接 / 同步到合理状态，不产生重复应用风暴。
- [ ] 窗口唤醒：当 Panel 处于最小化状态时，再次运行可执行文件或点击快捷方式，窗口能正常恢复（unminimize）、展示（show）并获取焦点（set_focus），回到前台可见状态，不出现点击后无反应的现象。

## I. 异常恢复

建议分别测试：

- [ ] Panel 正常退出。
- [ ] Panel 强制结束进程。
- [ ] CS2 正常退出。
- [ ] CS2 异常结束 / 崩溃后再次打开 Panel。
- [ ] 本地饰品启动失败。
- [ ] 连续点击启动或短时间重复启动。
- [ ] Steam 更新 / 验证文件后再次运行。

每种情况后都至少确认一次：**不打开 Panel，直接从 Steam 启动仍是普通 CS2。**

## J. 性能与体验

在相同地图、相同 Bot 数量、相同图形设置下比较纯净 CS2 和 Local Cosmetics 模式：

- [ ] 平均 FPS 没有明显可感知下降。
- [ ] 1% Low / frametime 没有持续恶化。
- [ ] 没有规律性卡顿、周期性 hitch 或切枪时异常冻结。
- [ ] CPU / 内存没有持续增长迹象。
- [ ] Panel 在后台 / 最小化时不造成明显额外干扰。

不要求追求数学意义上的 0% 差异；如果差异明显超过正常测试波动，应把日志、性能数据和复现步骤交回 Agent 排查。

## K. 安装、恢复与旧 Mod

- [ ] 从清理后的 CS2 基线安装本项目成功。
- [ ] 原旧 Bot Improver 不再作为运行依赖。
- [ ] “修复安装”不会清空自己的饰品预设。
- [ ] “恢复 / 卸载”不会删除未知第三方插件或个人 cfg。
- [ ] “恢复 / 卸载”针对 CounterStrikeSharp 配置只按 property 级 ownership 恢复：若安装前 core.json 存在，仅恢复原 FollowCS2ServerGuidelines 值；若原文件为本项目由 example 生成，则安全清理 core.json；保留文件中其他第三方配置。
- [ ] 恢复后 Steam Verify Integrity 能顺利回到官方文件状态。
- [ ] 恢复后再直接 Steam 启动，没有本项目 runtime 残留。

## L. 回归记录建议

每次做完整回归时记录：

- 日期
- CS2 build
- MetaMod 版本
- CounterStrikeSharp 版本
- 本项目 commit / release
- 测试地图与 Bot 数量
- 失败项目与复现步骤

这些信息用于后续判断问题来自 Valve / runtime 更新还是项目自己的回归。
