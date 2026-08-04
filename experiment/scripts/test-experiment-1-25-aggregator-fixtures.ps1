param([switch]$KeepFixture)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture=Join-Path $repo 'backend\experiments\results\experiment-1-25\fixture-aggregator'
$core=Join-Path $fixture 'core';$out=Join-Path $fixture 'aggregate.json'
if(Test-Path $fixture){Remove-Item $fixture -Recurse -Force}
$composePaths=@('backend\docker-compose.experiment.yaml','backend\docker-compose.app-instance-t3-medium.yaml','backend\docker-compose.mock-headroom-4cpu.yaml','backend\docker-compose.http-pool-400.yaml','backend\docker-compose.mock-memory-headroom.yaml','backend\docker-compose.experiment-1-12-connection-attribution.yaml','backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml')
$compose=@($composePaths|ForEach-Object{[ordered]@{path=$_;sha256=(Get-FileHash (Join-Path $repo $_) -Algorithm SHA256).Hash.ToLowerInvariant()}})
$required=@('run-config.json','client-results.json','client-progress.jsonl','pool/pool-metrics.jsonl','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','pool/collector-lifecycle.json','application/container-stop.json','application/docker-logs.stdout.log','application/docker-logs.stderr.log','application/docker-logs-capture.json','application/application.log','database/database-metrics.jsonl','container/container-stats.jsonl','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/artifact-path-preflight.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json')
$arms=@('BASELINE-001','REMEDIATION-001','BASELINE-002','REMEDIATION-002','BASELINE-003','REMEDIATION-003')
function Write-Json($p,$v){New-Item -ItemType Directory -Force (Split-Path $p)|Out-Null;$json=$v|ConvertTo-Json -Depth 20;[IO.File]::WriteAllText($p,$json,(New-Object Text.UTF8Encoding($false)))}
function New-ValidRun([string]$arm){
 $id="RUN-20990101-EXP125-$arm";$condition=if($arm.StartsWith('BASELINE')){'BASELINE'}else{'REMEDIATION'};$dir=Join-Path $core $id;$app=Join-Path $dir 'application';$pool=Join-Path $dir 'pool';$prov=Join-Path $dir 'provenance'
 $times=@{pre='2026-08-04T00:00:00.000Z';preEnd='2026-08-04T00:00:00.100Z';collector='2026-08-04T00:00:01.000Z';first='2026-08-04T00:00:01.100Z';core='2026-08-04T00:00:02.000Z';coreEnd='2026-08-04T00:00:03.000Z';cover='2026-08-04T00:00:03.100Z';stopSignal='2026-08-04T00:00:03.200Z';collectorEnd='2026-08-04T00:00:03.300Z';stop='2026-08-04T00:00:04.000Z';stopEnd='2026-08-04T00:00:04.100Z';cap='2026-08-04T00:00:04.200Z';capEnd='2026-08-04T00:00:04.300Z';valid='2026-08-04T00:00:04.400Z';final='2026-08-04T00:00:04.500Z'}
 $policy=if($condition -eq 'BASELINE'){@{leasingStrategy='FIFO';maxIdleTimeMs=0;evictionIntervalMs=0}}else{@{leasingStrategy='LIFO';maxIdleTimeMs=3000;evictionIntervalMs=1000}}
 $cfg=[ordered]@{experiment='Experiment 1-25';runId=$id;runDate='20990101';condition=$condition;executionMode='EXECUTE';applicationImageTag='doeng-flux-exp119-fresh-first-20260803:latest';applicationImageId='sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168';mockImageTag='doeng-exp119-mock-frozen-20260803:latest';mockImageId='sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1';policy=$policy;composeFiles=$compose;workload=@{vu=200}}
 Write-Json (Join-Path $dir 'run-config.json') $cfg
 $preDirs=@('application','pool','database','container','mock','drain','provenance')|ForEach-Object{[ordered]@{name=$_;path=(Join-Path $dir $_);canonicalPath=(Join-Path $dir $_);directoryExistedBefore=$true;directoryExistsAfterInitialization=$true;created=$false;pathContained=$true;writeProbeCreated=$true;writeProbeContentVerified=$true;writeProbePassed=$true;deleteProbePassed=$true;probeFileAbsentAfterDelete=$true}}
 Write-Json (Join-Path $prov 'artifact-path-preflight.json') ([ordered]@{runId=$id;startedAt=$times.pre;completedAt=$times.preEnd;requiredDirectories=$preDirs;preflightStatus='ARTIFACT_PATH_PREFLIGHT_PASSED';failureType=$null})
 $tl=[ordered]@{artifactPathPreflightStartedAt=$times.pre;artifactPathPreflightCompletedAt=$times.preEnd;collectorProcessStartedAt=$times.collector;collectorFirstValidSampleAt=$times.first;coreInvocationStartedAt=$times.core;coreInvocationCompletedAt=$times.coreEnd;collectorFirstSampleCoveringCoreEndAt=$times.cover;postCoreCoverageConfirmedAt=$times.cover;collectorStopSignalIssuedAt=$times.stopSignal;collectorProcessCompletedAt=$times.collectorEnd;applicationStopStartedAt=$times.stop;applicationStopCompletedAt=$times.stopEnd;applicationLogCaptureStartedAt=$times.cap;applicationLogCaptureCompletedAt=$times.capEnd;artifactValidationCompletedAt=$times.valid;finalizationCompletedAt=$times.final}
 Write-Json (Join-Path $prov 'execution-timeline.json') $tl
 Write-Json (Join-Path $pool 'pool-metrics.jsonl.summary.json') ([ordered]@{collectorStatus='COLLECTOR_STOPPED_BY_SIGNAL';stopSignalObserved=$true;failures=0})
 Write-Json (Join-Path $pool 'collector-lifecycle.json') ([ordered]@{mode='CORE_BOUND_STOP_SIGNAL';lifecycleStatus='COLLECTOR_LIFECYCLE_PASSED';failureType=$null;stopSignalObserved=$true;processExitCode=0;summaryCollectorStatus='COLLECTOR_STOPPED_BY_SIGNAL';summaryFailures=0;summaryStopSignalObserved=$true;collectorFirstSampleCoveringCoreEndAt=$times.cover;postCoreCoverageConfirmedAt=$times.cover;collectorStopSignalIssuedAt=$times.stopSignal;collectorProcessCompletedAt=$times.collectorEnd})
 Write-Json (Join-Path $pool 'collector-coverage.json') ([ordered]@{coverageStatus='COLLECTOR_COVERAGE_PASSED';coversCoreStart=$true;coversCoreEnd=$true;timestampsNonDecreasing=$true;invalidSampleCount=0;collectorFailures=0;validSampleCount=3;collectorFirstSampleCoveringCoreEndAt=$times.cover;waitReturnedFirstCoveringSampleAt=$times.cover;coreInvocationCompletedAt=$times.coreEnd;collectorProcessStartedAt=$times.collector;collectorFirstValidSampleAt=$times.first;coreInvocationStartedAt=$times.core;collectorProcessCompletedAt=$times.collectorEnd})
 Write-Json (Join-Path $prov 'runtime-provenance.json') ([ordered]@{runtimeProvenance='ACTUAL';runId=$id;runDate='20990101';condition=$condition;applicationImageTag=$cfg.applicationImageTag;applicationImageId=$cfg.applicationImageId;mockImageTag=$cfg.mockImageTag;mockImageId=$cfg.mockImageId;policy=$policy;collectorMode='CORE_BOUND_STOP_SIGNAL';composeFiles=$compose})
 $sample=[ordered]@{timestamp=$times.cover;failure=$null};[IO.File]::WriteAllText((Join-Path $pool 'pool-metrics.jsonl'),($sample|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
 $stop=[ordered]@{runId=$id;containerId='fixture-container';command='docker compose stop';startedAt=$times.stop;completedAt=$times.stopEnd;gracePeriodSeconds=15;processTimeoutSeconds=30;timedOut=$false;exitCode=0;stateBefore='running';stateAfter='exited';containerStillExists=$true;inspectExitCodeBefore=0;inspectExitCodeAfter=0;stopStatus='APPLICATION_CONTAINER_STOPPED'};Write-Json (Join-Path $app 'container-stop.json') $stop
 [IO.File]::WriteAllText((Join-Path $app 'docker-logs.stdout.log'),'stdout',(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText((Join-Path $app 'docker-logs.stderr.log'),'',(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText((Join-Path $app 'application.log'),'application',(New-Object Text.UTF8Encoding($false)))
 $relApp="/repo/backend/experiments/results/experiment-1-25/fixture-aggregator/core/$id/application";$cap=[ordered]@{runId=$id;containerId='fixture-container';captureMode='POST_STOP_SNAPSHOT';containerStateAtCapture='exited';timeoutSeconds=30;timedOut=$false;exitCode=0;captureStatus='APPLICATION_LOG_CAPTURE_PASSED';startedAt=$times.cap;completedAt=$times.capEnd;stdoutPath="$relApp/docker-logs.stdout.log";stderrPath="$relApp/docker-logs.stderr.log";combinedPath="$relApp/application.log";stdoutBytes=([IO.FileInfo](Join-Path $app 'docker-logs.stdout.log')).Length;stderrBytes=0;combinedBytes=([IO.FileInfo](Join-Path $app 'application.log')).Length};Write-Json (Join-Path $app 'docker-logs-capture.json') $cap
 foreach($rel in $required){$p=Join-Path $dir $rel;if(-not(Test-Path $p)){if($rel -match '\.json$'){Write-Json $p @{fixture=$true}}else{New-Item -ItemType Directory -Force (Split-Path $p)|Out-Null;Set-Content $p 'fixture'}}}
 Write-Json (Join-Path $dir 'execution-summary.json') ([ordered]@{runId=$id;executionStatus='COMPLETED';artifactValidation='PASSED';cleanupResult='COMPLETED'})
 New-Item -ItemType File (Join-Path $dir 'COMPLETED')|Out-Null
}
New-Item -ItemType Directory -Force $core|Out-Null;$arms|ForEach-Object{New-ValidRun $_}
$dockerArgs=@('run','--rm','--mount',"type=bind,source=$repo,target=/repo",'--workdir','/repo','node:24.18.0-bookworm-slim','node','experiment/scripts/aggregate-experiment-1-25.js','--readiness','20990101','backend/experiments/results/experiment-1-25/fixture-aggregator/core','backend/experiments/results/experiment-1-25/fixture-aggregator/aggregate.json')
& docker @dockerArgs;if($LASTEXITCODE){throw 'AGGREGATOR_FIXTURE_PROCESS_FAILED'}
$aggregate=Get-Content $out -Raw|ConvertFrom-Json;if($aggregate.completedRuns.Count -ne 6 -or $aggregate.missingRuns.Count -ne 0 -or $aggregate.aggregateReadiness -ne 'READY_TO_AGGREGATE' -or $aggregate.decisionState -ne 'NOT_RUN'){throw 'X10_AGGREGATOR_ACCEPTANCE_FAILED'}
$mutations=@(
 @{name='X11';path='run-config.json';action={param($o)$o.runId='WRONG';$o}},
 @{name='X12';path='execution-summary.json';action={param($o)$o.executionStatus='EXECUTION_FAILED';$o}},
 @{name='X13';path='provenance/artifact-path-preflight.json';action={param($o)$o.preflightStatus='ARTIFACT_PATH_PREFLIGHT_FAILED';$o}},
 @{name='X14';path='provenance/artifact-path-preflight.json';action={param($o)$o.requiredDirectories[0].pathContained=$false;$o}},
 @{name='X15';path='provenance/artifact-path-preflight.json';action={param($o)$o.requiredDirectories[0].created=$true;$o}},
 @{name='X16';path='application/docker-logs-capture.json';action={param($o)$o.combinedPath=(Join-Path $repo 'outside.log');$o}},
 @{name='X17';path='application/docker-logs-capture.json';action={param($o)$o.captureStatus='APPLICATION_LOG_CAPTURE_FAILED';$o}},
 @{name='X18';path='application/container-stop.json';action={param($o)$o.stopStatus='APPLICATION_CONTAINER_STOP_FAILED';$o}}
)
foreach($m in $mutations){$dir=Join-Path $core 'RUN-20990101-EXP125-BASELINE-001';$p=Join-Path $dir $m.path;$backup=Get-Content $p -Raw;$o=$backup|ConvertFrom-Json;$o=& $m.action $o;Write-Json $p $o;if($m.name -eq 'X12'){$summaryPath=$p};if($m.name -eq 'X13' -or $m.name -eq 'X14' -or $m.name -eq 'X15'){$summaryPath=$out};& docker @dockerArgs|Out-Null;$check=Get-Content $out -Raw|ConvertFrom-Json;if($check.aggregateReadiness -ne 'INCOMPLETE'){throw "$($m.name)_MUTATION_NOT_REJECTED"};Set-Content $p $backup -Encoding UTF8}
$runDir=Join-Path $core 'RUN-20990101-EXP125-BASELINE-001';New-Item -ItemType File (Join-Path $runDir 'RUNNING')|Out-Null;& docker @dockerArgs|Out-Null;$check=Get-Content $out -Raw|ConvertFrom-Json;if($check.aggregateReadiness -ne 'INCOMPLETE'){throw 'X18_MUTATION_NOT_REJECTED'};Remove-Item (Join-Path $runDir 'RUNNING') -Force
Write-Output 'EXP125_AGGREGATOR_FIXTURES_X10_X18_PASS'
if(-not$KeepFixture){Remove-Item $fixture -Recurse -Force}











