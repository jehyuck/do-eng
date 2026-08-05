param(
    [Parameter(Mandatory=$true)][string]$ManagementUrl,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$FailurePath,
    [Parameter(Mandatory=$true)][string]$SummaryPath,
    [Parameter(Mandatory=$true)][string]$StopSignalPath,
    [int]$IntervalMilliseconds = 1000,
    [int]$RequestTimeoutSeconds = 5,
    [int]$MaxDurationSeconds = 120
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath),(Split-Path -Parent $FailurePath),(Split-Path -Parent $SummaryPath) | Out-Null
[IO.File]::WriteAllText($FailurePath,'',(New-Object Text.UTF8Encoding($false)))
$started=[DateTimeOffset]::UtcNow; $attempt=0; $samples=0; $failures=0; $lastValid=$null; $maxGap=0.0; $stop=$false
function Write-Utf8Json([string]$Path,[object]$Value){[IO.File]::AppendAllText($Path,(($Value|ConvertTo-Json -Depth 30 -Compress)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))}
try {
  while([DateTimeOffset]::UtcNow -lt $started.AddSeconds($MaxDurationSeconds)) {
    $attempt++; $requestStarted=[DateTimeOffset]::UtcNow
    try {
      $payload=Invoke-RestMethod -Uri ($ManagementUrl.TrimEnd('/')+'/actuator/doengdiagnosticpool') -TimeoutSec $RequestTimeoutSeconds
      $completed=[DateTimeOffset]::UtcNow
      if($null -ne $lastValid){$gap=($requestStarted-$lastValid).TotalMilliseconds;if($gap -gt $maxGap){$maxGap=[math]::Round($gap,3)}}
      $lastValid=$requestStarted; $samples++
      Write-Utf8Json $OutputPath ([ordered]@{ok=$true;attempt=$attempt;timestamp=$requestStarted.ToString('o');requestStartedAt=$requestStarted.ToString('o');requestCompletedAt=$completed.ToString('o');elapsedMilliseconds=[math]::Round(($completed-$requestStarted).TotalMilliseconds,3);httpStatus=200;poolMode=$payload.poolMode;providers=@($payload.providers);metrics=@($payload.metrics);failure=$null})
    } catch {
      $failures++; $completed=[DateTimeOffset]::UtcNow; $errorRecord=[ordered]@{ok=$false;attempt=$attempt;timestamp=$requestStarted.ToString('o');endpoint=($ManagementUrl.TrimEnd('/')+'/actuator/doengdiagnosticpool');requestStartedAt=$requestStarted.ToString('o');requestCompletedAt=$completed.ToString('o');elapsedMilliseconds=[math]::Round(($completed-$requestStarted).TotalMilliseconds,3);httpStatus=$null;timeout=$true;applicationContainerRunning='NOT_AVAILABLE';previousSuccessfulSampleAt=if($null -ne $lastValid){$lastValid.ToString('o')}else{$null};nextSuccessfulSampleAt=$null;exceptionClass=$_.Exception.GetType().FullName;exceptionMessage=$_.Exception.Message;retryAttempted=$false;failure='POOL_ENDPOINT_REQUEST_FAILED'}
      Write-Utf8Json $OutputPath $errorRecord; Write-Utf8Json $FailurePath $errorRecord
    }
    if(Test-Path -LiteralPath $StopSignalPath){$stop=$true;break}
    $sleep=[int][math]::Max(0,($requestStarted.AddMilliseconds($IntervalMilliseconds)-[DateTimeOffset]::UtcNow).TotalMilliseconds);if($sleep -gt 0){Start-Sleep -Milliseconds $sleep}
  }
} finally {
  $status=if($stop){'COLLECTOR_STOPPED_BY_SIGNAL'}else{'STOP_SIGNAL_MISSED'}
  $summary=[ordered]@{collectorStatus=$status;collectorProcessStartedAt=$started.ToString('o');collectorProcessCompletedAt=[DateTimeOffset]::UtcNow.ToString('o');intervalMilliseconds=$IntervalMilliseconds;requestTimeoutSeconds=$RequestTimeoutSeconds;attempts=$attempt;samples=$samples;failures=$failures;maximumValidSampleGapMilliseconds=$maxGap;invalidJsonlRowCount=0;stopSignalObserved=$stop;processExitCode=if($stop){0}else{1}}
  [IO.File]::WriteAllText($SummaryPath,($summary|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
}
if(-not $stop){exit 1}
