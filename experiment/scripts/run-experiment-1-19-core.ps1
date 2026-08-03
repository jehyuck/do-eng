param(
    [Parameter(Mandatory = $true)][ValidateSet("BASELINE", "REMEDIATION")][string]$Condition,
    [Parameter(Mandatory = $true)][ValidateSet("001", "002", "003")][string]$RunIndex,
    [ValidateSet("PLAN", "EXECUTE")][string]$ExecutionMode = "PLAN"
)

# Experiment 1-19 core execution path. PLAN is deliberately the default and
# has no Docker/DB/mock/k6/warm-up/collector side effects.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "experiment-1-19-artifact-contract.ps1")
$sourceCommit = "270349fa7937eb4486087d34184461ae6aaab10a"
$frozenAppImage = "sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168"
$frozenMockImage = "sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1"
$mockTag = "doeng-exp119-mock-frozen-20260803:latest"
$appTag = "doeng-flux-exp119-fresh-first-20260803:latest"
$runId = "RUN-20260803-EXP119-$Condition-$RunIndex"
$warmupId = "SMOKE-20260803-EXP119-$Condition-$RunIndex"
$resultRoot = Join-Path $root "backend\experiments\results\experiment-1-19"
$planRoot = Join-Path $resultRoot "plan"
$coreRoot = Join-Path $resultRoot "core"
$runRoot = Join-Path $coreRoot $runId
$legacyRoot = Join-Path $root "experiment\results"
$legacyRunRoot = Join-Path $legacyRoot $runId
$legacyWarmupRoot = Join-Path $legacyRoot $warmupId
$composeProject = "doeng-exp119-core"
$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-12-connection-attribution.yaml",
    "backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml"
)
$requiredTools = @(
    "run-isolated-vu-success-smoke.ps1",
    "provision-experiment-users.ps1",
    "collect-diagnostic-pool.ps1",
    "invoke-experiment-1-12-capture.ps1",
    "monitor-containers.ps1",
    "aggregate-experiment-1-11-correlation.js",
    "aggregate-experiment-1-12-connection.js",
    "summarize-experiment-1-12-mechanism.js"
)
$policy = if ($Condition -eq "BASELINE") {
    [ordered]@{ leasingStrategy = "FIFO"; maxIdleTimeMs = "0"; evictionIntervalMs = "0" }
} else {
    [ordered]@{ leasingStrategy = "LIFO"; maxIdleTimeMs = "3000"; evictionIntervalMs = "1000" }
}
$requiredArtifacts = Get-Exp119RequiredArtifacts

