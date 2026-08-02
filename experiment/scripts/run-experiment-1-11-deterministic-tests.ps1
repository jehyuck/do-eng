param(
    [string]$OutputDirectory = ".experiment-work\experiment-1-11-deterministic"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$output = Join-Path $root $OutputDirectory
New-Item -ItemType Directory -Force -Path $output | Out-Null
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
$previousLimit = $env:DOENG_ADMISSION_MAX_CONCURRENT
$env:DOENG_ADMISSION_MAX_CONCURRENT = "1"

function Wait-Health([string]$Url) {
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod $Url -TimeoutSec 5
            if ($health.status -eq "UP" -or $health.status -eq "ok") { return }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "health timeout: $Url"
}

try {
    docker compose -p $composeProject @composeArgs build experiment-mock | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "deterministic mock image build failed" }
    docker compose -p $composeProject @composeArgs up -d --force-recreate mariadb experiment-mock flux-corrected | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "deterministic compose startup failed" }
    Wait-Health "http://127.0.0.1:9001/actuator/health"
    Wait-Health "http://127.0.0.1:9100/health"
    $env:TARGET_URL = "http://127.0.0.1:8001/game/face?answer=happy&sceneId=2"
    $env:MOCK_URL = "http://127.0.0.1:9100"
    $env:RESULT_PATH = Join-Path $output "e2e-result.json"
    & $node (Join-Path $root "experiment\load\experiment-1-11-correlation.e2e.test.js")
    if ($LASTEXITCODE -ne 0) { throw "deterministic E2E scenarios failed" }

    $container = (docker compose -p $composeProject @composeArgs ps -q flux-corrected).Trim()
    $logPath = Join-Path $output "application.log"
    $previousLogErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    docker logs --timestamps $container 2>&1 |
        ForEach-Object { $_.ToString() } |
        Out-File -LiteralPath $logPath -Encoding UTF8
    $ErrorActionPreference = $previousLogErrorAction

    $log = Get-Content -Raw -LiteralPath $logPath
    $e2e = Get-Content -Raw -LiteralPath (Join-Path $output "e2e-result.json") | ConvertFrom-Json
    $testReports = @(Get-ChildItem -LiteralPath (Join-Path $root "backend\doEngGameFlux\build\test-results\test") -Filter "TEST-*.xml")
    $testFailures = 0
    foreach ($report in $testReports) {
        [xml]$testResult = Get-Content -Raw -LiteralPath $report.FullName
        $testFailures += [int]$testResult.testsuite.failures + [int]$testResult.testsuite.errors
    }
    $noSemanticChange = $testReports.Count -gt 0 -and $testFailures -eq 0
    $assertions = [ordered]@{
        contextAndAiHeader = $log.Contains("requestId=exp111-normal") -and $log.Contains("event=STAGE_SUCCEEDED")
        admissionNoAiRequest = $e2e.admission.valid
        normalAiResponse = $e2e.normal.valid
        forcedClosePremature = $e2e.forcedClose.valid -and $log.Contains("requestId=exp111-forced-close") -and $log.Contains("PrematureCloseException") -and $log.Contains("status=500")
        clientCancellation = $e2e.cancellation.valid -and $log.Contains("requestId=exp111-client-cancel")
        noSemanticChange = $noSemanticChange
    }
    $summary = [ordered]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString("o")
        assertions = $assertions
        valid = -not (@($assertions.Values) -contains $false)
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $output "deterministic-summary.json")
    if (-not $summary.valid) { throw "deterministic correlation assertions failed" }
} finally {
    Remove-Item Env:TARGET_URL,Env:MOCK_URL,Env:RESULT_PATH -ErrorAction SilentlyContinue
    if ($null -eq $previousLimit) { Remove-Item Env:DOENG_ADMISSION_MAX_CONCURRENT -ErrorAction SilentlyContinue }
    else { $env:DOENG_ADMISSION_MAX_CONCURRENT = $previousLimit }
}
