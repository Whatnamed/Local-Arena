# Comprehensive integration tests for Diagnostic A/B Transaction, Exact Purge, and Exact Restore
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "DiagnosticTransaction.ps1")

$testBase = Join-Path $repo ".cache\test-diagnostic-lifecycle"
if (Test-Path -LiteralPath $testBase) {
    Remove-Item -LiteralPath $testBase -Recurse -Force
}
New-Item -ItemType Directory -Path $testBase -Force | Out-Null

function Setup-BaseTarget {
    param([string]$Target)
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\metamod\bin\win64") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\bin\win64") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\dotnet") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\gamedata") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\lang") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\plugins\BotHiderImpl") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Target "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer") -Force | Out-Null
    
    # gameinfo
    '"GameInfo" { "FileSystem" { "SearchPaths" { "Game" "csgo" } } }' | Set-Content (Join-Path $Target "gameinfo.gi")

    # Mock older runtime files
    "dummy-old-server-dll" | Set-Content (Join-Path $Target "addons\metamod\bin\win64\server.dll")
    "dummy-old-css-dll" | Set-Content (Join-Path $Target "addons\counterstrikesharp\bin\win64\counterstrikesharp.dll")
    "dummy-old-dotnet" | Set-Content (Join-Path $Target "addons\counterstrikesharp\dotnet\dotnet.exe")
    "dummy-old-gamedata" | Set-Content (Join-Path $Target "addons\counterstrikesharp\gamedata\gamedata.json")

    # User preset that must NOT be overwritten
    '{"custom_knife": "butterfly", "preserved": true}' | Set-Content (Join-Path $Target "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\player_knife_presets.json")
}

Write-Host "=========================================================="
Write-Host "Running Diagnostic Transaction Simulation Tests (Cases 1-5)"
Write-Host "=========================================================="

# -------------------------------------------------------------------
# Case 1: Pre-test all components active
# Original active -> Install A -> Verify A -> Install B -> Verify B -> Restore -> Exact Original
# -------------------------------------------------------------------
Write-Host "`n--- Case 1: All components active pre-test ---"
$c1 = Join-Path $testBase "case1\game\csgo"
Setup-BaseTarget $c1

