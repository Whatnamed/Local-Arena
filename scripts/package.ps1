[CmdletBinding()]
param(
    [string]$DotNet,
    [string]$Cargo,
    [string]$Rustc,
    [string]$RustToolchain,
    [string]$NodeBin,
    [string]$Npm,
    [string]$OutputDirectory,
    [string]$ReleaseVersion = "1.4.3.3",
    [switch]$SkipBuild,
    [switch]$SkipNpmInstall
)

# Cosmetics-only release packaging.
#
# The package is assembled from an explicit allowlist: the two pinned runtime
# archives, this repository's own plugin build, the Panel executable and the
# license / attribution files. Nothing is copied from a full Local Arena payload
# and then trimmed, so a Bot component cannot reappear by omission. The audit at
# the end re-reads the finished tree and fails the build on any forbidden path.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$displayVersion = $ReleaseVersion.Trim().TrimStart('v', 'V')
if ($displayVersion -notmatch '^\d+\.\d+\.\d+\.\d+(?:-Preview\.\d+)?$') {
    throw "ReleaseVersion must use four numeric parts with an optional -Preview.N suffix."
}
$isPreview = $displayVersion -match '-Preview\.\d+$'
$releaseTag = "v$displayVersion"
$releaseName = "LocalCosmetics-$releaseTag-windows"
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "dependencies.json") -Raw | ConvertFrom-Json
$cache = Join-Path $repo ".cache\package"
$stage = Join-Path $cache "stage"
$extract = Join-Path $cache "extract"
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo "artifacts" }

# Every file the Cosmetics-only payload installs, the pinned plugin build output,
# and the components that must never reach the archive. scripts/verify-workspace.ps1
# re-audits the finished package against this same inventory.
$inventory = Get-Content -LiteralPath (Join-Path $PSScriptRoot "release-inventory.json") -Raw | ConvertFrom-Json
$requiredPayloadFiles = @($inventory.required_payload_files)
$cosmeticsPluginFiles = @($inventory.cosmetics_plugin_files)
$preserveConfigPaths = @($inventory.preserve_config_paths)
$panelOwnedPaths = @($inventory.panel_owned_paths)
$forbiddenSegments = @($inventory.forbidden_segments)
$forbiddenFileNames = @($inventory.forbidden_file_names)
$forbiddenExtensions = @($inventory.forbidden_extensions)

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

function Assert-ChildPath {
    param([string]$Parent, [string]$Child)
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $childPath = [IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the package cache: $childPath"
    }
}

