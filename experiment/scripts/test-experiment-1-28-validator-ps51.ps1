$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'experiment-1-25-artifact-contract.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $root 'backend\experiments\results\experiment-1-28\core\RUN-20260804-EXP128-BASELINE-001-DRAIN-CONTRACT'
if (-not (Test-Path -LiteralPath $fixture)) { throw 'Diagnostic artifact missing' }
$temp = Join-Path $env:TEMP ('exp128-validator-' + [guid]::NewGuid().ToString('N'))
try {
    if (-not (Test-Exp125PathWithinRoot -RootPath (Join-Path $temp 'application') -CandidatePath (Join-Path $temp 'application\docker-logs.stdout.log'))) { throw 'P1 failed' }
    if (Test-Exp125PathWithinRoot -RootPath (Join-Path $temp 'application') -CandidatePath (Join-Path $temp 'application-evil\docker-logs.stdout.log')) { throw 'P2 failed' }
    if (Test-Exp125PathWithinRoot -RootPath (Join-Path $temp 'application') -CandidatePath (Join-Path $temp 'application\..\outside.log')) { throw 'P3 failed' }
    Copy-Item -LiteralPath $fixture -Destination $temp -Recurse
    $capturePath = Join-Path $temp 'application\docker-logs-capture.json'
    $capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
    $capture.stdoutPath = Join-Path $temp 'application\docker-logs.stdout.log'
    $capture.stderrPath = Join-Path $temp 'application\docker-logs.stderr.log'
    $capture.combinedPath = Join-Path $temp 'application\application.log'
    $capture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $capturePath -Encoding UTF8
    Assert-Exp125CaptureIdentity $temp
    Remove-Item -LiteralPath (Join-Path $temp 'application\docker-logs.stdout.log')
    $missing = $false; try { Assert-Exp125CaptureIdentity $temp } catch { $missing = $_.Exception.Message -eq 'Capture path missing' }
    if (-not $missing) { throw 'P4 failed' }
    Copy-Item -LiteralPath (Join-Path $fixture 'application\docker-logs.stdout.log') -Destination (Join-Path $temp 'application\docker-logs.stdout.log')
    $capture.stdoutPath = Join-Path $temp 'application\wrong-name.log'
    Copy-Item -LiteralPath (Join-Path $temp 'application\docker-logs.stdout.log') -Destination $capture.stdoutPath
    $capture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $capturePath -Encoding UTF8
    $mismatch = $false; try { Assert-Exp125CaptureIdentity $temp } catch { $mismatch = $_.Exception.Message -eq 'Capture filename identity failed' }
    if (-not $mismatch) { throw 'P5 failed' }
    $capture.stdoutPath = Join-Path $temp 'application\docker-logs.stdout.log'
    $capture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $capturePath -Encoding UTF8
    Assert-Exp125CaptureIdentity $temp
    Write-Output 'EXP128_VALIDATOR_P1_P6_PASS'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
