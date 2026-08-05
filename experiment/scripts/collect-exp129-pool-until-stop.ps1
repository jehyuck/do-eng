param(
    [Parameter(Mandatory = $true)][string]$ManagementUrl,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [Parameter(Mandatory = $true)][string]$StopSignalPath,
    [int]$IntervalMilliseconds = 1000,
    [int]$RequestTimeoutSeconds = 5,
    [int]$MaxDurationSeconds = 300
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath),(Split-Path -Parent $SummaryPath) | Out-Null
$started = [DateTimeOffset]::UtcNow
$attempts = 0; $samples = 0; $failures = 0; $lastValid = $null; $maxGap = 0.0
$status = 'COLLECTOR_MAX_DURATION_EXCEEDED'; $stopObserved = $false

function Write-Row([object]$Value) {
    [IO.File]::AppendAllText($OutputPath, (($Value | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

try {
    $deadline = $started.AddSeconds($MaxDurationSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $attempts++
        $requestStarted = [DateTimeOffset]::UtcNow
        try {
            $payload = Invoke-RestMethod -Uri ($ManagementUrl.TrimEnd('/') + '/actuator/doengdiagnosticpool') -TimeoutSec $RequestTimeoutSeconds
            $completed = [DateTimeOffset]::UtcNow
            $timestamp = $requestStarted.ToString('o')
            if ($null -ne $lastValid) {
                $gap = ($requestStarted - $lastValid).TotalMilliseconds
                if ($gap -gt $maxGap) { $maxGap = [math]::Round($gap, 3) }
            }
            $lastValid = $requestStarted
            $samples++
            Write-Row ([ordered]@{
                ok = $true; timestamp = $timestamp; requestStartedAt = $timestamp; requestCompletedAt = $completed.ToString('o')
                elapsedMilliseconds = [math]::Round(($completed - $requestStarted).TotalMilliseconds, 3); httpStatus = 200
                poolMode = $payload.poolMode; providers = @($payload.providers); metrics = @($payload.metrics); failure = $null
            })
        } catch {
            $failures++
            $completed = [DateTimeOffset]::UtcNow
            Write-Row ([ordered]@{
                ok = $false; timestamp = $requestStarted.ToString('o'); requestStartedAt = $requestStarted.ToString('o'); requestCompletedAt = $completed.ToString('o')
                elapsedMilliseconds = [math]::Round(($completed - $requestStarted).TotalMilliseconds, 3); httpStatus = $null
                poolMode = $null; providers = @(); metrics = @(); failure = $_.Exception.Message
            })
        }
        if (Test-Path -LiteralPath $StopSignalPath) { $stopObserved = $true; $status = 'COLLECTOR_STOPPED_BY_SIGNAL'; break }
        $next = $requestStarted.AddMilliseconds($IntervalMilliseconds)
        $sleepMs = [int][math]::Max(0, ($next - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
    }
} finally {
    [ordered]@{
        collectorStatus = $status; collectorProcessStartedAt = $started.ToString('o'); collectorProcessCompletedAt = [DateTimeOffset]::UtcNow.ToString('o')
        intervalMilliseconds = $IntervalMilliseconds; requestTimeoutSeconds = $RequestTimeoutSeconds; maxDurationSeconds = $MaxDurationSeconds
        attempts = $attempts; samples = $samples; failures = $failures; maximumValidSampleGapMilliseconds = $maxGap
        invalidJsonlRowCount = 0; stopSignalObserved = $stopObserved; processExitCode = if ($stopObserved) { 0 } else { 1 }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}
if (-not $stopObserved) { exit 1 }
