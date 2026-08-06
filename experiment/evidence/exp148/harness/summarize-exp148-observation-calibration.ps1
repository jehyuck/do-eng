param(
    [Parameter(Mandatory = $true)][string]$PoolTimelinePath,
    [Parameter(Mandatory = $true)][string]$ClientResultsPath,
    [Parameter(Mandatory = $true)][string]$ApplicationLogPath,
    [Parameter(Mandatory = $true)][string]$StageTimelinePath,
    [Parameter(Mandatory = $true)][string]$R2dbcTimelinePath,
    [Parameter(Mandatory = $true)][string]$ResourceSamplesPath,
    [Parameter(Mandatory = $true)][string]$ConsistencyPath,
    [Parameter(Mandatory = $true)][string]$OutputJsonPath,
    [Parameter(Mandatory = $true)][string]$OutputMarkdownPath
)

$ErrorActionPreference = "Stop"

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required JSON file not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Count-Pattern([string]$Text, [string]$Pattern) {
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    return ([regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
}

function To-EpochMs($Value) {
    if ($null -eq $Value) { return $null }
    return [DateTimeOffset]::Parse([string]$Value).ToUnixTimeMilliseconds()
}

function Metric-Points($Rows, [string]$MetricName, [string]$Provider) {
    $points = @()
    foreach ($row in $Rows) {
        if ($row.failure) { continue }
        foreach ($metric in @($row.metrics)) {
            if ([string]$metric.name -ne $MetricName) { continue }
            if ([string]$metric.tags.name -ne $Provider) { continue }
            if ($null -eq $metric.value) { continue }
            $points += [pscustomobject]@{
                timestamp = [string]$row.timestamp
                epochMs = To-EpochMs $row.timestamp
                value = [double]$metric.value
            }
        }
    }
    return @($points | Sort-Object epochMs)
}

function Peak($Points) {
    if (@($Points).Count -eq 0) { return $null }
    return [double](($Points | Measure-Object -Property value -Maximum).Maximum)
}

function First-AtOrAbove($Points, [double]$Threshold) {
    $point = @($Points | Where-Object { $_.value -ge $Threshold } | Select-Object -First 1)
    if ($point.Count -eq 0) { return $null }
    return $point[0]
}

$rows = @()
if (Test-Path -LiteralPath $PoolTimelinePath) {
    $rows = @(Get-Content -LiteralPath $PoolTimelinePath -Encoding UTF8 | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_)) { $_ | ConvertFrom-Json }
    })
}
if ($rows.Count -eq 0) {
    throw "Pool timeline is empty: $PoolTimelinePath"
}

$client = Read-JsonFile $ClientResultsPath
$summary = $client.summary
$applicationLog = if (Test-Path -LiteralPath $ApplicationLogPath) {
    Get-Content -LiteralPath $ApplicationLogPath -Raw -Encoding UTF8
} else { "" }

$provider = "doeng-external"
$prefix = "reactor.netty.connection.provider."
$active = Metric-Points $rows ($prefix + "active.connections") $provider
$pending = Metric-Points $rows ($prefix + "pending.connections") $provider
$idle = Metric-Points $rows ($prefix + "idle.connections") $provider
$total = Metric-Points $rows ($prefix + "total.connections") $provider
$maxConnectionsSeries = Metric-Points $rows ($prefix + "max.connections") $provider
$maxPendingSeries = Metric-Points $rows ($prefix + "max.pending.connections") $provider

$peakActive = Peak $active
$peakPending = Peak $pending
$peakTotal = Peak $total
$peakIdle = Peak $idle
$configuredMaxConnections = Peak $maxConnectionsSeries
$configuredMaxPending = Peak $maxPendingSeries
$firstActiveLimit = First-AtOrAbove $active 499.5
$firstPending = First-AtOrAbove $pending 1
$firstPendingLimit = First-AtOrAbove $pending 800

