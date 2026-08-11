param(
    [Parameter(Mandatory = $true)][string]$ComposeProject,
    [string]$ServerService = "mvc",
    [string[]]$ComposeFiles = @("backend\docker-compose.experiment.yaml"),
    [int]$DurationSeconds = 60,
    [int]$IntervalSeconds = 1,
    [int]$MainPort = 8002,
    [int]$ManagementPort = 9002,
    [int]$MockPort = 9100,
    [string]$ComposeFilesBase64 = "",
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFilesSource = "PARAMETER_DEFAULT"
if (-not [string]::IsNullOrWhiteSpace($ComposeFilesBase64)) {
    try {
        $bytes = [Convert]::FromBase64String($ComposeFilesBase64)
        $json = [Text.Encoding]::UTF8.GetString($bytes)
        $decoded = $json | ConvertFrom-Json
        if ($decoded.Count -lt 1) { throw "Decoded compose file list is empty" }
        $ComposeFiles = @($decoded | ForEach-Object { [string]$_ })
        $composeFilesSource = "BASE64_JSON"
    } catch {
        throw "COMPOSE_FILES_DECODE: FAIL — $($_.Exception.Message)"
    }
}
$composeArguments = @()
foreach ($file in $ComposeFiles) {
    $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $repositoryRoot $file }
    $composeArguments += @("-f", [IO.Path]::GetFullPath($path))
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repositoryRoot $OutputPath }
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null

function Convert-HttpContentToText {
    param($Content)
    if ($null -eq $Content) { return "" }
    if ($Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($Content) }
    if ($Content -is [string]) { return $Content }
    return [string]$Content
}

function Convert-HttpContent {
    param($Content)
    $text = Convert-HttpContentToText $Content
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return $text | ConvertFrom-Json } catch { return $text }
}

function Get-Json($uri) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 1
        $text = Convert-HttpContentToText $response.Content
        $body = Convert-HttpContent $response.Content
        return [ordered]@{ ok = $true; status = [int]$response.StatusCode; text = $text; body = $body }
    } catch {
        return [ordered]@{ ok = $false; status = 0; text = ""; body = $null; error = $_.Exception.Message }
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
$successfulApplicationSamples = 0
$successfulMockSamples = 0
$readinessFailures = 0
$containerStateFailures = 0
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
    if ($sample.application.ok) { $successfulApplicationSamples++ } else { $failedSamples++ }
    if ($sample.mock.ok) { $successfulMockSamples++ }
    if (-not ($sample.readiness.ok -and $sample.readiness.status -eq 200 -and
            $sample.readiness.body.status -eq "UP")) { $readinessFailures++ }
    if ($null -eq $sample.container) { $containerStateFailures++ }
    ($sample | ConvertTo-Json -Depth 12 -Compress) | Add-Content -Encoding UTF8 -LiteralPath $OutputPath
    Start-Sleep -Seconds $IntervalSeconds
}
$summary = [ordered]@{
    composeFileCount = @($ComposeFiles).Count
    composeFilesSource = $composeFilesSource
    capturedAt = (Get-Date).ToUniversalTime().ToString("o")
    durationSeconds = $DurationSeconds
    intervalSeconds = $IntervalSeconds
    sampleCount = $samples
    failedSampleCount = $failedSamples
    successfulApplicationSamples = $successfulApplicationSamples
    failedApplicationSamples = $failedSamples
    successfulMockSamples = $successfulMockSamples
    failedMockSamples = $samples - $successfulMockSamples
    readinessFailures = $readinessFailures
    containerStateFailures = $containerStateFailures
    coverageRatio = if ($samples -gt 0) { $successfulApplicationSamples / $samples } else { 0 }
    mockCoverageRatio = if ($samples -gt 0) { $successfulMockSamples / $samples } else { 0 }
    containerCoverageRatio = if ($samples -gt 0) { ($samples - $containerStateFailures) / $samples } else { 0 }
    observerValid = $samples -gt 0 -and
        $successfulApplicationSamples -gt 0 -and
        $successfulMockSamples -gt 0 -and
        $containerStateFailures -lt $samples
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath ([IO.Path]::ChangeExtension($OutputPath, ".summary.json"))
