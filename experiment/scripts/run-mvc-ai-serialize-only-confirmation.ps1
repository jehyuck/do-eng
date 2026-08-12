[CmdletBinding()]
param(
    [switch]$BootstrapOnly,
    [switch]$Execute,
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ($BootstrapOnly -and $Execute) { throw "Use either -BootstrapOnly or -Execute" }
if (-not $BootstrapOnly -and -not $Execute) { throw "Use -BootstrapOnly or separately approved -Execute" }
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
}
$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path

$runId = "MVC-AI-SERIALIZE-ONLY-001"
$project = "doeng-mvcdiag-ai-serialize-only-001"
$resultDirectory = Join-Path $RepositoryRoot "experiment/results/$runId"
$baseCompose = Join-Path $RepositoryRoot "backend/docker-compose.experiment.yaml"
$dockerfile = Join-Path $RepositoryRoot "backend/doEngGameMvc/Dockerfile.experiment"
$mvcContext = Join-Path $RepositoryRoot "backend/doEngGameMvc"
$loadScript = Join-Path $RepositoryRoot "experiment/load/mission-load.js"
$mvcImageTag = "doeng-mvc-ai-serialize-only-mvc:locked"
$mockImageTag = "doeng-mvc-ai-serialize-only-mock:locked"
$expectedMockImageId = "sha256:0bbf354a08732a5dbfd3a3013218a6f1955d74c1bc41ecc407e819ba1788bbf6"
$sourceBaseline = "0cc3f1472e76a04de5b4cfecd3737b460b973bd2"
$currentHead = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not resolve Git HEAD" }
$mvcSourceTree = (git rev-parse "HEAD:backend/doEngGameMvc").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mvcSourceTree)) { throw "Could not resolve MVC source tree" }

