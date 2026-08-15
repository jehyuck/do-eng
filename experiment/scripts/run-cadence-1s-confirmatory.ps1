param(
    [switch]$DryRun,
    [switch]$Execute,
    [switch]$ReviewApproved,
    [string]$NodeCommand = "node"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$configPath = Join-Path $repositoryRoot "experiment\config\cadence-1s-confirmatory.json"
$baseCommit = "d7448a74a1e45f6bf5a02e4624a3052ca86ac99a"
$runScript = Join-Path $repositoryRoot "experiment\scripts\run-isolated-vu-success-smoke.ps1"
$loadScript = Join-Path $repositoryRoot "experiment\load\mission-load.js"
$composeFiles = @(
    (Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml"),
    (Join-Path $repositoryRoot "experiment\compose\experiment-1-37-runtime.override.yml")
)
$env:GIT_CONFIG_COUNT = "1"
$env:GIT_CONFIG_KEY_0 = "safe.directory"
$env:GIT_CONFIG_VALUE_0 = "*"

if ($DryRun -eq $Execute) {
    throw "Specify exactly one of -DryRun or -Execute"
}

function Invoke-Git {
    param([string[]]$Arguments)
    $output = & git -c "safe.directory=*" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($Arguments -join ' ')" }
    return @($output)
}

function Assert-Contract {
    param($Config)
    if ((Invoke-Git @("rev-parse", "HEAD")).Trim() -ne $baseCommit) { throw "CANONICAL_BASE mismatch" }
    . (Join-Path $repositoryRoot "experiment\scripts\comparison-source-gate.ps1")
    $sourceStatus = Get-ComparisonSourceStatus -RepositoryRoot $repositoryRoot
    if (-not $sourceStatus.clean) { throw "PRODUCTION_SOURCE_GATE: NO ($($sourceStatus.dirtyPaths -join '; '))" }
    $allowed = @("experiment/config/cadence-1s-confirmatory.json", "experiment/scripts/run-cadence-1s-confirmatory.ps1")
    $unexpectedStatus = @(Invoke-Git @("status", "--short", "--untracked-files=all") | Where-Object {
        $line = $_.Trim()
        -not ($allowed | Where-Object { $line -match [regex]::Escape($_) })
    })
    if ($unexpectedStatus.Count -ne 0) { throw "WORKTREE_CLEAN: NO ($($unexpectedStatus -join '; '))" }
    $fixturePath = Join-Path $repositoryRoot $Config.fixture.path
    if (-not (Test-Path -LiteralPath $fixturePath)) { throw "Fixture missing" }
    $fixture = Get-Item -LiteralPath $fixturePath
    if ($fixture.Length -ne [int64]$Config.fixture.bytes) { throw "Fixture byte mismatch" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fixture.FullName).Hash.ToLowerInvariant() -ne $Config.fixture.sha256) { throw "Fixture SHA mismatch" }
    foreach ($file in @($runScript, $loadScript) + $composeFiles) { if (-not (Test-Path -LiteralPath $file)) { throw "Missing input: $file" } }
    if ($Config.load.loadScenario -ne "single-success" -or $Config.load.stopUserOnTrue) { throw "Fixed-periodic contract mismatch" }
    $checks = @(
        @{ name = "activeUsers"; actual = $Config.load.activeUsers; expected = 160 },
        @{ name = "intervalMs"; actual = $Config.load.intervalMs; expected = 1000 },
        @{ name = "durationMs"; actual = $Config.load.durationMs; expected = 105000 },
        @{ name = "requestTimeoutMs"; actual = $Config.load.requestTimeoutMs; expected = 10000 },
        @{ name = "aiDelayMs"; actual = $Config.downstream.aiDelayMs; expected = 2000 },
        @{ name = "storageDelayMs"; actual = $Config.downstream.storageDelayMs; expected = 100 },
        @{ name = "appCpu"; actual = [string]$Config.application.cpu; expected = "2.0" },
        @{ name = "appMemory"; actual = $Config.application.memory; expected = "3g" },
        @{ name = "httpMaxConnections"; actual = $Config.http.maxConnections; expected = 400 },
        @{ name = "httpPendingMaxCount"; actual = $Config.http.pendingMaxCount; expected = 400 },
        @{ name = "dbPoolMaxSize"; actual = $Config.database.poolMaxSize; expected = 10 },
        @{ name = "mvcMaxThreads"; actual = $Config.mvc.maxThreads; expected = 400 },
        @{ name = "jvmXms"; actual = $Config.jvm.xms; expected = "512m" },
        @{ name = "jvmXmx"; actual = $Config.jvm.xmx; expected = "2048m" },
        @{ name = "fixtureBytes"; actual = $Config.fixture.bytes; expected = 265745 }
    )
    foreach ($check in $checks) {
        if ([string]$check.actual -ne [string]$check.expected) { throw "Frozen contract mismatch: $($check.name)" }
    }
    if ($Config.runOrder.Count -ne 6) { throw "Run count mismatch" }
    $expected = @("MVC1", "WEBFLUX1", "WEBFLUX2", "MVC2", "MVC3", "WEBFLUX3")
    if ((@($Config.runOrder | ForEach-Object logicalRun) -join ",") -ne ($expected -join ",")) { throw "Run order mismatch" }
    $source = Get-Content -Raw -LiteralPath $loadScript
    foreach ($pattern in @("setInterval(() => {", "void submitFrame(user)", "stopUserOnTrue", 'loadScenario === "reconnect-ramp"')) {
        if ($source -notmatch [regex]::Escape($pattern)) { throw "Lower-level semantic marker missing: $pattern" }
    }
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
Assert-Contract $config

if ($DryRun) {
    [ordered]@{
        canonicalBase = $baseCommit
        worktreeClean = $true
        productionSourceClean = $true
        runCount = 6
        runOrder = @($config.runOrder | ForEach-Object logicalRun)
        vu = $config.load.activeUsers
        intervalMs = $config.load.intervalMs
        aiDelayMs = $config.downstream.aiDelayMs
        storageDelayMs = $config.downstream.storageDelayMs
        mvcThreads = $config.mvc.maxThreads
        http = "400/400"
        dbPool = $config.database.poolMaxSize
        fixtureSha256 = $config.fixture.sha256
        loadScenario = $config.load.loadScenario
        stopUserOnTrue = $config.load.stopUserOnTrue
        fixedPeriodicSemantics = "single-success label with STOP_USER_ON_TRUE=false; each user uses setInterval after staggered phase"
        reconnectSemantics = "no reconnect branch in this contract; reconnect-ramp branch remains distinct in lower-level runner"
        validityGate = "expected opportunities, actual starts, scheduling fidelity, event-loop delay, generator CPU/RSS"
        performanceExecution = "DISABLED"
    } | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $ReviewApproved) { throw "PERFORMANCE_EXECUTION_REQUIRES_REVIEW_APPROVAL" }

$resultsRoot = Join-Path $repositoryRoot "experiment\results"
$composeArguments = @()
foreach ($file in $composeFiles) { $composeArguments += @("-f", $file) }
$implementations = @{
    MVC400 = [ordered]@{ service = "mvc"; port = 8002 }
    WebFlux = [ordered]@{ service = "flux-corrected"; port = 8001 }
}

function Invoke-ComposeCommand {
    param([string]$Project, [string[]]$Arguments, [string]$StdOutPath, [string]$StdErrPath)
    if ($StdOutPath) {
        & docker compose -p $Project @composeArguments @Arguments 1> $StdOutPath 2> $StdErrPath
    } else {
        & docker compose -p $Project @composeArguments @Arguments
    }
    return [int]$LASTEXITCODE
}

function Wait-Readiness {
    param([int]$Port)
    for ($attempt = 1; $attempt -le 180; $attempt++) {
        try {
            $canary = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/test" -TimeoutSec 2
            $metrics = Invoke-RestMethod -Uri "http://127.0.0.1:9100/__metrics" -TimeoutSec 2
            if ([int]$canary.StatusCode -eq 200 -and $metrics.aiInFlight -eq 0 -and $metrics.storageInFlight -eq 0) { return }
        } catch { }
        Start-Sleep -Seconds 1
    }
    throw "STARTUP_GATE failed for port $Port"
}

function Invoke-ConfirmatoryRun {
    param($LogicalRun, $Implementation)
    $spec = $implementations[$Implementation]
    $runId = "CADENCE-1S-$LogicalRun"
    $runDirectory = Join-Path $resultsRoot $runId
    if (Test-Path -LiteralPath $runDirectory) { throw "Existing result directory: $runDirectory" }
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    $project = "doeng-cadence-$($LogicalRun.ToLowerInvariant())"
    $envValues = [ordered]@{
        APP_CPU = "2.0"; APP_MEMORY = "3g"; HTTP_MAX_CONNECTIONS = "400"; HTTP_PENDING_MAX_COUNT = "400"
        HTTP_CONNECT_TIMEOUT_MS = "2000"; HTTP_RESPONSE_TIMEOUT_MS = "10000"; HTTP_PENDING_ACQUIRE_TIMEOUT_MS = "10000"
        DB_POOL_MAX_SIZE = "10"; MVC_MAX_THREADS = "400"; JAVA_XMS = "512m"; JAVA_XMX = "2048m"
        MOCK_AI_RESULT = "true"; MOCK_AI_DELAY_MS = "2000"; MOCK_AI_STATUS = "200"
        MOCK_STORAGE_DELAY_MS = "100"; MOCK_STORAGE_STATUS = "200"
    }
    $previous = @{}
    foreach ($key in $envValues.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process"); [Environment]::SetEnvironmentVariable($key, $envValues[$key], "Process") }
    $runtimeStarted = $false
    try {
        $buildCode = Invoke-ComposeCommand $project @("build", "experiment-mock", $spec.service) (Join-Path $runDirectory "compose-build.stdout.log") (Join-Path $runDirectory "compose-build.stderr.log")
        if ($buildCode -ne 0) { throw "Compose build failed: $buildCode" }
        $upCode = Invoke-ComposeCommand $project @("up", "-d", $spec.service) (Join-Path $runDirectory "compose-up.stdout.log") (Join-Path $runDirectory "compose-up.stderr.log")
        if ($upCode -ne 0) { throw "Compose up failed: $upCode" }
        $runtimeStarted = $true
        Wait-Readiness $spec.port
        $runnerArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runScript,
            "-RunId", $runId, "-Implementation", $Implementation, "-TargetUrl", "http://127.0.0.1:$($spec.port)/game/face",
            "-ServerService", $spec.service, "-ComposeProject", $project, "-ComposeFiles", ($composeFiles -join ","),
            "-ConfigPath", $configPath, "-FixturePath", "image\arc.jpg", "-NodeCommand", $NodeCommand,
            "-EnableObservability", "1", "-EnableContainerMonitor", "1", "-EnableJfr", "0", "-SkipApplicationSnapshot", "0", "-SkipMockMetrics", "0",
            "-DrainObservationSeconds", "15", "-EchoImage", "1", "-LoadScenario", "single-success", "-AccountingMode", "corrected",
            "-ArrivalMode", "staggered", "-InitialActiveUsers", "160", "-ActivationStepUsers", "1", "-ActivationIntervalMs", "3000", "-ReconnectDelayMs", "1000",
            "-OutcomeMode", "controlled-admission"
        )
        & powershell.exe @runnerArgs 1> (Join-Path $runDirectory "runner.stdout.log") 2> (Join-Path $runDirectory "runner.stderr.log")
        $clientExitCode = [int]$LASTEXITCODE
        $clientPath = Join-Path $resultsRoot "$runId\client-results.json"
        if (-not (Test-Path -LiteralPath $clientPath)) { throw "Client result missing; exit=$clientExitCode" }
        $summary = (Get-Content -Raw -LiteralPath $clientPath | ConvertFrom-Json).summary
        $validity = [ordered]@{
            runId = $runId; logicalRun = $LogicalRun; implementation = $Implementation; expectedRequestOpportunities = 16800
            actualRequestStarts = $summary.startedRequests; schedulingFidelity = [double]$summary.startedRequests / 16800
            loadGenerator = $summary.loadGenerator; clientProcessExitCode = $clientExitCode
            loadGeneratorValid = ($summary.startedRequests -eq 16800 -and $clientExitCode -eq 0)
        }
        $validity | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "load-generator-validity.json")
    } finally {
        if ($runtimeStarted) { Invoke-ComposeCommand $project @("down", "--remove-orphans") $null $null | Out-Null }
        foreach ($key in $envValues.Keys) {
            if ($null -eq $previous[$key]) { Remove-Item "Env:$key" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process") }
        }
    }
}

foreach ($run in $config.runOrder) { Invoke-ConfirmatoryRun $run.logicalRun $run.implementation }
