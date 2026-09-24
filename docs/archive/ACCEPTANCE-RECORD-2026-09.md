# 实机回归记录 — 2026-09

> 历史证据，不是 current truth。本文件保存 2026 年 9 月几轮改动留下的定向实机项和当时的现场事实。
> 长期通用清单见 [`docs/MANUAL-ACCEPTANCE.md`](../MANUAL-ACCEPTANCE.md)。
> 下列项目**全部尚未实机验证通过**；不要因为存在记录就当作已完成。

## 2026-09-23 main 审计后的定向实机项（尚未通过）

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

## 当时的来源

- [docs/archive/MAIN-AUDIT-2026-09-23.md](MAIN-AUDIT-2026-09-23.md)
- [docs/archive/CS2-2026-09-23-COMPATIBILITY.md](CS2-2026-09-23-COMPATIBILITY.md)
- [docs/archive/UPSTREAM-v1.4.4-REVIEW.md](UPSTREAM-v1.4.4-REVIEW.md)
