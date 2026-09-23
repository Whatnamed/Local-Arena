[CmdletBinding()]
param(
    [string]$DotNet,
    [string]$Cargo,
    [string]$Rustc,
    [string]$RustToolchain = "stable-x86_64-pc-windows-msvc",
    [string]$CargoHome,
    [string]$RustupHome,
    [string]$NodeBin,
    [string]$Npm,
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$panel = Join-Path $repo "Panel"
$cache = Join-Path $repo ".cache"
$localBuildConfig = Join-Path $repo ".local-build.ps1"
if (Test-Path -LiteralPath $localBuildConfig -PathType Leaf) {
    . $localBuildConfig
}

function Resolve-ToolExecutable {
    param([string]$Value, [string]$Label)
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $command = Get-Command $Value -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Build tool $Label was not found: $Value"
}

function Import-VisualStudioEnvironment {
    $requiredTools = @("cl.exe", "link.exe", "rc.exe")
    $missingTools = @($requiredTools | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingTools.Count -eq 0) { return }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $vswhereCandidates = @(
        (Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"),
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    $vswhere = $vswhereCandidates | Select-Object -First 1
    if (-not $vswhere) {
        throw "Native MSVC tools are not on PATH, and vswhere.exe was not found. Run this script from Visual Studio Developer PowerShell or install the x64 C++ build tools."
    }

    $installPaths = & $vswhere -latest -products "*" -requires "Microsoft.VisualStudio.Component.VC.Tools.x86.x64" -property installationPath
    $vswhereExitCode = $LASTEXITCODE
    $installPath = $installPaths | Select-Object -First 1
    if ($vswhereExitCode -ne 0 -or -not $installPath) {
        throw "A Visual Studio installation with the x64 C++ toolset was not found."
    }

    $vcvars = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf)) {
        throw "Visual Studio x64 environment setup was not found: $vcvars"
    }

    $command = 'call "' + $vcvars + '" >nul && set'
    $environmentOutput = & $env:ComSpec /d /s /c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Visual Studio x64 environment setup failed: $vcvars"
    }

    $allowedNames = @(
        "PATH", "INCLUDE", "LIB", "LIBPATH", "VCINSTALLDIR", "VCToolsInstallDir",
        "VCToolsVersion", "VSINSTALLDIR", "VisualStudioVersion", "WindowsSdkDir",
        "WindowsSDKVersion", "WindowsSDKLibVersion", "UniversalCRTSdkDir", "UCRTVersion",
        "VSCMD_VER", "VSCMD_ARG_TGT_ARCH", "VSCMD_ARG_HOST_ARCH"
    )
    foreach ($line in $environmentOutput) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $name = $line.Substring(0, $separator)
        if ($name -in $allowedNames) {
            [Environment]::SetEnvironmentVariable($name, $line.Substring($separator + 1), "Process")
        }
    }

    $stillMissing = @($requiredTools | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($stillMissing.Count -gt 0) {
        throw "Visual Studio environment did not expose required native tools: $($stillMissing -join ', ')"
    }
}

if (-not $DotNet) { $DotNet = "dotnet" }
if (-not $Cargo) { $Cargo = "cargo" }
if (-not $Rustc) { $Rustc = "rustc" }
$DotNet = Resolve-ToolExecutable $DotNet "dotnet"
$Cargo = Resolve-ToolExecutable $Cargo "cargo"
$Rustc = Resolve-ToolExecutable $Rustc "rustc"
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "dependencies.json") -Raw | ConvertFrom-Json

