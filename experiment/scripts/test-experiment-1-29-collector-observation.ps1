$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'experiment-1-25-collector-coverage.ps1')
function Assert-Q([string]$Name,[string]$Expected,[hashtable]$Params){$actual=Get-Exp125ObservationQuality @Params;if($actual-ne$Expected){throw "$Name expected $Expected got $actual"}}
Assert-Q 'O1' 'COMPLETE' @{Failures=0;MaxConsecutiveFailures=0;MaximumValidSampleGapMilliseconds=1024.9;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$true}
Assert-Q 'O2' 'BOUNDED_TRANSIENT_LOSS' @{Failures=1;MaxConsecutiveFailures=1;MaximumValidSampleGapMilliseconds=7565.573;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$true}
Assert-Q 'O3' 'INVALID' @{Failures=2;MaxConsecutiveFailures=1;MaximumValidSampleGapMilliseconds=7565.573;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$true}
Assert-Q 'O4' 'INVALID' @{Failures=1;MaxConsecutiveFailures=2;MaximumValidSampleGapMilliseconds=7565.573;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$true}
Assert-Q 'O5' 'INVALID' @{Failures=1;MaxConsecutiveFailures=1;MaximumValidSampleGapMilliseconds=8000.001;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$true}
Assert-Q 'O6' 'INVALID' @{Failures=1;MaxConsecutiveFailures=1;MaximumValidSampleGapMilliseconds=7000;InvalidJsonlRowCount=0;CoversCoreStart=$true;CoversCoreEnd=$false}
$summary=[pscustomobject]@{collectorStatus='COLLECTOR_STOPPED_BY_SIGNAL';stopSignalObserved=$true;processExitCode=0};if(-not(Test-Exp125CollectorLifecycleSummary $summary 0)){throw 'O7 valid lifecycle failed'};$summary.stopSignalObserved=$false;if(Test-Exp125CollectorLifecycleSummary $summary 0){throw 'O7 invalid lifecycle failed'}
Write-Output 'EXP129_COLLECTOR_OBSERVATION_O1_O7_PASS'
