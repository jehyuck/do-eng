$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repoRoot

$baseCompose = "backend\docker-compose.experiment.yaml"
$overrideCompose = "experiment\compose\mvc400-vu120-ai1s.override.yml"
$configPath = "experiment\config\mvc400-vu120-ai1s.json"
$composeProject = "doeng-mvc400-vu120-ai1s"
$runId = "SPOT-MVC400-VU120-AI1S-002"
$composeArgs = @("-p", $composeProject, "-f", $baseCompose, "-f", $overrideCompose)

function Get-ComposeContainerId {
    param([Parameter(Mandatory = $true)][string]$Service)
    $ids = @(& docker compose @composeArgs ps -q $Service 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $id = @($ids | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($id.Count -eq 1) { return $id[0] }
    return $null
}

function Wait-ContainerHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$Service,
        [int]$TimeoutSeconds = 180
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $containerId = Get-ComposeContainerId -Service $Service
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $status = (@(& docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $containerId 2>$null) -join "").Trim()
            if ($status -eq "healthy") {
                Write-Host "$Service is healthy"
                return
            }
            if ($status -in @("unhealthy", "exited", "dead")) {
                throw "$Service entered terminal state: $status"
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "$Service did not become healthy within $TimeoutSeconds seconds"
}

function Wait-MvcReadiness {
    param([int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $uri = "http://127.0.0.1:9002/actuator/health/readiness"
    while ((Get-Date) -lt $deadline) {
        $containerId = Get-ComposeContainerId -Service "mvc"
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $state = (@(& docker inspect --format '{{.State.Status}}' $containerId 2>$null) -join "").Trim()
            if ($state -in @("exited", "dead")) {
                throw "mvc entered terminal state before readiness: $state"
            }
        }
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                Write-Host "mvc readiness is UP"
                return
            }
        } catch {
            # Startup is still in progress; keep polling until the fixed deadline.
        }
        Start-Sleep -Seconds 2
    }
    throw "mvc readiness did not become HTTP 200 within $TimeoutSeconds seconds"
}

Write-Host "=== MVC400 VU120 AI1s one-off spot check ==="
Write-Host "RunId: $runId"
Write-Host "Fresh isolated stack; no tuning; no WebFlux arm."

$runnerExitCode = $null
try {
    Write-Host "Resetting isolated compose project..."
    & docker compose @composeArgs down -v --remove-orphans
    if ($LASTEXITCODE -ne 0) { throw "Initial compose cleanup failed" }

    Write-Host "Starting mariadb, experiment-mock, and mvc..."
    & docker compose @composeArgs up -d --build mariadb experiment-mock mvc
    if ($LASTEXITCODE -ne 0) { throw "Compose startup failed" }

    Wait-ContainerHealthy -Service "mariadb"
    Wait-ContainerHealthy -Service "experiment-mock"
    Wait-MvcReadiness

    Write-Host "Runtime is ready. Starting the single measurement attempt..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
      -File ".\experiment\scripts\run-isolated-vu-success-smoke.ps1" `
      -RunId $runId `
      -Implementation "MVC400-VU120-AI1S-SPOTCHECK" `
      -TargetUrl "http://127.0.0.1:8002/game/face" `
      -ServerService "mvc" `
      -ComposeProject $composeProject `
      -ComposeFiles "$baseCompose,$overrideCompose" `
      -ConfigPath $configPath `
      -EnableObservability 0 `
      -EnableJfr 0 `
      -EnableContainerMonitor 0 `
      -SkipApplicationSnapshot 1 `
      -SkipMockMetrics 1

    $runnerExitCode = $LASTEXITCODE
    Write-Host "Runner exit code: $runnerExitCode"
    Write-Host "Result directory: experiment\results\$runId"
} finally {
    Write-Host "Stopping isolated compose project..."
    & docker compose @composeArgs down -v --remove-orphans
}

if ($null -eq $runnerExitCode) {
    exit 1
}
exit $runnerExitCode
