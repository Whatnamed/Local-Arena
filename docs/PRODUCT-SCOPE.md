# Local Cosmetics — Product Scope

## 1. 产品定位

Local Cosmetics 是一个面向 Windows 本地 CS2 对局的轻量饰品工具。

它提供外部桌面 Panel，用于为真人玩家配置刀具、刀皮、手套和枪械皮肤，并在本地 / 离线对局中通过 MetaMod + CounterStrikeSharp 应用这些预设。

项目以 Local Arena 的玩家饰品能力为主要技术基底，但最终产品不以增强 Bot、比赛统计或完整 Local Arena 平台为目标。

### 核心使用场景

用户只有两种需要理解的日常入口：

1. **正常 CS2**：直接从 Steam 启动。此时不得加载本项目 Mod，不需要打开 Panel，也不需要提前切换任何模式。
2. **本地饰品模式**：打开 Local Cosmetics Panel，配置饰品后由 Panel 启动 CS2。该启动使用 `-insecure`，加载本项目受管 runtime，用于官方普通 Bot / 本地离线玩法。

这是整个产品最重要的行为边界。

---

## 2. 第一版必须保留的能力

### 2.1 枪械皮肤

- 保留 Local Arena 现有枪械皮肤配置能力和总体 UI 比重，不因为用户更常使用刀具而隐藏或降级枪械入口。
- CT / T 专属武器继续分别配置。
- 双方共用武器继续支持现有的联动 / 分离语义，除非实现审计证明需要小幅调整。
- 支持当前 catalog 中兼容的 PaintKit、Wear、Seed、Name Tag、StatTrak / Souvenir 等已经稳定的字段。
- 玩家自己购买、出生发放或本项目明确创建的枪械应用自己的预设。
- 玩家捡起地面上已经存在的枪械实体时，保持该实体原本的外观；不得仅因为 `item_pickup` 就覆盖成玩家自己的预设。
- 玩家把自己的枪丢掉后再捡回，应自然保持该实体原本已经应用的外观。

### 2.2 刀具与刀皮

- 支持当前 catalog 中可用的全部刀型，不删减完整目录。
- UI 默认将用户常用刀型放在更靠前位置。第一版偏好顺序：
  1. Karambit / 爪子刀
  2. Butterfly Knife / 蝴蝶刀
  3. M9 Bayonet / M9 刺刀
  4. Bayonet / 刺刀
  5. Skeleton Knife / 骷髅匕首
  6. Falchion Knife / 弯刀
  7. Stiletto Knife / 锥型折叠刀
  8. Talon Knife / 锯齿爪刀
  9. Huntsman Knife / 猎杀者匕首
  10. Flip Knife / 折叠刀
  11. Ursus Knife / 熊刀
  12. Classic Knife / 经典匕首
  13. Nomad Knife / 流浪者匕首
  14. Kukri Knife / 廓尔喀刀
  15. Bowie Knife / 鲍伊猎刀
  16. 其余刀型按 catalog / fallback 排序
- 每把刀保留自己的独立皮肤预设。切回某把刀时恢复该刀最后保存的 PaintKit / Wear / Seed 等，而不是复用当前全局刀皮。
- 皮肤展示偏好可把 Vanilla、Blue Steel、Black Laminate、偏暗 Doppler、Night / Night Stripe、Damascus Steel、Ultraviolet 等深色 / 中性风格排得更靠前；这只是 UI 排序，不能隐藏完整 catalog。
- Doppler / Gamma Doppler 的阶段、Ruby、Sapphire、Black Pearl 等继续作为独立 PaintKit 条目处理，不通过 Seed 猜阶段。
- Wear 必须 clamp 到该 PaintKit 的有效 min/max 区间。

### 2.3 手套

- 保留完整支持的手套型号和 PaintKit。
- UI 推荐排序可优先偏通用、深色 / 中性色组合，例如 Nocts、Black Tie、Smoke Out 等，但完整目录始终可用。
- 手套配置与刀具配置相互独立，不强制绑定刀套。
- 支持 Wear / Seed，并遵守 catalog 的有效范围。

### 2.4 中文和检索

- 简体中文是一等语言，不是后补翻译。
- Panel UI、刀名、手套名、皮肤名尽量使用现有可靠中文本地化数据。
- 找不到中文条目时可以回退英文或 PaintKit ID，但不能让整个饰品目录只显示英文。
- 搜索至少可靠支持当前显示语言；目标体验是中文名称、英文名称和 ID 都能命中同一饰品条目。实现是否采用双语索引由 Agent 根据现有数据结构决定。
- 配置持久层继续保存数值 ID / DefIndex / PaintKit，不把本地化字符串作为配置主键。

