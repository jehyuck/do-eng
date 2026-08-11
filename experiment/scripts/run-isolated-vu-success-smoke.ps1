param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$Implementation,
    [Parameter(Mandatory = $true)]
    [string]$TargetUrl,
    [Parameter(Mandatory = $true)]
    [string]$ServerService,
    [string]$ComposeProject = "doeng-experiment",
    [string[]]$ComposeFiles,
    [ValidateRange(2, 1000)]
    [int]$ActiveMissions = 2,
    [string]$FixturePath = "image\arc.jpg",
    [long]$SceneId = 2,
    [string]$Answer = "happy",
    [int]$AiDelayMs = 500,
    [int]$StorageDelayMs = 100,
    [int]$IntervalMs = 3000,
    [int]$DurationMs = 3500,
    [int]$RequestTimeoutMs = 10000,
    [ValidateRange(1, 60000)]
    [int]$TargetP95Ms = 3000,
    [ValidateSet("aligned", "staggered")]
    [string]$ArrivalMode = "aligned",
    [ValidateSet("single-success", "reconnect-ramp")]
    [string]$LoadScenario = "single-success",
    [ValidateSet("standard", "controlled-admission")]
    [string]$OutcomeMode = "standard",
    [ValidateSet("legacy", "corrected")]
    [string]$AccountingMode = "legacy",
    [int]$InitialActiveUsers = 0,
    [int]$ActivationStepUsers = 0,
    [int]$ActivationIntervalMs = 3000,
    [int]$ReconnectDelayMs = 3000,
    [ValidateSet(0, 1)]
    [int]$EnableObservability = 0,
    [ValidateSet(-1, 0, 1)]
    [int]$EnableJfr = -1,
    [ValidateSet(0, 1)]
    [int]$EnableContainerMonitor = 1,
    [ValidateSet(0, 1)]
    [int]$SkipApplicationSnapshot = 0,
    [ValidateSet(0, 1)]
    [int]$SkipMockMetrics = 0,
    [ValidateRange(0, 300)]
    [int]$DrainObservationSeconds = 0,
    [ValidateRange(0, 86400000)]
    [int]$WarmupMs = 0,
    [bool]$AiResult = $true,
    [ValidateRange(100, 599)]
    [int]$AiStatus = 200,
    [ValidateRange(100, 599)]
    [int]$StorageStatus = 200,
    [string]$AppCpu,
    [string]$AppMemory,
    [Nullable[int]]$HttpMaxConnections,
    [Nullable[int]]$HttpPendingMaxCount,
    [Nullable[int]]$HttpConnectTimeoutMs,
    [Nullable[int]]$HttpResponseTimeoutMs,
    [Nullable[int]]$HttpPendingAcquireTimeoutMs,
    [Nullable[int]]$DbPoolMaxSize,
    [Nullable[int]]$MvcMaxThreads,
    [string]$JavaXms,
    [string]$JavaXmx,
    [string]$ConfigPath,
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "resolve-verification-validity.ps1")
$configDocument = $null
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        [System.IO.Path]::GetFullPath($ConfigPath)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ConfigPath))
    }
    if (-not (Test-Path -LiteralPath $resolvedConfigPath)) {
        throw "Configuration file not found: $resolvedConfigPath"
    }
    $configDocument = Get-Content -Raw -LiteralPath $resolvedConfigPath | ConvertFrom-Json
    $loadConfig = $configDocument.load
    $downstreamConfig = $configDocument.downstream
    $applicationConfig = $configDocument.application
    $httpConfig = $configDocument.http
    $databaseConfig = $configDocument.database
    $mvcConfig = $configDocument.mvc
    $jvmConfig = $configDocument.jvm
    if ($null -ne $loadConfig.activeMissions) { $ActiveMissions = [int]$loadConfig.activeMissions }
    if ($null -ne $loadConfig.loadScenario) { $LoadScenario = [string]$loadConfig.loadScenario }
    if ($null -ne $loadConfig.accountingMode) { $AccountingMode = [string]$loadConfig.accountingMode }
    if ($null -ne $loadConfig.intervalMs) { $IntervalMs = [int]$loadConfig.intervalMs }
    if ($null -ne $loadConfig.durationMs) { $DurationMs = [int]$loadConfig.durationMs }
    if ($null -ne $loadConfig.requestTimeoutMs) { $RequestTimeoutMs = [int]$loadConfig.requestTimeoutMs }
    if ($null -ne $loadConfig.arrivalMode) { $ArrivalMode = [string]$loadConfig.arrivalMode }
    if ($null -ne $loadConfig.initialActiveUsers) { $InitialActiveUsers = [int]$loadConfig.initialActiveUsers }
    if ($null -ne $loadConfig.activationStepUsers) { $ActivationStepUsers = [int]$loadConfig.activationStepUsers }
    if ($null -ne $loadConfig.activationIntervalMs) { $ActivationIntervalMs = [int]$loadConfig.activationIntervalMs }
    if ($null -ne $loadConfig.reconnectDelayMs) { $ReconnectDelayMs = [int]$loadConfig.reconnectDelayMs }
    if ($null -ne $loadConfig.warmupMs) { $WarmupMs = [int]$loadConfig.warmupMs }
    if ($null -ne $loadConfig.drainObservationSeconds) { $DrainObservationSeconds = [int]$loadConfig.drainObservationSeconds }
    if ($null -ne $downstreamConfig.aiResult) { $AiResult = [bool]$downstreamConfig.aiResult }
    if ($null -ne $downstreamConfig.aiDelayMs) { $AiDelayMs = [int]$downstreamConfig.aiDelayMs }
    if ($null -ne $downstreamConfig.aiStatus) { $AiStatus = [int]$downstreamConfig.aiStatus }
    if ($null -ne $downstreamConfig.storageDelayMs) { $StorageDelayMs = [int]$downstreamConfig.storageDelayMs }
    if ($null -ne $downstreamConfig.storageStatus) { $StorageStatus = [int]$downstreamConfig.storageStatus }
    if ($null -ne $applicationConfig.cpu) { $AppCpu = [string]$applicationConfig.cpu }
    if ($null -ne $applicationConfig.memory) { $AppMemory = [string]$applicationConfig.memory }
    if ($null -ne $httpConfig.maxConnections) { $HttpMaxConnections = [int]$httpConfig.maxConnections }
    if ($null -ne $httpConfig.pendingMaxCount) { $HttpPendingMaxCount = [int]$httpConfig.pendingMaxCount }
    if ($null -ne $httpConfig.connectTimeoutMs) { $HttpConnectTimeoutMs = [int]$httpConfig.connectTimeoutMs }
    if ($null -ne $httpConfig.responseTimeoutMs) { $HttpResponseTimeoutMs = [int]$httpConfig.responseTimeoutMs }
    if ($null -ne $httpConfig.pendingAcquireTimeoutMs) { $HttpPendingAcquireTimeoutMs = [int]$httpConfig.pendingAcquireTimeoutMs }
    if ($null -ne $databaseConfig.poolMaxSize) { $DbPoolMaxSize = [int]$databaseConfig.poolMaxSize }
    if ($null -ne $mvcConfig.maxThreads) { $MvcMaxThreads = [int]$mvcConfig.maxThreads }
    if ($null -ne $jvmConfig.xms) { $JavaXms = [string]$jvmConfig.xms }
    if ($null -ne $jvmConfig.xmx) { $JavaXmx = [string]$jvmConfig.xmx }
} else {
    $resolvedConfigPath = $null
}
if ($ArrivalMode -notin @("aligned", "staggered")) { throw "ArrivalMode must be aligned or staggered" }
if ($LoadScenario -notin @("single-success", "reconnect-ramp")) { throw "LoadScenario must be single-success or reconnect-ramp" }
if ($AccountingMode -notin @("legacy", "corrected")) { throw "AccountingMode must be legacy or corrected" }
foreach ($value in @($ActiveMissions, $IntervalMs, $DurationMs, $RequestTimeoutMs, $ActivationIntervalMs, $ReconnectDelayMs, $AiDelayMs, $StorageDelayMs)) {
    if ($value -lt 1) { throw "Load and downstream timing values must be positive" }
}
foreach ($value in @($WarmupMs, $DrainObservationSeconds)) {
    if ($value -lt 0) { throw "Warmup and drain values must be non-negative" }
}
if ($AiStatus -lt 100 -or $AiStatus -gt 599 -or $StorageStatus -lt 100 -or $StorageStatus -gt 599) { throw "Mock status values must be valid HTTP status codes" }
foreach ($value in @($HttpMaxConnections, $HttpPendingMaxCount, $HttpConnectTimeoutMs, $HttpResponseTimeoutMs, $HttpPendingAcquireTimeoutMs, $DbPoolMaxSize, $MvcMaxThreads)) {
    if ($null -ne $value -and $value -lt 1) { throw "Numeric resource and timeout configuration values must be positive" }
}
$configurationEnvironmentNames = @("APP_CPU", "APP_MEMORY", "HTTP_MAX_CONNECTIONS", "HTTP_PENDING_MAX_COUNT", "HTTP_CONNECT_TIMEOUT_MS", "HTTP_RESPONSE_TIMEOUT_MS", "HTTP_PENDING_ACQUIRE_TIMEOUT_MS", "DB_POOL_MAX_SIZE", "MVC_MAX_THREADS", "JAVA_XMS", "JAVA_XMX", "MOCK_AI_RESULT", "MOCK_AI_DELAY_MS", "MOCK_AI_STATUS", "MOCK_STORAGE_DELAY_MS", "MOCK_STORAGE_STATUS")
$previousConfigurationEnvironment = @{}
foreach ($name in $configurationEnvironmentNames) { $previousConfigurationEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process") }
$explicitConfiguration = (-not [string]::IsNullOrWhiteSpace($ConfigPath)) -or $PSBoundParameters.ContainsKey("AppCpu") -or $PSBoundParameters.ContainsKey("AppMemory") -or $PSBoundParameters.ContainsKey("HttpMaxConnections") -or $PSBoundParameters.ContainsKey("HttpPendingMaxCount") -or $PSBoundParameters.ContainsKey("HttpConnectTimeoutMs") -or $PSBoundParameters.ContainsKey("HttpResponseTimeoutMs") -or $PSBoundParameters.ContainsKey("HttpPendingAcquireTimeoutMs") -or $PSBoundParameters.ContainsKey("DbPoolMaxSize") -or $PSBoundParameters.ContainsKey("MvcMaxThreads") -or $PSBoundParameters.ContainsKey("JavaXms") -or $PSBoundParameters.ContainsKey("JavaXmx") -or $PSBoundParameters.ContainsKey("AiResult") -or $PSBoundParameters.ContainsKey("AiDelayMs") -or $PSBoundParameters.ContainsKey("AiStatus") -or $PSBoundParameters.ContainsKey("StorageDelayMs") -or $PSBoundParameters.ContainsKey("StorageStatus")
function Set-ContractEnvironment {
    param([string]$Name, [object]$Value)
    if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) { [Environment]::SetEnvironmentVariable($Name, [string]$Value, "Process") }
}
if ($explicitConfiguration) {
    Set-ContractEnvironment "APP_CPU" $AppCpu
    Set-ContractEnvironment "APP_MEMORY" $AppMemory
    Set-ContractEnvironment "HTTP_MAX_CONNECTIONS" $HttpMaxConnections
    Set-ContractEnvironment "HTTP_PENDING_MAX_COUNT" $HttpPendingMaxCount
    Set-ContractEnvironment "HTTP_CONNECT_TIMEOUT_MS" $HttpConnectTimeoutMs
    Set-ContractEnvironment "HTTP_RESPONSE_TIMEOUT_MS" $HttpResponseTimeoutMs
    Set-ContractEnvironment "HTTP_PENDING_ACQUIRE_TIMEOUT_MS" $HttpPendingAcquireTimeoutMs
    Set-ContractEnvironment "DB_POOL_MAX_SIZE" $DbPoolMaxSize
    Set-ContractEnvironment "MVC_MAX_THREADS" $MvcMaxThreads
    Set-ContractEnvironment "JAVA_XMS" $JavaXms
    Set-ContractEnvironment "JAVA_XMX" $JavaXmx
    Set-ContractEnvironment "MOCK_AI_RESULT" ([string]$AiResult).ToLowerInvariant()
    Set-ContractEnvironment "MOCK_AI_DELAY_MS" $AiDelayMs
    Set-ContractEnvironment "MOCK_AI_STATUS" $AiStatus
    Set-ContractEnvironment "MOCK_STORAGE_DELAY_MS" $StorageDelayMs
    Set-ContractEnvironment "MOCK_STORAGE_STATUS" $StorageStatus
}
if ($null -eq $ComposeFiles -or $ComposeFiles.Count -eq 0) {
    $ComposeFiles = @("backend\docker-compose.experiment.yaml")
}
$ComposeFiles = @($ComposeFiles | ForEach-Object {
    $_ -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
})
$composeFiles = @($ComposeFiles | ForEach-Object {
    if ([System.IO.Path]::IsPathRooted($_)) {
        [System.IO.Path]::GetFullPath($_)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $_))
    }
})
foreach ($composeFile in $composeFiles) {
    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "Compose file not found: $composeFile"
    }
}
$composeArguments = @()
foreach ($composeFile in $composeFiles) {
    $composeArguments += @("-f", $composeFile)
}
$resultsRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "experiment\results"))
$runDirectory = Join-Path $resultsRoot $RunId
$mockBaseUrl = "http://127.0.0.1:9100"
$privateTokenPath = Join-Path $repositoryRoot ".experiment-work\$RunId-auth-tokens.json"
$observabilityEnabled = $EnableObservability -eq 1
$jfrEnabled = if ($EnableJfr -eq -1) {
    $observabilityEnabled
} else {
    $EnableJfr -eq 1
}
$containerMonitorEnabled = $observabilityEnabled -and $EnableContainerMonitor -eq 1

