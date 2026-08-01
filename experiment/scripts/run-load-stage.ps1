param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$Implementation,
    [Parameter(Mandatory = $true)]
    [string]$TargetUrl,
    [Parameter(Mandatory = $true)]
    [string]$ServerService,
    [string]$ComposeProject = "doeng-experiment",
    [string]$FixturePath = "image\arc.jpg",
    [int]$FixtureBytes = 0,
    [ValidateSet("aligned", "staggered")]
    [string]$ArrivalMode = "staggered",
    [int]$ActiveMissions = 10,
    [int]$IntervalMs = 3000,
    [int]$WarmupMs = 10000,
    [int]$DurationMs = 30000,
    [int]$RequestTimeoutMs = 10000,
    [int]$AiDelayMs = 100,
    [int]$AiStatus = 200,
    [long]$MemberId = 15,
    [long]$SceneId = 2,
    [string]$Answer = "happy",
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"

$positiveValues = @{
    ActiveMissions = $ActiveMissions
    IntervalMs = $IntervalMs
    DurationMs = $DurationMs
    RequestTimeoutMs = $RequestTimeoutMs
}
foreach ($entry in $positiveValues.GetEnumerator()) {
    if ($entry.Value -le 0) {
        throw "$($entry.Key) must be positive"
    }
}
if ($WarmupMs -lt 0 -or $AiDelayMs -lt 0) {
    throw "WarmupMs and AiDelayMs cannot be negative"
}
if ($FixtureBytes -lt 0) {
    throw "FixtureBytes cannot be negative"
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFile = Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml"
$resultsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "experiment\results")
)
$runDirectory = Join-Path $resultsRoot $RunId
$mockBaseUrl = "http://127.0.0.1:9100"

if (Test-Path -LiteralPath $runDirectory) {
    throw "Run result directory already exists: $runDirectory"
}

$resolvedFixture = $null
if ($FixtureBytes -eq 0) {
    $resolvedFixture = [System.IO.Path]::GetFullPath(
        (Join-Path $repositoryRoot $FixturePath)
    )
    if (-not (Test-Path -LiteralPath $resolvedFixture)) {
        throw "Fixture not found: $resolvedFixture"
    }
}

if ([string]::IsNullOrWhiteSpace($NodeCommand)) {
    $nodeOnPath = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeOnPath) {
        $NodeCommand = $nodeOnPath.Source
    } else {
        $bundledNode = Join-Path $env:USERPROFILE (
            ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
        )
        if (-not (Test-Path -LiteralPath $bundledNode)) {
            throw "Node executable not found; pass -NodeCommand"
        }
        $NodeCommand = $bundledNode
    }
}

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File (Join-Path $PSScriptRoot "capture-environment.ps1") `
    -RunId $RunId `
    -NodeCommand $NodeCommand
if ($LASTEXITCODE -ne 0) {
    throw "Environment capture failed"
}

& docker compose `
    -p $ComposeProject `
    -f $composeFile `
    config `
    --no-interpolate |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "compose.resolved-without-interpolation.yaml"
    )
if ($LASTEXITCODE -ne 0) {
    throw "Compose snapshot failed"
}

$serviceNames = @($ServerService, "mariadb", "experiment-mock")
$containerLimits = foreach ($serviceName in $serviceNames) {
    $containerId = (
        & docker compose `
            -p $ComposeProject `
            -f $composeFile `
            ps -q $serviceName
    ).Trim()
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw "Running container not found for service: $serviceName"
    }
    $inspect = & docker inspect $containerId | ConvertFrom-Json
    [ordered]@{
        service = $serviceName
        containerId = $containerId
        image = $inspect[0].Image
        nanoCpus = $inspect[0].HostConfig.NanoCpus
        memoryBytes = $inspect[0].HostConfig.Memory
        pidsLimit = $inspect[0].HostConfig.PidsLimit
        javaToolOptions = @(
            $inspect[0].Config.Env |
                Where-Object { $_ -like "JAVA_TOOL_OPTIONS=*" }
        )
    }
}
$containerLimits |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "container-limits.json"
    )
$serverContainerId = (
    & docker compose `
        -p $ComposeProject `
        -f $composeFile `
        ps -q $ServerService
).Trim()
if ([string]::IsNullOrWhiteSpace($serverContainerId)) {
    throw "Server container id was not captured"
}

$fixtureConfig = $null
if ($FixtureBytes -gt 0) {
    $fixtureData = New-Object byte[] $FixtureBytes
    for ($index = 0; $index -lt $FixtureBytes; $index++) {
        $fixtureData[$index] = [byte](($index * 31 + 17) -band 0xff)
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fixtureHashBytes = $sha256.ComputeHash($fixtureData)
    } finally {
        $sha256.Dispose()
    }
    $fixtureConfig = [ordered]@{
        source = "synthetic-deterministic-bytes"
        path = $null
        bytes = $FixtureBytes
        sha256 = (
            [System.BitConverter]::ToString($fixtureHashBytes)
        ).Replace("-", "").ToLower()
        generator = "(index * 31 + 17) & 0xff"
        contentClaim = "payload-size-only; not a real JPEG"
    }
} else {
    $fixture = Get-Item -LiteralPath $resolvedFixture
    $fixtureConfig = [ordered]@{
        source = "file"
        path = $resolvedFixture
        bytes = $fixture.Length
        sha256 = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedFixture
        ).Hash.ToLower()
    }
}

