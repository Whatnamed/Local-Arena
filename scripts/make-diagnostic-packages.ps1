param(
    [string]$OutputDirectory = "artifacts\diagnostic"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$stageBase = Join-Path $repo ".cache\package\stage-build\LocalArena-v1.4.3.3-windows"

if (-not (Test-Path -LiteralPath $stageBase)) {
    throw "Base stage build not found at $stageBase. Run scripts/package.ps1 first."
}

# Load DiagnosticTransaction helpers
. (Join-Path $PSScriptRoot "DiagnosticTransaction.ps1")

$output = Join-Path $repo $OutputDirectory
New-Item -ItemType Directory -Path $output -Force | Out-Null

function Update-PayloadManifest {
    param([string]$PayloadRoot, [string]$PackageVersion = "1.4.3.3-diag")
    $manifestEntries = foreach ($topLevel in @("addons", "cfg", "overrides")) {
        $root = Join-Path $PayloadRoot $topLevel
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($PayloadRoot, $file.FullName).Replace("\", "/")
            $plusOwned = $relative -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/*" -or
                $relative -like "addons/counterstrikesharp/plugins/BotHiderImpl/*" -or
                $relative -like "addons/counterstrikesharp/plugins/PlusMatchCoordinator/*" -or
                $relative -like "addons/counterstrikesharp/plugins/TeamLineupInjector/*" -or
                $relative -like "addons/counterstrikesharp/plugins/OfflineMatchTelemetry/*" -or
                $relative -like "addons/counterstrikesharp/shared/BotHiderApi/*" -or
                $relative -in @("cfg/my_bot_ffa_config.cfg", "cfg/my_bot_normal_config.cfg")
            $component = if ($relative -like "addons/counterstrikesharp/plugins/*") {
                ($relative -split "/")[3]
            }
            elseif ($relative -like "addons/BotHider/*") { "BotHider" }
            elseif ($relative -like "addons/RayTrace/*") { "RayTrace" }
            elseif ($relative -like "cfg/*") { "configuration" }
            elseif ($relative -like "overrides/*") { "overrides" }
            else { "runtime" }
            $preserveConfig = $relative -like "*/PlayerKnifeCustomizer/player_*_presets.json" -or
                $relative -in @(
                    "addons/counterstrikesharp/configs/core.json",
                    "addons/counterstrikesharp/plugins/BotRandomizer/bot_randomizer_options.json",
                    "cfg/my_bot_ffa_config.cfg",
                    "cfg/my_bot_normal_config.cfg",
                    "overrides/botprofile.vpk"
                )
            [ordered]@{
                path = $relative
                size = $file.Length
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                component = $component
                ownership = if ($plusOwned) { "plus" } else { "shared" }
                restore_policy = if ($preserveConfig) { "preserve-config" } else { "restore" }
            }
        }
    }
    $payloadManifest = [ordered]@{
        schema_version = 1
        package_version = $PackageVersion
        entries = @($manifestEntries | Sort-Object path)
    }
    $payloadManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PayloadRoot "plus-payload-manifest.json") -Encoding utf8
}

# Generate diagnostic runtime manifest covering exact files in runtime trees and loaders
Write-Host "Generating diagnostic runtime manifest from base stage..."
$runtimeManifest = New-DiagnosticRuntimeManifest $stageBase
$runtimeManifestJson = $runtimeManifest | ConvertTo-Json -Depth 5
$artifactsRuntimeManifest = Join-Path $output "diagnostic-runtime-manifest.json"
$runtimeManifestJson | Set-Content -LiteralPath $artifactsRuntimeManifest -Encoding utf8
Write-Host "Diagnostic runtime manifest: $($runtimeManifest.file_count) runtime files and loaders across $($runtimeManifest.trees.Count) trees."

function Copy-DiagnosticTooling {
    param([string]$StageRoot, [string]$Mode)
    
    $scriptsDir = Join-Path $StageRoot "scripts"
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo "scripts\DiagnosticTransaction.ps1") -Destination (Join-Path $scriptsDir "DiagnosticTransaction.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repo "scripts\install-diagnostic.ps1") -Destination (Join-Path $scriptsDir "install-diagnostic.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repo "scripts\verify-diagnostic-install.ps1") -Destination (Join-Path $scriptsDir "verify-diagnostic-install.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repo "scripts\restore-normal-install.ps1") -Destination (Join-Path $scriptsDir "restore-normal-install.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $repo "scripts\dependencies.json") -Destination (Join-Path $scriptsDir "dependencies.json") -Force
    Copy-Item -LiteralPath $artifactsRuntimeManifest -Destination (Join-Path $scriptsDir "diagnostic-runtime-manifest.json") -Force
    Copy-Item -LiteralPath $artifactsRuntimeManifest -Destination (Join-Path $StageRoot "diagnostic-runtime-manifest.json") -Force

    @"