if ($LoadScenario -eq "reconnect-ramp") {
    if ($InitialActiveUsers -lt 1 -or $InitialActiveUsers -gt $ActiveMissions) {
        throw "InitialActiveUsers must be between 1 and ActiveMissions for reconnect-ramp"
    }
    if ($ActivationStepUsers -lt 1) {
        throw "ActivationStepUsers must be positive for reconnect-ramp"
    }
    if ($ActivationIntervalMs -lt 1 -or $ReconnectDelayMs -lt 1) {
        throw "ActivationIntervalMs and ReconnectDelayMs must be positive"
    }
}
$effectiveInitialActiveUsers = if ($LoadScenario -eq "reconnect-ramp") { $InitialActiveUsers } else { $ActiveMissions }
$effectiveActivationStepUsers = if ($LoadScenario -eq "reconnect-ramp") { $ActivationStepUsers } else { $ActiveMissions }

if (Test-Path -LiteralPath $runDirectory) {
    throw "Run result directory already exists: $runDirectory"
}
if (Test-Path -LiteralPath $privateTokenPath) {
    throw "Private token file already exists: $privateTokenPath"
}

$resolvedFixture = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $FixturePath))
if (-not (Test-Path -LiteralPath $resolvedFixture)) {
    throw "Fixture not found: $resolvedFixture"
}
if ([string]::IsNullOrWhiteSpace($NodeCommand)) {
    $nodeOnPath = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeOnPath) {
        $NodeCommand = $nodeOnPath.Source
    } else {
        $NodeCommand = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
        if (-not (Test-Path -LiteralPath $NodeCommand)) {
            throw "Node executable not found; pass -NodeCommand"
        }
    }
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory = $true)][string]$Sql)
    $output = & docker compose -p $ComposeProject @composeArguments exec -T mariadb `
        mariadb -N -B -udoeng -pdoeng-experiment-pass doeng -e $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "Database observation failed"
    }
    return @($output)
}

function Get-DatabaseState {
    param([Parameter(Mandatory = $true)][array]$Users)
    $memberIds = @($Users | ForEach-Object { [long]$_.memberId }) -join ","
    $summaryRows = Invoke-DatabaseSql -Sql @"
SELECT m.id, m.member_id, COUNT(DISTINCT p.id), COUNT(pic.id)
FROM member m
LEFT JOIN progress p ON p.member_id=m.id AND p.scene_id=$SceneId
LEFT JOIN picture pic ON pic.progress_id=p.id
WHERE m.id IN ($memberIds)
GROUP BY m.id, m.member_id
ORDER BY m.id;
"@
    $pictures = Invoke-DatabaseSql -Sql @"
SELECT p.member_id, pic.image
FROM progress p
JOIN picture pic ON pic.progress_id=p.id
WHERE p.member_id IN ($memberIds) AND p.scene_id=$SceneId
ORDER BY p.member_id, pic.id;
"@
    [ordered]@{
        users = @($summaryRows | ForEach-Object {
            $fields = $_ -split "`t", 4
            if ($fields.Count -ne 4) { throw "Database user row could not be parsed: $_" }
            [ordered]@{
                memberId = [long]$fields[0]
                login = $fields[1]
                progressCount = [int]$fields[2]
                pictureCount = [int]$fields[3]
            }
        })
        pictures = @($pictures | ForEach-Object {
            $fields = $_ -split "`t", 2
            if ($fields.Count -ne 2) { throw "Database picture row could not be parsed: $_" }
            [ordered]@{ memberId = [long]$fields[0]; image = $fields[1] }
        })
    }
}

