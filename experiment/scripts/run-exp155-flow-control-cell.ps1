param(
    [Parameter(Mandatory=$true)][ValidateSet("CONTROL","GATE","SINK")][string]$Cell,
    [Parameter(Mandatory=$true)][ValidateSet("Plan","Smoke","Execute")][string]$Mode,
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resultRoot = Join-Path $repo "experiment\results\experiment-1-55"
$runDir = Join-Path $resultRoot $RunId
$baseComposeOriginal = Join-Path $repo "backend\docker-compose.experiment.yaml"
$override = Join-Path $repo ("experiment\compose\experiment-1-55-{0}.override.yml" -f $Cell.ToLowerInvariant())
$fixture = Join-Path $repo "image\arc.jpg"
$missionLoad = Join-Path $repo "experiment\load\mission-load.js"
$sourceCommit = if ($Cell -eq "SINK") { "cf5b36ad38928d55eab131d1328dc85ccff0ad3b" } else { "507e075016728daeaab75a51e7172577efe4c5ce" }
$sourceBranch = if ($Cell -eq "SINK") { "experiment/exp152-sink-dispatcher" } else { "experiment/exp151-admission-gate-capacity" }
$ports = switch ($Cell) {
    "CONTROL" { @{app=18500;management=19500;mock=18600;db=18700} }
    "GATE" { @{app=18501;management=19501;mock=18601;db=18701} }
    "SINK" { @{app=18502;management=19502;mock=18602;db=18702} }
}
$applicationUrl = "http://127.0.0.1:$($ports.app)"
$managementUrl = "http://127.0.0.1:$($ports.management)"
$mockUrl = "http://127.0.0.1:$($ports.mock)"
$runtimeCompose = $null
$sourceWorktree = $null
$seedDir = $null
$seedImage = $null
$collector = $null
$started = $false
$appImage = if ($Cell -eq "SINK") { "doeng-exp153-b3-recovery-flux-corrected:latest" } else { "doeng-exp153-a3-recovery-flux-corrected:latest" }
$mockImage = if ($Cell -eq "SINK") { "doeng-exp153-b3-recovery-experiment-mock:latest" } else { "doeng-exp153-a3-recovery-experiment-mock:latest" }

function Save-Json([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Resolve-NodeExecutable {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }
    $root = Join-Path $env:USERPROFILE ".cache\codex-runtimes"
    $node = Get-ChildItem $root -Recurse -Filter node.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($node) { return $node }
    throw "NODE_EXECUTABLE_NOT_FOUND"
}
function Invoke-Git([string[]]$GitArgs) { & git -C $repo @GitArgs }
function Assert-Inputs {
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and (Invoke-Git @("rev-parse","HEAD")).Trim() -ne $ExpectedCommit) { throw "HARNESS_HEAD_MISMATCH" }
    foreach ($path in @($baseComposeOriginal,$override,$fixture,$missionLoad)) { if (-not (Test-Path $path)) { throw "MISSING_INPUT:$path" } }
    if (Test-Path $runDir) { throw "RESULT_DIRECTORY_COLLISION:$runDir" }
    $sha = (Get-FileHash $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    $admissionMode = if ($Cell -eq "GATE") { "FULL_PATH/ENFORCE/400" } else { "OFF" }
    $sinkMode = if ($Cell -eq "SINK") { "ON" } else { "OFF" }
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    Save-Json (Join-Path $runDir "run-config.json") ([ordered]@{
        experiment="Exp155"; runId=$RunId; cell=$Cell; mode=$Mode; sourceCommit=$sourceCommit; sourceBranch=$sourceBranch
        harnessCommit=(Invoke-Git @("rev-parse","HEAD")).Trim(); fixture="image/arc.jpg"; fixtureSha256=$sha
        activeMissions=200; intervalMs=1000; durationMs=30000; clientTimeoutMs=15000; aiDelayMs=2000; storageDelayMs=100
        appCpu="2"; appMemory="3g"; jvm="-Xms512m -Xmx2g -XX:+UseG1GC"; dbPool=10
        tokenPool="100/160"; aiPool="400/640"; storagePool="100/160"; pendingAcquireTimeoutMs=10000
        admission=$admissionMode; sink=$sinkMode
    })
}
function Compose([string[]]$ComposeArgs) {
    & docker compose -p ("doeng-exp155-" + $RunId.ToLowerInvariant()) -f $runtimeCompose -f $override @ComposeArgs
    if ($LASTEXITCODE -ne 0) { throw "COMPOSE_FAILED:$($ComposeArgs -join ' ')" }
}
function Prepare-Source {
    $script:sourceWorktree = Join-Path $env:TEMP ("doeng-exp155-source-" + $RunId.ToLowerInvariant())
    if (Test-Path $sourceWorktree) { throw "SOURCE_WORKTREE_COLLISION" }
    & git -C $repo worktree add --detach $sourceWorktree $sourceCommit | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "SOURCE_WORKTREE_FAILED" }
    $actual = (& git -c ("safe.directory=" + $sourceWorktree.Replace('\','/')) -C $sourceWorktree rev-parse HEAD).Trim()
    if ($actual -ne $sourceCommit) { throw "SOURCE_COMMIT_MISMATCH" }
    Save-Json (Join-Path $runDir "source-fingerprint.json") ([ordered]@{expected=$sourceCommit;actual=$actual;branch=$sourceBranch;directory=$sourceWorktree})
}
function Prepare-Compose {
    $dump = Get-ChildItem (Join-Path $repo "exec") -Recurse -Filter doEng.sql -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $dump) { throw "DB_SEED_NOT_FOUND" }
    $script:seedDir = Join-Path $env:TEMP ("doeng-exp155-seed-" + $RunId.ToLowerInvariant())
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    Copy-Item $dump (Join-Path $seedDir "doEng.sql")
    Copy-Item (Join-Path $repo "backend\experiment-db\02-mission-completion.sql") (Join-Path $seedDir "02-mission-completion.sql")
    @("FROM mariadb:10.11","COPY doEng.sql /docker-entrypoint-initdb.d/01-doeng.sql","COPY 02-mission-completion.sql /docker-entrypoint-initdb.d/02-mission-completion.sql") | Set-Content (Join-Path $seedDir Dockerfile) -Encoding ASCII
    $script:seedImage = "doeng-exp155-db-$($RunId.ToLowerInvariant())"
    & docker build --quiet -t $seedImage $seedDir | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "DB_SEED_IMAGE_FAILED" }
    $script:runtimeCompose = Join-Path $repo ("backend\docker-compose.exp155-$($RunId.ToLowerInvariant()).yaml")
    $yaml = Get-Content $baseComposeOriginal -Raw -Encoding UTF8
    $yaml = [regex]::Replace($yaml,'(?m)^\s*-\s*"[^\r\n]*doEng\.sql:/docker-entrypoint\.d[^\r\n]*\r?\n','')
    $yaml = [regex]::Replace($yaml,'(?m)^\s*-\s*"[^\r\n]*02-mission-completion\.sql:/docker-entrypoint[^\r\n]*\r?\n','')
    $yaml = $yaml.Replace('image: mariadb:10.11',"image: $seedImage")
    foreach ($image in @($appImage,$mockImage)) { if (-not (docker image inspect $image 2>$null)) { throw "FROZEN_IMAGE_MISSING:$image" } }
    $sourceBackend = ((Join-Path $sourceWorktree "backend") -replace '\\','/')
    $yaml = $yaml.Replace('context: ./doEngGameFlux',"context: $sourceBackend/doEngGameFlux")
    $yaml = $yaml.Replace('context: ./experiment-mock',"context: $sourceBackend/experiment-mock")
    $yaml = [regex]::Replace($yaml, '(?ms)(  experiment-mock:\r?\n)    build:\r?\n      context:[^\r\n]*\r?\n', '$1    image: ' + $mockImage + "`n")
    $yaml = [regex]::Replace($yaml, '(?ms)(  flux-corrected:\r?\n)    build:\r?\n      context:[^\r\n]*\r?\n      dockerfile:[^\r\n]*\r?\n', '$1    image: ' + $appImage + "`n")
    $yaml = $yaml.Replace('"3307:3306"',('"'+$ports.db+':3306"'))
    $yaml = $yaml.Replace('"9100:9100"',('"'+$ports.mock+':9100"'))
    $yaml = $yaml.Replace('"8000:8000"',('"'+$ports.app+':8000"')).Replace('"8001:8000"',('"'+$ports.app+':8000"'))
    $yaml = $yaml.Replace('"9001:9091"',('"'+$ports.management+':9091"'))
    Set-Content $runtimeCompose $yaml -Encoding UTF8
}
function Wait-Health {
    for ($i=0;$i -lt 90;$i++) { try { if ((Invoke-RestMethod "$managementUrl/actuator/health" -TimeoutSec 2).status -eq "UP") { return } } catch {}; Start-Sleep 1 }
    throw "HEALTH_TIMEOUT"
}
function Start-Collector {
    $provider = Join-Path $runDir "provider-metrics.jsonl"; $stage=Join-Path $runDir "stage-metrics.jsonl"; $admission=Join-Path $runDir "admission-metrics.jsonl"; $resources=Join-Path $runDir "application-resources.jsonl"
    $script:collector = Start-Job -ScriptBlock {
        param($Provider,$Stage,$Admission,$Resources,$Management,$RunId,$Cell,$Mock,$Seconds)
        $end=(Get-Date).AddSeconds($Seconds)
        while((Get-Date)-lt $end){
            $ts=[DateTime]::UtcNow.ToString("o")
            foreach($spec in @(@("pool",$Provider,"doengdiagnosticpool"),@("stage",$Stage,"doengdiagnosticstage"),@("admission",$Admission,"doengadmission"))){ try { $v=Invoke-RestMethod "$Management/actuator/$($spec[2])" -TimeoutSec 3; (@{timestamp=$ts;runId=$RunId;cell=$Cell;value=$v}|ConvertTo-Json -Compress)|Add-Content $spec[1] } catch { (@{timestamp=$ts;error=$_.Exception.Message}|ConvertTo-Json -Compress)|Add-Content $spec[1] } }
            try { $s=docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.PIDs}}'; foreach($line in $s){(@{timestamp=$ts;value=$line}|ConvertTo-Json -Compress)|Add-Content $Resources} } catch {}
            Start-Sleep 1
        }
    } -ArgumentList $provider,$stage,$admission,$resources,$managementUrl,$RunId,$Cell,$mockUrl,95
}
function Run-Load {
    $node=Resolve-NodeExecutable; $loadDir=Join-Path $runDir load; New-Item -ItemType Directory -Force -Path $loadDir | Out-Null
    $result=Join-Path $loadDir "client-results.json"
    $env:TARGET_URL="$applicationUrl/game/face"; $env:ACTIVE_MISSIONS="200"; $env:INITIAL_ACTIVE_USERS="200"; $env:ACTIVATION_STEP_USERS="200"; $env:INTERVAL_MS="1000"; $env:DURATION_MS="30000"; $env:REQUEST_TIMEOUT_MS="15000"; $env:SCENE_ID="2"; $env:ANSWER="happy"; $env:AUTH_TOKEN="Bearer experiment-member-15"; $env:FIXTURE_PATH=$fixture; $env:EXPERIMENT_RUN_ID=$RunId; $env:IMPLEMENTATION=$Cell; $env:RESULT_PATH=$result; $env:PROGRESS_PATH=(Join-Path $loadDir "client-progress.jsonl"); $env:STOP_USER_ON_TRUE="false"; $env:LOAD_SCENARIO="single-success"; $env:ARRIVAL_MODE="staggered"; $env:ACCOUNTING_MODE="corrected"; $env:DRAIN_OBSERVATION_SECONDS="30"; $env:MOCK_METRICS_URL="$mockUrl/__metrics"; $env:LOAD_STOP_MOCK_METRICS_PATH=(Join-Path $runDir "load-stop-mock-metrics.json"); $env:MOCK_DRAIN_PATH=(Join-Path $runDir "mock-drain.jsonl"); $env:MOCK_DRAIN_SUMMARY_PATH=(Join-Path $runDir "mock-drain-summary.json")
    "node experiment/load/mission-load.js" | Set-Content (Join-Path $runDir "load-command.txt") -Encoding UTF8
    $p=Start-Process $node -ArgumentList $missionLoad -WorkingDirectory $repo -RedirectStandardOutput (Join-Path $loadDir "stdout.log") -RedirectStandardError (Join-Path $loadDir "stderr.log") -PassThru -Wait
    Save-Json (Join-Path $runDir "load-exit.json") ([ordered]@{exitCode=$p.ExitCode;startedAt=[DateTime]::UtcNow.ToString("o")})
    if ($p.ExitCode -ne 0 -or -not (Test-Path $result)) { throw "LOAD_FAILED_OR_RESULT_MISSING" }
    Copy-Item $result (Join-Path $runDir "load-summary.json")
}
function Save-Snapshots {
    foreach($pair in @(@("mock-final.json","$mockUrl/__metrics"),@("admission-final.json","$managementUrl/actuator/doengadmission"),@("stage-final.json","$managementUrl/actuator/doengdiagnosticstage"),@("pool-final.json","$managementUrl/actuator/doengdiagnosticpool"))){ try { Save-Json (Join-Path $runDir $pair[0]) (Invoke-RestMethod $pair[1] -TimeoutSec 5) } catch { Save-Json (Join-Path $runDir $pair[0]) ([ordered]@{status="NOT_AVAILABLE";error=$_.Exception.Message}) } }
    Save-Json (Join-Path $runDir "db-integrity.json") ([ordered]@{status="REACHABLE_ONLY";meaning="No semantic DB integrity inference"})
}
function Validate-Run {
    $load=Get-Content (Join-Path $runDir "load-summary.json") -Raw | ConvertFrom-Json
    $valid=$true; $reasons=@()
    if ($load.summary.fixtureSha256 -and $load.summary.fixtureSha256 -ne ((Get-FileHash $fixture -Algorithm SHA256).Hash.ToLowerInvariant())) { $valid=$false; $reasons += "FIXTURE_MISMATCH" }
    if ($Cell -eq "SINK") {
        $drain=Get-Content (Join-Path $runDir "mock-drain-summary.json") -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($drain -and -not $drain.drainCompleted) { $valid=$false; $reasons += "DOWNSTREAM_DRAIN_INCOMPLETE" }
    }
    Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$valid;validityScope="EXECUTE";reasons=$reasons;checkedAt=[DateTime]::UtcNow.ToString("o")})
    if (-not $valid) { throw "RUN_INVALID:$($reasons -join ',')" }
}
Assert-Inputs
if ($Mode -eq "Plan") { Save-Json (Join-Path $runDir "plan.json") ([ordered]@{status="PLAN_ONLY";cell=$Cell;activeMissions=200;durationMs=30000}); exit 0 }
try {
    Prepare-Source; Prepare-Compose; $started=$true
    Compose @("up","-d","--force-recreate","mariadb","experiment-mock","flux-corrected"); Wait-Health
    Save-Json (Join-Path $runDir "warmup.json") ([ordered]@{status="PASS"})
    Start-Collector; Start-Sleep 5; Run-Load; Save-Snapshots
    Wait-Job $collector -Timeout 100 | Out-Null; Receive-Job $collector -ErrorAction SilentlyContinue | Out-Null; Remove-Job $collector -Force
    Validate-Run
    "EXP155_EXECUTE_PASS CELL=$Cell RUN_ID=$RunId"
} catch {
    Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$false;validityScope="EXECUTE";reasons=@($_.Exception.Message);checkedAt=[DateTime]::UtcNow.ToString("o")})
    throw
} finally {
    if ($started) { try { Compose @("logs","--no-color","--timestamps","flux-corrected") | Set-Content (Join-Path $runDir "application.log") -Encoding UTF8 } catch {}; try { Compose @("logs","--no-color","--timestamps","experiment-mock") | Set-Content (Join-Path $runDir "mock.log") -Encoding UTF8 } catch {}; try { Compose @("down","--volumes","--remove-orphans") | Out-Null } catch {} }
    if ($collector) { Remove-Job $collector -Force -ErrorAction SilentlyContinue }
    if ($runtimeCompose -and (Test-Path $runtimeCompose)) { Remove-Item $runtimeCompose -Force -ErrorAction SilentlyContinue }
    if ($seedImage) { docker image rm -f $seedImage 2>$null | Out-Null }
    if ($seedDir -and (Test-Path $seedDir)) { Remove-Item $seedDir -Recurse -Force -ErrorAction SilentlyContinue }
    if ($sourceWorktree -and (Test-Path $sourceWorktree)) { & git -c ("safe.directory=" + $sourceWorktree.Replace('\','/')) -C $repo worktree remove --force $sourceWorktree 2>$null }
    & git -C $repo worktree prune 2>$null
    Save-Json (Join-Path $runDir "cleanup.json") ([ordered]@{completed=$true;at=[DateTime]::UtcNow.ToString("o")})
}
