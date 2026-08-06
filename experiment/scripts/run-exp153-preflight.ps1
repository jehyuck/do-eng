param(
    [ValidateSet("PREFLIGHT")][string]$ExecutionMode = "PREFLIGHT",
    [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$required = @(
    "experiment\docs\experiment-1-53-sink-dispatcher-ab-plan.md",
    "experiment\compose\experiment-1-53-baseline.override.yml",
    "experiment\compose\experiment-1-53-sink.override.yml",
    "experiment\compose\experiment-1-53-queue-full-smoke.override.yml",
    "experiment\compose\experiment-1-53-deadline-smoke.override.yml",
    "experiment\scripts\run-exp153-preflight.ps1",
    "experiment\scripts\run-exp153-cell.ps1"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative))) { throw "Required file missing: $relative" }
}

$base = Join-Path $repo "backend\docker-compose.experiment.yaml"
$baseline = Join-Path $repo "experiment\compose\experiment-1-53-baseline.override.yml"
$sink = Join-Path $repo "experiment\compose\experiment-1-53-sink.override.yml"
$queue = Join-Path $repo "experiment\compose\experiment-1-53-queue-full-smoke.override.yml"
$deadline = Join-Path $repo "experiment\compose\experiment-1-53-deadline-smoke.override.yml"
foreach ($override in @($baseline, $sink, $queue, $deadline)) {
    & docker compose -f $base -f $override config --quiet
    if ($LASTEXITCODE -ne 0) { throw "Compose render failed: $override" }
}

$branch = (& git -C $repo branch --show-current).Trim()
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($branch -ne "experiment/exp152-sink-dispatcher") { throw "Unexpected branch: $branch" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $head -ne $ExpectedCommit) {
    throw "Unexpected HEAD: expected $ExpectedCommit, actual $head"
}

Write-Output "EXP153_PREFLIGHT_PASS"
Write-Output "BRANCH=$branch"
Write-Output "HEAD=$head"
Write-Output "LOAD_EXECUTION=NOT_RUN"
