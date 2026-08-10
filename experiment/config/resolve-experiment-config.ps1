param(
    [ValidateSet("WebFlux", "MVC400")]
    [string]$Implementation,
    [string]$ConfigPath = "experiment/config/experiment-variable-contract.json",
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$configFile = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    [System.IO.Path]::GetFullPath($ConfigPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ConfigPath))
}
if (-not (Test-Path -LiteralPath $configFile)) { throw "Configuration file not found: $configFile" }
$config = Get-Content -Raw -LiteralPath $configFile | ConvertFrom-Json

function Require-Positive([string]$name, [object]$value) {
    if ($null -eq $value -or [int]$value -lt 1) { throw "$name must be a positive integer" }
    return [int]$value
}
function Require-Status([string]$name, [object]$value) {
    $status = Require-Positive $name $value
    if ($status -lt 100 -or $status -gt 599) { throw "$name must be a valid HTTP status" }
    return $status
}
function Get-Value($section, [string]$name, $fallback) {
    $value = $section.$name
    if ($null -eq $value) { return $fallback }
    return $value
}

$load = $config.load
$downstream = $config.downstream
$application = $config.application
$http = $config.http
$database = $config.database
$mvc = $config.mvc
$jvm = $config.jvm
$activeMissions = Require-Positive "load.activeMissions" (Get-Value $load "activeMissions" 2)
$loadScenario = [string](Get-Value $load "loadScenario" "single-success")
$accountingMode = [string](Get-Value $load "accountingMode" "legacy")
$arrivalMode = [string](Get-Value $load "arrivalMode" "aligned")
if ($loadScenario -notin @("single-success", "reconnect-ramp")) { throw "load.loadScenario is invalid" }
if ($accountingMode -notin @("legacy", "corrected")) { throw "load.accountingMode is invalid" }
if ($arrivalMode -notin @("aligned", "staggered")) { throw "load.arrivalMode is invalid" }
$intervalMs = Require-Positive "load.intervalMs" (Get-Value $load "intervalMs" 3000)
$durationMs = Require-Positive "load.durationMs" (Get-Value $load "durationMs" 3500)
$requestTimeoutMs = Require-Positive "load.requestTimeoutMs" (Get-Value $load "requestTimeoutMs" 10000)
$activationIntervalMs = Require-Positive "load.activationIntervalMs" (Get-Value $load "activationIntervalMs" 3000)
$reconnectDelayMs = Require-Positive "load.reconnectDelayMs" (Get-Value $load "reconnectDelayMs" 3000)
$initialActiveUsers = [int](Get-Value $load "initialActiveUsers" 0)
$activationStepUsers = [int](Get-Value $load "activationStepUsers" 0)
if ($loadScenario -eq "reconnect-ramp") {
    if ($initialActiveUsers -lt 1 -or $initialActiveUsers -gt $activeMissions) { throw "load.initialActiveUsers is invalid for reconnect-ramp" }
    if ($activationStepUsers -lt 1) { throw "load.activationStepUsers is invalid for reconnect-ramp" }
} else {
    $initialActiveUsers = $activeMissions
    $activationStepUsers = $activeMissions
}
$warmupMs = [int](Get-Value $load "warmupMs" 0)
$drainSeconds = [int](Get-Value $load "drainObservationSeconds" 0)
if ($warmupMs -lt 0 -or $drainSeconds -lt 0) { throw "load.warmupMs and load.drainObservationSeconds must be non-negative" }
$aiResult = [bool](Get-Value $downstream "aiResult" $true)
$aiDelayMs = Require-Positive "downstream.aiDelayMs" (Get-Value $downstream "aiDelayMs" 500)
$aiStatus = Require-Status "downstream.aiStatus" (Get-Value $downstream "aiStatus" 200)
$storageDelayMs = Require-Positive "downstream.storageDelayMs" (Get-Value $downstream "storageDelayMs" 100)
$storageStatus = Require-Status "downstream.storageStatus" (Get-Value $downstream "storageStatus" 200)

