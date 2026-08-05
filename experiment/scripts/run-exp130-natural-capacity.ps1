param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet('SMOKE','CORE')][string]$ExecutionMode = 'SMOKE',
    [string]$RunDate = (Get-Date -Format yyyyMMdd)
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resultRoot = Join-Path $root 'backend\experiments\results\experiment-1-30'
$legacyRoot = Join-Path $root ("experiment\results\{0}" -f $RunId)
$artifactRoot = Join-Path $resultRoot ("{0}\{1}" -f $ExecutionMode.ToLowerInvariant(), $RunId)
$project = 'doeng-exp130-natural-capacity'
$files = @(
    'backend\docker-compose.experiment.yaml',
    'backend\docker-compose.app-instance-t3-medium.yaml',
    'backend\docker-compose.mock-headroom-4cpu.yaml',
    'backend\docker-compose.http-pool-400.yaml',
    'backend\docker-compose.mock-memory-headroom.yaml',
    'backend\docker-compose.experiment-1-12-connection-attribution.yaml',
    'backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml',
    'backend\docker-compose.experiment-1-30-natural-capacity.yaml'
)
$compose = @(); foreach ($file in $files) { $compose += @('-f', (Join-Path $root $file)) }
$warmupId = "SMOKE-$RunDate-EXP130-A-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$duration = if ($ExecutionMode -eq 'CORE') { 105000 } else { 5000 }
$drainSeconds = if ($ExecutionMode -eq 'CORE') { 30 } else { 10 }

