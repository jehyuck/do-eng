param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("WebFlux", "MVC400")]
    [string]$Implementation,
    [string]$ConfigPath = "experiment/config/experiment-variable-contract.json",
    [string]$RunId,
    [string]$ComposeProject = "doeng-comparison",
    [string[]]$ComposeFiles,
    [switch]$Execute,
    [string]$NodeCommand
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
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
        if ($name -eq "APP_CPU") { return $renderedText -match [regex]::Escape("cpus: $value") }
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
    if (-not $Execute) { $configResult.validation = "PASS"; $configResult | ConvertTo-Json -Depth 12; exit 0 }
    if ([string]::IsNullOrWhiteSpace($RunId)) { throw "-RunId is required with -Execute" }
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
        "-ConfigPath", (if ([System.IO.Path]::IsPathRooted($ConfigPath)) { [System.IO.Path]::GetFullPath($ConfigPath) } else { [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ConfigPath)) })
    )
    if ($NodeCommand) { $runnerArguments += @("-NodeCommand", $NodeCommand) }
    & powershell.exe @runnerArguments
    if ($LASTEXITCODE -ne 0) { throw "Comparison runner failed" }
} finally {
    if ($Execute) { & docker compose -p $ComposeProject @composeArguments down --remove-orphans | Out-Null }
    foreach ($name in $envNames) {
        if ($null -eq $previous[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process") }
    }
}
