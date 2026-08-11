[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$BootstrapOnly,
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $invokedScriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrWhiteSpace($invokedScriptPath)) { throw "Could not resolve runner script path" }
    if (-not [IO.Path]::IsPathRooted($invokedScriptPath)) {
        $invokedScriptPath = Join-Path (Get-Location).Path $invokedScriptPath
    }
    $invokedScriptPath = [IO.Path]::GetFullPath($invokedScriptPath)
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $invokedScriptPath))
}
$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path
if ($Execute -and $BootstrapOnly) { throw "-Execute and -BootstrapOnly cannot be combined" }
$runId = "MVC-AI-ORIGINAL-SCHED-001"
$composeProject = "doeng-mvcdiag-ai-original-scheduler-001"
$resultDirectory = Join-Path $RepositoryRoot "experiment/results/$runId"
$baseCompose = Join-Path $RepositoryRoot "backend/docker-compose.experiment.yaml"
$imageOverride = Join-Path $resultDirectory "original-scheduler.images.override.yml"
$runtimeOverride = Join-Path $resultDirectory "original-scheduler.runtime.override.yml"
$loadScript = Join-Path $RepositoryRoot "experiment/load/mission-load.js"
$requestedNodeCommand = $env:NODE_COMMAND
$nodeCommand = $null
$canonicalImageContractPath = Join-Path $RepositoryRoot "experiment/results/matrix-image-contract.json"
$expectedMvcImageId = "sha256:984fa39f3ab397d831086f8bef96402180c1d80d2d47b0a0274b2189652b6d4d"
$expectedMockImageId = "sha256:0bbf354a08732a5dbfd3a3013218a6f1955d74c1bc41ecc407e819ba1788bbf6"
$lockedMvcImage = "doeng-mvcdiag-mvc:locked"
$lockedMockImage = "doeng-mvcdiag-mock:locked"
$runLockedMvcImage = "doeng-mvc-ai-original-scheduler-mvc:locked"
$runLockedMockImage = "doeng-mvc-ai-original-scheduler-mock:locked"

