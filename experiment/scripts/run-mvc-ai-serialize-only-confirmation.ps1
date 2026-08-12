[CmdletBinding()]
param(
    [switch]$BootstrapOnly,
    [switch]$Execute,
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"
if ($Execute) {
    throw "SERIALIZE_ONLY preparation does not permit -Execute"
}
if (-not $BootstrapOnly) {
    throw "Use -BootstrapOnly for SERIALIZE_ONLY preparation"
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
}
$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path

$runId = "MVC-AI-SERIALIZE-ONLY-001"
$composeProject = "doeng-mvcdiag-ai-serialize-only-001"
$resultDirectory = Join-Path $RepositoryRoot "experiment/results/$runId"
$matrixImageContract = Join-Path $RepositoryRoot "experiment/results/matrix-image-contract.json"
$probeSource = Join-Path $RepositoryRoot "backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/MvcAiRequestSerializationProbe.java"
$serviceSource = Join-Path $RepositoryRoot "backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/MvcDiagnosticProbeService.java"
$loadScript = Join-Path $RepositoryRoot "experiment/load/mission-load.js"

function Write-JsonFile {
    param([string]$Path, $Object)
    $Object | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Resolve-Node {
    $command = Get-Command node -All -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $fallback = "C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw "Node runtime is unavailable"
}

New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
$required = @($probeSource, $serviceSource, $loadScript, $matrixImageContract)
if (@($required | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -gt 0) {
    throw "SERIALIZE_ONLY source contract is incomplete"
}
$probeText = Get-Content -LiteralPath $probeSource -Raw
$serviceText = Get-Content -LiteralPath $serviceSource -Raw
if ($probeText -notmatch 'MappingJackson2HttpMessageConverter' -or
    $probeText -notmatch 'externalRestTemplate' -or
    $serviceText -notmatch 'SERIALIZE_ONLY') {
    throw "SERIALIZE_ONLY static contract failed"
}

$imageContract = Get-Content -LiteralPath $matrixImageContract -Raw | ConvertFrom-Json
$mvcImageId = [string]$imageContract.mvcImageId
$mockImageId = [string]$imageContract.mockImageId
if ([string]::IsNullOrWhiteSpace($mvcImageId) -or [string]::IsNullOrWhiteSpace($mockImageId)) {
    throw "Canonical image IDs are unavailable"
}
$null = docker image inspect $mvcImageId
if ($LASTEXITCODE -ne 0) { throw "MVC image contract failed" }
$null = docker image inspect $mockImageId
if ($LASTEXITCODE -ne 0) { throw "Mock image contract failed" }

$containerIds = @(docker ps -aq --filter "label=com.docker.compose.project=$composeProject" |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$volumeNames = @(docker volume ls -q --filter "label=com.docker.compose.project=$composeProject" |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($containerIds.Count -ne 0 -or $volumeNames.Count -ne 0) {
    throw "SERIALIZE_ONLY fresh project guard failed"
}

$node = Resolve-Node
$nodeVersion = (& $node --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v24\.14\.0$') {
    throw "SERIALIZE_ONLY Node runtime contract failed"
}

Write-JsonFile (Join-Path $resultDirectory "serialize-only-static-contract.json") ([ordered]@{
    runId = $runId
    composeProject = $composeProject
    mode = "SERIALIZE_ONLY"
    successJsonPath = "serialization.result"
    sourceProbe = "backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/MvcAiRequestSerializationProbe.java"
    sourceService = "backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/experiment/MvcDiagnosticProbeService.java"
    usesProductionRestTemplateConverter = $true
    newObjectMapper = $false
    callsAiClient = $false
    callsNetwork = $false
    performanceWorkloadStarted = $false
})
Write-JsonFile (Join-Path $resultDirectory "serialize-only-network-contract.json") ([ordered]@{
    status = "NOT_MEASURED"
    authoritativeMockAnalyzeFacePostCount = $null
    aiCompleted = $null
    aiMaxInFlight = $null
    pass = $null
})
Write-JsonFile (Join-Path $resultDirectory "measurement-validity.json") ([ordered]@{
    imageContract = "PASS"
    freshProjectGuard = "PASS"
    nodeRuntimeContract = "PASS"
    serializeOnlyStaticContract = "PASS"
    serializeOnlyNetworkContract = "NOT_MEASURED"
    composeStarted = $false
    performanceWorkloadStarted = $false
    measurementValid = $false
})
Write-Output "BOOTSTRAP_ONLY_VALIDATION: PASS"
