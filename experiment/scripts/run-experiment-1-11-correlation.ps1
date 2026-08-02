param(
    [Parameter(Mandatory = $true)][string]$RunId
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeProject = "doeng-exp18"
$composeFiles = @(
    "backend\docker-compose.experiment.yaml",
    "backend\docker-compose.app-instance-t3-medium.yaml",
    "backend\docker-compose.mock-headroom-4cpu.yaml",
    "backend\docker-compose.http-pool-400.yaml",
    "backend\docker-compose.mock-memory-headroom.yaml",
    "backend\docker-compose.experiment-1-11-correlation.yaml"
)
$composeArgs = @()
foreach ($file in $composeFiles) { $composeArgs += @("-f", $file) }
$node = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$resultsRoot = Join-Path $root "experiment\results"
$runDirectory = Join-Path $resultsRoot $RunId
$logPath = Join-Path $runDirectory "application.log"
$sourceCommit = (& git -C $root rev-parse HEAD).Trim()

$hashRows = foreach ($file in $composeFiles) {
    $absolute = Join-Path $root $file
    [ordered]@{ path = $file; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToLowerInvariant() }
}
$hashText = ($hashRows | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n"
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $composeHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashText))).Replace("-", "").ToLowerInvariant()
} finally { $sha.Dispose() }
$frozenHashPath = Join-Path $root ".experiment-work\experiment-1-11-compose-hash.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $frozenHashPath) | Out-Null
if (Test-Path -LiteralPath $frozenHashPath) {
    $frozenHash = (Get-Content -Raw -LiteralPath $frozenHashPath).Trim()
    if ($frozenHash -ne $composeHash) { throw "Experiment 1-11 compose hash changed" }
} else {
    Set-Content -LiteralPath $frozenHashPath -Encoding ASCII -Value $composeHash
}

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$writeProbe = Join-Path $resultsRoot ".$RunId-diagnostic-write-probe"
Set-Content -LiteralPath $writeProbe -Encoding ASCII -Value "writable"
Remove-Item -LiteralPath $writeProbe

try {
    docker compose -p $composeProject @composeArgs up -d --force-recreate mariadb experiment-mock | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "clean dependency recreate failed" }
    $mockHealth = $null
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try { $mockHealth = Invoke-RestMethod "http://127.0.0.1:9100/health" -TimeoutSec 5 } catch { $mockHealth = $null }
        if ($null -ne $mockHealth -and $mockHealth.status -eq "ok") { break }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $mockHealth -or $mockHealth.status -ne "ok") { throw "mock health timeout" }
    $idle = Invoke-RestMethod "http://127.0.0.1:9100/__metrics" -TimeoutSec 5
    if ($idle.aiInFlight -ne 0 -or $idle.storageInFlight -ne 0) { throw "pre-run mock backlog is not zero" }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot "run-experiment-1-4-before.ps1") `
        -RunId $RunId -RunKind core `
        -ComposeOverlay "backend\docker-compose.experiment-1-11-correlation.yaml" `
        -AiDelayMs 2000 -ComposeProject $composeProject -SkipPhase1Observer
    if ($LASTEXITCODE -ne 0) { throw "Experiment 1-11 core failed: $LASTEXITCODE" }
} finally {
    $container = (docker compose -p $composeProject @composeArgs ps -q flux-corrected).Trim()
    if (-not [string]::IsNullOrWhiteSpace($container) -and (Test-Path -LiteralPath $runDirectory)) {
        $previousLogErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        docker logs --timestamps $container 2>&1 |
            ForEach-Object { $_.ToString() } |
            Out-File -LiteralPath $logPath -Encoding UTF8
        $ErrorActionPreference = $previousLogErrorAction
    }
}

& $node (Join-Path $PSScriptRoot "aggregate-experiment-1-11-correlation.js") $runDirectory
if ($LASTEXITCODE -ne 0) { throw "correlation aggregation failed" }
if (-not (Test-Path -LiteralPath (Join-Path $runDirectory "correlation-summary.json"))) {
    throw "correlation summary is missing"
}

$provenance = [ordered]@{
    runId = $RunId
    sourceCommit = $sourceCommit
    composeHash = $composeHash
    composeFiles = $hashRows
    image = "doeng-flux-exp111-correlation-20260802:latest"
    diagnosticArtifactWritable = $true
    mockAndAppRecreated = $true
}
$provenance | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDirectory "correlation-provenance.json")
