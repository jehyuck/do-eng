param(
    [Parameter(Mandatory = $true)][string]$ComposeProject,
    [string]$ServerService = "mvc",
    [string[]]$ComposeFiles = @("backend\docker-compose.experiment.yaml"),
    [int]$MainPort = 8002,
    [int]$ManagementPort = 9002,
    [int]$MockPort = 9100,
    [int]$MaxWaitSeconds = 120,
    [int]$StableSeconds = 10,
    [string]$ComposeFilesBase64 = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFilesSource = "PARAMETER_DEFAULT"
if (-not [string]::IsNullOrWhiteSpace($ComposeFilesBase64)) {
    try {
        $bytes = [Convert]::FromBase64String($ComposeFilesBase64)
        $json = [Text.Encoding]::UTF8.GetString($bytes)
        $decoded = $json | ConvertFrom-Json
        if ($decoded.Count -lt 1) { throw "Decoded compose file list is empty" }
        $ComposeFiles = @($decoded | ForEach-Object { [string]$_ })
        $composeFilesSource = "BASE64_JSON"
    } catch {
        throw "COMPOSE_FILES_DECODE: FAIL — $($_.Exception.Message)"
    }
}
$composeArguments = @()
foreach ($file in $ComposeFiles) {
    $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $repositoryRoot $file }
    $composeArguments += @("-f", [IO.Path]::GetFullPath($path))
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot "startup-gate.json"
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot $OutputPath
}

function Convert-HttpContentToText {
    param($Content)
    if ($null -eq $Content) { return "" }
    if ($Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($Content) }
    if ($Content -is [string]) { return $Content }
    return [string]$Content
}

function Convert-HttpContent {
    param($Content)
    $text = Convert-HttpContentToText $Content
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return $text | ConvertFrom-Json } catch { return $text }
}

function Get-HttpJson {
    param([string]$Uri)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 2
        $text = Convert-HttpContentToText $response.Content
        $body = Convert-HttpContent $response.Content
        return [pscustomobject]@{ status = [int]$response.StatusCode; text = $text; body = $body }
    } catch {
        return [pscustomobject]@{ status = 0; text = ""; body = $null }
    }
}

function Get-ServerContainer {
    $ids = @(& docker compose -p $ComposeProject @composeArguments ps -q $ServerService 2>$null |
        ForEach-Object { $value = ([string]$_).Trim(); if ($value) { $value } })
    if ($ids.Count -ne 1) { return $null }
    $inspect = @(& docker inspect $ids[0] 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($inspect -join [Environment]::NewLine) | ConvertFrom-Json)[0]
}

function Test-Up($probe) {
    return $null -ne $probe -and $probe.status -eq 200 -and
        $probe.body.status -eq "UP"
}

function Test-Idle($snapshot) {
    if ($null -eq $snapshot -or $snapshot.status -ne 200) { return $false }
    $runtime = $snapshot.body.requestRuntime
    $http = $snapshot.body.outboundHttp
    if ($null -eq $runtime -or $null -eq $http) { return $false }
    if ($null -eq $runtime.busy -or $null -eq $runtime.queue -or
        $null -eq $http.active -or $null -eq $http.pending) { return $false }
    $runtimeOk = (($runtime.busy -as [double]) -eq 0 -and ($runtime.queue -as [double]) -eq 0)
    $httpOk = (($http.active -as [double]) -eq 0 -and ($http.pending -as [double]) -eq 0)
    return $runtimeOk -and $httpOk
}

$startedAt = Get-Date
$firstLivenessAt = $null
$firstReadinessAt = $null
$stableStartedAt = $null
$readyForLoadAt = $null
$stableCount = 0
$attempts = [ordered]@{ liveness = 0; readiness = 0; canary = 0 }
$last = $null

