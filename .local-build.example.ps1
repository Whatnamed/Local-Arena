# Machine-local build override template.
#
# Copy this file to the repository root as `.local-build.ps1` (already gitignored)
# only when the tools you want are NOT reachable from PATH. `scripts/build.ps1` dot-sources
# that file before applying its own defaults, and `scripts/verify-workspace.ps1` treats it as
# optional. A fresh clone that satisfies the prerequisites in CONTRIBUTING.md needs no
# `.local-build.ps1` at all.
#
# Every value below is a placeholder. Never commit real machine paths.

# Absolute path to a dotnet executable, or a bare name resolved from PATH.
# $DotNet = "C:\path\to\dotnet.exe"

# Rust driver and compiler. `cargo` normally resolves the toolchain itself, so bare names are fine.
# $Cargo = "cargo"
# $Rustc = "rustc"

# Rust toolchain triple passed to cargo when a specific one is required.
# $RustToolchain = "stable-x86_64-pc-windows-msvc"

# Redirect Cargo / rustup caches away from the user profile. Keep them under the ignored `.cache/`.
# $CargoHome = "C:\path\to\repo\.cache\cargo-home"
# $RustupHome = "C:\path\to\repo\.cache\rustup"

# Directory containing node.exe / npm, added to PATH for the Panel build.
# $NodeBin = "C:\path\to\node"
# $Npm = "npm"
