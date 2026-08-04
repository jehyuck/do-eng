param([string]$RunDate='PLAN-DATE',[ValidateSet('PLAN','EXECUTE')][string]$ExecutionMode='PLAN')
$ErrorActionPreference='Stop';$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path;$result=Join-Path $root 'backend\experiments\results\experiment-1-26';New-Item -ItemType Directory -Force (Join-Path $result 'plan')|Out-Null
$runs=@('BASELINE-001','REMEDIATION-001','BASELINE-002','REMEDIATION-002','BASELINE-003','REMEDIATION-003')
if($ExecutionMode-ne'PLAN'){throw 'EXP126_PRODUCTION_EXECUTION_NOT_ALLOWED_IN_RECOVERY'}
$ledger=[ordered]@{experiment='Experiment 1-26';runDate=$RunDate;executionMode='PLAN';requestedRuns=$runs;startedRuns=0;completedRuns=0;failedRuns=0;warmupInvocations=0;coreInvocations=0;k6Invocations=0;executionStatus='NOT_RUN';policyDecision='NOT_RUN'};$ledger|ConvertTo-Json -Depth 10|Set-Content (Join-Path $result 'plan/runner-readiness.json') -Encoding UTF8;Write-Output 'EXP126_PLAN_READY'
