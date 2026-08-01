param(
    [string]$RunId = "DIAG-DRYRUN",
    [switch]$PreflightOnly = $true,
    [string]$ManagementUrl = "http://127.0.0.1:9001"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runDirectory = Join-Path $repositoryRoot "experiment\results\$RunId"
if (-not $PreflightOnly) {
    throw "Diagnostic runner intentionally refuses load execution in harness implementation phase"
}
if (Test-Path -LiteralPath $runDirectory) {
    throw "Run directory already exists: $runDirectory"
}

$checks = [ordered]@{
    repositoryRoot = Test-Path $repositoryRoot
    collectorScript = Test-Path (Join-Path $PSScriptRoot "collect-diagnostic-pool.ps1")
    jfrInvocationInRunner = $false
    comprehensiveSnapshotInvocationInRunner = $false
    workloadExecution = $false
    managementUrl = $ManagementUrl
}
$checks | ConvertTo-Json -Depth 4
if (-not $checks.repositoryRoot -or -not $checks.collectorScript) {
    throw "Diagnostic harness preflight failed"
}
Write-Output "DIAGNOSTIC HARNESS DRY-RUN READY"
