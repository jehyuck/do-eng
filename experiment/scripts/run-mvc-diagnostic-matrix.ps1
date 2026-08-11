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

$imageContractProject = "$ComposeProjectPrefix-image-contract"
docker compose -p $imageContractProject -f $composeFile build mvc experiment-mock
if ($LASTEXITCODE -ne 0) { throw "Immutable image build failed" }
$mvcContractIds = @(& docker compose -p $imageContractProject -f $composeFile images -q mvc 2>$null)
$mockContractIds = @(& docker compose -p $imageContractProject -f $composeFile images -q experiment-mock 2>$null)
$matrixImageContract = [ordered]@{
    builtAt = (Get-Date).ToUniversalTime().ToString("o")
    project = $imageContractProject
    mvcImageId = if ($mvcContractIds.Count -gt 0) { ([string]$mvcContractIds[0]).Trim() } else { "" }
    mockImageId = if ($mockContractIds.Count -gt 0) { ([string]$mockContractIds[0]).Trim() } else { "" }
}
if ([string]::IsNullOrWhiteSpace($matrixImageContract.mvcImageId) -or
    [string]::IsNullOrWhiteSpace($matrixImageContract.mockImageId)) {
    throw "Immutable image IDs could not be resolved"
}
$matrixImageContract | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ResultsRoot "matrix-image-contract.json")

function Get-CaseClassification($case) {
    $resultPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($case.id)") "client-results.json"
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "Missing result for $($case.id)" }
    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    $successRate = if ($result.started -gt 0) { [double]$result.http200 / $result.started } else { 0 }
    $timeoutRate = if ($result.started -gt 0) { [double]$result.timeout / $result.started } else { 1 }
    $http4xxRate = if ($result.started -gt 0) { [double]$result.http4xx / $result.started } else { 0 }
    if ($http4xxRate -gt 0) { return "INVALID_CONFIGURATION" }
    if ($successRate -ge $manifest.classification.stable.successMin -and $timeoutRate -le $manifest.classification.stable.timeoutMax) { return "STABLE" }
    if ($successRate -ge $manifest.classification.degraded.successMin -and $successRate -lt $manifest.classification.degraded.successMaxExclusive) { return "DEGRADED" }
    return "COLLAPSE"
}

function Get-Container($project, $service) {
    $ids = @(& docker compose -p $project -f $composeFile ps -q $service 2>$null |
        ForEach-Object { $id = ([string]$_).Trim(); if ($id) { $id } })
    if ($ids.Count -ne 1) { throw "Expected one $service container for $project" }
    $raw = @(& docker inspect $ids[0] 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "docker inspect failed for $service" }
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)[0]
}

function Write-RuntimeContract($project, $caseDir) {
    $container = Get-Container $project "mvc"
    $environment = @{}
    foreach ($entry in @($container.Config.Env)) {
        $parts = $entry -split "=", 2
        if ($parts.Count -eq 2) { $environment[$parts[0]] = $parts[1] }
    }
    $javaOptions = [string]$environment.JAVA_TOOL_OPTIONS
    $contract = [ordered]@{
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        containerId = $container.Id
        imageId = $container.Image
        nanoCpus = $container.HostConfig.NanoCpus
        memory = $container.HostConfig.Memory
        environment = [ordered]@{
            MVC_MAX_THREADS = $environment.MVC_MAX_THREADS
            HTTP_MAX_CONNECTIONS = $environment.HTTP_MAX_CONNECTIONS
            DB_POOL_MAX_SIZE = $environment.DB_POOL_MAX_SIZE
            JAVA_TOOL_OPTIONS = $javaOptions
        }
        expected = [ordered]@{
            nanoCpus = 2000000000
            memory = 3221225472
            MVC_MAX_THREADS = "400"
            HTTP_MAX_CONNECTIONS = "400"
            DB_POOL_MAX_SIZE = "10"
            javaXms = "512m"
            javaXmx = "2048m"
        }
    }
    $contract.pass = $contract.nanoCpus -eq $contract.expected.nanoCpus -and
        $contract.memory -eq $contract.expected.memory -and
        $contract.environment.MVC_MAX_THREADS -eq $contract.expected.MVC_MAX_THREADS -and
        $contract.environment.HTTP_MAX_CONNECTIONS -eq $contract.expected.HTTP_MAX_CONNECTIONS -and
        $contract.environment.DB_POOL_MAX_SIZE -eq $contract.expected.DB_POOL_MAX_SIZE -and
        $javaOptions -match "-Xms512m" -and $javaOptions -match "-Xmx2048m"
    $contract | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $caseDir "runtime-contract.json")
    if (-not $contract.pass) { throw "RUNTIME_CONTRACT: FAIL for $caseDir" }
    return $container.Image
}

