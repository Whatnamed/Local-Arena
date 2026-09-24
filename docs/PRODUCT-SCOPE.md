# Local Arena Personal — Product Scope

本文件是产品定位、模式、行为和边界的 canonical source，只描述长期事实。
过日期、绑定某个 CS2 build 或某轮执行的证据放在 `docs/archive/`，发布记录放在 `docs/releases/`；分类见 `docs/README.md`。

## 1. 产品定位

本项目是基于 Local Arena 的个人 fork。长期底座保留原 Local Arena 的完整能力，包括 Panel、Bot、Local / Preview / Bots / Online 模式、比赛、统计以及现有的饰品功能。

工作方向是有明确价值的个人定制和 bug 修复，而不是把仓库重新裁剪成 Cosmetics-only 产品。现有功能只在改动直接影响它们时才调整；没有理由删除或隐藏 Bot、Match、Stats 等原有能力。

产品面向 Windows 本地 CS2 使用。简体中文保持一等 UI 语言，原 Local Arena 的模式切换和启动模型继续作为行为基线。

## 2. 保留的原有能力

- 保留原 Local Arena 的 Panel、Bot、Match、Stats、Local / Preview / Bots / Online 模式和相关 UI。
- 保留枪械、刀具、手套、音乐盒以及其他现有饰品入口和配置持久化。
- 保留原有安装、修复、恢复和诊断流程，对其只做与当前 bug 或 ownership 范围相关的最小修改。
- 保留 AGPL-3.0、来源说明和适用的 upstream attribution。
- 不引入大规模 UI redesign，不为了饰品功能裁剪 Bot runtime。

## 3. 饰品行为边界

### 3.1 枪械

- CT / T 独立配置、共享武器语义、PaintKit、Wear、Seed、Name Tag、StatTrak、Souvenir 等现有能力继续有效。
- 玩家购买、出生发放或本项目明确创建的枪械可以应用当前阵营对应的 preset。
- 玩家捡到 Bot / 地面枪时，如果当前阵营为该 weapon defindex 配置了 preset，允许按 Local Arena 原有逻辑应用自己的 preset。
- 如果没有对应 preset，不做无意义重写，保持当前实体状态。
- 本项目不新增 gun provenance / foreign-pickup preservation 子系统，也不把“拾取已有实体必须保留外来皮肤”作为产品 invariant。

### 3.2 刀具、手套和音乐盒

- 保留完整刀具目录、每把刀独立的 preset、手套 Wear / Seed 和音乐盒配置。
- 刀、枪、手套、音乐盒之间的配置相互独立。
- 配置持久层使用数值 ID / DefIndex / PaintKit，不使用本地化字符串作为主键。
- 中文、英文和 PaintKit / defindex 检索都应尽量命中同一条目；缺少可靠中文时才使用明确的英文或 ID fallback。

## 4. 快捷换刀

- 提供可靠的快捷换刀功能，默认循环顺序为 Karambit 507、Butterfly 515、M9 Bayonet 508、Bayonet 500、Skeleton 525、Falchion 512。
- 默认候选按键为 `\\`；未启用快捷功能时不得修改用户键位。保留将来配置自定义列表和按键的可能。
- 切换必须以真实持有刀的 ItemDefinitionIndex 作为当前位置事实来源。
- 不在当前 active entity 上直接原地 `ChangeSubclass` 作为完成方案，不生成一堆地面刀，也不依赖丢地再捡。
- replacement 只有在创建、目标 subclass / defindex、econ attributes 和 preset 路径成功后才替换旧刀；失败必须有界、可恢复，不能让玩家永久没刀或跳过轮换位置。
- 没有当前阵营 preset 时仍允许切刀型，并进入明确的 Vanilla / default 路径；不得从另一阵营复制 preset。

## 5. 运行中应用和重新发装备

- 饰品应用继续基于 Spawn、GiveNamedItem、明确实体事件、配置变化和有界 retry 等事件驱动路径。
- 不新增永久 Tick / Frame 轮询来扫描配置、Inventory 或 held weapon。
- `GiveNamedItem` 返回枪械实体时安排 Guns phase；返回 knife entity 时安排 Knife phase；一次发装备影响多类实体时允许组合 phases。
- 回防、特殊游戏模式重新发装备和 respawn/loadout pipeline 重新创建刀具时，使用 generation-safe / delayed apply 重新应用当前配置。
- native hook 内不直接写入尚未 ready 的 econ attributes；无效配置保留最后有效状态并记录清晰错误。

