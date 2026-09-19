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
    [string]$MinimumPanelVersion = "1.4.3.3",
    [switch]$SkipBuild,
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$displayVersion = $ReleaseVersion.Trim().TrimStart('v', 'V')
if ($displayVersion -notmatch '^\d+\.\d+\.\d+\.\d+(?:-Preview\.\d+)?$') {
    throw "ReleaseVersion must use four numeric parts with an optional -Preview.N suffix."
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo "artifacts" }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "dependencies.json") -Raw | ConvertFrom-Json
$cache = Join-Path $repo ".cache\package"
$stage = Join-Path $cache "stage"
$extract = Join-Path $cache "extract"

function Assert-ChildPath {
    param([string]$Parent, [string]$Child)
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $childPath = [IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the package cache: $childPath"
    }
}

function Copy-Tree {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Required package source directory is missing: $Source"
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

function Get-VerifiedAsset {
    param($Asset)
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $path = Join-Path $cache $Asset.name
    $expected = $Asset.sha256.ToLowerInvariant()
    if (Test-Path -LiteralPath $path) {
        $cached = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($cached -eq $expected) { return $path }
        Remove-Item -LiteralPath $path -Force
    }
    $download = "$path.download"
    try {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        Invoke-WebRequest -Uri $Asset.url -OutFile $download
        $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "SHA-256 mismatch for $($Asset.name): $actual" }
        Move-Item -LiteralPath $download -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
    }
    return $path
}

function Find-PayloadRoot {
    param([string]$Root, [string]$RequiredChild)
    $candidates = @((Get-Item -LiteralPath $Root)) + @(Get-ChildItem -LiteralPath $Root -Directory -Recurse)
    $found = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $RequiredChild) } | Select-Object -First 1
    if (-not $found) { throw "Could not locate archive payload containing $RequiredChild under $Root" }
    return $found.FullName
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
New-Item -ItemType Directory -Path $stage, $extract -Force | Out-Null

$metamodExtract = Join-Path $extract "metamod"
$counterStrikeSharpExtract = Join-Path $extract "counterstrikesharp"
Expand-Archive -LiteralPath $metamodZip -DestinationPath $metamodExtract
Expand-Archive -LiteralPath $counterStrikeSharpZip -DestinationPath $counterStrikeSharpExtract
$metamodRoot = Find-PayloadRoot $metamodExtract "addons\metamod"
$counterStrikeSharpRoot = Find-PayloadRoot $counterStrikeSharpExtract "addons\counterstrikesharp"

$releaseRoot = Join-Path $stage "LocalCosmetics-v$displayVersion-windows"
$payload = $releaseRoot
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Tree (Join-Path $metamodRoot "addons\metamod") (Join-Path $payload "addons\metamod")
Copy-Tree (Join-Path $counterStrikeSharpRoot "addons\counterstrikesharp") (Join-Path $payload "addons\counterstrikesharp")

# CounterStrikeSharp's MetaMod loader files are the only extra files copied
# into the MetaMod directory. No upstream plugin or bot payload is imported.
$cssMetaMod = Join-Path $counterStrikeSharpRoot "addons\metamod"
if (Test-Path -LiteralPath $cssMetaMod -PathType Container) {
    Get-ChildItem -LiteralPath $cssMetaMod -File |
        Where-Object { $_.Extension -in @('.vdf', '.ini') -or $_.Name -eq 'metaplugins.ini' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $payload "addons\metamod\$($_.Name)") -Force }
}

$pluginBuild = Join-Path $repo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\bin\Release\net10.0"
if (-not (Test-Path -LiteralPath (Join-Path $pluginBuild "PlayerKnifeCustomizer.dll"))) {
    throw "Expected PlayerCosmetics build output was not produced: $pluginBuild"
}
$pluginPayload = Join-Path $payload "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer"
Copy-Tree $pluginBuild $pluginPayload
Get-ChildItem -LiteralPath $pluginPayload -Recurse -File |
    Where-Object { $_.Extension -in @('.cs', '.csproj', '.user', '.sln') } |
    Remove-Item -Force

$panelExe = Join-Path $repo "Panel\src-tauri\target\release\cs2-bot-improver-plus-panel.exe"
if (-not (Test-Path -LiteralPath $panelExe)) { throw "Expected Panel executable was not produced: $panelExe" }
Copy-Item -LiteralPath $panelExe -Destination (Join-Path $releaseRoot "LocalCosmetics.exe") -Force
$webViewLoader = Join-Path $repo "Panel\src-tauri\target\release\WebView2Loader.dll"
if (Test-Path -LiteralPath $webViewLoader) {
    Copy-Item -LiteralPath $webViewLoader -Destination (Join-Path $releaseRoot "WebView2Loader.dll") -Force
}
Copy-Item -LiteralPath (Join-Path $repo "README.md") -Destination (Join-Path $releaseRoot "README.md") -Force
Copy-Item -LiteralPath (Join-Path $repo "README.zh-CN.md") -Destination (Join-Path $releaseRoot "README.zh-CN.md") -Force
Copy-Item -LiteralPath (Join-Path $repo "LICENSE") -Destination (Join-Path $releaseRoot "LICENSE") -Force
if (Test-Path -LiteralPath (Join-Path $repo "ATTRIBUTION.md")) {
    Copy-Item -LiteralPath (Join-Path $repo "ATTRIBUTION.md") -Destination (Join-Path $releaseRoot "ATTRIBUTION.md") -Force
}

$manifestEntries = foreach ($file in Get-ChildItem -LiteralPath (Join-Path $payload "addons") -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($payload, $file.FullName).Replace("\", "/")
    [ordered]@{
        path = $relative
        size = $file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        component = if ($relative -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/*") { "PlayerCosmetics" } elseif ($relative -like "addons/counterstrikesharp/*") { "CounterStrikeSharp" } else { "MetaMod" }
        ownership = if ($relative -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_*_presets.json") { "plus" } else { "shared" }
        restore_policy = if ($relative -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_*_presets.json") { "preserve-config" } else { "restore" }
    }
}
[ordered]@{
    schema_version = 1
    package_version = $displayVersion
    entries = @($manifestEntries | Sort-Object path)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload "plus-payload-manifest.json") -Encoding utf8

& (Join-Path $PSScriptRoot "verify-workspace.ps1") -PackageRoot $releaseRoot -ExpectedPackageVersion $displayVersion
if ($LASTEXITCODE -ne 0) { throw "Package verification failed." }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $OutputDirectory -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^LocalCosmetics-.*\.zip$|^SHA256SUMS\.txt$' } |
    Remove-Item -Force
$zip = Join-Path $OutputDirectory "LocalCosmetics-v$displayVersion-windows.zip"
Compress-Archive -Path $releaseRoot -DestinationPath $zip -CompressionLevel Optimal
$sum = "$( (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() )  $([IO.Path]::GetFileName($zip))"
Set-Content -LiteralPath (Join-Path $OutputDirectory "SHA256SUMS.txt") -Value $sum -Encoding ascii
Write-Host "Cosmetics-only package complete: $zip"
