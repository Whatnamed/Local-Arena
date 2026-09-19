# Local Cosmetics — Implementation Plan

## 0. 任务目标与执行原则

目标：以 `Whatnamed/Local-Arena`（fork 自 `numakkiyu/Local-Arena`）为技术基底，将其收敛为一个 Windows 本地 CS2 Cosmetics-only 工具，保留并改进真人玩家枪皮、刀具、刀皮、手套能力，同时建立可靠的“普通 Steam 启动”和“Panel 本地饰品启动”隔离。

`docs/PRODUCT-SCOPE.md` 是产品边界。此 Plan 负责实施顺序和验证，不重新定义产品。

### 执行约束

- 开始时报告当前 worktree、branch、HEAD、Git status。
- 如果父工作区包含多个 worktree，只允许写入被分配的当前 worktree。
- Phase A / B 是强制基线 Gate。没有完成当前源码 / 依赖 / 构建审计前，不大规模删除 Local Arena 模块。
- 无真实 blocker 时，达到一个 Gate 后自主继续下一阶段，不需要每阶段等待用户确认。
- 遇到会改变 `PRODUCT-SCOPE.md` 核心边界的问题才停止并报告。
- 不启动 CS2。所有游戏内行为留给 `docs/MANUAL-ACCEPTANCE.md`。
- 自动化测试、构建、打包、文件级启动隔离测试可以并且应该充分执行。
- 按阶段 / 逻辑边界提交，不制造巨型单提交。

---

# Phase A — Repository / upstream / dependency audit

## Goal

建立当前事实基线，确认从哪个代码状态继续，不依据聊天记忆猜测。

## Required audit

1. 阅读本仓库：
   - `README.md` / `README.zh-CN.md`
   - `docs/PLAYER-COSMETICS.md`
   - `Panel/src/panels/KnifePresetModal.tsx`
   - `GlovePresetModal.tsx`
   - `WeaponPresetModal.tsx` / `WeaponPresetsPanel.tsx`
   - `Panel/src/data/skinLocalization.ts`、`skinNames.json`、`weaponSkins.json`、`gloveSkins*`
   - `Panel/src-tauri/src/mode_files.rs`
   - `mode_layout.rs`
   - `steam.rs`
   - `installer.rs`
   - `install_checks.rs`
   - `online_update.rs`
   - `addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/*`
   - `scripts/build.ps1`
   - `scripts/package.ps1`
   - package / dependency manifests。
2. 对比 `numakkiyu/Local-Arena` 当前默认分支、近期 fork / preview（若确有相关维护分支）和 `ed0ard/CS2-Bot-Improver` 的当前兼容性相关变化。
3. 记录当前：
   - CounterStrikeSharp API package version；
   - MetaMod / CSS 打包来源与固定版本 / hash；
   - signature / native function 使用点；
   - Local Arena 官方 update endpoint / public key；
   - 当前 package 中哪些组件来自完整 Bot Improver payload。
4. 明确 fork 与 upstream 的许可证 / attribution 边界。

## Output

在执行日志 / 最终报告中形成“保留 / 修改 / 删除 / 暂缓”的模块矩阵。不要为了产出文档而复制整个仓库架构。

## Gate A

能够清楚回答：

- 当前玩家饰品数据和应用链路在哪里；
- 当前 Preview / Online 模式实际怎样修改文件；
- 当前 installer / package ownership 边界是什么；
- 哪些 Bot / match 组件和 PlayerCosmetics 真正耦合，哪些只是被整包带入；
- updater 会不会覆盖本 fork；
- 当前 fork 是否能直接进入构建基线。

---

# Phase B — Buildable upstream baseline

## Goal

在功能改造前证明选定基线至少可以构建、测试和打包到可分析状态。

## Work

1. 使用当前仓库约定安装 / 恢复依赖，不随意升级所有依赖。
2. 运行已有：
   - .NET plugin builds/tests；
   - Panel TypeScript build / lint / typecheck（按仓库实际脚本）；
   - Rust / Tauri tests；
   - install-gate tests；
   - packaging dry run / package script（若可在不启动 CS2 的情况下完成）。
3. 记录失败是环境缺失、上游已坏，还是 fork 问题。
4. 只修复阻塞后续开发的明确基线问题；不要在这个阶段顺手重构产品。

## Gate B

