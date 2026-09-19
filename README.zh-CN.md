# Local Cosmetics

[English](README.md) | **简体中文**

Local Cosmetics 是一个独立的 Windows 离线 CS2 工具，用于配置玩家刀具、手套、枪械涂装、音乐盒、贴纸、挂件和探员。

v1 安装包明确是 Cosmetics-only：只包含 MetaMod:Source、CounterStrikeSharp、PlayerCosmetics 插件、Panel 以及安装/恢复/诊断所需的最小运行时。不包含增强 Bot AI、BotRandomizer、NadeSystem、RayTrace、BotHider、Bot profile、比赛协调、rating、telemetry、统计或 Demo runtime。

## 安全边界

- 用户直接从 Steam 启动 CS2 时仍是普通、干净的游戏路径。只有用户在 Panel 中显式选择“饰品预览”并从 Panel 启动时，才会准备本地 runtime。
- 饰品预览使用 `-insecure`，不能用于官方匹配。
- Panel 使用事务式安装、备份、哈希校验、修复、恢复和窄 ownership manifest；未知第三方文件以及个人 cfg / autoexec / bind 默认保留。
- v1 已关闭 upstream 或 fork 的在线安装更新。请手动安装经过审查的 `LocalCosmetics-v*-windows.zip`。
- coding agent 不把未实机验证的游戏内行为报告为已通过。安装后请按 [docs/MANUAL-ACCEPTANCE.md](docs/MANUAL-ACCEPTANCE.md) 手动验收。

## 构建与测试

在仓库根目录使用 PowerShell：

```powershell
npm.cmd ci
npm.cmd run test:stickers
npm.cmd run test:install-gate
npm.cmd run test:cosmetics-catalog
npm.cmd run build
cargo test --locked --manifest-path Panel/src-tauri/Cargo.toml
```

在 pinned .NET、Rust、LLVM、Cargo Xwin、MetaMod 和 CounterStrikeSharp 依赖齐备时，使用 `scripts/package.ps1` 生成完整 Windows 安装包。

## 来源与许可证

仓库保留适用的 AGPL-3.0 声明、来源和署名信息。详见 [ATTRIBUTION.md](ATTRIBUTION.md) 与 [LICENSE](LICENSE)。
