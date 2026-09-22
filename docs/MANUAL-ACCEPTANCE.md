# Manual Acceptance Checklist

本清单专门用于需要实际启动 CS2、观察 WebView2 窗口或进行视觉判断才能确认的行为。Coding agent 不应自行启动 CS2；源码、测试、构建和静态检查不能代替本清单。

## A. 原 Local Arena 模式和启动

- [ ] Local、Preview、Bots、Online 等原有模式仍可从 Panel 正常选择和启动。
- [ ] 原有模式切换不会让 Panel 或 CS2 卡死、重复启动或丢失用户配置。
- [ ] Online 模式仍遵循原 Local Arena 的安全提示和启动约束；不要把本清单当成 VAC 或 Valve 政策保证。
- [ ] Panel 关闭、CS2 正常退出、CS2 异常退出后，重新打开 Panel 能看到合理的模式和安装状态。

## B. Bot、Match、Stats 回归

- [ ] 原有 Bot 功能、Bot 难度和体验仍可用，没有因为饰品改动被裁剪或替换。
- [ ] Match / Stats / 历史记录入口仍可访问，原有数据流程没有被本轮改动破坏。
- [ ] 现有 Local Arena UI 的主导航和相关页面仍在，没有被误改成 Cosmetics-only Panel。

## C. 刀具和快捷刀

准备至少：Karambit、Butterfly、M9 Bayonet、Bayonet、Skeleton、Falchion。

- [ ] 每把刀的模型、动画、HUD 和音效正常。
- [ ] 每把刀能够保存自己的独立 PaintKit；来回切换后各自恢复正确皮肤。
- [ ] `\\` 快捷功能按启用的列表轮换，默认顺序为 Karambit → Butterfly → M9 → Bayonet → Skeleton → Falchion。
- [ ] 快捷切换不在地面生成多余刀具，不会出现旧刀消失、永久没刀、跳过一个位置或错误 rollback 提示。
- [ ] 没有当前阵营 preset 时仍能切换刀型并呈现 Vanilla / default 路径；不会偷偷复制另一阵营 preset。
- [ ] 快捷功能关闭时不修改 `\\` 或其他按键。
- [ ] 运行中从 Panel 改刀型 / 刀皮能在安全时机应用；无法立即刷新时会在下一安全事件生效。

## D. 手套、音乐盒和图片

- [ ] 手套型号和 PaintKit 可以正常选择，模型 / bodygroup 没有裸手、重叠或持续闪烁。
- [ ] 手套名称显示可靠的 Simplified Chinese；英文名称、PaintKit 和 defindex 搜索也能命中。
- [ ] 音乐盒 picker 图片和名称正常，失败图片有可见 fallback，不出现大面积空白。
- [ ] 刀和枪 picker 的图片不因同一 CDN / WebView2 问题大面积失效。

## E. 枪械拾取和重新发装备

- [ ] 玩家购买、出生发放或本项目明确创建的枪械应用当前阵营自己的 preset。
- [ ] 拾取 Bot / 地面同型号枪时，如果当前阵营配置了该 weapon preset，Local Arena 可以按原逻辑应用自己的 preset。
- [ ] 如果当前阵营没有对应 preset，拾取不会无意义重写实体状态。
- [ ] 回防完成选枪后，配置的刀不会恢复成 Steam 默认刀。
- [ ] 特殊游戏模式重新发装备、respawn 或 loadout pipeline 创建新刀后，Knife phase 能重新应用配置。
- [ ] 上述枪械 / 刀具行为在回合切换和死亡重生后仍一致。

## F. Panel 生命周期和窗口恢复

- [ ] 配置保存后重开 Panel，预设仍在。
- [ ] CS2 运行期间修改配置不会要求重启整个游戏才能保存。
- [ ] 游戏退出后 Panel 不会留下无法恢复的任务栏缩略图或 Alt-Tab 窗口。
- [ ] 单实例第二次启动能唤醒已有窗口；窗口可见、未最小化、位置在屏幕内并获得合理焦点。
- [ ] Panel 强制结束、CS2 异常结束、连续点击启动后，再次打开 Panel 能恢复到可操作状态。

## G. 安装、恢复和 updater

- [ ] 安装 / 修复前后 `FollowCS2ServerGuidelines` 与饰品功能兼容；未知 `core.json` 字段仍保留。
- [ ] restore / uninstall 能按 ownership 恢复原 property，不删除未知第三方插件或个人 cfg / autoexec / bind。
- [ ] 应用内没有会把个人 fork 覆盖成官方 Local Arena release 的“更新”操作。
- [ ] 只读依赖 / 上游版本查看不会下载或安装官方 payload。

## H. 性能和体验

- [ ] 在相同地图、Bot 数量和图形设置下，饰品功能没有明显持续卡顿、周期性 hitch 或异常冻结。
- [ ] Panel 后台 / 最小化时没有明显额外干扰。
- [ ] 没有观察到持续增长的 CPU、内存或重复应用风暴。

## I. 回归记录建议

每次完整回归记录日期、CS2 build、MetaMod / CounterStrikeSharp 版本、本项目 commit、测试地图与 Bot 数量、失败项目和复现步骤。需要真实 CS2 进程、WebView2 composition 或视觉判断的结果由用户记录后交回 Agent 复审。
