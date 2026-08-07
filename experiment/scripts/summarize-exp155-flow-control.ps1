param(
    [string]$ResultRoot = "",
    [string]$Output = ""
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$root = if ($ResultRoot) { (Resolve-Path $ResultRoot).Path } else { Join-Path $repo "experiment\results\experiment-1-55" }
$out = if ($Output) { $Output } else { Join-Path $root "aggregate-summary.json" }
$ids = @("CONTROL-1","GATE-1","SINK-1","SINK-2","GATE-2","CONTROL-2","CONTROL-3","SINK-3","GATE-3")
$rows = @()
foreach ($id in $ids) {
    $dir = Join-Path $root $id
    $configPath = Join-Path $dir "run-config.json"
    $loadPath = Join-Path $dir "load-summary.json"
    $validPath = Join-Path $dir "validity.json"
    if (-not (Test-Path $configPath) -or -not (Test-Path $loadPath)) { continue }
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $load = Get-Content $loadPath -Raw | ConvertFrom-Json
    $valid = if (Test-Path $validPath) { (Get-Content $validPath -Raw | ConvertFrom-Json).valid } else { $false }
    $s = $load.summary; $o = $s.outcomeCounts
    $successRate = if ($s.completedRequests) { $s.successfulRequests / $s.completedRequests } else { 0 }
    $rows += [ordered]@{runId=$id;cell=$config.cell;valid=$valid;attempts=$s.scheduledRequests;completed=$s.completedRequests;success=$s.successfulRequests;http200=$o.HTTP_200_ACCEPTED;http500=$o.HTTP_500_UNCONTROLLED;http503=($o.HTTP_503_ADMISSION+$o.HTTP_503_DOWNSTREAM);http504=0;timeout=$o.CLIENT_TIMEOUT;connectionError=$o.CONNECTION_ERROR;successfulRps=$s.throughputRequestsPerSecond;successRate=$successRate;p50=$s.latencyMs.p50;p95=$s.latencyMs.p95;p99=$s.latencyMs.p99;max=$s.latencyMs.max;maxInFlight=$s.maxInFlight}
}
$groups = @{}
foreach ($cell in @("CONTROL","GATE","SINK")) {
    $cellRows = @($rows | Where-Object {$_.cell -eq $cell -and $_.valid})
    $groups[$cell] = [ordered]@{validRuns=$cellRows.Count;median=[ordered]@{successRate=($cellRows | % successRate | Sort-Object)[[Math]::Floor(($cellRows.Count-1)/2)];successfulRps=($cellRows | % successfulRps | Sort-Object)[[Math]::Floor(($cellRows.Count-1)/2)];p50=($cellRows | % p50 | Sort-Object)[[Math]::Floor(($cellRows.Count-1)/2)];p95=($cellRows | % p95 | Sort-Object)[[Math]::Floor(($cellRows.Count-1)/2)];p99=($cellRows | % p99 | Sort-Object)[[Math]::Floor(($cellRows.Count-1)/2)]};runs=$cellRows}
}
$result = [ordered]@{experiment="Exp155";generatedAt=[DateTime]::UtcNow.ToString("o");runs=$rows;groups=$groups;decision="NOT_RUN"}
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$result | ConvertTo-Json -Depth 30 | Set-Content $out -Encoding UTF8
Write-Output ("EXP155_SUMMARY_WRITTEN " + $out)
