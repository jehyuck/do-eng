param(
    [ValidateSet("BASELINE", "REMEDIATION")]
    [string]$Condition = "BASELINE",
    [string]$ImageTag = "doeng-flux-exp119-fresh-first-20260803:latest",
    [switch]$Finalize
)

# Adapted from the Experiment 1-13 Compose lifecycle and user-fixture
# harness.  This script is intentionally PRE-FLIGHT ONLY: it never invokes
# k6, a warm-up request, or a core performance run.

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$preflightRoot = Join-Path $repositoryRoot "backend\experiments\results\experiment-1-19\preflight"
$sourceCommit = "270349fa7937eb4486087d34184461ae6aaab10a"
$frozenMockImage = "sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1"
$mockTag = "doeng-exp119-mock-frozen-20260803:latest"
$composeProject = "doeng-exp119-preflight"
$mockBaseUrl = "http://127.0.0.1:9100"
$managementUrl = "http://127.0.0.1:9001"
$applicationUrl = "http://127.0.0.1:8001"

$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-12-connection-attribution.yaml",
    "backend\docker-compose.experiment-1-19-fresh-first-lifecycle.yaml"
) | ForEach-Object { Join-Path $repositoryRoot $_ }
$composeArguments = @()
foreach ($composeFile in $composeFiles) {
    if (-not (Test-Path -LiteralPath $composeFile)) { throw "Compose file not found: $composeFile" }
    $composeArguments += @("-f", $composeFile)
}

function Write-JsonFile {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-NodeCommand {
    $nodeOnPath = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeOnPath) { return $nodeOnPath.Source }
    $bundledNode = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
    if (-not (Test-Path -LiteralPath $bundledNode)) { throw "Node executable not found" }
    return $bundledNode
}

function Mask-RenderedCompose {
    param([Parameter(Mandatory = $true)][string]$Content)
    $masked = $Content -replace '(?i)(accessKey\\?"?\s*[:=]\s*\\?")[^\\"]+', '$1REDACTED'
    $masked = $masked -replace '(?i)(secretKey\\?"?\s*[:=]\s*\\?")[^\\"]+', '$1REDACTED'
    return $masked
}

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$ComposeCommand)
    # Docker Compose emits normal progress on stderr. Treat process exit code,
    # rather than that stream, as the command result.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & docker compose -p $composeProject @composeArguments @ComposeCommand 2>&1
        $composeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($composeExitCode -ne 0) { throw "docker compose failed: $($output -join [Environment]::NewLine)" }
    return @($output)
}

function Wait-HttpOk {
    param([Parameter(Mandatory = $true)][string]$Uri, [int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) { return }
        } catch { $lastError = $_.Exception.Message }
        Start-Sleep -Seconds 2
    }
    throw "Health check did not become ready: $Uri; last error: $lastError"
}

function Wait-TcpOpen {
    param([Parameter(Mandatory = $true)][string]$HostName, [Parameter(Mandatory = $true)][int]$Port, [int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connect = $client.BeginConnect($HostName, $Port, $null, $null)
            if ($connect.AsyncWaitHandle.WaitOne(3000) -and $client.Connected) { return }
        } catch { } finally { $client.Dispose() }
        Start-Sleep -Seconds 2
    }
    throw "TCP port did not become reachable: ${HostName}:$Port"
}

function Get-ContainerEnvironment {
    param([Parameter(Mandatory = $true)][string]$Service)
    $containerId = (Invoke-Compose -ComposeCommand @("ps", "-q", $Service) | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($containerId)) { throw "Container not found: $Service" }
    $environmentLines = & docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $containerId
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect environment for $Service" }
    $environment = @{}
    foreach ($line in $environmentLines) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { $environment[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return [ordered]@{ containerId = $containerId; environment = $environment }
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory = $true)][string]$Sql)
    $output = Invoke-Compose -ComposeCommand @("exec", "-T", "mariadb", "mariadb", "-N", "-B", "-udoeng", "-pdoeng-experiment-pass", "doeng", "-e", $Sql)
    return @($output)
}