function Write-JsonArtifact {
    param([string]$Path, $Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $Value | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Get-ImageId {
    param([string]$Tag)
    $id = (& docker image inspect $Tag --format '{{.Id}}' 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) { throw "Image unavailable: $Tag" }
    return $id
}

function Get-NodeRuntime {
    $command = Get-Command node -All -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $path = $command.Source }
    else { $path = "C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" }
    if (-not (Test-Path $path)) { throw "NODE_RUNTIME_CONTRACT: FAIL" }
    $version = (& $path --version 2>&1 | Out-String).Trim()
    if ($version -ne "v24.14.0") { throw "NODE_RUNTIME_CONTRACT: FAIL ($version)" }
    return [pscustomobject]@{ path = $path; version = $version }
}

function Assert-SourceGate {
    $allowed = @(
        "backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/",
        "backend/doEngGameMvc/src/test/java/com/example/doenggamemvc/experiment/",
        "experiment/scripts/run-mvc-ai-serialize-only-confirmation.ps1"
    )
    $changed = @(
        git diff --name-only $sourceBaseline HEAD
        git diff --name-only
        git ls-files --others --exclude-standard
    ) | Where-Object {
        $_ -and (($_.StartsWith("backend/doEngGameMvc/") -or $_ -eq $allowed[2])) -and
        $_ -notmatch '^backend/doEngGameMvc/(\.gradle|build)/'
    } | Sort-Object -Unique
    $unexpected = @($changed | Where-Object {
        $path = $_
        -not (@($allowed | Where-Object { $path.StartsWith($_) }).Count -gt 0)
    })
    $pass = $unexpected.Count -eq 0
    Write-JsonArtifact (Join-Path $resultDirectory "serialize-only-source-gate.json") ([ordered]@{
        baselineHead = $sourceBaseline
        currentHead = (git rev-parse HEAD)
        changedMvcPaths = @($changed)
        allowedChangedPaths = $allowed
        unexpectedChangedPaths = $unexpected
        pass = $pass
    })
    if (-not $pass) { throw "PRODUCTION_SOURCE_GATE: FAIL" }
    return $true
}

function Get-ComposeFilesBase64 {
    param([string[]]$Files)
    $json = @($Files) | ConvertTo-Json -Compress
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

function Get-ServiceContainer {
    param([string]$Service)
    $ids = @(& docker ps -aq --filter "label=com.docker.compose.project=$project" --filter "label=com.docker.compose.service=$Service" 2>$null |
        ForEach-Object { $value = ([string]$_).Trim(); if ($value) { $value } })
    if ($ids.Count -ne 1) { throw "Expected one $Service container, found $($ids.Count)" }
    return ((docker inspect $ids[0] | Out-String) | ConvertFrom-Json)[0]
}

function Get-EnvironmentMap {
    param($Container)
    $map = @{}
    foreach ($entry in @($Container.Config.Env)) {
        $parts = ([string]$entry).Split("=", 2)
        $map[$parts[0]] = if ($parts.Count -eq 2) { $parts[1] } else { "" }
    }
    return $map
}

function Test-MvcRuntimeContract {
    param($Container, [string]$ExpectedImageId)
    $env = Get-EnvironmentMap $Container
    return ($Container.Image -eq $ExpectedImageId -and
        $Container.HostConfig.NanoCpus -eq 2000000000 -and
        $Container.HostConfig.Memory -eq 3221225472 -and
        $env.DOENG_MVC_MAX_THREADS -eq "400" -and
        $env.DOENG_HTTP_MAX_CONNECTIONS -eq "400" -and
        $env.DOENG_DB_POOL_MAX_SIZE -eq "10" -and
        $env.JAVA_TOOL_OPTIONS -match "-Xms512m" -and
        $env.JAVA_TOOL_OPTIONS -match "-Xmx2048m")
}

function Test-MockRuntimeContract {
    param($Container)
    $env = Get-EnvironmentMap $Container
    return ($Container.Image -eq $expectedMockImageId -and
        $Container.HostConfig.NanoCpus -eq 4000000000 -and
        $Container.HostConfig.Memory -eq 1073741824 -and
        $env.MOCK_AI_RESULT -eq "true" -and
        $env.MOCK_AI_DELAY_MS -eq "0" -and
        $env.MOCK_AI_STATUS -eq "200" -and
        $env.MOCK_STORAGE_DELAY_MS -eq "100" -and
        $env.MOCK_STORAGE_STATUS -eq "200")
}

function Get-ProcessSummary {
    param($Summary)
    return [ordered]@{
        startedRequests = [int]$Summary.startedRequests
        completedRequests = [int]$Summary.completedRequests
        unfinishedRequests = [int]$Summary.unfinishedRequests
        successfulRequests = [int]$Summary.successfulRequests
        clientTimeout = [int]$Summary.clientTimeout
        connectionError = [int]$Summary.connectionError
        successRate = if ([int]$Summary.startedRequests -gt 0) { [double]$Summary.successfulRequests / [double]$Summary.startedRequests } else { 0 }
        timeoutRate = if ([int]$Summary.startedRequests -gt 0) { [double]$Summary.clientTimeout / [double]$Summary.startedRequests } else { 0 }
    }
}

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
Assert-SourceGate
$node = Get-NodeRuntime

if ($BootstrapOnly) {
    $bootstrapTag = "doeng-mvc-ai-serialize-only-mvc:bootstrap-$PID"
    & docker build -f $dockerfile -t $bootstrapTag $mvcContext
    $mvcBuildExitCode = $LASTEXITCODE
    if ($mvcBuildExitCode -ne 0) { throw "MVC image build failed" }
    $mvcId = Get-ImageId $bootstrapTag
    & docker tag $mvcId $mvcImageTag
    if ($LASTEXITCODE -ne 0) { throw "MVC locked tag failed" }
    $lockedMvcId = Get-ImageId $mvcImageTag
    if ($lockedMvcId -ne $mvcId) { throw "MVC locked image ID mismatch" }
    $mockId = Get-ImageId $expectedMockImageId
    & docker tag $mockId $mockImageTag
    if ($LASTEXITCODE -ne 0) { throw "Canonical mock tag failed" }
    $runMockId = Get-ImageId $mockImageTag
    if ($runMockId -ne $expectedMockImageId) { throw "Run-specific mock image ID mismatch" }
    Write-JsonArtifact (Join-Path $resultDirectory "serialize-only-image-contract.json") ([ordered]@{
        runId = $runId
        sourceHead = $currentHead
        mvcSourceTree = $mvcSourceTree
        dockerfile = "backend/doEngGameMvc/Dockerfile.experiment"
        buildContext = "backend/doEngGameMvc"
        mvcImageTag = $mvcImageTag
        mvcImageId = $lockedMvcId
        buildExitCode = $mvcBuildExitCode
        productionSourceGate = "PASS"
        canonicalMockImageId = $expectedMockImageId
        runSpecificMockTag = $mockImageTag
        runSpecificMockImageId = $runMockId
        pass = ($mvcBuildExitCode -eq 0 -and $lockedMvcId -eq $mvcId -and $runMockId -eq $expectedMockImageId)
    })
    if ($mvcBuildExitCode -ne 0) { throw "MVC_BUILD: FAIL" }
    if ($lockedMvcId -ne $mvcId -or $runMockId -ne $expectedMockImageId) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: FAIL" }
    $containers = @(& docker ps -aq --filter "label=com.docker.compose.project=$project" 2>$null)
    $volumes = @(& docker volume ls -q --filter "label=com.docker.compose.project=$project" 2>$null)
    if ($containers.Count -ne 0 -or $volumes.Count -ne 0) { throw "FRESH_PROJECT_GUARD: FAIL" }
    Write-JsonArtifact (Join-Path $resultDirectory "fresh-project-guard.json") ([ordered]@{
        project = $project
        existingContainerIds = @($containers)
        existingVolumes = @($volumes)
        containerCount = $containers.Count
        volumeCount = $volumes.Count
        pass = $true
    })
    Write-JsonArtifact (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
        imageContract = "PASS"
        sourceGate = "PASS"
        freshProjectGuard = "PASS"
        nodeRuntimeContract = "PASS"
        serializeOnlyNetworkContract = "NOT_MEASURED"
        composeStarted = $false
        performanceWorkloadStarted = $false
        measurementValid = $false
    })
    Write-Output "BOOTSTRAP_ONLY_VALIDATION: PASS"
    exit 0
}

$imageContractPath = Join-Path $resultDirectory "serialize-only-image-contract.json"
if (-not (Test-Path $imageContractPath)) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: missing Bootstrap artifact" }
$imageContract = Get-Content -Raw $imageContractPath | ConvertFrom-Json
if ($imageContract.pass -ne $true) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: FAIL" }
if ([string]$imageContract.sourceHead -ne $currentHead -or [string]$imageContract.mvcSourceTree -ne $mvcSourceTree) { throw "MVC_SOURCE_PROVENANCE: FAIL" }
$authoritativeMvcImageId = [string]$imageContract.mvcImageId
$resolvedMvcImageId = Get-ImageId $mvcImageTag
if ($resolvedMvcImageId -ne $authoritativeMvcImageId) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: MVC image mismatch" }
$mockId = Get-ImageId $mockImageTag
if ($mockId -ne $expectedMockImageId) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: mock image mismatch" }

$imagesOverride = Join-Path $resultDirectory "serialize-only.images.override.yml"
$resourcesOverride = Join-Path $resultDirectory "serialize-only.runtime.override.yml"
@(
    "services:",
    "  mvc:",
    "    image: $mvcImageTag",
    "  experiment-mock:",
    "    image: $mockImageTag"
) | Set-Content -Encoding UTF8 -LiteralPath $imagesOverride
@(
    "services:",
    "  mvc:",
    '    cpus: "2.0"',
    "    mem_limit: 3g",
    "  experiment-mock:",
    '    cpus: "4.0"',
    "    mem_limit: 1g"
) | Set-Content -Encoding UTF8 -LiteralPath $resourcesOverride

$composeFiles = @($baseCompose, $imagesOverride, $resourcesOverride)
$composeArguments = @("-p", $project)
foreach ($file in $composeFiles) { $composeArguments += @("-f", $file) }
$composeFilesBase64 = Get-ComposeFilesBase64 $composeFiles
$started = $false
$observer = $null
$client = $null
$clientExitCode = $null
$gates = [ordered]@{
    imageContract = $true; sourceGate = $true; freshProjectGuard = $true; nodeRuntimeContract = $true
    startupGate = $false; mvcRuntimeContract = $false; mockRuntimeContract = $false; clientAccounting = $false; nodeExitCodeZero = $false
    schedulerContract = $false; observerContract = $false; networkContract = $false; finalMvcState = $false
    finalMockState = $false; clientProcessStarted = $false; performanceWorkloadStarted = $false
}

$env:MODE = "SERIALIZE_ONLY"
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
$env:TARGET_URL = "http://127.0.0.1:8002/experiment/mvc-probe?mode=SERIALIZE_ONLY&runId=$runId&answer=happy"
$env:FIXTURE_PATH = Join-Path $RepositoryRoot "image/arc.jpg"
$env:ANSWER = "happy"
$env:SCENE_ID = "2"
$env:EXPERIMENT_RUN_ID = $runId
$env:RESULT_PATH = Join-Path $resultDirectory "client-results.json"
$env:PROGRESS_PATH = Join-Path $resultDirectory "client-progress.jsonl"
$env:SUCCESS_JSON_PATH = "serialization.result"
$env:SEND_AUTHORIZATION = "false"
$env:SEND_MISSION_RUN_ID = "false"
$env:SEND_SCENE_ID = "false"

try {
    $mvcId = Get-ImageId $mvcImageTag
    $mockId = Get-ImageId $mockImageTag
    if ($mvcId -ne $expectedMvcImageId -or $mockId -ne $expectedMockImageId) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: FAIL" }
    & docker compose @composeArguments up -d --no-build mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }
    $started = $true
    $mvc = Get-ServiceContainer "mvc"
    $mock = Get-ServiceContainer "experiment-mock"
    $gates.mvcRuntimeContract = Test-MvcRuntimeContract $mvc
    $gates.mockRuntimeContract = Test-MockRuntimeContract $mock
    Write-JsonArtifact (Join-Path $resultDirectory "runtime-contract.json") ([ordered]@{ pass = $gates.mvcRuntimeContract; imageId = $mvc.Image; cpuNano = $mvc.HostConfig.NanoCpus; memoryBytes = $mvc.HostConfig.Memory })
    Write-JsonArtifact (Join-Path $resultDirectory "mock-runtime-contract.json") ([ordered]@{ pass = $gates.mockRuntimeContract; imageId = $mock.Image; cpuNano = $mock.HostConfig.NanoCpus; memoryBytes = $mock.HostConfig.Memory })
    if (-not $gates.mvcRuntimeContract -or -not $gates.mockRuntimeContract) { throw "RUNTIME_CONTRACT: FAIL" }

    $startupPath = Join-Path $resultDirectory "startup-gate.json"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepositoryRoot "experiment/scripts/wait-mvc-readiness.ps1") -ComposeProject $project -ServerService mvc -MainPort 8002 -ManagementPort 9002 -MockPort 9100 -ComposeFilesBase64 $composeFilesBase64 -OutputPath $startupPath
    if ($LASTEXITCODE -ne 0) { throw "STARTUP_GATE: FAIL" }
    $gates.startupGate = $true

    $observer = Start-Process powershell.exe -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $RepositoryRoot "experiment/scripts/observe-mvc-diagnostic.ps1"),
        "-ComposeProject", $project, "-ServerService", "mvc", "-MainPort", "8002", "-ManagementPort", "9002", "-MockPort", "9100",
        "-DurationSeconds", "60", "-IntervalSeconds", "1", "-ComposeFilesBase64", $composeFilesBase64,
        "-OutputPath", (Join-Path $resultDirectory "observer.jsonl")
    ) -PassThru -WindowStyle Hidden

    $clientProcessContract = [ordered]@{
        attempted = $true; started = $false; performanceWorkloadStarted = $false; processId = $null
        nodePath = $node.path; nodeVersion = $node.version; scriptPath = $loadScript; exitCode = $null
        startedAt = $null; finishedAt = $null
    }
    $clientProcessContract.startedAt = (Get-Date).ToUniversalTime().ToString("o")
    $client = Start-Process -FilePath $node.path -ArgumentList @($loadScript) -RedirectStandardOutput (Join-Path $resultDirectory "client-process.stdout.log") -RedirectStandardError (Join-Path $resultDirectory "client-process.stderr.log") -Wait -PassThru -NoNewWindow
    $clientExitCode = $client.ExitCode
    $clientProcessContract.finishedAt = (Get-Date).ToUniversalTime().ToString("o")
    $clientProcessContract.started = $true
    $clientProcessContract.performanceWorkloadStarted = $true
    $clientProcessContract.processId = $client.Id
    $clientProcessContract.exitCode = $clientExitCode
    Write-JsonArtifact (Join-Path $resultDirectory "client-process-contract.json") $clientProcessContract
    $gates.clientProcessStarted = $true
    $gates.performanceWorkloadStarted = $true
    $gates.nodeExitCodeZero = ($clientExitCode -eq 0)
    if ($clientExitCode -ne 0) { throw "NODE_EXIT_CODE: FAIL" }

    if ($observer) { $observer.WaitForExit() }
    $resultPath = Join-Path $resultDirectory "client-results.json"
    if (-not (Test-Path $resultPath)) { throw "CLIENT_RESULT: MISSING" }
    $resultData = Get-Content -Raw $resultPath | ConvertFrom-Json
    $summary = $resultData.summary
    $accounting = Get-ProcessSummary $summary
    $gates.clientAccounting = ($accounting.startedRequests -gt 0 -and $accounting.completedRequests -eq $accounting.startedRequests -and $accounting.unfinishedRequests -eq 0 -and $summary.accounting.valid -eq $true)
    Write-JsonArtifact (Join-Path $resultDirectory "client-accounting-contract.json") ([ordered]@{ valid = $gates.clientAccounting; nodeExitCode = $clientExitCode; summary = $accounting })

    $freezePass = ($summary.activeMissions -eq 160 -and $summary.initialActiveUsers -eq 160 -and $summary.activationStepUsers -eq 1 -and $summary.activationIntervalMs -eq 3000 -and $summary.reconnectDelayMs -eq 1000 -and $summary.intervalMs -eq 1000 -and $summary.durationMs -eq 60000 -and $summary.requestTimeoutMs -eq 10000)
    $gates.schedulerContract = ($summary.loadScenario -eq "reconnect-ramp" -and $summary.arrivalMode -eq "staggered" -and $summary.successMatchMode -eq "json-path" -and $summary.successJsonPath -eq "serialization.result" -and $summary.sendAuthorization -eq $false -and $summary.sendMissionRunId -eq $false -and $summary.sendSceneId -eq $false -and $freezePass -and ($accounting.successfulRequests -eq 0 -or $summary.successTriggeredReconnects -gt 0))
    Write-JsonArtifact (Join-Path $resultDirectory "scheduler-contract.json") ([ordered]@{ valid = $gates.schedulerContract; loadScenario = $summary.loadScenario; arrivalMode = $summary.arrivalMode; successMatchMode = $summary.successMatchMode; successJsonPath = $summary.successJsonPath; freeze = $freezePass; successTriggeredReconnects = $summary.successTriggeredReconnects })

    $observerSummaryPath = Join-Path $resultDirectory "observer.summary.json"
    $observerSummary = Get-Content -Raw $observerSummaryPath | ConvertFrom-Json
    $gates.observerContract = ($observerSummary.sampleCount -gt 0 -and $observerSummary.observerValid -eq $true -and $observerSummary.successfulApplicationSamples -gt 0 -and $observerSummary.successfulMockSamples -gt 0 -and $observerSummary.containerStateFailures -lt $observerSummary.sampleCount)
    Write-JsonArtifact (Join-Path $resultDirectory "observer-contract.json") ([ordered]@{ pass = $gates.observerContract; summary = $observerSummary })

    $metricsResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:9100/__metrics"
    $metrics = $metricsResponse.Content | ConvertFrom-Json
    $requestCountsProperty = $metrics.PSObject.Properties["requestCounts"]
    $faceCountProperty = if ($requestCountsProperty) { $requestCountsProperty.Value.PSObject.Properties["POST /analyze/face"] } else { $null }
    $gates.networkContract = ($null -ne $faceCountProperty -and [int]$faceCountProperty.Value -eq 0 -and [int]$metrics.aiCompleted -eq 0 -and [int]$metrics.aiMaxInFlight -eq 0)
    Write-JsonArtifact (Join-Path $resultDirectory "serialize-only-network-contract.json") ([ordered]@{ pass = $gates.networkContract; requestCountsKeyPresent = $null -ne $faceCountProperty; analyzeFacePostCount = if ($faceCountProperty) { $faceCountProperty.Value } else { $null }; aiCompleted = $metrics.aiCompleted; aiMaxInFlight = $metrics.aiMaxInFlight })

    $firstProgress = @()
    $progressPath = Join-Path $resultDirectory "client-progress.jsonl"
    if (Test-Path $progressPath) { $firstProgress = @(Get-Content $progressPath | Select-Object -First 4) }
    Write-JsonArtifact (Join-Path $resultDirectory "initial-arrival-summary.json") ([ordered]@{ runId = $runId; firstProgressLines = $firstProgress; lineCountObserved = @($firstProgress).Count })
} finally {
    if ($observer -and -not $observer.HasExited) { Stop-Process -Id $observer.Id -Force }
    if ($started) {
        try {
            $mvcFinal = Get-ServiceContainer "mvc"
            $mockFinal = Get-ServiceContainer "experiment-mock"
            $gates.finalMvcState = ($mvcFinal.State.Running -eq $true -and $mvcFinal.RestartCount -eq 0 -and $mvcFinal.State.OOMKilled -eq $false)
            $gates.finalMockState = ($mockFinal.State.Running -eq $true -and $mockFinal.RestartCount -eq 0 -and $mockFinal.State.OOMKilled -eq $false)
            Write-JsonArtifact (Join-Path $resultDirectory "mvc-final-state-contract.json") ([ordered]@{ pass = $gates.finalMvcState; running = $mvcFinal.State.Running; restartCount = $mvcFinal.RestartCount; oomKilled = $mvcFinal.State.OOMKilled; exitCode = $mvcFinal.State.ExitCode })
            Write-JsonArtifact (Join-Path $resultDirectory "mock-final-state-contract.json") ([ordered]@{ pass = $gates.finalMockState; running = $mockFinal.State.Running; restartCount = $mockFinal.RestartCount; oomKilled = $mockFinal.State.OOMKilled; exitCode = $mockFinal.State.ExitCode })
        } catch { Write-JsonArtifact (Join-Path $resultDirectory "final-state-error.json") ([ordered]@{ error = $_.Exception.Message }) }
        & docker compose @composeArguments down --remove-orphans
    }
}

