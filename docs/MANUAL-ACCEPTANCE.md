# Manual Acceptance Checklist

本清单专门用于需要实际启动 CS2、观察 WebView2 窗口或进行视觉判断才能确认的行为。Coding agent 不应自行启动 CS2；源码、测试、构建和静态检查不能代替本清单。

## A. 原 Local Arena 模式和启动

- [ ] Local、Preview、Bots、Online 等原有模式仍可从 Panel 正常选择和启动。
- [ ] 原有模式切换不会让 Panel 或 CS2 卡死、重复启动或丢失用户配置。
- [ ] Online 模式仍遵循原 Local Arena 的安全提示和启动约束；不要把本清单当成 VAC 或 Valve 政策保证。
- [ ] Panel 关闭、CS2 正常退出、CS2 异常退出后，重新打开 Panel 能看到合理的模式和安装状态。

## B. Bot、Match、Stats 回归

- [ ] 原有 Bot 功能、Bot 难度和体验仍可用，没有因为饰品改动被裁剪或替换。
- [ ] Match / Stats / 历史记录入口仍可访问，原有数据流程没有被本轮改动破坏。
- [ ] 现有 Local Arena UI 的主导航和相关页面仍在，没有被误改成 Cosmetics-only Panel。

## C. 刀具和快捷刀

准备至少：Karambit、Butterfly、M9 Bayonet、Bayonet、Skeleton、Falchion。

- [ ] 每把刀的模型、动画、HUD 和音效正常。
- [ ] 每把刀能够保存自己的独立 PaintKit；来回切换后各自恢复正确皮肤。
- [ ] `\\` 快捷功能按启用的列表轮换，默认顺序为 Karambit → Butterfly → M9 → Bayonet → Skeleton → Falchion。
- [ ] 快捷切换不在地面生成多余刀具，不会出现旧刀消失、永久没刀、跳过一个位置或错误 rollback 提示。
- [ ] 没有当前阵营 preset 时仍能切换刀型并呈现 Vanilla / default 路径；不会偷偷复制另一阵营 preset。
- [ ] 快捷功能关闭时不修改 `\\` 或其他按键。
- [ ] 运行中从 Panel 改刀型 / 刀皮能在安全时机应用；无法立即刷新时会在下一安全事件生效。

## D. 手套、音乐盒和图片

- [ ] 手套型号和 PaintKit 可以正常选择，模型 / bodygroup 没有裸手、重叠或持续闪烁。
- [ ] 手套名称显示可靠的 Simplified Chinese；英文名称、PaintKit 和 defindex 搜索也能命中。
- [ ] 音乐盒 picker 图片和名称正常，失败图片有可见 fallback，不出现大面积空白。
- [ ] 刀和枪 picker 的图片不因同一 CDN / WebView2 问题大面积失效。

## E. 枪械拾取和重新发装备

- [ ] 玩家购买、出生发放或本项目明确创建的枪械应用当前阵营自己的 preset。
- [ ] 拾取 Bot / 地面同型号枪时，如果当前阵营配置了该 weapon preset，Local Arena 可以按原逻辑应用自己的 preset。
- [ ] 如果当前阵营没有对应 preset，拾取不会无意义重写实体状态。
- [ ] 回防完成选枪后，配置的刀不会恢复成 Steam 默认刀。
- [ ] 特殊游戏模式重新发装备、respawn 或 loadout pipeline 创建新刀后，Knife phase 能重新应用配置。
- [ ] 上述枪械 / 刀具行为在回合切换和死亡重生后仍一致。

## F. Panel 生命周期和窗口恢复

- [ ] 配置保存后重开 Panel，预设仍在。
- [ ] CS2 运行期间修改配置不会要求重启整个游戏才能保存。
- [ ] 游戏退出后 Panel 不会留下无法恢复的任务栏缩略图或 Alt-Tab 窗口。
- [ ] 单实例第二次启动能唤醒已有窗口；窗口可见、未最小化、位置在屏幕内并获得合理焦点。
- [ ] Panel 强制结束、CS2 异常结束、连续点击启动后，再次打开 Panel 能恢复到可操作状态。

## G. 安装、恢复和 updater

- [ ] 安装 / 修复前后 `FollowCS2ServerGuidelines` 与饰品功能兼容；未知 `core.json` 字段仍保留。
- [ ] restore / uninstall 能按 ownership 恢复原 property，不删除未知第三方插件或个人 cfg / autoexec / bind。
- [ ] 应用内没有会把个人 fork 覆盖成官方 Local Arena release 的“更新”操作。
- [ ] 只读依赖 / 上游版本查看不会下载或安装官方 payload。

## H. 性能和体验

- [ ] 在相同地图、Bot 数量和图形设置下，饰品功能没有明显持续卡顿、周期性 hitch 或异常冻结。
- [ ] Panel 后台 / 最小化时没有明显额外干扰。
- [ ] 没有观察到持续增长的 CPU、内存或重复应用风暴。

