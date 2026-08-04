function ConvertTo-Exp125Timestamp([object]$Value) {
    $p=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Value,[ref]$p)){throw "Invalid timestamp: $Value"}
    $p.ToUniversalTime()
}
function Wait-Exp125CollectorReady([System.Diagnostics.Process]$Process,[string]$JsonlPath,[int]$TimeoutSeconds=10) {
    $deadline=(Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while((Get-Date).ToUniversalTime()-lt$deadline){
        if($Process.HasExited){throw 'COLLECTOR_NOT_READY'}
        foreach($line in @(Get-Content $JsonlPath -ErrorAction SilentlyContinue|Where-Object{$_.Trim()})){
            try{$s=$line|ConvertFrom-Json;$at=ConvertTo-Exp125Timestamp $s.timestamp;if($null-eq$s.failure-or[string]::IsNullOrWhiteSpace([string]$s.failure)){return [ordered]@{collectorReadyAt=(Get-Date).ToUniversalTime().ToString('o');collectorFirstValidSampleAt=$at.ToString('o')}}}catch{}
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'COLLECTOR_NOT_READY'
}
function Wait-Exp125CollectorCoversCoreEnd([string]$JsonlPath,[string]$CoreCompletedAt,[int]$TimeoutSeconds=10) {
    $end=ConvertTo-Exp125Timestamp $CoreCompletedAt;$deadline=(Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
    while((Get-Date).ToUniversalTime()-lt$deadline){
        foreach($line in @(Get-Content $JsonlPath -ErrorAction SilentlyContinue|Where-Object{$_.Trim()})){
            try{$s=$line|ConvertFrom-Json;$at=ConvertTo-Exp125Timestamp $s.timestamp;if(($null-eq$s.failure-or[string]::IsNullOrWhiteSpace([string]$s.failure))-and$at-ge$end){$script:Exp125LastCoveringSampleAt=$at.ToString('o');return $script:Exp125LastCoveringSampleAt}}catch{}
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'COLLECTOR_POST_CORE_SAMPLE_TIMEOUT'
}
function New-Exp125CollectorLifecycle([string]$RunId,[string]$Mode,[int]$IntervalMilliseconds,[int]$ReadinessTimeoutSeconds,[int]$PostCoreSampleTimeoutSeconds,[int]$GracefulStopTimeoutSeconds,[int]$MaxDurationSeconds,[string]$CollectorProcessStartedAt,[string]$CollectorFirstValidSampleAt,[string]$CoreInvocationStartedAt,[string]$CoreInvocationCompletedAt,[string]$CollectorFirstSampleCoveringCoreEndAt,[string]$PostCoreCoverageConfirmedAt,[string]$CollectorStopSignalIssuedAt,[string]$CollectorProcessCompletedAt,[bool]$StopSignalObserved,[int]$ProcessExitCode,[bool]$ProcessTerminationAttempted,[bool]$ProcessTerminationConfirmed,[int64]$ActualDurationMilliseconds,[string]$LifecycleStatus,[string]$FailureType,[string]$SummaryCollectorStatus='NOT_AVAILABLE',[int]$SummaryFailures=-1,[bool]$SummaryStopSignalObserved=$false){[ordered]@{runId=$RunId;mode=$Mode;intervalMilliseconds=$IntervalMilliseconds;readinessTimeoutSeconds=$ReadinessTimeoutSeconds;postCoreSampleTimeoutSeconds=$PostCoreSampleTimeoutSeconds;gracefulStopTimeoutSeconds=$GracefulStopTimeoutSeconds;maxDurationSeconds=$MaxDurationSeconds;collectorProcessStartedAt=$CollectorProcessStartedAt;collectorFirstValidSampleAt=$CollectorFirstValidSampleAt;coreInvocationStartedAt=$CoreInvocationStartedAt;coreInvocationCompletedAt=$CoreInvocationCompletedAt;collectorFirstSampleCoveringCoreEndAt=$CollectorFirstSampleCoveringCoreEndAt;postCoreCoverageConfirmedAt=$PostCoreCoverageConfirmedAt;collectorStopSignalIssuedAt=$CollectorStopSignalIssuedAt;collectorProcessCompletedAt=$CollectorProcessCompletedAt;stopSignalObserved=$StopSignalObserved;processExitCode=$ProcessExitCode;processTerminationAttempted=$ProcessTerminationAttempted;processTerminationConfirmed=$ProcessTerminationConfirmed;actualDurationMilliseconds=$ActualDurationMilliseconds;summaryCollectorStatus=$SummaryCollectorStatus;summaryFailures=$SummaryFailures;summaryStopSignalObserved=$SummaryStopSignalObserved;lifecycleStatus=$LifecycleStatus;failureType=$FailureType}}




