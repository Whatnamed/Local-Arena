# Cosmetics-only Baseline Audit

Phase A 输出：当前事实基线与"保留 / 修改 / 删除 / 暂缓"模块矩阵。只记录会影响裁剪与重构决策的事实，不复制仓库架构。

## 1. 基线位置

- fork `Whatnamed/Local-Arena`（parent `numakkiyu/Local-Arena`），`origin` = fork。
- 代码 HEAD 与 upstream `main` 完全一致：upstream HEAD `81a71004`（2026-08-11）= 本仓 `81a7100`；其上只有 6 个文档 commit。
- 结论：本 fork 没有任何实现层改造，Phase B 之后的所有产品代码都是新工作。

## 2. 上游当前事实（2026-09-19 实测）

| 来源 | 当前状态 | 对本项目的影响 |
| --- | --- | --- |
| `numakkiyu/Local-Arena` | `main` @ `81a71004`，最新 release `v1.4.3.3` | 已同步，无待合入 delta |
| `ed0ard/CS2-Bot-Improver` | release `v1.4.4`（2026-09-04），含 "Sigs & offsets updates" | `scripts/dependencies.json` 仍 pin `v1.4.3`。Cosmetics-only 后整包 Bot payload 退出，v1.4.4 的 smoke/fake-defuse/roster 变化不再相关；其 sig 刷新只作为将来参考，不自动吸收 |
| CounterStrikeSharp | 最新 `v1.0.374`（2026-09-07） | pin `v1.0.371`；升级属于独立依赖审计，不在本次范围 |
| MetaMod | pin `2.0.0-git1406`（`mmsource-*-windows.zip`） | 上游无 GitHub releases，继续以 `dependencies.json` 的 sha256 为准 |

所有 pin 都带 SHA-256（`scripts/dependencies.json`），由 `build.ps1` / `package.ps1` 的 `Get-VerifiedAsset` 校验。

## 3. Gate A 六问

**Q1 玩家饰品数据与应用链路在哪里**

- 配置：`<csgo>/addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json`（`lib.rs:2027`）与同目录 `player_gun_presets.json`（`lib.rs:2031`）。Panel 侧镜像在 `<state>/presets/current/`（`app_storage.rs:169`）。
- 读写：Rust `get_knife_customizer` / `save_knife_customizer`（`lib.rs:2687`、`lib.rs:2704`）→ 前端唯一写入口 `api.saveKnifeCustomizer`（`Panel/src/lib/api.ts:728`），类型 `KnifeCustomizerConfig`（`api.ts:278`，`schema_version: 5`）。
- 应用：`PlayerKnifeCustomizer.cs` 的 `ApplyPreset`（`:552`）通过内联 hex 签名的 `MemoryFunctionVoid` 写 `set item texture prefab/seed/wear`（`:635-641`）。事件入口：`PlayerSpawn`/`RoundMvp`/`ItemPickup`/`PlayerDeath`/`PlayerTeam`/`PlayerDisconnect`/`RoundEnd` + `OnMapStart/End` + `GiveNamedItemFunc` post hook（`:239-248`）。
- **插件与 Bot 层零代码耦合**：`PlayerKnifeCustomizer.csproj` 唯一 `PackageReference` 是 `CounterStrikeSharp.API 1.0.371`，不引用 `BotControllerApi` / `MatchCore` / `BotHiderApi`。它是被整包打包带进来的，不是被 Bot 依赖拖进来的。

**Q2 Preview / Online 模式实际怎样改文件**