param([string]`$Cs2Root)
& (Join-Path `$PSScriptRoot "scripts\install-diagnostic.ps1") -Mode $Mode -Cs2Root `$Cs2Root -PackageSource `$PSScriptRoot
"@ | Set-Content -LiteralPath (Join-Path $StageRoot "INSTALL-DIAGNOSTIC-$Mode.ps1") -Encoding utf8

    @"
param([string]`$Cs2Root, [string]`$Mode = "$Mode")
& (Join-Path `$PSScriptRoot "scripts\verify-diagnostic-install.ps1") -Mode `$Mode -Cs2Root `$Cs2Root
"@ | Set-Content -LiteralPath (Join-Path $StageRoot "VERIFY-DIAGNOSTIC.ps1") -Encoding utf8

    @"
param([string]`$Cs2Root)
& (Join-Path `$PSScriptRoot "scripts\restore-normal-install.ps1") -Cs2Root `$Cs2Root
"@ | Set-Content -LiteralPath (Join-Path $StageRoot "RESTORE-NORMAL.ps1") -Encoding utf8
}

# --- Package A: Runtime only (BotHider OFF, PlayerCosmetics OFF) ---
Write-Host "Preparing Diagnostic Package A (Runtime Only)..."
$stageA = Join-Path $output "stage-diagA"
if (Test-Path -LiteralPath $stageA) { Remove-Item -LiteralPath $stageA -Recurse -Force }
New-Item -ItemType Directory -Path $stageA -Force | Out-Null
Copy-Item -Path (Join-Path $stageBase "*") -Destination $stageA -Recurse -Force

# BotHider OFF via .csbip-disabled rename
$botHiderVdfA = Join-Path $stageA "addons\metamod\BotHider.vdf"
$botHiderVdfDisabledA = Join-Path $stageA "addons\metamod\BotHider.vdf.csbip-disabled"
if (Test-Path -LiteralPath $botHiderVdfA) {
    Move-Item -LiteralPath $botHiderVdfA -Destination $botHiderVdfDisabledA -Force
}

$botHiderImplA = Join-Path $stageA "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
$botHiderImplDisabledA = Join-Path $stageA "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
if (Test-Path -LiteralPath $botHiderImplA) {
    Move-Item -LiteralPath $botHiderImplA -Destination $botHiderImplDisabledA -Force
}

# PlayerCosmetics OFF via .csbip-disabled rename
$knifeDllA = Join-Path $stageA "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"
$knifeDllDisabledA = Join-Path $stageA "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"
if (Test-Path -LiteralPath $knifeDllA) {
    Move-Item -LiteralPath $knifeDllA -Destination $knifeDllDisabledA -Force
}

# Diagnostic state marker
$markerA = [ordered]@{
    mode = "A"
    metamod = "2.0.0-git1469"
    counterstrikesharp = "1.0.375"
    bot_hider_native = $false
    bot_hider_impl = $false
    player_cosmetics = $false
}
$markerA | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stageA "diagnostic-state.json") -Encoding utf8

Copy-DiagnosticTooling $stageA "A"

@"
===================================================================
Local Arena Diagnostic Package A: Runtime-Only Baseline
===================================================================

Isolation & Transaction Contract:
- Narrow Mutation Surface: Diagnostic installer only mutates MM1469/CSS375 runtime
  trees, official loaders, and the 3 target components. It does NOT overwrite
  other existing plugins, shared libraries, cfgs, or overrides.
- Clean Runtime Purge: Target runtime trees are purged prior to installation
  to eliminate any stale CSS371 or Metamod residue.
- Pre-Diagnostic Snapshot: Created automatically at <csgo>/.csbip/diagnostic-snapshot
  before files are modified. Reversible via RESTORE-NORMAL.ps1.
- Metamod:Source: 2.0.0-git1469 (ACTIVE)
- CounterStrikeSharp: v1.0.375 (ACTIVE)
- BotHider native: OFF (disabled via BotHider.vdf.csbip-disabled)
- BotHiderImpl: OFF (disabled via BotHiderImpl.dll.csbip-disabled)
- PlayerCosmetics: OFF (disabled via PlayerKnifeCustomizer.dll.csbip-disabled)
- BotAI / BotRandomizer / NadeSystem / MatchCoordinator / RayTrace: ON (ACTIVE)

