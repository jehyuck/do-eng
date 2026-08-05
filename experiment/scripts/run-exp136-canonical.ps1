param(
  [Parameter(Mandatory=$true)][ValidateSet('SMOKE','CORE')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$RunId,
  [string]$RunDate='20260806'
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifact=Join-Path $root "backend\experiments\results\experiment-1-36\$Mode\$RunId"
$legacy=Join-Path $root "experiment\results\$RunId"
$project=("doeng-exp1-36-$RunId" -replace '[^A-Za-z0-9_-]','-').ToLowerInvariant()
$files=@('backend\docker-compose.experiment.yaml','backend\docker-compose.app-instance-t3-medium.yaml','backend\docker-compose.mock-headroom-4cpu.yaml','backend\docker-compose.http-pool-400.yaml','backend\docker-compose.mock-memory-headroom.yaml','backend\docker-compose.experiment-1-12-connection-attribution.yaml','backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml','backend\docker-compose.experiment-1-31-diagnostics.yaml','backend\docker-compose.experiment-1-36-pool-1000.yaml')
$compose=@();foreach($f in $files){$compose+=@('-f',(Join-Path $root $f))}
$node=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
function W([string]$p,[object]$v){New-Item -ItemType Directory -Force (Split-Path -Parent $p)|Out-Null;[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 30),(New-Object Text.UTF8Encoding($false)))}
function Inspect([string]$cid,[string]$p){$x=docker inspect $cid;if($LASTEXITCODE){throw "INSPECT_FAILED:$cid"};[IO.File]::WriteAllText($p,($x -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))}
function Logs([string]$cid,[string]$p){$old=$ErrorActionPreference;$ErrorActionPreference='Continue';$x=@(& docker logs --timestamps $cid 2>&1);$ErrorActionPreference=$old;[IO.File]::WriteAllText($p,(($x|ForEach-Object{[string]$_}) -join [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))}
$monitor=$null;$failure=$null
try {
  if((Test-Path $artifact) -or (Test-Path $legacy)){throw 'ARTIFACT_COLLISION'}
  New-Item -ItemType Directory -Force $artifact,(Join-Path $artifact 'containers'),(Join-Path $artifact 'logs')|Out-Null
  $env:DOENG_EXP136_APP_IMAGE='doeng-exp133-admission-off:a530aa6';$env:DOENG_EXP136_MOCK_IMAGE='doeng-exp136-mock-canonical:latest'
  docker compose -p $project @compose config | Set-Content (Join-Path $artifact 'rendered-compose.yaml') -Encoding utf8
  if($LASTEXITCODE){throw 'COMPOSE_CONFIG_FAILED'}
  docker compose -p $project @compose up -d --force-recreate --no-build mariadb experiment-mock flux-corrected|Out-Null;if($LASTEXITCODE){throw 'RECREATE_FAILED'}
  $appCid=(docker compose -p $project @compose ps -q flux-corrected).Trim();$mockCid=(docker compose -p $project @compose ps -q experiment-mock).Trim();$dbCid=(docker compose -p $project @compose ps -q mariadb).Trim();if(-not $appCid -or -not $mockCid -or -not $dbCid){throw 'CONTAINER_ID_MISSING'}
  $ready=$false;for($i=0;$i -lt 90 -and -not $ready;$i++){try{$h=Invoke-RestMethod 'http://127.0.0.1:9001/actuator/health';$m=Invoke-RestMethod 'http://127.0.0.1:9100/__metrics';$ready=($h.status -eq 'UP' -and $m.aiInFlight -eq 0 -and $m.storageInFlight -eq 0)}catch{};if(-not $ready){Start-Sleep 1}};if(-not $ready){throw 'HEALTH_OR_IDLE_FAILED'}
  Inspect $appCid (Join-Path $artifact 'containers/application-inspect-before.json');Inspect $mockCid (Join-Path $artifact 'containers/mock-inspect-before.json');Inspect $dbCid (Join-Path $artifact 'containers/db-inspect-before.json')
  $active=if($Mode -eq 'SMOKE'){20}else{200};$duration=if($Mode -eq 'SMOKE'){5000}else{105000};$drain=if($Mode -eq 'SMOKE'){10}else{30};$monitorOut=Join-Path $root "experiment\results\$RunId-monitor"
  $monitorArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'monitor-containers.ps1'),'-RunId',$RunId,'-ServerService','flux-corrected','-ComposeProject',$project,'-ComposeFiles',($files -join ','),'-IntervalSeconds','1','-DurationSeconds',([int]([Math]::Ceiling($duration/1000)+$drain+10)),'-SkipApplicationSnapshot','1','-SkipMockMetrics','1','-OutputDirectory',$monitorOut,'-NodeCommand',$node);$monitor=Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList $monitorArgs
  $childOut=Join-Path $artifact 'child.stdout.log';$childErr=Join-Path $artifact 'child.stderr.log';$childArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'run-isolated-vu-success-smoke.ps1'),'-RunId',$RunId,'-Implementation',"Exp136-$Mode",'-TargetUrl','http://127.0.0.1:8001/game/face','-ServerService','flux-corrected','-ComposeProject',$project,'-ComposeFiles',($files -join ','),'-ActiveMissions',"$active",'-AiDelayMs','2000','-StorageDelayMs','100','-IntervalMs','1000','-DurationMs',"$duration",'-RequestTimeoutMs','10000','-TargetP95Ms','10000','-EnableObservability','0','-EnableJfr','0','-EnableContainerMonitor','0','-SkipApplicationSnapshot','1','-SkipMockMetrics','1','-OutcomeMode','natural-capacity','-AccountingMode','corrected','-DrainObservationSeconds',"$drain",'-NodeCommand',$node);& powershell.exe @childArgs 1>$childOut 2>$childErr;$childExit=$LASTEXITCODE
  if(Test-Path $legacy){Copy-Item -Recurse -Force (Join-Path $legacy '*') $artifact};if(Test-Path $monitorOut){Copy-Item -Recurse -Force (Join-Path $monitorOut '*') (Join-Path $artifact 'container-monitor')}
  if($monitor -and -not $monitor.HasExited){$monitor.WaitForExit(15000)|Out-Null};if($monitor -and $monitor.ExitCode -ne 0){throw 'CONTAINER_MONITOR_FAILED'}
  W (Join-Path $artifact 'execution-status.json') ([ordered]@{runId=$RunId;mode=$Mode;childExitCode=$childExit;monitorExitCode=if($monitor){$monitor.ExitCode}else{$null};completedAt=[DateTimeOffset]::UtcNow.ToString('o')})
  Logs $appCid (Join-Path $artifact 'logs/application.log');Logs $mockCid (Join-Path $artifact 'logs/mock.log');Logs $dbCid (Join-Path $artifact 'logs/db.log');Inspect $appCid (Join-Path $artifact 'containers/application-inspect-after.json');Inspect $mockCid (Join-Path $artifact 'containers/mock-inspect-after.json');Inspect $dbCid (Join-Path $artifact 'containers/db-inspect-after.json')
  $v=Join-Path $artifact 'verification-summary.json';if(-not(Test-Path $v)){throw 'VERIFICATION_MISSING'};$vr=Get-Content $v -Raw|ConvertFrom-Json;if($childExit -ne 0 -or $vr.measurementValidity -ne 'VALID'){throw 'CANONICAL_RUN_INVALID'}
} catch {$failure=$_} finally {if($monitor -and -not $monitor.HasExited){try{$monitor.Kill()}catch{}};docker compose -p $project @compose down --remove-orphans|Out-Null}
if($failure){Write-Error $failure;exit 1};Write-Output "EXP136_COMPLETED:$RunId"