- `gameinfo.gi`：逐行改写（不是整文件覆盖）。`rewrite_gameinfo`（`mode_files.rs:54`）删掉 `Game csgo/addons/metamod` 与 `Game csgo/overrides/botprofile.vpk` 两行，非 Online 时在主 `Game csgo` 行前按原缩进插回；写入用 `atomic_fs::write_replace` + 回读校验 + 4 条不变式断言（`mode_files.rs:111-143`）。
- 插件/cfg/vpk：`mode_layout::apply_layout`（`:68`）按 `MANAGED_FILES`（19 项，`mode_layout.rs:8-28`）逐个 rename 成 `<name>.csbip-disabled`。
- **致命点：状态被持久留在文件里。** Online 与非 Online 的差别就是 `gameinfo.gi` 里那两行在不在；用户不打开 Panel 从 Steam 启动时，如果上次停在非 Online，MetaMod 仍会加载。这直接违反 `PRODUCT-SCOPE.md:119`。
- Preview 与 Bots 的 `gameinfo.gi` 内容完全相同（`mode_files.rs:106-110`），两者只差 `MANAGED_FILES` 的 rename 方向。
- **`MANAGED_FILES` 不含 `PlayerKnifeCustomizer`** → 饰品插件在三种模式下永远 active，隔离靠 JSON 里的 `enabled` 布尔（`enforce_mode_cosmetics`，`lib.rs:2669`），双 `cosmetics_enabled_before_*` 字段记录恢复值。这是崩溃不安全的补偿机制，不是真隔离。
- 模式判定是三方派生：`gameinfo.gi` 文本 + `mode_layout::is_preview()` + `config.mode`（`mode_at`，`lib.rs:1039-1074`），`pending` 标志用来掩盖三者发散。
- `mode_layout` 已有事务原语可复用：journal → apply → active.json → 删 journal，加幂等 `recover()`（`mode_layout.rs:163-210`）。
- 启动：`launch_cs2`（`lib.rs:1138`）→ `steam.exe -applaunch 730 -insecure -console`（`launch_request`，`lib.rs:1126`）。`steam.rs` 不负责启动，只做目录发现和 Steam 空闲判定。`reconcile_launch_options`（`lib.rs:1095`）是 `-> u32 { 0 }` 死代码。**Steam Launch Options 从未被读写**，`-insecure` 只在 Panel spawn 的参数里，这一点已符合要求。

**Q3 installer / package ownership 边界**

- installer 事务骨架是全仓最完备的一块：per-target 独占锁 + `journal.json` + `transaction-<ts>/` 回滚暂存 + `original/` 基线 + `record.json` 归属清单（含 `original_sha256` / `ownership` / `restore_policy`）+ 失败自动 rollback（`installer.rs:958-1234`、`905-956`、`376-389`）。归属证据不足时只删 `ownership == "plus"` 且 sha256 匹配的文件（`installer.rs:1321-1336`）——这个保守策略要保留。
- 安装前置：`ensure_target_not_running` + `ensure_steam_app_idle`（`lib.rs:679-699`），CS2 运行时拒绝写。
- package 边界（`scripts/package.ps1`）：**当前是"整包复制上游再删"**。`:132` 把上游 `CS2BotImprover.zip` 的完整 payload `Copy-Tree` 进 release 根目录，之后只删 `Panel*.exe`（`:133`）、`gameinfo.gi`（`:138-142`）、`BotHider.linux.vdf`（`:186`）、`BotHiderImpl/shared`（`:297`）。BotAI/BotBuy/NadeSystem/RayTrace/BotHider/MatchCoordinator/Telemetry 全部是被复制进来的。违反 `PRODUCT-SCOPE.md:155`。
- **仓库中没有任何包边界 allowlist/denylist 断言**（`allowlist` 一词在 `package.ps1` 只出现在 `:237` 的 telemetry 目录内部文件集）。
- `gameinfo.gi` 不进包：`package.ps1:138-142` 递归删 + `verify-workspace.ps1:584` 断言不存在。这条已经合规，必须保留。
- `scripts/verify-workspace.ps1:472-519` 把 47 个 bot/rating/telemetry 路径列为 **required**，`:711-745` pin 了 RayTrace/BotHider/BotController DLL 的 sha256 → 包收敛必须先反转这个清单，否则 `package.ps1:384` 直接失败。
- Git 跟踪的二进制只有 8 个 `botprofile.db`；**0 个 dll/so/vpk/zip/exe 被提交**，所有第三方 payload 只在运行期 `.cache/` 存在。包边界可以纯靠脚本收敛，不需要 history 重写。另有 31MB `overrides/archived/localizations/*.txt` 被跟踪（不进包，但进 clone）。

**Q4 哪些 Bot/match 组件与 PlayerCosmetics 真正耦合**

真实耦合：**无源码级耦合**。仅存在以下打包/数据面连带：

