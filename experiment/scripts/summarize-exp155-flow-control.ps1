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
function Get-Median($Values) {
    $v = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    return $v[[Math]::Floor(($v.Count - 1) / 2)]
}
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
    $completedPerLoadSecond = $s.throughputRequestsPerSecond
    $acceptedCompletionsPerLoadSecond = if ($s.durationMs) { $s.successfulRequests / ($s.durationMs / 1000) } else { $null }
    $http200Latency = $s.latencyByOutcome.HTTP_200_ACCEPTED
    $poolFinal = $null
    $poolPath = Join-Path $dir "pool-final.json"
    if (Test-Path $poolPath) {
        $poolFinal = Get-Content $poolPath -Raw | ConvertFrom-Json
    }
    $rows += [ordered]@{
        runId=$id;cell=$config.cell;valid=$valid;attempts=$s.scheduledRequests;completed=$s.completedRequests;successfulRequests=$s.successfulRequests
        http200=$o.HTTP_200_ACCEPTED;http500=$o.HTTP_500_UNCONTROLLED;http503Admission=$o.HTTP_503_ADMISSION;http503Downstream=$o.HTTP_503_DOWNSTREAM;http503Total=($o.HTTP_503_ADMISSION+$o.HTTP_503_DOWNSTREAM);http504=0;timeout=$o.CLIENT_TIMEOUT;connectionError=$o.CONNECTION_ERROR
        completedPerLoadSecond=$completedPerLoadSecond;acceptedCompletionsPerLoadSecond=$acceptedCompletionsPerLoadSecond;successRate=$successRate
        allLatency=$s.latencyMs;http200Latency=$http200Latency;maxInFlight=$s.maxInFlight
        providerFinalMetrics=if ($poolFinal) { $poolFinal.metrics } else { $null }
        providerTimelineStatus="PARTIAL"
        sinkQueueEvidenceStatus=if ($config.cell -eq "SINK") { "NOT_AVAILABLE" } else { "NOT_APPLICABLE" }
    }
}
$groups = @{}
foreach ($cell in @("CONTROL","GATE","SINK")) {
    $cellRows = @($rows | Where-Object {$_.cell -eq $cell -and $_.valid})
    $groups[$cell] = [ordered]@{
        validRuns=$cellRows.Count
        median=[ordered]@{
            successRate=Get-Median ($cellRows | % successRate)
            completedPerLoadSecond=Get-Median ($cellRows | % completedPerLoadSecond)
            acceptedCompletionsPerLoadSecond=Get-Median ($cellRows | % acceptedCompletionsPerLoadSecond)
            allLatencyP50=Get-Median ($cellRows | % { $_.allLatency.p50 })
            allLatencyP95=Get-Median ($cellRows | % { $_.allLatency.p95 })
            allLatencyP99=Get-Median ($cellRows | % { $_.allLatency.p99 })
            http200LatencyP50=Get-Median ($cellRows | % { $_.http200Latency.p50 })
            http200LatencyP95=Get-Median ($cellRows | % { $_.http200Latency.p95 })
            http200LatencyP99=Get-Median ($cellRows | % { $_.http200Latency.p99 })
            http503Admission=Get-Median ($cellRows | % http503Admission)
            http503Downstream=Get-Median ($cellRows | % http503Downstream)
            timeout=Get-Median ($cellRows | % timeout)
            connectionError=Get-Median ($cellRows | % connectionError)
        }
        runs=$cellRows
    }
}
$result = [ordered]@{
    experiment="Exp155"
    metricSchemaVersion="exp155-evidence-repair-v1"
    generatedAt=[DateTime]::UtcNow.ToString("o")
    runs=$rows
    groups=$groups
    decision="INCONCLUSIVE"
    decisionBasis="Provider pending/acquire and Sink queue/wait timelines are not fully recoverable from existing raw artifacts; no new load was executed."
    supersededFields=@("successfulRps","http503")
    replacementFields=@("completedPerLoadSecond","acceptedCompletionsPerLoadSecond","http503Admission","http503Downstream","http200Latency")
}
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$result | ConvertTo-Json -Depth 30 | Set-Content $out -Encoding UTF8
Write-Output ("EXP155_SUMMARY_WRITTEN " + $out)
