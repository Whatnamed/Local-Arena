[CmdletBinding()]
param(
    [string]$DotNet,
    [string]$Cargo,
    [string]$Rustc,
    [string]$RustToolchain,
    [string]$LlvmBin,
    [string]$XwinCache,
    [string]$OutputDirectory,
    [string]$ReleaseVersion = "1.4.3.3",
    [string]$MinimumPanelVersion = "1.4.2.4",
    [switch]$SkipBuild,
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$displayVersion = $ReleaseVersion.Trim().TrimStart('v', 'V')
if ($displayVersion -notmatch '^\d+\.\d+\.\d+\.\d+(?:-Preview\.\d+)?$') {
    throw "ReleaseVersion must use four numeric parts with an optional -Preview.N suffix."
}
$minimumPanelVersion = $MinimumPanelVersion.Trim().TrimStart('v', 'V')
if ($minimumPanelVersion -notmatch '^\d+\.\d+\.\d+\.\d+(?:-Preview\.\d+)?$') {
    throw "MinimumPanelVersion must use four numeric parts with an optional -Preview.N suffix."
}
$isPreview = $displayVersion -match '-Preview\.\d+$'
$releaseTag = "v$displayVersion"
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "dependencies.json") -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot "VpkTools.ps1")
$cache = Join-Path $repo ".cache\package"
$stage = Join-Path $cache "stage"
$extract = Join-Path $cache "extract"
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo "artifacts" }

function Get-VerifiedAsset {
    param($Asset)
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $path = Join-Path $cache $Asset.name
    $expected = $Asset.sha256.ToLowerInvariant()
    if (Test-Path -LiteralPath $path) {
        $cached = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($cached -eq $expected) { return $path }
        Write-Host "Refreshing stale cached asset: $($Asset.name)"
    }

    $download = "$path.download"
    try {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        Invoke-WebRequest -Uri $Asset.url -OutFile $download
        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "SHA-256 mismatch for $($Asset.name): $actual"
        }
        Move-Item -LiteralPath $download -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
    }
    return $path
}

