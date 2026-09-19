# Project-specific agent rules

本文件只记录本项目相对于全局 `AGENTS.MD` 的额外规则。全局沟通、Git、Agent 与工具约定不在这里重复。

## Canonical sources

- `docs/PRODUCT-SCOPE.md` 是产品定位、用户行为和功能边界的 canonical source。实现不得自行改变其中的硬约束。
- 当前主任务的阶段、风险、验证方法和 Gate 以 `temp/prompts/local-cosmetics-implementation-plan.md` 为准。
- 需要启动 CS2 才能确认的行为统一留给 `docs/MANUAL-ACCEPTANCE.md`，coding agent 不得把未实机验证的项目标记为已通过。
- Local Arena、CS2-Bot-Improver、MetaMod、CounterStrikeSharp 的当前事实必须以当前源码、Git 历史、构建产物和必要的官方资料为依据；旧聊天或记忆只用于定位背景。

## Worktree isolation

本项目可能同时由多个模型 / harness 在不同 Git worktree 中并行执行。

- 每个 Agent 只能写入明确分配给自己的 worktree，所有 shell、构建、测试、格式化和 Git 操作都必须以该 worktree 为 cwd。
- 工作区父目录可能同时包含 `main` 与多个实验 worktree；不要把父目录误当成仓库根目录，也不要修改兄弟 worktree。
- 每个 worktree 使用独立 branch；不要尝试让两个 worktree checkout 同一 branch。
- 未经用户要求，不执行 `git worktree remove/prune`、`git gc`、强制移动其他 branch/ref、跨 worktree reset/clean 等仓库级维护操作。
- 不自动 cherry-pick、merge 或复制另一个实验分支的实现。并行比较阶段必须保持实现独立；需要汇总时由用户明确指定。
- 任务开始和结束都报告：worktree 路径、branch、HEAD、Git status。

## Upstream and ownership

- 主基底：`numakkiyu/Local-Arena`。
- 参考上游：`ed0ard/CS2-Bot-Improver`。
- 不直接修改 upstream；只在 `Whatnamed/Local-Arena` 的分支 / worktree 中开发。
- 保留适用的 AGPL-3.0 许可证、版权、来源和 attribution。裁剪功能、重命名或重新打包时不得删除应保留的许可证与署名。
- 未经审计，不复制来源不明或许可证边界不清的第三方实现。

## Product invariants

- 本项目是本地 / 离线 CS2 饰品工具，不是增强 Bot 项目、公共 skin server 或游戏内 Overlay。
- 用户不打开 Panel、直接从 Steam 启动 CS2 时，必须保持普通、未加载本项目 Mod 的状态；不能要求用户先在 Panel 中“切回 Normal”。
- 只有用户显式从本项目 Panel 启动本地饰品模式时，才允许启用本项目 runtime，并使用 `-insecure`。
- 最终 Cosmetics-only payload 不得重新引入 Enhanced Bot AI、BotRandomizer、NadeSystem、RayTrace、比赛统计等与饰品无关的运行组件。
- 自己购买、出生发放或本项目明确创建的武器可以应用玩家预设；拾取已有武器实体时不得无条件套用自己的枪皮。
- 实时饰品同步必须优先采用有界事件与配置变更驱动，不允许永久 Tick / Frame 轮询扫描配置或 Inventory。
- 不添加常驻游戏内 UI。快捷换刀键是可选功能，未启用时不得改写用户键位。
- 未知第三方文件、用户个人 cfg / autoexec / bind 不得被清理、覆盖或纳入本项目 ownership boundary。

## Development discipline

- 先审计、建立可构建基线，再改动。不得在未确认当前上游结构和构建状态的情况下大规模删除模块。
- 启动隔离、安装 / 恢复、payload ownership、在线更新通道属于高风险区域。修改前优先补可重复的文件级 / 单元测试夹具。
- 对 CS2、MetaMod、CounterStrikeSharp、signature / native API 的兼容性结论必须有当前证据，不能仅由版本号猜测。
- Coding agent 不自动启动 CS2。Agent 负责源码审计、单元测试、构建、打包、静态检查和可自动化验证；游戏内行为由用户按 `docs/MANUAL-ACCEPTANCE.md` 手动验收。
- 不制造巨型单提交。按阶段或逻辑边界提交，并在提交信息中写清变更摘要。
- 如果实现需要改变 `docs/PRODUCT-SCOPE.md` 中的产品边界、引入新的高风险依赖或与既定核心行为冲突，应停止该方向并明确报告，而不是自行重新定义需求。