- `scripts/generate-player-cosmetic-placements.mjs:7-9` 的输入源在 `BotRandomizer/cosmetic_catalog.json` 与 `charm_placements.json` → 这两个数据文件必须在裁剪前先搬到 cosmetics 自有目录，否则 catalog 无法再生成。
- `package.ps1:245-246` 会把 `BotRandomizer/cosmetic_catalog.json`、`charm_placements.json` 当数据打进包。
- Panel 侧 `mode_layout::MANAGED_FILES` / `installer` 的 bot 条目 / `install_checks.rs:210-283` 的 bot 组件检查项 / `mode_files` 的 `botprofile.vpk` 逻辑，都是"共用同一套机制"而不是依赖 Bot 行为。

只是被整包带入：BotAI、BotAimImprover、BotBuy、BotControllerImpl、BotHiderImpl、BotRandomizer、BotState、NadeSystem、RoundDamageRecap、TeamLineupInjector、PlusMatchCoordinator、OfflineMatchTelemetry、shared/BotControllerApi、shared/BotHiderApi、shared/MatchCore、RayTrace、`overrides/*`、`cfg/my_bot_*`。

**Q5 updater 会不会覆盖本 fork**

**会。** `online_update.rs:13-15` 硬编码 `github.com/numakkiyu/Local-Arena/releases/latest/download/latest.json`，验签公钥内嵌在 `online_update.rs:16`（同一把在 `scripts/update-public-key.txt`），而 `package.ps1:421-426` 也用同一 repo 生成 `latest.json` + `.sig`。链路：`update_core.rs:105` schema 校验 → `:127` https+github 域白名单 → `:154` ed25519 验签 → `online_update.rs:452` sha256 → `update_core.rs:281` zip-slip/bomb 防护 → `prepare_panel`/`schedule_panel_replace`（`online_update.rs:566-652`）替换 Panel 自身，`activate_payload`（`:716`）切换 plugin payload。

即：点一次"全部更新"（`install_all_updates`，`lib.rs:3042`；UI 入口 `Panel/src/panels/settings/OnlineUpdatePage.tsx:48`）就会把 upstream 完整 Bot payload 装回来。而且 `lib.rs:4113` 在启动时静默 check。私钥不在本 fork 手里，所以不能靠换 URL 解决——必须按 `PRODUCT-SCOPE.md:196` 关闭安装路径。

**Q6 当前 fork 能否直接进入构建基线**

仓库约定完整（`scripts/build.ps1` 一条命令跑 npm + 11 个 csproj + 2 个测试工程 + cargo test + release build），但本机缺：.NET SDK（只有 6/7/8 runtime，插件要 `net10.0`）、`cargo-xwin`、LLVM（`build.ps1:148-161` 会 throw）、`.local-build.ps1`（`verify-workspace.ps1:51-54` 在非 CI 下要求存在）。MSVC 14.43 + Windows SDK 10.0.22621 已具备。`Panel/node_modules` 已通过 `npm ci` 恢复。

## 4. 模块矩阵

判定基准：`PRODUCT-SCOPE.md §7` 的 Cosmetics-only payload 边界。

