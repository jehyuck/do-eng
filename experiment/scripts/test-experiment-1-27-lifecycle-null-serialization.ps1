$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'experiment-1-25-collector-lifecycle.ps1')
. (Join-Path $PSScriptRoot 'experiment-1-25-artifact-contract.ps1')
$dir=Join-Path $root 'backend\experiments\results\experiment-1-27\lifecycle-fixtures';if(Test-Path $dir){throw 'FIXTURE_COLLISION'};New-Item -ItemType Directory -Force (Join-Path $dir 'provenance'),(Join-Path $dir 'pool')|Out-Null
$t=@{a='2026-08-04T00:00:00.000Z';b='2026-08-04T00:00:01.000Z';c='2026-08-04T00:00:02.000Z';d='2026-08-04T00:00:03.000Z';e='2026-08-04T00:00:04.000Z';f='2026-08-04T00:00:05.000Z';g='2026-08-04T00:00:06.000Z'}
$life=New-Exp125CollectorLifecycle 'FIXTURE-EXP127' 'CORE_BOUND_STOP_SIGNAL' 1000 10 10 10 300 $t.a $t.b $t.c $t.d $t.e $t.e $t.f $t.g $true 0 $false $false 7000 'COLLECTOR_LIFECYCLE_PASSED' $null 'COLLECTOR_STOPPED_BY_SIGNAL' 0 $true;if([string]::IsNullOrWhiteSpace([string]$life.failureType)){$life.failureType=$null}
$life|ConvertTo-Json -Depth 12|Set-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Encoding UTF8
$tl=[ordered]@{collectorFirstSampleCoveringCoreEndAt=$t.e;postCoreCoverageConfirmedAt=$t.e;collectorStopSignalIssuedAt=$t.f;collectorProcessCompletedAt=$t.g};$tl|ConvertTo-Json|Set-Content (Join-Path $dir 'provenance/execution-timeline.json') -Encoding UTF8
$read=Get-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Raw|ConvertFrom-Json;if($null -ne $read.failureType){throw 'L1_FAILED'};Assert-Exp125CollectorLifecycle $dir
$life.failureType='';if([string]::IsNullOrWhiteSpace([string]$life.failureType)){$life.failureType=$null};$life|ConvertTo-Json|Set-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Encoding UTF8;$read=Get-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Raw|ConvertFrom-Json;if($null -ne $read.failureType){throw 'L2_FAILED'}
$life.failureType='COLLECTOR_STOP_TIMEOUT';$life|ConvertTo-Json|Set-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Encoding UTF8;$read=Get-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Raw|ConvertFrom-Json;if($read.failureType -ne 'COLLECTOR_STOP_TIMEOUT'){throw 'L3_FAILED'}
$life.failureType='';$life|ConvertTo-Json|Set-Content (Join-Path $dir 'pool/collector-lifecycle.json') -Encoding UTF8;$rejected=$false;try{Assert-Exp125CollectorLifecycle $dir}catch{$rejected=$true};if(-not$rejected){throw 'L4_FAILED'};Write-Output 'EXP127_LIFECYCLE_NULL_SERIALIZATION_REGRESSION_PASS'