---

## 3. 运行中修改

第一版目标支持在 CS2 已经运行、本地饰品模式已经加载的情况下，从外部 Panel 修改饰品并尽快应用。

### 行为要求

- 刀型改变：若当前玩家实体满足条件，尽量在当前生命内刷新；若当下实体不可安全修改，则保存配置并在下一次适当事件应用。
- 刀皮改变：只刷新相关刀具属性。
- 手套改变：只刷新 `EconGloves` / 必要 bodygroup 状态。
- 枪皮改变：只处理玩家自己拥有且符合 provenance / ownership 规则的对应武器实体；不得为了实时刷新而污染拾来的枪。
- 玩家已死亡、实体正在切换或 API 暂时不可用时允许延迟到下一个安全事件应用，不能为了“立刻”而无限重试或持续扫描。

### 技术约束

- 不采用每 Tick / 每 Frame 扫 JSON、扫玩家 Inventory 或重复写 econ 属性的方案。
- Panel 保存配置使用原子写或等效方式，避免插件读取半写文件。
- 插件侧采用配置变更事件 / watcher + debounce 或同等事件驱动方案。
- 变更后做 schema / catalog 校验，再 diff 新旧状态，只重应用发生变化的区域。
- 游戏线程相关修改必须通过 CounterStrikeSharp 支持的安全调度路径执行。
- 配置文件暂时无效时保留最后一个有效配置并记录错误，不应导致游戏崩溃。

---

## 4. 快捷刀

快捷刀是可选功能，不是基础运行依赖。