function Ensure-MissionCompletionSchema {
    Invoke-DatabaseSql -Sql @"
CREATE TABLE IF NOT EXISTS mission_completion (
  member_id BIGINT NOT NULL,
  scene_id BIGINT NOT NULL,
  mission_run_id VARCHAR(191) NOT NULL,
  object_key VARCHAR(255) NOT NULL,
  completed_at DATETIME(6) NOT NULL,
  PRIMARY KEY (member_id, scene_id, mission_run_id),
  UNIQUE KEY uk_mission_completion_object_key (object_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
"@ | Out-Null
}

function Get-MissionCompletions {
    param([Parameter(Mandatory = $true)][array]$Users)
    $memberIds = @($Users | ForEach-Object { [long]$_.memberId }) -join ","
    $rows = Invoke-DatabaseSql -Sql @"
SELECT member_id, scene_id, mission_run_id, object_key, completed_at
FROM mission_completion
WHERE member_id IN ($memberIds) AND scene_id=$SceneId
ORDER BY member_id, mission_run_id;
"@
    return @($rows | ForEach-Object {
        $fields = $_ -split "`t", 5
        if ($fields.Count -ne 5) { throw "Mission completion row could not be parsed: $_" }
        [ordered]@{
            memberId = [long]$fields[0]
            sceneId = [long]$fields[1]
            missionRunId = $fields[2]
            objectKey = $fields[3]
            completedAt = $fields[4]
        }
    })
}

function Get-ServerContainerId {
    param([switch]$IncludeStopped)
    $psArguments = @("ps")
    if ($IncludeStopped) { $psArguments += "--all" }
    $psArguments += @("-q", $ServerService)
    $output = @(& docker compose -p $ComposeProject @composeArguments @psArguments 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $ids = @($output | ForEach-Object {
        $value = ([string]$_).Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) { $value }
    })
    if ($ids.Count -gt 1) {
        throw "Expected exactly one server container for $ServerService; found $($ids.Count)"
    }
    if ($ids.Count -eq 1) { return $ids[0] }
    return $null
}

function Get-SafeContainerState {
    param([Parameter(Mandatory = $true)][string]$ContainerId)
    $inspectOutput = @(& docker inspect $ContainerId 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "docker inspect failed for $ContainerId" }
    $container = (($inspectOutput -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop)[0]
    return [ordered]@{
        containerId = $container.Id
        name = $container.Name
        image = $container.Config.Image
        restartCount = $container.RestartCount
        state = [ordered]@{
            status = $container.State.Status
            running = $container.State.Running
            restarting = $container.State.Restarting
            paused = $container.State.Paused
            dead = $container.State.Dead
            exitCode = $container.State.ExitCode
            oomKilled = $container.State.OOMKilled
            error = $container.State.Error
            startedAt = $container.State.StartedAt
            finishedAt = $container.State.FinishedAt
        }
        hostConfig = [ordered]@{
            nanoCpus = $container.HostConfig.NanoCpus
            cpuQuota = $container.HostConfig.CpuQuota
            cpuPeriod = $container.HostConfig.CpuPeriod
            cpusetCpus = $container.HostConfig.CpusetCpus
            memory = $container.HostConfig.Memory
            memorySwap = $container.HostConfig.MemorySwap
        }
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Capture-ApplicationDiagnostics {
    param([Parameter(Mandatory = $true)][string]$ContainerId)
    $capture = [ordered]@{
        attempted = $true
        succeeded = $false
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        exitCode = $null
        applicationLog = "application-container.log"
        stdoutLog = "application-container.stdout.log"
        stderrLog = "application-container.stderr.log"
        phaseTrace = "mvc-phase-trace.jsonl"
        phaseCount = 0
        phaseTraceJsonlValid = $false
        phaseParseFailures = 0
    }
    $recoveryErrors = @()
    try {
        $state = Get-SafeContainerState -ContainerId $ContainerId
        $state | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "server-container-state.json")
    } catch {
        $recoveryErrors += "container-state: $($_.Exception.Message)"
    }
    try {
        $applicationLogPath = Join-Path $runDirectory "application-container.log"
        $phaseTracePath = Join-Path $runDirectory "mvc-phase-trace.jsonl"
        $stdoutPath = Join-Path $runDirectory "application-container.stdout.log"
        $stderrPath = Join-Path $runDirectory "application-container.stderr.log"
        $logProcess = Start-Process -FilePath "docker" -ArgumentList @("logs", $ContainerId) -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $capture.exitCode = [int]$logProcess.ExitCode
        $stdoutLines = if (Test-Path -LiteralPath $stdoutPath) { @(Get-Content -LiteralPath $stdoutPath) } else { @() }
        $stderrLines = if (Test-Path -LiteralPath $stderrPath) { @(Get-Content -LiteralPath $stderrPath) } else { @() }
        $applicationLogOutput = @($stdoutLines + $stderrLines)
        $applicationLogOutput | Set-Content -Encoding UTF8 -LiteralPath $applicationLogPath
        $phaseLines = @($applicationLogOutput | ForEach-Object {
            $line = [string]$_
            $marker = $line.IndexOf("DOENG_PHASE ", [System.StringComparison]::Ordinal)
            if ($marker -ge 0) { $line.Substring($marker + "DOENG_PHASE ".Length) }
        })
        $phaseObjects = @()
        foreach ($phaseLine in $phaseLines) {
            try {
                $phaseObject = $phaseLine | ConvertFrom-Json -ErrorAction Stop
                $requiredFields = @("event", "runId", "requestId", "missionRunId", "capturedAt", "elapsedFromServerEnterMicros", "thread")
                if (@($requiredFields | Where-Object { $null -eq $phaseObject.$_ }).Count -gt 0 -or
                    ($phaseObject.event -match "_HTTP_" -and [string]::IsNullOrWhiteSpace([string]$phaseObject.outboundType))) {
                    throw "required phase field missing"
                }
                $phaseObjects += $phaseObject
            } catch {
                $capture.phaseParseFailures += 1
            }
        }
        $phaseLines | Set-Content -Encoding UTF8 -LiteralPath $phaseTracePath
        $capture.phaseCount = $phaseLines.Count
        $capture.phaseTraceJsonlValid = $capture.phaseParseFailures -eq 0
        $capture.succeeded = $capture.exitCode -eq 0
    } catch {
        $recoveryErrors += "application-log: $($_.Exception.Message)"
    }
    if ($recoveryErrors.Count -gt 0) {
        $recoveryErrors | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "application-diagnostic-recovery-error.txt")
    }
    $capture | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "application-log-capture.json")
    return $capture
}

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "capture-environment.ps1") `
        -RunId $RunId -NodeCommand $NodeCommand
    if ($LASTEXITCODE -ne 0) { throw "Environment capture failed" }

    Ensure-MissionCompletionSchema
    $fixture = Get-Item -LiteralPath $resolvedFixture
    $configurationSource = if ($resolvedConfigPath) { "config-file" } else { "parameter-or-runner-default" }
    $composeSource = if ($explicitConfiguration) { $configurationSource } else { "compose-default" }
    $resolvedConfiguration = [ordered]@{
        contractVersion = 1
        configPath = $resolvedConfigPath
        implementation = $Implementation
        load = [ordered]@{
            activeMissions = $ActiveMissions
            loadScenario = $LoadScenario
            accountingMode = $AccountingMode
            intervalMs = $IntervalMs
            durationMs = $DurationMs
            requestTimeoutMs = $RequestTimeoutMs
            arrivalMode = $ArrivalMode
            initialActiveUsers = $effectiveInitialActiveUsers
            activationStepUsers = $effectiveActivationStepUsers
            activationIntervalMs = $ActivationIntervalMs
            reconnectDelayMs = $ReconnectDelayMs
            warmupMs = $WarmupMs
            drainObservationSeconds = $DrainObservationSeconds
            source = $configurationSource
        }
        downstream = [ordered]@{
            aiResult = $AiResult
            aiDelayMs = $AiDelayMs
            aiStatus = $AiStatus
            storageDelayMs = $StorageDelayMs
            storageStatus = $StorageStatus
            source = $configurationSource
        }
        application = [ordered]@{ cpu = $AppCpu; memory = $AppMemory; source = $composeSource }
        http = [ordered]@{
            maxConnections = $HttpMaxConnections
            pendingMaxCount = $HttpPendingMaxCount
            connectTimeoutMs = $HttpConnectTimeoutMs
            responseTimeoutMs = $HttpResponseTimeoutMs
            pendingAcquireTimeoutMs = $HttpPendingAcquireTimeoutMs
            source = $composeSource
        }
        database = [ordered]@{ poolMaxSize = $DbPoolMaxSize; source = $composeSource }
        mvc = [ordered]@{ maxThreads = $MvcMaxThreads; source = $composeSource }
        jvm = [ordered]@{ xms = $JavaXms; xmx = $JavaXmx; source = $composeSource }
    }
    if ($resolvedConfigPath) {
        $sharedResolvedJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\config\resolve-experiment-config.ps1") -Implementation $Implementation -ConfigPath $resolvedConfigPath
        if ($LASTEXITCODE -ne 0) { throw "Shared experiment config resolution failed" }
        $resolvedConfiguration = @($sharedResolvedJson) -join [Environment]::NewLine | ConvertFrom-Json
    }
    $resolvedConfiguration | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "resolved-experiment-config.json")
    $runConfig = [ordered]@{
        runId = $RunId
        implementation = $Implementation
        targetUrl = $TargetUrl
        serverService = $ServerService
        composeProject = $ComposeProject
        composeFiles = @($composeFiles | ForEach-Object {
            [ordered]@{
                path = $_
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLower()
            }
        })
        activeMissions = $ActiveMissions
        arrivalMode = $ArrivalMode
        loadScenario = $LoadScenario
        outcomeMode = $OutcomeMode
        accountingMode = $AccountingMode
        initialActiveUsers = $effectiveInitialActiveUsers
        activationStepUsers = $effectiveActivationStepUsers
        activationIntervalMs = if ($LoadScenario -eq "reconnect-ramp") { $ActivationIntervalMs } else { $null }
        reconnectDelayMs = if ($LoadScenario -eq "reconnect-ramp") { $ReconnectDelayMs } else { $null }
        intervalMs = $IntervalMs
        durationMs = $DurationMs
        requestTimeoutMs = $RequestTimeoutMs
        targetP95Ms = $TargetP95Ms
        warmupMs = $WarmupMs
        resolvedConfiguration = $resolvedConfiguration
        sceneId = $SceneId
        answer = $Answer
        ai = [ordered]@{ result = $AiResult; delayMs = $AiDelayMs; status = $AiStatus }
        storage = [ordered]@{ delayMs = $StorageDelayMs; status = $StorageStatus }
        observability = [ordered]@{
            enabled = $observabilityEnabled
            containerMonitorEnabled = $containerMonitorEnabled
            jfrEnabled = $jfrEnabled
            applicationIntervalMs = if ($containerMonitorEnabled) { 1000 } else { $null }
            applicationSnapshotEnabled = $containerMonitorEnabled -and $SkipApplicationSnapshot -eq 0
            mockContinuousPollingEnabled = $containerMonitorEnabled -and $SkipMockMetrics -eq 0
            databaseIntervalMs = if ($containerMonitorEnabled) { 2000 } else { $null }
        }
        lifecycle = [ordered]@{
            preRunMockIdleRequired = $true
            drainObservationSeconds = $DrainObservationSeconds
            endOfLoadBacklogIsSystemOutcome = $true
        }
        fixture = [ordered]@{
            path = $resolvedFixture
            bytes = $fixture.Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedFixture).Hash.ToLower()
        }
        authentication = [ordered]@{
            mode = "per-vu mock-issued token"
            loginCompletedBeforeMeasurement = $true
            rawTokensPersistedInResults = $false
        }
    }
    $runConfig | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "run-config.json")

    $preRunMockMetrics = Invoke-RestMethod -Uri "$mockBaseUrl/__metrics"
    $preRunMockMetrics | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "mock-metrics-pre-run.json")
    $preRunMockIdle = $preRunMockMetrics.aiInFlight -eq 0 -and $preRunMockMetrics.storageInFlight -eq 0
    if (-not $preRunMockIdle) { throw "Pre-run mock in-flight is not zero" }

    Invoke-RestMethod -Method Post -Uri "$mockBaseUrl/__reset" -ContentType "application/json" -Body "{}" | Out-Null
    Invoke-RestMethod -Method Post -Uri "$mockBaseUrl/__control" -ContentType "application/json" -Body (([ordered]@{
        result = $AiResult
        delayMs = $AiDelayMs
        status = $AiStatus
        storageDelayMs = $StorageDelayMs
        storageStatus = $StorageStatus
    }) | ConvertTo-Json -Compress) | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "mock-control.json")

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "provision-experiment-users.ps1") `
        -RunId $RunId -ComposeProject $ComposeProject -UserCount $ActiveMissions `
        -MetadataPath (Join-Path $runDirectory "prepared-users.json") -TokenPath $privateTokenPath `
        -ComposeFiles ($composeFiles -join ",") -MockBaseUrl $mockBaseUrl | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Experiment-user provisioning failed" }

    $preparedUsers = Get-Content -Raw -LiteralPath (Join-Path $runDirectory "prepared-users.json") | ConvertFrom-Json
    $databaseBefore = Get-DatabaseState -Users @($preparedUsers.users)
    $databaseBefore | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "db-before.json")
    $storageBefore = Invoke-RestMethod -Uri "$mockBaseUrl/__storage"
    $storageBefore | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "storage-before.json")

    $env:TARGET_URL = $TargetUrl
    $env:ACTIVE_MISSIONS = [string]$ActiveMissions
    $env:INTERVAL_MS = [string]$IntervalMs
    $env:DURATION_MS = [string]$DurationMs
    $env:REQUEST_TIMEOUT_MS = [string]$RequestTimeoutMs
    $env:TARGET_P95_MS = [string]$TargetP95Ms
    $env:SCENE_ID = [string]$SceneId
    $env:ANSWER = $Answer
    $env:FIXTURE_PATH = $resolvedFixture
    $env:EXPERIMENT_RUN_ID = $RunId
    $env:IMPLEMENTATION = $Implementation
    $env:ARRIVAL_MODE = $ArrivalMode
    $env:LOAD_SCENARIO = $LoadScenario
    $env:ACCOUNTING_MODE = $AccountingMode
    $env:INITIAL_ACTIVE_USERS = [string]$effectiveInitialActiveUsers
    $env:ACTIVATION_STEP_USERS = [string]$effectiveActivationStepUsers
    $env:ACTIVATION_INTERVAL_MS = [string]$ActivationIntervalMs
    $env:RECONNECT_DELAY_MS = [string]$ReconnectDelayMs
    $env:STOP_USER_ON_TRUE = if ($AccountingMode -eq "corrected" -or $LoadScenario -eq "reconnect-ramp") { "false" } else { "true" }
    $env:AUTH_TOKENS_PATH = $privateTokenPath
    Remove-Item Env:AUTH_TOKEN -ErrorAction SilentlyContinue
    $env:RESULT_PATH = Join-Path $runDirectory "client-results.json"
    $env:PROGRESS_PATH = Join-Path $runDirectory "client-progress.jsonl"
    $env:MOCK_METRICS_URL = "$mockBaseUrl/__metrics"
    $env:DRAIN_OBSERVATION_SECONDS = [string]$DrainObservationSeconds
    $env:LOAD_STOP_MOCK_METRICS_PATH = Join-Path $runDirectory "load-stop-mock-metrics.json"
    $env:MOCK_DRAIN_PATH = Join-Path $runDirectory "mock-drain.jsonl"
    $env:MOCK_DRAIN_SUMMARY_PATH = Join-Path $runDirectory "mock-drain-summary.json"

