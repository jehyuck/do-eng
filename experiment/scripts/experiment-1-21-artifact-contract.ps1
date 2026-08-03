$script:Exp121Required = @('run-config.json','client-results.json','client-progress.jsonl','pool/pool-metrics.jsonl','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','application/docker-logs.stdout.log','application/docker-logs.stderr.log','application/docker-logs-capture.json','application/application.log','database/database-metrics.jsonl','container/container-stats.jsonl','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json')
function Get-Exp121Required { @($script:Exp121Required) }
function Test-Exp121Json([string]$Path) { try { $null=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json; $true } catch { $false } }
function Get-Exp121Timestamp([object]$Timeline,[string]$Key,[bool]$Required=$true) {
    $value = [string]$Timeline.$Key
    if([string]::IsNullOrWhiteSpace($value)) { if($Required){throw "Timeline timestamp missing: $Key"}; return $null }
    $parsed=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse($value,[ref]$parsed)){throw "Timeline timestamp invalid: $Key"}
    return $parsed
}
function Assert-Exp121MeasurementTimeline([object]$Timeline) {
    $ordered=@('collectorProcessStartedAt','collectorFirstValidSampleAt','coreInvocationStartedAt','coreInvocationCompletedAt','applicationLogCaptureStartedAt','applicationLogCaptureCompletedAt','collectorProcessCompletedAt')
    $times=@{};foreach($key in $ordered){$times[$key]=Get-Exp121Timestamp $Timeline $key $true}
    for($i=1;$i-lt$ordered.Count;$i++){if($times[$ordered[$i]] -lt $times[$ordered[$i-1]]){throw "Timeline order invalid: $($ordered[$i-1]) -> $($ordered[$i])"}}
}
function Assert-Exp121BaseArtifacts([string]$Root) {
    $zeroByteAllowed=@('application/docker-logs.stdout.log','application/docker-logs.stderr.log');foreach($r in $script:Exp121Required){$p=Join-Path $Root $r;if(-not(Test-Path $p)){throw "Required artifact missing: $r"};if($zeroByteAllowed -notcontains $r -and (Get-Item $p).Length -le 0){throw "Required artifact empty: $r"}}
    foreach($r in @('run-config.json','client-results.json','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','application/docker-logs-capture.json','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json')){if(-not(Test-Exp121Json (Join-Path $Root $r))){throw "Invalid JSON: $r"}}
    $lines=@(Get-Content (Join-Path $Root 'pool/pool-metrics.jsonl')|Where-Object{$_.Trim()});if($lines.Count -le 1){throw 'Pool JSONL has fewer than two valid-sample candidates'};foreach($line in $lines){try{$null=$line|ConvertFrom-Json}catch{throw 'Pool JSONL contains invalid JSON'}}
    $summary=Get-Content (Join-Path $Root 'pool/pool-metrics.jsonl.summary.json') -Raw|ConvertFrom-Json;if($summary.failures -ne 0){throw "Pool collector failures: $($summary.failures)"}
    . (Join-Path $PSScriptRoot 'experiment-1-21-collector-coverage.ps1');Assert-Exp121CollectorCoverage (Join-Path $Root 'pool/collector-coverage.json')
    $capture=Get-Content (Join-Path $Root 'application/docker-logs-capture.json') -Raw|ConvertFrom-Json;if($capture.captureStatus-ne'APPLICATION_LOG_CAPTURE_PASSED'-or$capture.exitCode-ne0-or($capture.stdoutBytes+$capture.stderrBytes)-le0-or$capture.combinedBytes-le0){throw 'Native capture metadata validation failed'}
    $runConfig=Get-Content (Join-Path $Root 'run-config.json') -Raw|ConvertFrom-Json;if($capture.runId -ne $runConfig.runId){throw 'Capture runId does not match run-config'}
    $applicationRoot=([IO.Path]::GetFullPath((Join-Path $Root 'application'))).TrimEnd('\')+'\';$capturePaths=@($capture.stdoutPath,$capture.stderrPath,$capture.combinedPath);foreach($p in $capturePaths){if(-not(Test-Path $p)){throw "Capture path missing: $p"};$candidate=[IO.Path]::GetFullPath($p);if(-not $candidate.StartsWith($applicationRoot,[StringComparison]::OrdinalIgnoreCase)){throw "Capture path outside run application directory: $p"}}
    if([int64]$capture.stdoutBytes -ne [int64](Get-Item $capture.stdoutPath).Length -or [int64]$capture.stderrBytes -ne [int64](Get-Item $capture.stderrPath).Length -or [int64]$capture.combinedBytes -ne [int64](Get-Item $capture.combinedPath).Length){throw 'Native capture metadata byte counts do not match files'}
    $captureStarted=Get-Exp121Timestamp $capture 'startedAt' $true;$captureCompleted=Get-Exp121Timestamp $capture 'completedAt' $true;if($captureCompleted -lt $captureStarted){throw 'Capture completion precedes capture start'}
    $timeline=Get-Content (Join-Path $Root 'provenance/execution-timeline.json') -Raw|ConvertFrom-Json;Assert-Exp121MeasurementTimeline $timeline
}
function Assert-Exp121StructuralArtifacts([string]$Root) {
    Assert-Exp121BaseArtifacts $Root
    $summary=Get-Content (Join-Path $Root 'execution-summary.json') -Raw|ConvertFrom-Json
    if($summary.executionStatus -ne 'FINALIZING' -or $summary.artifactValidation -ne 'PENDING'){throw 'Structural validation requires FINALIZING/PENDING execution summary'}
}
function Assert-Exp121CommittedArtifacts([string]$Root) {
    Assert-Exp121BaseArtifacts $Root
    $summary=Get-Content (Join-Path $Root 'execution-summary.json') -Raw|ConvertFrom-Json
    if($summary.executionStatus -ne 'COMPLETED' -or $summary.artifactValidation -ne 'PASSED'){throw 'Committed validation requires COMPLETED/PASSED execution summary'}
    $timeline=Get-Content (Join-Path $Root 'provenance/execution-timeline.json') -Raw|ConvertFrom-Json
    Assert-Exp121MeasurementTimeline $timeline
    $artifact=Get-Exp121Timestamp $timeline 'artifactValidationCompletedAt' $true;$final=Get-Exp121Timestamp $timeline 'finalizationCompletedAt' $true
    if($final -lt $artifact){throw 'Finalization precedes artifact validation completion'}
}
function Assert-Exp121Artifacts([string]$Root) { Assert-Exp121StructuralArtifacts $Root }
function Copy-Exp121Artifacts([string]$Legacy,[string]$Staging,[string]$Destination) {
    $map=@(@('run-config.json','run-config.json'),@('client-results.json','client-results.json'),@('client-progress.jsonl','client-progress.jsonl'),@('database-metrics.jsonl','database/database-metrics.jsonl'),@('container-stats.jsonl','container/container-stats.jsonl'),@('load-stop-mock-metrics.json','mock/load-stop-mock-metrics.json'),@('mock-drain-summary.json','drain/mock-drain-summary.json'),@('verification-summary.json','verification-summary.json'))
    foreach($m in $map){$s=Join-Path $Legacy $m[0];if(-not(Test-Path $s)){throw "Legacy artifact missing: $s"};$d=Join-Path $Destination $m[1];New-Item -ItemType Directory -Force -Path (Split-Path $d)|Out-Null;Copy-Item $s $d}
    foreach($name in @('pool-metrics.jsonl','pool-metrics.jsonl.summary.json')){$s=Join-Path $Staging $name;if(-not(Test-Path $s)){throw "Collector artifact missing: $s"};$d=Join-Path $Destination "pool/$name";New-Item -ItemType Directory -Force -Path (Split-Path $d)|Out-Null;Copy-Item $s $d}
}
function Set-Exp121Terminal([string]$Root,[ValidateSet('COMPLETED','EXECUTION_FAILED')][string]$State){foreach($m in @('RUNNING','COMPLETED','EXECUTION_FAILED')){$p=Join-Path $Root $m;if(Test-Path $p){Remove-Item $p -Force}};New-Item -ItemType File -Path (Join-Path $Root $State)|Out-Null}




