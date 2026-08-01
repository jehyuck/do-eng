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
    [ValidateRange(2, 1000)]
    [int]$ActiveMissions,
    [string]$FixturePath = "image\arc.jpg",
    [long]$SceneId = 2,
    [string]$Answer = "happy",
    [int]$AiDelayMs = 500,
    [int]$StorageDelayMs = 100,
    [int]$IntervalMs = 3000,
    [int]$DurationMs = 3500,
    [int]$RequestTimeoutMs = 10000,
    [ValidateSet("aligned", "staggered")]
    [string]$ArrivalMode = "aligned",
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"
$smokeScript = Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1"
if ($RunId -notmatch "^RUN-") {
    throw "RunId must start with RUN-"
}
$warmupRunId = $RunId -replace "^RUN-", "SMOKE-"

$commonArguments = @{
    Implementation = $Implementation
    TargetUrl = $TargetUrl
    ServerService = $ServerService
    ComposeProject = $ComposeProject
    ActiveMissions = $ActiveMissions
    FixturePath = $FixturePath
    SceneId = $SceneId
    Answer = $Answer
    AiDelayMs = $AiDelayMs
    StorageDelayMs = $StorageDelayMs
    IntervalMs = $IntervalMs
    DurationMs = $DurationMs
    RequestTimeoutMs = $RequestTimeoutMs
    ArrivalMode = $ArrivalMode
}
if (-not [string]::IsNullOrWhiteSpace($NodeCommand)) {
    $commonArguments.NodeCommand = $NodeCommand
}

# Warm-up uses a separate user cohort and is intentionally excluded from the
# measured run. Its artifacts remain under its own SMOKE run ID.
& $smokeScript -RunId $warmupRunId @commonArguments
if ($LASTEXITCODE -ne 0) { throw "Warm-up success burst failed" }

& $smokeScript -RunId $RunId -EnableObservability 1 @commonArguments
if ($LASTEXITCODE -ne 0) { throw "Measured success burst failed" }