while (((Get-Date) - $startedAt).TotalSeconds -lt $MaxWaitSeconds) {
    $container = Get-ServerContainer
    $containerReady = $null -ne $container -and $container.State.Running -and
        -not $container.State.Restarting -and -not $container.State.OOMKilled -and
        $container.RestartCount -eq 0
    $mainLive = Get-HttpJson "http://127.0.0.1:$MainPort/livez"
    $managementLive = Get-HttpJson "http://127.0.0.1:$ManagementPort/actuator/health/liveness"
    $mainReady = Get-HttpJson "http://127.0.0.1:$MainPort/readyz"
    $managementReady = Get-HttpJson "http://127.0.0.1:$ManagementPort/actuator/health/readiness"
    $canary = Get-HttpJson "http://127.0.0.1:$MainPort/test"
    $mockHealth = Get-HttpJson "http://127.0.0.1:$MockPort/health"
    $mockMetrics = Get-HttpJson "http://127.0.0.1:$MockPort/__metrics"
    $snapshot = Get-HttpJson "http://127.0.0.1:$ManagementPort/actuator/doengexperiment"
    $attempts.liveness++
    if (Test-Up $mainLive -and Test-Up $managementLive -and $null -eq $firstLivenessAt) { $firstLivenessAt = Get-Date }
    if (Test-Up $mainReady -and Test-Up $managementReady -and $null -eq $firstReadinessAt) { $firstReadinessAt = Get-Date }
    if ($canary.status -eq 200) { $attempts.canary++ }
    if (Test-Up $mainReady) { $attempts.readiness++ }
    $mockReady = $mockHealth.status -eq 200 -and $mockMetrics.status -eq 200 -and
        ($mockMetrics.body.aiInFlight -as [double]) -eq 0 -and
        ($mockMetrics.body.storageInFlight -as [double]) -eq 0
    $allReady = $containerReady -and (Test-Up $mainLive) -and (Test-Up $managementLive) -and
        (Test-Up $mainReady) -and (Test-Up $managementReady) -and $canary.status -eq 200 -and
        $mockReady -and (Test-Idle $snapshot)
    if ($allReady) {
        if ($stableCount -eq 0) { $stableStartedAt = Get-Date }
        $stableCount++
    } else {
        $stableCount = 0
        $stableStartedAt = $null
    }
    $last = [ordered]@{
        container = $containerReady
        mainLiveness = $mainLive
        managementLiveness = $managementLive
        mainReadiness = $mainReady
        managementReadiness = $managementReady
        canary = $canary
        mockHealth = $mockHealth
        mockMetrics = $mockMetrics
        applicationSnapshot = $snapshot
        stableCount = $stableCount
    }
    $stableElapsedMs = if ($stableStartedAt) { [math]::Round(((Get-Date) - $stableStartedAt).TotalMilliseconds) } else { 0 }
    if ($stableStartedAt -and $stableElapsedMs -ge ($StableSeconds * 1000)) {
        $readyForLoadAt = Get-Date
        break
    }
    Start-Sleep -Seconds 1
}

$result = [ordered]@{
    composeFileCount = @($ComposeFiles).Count
    composeFiles = @($ComposeFiles)
    composeFilesSource = $composeFilesSource
    containerStartedAt = if ($null -ne $container) { $container.State.StartedAt } else { $null }
    firstLivenessUpAt = if ($firstLivenessAt) { $firstLivenessAt.ToUniversalTime().ToString("o") } else { $null }
    firstReadinessUpAt = if ($firstReadinessAt) { $firstReadinessAt.ToUniversalTime().ToString("o") } else { $null }
    stableWindowStartedAt = if ($stableStartedAt) { $stableStartedAt.ToUniversalTime().ToString("o") } else { $null }
    readyForLoadAt = if ($readyForLoadAt) { $readyForLoadAt.ToUniversalTime().ToString("o") } else { $null }
    startupAgeMsAtLoad = if ($readyForLoadAt -and $container) { [math]::Round(($readyForLoadAt - [datetime]$container.State.StartedAt).TotalMilliseconds) } else { $null }
    livenessAttempts = $attempts.liveness
    readinessAttempts = $attempts.readiness
    canaryAttempts = $attempts.canary
    containerId = if ($container) { $container.Id } else { $null }
    restartCount = if ($container) { $container.RestartCount } else { $null }
    oomKilled = if ($container) { $container.State.OOMKilled } else { $null }
    mainLiveness = $last.mainLiveness
    managementLiveness = $last.managementLiveness
    mainReadiness = $last.mainReadiness
    managementReadiness = $last.managementReadiness
    mockHealth = $last.mockHealth
    mockAiInFlight = if ($last.mockMetrics) { $last.mockMetrics.body.aiInFlight } else { $null }
    mockStorageInFlight = if ($last.mockMetrics) { $last.mockMetrics.body.storageInFlight } else { $null }
    stableWindowSeconds = $StableSeconds
    stableWindowActualMs = if ($stableStartedAt -and $readyForLoadAt) {
        [math]::Round(($readyForLoadAt - $stableStartedAt).TotalMilliseconds)
    } else { 0 }
    loadAllowed = $null -ne $readyForLoadAt
}
$result | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $OutputPath
if (-not $result.loadAllowed) { Write-Error "STARTUP_GATE: FAIL"; exit 1 }
Write-Output "STARTUP_GATE: PASS"