$stageRows = @()
if (Test-Path -LiteralPath $StageTimelinePath) {
    $stageRows = @(Get-Content -LiteralPath $StageTimelinePath -Encoding UTF8 | Where-Object { $_ } | ForEach-Object {
        $row = $_ | ConvertFrom-Json
        if ($null -ne $row.PSObject.Properties['stages']) { $row }
    })
}
$stageSummary = [ordered]@{}
foreach ($row in $stageRows | Select-Object -Last 1) {
    foreach ($stage in @($row.stages)) {
        $stageSummary[[string]$stage.stage] = [ordered]@{
            started = $stage.started
            succeeded = $stage.succeeded
            failed = $stage.failed
            cancelled = $stage.cancelled
            maxInFlight = $stage.maxInFlight
            p50 = $stage.durationMsP50
            p95 = $stage.durationMsP95
            p99 = $stage.durationMsP99
            max = $stage.durationMsMax
        }
    }
}
$r2dbcRows = @()
if (Test-Path -LiteralPath $R2dbcTimelinePath) {
    $r2dbcRows = @(Get-Content -LiteralPath $R2dbcTimelinePath -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}
$r2dbcAvailable = @($r2dbcRows | Where-Object { $_.metricsAvailable -eq $true }).Count -gt 0
$resourceRows = @()
if (Test-Path -LiteralPath $ResourceSamplesPath) { $resourceRows = @(Import-Csv -LiteralPath $ResourceSamplesPath) }

$exceptionCounts = [ordered]@{
    deadlockFound = Count-Pattern $applicationLog "Deadlock found when trying to get lock"
    concurrencyFailure = Count-Pattern $applicationLog "ConcurrencyFailureException"
    poolAcquirePendingLimit = Count-Pattern $applicationLog "PoolAcquirePendingLimitException"
    poolAcquireTimeout = Count-Pattern $applicationLog "PoolAcquireTimeoutException|pending acquire.*timeout|Pool#acquire.*timeout"
    webClientTimeout = Count-Pattern $applicationLog "WebClient.*timeout|response timeout|ReadTimeoutException"
    prematureClose = Count-Pattern $applicationLog "PrematureCloseException"
    r2dbcConcurrency = Count-Pattern $applicationLog "R2DBC.*concurr|Concurrent.*R2DBC|Connection.*concurrent"
    r2dbcRollback = Count-Pattern $applicationLog "R2DBC.*rollback|rollback.*R2DBC|RollbackException"
    outOfMemory = Count-Pattern $applicationLog "OutOfMemoryError"
}

$consistency = [ordered]@{ status = "NOT_AVAILABLE"; missionCompletion = $null; progress = $null; picture = $null; orphanPicture = $null; duplicateMissionRunId = $null; atomicity = "NOT_EXECUTED" }
if (Test-Path -LiteralPath $ConsistencyPath) {
    $line = (Get-Content -LiteralPath $ConsistencyPath -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch '^mission_completion_count' } | Select-Object -Last 1)
    if ($line) {
        $parts = ([string]$line -split "`t")
        if ($parts.Count -ge 5) {
            $consistency = [ordered]@{ status = "PASS"; missionCompletion = [int64]$parts[0]; progress = [int64]$parts[1]; picture = [int64]$parts[2]; orphanPicture = [int64]$parts[3]; duplicateMissionRunId = [int64]$parts[4]; atomicity = "NOT_EXECUTED" }
        }
    }
}

$outcomes = $summary.outcomeCounts
$attempts = [int]$summary.completedRequests
$http200 = [int]$outcomes.HTTP_200_ACCEPTED
$http500 = [int]$outcomes.HTTP_500_UNCONTROLLED
$clientTimeout = [int]$outcomes.CLIENT_TIMEOUT
$connectionError = [int]$outcomes.CONNECTION_ERROR
$successRate = if ($attempts -gt 0) { [double]$http200 / $attempts } else { $null }

$contractValid = ($configuredMaxConnections -eq 500 -and $configuredMaxPending -eq 800)
$meterCoverageValid = (@($active).Count -gt 0 -and @($pending).Count -gt 0 -and $null -ne $configuredMaxConnections -and $null -ne $configuredMaxPending)

$dbStage = if ($stageSummary.Contains("DB")) { $stageSummary["DB"] } else { $null }
$progressUpdate = if ($stageSummary.Contains("DB_PROGRESS_UPDATE")) { $stageSummary["DB_PROGRESS_UPDATE"] } else { $null }
$pictureInsert = if ($stageSummary.Contains("DB_PICTURE_INSERT")) { $stageSummary["DB_PICTURE_INSERT"] } else { $null }
$classification = "FIX_EFFECT_NOT_ISOLATED"
if ($contractValid -and $meterCoverageValid -and $null -ne $progressUpdate -and $null -ne $consistency) {
    if ([int]$progressUpdate.failed -eq 0 -and $exceptionCounts.deadlockFound -eq 0 -and $exceptionCounts.r2dbcRollback -eq 0 -and [int]$pictureInsert.failed -eq 0 -and $consistency.status -eq "PASS" -and $consistency.orphanPicture -eq 0 -and $consistency.duplicateMissionRunId -eq 0 -and $consistency.atomicity -eq "PASS") {
        $classification = "DB_DEADLOCK_FIX_VALIDATED"
    } elseif ([int]$progressUpdate.failed -lt 215 -or $exceptionCounts.deadlockFound -lt 860) {
        $classification = "DB_DEADLOCK_REDUCED_NOT_ELIMINATED"
    } else {
        $classification = "DB_FIX_NO_EFFECT"
    }
}