$runConfig = [ordered]@{
    runId = $RunId
    implementation = $Implementation
    targetUrl = $TargetUrl
    serverService = $ServerService
    composeProject = $ComposeProject
    fixture = $fixtureConfig
    arrivalMode = $ArrivalMode
    activeMissions = $ActiveMissions
    intervalMs = $IntervalMs
    warmupMs = $WarmupMs
    durationMs = $DurationMs
    requestTimeoutMs = $RequestTimeoutMs
    aiResult = $false
    aiDelayMs = $AiDelayMs
    aiStatus = $AiStatus
    memberId = $MemberId
    sceneId = $SceneId
    answer = $Answer
    authorization = "Bearer experiment-member-***"
    jfr = [ordered]@{
        enabled = $true
        settings = "profile"
        maxSize = "64m"
        scope = "measurement-and-monitor-tail"
    }
}
$runConfig |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "run-config.json"
    )

$databaseSql = @"
SELECT COUNT(*) FROM progress WHERE member_id=$MemberId AND scene_id=$SceneId;
SELECT COUNT(*) FROM picture p JOIN progress pr ON pr.id=p.progress_id WHERE pr.member_id=$MemberId AND pr.scene_id=$SceneId;
SELECT COUNT(*) FROM progress;
SELECT COUNT(*) FROM picture;
"@

function Get-DatabaseState {
    $output = & docker compose `
        -p $ComposeProject `
        -f $composeFile `
        exec -T mariadb `
        mariadb -N -B `
        -udoeng `
        -pdoeng-experiment-pass `
        doeng `
        -e $databaseSql
    if ($LASTEXITCODE -ne 0) {
        throw "Database observation failed"
    }
    return @($output)
}

function Set-MockState {
    Invoke-RestMethod `
        -Method Post `
        -Uri "$mockBaseUrl/__reset" `
        -ContentType "application/json" `
        -Body "{}" | Out-Null
    $controlPayload = [ordered]@{
        result = $false
        delayMs = $AiDelayMs
        status = $AiStatus
        storageDelayMs = 0
        storageStatus = 200
    }
    return Invoke-RestMethod `
        -Method Post `
        -Uri "$mockBaseUrl/__control" `
        -ContentType "application/json" `
        -Body ($controlPayload | ConvertTo-Json -Compress)
}

function Invoke-LoadDriver {
    param(
        [string]$LoadRunId,
        [int]$LoadDurationMs,
        [string]$ResultFileName,
        [string]$StdoutFileName
    )

    $env:TARGET_URL = $TargetUrl
    $env:ACTIVE_MISSIONS = [string]$ActiveMissions
    $env:INTERVAL_MS = [string]$IntervalMs
    $env:DURATION_MS = [string]$LoadDurationMs
    $env:REQUEST_TIMEOUT_MS = [string]$RequestTimeoutMs
    $env:SCENE_ID = [string]$SceneId
    $env:ANSWER = $Answer
    $env:AUTH_TOKEN = "Bearer experiment-member-$MemberId"
    if ($FixtureBytes -gt 0) {
        $env:FIXTURE_BYTES = [string]$FixtureBytes
        Remove-Item Env:FIXTURE_PATH -ErrorAction SilentlyContinue
    } else {
        $env:FIXTURE_PATH = $resolvedFixture
        Remove-Item Env:FIXTURE_BYTES -ErrorAction SilentlyContinue
    }
    $env:EXPERIMENT_RUN_ID = $LoadRunId
    $env:IMPLEMENTATION = $Implementation
    $env:ARRIVAL_MODE = $ArrivalMode
    $env:STOP_USER_ON_TRUE = "false"
    $env:RESULT_PATH = Join-Path $runDirectory $ResultFileName
    $env:PROGRESS_PATH = Join-Path $runDirectory (
        $ResultFileName -replace "-results\.json$", "-progress.jsonl"
    )

    $stdout = & $NodeCommand (
        Join-Path $repositoryRoot "experiment\load\mission-load.js"
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Load driver failed: $LoadRunId"
    }
    $stdout |
        Set-Content -Encoding UTF8 -LiteralPath (
            Join-Path $runDirectory $StdoutFileName
        )
}

