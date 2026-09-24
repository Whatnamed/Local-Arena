[CmdletBinding()]
param(
    [string]$Cs2Root
)

$ErrorActionPreference = "Stop"

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

$runningCs2 = Get-Process -Name "cs2" -ErrorAction SilentlyContinue
if ($runningCs2) {
    throw "CS2 is currently running. Please close CS2 before restoring installation."
}

$csgo = Find-Cs2Root $Cs2Root
Write-Host "Target game/csgo: $csgo"
Write-Host "Restoring normal Local-Arena installation state..."

# Restore BotHider.vdf
$vdfDisabled = Join-Path $csgo "addons\metamod\BotHider.vdf.csbip-disabled"
$vdfActive = Join-Path $csgo "addons\metamod\BotHider.vdf"
if (Test-Path -LiteralPath $vdfDisabled) {
    if (Test-Path -LiteralPath $vdfActive) { Remove-Item -LiteralPath $vdfActive -Force }
    Move-Item -LiteralPath $vdfDisabled -Destination $vdfActive -Force
    Write-Host "Restored: BotHider.vdf"
}

# Restore BotHiderImpl.dll
$implDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
$implActive = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
if (Test-Path -LiteralPath $implDisabled) {
    if (Test-Path -LiteralPath $implActive) { Remove-Item -LiteralPath $implActive -Force }
    Move-Item -LiteralPath $implDisabled -Destination $implActive -Force
    Write-Host "Restored: BotHiderImpl.dll"
}

# Restore PlayerKnifeCustomizer.dll
$knifeDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"
$knifeActive = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"
if (Test-Path -LiteralPath $knifeDisabled) {
    if (Test-Path -LiteralPath $knifeActive) { Remove-Item -LiteralPath $knifeActive -Force }
    Move-Item -LiteralPath $knifeDisabled -Destination $knifeActive -Force
    Write-Host "Restored: PlayerKnifeCustomizer.dll"
}

# Clean diagnostic markers
$m1 = Join-Path $csgo "diagnostic-state.json"
if (Test-Path -LiteralPath $m1) { Remove-Item -LiteralPath $m1 -Force }
$m2 = Join-Path $csgo ".csbip\diagnostic-state.json"
if (Test-Path -LiteralPath $m2) { Remove-Item -LiteralPath $m2 -Force }

Write-Host "Normal Local-Arena layout restored successfully." -ForegroundColor Green
