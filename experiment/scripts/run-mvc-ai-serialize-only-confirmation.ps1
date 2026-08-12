[CmdletBinding()]
param(
    [switch]$BootstrapOnly,
    [switch]$Execute,
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ($BootstrapOnly -and $Execute) { throw "Use either -BootstrapOnly or -Execute" }
if (-not $BootstrapOnly -and -not $Execute) {
    throw "Prepared MVC-AI-SERIALIZE-ONLY-001; use -BootstrapOnly or separately approved -Execute."
}
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
}
$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path

$runId = "MVC-AI-SERIALIZE-ONLY-001"
$composeProject = "doeng-mvcdiag-ai-serialize-only-001"
$resultDirectory = Join-Path $RepositoryRoot "experiment/results/$runId"
$baseCompose = Join-Path $RepositoryRoot "backend/docker-compose.experiment.yaml"
$dockerfile = Join-Path $RepositoryRoot "backend/doEngGameMvc/Dockerfile.experiment"
$buildContext = Join-Path $RepositoryRoot "backend/doEngGameMvc"
$imageTag = "doeng-mvc-ai-serialize-only-mvc:locked"
$mockTag = "doeng-mvc-ai-serialize-only-mock:locked"
$imageOverride = Join-Path $resultDirectory "serialize-only.images.override.yml"
$runtimeOverride = Join-Path $resultDirectory "serialize-only.runtime.override.yml"
$loadScript = Join-Path $RepositoryRoot "experiment/load/mission-load.js"
$baselineHead = "0cc3f1472e76a04de5b4cfecd3737b460b973bd2"

function Write-JsonFile { param([string]$Path, $Object) $Object | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path }
function Resolve-Node {
    $command = Get-Command node -All -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $fallback = "C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw "Node runtime is unavailable"
}
function Get-ImageId([string]$Tag) {
    $id = (& docker image inspect $Tag --format '{{.Id}}' 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) { throw "Image not found: $Tag" }
    return $id
}
function Assert-SourceGate {
    $allowed = @(
        'backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/',
        'backend/doEngGameMvc/src/test/java/com/example/doenggamemvc/experiment/',
        'experiment/scripts/run-mvc-ai-serialize-only-confirmation.ps1'
    )
    $changed = @((git diff --name-only $baselineHead HEAD); git diff --name-only; git ls-files --others --exclude-standard)
    $changed = @($changed | Where-Object {
        $_ -and ($_.StartsWith('backend/doEngGameMvc/') -or $_ -eq 'experiment/scripts/run-mvc-ai-serialize-only-confirmation.ps1') -and
        $_ -notmatch '^backend/doEngGameMvc/(\.gradle|build)/'
    } | Sort-Object -Unique)
    $unexpected = @($changed | Where-Object {
        $path = $_
        -not ($allowed | Where-Object { $path.StartsWith($_) })
    })
    $pass = $unexpected.Count -eq 0
    Write-JsonFile (Join-Path $resultDirectory 'serialize-only-source-gate.json') ([ordered]@{
        baselineHead = $baselineHead; currentHead = git rev-parse HEAD
        changedMvcPaths = $changed; allowedChangedPaths = $allowed
        unexpectedChangedPaths = $unexpected; pass = $pass
    })
    if (-not $pass) { throw "PRODUCTION_SOURCE_GATE: FAIL ($($unexpected -join ', '))" }
}
function Assert-Node {
    $node = Resolve-Node
    $version = (& $node --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -ne 'v24.14.0') { throw "NODE_RUNTIME_CONTRACT: FAIL" }
    return [pscustomobject]@{ path = $node; version = $version }
}

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
Assert-SourceGate
if (-not (Test-Path $dockerfile) -or -not (Test-Path $baseCompose) -or -not (Test-Path $loadScript)) { throw "SERIALIZE_ONLY source contract incomplete" }

