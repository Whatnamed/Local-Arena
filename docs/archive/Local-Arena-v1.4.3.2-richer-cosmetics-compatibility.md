# Local Arena v1.4.3.2 “更丰富的饰品”兼容性分析

状态：1.4.3.2 实现记录，不是发布说明；自动化验证已完成，但按用户要求没有启动 CS2，因此不代表已经完成真人饰品实机验证。

## 结论

`emptysuns/CS2-Skin-Forge` 与当前项目在 CS2 经济属性名称层面具有较高兼容性，但不是可直接安装或复制的插件。当前项目应继续保持模块边界：`PlayerKnifeCustomizer` 负责真人玩家，`BotRandomizer` 负责机器人。Skin Forge 的 `PlayerSkinMod` 不应与两者并装，也不应直接覆盖当前 Panel/Tauri 配置格式。

最可复用的是：

- 贴纸属性契约：`sticker slot N id/schema/offset x/offset y/wear/scale/rotation`；
- 挂件属性契约：`keychain slot 0 id/seed/offset x/offset y/offset z`；
- 探员的 CT/T 独立模型路径思路；
- 以武器 defindex 为键保存饰品选择。

不可直接复用的是运行时实现、面板协议、安装器和版本化数据。外部仓库当前快照为 [`b2edea17db9128609dd41f726f179cd965206433`](https://github.com/emptysuns/CS2-Skin-Forge/tree/b2edea17db9128609dd41f726f179cd965206433)。

## 外部实现路径

### Skin Forge 插件

外部 `PlayerSkinMod` 使用 `net8.0` 和 `CounterStrikeSharp.API 1.0.313`。它从插件目录读取 `player_loadout.json`，通过 `FileSystemWatcher` 热加载，并在真人玩家出生、购买/给予武器和拾取刀具等事件中写入饰品。

- 探员：按 CT/T 选择模型路径，`pawn.SetModel` 后标记 `m_CBodyComponent`；
- 普通武器：在 `GiveNamedItem` 后取得实体的 `CEconItemView`，清空属性列表，写入基础皮肤，再写贴纸和挂件属性；
- 贴纸：最多五个槽位，外部模型有 `id/schema/offsetX/offsetY/wear/scale/rotation`；偏移非零时额外写入 `schema = 0`；
- 挂件：只使用 `keychain slot 0`，写入 ID、XYZ 偏移和可选 seed；
- 面板：Rust 端对 loadout 保持无类型 `serde_json::Value`，直接保存到插件目录，和当前项目的 schema/migration/安装器协议不同。

外部 Panel 的贴纸、挂件目录来自 ByMykel CSGO-API 的生成数据，图片主要是远程 Steam CDN URL；这与当前项目已锁定的本地目录、生成来源和哈希审计不一致。

### 当前项目实现路径

当前项目有两条明确的饰品链路：

1. `PlayerKnifeCustomizer` 面向真人。Panel/Tauri 已升级到 `KnifeCustomizerConfig` schema 5：贴纸实例槽与武器原生 schema 分离，枪械预设可保存一个 `CharmPreset`，CT/T loadout 可分别保存一个白名单 `agent_model`。插件通过独立目录校验贴纸 ID/schema、挂件 ID/placement 和探员阵营，在 C# 内解析挂件 XYZ，并在地图开始预缓存探员模型。配置入口仍受“实验性功能”显式开关约束，默认关闭。
2. `BotRandomizer` 面向机器人。它已经使用 `GiveNamedItem` 前置 Hook 构造并替换完整 `CEconItemView`，然后写入基础皮肤、最多五张贴纸、挂件和每把武器的挂点。`charm_placements.json` 对每个武器保存 XYZ 候选位置，`cosmetic_catalog.json` 保存贴纸 schema、贴纸目录、挂件定义、枪皮和探员目录。机器人探员通过预缓存模型后调用 `SetModel` 应用。

这两条链路有意不共享“玩家配置文件”：机器人饰品是随机生成的运行时状态，真人饰品需要可迁移、可审计和在线模式门控的持久化配置。

## 逐项兼容性

| 能力 | Skin Forge | 当前项目 | 结论 |
| --- | --- | --- | --- |
| 贴纸属性名 | `sticker slot N ...` | PlayerKnifeCustomizer 规划器和 BotRandomizer 均使用同一命名族 | 属性契约兼容，可复用名称；仍需游戏内验证 schema/偏移语义 |
| 贴纸写入时机 | 真人 `GiveNamedItem` 后置及出生重应用 | 真人后置 Hook 延迟到安全阶段；机器人 `GiveNamedItem` 前置构造 item view | 不能直接替换 Hook；外部后置写入会与本地真人延迟管线竞争 |
| 挂件 | slot 0 + XYZ + seed | BotRandomizer 保持原管线；PlayerKnifeCustomizer 新增独立的 ID/placement 配置与目录解析 | 配置与自动化校验已兼容，真人实机行为仍待离线验证 |
| 探员 | 真人 CT/T `SetModel` | PlayerKnifeCustomizer 使用独立真人出生 phase；BotRandomizer 保持机器人专属管线 | 属性行为兼容，但 Hook、目录和状态所有权相互隔离 |
| 数据协议 | `player_loadout.json`，Rust 无类型 | Tauri schema 5、v2/v3/v4 迁移、备份、模式门控 | 不兼容，不能直接导入外部文件 |
| CounterStrikeSharp | API 1.0.313/net8 | PlayerKnifeCustomizer/BotRandomizer API 1.0.371/net10 | 外部二进制和签名不可直接使用，必须在本项目工具链重编译 |
| 安装/运行边界 | 外部插件自己部署 CSS 和 `-insecure` | Local Arena 由安装器、在线/预览/机器人模式统一管理 | 不应把外部安装器接入当前发布包 |

## 主要风险

- **重复 Hook/重复写入**：Skin Forge、PlayerKnifeCustomizer、BotRandomizer 都触及 `GiveNamedItem` 或 `CEconItemView`。同时启用会造成先后顺序依赖、属性清空、模型覆盖和难以归因的崩溃。
- **原生签名漂移**：外部使用旧 API 和 `MemoryFunctionVoid`，本项目使用带返回值的动态函数封装；签名能否继续匹配必须以当前 CS2/gamedata 和实际进程为准。
- **挂点不是通用常量**：挂件 XYZ 与武器模型相关。只有 ID/XYZ/seed 而没有本项目式的武器挂点目录时，不能声称“所有武器兼容”。
- **目录和远程图片漂移**：外部目录来自第三方 API，不能替代当前项目的生成来源、数量和 SHA-256 校验；远程 CDN 也不适合当前离线包完整性边界。
- **许可证不清晰**：GitHub API 对该快照未返回许可证，仓库树也没有 `LICENSE` 文件；不能把外部源码视为已获许可的可复制代码。当前项目是 AGPLv3。仅借鉴属性名称、字段形状和公开数据来源，并保留独立实现；若要复制代码，必须先取得作者明确许可并补齐归属/许可证审查。
- **安全边界**：Skin Forge 自己要求 `-insecure` 并提示 VAC 风险。Local Arena 的在线模式门控不能因为接入外部实现而放宽。

## 1.4.3.2 已实现范围

1. BotRandomizer 源码与运行状态未改动；真人和机器人继续通过 `IsBot: false/true` 分离。
2. 2.5D 面板使用当前枪皮图、贴纸缩略图、武器 schema 热点和聚类挂点，不启动 CS2，也不依赖实机截图。
3. 配置只保存 `placement_id`，原生 XYZ 仅存在于 PlayerKnifeCustomizer 专用只读目录中；目录由现有 BotRandomizer 数据确定性生成，但两条运行管线不互相调用。
4. v3 贴纸迁移会根据武器能力补充 schema；无效贴纸或挂件只会被清空，paint/seed/wear/StatTrak 和整个枪械预设继续保留。
5. 原生装饰品先完成全部规划再写入；签名缺失时沿用现有安全跳过，单次装饰品写入异常时清空部分属性并重建基础枪皮。
6. 真人探员作为独立 `Agent` phase 接入现有代际管线；购买武器只触发枪械 phase，不会重复写入玩家模型。

当前判定：**贴纸、挂件和探员的公开属性/模型行为兼容，外部运行时和配置协议不兼容；本项目已完成独立实现，没有复制或集成 Skin Forge 插件。真实 CS2 客户端行为仍需后续离线实机验证。**
