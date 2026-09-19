# Manual Acceptance Checklist

本清单专门用于需要实际启动 CS2 才能确认的行为。

Coding agent **不应自行启动 CS2 完成本清单**。Agent 只负责对应代码路径、单元测试、构建、静态检查和打包检查，并把无法从代码证明的行为留给用户手动验证。

每次 CS2 / CounterStrikeSharp / MetaMod 大更新后，也可以复用本清单做回归。

## A. 普通 Steam 启动隔离

当前实现：`gameinfo.gi` 的常驻状态就是 clean，本项目 SearchPath 只存在于一次 Panel 启动所打开的窗口内，退出时由插件恢复，异常残留由 Panel 下次启动或插件自愈处理。因此需要覆盖"恢复发生了但没有被面板看到"的情况。

- [ ] 完整退出 Panel 和 CS2。
- [ ] 确认 `<csgo>\gameinfo.gi` 中不含 `csgo/addons/metamod` 行。
- [ ] 直接从 Steam 启动 CS2。
- [ ] 游戏可以正常进入普通环境，没有因为残留 `-insecure` 或 Mod SearchPath 造成模式异常。
- [ ] 本项目 PlayerCosmetics 不应加载或改变真人玩家饰品。
- [ ] 上一次曾经使用本地饰品模式并正常退出 CS2，也不会改变上述结果。
- [ ] CS2 正常退出后，插件日志（CounterStrikeSharp 日志）出现 `Restored clean gameinfo.gi (plugin unload)`。
- [ ] 曾经强退 Panel / CS2 后，再直接 Steam 启动仍是普通状态。
- [ ] 强退 Panel 但 CS2 继续运行，再退出 CS2、再 Steam 启动：仍是普通 CS2。
- [ ] 让 CS2 直接崩溃（或强杀进程）后立刻从 Steam 再启动一次：**这一次可能仍加载 Mod**（残留窗口），但插件日志应出现 `Restored clean gameinfo.gi (runtime loaded outside a Panel launch)`，并且**再下一次** Steam 启动必须是完全普通的 CS2。这是当前设计承认的残余限制，需要确认它确实只影响一次启动。
- [ ] Panel 日志出现 `panel.isolation_recovered`（若上一次事务未完成）。
- [ ] 如果你另外装有第三方 MetaMod，确认本项目**没有**移除它的 SearchPath。

如需技术确认，可在退出游戏后把日志 / 当前 `gameinfo.gi` 状态交给 Agent 复审，但不要仅凭 Panel 文案认定隔离成功。

## B. 本地饰品模式启动

- [ ] 打开 Panel，通过本项目入口启动本地饰品模式。
- [ ] Panel 不要求永久修改 Steam Launch Options，也没有任何"模式"选项需要事先切换。
- [ ] 该次启动使用 `-insecure`。
- [ ] 启动后 `<csgo>\addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\panel_isolation.json` 被插件消费（该文件消失属正常）。
- [ ] MetaMod、CounterStrikeSharp 和 PlayerCosmetics 正常加载。
- [ ] **换地图 / 重开一局后饰品仍然生效**，且此时 `gameinfo.gi` 仍是 clean —— 这验证引擎只在进程启动时读取 gameinfo。
- [ ] 使用的是 CS2 官方普通 Bot，而不是 Enhanced Bot AI。
- [ ] Bot 瞄准、投掷物、购买和行为没有出现旧 Bot Improver 的增强逻辑。
- [ ] 游戏内控制台 `css_cs2bi_knives_status` 报告的 `enabled`、catalog 数量和面板所见一致。

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

快捷刀轮换默认关闭。先在 Panel 中启用、挑选轮换列表，并把 Panel 显示的 `bind …` 命令自行加入个人配置后再进游戏验证：

- [ ] Panel 不会自动写入或改写任何 cfg / bind；未手动复制绑定命令时，按键完全不起作用。
- [ ] 默认或自定义快捷列表按预期轮换。
- [ ] 轮换顺序与在 Panel 中点击加入的顺序一致。
- [ ] 不再像旧 cfg 一样一次在地面生成大量刀具实体。
- [ ] 每把刀切换后恢复该刀自己的皮肤预设。
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
- [ ] 恢复后 Steam Verify Integrity 能顺利回到官方文件状态。
- [ ] 恢复后再直接 Steam 启动，没有本项目 runtime 残留。

## L. 运行中热更新

CS2 正在跑本地饰品模式时，从 Panel 改配置应在几十毫秒到一次安全事件内生效，不需要重启游戏，也不需要重新开局。

- [ ] 改刀皮：只有刀具外观刷新，手套 / 枪械外观不变。
- [ ] 改手套：只有手套与相关 bodygroup 变化，不出现裸手、模型重叠或持续闪烁。
- [ ] 只改某一把枪的枪皮：只有该型号且属于你自己的武器变化，其他枪不动。
- [ ] 保存同一个配置（不改动任何值后再次点保存）不应产生可见的重复应用或闪烁。
- [ ] 玩家死亡瞬间保存：不崩溃，效果推迟到下一次安全事件（重生 / 换队）正确生效。
- [ ] 连续快速保存多次编辑：最终状态正确，不出现队列堆积或长时间无响应。
- [ ] 把 `player_knife_presets.json` 手动改成非法 JSON 再保存 Panel 侧改动：游戏内饰品保持上一次仍然有效的外观，CounterStrikeSharp 日志记录加载失败，不崩溃。
- [ ] 手工把一个 Wear 改成超出该 PaintKit 区间（例如 `0.99`）：重生后应看到该 PaintKit 允许的最旧磨损，而不是皮肤消失。
- [ ] StatTrak 击杀计数在运行中累加并写回配置文件，不应触发整把武器的重复应用或视觉抖动。
- [ ] 关闭 Panel 后本局饰品继续生效；重开 Panel 后预设仍在且不产生重新应用风暴。

## M. 回归记录建议

每次做完整回归时记录：

- 日期
- CS2 build
- MetaMod 版本
- CounterStrikeSharp 版本
- 本项目 commit / release
- 测试地图与 Bot 数量
- 失败项目与复现步骤

这些信息用于后续判断问题来自 Valve / runtime 更新还是项目自己的回归。