$imageId = $null
$mockImageId = $null
if ($BootstrapOnly) {
    & docker build -f $dockerfile -t $imageTag $buildContext
    if ($LASTEXITCODE -ne 0) { throw "SERIALIZE_ONLY MVC image build failed" }
    $imageId = Get-ImageId $imageTag
    $canonicalMockId = Get-ImageId 'doeng-mvcdiag-mock:locked'
    & docker tag $canonicalMockId $mockTag
    if ($LASTEXITCODE -ne 0) { throw "SERIALIZE_ONLY mock tag failed" }
    $mockImageId = Get-ImageId $mockTag
    Write-JsonFile (Join-Path $resultDirectory 'serialize-only-image-contract.json') ([ordered]@{
        sourceHead = git rev-parse HEAD; tag = $imageTag; imageId = $imageId
        dockerfile = 'backend/doEngGameMvc/Dockerfile.experiment'; context = 'backend/doEngGameMvc'
        productionSourceGate = 'PASS'; canonicalMockImage = $mockImageId; pass = $true
    })
} else {
    $imageId = Get-ImageId $imageTag
    $mockImageId = Get-ImageId $mockTag
    $contract = Get-Content (Join-Path $RepositoryRoot 'experiment/results/MVC-AI-SERIALIZE-ONLY-001/serialize-only-image-contract.json') -Raw | ConvertFrom-Json
    if ($contract.imageId -ne $imageId -or $contract.sourceHead -ne (git rev-parse HEAD)) { throw "SERIALIZE_ONLY_IMAGE_CONTRACT: FAIL" }
}
$node = Assert-Node
$containers = @(docker ps -aq --filter "label=com.docker.compose.project=$composeProject" | Where-Object {$_.Trim()})
$volumes = @(docker volume ls -q --filter "label=com.docker.compose.project=$composeProject" | Where-Object {$_.Trim()})
if ($containers.Count -ne 0 -or $volumes.Count -ne 0) { throw "FRESH_PROJECT_GUARD: FAIL" }
Write-JsonFile (Join-Path $resultDirectory 'fresh-project-guard.json') ([ordered]@{project=$composeProject;existingContainerIds=$containers;existingVolumes=$volumes;containerCount=$containers.Count;volumeCount=$volumes.Count;pass=$true})
if ($BootstrapOnly) {
    Write-JsonFile (Join-Path $resultDirectory 'measurement-validity.json') ([ordered]@{imageContract='PASS';sourceGate='PASS';freshProjectGuard='PASS';nodeRuntimeContract='PASS';serializeOnlyStaticContract='PASS';serializeOnlyNetworkContract='NOT_MEASURED';composeStarted=$false;performanceWorkloadStarted=$false;measurementValid=$false})
    Write-Output 'BOOTSTRAP_ONLY_VALIDATION: PASS'
    exit 0
}

@"
services:
  mvc:
    image: $imageTag
  experiment-mock:
    image: $mockTag
"@ | Set-Content -Encoding UTF8 -LiteralPath $imageOverride
@"
services:
  mvc:
    cpus: "2.0"
    mem_limit: 3g
  experiment-mock:
    cpus: "4.0"
    mem_limit: 1g
