# Parallel Agent Comparison — Worktree Guide

本文件用于同一基线下比较不同模型 / harness 的实现效果，不是长期产品文档。

## 推荐目录

不要把主 clone 直接放成 `E:\CS2MOD` 自身。为了让多个 worktree 都位于同一个总工作区，推荐：

```text
E:\CS2MOD\
├─ main\          # 主工作树，保持基线 / 用于审查和汇总
├─ wt-agent-a\    # 实验 A
├─ wt-agent-b\    # 实验 B
└─ wt-agent-c\    # 可选更多实验
```

这样可以把 harness 的总 workspace 指向 `E:\CS2MOD`，再在每个 Agent Prompt 中明确分配具体 worktree。若 harness 支持直接把 workspace 指向某个 worktree，则那样更安全。

## 初始创建示例

```powershell
git clone https://github.com/Whatnamed/Local-Arena.git E:\CS2MOD\main
Set-Location E:\CS2MOD\main

git worktree add -b experiment/agent-a E:\CS2MOD\wt-agent-a main
git worktree add -b experiment/agent-b E:\CS2MOD\wt-agent-b main
# 需要第三个时：
git worktree add -b experiment/agent-c E:\CS2MOD\wt-agent-c main

git worktree list
```

每个 worktree 必须使用不同 branch。

## 给每个 Agent 的启动方式

对实验 A：

```text
你的唯一可写仓库是 E:\CS2MOD\wt-agent-a。
所有命令、构建、测试、Git 操作必须在该目录执行。
阅读 temp/prompts/start-local-cosmetics.md 后完整执行 Implementation Plan。
不要读取或复制其他 wt-agent-* 目录里的实现。
```

实验 B / C 只替换路径。

若要公平比较，给不同模型相同的 `PRODUCT-SCOPE.md`、Implementation Plan、初始 commit 和运行权限，不在中途给其中一个模型额外提示，除非你有意测试“模型 + 辅助程度”的组合。

## 并行时不要做的事

多个 worktree 共享同一个 Git object database 和部分 repository metadata，因此并行开发时避免：

- `git gc` / aggressive repack；
- `git worktree prune/remove`；
- 强制删除另一个实验 branch；
- 强制移动公共 refs；
- 从一个实验目录直接复制成品代码到另一个实验目录；
- 两个 Agent 使用同一 branch。

普通 `git fetch`、各自在自己 branch commit / push 一般没有问题，但为了比较稳定，建议开跑前统一 fetch 一次，运行期间不自动 merge upstream。

## 磁盘占用

Git worktree 会共享 `.git` 对象库，因此**源代码历史不会按 worktree 完整复制**。刚创建的额外 worktree 通常主要增加一份 checkout 文件，当前阶段开 2～4 个并不重。

真正会放大占用的是各工作树自己的构建输出，例如：

- `Panel/node_modules`
- `Panel/src-tauri/target`
- .NET `bin/` / `obj/`
- 打包 stage / artifacts

NuGet / npm / Cargo 的全局下载 cache 可以部分共享，但 Tauri / Rust `target`、node_modules 和项目 build output 通常仍会按 worktree 各占一份。进入完整构建阶段后，一个 worktree 从数百 MB 增长到数 GB 都是正常可能性，因此多开实验时主要监控 `src-tauri/target` 和 package artifacts，而不是 Git 本身。

## 比较结果建议

不要只比较 Agent 最后的文字总结。每个实验结束后统一记录：

- branch / HEAD / commit 数量；
- 总 diff 和关键文件；
- 是否严格遵守产品 invariant；
- build/test/package 结果；
- 是否产生超范围改动；
- launch isolation 设计；
- weapon provenance 设计；
- package ownership / updater 处理；
- 代码复杂度、可维护性和上游同步难度；
- 未验证项是否诚实保留给手测。

最后由 `main` 工作树统一审计各 branch；不要让实验 Agent 自己互相评判后直接合并。
