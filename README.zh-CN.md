<div align="center">

# Local Cosmetics

[English](README.md) | **简体中文**

<br/>

<img alt="支持平台" src="https://img.shields.io/badge/platform-Windows-0078D4">
<a href="LICENSE"><img alt="许可证" src="https://img.shields.io/badge/license-AGPL--3.0-green"></a>

<br/>
<br/>

[饰品配置](#你可以配置什么) · [启动隔离](#两种启动-cs2-的方式) · [首次安装](#四步完成首次安装) · [恢复与诊断](#安装状态恢复与诊断) · [代码来源与署名](#上游代码来源与署名)

</div>

> [!IMPORTANT]
> Local Cosmetics 是一个轻量的 Windows 本地 CS2 **玩家饰品**工具，由 [Local Arena](https://github.com/numakkiyu/Local-Arena) 的玩家饰品能力派生，独立开发与维护
>
> 本项目不是增强 Bot 项目，不是公共或联机皮肤服务器，也不是游戏内 Overlay；它不会修改你真实的 Steam 库存，也不会进入 VAC 安全服务器
>
> 产品定位、用户行为和功能边界以 `docs/PRODUCT-SCOPE.md` 为准；`docs/UPSTREAM.md` 记录从上游保留了什么、明确不带入什么
>
> 本项目的构建、面板、安装、饰品、诊断与闪退问题只在本仓库反馈，不要向上游项目提交本 fork 的问题

<div align="center">

当前 `main` 分支源码版本为 **1.4.3.3** · 安装包 `LocalCosmetics-v1.4.3.3-windows.zip`

</div>

## 这个项目做什么

你在外部桌面 Panel 里为真人玩家配置刀具、刀皮、手套和枪械皮肤预设，然后由 Panel 启动 CS2，在离线本地对局中应用这些预设。官方普通 Bot 继续正常工作，本项目不改变任何 Bot 行为。

## 两种启动 CS2 的方式

这是整个产品最重要的行为边界：

| 启动方式 | 得到的结果 |
| --- | --- |
| **直接从 Steam 启动** | 普通、未加载本项目内容的 CS2。不需要打开 Panel，`gameinfo.gi` 中不会残留本项目搜索路径，也不需要先“切回正常模式” |
| **从 Panel 启动** | 本地饰品模式。Panel 开启启动事务，只为这一次运行写入受管 `gameinfo.gi` 搜索路径，并带上 `-insecure` 启动 CS2 |

`-insecure` 表示这次会话是离线的：无法进入官方匹配或 VAC 安全服务器，而这正是本地饰品能够生效的环境。CS2 正常退出后，游戏内插件与 Panel 会把状态恢复为干净。如果上一次运行是被强制结束而不是正常关闭，下一次启动、修复或恢复会先走完恢复流程再做其他事情——游戏内的实际表现请按 `docs/MANUAL-ACCEPTANCE.md` 自行验收。

## 你可以配置什么

### 刀具、手套、枪械

- 保留当前 catalog 的完整刀型，每把刀都有自己的皮肤预设，切回某把刀时恢复该刀最后保存的 PaintKit、磨损与图案模板
- CT 与 T 专属武器分别配置；双方共用武器默认联动，也可以解除联动后分别设置
- 只有兼容的 catalog 条目才会显示 StatTrak 或纪念品选项，数值写回对应阵营预设
- 磨损会 clamp 到所选 PaintKit 的有效区间；Doppler、Gamma Doppler 的阶段、Ruby、Sapphire、Black Pearl 继续作为独立条目，不通过 Seed 猜测阶段
- 真人玩家音乐盒预设
- 只保证玩家自己拥有（购买、出生发放或由本项目创建）的武器应用枪皮预设；捡起地面上已有的枪时保持该实体原本的外观

### 运行中修改

CS2 已经运行、本地饰品模式已加载时保存预设，会通过配置变更 watcher + debounce + 有界重试应用变更。不存在永久 Tick / Frame 轮询扫描配置或库存的实现，并且只重新应用真正发生变化的区域。

### 可选的快捷换刀

饰品装备页面可以排定快捷换刀顺序，并给出对应的控制台绑定命令供一键复制。Panel 不会写入任何 bind、cfg 或 autoexec：在你自己粘贴这行命令之前，你的键位保持原样；关闭该功能也不会留下残留。

### 实验性功能

**设置 → 实验性功能** 提供贴纸、经过校验的挂件位置和真人玩家 CT/T 探员模型。贴纸槽位与武器原生位置分开选择；挂件只吸附到本地 catalog 中经过校验的挂点，配置不保存任意 XYZ；探员只从按阵营隔离的本地白名单选择。工坊预览是本地 2.5D 渲染，不需要启动 CS2。刀具不支持贴纸或挂件。

### 简体中文

简体中文是一等语言：面板文案、刀名、手套名、皮肤名来自本地 catalog 数据，搜索可以命中当前显示语言名称、英文名称和 ID。

## 开始之前

> [!WARNING]
> 安装、修复、恢复以及修改实验性设置之前必须完整关闭 CS2

- 仅支持 Windows
- 把 ZIP 完整解压到普通文件夹后再打开 Panel，不要直接在压缩包内运行
- Panel 可执行文件、`addons`、`LICENSE`、`README.md`、`UPSTREAM.md` 与 `plus-payload-manifest.json` 需要放在同一个文件夹
- 正确的游戏目录是以 `Counter-Strike Global Offensive\game\csgo` 结尾、且直接包含 `gameinfo.gi` 的那个；不要选择 CS2 根目录、`game`、`bin` 或 Panel 所在目录
- Panel 记忆、日志、备份和玩家预设保存在 Panel 旁边的便携式 `.csbip` 文件夹

## 四步完成首次安装

1. **选择面板语言。** 只改变 Panel 显示，不向 CS2 写入任何内容
2. **确认 `game/csgo` 游戏目录。** Panel 会搜索 Steam 注册表、所有 `libraryfolders.vdf` 和 CS2 应用清单；只有一个有效安装时自动选中，存在多个时需要你选择 Steam 实际启动的那一份，只有自动检测失败时才手动浏览
3. **检查安装计划。** 改动文件之前先给出环境判定：纯净 CS2、已纳管安装、旧版安装、上游原版插件，或不完整或混合环境；混合或未知会禁止自动安装
4. **执行安装。** 事务日志会校验每一个复制的文件，任一步失败都会回滚已完成的步骤。事务运行期间不要启动 CS2、关闭 Panel 或反复点击安装

## 更新方式

Local Cosmetics 没有自动更新通道，也不发布更新清单：Panel 不会下载其他项目的发布包，已发布面板中不存在任何把上游构建当作“本项目更新”覆盖安装的路径。更新方式是关闭 CS2 和旧 Panel，把新包解压到同一个便携目录，并保留隐藏的 `.csbip` 文件夹。如果必须更换面板目录，先把旧的 `.csbip` 完整复制到新 Panel 旁边再打开，原始备份、安装登记、玩家预设和日志才不会断开。

上游同步通过 Git 审查进行，而不是通过发布通道，详见 `docs/UPSTREAM.md`。

玩家饰品 JSON 不会被当成负载损坏文件。环境被判定为混合或未知时不要继续手动覆盖：先导出诊断，再使用 **恢复纯净 CS2**，完成 Steam 文件验证后重新执行干净的首次安装。

## 安装状态、恢复与诊断

**设置 → 安装与恢复** 显示环境判定、已安装版本、受管文件健康状态、备份位置和可执行的操作。ownership 边界就是 `plus-payload-manifest.json`：只有本项目能够证明属于自己的文件才会被替换或删除。

| 操作 | 什么时候用 | 结果 |
| --- | --- | --- |
| 校验安装 | 想要一份新的健康结果 | 只读的受管文件检查 |
| 修复安装 | 受管文件缺失或损坏 | 只重装受影响的本项目文件 |
| 恢复原始文件 | 需要回滚一次受管安装 | 还原安装时记录的备份，并删除本项目创建的文件 |
| 恢复纯净 CS2 | 需要移除全部已识别的插件文件 | 删除已识别插件文件，保留未知第三方文件，然后提示去 Steam 校验游戏文件 |
| 导出诊断 | 问题可复现或原因不明确 | 生成 ZIP 并自动打开所在目录 |

已保存的刀、手套、枪械预设采用 preserve-config 策略，修复和恢复都不会覆盖它们；受管恢复还会先把它们复制到 `.csbip/presets`。你自己的 `cfg`、`autoexec`、bind 以及 Panel 无法判定归属的第三方文件都会原样保留。

## 常见问题

**所有目录和文件状态都是红色** —— Panel 没有找到有效的 `game/csgo` 目录。打开 **设置 → 目录**，选择直接包含 `gameinfo.gi` 的文件夹后重新检查。

**环境被判定为混合或未知** —— 在删除或覆盖任何文件之前先导出诊断，然后使用 **恢复纯净 CS2**，在 Steam 中校验游戏文件，再执行干净的首次安装。

**按钮不可用或安装看起来卡住** —— 所选 CS2 很可能仍在运行，或另一个安装事务仍持有文件锁。完整关闭 CS2，等待 `cs2.exe` 消失，保持 Panel 打开，状态刷新后重试。

**某个受管文件被报告为已修改** —— 先点 **校验安装**；只有确认受管文件真的缺失或损坏才使用 **修复安装**，修复期间必须关闭 CS2。饰品预设不是损坏。

**饰品没有生效** —— 这一局必须是从 Panel 启动的；直接从 Steam 启动的 CS2 是有意保持未修改状态。确认当前 CT 或 T 的刀具、手套和武器预设已启用，再依次尝试校验与修复，最后才考虑恢复操作。

**恢复原始文件后仍然不是纯净 CS2** —— **恢复原始文件**只回到受管安装记录里的安装前状态，而安装前状态本身可能已经包含旧版安装或上游插件。需要删除全部能够确认的插件文件时使用 **恢复纯净 CS2**，并在启动游戏前完成 Steam 文件验证。

**CS2 卡死或闪退** —— 立刻重新打开 Panel 使用 **导出诊断**，并附上地图、游戏类型、阵营和准确复现步骤。强杀 `cs2.exe` 会故意留下未闭合的启动事务；下一次 Panel 操作会完成恢复，游戏也会在加载时自愈搜索路径。

## 明确不包含的内容

增强 Bot AI 与难度预设、Bot 瞄准与购买系统、投掷物系统、Bot 档案与队伍注入、Bot 随机化与伪装、RayTrace、比赛协调、评分、遥测、统计、Demo、战队阵容、游戏内 Overlay 界面，以及上游的在线更新通道。打包 gate 会断言这些组件都不进入发布包。

## 遗留命名

产品名是 Local Cosmetics，但 Panel 可执行文件仍叫 `cs2-bot-improver-plus-panel.exe`，窗口品牌仍显示 **Local Arena**，数据仍存放在 `.csbip`。这些标识暂时有意保留，以免破坏现有安装、备份和预设的兼容性。

## 上游代码来源与署名

- [numakkiyu/Local-Arena](https://github.com/numakkiyu/Local-Arena) —— 面板与玩家饰品插件的主要技术基底，AGPL-3.0
- [ed0ard/CS2-Bot-Improver](https://github.com/ed0ard/CS2-Bot-Improver) —— CS2 / CounterStrikeSharp 兼容性工作的参考上游与署名对象；其增强 Bot 运行内容不在本项目发布包中
- [Metamod:Source](https://github.com/alliedmodders/metamod-source) 与 [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp) —— 固定的运行依赖，打包时按 SHA-256 校验
- 饰品数据：[Nereziel/cs2-WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints)（GPL-3.0）、[ByMykel/CSGO-API](https://github.com/ByMykel/CSGO-API)（MIT）、[SteamTracking/GameTracking-CS2](https://github.com/SteamTracking/GameTracking-CS2)（未发布许可证，仅作为事实型 schema 参考）

固定版本、哈希以及完整的“不带入清单”见 `docs/UPSTREAM.md`；同样的信息也展示在 Panel 的 **设置 → 关于** 页面。

Local Cosmetics 与上述上游项目不存在隶属、授权或支持关系。

## 许可证

[AGPL-3.0](LICENSE) —— 适用的上游版权、来源与署名声明均予以保留。
