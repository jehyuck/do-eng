param(
    [Parameter(Mandatory = $true)][string]$ExpectedCommit,
    [ValidateSet("PREFLIGHT", "EXECUTE")][string]$ExecutionMode = "PREFLIGHT",
    [ValidateSet("P", "D")][string]$ObservationMode = "D"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$baseCompose = Join-Path $repo "backend\docker-compose.experiment.yaml"
$overrideSource = Join-Path $repo "experiment\compose\experiment-1-46-broad-attribution.override.yml"
$overrideCompose = Join-Path $env:TEMP ("doeng-exp148-" + $ObservationMode.ToLowerInvariant() + ".override.yml")
$missionLoad = Join-Path $repo "experiment\load\mission-load.js"
$poolCollector = Join-Path $repo "experiment\scripts\collect-diagnostic-pool.ps1"
$summarizer = Join-Path $repo "experiment\scripts\summarize-exp148-observation-calibration.ps1"
$fixture = Join-Path $repo "image\arc.jpg"
$resultRoot = Join-Path $repo ("backend\experiments\results\experiment-1-48\a1b0-observation-calibration\" + ($(if ($ObservationMode -eq "P") { "performance-001" } else { "diagnostic-001" })))
$planDir = Join-Path $resultRoot "plan"
$warmupDir = Join-Path $resultRoot ("WARMUP\" + ($(if ($ObservationMode -eq "P") { "WARMUP-EXP148-A1B0-P-001" } else { "WARMUP-EXP148-A1B0-D-001" })))
$highDir = Join-Path $resultRoot ("HIGH\" + ($(if ($ObservationMode -eq "P") { "RUN-EXP148-A1B0-PERFORMANCE-001" } else { "RUN-EXP148-A1B0-DIAGNOSTIC-001" })))
$analysisDir = Join-Path $resultRoot "analysis"
$runtimeCompose = $null
$runtimeDbDumpDir = $null
$runtimeSeedImage = $null
$project = if ($ObservationMode -eq "P") { "doeng-exp148-p" } else { "doeng-exp148-d" }
$applicationUrl = "http://127.0.0.1:8001"
$managementUrl = "http://127.0.0.1:9001"
$mockUrl = "http://127.0.0.1:9100"
$stageExpected = if ($ObservationMode -eq "P") { "false" } else { "true" }

if (-not (Test-Path -LiteralPath $overrideSource)) { throw "Frozen Exp146 override not found" }
$overrideText = Get-Content -LiteralPath $overrideSource -Raw -Encoding UTF8
$overrideText = [regex]::Replace($overrideText, 'DOENG_STAGE_OBSERVATION_ENABLED:\s*"?(true|false)"?', "DOENG_STAGE_OBSERVATION_ENABLED: `"$stageExpected`"")
Set-Content -LiteralPath $overrideCompose -Value $overrideText -Encoding UTF8

function Save-Json([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Value | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Compose([string[]]$Arguments) {
    & docker compose -p $project -f $baseCompose -f $overrideCompose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed ($LASTEXITCODE): $($Arguments -join ' ')"
    }
}

function Prepare-RuntimeCompose {
    $sourceDump = Get-ChildItem -LiteralPath (Join-Path $repo "exec") -Recurse -File -Filter "doEng.sql" |
        Select-Object -First 1 -ExpandProperty FullName
    if ([string]::IsNullOrWhiteSpace($sourceDump) -or -not (Test-Path -LiteralPath $sourceDump)) {
        throw "DB dump not found below exec directory"
    }

    $script:runtimeDbDumpDir = Join-Path $env:TEMP ("doeng-exp148-db-seed-" + $ObservationMode.ToLowerInvariant())
    New-Item -ItemType Directory -Force -Path $script:runtimeDbDumpDir | Out-Null
    $runtimeDump = Join-Path $script:runtimeDbDumpDir "doEng.sql"
    Copy-Item -LiteralPath $sourceDump -Destination $runtimeDump -Force
    Copy-Item -LiteralPath (Join-Path $repo "backend\experiment-db\02-mission-completion.sql") `
        -Destination (Join-Path $script:runtimeDbDumpDir "02-mission-completion.sql") -Force
    Set-Content -LiteralPath (Join-Path $script:runtimeDbDumpDir "Dockerfile") -Value @(
        "FROM mariadb:10.11"
        "COPY doEng.sql /docker-entrypoint-initdb.d/01-doeng.sql"
        "COPY 02-mission-completion.sql /docker-entrypoint-initdb.d/02-mission-completion.sql"
    ) -Encoding ASCII
    $script:runtimeSeedImage = "doeng-exp148-mariadb-seeded-$($ObservationMode.ToLowerInvariant()):latest"
    & docker build --tag $script:runtimeSeedImage $script:runtimeDbDumpDir
    if ($LASTEXITCODE -ne 0) { throw "MariaDB seed image build failed ($LASTEXITCODE)" }

    $script:runtimeCompose = Join-Path $repo ("backend\docker-compose.experiment.exp148-runtime-$($ObservationMode.ToLowerInvariant()).yaml")
    $yaml = Get-Content -LiteralPath $baseCompose -Raw -Encoding UTF8
    $mount = ('- "{0}:/docker-entrypoint-initdb.d/01-doeng.sql:ro"' -f ($runtimeDump -replace '\\', '/'))
    $pattern = '(?m)^\s*-\s*"\.\./exec/3 \(DB .*?\)/doEng\.sql:/docker-entrypoint-initdb\.d/01-doeng\.sql:ro"\s*$'
    $updated = [regex]::Replace($yaml, $pattern, "      $mount")
    if ($updated -eq $yaml) { throw "Could not normalize DB dump mount in runtime compose" }
    $updated = $updated.Replace('image: mariadb:10.11', "image: $script:runtimeSeedImage")
    $updated = [regex]::Replace($updated, '(?m)^\s*-\s*"\.?/?\.?/experiment/capture:/app"\s*$\r?\n?', '')
    $updated = [regex]::Replace($updated, '(?m)^\s*-\s*"[^\r\n]*?/docker-entrypoint-initdb\.d/01-doeng\.sql:ro"\s*$\r?\n?', '')
    $updated = [regex]::Replace($updated, '(?m)^\s*-\s*"[^\r\n]*?/docker-entrypoint-initdb\.d/02-mission-completion\.sql:ro"\s*$\r?\n?', '')
    Set-Content -LiteralPath $script:runtimeCompose -Value $updated -Encoding UTF8
    $script:baseCompose = $script:runtimeCompose
}

function Wait-Health {
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri "$managementUrl/actuator/health" -TimeoutSec 2
            if ($health.status -eq "UP") { return $health }
        } catch {
            # Poll until the fixed deadline.
        }
        Start-Sleep -Seconds 1
    }
    throw "Management health did not become UP within 60 seconds"
}

function Resolve-Node {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCommand) { return $nodeCommand.Source }
    $fallback = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw "Node executable not found"
}

function Wait-NativeProcess([System.Diagnostics.Process]$Process, [int]$WatchdogSeconds) {
    $deadline = (Get-Date).AddSeconds($WatchdogSeconds)
    while (-not $Process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $Process.Refresh()
    }
    if (-not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force
        $Process.WaitForExit()
        throw "Node watchdog exceeded $WatchdogSeconds seconds"
    }
    $Process.WaitForExit()
    return [int]$Process.ExitCode
}

function Invoke-NodeLoad(
    [string]$RunId,
    [int]$ActiveMissions,
    [int]$DurationMs,
    [int]$DrainSeconds,
    [int]$WatchdogSeconds,
    [string]$OutputDir
) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $node = Resolve-Node
    $resultPath = Join-Path $OutputDir "client-results.json"
    $progressPath = Join-Path $OutputDir "client-progress.jsonl"
    $loadStopPath = Join-Path $OutputDir "load-stop-mock-metrics.json"
    $drainPath = Join-Path $OutputDir "mock-drain.jsonl"
    $drainSummaryPath = Join-Path $OutputDir "mock-drain-summary.json"
    $stdoutPath = Join-Path $OutputDir "node.stdout.log"
    $stderrPath = Join-Path $OutputDir "node.stderr.log"

    $env:TARGET_URL = "$applicationUrl/game/face"
    $env:ACTIVE_MISSIONS = [string]$ActiveMissions
    $env:INTERVAL_MS = "1000"
    $env:DURATION_MS = [string]$DurationMs
    $env:REQUEST_TIMEOUT_MS = "10000"
    $env:SCENE_ID = "2"
    $env:ANSWER = "happy"
    $env:AUTH_TOKEN = "Bearer experiment-member-15"
    $env:FIXTURE_PATH = $fixture
    $env:EXPERIMENT_RUN_ID = $RunId
    $env:IMPLEMENTATION = "webflux"
    $env:ARRIVAL_MODE = "staggered"
    $env:LOAD_SCENARIO = "single-success"
    $env:ACCOUNTING_MODE = "corrected"
    $env:STOP_USER_ON_TRUE = "false"
    $env:RESULT_PATH = $resultPath
    $env:PROGRESS_PATH = $progressPath
    $env:DRAIN_OBSERVATION_SECONDS = [string]$DrainSeconds
    $env:MOCK_METRICS_URL = "$mockUrl/__metrics"
    $env:LOAD_STOP_MOCK_METRICS_PATH = $loadStopPath
    $env:MOCK_DRAIN_PATH = $drainPath
    $env:MOCK_DRAIN_SUMMARY_PATH = $drainSummaryPath

    Save-Json (Join-Path $OutputDir "node-contract.json") ([ordered]@{
        runId = $RunId
        activeMissions = $ActiveMissions
        intervalMs = 1000
        durationMs = $DurationMs
        requestTimeoutMs = 10000
        drainObservationSeconds = $DrainSeconds
        arrivalMode = "staggered"
        accountingMode = "corrected"
        internalWarmupMs = 0
        note = "mission-load.js has no WARMUP_MS binding; warm-up is an explicit separate Node run"
    })

    $process = Start-Process -FilePath $node -ArgumentList $missionLoad -WorkingDirectory $repo `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $exitCode = Wait-NativeProcess -Process $process -WatchdogSeconds $WatchdogSeconds

    $flushDeadline = (Get-Date).AddSeconds(5)
    while (-not (Test-Path -LiteralPath $resultPath) -and (Get-Date) -lt $flushDeadline) {
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "CLIENT_RESULTS_NOT_CREATED: $RunId"
    }
    if ($exitCode -ne 0) {
        throw "Node runner exited with code $exitCode for $RunId"
    }

    $client = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Save-Json (Join-Path $OutputDir "node-execution.json") ([ordered]@{
        runId = $RunId
        exitCode = $exitCode
        completedRequests = $client.summary.completedRequests
        successfulRequests = $client.summary.successfulRequests
        accountingValid = $client.summary.accounting.valid
        drainCompleted = $client.summary.mockDrain.drainCompleted
    })
    return $client
}

function Get-ContainerId([string]$Service) {
    $id = (& docker compose -p $project -f $baseCompose -f $overrideCompose ps -q $Service).Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Container id not found for $Service" }
    return $id
}

function Inspect-Container([string]$ContainerId, [string]$OutputPath) {
    $raw = & docker inspect $ContainerId
    if ($LASTEXITCODE -ne 0) { throw "docker inspect failed: $ContainerId" }
    $raw | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    return ($raw | ConvertFrom-Json)[0]
}

function Env-Map($Inspect) {
    $map = @{}
    foreach ($entry in @($Inspect.Config.Env)) {
        $parts = [string]$entry -split "=", 2
        $map[$parts[0]] = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    }
    return $map
}

function Metric-Value($Snapshot, [string]$Name, [string]$Provider) {
    $match = @($Snapshot.metrics | Where-Object {
        [string]$_.name -eq $Name -and [string]$_.tags.name -eq $Provider
    } | Select-Object -First 1)
    if ($match.Count -eq 0 -or $null -eq $match[0].value) { return $null }
    return [double]$match[0].value
}

function Get-StageSnapshot {
    return Invoke-RestMethod -Uri "$managementUrl/actuator/doengdiagnosticstage" -TimeoutSec 3
}

if (-not (Test-Path -LiteralPath $baseCompose)) { throw "Base compose not found" }
if (-not (Test-Path -LiteralPath $overrideCompose)) { throw "Frozen Exp146 runtime override not found" }
if (-not (Test-Path -LiteralPath $missionLoad)) { throw "mission-load.js not found" }
if (-not (Test-Path -LiteralPath $poolCollector)) { throw "Pool collector not found" }
if (-not (Test-Path -LiteralPath $summarizer)) { throw "Exp148 summarizer not found" }
if (-not (Test-Path -LiteralPath $fixture)) { throw "Fixture not found" }

$gitSafe = "safe.directory=$($repo.Replace('\', '/'))"
$headOutput = @(& git -C $repo -c $gitSafe rev-parse HEAD 2>$null)
$branchOutput = @(& git -C $repo -c $gitSafe branch --show-current 2>$null)
$head = if ($headOutput.Count -gt 0) { [string]$headOutput[0].Trim() } else { "" }
$branch = if ($branchOutput.Count -gt 0) { [string]$branchOutput[0].Trim() } else { "DETACHED" }
$dirty = @(& git -C $repo -c $gitSafe status --porcelain 2>$null)
if ($head -ne $ExpectedCommit) {
    throw "Commit mismatch: expected $ExpectedCommit, actual $head"
}
if ($dirty.Count -gt 0) {
    $allowedResultPrefix = ((Resolve-Path (Join-Path $repo "backend\experiments\results\experiment-1-48") -ErrorAction SilentlyContinue).Path)
    if ([string]::IsNullOrWhiteSpace($allowedResultPrefix)) {
        throw "Working tree must be clean outside the Exp148 result root."
    }
    foreach ($entry in $dirty) {
        $candidate = [string]$entry
        if ($candidate.Length -gt 3) { $candidate = $candidate.Substring(3) }
        $candidatePath = Join-Path $repo $candidate
        $resolvedCandidate = (Resolve-Path $candidatePath -ErrorAction SilentlyContinue).Path
        if ($null -eq $resolvedCandidate -or (-not $allowedResultPrefix.StartsWith($resolvedCandidate, [System.StringComparison]::OrdinalIgnoreCase) -and -not $resolvedCandidate.StartsWith($allowedResultPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            throw "Unexpected working tree change before EXECUTE: $entry"
        }
    }
}
if ((Test-Path -LiteralPath $resultRoot) -and $ExecutionMode -eq "PREFLIGHT") {
    throw "Result root already exists: $resultRoot"
}

New-Item -ItemType Directory -Force -Path $planDir, $warmupDir, $highDir, $analysisDir | Out-Null
Save-Json (Join-Path $planDir "baseline.json") ([ordered]@{
    repository = "https://github.com/jehyuck/do-eng"
    branch = $branch
    commit = $head
    workingTreeClean = $true
    question = "Which stage, pool, database, or resource signal best explains the frozen HIGH workload failures?"
})

$renderedPath = Join-Path $planDir "rendered-compose.yml"
& docker compose -p $project -f $baseCompose -f $overrideCompose config | Set-Content -LiteralPath $renderedPath -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "Compose rendering failed" }
$rendered = Get-Content -LiteralPath $renderedPath -Raw -Encoding UTF8
$requiredPatterns = [ordered]@{
    poolMode = 'DOENG_EXTERNAL_POOL_MODE:\s*"?SHARED"?'
    maxConnections = 'DOENG_SHARED_POOL_MAX_CONNECTIONS:\s*"?500"?'
    maxPending = 'DOENG_SHARED_POOL_PENDING_MAX_COUNT:\s*"?800"?'
    poolObservation = 'DOENG_POOL_OBSERVATION_ENABLED:\s*"?true"?'
    stageObservation = ('DOENG_STAGE_OBSERVATION_ENABLED:\s*"?' + $stageExpected + '"?')
    exposure = 'MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE:\s*"?health,metrics,doengexperiment,doengdiagnosticpool,doengdiagnosticstage"?'
}
foreach ($entry in $requiredPatterns.GetEnumerator()) {
    if ($rendered -notmatch $entry.Value) {
        throw "Rendered compose contract missing: $($entry.Key)"
    }
}

Save-Json (Join-Path $planDir "static-contract.json") ([ordered]@{
    status = "PASS"
    maxConnectionsVariable = "DOENG_SHARED_POOL_MAX_CONNECTIONS=500"
    maxPendingVariable = "DOENG_SHARED_POOL_PENDING_MAX_COUNT=800"
    rejectedLegacyVariable = "DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT"
    poolObservation = $true
    diagnosticEndpointExposed = $true
    sourceMetricsRegistration = "ExternalHttpClientConfig builder.metrics(true) + HttpClient.metrics(true, uriMapper)"
})

if ($ExecutionMode -eq "PREFLIGHT") {
    Write-Output "EXP147_STATIC_PREFLIGHT_PASS"
    exit 0
}

$started = $false
$poolJob = $null
$resourceJob = $null
$stageJob = $null
$r2dbcJob = $null
try {
    Prepare-RuntimeCompose
    Invoke-Compose @("build", "flux-corrected", "experiment-mock")
    Invoke-Compose @("up", "-d", "--force-recreate", "mariadb", "experiment-mock", "flux-corrected")
    $started = $true
    $health = Wait-Health
    Invoke-RestMethod -Method Post -Uri "$mockUrl/__control" -ContentType "application/json" `
        -Body '{"result":true,"delayMs":2000,"status":200,"storageDelayMs":100,"storageStatus":200}' | Out-Null

    $appId = Get-ContainerId "flux-corrected"
    $mockId = Get-ContainerId "experiment-mock"
    $dbId = Get-ContainerId "mariadb"
    $appInspect = Inspect-Container $appId (Join-Path $planDir "application-inspect.json")
    $mockInspect = Inspect-Container $mockId (Join-Path $planDir "mock-inspect.json")
    $null = Inspect-Container $dbId (Join-Path $planDir "database-inspect.json")
    $appEnv = Env-Map $appInspect

    $runtimeContract = [ordered]@{
        health = $health.status
        applicationCpu = [double]$appInspect.HostConfig.NanoCpus / 1000000000
        applicationMemoryBytes = [double]$appInspect.HostConfig.Memory
        mockCpu = [double]$mockInspect.HostConfig.NanoCpus / 1000000000
        mockMemoryBytes = [double]$mockInspect.HostConfig.Memory
        poolMode = $appEnv.DOENG_EXTERNAL_POOL_MODE
        maxConnections = $appEnv.DOENG_SHARED_POOL_MAX_CONNECTIONS
        maxPending = $appEnv.DOENG_SHARED_POOL_PENDING_MAX_COUNT
        pendingAcquireTimeoutMs = $appEnv.DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS
        poolObservation = $appEnv.DOENG_POOL_OBSERVATION_ENABLED
        stageObservation = $appEnv.DOENG_STAGE_OBSERVATION_ENABLED
        exposure = $appEnv.MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE
    }
    Save-Json (Join-Path $planDir "runtime-contract.json") $runtimeContract

    if ($runtimeContract.applicationCpu -ne 2 -or $runtimeContract.mockCpu -ne 4) { throw "CPU contract mismatch" }
    if ($runtimeContract.applicationMemoryBytes -ne 3221225472 -or $runtimeContract.mockMemoryBytes -ne 1073741824) { throw "Memory contract mismatch" }
    if ($runtimeContract.maxConnections -ne "500" -or $runtimeContract.maxPending -ne "800") { throw "Pool runtime env mismatch" }
    if ($runtimeContract.poolObservation -ne "true") { throw "Pool observation is not enabled" }
    if ($runtimeContract.stageObservation -ne $stageExpected) { throw "Stage observation runtime mismatch" }
    try {
        $stageHealth = Invoke-RestMethod -Uri "$managementUrl/actuator/doengdiagnosticstage" -TimeoutSec 3
        if ($null -eq $stageHealth.stages) { throw "Stage endpoint response has no stages property" }
    } catch {
        throw "EXP148_STAGE_ENDPOINT_INVALID: $($_.Exception.Message)"
    }

    $warmupRunId = if ($ObservationMode -eq "P") { "WARMUP-EXP148-A1B0-P-001" } else { "WARMUP-EXP148-A1B0-D-001" }
    $highRunId = if ($ObservationMode -eq "P") { "RUN-EXP148-A1B0-PERFORMANCE-001" } else { "RUN-EXP148-A1B0-DIAGNOSTIC-001" }
    $warmup = Invoke-NodeLoad -RunId $warmupRunId -ActiveMissions 1 `
        -DurationMs 5000 -DrainSeconds 10 -WatchdogSeconds 45 -OutputDir $warmupDir
    if ($warmup.summary.successfulRequests -lt 1 -or -not $warmup.summary.accounting.valid -or -not $warmup.summary.mockDrain.drainCompleted) {
        throw "Warm-up full-path contract failed"
    }

    $poolReady = $null
    $lastPoolReadinessError = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            $snapshot = Invoke-RestMethod -Uri "$managementUrl/actuator/doengdiagnosticpool" -TimeoutSec 3
            $active = Metric-Value $snapshot "reactor.netty.connection.provider.active.connections" "doeng-external"
            $pending = Metric-Value $snapshot "reactor.netty.connection.provider.pending.connections" "doeng-external"
            $maxConnections = Metric-Value $snapshot "reactor.netty.connection.provider.max.connections" "doeng-external"
            $maxPending = Metric-Value $snapshot "reactor.netty.connection.provider.max.pending.connections" "doeng-external"
            if ($null -ne $active -and $null -ne $pending -and $maxConnections -eq 500 -and $maxPending -eq 800) {
                $poolReady = [ordered]@{
                    status = "PASS"
                    attempt = $attempt
                    snapshot = $snapshot
                    active = $active
                    pending = $pending
                    maxConnections = $maxConnections
                    maxPending = $maxPending
                }
                break
            }
        } catch {
            $lastPoolReadinessError = $_.Exception.Message
        }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $poolReady) {
        Save-Json (Join-Path $planDir "pool-readiness.json") ([ordered]@{
            status = "FAIL"
            error = $lastPoolReadinessError
            reason = "Pool meters must be checked after an actual external request because they are registered lazily"
        })
        throw "EXP148_POOL500_METER_NOT_READY_AFTER_WARMUP"
    }
    Save-Json (Join-Path $planDir "pool-readiness.json") $poolReady
    Invoke-RestMethod -Uri "$managementUrl/actuator/metrics" -TimeoutSec 3 |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $planDir "actuator-metric-names.json") -Encoding UTF8

    $poolTimeline = Join-Path $highDir "pool-timeline.jsonl"
    $resourceTimeline = Join-Path $highDir "resource-samples.csv"
    $stageTimeline = Join-Path $highDir "stage-timeline.jsonl"
    $r2dbcTimeline = Join-Path $highDir "r2dbc-timeline.jsonl"
    $stageBefore = Get-StageSnapshot
    Save-Json (Join-Path $highDir "stage-before.json") $stageBefore
    $schemaPath = Join-Path $highDir "db-schema.txt"
    & docker compose -p $project -f $baseCompose -f $overrideCompose exec -T mariadb mariadb -udoeng -pdoeng-experiment-pass doeng -e "SHOW CREATE TABLE mission_completion; SHOW CREATE TABLE progress; SHOW CREATE TABLE picture; SHOW INDEX FROM mission_completion; SHOW INDEX FROM progress; SHOW INDEX FROM picture;" |
        Set-Content -LiteralPath $schemaPath -Encoding UTF8
    $collectorScript = $poolCollector
    $poolJob = Start-Job -ScriptBlock {
        param($ScriptPath, $ManagementUrl, $OutputPath)
        & $ScriptPath -ManagementUrl $ManagementUrl -OutputPath $OutputPath -DurationSeconds 75 -IntervalMilliseconds 1000
    } -ArgumentList $collectorScript, $managementUrl, $poolTimeline

    $resourceJob = Start-Job -ScriptBlock {
        param($OutputPath)
        "timestampUtc,name,cpuPercent,memoryUsage,memoryPercent,pids" | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        $deadline = (Get-Date).AddSeconds(75)
        while ((Get-Date) -lt $deadline) {
            $timestamp = [DateTime]::UtcNow.ToString("o")
            $lines = & docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.PIDs}}'
            foreach ($line in $lines) { "$timestamp,$line" | Add-Content -LiteralPath $OutputPath -Encoding UTF8 }
            Start-Sleep -Seconds 1
        }
    } -ArgumentList $resourceTimeline

    $stageJob = if ($ObservationMode -eq "D") { Start-Job -ScriptBlock {
        param($ManagementUrl, $OutputPath)
        $deadline = (Get-Date).AddSeconds(75)
        while ((Get-Date) -lt $deadline) {
            try {
                $snapshot = Invoke-RestMethod -Uri "$ManagementUrl/actuator/doengdiagnosticstage" -TimeoutSec 3
                $snapshot | Add-Member -NotePropertyName capturedAtHost -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) -Force
                ($snapshot | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $OutputPath -Encoding UTF8
            } catch {
                (@{capturedAtHost=[DateTime]::UtcNow.ToString("o");failure=$_.Exception.Message} | ConvertTo-Json -Compress) | Add-Content -LiteralPath $OutputPath -Encoding UTF8
            }
            Start-Sleep -Seconds 1
        }
    } -ArgumentList $managementUrl, $stageTimeline } else { $null }

    $r2dbcJob = Start-Job -ScriptBlock {
        param($ManagementUrl, $OutputPath)
        $metricNames = $null
        $deadline = (Get-Date).AddSeconds(75)
        while ((Get-Date) -lt $deadline) {
            try {
                if ($null -eq $metricNames) {
                    $metricNames = @((Invoke-RestMethod -Uri "$ManagementUrl/actuator/metrics" -TimeoutSec 3).names | Where-Object { $_ -match '^r2dbc\.pool\.' })
                }
                $values = [ordered]@{ capturedAtHost = [DateTime]::UtcNow.ToString("o"); metricsAvailable = ($metricNames.Count -gt 0) }
                foreach ($name in $metricNames) {
                    try { $values[$name] = (Invoke-RestMethod -Uri "$ManagementUrl/actuator/metrics/$name" -TimeoutSec 3).measurements[0].value } catch { $values[$name] = $null }
                }
                ($values | ConvertTo-Json -Compress) | Add-Content -LiteralPath $OutputPath -Encoding UTF8
            } catch {
                (@{capturedAtHost=[DateTime]::UtcNow.ToString("o");metricsAvailable=$false;failure=$_.Exception.Message} | ConvertTo-Json -Compress) | Add-Content -LiteralPath $OutputPath -Encoding UTF8
            }
            Start-Sleep -Seconds 1
        }
    } -ArgumentList $managementUrl, $r2dbcTimeline

    $runTimestamps = [ordered]@{
        collectorStartedAt = [DateTime]::UtcNow.ToString("o")
        highNodeStartedAt = $null
        highNodeFinishedAt = $null
        collectorsFinishedAt = $null
    }
    $runTimestamps.highNodeStartedAt = [DateTime]::UtcNow.ToString("o")
    $high = Invoke-NodeLoad -RunId $highRunId -ActiveMissions 200 `
        -DurationMs 30000 -DrainSeconds 30 -WatchdogSeconds 120 -OutputDir $highDir
    $runTimestamps.highNodeFinishedAt = [DateTime]::UtcNow.ToString("o")

    foreach ($job in @($poolJob, $resourceJob, $stageJob, $r2dbcJob)) {
        if ($null -eq $job) { continue }
        Wait-Job -Job $job -Timeout 30 | Out-Null
        if ($job.State -eq "Running") { Stop-Job -Job $job }
        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    }
    $runTimestamps.collectorsFinishedAt = [DateTime]::UtcNow.ToString("o")
    Save-Json (Join-Path $highDir "run-timestamps.json") $runTimestamps
    Save-Json (Join-Path $highDir "stage-load-stop.json") (Get-StageSnapshot)
    Save-Json (Join-Path $highDir "stage-after-drain.json") (Get-StageSnapshot)
    & docker compose -p $project -f $baseCompose -f $overrideCompose exec -T mariadb mariadb -uroot -pdoeng-experiment-root doeng -e "SHOW ENGINE INNODB STATUS;" |
        Set-Content -LiteralPath (Join-Path $highDir "innodb-status-after-high.txt") -Encoding UTF8
    $consistencySql = "SELECT (SELECT COUNT(*) FROM mission_completion) AS mission_completion_count, (SELECT COUNT(*) FROM progress) AS progress_count, (SELECT COUNT(*) FROM picture) AS picture_count, (SELECT COUNT(*) FROM picture p LEFT JOIN progress pr ON pr.id=p.progress_id WHERE pr.id IS NULL) AS orphan_picture_count, (SELECT COUNT(*) FROM (SELECT mission_run_id FROM mission_completion GROUP BY mission_run_id HAVING COUNT(*) > 1) d) AS duplicate_mission_run_id_count;"
    & docker compose -p $project -f $baseCompose -f $overrideCompose exec -T mariadb mariadb -uroot -pdoeng-experiment-root doeng --batch --skip-column-names -e $consistencySql |
        Set-Content -LiteralPath (Join-Path $highDir "consistency.tsv") -Encoding UTF8
    $r2dbcRows = @()
    if (Test-Path -LiteralPath $r2dbcTimeline) {
        $r2dbcRows = @(Get-Content -LiteralPath $r2dbcTimeline -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    }
    Save-Json (Join-Path $highDir "r2dbc-availability.json") ([ordered]@{
        available = @($r2dbcRows | Where-Object { $_.metricsAvailable -eq $true }).Count -gt 0
        sampleCount = $r2dbcRows.Count
        status = if ($r2dbcRows.Count -gt 0 -and @($r2dbcRows | Where-Object { $_.metricsAvailable -eq $true }).Count -gt 0) { "AVAILABLE" } else { "R2DBC_POOL_METRICS_NOT_AVAILABLE" }
    })

    Invoke-Compose @("logs", "--no-color", "--timestamps", "flux-corrected") |
        Set-Content -LiteralPath (Join-Path $highDir "application.log") -Encoding UTF8
    Invoke-Compose @("logs", "--no-color", "--timestamps", "experiment-mock") |
        Set-Content -LiteralPath (Join-Path $highDir "mock.log") -Encoding UTF8
    $null = Inspect-Container $appId (Join-Path $highDir "application-inspect-after.json")
    $null = Inspect-Container $mockId (Join-Path $highDir "mock-inspect-after.json")
    $null = Inspect-Container $dbId (Join-Path $highDir "database-inspect-after.json")
    Save-Json (Join-Path $highDir "pool-final-snapshot.json") (Invoke-RestMethod -Uri "$managementUrl/actuator/doengdiagnosticpool" -TimeoutSec 3)
    Save-Json (Join-Path $highDir "mock-final-metrics.json") (Invoke-RestMethod -Uri "$mockUrl/__metrics" -TimeoutSec 3)

    & $summarizer -PoolTimelinePath $poolTimeline `
        -ClientResultsPath (Join-Path $highDir "client-results.json") `
        -ApplicationLogPath (Join-Path $highDir "application.log") `
        -StageTimelinePath (Join-Path $highDir "stage-timeline.jsonl") `
        -R2dbcTimelinePath (Join-Path $highDir "r2dbc-timeline.jsonl") `
        -ResourceSamplesPath (Join-Path $highDir "resource-samples.csv") `
        -ConsistencyPath (Join-Path $highDir "consistency.tsv") `
        -OutputJsonPath (Join-Path $analysisDir "run-summary.json") `
        -OutputMarkdownPath (Join-Path $analysisDir "run-report.md") |
        Set-Content -LiteralPath (Join-Path $analysisDir "classification.txt") -Encoding UTF8

    Save-Json (Join-Path $planDir "execution-status.json") ([ordered]@{
        status = if ($ObservationMode -eq "P") { "EXP148_A1B0_P_COMPLETE" } else { "EXP148_A1B0_D_COMPLETE" }
        warmupRunId = $warmupRunId
        highRunId = $highRunId
        observationMode = $ObservationMode
        additionalRuns = 0
        observationCalibrationExecuted = $true
        mvcExecuted = $false
        productionJavaModified = $false
    })
    Write-Output (if ($ObservationMode -eq "P") { "EXP148_A1B0_P_COMPLETE" } else { "EXP148_A1B0_D_COMPLETE" })
} catch {
    Save-Json (Join-Path $planDir "execution-status.json") ([ordered]@{
        status = "EXP148_EXECUTION_STOPPED"
        error = $_.Exception.Message
        additionalRuns = 0
    })
    throw
} finally {
    foreach ($job in @($poolJob, $resourceJob, $stageJob, $r2dbcJob)) {
        if ($null -eq $job) { continue }
        if ($job.State -eq "Running") { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    if ($started) {
        try {
            & docker compose -p $project -f $baseCompose -f $overrideCompose ps |
                Set-Content -LiteralPath (Join-Path $planDir "compose-ps-final.txt") -Encoding UTF8
        } catch { }
        try { Invoke-Compose @("down", "--remove-orphans") } catch { }
    }
    if ($runtimeCompose -and (Test-Path -LiteralPath $runtimeCompose)) {
        Remove-Item -LiteralPath $runtimeCompose -Force -ErrorAction SilentlyContinue
    }
    if ($runtimeDbDumpDir -and (Test-Path -LiteralPath $runtimeDbDumpDir)) {
        Remove-Item -LiteralPath $runtimeDbDumpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($runtimeSeedImage) {
        & docker image rm $runtimeSeedImage 2>$null | Out-Null
    }
}
