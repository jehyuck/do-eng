param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet("SHARED", "ISOLATED")][string]$PoolMode,
    [ValidateSet("scout", "core")][string]$RunKind = "core"
)

$ErrorActionPreference = "Stop"
$previousPoolMode = $env:DOENG_EXTERNAL_POOL_MODE
$env:DOENG_EXTERNAL_POOL_MODE = $PoolMode
try {
    # The existing lifecycle runner owns fresh-JVM, warm-up, observer, drain,
    # consistency and provenance handling. Scout is run with the same collector
    # path but is excluded from the final aggregate by the ledger.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
        -RunId $RunId -RunKind core `
        -ComposeOverlay "backend\docker-compose.experiment-1-8-pool-isolation.yaml" `
        -AiDelayMs 2000 -ComposeProject "doeng-exp18"
    if ($LASTEXITCODE -ne 0) {
        throw "Experiment 1-8 $RunKind failed: exit code $LASTEXITCODE"
    }
} finally {
    if ($null -eq $previousPoolMode) {
        Remove-Item Env:DOENG_EXTERNAL_POOL_MODE -ErrorAction SilentlyContinue
    } else {
        $env:DOENG_EXTERNAL_POOL_MODE = $previousPoolMode
    }
}
