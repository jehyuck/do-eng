param([Parameter(Mandatory=$true)][string]$RunDir)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$run=(Resolve-Path $RunDir).Path
function Read-Jsonl($path) { if(-not(Test-Path $path)){return @()}; @(Get-Content $path | % { try { $_|ConvertFrom-Json } catch {} }) }
$stageRows=Read-Jsonl (Join-Path $run 'stage-metrics.jsonl')
$stageTimeline=Join-Path $run 'stage-timeline.jsonl'
if(Test-Path $stageTimeline){Remove-Item $stageTimeline -Force}
$previous=@{}
function Normalize-Stage($s) {
  if($s -is [string]) {
    $o=[ordered]@{}
    foreach($k in @('stage','started','succeeded','failed','cancelled','inFlight','maxInFlight','durationMsTotal','durationMsP50','durationMsP95','durationMsP99','durationMsMax')) { if($s -match ($k+'=([^;}]*)')){$o[$k]=$Matches[1].Trim()} }
    return [pscustomobject]$o
  }
  return $s
}
foreach($row in $stageRows){
  if(-not $row.value.stages){continue}
  foreach($raw in $row.value.stages){ $s=Normalize-Stage $raw; if(-not $s.stage){continue}
    $name=[string]$s.stage; $old=$previous[$name]
    $delta=[ordered]@{timestamp=$row.timestamp;stage=$name;started=[int64]$s.started;succeeded=[int64]$s.succeeded;failed=[int64]$s.failed;cancelled=[int64]$s.cancelled;startedPerSec=$null;succeededPerSec=$null;failedPerSec=$null;inFlight=$s.inFlight;maxInFlight=$s.maxInFlight;durationMsTotal=$s.durationMsTotal;durationMsP50=$s.durationMsP50;durationMsP95=$s.durationMsP95;durationMsP99=$s.durationMsP99;durationMsMax=$s.durationMsMax;queueDepth=$null}
    if($old){$delta.startedPerSec=[math]::Max(0,([double]$s.started-[double]$old.started));$delta.succeededPerSec=[math]::Max(0,([double]$s.succeeded-[double]$old.succeeded));$delta.failedPerSec=[math]::Max(0,([double]$s.failed-[double]$old.failed))}
    ($delta|ConvertTo-Json -Compress)|Add-Content $stageTimeline -Encoding UTF8; $previous[$name]=$s
  }
}
$events=@(); $log=Join-Path $run 'application.log'
if(Test-Path $log){ foreach($line in Get-Content $log){ if($line -match 'DOENG_STAGE_EVENT \{(.*)\}'){ $body=$Matches[1]; $get={param($k) if($body -match ($k+'=([^,}]*)')){$Matches[1]}else{$null}}; $events += [pscustomobject]@{timestamp=&$get 'timestamp';event=&$get 'event';requestId=&$get 'requestId';runId=&$get 'runId';missionRunId=&$get 'missionRunId';stage=&$get 'stage';thread=&$get 'thread'} } } }
$groups=$events|Group-Object requestId,stage
$residencies=@(); foreach($g in $groups){$ordered=$g.Group|Sort-Object timestamp; $start=$ordered|?{$_.event -eq 'STAGE_STARTED'}|Select-Object -First 1; $term=$ordered|?{$_.event -eq 'STAGE_TERMINATED'}|Select-Object -Last 1; if($start -and $term){$a=[datetime]$start.timestamp;$b=[datetime]$term.timestamp;$residencies += [pscustomobject]@{requestId=$start.requestId;runId=$start.runId;missionRunId=$start.missionRunId;stage=$start.stage;stageStartedAt=$start.timestamp;stageTerminatedAt=$term.timestamp;stageResidenceMs=($b-$a).TotalMilliseconds;terminalEvent=$term.event} } }
$residencies | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $run 'request-stage-residency.json') -Encoding UTF8
$aggregate=[ordered]@{runId=(Split-Path $run -Leaf);stageTimelinePath='stage-timeline.jsonl';requestResidencyPath='request-stage-residency.json';eventCount=$events.Count;residencyCount=$residencies.Count;stageRows=$stageRows.Count;notes=@('Queue wait is NOT_AVAILABLE when not exposed by existing dispatcher metrics.','Residence covers StageObservation observe() boundaries; it is not a queue-only or network-only decomposition.')}
$aggregate | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $run 'stage-analysis-summary.json') -Encoding UTF8
