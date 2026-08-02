param(
    [Parameter(Mandatory = $true)][string]$RunId,
    [ValidateSet("CLEAN", "REUSED")][string]$StateMode = "CLEAN"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-10-transport-attribution.yaml"
)
$composeArgs = @()
foreach ($file in $composeFiles) { $composeArgs += @("-f", $file) }
$composeProject = "doeng-exp18"
$previousTransport = $env:DOENG_TRANSPORT_ATTRIBUTION_ENABLED
$logPath = Join-Path $root "experiment\results\$RunId\application.log"

function Invoke-Compose([string[]]$Services) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker compose -p $composeProject @composeArgs up -d --force-recreate @Services | Out-Null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($exitCode -ne 0) { throw "compose dependency recreate failed with exit $exitCode" }
}

function Wait-Healthy([string]$Url, [int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-RestMethod $Url -TimeoutSec 5
            if ($null -ne $response -and ($response.status -eq "UP" -or $response.status -eq "ok")) { return }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "health did not become ready: $Url"
}

try {
    $env:DOENG_TRANSPORT_ATTRIBUTION_ENABLED = "true"
    if ($StateMode -eq "CLEAN") {
        Invoke-Compose @("mariadb", "experiment-mock")
    }
    Wait-Healthy "http://127.0.0.1:9100/health"
    $mock = Invoke-RestMethod "http://127.0.0.1:9100/__metrics" -TimeoutSec 5
    if ($mock.aiInFlight -ne 0 -or $mock.storageInFlight -ne 0) {
        throw "pre-run mock is not idle"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
        -RunId $RunId -RunKind core `
        -ComposeOverlay "backend\docker-compose.experiment-1-10-transport-attribution.yaml" `
        -AiDelayMs 2000 -ComposeProject $composeProject -SkipPhase1Observer
    if ($LASTEXITCODE -ne 0) { throw "transport attribution run failed: $LASTEXITCODE" }
} finally {
    $runDirectory = Join-Path $root "experiment\results\$RunId"
    New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
    $container = (docker compose -p $composeProject @composeArgs ps -q flux-corrected).Trim()
    if (-not [string]::IsNullOrWhiteSpace($container)) {
        $previousLogErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        docker logs --timestamps $container 2>&1 |
            ForEach-Object { $_.ToString() } |
            Out-File -LiteralPath $logPath -Encoding UTF8
        $ErrorActionPreference = $previousLogErrorAction
    }
    if ($null -eq $previousTransport) { Remove-Item Env:DOENG_TRANSPORT_ATTRIBUTION_ENABLED -ErrorAction SilentlyContinue }
    else { $env:DOENG_TRANSPORT_ATTRIBUTION_ENABLED = $previousTransport }
}
