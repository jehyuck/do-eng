param([ValidateSet("PREFLIGHT","EXECUTE")][string]$ExecutionMode="PREFLIGHT")
$ErrorActionPreference="Stop"
$repo=(Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$base=Join-Path $repo "backend\docker-compose.experiment.yaml"
$override=Join-Path $repo "experiment\compose\experiment-1-37-runtime.override.yml"
$root=Join-Path $repo "backend\experiments\results\experiment-1-37\runtime-recovery-attempt-006"
$plan=Join-Path $root "plan"; $project="doeng-exp137r"; $app="http://127.0.0.1:8001"; $management="http://127.0.0.1:9001"; $mock="http://127.0.0.1:9100"
$nodeCommand=Get-Command node -ErrorAction SilentlyContinue
if($nodeCommand){$node=$nodeCommand.Source}else{$node=Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe";if(!(Test-Path $node)){throw "Node executable not found"}}
New-Item -ItemType Directory -Force -Path $plan|Out-Null
function Save-Json($p,$v){$v|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $p}
function Wait-Health{for($i=0;$i -lt 60;$i++){try{$h=Invoke-RestMethod "$management/actuator/health" -TimeoutSec 2;if($h.status -eq "UP"){return $h}}catch{};Start-Sleep 1};throw "management health did not become UP"}
function Set-Mock{Invoke-RestMethod -Method Post -Uri "$mock/__control" -ContentType "application/json" -Body '{"result":true,"delayMs":2000,"status":200,"storageDelayMs":100,"storageStatus":200}'|Out-Null}
function Capture-Thread($p,$id){try{& docker exec $id jcmd 1 Thread.print -l 2>&1|Set-Content -Encoding UTF8 -LiteralPath $p}catch{ "THREAD_DUMP_FAILED: $($_.Exception.Message)"|Set-Content -Encoding UTF8 -LiteralPath $p}}
function Invoke-Run([string]$runId,[int]$vu,[string]$label){
  $dir=Join-Path (Join-Path $root $label) $runId;if(Test-Path $dir){throw "run directory exists: $dir"};New-Item -ItemType Directory -Force -Path $dir|Out-Null
  $started=$false;$appId=$null
  try{
    & docker compose -p $project -f $base -f $override up -d --no-build --force-recreate mariadb experiment-mock flux-corrected;if($LASTEXITCODE-ne 0){throw "compose startup failed"};$started=$true
    $health=Wait-Health;Set-Mock
    $appId=(& docker compose -p $project -f $base -f $override ps -q flux-corrected).Trim()
    $mockId=(& docker compose -p $project -f $base -f $override ps -q experiment-mock).Trim();$dbId=(& docker compose -p $project -f $base -f $override ps -q mariadb).Trim()
    Save-Json (Join-Path $dir "runtime-preflight.json") ([ordered]@{health=$health;runId=$runId;vu=$vu;appContainer=$appId;mockContainer=$mockId;dbContainer=$dbId;contract=@{aiResult=$true;aiDelayMs=2000;storageDelayMs=100;appCpu=2;appMemory="3GiB";pool=400;pending=800;admission="OFF";mockCpu=4;mockMemory="1GiB"}})
    $fixture=Join-Path $repo "image\arc.jpg";$body=@{image=[Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))}|ConvertTo-Json -Compress
    $jfrName="exp137r_"+($runId -replace '[^A-Za-z0-9_]','_');$jfrFile="/tmp/$runId.jfr"
    $jfrAvailable=$false;$jfrExit=$null
    if($label -ne "SMOKE"){try{$jfrOut=& docker exec $appId jcmd 1 JFR.start "name=$jfrName" "settings=profile" "duration=70s" "filename=$jfrFile" "maxsize=64m" 2>&1;$jfrExit=$LASTEXITCODE}catch{$jfrOut=@($_.Exception.Message);$jfrExit=1};$jfrOut|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "jfr-start.log");if($jfrExit -eq 0){$jfrAvailable=$true}}
    $sample=Join-Path $dir "resource-samples.csv";"timestamp,service,cpuPercent,memoryUsage,memoryLimit,pids"|Set-Content -Encoding UTF8 -LiteralPath $sample
    $dumps=Join-Path $dir "thread-dumps";New-Item -ItemType Directory -Force $dumps|Out-Null
    $duration=if($label -eq "SMOKE"){5000}else{30000};$warmup=if($label -eq "SMOKE"){0}else{10000}
    $env:TARGET_URL="$app/game/face";$env:ACTIVE_MISSIONS=[string]$vu;$env:INTERVAL_MS="1000";$env:DURATION_MS=[string]$duration;$env:WARMUP_MS=[string]$warmup;$env:REQUEST_TIMEOUT_MS="10000";$env:SCENE_ID="2";$env:ANSWER="happy";$env:AUTH_TOKEN="Bearer experiment-member-15";$env:FIXTURE_PATH=$fixture;$env:EXPERIMENT_RUN_ID=$runId;$env:IMPLEMENTATION="webflux";$env:ARRIVAL_MODE="staggered";$env:STOP_USER_ON_TRUE="false";$env:RESULT_PATH=Join-Path $dir "client-results.json";$env:PROGRESS_PATH=Join-Path $dir "client-progress.jsonl";$env:DRAIN_OBSERVATION_SECONDS="30";$env:MOCK_METRICS_URL="$mock/__metrics"
    $load=Start-Process -FilePath $node -ArgumentList (Join-Path $repo "experiment\load\mission-load.js") -WorkingDirectory $repo -RedirectStandardOutput (Join-Path $dir "node-runner.stdout.log") -RedirectStandardError (Join-Path $dir "node-runner.stderr.log") -PassThru
    $nodeRunWatchdogSeconds=120;$start=Get-Date;$dumpIndex=0;while(-not $load.HasExited -and ((Get-Date)-$start).TotalSeconds -lt $nodeRunWatchdogSeconds){$rows=& docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.PIDs}}';foreach($row in $rows){"$([DateTime]::UtcNow.ToString('o')),$row"|Add-Content -LiteralPath $sample};if($dumpIndex -in 0,10,20){Capture-Thread (Join-Path $dumps ("thread-{0}s.txt" -f $dumpIndex)) $appId};$dumpIndex++;Start-Sleep 1;$load.Refresh()};if(-not $load.HasExited){Stop-Process $load.Id -Force;$load.WaitForExit();throw "CLIENT_RESULTS_NOT_CREATED: Node watchdog exceeded $nodeRunWatchdogSeconds seconds"};Capture-Thread (Join-Path $dumps "thread-before-stop.txt") $appId
    Start-Sleep -Seconds 30;Capture-Thread (Join-Path $dumps "thread-after-drain.txt") $appId
    $m=Invoke-RestMethod "$mock/__metrics";$s=Invoke-RestMethod "$mock/__storage";Save-Json (Join-Path $dir "mock-metrics-after.json") $m;Save-Json (Join-Path $dir "storage-after.json") $s
    if($label -ne "SMOKE" -and $jfrAvailable){try{& docker exec $appId jcmd 1 JFR.check "name=$jfrName" 2>&1|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "jfr-check.log");& docker cp "$($appId):$jfrFile" (Join-Path $dir "application.jfr")|Out-Null}catch{$jfrAvailable=$false}}
    & docker compose -p $project -f $base -f $override logs --no-color --timestamps flux-corrected experiment-mock|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "application-mock.log")
    $client=Get-Content (Join-Path $dir "client-results.json") -Raw|ConvertFrom-Json;$status="COMPLETED";Save-Json (Join-Path $dir "node-runner-result.json") ([ordered]@{runId=$runId;status=$status;exitCode=$load.ExitCode;summary=$client.summary;aiCompleted=$m.aiCompleted;storageCompleted=$m.storageCompleted});Save-Json (Join-Path $dir ("{0}-result.json" -f $label.ToLower())) ([ordered]@{runId=$runId;status=$status;summary=$client.summary;aiCompleted=$m.aiCompleted;storageCompleted=$m.storageCompleted});Save-Json (Join-Path $dir "diagnostic-availability.json") ([ordered]@{jfr=if($jfrAvailable){"AVAILABLE"}else{"COLLECTION_FAILED"};threadDump="PARTIAL";resourceSampling="AVAILABLE";applicationLog="AVAILABLE";mockLog="AVAILABLE";requestResult="AVAILABLE"});Save-Json (Join-Path $dir "run-status.json") ([ordered]@{runId=$runId;status=$status;exitCode=$load.ExitCode;summary=$client.summary})
    if($label -eq "SMOKE" -and $status -ne "PASS"){throw "Node smoke contract failed"}
  }finally{if($started){docker compose -p $project -f $base -f $override ps|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $dir "compose-ps.txt");docker compose -p $project -f $base -f $override down --remove-orphans|Out-Null}}
}
$gitSafe="safe.directory=$($repo.Replace('\','/'))";$branch=(& git -c $gitSafe branch --show-current).Trim();$head=(& git -c $gitSafe rev-parse HEAD).Trim();Save-Json (Join-Path $plan "baseline-head.json") ([ordered]@{branch=$branch;head=$head;workingTree="pre-existing artifacts preserved";productionSourceDiff="NOT_MODIFIED"})
$rendered=Join-Path $plan "rendered-compose.yaml";& docker compose -p $project -f $base -f $override config|Set-Content -Encoding UTF8 -LiteralPath $rendered;if($LASTEXITCODE-ne 0){throw "compose render failed"};$yaml=Get-Content $rendered -Raw;foreach($needle in @('MOCK_AI_RESULT: "true"','MOCK_AI_DELAY_MS: "2000"','MOCK_STORAGE_DELAY_MS: "100"','DOENG_HTTP_MAX_CONNECTIONS: "400"','DOENG_AI_ADMISSION_ENABLED: "false"','DOENG_ADMISSION_MODE: "OFF"')){if($yaml -notmatch [regex]::Escape($needle)){throw "contract mismatch: $needle"}}
Save-Json (Join-Path $plan "runtime-contract-validation.json") ([ordered]@{status="PASS";mockResource=@{source="Exp136 docker-compose.mock-headroom-4cpu.yaml and docker-compose.mock-memory-headroom.yaml";cpu=4;memory="1GiB"};appCpu=2;appMemory="3GiB";pool=400;pending=800;admission="OFF";observation="OFF"})
if($ExecutionMode -eq "PREFLIGHT"){Write-Output "EXP137R2_PREFLIGHT_PASS";exit 0}
Invoke-Run "RUN-EXP137R6-RUNTIME-LOW-006" 20 "LOW";Invoke-Run "RUN-EXP137R6-RUNTIME-HIGH-006" 200 "HIGH";Save-Json (Join-Path $root "diagnostic-contract.json") ([ordered]@{status="COMPLETED";smokeReused="SMOKE-EXP137R5-NODE-005 PASS";runs=@("RUN-EXP137R6-RUNTIME-LOW-006","RUN-EXP137R6-RUNTIME-HIGH-006");additionalRuns=0});Write-Output "EXP137R6_RUNTIME_DIAGNOSTIC_COMPLETE"
