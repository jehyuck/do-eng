param(
    [string]$OutputDirectory = ".experiment-work\experiment-1-12-controls"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$output = [System.IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$captureWork = Join-Path $output "capture-work"
$captureOutput = Join-Path $output "capture"
$composeProject = "doeng-exp112-control"
$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-12-connection-attribution.yaml"
)
$composeArgs = @()
foreach ($file in $composeFiles) { $composeArgs += @("-f", $file) }
$node = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$previousLimit = $env:DOENG_ADMISSION_MAX_CONCURRENT
$previousTarget = $env:TARGET_URL
$previousMock = $env:MOCK_URL
$previousResult = $env:RESULT_PATH
$env:DOENG_ADMISSION_MAX_CONCURRENT = "1"
$captureStarted = $false

function Wait-Health([string]$Url) {
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod $Url -TimeoutSec 5
            if ($health.status -eq "UP" -or $health.status -eq "ok") { return }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "health timeout: $Url"
}

New-Item -ItemType Directory -Force -Path $output,$captureOutput | Out-Null

try {
    docker compose -p $composeProject @composeArgs build experiment-mock | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mock build failed" }
    docker compose -p $composeProject @composeArgs up -d --force-recreate mariadb experiment-mock flux-corrected | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "control environment startup failed" }
    Wait-Health "http://127.0.0.1:9001/actuator/health"
    Wait-Health "http://127.0.0.1:9100/health"

    & (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") `
        -Action Start -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles
    $captureStarted = $true

    $env:TARGET_URL = "http://127.0.0.1:8001/game/face?answer=happy&sceneId=2"
    $env:MOCK_URL = "http://127.0.0.1:9100"
    $env:RESULT_PATH = Join-Path $output "control-result.json"
    & $node (Join-Path $root "experiment\load\experiment-1-12-controls.e2e.test.js")
    if ($LASTEXITCODE -ne 0) { throw "control scenarios failed" }
} finally {
    if ($captureStarted) {
        & (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") `
            -Action Stop -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles
        $captureStarted = $false
    }
    $containerOutput = docker compose -p $composeProject @composeArgs ps -q flux-corrected
    $container = if ($null -eq $containerOutput) { "" } else { $containerOutput.ToString().Trim() }
    if (-not [string]::IsNullOrWhiteSpace($container)) {
        $oldError = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        docker logs --timestamps $container 2>&1 | ForEach-Object { $_.ToString() } |
            Out-File -LiteralPath (Join-Path $output "application.log") -Encoding UTF8
        $ErrorActionPreference = $oldError
    }
    if ($null -eq $previousLimit) { Remove-Item Env:DOENG_ADMISSION_MAX_CONCURRENT -ErrorAction SilentlyContinue }
    else { $env:DOENG_ADMISSION_MAX_CONCURRENT = $previousLimit }
    if ($null -eq $previousTarget) { Remove-Item Env:TARGET_URL -ErrorAction SilentlyContinue }
    else { $env:TARGET_URL = $previousTarget }
    if ($null -eq $previousMock) { Remove-Item Env:MOCK_URL -ErrorAction SilentlyContinue }
    else { $env:MOCK_URL = $previousMock }
    if ($null -eq $previousResult) { Remove-Item Env:RESULT_PATH -ErrorAction SilentlyContinue }
    else { $env:RESULT_PATH = $previousResult }
}

& (Join-Path $PSScriptRoot "invoke-experiment-1-12-capture.ps1") `
    -Action Verify -CaptureRoot $captureWork -ComposeProject $composeProject -ComposeFiles $composeFiles

Copy-Item -Force (Join-Path $captureWork "application\application-control.pcap") $captureOutput
Copy-Item -Force (Join-Path $captureWork "application\application-control.txt") $captureOutput
Copy-Item -Force (Join-Path $captureWork "mock\mock-control.pcap") $captureOutput
Copy-Item -Force (Join-Path $captureWork "mock\mock-control.txt") $captureOutput

$control = Get-Content -Raw -LiteralPath (Join-Path $output "control-result.json") | ConvertFrom-Json
[ordered]@{
    summary = [ordered]@{ experimentRunId = "EXP112-CONTROL" }
    requests = $control.requests
} | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $output "client-results.json")
[ordered]@{
    aiLifecycleEvents = $control.aiLifecycleEvents
} | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $output "mock-requests.json")

& $node (Join-Path $PSScriptRoot "aggregate-experiment-1-11-correlation.js") $output
if ($LASTEXITCODE -ne 0) { throw "control request aggregation failed" }
& $node (Join-Path $PSScriptRoot "aggregate-experiment-1-12-connection.js") $output
if ($LASTEXITCODE -ne 0) { throw "control connection aggregation failed" }
& $node (Join-Path $PSScriptRoot "verify-experiment-1-12-controls.js") $output
if ($LASTEXITCODE -ne 0) { throw "positive control verification failed" }