function Write-JsonFile {
    param([string]$Path, $object)
    $object | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Resolve-NodeExecutable {
    $candidates = @()
    $sources = @{}
    if (-not [string]::IsNullOrWhiteSpace($requestedNodeCommand)) {
        if ([IO.Path]::IsPathRooted($requestedNodeCommand)) {
            $candidates += $requestedNodeCommand
            $sources[$requestedNodeCommand] = "NODE_COMMAND"
        } else {
            $command = Get-Command $requestedNodeCommand -All -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($command) {
                $candidates += $command.Source
                $sources[$command.Source] = "NODE_COMMAND"
            }
        }
    } else {
        $command = Get-Command node -All -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            $candidates += $command.Source
            $sources[$command.Source] = "GET_COMMAND"
        }
        $localNode = "C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
        if (Test-Path -LiteralPath $localNode) {
            $candidates += $localNode
            $sources[$localNode] = "VERIFIED_LOCAL_PATH"
        }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $versionOutput = @(& $candidate --version 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0 -and $versionOutput.Count -gt 0) {
            $contract = [ordered]@{
                requestedNodeCommand = $requestedNodeCommand
                resolvedExecutable = $candidate
                version = ([string]($versionOutput -join " ")).Trim()
                resolutionSource = $sources[$candidate]
                preflightExitCode = $exitCode
                pass = $true
            }
            Write-JsonFile (Join-Path $resultDirectory "node-runtime-contract.json") $contract
            return $contract
        }
    }
    $contract = [ordered]@{
        requestedNodeCommand = $requestedNodeCommand
        resolvedExecutable = $null
        version = $null
        resolutionSource = $null
        preflightExitCode = $null
        pass = $false
    }
    Write-JsonFile (Join-Path $resultDirectory "node-runtime-contract.json") $contract
    throw "NODE_RUNTIME_CONTRACT: FAIL"
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

function Assert-ClientAccounting {
    param($Client)
    $summary = $Client.summary
    $actual = [ordered]@{
        startedRequests = $summary.startedRequests
        completedRequests = $summary.completedRequests
        unfinishedRequests = $summary.unfinishedRequests
        accountingValid = $summary.accounting.valid
        nodeExitCode = $script:nodeExitCode
    }
    $pass = $actual.nodeExitCode -eq 0 -and $actual.startedRequests -gt 0 -and
        $actual.completedRequests -eq $actual.startedRequests -and
        $actual.unfinishedRequests -eq 0 -and $actual.accountingValid -eq $true
    $actual.pass = $pass
    Write-JsonFile (Join-Path $resultDirectory "client-accounting-contract.json") $actual
    if (-not $pass) { throw "CLIENT_ACCOUNTING_CONTRACT: FAIL" }
}

function Assert-ObserverContract {
    param([string]$ObserverSummaryPath)
    if (-not (Test-Path -LiteralPath $ObserverSummaryPath)) { throw "OBSERVER_CONTRACT: missing summary" }
    $summary = Get-Content -Raw -LiteralPath $ObserverSummaryPath | ConvertFrom-Json
    $pass = $summary.sampleCount -gt 0 -and $summary.observerValid -eq $true -and
        $summary.successfulApplicationSamples -gt 0 -and
        $summary.successfulMockSamples -gt 0 -and
        $summary.containerStateFailures -lt $summary.sampleCount
    $contract = [ordered]@{
        expected = [ordered]@{
            sampleCount = "> 0"
            observerValid = $true
            successfulApplicationSamples = "> 0"
            successfulMockSamples = "> 0"
            containerStateFailures = "< sampleCount"
        }
        actual = $summary
        pass = $pass
    }
    Write-JsonFile (Join-Path $resultDirectory "observer-contract.json") $contract
    if (-not $pass) { throw "OBSERVER_CONTRACT: FAIL" }
}

function Capture-FinalContainerState {
    param([string]$Service, [string]$Path)
    $container = Get-InspectedContainer $Service
    $state = [ordered]@{
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        containerId = $container.Id
        imageId = $container.Image
        running = $container.State.Running
        restartCount = $container.RestartCount
        oomKilled = $container.State.OOMKilled
        exitCode = $container.State.ExitCode
        status = $container.State.Status
    }
    Write-JsonFile $Path $state
    return $state
}

function Assert-FinalContainerState {
    param($State, [string]$Name)
    $pass = $State.running -eq $true -and $State.restartCount -eq 0 -and $State.oomKilled -eq $false
    Write-JsonFile (Join-Path $resultDirectory "$Name-final-state-contract.json") ([ordered]@{ actual = $State; pass = $pass })
    if (-not $pass) { throw "$Name`_FINAL_STATE: FAIL" }
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

if (-not $Execute -and -not $BootstrapOnly) {
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


function Get-InspectedContainer {
    param([string]$Service)
    $id = (& docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride ps -q $Service 2>$null |
        Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Could not resolve container for $Service" }
    $raw = @(& docker inspect $id 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "docker inspect failed for $Service" }
    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)[0]
}

function Get-ContainerEnvironment {
    param($Container)
    $environment = @{}
    foreach ($entry in @($Container.Config.Env)) {
        $parts = ([string]$entry) -split "=", 2
        if ($parts.Count -eq 2) { $environment[$parts[0]] = $parts[1] }
    }
    return $environment
}

function Get-ImageId {
    param([string]$Tag)
    $id = ([string](@(& docker image inspect $Tag --format "{{.Id}}" 2>$null) -join "")).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) { throw "Could not inspect image $Tag" }
    return $id
}

function Try-GetImageId {
    param([string]$Reference)
    $id = ([string](@(& docker image inspect $Reference --format "{{.Id}}" 2>$null) -join "")).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) { return $null }
    return $id
}

function Assert-CanonicalImageContract {
    if (-not (Test-Path -LiteralPath $canonicalImageContractPath)) { throw "IMAGE_CONTRACT: missing canonical contract" }
    $contract = Get-Content -Raw -LiteralPath $canonicalImageContractPath | ConvertFrom-Json
    $mvcId = Try-GetImageId $expectedMvcImageId
    $mockId = Try-GetImageId $expectedMockImageId
    $lockedMvcId = Try-GetImageId $lockedMvcImage
    $lockedMockId = Try-GetImageId $lockedMockImage
    $actual = [ordered]@{
        stage = "IMAGE_CONTRACT"
        lockedMvcTagPresent = $null -ne $lockedMvcId
        lockedMockTagPresent = $null -ne $lockedMockId
        canonicalMvcImagePresent = $null -ne $mvcId
        canonicalMockImagePresent = $null -ne $mockId
        lockedMvcImage = $lockedMvcId
        lockedMockImage = $lockedMockId
        canonicalMvcImage = $mvcId
        canonicalMockImage = $mockId
        expectedMvcImage = $expectedMvcImageId
        expectedMockImage = $expectedMockImageId
        sourceContractMvcImage = [string]$contract.mvcImageId
        sourceContractMockImage = [string]$contract.mockImageId
        sourceContractMatch = [string]$contract.mvcImageId -eq $expectedMvcImageId -and
            [string]$contract.mockImageId -eq $expectedMockImageId
    }
    $pass = $null -ne $mvcId -and $null -ne $mockId -and
        $actual.canonicalMvcImagePresent -and $actual.canonicalMockImagePresent
    $actual.pass = $pass
    Write-JsonFile (Join-Path $resultDirectory "image-contract.json") $actual
    if (-not $pass) { throw "IMAGE_CONTRACT: FAIL" }
}

function Ensure-RunSpecificImageTags {
    $mvcId = Get-ImageId $expectedMvcImageId
    $mockId = Get-ImageId $expectedMockImageId
    & docker tag $mvcId $runLockedMvcImage
    if ($LASTEXITCODE -ne 0) { throw "Could not create run-specific MVC image tag" }
    & docker tag $mockId $runLockedMockImage
    if ($LASTEXITCODE -ne 0) { throw "Could not create run-specific mock image tag" }
    $taggedMvcId = Get-ImageId $runLockedMvcImage
    $taggedMockId = Get-ImageId $runLockedMockImage
    $pass = $taggedMvcId -eq $expectedMvcImageId -and $taggedMockId -eq $expectedMockImageId
    Write-JsonFile (Join-Path $resultDirectory "run-specific-image-tags.json") ([ordered]@{
        mvcTag = $runLockedMvcImage
        mockTag = $runLockedMockImage
        mvcImageId = $taggedMvcId
        mockImageId = $taggedMockId
        pass = $pass
    })
    if (-not $pass) { throw "RUN_SPECIFIC_IMAGE_TAGGING: FAIL" }
    @"
services:
  mvc:
    image: $runLockedMvcImage
  experiment-mock:
    image: $runLockedMockImage
"@ | Set-Content -Encoding UTF8 -LiteralPath $imageOverride
}

function Assert-FreshProject {
    $ids = @(& docker ps -aq --filter "label=com.docker.compose.project=$composeProject" 2>$null |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($LASTEXITCODE -ne 0) { throw "FRESH_PROJECT_GUARD: unable to inspect project" }
    $volumes = @(& docker volume ls -q --filter "label=com.docker.compose.project=$composeProject" 2>$null |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($LASTEXITCODE -ne 0) { throw "FRESH_PROJECT_GUARD: unable to inspect project volumes" }
    $guard = [ordered]@{
        project = $composeProject
        existingContainerIds = @($ids)
        existingVolumes = @($volumes)
        containerCount = $ids.Count
        volumeCount = $volumes.Count
        pass = $ids.Count -eq 0 -and $volumes.Count -eq 0
    }
    Write-JsonFile (Join-Path $resultDirectory "fresh-project-guard.json") $guard
    if (-not $guard.pass) { throw "FRESH_PROJECT_GUARD: FAIL" }
}

function Assert-MvcRuntimeContract {
    param($Container)
    $environment = Get-ContainerEnvironment $Container
    $javaOptions = [string]$environment.JAVA_TOOL_OPTIONS
    $actual = [ordered]@{
        sourceRoot = "backend/doEngGameMvc"
        imageId = $Container.Image
        nanoCpus = $Container.HostConfig.NanoCpus
        memory = $Container.HostConfig.Memory
        environment = [ordered]@{
            DOENG_MVC_MAX_THREADS = $environment.DOENG_MVC_MAX_THREADS
            DOENG_HTTP_MAX_CONNECTIONS = $environment.DOENG_HTTP_MAX_CONNECTIONS
            DOENG_DB_POOL_MAX_SIZE = $environment.DOENG_DB_POOL_MAX_SIZE
            JAVA_TOOL_OPTIONS = $javaOptions
        }
    }
    $expected = [ordered]@{
        imageId = $expectedMvcImageId
        nanoCpus = 2000000000
        memory = 3221225472
        DOENG_MVC_MAX_THREADS = "400"
        DOENG_HTTP_MAX_CONNECTIONS = "400"
        DOENG_DB_POOL_MAX_SIZE = "10"
        javaXms = "512m"
        javaXmx = "2048m"
    }
    $pass = $actual.imageId -eq $expected.imageId -and $actual.nanoCpus -eq $expected.nanoCpus -and
        $actual.memory -eq $expected.memory -and
        $actual.environment.DOENG_MVC_MAX_THREADS -eq $expected.DOENG_MVC_MAX_THREADS -and
        $actual.environment.DOENG_HTTP_MAX_CONNECTIONS -eq $expected.DOENG_HTTP_MAX_CONNECTIONS -and
        $actual.environment.DOENG_DB_POOL_MAX_SIZE -eq $expected.DOENG_DB_POOL_MAX_SIZE -and
        $javaOptions -match "-Xms512m" -and $javaOptions -match "-Xmx2048m"
    Write-JsonFile (Join-Path $resultDirectory "runtime-contract.json") ([ordered]@{ expected = $expected; actual = $actual; pass = $pass })
    if (-not $pass) { throw "MVC_RUNTIME_CONTRACT: FAIL" }
}

function Assert-MockRuntimeContract {
    param($Container)
    $environment = Get-ContainerEnvironment $Container
    $actual = [ordered]@{
        imageId = $Container.Image
        nanoCpus = $Container.HostConfig.NanoCpus
        memory = $Container.HostConfig.Memory
        environment = [ordered]@{
            MOCK_AI_RESULT = $environment.MOCK_AI_RESULT
            MOCK_AI_DELAY_MS = $environment.MOCK_AI_DELAY_MS
            MOCK_AI_STATUS = $environment.MOCK_AI_STATUS
            MOCK_STORAGE_DELAY_MS = $environment.MOCK_STORAGE_DELAY_MS
            MOCK_STORAGE_STATUS = $environment.MOCK_STORAGE_STATUS
        }
    }
    $expected = [ordered]@{
        imageId = $expectedMockImageId
        nanoCpus = 4000000000
        memory = 1073741824
        MOCK_AI_RESULT = "true"
        MOCK_AI_DELAY_MS = "0"
        MOCK_AI_STATUS = "200"
        MOCK_STORAGE_DELAY_MS = "100"
        MOCK_STORAGE_STATUS = "200"
    }
    $pass = $actual.imageId -eq $expected.imageId -and $actual.nanoCpus -eq $expected.nanoCpus -and
        $actual.memory -eq $expected.memory -and
        $actual.environment.MOCK_AI_RESULT -eq $expected.MOCK_AI_RESULT -and
        $actual.environment.MOCK_AI_DELAY_MS -eq $expected.MOCK_AI_DELAY_MS -and
        $actual.environment.MOCK_AI_STATUS -eq $expected.MOCK_AI_STATUS -and
        $actual.environment.MOCK_STORAGE_DELAY_MS -eq $expected.MOCK_STORAGE_DELAY_MS -and
        $actual.environment.MOCK_STORAGE_STATUS -eq $expected.MOCK_STORAGE_STATUS
    Write-JsonFile (Join-Path $resultDirectory "mock-runtime-contract.json") ([ordered]@{ expected = $expected; actual = $actual; pass = $pass })
    if (-not $pass) { throw "MOCK_RUNTIME_CONTRACT: FAIL" }
}

$script:bootstrapStage = "IMAGE_CONTRACT"
$script:performanceWorkloadStarted = $false
$script:imageContractPass = $false
$script:freshProjectGuardPass = $false
$script:nodeRuntimeContractPass = $false
try {
    Assert-CanonicalImageContract
    $script:imageContractPass = $true
    $script:bootstrapStage = "RUN_SPECIFIC_IMAGE_TAGGING"
    Ensure-RunSpecificImageTags
    $script:bootstrapStage = "FRESH_PROJECT_GUARD"
    Assert-FreshProject
    $script:freshProjectGuardPass = $true
    $script:bootstrapStage = "NODE_RUNTIME_CONTRACT"
    $nodeContract = Resolve-NodeExecutable
    $nodeCommand = $nodeContract.resolvedExecutable
    $script:nodeRuntimeContractPass = $true
    if ($BootstrapOnly) {
        Write-JsonFile (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
            imageContract = "PASS"
            freshProjectGuard = "PASS"
            nodeRuntimeContract = "PASS"
            measurementValid = $false
            composeStarted = $false
            performanceWorkloadStarted = $false
        })
        Write-Output "BOOTSTRAP_ONLY_VALIDATION: PASS"
        exit 0
    }
} catch {
    $errorRecord = $_
    Write-JsonFile (Join-Path $resultDirectory "bootstrap-failure.json") ([ordered]@{
        stage = $script:bootstrapStage
        message = $errorRecord.Exception.Message
        exceptionType = $errorRecord.Exception.GetType().FullName
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        performanceWorkloadStarted = $false
    })
    Write-JsonFile (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
        imageContract = if ($script:imageContractPass) { "PASS" } else { "FAIL" }
        freshProjectGuard = if ($script:freshProjectGuardPass) { "PASS" } else { "FAIL" }
        nodeRuntimeContract = if ($script:nodeRuntimeContractPass) { "PASS" } else { "FAIL" }
        measurementValid = $false
        composeStarted = $false
        performanceWorkloadStarted = $false
    })
    throw
}

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
$script:startupGatePass = $false
$script:mvcRuntimeContractPass = $false
$script:mockRuntimeContractPass = $false
$script:clientAccountingPass = $false
$script:schedulerContractPass = $false
$script:observerContractPass = $false
$script:mvcFinalStatePass = $false
$script:mockFinalStatePass = $false
$script:nodeExitCode = $null
$script:clientProcessInvocationAttempted = $false
$script:clientProcessStarted = $false
$clientProcess = $null
try {
    $script:bootstrapStage = "COMPOSE_STARTUP"
    & docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride up -d --no-build mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }

    $script:bootstrapStage = "STARTUP_GATE"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepositoryRoot "experiment/scripts/wait-mvc-readiness.ps1") `
        -ComposeProject $composeProject -ServerService mvc -MainPort 8002 -ManagementPort 9002 -MockPort 9100 `
        -ComposeFilesBase64 $composeFilesBase64 -OutputPath (Join-Path $resultDirectory "startup-gate.json")
    if ($LASTEXITCODE -ne 0) { throw "Startup gate failed" }
    $script:startupGatePass = $true

    $script:bootstrapStage = "RUNTIME_CONTRACT"
    $mvcContainer = Get-InspectedContainer "mvc"
    $mockContainer = Get-InspectedContainer "experiment-mock"
    $mvcId = $mvcContainer.Id
    $mockId = $mockContainer.Id
    $mvcContainer | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultDirectory "container-state-start.json")
    $mockContainer | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultDirectory "mock-container-state-start.json")
    Assert-MvcRuntimeContract $mvcContainer
    $script:mvcRuntimeContractPass = $true
    Assert-MockRuntimeContract $mockContainer
    $script:mockRuntimeContractPass = $true

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

    $script:bootstrapStage = "CLIENT_PROCESS_BOOTSTRAP"
    $script:clientProcessInvocationAttempted = $true
    $clientStartedAt = Get-Date
    $clientProcess = Start-Process -FilePath $nodeCommand -ArgumentList @($loadScript) `
        -RedirectStandardOutput $clientStdout -RedirectStandardError $clientStderr `
        -Wait -PassThru -NoNewWindow
    $script:clientProcessStarted = $true
    $script:performanceWorkloadStarted = $true
    $nodeExitCode = $clientProcess.ExitCode
    $script:nodeExitCode = $nodeExitCode
    $clientFinishedAt = Get-Date
    Write-JsonFile (Join-Path $resultDirectory "client-process-contract.json") ([ordered]@{
        startedAt = $clientStartedAt.ToUniversalTime().ToString("o")
        finishedAt = $clientFinishedAt.ToUniversalTime().ToString("o")
        elapsedMs = ($clientFinishedAt - $clientStartedAt).TotalMilliseconds
        nodeCommand = $nodeCommand
        resolvedNodeExecutable = $nodeContract.resolvedExecutable
        nodeVersion = $nodeContract.version
        processId = $clientProcess.Id
        processStarted = $script:clientProcessStarted
        invocationAttempted = $script:clientProcessInvocationAttempted
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
    Assert-ClientAccounting $client
    $script:clientAccountingPass = $true
    if (-not (Test-SummaryContract $client.summary)) { throw "SCHEDULER_CONTRACT failed" }
    $script:schedulerContractPass = $true
    Assert-ObserverContract (Join-Path $resultDirectory "observer.summary.json")
    $script:observerContractPass = $true
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
    if ($script:clientProcessInvocationAttempted -and -not (Test-Path -LiteralPath (Join-Path $resultDirectory "client-process-contract.json"))) {
        Write-JsonFile (Join-Path $resultDirectory "client-process-contract.json") ([ordered]@{
            nodeCommand = $nodeCommand
            resolvedNodeExecutable = if ($nodeContract) { $nodeContract.resolvedExecutable } else { $null }
            nodeVersion = if ($nodeContract) { $nodeContract.version } else { $null }
            processId = if ($clientProcess) { $clientProcess.Id } else { $null }
            processStarted = $script:clientProcessStarted
            invocationAttempted = $script:clientProcessInvocationAttempted
            exitCode = $script:nodeExitCode
        })
    }
    Write-JsonFile (Join-Path $resultDirectory "bootstrap-failure.json") ([ordered]@{
        stage = $script:bootstrapStage
        message = $_.Exception.Message
        exceptionType = $_.Exception.GetType().FullName
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        performanceWorkloadStarted = $script:performanceWorkloadStarted
    })
    throw
}
finally {
    if ($observerProcess -and -not $observerProcess.HasExited) { Stop-Process -Id $observerProcess.Id -Force }
    if ($mvcLogProcess -and -not $mvcLogProcess.HasExited) { Stop-Process -Id $mvcLogProcess.Id -Force }
    if ($Execute) {
        Write-JsonFile (Join-Path $resultDirectory "application-log-capture.json") ([ordered]@{
            containerId = $mvcId
            stdoutPath = $mvcStdout
            stderrPath = $mvcStderr
            captureMode = "docker logs -f"
        })
    }
    if ($Execute -and $mvcId -and $mockId) {
        try {
            $mvcFinal = Capture-FinalContainerState "mvc" (Join-Path $resultDirectory "container-state-final.json")
            $mockFinal = Capture-FinalContainerState "experiment-mock" (Join-Path $resultDirectory "mock-container-state-final.json")
            $script:mvcFinalStatePass = $mvcFinal.running -eq $true -and $mvcFinal.restartCount -eq 0 -and $mvcFinal.oomKilled -eq $false
            $script:mockFinalStatePass = $mockFinal.running -eq $true -and $mockFinal.restartCount -eq 0 -and $mockFinal.oomKilled -eq $false
            Write-JsonFile (Join-Path $resultDirectory "mvc-final-state-contract.json") ([ordered]@{ actual = $mvcFinal; pass = $script:mvcFinalStatePass })
            Write-JsonFile (Join-Path $resultDirectory "mock-final-state-contract.json") ([ordered]@{ actual = $mockFinal; pass = $script:mockFinalStatePass })
        } catch {
            $_.Exception.Message | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultDirectory "final-state-capture-error.txt")
        }
    }
    if ($Execute) {
        $measurementValid = $script:imageContractPass -and $script:freshProjectGuardPass -and
            $script:nodeRuntimeContractPass -and $script:startupGatePass -and $script:mvcRuntimeContractPass -and $script:mockRuntimeContractPass -and
            $script:nodeExitCode -eq 0 -and $script:clientAccountingPass -and $script:schedulerContractPass -and
            $script:observerContractPass -and $script:mvcFinalStatePass -and $script:mockFinalStatePass
        Write-JsonFile (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
            imageContract = if ($script:imageContractPass) { "PASS" } else { "FAIL" }
            freshProjectGuard = if ($script:freshProjectGuardPass) { "PASS" } else { "FAIL" }
            nodeRuntimeContract = if ($script:nodeRuntimeContractPass) { "PASS" } else { "FAIL" }
            startupGate = if ($script:startupGatePass) { "PASS" } else { "FAIL" }
            mvcRuntimeContract = if ($script:mvcRuntimeContractPass) { "PASS" } else { "FAIL" }
            mockRuntimeContract = if ($script:mockRuntimeContractPass) { "PASS" } else { "FAIL" }
            nodeExitCode = $script:nodeExitCode
            clientAccountingContract = if ($script:clientAccountingPass) { "PASS" } else { "FAIL" }
            schedulerContract = if ($script:schedulerContractPass) { "PASS" } else { "FAIL" }
            observerContract = if ($script:observerContractPass) { "PASS" } else { "FAIL" }
            mvcFinalState = if ($script:mvcFinalStatePass) { "PASS" } else { "FAIL" }
            mockFinalState = if ($script:mockFinalStatePass) { "PASS" } else { "FAIL" }
            clientProcessInvocationAttempted = $script:clientProcessInvocationAttempted
            clientProcessStarted = $script:clientProcessStarted
            performanceWorkloadStarted = $script:performanceWorkloadStarted
            measurementValid = $measurementValid
        })
    }
    if ($Execute) {
        & docker compose -p $composeProject -f $baseCompose -f $imageOverride -f $runtimeOverride down --remove-orphans
    }
}
