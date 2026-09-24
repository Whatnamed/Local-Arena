param(
    [string]$OutputDirectory = "artifacts\diagnostic"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$stageBase = Join-Path $repo ".cache\package\stage-build\LocalArena-v1.4.3.3-windows"

if (-not (Test-Path -LiteralPath $stageBase)) {
    throw "Base stage build not found at $stageBase. Run scripts/package.ps1 first."
}

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

# --- Package A: Runtime only (BotHider OFF, PlayerCosmetics OFF) ---
$stageA = Join-Path $output "stage-diagA"
if (Test-Path -LiteralPath $stageA) { Remove-Item -LiteralPath $stageA -Recurse -Force }
New-Item -ItemType Directory -Path $stageA -Force | Out-Null
Copy-Item -Path (Join-Path $stageBase "*") -Destination $stageA -Recurse -Force

# BotHider OFF
Remove-Item -LiteralPath (Join-Path $stageA "addons\metamod\BotHider.vdf") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stageA "addons\BotHider") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stageA "addons\counterstrikesharp\plugins\BotHiderImpl") -Recurse -Force -ErrorAction SilentlyContinue

# PlayerCosmetics OFF
Remove-Item -LiteralPath (Join-Path $stageA "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer") -Recurse -Force -ErrorAction SilentlyContinue

@"
===================================================================
Local Arena Diagnostic Package A: Runtime Only Baseline
===================================================================
Components:
- Metamod:Source: 2.0.0-git1469
- CounterStrikeSharp: v1.0.375
- BotHider native: OFF (disabled)
- BotHiderImpl: OFF (disabled)
- PlayerCosmetics: OFF (disabled)
- BotAI / BotRandomizer / NadeSystem / MatchCoordinator: ON

Test Steps:
1. Extract into game directory (or install via Panel).
2. Launch CS2 in Offline with Enhanced Bots mode.
3. Wait 10 seconds.
4. Press 1 (primary), 2 (secondary), 3 (knife).
5. Switch weapons repeatedly and verify if CopyExistingEntity crash occurs.

Expected Outcome:
If this package does NOT crash, the new MM 1469 + CSS 375 runtime baseline is healthy.
"@ | Set-Content -LiteralPath (Join-Path $stageA "DIAGNOSTIC-MODE-A.txt") -Encoding utf8

Update-PayloadManifest $stageA "1.4.3.3-diagA"
$zipA = Join-Path $output "LocalArena-diagA-runtime-only.zip"
if (Test-Path -LiteralPath $zipA) { Remove-Item -LiteralPath $zipA -Force }
Compress-Archive -Path (Join-Path $stageA "*") -DestinationPath $zipA -CompressionLevel Optimal
Write-Host "Diagnostic Package A ready: $zipA"

# --- Package B: Cosmetics Only (BotHider OFF, PlayerCosmetics ON) ---
$stageB = Join-Path $output "stage-diagB"
if (Test-Path -LiteralPath $stageB) { Remove-Item -LiteralPath $stageB -Recurse -Force }
New-Item -ItemType Directory -Path $stageB -Force | Out-Null
Copy-Item -Path (Join-Path $stageBase "*") -Destination $stageB -Recurse -Force

# BotHider OFF
Remove-Item -LiteralPath (Join-Path $stageB "addons\metamod\BotHider.vdf") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stageB "addons\BotHider") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $stageB "addons\counterstrikesharp\plugins\BotHiderImpl") -Recurse -Force -ErrorAction SilentlyContinue

# PlayerCosmetics ON (uses non-destructive knife path and CSS 375 compiled DLL)

@"
===================================================================
Local Arena Diagnostic Package B: Human Cosmetics Only
===================================================================
Components:
- Metamod:Source: 2.0.0-git1469
- CounterStrikeSharp: v1.0.375
- BotHider native: OFF (disabled)
- BotHiderImpl: OFF (disabled)
- PlayerCosmetics: ON (non-destructive knife path, CSS 375 AcceptInput)
- BotAI / BotRandomizer / NadeSystem / MatchCoordinator: ON

Test Steps:
1. Extract into game directory (or install via Panel).
2. Launch CS2 in Offline with Enhanced Bots mode.
3. Wait 10 seconds after spawn.
4. Press 3 to switch to knife. Inspect default custom knife model.
5. Use quick knife cycle (if bound) or switch between 1/2/3.
6. Check Gloves.
7. Test M4A4 paint 632 (Desolate Space, legacy model).
8. Test P250 paint 258 (Supernova, legacy model).
9. Test control AK-47 / AWP skins.

Expected Outcome:
If Package A is stable and Package B functions correctly without crashes,
the AcceptInput / ChangeSubclass fix has resolved the missing client entity issue.
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
