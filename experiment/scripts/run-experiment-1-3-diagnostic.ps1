param([Parameter(Mandatory = $true)][string]$RunId)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$tmp = Join-Path $root "experiment\.tmp-exp13"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
foreach ($name in @("stage-live.jsonl", "pool-live.jsonl", "stage-live.jsonl.summary.json", "pool-live.jsonl.summary.json")) {
    Remove-Item -LiteralPath (Join-Path $tmp $name) -ErrorAction SilentlyContinue
}

$stage = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $PSScriptRoot "collect-stage-observation.ps1"),
    "-ManagementUrl", "http://127.0.0.1:9001",
    "-OutputPath", (Join-Path $tmp "stage-live.jsonl"),
    "-DurationSeconds", "180"
)
$pool = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $PSScriptRoot "collect-diagnostic-pool.ps1"),
    "-ManagementUrl", "http://127.0.0.1:9001",
    "-OutputPath", (Join-Path $tmp "pool-live.jsonl"),
    "-DurationSeconds", "180"
)

$compose = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-3-diagnostic.yaml"
)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
    -RunId $RunId -Implementation webflux -TargetUrl http://127.0.0.1:8001/game/face `
    -ServerService flux-corrected -ComposeProject doeng-exp13 `
    -ComposeFiles ($compose -join ",") -ActiveMissions 200 `
    -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 -DurationMs 105000 `
    -RequestTimeoutMs 10000 -TargetP95Ms 10000 -EnableObservability 1 `
    -EnableJfr 0 -EnableContainerMonitor 1 -SkipApplicationSnapshot 1 `
    -SkipMockMetrics 1 -DrainObservationSeconds 30
$exitCode = $LASTEXITCODE

$stage.WaitForExit()
$pool.WaitForExit()
if ($exitCode -ne 0) {
    throw "Diagnostic runner failed with exit code $exitCode"
}

$runDirectory = Join-Path $root "experiment\results\$RunId"
Copy-Item (Join-Path $tmp "stage-live.jsonl") (Join-Path $runDirectory "stage-observation.jsonl") -Force
Copy-Item (Join-Path $tmp "stage-live.jsonl.summary.json") (Join-Path $runDirectory "stage-observation.summary.json") -Force
Copy-Item (Join-Path $tmp "pool-live.jsonl") (Join-Path $runDirectory "pool-observation.jsonl") -Force
Copy-Item (Join-Path $tmp "pool-live.jsonl.summary.json") (Join-Path $runDirectory "pool-observation.summary.json") -Force
Write-Output "DIAGNOSTIC RUN COMPLETE: $RunId"
