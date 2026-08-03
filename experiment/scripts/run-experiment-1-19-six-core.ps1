param([ValidateSet("PLAN", "EXECUTE")][string]$ExecutionMode = "PLAN")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$planRoot = Join-Path $root "backend\experiments\results\experiment-1-19\plan"
$coreRunner = Join-Path $PSScriptRoot "run-experiment-1-19-core.ps1"
$runs = @(
    @{ Condition="BASELINE"; RunIndex="001" }, @{ Condition="REMEDIATION"; RunIndex="001" },
    @{ Condition="BASELINE"; RunIndex="002" }, @{ Condition="REMEDIATION"; RunIndex="002" },
    @{ Condition="BASELINE"; RunIndex="003" }, @{ Condition="REMEDIATION"; RunIndex="003" }
)
$plan = [ordered]@{ executionStatus="NOT_RUN"; orderedRuns=@($runs | ForEach-Object { "$($_.Condition)-$($_.RunIndex)" }); pairStructure=@("PAIR-01","PAIR-02","PAIR-03"); sourceCommit="270349fa7937eb4486087d34184461ae6aaab10a"; harnessHead=((& git -C $root rev-parse HEAD).Trim()); applicationImage="sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168"; mockImage="sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1"; workload=@{vu=200;durationMs=105000;intervalMs=1000;aiDelayMs=2000;storageDelayMs=100;timeoutMs=10000;drainSeconds=30}; controlledDiff="FRESH_FIRST_LIFECYCLE_POLICY_V1"; stopOnFirstFailure=$true; allowRerun=$false; allowAdditionalRun=$false }
New-Item -ItemType Directory -Force -Path $planRoot | Out-Null
foreach ($run in $runs) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $coreRunner -Condition $run.Condition -RunIndex $run.RunIndex -ExecutionMode $ExecutionMode
    if ($LASTEXITCODE -ne 0) { throw "Run path failed: $($run.Condition)-$($run.RunIndex)" }
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $planRoot "six-core-execution-plan.json") -Encoding UTF8
[ordered]@{ executionMode=$ExecutionMode; plannedRuns=$plan.orderedRuns; warmupCount=0; k6InvocationCount=0; coreCount=0; clientResultsCreated=0; completedCoreDirectories=0; state=if($ExecutionMode -eq "PLAN"){"CORE_RUNNER_READY"}else{"EXECUTE_REQUESTED"} } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $planRoot "runner-readiness.json") -Encoding UTF8
