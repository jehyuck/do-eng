param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet("scout", "core")][string]$RunKind = "core",
    [string]$ComposeOverlay = "backend\docker-compose.experiment-1-4-before.yaml"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$compose = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    $ComposeOverlay
)
$composeArg = $compose -join ","
$composeArgs = @()
foreach ($file in $compose) { $composeArgs += @("-f", $file) }
$warmupId = "SMOKE-$RunId"
$node = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$collectorRoot = Join-Path $root ".experiment-work\$RunId-collectors"
New-Item -ItemType Directory -Force -Path $collectorRoot | Out-Null
$collectorProcesses = @()

function Start-Collector([string]$ScriptName, [string]$OutputName, [int]$DurationSeconds) {
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot $ScriptName),
        "-ManagementUrl", "http://127.0.0.1:9001",
        "-OutputPath", (Join-Path $collectorRoot $OutputName),
        "-DurationSeconds", [string]$DurationSeconds,
        "-IntervalMilliseconds", "1000"
    )
    return Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru
}

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
docker compose -p doeng-exp13 @composeArgs up -d --force-recreate flux-corrected | Out-Null
$composeExit = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($composeExit -ne 0) { throw "compose recreate failed with exit $composeExit" }
$healthDeadline = (Get-Date).AddSeconds(90)
$health = $null
while ((Get-Date) -lt $healthDeadline) {
    try { $health = Invoke-RestMethod http://127.0.0.1:9001/actuator/health -TimeoutSec 5 } catch { $health = $null }
    if ($null -ne $health -and $health.status -eq "UP") { break }
    Start-Sleep -Seconds 2
}
if ($null -eq $health -or $health.status -ne "UP") { throw "management health is not UP before deadline" }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
    -RunId $warmupId -Implementation webflux -TargetUrl http://127.0.0.1:8001/game/face `
    -ServerService flux-corrected -ComposeProject doeng-exp13 -ComposeFiles $composeArg `
    -ActiveMissions 20 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
    -DurationMs 5000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
    -EnableObservability 0 -OutcomeMode controlled-admission -AccountingMode corrected -DrainObservationSeconds 10 `
    -NodeCommand $node
if ($LASTEXITCODE -ne 0) { throw "warm-up failed" }

try {
    if ($RunKind -eq "core") {
        $collectorProcesses += Start-Collector "collect-phase1-observer.ps1" "phase1-observer" 145
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") `
        -RunId $RunId -Implementation webflux -TargetUrl http://127.0.0.1:8001/game/face `
        -ServerService flux-corrected -ComposeProject doeng-exp13 -ComposeFiles $composeArg `
        -ActiveMissions 200 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 `
        -DurationMs 105000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 `
        -EnableObservability 1 -EnableJfr 0 -EnableContainerMonitor 1 `
        -SkipApplicationSnapshot 1 -SkipMockMetrics 1 -OutcomeMode controlled-admission `
        -AccountingMode corrected -DrainObservationSeconds 30 -NodeCommand $node
    if ($LASTEXITCODE -ne 0) { throw "run failed" }
} finally {
    foreach ($process in $collectorProcesses) {
        $deadline = (Get-Date).AddSeconds(15)
        while (-not $process.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250; $process.Refresh() }
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}

$runDirectory = Join-Path $root "experiment\results\$RunId"
if ($RunKind -eq "core" -and (Test-Path -LiteralPath $runDirectory)) {
    Copy-Item -Force (Join-Path $collectorRoot "phase1-observer\*.jsonl") -Destination $runDirectory -ErrorAction SilentlyContinue
    Copy-Item -Force (Join-Path $collectorRoot "phase1-observer\*.summary.json") -Destination $runDirectory -ErrorAction SilentlyContinue
    $summaryPath = Join-Path $collectorRoot "phase1-observer\phase1-observer.summary.json"
    if (-not (Test-Path -LiteralPath $summaryPath)) { throw "collector summary missing: phase1-observer.summary.json" }
    $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
    if ($summary.totalFailures -ne 0) { throw "collector failures recorded in phase1 observer" }
}
Write-Output "EXP14 $RunKind COMPLETE: $RunId"