| 模块 | 判定 | 依据 / 处理方式 |
| --- | --- | --- |
| `PlayerKnifeCustomizer`（1715 行，1 插件） | **修改** | 本体保留。改名/重命名目录要连带 `MANAGED_FILES`、`installer` 标记、`package.ps1`；本次保留物理路径（`PLAYER-COSMETICS.md:19` 说明保留是为了 copy-over 升级兼容），只重构内部行为（provenance、watcher、快捷刀命令、Wear 校验） |
| `PlayerKnifeCustomizer.Tests`（278 行 / 67 断言，顶级语句 + `Require()`） | **保留 + 扩充** | 已是纯逻辑、无 CS2 依赖，provenance 与 diff 策略测试直接加在这里 |
| `mode_files.rs` | **重写** | 三态 `LaunchMode` → 二态；删 `botprofile.vpk` 逻辑；改为"持久状态恒 clean + 启动窗口事务" |
| `mode_layout.rs` | **删除（合并）** | Cosmetics-only payload 里没有需要 rename 的 bot 文件，`MANAGED_FILES` 机制失去对象；其 journal 事务形态迁移到新的启动事务模块 |
| `steam.rs` | **保留** | 目录发现 + Steam 空闲判定是安装/启动前置，cosmetics 需要 |
| `installer.rs`（2299 行） | **修改** | 保留事务骨架与 `record.json` ownership 判定；删 `UPSTREAM_MARKERS`/`SUITE_OWNED_*` 的 bot 项（`:22-82`）、`SUPERSEDED_PAYLOAD_PATHS`；`install_checks.rs` 组件清单重写 |
| `install_checks.rs` | **修改** | `:210-283` 的 bot/RayTrace/BotHider/match 组件项整段替换为 cosmetics 清单；当前只有 1 个测试，是覆盖最薄的一块，需要补 fixture |
| `online_update.rs` + `update_core.rs` | **删除（关闭）** | 按 Phase I：保留只读版本提示，切断任何安装路径 |
| `cs2ss_bridge.rs`（1530 行） | **删除** | 纯 telemetry/战绩，只依赖 rusqlite |
| `match_system.rs`（940 行） | **删除** | 纯比赛会话 |
| `diagnostics.rs` | **修改** | 保留 cosmetics/install/mode 部分，删 mount/match/WER/demo 部分 |
| `atomic_fs.rs` / `app_storage.rs` / `runtime_state.rs` / `logging.rs` / `app_version.rs` | **保留** | 启动事务与配置镜像的底座 |
| `appearance.rs` | **暂缓** | 与饰品无关但不危害边界；Phase G 视包大小决定 |
| `lib.rs` 中 bot/match/demo/timescale/difficulty 命令（约 30 个） | **删除** | 见 `lib.rs:1727-1980`、`1165-1640` 分类 |
| `Panel/src/panels/`：Stats*(4)、Match*(3)、PresetsPanel、BotItemsPanel、TeamsSection、ModeCard、DifficultyCard | **删除** | 其中 `BotItemsPanel.tsx`、`TeamsSection.tsx`、`StatsPlayerDetail.tsx` 已是无 importer 孤儿 |
| `Panel/src/panels/CommandsPanel.tsx`（526 行） | **修改** | 5 个 tab 里 bots/teams/buy 属 Bot 语义，需收缩为通用/多人 |
| `WeaponPresetsPanel.tsx` + 4 个 Preset Modal + `StickersPanel.tsx` | **保留 + 修改** | 饰品 UI 主体；`WeaponPresetsPanel.tsx:115-167` 的"刷一地刀"快捷刀区块替换为 preset 轮换 |
| `OverviewDashboard.tsx` / `GuideView.tsx` / `settings/*` | **修改** | 首页与引导需去掉 Bot/match 入口与截图；安装/目录/语言/关于页保留 |
| `cfg/my_bot_*`、`overrides/*`、RayTrace、BotHider | **删除** | 不进 Cosmetics-only payload |
| `scripts/package.ps1` | **重写核心策略** | 从"复制再删"改成显式 allowlist + 打包后 denylist 断言 |
| `scripts/build.ps1` | **修改** | 构建目标收缩；补无 xwin/无 SDK 时的本地路径 |
| `scripts/VpkTools.ps1` | **删除** | 只为 `botprofile.vpk` 瘦身服务 |
| `scripts/sign-update.py` / `verify-update-assets.py` / `update-public-key.txt` | **删除（保留 zip 安全校验思路）** | 更新通道关闭后不再需要签名私钥路径 |
| `LICENSE`（AGPL-3.0）、README attribution 段、`Panel/src/data/devs.ts` | **保留** | 裁剪与改名不得移除上游许可证与署名；`devs.ts` 里 Bot 专用条目改为保留 attribution 或如实标注来源 |

## 5. 已确认的关键缺陷（后续阶段的修复对象）