Background & Root-Cause Status:
- Proven: CounterStrikeSharp 371 signature CEntityInstance_AcceptInput has 0 matches
  in CS2 1.41.8.2 server.dll, while CSS 375 matches uniquely.
- Strong correlation: All failing cosmetic surfaces (knife ChangeSubclass, glove
  bodygroup, legacy-model gun bodygroup) rely on AcceptInput.
- Not yet proven: The exact internal entity replication mechanism of the CopyExistingEntity
  client crash. This A/B diagnostic isolates runtime vs cosmetics to converge on root cause.

Installation:
DO NOT use Panel to install or launch this diagnostic build. Panel mode switching
automatically re-enables disabled components in Enhanced Bots mode.
Instead, run:
  pwsh .\INSTALL-DIAGNOSTIC-A.ps1 -Cs2Root "<path-to-game/csgo>"
Verify after install:
  pwsh .\VERIFY-DIAGNOSTIC.ps1 -Cs2Root "<path-to-game/csgo>"

Manual Test Procedure:
1. Ensure CS2 is closed before running INSTALL-DIAGNOSTIC-A.ps1.
2. Run VERIFY-DIAGNOSTIC.ps1 and confirm:
   - Exact runtime tree verified (matches manifest with 0 stale residues)
   - MM 1469 active
   - CSS 375 active
   - BotHider OFF
   - BotHiderImpl OFF
   - PlayerCosmetics OFF
3. Launch CS2 (directly or via Steam with -insecure).
4. Start an Offline match with Enhanced Bots.
5. Stand still for 10 seconds after spawn.
6. Press 1 -> 2 -> 3 normally.
7. Switch back and forth between weapons several times.
8. Observe whether CopyExistingEntity client crash occurs.

Decision Gate:
- If Package A crashes: STOP. The crash is in the base runtime / bot components, not cosmetics. Do not test B.
- If Package A does NOT crash: Proceed to Package B.
- To abort or restore original pre-test state at any time:
  pwsh .\RESTORE-NORMAL.ps1 -Cs2Root "<path-to-game/csgo>"
"@ | Set-Content -LiteralPath (Join-Path $stageA "DIAGNOSTIC-MODE-A.txt") -Encoding utf8

Update-PayloadManifest $stageA "1.4.3.3-diagA"
$zipA = Join-Path $output "LocalArena-diagA-runtime-only.zip"
if (Test-Path -LiteralPath $zipA) { Remove-Item -LiteralPath $zipA -Force }
Compress-Archive -Path (Join-Path $stageA "*") -DestinationPath $zipA -CompressionLevel Optimal
Write-Host "Diagnostic Package A ready: $zipA"

# --- Package B: Cosmetics Only (BotHider OFF, PlayerCosmetics ON) ---
Write-Host "Preparing Diagnostic Package B (Human Cosmetics Only)..."
$stageB = Join-Path $output "stage-diagB"
if (Test-Path -LiteralPath $stageB) { Remove-Item -LiteralPath $stageB -Recurse -Force }
New-Item -ItemType Directory -Path $stageB -Force | Out-Null
Copy-Item -Path (Join-Path $stageBase "*") -Destination $stageB -Recurse -Force

# BotHider OFF via .csbip-disabled rename
$botHiderVdfB = Join-Path $stageB "addons\metamod\BotHider.vdf"
$botHiderVdfDisabledB = Join-Path $stageB "addons\metamod\BotHider.vdf.csbip-disabled"
if (Test-Path -LiteralPath $botHiderVdfB) {
    Move-Item -LiteralPath $botHiderVdfB -Destination $botHiderVdfDisabledB -Force
}

$botHiderImplB = Join-Path $stageB "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
$botHiderImplDisabledB = Join-Path $stageB "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
if (Test-Path -LiteralPath $botHiderImplB) {
    Move-Item -LiteralPath $botHiderImplB -Destination $botHiderImplDisabledB -Force
}

# PlayerCosmetics ON (ensure active DLL is present, remove any .csbip-disabled residue)
$knifeDllDisabledB = Join-Path $stageB "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"
if (Test-Path -LiteralPath $knifeDllDisabledB) {
    Remove-Item -LiteralPath $knifeDllDisabledB -Force
}

