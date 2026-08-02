param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet(0, 4000)][int]$MaxIdleTimeMs
)

$ErrorActionPreference = "Stop"
$match = [regex]::Match($RunId, '^RUN-20260802-EXP113-(BASELINE|REMEDIATION)-00([1-3])$')
if (-not $match.Success) { throw "invalid Experiment 1-13 run ID: $RunId" }
$condition = $match.Groups[1].Value
$expectedIdle = if ($condition -eq "BASELINE") { 0 } else { 4000 }
if ($MaxIdleTimeMs -ne $expectedIdle) { throw "run ID and maxIdleTime mismatch" }

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeProject = "doeng-exp113"
$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-12-connection-attribution.yaml",
    "backend\docker-compose.experiment-1-13-idle-freshness.yaml"
)
$composeArgs = @()
foreach ($file in $composeFiles) { $composeArgs += @("-f", $file) }
$composeArg = $composeFiles -join ","
$node = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$resultsRoot = Join-Path $root "experiment\results"
$runDirectory = Join-Path $resultsRoot $RunId
$warmupId = "SMOKE-$RunId"
$captureWork = Join-Path $root ".experiment-work\experiment-1-13-capture-$RunId"
$poolWork = Join-Path $captureWork "pool-metrics.jsonl"
$sourceCommit = (& git -C $root rev-parse HEAD).Trim()
$previousIdle = $env:DOENG_EXTERNAL_MAX_IDLE_TIME_MS
$previousCaptureRoot = $env:EXP112_CAPTURE_ROOT
$env:DOENG_EXTERNAL_MAX_IDLE_TIME_MS = [string]$MaxIdleTimeMs
$env:EXP112_CAPTURE_ROOT = $captureWork.Replace("\", "/")
$captureStarted = $false
$poolProcess = $null

if (Test-Path -LiteralPath $runDirectory) { throw "core result already exists: $runDirectory" }
if (Test-Path -LiteralPath (Join-Path $resultsRoot $warmupId)) { throw "warm-up result already exists: $warmupId" }
if (Test-Path -LiteralPath $captureWork) { throw "capture work already exists: $captureWork" }

$hashRows = foreach ($file in $composeFiles) {
    $absolute = Join-Path $root $file
    [ordered]@{ path = $file; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToLowerInvariant() }
}
$hashText = ($hashRows | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $composeHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashText))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }

function Wait-Health([string]$Url) {
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try { $health = Invoke-RestMethod $Url -TimeoutSec 5; if ($health.status -eq "UP" -or $health.status -eq "ok") { return } } catch {}
        Start-Sleep -Seconds 2
    }
    throw "health timeout: $Url"
}