function Ensure-ImageFromSourceCommit {
    param([Parameter(Mandatory = $true)][string]$DockerfileSha)
    # An absent tag is expected before the one frozen-source build.  Catch it
    # explicitly so native stderr does not become a preflight failure.
    $imageLookupOutput = @()
    $imageLookupExit = 1
    try {
        $imageLookupOutput = @(& docker image inspect --format '{{.Id}}' $ImageTag 2>$null)
        $imageLookupExit = $LASTEXITCODE
    } catch {
        $imageLookupOutput = @()
        $imageLookupExit = 1
    }
    $imageId = [string]::Join("`n", [string[]]$imageLookupOutput).Trim()
    if ($imageLookupExit -eq 0 -and -not [string]::IsNullOrWhiteSpace($imageId)) {
        $imageMetadata = ((& docker image inspect $ImageTag) -join "`n" | ConvertFrom-Json)[0]
        $existingSource = [string]$imageMetadata.Config.Labels.'doeng.experiment.source-commit'
        $existingDockerfile = [string]$imageMetadata.Config.Labels.'doeng.experiment.dockerfile-sha256'
        if ($existingSource -ne $sourceCommit -or $existingDockerfile -ne $DockerfileSha) {
            throw "Existing Experiment 1-19 image provenance does not match the frozen source commit/Dockerfile"
        }
        return [ordered]@{ imageId = $imageId; builtThisPreflight = $false }
    }

    # Build context is a Git object, not the dirty worktree. cmd.exe keeps the
    # archive stream byte-exact while Docker reads it as a tar build context.
    $command = "git archive --format=tar $sourceCommit`:backend/doEngGameFlux | docker build --label doeng.experiment.source-commit=$sourceCommit --label doeng.experiment.dockerfile-sha256=$DockerfileSha -t $ImageTag -f Dockerfile.experiment -"
    & cmd.exe /d /c $command
    if ($LASTEXITCODE -ne 0) { throw "Git-object application image build failed" }
    $builtImageOutput = @(& docker image inspect --format '{{.Id}}' $ImageTag)
    $imageId = [string]::Join("`n", [string[]]$builtImageOutput).Trim()
    if ([string]::IsNullOrWhiteSpace($imageId)) { throw "Built Experiment 1-19 image could not be inspected" }
    return [ordered]@{ imageId = $imageId; builtThisPreflight = $true }
}

function Ensure-MockImage {
    $sourceId = [string]::Join("`n", [string[]]@(& docker image inspect --format '{{.Id}}' $frozenMockImage 2>$null)).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceId) -or $sourceId -ne $frozenMockImage) { throw "Frozen mock digest unavailable or mismatched" }
    & docker tag $frozenMockImage $mockTag
    if ($LASTEXITCODE -ne 0) { throw "Frozen mock stable tag creation failed" }
    $mockId = [string]::Join("`n", [string[]]@(& docker image inspect --format '{{.Id}}' $mockTag 2>$null)).Trim()
    if ($LASTEXITCODE -ne 0 -or $mockId -ne $frozenMockImage) { throw "Frozen mock stable tag verification failed" }
    return $mockId
}