1. 启动隔离是持久文件状态，Steam 直接启动可能带 Mod（`mode_files.rs:106-110`）。
2. `OnItemPickup`（`PlayerKnifeCustomizer.cs:332-340`）忽略 `@event.Item`，对全身枪械无条件重跑 `TryApplyGunPresets`（`:511-525`），且 `ApplyPreset` 会重写 `ItemID`（`:773`）→ 拾来的枪会被套上玩家预设。已写好的 `GetEligibleHumanOwner`（`:751`）是死代码。
3. 配置只在 `Load()`（`:218`）和 `css_cs2bi_knives_reload`（`:223`）读取，而该命令**全仓无调用者** → 运行中改配置实际无效；也没有 watcher。同时也没有 Tick/Frame 轮询（`NextFrame` 只在 `:398`、`:538`，有界重试 `RetryDelays=[0.10,0.25,0.50,0.90]` `:1290`），所以是"完全没有热重载"而不是"轮询太重"。
4. Wear 越界是**静默拒绝**而非 clamp：`ValidatePreset:706-719` 校验失败直接 return false，皮肤不生效并耗尽重试；`Normalize`（`:1654`）只 clamp 到通用 `[0,1]`。`:715` 的 `skin == null → IsKnifeDefIndex` 是绕过 catalog 校验的后门。
5. UI 完全没有排序逻辑：刀型顺序 = `Panel/src/data/knifeIcons.ts:5-6` 硬编码 20 个 id；刀皮列表 = `skinImages.json` 原始顺序（`KnifePresetModal.tsx:76`，实测 paint 序列乱序）；无任何 rarity/colour 字段可用来做"深色优先"。
6. 中文覆盖率：刀皮 556/556 全中文化，但**手套 finish 0/91**、挂件 0/81、探员 0/79、UI 字典 477/985（48.4%）。反向问题：`weaponSkins.json` 的 `name` 字段本身是简体中文，English 界面下 130 行枪皮名会泄漏中文。
7. 搜索只匹配当前语言（`KnifePresetModal.tsx:88`、`WeaponPresetModal.tsx:34`、`GlovePresetModal.tsx:40`），不支持英文 alias / defindex；只有音乐盒是三路（`MusicKitPresetModal.tsx:39`）。
8. 快捷刀当前实现是往 4 个 `cfg/my_bot_*.cfg` 写 `bind ... "subclass_create 500;…;526"`（`lib.rs:2006-2022`）→ 与 `PRODUCT-SCOPE.md:105` 直接冲突。注意：插件内已改用 `AcceptInput("ChangeSubclass")` 就地变形（`:496-501`），地上刷刀只存在于 cfg bind 路径。
9. `Panel/src/data/weaponSkins.json` 与插件 `weapon_skins.json` 是 2106 条完全等值的重复数据（脚本核对 key set 全等），且**没有生成脚本**，属手工/vendor 产物。
10. 前端零测试框架、零 lint；`tsconfig` 开了 `noUnusedLocals`/`noUnusedParameters` → 删页面必须连带清 `store.tsx`/`api.ts`，否则 `tsc` 直接失败。

## 6. Phase B 可构建基线（2026-09-19 实测）

选定基线：本 fork HEAD（等同 upstream `main` @ `81a71004`）。所有结果在 `E:\CS2MOD\wt-agent-b` 本机构建得到，未启动 CS2。

| 目标 | 命令 | 结果 |
| --- | --- | --- |
| Panel 前端类型检查 + 打包 | `npm ci`、`npm run build`（`tsc && vite build`） | 通过；产物 8.32 MB JS / 159.79 kB CSS（`skinNames.json` 等 catalog 全量进 bundle，Phase G 需复核） |
| Node 断言脚本 | `node scripts/test-install-gate.mjs`、`node scripts/test-sticker-editor.mjs` | 通过（4 断言 / 全部贴纸-挂件-探员断言） |
| PlayerCosmetics 插件 | `dotnet build PlayerKnifeCustomizer.csproj -c Release` | 通过，0 warning 0 error |
| 插件测试 | `dotnet run --project PlayerKnifeCustomizer.Tests -c Release` | 通过（67 断言） |
| MatchCore 测试 | `dotnet run --project MatchCore.Tests -c Release`（需 `DOTNET_ROLL_FORWARD=LatestMajor`） | 通过（约 57 断言） |
| Panel Rust 测试 | `cargo test --manifest-path Panel/src-tauri/Cargo.toml --lib` | 通过，120 passed / 0 failed / 1 ignored |
| Panel release 构建 | `cargo build --target x86_64-pc-windows-msvc --release --locked --features tauri/custom-protocol` | 通过（见下节的环境限制） |
| 仓库级校验 | `pwsh ./scripts/verify-workspace.ps1`（工作区模式） | 通过；报告 Bot identities 1941 / Weapon skins 2106 / Glove skins 91 / Music kits 101 |
| 打包 | `pwsh ./scripts/package.ps1` | **未执行**：`build.ps1:148-161` 要求 `cargo-xwin` 与 LLVM（`clang-cl`/`lld-link`/`llvm-rc`），本机没有 |

