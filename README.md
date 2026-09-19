# Local Cosmetics

**English** | [简体中文](README.zh-CN.md)

Local Cosmetics is an independent Windows-only, offline CS2 tool for player knives, gloves, weapon finishes, music kits, stickers, charms, and agents.

The v1 package is intentionally Cosmetics-only. It contains MetaMod:Source, CounterStrikeSharp, the PlayerCosmetics plugin, the Panel, and the minimum installation/restore/diagnostics runtime. It does not ship enhanced Bot AI, bot randomizers, NadeSystem, RayTrace, BotHider, bot profiles, match coordination, rating, telemetry, statistics, or Demo runtime.

## Safety boundaries

- Starting CS2 directly from Steam remains the ordinary clean game path. The Panel only prepares the local runtime after the user explicitly selects Cosmetics Preview and launches from the Panel.
- Cosmetics Preview uses `-insecure`; it is not for official matchmaking.
- The Panel uses transactional installation, backups, hash verification, repair, restore, and a narrow ownership manifest. Unknown third-party files and personal cfg/autoexec/binds are preserved.
- Online installation of upstream or fork updates is disabled in v1. Install a reviewed `LocalCosmetics-v*-windows.zip` package manually.
- The coding agent does not claim in-game behavior as tested. Follow [docs/MANUAL-ACCEPTANCE.md](docs/MANUAL-ACCEPTANCE.md) after installing the package.

## Build and test

From the repository root in PowerShell:

```powershell
npm.cmd ci
npm.cmd run test:stickers
npm.cmd run test:install-gate
npm.cmd run test:cosmetics-catalog
npm.cmd run build
cargo test --locked --manifest-path Panel/src-tauri/Cargo.toml
```

The complete Windows release package is produced by `scripts/package.ps1` when the pinned .NET, Rust, LLVM, Cargo Xwin, MetaMod, and CounterStrikeSharp prerequisites are available.

## Source and license

The repository preserves applicable AGPL-3.0 notices and source attribution. See [ATTRIBUTION.md](ATTRIBUTION.md) and [LICENSE](LICENSE).