$databaseBefore = Get-DatabaseState
$databaseBefore |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-before.tsv"
    )

Set-MockState |
    ConvertTo-Json -Depth 5 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "mock-control.json"
    )

if ($WarmupMs -gt 0) {
    Invoke-LoadDriver `
        -LoadRunId "$RunId-warmup" `
        -LoadDurationMs $WarmupMs `
        -ResultFileName "warmup-client-results.json" `
        -StdoutFileName "warmup-client-summary.stdout.json"
}

Set-MockState | Out-Null

$monitorScript = Join-Path $PSScriptRoot "monitor-containers.ps1"
$monitorStdout = Join-Path $runDirectory "monitor.stdout.log"
$monitorStderr = Join-Path $runDirectory "monitor.stderr.log"
$monitorDurationSeconds = [int][Math]::Ceiling($DurationMs / 1000) + 2
$jfrDurationSeconds = $monitorDurationSeconds + 3
$jfrName = "doeng_" + ($RunId -replace "[^A-Za-z0-9_]", "_")
$jfrContainerFile = "/tmp/$RunId.jfr"
$jfrStartArguments = @(
    "1",
    "JFR.start",
    "name=$jfrName",
    "settings=profile",
    "duration=$($jfrDurationSeconds)s",
    "filename=$jfrContainerFile",
    "maxsize=64m"
)
$jfrStartOutput = & docker exec $serverContainerId `
    env -u JAVA_TOOL_OPTIONS `
    jcmd @jfrStartArguments 2>&1
if ($LASTEXITCODE -ne 0) {
    $jfrStartOutput | Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "jfr-start.stderr.log"
    )
    throw "JFR start failed"
}
$jfrStartedAt = Get-Date
[ordered]@{
    containerId = $serverContainerId
    command = "jcmd " + ($jfrStartArguments -join " ")
    startedAt = $jfrStartedAt.ToUniversalTime().ToString("o")
    output = @($jfrStartOutput)
} |
    ConvertTo-Json -Depth 5 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "jfr-command.json"
    )