function Copy-Tree {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

function Expand-TarGz {
    param([string]$Archive, [string]$Destination)
    $tar = (Get-Command tar.exe -ErrorAction Stop).Source
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & $tar -xzf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract $Archive" }
}

function Assert-ChildPath {
    param([string]$Parent, [string]$Child)
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $childPath = [IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the package cache: $childPath"
    }
}

if (-not $SkipBuild) {
    $buildArguments = @{ SkipNpmInstall = $SkipNpmInstall }
    if ($DotNet) { $buildArguments.DotNet = $DotNet }
    if ($Cargo) { $buildArguments.Cargo = $Cargo }
    if ($Rustc) { $buildArguments.Rustc = $Rustc }
    if ($RustToolchain) { $buildArguments.RustToolchain = $RustToolchain }
    if ($LlvmBin) { $buildArguments.LlvmBin = $LlvmBin }
    if ($XwinCache) { $buildArguments.XwinCache = $XwinCache }
    & (Join-Path $PSScriptRoot "build.ps1") @buildArguments
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
}

$metamodZip = Get-VerifiedAsset $manifest.metamod.windowsAsset
$counterStrikeSharpZip = Get-VerifiedAsset $manifest.counterStrikeSharp.windowsAsset

Assert-ChildPath $cache $stage
Assert-ChildPath $cache $extract
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
New-Item -ItemType Directory -Path $stage,$extract -Force | Out-Null

$metamodExtract = Join-Path $extract "metamod"
$counterStrikeSharpExtract = Join-Path $extract "counterstrikesharp"
Expand-Archive -LiteralPath $metamodZip -DestinationPath $metamodExtract
Expand-Archive -LiteralPath $counterStrikeSharpZip -DestinationPath $counterStrikeSharpExtract

$releaseRoot = Join-Path $stage "LocalArena-$releaseTag-windows"
$payload = $releaseRoot
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

# 1. Metamod runtime
$metamodAddons = Join-Path $metamodExtract "addons"
if (-not (Test-Path -LiteralPath $metamodAddons)) { throw "Metamod archive has no addons payload." }
Copy-Tree $metamodAddons (Join-Path $payload "addons")

# 2. CounterStrikeSharp runtime
$counterStrikeSharpAddons = Join-Path $counterStrikeSharpExtract "addons"
if (-not (Test-Path -LiteralPath $counterStrikeSharpAddons)) { throw "CounterStrikeSharp archive has no addons payload." }
Copy-Tree $counterStrikeSharpAddons (Join-Path $payload "addons")

# Clean sample / extraneous default plugins from CSS archive
$defaultPluginDir = Join-Path $payload "addons\counterstrikesharp\plugins"
if (Test-Path -LiteralPath $defaultPluginDir) {
    Get-ChildItem -LiteralPath $defaultPluginDir -Recurse | Remove-Item -Recurse -Force
}

# 3. Cosmetics-only plugin: PlayerKnifeCustomizer
$pluginBuild = Join-Path $repo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\bin\Release\net10.0"
if (-not (Test-Path -LiteralPath (Join-Path $pluginBuild "PlayerKnifeCustomizer.dll"))) {
    throw "PlayerKnifeCustomizer build output was not found: $pluginBuild"
}
Copy-Tree $pluginBuild (Join-Path $payload "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer")

# 4. Quickknife opt-in cfg
$quickknifeSource = Join-Path $repo "cfg\cs2bi_quickknife.cfg"
$cfgDir = Join-Path $payload "cfg"
New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
if (Test-Path -LiteralPath $quickknifeSource) {
    Copy-Item -LiteralPath $quickknifeSource -Destination (Join-Path $cfgDir "cs2bi_quickknife.cfg") -Force
} else {
    "// cs2bi_quickknife.cfg - Opt-in knife cycle shortcut managed by Local Arena" | Set-Content -LiteralPath (Join-Path $cfgDir "cs2bi_quickknife.cfg") -Encoding utf8
}

# 5. Panel executable & documentation
$panelExe = Join-Path $repo "Panel\src-tauri\target\release\cs2-bot-improver-plus-panel.exe"
if (-not (Test-Path -LiteralPath $panelExe)) {
    $panelExe = Join-Path $repo "Panel\src-tauri\target-msvc\x86_64-pc-windows-msvc\release\cs2-bot-improver-plus-panel.exe"
}
if (-not (Test-Path -LiteralPath $panelExe)) {
    throw "Panel executable was not found: $panelExe"
}
Copy-Item -LiteralPath $panelExe -Destination (Join-Path $releaseRoot "LocalArena.exe") -Force
$webViewLoader = Join-Path (Split-Path $panelExe) "WebView2Loader.dll"
if (Test-Path -LiteralPath $webViewLoader) {
    Copy-Item -LiteralPath $webViewLoader -Destination (Join-Path $releaseRoot "WebView2Loader.dll") -Force
}
Copy-Item -LiteralPath (Join-Path $repo "README.md") -Destination (Join-Path $releaseRoot "README.md") -Force
Copy-Item -LiteralPath (Join-Path $repo "README.zh-CN.md") -Destination (Join-Path $releaseRoot "README.zh-CN.md") -Force
Copy-Item -LiteralPath (Join-Path $repo "LICENSE") -Destination (Join-Path $releaseRoot "LICENSE") -Force
if ($isPreview) {
    $packageReadme = Join-Path $releaseRoot "README.md"
    $packageReadmeZh = Join-Path $releaseRoot "README.zh-CN.md"
    (Get-Content -LiteralPath $packageReadme -Raw).Replace(
        "The current ``main`` branch targets **1.4.3.3**",
        "This local test package is **$displayVersion** (preview; may contain bugs; please report problems)"
    ) | Set-Content -LiteralPath $packageReadme -Encoding utf8
    (Get-Content -LiteralPath $packageReadmeZh -Raw).Replace(
        "当前 ``main`` 分支源码版本为 **1.4.3.3**",
        "当前本地测试包版本为 **$displayVersion**（预览版本，可能包含 Bug，请反馈）"
    ) | Set-Content -LiteralPath $packageReadmeZh -Encoding utf8
    @"
Local Arena $releaseTag

PREVIEW VERSION - MAY CONTAIN BUGS
This local test package is not an official GitHub release.
Please report problems together with an exported diagnostics ZIP.
"@ | Set-Content -LiteralPath (Join-Path $releaseRoot "PREVIEW-NOTICE.txt") -Encoding utf8
}

# 6. plus-payload-manifest.json
$manifestEntries = foreach ($topLevel in @("addons", "cfg")) {
    $root = Join-Path $payload $topLevel
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($payload, $file.FullName).Replace("\", "/")
        $plusOwned = $relative -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/*" -or
            $relative -eq "cfg/cs2bi_quickknife.cfg"
        $component = if ($relative -like "addons/counterstrikesharp/plugins/*") {
            ($relative -split "/")[3]
        }
        elseif ($relative -like "cfg/*") { "configuration" }
        else { "runtime" }
        $preserveConfig = $relative -like "*/PlayerKnifeCustomizer/player_*_presets.json" -or
            $relative -eq "cfg/cs2bi_quickknife.cfg"
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
    package_version = $displayVersion
    entries = @($manifestEntries | Sort-Object path)
}
$payloadManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload "plus-payload-manifest.json") -Encoding utf8

# 7. Denylist and Allowlist assertion gates
$forbiddenPatterns = @(
    "gameinfo.gi",
    "BotAI", "BotAim", "BotBuy", "BotController", "BotHider", "BotRandomizer",
    "BotState", "NadeSystem", "RayTrace", "RoundDamageRecap",
    "PlusMatchCoordinator", "TeamLineup", "OfflineMatchTelemetry",
    "botprofile", "overrides", "open-rating", "rating-plus",
    "my_bot_ffa_config", "my_bot_normal_config", "bot_buy.cfg"
)
function Test-IsForbiddenPath([string]$Path, [string]$Pattern) {
    if ($Pattern -eq "overrides") {
        return ($Path -match '(^|/)overrides(/|$)')
    }
    return ($Path -like "*$Pattern*")
}
$payloadAllFiles = @(Get-ChildItem -LiteralPath $releaseRoot -File -Recurse | ForEach-Object {
    [IO.Path]::GetRelativePath($releaseRoot, $_.FullName).Replace("\", "/")
})
foreach ($forbidden in $forbiddenPatterns) {
    $matched = @($payloadAllFiles | Where-Object { Test-IsForbiddenPath $_ $forbidden })
    if ($matched.Count -gt 0) {
        throw "Packaging denylist gate failed: forbidden component '$forbidden' found in package: $($matched -join ', ')"
    }
}

$requiredAllowlist = @(
    "LocalArena.exe",
    "README.md",
    "README.zh-CN.md",
    "LICENSE",
    "plus-payload-manifest.json",
    "addons/metamod/bin/win64/server.dll",
    "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll",
    "addons/metamod/counterstrikesharp.vdf",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/skins_en.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
    "cfg/cs2bi_quickknife.cfg"
)
foreach ($req in $requiredAllowlist) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $req) -PathType Leaf)) {
        throw "Packaging allowlist gate failed: missing required file '$req'"
    }
}

