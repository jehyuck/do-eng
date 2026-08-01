param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet("scout", "core")][string]$RunKind = "core"
)

$script = Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
    -RunId $RunId -RunKind $RunKind `
    -ComposeOverlay "backend\docker-compose.experiment-1-4-after.yaml"
if ($LASTEXITCODE -ne 0) { throw "Phase 2 runner failed: $RunId" }
