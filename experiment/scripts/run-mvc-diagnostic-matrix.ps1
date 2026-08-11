param(
    [string]$CasesPath = "experiment\config\mvc-diagnostic-cases.json",
    [string]$ResultsRoot = "experiment\results",
    [string]$ComposeProjectPrefix = "doeng-mvcdiag",
    [string]$NodeCommand = "node",
    [switch]$Execute
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (-not [IO.Path]::IsPathRooted($CasesPath)) { $CasesPath = Join-Path $repositoryRoot $CasesPath }
if (-not [IO.Path]::IsPathRooted($ResultsRoot)) { $ResultsRoot = Join-Path $repositoryRoot $ResultsRoot }
$manifest = Get-Content -Raw -LiteralPath $CasesPath | ConvertFrom-Json
$composeFile = Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml"
$casePlan = @($manifest.topologyLadder | ForEach-Object {
    $case = $_
    [ordered]@{
        id = $case.id
        kind = "TOPOLOGY"
        mode = $case.mode
        payload = $case.payload
        aiDelayMs = if ($null -ne $case.aiDelayMs) { $case.aiDelayMs } else { $manifest.defaults.aiDelayMs }
        storageDelayMs = if ($null -ne $case.storageDelayMs) { $case.storageDelayMs } else { $manifest.defaults.storageDelayMs }
        intervalMs = $manifest.defaults.intervalMs
        requestTimeoutMs = $manifest.defaults.requestTimeoutMs
    }
}) + @($manifest.boundaryMatrix | ForEach-Object {
    $case = $_
    [ordered]@{
        id = $case.id
        kind = "BOUNDARY"
        mode = "FULL"
        payload = "REAL"
        aiDelayMs = if ($null -ne $case.aiDelayMs) { $case.aiDelayMs } else { $manifest.defaults.aiDelayMs }
        storageDelayMs = $manifest.defaults.storageDelayMs
        intervalMs = if ($null -ne $case.intervalMs) { $case.intervalMs } else { $manifest.defaults.intervalMs }
        requestTimeoutMs = if ($null -ne $case.requestTimeoutMs) { $case.requestTimeoutMs } else { $manifest.defaults.requestTimeoutMs }
    }
})

$planPath = Join-Path $ResultsRoot "MVC-DIAG-matrix-plan.json"
New-Item -ItemType Directory -Force -Path $ResultsRoot | Out-Null
$plan = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    cases = $casePlan
    readinessGate = [ordered]@{
        stableWindowSeconds = 10
        maxWaitSeconds = 120
        loadAllowedOnlyAfter = @("CONTAINER_RUNNING", "LIVENESS_UP", "READINESS_UP", "MAIN_HTTP_CANARY_PASS", "MOCK_READY_AND_IDLE", "APPLICATION_IDLE", "STABLE_WINDOW")
    }
    executed = $false
}
$plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
if (-not $Execute) {
    Write-Output "MATRIX_PLAN_ONLY: $planPath"
    exit 0
}

function Get-CaseClassification($case) {
    $resultPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($case.id)") "client-results.json"
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "Missing result for $($case.id)" }
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    $successRate = if ($result.started -gt 0) { [double]$result.http200 / $result.started } else { 0 }
    $timeoutRate = if ($result.started -gt 0) { [double]$result.timeout / $result.started } else { 1 }
    if ($successRate -ge $manifest.classification.stable.successMin -and $timeoutRate -le $manifest.classification.stable.timeoutMax) { return "STABLE" }
    if ($successRate -ge $manifest.classification.degraded.successMin -and $successRate -lt $manifest.classification.degraded.successMaxExclusive) { return "DEGRADED" }
    return "COLLAPSE"
}

function Invoke-Case($case) {
    $project = "$ComposeProjectPrefix-$($case.id.ToLowerInvariant())"
    $caseDir = Join-Path $ResultsRoot "MVC-DIAG-$($case.id)"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $env:MOCK_AI_DELAY_MS = [string]$case.aiDelayMs
    $env:MOCK_STORAGE_DELAY_MS = [string]$case.storageDelayMs
    $env:APP_CPU = [string]$manifest.defaults.appCpu
    $env:APP_MEMORY = [string]$manifest.defaults.appMemory
    $env:DOENG_MVC_MAX_THREADS = [string]$manifest.defaults.mvcMaxThreads
    $env:DOENG_HTTP_MAX_CONNECTIONS = [string]$manifest.defaults.httpMaxConnections
    $env:DOENG_DB_POOL_MAX_SIZE = [string]$manifest.defaults.dbPoolMaxSize
    docker compose -p $project -f $composeFile up -d mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "compose up failed for $($case.id)" }
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "wait-mvc-readiness.ps1") `
            -ComposeProject $project -ServerService mvc -OutputPath (Join-Path $caseDir "startup-gate.json")
        if ($LASTEXITCODE -ne 0) { throw "STARTUP_GATE: FAIL for $($case.id)" }
        $observer = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "observe-mvc-diagnostic.ps1"),
            "-ComposeProject", $project, "-ServerService", "mvc", "-DurationSeconds", [string]([math]::Ceiling($manifest.defaults.durationMs / 1000)),
            "-OutputPath", (Join-Path $caseDir "observer.jsonl")
        ) -PassThru -WindowStyle Hidden
        $target = if ($case.mode -eq "FULL") { "http://127.0.0.1:8002/game/face" } else { "http://127.0.0.1:8002/experiment/mvc-probe" }
        $env:TARGET_URL = $target
        $env:MODE = [string]$case.mode
        $env:PAYLOAD_PROFILE = [string]$case.payload
        $env:ACTIVE_USERS = [string]$manifest.defaults.activeUsers
        $env:INTERVAL_MS = [string]$case.intervalMs
        $env:DURATION_MS = [string]$manifest.defaults.durationMs
        $env:REQUEST_TIMEOUT_MS = [string]$case.requestTimeoutMs
        $env:EXPERIMENT_RUN_ID = "MVC-DIAG-$($case.id)"
        $env:RESULT_PATH = Join-Path $caseDir "client-results.json"
        $env:PROGRESS_PATH = Join-Path $caseDir "client-progress.jsonl"
        & $NodeCommand (Join-Path $repositoryRoot "experiment\load\mvc-diagnostic-load.js")
        if ($LASTEXITCODE -ne 0) { throw "diagnostic load failed for $($case.id)" }
        if (-not $observer.HasExited) { $observer.WaitForExit() }
    } finally {
        docker compose -p $project -f $composeFile down --remove-orphans
    }
}

foreach ($case in @($casePlan | Where-Object kind -eq "TOPOLOGY")) {
    Invoke-Case $case
    $plan.executed = $true
    $plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
    if ((Get-CaseClassification $case) -ne "STABLE") { break }
}
foreach ($case in @($casePlan | Where-Object kind -eq "BOUNDARY")) {
    Invoke-Case $case
    $plan.executed = $true
    $plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
}
