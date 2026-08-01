param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet("scout", "core")][string]$RunKind = "core",
    [Parameter(Mandatory = $true)][ValidateSet(500, 1000)][int]$AiDelayMs
)

$ErrorActionPreference = "Stop"
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
    -RunId $RunId -RunKind $RunKind `
    -ComposeOverlay "backend\docker-compose.experiment-1-4-before.yaml" `
    -AiDelayMs $AiDelayMs
if ($LASTEXITCODE -ne 0) { throw "Experiment 1-6 failed: exit code $LASTEXITCODE" }