- 已有测试 / build 状态可复现；
- 能产出 Panel / PlayerCosmetics 构建结果或明确记录环境 blocker；
- 没有把“未启动 CS2”包装成 runtime 已验证。

---

# Phase C — Launch isolation redesign

## Goal

满足最关键产品 invariant：**用户不打开 Panel，直接从 Steam 启动必须是普通、未加载本项目 Mod 的 CS2。**

Local Arena 当前通过改写 `gameinfo.gi` SearchPath 切模式，并把状态持久留在文件中；该行为不能直接作为最终方案。

## Required spike

先测试 / 论证可行路径，再选实现，不要直接把第一想法写死：

1. 是否能利用独立 launch context / game directory / MetaMod 加载机制，使官方 `gameinfo.gi` 默认永远保持 clean；
2. 如果必须改 `gameinfo.gi`，是否可以：
   - 启动前事务式插入必要 SearchPath；
   - 启动确认后尽早恢复 clean 文件，而不影响当前进程已加载 runtime；
   - 在 Panel crash / launch failure / next-start recovery 中可靠自愈；
3. 任何方案都必须保留 Steam 后续更新写入的新内容，不能用陈旧整文件覆盖。

## Implementation requirements

- `-insecure` 只加入 Panel 发起的 Local Cosmetics 进程参数，不写入永久 Steam Launch Options。
- 建立 journal / state record，写操作原子化。
- 启动前 / 下次 Panel 打开时先处理未完成事务。
- 多次调用应幂等，不重复插 SearchPath。
- 只操作本项目明确拥有的行 / state；保留未知 SearchPath。
- 普通模式不应要求 Panel 做一次“切回 Normal”才能安全。

## Automated tests

至少为纯文件状态机建立 fixture：

- clean -> prepare local -> restore clean；
- prepare 重复执行；
- 中途 journal 存在；
- active file 被 Steam 更新后重新处理；
- unknown SearchPath 保留；
- malformed / missing gameinfo fail closed；
- local launch argument builder 只在 local mode 添加 `-insecure`。

## Gate C

测试从代码层面证明 clean/default 状态和异常恢复设计；真实 CS2 启动行为仍留给用户手测。

---

# Phase D — PlayerCosmetics semantics and weapon provenance

## Goal

修正 Local Arena 当前 `item_pickup` 后可能把枪重新套成玩家预设的行为。

## Desired semantics

- `GiveNamedItem` / purchase / spawn grant 等属于玩家自己的新武器 -> 应用玩家预设。
- 已存在的地面武器被拾取 -> 保持该实体当前外观。
- 玩家自己的枪掉落后再捡 -> 因实体本身已有玩家外观，自然保持。
- 实时修改某枪型预设时，只刷新能够证明属于玩家 preset pipeline 的对应实体，不覆盖未知 / 外来实体。

## Work

1. 审计 `EventItemPickup`、`GiveNamedItem`、spawn、entity-created、knife pickup 的现有 apply pipeline。
2. 设计最小 provenance / ownership 记录：以实体 identity / handle / generation-safe key 为基础，避免只按 DefIndex 判断。
3. 明确 entity destruction、round transition、disconnect 时的清理。
4. 刀具与枪械分开处理；不要为修枪皮破坏已有 `ChangeSubclass` 刀逻辑。
5. 保留对短暂实体转换的 bounded retry，禁止永久扫描。

## Tests

尽量把 policy 抽成可测试纯逻辑：

- new owned entity -> apply；
- unknown picked entity -> preserve；
- owned dropped/re-picked entity -> preserve existing appearance / still considered owned only where safe；
- destroyed entity -> provenance removed；
- same DefIndex but different entity -> no state leak；
- generation / handle reuse -> no old ownership leak。

## Gate D

代码路径中不再存在“所有 `item_pickup` 无条件重新应用玩家枪皮”的行为，并有测试覆盖核心 provenance policy。

---

# Phase E — Event-driven live cosmetic reload

## Goal

Panel 在游戏运行期间保存配置后，插件能在安全时机重应用相关饰品，而不是依赖下一次 spawn 或永久轮询。

## Design

推荐流程（可根据现有架构调整）：

Panel save -> atomic replace -> plugin watcher / equivalent event -> 100–250 ms debounce -> parse / validate -> diff last valid config -> schedule on game thread -> apply changed section only。