function Write-Json([object]$Value, [string]$Path) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Image-Id([string]$Image) {
    $id = (& docker image inspect --format '{{.Id}}' $Image 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($id)) { throw "Frozen image unavailable: $Image" }
    return $id.Trim()
}
function Compose-Args { $args = @(); foreach ($file in $composeFiles) { $args += @("-f", (Join-Path $root $file)) }; return $args }
function Assert-Prerequisites {
    & git -C $root merge-base --is-ancestor "bfe379e2fbadaed2e7dda383901a2ae0131c4af3" HEAD
    if ($LASTEXITCODE -ne 0) { throw "Harness base is not present in current HEAD" }
    if ((& git -C $root cat-file -t $sourceCommit).Trim() -ne "commit") { throw "Application source commit unavailable" }
    if ((Image-Id $appTag) -ne $frozenAppImage) { throw "Frozen application image mismatch" }
    $mockId = Image-Id $mockTag
    if ($mockId -ne $frozenMockImage) { throw "Frozen mock stable tag mismatch" }
    foreach ($relative in $composeFiles) { if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) { throw "Compose file missing: $relative" } }
    foreach ($tool in $requiredTools) { if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $tool))) { throw "Required helper missing: $tool" } }
    if (-not (Test-Path -LiteralPath (Join-Path $root "experiment\load\mission-load.js"))) { throw "k6 workload script missing" }
}
function Existing-RunArtifact {
    return (Test-Path -LiteralPath $runRoot) -or (Test-Path -LiteralPath $legacyRunRoot)
}
function Command-Manifest {
    return [ordered]@{
        runId = $runId; condition = $Condition; runIndex = $RunIndex; executionMode = $ExecutionMode
        sourceCommit = $sourceCommit; applicationImageId = $frozenAppImage; mockImageTag = $mockTag; mockImageId = $frozenMockImage; mockImageBindingMode = "EXPLICIT_FROZEN_TAG"
        composeFiles = $composeFiles; environment = $policy; artifactRoot = $runRoot
        workload = [ordered]@{ vu = 200; initialVu = 200; durationMs = 105000; intervalMs = 1000; aiDelayMs = 2000; storageDelayMs = 100; requestTimeoutMs = 10000; drainSeconds = 30; appCpu = 2; appMemory = "3GiB"; poolMax = 400; poolPending = 800; dbPool = 10; admission = 320 }
        orderedSteps = @("provenance", "artifact gate", "rendered compose", "fresh recreate", "health", "idle", "reset", "fixture/auth", "runtime snapshot", "collector", "warm-up", "pre-core idle", "k6 core", "load-stop", "drain", "consistency", "artifact verification", "cleanup")
        commands = @("docker compose ... up -d --force-recreate --no-build", "run-isolated-vu-success-smoke.ps1 warm-up", "node experiment/load/mission-load.js via smoke runner", "collect-diagnostic-pool.ps1", "docker compose ... down --remove-orphans")
        requiredArtifacts = $requiredArtifacts
        forbiddenCommandsInPlanMode = @("docker compose up", "DB reset", "mock reset", "token fixture", "warm-up", "k6", "collector process", "drain", "cleanup")
    }
}

Assert-Prerequisites
$manifestPath = Join-Path $planRoot "$Condition-$RunIndex-command-manifest.json"
Write-Json (Command-Manifest) $manifestPath
if ($ExecutionMode -eq "PLAN") { Write-Output "PLAN READY: $runId"; exit 0 }