$monitorProcess = $null
$monitorDurationSeconds = [int][Math]::Ceiling($DurationMs / 1000) + 2
$jfrContainerFile = "/tmp/$RunId.jfr"
$serverContainerId = Get-ServerContainerId
if ([string]::IsNullOrWhiteSpace($serverContainerId)) {
    throw "Running server container was not found: $ServerService"
}
$applicationLogCapture = [ordered]@{
    attempted = $false
    succeeded = $false
    capturedAt = $null
    exitCode = $null
    applicationLog = "application-container.log"
    phaseTrace = "mvc-phase-trace.jsonl"
    phaseCount = 0
    phaseTraceJsonlValid = $false
    phaseParseFailures = 0
}
$observability = $null
if ($observabilityEnabled) {
    if ($jfrEnabled) {
            $jfrName = "doeng_" + ($RunId -replace "[^A-Za-z0-9_]", "_")
            $jfrStartArguments = @(
                "1", "JFR.start", "name=$jfrName", "settings=profile",
                "maxsize=64m"
            )
            $jfrStartOutput = & docker exec $serverContainerId env -u JAVA_TOOL_OPTIONS jcmd @jfrStartArguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                $jfrStartOutput | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-start.stderr.log")
                throw "JFR start failed"
            }
            $jfrStartedAt = Get-Date
            $jfrStartCommandText = "jcmd " + ($jfrStartArguments -join " ")
            [ordered]@{
                containerId = $serverContainerId
                command = $jfrStartCommandText
                startCommand = $jfrStartCommandText
                startedAt = $jfrStartedAt.ToUniversalTime().ToString("o")
            } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-command.json")
        }
        if ($containerMonitorEnabled) {
            $monitorArguments = @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "monitor-containers.ps1"),
                "-RunId", $RunId, "-ServerService", $ServerService, "-ComposeProject", $ComposeProject,
                "-ComposeFiles"
            ) + @($composeFiles -join ",") + @(
                "-DurationSeconds", [string]$monitorDurationSeconds, "-IntervalSeconds", "1", "-NodeCommand", $NodeCommand,
                "-SkipApplicationSnapshot", [string]$SkipApplicationSnapshot,
                "-SkipMockMetrics", [string]$SkipMockMetrics
            )
            $monitorProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $monitorArguments -WorkingDirectory $repositoryRoot -WindowStyle Hidden `
                -RedirectStandardOutput (Join-Path $runDirectory "monitor.stdout.log") `
                -RedirectStandardError (Join-Path $runDirectory "monitor.stderr.log") -PassThru
            Start-Sleep -Seconds 1
        }
    }

    $clientStdout = & $NodeCommand (Join-Path $repositoryRoot "experiment\load\mission-load.js")
    if ($LASTEXITCODE -ne 0) { throw "Load driver failed" }
    $clientStdout | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "client-summary.stdout.json")

    if ($observabilityEnabled) {
        $monitorStatus = $null
        if ($containerMonitorEnabled) {
            $monitorDeadline = (Get-Date).AddSeconds($monitorDurationSeconds + 10)
            while (-not $monitorProcess.HasExited -and (Get-Date) -lt $monitorDeadline) {
                Start-Sleep -Milliseconds 500
                $monitorProcess.Refresh()
            }
            if (-not $monitorProcess.HasExited) {
                Stop-Process -Id $monitorProcess.Id
                throw "Container monitor exceeded its deadline"
            }
            $monitorProcess.Refresh()
            $monitorStatusPath = Join-Path $runDirectory "monitor-process-status.json"
            if (-not (Test-Path -LiteralPath $monitorStatusPath)) {
                throw "Container monitor completed without its status file"
            }
            $monitorStatus = Get-Content -Raw -LiteralPath $monitorStatusPath | ConvertFrom-Json
            if (-not $monitorStatus.success -or $monitorStatus.nodeExitCode -ne 0) {
                throw "Container monitor reported an unsuccessful completion"
            }
            $monitorSummaryPath = Join-Path $runDirectory "container-monitor-summary.json"
            if (-not (Test-Path -LiteralPath $monitorSummaryPath)) {
                throw "Container monitor completed without its summary"
            }
            $monitorSummary = Get-Content -Raw -LiteralPath $monitorSummaryPath | ConvertFrom-Json
            if ($monitorSummary.applicationFailures -gt 0 -or
                $monitorSummary.databaseFailures -gt 0) {
                throw "Lightweight monitor recorded collection failures"
            }
            & $NodeCommand (Join-Path $PSScriptRoot "render-timeseries.js") `
                "--run-directory" $runDirectory
            if ($LASTEXITCODE -ne 0) {
                throw "Timeseries rendering failed"
            }
        }
        $jfrValidation = $null
        $jfrRecordingPath = $null
        if ($jfrEnabled) {
            $jfrStopArguments = @(
                "1", "JFR.stop", "name=$jfrName", "filename=$jfrContainerFile"
            )
            $jfrStopCommandText = "jcmd " + ($jfrStopArguments -join " ")
            $jfrStoppedAt = Get-Date
            [ordered]@{
                containerId = $serverContainerId
                stopCommand = $jfrStopCommandText
                stoppedAt = $jfrStoppedAt.ToUniversalTime().ToString("o")
            } | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-stop-command.json")

            $jfrStopOutput = & docker exec $serverContainerId env -u JAVA_TOOL_OPTIONS jcmd @jfrStopArguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                $jfrStopOutput | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-stop.stderr.log")
                throw "JFR stop failed"
            }
            $jfrStopOutput | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-stop.stdout.log")
            $jfrCompleted = $true

            $jfrSummaryPath = Join-Path $runDirectory "jfr-summary.txt"
            & docker exec $serverContainerId env -u JAVA_TOOL_OPTIONS jfr summary $jfrContainerFile |
                Set-Content -Encoding UTF8 -LiteralPath $jfrSummaryPath
            if ($LASTEXITCODE -ne 0) { throw "JFR summary failed after JFR stop" }

            $jfrSourceSizeText = (@(& docker exec $serverContainerId sh -c "wc -c < '$jfrContainerFile'" 2>$null) -join "").Trim()
            if ($jfrSourceSizeText -notmatch "^\d+$") { throw "JFR source size could not be read" }
            [long]$jfrSourceBytes = $jfrSourceSizeText
            if ($jfrSourceBytes -le 0) { throw "JFR source file is empty" }

            $jfrRecordingPath = Join-Path $runDirectory "jvm-recording.jfr"
            & docker cp "$($serverContainerId):$jfrContainerFile" $jfrRecordingPath
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $jfrRecordingPath)) {
                throw "JFR recording copy failed"
            }
            [long]$jfrCopiedBytes = (Get-Item -LiteralPath $jfrRecordingPath).Length
            if ($jfrCopiedBytes -ne $jfrSourceBytes) { throw "JFR copy size does not match the completed source" }

            $jfrValidation = [ordered]@{
                completed = $jfrCompleted
                startCommand = $jfrStartCommandText
                stopCommand = $jfrStopCommandText
                stopSucceeded = $true
                sourceBytes = $jfrSourceBytes
                copiedBytes = $jfrCopiedBytes
                summaryFile = "jfr-summary.txt"
                valid = $true
            }
            $jfrValidation | ConvertTo-Json -Depth 4 |
                Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "jfr-validation.json")
        }
        $observability = [ordered]@{
            enabled = $true
            containerMonitorEnabled = $containerMonitorEnabled
            applicationSnapshotSkipped = $containerMonitorEnabled -and $SkipApplicationSnapshot -eq 1
            mockContinuousPollingSkipped = $containerMonitorEnabled -and $SkipMockMetrics -eq 1
            monitorExitCode = if ($containerMonitorEnabled) { [int]$monitorStatus.nodeExitCode } else { $null }
            monitorSummaryExists = $containerMonitorEnabled -and (Test-Path -LiteralPath (Join-Path $runDirectory "container-monitor-summary.json"))
            applicationMetricsExists = $containerMonitorEnabled -and (Test-Path -LiteralPath (Join-Path $runDirectory "application-metrics.jsonl"))
            databaseMetricsExists = $containerMonitorEnabled -and (Test-Path -LiteralPath (Join-Path $runDirectory "database-metrics.jsonl"))
            applicationLogCapture = $applicationLogCapture
            jfrEnabled = $jfrEnabled
            jfrExists = $jfrEnabled -and (Test-Path -LiteralPath $jfrRecordingPath)
            jfrValidated = $jfrEnabled -and $jfrValidation.valid
        }
    }

    $loadStopMockMetricsPath = Join-Path $runDirectory "load-stop-mock-metrics.json"
    $mockDrainPath = Join-Path $runDirectory "mock-drain.jsonl"
    $mockDrainSummaryPath = Join-Path $runDirectory "mock-drain-summary.json"
    $loadStopMockMetrics = if (Test-Path -LiteralPath $loadStopMockMetricsPath) { Get-Content -Raw -LiteralPath $loadStopMockMetricsPath | ConvertFrom-Json } else { $null }
    $mockDrain = if (Test-Path -LiteralPath $mockDrainSummaryPath) { Get-Content -Raw -LiteralPath $mockDrainSummaryPath | ConvertFrom-Json } else { $null }
    $drainArtifactsPresent = $DrainObservationSeconds -eq 0 -or (
        $null -ne $loadStopMockMetrics -and $loadStopMockMetrics.ok -and
        $null -ne $mockDrain -and $mockDrain.sampleCount -eq ($DrainObservationSeconds + 1) -and
        (Test-Path -LiteralPath $mockDrainPath)
    )

    $databaseAfter = Get-DatabaseState -Users @($preparedUsers.users)
    $databaseAfter | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "db-after.json")
    $storageAfter = Invoke-RestMethod -Uri "$mockBaseUrl/__storage"
    $storageAfter | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "storage-after.json")
    $mockRequests = Invoke-RestMethod -Uri "$mockBaseUrl/__requests"
    $mockRequests | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "mock-requests.json")
    $mockMetrics = Invoke-RestMethod -Uri "$mockBaseUrl/__metrics"
    $mockMetrics | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "mock-metrics-after.json")

    $applicationLogCapture = Capture-ApplicationDiagnostics -ContainerId $serverContainerId

    $clientResult = Get-Content -Raw -LiteralPath (Join-Path $runDirectory "client-results.json") | ConvertFrom-Json
    $missionCompletions = @(Get-MissionCompletions -Users @($preparedUsers.users))
    $missionCompletions | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "mission-completions.json")
    $requests = @($clientResult.requests)
    $storageObjects = @($storageAfter.objects)
    $storedKeys = @($storageObjects | ForEach-Object { $_.key })
    $pictureKeys = @($databaseAfter.pictures | ForEach-Object { $_.image })
    $trueResponses = @($requests | Where-Object { $_.status -eq 200 -and $_.body.Trim().ToLower() -eq "true" })
    $controlledRejectedRequests = @($requests | Where-Object { $_.status -eq 503 })
    $uncontrolledFailedRequests = @($requests | Where-Object { $_.status -ne 200 -and $_.status -ne 503 })
    $allUsersCreatedOneProgressAndPicture = @($databaseAfter.users | Where-Object {
        $_.progressCount -ne 1 -or $_.pictureCount -ne 1
    }).Count -eq 0
    $allPicturesStored = @($pictureKeys | Where-Object { $_ -notin $storedKeys }).Count -eq 0
    $allObjectsMatchFixture = @($storageObjects | Where-Object {
        [long]$_.bytes -ne [long]$runConfig.fixture.bytes -or $_.sha256 -ne $runConfig.fixture.sha256
    }).Count -eq 0
    $allUsersCompletedAtLeastOneMission = @($databaseAfter.users | Where-Object {
        $_.progressCount -ne 1 -or $_.pictureCount -lt 1
    }).Count -eq 0
    $trueResponseCount = $trueResponses.Count
    $storedObjectIncrease = $storageObjects.Count - $storageBefore.objects.Count
    $completionKeys = @($missionCompletions | ForEach-Object { $_.objectKey })
    $pictureKeysMatchCompletions = $pictureKeys.Count -eq $missionCompletions.Count -and @($pictureKeys | Where-Object { $_ -notin $completionKeys }).Count -eq 0
    $storageKeysMatchCompletions = $storedObjectIncrease -eq $missionCompletions.Count -and @($storedKeys | Where-Object { $_ -notin $completionKeys }).Count -eq 0
    $reconnectRampAssertions = [ordered]@{
        allPreparedUsersCompletedAtLeastOneMission = $allUsersCompletedAtLeastOneMission
        oneProgressPerPreparedUser = @($databaseAfter.users | Where-Object { $_.progressCount -ne 1 }).Count -eq 0
        picturesMatchUniqueMissionCompletions = $pictureKeysMatchCompletions
        storedObjectsMatchUniqueMissionCompletions = $storageKeysMatchCompletions
        atLeastOneReentry = @($requests | Where-Object { $_.missionNumber -ge 2 }).Count -gt 0
    }
    $assertions = [ordered]@{
        preRunMockIdle = $preRunMockIdle
        loadStopAndDrainArtifactsPresent = $drainArtifactsPresent
        userCountMatchesVu = @($preparedUsers.users).Count -eq $ActiveMissions
        loginCompletedBeforeMeasurement = $preparedUsers.auth.loginCompleted -eq $ActiveMissions -and $preparedUsers.auth.loginFailures -eq 0
        strictAuthEnabled = $mockMetrics.strictAuth -and $mockMetrics.authIssuedTokens -eq $ActiveMissions
        distinctAuthorizations = $clientResult.summary.authorizationMode -eq "per-vu-token-file" -and $clientResult.summary.distinctAuthorizationCount -eq $ActiveMissions
        accountingContract = if ($AccountingMode -eq "corrected") { $clientResult.summary.accounting.valid -eq $true } else { $true }
        oneTrueResponsePerVu = if ($AccountingMode -eq "corrected" -or $OutcomeMode -eq "controlled-admission") { $trueResponseCount -ge 0 } elseif ($LoadScenario -eq "single-success") { $requests.Count -eq $ActiveMissions -and $trueResponses.Count -eq $ActiveMissions } else { $trueResponseCount -ge $ActiveMissions }
        oneProgressAndPicturePerVu = if ($OutcomeMode -eq "controlled-admission") { $allPicturesStored } elseif ($LoadScenario -eq "single-success") { $allUsersCreatedOneProgressAndPicture } else { $allUsersCompletedAtLeastOneMission }
        oneStoredObjectPerVu = if ($OutcomeMode -eq "controlled-admission") { $storageKeysMatchCompletions } elseif ($LoadScenario -eq "single-success") { $storedObjectIncrease -eq $ActiveMissions } else { $storageKeysMatchCompletions }
        pictureKeysMatchStorage = if ($OutcomeMode -eq "controlled-admission") { $allPicturesStored -and $pictureKeysMatchCompletions } elseif ($LoadScenario -eq "single-success") { $pictureKeys.Count -eq $ActiveMissions -and $allPicturesStored } else { $pictureKeysMatchCompletions -and $allPicturesStored }
        reconnectRamp = if ($OutcomeMode -eq "controlled-admission") { $allPicturesStored -and $storageKeysMatchCompletions } elseif ($LoadScenario -eq "reconnect-ramp") { -not (@($reconnectRampAssertions.Values) -contains $false) } else { $true }
        storedObjectsMatchFixture = $allObjectsMatchFixture
        observabilityArtifactsPresent = -not $observabilityEnabled -or (
            (
                -not $observability.jfrEnabled -or (
                    $observability.jfrExists -and
                    $observability.jfrValidated
                )
            ) -and
            (
                -not $observability.containerMonitorEnabled -or (
                    $observability.monitorExitCode -eq 0 -and
                    $observability.monitorSummaryExists -and
                    $observability.applicationMetricsExists -and
                    $observability.databaseMetricsExists
                )
            )
        )
    }
    $verificationValidity = Get-VerificationValidity $assertions
    $executionValidity = $verificationValidity.executionValidity
    $applicationOutcomePassed = $verificationValidity.applicationOutcomePassed
    $endOfLoadInFlight = if ($null -ne $loadStopMockMetrics -and $null -ne $loadStopMockMetrics.metrics) {
        [ordered]@{
            aiInFlight = $loadStopMockMetrics.metrics.aiInFlight
            storageInFlight = $loadStopMockMetrics.metrics.storageInFlight
        }
    } else { $null }
    $verification = [ordered]@{
        runId = $RunId
        assertions = $assertions
        executionAssertions = $verificationValidity.executionAssertions
        executionValidity = $executionValidity
        applicationOutcomeAssertions = $verificationValidity.applicationOutcomeAssertions
        applicationOutcomePassed = $applicationOutcomePassed
        valid = $executionValidity -eq "VALID"
        measurementValidity = $executionValidity
        databaseAfter = $databaseAfter
        storageObjectCount = $storageObjects.Count
        clientSummary = $clientResult.summary
        mockMetrics = $mockMetrics
        systemOutcome = [ordered]@{
            endOfLoadInFlight = $endOfLoadInFlight
            drain = $mockDrain
        }
        missionCompletionCount = $missionCompletions.Count
        reconnectRamp = if ($LoadScenario -eq "reconnect-ramp") { $reconnectRampAssertions } else { $null }
        outcome = [ordered]@{
            acceptedSuccess = $trueResponses.Count
            controlledRejected = $controlledRejectedRequests.Count
            uncontrolledFailed = $uncontrolledFailedRequests.Count
            status503 = @($requests | Where-Object { $_.status -eq 503 }).Count
        }
        applicationLogCapture = $applicationLogCapture
        observability = $observability
    }
    $verification | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "verification-summary.json")
    $verification | ConvertTo-Json -Depth 8
    if ($executionValidity -ne "VALID") { throw "Isolated VU execution verification failed" }
} finally {
    try {
        $diagnosticStatePath = Join-Path $runDirectory "server-container-state.json"
        $diagnosticLogPath = Join-Path $runDirectory "application-container.log"
        $diagnosticRecoveryNeeded =
            -not (Test-Path -LiteralPath $diagnosticStatePath) -or
            -not (Test-Path -LiteralPath $diagnosticLogPath) -or
            $null -eq $applicationLogCapture -or
            -not $applicationLogCapture.succeeded
        if ($diagnosticRecoveryNeeded) {
            $recoveryContainerId = $serverContainerId
            if ([string]::IsNullOrWhiteSpace($recoveryContainerId)) {
                $recoveryContainerId = Get-ServerContainerId -IncludeStopped
            }
            if (-not [string]::IsNullOrWhiteSpace($recoveryContainerId)) {
                $recoveredCapture = Capture-ApplicationDiagnostics -ContainerId $recoveryContainerId
                if ($null -eq $applicationLogCapture -or -not $applicationLogCapture.succeeded) {
                    $applicationLogCapture = $recoveredCapture
                }
            } else {
                "container lookup: server container was not found during diagnostic recovery" |
                    Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "application-diagnostic-recovery-error.txt")
            }
        }
    } catch {
        $_.Exception.Message |
            Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "application-diagnostic-recovery-error.txt")
    }
    Remove-Item -LiteralPath $privateTokenPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:AUTH_TOKENS_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:LOAD_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:ACCOUNTING_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:INITIAL_ACTIVE_USERS -ErrorAction SilentlyContinue
    Remove-Item Env:ACTIVATION_STEP_USERS -ErrorAction SilentlyContinue
    Remove-Item Env:ACTIVATION_INTERVAL_MS -ErrorAction SilentlyContinue
    Remove-Item Env:RECONNECT_DELAY_MS -ErrorAction SilentlyContinue
    Remove-Item Env:MOCK_METRICS_URL -ErrorAction SilentlyContinue
    Remove-Item Env:DRAIN_OBSERVATION_SECONDS -ErrorAction SilentlyContinue
    Remove-Item Env:LOAD_STOP_MOCK_METRICS_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:MOCK_DRAIN_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:MOCK_DRAIN_SUMMARY_PATH -ErrorAction SilentlyContinue
    foreach ($name in $configurationEnvironmentNames) {
        $previousValue = $previousConfigurationEnvironment[$name]
        if ($null -eq $previousValue) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $previousValue, "Process")
        }
    }
}
