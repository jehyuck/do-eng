param([Parameter(Mandatory = $true)][string]$RunId)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$compose = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-3-remediation.yaml"
)
$composeArg = $compose -join ","
$composeArgs = @()
foreach ($file in $compose) { $composeArgs += @("-f", $file) }
$warmupId = "SMOKE-$RunId"

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
docker compose -p doeng-exp13 @composeArgs up -d --force-recreate flux-corrected | Out-Null
$composeExit = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($composeExit -ne 0) { throw "compose recreate failed with exit $composeExit" }
if ($LASTEXITCODE -ne 0) { throw "fresh JVM recreate failed" }
Start-Sleep -Seconds 8
if ((Invoke-RestMethod http://127.0.0.1:9001/actuator/health).status -ne "UP") {
    throw "management health is not UP"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
    -RunId $warmupId -Implementation webflux -TargetUrl http://127.0.0.1:8001/game/face `
    -ServerService flux-corrected -ComposeProject doeng-exp13 -ComposeFiles $composeArg `
    -ActiveMissions 200 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
    -DurationMs 10000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
    -EnableObservability 0 -OutcomeMode controlled-admission -DrainObservationSeconds 5
if ($LASTEXITCODE -ne 0) { throw "warm-up failed" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
    -RunId $RunId -Implementation webflux -TargetUrl http://127.0.0.1:8001/game/face `
    -ServerService flux-corrected -ComposeProject doeng-exp13 -ComposeFiles $composeArg `
    -ActiveMissions 200 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
    -DurationMs 105000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
    -EnableObservability 1 -EnableJfr 0 -EnableContainerMonitor 1 `
    -SkipApplicationSnapshot 1 -SkipMockMetrics 1 -OutcomeMode controlled-admission `
    -DrainObservationSeconds 30
if ($LASTEXITCODE -ne 0) { throw "core run failed" }
Write-Output "CORE COMPLETE: $RunId"
