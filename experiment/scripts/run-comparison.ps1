param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("WebFlux", "MVC400")]
    [string]$Implementation,
    [string]$ConfigPath = "experiment/config/experiment-variable-contract.json",
    [string]$RunId,
    [string]$ComposeProject = "doeng-comparison",
    [string[]]$ComposeFiles,
    [string]$ExperimentMockImage,
    [switch]$Execute,
    [switch]$PrepareRuntimeOnly,
    [switch]$CpuNormalizationSelfTest,
    [switch]$RunnerArgumentSelfTest,
    [switch]$ExperimentMockSelectionSelfTest,
    [switch]$ObservabilityPassthroughSelfTest,
    [int]$EnableObservability = 0,
    [int]$EnableJfr = -1,
    [int]$EnableContainerMonitor = 1,
    [int]$SkipApplicationSnapshot = 0,
    [int]$SkipMockMetrics = 0,
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
. (Join-Path $PSScriptRoot "comparison-source-gate.ps1")
function Test-NumericCpuValue($expected, $actual) {
    try {
        $expectedNumber = [double]::Parse([string]$expected, [Globalization.CultureInfo]::InvariantCulture)
        $actualNumber = [double]::Parse([string]$actual, [Globalization.CultureInfo]::InvariantCulture)
        return [Math]::Abs($expectedNumber - $actualNumber) -le 1e-9
    } catch {
        return $false
    }
}
function Resolve-RunnerConfigPath($path) {
    if ([System.IO.Path]::IsPathRooted($path)) {
        return [System.IO.Path]::GetFullPath($path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $path))
}
function Get-ObservabilityRunnerArguments {
    param(
        [int]$Observability,
        [int]$Jfr,
        [int]$ContainerMonitor,
        [int]$SkipApplication,
        [int]$SkipMock
    )
    @(
        "-EnableObservability", [string]$Observability,
        "-EnableJfr", [string]$Jfr,
        "-EnableContainerMonitor", [string]$ContainerMonitor,
        "-SkipApplicationSnapshot", [string]$SkipApplication,
        "-SkipMockMetrics", [string]$SkipMock
    )
}
function Get-ExperimentMockSelection([string]$image, [string]$service, [string]$composeProject) {
    $prebuilt = -not [string]::IsNullOrWhiteSpace($image)
    [ordered]@{
        selectionMode = if ($prebuilt) { "prebuilt-image" } else { "built-current" }
        requestedImage = if ($prebuilt) { $image } else { $null }
        runtimeTag = "$composeProject-experiment-mock:latest"
        buildServices = if ($prebuilt) { @($service) } else { @("experiment-mock", $service) }
        buildExperimentMock = -not $prebuilt
        useNoBuildOnStartup = $prebuilt
    }
}
if ($CpuNormalizationSelfTest) {
    $cases = @(
        [ordered]@{ name = "CASE_A"; expected = "2.0"; actual = "2"; pass = Test-NumericCpuValue "2.0" "2" },
        [ordered]@{ name = "CASE_B"; expected = "2.5"; actual = "2.5"; pass = Test-NumericCpuValue "2.5" "2.5" },
        [ordered]@{ name = "CASE_C"; expected = "2.0"; actual = "1"; pass = -not (Test-NumericCpuValue "2.0" "1") }
    )
    $cases | ConvertTo-Json -Depth 4
    if (@($cases | Where-Object { -not $_.pass }).Count -gt 0) { exit 1 }
    exit 0
}
if ($ExperimentMockSelectionSelfTest) {
    $normal = Get-ExperimentMockSelection $null "mvc" "self-test-normal"
    $prebuilt = Get-ExperimentMockSelection "historical-mock:latest" "mvc" "self-test-prebuilt"
    $webflux = Get-ExperimentMockSelection "historical-mock:latest" "flux-corrected" "self-test-webflux"
    $result = [ordered]@{
        normal = [ordered]@{
            buildServices = @($normal.buildServices)
            experimentMockBuildExecuted = $normal.buildExperimentMock
            pass = (@($normal.buildServices) -join ",") -eq "experiment-mock,mvc" -and $normal.buildExperimentMock -and -not $normal.useNoBuildOnStartup
        }
        prebuilt = [ordered]@{
            buildServices = @($prebuilt.buildServices)
            experimentMockBuildExecuted = $prebuilt.buildExperimentMock
            runtimeAlias = $prebuilt.runtimeTag
            pass = (@($prebuilt.buildServices) -join ",") -eq "mvc" -and -not $prebuilt.buildExperimentMock -and $prebuilt.useNoBuildOnStartup -and $prebuilt.runtimeTag -eq "self-test-prebuilt-experiment-mock:latest"
        }
        webflux = [ordered]@{
            buildServices = @($webflux.buildServices)
            pass = (@($webflux.buildServices) -join ",") -eq "flux-corrected" -and -not $webflux.buildExperimentMock -and $webflux.useNoBuildOnStartup
        }
    }
    $result | ConvertTo-Json -Depth 8
    if (-not ($result.normal.pass -and $result.prebuilt.pass -and $result.webflux.pass)) { exit 1 }
    exit 0
}
$resolvedRunnerConfigPath = Resolve-RunnerConfigPath $ConfigPath
if ($RunnerArgumentSelfTest) {
    $relativePath = Resolve-RunnerConfigPath "experiment/config/comparison-vu160-service-3s.json"
    $absolutePath = Resolve-RunnerConfigPath $relativePath
    $relativeArguments = @("-ConfigPath", $relativePath)
    $absoluteArguments = @("-ConfigPath", $absolutePath)
    $result = [ordered]@{
        relative = [ordered]@{ argument = $relativeArguments[0]; path = $relativeArguments[1]; pass = ($relativeArguments[0] -eq "-ConfigPath" -and [System.IO.Path]::IsPathRooted($relativeArguments[1])) }
        absolute = [ordered]@{ argument = $absoluteArguments[0]; path = $absoluteArguments[1]; pass = ($absoluteArguments[0] -eq "-ConfigPath" -and [System.IO.Path]::IsPathRooted($absoluteArguments[1])) }
    }
    $result | ConvertTo-Json -Depth 5
    if (-not ($result.relative.pass -and $result.absolute.pass)) { exit 1 }
    exit 0
}
if ($ObservabilityPassthroughSelfTest) {
    $arguments = Get-ObservabilityRunnerArguments 1 1 1 0 0
    $expected = @(
        "-EnableObservability", "1",
        "-EnableJfr", "1",
        "-EnableContainerMonitor", "1",
        "-SkipApplicationSnapshot", "0",
        "-SkipMockMetrics", "0"
    )
    $pass = (@($arguments) -join "|") -eq (@($expected) -join "|")
    [ordered]@{ arguments = @($arguments); pass = $pass } | ConvertTo-Json -Depth 4
    if (-not $pass) { exit 1 }
    exit 0
}
if ($null -eq $ComposeFiles -or $ComposeFiles.Count -eq 0) {
    $ComposeFiles = @("backend/docker-compose.experiment.yaml", "experiment/compose/experiment-1-37-runtime.override.yml")
}
$composePaths = @($ComposeFiles | ForEach-Object {
    $path = if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $repositoryRoot $_ }
    [System.IO.Path]::GetFullPath($path)
})
foreach ($path in $composePaths) { if (-not (Test-Path -LiteralPath $path)) { throw "Compose file not found: $path" } }
$composeArguments = @()
foreach ($path in $composePaths) { $composeArguments += @("-f", $path) }
$resolvedJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "..\config\resolve-experiment-config.ps1") -Implementation $Implementation -ConfigPath $ConfigPath
if ($LASTEXITCODE -ne 0) { throw "Experiment config resolution failed" }
$resolved = @($resolvedJson) -join [Environment]::NewLine | ConvertFrom-Json
$service = if ($Implementation -eq "WebFlux") { "flux-corrected" } else { "mvc" }
$targetUrl = if ($Implementation -eq "WebFlux") { "http://127.0.0.1:8001/game/face" } else { "http://127.0.0.1:8002/game/face" }
$sourceStatus = Get-ComparisonSourceStatus -RepositoryRoot $repositoryRoot
$runtimeMode = $Execute -or $PrepareRuntimeOnly
$mockSelection = Get-ExperimentMockSelection $ExperimentMockImage $service $ComposeProject
$requestedExperimentMockImageId = $null
if (-not [string]::IsNullOrWhiteSpace($ExperimentMockImage)) {
    $requestedImageInspect = @(& docker image inspect $ExperimentMockImage | ConvertFrom-Json)[0]
    if ($LASTEXITCODE -ne 0 -or $null -eq $requestedImageInspect) {
        throw "Experiment mock image was not found locally: $ExperimentMockImage"
    }
    $requestedExperimentMockImageId = [string]$requestedImageInspect.Id
}
if ($runtimeMode -and -not $sourceStatus.clean) {
    [ordered]@{
        comparisonSourceClean = $false
        dirtyPaths = $sourceStatus.dirtyPaths
        workloadExecuted = $false
        buildExecuted = $false
        validation = "FAIL"
    } | ConvertTo-Json -Depth 8
    throw "COMPARISON_SOURCE_CLEAN: NO"
}
if ($runtimeMode -and [string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "PREPARE-$Implementation-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
}
$identityDirectory = Join-Path $repositoryRoot "experiment/results/runtime-identities/$RunId"
$buildStdoutPath = Join-Path $identityDirectory "docker-build.stdout.log"
$buildStderrPath = Join-Path $identityDirectory "docker-build.stderr.log"
$runtimeIdentityPath = Join-Path $identityDirectory "runtime-identity.json"
$runtimeStarted = $false
$envNames = @("APP_CPU","APP_MEMORY","HTTP_MAX_CONNECTIONS","HTTP_PENDING_MAX_COUNT","HTTP_CONNECT_TIMEOUT_MS","HTTP_RESPONSE_TIMEOUT_MS","HTTP_PENDING_ACQUIRE_TIMEOUT_MS","DB_POOL_MAX_SIZE","MVC_MAX_THREADS","JAVA_XMS","JAVA_XMX","MOCK_AI_RESULT","MOCK_AI_DELAY_MS","MOCK_AI_STATUS","MOCK_STORAGE_DELAY_MS","MOCK_STORAGE_STATUS")
$previous = @{}
foreach ($name in $envNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process"); Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
try {
    foreach ($property in $resolved.composeEnvironment.PSObject.Properties) { [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value, "Process") }
    $rendered = & docker compose -p $ComposeProject @composeArguments config
    if ($LASTEXITCODE -ne 0) { throw "docker compose config failed" }
    $renderedText = @($rendered) -join [Environment]::NewLine
    function MemoryBytes($value) {
        if ([string]$value -match '^(\d+(?:\.\d+)?)([mMgG])$') { return [int64]([double]$matches[1] * $(if ($matches[2] -match '[gG]') { 1GB } else { 1MB })) }
        return $null
    }
    function Test-ComposeValue($name, $value) {
        if ($name -eq "APP_CPU") {
            $serviceMatch = [regex]::Match($renderedText, "(?ms)^[ ]{2}" + [regex]::Escape($service) + ":\r?\n(?<body>.*?)(?=^[ ]{2}\S|\z)")
            if (-not $serviceMatch.Success) { return $false }
            $cpuMatch = [regex]::Match($serviceMatch.Groups["body"].Value, '(?m)^[ \t]*cpus:\s*(?<value>[-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*$')
            if (-not $cpuMatch.Success) { return $false }
            return Test-NumericCpuValue $value $cpuMatch.Groups["value"].Value
        }
        if ($name -eq "APP_MEMORY") { return $renderedText -match [regex]::Escape("mem_limit: `"$(MemoryBytes $value)`"") }
        if ($name -eq "JAVA_XMS") { return $renderedText -match [regex]::Escape("-Xms$value") }
        if ($name -eq "JAVA_XMX") { return $renderedText -match [regex]::Escape("-Xmx$value") }
        return $renderedText -match [regex]::Escape("${name}:") -and $renderedText -match [regex]::Escape($value)
    }
    $composeChecks = @($resolved.composeEnvironment.PSObject.Properties | ForEach-Object { [ordered]@{ name = $_.Name; value = [string]$_.Value; present = [bool](Test-ComposeValue $_.Name ([string]$_.Value)) } })
    $loadSource = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot "experiment/load/mission-load.js")
    $runnerSource = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot "experiment/scripts/run-isolated-vu-success-smoke.ps1")
    $loadChecks = @($resolved.loadEnvironment.PSObject.Properties | ForEach-Object {
        $loadName = $_.Name
        $recognized = $loadSource -match [regex]::Escape("process.env.$loadName") -or $loadSource -match [regex]::Escape(('"' + $loadName + '"'))
        [ordered]@{ name = $loadName; value = [string]$_.Value; loadEnvRecognized = [bool]$recognized; runnerExports = [bool]($runnerSource -match [regex]::Escape(('$env:' + $loadName))) }
    })
    $allChecks = @($composeChecks + $loadChecks)
    $configResult = [ordered]@{
        implementation = $Implementation
        service = $service
        targetUrl = $targetUrl
        configPath = $resolved.configPath
        resolvedExperimentConfig = $resolved
        configToCompose = (@($composeChecks | Where-Object { -not $_.present }).Count -eq 0)
        configToLoad = (@($loadChecks | Where-Object { -not $_.loadEnvRecognized -or -not $_.runnerExports }).Count -eq 0)
        resolvedConfigMatch = (@($composeChecks | Where-Object { -not $_.present }).Count -eq 0) -and (@($loadChecks | Where-Object { -not $_.loadEnvRecognized -or -not $_.runnerExports }).Count -eq 0)
        checks = $allChecks
        workloadExecuted = $false
    }
    if (-not $configResult.configToCompose -or -not $configResult.configToLoad) { $configResult.validation = "FAIL"; $configResult | ConvertTo-Json -Depth 12; exit 1 }
    if (-not $runtimeMode) { $configResult.validation = "PASS"; $configResult | ConvertTo-Json -Depth 12; exit 0 }
    New-Item -ItemType Directory -Path $identityDirectory -Force | Out-Null
    function Invoke-NativeProcess {
        param(
            [Parameter(Mandatory = $true)][string]$FilePath,
            [Parameter(Mandatory = $true)][string[]]$Arguments,
            [Parameter(Mandatory = $true)][string]$StdOutPath,
            [Parameter(Mandatory = $true)][string]$StdErrPath
        )
        $startArguments = @($Arguments | ForEach-Object {
            $argument = [string]$_
            if ($argument -match '[\s"]') { '"' + $argument.Replace('"', '\"') + '"' } else { $argument }
        })
        $process = Start-Process -FilePath $FilePath -ArgumentList $startArguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath
        return [int]$process.ExitCode
    }
    if ($mockSelection.useNoBuildOnStartup) {
        & docker tag $ExperimentMockImage $mockSelection.runtimeTag
        if ($LASTEXITCODE -ne 0) { throw "Experiment mock runtime alias creation failed" }
        $buildExitCode = Invoke-NativeProcess -FilePath "docker" -Arguments (@("compose", "-p", $ComposeProject) + $composeArguments + @("build", $service)) -StdOutPath $buildStdoutPath -StdErrPath $buildStderrPath
    } else {
        $buildExitCode = Invoke-NativeProcess -FilePath "docker" -Arguments (@("compose", "-p", $ComposeProject) + $composeArguments + @("build", "experiment-mock", $service)) -StdOutPath $buildStdoutPath -StdErrPath $buildStderrPath
    }
    if ($buildExitCode -ne 0) { throw "Docker comparison image build failed with exit code $buildExitCode" }
    $configResult.buildExecuted = $true
    $upArguments = @("compose", "-p", $ComposeProject) + $composeArguments + @("up", "-d")
    if ($mockSelection.useNoBuildOnStartup) { $upArguments += "--no-build" }
    $upArguments += $service
    & docker @upArguments
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }
    $runtimeStarted = $true
    function Get-ContainerIdentity([string]$serviceName) {
        $id = (& docker compose -p $ComposeProject @composeArguments ps -q $serviceName).Trim()
        if ([string]::IsNullOrWhiteSpace($id)) { throw "Running container was not found: $serviceName" }
        $inspect = @(& docker inspect $id | ConvertFrom-Json)[0]
        if ($LASTEXITCODE -ne 0 -or $null -eq $inspect) { throw "Container identity capture failed: $serviceName" }
        $imageReference = [string]$inspect.Config.Image
        $image = @(& docker image inspect $imageReference | ConvertFrom-Json)[0]
        if ($LASTEXITCODE -ne 0 -or $null -eq $image) { throw "Image identity capture failed: $imageReference" }
        [ordered]@{
            containerId = $inspect.Id
            imageId = $inspect.Image
            imageCreated = $image.Created
            repoTags = @($image.RepoTags)
            repoDigests = @($image.RepoDigests)
        }
    }
    $applicationIdentity = Get-ContainerIdentity $service
    $experimentMockIdentity = Get-ContainerIdentity "experiment-mock"
    if ($mockSelection.useNoBuildOnStartup -and $requestedExperimentMockImageId -ne $experimentMockIdentity.imageId) {
        throw "Experiment mock image identity mismatch: requested $requestedExperimentMockImageId, running $($experimentMockIdentity.imageId)"
    }
    $mariadbIdentity = Get-ContainerIdentity "mariadb"
    $containerId = $applicationIdentity.containerId
    $jarPath = Join-Path $identityDirectory "app.jar"
    & docker cp "$containerId`:/app/app.jar" $jarPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $jarPath)) { throw "Running JAR capture failed" }
    $jarHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $jarPath).Hash
    Remove-Item -LiteralPath $jarPath -Force
    $manifestPath = Join-Path $repositoryRoot "experiment/config/comparison-source-manifest.txt"
    $manifestHash = if (Test-Path -LiteralPath $manifestPath) { (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash } else { $null }
    $runtimeIdentity = [ordered]@{
        git = [ordered]@{ head = (git rev-parse HEAD); branch = (git branch --show-current); comparisonSourceClean = $sourceStatus.clean }
        implementation = $Implementation
        container = [ordered]@{ id = $applicationIdentity.containerId; imageId = $applicationIdentity.imageId }
        image = [ordered]@{ id = $applicationIdentity.imageId; created = $applicationIdentity.imageCreated; repoTags = $applicationIdentity.repoTags; repoDigests = $applicationIdentity.repoDigests }
        application = [ordered]@{ jarPath = "/app/app.jar"; jarSha256 = $jarHash }
        source = [ordered]@{ comparisonSourceManifest = "experiment/config/comparison-source-manifest.txt"; comparisonSourceManifestSha256 = $manifestHash; experimentMockSourceRoot = "backend/experiment-mock"; experimentMockBuildExecuted = $mockSelection.buildExperimentMock }
        experimentMockSelectionMode = $mockSelection.selectionMode
        requestedExperimentMockImage = $mockSelection.requestedImage
        requestedExperimentMockImageId = $requestedExperimentMockImageId
        composeExperimentMockRuntimeTag = $mockSelection.runtimeTag
        dependencies = [ordered]@{ experimentMock = $experimentMockIdentity; mariadb = $mariadbIdentity }
        build = [ordered]@{ executed = $true; exitCode = $buildExitCode; stdout = "docker-build.stdout.log"; stderr = "docker-build.stderr.log" }
    }
    $runtimeIdentity | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $runtimeIdentityPath
    $configResult.runtimeIdentity = "experiment/results/runtime-identities/$RunId/runtime-identity.json"
    if ($PrepareRuntimeOnly) { $configResult.validation = "PASS"; $configResult.workloadExecuted = $false; $configResult | ConvertTo-Json -Depth 12; exit 0 }
    if (-not $Execute) { throw "Runtime mode was not selected" }
    $configResult.workloadExecuted = $true
    & docker compose -p $ComposeProject @composeArguments up -d $service
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }
    $port = if ($Implementation -eq "WebFlux") { 8001 } else { 8002 }
    $reachable = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $tcp = [Net.Sockets.TcpClient]::new()
        try { $tcp.Connect("127.0.0.1", $port); $reachable = $true; break } catch {} finally { $tcp.Dispose() }
        Start-Sleep -Seconds 1
    }
    if (-not $reachable) { throw "Target port did not become reachable: $port" }
    $runnerArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "run-isolated-vu-success-smoke.ps1"),
        "-RunId", $RunId, "-Implementation", $Implementation, "-TargetUrl", $targetUrl,
        "-ServerService", $service, "-ComposeProject", $ComposeProject, "-ComposeFiles", ($composePaths -join ","),
        "-ConfigPath", $resolvedRunnerConfigPath
    )
    $runnerArguments += Get-ObservabilityRunnerArguments $EnableObservability $EnableJfr $EnableContainerMonitor $SkipApplicationSnapshot $SkipMockMetrics
    if ($NodeCommand) { $runnerArguments += @("-NodeCommand", $NodeCommand) }
    & powershell.exe @runnerArguments
    if ($LASTEXITCODE -ne 0) { throw "Comparison runner failed" }
} finally {
    if ($runtimeStarted) { & docker compose -p $ComposeProject @composeArguments down --remove-orphans | Out-Null }
    foreach ($name in $envNames) {
        if ($null -eq $previous[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process") }
    }
}
