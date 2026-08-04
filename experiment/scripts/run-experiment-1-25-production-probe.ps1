param([ValidateSet('PLAN','EXECUTE')][string]$ExecutionMode='PLAN')
$ErrorActionPreference='Stop';$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; . (Join-Path $PSScriptRoot 'experiment-1-25-artifact-path-preflight.ps1')
$result=Join-Path $root 'backend\experiments\results\experiment-1-25\probe-closure';New-Item -ItemType Directory -Force $result|Out-Null;$rows=@()
foreach($condition in @('BASELINE','REMEDIATION')){
 $runRoot=Join-Path $result $condition; if(Test-Path $runRoot){throw "PROBE_COLLISION: $runRoot"}
 $pre=Invoke-Exp125ArtifactPathPreflight -RunId "PROBE-$condition" -RunRoot $runRoot;Assert-Exp125ArtifactPathPreflight $runRoot
 $compose=@('backend\docker-compose.experiment.yaml','backend\docker-compose.app-instance-t3-medium.yaml','backend\docker-compose.mock-headroom-4cpu.yaml','backend\docker-compose.http-pool-400.yaml','backend\docker-compose.mock-memory-headroom.yaml','backend\docker-compose.experiment-1-12-connection-attribution.yaml','backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml')
 $rows+=[ordered]@{condition=$condition;preflightStatus=$pre.preflightStatus;composeCount=$compose.Count;warmupInvoked=0;k6Invoked=0;coreInvoked=0}
}
$summary=[ordered]@{experiment='Experiment 1-25';executionMode=$ExecutionMode;conditions=$rows;status='PRODUCTION_PATH_PROBE_PASSED';performanceExecuted=$false};$summary|ConvertTo-Json -Depth 10|Set-Content (Join-Path $result 'probe-summary.json') -Encoding UTF8;Write-Output 'EXP125_PRODUCTION_PATH_PROBE_PASS'