function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory = $repo)
    Push-Location $WorkingDirectory
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-VerifiedAsset {
    param($Asset, [string]$DestinationDirectory)
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    $path = Join-Path $DestinationDirectory $Asset.name
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

function Get-RayTraceApi {
    $inputs = Join-Path $cache "build-inputs\raytrace-$($manifest.rayTrace.release)"
    $archive = Get-VerifiedAsset $manifest.rayTrace.cssAsset $inputs
    $extract = Join-Path $inputs "extract"
    $dll = Get-ChildItem -LiteralPath $extract -Filter "RayTraceApi.dll" -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]shared[\\/]RayTraceApi[\\/]' } |
        Select-Object -First 1
    if (-not $dll) {
        if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        $tar = (Get-Command tar.exe -ErrorAction Stop).Source
        & $tar -xzf $archive -C $extract
        if ($LASTEXITCODE -ne 0) { throw "Failed to extract $archive" }
        $dll = Get-ChildItem -LiteralPath $extract -Filter "RayTraceApi.dll" -File -Recurse |
            Where-Object { $_.FullName -match '[\\/]shared[\\/]RayTraceApi[\\/]' } |
            Select-Object -First 1
    }
    if (-not $dll) { throw "Pinned RayTraceApi.dll was not found in $archive" }
    return $dll.FullName
}

$cargo = (Get-Command $Cargo -ErrorAction Stop).Source
$rustc = (Get-Command $Rustc -ErrorAction Stop).Source

$npm = if ($Npm) { Resolve-ToolExecutable $Npm "npm" }
else {
    $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command npm -ErrorAction Stop }
    $command.Source
}

$previousEnvironment = [Environment]::GetEnvironmentVariables("Process")

