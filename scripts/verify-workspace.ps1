[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$ExpectedPackageVersion
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) { $failures.Add($Message) }
function Assert-File([string]$Relative) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $Relative) -PathType Leaf)) {
        Add-Failure "Required source file is missing: $Relative"
    }
}
function Relative-Files([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace("\", "/")
    })
}

foreach ($source in @(
    "LICENSE",
    "README.md",
    "README.zh-CN.md",
    "Panel/src/data/skinNames.json",
    "Panel/src/data/skinImages.json",
    "Panel/src/data/weaponSkins.json",
    "Panel/src/data/gloveSkins.json",
    "Panel/src/data/cosmeticOrdering.ts",
    "Panel/src/panels/WeaponPresetModal.tsx",
    "Panel/src/panels/KnifePresetModal.tsx",
    "Panel/src/panels/GlovePresetModal.tsx",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.cs",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.csproj",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json",
    "scripts/package.ps1",
    "scripts/build.ps1"
)) { Assert-File $source }

$playerCatalog = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json"
$panelCatalog = Join-Path $repo "Panel/src/data/weaponSkins.json"
if ((Get-FileHash -LiteralPath $playerCatalog -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $panelCatalog -Algorithm SHA256).Hash) {
    Add-Failure "Panel and PlayerCosmetics weapon catalogs are not identical."
}

$playerCosmetics = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.cs") -Raw
$coreConfigSource = Get-Content -LiteralPath (Join-Path $repo "Panel/src-tauri/src/core_config.rs") -Raw
if ($playerCosmetics -notmatch "WeaponProvenanceTracker" -or
    $playerCosmetics -notmatch "FileSystemWatcher" -or
    $playerCosmetics -notmatch "hook\.GetReturn<nint>\(\)" -or
    $playerCosmetics -match "OnItemPickup[\s\S]{0,800}ScheduleApplyPipeline" -or
    $playerCosmetics -notmatch "GiveNamedItem<CBasePlayerWeapon>" -or
    $playerCosmetics -notmatch "KnifeShortcutResolver" -or
    $playerCosmetics -notmatch "ApplyVanillaKnife" -or
    $playerCosmetics -match 'weapon\.AcceptInput\("ChangeSubclass"') {
    Add-Failure "PlayerCosmetics provenance, watcher, or pickup boundary is missing."
}
$panelBackend = Get-Content -LiteralPath (Join-Path $repo "Panel/src-tauri/src/lib.rs") -Raw
if ($coreConfigSource -notmatch "FollowCS2ServerGuidelines" -or
    $coreConfigSource -notmatch "ensure_local_mode" -or
    $coreConfigSource -notmatch "restore_owned" -or
    $panelBackend -notmatch "core_config::ensure_local_mode" -or
    $panelBackend -notmatch "core_config::restore_owned" -or
    $panelBackend -notmatch "window\.show\(\)" -or
    $panelBackend -notmatch "window\.unminimize\(\)" -or
    $panelBackend -notmatch "window\.set_focus\(\)") {
    Add-Failure "Local CSS core-config ownership or Panel window restoration path is missing."
}

$packageScript = Get-Content -LiteralPath (Join-Path $repo "scripts/package.ps1") -Raw
$buildScript = Get-Content -LiteralPath (Join-Path $repo "scripts/build.ps1") -Raw
$appSource = Get-Content -LiteralPath (Join-Path $repo "Panel/src/App.tsx") -Raw
$settingsSource = Get-Content -LiteralPath (Join-Path $repo "Panel/src/panels/settings/SettingsView.tsx") -Raw
if ($packageScript -match 'upstream\.windowsAsset|rayTrace|botHider|BotAI|BotRandomizer|PlusMatchCoordinator|OfflineMatchTelemetry|gameinfo\.gi' -or
    $buildScript -match 'BotAI|BotAimImprover|BotBuy|BotRandomizer|NadeSystem|PlusMatchCoordinator|OfflineMatchTelemetry|RayTrace') {
    Add-Failure "Build/package scripts still reference forbidden non-cosmetics runtime components."
}
if ($appSource -match '(?<![A-Za-z])(MatchPanel|MatchHistoryPanel|StatsDashboard|CommandsPanel|PresetsPanel|GuideView)(?![A-Za-z])' -or
    $settingsSource -match 'OnlineUpdatePage|installAllUpdates|installPluginUpdate|installPanelUpdate') {
    Add-Failure "The shipped Panel still exposes a Bot, match, statistics, guide, or online-update product route."
}

