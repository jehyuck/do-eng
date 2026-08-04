param(
    [string]$ManagementUrl,
    [string]$OutputPath,
    [string]$SummaryPath,
    [string]$StopSignalPath,
    [int]$IntervalMilliseconds = 1000,
    [int]$RequestTimeoutSeconds = 5,
    [int]$MaxDurationSeconds = 300,
    [scriptblock]$PollOperation
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Exp126Timestamp([object]$Value) {
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) { throw "Invalid timestamp: $Value" }
    $parsed.ToUniversalTime().ToString('o')
}

function Write-Exp126JsonLine([object]$Value, [string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::AppendAllText($Path, (($Value | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Exp126PoolPoll {
    param([string]$Url, [int]$TimeoutSeconds)
    $requestStarted = [DateTimeOffset]::UtcNow
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ($Url.TrimEnd('/') + '/actuator/doengdiagnosticpool') -TimeoutSec $TimeoutSeconds
        $completed = [DateTimeOffset]::UtcNow
        if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
            throw "HTTP_STATUS_$([int]$response.StatusCode)"
        }
        $payload = $response.Content | ConvertFrom-Json -ErrorAction Stop
        [ordered]@{
            ok = $true; timestamp = $requestStarted.ToString('o'); requestStartedAt = $requestStarted.ToString('o'); requestCompletedAt = $completed.ToString('o')
            elapsedMilliseconds = [math]::Round(($completed - $requestStarted).TotalMilliseconds, 3); httpStatus = [int]$response.StatusCode
            payloadParse = $true; metricCount = @($payload.metrics).Count; providerCount = @($payload.providers).Count
            poolMode = $payload.poolMode; providers = $payload.providers; metrics = $payload.metrics; failure = $null
        }
    } catch {
        $completed = [DateTimeOffset]::UtcNow
        $statusCode = $null
        try { if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) { $statusCode = [int]$_.Exception.Response.StatusCode } } catch { }
        [ordered]@{
            ok = $false; timestamp = $requestStarted.ToString('o'); requestStartedAt = $requestStarted.ToString('o'); requestCompletedAt = $completed.ToString('o')
            elapsedMilliseconds = [math]::Round(($completed - $requestStarted).TotalMilliseconds, 3); httpStatus = $statusCode; payloadParse = $false
            metricCount = $null; providerCount = $null; poolMode = $null; providers = @(); metrics = @()
            failure = [ordered]@{ exceptionType = $_.Exception.GetType().FullName; message = $_.Exception.Message }
        }
    }
}

function Invoke-Exp126CollectorLoop {
    param(
        [string]$ManagementUrl,
        [string]$OutputPath,
        [string]$SummaryPath,
        [string]$StopSignalPath,
        [int]$IntervalMilliseconds = 1000,
        [int]$RequestTimeoutSeconds = 5,
        [int]$MaxDurationSeconds = 300,
        [scriptblock]$PollOperation
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath),(Split-Path -Parent $SummaryPath) | Out-Null
    $started = [DateTimeOffset]::UtcNow; $lastSample = $null; $samples = 0; $failures = 0; $skipped = 0; $consecutive = 0; $maxConsecutive = 0; $maxGap = 0.0; $stopObserved = $false; $status = 'COLLECTOR_MAX_DURATION_EXCEEDED'; $attempt = 0
    $deadline = $started.AddSeconds($MaxDurationSeconds)
    try {
        while ([DateTimeOffset]::UtcNow -lt $deadline) {
            $attempt++
            $pollStarted = [DateTimeOffset]::UtcNow
            $sample = if ($null -ne $PollOperation) { & $PollOperation $attempt $pollStarted } else { Invoke-Exp126PoolPoll -Url $ManagementUrl -TimeoutSeconds $RequestTimeoutSeconds }
            $sample.attemptNumber = $attempt; $sample.processId = $PID; $sample.consecutiveFailures = if ($sample.ok) { 0 } else { $consecutive + 1 }
            if ($sample.ok) { $samples++; $consecutive = 0 } else { $failures++; $consecutive++; if ($consecutive -gt $maxConsecutive) { $maxConsecutive = $consecutive } }
            if ($null -ne $lastSample) { $gap = ([DateTimeOffset]::Parse($sample.timestamp) - [DateTimeOffset]::Parse($lastSample)).TotalMilliseconds; if ($gap -gt $maxGap) { $maxGap = [math]::Round($gap, 3) } }
            if ($sample.ok) { $lastSample = $sample.timestamp }
            Write-Exp126JsonLine $sample $OutputPath
            if (Test-Path -LiteralPath $StopSignalPath) { $stopObserved = $true; $status = 'COLLECTOR_STOPPED_BY_SIGNAL'; break }
            $next = $pollStarted.AddMilliseconds($IntervalMilliseconds); $sleepMs = [int][math]::Max(0, ($next - [DateTimeOffset]::UtcNow).TotalMilliseconds)
            if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
        }
    } finally {
        $completed = [DateTimeOffset]::UtcNow
        [ordered]@{ collectorStatus = $status; collectorProcessStartedAt = $started.ToString('o'); collectorProcessCompletedAt = $completed.ToString('o'); intervalMilliseconds = $IntervalMilliseconds; requestTimeoutSeconds = $RequestTimeoutSeconds; maxDurationSeconds = $MaxDurationSeconds; attempts = $attempt; samples = $samples; failures = $failures; skippedPolls = $skipped; maxConsecutiveFailures = $maxConsecutive; maximumValidSampleGapMilliseconds = $maxGap; invalidJsonlRowCount = 0; processExitCode = if($stopObserved){0}else{1}; stopSignalObserved = $stopObserved } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
    }
    if (-not $stopObserved) { return 1 }
    return 0
}

if ($PSBoundParameters.ContainsKey('ManagementUrl')) {
    exit (Invoke-Exp126CollectorLoop @PSBoundParameters)
}