& (Join-Path $PSScriptRoot "verify-workspace.ps1") -PackageRoot $releaseRoot -ExpectedPackageVersion $displayVersion
if ($LASTEXITCODE -ne 0) { throw "Package verification failed." }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $OutputDirectory -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(?:CS2BotImproverPlus|LocalArena)-.*\.zip$|^latest\.json(\.sig)?$|^SHA256SUMS\.txt$' } |
    Remove-Item -Force

$fullZip = Join-Path $OutputDirectory "LocalArena-$releaseTag-windows.zip"
Compress-Archive -Path $releaseRoot -DestinationPath $fullZip -CompressionLevel Optimal

$panelStage = Join-Path $stage "panel-update"
New-Item -ItemType Directory -Path $panelStage -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $releaseRoot "LocalArena.exe") -Destination $panelStage -Force
# Releases through 1.4.2.5 look up this legacy name before the new updater can run.
Copy-Item -LiteralPath (Join-Path $releaseRoot "LocalArena.exe") -Destination (Join-Path $panelStage "CS2BotImproverPlus.exe") -Force
@{
    schema_version = 1
    component = "panel-online-update"
    version = $displayVersion
    first_install_supported = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $panelStage "csbip-panel-update.json") -Encoding utf8
if (Test-Path -LiteralPath (Join-Path $releaseRoot "WebView2Loader.dll")) {
    Copy-Item -LiteralPath (Join-Path $releaseRoot "WebView2Loader.dll") -Destination $panelStage -Force
}
$panelZip = Join-Path $OutputDirectory "LocalArena-panel-$releaseTag-windows.zip"
Compress-Archive -Path (Join-Path $panelStage "*") -DestinationPath $panelZip -CompressionLevel Optimal

