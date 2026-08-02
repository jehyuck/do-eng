param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet("OBSERVE", "ENFORCE")][string]$AdmissionMode,
    [Parameter(Mandatory = $true)][ValidateRange(1, 1000)][int]$AdmissionLimit,
    [ValidateSet("scout", "core")][string]$RunKind = "core"
)

$ErrorActionPreference = "Stop"
$previousMode = $env:DOENG_ADMISSION_MODE
$previousLimit = $env:DOENG_ADMISSION_MAX_CONCURRENT
$env:DOENG_ADMISSION_MODE = $AdmissionMode
$env:DOENG_ADMISSION_MAX_CONCURRENT = [string]$AdmissionLimit
try {
    # Reuse the already healthy dependency project on the fixed experiment
    # ports; the runner still force-recreates flux-corrected for a fresh JVM.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
        -RunId $RunId -RunKind $RunKind `
        -ComposeOverlay "backend\docker-compose.experiment-1-9-overload-control.yaml" `
        -AiDelayMs 2000 -ComposeProject "doeng-exp18"
    if ($LASTEXITCODE -ne 0) {
        throw "Experiment 1-9 $RunKind failed: exit code $LASTEXITCODE"
    }
} finally {
    if ($null -eq $previousMode) { Remove-Item Env:DOENG_ADMISSION_MODE -ErrorAction SilentlyContinue }
    else { $env:DOENG_ADMISSION_MODE = $previousMode }
    if ($null -eq $previousLimit) { Remove-Item Env:DOENG_ADMISSION_MAX_CONCURRENT -ErrorAction SilentlyContinue }
    else { $env:DOENG_ADMISSION_MAX_CONCURRENT = $previousLimit }
}
