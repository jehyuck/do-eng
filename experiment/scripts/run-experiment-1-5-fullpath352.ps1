param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet("scout", "core")][string]$RunKind = "core"
)

$ErrorActionPreference = "Stop"
$overlay = "backend\docker-compose.experiment-1-5-fullpath352.yaml"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
    -RunId $RunId -RunKind $RunKind -ComposeOverlay $overlay
if ($LASTEXITCODE -ne 0) { throw "Experiment 1-5 run failed with exit $LASTEXITCODE" }
