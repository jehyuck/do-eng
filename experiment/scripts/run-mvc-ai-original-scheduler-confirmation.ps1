[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = "Stop"
$runId = "MVC-AI-ORIGINAL-SCHED-001"
$composeProject = "doeng-mvcdiag-ai-original-scheduler-001"
$resultDirectory = Join-Path $RepositoryRoot "experiment/results/$runId"
$baseCompose = Join-Path $RepositoryRoot "backend/docker-compose.experiment.yaml"
$imageOverride = Join-Path $RepositoryRoot "experiment/results/mvc-diagnostic-images.override.yml"
$runtimeOverride = Join-Path $resultDirectory "original-scheduler.runtime.override.yml"
$loadScript = Join-Path $RepositoryRoot "experiment/load/mission-load.js"
$nodeCommand = if ($env:NODE_COMMAND) { $env:NODE_COMMAND } else { "node" }

function Write-JsonFile {
    param([string]$Path, $object)
    $object | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Get-ComposeFilesBase64 {
    param([string[]]$Files)
    $json = ConvertTo-Json -Compress -InputObject @($Files)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

function Get-ServiceContainerId {
    param([string]$Service)
    $id = (& docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride ps -q $Service 2>$null | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Could not resolve container for $Service" }
    return $id
}

function Test-SummaryContract {
    param($Summary)
    $required = @{
        loadScenario = "reconnect-ramp"
        arrivalMode = "staggered"
        successMatchMode = "json-path"
        successJsonPath = "ai.result"
        sendAuthorization = $false
        sendMissionRunId = $false
        sendSceneId = $false
    }
    foreach ($key in $required.Keys) {
        if ($Summary.$key -ne $required[$key]) { return $false }
    }
    $hasSuccessfulResponse = @($Summary.statusCounts.PSObject.Properties | Where-Object {
        $_.Name -match "^2" -and [int]$_.Value -gt 0
    }).Count -gt 0
    if ($hasSuccessfulResponse -and [int]$Summary.successTriggeredReconnects -le 0) { return $false }
    return $true
}

function Write-InitialArrivalSummary {
    param([string]$ClientResultsPath)
    $client = Get-Content -Raw -LiteralPath $ClientResultsPath | ConvertFrom-Json
    $startsBySecond = @{}
    foreach ($request in @($client.requests)) {
        $second = [math]::Floor(([DateTimeOffset]$request.requestStartedAt).ToUnixTimeMilliseconds() / 1000)
        if (-not $startsBySecond.ContainsKey($second)) { $startsBySecond[$second] = 0 }
        $startsBySecond[$second] += 1
    }
    $firstSecond = if ($startsBySecond.Count) { ($startsBySecond.Keys | Sort-Object | Select-Object -First 1) } else { $null }
    $values = @()
    if ($null -ne $firstSecond) {
        foreach ($offset in 0..3) {
            $values += [pscustomobject]@{
                second = $offset + 1
                started = if ($startsBySecond.ContainsKey($firstSecond + $offset)) { $startsBySecond[$firstSecond + $offset] } else { 0 }
            }
        }
    }
    Write-JsonFile (Join-Path $resultDirectory "initial-arrival-summary.json") ([ordered]@{
        runId = $runId
        source = "client-results.json requestStartedAt"
        firstFourSeconds = $values
    })
}

if (-not $Execute) {
    Write-Output "Prepared $runId; use -Execute only for the separately approved confirmation run."
    exit 0
}

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
@"
services:
  experiment-mock:
    cpus: "4.0"
    mem_limit: 1g
"@ | Set-Content -Encoding UTF8 -LiteralPath $runtimeOverride

$composeFiles = @(
    (Resolve-Path $baseCompose).Path,
    (Resolve-Path $imageOverride).Path,
    (Resolve-Path $runtimeOverride).Path
)
$composeFilesBase64 = Get-ComposeFilesBase64 $composeFiles
$clientResults = Join-Path $resultDirectory "client-results.json"
$clientProgress = Join-Path $resultDirectory "client-progress.jsonl"
$observerOutput = Join-Path $resultDirectory "observer.jsonl"
$clientStdout = Join-Path $resultDirectory "client-process.stdout.log"
$clientStderr = Join-Path $resultDirectory "client-process.stderr.log"
$mvcStdout = Join-Path $resultDirectory "application-container.stdout.log"
$mvcStderr = Join-Path $resultDirectory "application-container.stderr.log"

$env:APP_CPU = "2.0"
$env:APP_MEMORY = "3g"
$env:MVC_MAX_THREADS = "400"
$env:HTTP_MAX_CONNECTIONS = "400"
$env:DB_POOL_MAX_SIZE = "10"
$env:JAVA_XMS = "512m"
$env:JAVA_XMX = "2048m"
$env:MOCK_AI_RESULT = "true"
$env:MOCK_AI_DELAY_MS = "0"
$env:MOCK_AI_STATUS = "200"
$env:MOCK_STORAGE_DELAY_MS = "100"
$env:MOCK_STORAGE_STATUS = "200"
$env:MOCK_METRICS_URL = "http://127.0.0.1:9100/__metrics"
$env:LOAD_STOP_MOCK_METRICS_PATH = Join-Path $resultDirectory "mock-metrics-final.json"
$env:DRAIN_OBSERVATION_SECONDS = "15"
$env:MOCK_DRAIN_PATH = Join-Path $resultDirectory "mock-drain.jsonl"
$env:MOCK_DRAIN_SUMMARY_PATH = Join-Path $resultDirectory "mock-drain-summary.json"

$observerProcess = $null
$mvcLogProcess = $null
$originalError = $null
try {
    & docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride up -d --no-build mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepositoryRoot "experiment/scripts/wait-mvc-readiness.ps1") `
        -ComposeProject $composeProject -ServerService mvc -MainPort 8002 -ManagementPort 9002 -MockPort 9100 `
        -ComposeFilesBase64 $composeFilesBase64 -OutputPath (Join-Path $resultDirectory "startup-gate.json")
    if ($LASTEXITCODE -ne 0) { throw "Startup gate failed" }

    $mvcId = Get-ServiceContainerId "mvc"
    $mockId = Get-ServiceContainerId "experiment-mock"
    docker inspect $mvcId | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultDirectory "container-state.json")
    docker inspect $mockId | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultDirectory "mock-container-state.json")
    Write-JsonFile (Join-Path $resultDirectory "runtime-contract.json") ([ordered]@{
        composeProject = $composeProject
        composeFiles = $composeFiles
        composeFilesSource = "BASE64_JSON"
        mvcContainerId = $mvcId
        mockContainerId = $mockId
    })
    Write-JsonFile (Join-Path $resultDirectory "mock-runtime-contract.json") ([ordered]@{
        composeProject = $composeProject
        service = "experiment-mock"
        containerId = $mockId
        sourceRoot = "backend/experiment-mock"
        composeFilesSource = "BASE64_JSON"
    })

    $mvcLogProcess = Start-Process -FilePath "docker" -ArgumentList @("logs", "-f", $mvcId) -RedirectStandardOutput $mvcStdout -RedirectStandardError $mvcStderr -PassThru -WindowStyle Hidden
    $observerArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $RepositoryRoot "experiment/scripts/observe-mvc-diagnostic.ps1"),
        "-ComposeProject", $composeProject, "-ServerService", "mvc", "-MainPort", "8002", "-ManagementPort", "9002", "-MockPort", "9100",
        "-DurationSeconds", "60", "-IntervalSeconds", "1", "-ComposeFilesBase64", $composeFilesBase64, "-OutputPath", $observerOutput
    )
    $observerProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $observerArgs -PassThru -WindowStyle Hidden

    $env:MODE = "AI"
    $env:PAYLOAD_PROFILE = "REAL"
    $env:ACTIVE_MISSIONS = "160"
    $env:LOAD_SCENARIO = "reconnect-ramp"
    $env:ACCOUNTING_MODE = "corrected"
    $env:ARRIVAL_MODE = "staggered"
    $env:INITIAL_ACTIVE_USERS = "160"
    $env:ACTIVATION_STEP_USERS = "1"
    $env:ACTIVATION_INTERVAL_MS = "3000"
    $env:RECONNECT_DELAY_MS = "1000"
    $env:INTERVAL_MS = "1000"
    $env:DURATION_MS = "60000"
    $env:REQUEST_TIMEOUT_MS = "10000"
    $env:TARGET_URL = "http://127.0.0.1:8002/experiment/mvc-probe?mode=AI&runId=$runId"
    $env:FIXTURE_PATH = Join-Path $RepositoryRoot "image/arc.jpg"
    $env:ANSWER = "happy"
    $env:SCENE_ID = "2"
    $env:EXPERIMENT_RUN_ID = $runId
    $env:RESULT_PATH = $clientResults
    $env:PROGRESS_PATH = $clientProgress
    $env:SUCCESS_JSON_PATH = "ai.result"
    $env:SEND_AUTHORIZATION = "false"
    $env:SEND_MISSION_RUN_ID = "false"
    $env:SEND_SCENE_ID = "false"

    $clientStartedAt = Get-Date
    & $nodeCommand $loadScript 1> $clientStdout 2> $clientStderr
    $nodeExitCode = $LASTEXITCODE
    $clientFinishedAt = Get-Date
    Write-JsonFile (Join-Path $resultDirectory "client-process-contract.json") ([ordered]@{
        startedAt = $clientStartedAt.ToUniversalTime().ToString("o")
        finishedAt = $clientFinishedAt.ToUniversalTime().ToString("o")
        elapsedMs = ($clientFinishedAt - $clientStartedAt).TotalMilliseconds
        nodeCommand = $nodeCommand
        scriptPath = $loadScript
        exitCode = $nodeExitCode
        resultPath = $clientResults
        progressPath = $clientProgress
        fixturePath = $env:FIXTURE_PATH
    })
    if ($nodeExitCode -ne 0) { throw "mission-load exited with code $nodeExitCode" }

    if ($observerProcess -and -not $observerProcess.HasExited) { $observerProcess.WaitForExit() }
    if ($mvcLogProcess -and -not $mvcLogProcess.HasExited) { Stop-Process -Id $mvcLogProcess.Id -Force }
    Write-JsonFile (Join-Path $resultDirectory "application-log-capture.json") ([ordered]@{
        containerId = $mvcId
        stdoutPath = $mvcStdout
        stderrPath = $mvcStderr
        captureMode = "docker logs -f"
    })
    $client = Get-Content -Raw -LiteralPath $clientResults | ConvertFrom-Json
    if (-not (Test-SummaryContract $client.summary)) { throw "SCHEDULER_CONTRACT failed" }
    Write-InitialArrivalSummary $clientResults
    Write-JsonFile (Join-Path $resultDirectory "scheduler-contract.json") ([ordered]@{
        valid = $true
        loadScenario = $client.summary.loadScenario
        arrivalMode = $client.summary.arrivalMode
        successMatchMode = $client.summary.successMatchMode
        successJsonPath = $client.summary.successJsonPath
        sendAuthorization = $client.summary.sendAuthorization
        sendMissionRunId = $client.summary.sendMissionRunId
        sendSceneId = $client.summary.sendSceneId
        successTriggeredReconnects = $client.summary.successTriggeredReconnects
    })
}
catch {
    $originalError = $_
    throw
}
finally {
    if ($observerProcess -and -not $observerProcess.HasExited) { Stop-Process -Id $observerProcess.Id -Force }
    if ($mvcLogProcess -and -not $mvcLogProcess.HasExited) { Stop-Process -Id $mvcLogProcess.Id -Force }
    if ($Execute) {
        & docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride down --remove-orphans
    }
}
