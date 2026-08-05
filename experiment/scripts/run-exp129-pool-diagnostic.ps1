param(
    [Parameter(Mandatory = $true)][ValidateSet('BASELINE','REMEDIATION')][string]$Condition,
    [Parameter(Mandatory = $true)][string]$RunId,
    [string]$RunDate = '20260805'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outRoot = Join-Path $root 'backend\experiments\results\experiment-1-29\diagnostic-pool-20260805'
$runIndex = ($RunId -split '-')[-1]
if ($runIndex -notmatch '^\d{3}$') { throw "INVALID_DIAGNOSTIC_RUN_ID: $RunId" }
$runRoot = Join-Path $outRoot ("{0}-{1}" -f $Condition.ToLowerInvariant(), $runIndex)
$timeseries = Join-Path $runRoot 'pool-timeseries.jsonl'
$summaryPath = Join-Path $outRoot ("diagnostic-summary-{0}.json" -f $runIndex)
$legacyRoot = Join-Path $root ("experiment\results\{0}" -f $RunId)
$project = 'doeng-exp129-pool-diagnostic'
$composeFiles = @(
    'backend\docker-compose.experiment.yaml',
    'backend\docker-compose.app-instance-t3-medium.yaml',
    'backend\docker-compose.mock-headroom-4cpu.yaml',
    'backend\docker-compose.http-pool-400.yaml',
    'backend\docker-compose.mock-memory-headroom.yaml',
    'backend\docker-compose.experiment-1-12-connection-attribution.yaml',
    'backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml'
)
$compose = @(); foreach ($file in $composeFiles) { $compose += @('-f', (Join-Path $root $file)) }
$policy = if ($Condition -eq 'BASELINE') {
    [ordered]@{ leasingStrategy = 'FIFO'; maxIdleTimeMs = 0; evictionIntervalMs = 0 }
} else {
    [ordered]@{ leasingStrategy = 'LIFO'; maxIdleTimeMs = 3000; evictionIntervalMs = 1000 }
}

function Write-JsonFile([string]$Path, [object]$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}

function Wait-Health([string]$Url, [int]$Attempts = 60) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            $health = Invoke-RestMethod -Uri $Url -TimeoutSec 5
            if ($health.status -eq 'UP') { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw "HEALTH_GATE_FAILED: $Url"
}

function Assert-MockIdle() {
    $metrics = Invoke-RestMethod -Uri 'http://127.0.0.1:9100/__metrics' -TimeoutSec 10
    foreach ($name in @('aiInFlight','storageInFlight')) {
        if ($null -ne $metrics.$name -and [int]$metrics.$name -ne 0) { throw "MOCK_NOT_IDLE: $name=$($metrics.$name)" }
    }
}

function Get-MetricRows([object]$Samples) {
    $rows = @()
    foreach ($sample in @($Samples)) {
        if ($sample.failure -ne $null) { continue }
        foreach ($metric in @($sample.metrics)) {
            $value = $metric.value
            if ($null -eq $value -and $metric.type -eq 'TIMER') { $value = $metric.meanMs }
            $parsed = 0.0
            if ($null -ne $value -and [double]::TryParse([string]$value, [ref]$parsed)) {
                $rows += [pscustomobject]@{ timestamp = $sample.timestamp; name = $metric.name; value = [double]$parsed; tags = $metric.tags }
            }
        }
    }
    return $rows
}

function Get-PoolSummary([object[]]$Rows) {
    $result = [ordered]@{}
    foreach ($metricName in @('active.connections','idle.connections','total.connections','pending.connections','max.pending.connections','max.connections')) {
        $key = $metricName -replace '\.connections','' -replace '\.','_'
        $values = @($Rows | Where-Object { $_.name -like "*.$metricName" } | ForEach-Object { [double]$_.value })
        if ($values.Count -eq 0) { $result[$key] = 'NOT_AVAILABLE'; continue }
        $result[$key] = [ordered]@{
            peak = ($values | Measure-Object -Maximum).Maximum
            minimum = ($values | Measure-Object -Minimum).Minimum
            last = $values[-1]
            sampleCount = $values.Count
        }
    }
    $pendingTimer = @($Rows | Where-Object { $_.name -like '*pending.connections.time' } | ForEach-Object { [double]$_.value })
    $result['pending_acquire_time_ms'] = if ($pendingTimer.Count -eq 0) { 'NOT_AVAILABLE' } else { [ordered]@{ peak = ($pendingTimer | Measure-Object -Maximum).Maximum; last = $pendingTimer[-1]; sampleCount = $pendingTimer.Count } }
    return $result
}

$oldEnvironment = @{}
$environment = [ordered]@{
    DOENG_EXP119_APP_IMAGE = 'doeng-flux-exp119-fresh-first-20260803:latest'
    DOENG_EXP119_MOCK_IMAGE = 'doeng-exp119-mock-frozen-20260803:latest'
    DOENG_EXTERNAL_LEASING_STRATEGY = $policy.leasingStrategy
    DOENG_EXTERNAL_MAX_IDLE_TIME_MS = [string]$policy.maxIdleTimeMs
    DOENG_EXTERNAL_EVICTION_INTERVAL_MS = [string]$policy.evictionIntervalMs
}
foreach ($entry in $environment.GetEnumerator()) { $oldEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process'); [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }

$collector = $null
$coreExit = $null
$collectorSummary = $null
$failure = $null
try {
    New-Item -ItemType Directory -Force -Path $outRoot, $runRoot | Out-Null
    if (Test-Path $timeseries) { throw "ARTIFACT_COLLISION: $timeseries" }
    if (Test-Path $legacyRoot) { throw "ARTIFACT_COLLISION: $legacyRoot" }

    docker compose -p $project @compose up -d --force-recreate --no-build mariadb experiment-mock flux-corrected
    if ($LASTEXITCODE) { throw 'FRESH_RECREATE_FAILED' }
    Wait-Health 'http://127.0.0.1:9001/actuator/health'
    Assert-MockIdle

    $composeList = $composeFiles -join ','
    $warmupRunId = "SMOKE-$RunDate-EXP129-$Condition-POOL-$runIndex"
    if (Test-Path (Join-Path $root "experiment\results\$warmupRunId")) { throw "WARMUP_ARTIFACT_COLLISION: $warmupRunId" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-isolated-vu-success-smoke.ps1') `
        -RunId $warmupRunId -Implementation ("Exp129-{0}-pool-warmup" -f $Condition) `
        -TargetUrl 'http://127.0.0.1:8001/game/face' -ServerService flux-corrected -ComposeProject $project -ComposeFiles $composeList `
        -ActiveMissions 20 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 -DurationMs 5000 -RequestTimeoutMs 10000 `
        -EnableObservability 0 -EnableContainerMonitor 0 -SkipApplicationSnapshot 1 -SkipMockMetrics 1 `
        -OutcomeMode controlled-admission -AccountingMode corrected -DrainObservationSeconds 10
    if ($LASTEXITCODE) { throw 'WARMUP_FAILED' }
    Assert-MockIdle

    $staging = Join-Path $runRoot 'collector-staging'
    $signal = Join-Path $staging 'STOP-COLLECTOR'
    $collectorSummaryPath = Join-Path $staging 'pool-metrics.jsonl.summary.json'
    $collector = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'collect-exp129-pool-until-stop.ps1'),
        '-ManagementUrl','http://127.0.0.1:9001','-OutputPath',(Join-Path $staging 'pool-metrics.jsonl'),
        '-SummaryPath',$collectorSummaryPath,'-StopSignalPath',$signal,'-IntervalMilliseconds','1000','-MaxDurationSeconds','300'
    )
    Start-Sleep -Seconds 2
    $validSamples = @()
    for ($attempt = 0; $attempt -lt 10 -and $validSamples.Count -lt 3; $attempt++) {
        Start-Sleep -Milliseconds 1000
        $validSamples = @(Get-Content (Join-Path $staging 'pool-metrics.jsonl') | ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { }
        } | Where-Object { $_.ok -eq $true -and @($_.metrics).Count -gt 0 })
    }
    if ($validSamples.Count -lt 3) { throw 'POOL_METRIC_SMOKE_EMPTY' }
    foreach ($metricName in @('active.connections','idle.connections','total.connections','pending.connections')) {
        $found = @($validSamples | ForEach-Object { $_.metrics } | Where-Object { $_.name -like "*.$metricName" -and $null -ne $_.value })
        if ($found.Count -eq 0) { throw "POOL_METRIC_MISSING: $metricName" }
    }

    $coreExit = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-isolated-vu-success-smoke.ps1') `
        -RunId $RunId -Implementation ("Exp129-{0}-pool-core" -f $Condition) -TargetUrl 'http://127.0.0.1:8001/game/face' `
        -ServerService flux-corrected -ComposeProject $project -ComposeFiles $composeList -ActiveMissions 200 -InitialActiveUsers 200 `
        -ActivationStepUsers 200 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 -DurationMs 105000 -RequestTimeoutMs 10000 `
        -EnableObservability 1 -EnableJfr 0 -EnableContainerMonitor 1 -SkipApplicationSnapshot 1 -SkipMockMetrics 1 `
        -OutcomeMode controlled-admission -AccountingMode corrected -DrainObservationSeconds 30
    if ($LASTEXITCODE) { throw 'CORE_LOAD_FAILED' }

    New-Item -ItemType File -Path ($signal + '.tmp') | Out-Null
    Move-Item -Force ($signal + '.tmp') $signal
    if (-not $collector.WaitForExit(15000)) { throw 'COLLECTOR_STOP_TIMEOUT' }
    $collectorSummary = Get-Content -Raw $collectorSummaryPath | ConvertFrom-Json
    if ($collectorSummary.collectorStatus -ne 'COLLECTOR_STOPPED_BY_SIGNAL' -or $collectorSummary.failures -ne 0) { throw 'COLLECTOR_SUMMARY_INVALID' }
    Copy-Item (Join-Path $staging 'pool-metrics.jsonl') $timeseries

    $samples = @(Get-Content -LiteralPath $timeseries | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { throw 'EMPTY_JSONL_ROW' }
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { throw 'INVALID_JSONL_ROW' }
    })
    $rows = @(Get-MetricRows $samples)
    $clientResults = Get-Content -Raw (Join-Path $legacyRoot 'client-results.json') | ConvertFrom-Json
    $drain = Get-Content -Raw (Join-Path $legacyRoot 'mock-drain-summary.json') | ConvertFrom-Json
    $runSummary = [ordered]@{
        runId = $RunId; condition = $Condition; runDate = $RunDate; policy = $policy
        workload = [ordered]@{ vu = 200; durationSeconds = 105; aiDelayMs = 2000; storageDelayMs = 100; requestTimeoutMs = 10000; frameIntervalSeconds = 1; appCpu = 2; appMemory = '3GiB'; httpPool = 400; pending = 800; dbPool = 10; admission = 320 }
        poolMetricEndpoint = '/actuator/doengdiagnosticpool'; poolMetricSampleCount = $samples.Count; poolMetricRows = $rows.Count
        pool = Get-PoolSummary $rows; collectorSummary = $collectorSummary
        client = [ordered]@{ totalRequests = $clientResults.summary.scheduledRequests; successfulRequests = $clientResults.summary.successfulRequests; failedRequests = $clientResults.summary.failedRequests; throughputRequestsPerSecond = $clientResults.summary.throughputRequestsPerSecond; timeoutCount = $clientResults.summary.outcomeCounts.CLIENT_TIMEOUT; p50 = $clientResults.summary.latencyMs.p50; p95 = $clientResults.summary.latencyMs.p95; p99 = $clientResults.summary.latencyMs.p99 }
        drain = $drain
        rawClientResults = (Join-Path $legacyRoot 'client-results.json'); rawDrainSummary = (Join-Path $legacyRoot 'mock-drain-summary.json')
        diagnosticStatus = 'COMPLETED'
    }
    $existing = @()
    if (Test-Path $summaryPath) { $existing = @((Get-Content -Raw $summaryPath | ConvertFrom-Json).runs) }
    Write-JsonFile $summaryPath ([ordered]@{ experiment = 'Exp129 follow-up pool diagnostic'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); runs = @($existing + $runSummary) })
} catch { $failure = $_ } finally {
    if ($null -ne $collector -and -not $collector.HasExited) { try { $collector.Kill() } catch { } }
    docker compose -p $project @compose down --remove-orphans | Out-Null
    foreach ($entry in $oldEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
if ($failure) { Write-Error $failure; exit 1 }
Write-Output ("DIAGNOSTIC_RUN_COMPLETED: {0}" -f $RunId)
