# Local Arena Personal — Implementation Plan

> 2026-09-23 follow-up：旧计划的首轮基线与具体方案已完成，不作为本次故障修复的预设答案。本轮从远端 `main` 的 `e21c7db` 重新审计，范围、现场证据及有限修复见 `docs/MAIN-AUDIT-2026-09-23.md`；实机项仍见 `docs/MANUAL-ACCEPTANCE.md`。

## 0. 任务目标与执行原则

目标：以当前 main 的原始 Local Arena 为长期底座，保留其完整 Panel、Bot、Match、Stats、Local / Preview / Bots / Online 模式和其他现有能力，只完成本轮明确的个人定制与 bug 修复。`docs/PRODUCT-SCOPE.md` 是产品边界；本文件只规定执行顺序、风险和验证。

- 只能写入当前分配的 worktree；本轮固定为 `E:\CS2MOD\main`。
- A/C 只读参考实现思路，B 排除；不整体 merge、cherry-pick 或复制其他 worktree。
- 先审计和建立可构建基线，再修改高风险生命周期、安装和 runtime 代码。
- 不启动 CS2。源码、测试、构建和文件级验证不能冒充游戏内通过。
- 按逻辑边界提交，不制造巨型 commit；无真实 blocker 时自主继续到下一阶段。

## Phase A — 文档和基线事实

1. 先将 `docs/PRODUCT-SCOPE.md`、本计划、`docs/MANUAL-ACCEPTANCE.md` 和直接冲突的辅助文档对齐到完整 personal fork 方向。
2. 记录 cwd、branch、HEAD、status、worktree list，确认当前基线为 `0215561a3bd2f1d4e70b4ce3460fd58f563e09a1`。
3. 审计当前 PlayerCosmetics / PlayerKnifeCustomizer 的事件链、Panel Tauri mode / installer / updater、catalog 和 package inputs。
4. 仅在当前 main 内做源码、历史和静态依赖检查；不读取或使用其他 worktree 的构建产物。

Gate A：能回答当前应用链路、原 Local Arena mode 切换、安装 ownership、updater 入口和 package 组件，且没有把旧 Cosmetics-only 目标继续当作边界。

## Phase B — Panel 现场和可构建基线

1. 若旧 LocalArena.exe / WebView2 进程仍在，先取证进程树、HWND、窗口 placement / visibility / cloaking、single-instance callback、日志和安装目录；取证完成后才按需结束旧进程。
2. 记录 Panel TypeScript、Rust/Tauri、PlayerKnifeCustomizer .NET 和现有脚本的基线测试 / build 结果。
3. 只修复阻塞后续工作的明确环境或基线问题，不在基线阶段做无关重构。

Gate B：现场证据与 main 源码已分开记录；构建 / 测试状态可复现，或明确记录环境 blocker。

## Phase C — Guidelines 配置协调

实现最小、事务式的 `FollowCS2ServerGuidelines` ownership：

- 安装 / 修复 / 本地饰品启动前确保值为 `false`；只修改该 property，保留未知 JSON 字段。
- 不存在时从当前 `core.example.json` 派生；malformed、权限错误和无法安全写入必须 fail closed。
- 记录原文件 / 原 property 状态，restore / uninstall 只按 ownership 恢复。
- 用 Rust fixture 覆盖 preserve、missing、malformed、write failure、already-false 和 restore。

Gate C：配置协调可自动测试，且不复制 A/C 的整套 launch architecture。

## Phase D — 重新发装备与快捷刀

1. 审查 `OnGiveNamedItemPost()` 和现有 generation-safe delayed apply。根据返回实体类型安排 Guns / Knife phase，覆盖回防、特殊模式和 respawn/loadout 重建。
2. 将 phase selection / combination 抽成纯逻辑测试；不增加永久 Tick / Frame polling。
3. 先做小型 knife replacement runtime spike：基于新生成的普通 knife entity，完成目标 subclass / defindex、econ ready、preset / Vanilla apply 后再替换旧刀；保留真实旧刀事实来源和有界 rollback / recreation。
4. 实现默认 `\\` 快捷循环：507、515、508、500、525、512。失败不能跳过位置、丢刀或打印未发生的“保留旧刀”提示。
5. 保持原 Local Arena pickup 语义：有当前阵营 preset 时允许套用，没有 preset 时保持实体状态；不新增 provenance subsystem。

Gate D：PlayerKnifeCustomizer tests 覆盖 phase selection、轮换位置、失败安全和 default fallback；实际模型、动画、音效仍留手测。

## Phase E — 图片和手套中文数据

1. 统计 glove / music / knife / weapon catalog 图片 URL 的状态和总尺寸，不先大规模下载素材。
2. 找出共享远程 Steam CDN 失败的根因，加入可维护的 URL 校验、有限本地 cache 或 UI fallback。
3. 为 gloves / music 增加完整性检查；检查失败要让 build / verification 明确失败。
4. 从可追溯的 CS2 / Steam localization 数据生成或更新手套 Simplified Chinese display name，并让搜索同时覆盖中英文名称、PaintKit 和 defindex。

Gate E：有统计、自动完整性测试和 localization 覆盖率证据；WebView2 实际视觉加载仍留手测。

## Phase F — Updater、文档和最终验证

1. 禁止安装上游 `numakkiyu/Local-Arena` release 覆盖当前 fork；保留只读检查时明确它不会安装 payload。
2. 复核 README / docs / UI 文案，不再把本项目描述成 Cosmetics-only，也不再承诺本轮未实现的 clean launch isolation 或 provenance preservation。
3. 运行 PlayerKnifeCustomizer tests、Panel TypeScript build、Rust tests、.NET build、workspace verification、package、package contents audit 和 forbidden accidental deletion / unrelated diff audit。
4. 所有 artifact 写入 `E:\CS2MOD\main\artifacts\main-personal\`，不创建 GitHub Release、tag 或跨 worktree package。

Gate F：完整 Local Arena runtime 和 UI 仍在 package，目标改动有直接测试证据，CS2 手工项完整列在 `docs/MANUAL-ACCEPTANCE.md`。

## 最终报告

报告 worktree / branch / HEAD、commit 列表、相对初始基线的 diff summary、A/C 仅参考了什么、Bot / Match / Stats 是否保留、快捷刀 lifecycle、回防 phase、guideline ownership、pickup semantics、Panel 现场和修复、图片根因及统计、手套中文覆盖率、updater 行为、所有测试 / build / verify 结果、package 精确路径和 SHA256、仍需 CS2 手测项目，以及最终 `git status --short --branch`。