function Capture-CaseArtifacts($project, $caseDir) {
    $container = Get-Container $project "mvc"
    [ordered]@{
        containerId = $container.Id
        name = $container.Name
        image = $container.Image
        state = $container.State
        restartCount = $container.RestartCount
        hostConfig = [ordered]@{
            nanoCpus = $container.HostConfig.NanoCpus
            memory = $container.HostConfig.Memory
            memorySwap = $container.HostConfig.MemorySwap
        }
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $caseDir "container-state.json")
    $mockMetrics = Invoke-RestMethod -Uri "http://127.0.0.1:9100/__metrics"
    $mockMetrics | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $caseDir "mock-metrics-final.json")
    $stdoutPath = Join-Path $caseDir "application-container.stdout.log"
    $stderrPath = Join-Path $caseDir "application-container.stderr.log"
    $logProcess = Start-Process -FilePath "docker" -ArgumentList @("logs", $container.Id) -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    [ordered]@{ exitCode = $logProcess.ExitCode; stdout = $stdoutPath; stderr = $stderrPath } |
        ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $caseDir "application-log-capture.json")
}

function Wait-IdleWindow([int]$seconds = 5) {
    for ($index = 0; $index -lt $seconds; $index++) {
        $snapshot = Invoke-RestMethod -Uri "http://127.0.0.1:9002/actuator/doengexperiment"
        $metrics = Invoke-RestMethod -Uri "http://127.0.0.1:9100/__metrics"
        if ($null -eq $snapshot.requestRuntime -or $null -eq $snapshot.outboundHttp -or
            $null -eq $snapshot.requestRuntime.busy -or $null -eq $snapshot.requestRuntime.queue -or
            $null -eq $snapshot.outboundHttp.active -or $null -eq $snapshot.outboundHttp.pending -or
            $snapshot.requestRuntime.busy -ne 0 -or $snapshot.requestRuntime.queue -ne 0 -or
            $snapshot.outboundHttp.active -ne 0 -or $snapshot.outboundHttp.pending -ne 0 -or
            $metrics.aiInFlight -ne 0 -or $metrics.storageInFlight -ne 0) { return $false }
        if ($index -lt $seconds - 1) { Start-Sleep -Seconds 1 }
    }
    return $true
}

function Invoke-B01Warmup($case, $target, $caseDir) {
    $warmupRequests = 20
    for ($index = 1; $index -le $warmupRequests; $index++) {
        $env:TARGET_URL = $target
        $env:MODE = [string]$case.mode
        $env:PAYLOAD_PROFILE = [string]$case.payload
        $env:ACTIVE_USERS = "1"
        $env:INTERVAL_MS = "60000"
        $env:DURATION_MS = "1"
        $env:REQUEST_TIMEOUT_MS = [string]$case.requestTimeoutMs
        $env:EXPERIMENT_RUN_ID = "MVC-DIAG-$($case.id)-W$index"
        $env:RESULT_PATH = Join-Path $caseDir "warmup-$index.json"
        $env:PROGRESS_PATH = Join-Path $caseDir "warmup-$index.progress.jsonl"
        & $NodeCommand (Join-Path $repositoryRoot "experiment\load\mvc-diagnostic-load.js")
        if ($LASTEXITCODE -ne 0) { throw "B01 warmup request $index failed" }
    }
    if (-not (Wait-IdleWindow 5)) { throw "B01 warmup idle gate failed" }
}