$onlineUpdate = Get-Content -LiteralPath (Join-Path $repo "Panel/src-tauri/src/online_update.rs") -Raw
if ($onlineUpdate -match 'numakkiyu/Local-Arena' -or
    $panelBackend -match 'invoke_handler!\[\s*[\s\S]{0,300}install_(panel|plugin|all)_update' -or
    $panelBackend -match 'fn maybe_run_update_helper\(\)[\s\S]{0,120}online_update::maybe_apply_panel_update') {
    Add-Failure "The shipped Panel still has an upstream online update installation path."
}

if ($PackageRoot) {
    $root = (Resolve-Path -LiteralPath $PackageRoot).Path
    $files = Relative-Files $root
    $forbidden = '(?i)(^|/)(BotAI|BotAimImprover|BotBuy|BotController|BotControllerImpl|BotHider|BotHiderImpl|BotRandomizer|BotState|NadeSystem|RayTrace|RoundDamageRecap|TeamLineupInjector|OfflineMatchTelemetry|PlusMatchCoordinator|MatchCore|match|rating|telemetry|stats|demo)(/|$)|botprofile|gameinfo\.gi'
    foreach ($relative in $files) {
        if ($relative -match $forbidden) { Add-Failure "Forbidden package path: $relative" }
        $top = ($relative -split '/')[0]
        if ($top -notin @('addons', 'LocalCosmetics.exe', 'WebView2Loader.dll', 'README.md', 'README.zh-CN.md', 'LICENSE', 'ATTRIBUTION.md', 'plus-payload-manifest.json', 'PREVIEW-NOTICE.txt')) {
            Add-Failure "Unexpected package top-level path: $relative"
        }
    }
    foreach ($required in @(
        "LocalCosmetics.exe",
        "LICENSE",
        "addons/metamod/bin/win64/server.dll",
        "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll",
        "addons/counterstrikesharp/dotnet/dotnet.exe",
        "addons/counterstrikesharp/configs/core.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
        "plus-payload-manifest.json"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            Add-Failure "Required package file is missing: $required"
        }
    }
    $coreConfigPath = Join-Path $root "addons/counterstrikesharp/configs/core.json"
    if (Test-Path -LiteralPath $coreConfigPath -PathType Leaf) {
        try {
            $coreConfig = Get-Content -LiteralPath $coreConfigPath -Raw | ConvertFrom-Json
            if ($null -eq $coreConfig.PSObject.Properties["FollowCS2ServerGuidelines"]) {
                Add-Failure "Package core.json does not expose FollowCS2ServerGuidelines."
            }
        }
        catch { Add-Failure "Package core.json is invalid JSON: $($_.Exception.Message)" }
    }
    $manifestPath = Join-Path $root "plus-payload-manifest.json"
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            if ($ExpectedPackageVersion -and $manifest.package_version -ne $ExpectedPackageVersion) {
                Add-Failure "Package manifest version mismatch: $($manifest.package_version) != $ExpectedPackageVersion"
            }
            foreach ($entry in @($manifest.entries)) {
                if ($entry.path -match $forbidden) { Add-Failure "Forbidden manifest path: $($entry.path)" }
                $file = Join-Path $root ($entry.path.Replace('/', '\'))
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    Add-Failure "Manifest entry is missing from package: $($entry.path)"
                    continue
                }
                $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($hash -ne $entry.sha256.ToLowerInvariant()) {
                    Add-Failure "Manifest hash mismatch: $($entry.path)"
                }
            }
        }
        catch { Add-Failure "Package manifest is invalid: $($_.Exception.Message)" }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
if ($PackageRoot) { Write-Host "Cosmetics-only package verification passed: $PackageRoot" }
else { Write-Host "Cosmetics-only workspace verification passed." }