## Requirements

- 不每 Tick / Frame 读 JSON。
- 防止 FileSystemWatcher 常见的重复事件。
- 配置写入使用 temp + replace 或现有 atomic fs 机制。
- JSON 暂时无效时保留 last-known-good config。
- schema / PaintKit / wear validation 失败只拒绝该次更新并记录日志。
- 只有发生变化的 section 执行 apply：
  - knife -> knife；
  - glove -> gloves / bodygroup；
  - one gun preset -> eligible owned matching entities；
  - 其他区域不重复写。
- Entity 处于短暂不可用状态时只做有界 retry。

## Tests

- duplicate file events collapse；
- invalid JSON 不替换 last valid config；
- identical config 不产生 apply；
- diff 能识别 knife / glove / gun；
- watcher lifecycle unload 后不再触发；
- debounce 不积累无限任务。

## Gate E

源码和测试证明实时机制是事件驱动、有界的；视觉即时刷新仍由用户实机确认。

---

# Phase F — UI, Simplified Chinese, ordering and knife shortcuts

## Goal

在保留 Local Arena 现有饰品信息架构的前提下改善用户实际使用体验。

## F1 — Preserve cosmetics UI

- 保留枪皮、刀具、手套现有产品比重。
- 不为了“刀更常用”把枪皮藏进深层二级页面。
- 与 Bot / match 有关的页面在 Cosmetics-only 裁剪阶段再移除。

## F2 — Simplified Chinese and search

- 保留 `schinese` UI。
- 审计 `skinNames.json` / glove naming 对常见条目的覆盖。
- 配置仍使用 ID，不使用本地化名称作 key。
- 中文界面显示可靠中文名称；缺失时 English -> ID fallback。
- 搜索至少支持当前语言；若现有数据允许，增加英文 alias，使中文 UI 搜 `Blue Steel` 也能命中。
- 支持 PaintKit / numeric ID 搜索。

## F3 — Knife / finish ordering

- 刀型默认顺序按 `docs/PRODUCT-SCOPE.md`。
- 深色 / 中性 finish 的优先展示通过独立 preference metadata / sort policy 实现，不修改 canonical compatibility catalog。
- 完整 compatible catalog 永远可见。

## F4 — Knife shortcut

- 新增 CounterStrikeSharp command（名称按现有命名规范决定）循环 configured shortcut knives。
- 默认：Karambit -> Butterfly -> M9 -> Bayonet -> Skeleton -> Falchion。
- 直接切当前刀 / 默认刀 preset，不生成地上一堆刀。
- 使用每把刀自己的已有 preset。
- 绑定是 opt-in。
- 如果无法可靠保存 / 恢复用户原 bind，优先提供可复制 bind 命令或只管理明确属于本项目的 cfg，不做破坏性覆盖。

## Gate F

- 枪械 UI 未被无理由降级；
- 中文 common entries 和搜索通过数据级 / UI 测试；
- 快捷刀关闭时对键位零影响；
- 排序不破坏 catalog compatibility。

---

# Phase G — True Cosmetics-only product and package

## Goal

把最终产物从“完整 Local Arena + Preview 禁用 Bot”变成真正只包含饰品所需 runtime 的产品。

## Work

1. 先做依赖图，不先删文件。
2. 从 Panel 导航 / routes / state 中移除与 Bot、比赛、统计、Demo、队伍等无关的产品页面和设置。
3. 保留安装、恢复、诊断中对 Cosmetics-only 必需的部分。
4. 重写 `scripts/package.ps1` 的核心策略：不要先复制整套 Bot Improver payload 再删除；优先显式 allowlist 所需组件。
5. 最终 package 目标只包含：
   - MetaMod；
   - CounterStrikeSharp；
   - PlayerCosmetics（或重命名后的插件）；
   - cosmetics data / localization / config；
   - Panel；
   - minimal installer / restore / diagnostics runtime；
   - 必须的 license / attribution。
6. 不应包含：BotAI、BotAimImprover、BotBuy、BotRandomizer、NadeSystem、RayTrace、BotHider、bot profile、lineup、match coordinator、rating、telemetry、stats/demo runtime。
7. 同步更新：
   - build scripts；
   - package manifest；
   - installer ownership；
   - install checks；
   - repair / restore；
   - diagnostics component list。