- 默认快捷顺序：Karambit → Butterfly → M9 Bayonet → Bayonet → Skeleton → Falchion。
- 用户可以在 Panel 中调整快捷刀列表和顺序。
- 快捷命令应直接切换当前刀型 / 默认刀预设，不再通过 `subclass_create` 一次生成大量刀具实体。
- 每次切换加载对应刀型自己的已保存皮肤预设。
- 默认候选按键为 `\`，但只有用户明确启用快捷功能时才允许建立绑定。
- 除该可选绑定外，不修改用户其他游戏键位。
- 如果不能可靠证明某个 cfg / bind 是本项目拥有的，卸载 / 恢复时不得删除或覆盖它。

---

## 5. 启动与隔离

### 5.1 普通 Steam 启动

硬性要求：

> 用户不打开 Local Cosmetics，直接从 Steam 启动 CS2 时，必须得到普通、未加载本项目 Mod 的 CS2。

因此不能把“上一次选择的 Preview / Mod 状态”永久留给下一次 Steam 启动，也不能要求用户记得先在 Panel 中切回 Normal。

### 5.2 本地饰品启动

- 只有由 Panel 显式发起的本地饰品启动才启用本项目 runtime。
- 该启动自动添加 `-insecure`；不要求用户把 `-insecure` 永久写进 Steam Launch Options。
- 本地饰品模式保留官方普通 Bot，不启用 Enhanced Bot AI。
- Panel 应明确显示它正在准备 / 启动本地饰品模式，但不要把无法直接观测的状态包装成绝对安全保证。

### 5.3 启动实现原则

Local Arena 当前会改写 `gameinfo.gi` SearchPath。第一版不预先指定最终实现方式，必须由实现阶段对以下目标做 Spike 和验证：

- 普通 Steam 启动默认干净。
- Panel / CS2 异常退出、启动失败、重复启动、进程崩溃后能自动恢复或在下次 Panel 启动时可靠自愈。
- 不破坏 Steam 更新后的新 `gameinfo.gi` 内容。
- 修改必须事务式、可验证、可恢复。
- 不通过永久残留的 Mod SearchPath 实现“以后可能记得切回来”。

如果当前 CS2 / MetaMod 机制不允许完全无持久状态，应选择能满足上述用户行为的最稳妥方案，并在实现文档中明确剩余限制。

---

## 6. Panel 形态

- Panel 是独立 Windows 桌面应用，不是 CS2 控制台，也不是游戏内菜单。
- 保留 Local Arena 现有饰品 UI 结构作为主要起点；不为了“刀更常用”而大改枪械页面结构。
- 不添加游戏内 Overlay、常驻置顶 HUD 或实时 3D 预览作为第一版要求。
- Panel 开着时可用于运行中改饰品；配置已经保存后，Panel 是否必须持续运行取决于最终 watcher / runtime 架构，但目标是尽量不让 Panel 成为饰品持续生效的硬依赖。

---

## 7. Cosmetics-only 发布边界

最终发布包不应只是“完整 Local Arena + 把 Bot 功能按钮隐藏”。

第一版完成后应把 runtime / payload 收敛为真正需要的组件：

- MetaMod
- CounterStrikeSharp
- PlayerCosmetics / 对应本项目插件
- 饰品 catalog、本地化和玩家配置
- Panel 与必要的安装 / 恢复 / 诊断代码

以下内容不应进入最终 Cosmetics-only payload，除非实现审计证明某个组件是不可替代的底层依赖并有明确说明：

- Enhanced Bot AI
- BotAimImprover
- BotBuy
- BotRandomizer
- NadeSystem
- RayTrace
- BotHider
- Bot profiles / team injection
- Match coordinator / rating / telemetry
- Demo / 比赛统计相关 runtime

UI 中与这些功能相关的页面也应在最终产品中移除，而不只是不可用。

---

## 8. 安装、清理和恢复

- 本项目不依赖用户现有的旧 CS2-Bot-Improver 安装。
- 首次安装前应能识别旧 Local Arena / Bot Improver / MetaMod / CounterStrikeSharp 环境。
- 清理只允许删除能够可靠归属到旧受管 Mod 或本项目自身的文件。
- Steam“验证游戏文件完整性”可以作为恢复官方文件的一步，但不能假设它会自动删除所有额外第三方文件。
- 未知第三方插件和用户个人 cfg / autoexec / bind 默认保留。
- 保留 Local Arena 中有价值的事务式备份、安装校验、回滚和恢复思想，但 ownership manifest 要缩小到 Cosmetics-only 实际拥有的文件。
- 安装、修复、更新和恢复不得在 CS2 正运行并可能持有目标文件时无保护地执行。

---

## 9. 更新与上游同步

- 本项目是独立 fork，不允许继续使用 Local Arena 官方在线更新通道直接覆盖本项目 Panel / plugin payload。
- 第一版可关闭应用自身的自动更新，保留必要的版本 / 兼容提示；等项目稳定后再决定是否建设自己的签名更新通道。
- 上游同步通过 Git 明确进行：
  - Local Arena：主要同步玩家饰品 UI、catalog、兼容修复、安装器可复用改进。
  - CS2-Bot-Improver：按需参考最新 CS2 / CounterStrikeSharp 兼容修复和饰品数据变化。
  - MetaMod / CounterStrikeSharp：作为独立运行依赖审计和升级。
- 不接受“因为 upstream 更晚”就整包覆盖本项目改造的做法。

---

## 10. 性能和游戏体验边界

本项目不应修改：Bot AI、武器伤害、后坐力、移动、经济、地图规则、烟雾 / 投掷物逻辑、命中判定以及原生 HUD / 雷达 / 计分板。

运行时饰品逻辑应主要在 Spawn、GiveNamedItem、明确的实体事件、配置变化和必要的有界重试中工作。

第一版不要求 coding agent 启动游戏做 FPS 基准。Agent 负责确认代码中没有永久高频轮询，并完成能自动化的构建 / 测试。实际帧率和体感由用户按手工验收清单比较。

---

## 11. 第一版非目标

以下内容不作为第一版核心范围：

- 增强 Bot AI
- 公共 / 联机 Skin Server
- VAC-secured 环境中的饰品功能
- 修改真实 Steam Inventory
- 游戏内 Overlay / ImGui 菜单
- 3D 饰品预览器
- Steam 市场价格 / 交易功能
- 库存同步
- 大规模重做现有枪皮 UI
- 深度扩展贴纸 / 挂件编辑器
- 为了理论完整性重写所有 Local Arena 架构

现有探员、音乐盒、贴纸、挂件等能力是否保留代码兼容性，由实现审计决定；它们不得阻碍核心刀具、手套、枪皮和启动隔离的完成。

---

## 12. 第一版完成标准

第一版可以收口的条件：

- 项目已经成为独立 Cosmetics-only fork / 产品，而不是完整 Bot 平台的隐藏 UI 版本。
- 普通 Steam 启动与本地饰品启动的边界在代码和安装状态层面清晰。
- 玩家枪械 provenance / pickup 语义符合本文件规定。
- 刀、手套、枪械现有饰品能力可构建，运行中更新路径已实现为事件驱动。
- 简体中文显示和搜索不出现系统性英文目录退化。
- 快捷刀功能为可选且不污染其他键位。
- packaging / installer / restore / updater 均已按本项目 ownership 重构并通过自动化检查。
- coding agent 的自动化测试、构建和包内容验证全部通过。
- 游戏内行为未由 Agent 冒充“已验证”；所有需要实机确认的项目明确列入 `docs/MANUAL-ACCEPTANCE.md`，由用户自行验收。
