[CmdletBinding()]
param(
    [string]$Cs2Root
)

$ErrorActionPreference = "Stop"

$runningCs2 = Get-Process -Name "cs2" -ErrorAction SilentlyContinue
if ($runningCs2) {
    throw "CS2 is currently running (PID: $($runningCs2.Id -join ', ')). Close CS2 before restoring."
}

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
Write-Host "Target CS2 game/csgo: $csgo"
Write-Host "Executing exact pre-diagnostic restore..."

Restore-DiagnosticSnapshot -CsgoRoot $csgo

Write-Host "Target has been restored to exact pre-diagnostic state." -ForegroundColor Green
