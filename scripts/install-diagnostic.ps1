[CmdletBinding()]
param(
    [ValidateSet("A", "B")]
    [string]$Mode = "A",
    [string]$Cs2Root,
    [string]$PackageSource,
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

$runningCs2 = Get-Process -Name "cs2" -ErrorAction SilentlyContinue
if ($runningCs2) {
    throw "CS2 is currently running (PID: $($runningCs2.Id -join ', ')). Close CS2 before installing diagnostic packages."
}

function Find-Cs2Root {
    param([string]$UserPath)
    if ($UserPath) {
        $candidate = (Resolve-Path -LiteralPath $UserPath -ErrorAction Stop).Path
        if (Test-Path -LiteralPath (Join-Path $candidate "gameinfo.gi")) { return $candidate }
        $sub = Join-Path $candidate "game\csgo"
        if (Test-Path -LiteralPath (Join-Path $sub "gameinfo.gi")) { return $sub }
        throw "Specified path is not a CS2 directory (gameinfo.gi missing): $UserPath"
    }
    $panelConfigs = @(
        (Join-Path $HOME ".csbip\config\panel.json"),
        (Join-Path $env:APPDATA "cs2bi\config\panel.json")
    )
    foreach ($cfg in $panelConfigs) {
        if (Test-Path -LiteralPath $cfg) {
            try {
                $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
                if ($json.csgo_path -and (Test-Path -LiteralPath (Join-Path $json.csgo_path "gameinfo.gi"))) {
                    return $json.csgo_path
                }
            } catch {}
        }
    }
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) {
        $stdCsgo = Join-Path $steamPath "steamapps\common\Counter-Strike Global Offensive\game\csgo"
        if (Test-Path -LiteralPath (Join-Path $stdCsgo "gameinfo.gi")) { return $stdCsgo }
        $libFolders = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libFolders) {
            $content = Get-Content -LiteralPath $libFolders -Raw
            $matches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
            foreach ($m in $matches) {
                $libPath = $m.Groups[1].Value.Replace("\\", "\")
                $cand = Join-Path $libPath "steamapps\common\Counter-Strike Global Offensive\game\csgo"
                if (Test-Path -LiteralPath (Join-Path $cand "gameinfo.gi")) { return $cand }
            }
        }
    }
    throw "Could not locate CS2 game/csgo directory automatically. Pass -Cs2Root <path to game/csgo>."
}

$csgo = Find-Cs2Root $Cs2Root
Write-Host "Target CS2 game/csgo: $csgo"
Write-Host "Installing Diagnostic Mode: $Mode"

# Resolve package source directory
if (-not $PackageSource) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "addons")) {
        $PackageSource = $PSScriptRoot
    } else {
        $repo = Split-Path -Parent $PSScriptRoot
        $stageCand = Join-Path $repo "artifacts\diagnostic\stage-diag$Mode"
        if (Test-Path -LiteralPath $stageCand) {
            $PackageSource = $stageCand
        } else {
            throw "Package source directory not found. Run scripts/make-diagnostic-packages.ps1 first, or pass -PackageSource."
        }
    }
}
Write-Host "Package source: $PackageSource"

# Configuration preservation allowlist
$preserveConfigs = @(
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
    "addons/counterstrikesharp/plugins/BotRandomizer/bot_randomizer_options.json",
    "cfg/my_bot_ffa_config.cfg",
    "cfg/my_bot_normal_config.cfg",
    "overrides/botprofile.vpk"
)

# Step 1: Pre-install renaming/disabling of existing active files in target
Write-Host "Reconciling target component states before copy..."

# Both Mode A and Mode B disable BotHider native and BotHiderImpl
$targetVdf = Join-Path $csgo "addons\metamod\BotHider.vdf"
$targetVdfDisabled = Join-Path $csgo "addons\metamod\BotHider.vdf.csbip-disabled"
if (Test-Path -LiteralPath $targetVdf) {
    if (Test-Path -LiteralPath $targetVdfDisabled) {
        Remove-Item -LiteralPath $targetVdf -Force
    } else {
        Move-Item -LiteralPath $targetVdf -Destination $targetVdfDisabled -Force
    }
    Write-Host "Disabled existing BotHider native: BotHider.vdf -> BotHider.vdf.csbip-disabled"
}

