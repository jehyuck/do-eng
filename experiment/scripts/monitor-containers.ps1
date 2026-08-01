param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    [Parameter(Mandatory = $true)]
    [string]$ServerService,
    [string]$ComposeProject = "doeng-experiment",
    [string[]]$ComposeFiles,
    [int]$IntervalSeconds = 1,
    [int]$DurationSeconds = 60,
    [ValidateSet(0, 1)]
    [int]$SkipApplicationSnapshot = 0,
    [ValidateSet(0, 1)]
    [int]$SkipMockMetrics = 0,
    [string]$OutputDirectory,
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"

if ($IntervalSeconds -le 0 -or $DurationSeconds -le 0) {
    throw "IntervalSeconds and DurationSeconds must be positive"
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($null -eq $ComposeFiles -or $ComposeFiles.Count -eq 0) {
    $ComposeFiles = @(Join-Path $repositoryRoot "backend\docker-compose.experiment.yaml")
}
$ComposeFiles = @($ComposeFiles | ForEach-Object {
    $_ -split ',' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
})
$composeArguments = @()
foreach ($composeFile in $ComposeFiles) {
    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "Compose file not found: $composeFile"
    }
    $composeArguments += @("-f", $composeFile)
}
$resultsRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "experiment\results")
)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $resultsRoot $RunId
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$resultsPrefix = $resultsRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedOutput.StartsWith(
        $resultsPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "OutputDirectory must be inside $resultsRoot"
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

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

$serviceNames = @($ServerService, "mariadb", "experiment-mock")
$containers = foreach ($serviceName in $serviceNames) {
    $containerId = (
        & docker compose `
            -p $ComposeProject `
            @composeArguments `
            ps -q $serviceName
    ).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw "Running container not found for service: $serviceName"
    }

    [pscustomobject][ordered]@{
        service = $serviceName
        id = $containerId
    }
}

$serverContainerId = (
    $containers |
        Where-Object { $_.service -eq $ServerService } |
        Select-Object -ExpandProperty id
)

$serverInspect = & docker inspect $serverContainerId | ConvertFrom-Json
$serverPortBindings = $serverInspect[0].NetworkSettings.Ports.'9091/tcp'
if ($null -eq $serverPortBindings -or $serverPortBindings.Count -eq 0) {
    throw "Published management port not found for service: $ServerService"
}
$serverHostPort = $serverPortBindings[0].HostPort

$mockContainerId = (
    $containers |
        Where-Object { $_.service -eq "experiment-mock" } |
        Select-Object -ExpandProperty id
)
$databaseContainerId = (
    $containers |
        Where-Object { $_.service -eq "mariadb" } |
        Select-Object -ExpandProperty id
)
$mockInspect = & docker inspect $mockContainerId | ConvertFrom-Json
$mockPortBindings = $mockInspect[0].NetworkSettings.Ports.'9100/tcp'
if ($null -eq $mockPortBindings -or $mockPortBindings.Count -eq 0) {
    throw "Published mock port not found"
}
$mockHostPort = $mockPortBindings[0].HostPort

$env:MONITOR_RUN_ID = $RunId
$env:MONITOR_OUTPUT_DIRECTORY = $resolvedOutput
$env:MONITOR_SERVER_CONTAINER_ID = $serverContainerId
$env:MONITOR_DATABASE_CONTAINER_ID = $databaseContainerId
$env:MONITOR_DURATION_MS = [string]($DurationSeconds * 1000)
$env:MONITOR_INTERVAL_MS = [string]($IntervalSeconds * 1000)
$env:MONITOR_DATABASE_INTERVAL_MS = [string](
    [Math]::Max(2000, $IntervalSeconds * 1000)
)
$env:MONITOR_CONTAINER_MAP = (
    $containers |
        ConvertTo-Json -Compress
)
$env:MONITOR_APP_METRICS_URL = "http://127.0.0.1:$serverHostPort/actuator/doengexperiment"
$env:MONITOR_MOCK_METRICS_URL = "http://127.0.0.1:$mockHostPort/__metrics"
$env:MONITOR_SKIP_APPLICATION_SNAPSHOT = [string]$SkipApplicationSnapshot
$env:MONITOR_SKIP_MOCK_METRICS = [string]$SkipMockMetrics

& $NodeCommand (Join-Path $PSScriptRoot "monitor-containers.js")
if ($LASTEXITCODE -ne 0) {
    throw "Container monitor failed"
}

[ordered]@{
    runId = $RunId
    success = $true
    nodeExitCode = $LASTEXITCODE
    completedAt = (Get-Date).ToUniversalTime().ToString("o")
} |
    ConvertTo-Json -Depth 3 |
    Set-Content -Encoding UTF8 -LiteralPath (
        Join-Path $resolvedOutput "monitor-process-status.json"
    )

exit 0
