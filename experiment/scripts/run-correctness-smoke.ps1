param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$Implementation,
    [Parameter(Mandatory = $true)]
    [string]$TargetUrl,
    [Parameter(Mandatory = $true)]
    [string]$ServerService,
    [string]$ComposeProject = "doeng-smoke-20260728a",
    [string]$FixturePath = "image\arc.jpg",
    [long]$MemberId = 15,
    [long]$SceneId = 2,
    [string]$Answer = "happy",
    [ValidateSet(0, 1)]
    [int]$AiResult = 0,
    [int]$AiDelayMs = 0,
    [int]$AiStatus = 200,
    [int]$StorageDelayMs = 0,
    [int]$StorageStatus = 200,
    [int]$ActiveMissions = 1,
    [int]$IntervalMs = 3000,
    [int]$DurationMs = 3500,
    [int]$RequestTimeoutMs = 10000,
    [ValidateSet(0, 1)]
    [int]$StopUserOnTrue = 0,
    [ValidateSet(0, 1)]
    [int]$VerifyTruePath = 0,
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resultsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "experiment\results")
)
$runDirectory = Join-Path $resultsRoot $RunId
$composeFile = Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml"
$mockBaseUrl = "http://127.0.0.1:9100"
$aiResultBoolean = $AiResult -eq 1
$stopUserOnTrueBoolean = $StopUserOnTrue -eq 1
$verifyTruePathBoolean = $VerifyTruePath -eq 1

if ($verifyTruePathBoolean -and
    (-not $aiResultBoolean -or -not $stopUserOnTrueBoolean -or
        $ActiveMissions -ne 1)) {
    throw "VerifyTruePath requires AiResult=1, StopUserOnTrue=1, and ActiveMissions=1"
}

if (Test-Path -LiteralPath $runDirectory) {
    throw "Run result directory already exists: $runDirectory"
}

$resolvedFixture = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot $FixturePath)
)
if (-not (Test-Path -LiteralPath $resolvedFixture)) {
    throw "Fixture not found: $resolvedFixture"
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

$controlPayload = [ordered]@{
    result = $aiResultBoolean
    delayMs = $AiDelayMs
    status = $AiStatus
    storageDelayMs = $StorageDelayMs
    storageStatus = $StorageStatus
}

Invoke-RestMethod `
    -Method Post `
    -Uri "$mockBaseUrl/__reset" `
    -ContentType "application/json" `
    -Body "{}" | Out-Null
$controlResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "$mockBaseUrl/__control" `
    -ContentType "application/json" `
    -Body ($controlPayload | ConvertTo-Json -Compress)
$controlResponse |
    ConvertTo-Json -Depth 5 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "mock-control.json"
    )

$fixture = Get-Item -LiteralPath $resolvedFixture
$runConfig = [ordered]@{
    runId = $RunId
    implementation = $Implementation
    targetUrl = $TargetUrl
    serverService = $ServerService
    composeProject = $ComposeProject
    fixture = [ordered]@{
        path = $resolvedFixture
        bytes = $fixture.Length
        sha256 = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedFixture
        ).Hash.ToLower()
    }
    memberId = $MemberId
    sceneId = $SceneId
    answer = $Answer
    authorization = "Bearer experiment-member-***"
    ai = $controlPayload
    activeMissions = $ActiveMissions
    intervalMs = $IntervalMs
    durationMs = $DurationMs
    requestTimeoutMs = $RequestTimeoutMs
    stopUserOnTrue = $stopUserOnTrueBoolean
    verifyTruePath = $verifyTruePathBoolean
}
$runConfig |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "run-config.json"
    )

function Invoke-DatabaseSql {
    param([Parameter(Mandatory = $true)][string]$Sql)

    $output = & docker compose `
        -p $ComposeProject `
        -f $composeFile `
        exec -T mariadb `
        mariadb -N -B `
        -udoeng `
        -pdoeng-experiment-pass `
        doeng `
        -e $Sql
    if ($LASTEXITCODE -ne 0) {
        throw "Database observation failed"
    }
    return @($output)
}