if (Existing-RunArtifact) { throw "Existing run artifact blocks execution: $runId" }
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
New-Item -ItemType File -Path (Join-Path $runRoot "RUNNING") | Out-Null
$composeArgs = Compose-Args
$previousPolicy = @{}
foreach ($entry in @{ DOENG_EXP119_APP_IMAGE = $appTag; DOENG_EXP119_MOCK_IMAGE = $mockTag; DOENG_EXTERNAL_LEASING_STRATEGY = $policy.leasingStrategy; DOENG_EXTERNAL_MAX_IDLE_TIME_MS = $policy.maxIdleTimeMs; DOENG_EXTERNAL_EVICTION_INTERVAL_MS = $policy.evictionIntervalMs }.GetEnumerator()) { $previousPolicy[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process"); [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process") }
$completedSteps = [System.Collections.Generic.List[string]]::new()
$failure = $null
$cleanupResult = "NOT_ATTEMPTED"
try {
    # The validated Experiment 1-13 execution primitives are reused below;
    # this wrapper supplies only the frozen 1-19 image, policy and run contract.
    docker compose -p $composeProject @composeArgs up -d --force-recreate --no-build mariadb experiment-mock flux-corrected
    if ($LASTEXITCODE -ne 0) { throw "Fresh recreate failed" }
    $completedSteps.Add("fresh recreate")
    # run-isolated performs health/idle/reset/auth/DB/consistency/load-stop/drain.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") -RunId $warmupId -Implementation "exp119-$Condition-warmup" -TargetUrl "http://127.0.0.1:8001/game/face" -ServerService flux-corrected -ComposeProject $composeProject -ComposeFiles ($composeFiles -join ",") -ActiveMissions 20 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 -DurationMs 5000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 -EnableObservability 0 -OutcomeMode controlled-admission -AccountingMode corrected -DrainObservationSeconds 10
    if ($LASTEXITCODE -ne 0) { throw "Warm-up failed" }
    $completedSteps.Add("warm-up")
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1") -RunId $runId -Implementation "exp119-$Condition-core" -TargetUrl "http://127.0.0.1:8001/game/face" -ServerService flux-corrected -ComposeProject $composeProject -ComposeFiles ($composeFiles -join ",") -ActiveMissions 200 -InitialActiveUsers 200 -ActivationStepUsers 200 -AiDelayMs 2000 -StorageDelayMs 100 -IntervalMs 1000 -DurationMs 105000 -RequestTimeoutMs 10000 -TargetP95Ms 10000 -EnableObservability 1 -EnableJfr 0 -EnableContainerMonitor 1 -SkipApplicationSnapshot 1 -SkipMockMetrics 1 -OutcomeMode controlled-admission -AccountingMode corrected -DrainObservationSeconds 30
    if ($LASTEXITCODE -ne 0) { throw "Core load/verification failed" }
    $completedSteps.Add("k6 core, drain and verification")
    Copy-Exp119LegacyArtifacts -LegacyRunRoot $legacyRunRoot -RunRoot $runRoot
    $completedSteps.Add("artifact copy")
    New-Item -ItemType Directory -Force -Path (Join-Path $runRoot "provenance") | Out-Null
    Write-Json ([ordered]@{ runId=$runId; sourceCommit=$sourceCommit; applicationImageId=$frozenAppImage; mockImageTag=$mockTag; mockImageId=$frozenMockImage; mockImageBindingMode="EXPLICIT_FROZEN_TAG"; condition=$Condition; policy=$policy }) (Join-Path $runRoot "provenance\runtime-provenance.json")
    $completedSteps.Add("runtime provenance")
} catch {
    $failure = $_
} finally {
    try {
        docker compose -p $composeProject @composeArgs down --remove-orphans | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Container cleanup failed" }
        $cleanupResult = "COMPLETED"
    } catch {
        $cleanupResult = "FAILED: $($_.Exception.Message)"
        if ($null -eq $failure) { $failure = $_ }
    }
    foreach ($entry in $previousPolicy.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process") }
}
if ($null -eq $failure) {
    try {
        Write-Json ([ordered]@{ runId=$runId; condition=$Condition; executionStatus="COMPLETED"; artifactValidation="PASSED"; completedSteps=@($completedSteps); cleanupResult=$cleanupResult; requiredArtifactContract=$requiredArtifacts; finalizedAt=(Get-Date).ToUniversalTime().ToString("o") }) (Join-Path $runRoot "execution-summary.json")
        Assert-Exp119RequiredArtifactCompleteness -RunRoot $runRoot
        Set-Exp119TerminalState -RunRoot $runRoot -State "COMPLETED"
    } catch {
        $failure = $_
    }
}
if ($null -ne $failure) {
    $present = @(Get-Exp119RequiredArtifacts | Where-Object { Test-Path -LiteralPath (Join-Path $runRoot $_) })
    $missing = @(Get-Exp119RequiredArtifacts | Where-Object { -not (Test-Path -LiteralPath (Join-Path $runRoot $_)) })
    Write-Json ([ordered]@{ runId=$runId; condition=$Condition; failedStep=if($completedSteps.Count -gt 0){$completedSteps[$completedSteps.Count-1]}else{"pre-run"}; errorType=$failure.Exception.GetType().FullName; errorMessage=$failure.Exception.Message; completedSteps=@($completedSteps); artifactPathsPresent=$present; artifactPathsMissing=$missing; cleanupResult=$cleanupResult; timestamp=(Get-Date).ToUniversalTime().ToString("o") }) (Join-Path $runRoot "failure-summary.json")
    Set-Exp119TerminalState -RunRoot $runRoot -State "EXECUTION_FAILED"
    throw $failure
}