$pluginStage = Join-Path $stage "plugin-update"
New-Item -ItemType Directory -Path $pluginStage -Force | Out-Null
foreach ($name in @("addons", "cfg", "plus-payload-manifest.json")) {
    $source = Join-Path $releaseRoot $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $pluginStage -Recurse -Force }
}
$pluginZip = Join-Path $OutputDirectory "LocalArena-plugin-$releaseTag-windows.zip"
Compress-Archive -Path (Join-Path $pluginStage "*") -DestinationPath $pluginZip -CompressionLevel Optimal

$releaseBase = "https://github.com/numakkiyu/Local-Arena/releases/download/$releaseTag"
$latest = [ordered]@{
    schema_version = 1
    release_version = $displayVersion
    published_at = [DateTimeOffset]::UtcNow.ToString("o")
    release_notes_url = "https://github.com/numakkiyu/Local-Arena/releases/tag/$releaseTag"
    components = [ordered]@{
        panel = [ordered]@{
            version = $displayVersion
            url = "$releaseBase/$([IO.Path]::GetFileName($panelZip))"
            size = (Get-Item -LiteralPath $panelZip).Length
            sha256 = (Get-FileHash -LiteralPath $panelZip -Algorithm SHA256).Hash.ToLowerInvariant()
            min_panel_version = $minimumPanelVersion
        }
        plugin = [ordered]@{
            version = $displayVersion
            url = "$releaseBase/$([IO.Path]::GetFileName($pluginZip))"
            size = (Get-Item -LiteralPath $pluginZip).Length
            sha256 = (Get-FileHash -LiteralPath $pluginZip -Algorithm SHA256).Hash.ToLowerInvariant()
            min_panel_version = $minimumPanelVersion
        }
    }
}
$latestPath = Join-Path $OutputDirectory "latest.json"
$latest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $latestPath -Encoding utf8
$signaturePath = Join-Path $OutputDirectory "latest.json.sig"
if ($env:CSBIP_UPDATE_SIGNING_KEY) {
    $python = (Get-Command python -ErrorAction Stop).Source
    & $python (Join-Path $PSScriptRoot "sign-update.py") $latestPath $signaturePath `
        --public-key (Join-Path $PSScriptRoot "update-public-key.txt")
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $signaturePath)) { throw "Update signing failed." }
}

$sumFiles = @($fullZip, $panelZip, $pluginZip, $latestPath)
if (Test-Path -LiteralPath $signaturePath) { $sumFiles += $signaturePath }
$sumLines = foreach ($file in $sumFiles) {
    "$((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($file))"
}
$sums = Join-Path $OutputDirectory "SHA256SUMS.txt"
Set-Content -LiteralPath $sums -Value $sumLines -Encoding ascii

# Assert release archives do not contain forbidden bot / match components
$tarCmd = (Get-Command tar.exe -ErrorAction SilentlyContinue)
if ($tarCmd) {
    foreach ($archive in @($fullZip, $panelZip, $pluginZip)) {
        $entries = & $tarCmd.Source -tf $archive
        foreach ($forbidden in $forbiddenPatterns) {
            $bad = @($entries | Where-Object { Test-IsForbiddenPath $_ $forbidden })
            if ($bad.Count -gt 0) {
                throw "Archive $([IO.Path]::GetFileName($archive)) contains forbidden component '$forbidden': $($bad -join ', ')"
            }
        }
    }
}

Write-Host "Package complete: $fullZip"
Write-Host "Panel update: $panelZip"
Write-Host "Plugin update: $pluginZip"
