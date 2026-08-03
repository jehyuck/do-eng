function ConvertTo-Exp121UtcIso {
    param([Parameter(Mandatory)][object]$Value)
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) {
        throw "Unparseable collector timestamp: $Value"
    }
    $parsed.ToUniversalTime()
}

function Get-Exp121CollectorLines {
    param([Parameter(Mandatory)][string]$JsonlPath)
    if (-not (Test-Path -LiteralPath $JsonlPath)) { return @() }
    @((Get-Content -LiteralPath $JsonlPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
}

function Wait-Exp121CollectorReady {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$JsonlPath,
        [int]$TimeoutSeconds = 10
    )
    $deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while ((Get-Date).ToUniversalTime() -lt $deadline) {
        if ($Process.HasExited) { throw 'COLLECTOR_NOT_READY: collector process exited before readiness' }
        $lines = Get-Exp121CollectorLines $JsonlPath
        if ($lines.Count -gt 0) {
            try { $sample = ($lines[0] -replace '^\uFEFF','') | ConvertFrom-Json -ErrorAction Stop }
            catch { Start-Sleep -Milliseconds 100; continue }
            try { $sampleAt = ConvertTo-Exp121UtcIso $sample.timestamp }
            catch { throw 'COLLECTOR_NOT_READY: first sample timestamp is invalid' }
            if ($null -ne $sample.failure -and -not [string]::IsNullOrWhiteSpace([string]$sample.failure)) {
                throw "COLLECTOR_NOT_READY: first sample reported failure: $($sample.failure)"
            }
            return [ordered]@{
                collectorReadyAt = (Get-Date).ToUniversalTime().ToString('o')
                collectorFirstValidSampleAt = $sampleAt.ToString('o')
            }
        }
        Start-Sleep -Milliseconds 100
    }
    throw "COLLECTOR_NOT_READY: no valid first sample within $TimeoutSeconds seconds"
}

function New-Exp121CollectorCoverage {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$JsonlPath,
        [Parameter(Mandatory)][string]$SummaryPath,
        [Parameter(Mandatory)][int]$CollectorDurationSeconds,
        [Parameter(Mandatory)][int]$IntervalMilliseconds,
        [Parameter(Mandatory)][string]$CollectorProcessStartedAt,
        [Parameter(Mandatory)][string]$CoreInvocationStartedAt,
        [Parameter(Mandatory)][string]$CoreInvocationCompletedAt,
        [Parameter(Mandatory)][string]$CollectorProcessCompletedAt
    )
    $invalid = 0; $valid = @(); $timestamps = @(); $failureType = $null
    foreach ($line in (Get-Exp121CollectorLines $JsonlPath)) {
        try { $sample = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { $invalid++; $failureType = 'COLLECTOR_INVALID_JSONL'; continue }
        try { $at = ConvertTo-Exp121UtcIso $sample.timestamp }
        catch { $invalid++; if ($null -eq $failureType) { $failureType = 'COLLECTOR_TIMESTAMP_INVALID' }; continue }
        $timestamps += $at
        if ($null -eq $sample.failure -or [string]::IsNullOrWhiteSpace([string]$sample.failure)) { $valid += $at }
    }
    $summaryFailures = $null
    try { $summaryFailures = [int](Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json -ErrorAction Stop).failures }
    catch { if ($null -eq $failureType) { $failureType = 'COLLECTOR_REPORTED_FAILURE' } }
    $nonDecreasing = $true
    for ($i = 1; $i -lt $timestamps.Count; $i++) { if ($timestamps[$i] -lt $timestamps[$i - 1]) { $nonDecreasing = $false; break } }
    $start = ConvertTo-Exp121UtcIso $CoreInvocationStartedAt; $end = ConvertTo-Exp121UtcIso $CoreInvocationCompletedAt
    $first = if ($valid.Count) { $valid[0] } else { $null }; $last = if ($valid.Count) { $valid[$valid.Count - 1] } else { $null }
    $coversStart = ($null -ne $first -and $first -le $start); $coversEnd = ($null -ne $last -and $last -ge $end)
    if ($invalid -gt 0 -and $failureType -ne 'COLLECTOR_TIMESTAMP_INVALID') { $failureType = 'COLLECTOR_INVALID_JSONL' }
    elseif (-not $nonDecreasing -and $null -eq $failureType) { $failureType = 'COLLECTOR_TIMESTAMP_INVALID' }
    elseif ($summaryFailures -ne 0 -and $null -eq $failureType) { $failureType = 'COLLECTOR_REPORTED_FAILURE' }
    elseif ($valid.Count -le 1 -and $null -eq $failureType) { $failureType = 'COLLECTOR_NOT_READY' }
    elseif (-not $coversStart -and $null -eq $failureType) { $failureType = 'COLLECTOR_STARTED_LATE' }
    elseif (-not $coversEnd -and $null -eq $failureType) { $failureType = 'COLLECTOR_ENDED_EARLY' }
    [ordered]@{
        runId = $RunId; collectorDurationSeconds = $CollectorDurationSeconds; intervalMilliseconds = $IntervalMilliseconds
        collectorProcessStartedAt = (ConvertTo-Exp121UtcIso $CollectorProcessStartedAt).ToString('o')
        collectorFirstValidSampleAt = if ($first) { $first.ToString('o') } else { $null }
        coreInvocationStartedAt = $start.ToString('o'); coreInvocationCompletedAt = $end.ToString('o')
        collectorProcessCompletedAt = (ConvertTo-Exp121UtcIso $CollectorProcessCompletedAt).ToString('o')
        collectorLastValidSampleAt = if ($last) { $last.ToString('o') } else { $null }
        validSampleCount = $valid.Count; invalidSampleCount = $invalid; collectorFailures = $summaryFailures
        coversCoreStart = $coversStart; coversCoreEnd = $coversEnd; timestampsNonDecreasing = $nonDecreasing
        coverageStatus = if ($null -eq $failureType) { 'COLLECTOR_COVERAGE_PASSED' } else { 'COLLECTOR_COVERAGE_FAILED' }
        failureType = $failureType
    }
}

function Assert-Exp121CollectorCoverage {
    param([Parameter(Mandatory)][string]$CoveragePath)
    $coverage = Get-Content -LiteralPath $CoveragePath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($coverage.coverageStatus -ne 'COLLECTOR_COVERAGE_PASSED') { throw "Collector coverage failed: $($coverage.failureType)" }
    if (-not $coverage.coversCoreStart -or -not $coverage.coversCoreEnd -or -not $coverage.timestampsNonDecreasing) { throw 'Collector coverage flags failed' }
    if ($coverage.invalidSampleCount -ne 0 -or $coverage.collectorFailures -ne 0 -or $coverage.validSampleCount -le 1) { throw 'Collector coverage counts failed' }
}

