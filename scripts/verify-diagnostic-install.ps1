[CmdletBinding()]
param(
    [ValidateSet("A", "B")]
    [string]$Mode = "A",
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

$csgo = Find-Cs2Root $Cs2Root
Write-Host "Target game/csgo: $csgo"
Write-Host "Verifying Diagnostic Mode: $Mode"
Write-Host "--------------------------------------------------------"

$manifestPath = Join-Path $PSScriptRoot "dependencies.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $expectedMetamodLoader = "c57f348a49561e614768f20af8545998cab5ab7f8e4f913906c8889d34e40cfc"
    $expectedCssCore = "69334463860eed462993502b667ac4bec626ef0dc38c3977c792415c37bee1dd"
    $expectedCssGamedata = "7d9bff7aaff8e9edb1ada4ca508fa4e2ad7b12e16ed00ee1b84dd0cb9a3e4ac5"
    $expectedCssDotnetHost = "37c8f27cf35c5c59d942f7513496c3be68ba3018ed1b2220a31f5e5035df07ba"
} else {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $expectedMetamodLoader = $manifest.metamod.windowsLoaderSha256.ToLowerInvariant()
    $expectedCssCore = $manifest.counterStrikeSharp.windowsCoreSha256.ToLowerInvariant()
    $expectedCssGamedata = $manifest.counterStrikeSharp.windowsGamedataSha256.ToLowerInvariant()
    $expectedCssDotnetHost = $manifest.counterStrikeSharp.windowsDotnetHostSha256.ToLowerInvariant()
}

$expectedKnifeCustomizerHash = "7e44ddf9b7d27767888813a55d4d93034f31d5a76e277e83ebd6dc0a47ad6e28"

$errors = [Collections.Generic.List[string]]::new()
$checks = [Collections.Generic.List[PSCustomObject]]::new()

function Record-Check {
    param([string]$Component, [string]$Status, [string]$Details, [bool]$Ok)
    $checks.Add([PSCustomObject]@{
        Component = $Component
        Status = $Status
        Details = $Details
    })
    if (-not $Ok) {
        $errors.Add("[$Component] $Status - $Details")
    }
}

# 1. Diagnostic state marker
$markerPath = Join-Path $csgo "diagnostic-state.json"
if (-not (Test-Path -LiteralPath $markerPath)) {
    $markerPath = Join-Path $csgo ".csbip\diagnostic-state.json"
}
if (Test-Path -LiteralPath $markerPath) {
    try {
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if ($marker.mode -ne $Mode) {
            Record-Check "Diagnostic Marker" "FAIL" "Marker indicates mode $($marker.mode), expected $Mode" $false
        } else {
            Record-Check "Diagnostic Marker" "PASS" "Mode $($marker.mode) marker verified" $true
        }
    } catch {
        Record-Check "Diagnostic Marker" "FAIL" "Cannot parse ${markerPath}: $($_.Exception.Message)" $false
    }
} else {
    Record-Check "Diagnostic Marker" "WARN" "diagnostic-state.json not found on target" $true
}

# 2. Metamod runtime
$mmLoader = Join-Path $csgo "addons\metamod\bin\win64\server.dll"
if (Test-Path -LiteralPath $mmLoader) {
    $actualHash = (Get-FileHash -LiteralPath $mmLoader -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -eq $expectedMetamodLoader) {
        Record-Check "Metamod 1469 Loader" "PASS" "server.dll matches pinned hash" $true
    } else {
        Record-Check "Metamod 1469 Loader" "FAIL" "server.dll hash mismatch: $actualHash" $false
    }
} else {
    Record-Check "Metamod 1469 Loader" "FAIL" "server.dll missing" $false
}

# 3. CSS runtime core
$cssCore = Join-Path $csgo "addons\counterstrikesharp\bin\win64\counterstrikesharp.dll"
if (Test-Path -LiteralPath $cssCore) {
    $actualHash = (Get-FileHash -LiteralPath $cssCore -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -eq $expectedCssCore) {
        Record-Check "CSS 375 Core" "PASS" "counterstrikesharp.dll matches pinned hash" $true
    } else {
        Record-Check "CSS 375 Core" "FAIL" "counterstrikesharp.dll hash mismatch: $actualHash" $false
    }
} else {
    Record-Check "CSS 375 Core" "FAIL" "counterstrikesharp.dll missing" $false
}

# 4. CSS gamedata
$cssGamedata = Join-Path $csgo "addons\counterstrikesharp\gamedata\gamedata.json"
if (Test-Path -LiteralPath $cssGamedata) {
    $actualHash = (Get-FileHash -LiteralPath $cssGamedata -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -eq $expectedCssGamedata) {
        Record-Check "CSS 375 Gamedata" "PASS" "gamedata.json matches CSS 375 signature release" $true
    } else {
        Record-Check "CSS 375 Gamedata" "FAIL" "gamedata.json hash mismatch (possible stale 371): $actualHash" $false
    }
} else {
    Record-Check "CSS 375 Gamedata" "FAIL" "gamedata.json missing" $false
}

