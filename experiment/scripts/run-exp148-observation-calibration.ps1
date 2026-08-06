param(
    [Parameter(Mandatory = $true)][string]$ExpectedCommit,
    [ValidateSet("PREFLIGHT", "EXECUTE")][string]$ExecutionMode = "PREFLIGHT"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$cell = Join-Path $repo "experiment\scripts\run-exp148-observation-calibration-cell.ps1"
$resultRoot = Join-Path $repo "backend\experiments\results\experiment-1-48\a1b0-observation-calibration"
$gitSafe = "safe.directory=$($repo.Replace('\', '/'))"
$head = (& git -C $repo -c $gitSafe rev-parse HEAD).Trim()
if ($head -ne $ExpectedCommit) { throw "Commit mismatch: expected $ExpectedCommit, actual $head" }
if (-not (Test-Path -LiteralPath $cell)) { throw "Calibration cell runner not found" }

foreach ($mode in @("P", "D")) {
    if ($ExecutionMode -eq "EXECUTE") {
        $existingSummary = if ($mode -eq "P") { Join-Path $resultRoot "performance-001\analysis\run-summary.json" } else { Join-Path $resultRoot "diagnostic-001\analysis\run-summary.json" }
        if (Test-Path -LiteralPath $existingSummary) {
            $reuseMarker = if ($mode -eq "P") { "EXP148_A1B0_P_EXISTING_ARTIFACT_REUSED" } else { "EXP148_A1B0_D_EXISTING_ARTIFACT_REUSED" }
            Write-Output $reuseMarker
            continue
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cell -ExpectedCommit $ExpectedCommit -ExecutionMode $ExecutionMode -ObservationMode $mode
    if ($LASTEXITCODE -ne 0) { throw "Exp148 cell $mode failed" }
}

if ($ExecutionMode -eq "PREFLIGHT") {
    Write-Output "EXP148_STATIC_PREFLIGHT_PASS"
    exit 0
}

$p = Join-Path $resultRoot "performance-001\analysis\run-summary.json"
$d = Join-Path $resultRoot "diagnostic-001\analysis\run-summary.json"
if (-not (Test-Path $p) -or -not (Test-Path $d)) { throw "Both calibration summaries are required" }
$performance = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
$diagnostic = Get-Content $d -Raw -Encoding UTF8 | ConvertFrom-Json
function Delta($a, $b) { if ($null -eq $a -or $null -eq $b) { return $null }; return ([double]$b - [double]$a) }
function PctDelta($a, $b) { if ($null -eq $a -or $a -eq 0 -or $null -eq $b) { return $null }; return (([double]$b - [double]$a) / [double]$a) }
$delta = [ordered]@{
    successfulRps = Delta $performance.client.attempts $diagnostic.client.attempts
    http200 = Delta $performance.client.http200 $diagnostic.client.http200
    http500 = Delta $performance.client.http500 $diagnostic.client.http500
    timeout = Delta $performance.client.clientTimeout $diagnostic.client.clientTimeout
    connectionError = Delta $performance.client.connectionError $diagnostic.client.connectionError
    successRate = Delta $performance.client.successRate $diagnostic.client.successRate
    p50 = Delta $performance.client.p50Ms $diagnostic.client.p50Ms
    p95 = Delta $performance.client.p95Ms $diagnostic.client.p95Ms
    p99 = Delta $performance.client.p99Ms $diagnostic.client.p99Ms
    appCpuPeak = $null
    appMemoryPeak = $null
    webClientPending = Delta $performance.timeline.peakPendingConnections $diagnostic.timeline.peakPendingConnections
    pendingLimit = Delta $performance.exceptions.poolAcquirePendingLimit $diagnostic.exceptions.poolAcquirePendingLimit
    r2dbcPending = $null
}
$rpsP = if ($performance.client.mockDrain) { [double]$performance.client.http200 / 30.0 } else { $null }
$rpsD = [double]$diagnostic.client.http200 / 30.0
$delta.successfulRps = $rpsD - $rpsP
$classification = if ([math]::Abs((PctDelta $performance.client.http200 $diagnostic.client.http200)) -le 0.05 -and [math]::Abs((PctDelta $performance.client.p95Ms $diagnostic.client.p95Ms)) -le 0.05) { "OBSERVATION_OVERHEAD_LOW" } elseif ([math]::Abs((PctDelta $performance.client.http200 $diagnostic.client.http200)) -gt 0.15 -or [math]::Abs((PctDelta $performance.client.p95Ms $diagnostic.client.p95Ms)) -gt 0.15) { "OBSERVATION_OVERHEAD_SEVERE" } else { "OBSERVATION_OVERHEAD_MATERIAL" }
$analysisDir = Join-Path $resultRoot "analysis"
New-Item -ItemType Directory -Force -Path $analysisDir | Out-Null
$result = [ordered]@{ experiment = "Exp148"; performance = $performance; diagnostic = $diagnostic; observationOnMinusOff = $delta; classification = $classification; atomicityClassification = "SEE_PHASE_1_TEST"; additionalRuns = 0 }
$result | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $analysisDir "exp148-observation-calibration-summary.json") -Encoding UTF8
$report = @"
# Exp148 Observation Calibration Report

## Phase 2

- A1B0-P HTTP200: $($performance.client.http200); p95: $($performance.client.p95Ms) ms; timeout: $($performance.client.clientTimeout)
- A1B0-D HTTP200: $($diagnostic.client.http200); p95: $($diagnostic.client.p95Ms) ms; timeout: $($diagnostic.client.clientTimeout)
- Observation ON minus OFF HTTP200: $($delta.http200)
- Observation ON minus OFF p95: $($delta.p95) ms
- Observation classification: **$classification**

## Interpretation guard

This is a single ordered calibration pair, not a statistical significance claim. Existing Exp146/147 performance conclusions are not reclassified solely from this pair.
"@
$report | Set-Content (Join-Path $analysisDir "exp148-observation-calibration-report.md") -Encoding UTF8
Write-Output "EXP148_CALIBRATION_COMPLETE"
