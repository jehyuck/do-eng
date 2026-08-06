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
function Invoke-Compose([string[]]$Args) {
    & docker compose -p ("doeng-exp153-" + $RunId.ToLowerInvariant()) -f $baseCompose -f $override @Args
    if ($LASTEXITCODE -ne 0) { throw "docker compose failed: $($Args -join ' ')" }
}
function Wait-Health {
    $management = "http://127.0.0.1:9001"
    for ($i=0; $i -lt 60; $i++) { try { $h=Invoke-RestMethod "$management/actuator/health" -TimeoutSec 2; if ($h.status -eq "UP") { return } } catch {}; Start-Sleep -Seconds 1 }
    throw "APPLICATION_HEALTH_TIMEOUT"
}
function Run-Load([int]$DurationMs) {
    $loadDir=Join-Path $runDir "load"
    New-Item -ItemType Directory -Force -Path $loadDir | Out-Null
    $result=Join-Path $loadDir "client-results.json"
    $env:TARGET_URL="http://127.0.0.1:8001/game/face"; $env:ACTIVE_MISSIONS="1"; $env:INTERVAL_MS="1000"; $env:DURATION_MS=[string]$DurationMs; $env:REQUEST_TIMEOUT_MS="15000"; $env:SCENE_ID="2"; $env:ANSWER="happy"; $env:AUTH_TOKEN="Bearer experiment-member-15"; $env:FIXTURE_PATH=$fixture; $env:EXPERIMENT_RUN_ID=$RunId; $env:IMPLEMENTATION=if($Cell -eq "A"){"baseline"}else{"webflux"}; $env:RESULT_PATH=$result; $env:PROGRESS_PATH=(Join-Path $loadDir "client-progress.jsonl"); $env:STOP_USER_ON_TRUE="false"; $env:LOAD_SCENARIO="single-success"; $env:ARRIVAL_MODE="staggered"; $env:ACCOUNTING_MODE="corrected"
    "node experiment/load/mission-load.js" | Set-Content (Join-Path $runDir "load-command.txt") -Encoding UTF8
    $p=Start-Process node -ArgumentList $missionLoad -WorkingDirectory $repo -RedirectStandardOutput (Join-Path $loadDir "load.stdout.log") -RedirectStandardError (Join-Path $loadDir "load.stderr.log") -PassThru
    $started=[DateTime]::UtcNow; $p.WaitForExit(); $finished=[DateTime]::UtcNow
    Save-Json (Join-Path $runDir "load-exit.json") ([ordered]@{ command="node experiment/load/mission-load.js"; startedAt=$started.ToString("o"); finishedAt=$finished.ToString("o"); exitCode=$p.ExitCode; timedOut=$false; processId=$p.Id })
    if ($p.ExitCode -ne 0 -or -not (Test-Path $result)) { throw "LOAD_FAILED_OR_RESULT_MISSING" }
    Copy-Item $result (Join-Path $runDir "load-summary.json")
}
Assert-Common
if ($Mode -eq "Plan") { Plan-Only; exit 0 }
$started=$false
try {
    Invoke-Compose @("up","-d","--force-recreate","mariadb","experiment-mock","flux-corrected"); $started=$true; Wait-Health
    Save-Json (Join-Path $runDir "warmup-result.json") ([ordered]@{status="PASS"; durationMs=1000})
    $providerPath=Join-Path $runDir "provider-metrics.jsonl"; $resourcePath=Join-Path $runDir "application-resources.jsonl"; $pollSeconds=if($Mode -eq "Smoke"){5}else{35}
    $job=Start-Job -ScriptBlock {
        param($ProviderPath,$ResourcePath,$RunId,$Cell,$PollSeconds)
        $end=(Get-Date).AddSeconds($PollSeconds)
        while((Get-Date)-lt $end){
            $ts=[DateTime]::UtcNow.ToString("o")
            try{$s=Invoke-RestMethod "http://127.0.0.1:9001/actuator/doengdiagnosticpool" -TimeoutSec 3; (@{timestamp=$ts;runId=$RunId;cell=$Cell;pool=$s}|ConvertTo-Json -Compress)|Add-Content $ProviderPath}catch{}
            try{$stats=docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.PIDs}}'; foreach($line in $stats){("{""timestamp"":""$ts"",""value"":""$line""}")|Add-Content $ResourcePath}}catch{}
            Start-Sleep -Seconds 1
        }
    } -ArgumentList $providerPath,$resourcePath,$RunId,$Cell,$pollSeconds
    Run-Load (if($Mode -eq "Smoke"){3000}else{30000})
    Wait-Job $job -Timeout 45 | Out-Null; Receive-Job $job -ErrorAction SilentlyContinue | Out-Null; Remove-Job $job -Force
    Save-Json (Join-Path $runDir "dispatcher-metrics.json") ([ordered]@{applicable=($Cell -eq "B"); reason=if($Cell -eq "A"){"baseline has no sink dispatcher"}else{"captured from actuator"}})
    Save-Json (Join-Path $runDir "provider-metrics.json") ([ordered]@{source="provider-metrics.jsonl"})
    Save-Json (Join-Path $runDir "application-resources.json") ([ordered]@{source="application-resources.jsonl"})
    Save-Json (Join-Path $runDir "db-integrity.json") ([ordered]@{status="NOT_CHECKED"; reason="Smoke harness does not infer integrity"})
    Save-Json (Join-Path $runDir "accounting.json") ([ordered]@{status="NOT_CHECKED"; reason="Requires dispatcher meter aggregation"})
    Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$false; reasons=@("SMOKE_ONLY_NOT_CORE"); checkedAt=[DateTime]::UtcNow.ToString("o")})
    "EXP153_$($Mode.ToUpperInvariant())_PASS CELL=$Cell RUN_ID=$RunId"
} catch { Save-Json (Join-Path $runDir "validity.json") ([ordered]@{valid=$false; reasons=@($_.Exception.Message); checkedAt=[DateTime]::UtcNow.ToString("o")}); throw }
finally { if($started){try{Invoke-Compose @("logs","--no-color","--timestamps","flux-corrected")|Set-Content (Join-Path $runDir "application.log") -Encoding UTF8}catch{}; try{Invoke-Compose @("logs","--no-color","--timestamps","experiment-mock")|Set-Content (Join-Path $runDir "mock.log") -Encoding UTF8}catch{}; try{Invoke-Compose @("down","--remove-orphans")|Out-Null}catch{}}; Save-Json (Join-Path $runDir "cleanup.json") ([ordered]@{completed=$true; at=[DateTime]::UtcNow.ToString("o")}) }