## 6. 模式、安装和配置协调

- Normal matchmaking：增强 runtime 不加载，PlayerCosmetics OFF；Cosmetics preview：PlayerCosmetics ON、增强 Bot OFF、官方普通 Bot 可用；Enhanced bots：增强 Bot 与 PlayerCosmetics 同时 ON。Match 使用相同的 Enhanced bots 协调，不恢复历史 `enabled` 快照来决定运行模式。
- 保留原 Local Arena 的 Local / Preview / Bots / Online 模式切换和启动模型。不引入“每次启动临时修改 `gameinfo.gi`、数秒后自动恢复 clean”的 launch isolation transaction。
- 直接启动 CS2 的行为以原 Local Arena 的模式管理为准，不额外承诺 Steam 直启时项目 runtime 永远完全未加载。
- `FollowCS2ServerGuidelines` 必须在安装、修复和本地饰品模式需要时可靠协调为 `false`，因为 `true` 会阻止本地饰品管线需要的 econ attributes。
- 只管理 `core.json` 的该 property，保留未知字段；记录原值并在 restore / uninstall 时按 ownership 恢复。
- `core.json` 不存在时可从当前安装的 `core.example.json` 派生；malformed、权限错误或无法安全写入时 fail closed，并显示清晰错误。
- 不覆盖未知第三方文件、用户个人 cfg / autoexec / bind。

## 7. Panel 生命周期

- Panel 窗口恢复问题先区分本机现场证据与当前源码，再决定是否修复；不在缺少证据时叠加 `set_focus()` 之类的补偿调用。
- 不为解决单一恢复问题无必要增加系统托盘。

某一时期残留进程、HWND / WebView2 composition 的具体调查过程和结论属于历史证据，见 `docs/archive/MAIN-AUDIT-2026-09-23.md`。

## 8. 图片资产和中文数据

- 手套和音乐盒 picker 的必要缩略图随 Panel 离线打包；构建校验文件集合、PNG signature、长度和 SHA256。新增本地图必须进入同一校验，不引入未校验的批量素材。
- 其他饰品图继续使用远程来源与文字 fallback。
- picker 不应大面积显示空白图；加载失败必须有可见 fallback。
- 优先使用可校验的 build-time catalog、有限本地 cache 或必要的本地缩略图，不在没有尺寸统计前把数 GB 素材塞进仓库。
- glove catalog 的每个可选条目都应有可靠的 Simplified Chinese display name。优先使用 CS2 / Steam 官方 localization 数据；没有官方条目时使用明确 fallback，不凭空手工翻译整批数据。
- 至少对 gloves 和 music 建立完整性检查，避免大量 404 或英文退化悄悄进入 build。当前资源清单与预算由 `scripts/check-cosmetic-media.mjs` 和构建检查决定，不在本文档重复具体数量。

## 9. Updater 和 fork 边界

- 这是独立个人 fork。上游 Git 同步可以审查后进行，但应用内 updater 不得把 `numakkiyu/Local-Arena` 的 release 当作本项目更新并覆盖个人 fork。
- UI 不显示实际上会安装官方 Local Arena payload 的“更新”操作。
- 可以保留只读的依赖检查、版本查看或兼容性信息；不构建个人自动更新通道，也不为个人 fork 建立 GitHub signed release / update pipeline。

## 10. 明确不做的事情

- 不删除 BotAI、BotRandomizer、BotAim、Match、Stats 或其他原 Local Arena 能力。
- 不引入实验分支的 hidden Bots mode、临时 launch isolation、gun provenance 或生命周期架构。
- 不修改原生 HUD、Buy Wheel，不添加游戏内 Overlay 或常驻 UI。
- 不新增永久高频轮询，不启动 CS2 做自动验收。
- 不执行与当前目标无关的重构、依赖升级、格式化或跨 worktree 清理。