# 5. CSS dotnet host
$cssDotnet = Join-Path $csgo "addons\counterstrikesharp\dotnet\dotnet.exe"
if (Test-Path -LiteralPath $cssDotnet) {
    $actualHash = (Get-FileHash -LiteralPath $cssDotnet -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -eq $expectedCssDotnetHost) {
        Record-Check "CSS 375 .NET Host" "PASS" "dotnet.exe matches pinned release" $true
    } else {
        Record-Check "CSS 375 .NET Host" "FAIL" "dotnet.exe hash mismatch: $actualHash" $false
    }
} else {
    Record-Check "CSS 375 .NET Host" "FAIL" "dotnet.exe missing" $false
}

# 6. BotHider native isolation
$botHiderVdf = Join-Path $csgo "addons\metamod\BotHider.vdf"
$botHiderVdfDisabled = Join-Path $csgo "addons\metamod\BotHider.vdf.csbip-disabled"
if (Test-Path -LiteralPath $botHiderVdf) {
    Record-Check "BotHider native" "FAIL" "Active BotHider.vdf found! Must be inactive for A/B bisection." $false
} elseif (Test-Path -LiteralPath $botHiderVdfDisabled) {
    Record-Check "BotHider native" "PASS" "BotHider.vdf is disabled (.csbip-disabled)" $true
} else {
    Record-Check "BotHider native" "PASS" "BotHider.vdf is not present" $true
}

# 7. BotHiderImpl isolation
$botHiderImplDll = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
$botHiderImplDllDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
if (Test-Path -LiteralPath $botHiderImplDll) {
    Record-Check "BotHiderImpl" "FAIL" "Active BotHiderImpl.dll found! Must be inactive for A/B bisection." $false
} elseif (Test-Path -LiteralPath $botHiderImplDllDisabled) {
    Record-Check "BotHiderImpl" "PASS" "BotHiderImpl.dll is disabled (.csbip-disabled)" $true
} else {
    Record-Check "BotHiderImpl" "PASS" "BotHiderImpl.dll is not present" $true
}

# 8. PlayerKnifeCustomizer (PlayerCosmetics) isolation
$knifeDll = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"
$knifeDllDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"

if ($Mode -eq "A") {
    if (Test-Path -LiteralPath $knifeDll) {
        Record-Check "PlayerCosmetics" "FAIL" "Active PlayerKnifeCustomizer.dll found! Must be OFF for Package A." $false
    } elseif (Test-Path -LiteralPath $knifeDllDisabled) {
        Record-Check "PlayerCosmetics" "PASS" "PlayerKnifeCustomizer.dll is disabled (.csbip-disabled)" $true
    } else {
        Record-Check "PlayerCosmetics" "PASS" "PlayerKnifeCustomizer.dll is not present" $true
    }
} else {
    if (-not (Test-Path -LiteralPath $knifeDll)) {
        Record-Check "PlayerCosmetics" "FAIL" "PlayerKnifeCustomizer.dll is missing! Must be ON for Package B." $false
    } else {
        $actualHash = (Get-FileHash -LiteralPath $knifeDll -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -eq $expectedKnifeCustomizerHash) {
            Record-Check "PlayerCosmetics" "PASS" "PlayerKnifeCustomizer.dll is active and matches current build" $true
        } else {
            Record-Check "PlayerCosmetics" "FAIL" "PlayerKnifeCustomizer.dll is present but hash mismatch (not current build): $actualHash" $false
        }
        if (Test-Path -LiteralPath $knifeDllDisabled) {
            Record-Check "PlayerCosmetics Residue" "WARN" "Leftover PlayerKnifeCustomizer.dll.csbip-disabled present" $true
        }
    }
}

# 9. Other standard Enhanced Bots components
$otherPlugins = @(
    "BotAI", "BotAimImprover", "BotBuy", "BotControllerImpl",
    "BotRandomizer", "BotState", "NadeSystem", "RoundDamageRecap",
    "PlusMatchCoordinator", "TeamLineupInjector", "OfflineMatchTelemetry"
)
$missingOther = @()
foreach ($p in $otherPlugins) {
    $pPath = Join-Path $csgo "addons\counterstrikesharp\plugins\$p\$p.dll"
    if (-not (Test-Path -LiteralPath $pPath)) {
        $missingOther += $p
    }
}
if ($missingOther.Count -eq 0) {
    Record-Check "Enhanced Bots plugins" "PASS" "All 11 enhanced bot plugins present and active" $true
} else {
    Record-Check "Enhanced Bots plugins" "FAIL" "Missing plugins: $($missingOther -join ', ')" $false
}

$checks | Format-Table -AutoSize

if ($errors.Count -gt 0) {
    $global:LASTEXITCODE = 1
    throw "Diagnostic verification FAILED for Mode ${Mode}:`n$($errors -join "`n")"
}

$global:LASTEXITCODE = 0
Write-Host "Diagnostic verification PASSED: target is reliably configured for Mode $Mode." -ForegroundColor Green
