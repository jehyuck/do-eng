param(
    [string]$ContractPath = "experiment/config/experiment-variable-contract.json",
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$contractFile = if ([System.IO.Path]::IsPathRooted($ContractPath)) {
    [System.IO.Path]::GetFullPath($ContractPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ContractPath))
}
$contract = Get-Content -Raw -LiteralPath $contractFile | ConvertFrom-Json
$requiredSections = @("load", "downstream", "application", "http", "database", "mvc", "jvm")
foreach ($section in $requiredSections) {
    if ($null -eq $contract.$section) { throw "Missing contract section: $section" }
}

$envMap = [ordered]@{
    APP_CPU = $contract.application.cpu
    APP_MEMORY = $contract.application.memory
    HTTP_MAX_CONNECTIONS = $contract.http.maxConnections
    HTTP_PENDING_MAX_COUNT = $contract.http.pendingMaxCount
    HTTP_CONNECT_TIMEOUT_MS = $contract.http.connectTimeoutMs
    HTTP_RESPONSE_TIMEOUT_MS = $contract.http.responseTimeoutMs
    HTTP_PENDING_ACQUIRE_TIMEOUT_MS = $contract.http.pendingAcquireTimeoutMs
    DB_POOL_MAX_SIZE = $contract.database.poolMaxSize
    MVC_MAX_THREADS = $contract.mvc.maxThreads
    JAVA_XMS = $contract.jvm.xms
    JAVA_XMX = $contract.jvm.xmx
    MOCK_AI_RESULT = ([string]$contract.downstream.aiResult).ToLowerInvariant()
    MOCK_AI_DELAY_MS = $contract.downstream.aiDelayMs
    MOCK_AI_STATUS = $contract.downstream.aiStatus
    MOCK_STORAGE_DELAY_MS = $contract.downstream.storageDelayMs
    MOCK_STORAGE_STATUS = $contract.downstream.storageStatus
}
$previous = @{}
foreach ($entry in $envMap.GetEnumerator()) {
    $previous[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
    if ($null -ne $entry.Value) { [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process") }
}
try {
    $composeFiles = @(
        (Join-Path $repositoryRoot "backend/docker-compose.experiment.yaml"),
        (Join-Path $repositoryRoot "experiment/compose/experiment-1-37-runtime.override.yml")
    )
    $rendered = & docker compose -p doeng-contract-validation @($composeFiles | ForEach-Object { @("-f", $_) }) config
    if ($LASTEXITCODE -ne 0) { throw "docker compose config failed" }
    $renderedText = @($rendered) -join [Environment]::NewLine
    $httpExpected = 'DOENG_HTTP_MAX_CONNECTIONS: "' + [string]$contract.http.maxConnections + '"'
    $dbExpected = 'DOENG_DB_POOL_MAX_SIZE: "' + [string]$contract.database.poolMaxSize + '"'
    $mvcExpected = 'DOENG_MVC_MAX_THREADS: "' + [string]$contract.mvc.maxThreads + '"'
    $aiExpected = 'MOCK_AI_DELAY_MS: "' + [string]$contract.downstream.aiDelayMs + '"'
    $storageExpected = 'MOCK_STORAGE_DELAY_MS: "' + [string]$contract.downstream.storageDelayMs + '"'
    $memoryBytes = $null
    if ($null -ne $contract.application.memory -and [string]$contract.application.memory -match '^(\d+(?:\.\d+)?)([mMgG])$') {
        $memoryBytes = [int64]([double]$matches[1] * $(if ($matches[2] -match '[gG]') { 1GB } else { 1MB }))
    }
    $checks = [ordered]@{
        appCpu = if ($null -eq $contract.application.cpu) { "COMPOSE_DEFAULT" } else { $renderedText -match [regex]::Escape("cpus: $($contract.application.cpu)") }
        appMemory = if ($null -eq $contract.application.memory) { "COMPOSE_DEFAULT" } else { $renderedText -match "mem_limit:\s+`"$memoryBytes`"" }
        httpMaxConnections = if ($null -eq $contract.http.maxConnections) { "COMPOSE_DEFAULT" } else { $renderedText -match [regex]::Escape($httpExpected) }
        dbPoolMaxSize = if ($null -eq $contract.database.poolMaxSize) { "COMPOSE_DEFAULT" } else { $renderedText -match [regex]::Escape($dbExpected) }
        mvcMaxThreads = if ($null -eq $contract.mvc.maxThreads) { "COMPOSE_DEFAULT" } else { $renderedText -match [regex]::Escape($mvcExpected) }
        mockAiDelay = $renderedText -match [regex]::Escape($aiExpected)
        mockStorageDelay = $renderedText -match [regex]::Escape($storageExpected)
    }
    $result = [ordered]@{
        validation = "PASS"
        workloadExecuted = $false
        contractPath = $contractFile
        composeFiles = $composeFiles
        resolvedContract = $contract
        composeChecks = $checks
    }
    $json = $result | ConvertTo-Json -Depth 10
    if ($OutputPath) {
        $absoluteOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repositoryRoot $OutputPath }
        New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteOutput) -Force | Out-Null
        $json | Set-Content -Encoding UTF8 -LiteralPath $absoluteOutput
    }
    $json
} finally {
    foreach ($entry in $previous.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
        }
    }
}
