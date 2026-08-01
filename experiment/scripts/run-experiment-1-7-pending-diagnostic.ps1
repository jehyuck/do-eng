param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet(500, 1000)][int]$AiDelayMs
)

$ErrorActionPreference = "Stop"
& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
    -RunId $RunId -RunKind core `
    -ComposeOverlay "backend\docker-compose.experiment-1-7-pending-diagnostic.yaml" `
    -AiDelayMs $AiDelayMs
if ($LASTEXITCODE -ne 0) { throw "Experiment 1-7 diagnostic failed: exit code $LASTEXITCODE" }
