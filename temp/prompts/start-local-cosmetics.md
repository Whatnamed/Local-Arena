# Local Arena Personal — Agent Start Prompt

你被分配到 `E:\CS2MOD\main` 执行 Local Arena personal fork 的开发任务。父工作区可能同时存在其他模型 / harness 的 worktree。

开始后先确认并报告当前实际 worktree 路径、branch、HEAD、`git status --short --branch` 和 `git worktree list`。

只能修改当前 worktree。不要写入、复制、删除或清理 `wt-agent-a`、`wt-agent-b`、`wt-agent-c`，不要执行 `git worktree prune/remove`、跨 worktree `clean/reset`、`git gc`、删除实验 branch 等操作。

严格以 `docs/PRODUCT-SCOPE.md` 作为产品边界，以 `temp/prompts/local-cosmetics-implementation-plan.md` 作为执行计划。当前方向是保留原始 Local Arena 的完整 Panel、Bot、Match、Stats、Local / Preview / Bots / Online 模式和其他现有功能；不要重新实现 Cosmetics-only 产品。

本轮尤其不能遗漏：

1. 先调查可能残留的 Panel / WebView2 窗口现场，再决定是否结束旧进程；区分现场证据与 main 源码。
2. `FollowCS2ServerGuidelines` 只做可靠、事务式的 property 协调，不整文件覆盖 `core.json`。
3. `OnGiveNamedItemPost()` 覆盖枪械和刀具 phase，处理回防、特殊模式和 respawn/loadout 重新发装备。
4. 新增失败安全、有界的 `\\` 快捷换刀；默认循环 Karambit、Butterfly、M9、Bayonet、Skeleton、Falchion。
5. 保留原 Local Arena 的 pickup 语义：有当前阵营 preset 时可以应用自己的 preset，没有 preset 时保持实体状态；不要引入 provenance subsystem。
6. 修复 glove / music 等 picker 图片完整性、fallback 和手套 Simplified Chinese localization。
7. 禁止应用内 updater 把官方 `numakkiyu/Local-Arena` release 覆盖本 fork；只读检查可以保留。
8. 不整体搬入 A/C 的 hidden Bots、临时 launch isolation、provenance 或生命周期架构；B 分支排除。
9. 不启动 CS2；所有游戏内、窗口视觉和实际 WebView2 结果留给 `docs/MANUAL-ACCEPTANCE.md`。
10. 保留 AGPL-3.0、来源和 attribution，按逻辑边界提交。

开发过程中优先运行能直接证明本次改动正确的测试和 build。最终报告 worktree / branch / HEAD、commits、变更摘要、原能力保留情况、关键行为实现、现场调查、图片统计、localization 覆盖率、updater 行为、所有验证结果、main 专属 package 路径与 SHA256、Manual Acceptance 未验证项和最终 Git status。