function Write-Json([string]$Path, [object]$Value) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}
function Get-Json([string]$Path) { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$old = @{}
$envValues = [ordered]@{
    DOENG_EXP119_APP_IMAGE = 'doeng-flux-exp119-fresh-first-20260803:latest'
    DOENG_EXP119_MOCK_IMAGE = 'doeng-exp119-mock-frozen-20260803:latest'
}
$failure = $null
try {
    Require (-not (Test-Path -LiteralPath $artifactRoot)) "ARTIFACT_COLLISION: $artifactRoot"
    Require (-not (Test-Path -LiteralPath $legacyRoot)) "LEGACY_ARTIFACT_COLLISION: $legacyRoot"
    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

    foreach ($file in $files) { Require (Test-Path -LiteralPath (Join-Path $root $file)) "COMPOSE_FILE_MISSING: $file" }
    docker compose -p $project @compose config | Set-Content -LiteralPath (Join-Path $artifactRoot 'rendered-compose.yaml') -Encoding UTF8
    Require ($LASTEXITCODE -eq 0) 'COMPOSE_RENDER_FAILED'
    $rendered = Get-Content -Raw (Join-Path $artifactRoot 'rendered-compose.yaml')
    foreach ($expected in @(
        'DOENG_ADMISSION_MODE:\s*"?OFF"?',
        'DOENG_AI_ADMISSION_ENABLED:\s*"?false"?',
        'DOENG_EXTERNAL_POOL_MODE:\s*"?SHARED"?',
        'DOENG_SHARED_POOL_MAX_CONNECTIONS:\s*"?1000"?',
        'DOENG_HTTP_MAX_CONNECTIONS:\s*"?1000"?',
        'DOENG_SHARED_POOL_PENDING_MAX_COUNT:\s*"?800"?',
        'DOENG_HTTP_PENDING_MAX_COUNT:\s*"?800"?',
        'DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT:\s*"?800"?'
    )) { Require ([regex]::IsMatch($rendered, $expected)) "RENDERED_VALUE_MISSING: $expected" }

    foreach ($entry in $envValues.GetEnumerator()) { $old[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process'); [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    docker compose -p $project @compose up -d --force-recreate --no-build mariadb experiment-mock flux-corrected | Out-Null
    Require ($LASTEXITCODE -eq 0) 'FRESH_RECREATE_FAILED'

    $baseArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'run-isolated-vu-success-smoke.ps1'),
        '-TargetUrl','http://127.0.0.1:8001/game/face','-ServerService','flux-corrected','-ComposeProject',$project,
        '-ComposeFiles',($files -join ','),'-AiDelayMs','2000','-StorageDelayMs','100','-IntervalMs','1000',
        '-RequestTimeoutMs','10000','-TargetP95Ms','10000','-EnableObservability','1','-EnableJfr','0',
        '-EnableContainerMonitor','1','-SkipApplicationSnapshot','1','-SkipMockMetrics','1',
        '-OutcomeMode','natural-capacity','-AccountingMode','corrected', '-DrainObservationSeconds',([string]$drainSeconds))

    & powershell.exe @baseArgs -RunId $warmupId -Implementation 'Exp130-A-warmup' -ActiveMissions 20 -DurationMs 5000
    Require ($LASTEXITCODE -eq 0) 'WARMUP_FAILED'
    $admissionBefore = Invoke-RestMethod -Uri 'http://127.0.0.1:9001/actuator/doengadmission' -TimeoutSec 5
    Require ($admissionBefore.mode -eq 'OFF') 'ADMISSION_NOT_OFF_BEFORE_CORE'

    $collectorRoot = Join-Path $artifactRoot 'pool'
    $signal = Join-Path $collectorRoot 'STOP-COLLECTOR'
    $collectorSummary = Join-Path $collectorRoot 'pool-metrics.jsonl.summary.json'
    $collectorOutput = Join-Path $collectorRoot 'pool-metrics.jsonl'
    $collector = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'collect-exp129-pool-until-stop.ps1'),
        '-ManagementUrl','http://127.0.0.1:9001','-OutputPath',$collectorOutput,'-SummaryPath',$collectorSummary,
        '-StopSignalPath',$signal,'-IntervalMilliseconds','1000','-MaxDurationSeconds','300')
    Start-Sleep -Seconds 2
    $coreArgs = $baseArgs + @('-RunId',$RunId,'-Implementation','Exp130-A-natural-capacity',
        '-ActiveMissions','200','-InitialActiveUsers','200','-ActivationStepUsers','200','-DurationMs',([string]$duration))
    & powershell.exe @coreArgs
    $coreExit = $LASTEXITCODE
    New-Item -ItemType File -Force -Path $signal | Out-Null
    Require ($collector.WaitForExit(15000)) 'COLLECTOR_STOP_TIMEOUT'
    Require ($coreExit -eq 0) 'CORE_OR_SMOKE_FAILED'

    $admissionAfter = Invoke-RestMethod -Uri 'http://127.0.0.1:9001/actuator/doengadmission' -TimeoutSec 5
    Write-Json (Join-Path $artifactRoot 'admission-before.json') $admissionBefore
    Write-Json (Join-Path $artifactRoot 'admission-after.json') $admissionAfter
    Require ($admissionAfter.mode -eq 'OFF') 'ADMISSION_NOT_OFF_AFTER_CORE'
    Require (Test-Path -LiteralPath $collectorOutput) 'POOL_ARTIFACT_MISSING'
    Require (Test-Path -LiteralPath $collectorSummary) 'POOL_SUMMARY_MISSING'
    $summary = Get-Json $collectorSummary
    Require ($summary.failures -eq 0) 'POOL_COLLECTOR_FAILURES'
    $samples = @(Get-Content -LiteralPath $collectorOutput | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.ok -eq $true })
    Require ($samples.Count -ge 3) 'POOL_SAMPLE_COUNT_LT_3'
    foreach ($name in @('active.connections','idle.connections','total.connections','pending.connections')) {
        $values = @($samples | ForEach-Object { $_.metrics } | Where-Object { $_.name -like "*.$name" -and $null -ne $_.value })
        Require ($values.Count -gt 0) "POOL_METRIC_NOT_NUMERIC: $name"
    }

    if (Test-Path -LiteralPath $legacyRoot) {
        Copy-Item -Recurse -Force (Join-Path $legacyRoot '*') $artifactRoot
    }
    Write-Json (Join-Path $artifactRoot 'exp130-run-config.json') ([ordered]@{
        runId=$RunId; executionMode=$ExecutionMode; warmupRunId=$warmupId; admissionMode='OFF'; admissionEnabled=$false
        poolMode='SHARED'; sharedPoolMaxConnections=1000; pendingAcquireMaxCount=800; leasingStrategy='FIFO'
        maxIdleTimeMs=0; evictionIntervalMs=0; vu=200; durationMs=$duration; aiDelayMs=2000; storageDelayMs=100
        requestTimeoutMs=10000; appCpu=2; appMemory='3GiB'; dbPool=10; imageFrozen=$true
    })
    Write-Output "EXP130_SMOKE_COMPLETED: $RunId"
} catch { $failure = $_ } finally {
    if ($null -ne $collector -and -not $collector.HasExited) { try { $collector.Kill() } catch {} }
    docker compose -p $project @compose down --remove-orphans | Out-Null
    foreach ($entry in $old.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
}
if ($failure) { Write-Error $failure; exit 1 }