function Invoke-Finalize {
    $baselinePath = Join-Path $preflightRoot "baseline-rendered-compose.raw.json"
    $remediationPath = Join-Path $preflightRoot "remediation-rendered-compose.raw.json"
    foreach ($required in @($baselinePath, $remediationPath, (Join-Path $preflightRoot "baseline-runtime-config.json"), (Join-Path $preflightRoot "remediation-runtime-config.json"))) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Cannot finalize: missing preflight artifact $required" }
    }
    $node = Get-NodeCommand
    & $node (Join-Path $PSScriptRoot "verify-experiment-1-19-controlled-diff.js") $baselinePath $remediationPath (Join-Path $preflightRoot "baseline-runtime-config.json") (Join-Path $preflightRoot "remediation-runtime-config.json") (Join-Path $preflightRoot "runtime-config-diff.json") (Join-Path $preflightRoot "controlled-compose-diff.txt")
    if ($LASTEXITCODE -ne 0) { throw "Controlled Compose diff validation failed" }
    & $node (Join-Path $PSScriptRoot "aggregate-experiment-1-19.js") (Join-Path $preflightRoot "aggregator-schema.json")
    if ($LASTEXITCODE -ne 0) { throw "Aggregator schema generation failed" }

    $baseline = Get-Content -Raw -LiteralPath (Join-Path $preflightRoot "baseline-runtime-config.json") | ConvertFrom-Json
    $remediation = Get-Content -Raw -LiteralPath (Join-Path $preflightRoot "remediation-runtime-config.json") | ConvertFrom-Json
    $sameImage = $baseline.provenance.appImageId -eq $remediation.provenance.appImageId
    $sameMock = $baseline.provenance.mockImageId -eq $remediation.provenance.mockImageId
    $controlled = Get-Content -Raw -LiteralPath (Join-Path $preflightRoot "runtime-config-diff.json") | ConvertFrom-Json
    $provenance = [ordered]@{
        sourceCommit = $baseline.provenance.sourceCommit
        worktreeDirtyAtImageBuild = $baseline.provenance.worktreeDirtyAtBuild
        dockerfileGitObjectSha256 = $baseline.provenance.dockerfileGitObjectSha256
        appImage = [ordered]@{ tag = $baseline.provenance.appImageTag; id = $baseline.provenance.appImageId; repoDigests = $baseline.provenance.appImageRepoDigests; localDigest = $baseline.provenance.appImageLocalDigest }
        mockImageId = $baseline.provenance.mockImageId
        baselineRunnerSha256 = $baseline.provenance.runnerSha256
        remediationRunnerSha256 = $remediation.provenance.runnerSha256
        baselineRenderedComposeSha256 = $baseline.provenance.renderedComposeSha256
        remediationRenderedComposeSha256 = $remediation.provenance.renderedComposeSha256
        k6ScriptSha256 = $baseline.provenance.k6ScriptSha256
        sameImageAcrossArms = $sameImage
        sameMockAcrossArms = $sameMock
    }
    Write-JsonFile -Value $provenance -Path (Join-Path $preflightRoot "provenance.json")
    $collectorReadiness = [ordered]@{
        executionStatus = "NOT_RUN"
        poolCollectorScript = "collect-diagnostic-pool.ps1"
        poolEndpointSnapshot = "GET /actuator/doengdiagnosticpool succeeded during each preflight"
        containerMonitor = "docker executable available"
        databaseMonitor = "docker compose exec mariadb succeeded"
        nodeRuntime = Get-NodeCommand
        continuousApplicationSnapshot = "OFF during the future core contract"
        continuousMockPolling = "OFF during the future core contract"
    }
    Write-JsonFile -Value $collectorReadiness -Path (Join-Path $preflightRoot "collector-readiness.json")
    $validity = [ordered]@{
        experiment = "Experiment 1-19"
        executionStatus = "NOT_RUN"
        baselinePreflight = "READY"
        remediationPreflight = "READY"
        sameApplicationImage = $sameImage
        sameMockImage = $sameMock
        policyOnlyRenderedComposeDiff = $controlled.controlledDiffValid
        readyForSixCoreRuns = ($sameImage -and $sameMock -and $controlled.controlledDiffValid)
        decisionState = "NOT_RUN"
    }
    Write-JsonFile -Value $validity -Path (Join-Path $preflightRoot "validity.json")
    $summary = [ordered]@{
        experiment = "Experiment 1-19"
        phase = "A/B harness provenance dry-run"
        coreRunsExecuted = 0
        baseline = $baseline.preflight
        remediation = $remediation.preflight
        readiness = if ($validity.readyForSixCoreRuns) { "READY_FOR_SIX_CORE_RUNS" } else { "HARNESS_INVALID" }
        decisionState = "NOT_RUN"
    }
    Write-JsonFile -Value $summary -Path (Join-Path $preflightRoot "preflight-summary.json")
    if (-not $validity.readyForSixCoreRuns) { throw "HARNESS_INVALID" }
    Write-Output "READY_FOR_SIX_CORE_RUNS"
}

New-Item -ItemType Directory -Force -Path $preflightRoot | Out-Null
if ($Finalize) { Invoke-Finalize; exit 0 }

$policy = if ($Condition -eq "BASELINE") {
    [ordered]@{ leasingStrategy = "FIFO"; maxIdleTimeMs = "0"; evictionIntervalMs = "0" }
} else {
    [ordered]@{ leasingStrategy = "LIFO"; maxIdleTimeMs = "3000"; evictionIntervalMs = "1000" }
}