function Get-DatabaseState {
    $summarySql = @"
SELECT COUNT(*) FROM member WHERE id=$MemberId;
SELECT COUNT(*) FROM scene WHERE id=$SceneId;
SELECT COUNT(*) FROM progress WHERE member_id=$MemberId AND scene_id=$SceneId;
SELECT COUNT(*) FROM picture p JOIN progress pr ON pr.id=p.progress_id WHERE pr.member_id=$MemberId AND pr.scene_id=$SceneId;
SELECT COUNT(*) FROM progress;
SELECT COUNT(*) FROM picture;
"@
    $summary = Invoke-DatabaseSql -Sql $summarySql
    if ($summary.Count -ne 6) {
        throw "Database summary returned an unexpected row count: $($summary.Count)"
    }

    $pictureSql = @"
SELECT p.id, pic.id, pic.image
FROM progress p
JOIN picture pic ON pic.progress_id=p.id
WHERE p.member_id=$MemberId AND p.scene_id=$SceneId
ORDER BY pic.id;
"@
    $pictureRows = Invoke-DatabaseSql -Sql $pictureSql
    $pictures = @($pictureRows | ForEach-Object {
        $fields = $_ -split "`t", 3
        if ($fields.Count -ne 3) {
            throw "Picture observation row could not be parsed: $_"
        }
        [ordered]@{
            progressId = [long]$fields[0]
            pictureId = [long]$fields[1]
            image = $fields[2]
        }
    })

    return [ordered]@{
        memberExists = [int]$summary[0]
        sceneExists = [int]$summary[1]
        progressCount = [int]$summary[2]
        pictureCount = [int]$summary[3]
        totalProgressCount = [int]$summary[4]
        totalPictureCount = [int]$summary[5]
        pictures = $pictures
        rawSummary = $summary
        rawPictures = $pictureRows
    }
}

$databaseBefore = Get-DatabaseState
$databaseBefore.rawSummary + $databaseBefore.rawPictures |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-before.tsv"
    )
$databaseBefore |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-before.json"
    )
if ($verifyTruePathBoolean -and
    ($databaseBefore.memberExists -ne 1 -or
        $databaseBefore.sceneExists -ne 1 -or
        $databaseBefore.progressCount -ne 0 -or
        $databaseBefore.pictureCount -ne 0)) {
    throw "VerifyTruePath requires an existing member and scene with no progress or picture rows"
}
$storageBefore = Invoke-RestMethod -Uri "$mockBaseUrl/__storage"
$storageBefore |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "storage-before.json"
    )

$env:TARGET_URL = $TargetUrl
$env:ACTIVE_MISSIONS = [string]$ActiveMissions
$env:INTERVAL_MS = [string]$IntervalMs
$env:DURATION_MS = [string]$DurationMs
$env:REQUEST_TIMEOUT_MS = [string]$RequestTimeoutMs
$env:SCENE_ID = [string]$SceneId
$env:ANSWER = $Answer
$env:AUTH_TOKEN = "Bearer experiment-member-$MemberId"
$env:FIXTURE_PATH = $resolvedFixture
$env:EXPERIMENT_RUN_ID = $RunId
$env:IMPLEMENTATION = $Implementation
$env:STOP_USER_ON_TRUE = $stopUserOnTrueBoolean.ToString().ToLower()
$env:RESULT_PATH = Join-Path $runDirectory "client-results.json"

$clientStdout = & $NodeCommand (
    Join-Path $repositoryRoot "experiment\load\mission-load.js"
)
if ($LASTEXITCODE -ne 0) {
    throw "Load driver failed"
}
$clientStdout |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "client-summary.stdout.json"
    )

$databaseAfter = Get-DatabaseState
$databaseAfter.rawSummary + $databaseAfter.rawPictures |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-after.tsv"
    )
$databaseAfter |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "db-after.json"
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
$mockMetrics = Invoke-RestMethod -Uri "$mockBaseUrl/__metrics"
$mockMetrics |
    ConvertTo-Json -Depth 8 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "mock-metrics-after.json"
    )

$containerIds = @(
    $ServerService,
    "mariadb",
    "experiment-mock"
) | ForEach-Object {
    & docker compose `
        -p $ComposeProject `
        -f $composeFile `
        ps -q $_
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($containerIds.Count -gt 0) {
    & docker stats `
        --no-stream `
        --format "{{json .}}" `
        @containerIds |
        Set-Content -Encoding UTF8 -LiteralPath (
            Join-Path $runDirectory "container-stats-after.jsonl"
        )
}