function Invoke-Case($case) {
    $project = "$ComposeProjectPrefix-$($case.id.ToLowerInvariant())"
    $caseDir = Join-Path $ResultsRoot "MVC-DIAG-$($case.id)"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    $env:MOCK_AI_DELAY_MS = [string]$case.aiDelayMs
    $env:MOCK_STORAGE_DELAY_MS = [string]$case.storageDelayMs
    $env:APP_CPU = [string]$manifest.defaults.appCpu
    $env:APP_MEMORY = [string]$manifest.defaults.appMemory
    $env:MVC_MAX_THREADS = [string]$manifest.defaults.mvcMaxThreads
    $env:HTTP_MAX_CONNECTIONS = [string]$manifest.defaults.httpMaxConnections
    $env:DB_POOL_MAX_SIZE = [string]$manifest.defaults.dbPoolMaxSize
    $env:JAVA_XMS = [string]$manifest.defaults.javaXms
    $env:JAVA_XMX = [string]$manifest.defaults.javaXmx
    docker compose -p $project -f $composeFile up -d mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "compose up failed for $($case.id)" }
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "wait-mvc-readiness.ps1") `
            -ComposeProject $project -ServerService mvc -OutputPath (Join-Path $caseDir "startup-gate.json")
        if ($LASTEXITCODE -ne 0) { throw "STARTUP_GATE: FAIL for $($case.id)" }
        $mvcImageId = Write-RuntimeContract $project $caseDir
        $mockImageId = (Get-Container $project "experiment-mock").Image
        if ($mvcImageId -ne $matrixImageContract.mvcImageId -or $mockImageId -ne $matrixImageContract.mockImageId) {
            throw "MATRIX_IMAGE_CONTRACT: FAIL for $($case.id)"
        }
        $tokenPath = Join-Path $caseDir "auth-tokens.json"
        if ($case.mode -in @("TOKEN_AI_STORAGE", "FULL", "FULL_ORIGINAL_SCHEDULER")) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "provision-experiment-users.ps1") `
                -RunId "MVC-DIAG-$($case.id)" -ComposeProject $project -UserCount $manifest.defaults.activeUsers `
                -MetadataPath (Join-Path $caseDir "prepared-users.json") -TokenPath $tokenPath `
                -ComposeFiles @($composeFile)
            if ($LASTEXITCODE -ne 0) { throw "token provisioning failed for $($case.id)" }
            $env:AUTH_TOKENS_PATH = $tokenPath
        } else {
            Remove-Item Env:AUTH_TOKENS_PATH -ErrorAction SilentlyContinue
        }
        $target = if ($case.mode -in @("FULL", "FULL_ORIGINAL_SCHEDULER")) { "http://127.0.0.1:8002/game/face" } else { "http://127.0.0.1:8002/experiment/mvc-probe" }
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
        if ($case.id -eq "B01") { Invoke-B01Warmup $case $target $caseDir }
        $observer = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "observe-mvc-diagnostic.ps1"),
            "-ComposeProject", $project, "-ServerService", "mvc", "-DurationSeconds", [string]([math]::Ceiling($manifest.defaults.durationMs / 1000)),
            "-OutputPath", (Join-Path $caseDir "observer.jsonl")
        ) -PassThru -WindowStyle Hidden
        if ($case.mode -eq "FULL_ORIGINAL_SCHEDULER") {
            $env:ACTIVE_MISSIONS = [string]$manifest.defaults.activeUsers
            $env:LOAD_SCENARIO = "reconnect-ramp"
            $env:ACCOUNTING_MODE = "corrected"
            $env:ARRIVAL_MODE = "staggered"
            $env:INITIAL_ACTIVE_USERS = [string]$manifest.defaults.activeUsers
            $env:ACTIVATION_STEP_USERS = "1"
            $env:ACTIVATION_INTERVAL_MS = "3000"
            $env:RECONNECT_DELAY_MS = "1000"
            $env:RESULT_PATH = Join-Path $caseDir "client-results.json"
            $env:PROGRESS_PATH = Join-Path $caseDir "client-progress.jsonl"
            & $NodeCommand (Join-Path $repositoryRoot "experiment\load\mission-load.js")
        } else {
            & $NodeCommand (Join-Path $repositoryRoot "experiment\load\mvc-diagnostic-load.js")
        }
        if ($LASTEXITCODE -ne 0) { throw "diagnostic load failed for $($case.id)" }
        if (-not (Wait-IdleWindow 5)) { throw "post-warmup/load idle gate failed for $($case.id)" }
        if (-not $observer.HasExited) { $observer.WaitForExit() }
    } finally {
        if (Test-Path -LiteralPath $caseDir) {
            try { Capture-CaseArtifacts $project $caseDir } catch { $_.Exception.Message | Set-Content (Join-Path $caseDir "capture-error.txt") }
        }
        docker compose -p $project -f $composeFile down --remove-orphans
    }
}

