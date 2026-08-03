$script:Exp121Required = @('run-config.json','client-results.json','client-progress.jsonl','pool/pool-metrics.jsonl','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','application/docker-logs.stdout.log','application/docker-logs.stderr.log','application/docker-logs-capture.json','application/application.log','database/database-metrics.jsonl','container/container-stats.jsonl','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json')
function Get-Exp121Required { @($script:Exp121Required) }
function Test-Exp121Json([string]$Path) { try { $null=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json; $true } catch { $false } }
function Assert-Exp121Artifacts([string]$Root) {
    foreach($r in $script:Exp121Required){$p=Join-Path $Root $r;if(-not(Test-Path $p) -or (Get-Item $p).Length -le 0){throw "Required artifact missing or empty: $r"}}
    foreach($r in @('run-config.json','client-results.json','pool/pool-metrics.jsonl.summary.json','pool/collector-coverage.json','application/docker-logs-capture.json','mock/load-stop-mock-metrics.json','drain/mock-drain-summary.json','verification-summary.json','provenance/runtime-provenance.json','provenance/execution-timeline.json','execution-summary.json')){if(-not(Test-Exp121Json (Join-Path $Root $r))){throw "Invalid JSON: $r"}}
    $lines=@(Get-Content (Join-Path $Root 'pool/pool-metrics.jsonl')|Where-Object{$_.Trim()});if($lines.Count -le 1){throw 'Pool JSONL has fewer than two valid-sample candidates'};foreach($line in $lines){try{$null=$line|ConvertFrom-Json}catch{throw 'Pool JSONL contains invalid JSON'}}
    $summary=Get-Content (Join-Path $Root 'pool/pool-metrics.jsonl.summary.json') -Raw|ConvertFrom-Json;if($summary.failures -ne 0){throw "Pool collector failures: $($summary.failures)"}
    . (Join-Path $PSScriptRoot 'experiment-1-21-collector-coverage.ps1');Assert-Exp121CollectorCoverage (Join-Path $Root 'pool/collector-coverage.json')
}
function Copy-Exp121Artifacts([string]$Legacy,[string]$Staging,[string]$Destination) {
    $map=@(@('run-config.json','run-config.json'),@('client-results.json','client-results.json'),@('client-progress.jsonl','client-progress.jsonl'),@('database-metrics.jsonl','database/database-metrics.jsonl'),@('container-stats.jsonl','container/container-stats.jsonl'),@('load-stop-mock-metrics.json','mock/load-stop-mock-metrics.json'),@('mock-drain-summary.json','drain/mock-drain-summary.json'),@('verification-summary.json','verification-summary.json'))
    foreach($m in $map){$s=Join-Path $Legacy $m[0];if(-not(Test-Path $s)){throw "Legacy artifact missing: $s"};$d=Join-Path $Destination $m[1];New-Item -ItemType Directory -Force -Path (Split-Path $d)|Out-Null;Copy-Item $s $d}
    foreach($name in @('pool-metrics.jsonl','pool-metrics.jsonl.summary.json')){$s=Join-Path $Staging $name;if(-not(Test-Path $s)){throw "Collector artifact missing: $s"};$d=Join-Path $Destination "pool/$name";New-Item -ItemType Directory -Force -Path (Split-Path $d)|Out-Null;Copy-Item $s $d}
}
function Set-Exp121Terminal([string]$Root,[ValidateSet('COMPLETED','EXECUTION_FAILED')][string]$State){foreach($m in @('RUNNING','COMPLETED','EXECUTION_FAILED')){$p=Join-Path $Root $m;if(Test-Path $p){Remove-Item $p -Force}};New-Item -ItemType File -Path (Join-Path $Root $State)|Out-Null}