& docker compose `
    -p $ComposeProject `
    -f $composeFile `
    logs `
    --no-color `
    --timestamps `
    --since 5m `
    $ServerService `
    experiment-mock |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "server.log"
    )

$clientResult = Get-Content -LiteralPath (
    Join-Path $runDirectory "client-results.json"
) -Raw | ConvertFrom-Json
$requests = @($clientResult.requests)
$beforePictureIds = @($databaseBefore.pictures | ForEach-Object {
    [long]$_.pictureId
})
$newPictures = @($databaseAfter.pictures | Where-Object {
    $beforePictureIds -notcontains [long]$_.pictureId
})
$storageObjects = @($storageAfter.objects)
$fixtureSha256 = $runConfig.fixture.sha256

function Get-MockRequestCount {
    param(
        [Parameter(Mandatory = $true)]$Counts,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $property = $Counts.PSObject.Properties[$Key]
    if ($null -eq $property) {
        return 0
    }
    return [int]$property.Value
}

$truePathAssertions = $null
$truePathValid = $null
if ($verifyTruePathBoolean) {
    $newPicture = if ($newPictures.Count -eq 1) {
        $newPictures[0]
    } else {
        $null
    }
    $storedObject = @(
        if ($null -ne $newPicture) {
            $storageObjects | Where-Object {
                $_.key -eq $newPicture.image
            } | Select-Object -First 1
        }
    )
    $matchingStoredObject = if ($storedObject.Count -eq 1) {
        $storedObject[0]
    } else {
        $null
    }
    $trueResponseCount = @($requests | Where-Object {
        $_.status -eq 200 -and $_.body.Trim().ToLower() -eq "true"
    }).Count
    $truePathAssertions = [ordered]@{
        oneClientRequest = $requests.Count -eq 1
        oneTrueResponse = $trueResponseCount -eq 1
        oneAiRequest = (Get-MockRequestCount -Counts $mockRequests.counts -Key "POST /analyze/face") -eq 1
        oneStoragePut = (Get-MockRequestCount -Counts $mockRequests.counts -Key "PUT /storage/object") -eq 1
        storageCompleted = $mockMetrics.storageCompleted -eq 1
        progressCreated = ($databaseAfter.progressCount - $databaseBefore.progressCount) -eq 1
        pictureCreated = ($databaseAfter.pictureCount - $databaseBefore.pictureCount) -eq 1
        oneStoredObject = ($storageObjects.Count - $storageBefore.objects.Count) -eq 1
        pictureKeyMatchesStoredObject = $null -ne $matchingStoredObject
        storedBytesMatchFixture = $null -ne $matchingStoredObject -and [long]$matchingStoredObject.bytes -eq [long]$runConfig.fixture.bytes
        storedSha256MatchesFixture = $null -ne $matchingStoredObject -and $matchingStoredObject.sha256 -eq $fixtureSha256
    }
    $truePathValid = -not (@($truePathAssertions.Values) -contains $false)
}

$verification = [ordered]@{
    runId = $RunId
    requestCount = $requests.Count
    statusCounts = $clientResult.summary.statusCounts
    responseBodies = @($requests | ForEach-Object { $_.body })
    maxInFlight = $clientResult.summary.maxInFlight
    requestBodyBytes = $clientResult.summary.requestBodyBytes
    databaseChanged = (
        ($databaseBefore.rawSummary -join "`n") -ne
        ($databaseAfter.rawSummary -join "`n")
    )
    progressCountBefore = $databaseBefore.progressCount
    progressCountAfter = $databaseAfter.progressCount
    pictureCountBefore = $databaseBefore.pictureCount
    pictureCountAfter = $databaseAfter.pictureCount
    newPictures = $newPictures
    storageCountBefore = @($storageBefore.objects).Count
    storageCountAfter = @($storageAfter.objects).Count
    mockRequestCounts = $mockRequests.counts
    mockMetrics = $mockMetrics
    truePathVerificationEnabled = $verifyTruePathBoolean
    truePathAssertions = $truePathAssertions
    truePathValid = $truePathValid
}
$verification |
    ConvertTo-Json -Depth 6 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $runDirectory "verification-summary.json"
    )

$verification | ConvertTo-Json -Depth 6
if ($verifyTruePathBoolean -and -not $truePathValid) {
    throw "True-path verification failed; see verification-summary.json"
}
