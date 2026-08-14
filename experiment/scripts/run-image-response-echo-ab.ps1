param(
    [switch]$Execute
)

$ErrorActionPreference = "Stop"
if (-not $Execute) {
    Write-Output "DRY_RUN_ONLY"
    exit 0
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resultsRoot = Join-Path $repositoryRoot "experiment\results"
$orchestrationRoot = Join-Path $resultsRoot "WEBFLUX-IMAGE-ECHO-AB-20260814"
$baseCompose = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml"))
$overrideCompose = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "experiment\compose\experiment-1-37-runtime.override.yml"))
$configPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "experiment\config\comparison-vu160-service-3s.json"))
$readinessScript = Join-Path $repositoryRoot "experiment\scripts\wait-mvc-readiness.ps1"
$runnerScript = Join-Path $repositoryRoot "experiment\scripts\run-isolated-vu-success-smoke.ps1"
$nodeCommand = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$composeFiles = @($baseCompose, $overrideCompose)
$composeArgs = @()
foreach ($file in $composeFiles) { $composeArgs += @("-f", $file) }
$composeFilesBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@("backend\docker-compose.experiment.yaml", "experiment\compose\experiment-1-37-runtime.override.yml") | ConvertTo-Json -Compress)))
$sourceHead = (& git -C $repositoryRoot rev-parse HEAD).Trim()
$branch = (& git -C $repositoryRoot branch --show-current).Trim()

$runs = @(
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-A1"; condition = "A"; echoImage = 1; project = "doeng-echo-ab-a1" },
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-B1"; condition = "B"; echoImage = 0; project = "doeng-echo-ab-b1" },
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-B2"; condition = "B"; echoImage = 0; project = "doeng-echo-ab-b2" },
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-A2"; condition = "A"; echoImage = 1; project = "doeng-echo-ab-a2" },
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-A3"; condition = "A"; echoImage = 1; project = "doeng-echo-ab-a3" },
    [pscustomobject]@{ id = "WEBFLUX-IMAGE-ECHO-B3"; condition = "B"; echoImage = 0; project = "doeng-echo-ab-b3" }
)

if (-not (Test-Path -LiteralPath $nodeCommand)) { throw "Bundled Node executable not found: $nodeCommand" }
foreach ($required in @($baseCompose, $overrideCompose, $configPath, $readinessScript, $runnerScript)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required file not found: $required" }
}

New-Item -ItemType Directory -Force -Path $orchestrationRoot | Out-Null
foreach ($run in $runs) {
    $runDirectory = Join-Path $resultsRoot $run.id
    if (Test-Path -LiteralPath $runDirectory) { throw "Run result directory already exists: $runDirectory" }
    $runOrchestration = Join-Path $orchestrationRoot $run.id
    if (Test-Path -LiteralPath $runOrchestration) { throw "Run orchestration directory already exists: $runOrchestration" }
}

$contractEnvironment = [ordered]@{
    APP_CPU = "2.0"
    APP_MEMORY = "3g"
    HTTP_MAX_CONNECTIONS = "400"
    HTTP_PENDING_MAX_COUNT = "400"
    HTTP_CONNECT_TIMEOUT_MS = "2000"
    HTTP_RESPONSE_TIMEOUT_MS = "10000"
    HTTP_PENDING_ACQUIRE_TIMEOUT_MS = "10000"
    DB_POOL_MAX_SIZE = "10"
    JAVA_XMS = "512m"
    JAVA_XMX = "2048m"
    MOCK_AI_RESULT = "true"
    MOCK_AI_DELAY_MS = "2000"
    MOCK_AI_STATUS = "200"
    MOCK_STORAGE_DELAY_MS = "100"
    MOCK_STORAGE_STATUS = "200"
}
$previousEnvironment = @{}
foreach ($name in $contractEnvironment.Keys) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
    [Environment]::SetEnvironmentVariable($name, $contractEnvironment[$name], "Process")
}

function Invoke-Captured {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$StdoutPath,
        [Parameter(Mandatory = $true)][string]$StderrPath
    )
    & $FilePath @Arguments 1> $StdoutPath 2> $StderrPath
    return [int]$LASTEXITCODE
}

