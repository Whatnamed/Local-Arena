# Local Cosmetics — Agent Start Prompt

你被分配到一个独立 Git worktree 中执行 Local Cosmetics 开发任务。父工作区可能同时存在其他模型 / harness 的 worktree。

开始后先确认并报告：

- 当前实际 worktree 路径；
- 当前 branch；
- HEAD；
- `git status --short --branch`。

**只能修改当前被分配的 worktree。** 不要写入父工作区其他目录，不要修改兄弟 worktree，不要 checkout / reset 其他实验 branch，也不要执行 `git worktree prune/remove`、`git gc` 等会影响并行实验的仓库级维护操作。

首先完整阅读：

- `AGENTS.md`
- `docs/PRODUCT-SCOPE.md`
- `temp/prompts/local-cosmetics-implementation-plan.md`
- `docs/MANUAL-ACCEPTANCE.md`

严格以 `PRODUCT-SCOPE.md` 作为产品边界，以 Implementation Plan 作为本次执行计划。

先完成 Phase A / B 的 upstream、源码、依赖、构建与现有行为基线审计；不要一开始大规模删除或重写 Local Arena。若没有会改变核心产品边界的真实 blocker，达到 Gate 后自主继续后续阶段，不需要每阶段停下来等待确认。

本任务尤其不能遗漏：

1. 直接从 Steam 启动必须保持普通、未加载本项目 Mod 的 CS2；不能依赖用户先打开 Panel 手动切回 Normal。
2. 只有 Panel 显式启动本地饰品模式时才启用 runtime，并使用 `-insecure`。
3. 玩家自己购买 / 生成 / 明确发放的枪可以应用自己的预设；拾取已有武器实体时不得无条件套用自己的枪皮。
4. 最终 payload 必须是真正 Cosmetics-only，不是完整 Local Arena / Bot Improver 负载仅隐藏 UI。
5. 不重新引入 Enhanced Bot AI、BotRandomizer、NadeSystem、RayTrace、比赛统计等无关 runtime。
6. 实时饰品应用必须事件驱动、有界，不做永久 Tick / Frame 轮询。
7. Local Arena 官方在线更新通道不能覆盖本 fork。
8. 安装 / 清理 / 恢复只能处理明确 owned 的文件；未知第三方内容和用户个人 cfg 默认保留。
9. 保留适用 AGPL-3.0 许可证和 attribution。
10. 不要启动 CS2 做实机验收。你负责源码审计、测试、构建、打包和可自动化验证；需要游戏内确认的项目全部留在 `docs/MANUAL-ACCEPTANCE.md` 给用户手动执行。

允许自主决定低层实现细节，也允许在证据充分时调整 Plan 中非核心的实现建议；但不要自行改变 `PRODUCT-SCOPE.md` 的产品边界。

开发过程中按逻辑阶段提交，避免巨型单提交。任务结束时给出：worktree / branch / HEAD、提交摘要、变更范围、执行过的验证及结果、最终 package 的关键包含 / 排除证据、仍需用户实机验证的项目、已知限制，以及 Git status / push 状态。