function Get-RelativePaths {
    param([string]$Root)
    @(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object {
        if ($_.PSIsContainer) { return }
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace("\", "/")
    } | Sort-Object)
}

if (-not $SkipBuild) {
    $buildArguments = @{ SkipNpmInstall = $SkipNpmInstall }
    if ($DotNet) { $buildArguments.DotNet = $DotNet }
    if ($Cargo) { $buildArguments.Cargo = $Cargo }
    if ($Rustc) { $buildArguments.Rustc = $Rustc }
    if ($RustToolchain) { $buildArguments.RustToolchain = $RustToolchain }
    if ($NodeBin) { $buildArguments.NodeBin = $NodeBin }
    if ($Npm) { $buildArguments.Npm = $Npm }
    & (Join-Path $PSScriptRoot "build.ps1") @buildArguments
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
}

$metamodZip = Get-VerifiedAsset $manifest.metamod.windowsAsset
$counterStrikeSharpZip = Get-VerifiedAsset $manifest.counterStrikeSharp.windowsAsset

Assert-ChildPath $cache $stage
Assert-ChildPath $cache $extract
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
New-Item -ItemType Directory -Path $stage, $extract -Force | Out-Null

$metamodExtract = Join-Path $extract "metamod"
$counterStrikeSharpExtract = Join-Path $extract "counterstrikesharp"
Expand-Archive -LiteralPath $metamodZip -DestinationPath $metamodExtract
Expand-Archive -LiteralPath $counterStrikeSharpZip -DestinationPath $counterStrikeSharpExtract
foreach ($archive in @(@{ Path = $metamodExtract; Label = "Metamod" }, @{ Path = $counterStrikeSharpExtract; Label = "CounterStrikeSharp" })) {
    if (-not (Test-Path -LiteralPath (Join-Path $archive.Path "addons"))) {
        throw "$($archive.Label) archive has no addons payload."
    }
}

$releaseRoot = Join-Path $stage $releaseName
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

# 1. Pinned runtime: MetaMod first, then CounterStrikeSharp, which also drops its
#    own addons/metamod/counterstrikesharp.vdf into the loader directory.
Copy-Tree (Join-Path $metamodExtract "addons") (Join-Path $releaseRoot "addons")
Copy-Tree (Join-Path $counterStrikeSharpExtract "addons") (Join-Path $releaseRoot "addons")

# 2. This repository's cosmetics plugin.
$pluginBuild = Join-Path $repo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\bin\Release\net10.0"
if (-not (Test-Path -LiteralPath (Join-Path $pluginBuild "PlayerKnifeCustomizer.dll"))) {
    throw "The cosmetics plugin was not built: $pluginBuild"
}
$cosmeticsDirectory = Join-Path $releaseRoot "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer"
Copy-Tree $pluginBuild $cosmeticsDirectory

# 3. Panel and the documentation the project must keep shipping.
$panelExe = Join-Path $repo "Panel\src-tauri\target\release\cs2-bot-improver-plus-panel.exe"
if (-not (Test-Path -LiteralPath $panelExe)) {
    throw "The release Panel was not built: $panelExe"
}
Copy-Item -LiteralPath $panelExe -Destination (Join-Path $releaseRoot "cs2-bot-improver-plus-panel.exe") -Force
$webViewLoader = Join-Path $repo "Panel\src-tauri\target\release\WebView2Loader.dll"
if (Test-Path -LiteralPath $webViewLoader) {
    Copy-Item -LiteralPath $webViewLoader -Destination $releaseRoot -Force
}
foreach ($document in @("README.md", "README.zh-CN.md", "LICENSE", "docs/UPSTREAM.md")) {
    $source = Join-Path $repo $document
    if (-not (Test-Path -LiteralPath $source)) { throw "Required release document is missing: $document" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $releaseRoot ([IO.Path]::GetFileName($document))) -Force
}
if ($isPreview) {
    @"
Local Cosmetics $releaseTag

PREVIEW VERSION - MAY CONTAIN BUGS
This local test package is not an official release.
Please report problems together with an exported diagnostics ZIP.
"@ | Set-Content -LiteralPath (Join-Path $releaseRoot "PREVIEW-NOTICE.txt") -Encoding utf8
}

# 4. Audit the finished tree before anything is hashed or compressed.
$packageFiles = Get-RelativePaths $releaseRoot
foreach ($relative in $requiredPayloadFiles) {
    if ($relative -eq "plus-payload-manifest.json") { continue }
    if ($packageFiles -notcontains $relative) {
        throw "Cosmetics-only package is missing a required file: $relative"
    }
}
$packagedPluginFiles = @(Get-RelativePaths $cosmeticsDirectory | ForEach-Object { Split-Path -Leaf $_ })
$pluginDifference = @(Compare-Object ($cosmeticsPluginFiles | Sort-Object) ($packagedPluginFiles | Sort-Object))
if ($pluginDifference.Count -gt 0) {
    throw "The packaged cosmetics plugin does not match its pinned build allowlist: $(($pluginDifference | ForEach-Object InputObject) -join ', ')"
}
foreach ($relative in $packageFiles) {
    $segments = $relative -split "/"
    $leaf = $segments[-1]
    $hit = @($segments | Where-Object { $forbiddenSegments -contains $_ })
    if ($forbiddenFileNames -contains $leaf) { $hit += $leaf }
    if ($leaf -match '(?i)^(?:bot|my_bot)' -or $leaf -match '(?i)botprofile') { $hit += $leaf }
    if ($forbiddenExtensions -contains [IO.Path]::GetExtension($leaf)) { $hit += $leaf }
    if ($hit.Count -gt 0) {
        throw "Forbidden component reached the release package: $relative (matched: $($hit -join ', '))"
    }
}

# 5. The installation ownership boundary the Panel reads at install time.
$manifestEntries = foreach ($relative in (Get-RelativePaths $releaseRoot | Where-Object { $_ -like "addons/*" })) {
    $file = Join-Path $releaseRoot $relative
    $ownedByUs = @($panelOwnedPaths | Where-Object { $relative -like "$_/*" }).Count -gt 0
    $component = if ($ownedByUs) { "cosmetics" }
        elseif ($relative -like "addons/metamod*") { "metamod" }
        elseif ($relative -like "addons/counterstrikesharp/*") { "counterstrikesharp" }
        else { "runtime" }
    $preserveConfig = $preserveConfigPaths -contains $relative
    [ordered]@{
        path = $relative
        size = (Get-Item -LiteralPath $file).Length
        sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        component = $component
        ownership = if ($ownedByUs) { "plus" } else { "shared" }
        restore_policy = if ($preserveConfig) { "preserve-config" } else { "restore" }
    }
}
[ordered]@{
    schema_version = 1
    package_version = $displayVersion
    entries = @($manifestEntries | Sort-Object path)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseRoot "plus-payload-manifest.json") -Encoding utf8

& (Join-Path $PSScriptRoot "verify-workspace.ps1") -PackageRoot $releaseRoot -ExpectedPackageVersion $displayVersion
if ($LASTEXITCODE -ne 0) { throw "Package verification failed." }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $OutputDirectory -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(?:LocalCosmetics|LocalArena|CS2BotImproverPlus)-.*\.zip$|^latest\.json(\.sig)?$|^SHA256SUMS\.txt$' } |
    Remove-Item -Force

$fullZip = Join-Path $OutputDirectory "$releaseName.zip"
Compress-Archive -Path $releaseRoot -DestinationPath $fullZip -CompressionLevel Optimal
$sums = Join-Path $OutputDirectory "SHA256SUMS.txt"
"$((Get-FileHash -LiteralPath $fullZip -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($fullZip))" |
    Set-Content -LiteralPath $sums -Encoding ascii

Write-Host "Package complete: $fullZip"
Write-Host "Payload files: $((Get-RelativePaths (Join-Path $releaseRoot 'addons')).Count) under addons/, $((Get-RelativePaths $releaseRoot).Count) in the release root"
