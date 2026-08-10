param(
    [string]$ContractPath = "experiment/config/experiment-variable-contract.json",
    [ValidateSet("WebFlux", "MVC400")]
    [string]$Implementation = "WebFlux",
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolver = Join-Path $PSScriptRoot "resolve-experiment-config.ps1"
$contractFile = if ([System.IO.Path]::IsPathRooted($ContractPath)) { [System.IO.Path]::GetFullPath($ContractPath) } else { [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $ContractPath)) }
if (-not (Test-Path -LiteralPath $contractFile)) { throw "Contract file not found: $contractFile" }
$resolvedJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -Implementation $Implementation -ConfigPath $contractFile
if ($LASTEXITCODE -ne 0) { throw "Config resolver failed" }
$resolved = @($resolvedJson) -join [Environment]::NewLine | ConvertFrom-Json
$envNames = @("APP_CPU","APP_MEMORY","HTTP_MAX_CONNECTIONS","HTTP_PENDING_MAX_COUNT","HTTP_CONNECT_TIMEOUT_MS","HTTP_RESPONSE_TIMEOUT_MS","HTTP_PENDING_ACQUIRE_TIMEOUT_MS","DB_POOL_MAX_SIZE","MVC_MAX_THREADS","JAVA_XMS","JAVA_XMX","MOCK_AI_RESULT","MOCK_AI_DELAY_MS","MOCK_AI_STATUS","MOCK_STORAGE_DELAY_MS","MOCK_STORAGE_STATUS")
$previous = @{}
foreach ($name in $envNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process"); Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
try {
    foreach ($property in $resolved.composeEnvironment.PSObject.Properties) { [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value, "Process") }
    $composeFiles = @((Join-Path $repositoryRoot "backend/docker-compose.experiment.yaml"),(Join-Path $repositoryRoot "experiment/compose/experiment-1-37-runtime.override.yml"))
    $rendered = & docker compose -p doeng-contract-validation -f $composeFiles[0] -f $composeFiles[1] config
    if ($LASTEXITCODE -ne 0) { throw "docker compose config failed" }
    $renderedText = @($rendered) -join [Environment]::NewLine
    function MemoryBytes($value) {
        if ([string]$value -match '^(\d+(?:\.\d+)?)([mMgG])$') { return [int64]([double]$matches[1] * $(if ($matches[2] -match '[gG]') { 1GB } else { 1MB })) }
        return $null
    }
    $composeChecks = @($resolved.composeEnvironment.PSObject.Properties | ForEach-Object {
        $name = $_.Name; $value = [string]$_.Value
        $present = if ($name -eq "APP_CPU") { $renderedText -match [regex]::Escape("cpus: $value") } elseif ($name -eq "APP_MEMORY") { $renderedText -match [regex]::Escape("mem_limit: `"$(MemoryBytes $value)`"") } elseif ($name -eq "JAVA_XMS") { $renderedText -match [regex]::Escape("-Xms$value") } elseif ($name -eq "JAVA_XMX") { $renderedText -match [regex]::Escape("-Xmx$value") } else { $renderedText -match [regex]::Escape("${name}:") -and $renderedText -match [regex]::Escape($value) }
        [ordered]@{ name = $name; value = $value; present = [bool]$present }
    })
    $loadSource = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot "experiment/load/mission-load.js")
    $runnerSource = Get-Content -Raw -LiteralPath (Join-Path $repositoryRoot "experiment/scripts/run-isolated-vu-success-smoke.ps1")
    $loadChecks = @($resolved.loadEnvironment.PSObject.Properties | ForEach-Object {
        $loadName = $_.Name
        $recognized = $loadSource -match [regex]::Escape("process.env.$loadName") -or $loadSource -match [regex]::Escape(('"' + $loadName + '"'))
        [ordered]@{ name = $loadName; loadEnvRecognized = [bool]$recognized; runnerExports = [bool]($runnerSource -match [regex]::Escape(('$env:' + $loadName))) }
    })
    $runnerResolvedCheck = $runnerSource -match 'resolved-experiment-config\.json' -and $runnerSource -match 'resolve-experiment-config\.ps1'
    $downstreamCheck = $runnerSource -match '\$AiResult' -and $runnerSource -match '\$AiDelayMs' -and $runnerSource -match '\$StorageDelayMs' -and $runnerSource -match '__control'
    $invalidPath = Join-Path $env:TEMP "doeng-invalid-contract-$([guid]::NewGuid().ToString('N')).json"
    $invalidConfig = Get-Content -Raw -LiteralPath $contractFile | ConvertFrom-Json
    $invalidConfig.load.loadScenario = "invalid-scenario"
    $invalidConfig | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $invalidPath
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -Implementation $Implementation -ConfigPath $invalidPath 1>$null 2>$null
    $negativeExit = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    [IO.File]::Delete($invalidPath)
    $negativeCheck = $negativeExit -ne 0
    $result = [ordered]@{
        validation = "PASS"
        workloadExecuted = $false
        implementation = $Implementation
        resolvedExperimentConfig = $resolved
        configToCompose = (@($composeChecks | Where-Object { -not $_.present }).Count -eq 0)
        configToLoad = (@($loadChecks | Where-Object { -not $_.loadEnvRecognized -or -not $_.runnerExports }).Count -eq 0)
        resolvedConfigMatch = [bool]$runnerResolvedCheck
        downstreamPropagation = [bool]$downstreamCheck
        validatorNegativeTest = [bool]$negativeCheck
        composeChecks = $composeChecks
        loadChecks = $loadChecks
    }
    if (-not $result.configToCompose -or -not $result.configToLoad -or -not $result.resolvedConfigMatch -or -not $result.downstreamPropagation -or -not $result.validatorNegativeTest) { $result.validation = "FAIL" }
    $json = $result | ConvertTo-Json -Depth 12
    if ($OutputPath) { $outputFile = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repositoryRoot $OutputPath }; New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null; $json | Set-Content -Encoding UTF8 -LiteralPath $outputFile }
    $json
    if ($result.validation -eq "FAIL") { exit 1 }
} finally {
    foreach ($name in $envNames) { if ($null -eq $previous[$name]) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name, $previous[$name], "Process") } }
}
