param(
    [Parameter(Mandatory = $true)][string]$ComposeProject,
    [string]$ServerService = "mvc",
    [string[]]$ComposeFiles = @("backend\docker-compose.experiment.yaml"),
    [int]$DurationSeconds = 60,
    [int]$IntervalSeconds = 1,
    [int]$MainPort = 8002,
    [int]$ManagementPort = 9002,
    [int]$MockPort = 9100,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeArguments = @()
foreach ($file in $ComposeFiles) {
    $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $repositoryRoot $file }
    $composeArguments += @("-f", [IO.Path]::GetFullPath($path))
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repositoryRoot $OutputPath }
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null

function Get-Json($uri) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 1
        $body = $null
        try { $body = $response.Content | ConvertFrom-Json } catch { $body = $response.Content }
        return [ordered]@{ ok = $true; status = $response.StatusCode; body = $body }
    } catch {
        return [ordered]@{ ok = $false; status = 0; body = $null; error = $_.Exception.Message }
    }
}

function Get-State {
    $ids = @(& docker compose -p $ComposeProject @composeArguments ps -q $ServerService 2>$null |
        ForEach-Object { $id = ([string]$_).Trim(); if ($id) { $id } })
    if ($ids.Count -ne 1) { return $null }
    $raw = @(& docker inspect $ids[0] 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    $c = (($raw -join [Environment]::NewLine) | ConvertFrom-Json)[0]
    return [ordered]@{
        containerId = $c.Id
        running = $c.State.Running
        restartCount = $c.RestartCount
        oomKilled = $c.State.OOMKilled
        status = $c.State.Status
        exitCode = $c.State.ExitCode
    }
}

Set-Content -Encoding UTF8 -LiteralPath $OutputPath -Value ""
$started = Get-Date
$samples = 0
$failedSamples = 0
while (((Get-Date) - $started).TotalSeconds -lt $DurationSeconds) {
    $sample = [ordered]@{
        capturedAt = (Get-Date).ToUniversalTime().ToString("o")
        elapsedMs = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
        application = Get-Json "http://127.0.0.1:$ManagementPort/actuator/doengexperiment"
        readiness = Get-Json "http://127.0.0.1:$MainPort/readyz"
        mock = Get-Json "http://127.0.0.1:$MockPort/__metrics"
        container = Get-State
    }
    $samples++
    if (-not $sample.application.ok -or -not $sample.readiness.ok -or -not $sample.mock.ok -or $null -eq $sample.container) { $failedSamples++ }
    ($sample | ConvertTo-Json -Depth 12 -Compress) | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    Start-Sleep -Seconds $IntervalSeconds
}
$summary = [ordered]@{
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    durationSeconds = $DurationSeconds
    intervalSeconds = $IntervalSeconds
    sampleCount = $samples
    failedSampleCount = $failedSamples
    observerValid = $true
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath ([IO.Path]::ChangeExtension($OutputPath, ".summary.json"))
