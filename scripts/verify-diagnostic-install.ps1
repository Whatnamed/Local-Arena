[CmdletBinding()]
param(
    [ValidateSet("A", "B")]
    [string]$Mode = "A",
    [string]$Cs2Root
)

$ErrorActionPreference = "Stop"

# Resolve DiagnosticTransaction helpers
$transactionScript = Join-Path $PSScriptRoot "DiagnosticTransaction.ps1"
if (-not (Test-Path -LiteralPath $transactionScript)) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "scripts\DiagnosticTransaction.ps1")) {
        $transactionScript = Join-Path $PSScriptRoot "scripts\DiagnosticTransaction.ps1"
    } else {
        throw "Could not locate DiagnosticTransaction.ps1"
    }
}
. $transactionScript

$csgo = Find-Cs2Root $Cs2Root
Write-Host "Target game/csgo: $csgo"
Write-Host "Verifying Diagnostic Mode: $Mode"
Write-Host "--------------------------------------------------------"

$manifestPath = Join-Path $PSScriptRoot "dependencies.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $manifestPath = Join-Path $PSScriptRoot "scripts\dependencies.json"
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $expectedMetamodLoader = "c57f348a49561e614768f20af8545998cab5ab7f8e4f913906c8889d34e40cfc"
    $expectedCssCore = "69334463860eed462993502b667ac4bec626ef0dc38c3977c792415c37bee1dd"
    $expectedCssGamedata = "7d9bff7aaff8e9edb1ada4ca508fa4e2ad7b12e16ed00ee1b84dd0cb9a3e4ac5"
    $expectedCssDotnetHost = "37c8f27cf35c5c59d942f7513496c3be68ba3018ed1b2220a31f5e5035df07ba"
} else {
    $depManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $expectedMetamodLoader = $depManifest.metamod.windowsLoaderSha256.ToLowerInvariant()
    $expectedCssCore = $depManifest.counterStrikeSharp.windowsCoreSha256.ToLowerInvariant()
    $expectedCssGamedata = $depManifest.counterStrikeSharp.windowsGamedataSha256.ToLowerInvariant()
    $expectedCssDotnetHost = $depManifest.counterStrikeSharp.windowsDotnetHostSha256.ToLowerInvariant()
}

$expectedKnifeCustomizerHash = $null
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildDll = Join-Path $repoRoot "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\bin\Release\net10.0\PlayerKnifeCustomizer.dll"
if (Test-Path -LiteralPath $buildDll) {
    $expectedKnifeCustomizerHash = (Get-FileHash -LiteralPath $buildDll -Algorithm SHA256).Hash.ToLowerInvariant()
} else {
    $manifestCandidates = @(
        (Join-Path $csgo "plus-payload-manifest.json"),
        (Join-Path $PSScriptRoot "plus-payload-manifest.json"),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts\diagnostic\stage-diagB\plus-payload-manifest.json")
    )
    foreach ($cand in $manifestCandidates) {
        if (Test-Path -LiteralPath $cand) {
            try {
                $payloadMan = Get-Content -LiteralPath $cand -Raw | ConvertFrom-Json
                $entry = $payloadMan.entries | Where-Object { $_.path -like "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll*" } | Select-Object -First 1
                if ($entry) {
                    $expectedKnifeCustomizerHash = $entry.sha256.ToLowerInvariant()
                    break
                }
            } catch {}
        }
    }
}
if (-not $expectedKnifeCustomizerHash) {
    $expectedKnifeCustomizerHash = "9e8c1f4d83962d5843865fdf1e255aa33bc714551b7c4fac7cc72b1ffa306c3b"
}

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

# 1. Exact runtime tree verification against diagnostic-runtime-manifest.json
$runtimeManifestCandidates = @(
    (Join-Path $csgo "diagnostic-runtime-manifest.json"),
    (Join-Path $csgo ".csbip\diagnostic-runtime-manifest.json"),
    (Join-Path $PSScriptRoot "diagnostic-runtime-manifest.json"),
    (Join-Path $PSScriptRoot "scripts\diagnostic-runtime-manifest.json"),
    (Join-Path (Split-Path -Parent $PSScriptRoot) "artifacts\diagnostic\stage-diag$Mode\diagnostic-runtime-manifest.json")
)

