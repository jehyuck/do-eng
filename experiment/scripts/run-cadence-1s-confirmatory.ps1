param(
    [switch]$DryRun,
    [switch]$Execute,
    [switch]$ReviewApproved,
    [switch]$NativeIoSelfTest,
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

if (-not $NativeIoSelfTest -and $DryRun -eq $Execute) {
    throw "Specify exactly one of -DryRun or -Execute"
}

function Invoke-Git {
    param([string[]]$Arguments)
    $output = & git -c "safe.directory=*" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($Arguments -join ' ')" }
    return @($output)
}

function Get-CurrentHead {
    return ((Invoke-Git @("rev-parse", "HEAD")) -join "").Trim()
}

function Get-ExpectedRequestOpportunities {
    param(
        [int]$ActiveMissions,
        [int]$IntervalMs,
        [int]$DurationMs
    )
    $total = [int64]0
    for ($index = 0; $index -lt $ActiveMissions; $index++) {
        $phase = [math]::Floor(($index * $IntervalMs) / $ActiveMissions)
        if ($phase -lt $DurationMs) {
            $total += 1 + [math]::Floor(($DurationMs - 1 - $phase) / $IntervalMs)
        }
    }
    return $total
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)]
        [string]$StdOutPath,
        [Parameter(Mandatory = $true)]
        [string]$StdErrPath
    )
    $parentDirectories = @((Split-Path -Parent $StdOutPath), (Split-Path -Parent $StdErrPath)) | Where-Object { $_ }
    foreach ($directory in $parentDirectories | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    }
    $process = Start-Process -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $StdOutPath `
        -RedirectStandardError $StdErrPath
    return [int]$process.ExitCode
}

function Test-NativeIoHelper {
    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) "doeng-cadence-native-io-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
    try {
        $stdoutA = Join-Path $testDirectory "a.stdout.log"
        $stderrA = Join-Path $testDirectory "a.stderr.log"
        $exitA = Invoke-NativeProcess -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-Command", "[Console]::Error.WriteLine('synthetic stderr'); exit 0"
        ) -StdOutPath $stdoutA -StdErrPath $stderrA
        if ($exitA -ne 0 -or [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $stderrA))) {
            throw "Native stderr + exit 0 regression failed"
        }

        $stdoutB = Join-Path $testDirectory "b.stdout.log"
        $stderrB = Join-Path $testDirectory "b.stderr.log"
        $exitB = Invoke-NativeProcess -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-Command", "[Console]::Error.WriteLine('synthetic failure'); exit 7"
        ) -StdOutPath $stdoutB -StdErrPath $stderrB
        if ($exitB -ne 7 -or [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath $stderrB))) {
            throw "Native stderr + non-zero exit regression failed"
        }
    } finally {
        if (Test-Path -LiteralPath $testDirectory) { Remove-Item -LiteralPath $testDirectory -Recurse -Force }
    }
    return $true
}

function Test-ActiveMissionsPropagation {
    param([string]$NodeExecutable)
    $resolvedNode = $NodeExecutable
    if (-not (Test-Path -LiteralPath $resolvedNode)) {
        $command = Get-Command $NodeExecutable -ErrorAction SilentlyContinue
        if ($null -eq $command) { throw "Node executable not found for propagation test: $NodeExecutable" }
        $resolvedNode = $command.Source
    }
    $previous = [Environment]::GetEnvironmentVariable("ACTIVE_MISSIONS", "Process")
    try {
        $env:ACTIVE_MISSIONS = "160"
        $observed = (& $resolvedNode -e "process.stdout.write(process.env.ACTIVE_MISSIONS || '')").Trim()
        if ($LASTEXITCODE -ne 0 -or $observed -ne "160") { throw "ACTIVE_MISSIONS propagation failed: '$observed'" }
    } finally {
        if ($null -eq $previous) { Remove-Item Env:ACTIVE_MISSIONS -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable("ACTIVE_MISSIONS", $previous, "Process") }
    }
    return $true
}

function Assert-Contract {
    param($Config)
    $currentHead = Get-CurrentHead
    $ancestorCheck = & git -c "safe.directory=*" merge-base --is-ancestor $baseCommit $currentHead
    if ($LASTEXITCODE -ne 0) { throw "CANONICAL_BASE ancestry mismatch: $baseCommit is not an ancestor of $currentHead" }
    $productionPrefixes = @(
        "backend/doEngGameFlux/src/main/",
        "backend/doEngGameMvc/src/main/"
    )
    $sourceDiff = @(Invoke-Git @("diff", "--name-only", "$baseCommit..$currentHead")) | Where-Object {
        $candidate = $_.Trim().Replace("\\", "/")
        $productionPrefixes | Where-Object { $candidate.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
    }
    if ($sourceDiff.Count -ne 0) { throw "PRODUCTION_SOURCE_GATE: NO ($($sourceDiff -join '; '))" }
    $productionWorkingTreeStatus = @(Invoke-Git @("status", "--short", "--untracked-files=all", "--", "backend/doEngGameFlux/src/main", "backend/doEngGameMvc/src/main"))
    if ($productionWorkingTreeStatus.Count -ne 0) { throw "PRODUCTION_SOURCE_GATE: NO ($($productionWorkingTreeStatus -join '; '))" }
    $approvedExperimentTools = @("experiment/scripts/run-cadence-1s-confirmatory.ps1", "experiment/scripts/run-isolated-vu-success-smoke.ps1")
    $allStatus = @(Invoke-Git @("status", "--short", "--untracked-files=all"))
    $unexpectedStatus = @($allStatus | Where-Object {
        $line = $_.Trim()
        $path = ($line -replace '^\s*[?A-Z!]{1,2}\s+', '').Replace("\\", "/")
        $approvedExperimentTools -notcontains $path
    })
    if ($unexpectedStatus.Count -ne 0) { throw "UNEXPECTED_CHANGE_GATE: NO ($($unexpectedStatus -join '; '))" }
    $fixturePath = Join-Path $repositoryRoot $Config.fixture.path
    if (-not (Test-Path -LiteralPath $fixturePath)) { throw "Fixture missing" }
    $fixture = Get-Item -LiteralPath $fixturePath
    if ($fixture.Length -ne [int64]$Config.fixture.bytes) { throw "Fixture byte mismatch" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $fixture.FullName).Hash.ToLowerInvariant() -ne $Config.fixture.sha256) { throw "Fixture SHA mismatch" }
    foreach ($file in @($runScript, $loadScript) + $composeFiles) { if (-not (Test-Path -LiteralPath $file)) { throw "Missing input: $file" } }
    if ($Config.load.loadScenario -ne "single-success" -or $Config.load.accountingMode -ne "corrected" -or $Config.load.stopUserOnTrue) { throw "Fixed-periodic contract mismatch" }
    $checks = @(
        @{ name = "activeMissions"; actual = $Config.load.activeMissions; expected = 160 },
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
    $expectedOpportunities = Get-ExpectedRequestOpportunities $Config.load.activeMissions $Config.load.intervalMs $Config.load.durationMs
    if ($expectedOpportunities -ne [int64]$Config.load.expectedRequestOpportunities) { throw "Expected request opportunity formula mismatch" }
    if ([string]$Config.load.expectedOpportunityFormula -notmatch "floor\(i\*intervalMs/activeMissions\)") { throw "Expected request opportunity formula is not preregistered" }
    if ($Config.runOrder.Count -ne 6) { throw "Run count mismatch" }
    $expected = @("MVC1", "WEBFLUX1", "WEBFLUX2", "MVC2", "MVC3", "WEBFLUX3")
    if ((@($Config.runOrder | ForEach-Object logicalRun) -join ",") -ne ($expected -join ",")) { throw "Run order mismatch" }
    $source = Get-Content -Raw -LiteralPath $loadScript
    foreach ($pattern in @("setInterval(() => {", "void submitFrame(user)", "stopUserOnTrue", 'loadScenario === "reconnect-ramp"')) {
        if ($source -notmatch [regex]::Escape($pattern)) { throw "Lower-level semantic marker missing: $pattern" }
    }
    if ($source -notmatch [regex]::Escape('single-success')) { throw "Single-success scheduler marker missing" }
    if ($source -notmatch [regex]::Escape('arrivalMode === "staggered"')) { throw "Staggered scheduler marker missing" }
    if ($source -notmatch "ACTIVE_MISSIONS") { throw "ACTIVE_MISSIONS lower-level binding missing" }
    return [ordered]@{
        currentHead = $currentHead
        ancestry = $true
        productionSourceClean = $true
        approvedExperimentToolChanges = $true
        unexpectedChangeGate = $true
        expectedRequestOpportunities = $expectedOpportunities
    }
}

if ($NativeIoSelfTest) {
    Test-NativeIoHelper | Out-Null
    [ordered]@{
        nativeProcessHelper = "PASS"
        stderrExitZero = "PASS"
        stderrNonZero = "PASS"
        performanceExecution = "DISABLED"
    } | ConvertTo-Json
    exit 0
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$contract = Assert-Contract $config
$nodeForValidation = $NodeCommand
if ($DryRun) {
    $propagation = Test-ActiveMissionsPropagation $nodeForValidation
}

if ($DryRun) {
    [ordered]@{
        canonicalApplicationBase = $baseCommit
        experimentHarnessHead = $contract.currentHead
        ancestryGate = $contract.ancestry
        worktreeClean = $true
        productionSourceClean = $contract.productionSourceClean
        approvedExperimentToolChanges = $contract.approvedExperimentToolChanges
        unexpectedChangeGate = $contract.unexpectedChangeGate
        activeMissionsConfigKey = "activeMissions"
        activeMissionsPropagation = [ordered]@{ value = $config.load.activeMissions; status = if ($propagation) { "PASS" } else { "FAIL" } }
        runCount = 6
        runOrder = @($config.runOrder | ForEach-Object logicalRun)
        vu = $config.load.activeMissions
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
        expectedRequestOpportunities = [ordered]@{ value = $contract.expectedRequestOpportunities; formula = $config.load.expectedOpportunityFormula }
        validityGate = "PASS iff actualStartedRequests == expectedRequestOpportunities; scheduling fidelity, event-loop delay, generator CPU/RSS are recorded"
        resultDirectoryOwner = "LOWER_LEVEL_RUNNER"
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
    if (-not $StdOutPath) { $StdOutPath = Join-Path ([IO.Path]::GetTempPath()) "doeng-cadence-compose-$([guid]::NewGuid().ToString('N')).stdout.log" }
    if (-not $StdErrPath) { $StdErrPath = Join-Path ([IO.Path]::GetTempPath()) "doeng-cadence-compose-$([guid]::NewGuid().ToString('N')).stderr.log" }
    $nativeArguments = @("compose", "-p", $Project) + $composeArguments + $Arguments
    return Invoke-NativeProcess -FilePath "docker.exe" -ArgumentList $nativeArguments -StdOutPath $StdOutPath -StdErrPath $StdErrPath
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
    $orchestrationDirectory = Join-Path ([IO.Path]::GetTempPath()) "doeng-cadence-1s-$runId"
    if (Test-Path -LiteralPath $orchestrationDirectory) { Remove-Item -LiteralPath $orchestrationDirectory -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $orchestrationDirectory | Out-Null
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
        $buildCode = Invoke-ComposeCommand $project @("build", "experiment-mock", $spec.service) (Join-Path $orchestrationDirectory "compose-build.stdout.log") (Join-Path $orchestrationDirectory "compose-build.stderr.log")
        if ($buildCode -ne 0) { throw "Compose build failed: $buildCode" }
        $upCode = Invoke-ComposeCommand $project @("up", "-d", $spec.service) (Join-Path $orchestrationDirectory "compose-up.stdout.log") (Join-Path $orchestrationDirectory "compose-up.stderr.log")
        if ($upCode -ne 0) { throw "Compose up failed: $upCode" }
        $runtimeStarted = $true
        Wait-Readiness $spec.port
        $runnerArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runScript,
            "-RunId", $runId, "-Implementation", $Implementation, "-TargetUrl", "http://127.0.0.1:$($spec.port)/game/face",
            "-ServerService", $spec.service, "-ComposeProject", $project, "-ComposeFiles", ($composeFiles -join ","),
            "-ConfigPath", $configPath, "-ActiveMissions", "160", "-FixturePath", "image\arc.jpg", "-NodeCommand", $NodeCommand,
            "-EnableObservability", "1", "-EnableContainerMonitor", "1", "-EnableJfr", "0", "-SkipApplicationSnapshot", "0", "-SkipMockMetrics", "0",
            "-DrainObservationSeconds", "15", "-EchoImage", "1", "-LoadScenario", "single-success", "-AccountingMode", "corrected",
            "-ArrivalMode", "staggered", "-InitialActiveUsers", "160", "-ActivationStepUsers", "1", "-ActivationIntervalMs", "3000", "-ReconnectDelayMs", "1000",
            "-OutcomeMode", "controlled-admission"
        )
        $clientExitCode = Invoke-NativeProcess -FilePath "powershell.exe" -ArgumentList $runnerArgs `
            -StdOutPath (Join-Path $orchestrationDirectory "runner.stdout.log") `
            -StdErrPath (Join-Path $orchestrationDirectory "runner.stderr.log")
        $clientPath = Join-Path $resultsRoot "$runId\client-results.json"
        $logDestination = $runDirectory
        if (-not (Test-Path -LiteralPath $logDestination)) {
            $failureRoot = Join-Path $resultsRoot "_preload-blocked"
            $logDestination = Join-Path $failureRoot "$runId-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))"
            New-Item -ItemType Directory -Force -Path $logDestination | Out-Null
        }
        Get-ChildItem -LiteralPath $orchestrationDirectory -Filter "*.log" -File | Copy-Item -Destination $logDestination -Force
        if (-not (Test-Path -LiteralPath $clientPath)) { throw "Client result missing; exit=$clientExitCode" }
        $summary = (Get-Content -Raw -LiteralPath $clientPath | ConvertFrom-Json).summary
        $expectedOpportunities = [int64]$config.load.expectedRequestOpportunities
        $validity = [ordered]@{
            runId = $runId; logicalRun = $LogicalRun; implementation = $Implementation; expectedRequestOpportunities = $expectedOpportunities
            expectedOpportunityFormula = $config.load.expectedOpportunityFormula
            actualRequestStarts = $summary.startedRequests; schedulingFidelity = [double]$summary.startedRequests / $expectedOpportunities
            loadGenerator = $summary.loadGenerator; clientProcessExitCode = $clientExitCode
            loadGeneratorValid = ($summary.startedRequests -eq $expectedOpportunities -and $clientExitCode -eq 0)
        }
        $validity | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "load-generator-validity.json")
    } finally {
        if ($runtimeStarted) { Invoke-ComposeCommand $project @("down", "--remove-orphans") $null $null | Out-Null }
        if (Test-Path -LiteralPath $orchestrationDirectory) { Remove-Item -LiteralPath $orchestrationDirectory -Recurse -Force }
        foreach ($key in $envValues.Keys) {
            if ($null -eq $previous[$key]) { Remove-Item "Env:$key" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process") }
        }
    }
}

foreach ($run in $config.runOrder) { Invoke-ConfirmatoryRun $run.logicalRun $run.implementation }