### 环境结论

- 失败原因分类：**全部是环境缺失，没有上游已坏或 fork 缺陷**。基线本身可构建、可测试。
- 本机没有 .NET SDK（只有 6/7/8 runtime），插件要 `net10.0`。已在 `.cache/build-inputs/dotnet`（gitignored）放 portable SDK `10.0.401`，通过仓库自身的 `.local-build.ps1` 钩子注入（`build.ps1:20-23` dot-source 它，`verify-workspace.ps1:51-54` 又要求它存在）。系统级 .NET 安装未被改动。
- `build.ps1` 走 `cargo xwin` 是为没有 MSVC 的机器交叉编译。本机已有 MSVC 14.43（`D:\Visual Studio\product`）与 Windows SDK 10.0.22621（`D:\Windows Kits\10`），直接 `--target x86_64-pc-windows-msvc` 即可，因此不需要装 LLVM/xwin。Phase G 的脚本收缩会让本地打包路径变得可跑。
- `addons/**/*.csproj` 的 NuGet 版本三套并存（`1.0.371`/net10、`1.0.367`/net8、`1.0.362`），且 `disabled/BotAI_for_Linux` 的 `HintPath` 指向仓库外绝对路径。Cosmetics-only 只保留 net10 + `1.0.371` 一条线。

## 7. Phase G — Cosmetics-only 打包 gate（2026-09-20 实测）

`scripts/package.ps1` 与 `scripts/verify-workspace.ps1` 已重写为显式 allowlist 组装，不再"先复制完整 Local Arena payload 再删"。共享清单 `scripts/release-inventory.json` 同时被两个脚本读取：package 用它组装，verify 用它复审，避免两份列表漂移。

| 命令 | 结果 |
| --- | --- |
| `pwsh ./scripts/package.ps1 -ReleaseVersion 1.4.3.3` | 通过：完整 build.ps1 门（npm 三个断言脚本 + tsc/vite + 插件 Release 构建 + 插件测试 + cargo 测试 + release 构建 2m47s）→ 组装 → 审计 → `artifacts/LocalCosmetics-v1.4.3.3-windows.zip` |
| 归档 | 75.5 MB，459 文件；顶层只有 Panel 可执行文件、`plus-payload-manifest.json`、`LICENSE`、`README.md`、`README.zh-CN.md`、`UPSTREAM.md` 与 `addons/` |
| manifest | 453 条：`ownership=plus` 10 条（全部在 `addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/`），`shared` 443 条；`restore_policy=preserve-config` 仅玩家预设两文件 |
| 插件目录 | `addons/counterstrikesharp/plugins/` 下只有 `PlayerKnifeCustomizer`；`addons/metamod/` 只有 `counterstrikesharp.vdf`、`metaplugins.ini`、`README.txt` |
| 归档级禁入扫描 | 无 `gameinfo.gi`、无 `.vpk`、无 `cfg/`、无 `overrides/`、无任何 Bot / Nade / RayTrace / Lineup / Match / Telemetry / Rating 组件 |

禁入断言不是空转：向 staged 包植入 `addons/counterstrikesharp/plugins/BotAI/BotAI.dll` 和一个根级 `cfg` 文件后重跑 `verify-workspace.ps1 -PackageRoot`，报出 3 条失败（禁入组件 × 2、manifest 未跟踪文件 × 1）并以退出码 1 失败。

pinned 输入仍只有两个，且下载后按 `scripts/dependencies.json` 的 SHA-256 校验：MetaMod 2.0.0-git1406（7 117 569 B）、CounterStrikeSharp v1.0.371 with-runtime（51 944 999 B）。
