$exp122 = Join-Path $PSScriptRoot 'experiment-1-22-artifact-contract.ps1'
. $exp122
function Assert-Exp123CollectorLifecycle([string]$Root) {
  $p=Join-Path $Root 'pool/collector-lifecycle.json'; if(-not(Test-Path $p)){throw 'Collector lifecycle artifact missing'}
  $l=Get-Content $p -Raw|ConvertFrom-Json
  if($l.mode -ne 'CORE_BOUND_STOP_SIGNAL' -or $l.lifecycleStatus -ne 'COLLECTOR_LIFECYCLE_PASSED' -or $l.stopSignalObserved -ne $true -or [int]$l.processExitCode -ne 0){throw 'Collector lifecycle contract failed'}
}
function Assert-Exp123BaseArtifacts([string]$Root){ Assert-Exp122BaseArtifacts $Root }
function Assert-Exp123StructuralArtifacts([string]$Root){ Assert-Exp122StructuralArtifacts $Root }
function Assert-Exp123CommittedArtifacts([string]$Root){ Assert-Exp122CommittedArtifacts $Root }
function Assert-Exp123StopIdentity([string]$Root){ Assert-Exp122StopIdentity $Root }
function Assert-Exp123Timeline([object]$Timeline){ Assert-Exp122Timeline $Timeline }
function Set-Exp123Terminal([string]$Root,[ValidateSet('COMPLETED','EXECUTION_FAILED')][string]$State){ Set-Exp122Terminal $Root $State }
