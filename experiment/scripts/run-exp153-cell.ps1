param(
    [Parameter(Mandatory = $true)][ValidateSet("A", "B")][string]$Cell,
    [Parameter(Mandatory = $true)][ValidateSet("PREFLIGHT", "EXECUTE")][string]$ExecutionMode,
    [Parameter(Mandatory = $true)][string]$RunId,
    [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($ExecutionMode -eq "PREFLIGHT") {
    & (Join-Path $repo "experiment\scripts\run-exp153-preflight.ps1") -ExpectedCommit $ExpectedCommit
    if ($LASTEXITCODE -ne 0) { throw "Exp153 preflight failed" }
    Write-Output "EXP153_CELL_PREFLIGHT_PASS CELL=$Cell RUN_ID=$RunId"
    exit 0
}

throw "Exp153 measurement execution is not enabled by this preparation harness. Run approval is required before load execution."
