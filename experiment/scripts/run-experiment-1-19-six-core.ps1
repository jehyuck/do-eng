param([ValidateSet("PLAN", "EXECUTE")][string]$ExecutionMode = "PLAN")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$planRoot = Join-Path $root "backend\experiments\results\experiment-1-19\plan"
$coreRoot = Join-Path $root "backend\experiments\results\experiment-1-19\core"
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
$executionRuns = @()
if ($ExecutionMode -eq "EXECUTE") {
    foreach ($run in $runs) {
        $runId = "RUN-20260803-EXP119-$($run.Condition)-$($run.RunIndex)"
        $summaryPath = Join-Path $coreRoot "$runId\execution-summary.json"
        $summary = if (Test-Path -LiteralPath $summaryPath) { Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json } else { $null }
        $executionRuns += [ordered]@{ runId=$runId; started=(Test-Path -LiteralPath (Join-Path $coreRoot $runId)); completed=($null -ne $summary -and $summary.executionStatus -eq "COMPLETED" -and (Test-Path -LiteralPath (Join-Path $coreRoot "$runId\COMPLETED"))); failed=(Test-Path -LiteralPath (Join-Path $coreRoot "$runId\EXECUTION_FAILED")); clientResultsCreated=(Test-Path -LiteralPath (Join-Path $coreRoot "$runId\client-results.json")) }
    }
}
$started = @($executionRuns | Where-Object { $_.started }).Count
$completed = @($executionRuns | Where-Object { $_.completed }).Count
$failed = @($executionRuns | Where-Object { $_.failed }).Count
$clients = @($executionRuns | Where-Object { $_.clientResultsCreated }).Count
[ordered]@{ executionMode=$ExecutionMode; plannedRuns=@($plan.orderedRuns); requestedRuns=@($plan.orderedRuns); startedRuns=$started; completedRuns=$completed; failedRuns=$failed; notStartedRuns=if($ExecutionMode -eq "PLAN"){@($plan.orderedRuns)}else{@($executionRuns | Where-Object {-not $_.started} | ForEach-Object {$_.runId})}; warmupInvocations=if($ExecutionMode -eq "PLAN"){0}else{$started}; k6InvocationCount=if($ExecutionMode -eq "PLAN"){0}else{$started}; coreInvocations=if($ExecutionMode -eq "PLAN"){0}else{$started}; warmupCount=if($ExecutionMode -eq "PLAN"){0}else{$started}; coreCount=if($ExecutionMode -eq "PLAN"){0}else{$started}; completedCoreDirectories=$completed; clientResultsCreated=$clients; executionStatus=if($ExecutionMode -eq "PLAN"){"NOT_RUN"}elseif($failed -gt 0){"FAILED"}elseif($completed -eq $runs.Count){"COMPLETED"}else{"INCOMPLETE"}; stoppedAfterRun=if($ExecutionMode -eq "PLAN"){$null}elseif($failed -gt 0){($executionRuns | Where-Object {$_.failed} | Select-Object -First 1 -ExpandProperty runId)}else{$null}; state=if($ExecutionMode -eq "PLAN"){"CORE_RUNNER_READY"}else{"EXECUTE_FINISHED"}; runStates=$executionRuns } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $planRoot "runner-readiness.json") -Encoding UTF8