function Write-NotApplicable($case, $reason) {
    $caseDir = Join-Path $ResultsRoot "MVC-DIAG-$($case.id)"
    New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
    [ordered]@{ caseId = $case.id; status = "NOT_APPLICABLE"; reason = $reason } |
        ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $caseDir "case-status.json")
}

$topologyCases = @($casePlan | Where-Object { $_.kind -eq "TOPOLOGY" })
$topologyTarget = $null
foreach ($case in @($topologyCases | Where-Object { $_.id -in @("T00", "T01", "T02", "T03", "T04", "T05", "T06") })) {
    Invoke-Case $case
    $plan.executed = $true
    $plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
    $classification = Get-CaseClassification $case
    if ($classification -ne "STABLE") {
        $topologyTarget = $case
        break
    }
}
$t07 = @($topologyCases | Where-Object { $_.id -eq "T07" }) | Select-Object -First 1
if ($null -eq $topologyTarget) {
    Invoke-Case $t07
    $plan.executed = $true
    $plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
    $topologyTarget = if ((Get-CaseClassification $t07) -eq "STABLE") {
        @($topologyCases | Where-Object { $_.id -eq "T06" }) | Select-Object -First 1
    } else { $t07 }
}
foreach ($boundary in @($casePlan | Where-Object { $_.kind -eq "BOUNDARY" })) {
    $case = [ordered]@{}
    foreach ($property in $boundary.PSObject.Properties) { $case[$property.Name] = $property.Value }
    $case.mode = $topologyTarget.mode
    $case.payload = $topologyTarget.payload
    if ($case.kind -eq "BOUNDARY" -and $case.id -in @("B02", "B03", "B04", "B05") -and
        $case.mode -notin @("AI", "AI_DECODE", "AI_STORAGE", "TOKEN_AI_STORAGE", "FULL", "FULL_ORIGINAL_SCHEDULER")) {
        Write-NotApplicable $case "boundary target does not execute AI"
        continue
    }
    Invoke-Case $case
    $plan.executed = $true
    $plan | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $planPath
}
$summary = [ordered]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    imageContract = $matrixImageContract
    runtimeContract = "per-case runtime-contract.json"
    topologyResults = @($topologyCases | ForEach-Object {
        $statusPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($_.id)") "case-status.json"
        $resultPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($_.id)") "client-results.json"
        [ordered]@{ id = $_.id; result = $resultPath; status = if (Test-Path $statusPath) { (Get-Content -Raw $statusPath | ConvertFrom-Json).status } elseif (Test-Path $resultPath) { Get-CaseClassification $_ } else { "NOT_EXECUTED" } }
    })
    firstUnstableBoundary = if ($topologyTarget) { $topologyTarget.id } else { $null }
    boundaryTarget = if ($topologyTarget) { [ordered]@{ id = $topologyTarget.id; mode = $topologyTarget.mode; payload = $topologyTarget.payload } } else { $null }
    boundaryResults = @($casePlan | Where-Object { $_.kind -eq "BOUNDARY" } | ForEach-Object {
        $statusPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($_.id)") "case-status.json"
        $resultPath = Join-Path (Join-Path $ResultsRoot "MVC-DIAG-$($_.id)") "client-results.json"
        [ordered]@{ id = $_.id; result = $resultPath; status = if (Test-Path $statusPath) { (Get-Content -Raw $statusPath | ConvertFrom-Json).status } elseif (Test-Path $resultPath) { Get-CaseClassification $_ } else { "NOT_EXECUTED" } }
    })
    observerCoverage = "per-case observer.summary.json"
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ResultsRoot "MVC-DIAG-matrix-summary.json")