$measurementValid = ($gates.Values -notcontains $false)
$classification = "INVALID"
$serializationPathSufficient = "NOT_ESTABLISHED"
if ($measurementValid) {
    $successRate = $accounting.successRate
    $timeoutRate = $accounting.timeoutRate
    if ($successRate -ge 0.95 -and $timeoutRate -le 0.05) { $classification = "STABLE"; $serializationPathSufficient = "NO" }
    elseif ($successRate -ge 0.80 -and $successRate -lt 0.95) { $classification = "DEGRADED" }
    else { $classification = "COLLAPSE"; $serializationPathSufficient = "SUPPORTED" }
}
Write-JsonArtifact (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
    sourceGate = if ($gates.sourceGate) { "PASS" } else { "FAIL" }
    imageContract = if ($gates.imageContract) { "PASS" } else { "FAIL" }
    freshProjectGuard = if ($gates.freshProjectGuard) { "PASS" } else { "FAIL" }
    nodeRuntimeContract = if ($gates.nodeRuntimeContract) { "PASS" } else { "FAIL" }
    startupGate = if ($gates.startupGate) { "PASS" } else { "FAIL" }
    mvcRuntimeContract = if ($gates.mvcRuntimeContract) { "PASS" } else { "FAIL" }
    mockRuntimeContract = if ($gates.mockRuntimeContract) { "PASS" } else { "FAIL" }
    clientAccountingContract = if ($gates.clientAccounting) { "PASS" } else { "FAIL" }
    nodeExitCode = $clientExitCode
    nodeExitCodeZero = if ($gates.nodeExitCodeZero) { "PASS" } else { "FAIL" }
    schedulerContract = if ($gates.schedulerContract) { "PASS" } else { "FAIL" }
    observerContract = if ($gates.observerContract) { "PASS" } else { "FAIL" }
    serializeOnlyNetworkContract = if ($gates.networkContract) { "PASS" } else { "FAIL" }
    mvcFinalState = if ($gates.finalMvcState) { "PASS" } else { "FAIL" }
    mockFinalState = if ($gates.finalMockState) { "PASS" } else { "FAIL" }
    clientProcessStarted = $gates.clientProcessStarted
    performanceWorkloadStarted = $gates.performanceWorkloadStarted
    measurementValid = $measurementValid
    classification = $classification
    serializationPathSufficient = $serializationPathSufficient
})