## Automated package gate

增加明确的 allowlist / denylist assertion：如果 forbidden Bot / match component 重新出现在 release archive，则 packaging 失败。

不得把陈旧 `gameinfo.gi` 随包分发。

## Gate G

对最终 archive 做文件级审计，证明它本身就是 Cosmetics-only，而不是运行时开关隐藏完整 Bot 负载。

---

# Phase H — Installer, legacy cleanup, restore ownership

## Goal

支持用户当前旧 Bot Improver 环境，同时保证不会误删未知第三方 / 个人配置。

## Environment classes

至少识别：

- clean CS2；
- 本项目 managed install；
- recognizable Local Arena；
- recognizable upstream Bot Improver；
- mixed / unknown third-party environment。

## Cleanup rules

- 只删除有 manifest / hash / known path 证据的 owned legacy files。
- 未知第三方插件保留并提示。
- 用户 cfg / autoexec / bind 默认保留。
- Steam Verify Integrity 只是恢复官方文件的一步，不作为“会删掉第三方文件”的假设。
- mixed / unknown 状态 fail closed，提供诊断，不猜测清理。

## Restore rules

- 有有效事务备份时恢复原官方文件。
- 删除本项目明确新建的 managed files。
- 玩家饰品预设放在不会被 repair/update 擦除的位置。
- restore / repair 尽量幂等。

## Tests

文件系统 fixture 覆盖：clean install、managed update、known Local Arena migration、known Bot Improver migration、unknown plugin preserved、personal cfg preserved、interrupted install recovery、restore 后无 project-owned launch state。

## Gate H

ownership boundary 比原完整 Local Arena 更窄，并被自动化测试覆盖。

---

# Phase I — Update channel and upstream maintenance

## Goal

防止 Local Arena 官方在线更新逻辑把本 fork 覆盖回 upstream binary / payload。

## Work

1. 找到所有 `numakkiyu/Local-Arena` signed update manifest / executable update 路径。
2. v1 优先关闭实际安装上游更新的能力，而不是临时做一个无签名自更新器。
3. 可以保留只读版本 / 兼容信息，但不能点击后安装官方 Local Arena package。
4. upstream 同步通过 Git 审查后 merge / cherry-pick，不做整包自动覆盖。
5. 保留许可证和来源说明。

## Gate I

用户在 shipped Panel 中没有任何路径能把官方 Local Arena Panel / plugin payload 当成“本项目更新”覆盖安装。

---

# Phase J — Automated final verification

## Goal

完成所有不需要启动 CS2 的验证。

## Required checks

运行仓库实际支持的等价项：

- relevant .NET builds；
- PlayerCosmetics / PlayerKnifeCustomizer tests；
- Rust / Tauri tests；
- TypeScript build / lint / typecheck；
- install gate / filesystem tests；
- packaging；
- package allowlist / denylist assertions；
- repository-wide search：stale update URL、stale product naming、forbidden runtime、无效 mode branch；
- license / attribution presence；
- Git diff / status review。

## Source-level acceptance

从代码 / 测试证明：

- local launch 才构造 `-insecure`；
- ordinary Steam usage 不依赖 Panel 先切 Normal；
- pickup 不再无条件应用玩家枪皮；
- 无永久高频 cosmetic polling loop；
- package 不含 Enhanced Bot runtime；
- Local Arena 官方 updater 不会覆盖 fork；
- user cfg / unknown third-party cleanup 不是 broad delete。

## Manual-only items

不得自动标记为通过：

- 实际刀模型 / 动画 / HUD；
- 手套 bodygroup；
- 捡枪视觉保持；
- 实时视觉刷新；
- FPS / frametime；
- 真实 Steam 直接启动行为；
- 涉及真实 CS2 进程的 crash recovery。

确保这些都在 `docs/MANUAL-ACCEPTANCE.md`。

## Final report

完成后报告：

- worktree path / branch / HEAD；
- 分阶段 commit；
- 主要变更与删除范围；
- 所有执行过的 build/test/package 命令和结果；
- 最终 package 的关键 include / exclude 证据；
- 未执行的实机项目；
- 已知限制 / 风险；
- Git status；
- 是否 push，以及远端 branch。

达到上述范围后应收口。不要因为发现低收益理论优化而无限继续 audit -> fix -> audit。