$env:DOENG_EXP119_APP_IMAGE = $ImageTag
$env:DOENG_EXP119_MOCK_IMAGE = $mockTag
$env:DOENG_EXTERNAL_LEASING_STRATEGY = $policy.leasingStrategy
$env:DOENG_EXTERNAL_MAX_IDLE_TIME_MS = $policy.maxIdleTimeMs
$env:DOENG_EXTERNAL_EVICTION_INTERVAL_MS = $policy.evictionIntervalMs
$env:EXP112_CAPTURE_ROOT = (Join-Path $preflightRoot "collector-probe")
New-Item -ItemType Directory -Force -Path $env:EXP112_CAPTURE_ROOT | Out-Null

$dockerfileContent = & git show "$sourceCommit`:backend/doEngGameFlux/Dockerfile.experiment"
if ($LASTEXITCODE -ne 0) { throw "Frozen Dockerfile Git object could not be read" }
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $dockerfileHashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes(($dockerfileContent -join "`n") + "`n"))
    $dockerfileSha = ([BitConverter]::ToString($dockerfileHashBytes) -replace "-", "").ToLower()
} finally {
    $sha256.Dispose()
}
$worktreeDirty = -not [string]::IsNullOrWhiteSpace((& git status --porcelain))
$image = Ensure-ImageFromSourceCommit -DockerfileSha $dockerfileSha
$expectedMockImageId = Ensure-MockImage

