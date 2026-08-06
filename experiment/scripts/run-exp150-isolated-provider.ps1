param(
    [Parameter(Mandatory = $true)][string]$ExpectedCommit,
    [ValidateSet("PREFLIGHT", "EXECUTE")][string]$ExecutionMode = "PREFLIGHT"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$cell = Join-Path $repo "experiment\scripts\run-exp150-isolated-provider-cell.ps1"
$resultRoot = Join-Path $repo "backend\experiments\results\experiment-1-50\isolated-provider"
$gitSafe = "safe.directory=$($repo.Replace('\', '/'))"
$head = (& git -C $repo -c $gitSafe rev-parse HEAD).Trim()
if ($head -ne $ExpectedCommit) { throw "Commit mismatch: expected $ExpectedCommit, actual $head" }
if (-not (Test-Path -LiteralPath $cell)) { throw "Calibration cell runner not found" }

foreach ($mode in @("D", "P")) {
    if ($ExecutionMode -eq "EXECUTE") {
        $existingSummary = if ($mode -eq "P") { Join-Path $resultRoot "a1b1-performance-001\analysis\run-summary.json" } else { Join-Path $resultRoot "a1b1-diagnostic-001\analysis\run-summary.json" }
        if (Test-Path -LiteralPath $existingSummary) {
            $reuseMarker = if ($mode -eq "P") { "EXP150_A1B1_P_EXISTING_ARTIFACT_REUSED" } else { "EXP150_A1B1_D_EXISTING_ARTIFACT_REUSED" }
            Write-Output $reuseMarker
            continue
        }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cell -ExpectedCommit $ExpectedCommit -ExecutionMode $ExecutionMode -ObservationMode $mode
    if ($LASTEXITCODE -ne 0) { throw "Exp150 isolated-provider cell $mode failed" }
}

if ($ExecutionMode -eq "PREFLIGHT") {
    Write-Output "EXP150_STATIC_PREFLIGHT_PASS"
    exit 0
}

$p = Join-Path $resultRoot "a1b1-performance-001\analysis\run-summary.json"
$d = Join-Path $resultRoot "a1b1-diagnostic-001\analysis\run-summary.json"
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
$rpsP = [double]$performance.client.http200 / 30.0
$rpsD = [double]$diagnostic.client.http200 / 30.0
$delta.successfulRps = $rpsD - $rpsP
$classification = if ([math]::Abs((PctDelta $performance.client.http200 $diagnostic.client.http200)) -le 0.05 -and [math]::Abs((PctDelta $performance.client.p95Ms $diagnostic.client.p95Ms)) -le 0.05) { "OBSERVATION_OVERHEAD_LOW" } elseif ([math]::Abs((PctDelta $performance.client.http200 $diagnostic.client.http200)) -gt 0.15 -or [math]::Abs((PctDelta $performance.client.p95Ms $diagnostic.client.p95Ms)) -gt 0.15) { "OBSERVATION_OVERHEAD_SEVERE" } else { "OBSERVATION_OVERHEAD_MATERIAL" }
$analysisDir = Join-Path $resultRoot "analysis"
New-Item -ItemType Directory -Force -Path $analysisDir | Out-Null
$result = [ordered]@{ experiment = "Exp150"; factor = "B_ISOLATED_PROVIDERS"; performance = $performance; diagnostic = $diagnostic; diagnosticMinusPerformance = $delta; classification = "NOT_A_CALIBRATION_COMPARISON"; additionalRuns = 0 }
$result | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $analysisDir "exp150-isolated-provider-summary.json") -Encoding UTF8
$report = @"
# Exp150 Isolated Provider Summary

## Ordered runs

- A1B1-P HTTP200: $($performance.client.http200); p95: $($performance.client.p95Ms) ms; timeout: $($performance.client.clientTimeout)
- A1B1-D HTTP200: $($diagnostic.client.http200); p95: $($diagnostic.client.p95Ms) ms; timeout: $($diagnostic.client.clientTimeout)
- A1B1-D was executed before A1B1-P.
- This diagnostic/performance pair is not an observation-overhead comparison.

## Interpretation guard

This is a single isolated-provider diagnostic plus performance pair. It does not establish a general production recommendation.
"@
$report | Set-Content (Join-Path $analysisDir "exp150-isolated-provider-report.md") -Encoding UTF8
Write-Output "EXP150_ISOLATED_PROVIDER_COMPLETE"

