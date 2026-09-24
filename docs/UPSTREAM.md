# Upstream Policy

本文件描述 upstream 的 ownership、同步政策和打包装配方式。它**不**保存精确版本号。

## Canonical pins

Runtime dependency 的唯一 machine-readable source of truth 是 `scripts/dependencies.json`。
每个条目记录 repository、release、下载 asset 名称 / URL 和 SHA-256。

消费者：

- `scripts/build.ps1` — 读取 manifest 驱动本地构建。
- `scripts/package.ps1` — 按 manifest 下载并校验每个 archive 和关键 native DLL。
- `scripts/verify-workspace.ps1` — 校验 manifest 自身结构与 pin 的可用性。

任何文档、脚本或 workflow 需要引用 runtime 版本时，应指向 `scripts/dependencies.json`，
不要再复制一份版本字符串。过期的手工副本比缺失说明更有害。

## Ownership

- 主基底：`numakkiyu/Local-Arena` — 本仓库是它的个人 fork，开发只发生在 `Whatnamed/Local-Arena`。
- 参考上游：`ed0ard/CS2-Bot-Improver` — AGPL-3.0 组件来源，可做审计后的兼容性同步。
- 不直接修改 upstream，不修改 `numakkiyu` 或 `ed0ard` 的远端。
- 保留适用的 AGPL-3.0 许可证、版权、来源与 attribution；裁剪功能或重新打包时不得删除应保留的许可证与署名。

## 打包装配模型

Windows package 不提交生成的或第三方的二进制。`scripts/package.ps1` 按以下顺序装配：

1. 下载 manifest 中 pinned 的上游 Windows release archive，作为官方 runtime 布局基线。
2. Overlay pinned 的 MetaMod loader、CounterStrikeSharp（含其捆绑 .NET runtime）和 RayTrace 的 native module 与 CSS API / implementation。
3. Overlay pinned 的 BotHider native module。
4. 从 pinned source tree 重新构建 Plus 自有的模块（包括 BotAI、BotAimImprover、BotBuy、NadeSystem），使较新的源码修复不会被旧 release DLL 覆盖。
5. Overlay Plus 构建的 `BotHiderImpl`、`BotHiderApi`、`PlayerKnifeCustomizer` 程序集，并用 Plus Panel 替换上游 Panel 可执行文件，保持同样的 standalone workflow。
6. 每个下载的 archive 和每个关键 runtime DLL 在打包前做 SHA-256 校验；布局与文件集合由 `scripts/verify-workspace.ps1` 断言。

## 同步政策

1. Fetch upstream，审查 release notes、issues 和相关 PR。
2. 在隔离分支中 rebase 或 merge，不在主分支直接同步。
3. 保留 Plus-only 模块和 Panel 路由。
4. I18N 调和：保留完整的新一版 upstream key / dictionary，再重新套用 Plus key 与翻译。
5. Catalog 只从可追溯来源刷新，并校验 locale 与条目数量。
6. 构建全部目标并生成一次性 package，确认无误后才更新 `scripts/dependencies.json` 的 pin 和哈希。
7. 对 CS2 / MetaMod / CounterStrikeSharp / signature / native API 的兼容性结论必须有当前证据（实际解析结果、构建产物或官方变更说明），不能仅由版本号推断。

## Provenance 记录

以下内容是"某段代码来自哪里"的历史事实，不是当前 pin，不随 manifest 更新：

- BotAI 的 Windows signature 刷新来自上游 PR #75（`3db93ba`）。
- Cosmetic / native binding 的逐条来源与本地用法见
  [docs/archive/CS2-2026-09-23-COMPATIBILITY.md](archive/CS2-2026-09-23-COMPATIBILITY.md)。
- BotHider Windows gamedata 的 overlay 来源同一份记录，`scripts/dependencies.json` 的 `botHider.gamedataWindowsSourceCommit` 保存对应 commit。
- v1.4.4 upstream 的审查结论与「保持既有 pin」的决定见
  [docs/archive/UPSTREAM-v1.4.4-REVIEW.md](archive/UPSTREAM-v1.4.4-REVIEW.md)。

## Third-Party Data

Weapon images 和 localized skin names 来自 `Nereziel/cs2-WeaponPaints`。Indonesian 目前没有该来源的
skin-name 表，因此使用英文 fallback；这仅影响显示，物品应用始终使用数值 catalog 标识。

BotHider 由 `XBribo/CS2-Bot-Hider` 维护，package 使用 `scripts/dependencies.json` 中 pinned 的 release。
打包校验官方 release archive 与 native DLL 哈希，不做 binary patching。

`BotHiderImpl` 只对 BotHider 报告为受管 Bot 的 slot 补充 native name publication，通过
`CBasePlayerController.m_iszPlayerName`，并在 Bot 创建前强制使用 Plus 的 `bot_info.json` 名称来源。
它不写入人类玩家 slot 的名称。Steam ID、头像、卡片、crosshair code、ping、scoreboard flair、
bot disguise、respawn 行为以及所有 upstream enhanced-bot module 都保持原有路径。
仓库可以自动校验这一隔离性和 package 布局，但最终的 host-local scoreboard 结果仍需游戏内
Enhanced Bots 练习局确认，见 `docs/MANUAL-ACCEPTANCE.md`。