$completed = $false
try {
    $renderedRawPath = Join-Path $preflightRoot ("{0}-rendered-compose.raw.json" -f $Condition.ToLower())
    $rendered = Invoke-Compose -ComposeCommand @("config", "--format", "json")
    $rendered -join "`n" | Set-Content -LiteralPath $renderedRawPath -Encoding UTF8
    $renderedYaml = Invoke-Compose -ComposeCommand @("config")
    (Mask-RenderedCompose -Content ($renderedYaml -join "`n")) | Set-Content -LiteralPath (Join-Path $preflightRoot ("{0}-rendered-compose.yaml" -f $Condition.ToLower())) -Encoding UTF8
    $renderedJson = Get-Content -Raw -LiteralPath $renderedRawPath | ConvertFrom-Json
    if ($null -eq $renderedJson.services.'flux-corrected') { throw "Rendered compose lacks flux-corrected" }

    Invoke-Compose -ComposeCommand @("up", "-d", "--force-recreate", "--no-build", "mariadb", "experiment-mock", "flux-corrected") | Out-Null
    Wait-HttpOk -Uri "$managementUrl/actuator/health"
    Wait-HttpOk -Uri "$mockBaseUrl/health"
    Wait-TcpOpen -HostName "127.0.0.1" -Port 8001

    $beforeReset = Invoke-RestMethod -Uri "$mockBaseUrl/__metrics" -TimeoutSec 5
    if ($beforeReset.aiInFlight -ne 0 -or $beforeReset.storageInFlight -ne 0) { throw "Pre-run mock is not idle" }
    Invoke-RestMethod -Method Post -Uri "$mockBaseUrl/__reset" -ContentType "application/json" -Body "{}" -TimeoutSec 5 | Out-Null
    $mockControl = Invoke-RestMethod -Method Post -Uri "$mockBaseUrl/__control" -ContentType "application/json" -Body (@{ result = $true; delayMs = 2000; status = 200; storageDelayMs = 100; storageStatus = 200 } | ConvertTo-Json -Compress) -TimeoutSec 5
    $afterReset = Invoke-RestMethod -Uri "$mockBaseUrl/__metrics" -TimeoutSec 5
    if ($afterReset.aiInFlight -ne 0 -or $afterReset.storageInFlight -ne 0) { throw "Mock reset did not leave zero in-flight work" }

    # Experiment data reset is deliberately scoped to this experiment's
    # completion rows. User/scene fixtures are managed by the reused harness.
    Invoke-DatabaseSql -Sql "CREATE TABLE IF NOT EXISTS mission_completion (member_id BIGINT NOT NULL, scene_id BIGINT NOT NULL, mission_run_id VARCHAR(191) NOT NULL, object_key VARCHAR(255) NOT NULL, completed_at DATETIME(6) NOT NULL, PRIMARY KEY (member_id, scene_id, mission_run_id), UNIQUE KEY uk_mission_completion_object_key (object_key)) ENGINE=InnoDB; DELETE FROM mission_completion WHERE mission_run_id LIKE 'EXP119-%';" | Out-Null
    $completionRows = Invoke-DatabaseSql -Sql "SELECT COUNT(*) FROM mission_completion WHERE mission_run_id LIKE 'EXP119-%';"
    $completionCount = if ($completionRows.Count -eq 1) { [int]([string]$completionRows[0]).Trim() } else { -1 }
    if ($completionCount -ne 0) { throw "Scoped Experiment 1-19 DB reset verification failed; rows=[$($completionRows -join ',')] count=$($completionRows.Count)" }

    $fixturePath = Join-Path $repositoryRoot "image\arc.jpg"
    if (-not (Test-Path -LiteralPath $fixturePath)) { throw "Fixture not found: $fixturePath" }
    $fixture = Get-Item -LiteralPath $fixturePath
    $authMetadataPath = Join-Path $preflightRoot ("{0}-prepared-users.json" -f $Condition.ToLower())
    $privateTokenPath = Join-Path $repositoryRoot (".experiment-work\EXP119-{0}-PREFLIGHT-auth-tokens.json" -f $Condition)
    $preflightMemberPrefix = "experiment-EXP119-$Condition-PREFLIGHT-%"
    Invoke-DatabaseSql -Sql "DELETE FROM member WHERE member_id LIKE '$preflightMemberPrefix';" | Out-Null
    if (Test-Path -LiteralPath $authMetadataPath) { Remove-Item -LiteralPath $authMetadataPath -Force }
    if (Test-Path -LiteralPath $privateTokenPath) { Remove-Item -LiteralPath $privateTokenPath -Force }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "provision-experiment-users.ps1") -RunId "EXP119-$Condition-PREFLIGHT" -ComposeProject $composeProject -UserCount 200 -MetadataPath $authMetadataPath -TokenPath $privateTokenPath -ComposeFiles ($composeFiles -join ",") -MockBaseUrl $mockBaseUrl | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture/auth preflight failed" }
    $authMetadata = Get-Content -Raw -LiteralPath $authMetadataPath | ConvertFrom-Json
    if ($authMetadata.userCount -ne 200 -or -not $authMetadata.auth.strictAuth -or $authMetadata.auth.issuedTokens -ne 200) { throw "Fixture/auth preflight did not establish the VU200 token contract" }

    $appContainer = Get-ContainerEnvironment -Service "flux-corrected"
    $mockContainer = Get-ContainerEnvironment -Service "experiment-mock"
    $appImageId = (& docker inspect --format '{{.Image}}' $appContainer.containerId).Trim()
    $mockImageId = (& docker inspect --format '{{.Image}}' $mockContainer.containerId).Trim()
    if ($mockImageId -ne $expectedMockImageId) { throw "Running mock image does not match the preflight mock image" }
    $appImageMetadata = ((& docker image inspect $ImageTag) -join "`n" | ConvertFrom-Json)[0]
    $appImageRepoDigests = @($appImageMetadata.RepoDigests)
    $poolSnapshot = Invoke-RestMethod -Uri "$managementUrl/actuator/doengdiagnosticpool" -TimeoutSec 5
    $collectorPath = Join-Path $PSScriptRoot "collect-diagnostic-pool.ps1"
    $collectorReady = (Test-Path -LiteralPath $collectorPath) -and $null -ne (Get-Command docker -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace((Get-NodeCommand))
    if (-not $collectorReady) { throw "Required diagnostic collectors are not executable" }

    $runtimeConfig = [ordered]@{
        condition = $Condition
        executionStatus = "NOT_RUN"
        policy = $policy
        runtimePropertyProof = [ordered]@{
            source = "docker inspect environment plus Spring @ConfigurationProperties unit test"
            containerEnvironment = [ordered]@{
                DOENG_EXTERNAL_LEASING_STRATEGY = $appContainer.environment["DOENG_EXTERNAL_LEASING_STRATEGY"]
                DOENG_EXTERNAL_MAX_IDLE_TIME_MS = $appContainer.environment["DOENG_EXTERNAL_MAX_IDLE_TIME_MS"]
                DOENG_EXTERNAL_EVICTION_INTERVAL_MS = $appContainer.environment["DOENG_EXTERNAL_EVICTION_INTERVAL_MS"]
                DOENG_EXTERNAL_POOL_MODE = $appContainer.environment["DOENG_EXTERNAL_POOL_MODE"]
            DOENG_SHARED_POOL_MAX_CONNECTIONS = $appContainer.environment["DOENG_SHARED_POOL_MAX_CONNECTIONS"]
            DOENG_SHARED_POOL_PENDING_MAX_COUNT = $appContainer.environment["DOENG_SHARED_POOL_PENDING_MAX_COUNT"]
            DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS = $appContainer.environment["DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS"]
            DOENG_HTTP_CONNECT_TIMEOUT_MS = $appContainer.environment["DOENG_HTTP_CONNECT_TIMEOUT_MS"]
            DOENG_HTTP_RESPONSE_TIMEOUT_MS = $appContainer.environment["DOENG_HTTP_RESPONSE_TIMEOUT_MS"]
            DOENG_AI_ADMISSION_MAX_CONCURRENT = $appContainer.environment["DOENG_AI_ADMISSION_MAX_CONCURRENT"]
            }
            actuatorPoolMode = $poolSnapshot.poolMode
            limitation = "The existing pool endpoint exposes pool mode and pool gauges, not lifecycle property fields; direct runtime proof is the inspected container environment, with binding verified by the Java 11 property tests."
        }
        provenance = [ordered]@{
            sourceCommit = $sourceCommit
            worktreeDirtyAtBuild = $worktreeDirty
            dockerfileGitObjectSha256 = $dockerfileSha
            appImageTag = $ImageTag
            appImageId = $appImageId
            appImageRepoDigests = $appImageRepoDigests
            appImageLocalDigest = $appImageId
            mockImageTag = $mockTag
            mockImageId = $mockImageId
            mockImageBindingMode = "EXPLICIT_FROZEN_TAG"
            runnerSha256 = Get-Sha256 -Path $PSCommandPath
            k6ScriptSha256 = Get-Sha256 -Path (Join-Path $repositoryRoot "experiment\load\mission-load.js")
            composeSources = @($composeFiles | ForEach-Object { [ordered]@{ path = $_.Substring($repositoryRoot.Length + 1); sha256 = Get-Sha256 -Path $_ } })
            renderedComposeSha256 = Get-Sha256 -Path $renderedRawPath
        }
        preflight = [ordered]@{
            freshJvm = $true
            managementHealth = "UP"
            applicationHealth = "UP"
            mockHealth = "UP"
            preRunMockIdle = $true
            mockReset = $true
            dbScopedReset = $true
            fixture = [ordered]@{ path = "image/arc.jpg"; bytes = $fixture.Length; sha256 = Get-Sha256 -Path $fixturePath }
            authContract = [ordered]@{ vu = 200; strictAuth = $authMetadata.auth.strictAuth; issuedTokens = $authMetadata.auth.issuedTokens; rawTokensPersisted = $false }
            collectorsReady = $collectorReady
            coreLoadCommandPreparedButNotExecuted = "k6 run experiment/load/mission-load.js (VU=200, duration=105s, frame/reconnect=1s, timeout=10s)"
            coreRunsExecuted = 0
        }
    }
    $runtimeConfigPath = Join-Path $preflightRoot ("{0}-runtime-config.json" -f $Condition.ToLower())
    Write-JsonFile -Value $runtimeConfig -Path $runtimeConfigPath
    Remove-Item -LiteralPath $privateTokenPath -Force -ErrorAction SilentlyContinue
    $completed = $true
    Write-Output "$Condition PRE-FLIGHT READY; core load intentionally not executed"
} finally {
    try { Invoke-Compose -ComposeCommand @("down", "--remove-orphans") | Out-Null } catch { Write-Warning "Compose cleanup failed: $($_.Exception.Message)" }
}