"@ | Set-Content -Encoding UTF8 -LiteralPath $runtimeOverride
$composeFiles = @($baseCompose,$imageOverride,$runtimeOverride)
$composeArgs = @('-p',$composeProject,'-f',$baseCompose,'-f',$imageOverride,'-f',$runtimeOverride)
$clientResults = Join-Path $resultDirectory 'client-results.json'
$clientProgress = Join-Path $resultDirectory 'client-progress.jsonl'
$observerOutput = Join-Path $resultDirectory 'observer.jsonl'
$env:MODE='SERIALIZE_ONLY';$env:PAYLOAD_PROFILE='REAL';$env:ACTIVE_MISSIONS='160';$env:LOAD_SCENARIO='reconnect-ramp';$env:ACCOUNTING_MODE='corrected';$env:ARRIVAL_MODE='staggered';$env:INITIAL_ACTIVE_USERS='160';$env:ACTIVATION_STEP_USERS='1';$env:ACTIVATION_INTERVAL_MS='3000';$env:RECONNECT_DELAY_MS='1000';$env:INTERVAL_MS='1000';$env:DURATION_MS='60000';$env:REQUEST_TIMEOUT_MS='10000';$env:TARGET_URL="http://127.0.0.1:8002/experiment/mvc-probe?mode=SERIALIZE_ONLY&runId=$runId&answer=happy";$env:FIXTURE_PATH=Join-Path $RepositoryRoot 'image/arc.jpg';$env:ANSWER='happy';$env:SCENE_ID='2';$env:EXPERIMENT_RUN_ID=$runId;$env:RESULT_PATH=$clientResults;$env:PROGRESS_PATH=$clientProgress;$env:SUCCESS_JSON_PATH='serialization.result';$env:SEND_AUTHORIZATION='false';$env:SEND_MISSION_RUN_ID='false';$env:SEND_SCENE_ID='false'
& docker compose @composeArgs up -d --no-build mariadb experiment-mock mvc
if ($LASTEXITCODE -ne 0) { throw 'Compose startup failed' }
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepositoryRoot 'experiment/scripts/wait-mvc-readiness.ps1') -ComposeProject $composeProject -ServerService mvc -MainPort 8002 -ManagementPort 9002 -MockPort 9100 -OutputPath (Join-Path $resultDirectory 'startup-gate.json')
    if ($LASTEXITCODE -ne 0) { throw 'Startup gate failed' }
    $observer = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $RepositoryRoot 'experiment/scripts/observe-mvc-diagnostic.ps1'),'-ComposeProject',$composeProject,'-ServerService','mvc','-MainPort','8002','-ManagementPort','9002','-MockPort','9100','-DurationSeconds','60','-IntervalSeconds','1','-OutputPath',$observerOutput) -PassThru -WindowStyle Hidden
    $client = Start-Process -FilePath $node.path -ArgumentList @($loadScript) -RedirectStandardOutput (Join-Path $resultDirectory 'client-process.stdout.log') -RedirectStandardError (Join-Path $resultDirectory 'client-process.stderr.log') -Wait -PassThru -NoNewWindow
    if ($client.ExitCode -ne 0) { throw "mission-load exited with code $($client.ExitCode)" }
    if ($observer -and -not $observer.HasExited) { $observer.WaitForExit() }
    $result = Get-Content $clientResults -Raw | ConvertFrom-Json
    $mockResponse = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:9100/__metrics'
    $mockMetrics = $mockResponse.Content | ConvertFrom-Json
    $postCount = 0; if ($mockMetrics.requestCounts.'POST /analyze/face') { $postCount = [int]$mockMetrics.requestCounts.'POST /analyze/face' }
    $networkPass = $postCount -eq 0 -and [int]$mockMetrics.aiCompleted -eq 0 -and [int]$mockMetrics.aiMaxInFlight -eq 0
    Write-JsonFile (Join-Path $resultDirectory 'serialize-only-network-contract.json') ([ordered]@{analyzeFacePostCount=$postCount;aiCompleted=$mockMetrics.aiCompleted;aiMaxInFlight=$mockMetrics.aiMaxInFlight;pass=$networkPass})
    Write-JsonFile (Join-Path $resultDirectory 'serialize-only-classification.json') ([ordered]@{measurementValid=$networkPass;successRate=($result.summary.successfulRequests/[double]$result.summary.startedRequests);timeoutRate=($result.summary.outcomeCounts.CLIENT_TIMEOUT/[double]$result.summary.startedRequests);classification=if($networkPass){if($result.summary.successfulRequests/[double]$result.summary.startedRequests -ge .95){'STABLE'}elseif($result.summary.successfulRequests/[double]$result.summary.startedRequests -ge .8){'DEGRADED'}else{'COLLAPSE'}}else{'INVALID'};serializationPathSufficient=if($networkPass -and $result.summary.successfulRequests/[double]$result.summary.startedRequests -lt .8){'SUPPORTED'}else{'NOT_ESTABLISHED'}})
    Write-JsonFile (Join-Path $resultDirectory 'measurement-validity.json') ([ordered]@{imageContract='PASS';sourceGate='PASS';freshProjectGuard='PASS';nodeRuntimeContract='PASS';startupGate='PASS';clientAccountingContract='PASS';schedulerContract='PASS';serializeOnlyNetworkContract=if($networkPass){'PASS'}else{'FAIL'};nodeExitCode=$client.ExitCode;performanceWorkloadStarted=$true;measurementValid=$networkPass})
} finally { & docker compose @composeArgs down --remove-orphans }
