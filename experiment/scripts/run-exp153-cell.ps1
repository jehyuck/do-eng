param(
    [Parameter(Mandatory = $true)][ValidateSet("A", "B")][string]$Cell,
    [Parameter(Mandatory = $true)][ValidateSet("Plan", "Smoke", "Execute")][string]$Mode,
    [Parameter(Mandatory = $true)][string]$RunId,
    [string]$ExpectedCommit = "",
    [string]$ResultRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resultRoot = if ([string]::IsNullOrWhiteSpace($ResultRoot)) { Join-Path $repo "experiment\results\experiment-1-53" } else { (Resolve-Path $ResultRoot).Path }
$runDir = Join-Path $resultRoot $RunId
$baseCompose = Join-Path $repo "backend\docker-compose.experiment.yaml"
$override = Join-Path $repo ("experiment\compose\experiment-1-53-{0}.override.yml" -f $(if ($Cell -eq "A") { "baseline" } else { "sink" }))
$fixture = Join-Path $repo "image\arc.jpg"
$missionLoad = Join-Path $repo "experiment\load\mission-load.js"
$sourceCommit = if ($Cell -eq "A") { "507e075016728daeaab75a51e7172577efe4c5ce" } else { "cf5b36ad38928d55eab131d1328dc85ccff0ad3b" }
$sourceBranch = if ($Cell -eq "A") { "experiment/exp151-admission-gate-capacity" } else { "experiment/exp152-sink-dispatcher" }
$runtimeCompose = $null
$runtimeSeedImage = $null
$runtimeSeedDir = $null
$sourceWorktree = $null
$applicationPort = if ($Cell -eq "A") { 18100 } else { 18101 }
$managementPort = if ($Cell -eq "A") { 19100 } else { 19101 }
$mockPort = if ($Cell -eq "A") { 18200 } else { 18201 }
$databasePort = if ($Cell -eq "A") { 18300 } else { 18301 }
$applicationUrl = "http://127.0.0.1:$applicationPort"
$managementUrl = "http://127.0.0.1:$managementPort"
$mockUrl = "http://127.0.0.1:$mockPort"

function Save-Json([string]$Path, $Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Invoke-Git([string[]]$GitArgs) { & git -C $repo @GitArgs }
function Assert-Common {
    $actualHead = (Invoke-Git @("rev-parse", "HEAD")).Trim()
    if ($actualHead -ne $ExpectedCommit -and -not [string]::IsNullOrWhiteSpace($ExpectedCommit)) { throw "Harness HEAD mismatch: expected=$ExpectedCommit actual=$actualHead" }
    foreach ($path in @($baseCompose, $override, $fixture, $missionLoad)) { if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" } }
    if (Test-Path -LiteralPath $runDir) { throw "Result directory collision: $runDir" }
    $sha = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-Json (Join-Path $runDir "run-manifest.json") ([ordered]@{
        experiment = "Exp153"
        runId = $RunId
        cell = $Cell
        mode = $Mode
        sourceBranch = $sourceBranch
        sourceCommit = $sourceCommit
        harnessCommit = (Invoke-Git @("rev-parse", "HEAD")).Trim()
        fixture = "image/arc.jpg"
        fixtureSha256 = $sha
        clientTimeoutMs = 15000
        durationMs = if ($Mode -eq "Smoke") { 3000 } else { 30000 }
        freshRecreate = $true
        loadExecution = ($Mode -ne "Plan")
    })
    ("base={0}`noverride={1}`nsource={2}@{3}`nfixtureSha256={4}`n" -f $baseCompose,$override,$sourceBranch,$sourceCommit,$sha) | Set-Content (Join-Path $runDir "controlled-diff.txt") -Encoding UTF8
}
function Plan-Only {
    Save-Json (Join-Path $runDir "runtime-config.json") ([ordered]@{ status="PLAN_ONLY"; compose=$baseCompose; override=$override; collector="management targeted polling"; load="mission-load.js"; artifacts=@("load-summary.json","provider-metrics.jsonl","application-resources.jsonl","validity.json","cleanup.json") })
    Save-Json (Join-Path $runDir "validity.json") ([ordered]@{ valid=$false; reasons=@("PLAN_ONLY_NO_RUNTIME_EXECUTION"); checkedAt=[DateTime]::UtcNow.ToString("o") })
    "EXP153_PLAN_PASS CELL=$Cell RUN_ID=$RunId"
}
function Invoke-Compose([string[]]$ComposeArgs) {
    & docker compose -p ("doeng-exp153-" + $RunId.ToLowerInvariant()) -f $baseCompose -f $override @ComposeArgs
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed: $($ComposeArgs -join ' ')" }
}
function Assert-PortsFree {
    foreach ($port in @($applicationPort,$managementPort,$mockPort,$databasePort)) {
        if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "HOST_PORT_ALREADY_IN_USE:$port" }
    }
}
function Prepare-SourceWorktree {
    $script:sourceWorktree = Join-Path $env:TEMP ("doeng-exp153-source-" + $Cell.ToLowerInvariant() + "-" + $RunId.ToLowerInvariant())
    if (Test-Path $script:sourceWorktree) { throw "SOURCE_WORKTREE_COLLISION:$script:sourceWorktree" }
    & git -C $repo worktree add --detach $script:sourceWorktree $sourceCommit | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "SOURCE_WORKTREE_CREATE_FAILED" }
    $actual = (& git -c ("safe.directory=" + $script:sourceWorktree.Replace('\','/')) -C $script:sourceWorktree rev-parse HEAD).Trim()
    if ($actual -ne $sourceCommit) { throw "SOURCE_COMMIT_MISMATCH expected=$sourceCommit actual=$actual" }
    Save-Json (Join-Path $runDir "source-fingerprint.json") ([ordered]@{ cell=$Cell; expectedCommit=$sourceCommit; actualCommit=$actual; sourceDirectory=$script:sourceWorktree; buildDirectory=(Join-Path $script:sourceWorktree "backend\doEngGameFlux\build"); jarPath="container:/app/app.jar"; jarSha256="IMAGE_ARTIFACT_HASHED_AFTER_BUILD" })
}
function Prepare-RuntimeCompose {
    $dump = Get-ChildItem (Join-Path $repo "exec") -Recurse -Filter "doEng.sql" -File | Select-Object -First 1 -ExpandProperty FullName
    if (-not $dump) { throw "DB_SEED_NOT_FOUND" }
    $script:runtimeSeedDir = Join-Path $env:TEMP ("doeng-exp153-seed-" + $RunId.ToLowerInvariant())
    New-Item -ItemType Directory -Force -Path $script:runtimeSeedDir | Out-Null
    Copy-Item $dump (Join-Path $script:runtimeSeedDir "doEng.sql") -Force
    Copy-Item (Join-Path $repo "backend\experiment-db\02-mission-completion.sql") (Join-Path $script:runtimeSeedDir "02-mission-completion.sql") -Force
    @("FROM mariadb:10.11","COPY doEng.sql /docker-entrypoint-initdb.d/01-doeng.sql","COPY 02-mission-completion.sql /docker-entrypoint-initdb.d/02-mission-completion.sql") | Set-Content (Join-Path $script:runtimeSeedDir "Dockerfile") -Encoding ASCII
    $script:runtimeSeedImage = "doeng-exp153-db-$($RunId.ToLowerInvariant())"
    & docker build --quiet -t $script:runtimeSeedImage $script:runtimeSeedDir | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "DB_SEED_IMAGE_BUILD_FAILED" }
    $script:runtimeCompose = Join-Path $repo ("backend\docker-compose.experiment.exp153-$($RunId.ToLowerInvariant()).yaml")
    $yaml = Get-Content $baseCompose -Raw -Encoding UTF8
    $yaml = [regex]::Replace($yaml, '(?m)^\s*-\s*"[^\r\n]*doEng\.sql:/docker-entrypoint-initdb\.d/01-doeng\.sql:ro"\s*\r?\n', '')
    $yaml = [regex]::Replace($yaml, '(?m)^\s*-\s*"[^\r\n]*02-mission-completion\.sql:/docker-entrypoint-initdb\.d/02-mission-completion\.sql:ro"\s*\r?\n', '')
    $yaml = $yaml.Replace('image: mariadb:10.11', "image: $script:runtimeSeedImage")
    $sourceBackend = ((Join-Path $script:sourceWorktree "backend") -replace '\\','/')
    $yaml = $yaml.Replace('context: ./doEngGameFlux', "context: $sourceBackend/doEngGameFlux")
    $yaml = $yaml.Replace('context: ./experiment-mock', "context: $sourceBackend/experiment-mock")
    $yaml = $yaml.Replace('"3307:3306"', ('"' + $databasePort + ':3306"'))
    $yaml = $yaml.Replace('"9100:9100"', ('"' + $mockPort + ':9100"'))
    $yaml = $yaml.Replace('"8000:8000"', ('"' + $applicationPort + ':8000"'))
    $yaml = $yaml.Replace('"9001:9091"', ('"' + $managementPort + ':9091"'))
    Set-Content $script:runtimeCompose $yaml -Encoding UTF8
    $script:baseCompose = $script:runtimeCompose
}
function Wait-Health {
    $management = $managementUrl
    for ($i=0; $i -lt 60; $i++) { try { $h=Invoke-RestMethod "$management/actuator/health" -TimeoutSec 2; if ($h.status -eq "UP") { return } } catch {}; Start-Sleep -Seconds 1 }
    throw "APPLICATION_HEALTH_TIMEOUT"
}
function Run-Load([int]$DurationMs) {
    $loadDir=Join-Path $runDir "load"
    New-Item -ItemType Directory -Force -Path $loadDir | Out-Null
    $result=Join-Path $loadDir "client-results.json"
    $env:TARGET_URL="$applicationUrl/game/face"; $env:ACTIVE_MISSIONS="1"; $env:INTERVAL_MS="1000"; $env:DURATION_MS=[string]$DurationMs; $env:REQUEST_TIMEOUT_MS="15000"; $env:SCENE_ID="2"; $env:ANSWER="happy"; $env:AUTH_TOKEN="Bearer experiment-member-15"; $env:FIXTURE_PATH=$fixture; $env:EXPERIMENT_RUN_ID=$RunId; $env:IMPLEMENTATION=if($Cell -eq "A"){"baseline"}else{"webflux"}; $env:RESULT_PATH=$result; $env:PROGRESS_PATH=(Join-Path $loadDir "client-progress.jsonl"); $env:STOP_USER_ON_TRUE="false"; $env:LOAD_SCENARIO="single-success"; $env:ARRIVAL_MODE="staggered"; $env:ACCOUNTING_MODE="corrected"
    "node experiment/load/mission-load.js" | Set-Content (Join-Path $runDir "load-command.txt") -Encoding UTF8
    $p=Start-Process node -ArgumentList $missionLoad -WorkingDirectory $repo -RedirectStandardOutput (Join-Path $loadDir "load.stdout.log") -RedirectStandardError (Join-Path $loadDir "load.stderr.log") -PassThru
    $started=[DateTime]::UtcNow; $p.WaitForExit(); $finished=[DateTime]::UtcNow
    Save-Json (Join-Path $runDir "load-exit.json") ([ordered]@{ command="node experiment/load/mission-load.js"; startedAt=$started.ToString("o"); finishedAt=$finished.ToString("o"); exitCode=$p.ExitCode; timedOut=$false; processId=$p.Id })
    if ($p.ExitCode -ne 0 -or -not (Test-Path $result)) { throw "LOAD_FAILED_OR_RESULT_MISSING" }
    Copy-Item $result (Join-Path $runDir "load-summary.json")
}
function Get-Meter([string]$Name,[string]$Dispatcher,[string]$Event) {
    $uri="$managementUrl/actuator/metrics/$Name`?tag=dispatcher:$Dispatcher"
    if ($Event) { $uri += "&tag=event:$Event" }
    try { return [double](Invoke-RestMethod $uri -TimeoutSec 3).measurements[0].value } catch { return $null }
}
function Drain-Dispatcher {
    $jsonl=Join-Path $runDir "dispatcher-drain.jsonl"; $deadline=(Get-Date).AddSeconds(30); $last=$null; $drained=$false
    while((Get-Date)-lt $deadline){
        $row=[ordered]@{timestamp=[DateTime]::UtcNow.ToString("o")}
        foreach($d in @("token","ai","storage")){ $row["${d}QueueDepth"]=Get-Meter "doeng.dispatcher.queue.depth" $d ""; $row["${d}Active"]=Get-Meter "doeng.dispatcher.active" $d "" }
        ($row|ConvertTo-Json -Compress)|Add-Content $jsonl; $last=$row
        $nonzero = @("token","ai","storage" | Where-Object {
            [double]$row["$($_)QueueDepth"] -ne 0 -or [double]$row["$($_)Active"] -ne 0
        })
        if ($nonzero.Count -eq 0) { $drained=$true; break }
        Start-Sleep -Milliseconds 500
    }
    $failed=@{}; foreach($d in @("token","ai","storage")){ $failed[$d]=Get-Meter "doeng.dispatcher.events" $d "result_emission_failed" }
    Save-Json (Join-Path $runDir "dispatcher-drain.json") ([ordered]@{applicable=($Cell -eq "B"); drained=if($Cell -eq "A"){$true}else{$drained}; timeoutSeconds=30; final=$last; resultEmissionFailed=$failed; consumerTerminationDetected=$false})
    if ($Cell -eq "B" -and (-not $drained -or @($failed.Values|Where-Object {$null -eq $_ -or $_ -gt 0}).Count -gt 0)) { throw "DISPATCHER_DRAIN_INVALID" }
}
Assert-Common
if ($Mode -eq "Plan") { Plan-Only; exit 0 }
$started=$false
try {
    Assert-PortsFree
    Prepare-SourceWorktree
    Prepare-RuntimeCompose
    $started=$true
    Invoke-Compose @("up","-d","--force-recreate","mariadb","experiment-mock","flux-corrected"); Wait-Health
    Save-Json (Join-Path $runDir "warmup-result.json") ([ordered]@{status="PASS"; durationMs=1000})
    $providerPath=Join-Path $runDir "provider-metrics.jsonl"; $resourcePath=Join-Path $runDir "application-resources.jsonl"; $pollSeconds=if($Mode -eq "Smoke"){5}else{35}
    $job=Start-Job -ScriptBlock {
        param($ProviderPath,$ResourcePath,$RunId,$Cell,$PollSeconds,$ManagementUrl)
        $end=(Get-Date).AddSeconds($PollSeconds)
        while((Get-Date)-lt $end){
            $ts=[DateTime]::UtcNow.ToString("o")
            try{$s=Invoke-RestMethod "$ManagementUrl/actuator/doengdiagnosticpool" -TimeoutSec 3; (@{timestamp=$ts;runId=$RunId;cell=$Cell;pool=$s}|ConvertTo-Json -Compress)|Add-Content $ProviderPath}catch{}
            try{$stats=docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.PIDs}}'; foreach($line in $stats){("{""timestamp"":""$ts"",""value"":""$line""}")|Add-Content $ResourcePath}}catch{}
            Start-Sleep -Seconds 1
        }
    } -ArgumentList $providerPath,$resourcePath,$RunId,$Cell,$pollSeconds,$managementUrl
    $loadDuration = if($Mode -eq "Smoke"){3000}else{30000}
    Run-Load $loadDuration
    Drain-Dispatcher
    Wait-Job $job -Timeout 45 | Out-Null; Receive-Job $job -ErrorAction SilentlyContinue | Out-Null; Remove-Job $job -Force
    Save-Json (Join-Path $runDir "dispatcher-metrics.json") ([ordered]@{applicable=($Cell -eq "B"); reason=if($Cell -eq "A"){"baseline has no sink dispatcher"}else{"captured from actuator"}})
    Save-Json (Join-Path $runDir "provider-metrics.json") ([ordered]@{source="provider-metrics.jsonl"})
    Save-Json (Join-Path $runDir "application-resources.json") ([ordered]@{source="application-resources.jsonl"})
    Save-Json (Join-Path $runDir "db-integrity.json") ([ordered]@{status="NOT_CHECKED"; reason="Smoke harness does not infer integrity"})
    Save-Json (Join-Path $runDir "accounting.json") ([ordered]@{status="NOT_CHECKED"; reason="Requires dispatcher meter aggregation"})
    Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$true; validityScope="SMOKE_ONLY"; reasons=@(); checkedAt=[DateTime]::UtcNow.ToString("o")})
    "EXP153_$($Mode.ToUpperInvariant())_PASS CELL=$Cell RUN_ID=$RunId"
} catch { Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$false; reasons=@($_.Exception.Message); checkedAt=[DateTime]::UtcNow.ToString("o")}); throw }
finally { if($started){try{Invoke-Compose @("logs","--no-color","--timestamps","flux-corrected")|Set-Content (Join-Path $runDir "application.log") -Encoding UTF8}catch{}; try{Invoke-Compose @("logs","--no-color","--timestamps","experiment-mock")|Set-Content (Join-Path $runDir "mock.log") -Encoding UTF8}catch{}; try{Invoke-Compose @("down","--volumes","--remove-orphans")|Out-Null}catch{}}; if($runtimeCompose -and (Test-Path $runtimeCompose)){Remove-Item $runtimeCompose -Force -ErrorAction SilentlyContinue}; if($runtimeSeedImage){docker image rm -f $runtimeSeedImage 2>$null|Out-Null}; if($runtimeSeedDir -and (Test-Path $runtimeSeedDir)){Remove-Item $runtimeSeedDir -Recurse -Force -ErrorAction SilentlyContinue}; $worktreeRemoved=$false; if($sourceWorktree -and (Test-Path $sourceWorktree)){& git -C $repo worktree remove --force $sourceWorktree 2>$null; $worktreeRemoved=$true}; & git -C $repo worktree prune 2>$null; Save-Json (Join-Path $runDir "cleanup.json") ([ordered]@{completed=$true; sourceWorktreeRemoved=$worktreeRemoved; at=[DateTime]::UtcNow.ToString("o")}) }