## I. 回归记录建议

### 2026-09-23 main 审计后的定向实机项（尚未通过）

2026-09-24 compatibility patch 的源码和 Windows binary signature 已静态核对；以下运行中行为仍未实机确认：

本轮 Human PlayerCosmetics runtime 修复后的首轮验收：

- [ ] CT 与 T 各选一款手套，分别经历出生、死亡重生和一次换队；确认无默认/自定义手套重叠、裸手或持续闪烁。
- [ ] 检查 CT M4A4 PaintKit `632`、CT/T P250 PaintKit `258`，并以 AK/AWP 作对照；观察第一人称、丢弃模型、重新装备和重生后的材质。若仍异常，记录插件日志中的 defindex、paint、legacy_model、quality、item_id。
- [ ] 从 Karambit 开始，按 `\\` 走完 Karambit → Butterfly → M9 → Bayonet → Skeleton → Falchion 一圈；成功后至少五圈，核对模型、动画、HUD、active slot 和无地面残留。再跨死亡重生及换队各试一次。
- [ ] 任一切刀失败时，记录日志中的 `detach`、`give`、`ownership`、`econ readiness`、`preset` 或 `equip verification` 阶段，并确认旧刀仍在或原刀已重建且装备；不把“已发出切刀命令”当作成功。

- [ ] Enhanced Bots：Human CT/T 刀、手套、枪械 preset，以及拾取已有武器后应用当前阵营 preset；确认无错误材质或贴图。
- [ ] 快捷切刀按现有顺序至少完整循环 5 圈；型号和皮肤均正确，无 client error、丢刀或残留旧刀。
- [ ] Retakes：初始刀、选择 loadout 后的刀、手套、枪皮，以及换队/换回合后的重新应用。
- [ ] Bot：CT/T agent、枪皮、刀、手套、profile/avatar/Steam identity/fake ping；确认名字、行为、music 保持正常，并记录 BotHider hook status。

- [ ] 针对 CS2 `1.41.8.2` / build `2000913`，在 Windows Local Arena 环境确认 MetaMod 2.0.0-git1406、CounterStrikeSharp 1.0.371、RayTrace 1.0.16 和 BotHider 0.3.3 的实际加载与运行；构建成功不代表该组合已兼容本次 Source 2 更新。
- [ ] BotHider 需单独确认 hook 初始化以及 Bot name、agent、weapon skin、SteamID 行为。[上游 Windows issue #35](https://github.com/XBribo/CS2-Bot-Hider/issues/35) 报告更新后这些功能失效并有 `MaintainBotQuota`、`PackEntities`、`HumanTeamRestriction`、`SameMapTeardown` hook 未解析；issue 未给出明确版本，latest v0.4.4 也早于本次更新。
- [ ] 确认 BotState 在 Deathmatch 中不会因临时 T/CT team number 把存活 Bot 锁到刀具；同时确认 BotController API 14 与随当前 v1.4.3 package payload 的 native DLL 配套加载。
- [ ] [CounterStrikeSharp upstream PR #1432](https://github.com/roflmuffin/CounterStrikeSharp/pull/1432) 针对 Linux gamedata，明确注明 Windows 未变；仍需确认 Windows Local Arena 中 CounterStrikeSharp、BotAI、PlayerKnifeCustomizer 与 Source 2 新 schema / hooks 的实际行为。
- [ ] 快捷刀至少连续 5 个完整循环，观察 client 错误、`MyWeapons`/active slot、模型与动画；失败后确认原刀保留或有界重建，不接受仅有成功聊天提示。
- [ ] 切换过程中死亡、换队、回合结束，确认不操作新 Pawn 或被重用的实体，不留下悬空刀。
- [ ] 回防第一次选枪、重复选择、死亡重生后的刀均正确；确认新刀事件能覆盖绕过 `GiveNamedItem` 的路径。未重建实体、仅原地重置 econ 的引擎路径仍需现场确认。
- [ ] 从默认 `enabled=false`、旧 Preview/Online 状态分别进入 Enhanced bots 和 Match，CT/T 刀枪手套及音乐盒均启用；Normal matchmaking 不加载增强插件。
- [ ] CS2 正常退出及报错退出后 Panel 内容能交互，无 Ghost 窗口；原生 `TaskbarCreated` smoke test 不等同于这一项实机通过。
- [ ] 断网后打开 glove/music picker，192 张本地缩略图正常呈现；任意 Panel 语言下中英文名称、PaintKit、defindex 搜索均有效。

每次完整回归记录日期、CS2 build、MetaMod / CounterStrikeSharp 版本、本项目 commit、测试地图与 Bot 数量、失败项目和复现步骤。需要真实 CS2 进程、WebView2 composition 或视觉判断的结果由用户记录后交回 Agent 复审。
