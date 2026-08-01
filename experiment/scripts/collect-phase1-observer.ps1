param(
    [Parameter(Mandatory = $true)][string]$ManagementUrl,
    [Parameter(Mandatory = $true)][Alias("OutputPath")][string]$OutputDirectory,
    [int]$DurationSeconds = 145,
    [int]$IntervalMilliseconds = 1000
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$paths = @{
    stage = Join-Path $OutputDirectory "stage-observation.jsonl"
    pool = Join-Path $OutputDirectory "pool-metrics.jsonl"
    admission = Join-Path $OutputDirectory "admission-metrics.jsonl"
}
$counts = @{ stage = 0; pool = 0; admission = 0 }
$failures = @{ stage = 0; pool = 0; admission = 0 }
$recoveredFailures = @{ stage = 0; pool = 0; admission = 0 }
$started = Get-Date
$deadline = $started.AddSeconds($DurationSeconds)

function Capture([string]$Kind, [string]$Path, [string]$Endpoint) {
    $capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    $startedAt = Get-Date
    $attempts = 0
    $snapshot = $null
    $lastError = $null
    while ($attempts -lt 2 -and $null -eq $snapshot) {
        $attempts++
        try { $snapshot = Invoke-RestMethod -Uri ($ManagementUrl.TrimEnd('/') + $Endpoint) -TimeoutSec 5 }
        catch { $lastError = $_.Exception.Message; if ($attempts -lt 2) { Start-Sleep -Milliseconds 100 } }
    }
    $ok = $null -ne $snapshot
    if (-not $ok) { $failures[$Kind]++ } elseif ($attempts -gt 1) { $recoveredFailures[$Kind]++ }
    $row = [ordered]@{ timestamp = $capturedAt; startedAt = $startedAt.ToUniversalTime().ToString("o"); finishedAt = (Get-Date).ToUniversalTime().ToString("o"); ok = $ok; attempts = $attempts; recovered = $ok -and $attempts -gt 1; snapshot = $snapshot; error = if ($ok) { $null } else { $lastError } }
    $counts[$Kind]++
    $row | ConvertTo-Json -Depth 10 -Compress | Add-Content -Encoding UTF8 -LiteralPath $Path
}

while ((Get-Date) -lt $deadline) {
    $cycleStarted = Get-Date
    Capture "stage" $paths.stage "/actuator/doengstages"
    Capture "pool" $paths.pool "/actuator/doengdiagnosticpool"
    Capture "admission" $paths.admission "/actuator/doengadmission"
    $remaining = $IntervalMilliseconds - ((Get-Date) - $cycleStarted).TotalMilliseconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]$remaining) }
}

$summary = [ordered]@{
    startedAt = $started.ToUniversalTime().ToString("o")
    finishedAt = (Get-Date).ToUniversalTime().ToString("o")
    durationSeconds = $DurationSeconds
    intervalMilliseconds = $IntervalMilliseconds
    counts = $counts
    failures = $failures
    recoveredFailures = $recoveredFailures
    totalFailures = ($failures.Values | Measure-Object -Sum).Sum
    paths = $paths
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutputDirectory "phase1-observer.summary.json")