"vdf-content-c1" | Set-Content (Join-Path $c1 "addons\metamod\BotHider.vdf")
"impl-dll-c1" | Set-Content (Join-Path $c1 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll")
"knife-dll-c1" | Set-Content (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll")

$vdfOriginalHash = (Get-FileHash (Join-Path $c1 "addons\metamod\BotHider.vdf") -Algorithm SHA256).Hash
$implOriginalHash = (Get-FileHash (Join-Path $c1 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll") -Algorithm SHA256).Hash
$knifeOriginalHash = (Get-FileHash (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll") -Algorithm SHA256).Hash

Write-Host "Installing Mode A..."
& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode A -Cs2Root $c1
& (Join-Path $PSScriptRoot "verify-diagnostic-install.ps1") -Mode A -Cs2Root $c1
if ($LASTEXITCODE -ne 0) { throw "Case 1: Mode A verification failed" }

Write-Host "Installing Mode B (switching from A)..."
& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode B -Cs2Root $c1
& (Join-Path $PSScriptRoot "verify-diagnostic-install.ps1") -Mode B -Cs2Root $c1
if ($LASTEXITCODE -ne 0) { throw "Case 1: Mode B verification failed" }

Write-Host "Restoring to pre-test state..."
& (Join-Path $PSScriptRoot "restore-normal-install.ps1") -Cs2Root $c1

# Assert all 3 are active and match original hashes
if (-not (Test-Path (Join-Path $c1 "addons\metamod\BotHider.vdf"))) { throw "Case 1: BotHider.vdf not active after restore" }
if (Test-Path (Join-Path $c1 "addons\metamod\BotHider.vdf.csbip-disabled")) { throw "Case 1: BotHider.vdf.csbip-disabled lingering" }
if ((Get-FileHash (Join-Path $c1 "addons\metamod\BotHider.vdf") -Algorithm SHA256).Hash -ne $vdfOriginalHash) { throw "Case 1: BotHider.vdf hash mismatch" }

if (-not (Test-Path (Join-Path $c1 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"))) { throw "Case 1: BotHiderImpl.dll not active" }
if (Test-Path (Join-Path $c1 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled")) { throw "Case 1: BotHiderImpl.dll.csbip-disabled lingering" }
if ((Get-FileHash (Join-Path $c1 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll") -Algorithm SHA256).Hash -ne $implOriginalHash) { throw "Case 1: BotHiderImpl.dll hash mismatch" }

if (-not (Test-Path (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"))) { throw "Case 1: PlayerKnifeCustomizer.dll not active" }
if (Test-Path (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled")) { throw "Case 1: PlayerKnifeCustomizer.dll.csbip-disabled lingering" }
if ((Get-FileHash (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll") -Algorithm SHA256).Hash -ne $knifeOriginalHash) { throw "Case 1: PlayerKnifeCustomizer.dll hash mismatch" }

# Assert user preset preserved
$c1Preset = Get-Content (Join-Path $c1 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\player_knife_presets.json") -Raw
if ($c1Preset -notmatch '"butterfly"') { throw "Case 1: User preset was overwritten!" }

# Assert original runtime server.dll was restored
if ((Get-Content (Join-Path $c1 "addons\metamod\bin\win64\server.dll") -Raw).Trim() -ne "dummy-old-server-dll") {
    throw "Case 1: Original runtime tree was not restored!"
}

Write-Host "Case 1 PASSED: All active components and original runtime restored exactly." -ForegroundColor Green

# -------------------------------------------------------------------
# Case 2: BotHider was already disabled pre-test
# Restore must keep it disabled, must NOT activate it!
# -------------------------------------------------------------------
Write-Host "`n--- Case 2: BotHider already disabled pre-test ---"
$c2 = Join-Path $testBase "case2\game\csgo"
Setup-BaseTarget $c2

"disabled-vdf-c2" | Set-Content (Join-Path $c2 "addons\metamod\BotHider.vdf.csbip-disabled")
"disabled-impl-c2" | Set-Content (Join-Path $c2 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled")
"knife-dll-c2" | Set-Content (Join-Path $c2 "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll")

& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode A -Cs2Root $c2
& (Join-Path $PSScriptRoot "restore-normal-install.ps1") -Cs2Root $c2

if (Test-Path (Join-Path $c2 "addons\metamod\BotHider.vdf")) {
    throw "Case 2: BotHider.vdf was illegally re-activated! Must remain disabled."
}
if (-not (Test-Path (Join-Path $c2 "addons\metamod\BotHider.vdf.csbip-disabled"))) {
    throw "Case 2: BotHider.vdf.csbip-disabled was lost!"
}
if ((Get-Content (Join-Path $c2 "addons\metamod\BotHider.vdf.csbip-disabled") -Raw).Trim() -ne "disabled-vdf-c2") {
    throw "Case 2: BotHider.vdf.csbip-disabled content mismatch!"
}

if (Test-Path (Join-Path $c2 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll")) {
    throw "Case 2: BotHiderImpl.dll was illegally re-activated!"
}
if (-not (Test-Path (Join-Path $c2 "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll.csbip-disabled"))) {
    throw "Case 2: BotHiderImpl.dll.csbip-disabled was lost!"
}

Write-Host "Case 2 PASSED: Pre-disabled component remained disabled after restore." -ForegroundColor Green

# -------------------------------------------------------------------
# Case 3: Pre-test has both active and disabled residue
# Must restore both, no auto-normalization.
# -------------------------------------------------------------------
Write-Host "`n--- Case 3: Both active and disabled residue exist pre-test ---"
$c3 = Join-Path $testBase "case3\game\csgo"
Setup-BaseTarget $c3

"active-vdf-c3" | Set-Content (Join-Path $c3 "addons\metamod\BotHider.vdf")
"disabled-vdf-c3" | Set-Content (Join-Path $c3 "addons\metamod\BotHider.vdf.csbip-disabled")

& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode A -Cs2Root $c3
& (Join-Path $PSScriptRoot "restore-normal-install.ps1") -Cs2Root $c3

if (-not (Test-Path (Join-Path $c3 "addons\metamod\BotHider.vdf"))) {
    throw "Case 3: Active BotHider.vdf was not restored!"
}
if (-not (Test-Path (Join-Path $c3 "addons\metamod\BotHider.vdf.csbip-disabled"))) {
    throw "Case 3: Disabled BotHider.vdf.csbip-disabled was not restored!"
}
if ((Get-Content (Join-Path $c3 "addons\metamod\BotHider.vdf") -Raw).Trim() -ne "active-vdf-c3") {
    throw "Case 3: Active BotHider.vdf content mismatch!"
}
if ((Get-Content (Join-Path $c3 "addons\metamod\BotHider.vdf.csbip-disabled") -Raw).Trim() -ne "disabled-vdf-c3") {
    throw "Case 3: Disabled BotHider.vdf content mismatch!"
}

Write-Host "Case 3 PASSED: Both active and disabled residues were restored faithfully." -ForegroundColor Green

# -------------------------------------------------------------------
# Case 4: Pre-test runtime tree has an extra stale file
# Install A must cleanly purge it (0 stale residue in A).
# Restore must restore this file with matching hash.
# -------------------------------------------------------------------
Write-Host "`n--- Case 4: Pre-test runtime directory has extra stale file ---"
$c4 = Join-Path $testBase "case4\game\csgo"
Setup-BaseTarget $c4

$staleFile = Join-Path $c4 "addons\counterstrikesharp\dotnet\stale_371_file.dll"
"stale-css371-binary-content" | Set-Content $staleFile
$staleOriginalHash = (Get-FileHash $staleFile -Algorithm SHA256).Hash

Write-Host "Installing Mode A with stale file present..."
& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode A -Cs2Root $c4

# Verify that stale file was completely purged from target runtime!
if (Test-Path $staleFile) {
    throw "Case 4: Stale file $staleFile was NOT purged during clean diagnostic install!"
}

# Verify that Mode A passes exact runtime tree verification (all 431 files match, 0 stale residues)
& (Join-Path $PSScriptRoot "verify-diagnostic-install.ps1") -Mode A -Cs2Root $c4
if ($LASTEXITCODE -ne 0) { throw "Case 4: Mode A exact runtime check failed" }
Write-Host "Clean purge confirmed: stale file disappeared and exact runtime verified." -ForegroundColor Cyan

Write-Host "Restoring pre-test state..."
& (Join-Path $PSScriptRoot "restore-normal-install.ps1") -Cs2Root $c4

# Verify that stale file was restored back to original state with matching hash!
if (-not (Test-Path $staleFile)) {
    throw "Case 4: Stale file was not restored back from snapshot!"
}
$staleRestoredHash = (Get-FileHash $staleFile -Algorithm SHA256).Hash
if ($staleRestoredHash -ne $staleOriginalHash) {
    throw "Case 4: Stale file restored hash mismatch: expected $staleOriginalHash, got $staleRestoredHash"
}

Write-Host "Case 4 PASSED: Clean purge eliminated stale file in A, exact restore returned it." -ForegroundColor Green

# -------------------------------------------------------------------
# Case 5: A -> B must NOT overwrite original snapshot
# -------------------------------------------------------------------
Write-Host "`n--- Case 5: A -> B does not overwrite original snapshot ---"
$c5 = Join-Path $testBase "case5\game\csgo"
Setup-BaseTarget $c5
"pre-test-unique-marker" | Set-Content (Join-Path $c5 "addons\metamod\bin\win64\server.dll")

& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode A -Cs2Root $c5
$snapshotManifestPath = Join-Path $c5 ".csbip\diagnostic-snapshot\snapshot-manifest.json"
$snapshotA = Get-Content $snapshotManifestPath -Raw | ConvertFrom-Json
$createdTimestampA = $snapshotA.created_at

Start-Sleep -Seconds 1

& (Join-Path $PSScriptRoot "install-diagnostic.ps1") -Mode B -Cs2Root $c5
$snapshotB = Get-Content $snapshotManifestPath -Raw | ConvertFrom-Json
$createdTimestampB = $snapshotB.created_at

if ($createdTimestampA -ne $createdTimestampB) {
    throw "Case 5: Snapshot was overwritten during Mode B install! ($createdTimestampA vs $createdTimestampB)"
}

& (Join-Path $PSScriptRoot "restore-normal-install.ps1") -Cs2Root $c5
$restoredServerDll = (Get-Content (Join-Path $c5 "addons\metamod\bin\win64\server.dll") -Raw).Trim()
if ($restoredServerDll -ne "pre-test-unique-marker") {
    throw "Case 5: Restored server.dll does not match original pre-A content!"
}

Write-Host "Case 5 PASSED: Snapshot was preserved across A -> B transition and exact pre-A state restored." -ForegroundColor Green

Write-Host "`n=========================================================="
Write-Host "ALL 5 DIAGNOSTIC TRANSACTION TEST CASES PASSED SUCCESSFULLY"
Write-Host "=========================================================="

Remove-Item -LiteralPath $testBase -Recurse -Force