$monitorArguments = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $monitorScript,
    "-RunId",
    $RunId,
    "-ServerService",
    $ServerService,
    "-ComposeProject",
    $ComposeProject,
    "-DurationSeconds",
    [string]$monitorDurationSeconds,
    "-IntervalSeconds",
    "1",
    "-NodeCommand",
    $NodeCommand
)
$monitorProcess = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList $monitorArguments `
    -WorkingDirectory $repositoryRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $monitorStdout `
    -RedirectStandardError $monitorStderr `
    -PassThru

Start-Sleep -Seconds 1
Invoke-LoadDriver `
    -LoadRunId $RunId `
    -LoadDurationMs $DurationMs `
    -ResultFileName "client-results.json" `
    -StdoutFileName "client-summary.stdout.json"

$monitorDeadline = (Get-Date).AddSeconds($monitorDurationSeconds + 10)
while (-not $monitorProcess.HasExited -and (Get-Date) -lt $monitorDeadline) {
    Start-Sleep -Milliseconds 500
    $monitorProcess.Refresh()
}
$monitorExceededDeadline = -not $monitorProcess.HasExited
if ($monitorExceededDeadline) {
    Stop-Process -Id $monitorProcess.Id
    $monitorProcess.WaitForExit()
}
$monitorProcess.WaitForExit()
$monitorProcess.Refresh()
$observedExitCode = $monitorProcess.ExitCode
[ordered]@{
    processId = $monitorProcess.Id
    hasExited = $monitorProcess.HasExited
    exitCodeAvailable = $null -ne $observedExitCode
    exitCode = $observedExitCode
    exceededDeadline = $monitorExceededDeadline
    observedAt = (Get-Date).ToUniversalTime().ToString("o")
} |
    ConvertTo-Json -Depth 3 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "monitor-launch-status.json"
    )

$monitorStatusPath = Join-Path $runDirectory "monitor-process-status.json"
$monitorSummaryPath = Join-Path $runDirectory "container-monitor-summary.json"
$monitorValidationErrors = [System.Collections.Generic.List[string]]::new()
$monitorStatus = $null
$monitorSummary = $null
if ($monitorExceededDeadline) {
    $monitorValidationErrors.Add("container monitor exceeded its deadline and was stopped")
}
if (-not (Test-Path -LiteralPath $monitorStatusPath)) {
    $monitorValidationErrors.Add("monitor-process-status.json is missing")
}
if (-not (Test-Path -LiteralPath $monitorSummaryPath)) {
    $monitorValidationErrors.Add("container-monitor-summary.json is missing")
}
if ($monitorValidationErrors.Count -eq 0) {
    try {
        $monitorStatus = Get-Content -LiteralPath $monitorStatusPath -Raw |
            ConvertFrom-Json
        $monitorSummary = Get-Content -LiteralPath $monitorSummaryPath -Raw |
            ConvertFrom-Json
    } catch {
        $monitorValidationErrors.Add("monitor completion JSON could not be read: $($_.Exception.Message)")
    }
}
if ($null -ne $monitorStatus -and -not $monitorStatus.success) {
    $monitorValidationErrors.Add("monitor process reported unsuccessful completion")
}
if ($null -ne $monitorSummary) {
    if ($monitorSummary.statsLines -le 0) {
        $monitorValidationErrors.Add("container stats samples are missing")
    }
    if ($monitorSummary.applicationSamples -le 0) {
        $monitorValidationErrors.Add("application metric samples are missing")
    }
    if ($monitorSummary.databaseSamples -le 0) {
        $monitorValidationErrors.Add("database metric samples are missing")
    }
    if ($monitorSummary.applicationFailures -gt 0) {
        $monitorValidationErrors.Add("application metric failures: $($monitorSummary.applicationFailures)")
    }
    if ($monitorSummary.databaseFailures -gt 0) {
        $monitorValidationErrors.Add("database metric failures: $($monitorSummary.databaseFailures)")
    }
}
foreach ($requiredArtifact in @(
    "application-metrics.jsonl",
    "database-metrics.jsonl",
    "client-progress.jsonl"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $runDirectory $requiredArtifact))) {
        $monitorValidationErrors.Add("monitor artifact is missing: $requiredArtifact")
    }
}
[ordered]@{
    valid = ($monitorValidationErrors.Count -eq 0)
    errors = @($monitorValidationErrors)
    statusPath = "monitor-process-status.json"
    summaryPath = "container-monitor-summary.json"
    applicationFailures = if ($null -eq $monitorSummary) { $null } else { $monitorSummary.applicationFailures }
    evaluatedAt = (Get-Date).ToUniversalTime().ToString("o")
} |
    ConvertTo-Json -Depth 4 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "monitor-validation.json"
    )

# A non-empty JFR file can still be actively written. Wait for the named
# recording to finish, validate its source bytes, then require an exact copy.
$jfrEarliestCompletion = $jfrStartedAt.AddSeconds($jfrDurationSeconds)
$jfrCompletionDeadline = $jfrEarliestCompletion.AddSeconds(10)
$jfrCompleted = $false
$jfrCheckText = ""
while ((Get-Date) -lt $jfrCompletionDeadline) {
    if ((Get-Date) -lt $jfrEarliestCompletion) {
        Start-Sleep -Milliseconds 500
        continue
    }
    $jfrCheckOutput = & docker exec $serverContainerId env -u JAVA_TOOL_OPTIONS `
        jcmd 1 JFR.check "name=$jfrName" 2>&1
    $jfrCheckText = (@($jfrCheckOutput) -join "`n")
    if ($jfrCheckText -notmatch "\(running\)") {
        $jfrCompleted = $true
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $jfrCompleted) { throw "JFR recording did not finish before its deadline" }

$jfrSummaryPath = Join-Path $runDirectory "jfr-summary.txt"
& docker exec $serverContainerId `
    env -u JAVA_TOOL_OPTIONS `
    jfr summary $jfrContainerFile |
    Set-Content -Encoding UTF8 -LiteralPath $jfrSummaryPath
if ($LASTEXITCODE -ne 0) { throw "JFR summary failed after recording completion" }

$jfrSourceSizeText = (@(& docker exec $serverContainerId sh -c "wc -c < '$jfrContainerFile'" 2>$null) -join "").Trim()
if ($jfrSourceSizeText -notmatch "^\d+$") { throw "JFR source size could not be read" }
[long]$jfrSourceBytes = $jfrSourceSizeText
if ($jfrSourceBytes -le 0) { throw "JFR source file is empty" }