$composeEnvironment = [ordered]@{
    MOCK_AI_RESULT = $aiResult.ToString().ToLowerInvariant()
    MOCK_AI_DELAY_MS = $aiDelayMs
    MOCK_AI_STATUS = $aiStatus
    MOCK_STORAGE_DELAY_MS = $storageDelayMs
    MOCK_STORAGE_STATUS = $storageStatus
}
$source = [ordered]@{}
foreach ($item in @(
    @("APP_CPU", $application.cpu, "application.cpu"),
    @("APP_MEMORY", $application.memory, "application.memory"),
    @("HTTP_MAX_CONNECTIONS", $http.maxConnections, "http.maxConnections"),
    @("HTTP_PENDING_MAX_COUNT", $http.pendingMaxCount, "http.pendingMaxCount"),
    @("HTTP_CONNECT_TIMEOUT_MS", $http.connectTimeoutMs, "http.connectTimeoutMs"),
    @("HTTP_RESPONSE_TIMEOUT_MS", $http.responseTimeoutMs, "http.responseTimeoutMs"),
    @("HTTP_PENDING_ACQUIRE_TIMEOUT_MS", $http.pendingAcquireTimeoutMs, "http.pendingAcquireTimeoutMs"),
    @("DB_POOL_MAX_SIZE", $database.poolMaxSize, "database.poolMaxSize"),
    @("MVC_MAX_THREADS", $mvc.maxThreads, "mvc.maxThreads"),
    @("JAVA_XMS", $jvm.xms, "jvm.xms"),
    @("JAVA_XMX", $jvm.xmx, "jvm.xmx")
)) {
    $envName = $item[0]; $value = $item[1]; $field = $item[2]
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { $composeEnvironment[$envName] = [string]$value; $source[$field] = "config-file" } else { $source[$field] = "compose-default" }
}
$resolved = [ordered]@{
    contractVersion = if ($null -ne $config.contractVersion) { $config.contractVersion } else { 1 }
    implementation = $Implementation
    configPath = $configFile
    load = [ordered]@{
        scenario = $loadScenario; activeMissions = $activeMissions; intervalMs = $intervalMs; durationMs = $durationMs; requestTimeoutMs = $requestTimeoutMs; warmupMs = $warmupMs; arrivalMode = $arrivalMode; initialActiveUsers = $initialActiveUsers; activationStepUsers = $activationStepUsers; activationIntervalMs = $activationIntervalMs; reconnectDelayMs = $reconnectDelayMs; drainObservationSeconds = $drainSeconds
    }
    downstream = [ordered]@{ aiResult = $aiResult; aiDelayMs = $aiDelayMs; aiStatus = $aiStatus; storageDelayMs = $storageDelayMs; storageStatus = $storageStatus }
    application = [ordered]@{ cpu = $application.cpu; memory = $application.memory }
    http = [ordered]@{ maxConnections = $http.maxConnections; pendingMaxCount = $http.pendingMaxCount; connectTimeoutMs = $http.connectTimeoutMs; responseTimeoutMs = $http.responseTimeoutMs; pendingAcquireTimeoutMs = $http.pendingAcquireTimeoutMs }
    database = [ordered]@{ poolMaxSize = $database.poolMaxSize }
    mvc = [ordered]@{ maxThreads = $mvc.maxThreads }
    jvm = [ordered]@{ xms = $jvm.xms; xmx = $jvm.xmx }
    source = $source
    composeEnvironment = $composeEnvironment
    loadEnvironment = [ordered]@{
        ACTIVE_MISSIONS = $activeMissions; LOAD_SCENARIO = $loadScenario; ACCOUNTING_MODE = $accountingMode; INTERVAL_MS = $intervalMs; DURATION_MS = $durationMs; REQUEST_TIMEOUT_MS = $requestTimeoutMs; ARRIVAL_MODE = $arrivalMode; INITIAL_ACTIVE_USERS = $initialActiveUsers; ACTIVATION_STEP_USERS = $activationStepUsers; ACTIVATION_INTERVAL_MS = $activationIntervalMs; RECONNECT_DELAY_MS = $reconnectDelayMs; DRAIN_OBSERVATION_SECONDS = $drainSeconds
    }
}
$json = $resolved | ConvertTo-Json -Depth 10
if ($OutputPath) {
    $outputFile = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repositoryRoot $OutputPath }
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null
    $json | Set-Content -Encoding UTF8 -LiteralPath $outputFile
}
$json
