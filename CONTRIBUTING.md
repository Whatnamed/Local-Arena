# Contributing

## Lineage and scope

This repository is a **personal fork** of [Local Arena](https://github.com/numakkiyu/Local-Arena). Selected AGPL-3.0
enhanced-bot components are ultimately derived from [`ed0ard/CS2-Bot-Improver`](https://github.com/ed0ard/CS2-Bot-Improver)
and may receive audited compatibility updates from that source. Preserve source attribution when adapting upstream code.

Development happens only on this fork. `numakkiyu/Local-Arena` and `ed0ard/CS2-Bot-Improver` are read-only references.
Product boundaries are defined in [`docs/PRODUCT-SCOPE.md`](docs/PRODUCT-SCOPE.md); documentation categories in
[`docs/README.md`](docs/README.md); agent rules in [`AGENTS.md`](AGENTS.md). Runtime dependency pins live in
`scripts/dependencies.json` — do not copy version numbers into other files.

## Development rules

1. Do not commit `bin`, `obj`, `node_modules`, `dist`, `target`, downloaded release archives, or third-party native DLLs.
2. Add every visible Panel string to `Panel/src/i18n/keys.ts`. Add locale overrides in `Panel/src/i18n/dictionary.ts`;
   never hardcode a new UI sentence in a component.
3. Keep saved cosmetic data language-independent. Persist numeric item definition indexes, paint kits, seeds, wear, and
   flags, not translated display names.
4. Keep normal matchmaking isolated from Metamod and player cosmetics. Changes to mode switching require Rust tests.
5. Preserve the package's upstream-compatible `game/csgo` copy layout.
6. Anything that needs a running CS2 process, real WebView2 composition, or a visual judgement is verified by hand and
   recorded in [`docs/MANUAL-ACCEPTANCE.md`](docs/MANUAL-ACCEPTANCE.md). Build success is not acceptance.

## Toolchain prerequisites

`scripts/build.ps1` runs on Windows and needs all of the following reachable. It resolves them from PATH, or from an
optional machine-local override (see below).

- **Git** with the pinned upstream commit fetched, so the upstream-diff whitelist can be evaluated.
- **Node.js and npm** for the Panel web build.
- **.NET SDK 10** for the CounterStrikeSharp plugin projects and their test projects.
- **Rust** whose host is `x86_64-pc-windows-msvc` (`build.ps1` throws if the selected toolchain reports another host).
- **Visual Studio 2022 or Build Tools with the VC++ x64 toolset and a Windows 10/11 SDK.** The native Panel build uses
  the MSVC toolchain: `build.ps1` looks for `cl.exe`, `link.exe` and `rc.exe`, and when they are not on PATH it locates
  a Visual Studio install through `vswhere.exe` and imports `VC\Auxiliary\Build\vcvars64.bat`. Running from a
  Developer PowerShell works too. Visual Studio is **required** unless those three tools are already on PATH.

Caches stay inside the repository: `build.ps1` points `CARGO_HOME`, `DOTNET_CLI_HOME`, `NUGET_PACKAGES`,
`NUGET_HTTP_CACHE_PATH` and `npm_config_cache` at the ignored `.cache/`, and the Cargo target directory is
`Panel/src-tauri/target`.

### Optional machine-local override

If a tool is not on PATH, copy `.local-build.example.ps1` to `.local-build.ps1` (gitignored) and set only the variables
you need. `build.ps1` dot-sources it before applying defaults. It is a convenience override, not a repository
requirement — a fresh clone that meets the prerequisites above builds and verifies without it.

## Build

```powershell
npm --prefix Panel ci
npm --prefix Panel run build
.\scripts\build.ps1
```

`build.ps1` accepts explicit tool locations and switches; all are optional:
`-DotNet`, `-Cargo`, `-Rustc`, `-RustToolchain`, `-CargoHome`, `-RustupHome`, `-NodeBin`, `-Npm`, `-SkipNpmInstall`.
It also runs the Panel test scripts, the .NET test projects and `cargo test --locked`, so it is the single heaviest
check. For a faster loop the individual gates are:

```powershell
npm --prefix Panel run test:stickers
npm --prefix Panel run test:install-gate
npm --prefix Panel run test:cosmetic-media
.\scripts\verify-workspace.ps1
```

## Package

```powershell
.\scripts\package.ps1 -OutputDirectory .\artifacts
```

`package.ps1` accepts `-DotNet`, `-Cargo`, `-Rustc`, `-RustToolchain`, `-OutputDirectory`, `-CacheKey`,
`-ReleaseVersion`, `-SkipBuild`, `-SkipNpmInstall`. It downloads and SHA-256-verifies every archive in
`scripts/dependencies.json`, assembles the release tree, and emits exactly two files into the output directory:
`LocalArena-<version>-windows.zip` and a `SHA256SUMS.txt` covering it. It does not produce a Panel-only or plugin-only
ZIP, `latest.json`, or a signature — this fork publishes no GitHub Release and runs no update channel, per
`docs/PRODUCT-SCOPE.md`. After packaging, inspect the ZIP file list and `SHA256SUMS.txt`, then smoke-test on a
disposable CS2 copy against `docs/MANUAL-ACCEPTANCE.md`.