$jfrRecordingPath = Join-Path $runDirectory "jvm-recording.jfr"
& docker cp "$($serverContainerId):$jfrContainerFile" $jfrRecordingPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $jfrRecordingPath)) {
    throw "JFR recording copy failed"
}
[long]$jfrCopiedBytes = (Get-Item -LiteralPath $jfrRecordingPath).Length
if ($jfrCopiedBytes -ne $jfrSourceBytes) { throw "JFR copy size does not match the completed source" }

$jfrValidation = [ordered]@{
    completed = $jfrCompleted
    checkOutput = $jfrCheckText
    sourceBytes = $jfrSourceBytes
    copiedBytes = $jfrCopiedBytes
    summaryFile = "jfr-summary.txt"
    valid = $true
}
$jfrValidation |
    ConvertTo-Json -Depth 4 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "jfr-validation.json"
    )

$jfrEvents = @(
    "jdk.JavaThreadStatistics",
    "jdk.ThreadPark",
    "jdk.JavaMonitorEnter",
    "jdk.SocketRead",
    "jdk.SocketWrite",
    "jdk.CPULoad",
    "jdk.GarbageCollection",
    "jdk.GCPhasePause",
    "jdk.ExecutionSample"
) -join ","
& docker exec $serverContainerId `
    env -u JAVA_TOOL_OPTIONS `
    jfr print `
    --json `
    --events $jfrEvents `
    $jfrContainerFile |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "jfr-key-events.json"
    )
if ($LASTEXITCODE -ne 0 -or
    (Get-Item -LiteralPath (
        Join-Path $runDirectory "jfr-key-events.json"
    )).Length -le 0) {
    throw "JFR key event export failed"
}

& $NodeCommand (Join-Path $PSScriptRoot "render-timeseries.js") `
    "--run-directory" $runDirectory
if ($LASTEXITCODE -ne 0 -or
    -not (Test-Path -LiteralPath (Join-Path $runDirectory "timeseries.csv")) -or
    -not (Test-Path -LiteralPath (Join-Path $runDirectory "timeseries.svg"))) {
    throw "Timeseries rendering failed"
}

$databaseAfter = Get-DatabaseState
$databaseAfter |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-after.tsv"
    )
$storageAfter = Invoke-RestMethod -Uri "$mockBaseUrl/__storage"
$storageAfter |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "storage-after.json"
    )
$mockRequests = Invoke-RestMethod -Uri "$mockBaseUrl/__requests"
$mockRequests |
    ConvertTo-Json -Depth 8 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "mock-requests.json"
    )

& docker compose `
    -p $ComposeProject `
    -f $composeFile `
    logs `
    --no-color `
    --timestamps `
    --since 10m `
    $ServerService `
    experiment-mock |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "server.log"
    )

$clientResult = Get-Content -LiteralPath (
    Join-Path $runDirectory "client-results.json"
) -Raw | ConvertFrom-Json
$verification = [ordered]@{
    runId = $RunId
    implementation = $Implementation
    statusCounts = $clientResult.summary.statusCounts
    scheduledRequests = $clientResult.summary.scheduledRequests
    completedRequests = $clientResult.summary.completedRequests
    maxInFlight = $clientResult.summary.maxInFlight
    latencyMs = $clientResult.summary.latencyMs
    throughputRequestsPerSecond =
        $clientResult.summary.throughputRequestsPerSecond
    errorRate = $clientResult.summary.errorRate
    loadGenerator = $clientResult.summary.loadGenerator
    monitor = [ordered]@{
        valid = ($monitorValidationErrors.Count -eq 0)
        errors = @($monitorValidationErrors)
        applicationFailures = if ($null -eq $monitorSummary) { $null } else { $monitorSummary.applicationFailures }
    }
    jfr = [ordered]@{
        recordingBytes = $jfrCopiedBytes
        sourceBytes = $jfrSourceBytes
        completed = $jfrCompleted
        validated = $jfrValidation.valid
        summaryFile = "jfr-summary.txt"
        keyEventsFile = "jfr-key-events.json"
    }
    databaseUnchanged = (
        ($databaseBefore -join "`n") -eq ($databaseAfter -join "`n")
    )
    storageCountAfter = @($storageAfter.objects).Count
    mockRequestCounts = $mockRequests.counts
}
$verification |
    ConvertTo-Json -Depth 8 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "verification-summary.json"
    )

if ($monitorValidationErrors.Count -gt 0) {
    throw "Container monitor completion artifacts are invalid: $($monitorValidationErrors -join '; ')"
}

$verification | ConvertTo-Json -Depth 8