$result = [ordered]@{
    status = "COMPLETED"
    provider = $provider
    poolContract = [ordered]@{
        expectedMaxConnections = 500
        expectedMaxPendingConnections = 800
        observedMaxConnections = $configuredMaxConnections
        observedMaxPendingConnections = $configuredMaxPending
        valid = $contractValid
    }
    timeline = [ordered]@{
        rawRows = $rows.Count
        failedRows = @($rows | Where-Object { $_.failure }).Count
        activeSampleCount = @($active).Count
        pendingSampleCount = @($pending).Count
        peakActiveConnections = $peakActive
        peakPendingConnections = $peakPending
        peakTotalConnections = $peakTotal
        peakIdleConnections = $peakIdle
        firstActiveLimit = $firstActiveLimit
        firstPending = $firstPending
        firstPendingAtOrAboveConfiguredLimit = $firstPendingLimit
    }
    client = [ordered]@{
        attempts = $attempts
        http200 = $http200
        successRate = $successRate
        http500 = $http500
        clientTimeout = $clientTimeout
        connectionError = $connectionError
        p50Ms = $summary.latencyMs.p50
        p95Ms = $summary.latencyMs.p95
        p99Ms = $summary.latencyMs.p99
        maxInFlight = $summary.maxInFlight
        accountingValid = $summary.accounting.valid
        drainCompleted = $summary.mockDrain.drainCompleted
        remainingBacklog = $summary.mockDrain.remainingBacklog
    }
    stages = $stageSummary
    consistency = $consistency
    baselineA0B0 = [ordered]@{ attempts = 5950; http200 = 1100; http500 = 2326; clientTimeout = 2524; successfulRps = 36.67; dbProgressUpdateFailed = 215; deadlockOccurrences = 860; rollbackOccurrences = 430; r2dbcPeakPending = 100; webClientPeakPending = 2039; webClientPendingLimitOccurrences = 4400; applicationCpuPercent = 209.18; applicationMemoryGiB = 2.295 }
    r2dbcPool = [ordered]@{
        available = $r2dbcAvailable
        sampleCount = $r2dbcRows.Count
        status = if ($r2dbcAvailable) { "AVAILABLE" } else { "R2DBC_POOL_METRICS_NOT_AVAILABLE" }
    }
    resources = [ordered]@{
        sampleCount = $resourceRows.Count
        application = @($resourceRows | Where-Object { $_.name -match 'flux-corrected' })
        mock = @($resourceRows | Where-Object { $_.name -match 'experiment-mock' })
        database = @($resourceRows | Where-Object { $_.name -match 'mariadb' })
    }
    exceptions = $exceptionCounts
    classification = $classification
    interpretationGuard = @(
        "pending.connections gauge may exceed max.pending.connections in Reactor Netty 1.0.28; do not infer queue internals from the gauge alone",
        "WEBCLIENT_POOL_DOMINANT requires active-at-limit, positive pending, and direct pending-limit failures",
        "This result does not prove that pool pressure is the only runtime bottleneck"
    )
}

$parent = Split-Path -Parent $OutputJsonPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputJsonPath -Encoding UTF8

$successRateText = if ($null -eq $successRate) { "NOT_AVAILABLE" } else { "{0:P2}" -f $successRate }
$markdown = @"
# Exp147 DB Write-Order Factor A Summary

## Runtime contract

- Provider: `$provider`
- max.connections: `$configuredMaxConnections`
- max.pending.connections: `$configuredMaxPending`
- Contract valid: `$contractValid`

## Pool timeline

- Samples: $($rows.Count)
- Failed samples: $(@($rows | Where-Object { $_.failure }).Count)
- Peak active: `$peakActive`
- Peak pending: `$peakPending`
- Peak total: `$peakTotal`
- First active >= 500: `$($firstActiveLimit.timestamp)`
- First pending > 0: `$($firstPending.timestamp)`
- First pending >= 800: `$($firstPendingLimit.timestamp)`

## Client outcome

- Attempts: `$attempts`
- HTTP 200: `$http200`
- Success rate: `$successRateText`
- HTTP 500: `$http500`
- Client timeout: `$clientTimeout`
- Connection error: `$connectionError`
- p95: `$($summary.latencyMs.p95) ms`
- Max in-flight: `$($summary.maxInFlight)`
- Accounting valid: `$($summary.accounting.valid)`
- Mock drain completed: `$($summary.mockDrain.drainCompleted)`

## Stage summary

$(($stageSummary | ConvertTo-Json -Depth 8))

## R2DBC pool

- Status: `$(if ($r2dbcAvailable) { "AVAILABLE" } else { "R2DBC_POOL_METRICS_NOT_AVAILABLE" })`
- Samples: `$($r2dbcRows.Count)`

## Exception counts

- PoolAcquirePendingLimitException: `$($exceptionCounts.poolAcquirePendingLimit)`
- Pool acquire timeout: `$($exceptionCounts.poolAcquireTimeout)`
- WebClient timeout: `$($exceptionCounts.webClientTimeout)`
- PrematureCloseException: `$($exceptionCounts.prematureClose)`
- R2DBC concurrency: `$($exceptionCounts.r2dbcConcurrency)`
- R2DBC rollback: `$($exceptionCounts.r2dbcRollback)`
- OOM: `$($exceptionCounts.outOfMemory)`

## Classification

`$classification`

## Consistency

$(($consistency | ConvertTo-Json -Depth 5))

## Factor A

This run changes only the transaction write order from picture-insert-then-progress-update to progress-update-then-picture-insert. The WebClient/pool and workload contract remains the Exp146 A0B0 contract.

## Guard

This attribution is evidence-weighted and does not prove that one signal is the only runtime bottleneck.
"@
$markdown | Set-Content -LiteralPath $OutputMarkdownPath -Encoding UTF8

Write-Output $classification
