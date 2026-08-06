param(
    [Parameter(Mandatory = $true)][string]$PoolTimelinePath,
    [Parameter(Mandatory = $true)][string]$ClientResultsPath,
    [Parameter(Mandatory = $true)][string]$ApplicationLogPath,
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

$exceptionCounts = [ordered]@{
    poolAcquirePendingLimit = Count-Pattern $applicationLog "PoolAcquirePendingLimitException"
    poolAcquireTimeout = Count-Pattern $applicationLog "PoolAcquireTimeoutException|pending acquire.*timeout|Pool#acquire.*timeout"
    webClientTimeout = Count-Pattern $applicationLog "WebClient.*timeout|response timeout|ReadTimeoutException"
    prematureClose = Count-Pattern $applicationLog "PrematureCloseException"
    r2dbcConcurrency = Count-Pattern $applicationLog "R2DBC.*concurr|Concurrent.*R2DBC|Connection.*concurrent"
    r2dbcRollback = Count-Pattern $applicationLog "R2DBC.*rollback|rollback.*R2DBC|RollbackException"
    outOfMemory = Count-Pattern $applicationLog "OutOfMemoryError"
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

$classification = "INSUFFICIENT_POOL_EVIDENCE"
if (-not $contractValid) {
    $classification = "INVALID_POOL_CONTRACT"
} elseif ($meterCoverageValid -and $peakActive -ge 499.5 -and $peakPending -gt 0 -and $exceptionCounts.poolAcquirePendingLimit -gt 0) {
    $classification = "POOL500_RUNTIME_SATURATION_PROVEN"
} elseif ($meterCoverageValid -and $peakActive -lt 499.5) {
    $classification = "POOL500_RUNTIME_NOT_SATURATED"
} else {
    $classification = "INSUFFICIENT_POOL500_EVIDENCE"
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
    exceptions = $exceptionCounts
    classification = $classification
    interpretationGuard = @(
        "pending.connections gauge may exceed max.pending.connections in Reactor Netty 1.0.28; do not infer queue internals from the gauge alone",
        "POOL500_RUNTIME_SATURATION_PROVEN requires active-at-limit, positive pending, and PoolAcquirePendingLimitException together",
        "This result does not prove that pool pressure is the only runtime bottleneck"
    )
}

$parent = Split-Path -Parent $OutputJsonPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputJsonPath -Encoding UTF8

$successRateText = if ($null -eq $successRate) { "NOT_AVAILABLE" } else { "{0:P2}" -f $successRate }
$markdown = @"
# Exp142 Pool500 Probe Summary

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

## Guard

This classification does not prove that pool pressure is the only runtime bottleneck. The pending gauge is interpreted together with active-at-limit and the direct pending-limit exception.
"@
$markdown | Set-Content -LiteralPath $OutputMarkdownPath -Encoding UTF8

Write-Output $classification