# Diagnostic state marker
$markerB = [ordered]@{
    mode = "B"
    metamod = "2.0.0-git1469"
    counterstrikesharp = "1.0.375"
    bot_hider_native = $false
    bot_hider_impl = $false
    player_cosmetics = $true
}
$markerB | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stageB "diagnostic-state.json") -Encoding utf8

Copy-DiagnosticTooling $stageB "B"

@"
===================================================================
Local Arena Diagnostic Package B: Human Cosmetics Only
===================================================================

Isolation & Transaction Contract:
- Narrow Mutation Surface: Diagnostic installer only mutates MM1469/CSS375 runtime
  trees, official loaders, and the 3 target components. It does NOT overwrite
  other existing plugins, shared libraries, cfgs, or overrides.
- Clean Runtime Purge: Target runtime trees are purged prior to installation
  to eliminate any stale CSS371 or Metamod residue.
- Pre-Diagnostic Snapshot: Preserved from Package A (original pre-test state is retained).
- Metamod:Source: 2.0.0-git1469 (ACTIVE)
- CounterStrikeSharp: v1.0.375 (ACTIVE)
- BotHider native: OFF (disabled via BotHider.vdf.csbip-disabled)
- BotHiderImpl: OFF (disabled via BotHiderImpl.dll.csbip-disabled)
- PlayerCosmetics: ON (ACTIVE, built from commit 8cddb93+d27c050 on CSS 375)
- BotAI / BotRandomizer / NadeSystem / MatchCoordinator / RayTrace: ON (ACTIVE)

Background & Root-Cause Status:
- Proven: CounterStrikeSharp 371 signature CEntityInstance_AcceptInput has 0 matches
  in CS2 1.41.8.2 server.dll, while CSS 375 matches uniquely.
- Strong correlation: All failing cosmetic surfaces (knife ChangeSubclass, glove
  bodygroup, legacy-model gun bodygroup) rely on AcceptInput.
- Not yet proven: The exact internal entity replication mechanism of the CopyExistingEntity
  client crash.

Prerequisite:
Test Package B ONLY after Package A has passed without crashes!

Installation:
DO NOT use Panel to install or launch this diagnostic build.
Run:
  pwsh .\INSTALL-DIAGNOSTIC-B.ps1 -Cs2Root "<path-to-game/csgo>"
Verify after install:
  pwsh .\VERIFY-DIAGNOSTIC.ps1 -Cs2Root "<path-to-game/csgo>"

Manual Test Procedure:
1. Ensure CS2 is closed before running INSTALL-DIAGNOSTIC-B.ps1.
2. Run VERIFY-DIAGNOSTIC.ps1 and confirm:
   - Exact runtime tree verified (matches manifest with 0 stale residues)
   - MM 1469 active
   - CSS 375 active
   - BotHider OFF
   - BotHiderImpl OFF
   - PlayerCosmetics ON (verified against current build hash)
3. Launch CS2.
4. Start an Offline match with Enhanced Bots.
5. Wait 10 seconds after spawn.
6. Press 3 to switch to knife. Inspect default custom knife model.
7. Press the quick knife cycle key once.
8. Wait 2 seconds.
9. Press quick knife cycle key a second time.
10. Check gloves.
11. Test M4A4 paint 632 (Desolate Space, legacy_model=true).
12. Test P250 paint 258 (Supernova, legacy_model=true).
13. Test AK-47 / AWP skins as control.
14. Observe whether CopyExistingEntity client crash occurs.

Post-Test:
To restore exact pre-diagnostic environment when testing is complete:
  pwsh .\RESTORE-NORMAL.ps1 -Cs2Root "<path-to-game/csgo>"
"@ | Set-Content -LiteralPath (Join-Path $stageB "DIAGNOSTIC-MODE-B.txt") -Encoding utf8

Update-PayloadManifest $stageB "1.4.3.3-diagB"
$zipB = Join-Path $output "LocalArena-diagB-cosmetics-only.zip"
if (Test-Path -LiteralPath $zipB) { Remove-Item -LiteralPath $zipB -Force }
Compress-Archive -Path (Join-Path $stageB "*") -DestinationPath $zipB -CompressionLevel Optimal
Write-Host "Diagnostic Package B ready: $zipB"

# Write SHA256 sums
$diagZips = @($zipA, $zipB)
$lines = foreach ($z in $diagZips) {
    "$((Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($z))"
}
$sumsPath = Join-Path $output "SHA256SUMS.txt"
[IO.File]::WriteAllText($sumsPath, ($lines -join "`n") + "`n")
Write-Host "Diagnostic SHA256 manifest ready: $sumsPath"