try {
    docker compose -p $composeProject @composeArgs up -d --force-recreate mariadb experiment-mock flux-corrected | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fresh service recreate failed" }
    Wait-Health "http://127.0.0.1:9001/actuator/health"
    Wait-Health "http://127.0.0.1:9100/health"
    $idle = Invoke-RestMethod "http://127.0.0.1:9100/__metrics" -TimeoutSec 5
    if ($idle.aiInFlight -ne 0 -or $idle.storageInFlight -ne 0) { throw "pre-run mock backlog is not zero" }

    & (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") -Action Start -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles
    $captureStarted = $true

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
        -RunId $warmupId -Implementation "exp113-$condition-warmup" `
        -TargetUrl http://127.0.0.1:8001/game/face -ServerService flux-corrected `
        -ComposeProject $composeProject -ComposeFiles $composeArg `
        -ActiveMissions 20 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
        -DurationMs 5000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
        -EnableObservability 0 -OutcomeMode controlled-admission -AccountingMode corrected `
        -DrainObservationSeconds 10 -NodeCommand $node
    if ($LASTEXITCODE -ne 0) { throw "Experiment 1-13 warm-up failed" }

    $poolArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "collect-diagnostic-pool.ps1"),
        "-ManagementUrl", "http://127.0.0.1:9001", "-OutputPath", $poolWork,
        "-DurationSeconds", "140", "-IntervalMilliseconds", "1000"
    )
    $poolProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $poolArguments -WorkingDirectory $root -WindowStyle Hidden -PassThru

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
        -RunId $RunId -Implementation "exp113-$condition-core" `
        -TargetUrl http://127.0.0.1:8001/game/face -ServerService flux-corrected `
        -ComposeProject $composeProject -ComposeFiles $composeArg `
        -ActiveMissions 200 -InitialActiveUsers 200 -ActivationStepUsers 200 `
        -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
        -DurationMs 105000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
        -EnableObservability 1 -EnableJfr 0 -EnableContainerMonitor 1 `
        -SkipApplicationSnapshot 1 -SkipMockMetrics 1 -OutcomeMode controlled-admission `
        -AccountingMode corrected -DrainObservationSeconds 30 -NodeCommand $node
    if ($LASTEXITCODE -ne 0) { throw "Experiment 1-13 core failed" }
    Wait-Process -Id $poolProcess.Id
    if ($poolProcess.ExitCode -ne 0) { throw "pool collector failed" }
} finally {
    if ($poolProcess -and -not $poolProcess.HasExited) { Stop-Process -Id $poolProcess.Id -ErrorAction SilentlyContinue }
    if ($captureStarted) {
        & (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") -Action Stop -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles
    }
    $containerOutput = docker compose -p $composeProject @composeArgs ps -q flux-corrected
    $container = if ($null -eq $containerOutput) { "" } else { $containerOutput.ToString().Trim() }
    if (-not [string]::IsNullOrWhiteSpace($container) -and (Test-Path -LiteralPath $runDirectory)) {
        $oldError = $ErrorActionPreference; $ErrorActionPreference = "SilentlyContinue"
        docker logs --timestamps $container 2>&1 | ForEach-Object { $_.ToString() } | Out-File -LiteralPath (Join-Path $runDirectory "application.log") -Encoding UTF8
        $ErrorActionPreference = $oldError
    }
    if ($null -eq $previousIdle) { Remove-Item Env:DOENG_EXTERNAL_MAX_IDLE_TIME_MS -ErrorAction SilentlyContinue } else { $env:DOENG_EXTERNAL_MAX_IDLE_TIME_MS = $previousIdle }
    if ($null -eq $previousCaptureRoot) { Remove-Item Env:EXP112_CAPTURE_ROOT -ErrorAction SilentlyContinue } else { $env:EXP112_CAPTURE_ROOT = $previousCaptureRoot }
}

& (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") -Action Verify -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles
$captureDirectory = Join-Path $runDirectory "capture"
New-Item -ItemType Directory -Force -Path $captureDirectory | Out-Null
Copy-Item -Force (Join-Path $captureWork "application\application-control.pcap") $captureDirectory
Copy-Item -Force (Join-Path $captureWork "application\application-control.txt") $captureDirectory
Copy-Item -Force (Join-Path $captureWork "mock\mock-control.pcap") $captureDirectory
Copy-Item -Force (Join-Path $captureWork "mock\mock-control.txt") $captureDirectory
Copy-Item -Force $poolWork (Join-Path $runDirectory "pool-metrics.jsonl")
Copy-Item -Force ($poolWork + ".summary.json") (Join-Path $runDirectory "pool-metrics.summary.json")

& $node (Join-Path $PSScriptRoot "aggregate-experiment-1-11-correlation.js") $runDirectory
if ($LASTEXITCODE -ne 0) { throw "request aggregation failed" }
& $node (Join-Path $PSScriptRoot "aggregate-experiment-1-12-connection.js") $runDirectory
if ($LASTEXITCODE -ne 0) { throw "connection aggregation failed" }
& $node (Join-Path $PSScriptRoot "summarize-experiment-1-12-mechanism.js") $runDirectory
if ($LASTEXITCODE -ne 0) { throw "mechanism aggregation failed" }

$poolSummary = Get-Content -Raw -LiteralPath (Join-Path $runDirectory "pool-metrics.summary.json") | ConvertFrom-Json
if ($poolSummary.failures -ne 0) { throw "pool collector recorded failures" }
$imageId = (docker image inspect doeng-flux-exp113-idle-20260802:latest --format "{{.Id}}").Trim()
$mockContainerOutput = docker compose -p $composeProject @composeArgs ps -q experiment-mock
$mockContainer = if ($null -eq $mockContainerOutput) { "" } else { $mockContainerOutput.ToString().Trim() }
if ([string]::IsNullOrWhiteSpace($mockContainer)) { throw "mock container provenance unavailable" }
$mockImageId = (docker inspect $mockContainer --format "{{.Image}}").Trim()
[ordered]@{
    runId = $RunId; condition = $condition; maxIdleTimeMs = $MaxIdleTimeMs
    sourceCommit = $sourceCommit; image = "doeng-flux-exp113-idle-20260802:latest"; imageId = $imageId
    mockImageId = $mockImageId; composeHash = $composeHash; composeFiles = $hashRows
    poolCollectorFailures = $poolSummary.failures; captureSidecarsActiveBeforeWarmup = $true
} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "experiment-1-13-provenance.json")
