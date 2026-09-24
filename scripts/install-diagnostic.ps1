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

# Resolve DiagnosticTransaction helpers
$transactionScript = Join-Path $PSScriptRoot "DiagnosticTransaction.ps1"
if (-not (Test-Path -LiteralPath $transactionScript)) {
    if ($PackageSource -and (Test-Path -LiteralPath (Join-Path $PackageSource "scripts\DiagnosticTransaction.ps1"))) {
        $transactionScript = Join-Path $PackageSource "scripts\DiagnosticTransaction.ps1"
    } elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot "scripts\DiagnosticTransaction.ps1")) {
        $transactionScript = Join-Path $PSScriptRoot "scripts\DiagnosticTransaction.ps1"
    } else {
        throw "Could not locate DiagnosticTransaction.ps1"
    }
}
. $transactionScript

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

# Step 1: Ensure pre-diagnostic snapshot exists before any changes
$snapshot = Ensure-DiagnosticSnapshot $csgo

# Step 2: Perform clean diagnostic install with rollback guard
try {
    # 2.1 Clean purge of target runtime trees to eliminate any stale 371 or old MM files
    Write-Host "Purging target runtime trees for clean MM1469 + CSS375 convergence..."
    foreach ($tree in $Global:DiagnosticRuntimeTrees) {
        $treePath = Join-Path $csgo ($tree.Replace("/", "\"))
        if (Test-Path -LiteralPath $treePath) {
            Remove-Item -LiteralPath $treePath -Recurse -Force
        }
    }

    # 2.2 Reconcile component states before copy
    Write-Host "Reconciling component entry states..."
    $targetVdf = Join-Path $csgo "addons\metamod\BotHider.vdf"
    $targetImpl = Join-Path $csgo "addons\counterstrikesharp\plugins\BotHiderImpl\BotHiderImpl.dll"
    $targetKnife = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll"
    $targetKnifeDisabled = Join-Path $csgo "addons\counterstrikesharp\plugins\PlayerKnifeCustomizer\PlayerKnifeCustomizer.dll.csbip-disabled"

    if (Test-Path -LiteralPath $targetVdf) { Remove-Item -LiteralPath $targetVdf -Force }
    if (Test-Path -LiteralPath $targetImpl) { Remove-Item -LiteralPath $targetImpl -Force }

    if ($Mode -eq "A") {
        if (Test-Path -LiteralPath $targetKnife) { Remove-Item -LiteralPath $targetKnife -Force }
    } else {
        if (Test-Path -LiteralPath $targetKnifeDisabled) { Remove-Item -LiteralPath $targetKnifeDisabled -Force }
    }

    # 2.3 Copy diagnostic payload to target
    Write-Host "Copying diagnostic package payload to target..."
    $topLevels = @("addons", "cfg", "overrides")
    $copiedFiles = 0
    $preservedFiles = 0

    foreach ($topLevel in $topLevels) {
        $sourceTop = Join-Path $PackageSource $topLevel
        if (-not (Test-Path -LiteralPath $sourceTop)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $sourceTop -File -Recurse) {
            $rel = [IO.Path]::GetRelativePath($PackageSource, $file.FullName).Replace("\", "/")
            $targetFile = Join-Path $csgo ($rel.Replace("/", "\"))
            if ($rel -in $Global:DiagnosticPreservedConfigs -and (Test-Path -LiteralPath $targetFile)) {
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

    # 2.4 Copy runtime manifest into target for post-install verification
    $runtimeManifestSrc = Join-Path $PackageSource "diagnostic-runtime-manifest.json"
    if (-not (Test-Path -LiteralPath $runtimeManifestSrc)) {
        $runtimeManifestSrc = Join-Path $PackageSource "scripts\diagnostic-runtime-manifest.json"
    }
    if (Test-Path -LiteralPath $runtimeManifestSrc) {
        Copy-Item -LiteralPath $runtimeManifestSrc -Destination (Join-Path $csgo "diagnostic-runtime-manifest.json") -Force
        $csbipDir = Join-Path $csgo ".csbip"
        if (Test-Path -LiteralPath $csbipDir) {
            Copy-Item -LiteralPath $runtimeManifestSrc -Destination (Join-Path $csbipDir "diagnostic-runtime-manifest.json") -Force
        }
    }

    # 2.5 Enforce final active/disabled guarantees on target
    if ($Mode -eq "A") {
        if (Test-Path -LiteralPath $targetVdf) { Remove-Item -LiteralPath $targetVdf -Force }
        if (Test-Path -LiteralPath $targetImpl) { Remove-Item -LiteralPath $targetImpl -Force }
        if (Test-Path -LiteralPath $targetKnife) { Remove-Item -LiteralPath $targetKnife -Force }
    } else {
        if (Test-Path -LiteralPath $targetVdf) { Remove-Item -LiteralPath $targetVdf -Force }
        if (Test-Path -LiteralPath $targetImpl) { Remove-Item -LiteralPath $targetImpl -Force }
        if (Test-Path -LiteralPath $targetKnifeDisabled) { Remove-Item -LiteralPath $targetKnifeDisabled -Force }
    }

    # 2.6 Write diagnostic state marker
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

    # 2.7 Verification
    if (-not $SkipVerify) {
        Write-Host "Running post-install verification..."
        $verifier = Join-Path $PSScriptRoot "verify-diagnostic-install.ps1"
        if (-not (Test-Path -LiteralPath $verifier)) {
            $verifier = Join-Path $PackageSource "VERIFY-DIAGNOSTIC.ps1"
        }
        if (-not (Test-Path -LiteralPath $verifier)) {
            $verifier = Join-Path $PackageSource "scripts\verify-diagnostic-install.ps1"
        }
        if (Test-Path -LiteralPath $verifier) {
            & $verifier -Mode $Mode -Cs2Root $csgo
        } else {
            Write-Warning "Verifier script not found; skipping automatic post-install check."
        }
    }
}
catch {
    Write-Warning "Diagnostic install failed: $($_.Exception.Message)"
    Write-Warning "Attempting automatic rollback to pre-diagnostic snapshot..."
    try {
        Restore-DiagnosticSnapshot -CsgoRoot $csgo -RetainSnapshotOnSuccess
        Write-Host "Automatic rollback succeeded: target restored to pre-test state." -ForegroundColor Yellow
    }
    catch {
        Write-Error "Automatic rollback FAILED: $($_.Exception.Message)"
        Write-Error "Snapshot preserved at $csgo\.csbip\diagnostic-snapshot. Manual recovery required."
    }
    throw
}

Write-Host "Diagnostic Package $Mode successfully installed to $csgo." -ForegroundColor Green
Write-Host "Do NOT start CS2 through Panel! Launch CS2 directly or via Steam." -ForegroundColor Yellow