$runtimeManifestPath = $runtimeManifestCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $runtimeManifestPath) {
    Record-Check "Runtime Manifest" "FAIL" "diagnostic-runtime-manifest.json not found" $false
} else {
    try {
        $runtimeManifest = Get-Content -LiteralPath $runtimeManifestPath -Raw | ConvertFrom-Json
        $expectedMap = [ordered]@{}
        foreach ($entry in $runtimeManifest.entries) {
            $expectedMap[$entry.path] = $entry
        }

        # Enumerate actual files in target runtime-owned trees
        $actualMap = [ordered]@{}
        foreach ($tree in $Global:DiagnosticRuntimeTrees) {
            $treePath = Join-Path $csgo ($tree.Replace("/", "\"))
            if (Test-Path -LiteralPath $treePath) {
                foreach ($f in Get-ChildItem -LiteralPath $treePath -File -Recurse) {
                    $rel = [IO.Path]::GetRelativePath($csgo, $f.FullName).Replace("\", "/")
                    $actualMap[$rel] = $f
                }
            }
        }

        $missingFiles = [Collections.Generic.List[string]]::new()
        $unexpectedFiles = [Collections.Generic.List[string]]::new()
        $corruptFiles = [Collections.Generic.List[string]]::new()

        foreach ($path in $expectedMap.Keys) {
            if (-not $actualMap.Contains($path)) {
                $missingFiles.Add($path)
            } else {
                $actualFile = $actualMap[$path]
                $exp = $expectedMap[$path]
                if ($actualFile.Length -ne $exp.size) {
                    $corruptFiles.Add("$path (size mismatch: expected $($exp.size), actual $($actualFile.Length))")
                } else {
                    $actualHash = (Get-FileHash -LiteralPath $actualFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($actualHash -ne $exp.sha256) {
                        $corruptFiles.Add("$path (hash mismatch: expected $($exp.sha256), actual $actualHash)")
                    }
                }
            }
        }

        foreach ($path in $actualMap.Keys) {
            if (-not $expectedMap.Contains($path)) {
                $unexpectedFiles.Add($path)
            }
        }

        if ($missingFiles.Count -eq 0 -and $unexpectedFiles.Count -eq 0 -and $corruptFiles.Count -eq 0) {
            Record-Check "Exact Runtime Tree" "PASS" "All $($expectedMap.Count) runtime files matched exact MM1469+CSS375 manifest with 0 stale residues" $true
        } else {
            $errDetail = "Missing: $($missingFiles.Count), Unexpected: $($unexpectedFiles.Count), Corrupted: $($corruptFiles.Count)"
            if ($unexpectedFiles.Count -gt 0) {
                $errDetail += " [Stale residues: $($unexpectedFiles[0..([Math]::Min(2, $unexpectedFiles.Count - 1))] -join ', ')]"
            }
            if ($missingFiles.Count -gt 0) {
                $errDetail += " [Missing: $($missingFiles[0..([Math]::Min(2, $missingFiles.Count - 1))] -join ', ')]"
            }
            Record-Check "Exact Runtime Tree" "FAIL" $errDetail $false
        }
    }
    catch {
        Record-Check "Runtime Manifest" "FAIL" "Failed to verify runtime manifest: $($_.Exception.Message)" $false
    }
}

# 2. Diagnostic state marker
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

# 3. Representative runtime summaries
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

# 4. BotHider native isolation
$botHiderVdf = Join-Path $csgo "addons\metamod\BotHider.vdf"
$botHiderVdfDisabled = Join-Path $csgo "addons\metamod\BotHider.vdf.csbip-disabled"
if (Test-Path -LiteralPath $botHiderVdf) {
    Record-Check "BotHider native" "FAIL" "Active BotHider.vdf found! Must be inactive for A/B bisection." $false
} elseif (Test-Path -LiteralPath $botHiderVdfDisabled) {
    Record-Check "BotHider native" "PASS" "BotHider.vdf is disabled (.csbip-disabled)" $true
} else {
    Record-Check "BotHider native" "PASS" "BotHider.vdf is not present" $true
}

# 5. BotHiderImpl isolation
$botHiderImplDll = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
$botHiderImplDllDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"
if (Test-Path -LiteralPath $botHiderImplDll) {
    Record-Check "BotHiderImpl" "FAIL" "Active BotHiderImpl.dll found! Must be inactive for A/B bisection." $false
} elseif (Test-Path -LiteralPath $botHiderImplDllDisabled) {
    Record-Check "BotHiderImpl" "PASS" "BotHiderImpl.dll is disabled (.csbip-disabled)" $true
} else {
    Record-Check "BotHiderImpl" "PASS" "BotHiderImpl.dll is not present" $true
}

# 6. PlayerKnifeCustomizer (PlayerCosmetics) isolation
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

# 7. Other standard Enhanced Bots components
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
