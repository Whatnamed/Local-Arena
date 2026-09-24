# Project-specific agent rules

本文件只记录本项目相对于全局 `AGENTS.MD` 的额外规则。全局沟通、Git、Agent 与工具约定不在这里重复。

本文件只放长期稳定、与具体任务无关的规则。当前主任务、当前 baseline、当前 bug 状态和阶段性 Gate 不写在这里；`docs/` 的类别划分见 `docs/README.md`。

## Canonical sources

- `docs/PRODUCT-SCOPE.md` 是产品定位、模式、用户行为和功能边界的 canonical source。实现不得自行改变其中的硬约束。
- `docs/UPSTREAM.md` 描述 upstream 同步政策；runtime dependency 的精确 pin 以 `scripts/dependencies.json` 为唯一 machine-readable source，其他文档不再手工复制版本号。
- `docs/MANUAL-ACCEPTANCE.md` 是长期实机验收清单。需要启动 CS2、观察 WebView2 或做视觉判断的行为统一留在那里，coding agent 不得把未实机验证的项目标记为已通过。
- 开发、构建和验证入口见 `CONTRIBUTING.md`。
- Local Arena、CS2-Bot-Improver、MetaMod、CounterStrikeSharp 的当前事实必须以当前源码、Git 历史、构建产物和必要的官方资料为依据；旧聊天或记忆只用于定位背景。
- `temp/` 是 task-local 交接区，不进入 Git，也不具备任何 canonical 权威。

## Worktree isolation

本项目可能同时由多个模型 / harness 在不同 Git worktree 中并行执行。

- 每个 Agent 只能写入明确分配给自己的 worktree，所有 shell、构建、测试、格式化和 Git 操作都必须以该 worktree 为 cwd。
- 工作区父目录可能同时包含 `main` 与其他 worktree；不要把父目录误当成仓库根目录，也不要修改兄弟 worktree。
- 每个 worktree 使用独立 branch；不要尝试让两个 worktree checkout 同一 branch。
- 开始和结束都报告：worktree 路径、branch、HEAD、Git status。
- 未经用户要求，不执行 `git worktree remove/prune`、`git gc`、强制移动其他 branch/ref、跨 worktree reset/clean 等仓库级维护操作。
- 不自动 cherry-pick、merge 或复制另一个实验分支的实现。并行比较阶段必须保持实现独立；需要汇总时由用户明确指定。
- 仓库存在未提交的进行中工作时，另建独立 branch 进行维护类改动，不与该工作混合提交。

## Upstream and ownership

- 主基底：`numakkiyu/Local-Arena`；当前 fork：`Whatnamed/Local-Arena`。
- 参考上游：`ed0ard/CS2-Bot-Improver`。
- 不直接修改 upstream；只在 `Whatnamed/Local-Arena` 的分支 / worktree 中开发。
- 保留适用的 AGPL-3.0 许可证、版权、来源和 attribution。裁剪功能、重命名或重新打包时不得删除应保留的许可证与署名。
- 未经审计，不复制来源不明或许可证边界不清的第三方实现。

## Engineering guardrails

以下是最容易被无意破坏、且不属于单一任务阶段的硬约束；完整产品边界仍以 `docs/PRODUCT-SCOPE.md` 为准。

- 不添加常驻游戏内 UI、Overlay，不修改原生 HUD 或 Buy Wheel。
- 实时饰品应用保持事件与配置变更驱动，不引入永久 Tick / Frame 轮询扫描配置或 Inventory。
- 未知第三方文件、用户个人 cfg / autoexec / bind 不得被清理、覆盖或纳入本项目 ownership boundary。
- `.csbip`、`cs2bi.*` localStorage / state key、`PlayerKnifeCustomizer` 目录与程序集名等旧标识属于兼容性与升级依赖，不得仅因名称过时而批量重命名。

## Development discipline

- 先审计、建立可构建基线，再改动。不得在未确认当前结构和构建状态的情况下大规模删除模块。
- 启动隔离、安装 / 恢复、payload ownership、更新通道属于高风险区域。修改前优先补可重复的文件级 / 单元测试夹具。
- 对 CS2、MetaMod、CounterStrikeSharp、signature / native API 的兼容性结论必须有当前证据，不能仅由版本号猜测。
- Coding agent 不自动启动 CS2。Agent 负责源码审计、单元测试、构建、打包、静态检查和可自动化验证；游戏内行为由用户按 `docs/MANUAL-ACCEPTANCE.md` 手动验收。
- 不做与当前任务无关的重构、格式化、依赖升级或跨 worktree 清理。
- 不制造巨型单提交。按阶段或逻辑边界提交，并在提交信息中写清变更摘要。
- 如果实现需要改变 `docs/PRODUCT-SCOPE.md` 中的产品边界、引入新的高风险依赖或与既定核心行为冲突，应停止该方向并明确报告，而不是自行重新定义需求。
