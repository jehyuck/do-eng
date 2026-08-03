$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "experiment-1-19-artifact-contract.ps1")
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("doeng-exp119-finalization-" + [guid]::NewGuid().ToString("N"))
$node = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"

function Write-Text([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}
function New-FakeLegacyRun([string]$Path, [bool]$IncludePool) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    foreach ($name in @("run-config.json", "client-results.json", "load-stop-mock-metrics.json", "mock-drain-summary.json", "verification-summary.json", "experiment-1-13-provenance.json")) { Write-Text (Join-Path $Path $name) "{}" }
    Write-Text (Join-Path $Path "client-progress.jsonl") '{"sequence":1}'
    if ($IncludePool) { Write-Text (Join-Path $Path "pool-metrics.jsonl") '{"active":1}' }
    Write-Text (Join-Path $Path "application.log") "fixture application log"
    Write-Text (Join-Path $Path "database-metrics.jsonl") '{"active":0}'
    Write-Text (Join-Path $Path "container-stats.jsonl") '{"cpu":0}'
}
function Finalize-FakeSuccess([string]$Legacy, [string]$Destination) {
    Copy-Exp119LegacyArtifacts -LegacyRunRoot $Legacy -RunRoot $Destination
    Write-Text (Join-Path $Destination "provenance/runtime-provenance.json") "{}"
    Write-Text (Join-Path $Destination "execution-summary.json") '{"executionStatus":"COMPLETED","artifactValidation":"PASSED"}'
    Assert-Exp119RequiredArtifactCompleteness -RunRoot $Destination
    Set-Exp119TerminalState -RunRoot $Destination -State "COMPLETED"
}

try {
    $coreRoot = Join-Path $temporaryRoot "core"
    $successLegacy = Join-Path $temporaryRoot "legacy-success"
    $successRun = Join-Path $coreRoot "RUN-20260803-EXP119-BASELINE-001"
    New-FakeLegacyRun -Path $successLegacy -IncludePool $true
    Finalize-FakeSuccess -Legacy $successLegacy -Destination $successRun
    if (-not (Test-Path -LiteralPath (Join-Path $successRun "COMPLETED")) -or (Test-Path -LiteralPath (Join-Path $successRun "EXECUTION_FAILED"))) { throw "Success fixture terminal state failed" }

    $missingLegacy = Join-Path $temporaryRoot "legacy-missing"
    $missingRun = Join-Path $coreRoot "RUN-20260803-EXP119-REMEDIATION-001"
    New-FakeLegacyRun -Path $missingLegacy -IncludePool $false
    $missingRejected = $false
    try { Finalize-FakeSuccess -Legacy $missingLegacy -Destination $missingRun } catch { $missingRejected = $true; Set-Exp119TerminalState -RunRoot $missingRun -State "EXECUTION_FAILED" }
    if (-not $missingRejected -or (Test-Path -LiteralPath (Join-Path $missingRun "COMPLETED")) -or -not (Test-Path -LiteralPath (Join-Path $missingRun "EXECUTION_FAILED"))) { throw "Missing fixture terminal state failed" }

    if (-not (Test-Path -LiteralPath $node)) { throw "Bundled Node unavailable for aggregator fixture validation" }
    $aggregate = Join-Path $temporaryRoot "aggregate.json"
    & $node (Join-Path $PSScriptRoot "aggregate-experiment-1-19.js") --readiness $coreRoot $aggregate
    if ($LASTEXITCODE -ne 0) { throw "Aggregator fixture invocation failed" }
    $result = Get-Content -LiteralPath $aggregate -Raw | ConvertFrom-Json
    if ($result.completedRuns -notcontains "BASELINE-001" -or $result.completedRuns -contains "REMEDIATION-001") { throw "Aggregator finalization recognition failed: $($result | ConvertTo-Json -Compress)" }
    Write-Output "ARTIFACT_FINALIZATION_FIXTURES_PASSED"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
