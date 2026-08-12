$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repoRoot

$baseCompose = "backend\docker-compose.experiment.yaml"
$overrideCompose = "experiment\compose\mvc400-vu120-ai1s.override.yml"
$configPath = "experiment\config\mvc400-vu120-ai1s.json"
$runId = "SPOT-MVC400-VU120-AI1S-001"

Write-Host "=== MVC400 VU120 AI1s one-off spot check ==="
Write-Host "RunId: $runId"
Write-Host "No rerun. No tuning. No WebFlux arm."

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\experiment\scripts\run-isolated-vu-success-smoke.ps1" `
  -RunId $runId `
  -Implementation "MVC400-VU120-AI1S-SPOTCHECK" `
  -TargetUrl "http://127.0.0.1:8002/game/face" `
  -ServerService "mvc" `
  -ComposeProject "doeng-mvc400-vu120-ai1s" `
  -ComposeFiles "$baseCompose,$overrideCompose" `
  -ConfigPath $configPath `
  -EnableObservability 0 `
  -EnableJfr 0 `
  -EnableContainerMonitor 0 `
  -SkipApplicationSnapshot 1 `
  -SkipMockMetrics 1

$exitCode = $LASTEXITCODE
Write-Host "Runner exit code: $exitCode"
Write-Host "Result directory: experiment\results\$runId"
exit $exitCode