try {
    Import-VisualStudioEnvironment

    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $env:CARGO_HOME = if ($CargoHome) { $CargoHome } else { Join-Path $cache "cargo-home" }
    if ($RustupHome) { $env:RUSTUP_HOME = $RustupHome }
    $targetDirectory = Join-Path $panel "src-tauri\target"
    $env:CARGO_TARGET_DIR = $targetDirectory
    $env:DOTNET_CLI_HOME = Join-Path $cache "dotnet-home"
    $env:DOTNET_ROLL_FORWARD = "Major"
    $env:NUGET_HTTP_CACHE_PATH = Join-Path $cache "nuget\http"
    $env:NUGET_PACKAGES = Join-Path $cache "nuget\packages"
    $env:npm_config_cache = Join-Path $cache "npm"
    $env:RUSTC = $rustc
    $env:RUSTUP_TOOLCHAIN = $RustToolchain

    $rustInfo = & $rustc -vV
    $rustcExitCode = $LASTEXITCODE
    $rustHost = ($rustInfo | Where-Object { $_ -like "host: *" } | Select-Object -First 1) -replace "^host: ", ""
    if ($rustcExitCode -ne 0 -or $rustHost -ne "x86_64-pc-windows-msvc") {
        throw "The selected Rust toolchain must target x86_64-pc-windows-msvc; detected host '$rustHost'."
    }

    $nodePath = if ($NodeBin) { (Resolve-Path -LiteralPath $NodeBin).Path } else { $null }
    $toolPaths = @((Split-Path $cargo), (Split-Path $rustc), $nodePath) |
        Where-Object { $_ } | Select-Object -Unique
    $env:PATH = ($toolPaths -join ";") + ";" + $env:PATH

    if (-not $SkipNpmInstall) {
        Invoke-Checked $npm @("ci") $panel
    }
    Invoke-Checked $npm @("run", "test:stickers") $panel
    Invoke-Checked $npm @("run", "test:install-gate") $panel
    Invoke-Checked $npm @("run", "test:cosmetic-media") $panel
    Invoke-Checked $npm @("run", "build") $panel

    $rayTraceApi = Get-RayTraceApi
    $pluginProjects = @(
        @{ Path = "addons\counterstrikesharp\plugins\BotAI\BotAI.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\BotAimImprover\BotAimImprover.csproj"; Properties = @("-p:RayTraceApiPath=$rayTraceApi") },
        @{ Path = "addons\counterstrikesharp\plugins\BotBuy\BotBuy.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\BotControllerImpl\BotControllerImpl.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\BotState\BotState.csproj"; Properties = @("-p:RayTraceApiPath=$rayTraceApi") },
        @{ Path = "addons\counterstrikesharp\plugins\BotRandomizer\BotRandomizer.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\NadeSystem\NadeSystem.csproj"; Properties = @("-p:RayTraceApiPath=$rayTraceApi") },
        @{ Path = "addons\counterstrikesharp\plugins\RoundDamageRecap\RoundDamageRecap.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\TeamLineupInjector\TeamLineupInjector.csproj"; Properties = @() },
        @{ Path = "addons\counterstrikesharp\plugins\PlusMatchCoordinator\PlusMatchCoordinator.csproj"; Properties = @() }
    )
    foreach ($project in $pluginProjects) {
        Invoke-Checked $DotNet (@("build", $project.Path, "-c", "Release", "--nologo") + $project.Properties)
    }
    Invoke-Checked $DotNet @("publish", "addons\counterstrikesharp\plugins\OfflineMatchTelemetry\OfflineMatchTelemetry.csproj", "-c", "Release", "--nologo", "--self-contained", "false", "-o", (Join-Path $repo "addons\counterstrikesharp\plugins\OfflineMatchTelemetry\bin\Release\net8.0"))
    $omtBuild = Join-Path $repo "addons\counterstrikesharp\plugins\OfflineMatchTelemetry\bin\Release\net8.0"
    $sqliteNative = Join-Path $omtBuild "runtimes\win-x64\native\e_sqlite3.dll"
    if (Test-Path -LiteralPath $sqliteNative) { Copy-Item -LiteralPath $sqliteNative -Destination $omtBuild -Force }
    Invoke-Checked $DotNet @(
        "run", "--project", "addons\counterstrikesharp\shared\MatchCore.Tests\MatchCore.Tests.csproj",
        "-c", "Release", "--nologo"
    )
    Invoke-Checked $DotNet @(
        "run", "--project", "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer.Tests\PlayerKnifeCustomizer.Tests.csproj",
        "-c", "Release"
    )

    $tauriSource = Join-Path $panel "src-tauri"
    Invoke-Checked $cargo @("test", "--locked") $tauriSource

    Invoke-Checked $cargo @(
        "build", "--release", "--locked", "--features", "tauri/custom-protocol"
    ) $tauriSource

    $builtExe = Join-Path $targetDirectory "release\cs2-bot-improver-plus-panel.exe"
    if (-not (Test-Path -LiteralPath $builtExe)) {
        throw "Expected MSVC Panel executable was not produced: $builtExe"
    }
    $releaseBuildRoot = Join-Path $targetDirectory "release\build"
    $tauriBuildOutput = Get-ChildItem -LiteralPath $releaseBuildRoot -Directory |
        Where-Object { $_.Name -match '^tauri-[0-9a-f]+$' } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName "output" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $tauriBuildOutput -or
        -not (Get-Content -LiteralPath $tauriBuildOutput -Raw).Contains("cargo:dev=false")) {
        throw "Release Panel was not compiled with Tauri's production custom protocol."
    }
    $appBuildOutput = Get-ChildItem -LiteralPath $releaseBuildRoot -Directory |
        Where-Object { $_.Name -match '^cs2-bot-improver-plus-panel-[0-9a-f]+$' } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName "output" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $appBuildOutput -or
        (Get-Content -LiteralPath $appBuildOutput -Raw).Contains("cargo:rustc-cfg=dev")) {
        throw "Release Panel application still uses Tauri's development URL."
    }
}
finally {
    $currentEnvironment = [Environment]::GetEnvironmentVariables("Process")
    foreach ($name in @($currentEnvironment.Keys)) {
        if (-not $previousEnvironment.Contains($name)) {
            [Environment]::SetEnvironmentVariable([string]$name, $null, "Process")
        }
    }
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable([string]$name, [string]$previousEnvironment[$name], "Process")
    }
}

$exe = Join-Path $panel "src-tauri\target\release\cs2-bot-improver-plus-panel.exe"
if (-not (Test-Path -LiteralPath $exe)) {
    throw "Expected Panel executable was not produced: $exe"
}

Write-Host "Build complete: $exe"