$targetImpl = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
$targetImplDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
if (Test-Path -LiteralPath $targetImpl) {
    if (Test-Path -LiteralPath $targetImplDisabled) {
        Remove-Item -LiteralPath $targetImpl -Force
    } else {
        Move-Item -LiteralPath $targetImpl -Destination $targetImplDisabled -Force
    }
    Write-Host "Disabled existing BotHiderImpl: BotHiderImpl.dll -> BotHiderImpl.dll.csbip-disabled"
}

$targetKnife = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"
$targetKnifeDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"

if ($Mode -eq "A") {
    if (Test-Path -LiteralPath $targetKnife) {
        if (Test-Path -LiteralPath $targetKnifeDisabled) {
            Remove-Item -LiteralPath $targetKnife -Force
        } else {
            Move-Item -LiteralPath $targetKnife -Destination $targetKnifeDisabled -Force
        }
        Write-Host "Disabled existing PlayerKnifeCustomizer: PlayerKnifeCustomizer.dll -> PlayerKnifeCustomizer.dll.csbip-disabled"
    }
} else {
    # Mode B: Ensure disabled counterpart does not linger
    if (Test-Path -LiteralPath $targetKnifeDisabled) {
        Remove-Item -LiteralPath $targetKnifeDisabled -Force
    }
}

# Step 2: Overlay package files
Write-Host "Copying diagnostic package payload to target..."
$topLevels = @("addons", "cfg", "overrides")
$copiedFiles = 0
$preservedFiles = 0

foreach ($topLevel in $topLevels) {
    $sourceTop = Join-Path $PackageSource $topLevel
    if (-not (Test-Path -LiteralPath $sourceTop)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $sourceTop -File -Recurse) {
        $rel = [IO.Path]::GetRelativePath($PackageSource, $file.FullName).Replace("\", "/")
        $targetFile = Join-Path $csgo $rel
        if ($rel -in $preserveConfigs -and (Test-Path -LiteralPath $targetFile)) {
            $preservedFiles++
            continue
        }
        $targetDir = Split-Path -Parent $targetFile
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $targetFile -Force
        $copiedFiles++
    }
}
Write-Host "Payload copied: $copiedFiles files updated, $preservedFiles preserved user config files."

# Step 3: Enforce final active/inactive state guarantees on target
if ($Mode -eq "A") {
    if (Test-Path -LiteralPath $targetVdf) { Remove-Item -LiteralPath $targetVdf -Force }
    if (Test-Path -LiteralPath $targetImpl) { Remove-Item -LiteralPath $targetImpl -Force }
    if (Test-Path -LiteralPath $targetKnife) { Remove-Item -LiteralPath $targetKnife -Force }
} else {
    if (Test-Path -LiteralPath $targetVdf) { Remove-Item -LiteralPath $targetVdf -Force }
    if (Test-Path -LiteralPath $targetImpl) { Remove-Item -LiteralPath $targetImpl -Force }
    if (Test-Path -LiteralPath $targetKnifeDisabled) { Remove-Item -LiteralPath $targetKnifeDisabled -Force }
}

# Step 4: Write diagnostic state markers
$diagnosticState = [ordered]@{
    mode = $Mode
    metamod = "2.0.0-git1469"
    counterstrikesharp = "1.0.375"
    bot_hider_native = $false
    bot_hider_impl = $false
    player_cosmetics = ($Mode -eq "B")
    installed_at = (Get-Date -Format "o")
    csgo_root = $csgo
}
$stateJson = $diagnosticState | ConvertTo-Json -Depth 4
$stateJson | Set-Content -LiteralPath (Join-Path $csgo "diagnostic-state.json") -Encoding utf8
$csbipDir = Join-Path $csgo ".csbip"
if (Test-Path -LiteralPath $csbipDir) {
    $stateJson | Set-Content -LiteralPath (Join-Path $csbipDir "diagnostic-state.json") -Encoding utf8
}

Write-Host "Diagnostic marker written." -ForegroundColor Cyan

# Step 5: Run verification
if (-not $SkipVerify) {
    Write-Host "Running post-install verification..."
    $verifier = Join-Path $PSScriptRoot "verify-diagnostic-install.ps1"
    if (-not (Test-Path -LiteralPath $verifier)) {
        $verifier = Join-Path $PackageSource "VERIFY-DIAGNOSTIC.ps1"
    }
    if (Test-Path -LiteralPath $verifier) {
        & $verifier -Mode $Mode -Cs2Root $csgo
    }
}

Write-Host "Diagnostic Package $Mode successfully installed to $csgo." -ForegroundColor Green
Write-Host "Do NOT start CS2 through Panel! Launch CS2 directly or via Steam." -ForegroundColor Yellow