function Save-Json {
    param([object]$Value, [string]$Path)
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

$completedRuns = @()
$failure = $null
try {
    foreach ($run in $runs) {
        $runOrchestration = Join-Path $orchestrationRoot $run.id
        New-Item -ItemType Directory -Force -Path $runOrchestration | Out-Null
        $runDirectory = Join-Path $resultsRoot $run.id
        $eventStdout = Join-Path $runOrchestration "docker-events.jsonl"
        $eventStderr = Join-Path $runOrchestration "docker-events.stderr.log"
        $composeStdout = Join-Path $runOrchestration "compose-up.stdout.log"
        $composeStderr = Join-Path $runOrchestration "compose-up.stderr.log"
        $readinessStdout = Join-Path $runOrchestration "readiness.stdout.log"
        $readinessStderr = Join-Path $runOrchestration "readiness.stderr.log"
        $runnerStdout = Join-Path $runOrchestration "runner.stdout.log"
        $runnerStderr = Join-Path $runOrchestration "runner.stderr.log"
        $eventsProcess = $null

        try {
            $eventsProcess = Start-Process -FilePath "docker" -ArgumentList @("events", "--filter", "label=com.docker.compose.project=$($run.project)", "--format", "{{json .}}") -RedirectStandardOutput $eventStdout -RedirectStandardError $eventStderr -PassThru -WindowStyle Hidden
            $upCode = Invoke-Captured -FilePath "docker" -Arguments (@("compose", "-p", $run.project) + $composeArgs + @("up", "-d", "flux-corrected")) -StdoutPath $composeStdout -StderrPath $composeStderr
            if ($upCode -ne 0) { throw "Compose startup failed with exit code $upCode" }

            $readinessOutput = Join-Path $runOrchestration "startup-gate.json"
            $readinessArgs = @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $readinessScript,
                "-ComposeProject", $run.project, "-ServerService", "flux-corrected",
                "-MainPort", "8001", "-ManagementPort", "9001", "-MockPort", "9100",
                "-MaxWaitSeconds", "180", "-StableSeconds", "10", "-UseManagementHealthForReadiness",
                "-ComposeFilesBase64", $composeFilesBase64, "-OutputPath", $readinessOutput
            )
            $readinessCode = Invoke-Captured -FilePath "powershell.exe" -Arguments $readinessArgs -StdoutPath $readinessStdout -StderrPath $readinessStderr
            if ($readinessCode -ne 0) { throw "Startup/readiness gate failed with exit code $readinessCode" }
            $readinessGate = Get-Content -Raw -LiteralPath $readinessOutput | ConvertFrom-Json
            if ($readinessGate.pass -ne $true) { throw "Startup/readiness gate did not pass" }

            New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
            $runnerArgs = @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runnerScript,
                "-RunId", $run.id, "-Implementation", "WebFlux", "-TargetUrl", "http://127.0.0.1:8001/game/face",
                "-ServerService", "flux-corrected", "-ComposeProject", $run.project,
                "-ComposeFiles", ($composeFiles -join ","), "-ConfigPath", $configPath,
                "-EchoImage", [string]$run.echoImage, "-EnableObservability", "1", "-EnableJfr", "1",
                "-EnableContainerMonitor", "0", "-SkipApplicationSnapshot", "1", "-SkipMockMetrics", "1",
                "-DrainObservationSeconds", "15", "-NodeCommand", $nodeCommand
            )
            $runnerCode = Invoke-Captured -FilePath "powershell.exe" -Arguments $runnerArgs -StdoutPath $runnerStdout -StderrPath $runnerStderr
            $verificationPath = Join-Path $runDirectory "verification-summary.json"
            if (-not (Test-Path -LiteralPath $verificationPath)) { throw "verification-summary.json was not created" }
            $verification = Get-Content -Raw -LiteralPath $verificationPath | ConvertFrom-Json
            if ($runnerCode -ne 0 -or $verification.executionValidity -ne "VALID") { throw "Measurement execution was not VALID (exit=$runnerCode, validity=$($verification.executionValidity))" }

            $containerId = ((& docker compose -p $run.project @composeArgs ps -q flux-corrected) | Select-Object -First 1).Trim()
            $inspectPath = Join-Path $runOrchestration "post-inspect.json"
            (& docker inspect $containerId 2>&1) | Set-Content -Encoding UTF8 -LiteralPath $inspectPath
            (& docker stats --no-stream --all $containerId 2>&1) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runOrchestration "post-stats.txt")
            (& docker compose -p $run.project @composeArgs logs --no-color 2>&1) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runOrchestration "compose-logs.log")

            $mockRequestsPath = Join-Path $runDirectory "mock-requests.json"
            if (Test-Path -LiteralPath $mockRequestsPath) {
                $mockRequests = Get-Content -Raw -LiteralPath $mockRequestsPath | ConvertFrom-Json
                $writeEvents = @($mockRequests.aiLifecycleEvents | Where-Object { $_.event -eq "MOCK_AI_RESPONSE_WRITE_STARTED" })
                Save-Json ([ordered]@{
                    condition = $run.condition
                    echoImage = $run.echoImage -eq 1
                    responseWriteEventCount = $writeEvents.Count
                    responseBytes = @($writeEvents | ForEach-Object { $_.responseBytes } | Where-Object { $null -ne $_ })
                    responseBytesDistinct = @($writeEvents | ForEach-Object { $_.responseBytes } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
                    responseStatuses = @($writeEvents | ForEach-Object { $_.responseStatus } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
                } | ConvertTo-Json -Depth 8 | ConvertFrom-Json) (Join-Path $runDirectory "response-size-summary.json")
            }
            Save-Json ([ordered]@{
                runId = $run.id
                condition = $run.condition
                echoImage = $run.echoImage -eq 1
                composeProject = $run.project
                sourceHead = $sourceHead
                branch = $branch
                composeFiles = $composeFiles
                startupGate = $readinessGate
                runnerExitCode = $runnerCode
                verificationValidity = $verification.executionValidity
                applicationOutcomePassed = $verification.applicationOutcomePassed
            }) (Join-Path $runDirectory "outer-runtime.json")
            $completedRuns += $run.id
        } finally {
            if ($null -ne $eventsProcess -and -not $eventsProcess.HasExited) {
                Stop-Process -Id $eventsProcess.Id -Force -ErrorAction SilentlyContinue
                $eventsProcess.WaitForExit()
            }
            (& docker compose -p $run.project @composeArgs down --remove-orphans 2>&1) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runOrchestration "compose-down.log")
        }
    }
} catch {
    $failure = $_
} finally {
    foreach ($name in $contractEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
    }
    Save-Json ([ordered]@{
        runOrder = @($runs | ForEach-Object { $_.id })
        completedRuns = $completedRuns
        failed = $null -ne $failure
        failure = if ($null -ne $failure) { $failure.Exception.Message } else { $null }
        sourceHead = $sourceHead
        branch = $branch
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }) (Join-Path $orchestrationRoot "cohort-progress.json")
}

if ($null -ne $failure) { throw $failure }
Write-Output "ALL_SIX_RUNS_VALID"
